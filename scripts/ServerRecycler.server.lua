--!strict
--[[
	ServerRecycler
	রাখবেন: ServerScriptService > ServerRecycler (Script)

	সার্ভার ১২ ঘণ্টা (+ random ০–৩০ মিনিট) পুরনো হলে প্লেয়ারদের ধাপে ধাপে
	একটা নতুন সার্ভারে পাঠিয়ে দেয়। সার্ভার খালি হলে Roblox নিজেই সেটা বন্ধ করে।

	- শুধু নতুন (TARGET_MAX_HOURS-এর কম বয়সী) সার্ভারে পাঠায়, সবচেয়ে নতুনটা আগে।
	  এমন সার্ভার না থাকলে নতুন একটা খোলার জন্য অপেক্ষা করে।
	- নতুন আসা প্লেয়ারকে তার ডেটা লোড হওয়ার পর পাঠায়।
	- DataStore budget দেখে পাঠায়, যাতে একসাথে বেশি save জমে না যায়।

	আগের MemoryGuard স্ক্রিপ্টটা মুছে দিন বা Disabled করুন।
	সাথের LocalScript: StarterPlayer > StarterPlayerScripts > ServerRecycleNotice
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local CONFIG = {
	-- সার্ভার কত ঘণ্টা পর খালি করা শুরু হবে
	MAX_SERVER_HOURS = 12,
	-- সব সার্ভার যেন একসাথে খালি না হয়, তাই প্রতিটা সার্ভারে ০ থেকে এত মিনিট random যোগ হয়
	RANDOM_EXTRA_MINUTES = 30,

	-- শুধু এর চেয়ে কম বয়সী সার্ভারে প্লেয়ার পাঠানো হবে।
	-- এমন সার্ভার না থাকলে নতুন সার্ভার খোলার জন্য অপেক্ষা করবে।
	TARGET_MAX_HOURS = 6,
	-- গন্তব্য সার্ভারে বন্ধু/পার্টির জন্য কয়টা জায়গা খালি রেখে দেবে
	TARGET_FREE_SLOTS = 2,

	-- নতুন প্লেয়ার: join করার পর অন্তত এত সেকেন্ড অপেক্ষা,
	-- তারপর এই attribute true হলে পাঠানো হবে (আপনার ডেটা স্ক্রিপ্টে সেট করুন)
	DATA_LOADED_ATTRIBUTE = "DataLoaded",
	MIN_WAIT_AFTER_JOIN = 30,
	-- attribute কখনো true না হলে join-এর এত সেকেন্ড পর পাঠানো হবে
	MAX_WAIT_AFTER_JOIN = 180,

	-- একজন প্লেয়ার বের হলে আপনার গেম আনুমানিক কয়টা DataStore write করে
	-- (ProfileService + প্রতিটা লিডারবোর্ড)। budget কম থাকলে কম প্লেয়ার পাঠানো হয়।
	WRITES_PER_PLAYER = 6,

	-- false: ৬ ঘণ্টার কম বয়সী সার্ভার না থাকলে চুপচাপ অপেক্ষা করবে, যতক্ষণ না নতুন সার্ভার খোলে।
	-- true: WAIT_FOR_NEW_SERVER_MINUTES পরেও না পেলে একটা নতুন reserved সার্ভারে পাঠাবে।
	USE_RESERVED_FALLBACK = false,
	WAIT_FOR_NEW_SERVER_MINUTES = 45,

	-- কারো teleport এতবার ব্যর্থ হলে তাকে kick করা হবে (ডেটা সাধারণ leave-এর মতোই সেভ হয়)
	KICK_AFTER_FAILED_TRIES = 4,
	KICK_MESSAGE = "This server is restarting. Please rejoin the game.",

	-- নোটিফিকেশন: false করলে কোনো নোটিফিকেশন দেখাবে না
	SHOW_NOTICE = true,
	-- খালি করা শুরুর কত মিনিট আগে "শীঘ্রই" নোটিফিকেশন দেখাবে
	NOTICE_BEFORE_MINUTES = 5,
	NOTICE_SOON = "This server will refresh soon. You'll be moved to a new server automatically.",
	NOTICE_MOVING = "Moving you to a new server…",
	-- Studio-তে Play চাপলে নোটিফিকেশন কেমন দেখায় তা দেখাবে (Studio-তে teleport হয় না)
	PREVIEW_NOTICE_IN_STUDIO = true,

	-- টেস্টের জন্য: true করলে ৬ মিনিটেই সার্ভার খালি করা শুরু হবে। টেস্ট শেষে false করুন!
	TEST_MODE = false,
}

if CONFIG.TEST_MODE then
	CONFIG.MAX_SERVER_HOURS = 0.1 -- 6 minutes
	CONFIG.RANDOM_EXTRA_MINUTES = 0
	CONFIG.NOTICE_BEFORE_MINUTES = 2
	CONFIG.WAIT_FOR_NEW_SERVER_MINUTES = 2
	CONFIG.MIN_WAIT_AFTER_JOIN = 15
	CONFIG.MAX_WAIT_AFTER_JOIN = 60
end

local HEARTBEAT_SECONDS = 20
local ENTRY_TTL = 90
local STALE_SECONDS = 60
local LOOKUP_SECONDS = 15
local PENDING_TIMEOUT = 60
local HOLD_SECONDS = 60
local TARGET_BLOCK_SECONDS = 60
local RESERVED = "reserved"

local NOTICE_ATTRIBUTE = "ServerRecycleNotice" -- on workspace
local MOVING_ATTRIBUTE = "ServerRecycleMoving" -- on each Player

if RunService:IsStudio() then
	if CONFIG.SHOW_NOTICE and CONFIG.PREVIEW_NOTICE_IN_STUDIO then
		task.delay(3, function()
			workspace:SetAttribute(NOTICE_ATTRIBUTE, CONFIG.NOTICE_SOON)
		end)
		task.delay(14, function()
			for _, player in Players:GetPlayers() do
				player:SetAttribute(MOVING_ATTRIBUTE, CONFIG.NOTICE_MOVING)
			end
		end)
	end
	print("[ServerRecycler] Studio: notice preview only, no teleports.")
	return
end

-- VIP (owned private) servers are left alone.
if game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0 then
	return
end

if workspace:GetAttribute("ServerRecyclerRunning") then
	warn("[ServerRecycler] Another copy is already running.")
	return
end
workspace:SetAttribute("ServerRecyclerRunning", true)

local IS_PUBLIC = game.PrivateServerId == ""

local rng = Random.new()
local startedAt = os.time() - math.floor(time())
local limitSeconds = CONFIG.MAX_SERVER_HOURS * 3600
	+ rng:NextInteger(0, CONFIG.RANDOM_EXTRA_MINUTES * 60)
local noticeAt = limitSeconds - CONFIG.NOTICE_BEFORE_MINUTES * 60
local targetMaxAge = CONFIG.TARGET_MAX_HOURS * 3600

type State = {
	joined: number,
	due: number,
	failures: number,
	token: string?,
	target: string?,
	sentAt: number,
}

local states: { [Player]: State } = {}
local blocked: { [string]: number } = {}
local warningTimes: { [string]: number } = {}

local map = MemoryStoreService:GetSortedMap("ServerRecycler_v1_" .. game.PlaceId)

local draining = false
local closing = false
local published = false
local reservedCode: string? = nil

local function warnLimited(key: string, message: string)
	if os.clock() - (warningTimes[key] or -math.huge) >= 60 then
		warningTimes[key] = os.clock()
		warn("[ServerRecycler] " .. message)
	end
end

local function add(player: Player)
	if states[player] then
		return
	end
	states[player] = {
		joined = os.clock(),
		due = 0,
		failures = 0,
		token = nil,
		target = nil,
		sentAt = 0,
	}
end

Players.PlayerAdded:Connect(add)
Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)
for _, player in Players:GetPlayers() do
	add(player)
end

----------------------------------------------------------------------
-- Registry: young public servers advertise themselves so draining
-- servers can find them. Servers older than TARGET_MAX_HOURS remove
-- their entry, so nobody is sent to an old server.
----------------------------------------------------------------------

local function cleanHolds(value: any): number
	if type(value.holds) ~= "table" then
		value.holds = {}
	end
	local total = 0
	for id, hold in value.holds do
		if type(hold) ~= "table"
			or type(hold.count) ~= "number"
			or type(hold.untilTime) ~= "number"
			or hold.untilTime <= os.time()
		then
			value.holds[id] = nil
		else
			total += hold.count
		end
	end
	return total
end

local function freeSlots(value: any): number
	return value.capacity - value.count - cleanHolds(value) - CONFIG.TARGET_FREE_SLOTS
end

local function validTarget(value: any): boolean
	return type(value) == "table"
		and type(value.startedAt) == "number"
		and type(value.updated) == "number"
		and type(value.count) == "number"
		and type(value.capacity) == "number"
		and os.time() - value.updated <= STALE_SECONDS
		and os.time() - value.startedAt < targetMaxAge
end

local function canReceive(): boolean
	return IS_PUBLIC and not draining and not closing and time() < targetMaxAge
end

task.spawn(function()
	while not closing do
		if canReceive() then
			local ok, err = pcall(function()
				map:UpdateAsync(game.JobId, function(old: any)
					local value = if type(old) == "table" then old else {}
					cleanHolds(value)
					value.startedAt = startedAt
					value.count = #Players:GetPlayers()
					value.capacity = Players.MaxPlayers
					value.updated = os.time()
					return value, startedAt
				end, ENTRY_TTL)
			end)
			if ok then
				published = true
			else
				warnLimited("publish", "Registry write failed: " .. tostring(err))
			end
		elseif published then
			if pcall(function()
				map:RemoveAsync(game.JobId)
			end) then
				published = false
			end
		end
		task.wait(HEARTBEAT_SECONDS)
	end
end)

-- Youngest servers first. Reserves a few slots there so two draining
-- servers don't overfill the same destination.
local function findPublicTarget(wanted: number, ticket: string): (string?, number)
	local ok, rows = pcall(function()
		return map:GetRangeAsync(Enum.SortDirection.Descending, 200)
	end)
	if not ok then
		warnLimited("lookup", "Registry lookup failed; will retry.")
		return nil, 0
	end

	local tried = 0
	for _, row in rows do
		if tried >= 3 then
			break
		end
		local id = row.key
		if id ~= game.JobId
			and (blocked[id] or 0) <= os.clock()
			and validTarget(row.value)
			and freeSlots(row.value) >= 1
		then
			tried += 1
			local claimed, result = pcall(function()
				return map:UpdateAsync(id, function(current: any)
					if not validTarget(current) then
						return nil
					end
					local slots = math.min(wanted, freeSlots(current))
					if slots < 1 then
						return nil
					end
					current.holds[ticket] = {
						count = slots,
						untilTime = os.time() + HOLD_SECONDS,
					}
					return current, current.startedAt
				end, ENTRY_TTL)
			end)
			if claimed
				and type(result) == "table"
				and type(result.holds) == "table"
				and type(result.holds[ticket]) == "table"
			then
				return id, result.holds[ticket].count
			end
		end
	end
	return nil, 0
end

local function getReservedCode(): string?
	if reservedCode then
		return reservedCode
	end
	local ok, code = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if ok and type(code) == "string" then
		reservedCode = code
		return code
	end
	warnLimited("reserve", "ReserveServer failed: " .. tostring(code))
	return nil
end

----------------------------------------------------------------------
-- Teleport helpers
----------------------------------------------------------------------

local function failed(player: Player, token: string, reason: string)
	local state = states[player]
	if not state or state.token ~= token then
		return
	end

	state.token = nil
	if state.target == RESERVED then
		reservedCode = nil
	elseif state.target then
		blocked[state.target] = os.clock() + TARGET_BLOCK_SECONDS
	end
	state.target = nil
	state.failures += 1
	player:SetAttribute(MOVING_ATTRIBUTE, nil)

	warnLimited("teleport", "Teleport failed, will retry: " .. reason)

	if state.failures >= CONFIG.KICK_AFTER_FAILED_TRIES then
		player:Kick(CONFIG.KICK_MESSAGE)
		return
	end
	state.due = os.clock() + math.min(30, 2 ^ state.failures) + rng:NextNumber()
end

TeleportService.TeleportInitFailed:Connect(function(player, result, message, placeId, options)
	if not draining or placeId ~= game.PlaceId or not options then
		return
	end
	local ok, data = pcall(function()
		return options:GetTeleportData()
	end)
	if ok
		and type(data) == "table"
		and data.recycleSource == game.JobId
		and type(data.recycleToken) == "string"
	then
		failed(player, data.recycleToken, result.Name .. ": " .. message)
	end
end)

-- Has this player been here long enough for their data to load?
local function isReady(player: Player, state: State): boolean
	local waited = os.clock() - state.joined
	if waited < CONFIG.MIN_WAIT_AFTER_JOIN then
		return false
	end
	if waited >= CONFIG.MAX_WAIT_AFTER_JOIN then
		return true
	end
	return player:GetAttribute(CONFIG.DATA_LOADED_ATTRIBUTE) == true
end

-- Start small, speed up as the server empties.
local function batchPlan(remaining: number): (number, number)
	if remaining > 20 then
		return 3, 12
	end
	if remaining > 10 then
		return 4, 10
	end
	if remaining > 5 then
		return 5, 8
	end
	return math.max(1, remaining), 5
end

-- How many players can leave right now without running out of DataStore budget.
local function playersSaveBudgetAllows(): number
	local ok, budget = pcall(function()
		return math.min(
			DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementAsync),
			DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync),
			DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.SetIncrementSortedAsync)
		)
	end)
	if not ok then
		return math.huge
	end
	return math.floor(budget / math.max(1, CONFIG.WRITES_PER_PLAYER))
