--!nonstrict
--[[
	══════════════════════════════════════════════════════════════════════════
	BT SETTINGS — LIVE ENVIRONMENT · SERVER
	Script (RunContext = Server) · ReplicatedStorage > BTSettings > EnvironmentCycle

	Decides which environment is active right now and publishes it as
	attributes on the EnvironmentCycle folder. Every Client reads them and
	applies the preset. No RemoteEvent listens to players, so nobody can
	change the environment from their device.

	Published attributes (read-only for other scripts):
	  Preset, Index, StartedAt, EndsAt, NextPreset, NextIndex, Forced, ChangeId
	  (StartedAt / EndsAt are Unix seconds: compare with workspace:GetServerTimeNow())

	Other SERVER scripts can control it:
	  local cmd = ReplicatedStorage.BTSettings.EnvironmentCycle:WaitForChild("Command")
	  cmd:Invoke("set", "Night", 30)  -- Night for 30 units (Settings.timeUnit)
	  cmd:Invoke("next")              -- jump to the next one
	  cmd:Invoke("auto")              -- back to the timer
	  print(cmd:Invoke("status"))
	══════════════════════════════════════════════════════════════════════════
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local cycleFolder = script.Parent
local root = cycleFolder.Parent
local Config = require(root:WaitForChild("Config"))
local Settings = require(cycleFolder:WaitForChild("Settings"))

local TAG = "[BTSettings] Environment:"

if not Settings.enabled then
	cycleFolder:SetAttribute("Enabled", false)
	return
end

local lightingFolder = root:WaitForChild(Config.names.lightingFolder, 15)
if not lightingFolder then
	warn(TAG, "folder '" .. Config.names.lightingFolder .. "' not found in", root:GetFullName())
	return
end

-- ─────────────────────────────────────────────────────────────────────────
-- Schedule (checked once; bad lines are skipped with a warning)
-- ─────────────────────────────────────────────────────────────────────────
local UNITS = { seconds = 1, minutes = 60, hours = 3600 }
local unit = UNITS[Settings.timeUnit]
if not unit then
	warn(TAG, "timeUnit must be 'seconds', 'minutes' or 'hours' — using minutes")
	unit = 60
end

local function findPresetFolder(name: string): Instance?
	local exact = lightingFolder:FindFirstChild(name)
	if exact and exact:IsA("Folder") then
		return exact
	end
	local lower = string.lower(name)
	for _, child in lightingFolder:GetChildren() do
		if child:IsA("Folder") and string.lower(child.Name) == lower then
			return child
		end
	end
	return nil
end

type Entry = { index: number, preset: string, seconds: number }

local entries: { Entry } = {}
for i, line in ipairs(Settings.schedule or {}) do
	local where = ("schedule line %d"):format(i)
	if type(line) ~= "table" or type(line.preset) ~= "string" then
		warn(TAG, where .. ": 'preset' must be a folder name from All Lighting")
	elseif not findPresetFolder(line.preset) then
		warn(TAG, where .. ": preset '" .. line.preset .. "' is not a folder in All Lighting — skipped")
	elseif type(line.duration) ~= "number" or line.duration ~= line.duration or line.duration <= 0 then
		warn(TAG, where .. " (" .. line.preset .. "): 'duration' must be a number above 0 — skipped")
	else
		table.insert(entries, {
			index = i,
			preset = (findPresetFolder(line.preset) :: Instance).Name,
			seconds = line.duration * unit,
		})
	end
end

if #entries == 0 then
	warn(TAG, "the schedule has no valid lines — live environment is off")
	return
end

local total = 0
for _, e in entries do
	total += e.seconds
end

local function now(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

-- Order of `entries` for one round (shuffle is seeded by the round number,
-- so every server computes the very same order).
local function shuffled(round: number): { number }
	local order = table.create(#entries)
	for i = 1, #entries do
		order[i] = i
	end
	if Settings.order == "shuffle" and #order > 1 then
		local rng = Random.new(round * 7919 + 17)
		for i = #order, 2, -1 do
			local j = rng:NextInteger(1, i)
			order[i], order[j] = order[j], order[i]
		end
	end
	return order
end

local orderCache: { [number]: { number } } = {}
local function orderFor(round: number): { number }
	local cached = orderCache[round]
	if cached then
		return cached
	end
	local order = shuffled(round)
	if Settings.order == "shuffle" and #order >= 3 then
		-- never the same preset twice in a row across the round edge
		local prev = shuffled(round - 1)
		if order[1] == prev[#prev] then
			order[1], order[2] = order[2], order[1]
		end
	end
	orderCache[round] = order
	orderCache[round - 3] = nil
	return order
end

type Phase = { entry: Entry, startedAt: number, endsAt: number, nextEntry: Entry }

-- ── synced: same answer on every server, from the real clock ──
local anchor = 0
do
	local cs = Settings.cycleStart or {}
	anchor = (cs.hour or 0) * 3600 + (cs.minute or 0) * 60 - (cs.utcOffsetHours or 0) * 3600
end

local function syncedPhase(t: number): Phase
	local elapsed = t - anchor
	local round = math.floor(elapsed / total)
	local pos = elapsed - round * total
	local order = orderFor(round)
	local acc = 0
	for k, ei in order do
		local e = entries[ei]
		if pos < acc + e.seconds or k == #order then
			local startedAt = anchor + round * total + acc
			local nextEi = order[k + 1] or orderFor(round + 1)[1]
			return { entry = e, startedAt = startedAt, endsAt = startedAt + e.seconds, nextEntry = entries[nextEi] }
		end
		acc += e.seconds
	end
	error("unreachable")
end

-- ── local: this server runs its own cycle ──
local localState: { round: number, k: number, startedAt: number, endsAt: number }? = nil

local function localStart(t: number)
	local order = orderFor(0)
	local k = 1
	local sw = Settings.startWith
	if sw == "random" then
		k = Random.new():NextInteger(1, #order)
	elseif type(sw) == "number" then
		for i, ei in order do
			if entries[ei].index == sw then
				k = i
				break
			end
		end
	elseif type(sw) == "string" then
		for i, ei in order do
			if string.lower(entries[ei].preset) == string.lower(sw) then
				k = i
				break
			end
		end
	end
	localState = { round = 0, k = k, startedAt = t, endsAt = t + entries[order[k]].seconds }
end

local function localAdvance(startAt: number)
	local s = localState :: any
	s.k += 1
	if s.k > #orderFor(s.round) then
		s.round += 1
		s.k = 1
	end
	s.startedAt = startAt
	s.endsAt = startAt + entries[orderFor(s.round)[s.k]].seconds
end

local function localPhase(t: number): Phase
	if not localState then
		localStart(t)
	end
	local s = localState :: any
	while t >= s.endsAt do
		localAdvance(s.endsAt)
	end
	local order = orderFor(s.round)
	local nextEi = order[s.k + 1] or orderFor(s.round + 1)[1]
	return { entry = entries[order[s.k]], startedAt = s.startedAt, endsAt = s.endsAt, nextEntry = entries[nextEi] }
end

local function schedulePhase(t: number): Phase
	if Settings.syncAllServers then
		return syncedPhase(t)
	end
	return localPhase(t)
end

-- ── admin override (this server only) ──
local forced: Phase? = nil

local function currentPhase(t: number): (Phase, boolean)
	if forced and t < forced.endsAt then
		return forced, true
	end
	forced = nil
	return schedulePhase(t), false
end

-- ─────────────────────────────────────────────────────────────────────────
-- Publish to every client (attributes replicate by themselves)
-- ─────────────────────────────────────────────────────────────────────────
local changeId = 0
local lastKey = ""

local function publish()
	local t = now()
	local phase, isForced = currentPhase(t)
	local key = phase.entry.preset .. "|" .. math.floor(phase.startedAt) .. "|" .. tostring(isForced)
	if key == lastKey then
		return
	end
	lastKey = key
	changeId += 1
	cycleFolder:SetAttribute("Preset", phase.entry.preset)
	cycleFolder:SetAttribute("Index", phase.entry.index)
	cycleFolder:SetAttribute("StartedAt", phase.startedAt)
	cycleFolder:SetAttribute("EndsAt", phase.endsAt)
	cycleFolder:SetAttribute("NextPreset", phase.nextEntry.preset)
	cycleFolder:SetAttribute("NextIndex", phase.nextEntry.index)
	cycleFolder:SetAttribute("Forced", isForced)
	-- ChangeId last: clients react to it, so everything above is already set
	cycleFolder:SetAttribute("ChangeId", changeId)
end

-- ─────────────────────────────────────────────────────────────────────────
-- Commands (chat for admins, BindableFunction for server scripts)
-- ─────────────────────────────────────────────────────────────────────────
local function fmtDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	if h > 0 then
		return ("%dh %dm"):format(h, m)
	elseif m > 0 then
		return ("%dm"):format(m)
	end
	return ("%ds"):format(seconds)
end

local function presetNames(): { string }
	local names = {}
	for _, child in lightingFolder:GetChildren() do
		if child:IsA("Folder") then
			table.insert(names, child.Name)
		end
	end
	table.sort(names)
	return names
end

local function entryFor(presetName: string, seconds: number?): Entry
	for _, e in entries do
		if e.preset == presetName then
			return { index = e.index, preset = e.preset, seconds = seconds or e.seconds }
		end
	end
	-- a preset folder that is not in the schedule
	return { index = 0, preset = presetName, seconds = seconds or 30 * 60 }
end

local function runCommand(action: string?, arg: string?, amount: number?): string
	local t = now()
	action = string.lower(action or "status")

	if action == "status" then
		local phase, isForced = currentPhase(t)
		return ("Now: %s%s (%s left) · Next: %s"):format(
			phase.entry.preset,
			isForced and " (admin)" or "",
			fmtDuration(phase.endsAt - t),
			phase.nextEntry.preset
		)
	elseif action == "list" then
		return "Presets: " .. table.concat(presetNames(), ", ")
	elseif action == "auto" then
		forced = nil
		publish()
		return "Back to the timer · " .. runCommand("status")
	elseif action == "next" then
		local phase = currentPhase(t)
		if not Settings.syncAllServers and not forced then
			localAdvance(t)
			publish()
			return runCommand("status")
		end
		local nxt = phase.nextEntry
		forced = { entry = nxt, startedAt = t, endsAt = t + nxt.seconds, nextEntry = schedulePhase(t + nxt.seconds).entry }
		publish()
		return runCommand("status")
	elseif action == "set" then
		local folder = arg and findPresetFolder(arg)
		if not folder then
			return ("No preset named '%s'. Try: %s list"):format(tostring(arg), (Settings.admin or {}).prefix or "/env")
		end
		local seconds = nil
		if type(amount) == "number" and amount == amount and amount > 0 then
			seconds = math.min(amount * unit, 7 * 86400)
		end
		local e = entryFor(folder.Name, seconds)
		forced = { entry = e, startedAt = t, endsAt = t + e.seconds, nextEntry = schedulePhase(t + e.seconds).entry }
		publish()
		return runCommand("status")
	end
	return "Unknown command. Use: status, list, next, auto, or a preset name"
end

local command = Instance.new("BindableFunction")
command.Name = "Command"
command.OnInvoke = function(action, arg, amount)
	return runCommand(action, arg, amount)
end
command.Parent = cycleFolder

-- Server → client only (the server never listens to it): admin replies.
local adminReply = Instance.new("RemoteEvent")
adminReply.Name = "AdminReply"
adminReply.Parent = cycleFolder

local admin = Settings.admin or {}

local function isAdmin(player: Player): boolean
	if admin.allowInStudio and RunService:IsStudio() then
		return true
	end
	if table.find(admin.userIds or {}, player.UserId) then
		return true
	end
	if admin.allowGameOwner then
		if game.CreatorType == Enum.CreatorType.User then
			return player.UserId == game.CreatorId
		end
		local ok, rank = pcall(player.GetRankInGroup, player, game.CreatorId)
		return ok and rank == 255
	end
	return false
end

local lastCommand: { [Player]: number } = {}

local function onChatCommand(player: Player?, text: string)
	if not player or not isAdmin(player) then
		return
	end
	local clock = os.clock()
	if lastCommand[player] and clock - lastCommand[player] < 0.5 then
		return -- also drops the duplicate when both chat signals fire
	end
	lastCommand[player] = clock

	local words = string.split(text, " ")
	table.remove(words, 1) -- the prefix itself
	for i = #words, 1, -1 do
		if words[i] == "" then
			table.remove(words, i)
		end
	end

	local reply
	local first = words[1] and string.lower(words[1])
	if not first or first == "status" then
		reply = runCommand("status")
	elseif first == "list" or first == "next" or first == "auto" then
		reply = runCommand(first)
	else
		-- "/env Pink SKy 30" → preset "Pink SKy", amount 30
		local amount = tonumber(words[#words])
		if amount and #words > 1 then
			table.remove(words)
		else
			amount = nil
		end
		reply = runCommand("set", table.concat(words, " "), amount)
	end
	adminReply:FireClient(player, reply)
end

if admin.chatCommands then
	local prefix = admin.prefix or "/env"
	if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = "BTSettingsEnvironment"
		cmd.PrimaryAlias = prefix
		cmd.Triggered:Connect(function(source: TextSource, text: string)
			onChatCommand(Players:GetPlayerByUserId(source.UserId), text)
		end)
		cmd.Parent = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
	end
	local function hookChatted(player: Player)
		player.Chatted:Connect(function(message: string)
			local lowered = string.lower(message)
			if lowered == prefix or string.sub(lowered, 1, #prefix + 1) == prefix .. " " then
				onChatCommand(player, message)
			end
		end)
	end
	Players.PlayerAdded:Connect(hookChatted)
	for _, player in Players:GetPlayers() do
		hookChatted(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastCommand[player] = nil
	end)
end

-- ─────────────────────────────────────────────────────────────────────────
-- Main loop: one cheap check per second, publishes only when something changes
-- ─────────────────────────────────────────────────────────────────────────
publish()
cycleFolder:SetAttribute("Enabled", true)

while true do
	task.wait(1)
	local ok, err = pcall(publish)
	if not ok then
		warn(TAG, "update failed:", err)
	end
end
