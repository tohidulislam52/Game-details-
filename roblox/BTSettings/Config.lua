--!nonstrict
-- (nonstrict on purpose: this file is plain data that you edit, so the type
--  checker should not flood Script Analysis while you add controls)
--[[
	══════════════════════════════════════════════════════════════════════════
	BT SETTINGS — CONFIG
	ModuleScript · ReplicatedStorage > BTSettings · name: Config

	This ONE file controls the whole Settings panel: tabs, controls, what each
	control does, colors (theme), the floating button, sizes and lists.

	• How to add a new tab / button / toggle / slider, bindable vs remote, and
	  ready-to-copy receiver scripts → read the "HowToAddFeatures" script that
	  sits next to this module.
	• Every other value below has a plain-language explanation next to it.
	• Lines marked TODO need your real names / IDs.

	The 5 BTSettings files:
	  ReplicatedStorage   > BTSettings > Config            (this file)
	  ReplicatedStorage   > BTSettings > HowToAddFeatures  (guide, never runs)
	  ServerScriptService > BTSettings > Server
	  StarterPlayerScripts> BTSettings > UI                (draws the panel, sends signals)
	  StarterPlayerScripts> BTSettings > Features          (graphics, skybox, camera,
	                                                        audio, name tags, lag tip)
	  ReplicatedStorage   > BTSettings > EnvironmentCycle  (live sky / day-night timer
	                                                        for everyone → its Settings)
	══════════════════════════════════════════════════════════════════════════
]]

local Config = {}

-- Every event, GUI and global name is built from this word.
Config.PREFIX = "BTSettings"
local P = Config.PREFIX

-- The ReplicatedStorage > BTSettings folder this module lives in. Every script
-- finds BTSettingsRemotes, BTSettingsSkyboxes and "All Lighting" through it.
Config.root = script.Parent

Config.version = "1.1"

-- ═══════════════════════════════════════════════════════════════════════
-- NAMES (built from PREFIX — you normally never touch these)
-- ═══════════════════════════════════════════════════════════════════════
Config.names = {
	remotesFolder = P .. "Remotes", -- inside ReplicatedStorage > BTSettings (made by the server)
	skyboxFolder = P .. "Skyboxes", -- inside ReplicatedStorage > BTSettings: your Sky objects
	lightingFolder = "All Lighting", -- inside ReplicatedStorage > BTSettings: your preset folders

	-- client signals (BindableEvents, created on each device)
	skyboxEvent = P .. "SkyboxEvent",
	skyboxApplied = P .. "SkyboxApplied",
	notify = P .. "Notify",
	notifyClosed = P .. "NotifyClosed",
	openTab = P .. "OpenTab",
	addControl = P .. "AddControl",
	setValue = P .. "SetValue", -- Features → UI: "show this value on the slider/toggle"
	uiReady = P .. "UIReady", -- UI → Features: "I am listening now"
	getValue = P .. "GetValue", -- BindableFunction: read any remembered value
	floatingButtonToggle = P .. "SetFloatingButton", -- Fire(false) hides, Fire(true) shows

	-- server remotes (created by the Server script)
	getServerList = "GetServerList",
	requestTeleport = "RequestTeleport",
	serverNotice = "ServerDataUpdate",

	-- UI / runtime names
	gui = P .. "_v1",
	topbarHost = P .. "TopbarHost",
	toggleButton = P .. "Toggle",
	floatingGui = P .. "FloatingButton",
	cameraStep = P .. "CameraStep",
	topbarGlobal = P .. "TopbarIcon", -- _G.BTSettingsTopbarIcon
}

-- Leftovers from the previous version of the panel get destroyed on start.
-- The old brand word is joined from two pieces on purpose, so a text search
-- for it finds nothing. Safe to delete this block once every server runs v1.
local OLD = "Ne" .. "xus"
Config.legacy = {
	guiNames = {
		"BanglaTower_" .. OLD .. "_v5",
		"BanglaTower_" .. OLD .. "_v41",
		"BanglaTower_" .. OLD .. "_v4",
		OLD .. "TopbarHost",
	},
	globalNames = { OLD .. "TopbarIcon" },
}