end

----------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------

local drainStartedAt = 0
local nextBatch = 0
local noticeShown = false

task.spawn(function()
	while not closing do
		task.wait(1)
		local age = time()

		if CONFIG.SHOW_NOTICE and not noticeShown and age >= noticeAt then
			noticeShown = true
			workspace:SetAttribute(NOTICE_ATTRIBUTE, CONFIG.NOTICE_SOON)
		end

		if not draining then
			if age < limitSeconds then
				continue
			end
			draining = true
			drainStartedAt = os.clock()
			workspace:SetAttribute("ServerRecycling", true)
			print(string.format(
				"[ServerRecycler] Server is %.1f hours old. Moving players to newer servers.",
				age / 3600
			))
		end

		-- A teleport that never finished and never reported failure.
		for player, state in states do
			local token = state.token
			if token and os.clock() - state.sentAt >= PENDING_TIMEOUT then
				failed(player, token, "no response")
			end
		end

		if os.clock() < nextBatch then
			continue
		end

		local waiting: { Player } = {}
		for player, state in states do
			if not state.token
				and state.due <= os.clock()
				and player.Parent == Players
				and isReady(player, state)
			then
				table.insert(waiting, player)
			end
		end
		if #waiting == 0 then
			continue
		end
		-- Players who have been here longest go first.
		table.sort(waiting, function(a, b)
			return states[a].joined < states[b].joined
		end)

		local size, pause = batchPlan(#Players:GetPlayers())
		size = math.min(size, #waiting, playersSaveBudgetAllows())
		if size < 1 then
			nextBatch = os.clock() + 5
			continue
		end

		local token = HttpService:GenerateGUID(false)
		local options = Instance.new("TeleportOptions")
		local targetName = RESERVED
		local serverId, slots = findPublicTarget(size, token)

		if serverId then
			options.ServerInstanceId = serverId
			targetName = serverId
		elseif CONFIG.USE_RESERVED_FALLBACK
			and os.clock() - drainStartedAt >= CONFIG.WAIT_FOR_NEW_SERVER_MINUTES * 60
		then
			local code = getReservedCode()
			if not code then
				nextBatch = os.clock() + LOOKUP_SECONDS
				continue
			end
			options.ReservedServerAccessCode = code
			slots = size
		else
			-- No new-enough server yet. Wait for one to open.
			nextBatch = os.clock() + LOOKUP_SECONDS
			continue
		end

		options:SetTeleportData({
			recycleSource = game.JobId,
			recycleToken = token,
		})

		-- Registry calls yield, so re-check who is still here.
		local batch: { Player } = {}
		for _, player in waiting do
			local state = states[player]
			if state and not state.token and player.Parent == Players then
				state.token = token
				state.target = targetName
				state.sentAt = os.clock()
				if CONFIG.SHOW_NOTICE then
					player:SetAttribute(MOVING_ATTRIBUTE, CONFIG.NOTICE_MOVING)
				end
				table.insert(batch, player)
				if #batch >= slots then
					break
				end
			end
		end
		if #batch == 0 then
			continue
		end

		-- Let the "moving you" notice show before Roblox's teleport screen.
		if CONFIG.SHOW_NOTICE then
			task.wait(1.5)
		end

		local stillHere: { Player } = {}
		for _, player in batch do
			if player.Parent == Players then
				table.insert(stillHere, player)
			end
		end

		if #stillHere > 0 then
			local ok, err = pcall(function()
				TeleportService:TeleportAsync(game.PlaceId, stillHere, options)
			end)
			if not ok then
				for _, player in stillHere do
					failed(player, token, tostring(err))
				end
			end
		end

		nextBatch = os.clock() + pause
	end
end)

game:BindToClose(function()
	closing = true
	if published then
		pcall(function()
			map:RemoveAsync(game.JobId)
		end)
	end
	-- আপনার ডেটা-সেভের BindToClose হ্যান্ডলারগুলো যেমন আছে তেমনই রাখুন।
end)
