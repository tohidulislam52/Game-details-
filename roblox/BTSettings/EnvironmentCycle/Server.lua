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
	  cmd:Invoke("set", "Night", 30)  -- Night for 30 minutes
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
local DAY = 86400

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

-- "06:00" → seconds after midnight
local function parseClock(text: any, where: string): number?
	local h, m
	if type(text) == "string" then
		h, m = string.match(text, "^%s*(%d%d?):(%d%d)%s*$")
	end
	h, m = tonumber(h), tonumber(m)
	if not h or not m or h > 23 or m > 59 then
		warn(TAG, where .. ': time must look like "06:00" (24-hour) — skipped')
		return nil
	end
	return h * 3600 + m * 60
end

local offset = (tonumber(Settings.utcOffsetHours) or 0) * 3600

local blockSeconds = tonumber(Settings.blockHours)
if not blockSeconds or blockSeconds ~= blockSeconds or blockSeconds <= 0 then
	warn(TAG, "blockHours must be a number above 0 — using 2")
	blockSeconds = 2
end
blockSeconds = math.max(blockSeconds * 3600, 10)

type Entry = { index: number, preset: string, seconds: number }

local loop: { Entry } = {}
for i, line in ipairs(Settings.loop or {}) do
	local where = ("loop line %d"):format(i)
	local folder = type(line) == "table" and type(line.preset) == "string" and findPresetFolder(line.preset)
	if not folder then
		warn(TAG, where .. ": preset '" .. tostring(type(line) == "table" and line.preset) .. "' is not a folder in All Lighting — skipped")
	else
		table.insert(loop, { index = i, preset = folder.Name, seconds = blockSeconds })
	end
end

if #loop == 0 then
	warn(TAG, "Settings.loop has no valid presets — live environment is off")
	return
end

local function loopPosOf(preset: string): number?
	for k, e in loop do
		if e.preset == preset then
			return k
		end
	end
	return nil
end

type Fixed = { at: number, preset: string, loopPos: number? }

local fixed: { Fixed } = {}
for i, line in ipairs(Settings.fixedTimes or {}) do
	local where = ("fixedTimes line %d"):format(i)
	local folder = type(line) == "table" and type(line.preset) == "string" and findPresetFolder(line.preset)
	local at = type(line) == "table" and parseClock(line.at, where)
	if not folder then
		warn(TAG, where .. ": preset is not a folder in All Lighting — skipped")
	elseif at then
		local duplicate = false
		for _, f in fixed do
			duplicate = duplicate or f.at == at
		end
		if duplicate then
			warn(TAG, where .. ": another line already uses " .. tostring(line.at) .. " — skipped")
		else
			table.insert(fixed, { at = at, preset = folder.Name, loopPos = loopPosOf(folder.Name) })
		end
	end
end
table.sort(fixed, function(a, b)
	return a.at < b.at
end)
if #fixed == 0 then
	fixed = { { at = 0, preset = loop[1].preset, loopPos = 1 } }
end

-- preset → hours it may start in
local windows: { [string]: { from: number, to: number } } = {}
for name, w in pairs(Settings.onlyBetween or {}) do
	local where = "onlyBetween." .. tostring(name)
	local folder = type(name) == "string" and findPresetFolder(name)
	if not folder then
		warn(TAG, where .. ": not a folder in All Lighting — skipped")
	elseif type(w) ~= "table" then
		warn(TAG, where .. ': must look like { from = "19:00", to = "05:00" } — skipped')
	else
		local from, to = parseClock(w.from, where .. ".from"), parseClock(w.to, where .. ".to")
		if from and to then
			windows[folder.Name] = { from = from, to = to }
		end
	end
end

local function allowedAt(preset: string, localTime: number): boolean
	local w = windows[preset]
	if not w or w.from == w.to then
		return true
	end
	local s = localTime % DAY
	if w.from < w.to then
		return s >= w.from and s < w.to
	end
	return s >= w.from or s < w.to -- across midnight
end

-- the loop position that plays after `pos`, for a block starting at localTime
local function nextLoopPos(pos: number, localTime: number): number
	for step = 1, #loop do
		local p = (pos + step - 1) % #loop + 1
		if allowedAt(loop[p].preset, localTime) then
			return p
		end
	end
	return pos % #loop + 1 -- every preset is blocked at this hour: just take the next
end

local function now(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

local function entryFor(presetName: string, seconds: number?): Entry
	local pos = loopPosOf(presetName)
	return {
		index = pos and loop[pos].index or 0,
		preset = presetName,
		seconds = seconds or blockSeconds,
	}
end

type Phase = { entry: Entry, startedAt: number, endsAt: number, nextEntry: Entry }

-- What plays at Unix time t. Pure clock math, so every server gets the same.
local function schedulePhase(t: number): Phase
	local lt = t + offset
	local dayStart = math.floor(lt / DAY) * DAY

	-- the last fixed time at or before now (maybe yesterday's)
	local fi = 0
	for i = #fixed, 1, -1 do
		if dayStart + fixed[i].at <= lt then
			fi = i
			break
		end
	end
	local anchorT
	if fi == 0 then
		fi = #fixed
		anchorT = dayStart - DAY + fixed[fi].at
	else
		anchorT = dayStart + fixed[fi].at
	end
	local anchor = fixed[fi]
	local nextFixed = fixed[fi + 1] or fixed[1]
	local nextFixedT = fixed[fi + 1] and dayStart + nextFixed.at or dayStart + DAY + nextFixed.at
	if fi == #fixed and anchorT < dayStart then
		nextFixedT = dayStart + fixed[1].at
	end

	-- walk the loop from the fixed time to now
	local pos = anchor.loopPos or 0
	local preset = anchor.preset
	local startedAt = anchorT
	local endsAt = math.min(anchorT + blockSeconds, nextFixedT)
	while lt >= endsAt do
		pos = nextLoopPos(pos, endsAt)
		preset = loop[pos].preset
		startedAt = endsAt
		endsAt = math.min(endsAt + blockSeconds, nextFixedT)
	end

	local nextPreset
	if endsAt >= nextFixedT then
		nextPreset = nextFixed.preset
	else
		nextPreset = loop[nextLoopPos(pos, endsAt)].preset
	end

	return {
		entry = entryFor(preset, endsAt - startedAt),
		startedAt = startedAt - offset,
		endsAt = endsAt - offset,
		nextEntry = entryFor(nextPreset),
	}
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
		local nxt = entryFor(phase.nextEntry.preset)
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
			seconds = math.min(amount * 60, 7 * 86400)
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