-- ═══════════════════════════════════════════════════════════════════════
-- LOOK & FEEL (for you, the developer — players never see these options)
-- ═══════════════════════════════════════════════════════════════════════
Config.ui = {
	title = "Settings", -- big title on the home screen
	homeSubtitle = "Bangla Tower · choose a category",

	-- Which description to show where a Bangla version (descBn) exists:
	-- "en" = English only, "bn" = Bangla only, "both" = English + Bangla.
	-- If Bangla shows as empty boxes on some device, use "en".
	language = "en",

	-- Size multipliers on top of the automatic screen scaling.
	-- 1.0 = normal, 1.2 = 20% bigger, 0.9 = 10% smaller.
	desktopScale = 1.0,
	tabletScale = 1.0,
	mobileScale = 1.0,

	-- Smallest tap target on touch screens, in screen points (48 = Google/Apple advice).
	-- The Close (X) button, every button, toggle and slider respect it.
	mobileTouchMinSize = 36,

	-- true = phones skip the decorative animations (smoother on weak phones).
	reduceAnimationsOnMobile = true,

	-- Glass look: 0 = solid, 1 = invisible. Text and borders always stay solid.
	-- (Colors come from Config.theme; these only control see-through-ness.)
	panelTransparency = 0.3, -- the big panel
	cardTransparency = 0.3, -- cards, rows, buttons, toggles, slider rows
	-- Optional override for phones, e.g. { panel = 0.15, card = 0.1 } (more solid).
	mobileTransparency = nil :: { panel: number?, card: number? }?,
	backdropTransparency = 0.45, -- dark layer behind the panel (keeps text readable)

	-- false = tapping the dark area OUTSIDE the panel does nothing (the panel
	-- closes only with X, the TopbarPlus icon or the floating button).
	-- true  = tapping outside closes the panel (old behaviour).
	closeOnBackdropClick = false,

	-- Panel size as a share of the screen (width, height). Capped by maxWidth/maxHeight.
	panelSizeDesktop = Vector2.new(0.72, 0.78),
	panelSizeMobile = Vector2.new(0.96, 0.94),
	maxWidth = 720,
	maxHeight = 600,
	maxWidthMobile = 860,

	enableSearch = true, -- search icon in the header
	newBadgeText = "NEW",
}

-- Fonts used by the panel.
Config.fonts = {
	family = "rbxasset://fonts/families/GothamSSm.json",
	mono = "rbxasset://fonts/families/RobotoMono.json",
}

-- TopbarPlus icon (kept exactly as before; a fallback button appears if
-- TopbarPlus is not installed).
Config.topbar = {
	name = "BT Settings",
	image = "rbxassetid://109067899306607",
	fallbackPosition = UDim2.fromOffset(56, 4),
}

-- ═══════════════════════════════════════════════════════════════════════
-- FLOATING BUTTON — the small button on the screen edge that opens/closes
-- the panel. Every field is optional: leave one out and the default is used.
-- A wrong value prints a warning in Output and the default is used instead.
-- ═══════════════════════════════════════════════════════════════════════
Config.floatingButton = {
	enabled = true, -- false = the button is never created at all (TopbarPlus icon still works)

	-- ── position ──
	anchor = "Right", -- which screen edge: "Right" or "Left"
	positionY = 0.48, -- up/down: 0 = top, 0.5 = middle, 1 = bottom
	offsetX = 0, -- distance from the screen edge, in points
	offsetY = 0, -- small extra up(-)/down(+) nudge, in points

	-- ── size and shape ──
	width = 36, -- points
	height = 36, -- points
	cornerRadius = 6, -- 0 = sharp square corners, width/2 = perfect circle

	-- ── colors and transparency ──
	backgroundColor = Color3.fromRGB(28, 31, 44), -- normal color
	backgroundTransparency = 0.25, -- 0 = solid, 1 = invisible
	hoverColor = Color3.fromRGB(45, 45, 45), -- when the mouse is over it (PC)
	pressedColor = Color3.fromRGB(70, 70, 70), -- while it is being pressed / tapped
	-- true = ignore the 3 colors above, the stroke color and the icon colors,
	-- and use the active theme instead (background / elevated / hover / accent / text).
	useThemeColors = false,

	-- ── border (thin outline) ──
	strokeEnabled = true, -- false = no outline
	strokeColor = Color3.fromRGB(255, 255, 255),
	strokeThickness = 1, -- outline width in points
	strokeTransparency = 0.5, -- 0 = solid, 1 = invisible

	-- ── icon ──
	iconType = "image", -- "text" = a symbol/letters, "image" = a Roblox image
	iconText = "⚙️", -- the symbol shown when iconType = "text" (and the backup for images)
	iconTextColor = Color3.fromRGB(255, 255, 255),
	iconTextSize = 20, -- text size in points
	iconImage = "rbxassetid://109067899306607", -- your image ID when iconType = "image"; if it cannot load, iconText is shown
	iconImageColor = Color3.fromRGB(255, 255, 255), -- tint of the image (white = original colors)
	iconSize = 24, -- image size in points

	-- ── behaviour ──
	hideWhenOpen = true, -- fade the button away while the panel is open
	pressAnimation = true, -- small shrink when pressed
	zIndex = 10, -- drawing order (higher = on top of other buttons in its layer)
	mobileSizeMultiplier = 1.0, -- extra size on phones (multiplies ui.mobileScale; never below mobileTouchMinSize)
}
-- Other LocalScripts can hide the button for a moment (e.g. a cutscene):
--   ReplicatedStorage.BTSettings.BTSettingsRemotes:WaitForChild("BTSettingsSetFloatingButton"):Fire(false) -- hide
--   ...:Fire(true)  -- show again

