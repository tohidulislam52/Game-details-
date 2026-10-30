--!nonstrict
-- (nonstrict on purpose: this file is plain data that you edit)
--[[
	══════════════════════════════════════════════════════════════════════════
	BT SETTINGS — LIVE ENVIRONMENT · SETTINGS
	ModuleScript · ReplicatedStorage > BTSettings > EnvironmentCycle · name: Settings

	The server changes the WHOLE environment (sky, lighting, atmosphere,
	effects, grass, clouds) for EVERY player on a timer, using the preset
	folders in ReplicatedStorage > BTSettings > "All Lighting".

	You only edit THIS file. Full guide (Bangla + English): the "HowToUse"
	script next to this module.

	The 4 EnvironmentCycle files (all stay inside this folder):
	  Settings  (this file)   — schedule, times, notice look
	  Server    (Script, RunContext = Server) — decides what is active now
	  Client    (Script, RunContext = Client) — applies it on each device + notice
	  HowToUse  (guide, never runs)
	══════════════════════════════════════════════════════════════════════════
]]

local Settings = {}

-- false = the whole system is off (nothing changes, no notices).
Settings.enabled = true

-- ═══════════════════════════════════════════════════════════════════════
-- SCHEDULE — real clock + a 2-hour loop
--
-- How a day is built (every server computes the same, so every server of
-- the game shows the same environment at the same moment):
--   1. At each fixedTimes clock time, that preset starts — always.
--   2. After it, the loop goes on: every blockHours the next preset in `loop`.
--   3. A preset listed in onlyBetween is skipped outside its hours
--      (so Night never shows in the daytime).
--   4. When the next fixed time arrives, the running preset ends early.
--
-- With the values below, Bangladesh time:
--   06-08 Sunrise · 08-10 Day · 10-12 Afternoon · 12-14 Sunset
--   14-16 Day · 16-18 Afternoon · 18-20 Sunset · 20-22 Night
--   22-00 Day · 00-02 Afternoon · 02-04 Sunset · 04-06 Night · 06 Sunrise…
-- ═══════════════════════════════════════════════════════════════════════

-- Your time zone (hours from UTC). Bangladesh = 6. All clock times below
-- are in this time zone, wherever the Roblox server is.
Settings.utcOffsetHours = 6

-- How long each preset of the loop stays, in hours (0.5 = 30 minutes).
-- Testing tip: 0.01 ≈ 36 seconds, so you can watch the loop change fast.
Settings.blockHours = 2

-- The presets that take turns, in this order. One line = one preset.
--   preset          REQUIRED · exact folder name inside "All Lighting"
--   title           optional · name shown in the notice (default = preset name)
--   icon            optional · emoji in the notice
--   color           optional · notice accent color
--   message         optional · small line under the title in the notice
--   clockTime       optional · force the sun position (0-24), e.g. 0 for Night.
--                   Without it the preset's "Lighting Valus > ClockTime" is used.
--   transitionTime  optional · blend seconds just for this preset
Settings.loop = {
	{ preset = "Sunrise", title = "Sunrise", icon = "🌅", color = Color3.fromRGB(255, 170, 90) },
	{ preset = "Day", title = "Day", icon = "☀️", color = Color3.fromRGB(255, 220, 110) },
	{ preset = "AfternoonGoldenHour", title = "Afternoon", icon = "🌤️", color = Color3.fromRGB(255, 196, 80) },
	{ preset = "Sunset", title = "Sunset", icon = "🌇", color = Color3.fromRGB(255, 130, 70) },
	{ preset = "Night", title = "Night", icon = "🌙", color = Color3.fromRGB(130, 150, 255) },
}

-- Real clock times ("HH:MM", 24-hour) when a preset ALWAYS starts.
-- The loop continues from that preset afterwards.
-- (No lines here = the loop restarts from its first preset at 00:00.)
Settings.fixedTimes = {
	{ at = "06:00", preset = "Sunrise" }, -- morning: Sunrise
	{ at = "20:00", preset = "Night" }, -- evening: Night for sure
}

-- A preset may only START inside these hours; outside them the loop skips it.
-- "from" later than "to" means across midnight (19:00 → 05:00 = the night).
-- Presets not listed here can come at any time.
Settings.onlyBetween = {
	Night = { from = "19:00", to = "05:00" }, -- Night only at night
	Sunrise = { from = "05:00", to = "09:00" }, -- Sunrise only early morning
}

