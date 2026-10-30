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
-- SCHEDULE — which presets play, in which order, and for how long
-- ═══════════════════════════════════════════════════════════════════════
-- Unit for every `duration` below: "seconds", "minutes" or "hours".
-- (Testing tip: set "seconds" and small numbers like 20, see it change fast.)
Settings.timeUnit = "minutes"

-- One line = one environment. They play top to bottom, then start again.
--   preset         REQUIRED · exact folder name inside "All Lighting"
--   duration       REQUIRED · how long it stays (in Settings.timeUnit)
--   title          optional · name shown in the notice (default = preset name)
--   icon           optional · emoji in the notice
--   color          optional · notice accent color, e.g. Color3.fromRGB(255, 170, 60)
--   message        optional · small line under the title in the notice
--   clockTime      optional · force the sun position (0-24) for this preset,
--                  e.g. 0 = midnight moon. Without it the preset's own
--                  "Lighting Valus > ClockTime" is used.
--   transitionTime optional · blend seconds just for this preset
--
-- Use only the presets you want. The same preset may appear more than once.
-- Your preset folders: Sunrise, MorningGoldenHour, Day, AfternoonGoldenHour,
-- Sunset, Twilight, Night, Tower Main Light, Pink SKy, Golden Sky,
-- Cloudy sky, Breakup Sky
Settings.schedule = {
	{ preset = "Sunrise", duration = 60, title = "Sunrise", icon = "🌅", color = Color3.fromRGB(255, 170, 90) },
	{ preset = "Day", duration = 120, title = "Day", icon = "☀️", color = Color3.fromRGB(255, 220, 110) },
	{ preset = "AfternoonGoldenHour", duration = 60, title = "Afternoon", icon = "🌤️", color = Color3.fromRGB(255, 196, 80) },
	{ preset = "Sunset", duration = 60, title = "Sunset", icon = "🌇", color = Color3.fromRGB(255, 130, 70) },
	{ preset = "Night", duration = 120, title = "Night", icon = "🌙", color = Color3.fromRGB(130, 150, 255) },

	-- More examples (remove the "--" to use them):
	-- { preset = "Twilight", duration = 30, title = "Twilight", icon = "🌆", color = Color3.fromRGB(90, 130, 220) },
	-- { preset = "Pink SKy", duration = 60, title = "Pink Sky", icon = "🌸", color = Color3.fromRGB(240, 140, 230) },
	-- { preset = "Golden Sky", duration = 60, title = "Golden Sky", icon = "✨" },
}

-- "loop"    = play the list top to bottom, again and again.
-- "shuffle" = mix the order every round (every server still shows the same one
--             when syncAllServers = true).
Settings.order = "loop"

-- true  = EVERY server of the game shows the same environment at the same
--         moment (based on the real clock). A player who switches servers
--         sees the same sky. Recommended.
-- false = each server starts its own cycle when it opens (see startWith).
Settings.syncAllServers = true

-- syncAllServers = true only: the real clock time when the FIRST line of the
-- schedule starts. utcOffsetHours = your time zone (Bangladesh = 6).
-- Tip: make the durations add up to 24 hours and the presets follow the real
-- day — e.g. Sunrise at 6:00 in Bangladesh: hour = 6, minute = 0.
Settings.cycleStart = { hour = 6, minute = 0, utcOffsetHours = 6 }

-- syncAllServers = false only: where a new server starts.
-- 1 = first line · "random" = any line · "Night" = the first line with that preset.
Settings.startWith = 1

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
	-- The "Live environment" toggle in Settings › Graphics (added to Config).
	-- OFF = this player keeps their own sky; the timer no longer changes it.
	-- ON  = they follow the server again right away.
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
--   /env Night           → switch THIS server to Night now (for its normal duration)
--   /env Night 30        → Night for 30 minutes (Settings.timeUnit), then back to the timer
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