-- Pop-up messages.
Config.notifications = {
	maxVisible = 3,
	duration = 3.2, -- seconds before a normal pop-up disappears
	controlId = "ui_notifications", -- the toggle that turns pop-ups on/off
	-- DECISION: errors and the "game is slow" tip still show when the player
	-- turned pop-ups off, because they need the player's attention. Set false
	-- to hide those too.
	alwaysShowCritical = true,
}

-- ═══════════════════════════════════════════════════════════════════════
-- SOUNDS — the small "click" when the player uses the panel.
--
-- Where to get an ID: open the sound in the Creator Store / Toolbox (or your
-- own uploaded audio), copy its number, and paste it like this:
--     clickSoundId = "rbxassetid://1234567890",
-- Volume: 0 = silent, 0.5 = half, 1 = full. (Used by EVERY UI sound below.)
-- Turn all UI sounds off: enabled = false (nothing is created at all).
--
-- Plays on: home tab cards, buttons, toggles, quality preset cards, skybox
-- Apply, server Refresh / Join, Back, Close (X), search icon, pop-up buttons,
-- the floating button and the TopbarPlus icon. Sliders click ONCE when the
-- player starts dragging, never while the value changes.
-- New controls you add to Config get the sound automatically.
--
-- DECISIONS:
--   • UI sounds count as game audio: "Mute all game audio" (Audio tab)
--     silences them, and "Master volume" makes them quieter too.
--   • "Mute boombox" / "Boombox volume" never touch them.
--   • The "Pop-up messages" toggle only hides pop-ups; it does not change
--     sounds.
--   • reduceAnimationsOnMobile does not affect sounds (phones click too).
-- A missing or wrong ID prints one warning in Output; the panel keeps working.
-- ═══════════════════════════════════════════════════════════════════════
Config.sounds = {
	enabled = true, -- false = no UI sounds are created at all (zero cost)
	clickSoundId = "rbxassetid://139719503904449", -- TODO: paste your click sound ID here
	clickVolume = 2.5, -- 0 = silent, 1 = full volume (all UI sounds use this)
	clickPlaybackSpeed = 1, -- 1 = normal; 1.2 = a bit higher/faster, 0.8 = lower/slower

	-- Optional extra sounds. Leave "" to use the click sound instead.
	toggleSoundId = "rbxassetid://139719503904449", -- on/off switches
	sliderSoundId = "rbxassetid://139719503904449", -- when a slider drag starts
	openSoundId = "rbxassetid://70452176150315", -- when the panel opens ("" = the click)
	closeSoundId = "rbxassetid://139719503904449", -- when the panel closes ("" = the click)
	-- Mouse-over sound (PC only). "" = off (recommended: hover sounds get annoying).
	hoverSoundId = "",
}

--Config.sounds = {
--	enabled = true,

--	clickSoundId = "rbxassetid://139719503904449",
--	clickVolume = 0.5,
--	clickPlaybackSpeed = 1,

--	toggleSoundId = "rbxassetid://958120197",
--	sliderSoundId = "rbxassetid://958120197",
--	openSoundId = "rbxassetid://70452176150315",
--	closeSoundId = "rbxassetid://958120197",
--	hoverSoundId = "",
--}