-- ═══════════════════════════════════════════════════════════════════════
-- TRANSITION — how the change looks
-- ═══════════════════════════════════════════════════════════════════════
Settings.transition = {
	time = 6, -- seconds the lighting / fog / effects smoothly blend into the new preset
	skyFade = 0.8, -- seconds of a quick, soft dim while the sky picture swaps (0 = instant swap)
	skyDim = 0.35, -- how dark that dim gets: 0 = none, 1 = black
	-- How the sun moves when the time of day changes:
	--   "shortest" = the shorter way round the clock
	--   "forward"  = always forward, like a fast time-lapse
	clockDirection = "shortest",
	instantOnJoin = true, -- a player who just joined gets the current preset with no blend
}

-- ═══════════════════════════════════════════════════════════════════════
-- NOTICE — the small pop-up "Environment changed · Night"
-- ═══════════════════════════════════════════════════════════════════════
Settings.notice = {
	enabled = true,
	-- "toast" = the small card made for this system (recommended)
	-- "panel" = use the normal BTSettings pop-up instead
	style = "toast",
	header = "ENVIRONMENT CHANGED", -- small grey line above the name
	showNext = true, -- small line "Next: Sunset in 1h 59m"
	nextFormat = "Next: %s in %s",
	duration = 4.5, -- seconds the card stays on screen
	position = "Top", -- "Top" or "Bottom"
	offsetY = 10, -- points from that edge (Top is already below the Roblox top bar)
	transparency = 0.12, -- card background: 0 = solid, 1 = invisible
	shine = true, -- a soft light sweep across the card when it appears
	mobileScale = 0.9, -- card size on phones (1 = same as PC)
	showOnJoin = false, -- true = also show the card right after joining
	-- true = hidden for players who turned off "Pop-up messages" in Settings.
	respectPopupToggle = true,
	soundId = "", -- optional, e.g. "rbxassetid://1234567890" ("" = no sound)
	soundVolume = 0.5,
}

-- ═══════════════════════════════════════════════════════════════════════
-- PLAYERS — personal choice
-- ═══════════════════════════════════════════════════════════════════════
Settings.player = {
	-- The "Live environment" toggle in Settings › Graphics (in Config).
	-- OFF = this player keeps their own sky; the timer no longer changes it.
	-- ON  = they follow the server again right away. (Not saved: every
	-- player starts with it ON.)
	-- A player can still pick any sky in the Skybox tab at any time; it stays
	-- until the next environment change.
	controlId = "env_live",
	eventName = "BTSettingsEnvLive", -- = Config action name (PREFIX .. "EnvLive")
	-- true = the "Low" quality preset still turns post effects off and thins
	-- the fog after an environment change (uses Config.graphics.presets).
	respectQualityPreset = true,
	-- true = after "Reset lighting" (and no own sky picked), the live
	-- environment comes back instead of the map's original lighting.
	reapplyAfterLightingReset = true,
}

-- ═══════════════════════════════════════════════════════════════════════
-- EXTRAS
-- ═══════════════════════════════════════════════════════════════════════
-- Grass color from the preset's "Grass Color" value. A preset WITHOUT one
-- puts the map's original grass color back (so pink grass does not stay).
Settings.applyGrassColor = true
-- Workspace.Terrain.Clouds from the "Clouds = { ... }" part of the preset's
-- ModuleScript (Day, Night, Sunset ... have one). Needs a Clouds object in Terrain.
Settings.applyClouds = true

-- ═══════════════════════════════════════════════════════════════════════
-- ADMIN — change the environment while the game runs
-- ═══════════════════════════════════════════════════════════════════════
-- Chat commands (only for the people below):
--   /env                 → what is on now and what comes next
--   /env list            → all preset names
--   /env Night           → switch THIS server to Night now (for blockHours)
--   /env Night 30        → Night for 30 minutes, then back to the timer
--   /env next            → jump to the next one
--   /env auto            → cancel your change, back to the timer
-- A change made with a command affects only the server you are in.
Settings.admin = {
	chatCommands = true,
	prefix = "/env",
	userIds = {
		-- TODO: your Roblox user IDs, e.g. 123456789,
	},
	allowGameOwner = true, -- game owner (or group owner, rank 255) is always allowed
	allowInStudio = true, -- everyone may use the commands while testing in Studio
}

return Settings