-- ═══════════════════════════════════════════════════════════════════════
-- THEME — every color of the panel comes from here (layout never changes).
--
-- Change `active` to another preset name and the whole panel recolors.
-- Make your own: copy a preset block (e.g. Blue = { ... }), rename it
-- (MyTheme = { ... }), change the colors, then set active = "MyTheme".
-- A missing or wrong color prints a warning and is taken from Dark.
--
-- What each color is used for:
--   background    the big panel behind everything
--   card          cards, rows, toggle rows, slider rows
--   cardHover     a card/row while the mouse is over it
--   elevated      small raised parts: icon circles, dark buttons, back/close/search buttons
--   hover         a dark button while the mouse is over it
--   stroke        thin outlines around cards and rows
--   strokeStrong  stronger outlines: the panel edge, dark buttons, value boxes
--   accent        the highlight color: switches that are ON, slider fill + knob,
--                 main buttons, active preset card, "Applied" sky border, NEW badge
--   accentHover   a main (accent) button while the mouse is over it
--   onAccent      text/icons drawn ON the accent color (must be readable on it)
--   text          main text (titles)
--   textMuted     secondary text (values, labels)
--   textDim       small grey descriptions and section headings
--   track         the empty part of sliders and switches that are OFF
--   inset         darker boxes: the slider number box, the search box
--   backdrop      the dark layer behind the panel (its see-through amount is
--                 ui.backdropTransparency)
--   danger        error pop-ups (outline and icon)
-- Transparency is NOT part of the theme — see Config.ui above.
-- ═══════════════════════════════════════════════════════════════════════
Config.theme = {
	active = "Dark",

	presets = {
		Dark = {
			background = Color3.fromRGB(14, 14, 14),
			card = Color3.fromRGB(24, 24, 24),
			cardHover = Color3.fromRGB(32, 32, 32),
			elevated = Color3.fromRGB(38, 38, 38),
			hover = Color3.fromRGB(52, 52, 52),
			stroke = Color3.fromRGB(46, 46, 46),
			strokeStrong = Color3.fromRGB(105, 105, 105),
			accent = Color3.fromRGB(255, 255, 255),
			accentHover = Color3.fromRGB(222, 222, 222),
			onAccent = Color3.fromRGB(0, 0, 0),
			text = Color3.fromRGB(245, 245, 245),
			textMuted = Color3.fromRGB(175, 175, 175),
			textDim = Color3.fromRGB(128, 128, 128),
			track = Color3.fromRGB(58, 58, 58),
			inset = Color3.fromRGB(9, 9, 9),
			backdrop = Color3.fromRGB(0, 0, 0),
			danger = Color3.fromRGB(255, 90, 90),
		},

		Blue = {
			background = Color3.fromRGB(12, 14, 20),
			card = Color3.fromRGB(21, 25, 35),
			cardHover = Color3.fromRGB(29, 34, 47),
			elevated = Color3.fromRGB(35, 41, 56),
			hover = Color3.fromRGB(47, 55, 74),
			stroke = Color3.fromRGB(42, 50, 68),
			strokeStrong = Color3.fromRGB(94, 108, 138),
			accent = Color3.fromRGB(88, 160, 255),
			accentHover = Color3.fromRGB(128, 184, 255),
			onAccent = Color3.fromRGB(4, 14, 32),
			text = Color3.fromRGB(240, 244, 255),
			textMuted = Color3.fromRGB(168, 178, 200),
			textDim = Color3.fromRGB(118, 128, 150),
			track = Color3.fromRGB(52, 60, 80),
			inset = Color3.fromRGB(7, 9, 15),
			backdrop = Color3.fromRGB(0, 3, 10),
			danger = Color3.fromRGB(255, 95, 95),
		},

		Green = {
			background = Color3.fromRGB(12, 16, 14),
			card = Color3.fromRGB(21, 29, 25),
			cardHover = Color3.fromRGB(29, 39, 34),
			elevated = Color3.fromRGB(35, 47, 41),
			hover = Color3.fromRGB(47, 63, 55),
			stroke = Color3.fromRGB(42, 56, 49),
			strokeStrong = Color3.fromRGB(94, 128, 110),
			accent = Color3.fromRGB(72, 214, 134),
			accentHover = Color3.fromRGB(112, 228, 162),
			onAccent = Color3.fromRGB(3, 24, 12),
			text = Color3.fromRGB(240, 250, 244),
			textMuted = Color3.fromRGB(168, 190, 178),
			textDim = Color3.fromRGB(118, 140, 128),
			track = Color3.fromRGB(52, 68, 60),
			inset = Color3.fromRGB(7, 11, 9),
			backdrop = Color3.fromRGB(0, 6, 3),
			danger = Color3.fromRGB(255, 95, 95),
		},

		Gold = {
			background = Color3.fromRGB(18, 16, 12),
			card = Color3.fromRGB(29, 26, 20),
			cardHover = Color3.fromRGB(39, 35, 26),
			elevated = Color3.fromRGB(47, 42, 31),
			hover = Color3.fromRGB(63, 56, 41),
			stroke = Color3.fromRGB(57, 51, 38),
			strokeStrong = Color3.fromRGB(128, 113, 80),
			accent = Color3.fromRGB(242, 192, 72),
			accentHover = Color3.fromRGB(250, 210, 112),
			onAccent = Color3.fromRGB(30, 20, 0),
			text = Color3.fromRGB(250, 246, 236),
			textMuted = Color3.fromRGB(194, 184, 164),
			textDim = Color3.fromRGB(144, 134, 114),
			track = Color3.fromRGB(68, 61, 45),
			inset = Color3.fromRGB(11, 9, 6),
			backdrop = Color3.fromRGB(6, 4, 0),
			danger = Color3.fromRGB(255, 95, 95),
		},
	},
}

-- ═══════════════════════════════════════════════════════════════════════
-- GRAPHICS (Features → Graphics section)
-- ═══════════════════════════════════════════════════════════════════════
-- Roblox does not let game scripts change the player's own graphics quality
-- level or render distance, so presets change what a game CAN control:
--   shadows      true/false (nil = keep the map's value)
--   shadowSoftness  number 0..1 (nil = keep the map's value)
--   particleScale   1 = all particles, 0.5 = half emit rate, 0 = particles off
--   fogAmount       1 = map's full fog/atmosphere, 0.4 = much thinner fog
--   postEffects     false = turn off Bloom/Blur/SunRays/DepthOfField/ColorCorrection
Config.graphics = {
	presetControlId = "gfx_preset",
	presets = {
		Low = { shadows = false, particleScale = 0, fogAmount = 0.4, postEffects = false },
		Medium = { shadows = true, shadowSoftness = 0.6, particleScale = 0.5, fogAmount = 0.7, postEffects = true },
		High = { shadows = true, particleScale = 1, fogAmount = 1, postEffects = true },
	},
	maxFogEnd = 100000,
}

-- ═══════════════════════════════════════════════════════════════════════
-- LAG TIP (Features → Lag section) — session only, nothing is saved
-- ═══════════════════════════════════════════════════════════════════════
Config.lag = {
	enabled = true,
	fpsThreshold = 30, -- below this FPS counts as "slow"
	lowSeconds = 6, -- must stay slow this many seconds in a row
	startDelay = 20, -- wait after joining (loading is always slow)
	sampleWindow = 120, -- each check runs this long, then stops by itself
	lagNoticeCooldown = 300, -- seconds after the 1st tip is closed before the 2nd check (300 = 5 min, 600 = 10 min)
	maxNotices = 2, -- after this many tips, detection stops for the session
	okPresets = { "Low", "Medium" }, -- if the player picks one of these, no more tips
	title = "Game is running slowly",
	message = "Go to Settings › Graphics and choose Low for smoother play.",
	buttonText = "Open Graphics",
	tab = "graphics",
}

-- ═══════════════════════════════════════════════════════════════════════
-- AUDIO (Features → Audio section) — affects ONLY this player's device
-- ═══════════════════════════════════════════════════════════════════════
Config.audio = {
	-- TODO: put the REAL names of your two boombox Sound objects here.
	boomboxSoundNames = { "BoomboxSound", "MusicSound" },
	-- Optional: a CollectionService tag. Tag a Sound, or the Tool that
	-- contains the Sound. nil = names only.
	boomboxTag = nil :: string?,
	-- true = "Mute boombox" and "Boombox volume" only change OTHER players'
	-- boomboxes; your own boombox is never touched by them.
	excludeOwnBoombox = true,
}

-- ═══════════════════════════════════════════════════════════════════════
-- NAME TAGS / BILLBOARDS (Features → Billboards section)
-- ═══════════════════════════════════════════════════════════════════════
Config.billboards = {
	-- TODO: put the REAL BillboardGui names here. A "Hide <name>" toggle only
	-- appears for names that really exist on some player's character.
	hideBillboardNames = { "BillboardGui", "BTTitleBillboard", "VipTag" },
	includeOwnTag = true, -- true = also hide/show your own tag
	tab = "player",
	section = "character", -- section id inside that tab
	titleFormat = "Hide %s",
	descFormat = "Hides every %s above players. Only on your screen.",
}

-- ═══════════════════════════════════════════════════════════════════════
-- SKYBOX (UI Skybox page + Features → Skybox section)
-- ═══════════════════════════════════════════════════════════════════════
Config.skybox = {
	-- Preview pictures: Sky name → Roblox image asset ID. Adding a new sky =
	-- put a Sky in BTSettingsSkyboxes + a folder in "All Lighting" + one line here.
	-- A sky without a line here shows the ◆ symbol instead.
	previews = {
		-- TODO: replace with your real image IDs, e.g.
		-- ["Sunset"] = "rbxassetid://1234567890",
		-- ["Night"] = "rbxassetid://1234567891",
	} :: { [string]: string },

	showOriginal = true, -- first card = the map's own sky
	originalId = "__original",
	originalTitle = "Original",
	originalPreview = nil :: string?,
	activeControlId = "skybox_active", -- remembered value: which sky is on

	fadeTime = 0.4, -- seconds for the dim/brighten fade
	dimAmount = 1.5, -- how much darker during the switch
	valuesFolderNames = { "Lighting Values", "Lighting Valus" },
	grassValueNames = { "Grass Color", "GrassColor" },
	-- ONLY Lighting children of these classes are removed when a preset applies.
	-- ("PostEffect" = Bloom, Blur, ColorCorrection, SunRays, DepthOfField.)
	replaceClasses = { "Sky", "Atmosphere", "PostEffect" },
	resetOnResetAll = true, -- "Reset all settings" also goes back to the Original sky
	notifyOnApply = true,
}

-- ═══════════════════════════════════════════════════════════════════════
-- CAMERA (Features → Camera section)
-- ═══════════════════════════════════════════════════════════════════════
Config.camera = {
	-- TODO(walk mode): the final Walk behaviour is not decided yet. Today it
	-- smoothly follows your character and removes camera bobbing while you
	-- walk. Tune it here; the code is isolated in Features → Camera → walkStep().
	walkMode = {
		onlyWhileMoving = true, -- smoothing only while the character walks
		followSmoothing = 8, -- lower = smoother/slower follow, higher = snappier
		resetCameraOffset = true, -- force Humanoid.CameraOffset to 0 (removes head-bob scripts)
		fovWhileWalking = nil :: number?, -- e.g. 75 to widen the view while walking
	},
	distanceRestoreDelay = 0.25, -- seconds before scroll-zoom works again after using the slider
}

-- ═══════════════════════════════════════════════════════════════════════
-- SERVERS (Server script + the Servers page)
-- ═══════════════════════════════════════════════════════════════════════
Config.servers = {
	cacheSeconds = 8, -- re-opening the page within this time reuses the last list
	heartbeatTopic = "BanglaTower_Heartbeat_v5",
	heartbeatInterval = 10, -- seconds between server-to-server updates
	staleTimeout = 45, -- a server that stops updating disappears after this
	maxServers = 50,
	maxUserIdsInHeartbeat = 60, -- payload must stay under ~1 KB
	requestsPerMinute = 30, -- per player
	teleportCooldown = 5, -- seconds between Join presses per player
	friendsCacheSeconds = 600, -- how long the server remembers a player's friend list
	maxFriendAvatars = 3, -- small friend faces per card, then "+N more"

	-- Roblox gives no "server country". Options:
	--   "players" = most common country of the players in that server
	--               (official Roblox API, real data — shown as "Mostly players from …")
	--   "fixed"   = always show regionText below
	--   "hidden"  = no region line
	regionMode = "players",
	regionText = nil :: string?,
	countryNames = {
		BD = "Bangladesh",
		IN = "India",
		PK = "Pakistan",
		NP = "Nepal",
		LK = "Sri Lanka",
		MY = "Malaysia",
		SA = "Saudi Arabia",
		AE = "UAE",
		US = "United States",
		GB = "United Kingdom",
	} :: { [string]: string },
}

-- How long a remote slider waits between sends while dragging (anti-spam).
Config.remoteThrottle = 0.15

-- ═══════════════════════════════════════════════════════════════════════
-- HOME SCREEN — the "General" controls under the category cards
-- (control fields are explained in HowToAddFeatures)
-- ═══════════════════════════════════════════════════════════════════════
Config.home = {
	sectionTitle = "General",
	controls = {
		{
			type = "toggle",
			id = "ui_notifications",
			title = "Pop-up messages",
			desc = "Small messages like \"Skybox applied\". Errors and the slow-game tip still show.",
			default = true,
		},
		{
			type = "button",
			id = "ui_reset_all",
			title = "Reset all settings",
			desc = "Puts every setting back to how it was when you joined.",
			buttonText = "Reset all",
			style = "secondary",
			action = { kind = "internal", name = "resetAll" },
		},
	},
}

-- ═══════════════════════════════════════════════════════════════════════
-- TABS — the five category pages (how to add more: see HowToAddFeatures)
-- ═══════════════════════════════════════════════════════════════════════
Config.tabs = {
	{
		id = "graphics",
		title = "Graphics",
		icon = "◈",
		desc = "Quality, lighting, shadows and fog",
		controls = {
			{
				type = "choice",
				id = "gfx_preset",
				title = "Quality preset",
				style = "cards",
				default = "High",
				options = {
					{ id = "Low", title = "Low", desc = "Lightest · good for phones", descBn = "সবচেয়ে হালকা · ফোনের জন্য ভালো" },
					{ id = "Medium", title = "Medium", desc = "Balanced", descBn = "মাঝামাঝি" },
					{ id = "High", title = "High", desc = "Best looking", descBn = "সবচেয়ে সুন্দর" },
				},
				notify = "%s graphics enabled",
				action = { kind = "bindable", name = P .. "GraphicsPreset" },
			},

			-- Live environment (BTSettings > EnvironmentCycle). OFF = this player
			-- keeps their own sky; the server's timer no longer changes it.
			{ type = "section", title = "Environment" },
			{
				type = "toggle",
				id = "env_live",
				title = "Live environment",
				desc = "Sunrise, day, sunset and night change for everyone over time. Turn off to keep your own sky.",
				descBn = "সময়ের সাথে সবার জন্য সকাল, দিন, সন্ধ্যা, রাত বদলায়। নিজের আকাশ রাখতে বন্ধ করুন।",
				default = true,
				action = { kind = "bindable", name = P .. "EnvLive" },
			},

			{ type = "section", title = "Lighting" },
			{
				type = "toggle",
				id = "gfx_shadows",
				title = "Global shadows",
				desc = "Objects cast shadows. Turn off to save performance.",
				default = true,
				action = { kind = "bindable", name = P .. "Shadows" },
			},
			{
				type = "slider",
				id = "gfx_time",
				title = "Time of day",
				desc = "Move the sun across the sky.",
				min = 0,
				max = 24,
				step = 0.1,
				default = 14,
				format = "%.1f h",
				action = { kind = "bindable", name = P .. "TimeOfDay" },
			},
			{
				type = "slider",
				id = "gfx_brightness",
				title = "Brightness",
				desc = "How strong the overall light is.",
				min = 0,
				max = 5,
				step = 0.1,
				default = 2,
				format = "%.1f",
				action = { kind = "bindable", name = P .. "Brightness" },
			},
			{
				type = "slider",
				id = "gfx_softness",
				title = "Shadow softness",
				desc = "Higher values make shadow edges blurrier.",
				min = 0,
				max = 1,
				step = 0.01,
				default = 0.2,
				format = "%.2f",
				action = { kind = "bindable", name = P .. "ShadowSoftness" },
			},

			{ type = "section", title = "Atmosphere" },
			{
				type = "slider",
				id = "gfx_fogend",
				title = "Fog distance",
				desc = "How far away fog fully hides the world.",
				min = 0,
				max = 15000,
				step = 10,
				default = 10000,
				format = "%d m",
				action = { kind = "bindable", name = P .. "FogEnd" },
			},
			{
				type = "slider",
				id = "gfx_fogstart",
				title = "Fog start",
				desc = "How close to you the fog begins.",
				min = 0,
				max = 5000,
				step = 10,
				default = 0,
				format = "%d m",
				action = { kind = "bindable", name = P .. "FogStart" },
			},

			{ type = "section", title = "Reset" },
			{
				type = "button",
				id = "gfx_reset",
				title = "Reset lighting",
				desc = "Back to the map's (or the active sky's) own lighting. Your quality preset stays.",
				buttonText = "Reset lighting",
				style = "secondary",
				notify = "Lighting restored",
				action = { kind = "bindable", name = P .. "GraphicsReset" },
			},
		},
	},

	{
		id = "skybox",
		title = "Skybox",
		icon = "◆",
		desc = "Change the sky of your world",
		controls = {
			{ type = "custom", id = "skybox_list", builder = "Skybox" },
		},
	},

	{
		id = "servers",
		title = "Servers",
		icon = "◉",
		desc = "Find friends and join other servers",
		controls = {
			{ type = "custom", id = "servers_list", builder = "Servers" },
		},
	},

	{
		id = "player",
		title = "Player",
		icon = "◐",
		desc = "Camera and name tags",
		controls = {
			{ type = "custom", id = "player_you", builder = "You" },

			{ type = "section", title = "Camera" },
			{
				type = "slider",
				id = "cam_fov",
				title = "Field of view",
				desc = "How wide the camera sees.",
				min = 30,
				max = 120,
				step = 1,
				default = 70,
				format = "%d°",
				action = { kind = "bindable", name = P .. "CameraFov" },
			},
			{
				type = "slider",
				id = "cam_distance",
				title = "Camera distance",
				desc = "Zoom the camera in or out.",
				min = 2,
				max = 40,
				step = 0.5,
				default = 12.5,
				format = "%.1f",
				action = { kind = "bindable", name = P .. "CameraDistance" },
			},
			{
				type = "choice",
				id = "cam_mode",
				title = "Camera mode",
				style = "cycle",
				default = "Default",
				options = {
					{ id = "Default", title = "Default", desc = "Normal game camera. Tap to switch." },
					{ id = "Locked", title = "Locked", desc = "Camera is frozen where it is. Tap to switch." },
					{ id = "Walk", title = "Walk", desc = "Smooth follow, no camera bobbing while walking." },
				},
				notify = "Camera: %s",
				action = { kind = "bindable", name = P .. "CameraMode" },
			},

			-- Name-tag toggles appear here by themselves (see Config.billboards).
			{ type = "section", id = "character", title = "Character", hideWhenEmpty = true },
		},
	},

	{
		id = "audio",
		title = "Audio",
		icon = "♪",
		desc = "Game volume and boombox music",
		controls = {
			{ type = "section", title = "Game audio" },
			{
				type = "toggle",
				id = "audio_mute_all",
				title = "Mute all game audio",
				desc = "Silences every game sound on your device.",
				default = false,
				action = { kind = "bindable", name = P .. "MuteAll" },
			},
			{
				type = "slider",
				id = "audio_master",
				title = "Master volume",
				desc = "Volume of every game sound on your device.",
				min = 0,
				max = 100,
				step = 1,
				default = 100,
				format = "%d%%",
				action = { kind = "bindable", name = P .. "MasterVolume" },
			},

			{ type = "section", title = "Boombox" },
			{
				type = "toggle",
				id = "audio_mute_boombox",
				title = "Mute boombox",
				desc = "Silences other players' boomboxes for you only. Your own boombox keeps playing.",
				default = false,
				action = { kind = "bindable", name = P .. "MuteBoombox" },
			},
			{
				type = "slider",
				id = "audio_boombox",
				title = "Boombox volume",
				desc = "Volume of other players' boomboxes. Only changes what you hear.",
				min = 0,
				max = 100,
				step = 1,
				default = 100,
				format = "%d%%",
				action = { kind = "bindable", name = P .. "BoomboxVolume" },
			},
		},
	},
}

return Config
