--!nonstrict
--[[
	══════════════════════════════════════════════════════════════════════════
	BT SETTINGS — LIVE ENVIRONMENT · CLIENT
	Script (RunContext = Client) · ReplicatedStorage > BTSettings > EnvironmentCycle

	Runs on every player's device. When the Server publishes a new environment
	it smoothly applies that preset folder from "All Lighting" (same rules as
	the Skybox tab: Config.skybox) and shows the small "Environment changed"
	card. Respects the player's "Live environment" toggle, the quality preset
	and the "Pop-up messages" toggle.

	Nothing to edit here — everything is in Settings.
	══════════════════════════════════════════════════════════════════════════
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local cycleFolder = script.Parent
local root = cycleFolder.Parent
local Config = require(root:WaitForChild("Config"))
local Settings = require(cycleFolder:WaitForChild("Settings"))

local TAG = "[BTSettings] Environment:"

if not Settings.enabled then
	return
end

local lightingFolder = root:WaitForChild(Config.names.lightingFolder, 15)
if not lightingFolder then
	warn(TAG, "folder '" .. Config.names.lightingFolder .. "' not found in", root:GetFullName())
	return
end

local skyCfg = Config.skybox or {}
local noticeCfg = Settings.notice or {}
local transitionCfg = Settings.transition or {}
local playerCfg = Settings.player or {}

local OWN_ATTR = "BTEnvironment" -- marks instances this script created
local FADE_ATTR = "BTEnvironmentFade" -- the temporary dim effect

-- ─────────────────────────────────────────────────────────────────────────
-- [1] Link to the BTSettings panel (optional — works without it too)
-- ─────────────────────────────────────────────────────────────────────────
local remotes = root:WaitForChild(Config.names.remotesFolder, 15)
if remotes then
	-- give the panel time to start, so its "Original" sky snapshot is the map's own
	remotes:WaitForChild(Config.names.getValue, 10)
end

-- Reads a remembered panel value. Never blocks for more than ~1 second.
local function getValue(id: string?): any
	local fn = id and remotes and remotes:FindFirstChild(Config.names.getValue)
	if not fn or not fn:IsA("BindableFunction") then
		return nil
	end
	local done, result = false, nil
	task.spawn(function()
		local ok, value = pcall(fn.Invoke, fn, id)
		if ok then
			result = value
		end
		done = true
	end)
	local started = os.clock()
	while not done and os.clock() - started < 1 do
		task.wait()
	end
	return result
end

local function currentQuality(): { [string]: any }?
	local graphics = Config.graphics
	if not graphics or not playerCfg.respectQualityPreset then
		return nil
	end
	local id = getValue(graphics.presetControlId)
	return id and graphics.presets and graphics.presets[id] or nil
end

-- ─────────────────────────────────────────────────────────────────────────
-- [2] Schedule helpers
-- ─────────────────────────────────────────────────────────────────────────
local function lineFor(index: number?, preset: string): { [string]: any }
	local schedule = Settings.loop or {}
	local line = index and schedule[index]
	if type(line) == "table" and type(line.preset) == "string" and string.lower(line.preset) == string.lower(preset) then
		return line
	end
	for _, l in schedule do
		if type(l) == "table" and l.preset == preset then
			return l
		end
	end
	return { preset = preset }
end

local ICONS = {
	{ "night", "🌙" },
	{ "twilight", "🌆" },
	{ "sunrise", "🌅" },
	{ "morning", "🌄" },
	{ "sunset", "🌇" },
	{ "afternoon", "🌤️" },
	{ "golden", "✨" },
	{ "cloud", "☁️" },
	{ "pink", "🌸" },
	{ "day", "☀️" },
}
local function iconFor(line: { [string]: any }, preset: string): string
	if type(line.icon) == "string" and line.icon ~= "" then
		return line.icon
	end
	local lower = string.lower(preset)
	for _, pair in ICONS do
		if string.find(lower, pair[1], 1, true) then
			return pair[2]
		end
	end
	return "✦"
end

local function fmtDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	local h = seconds // 3600
	local m = (seconds % 3600) // 60
	if h > 0 then
		return m > 0 and ("%dh %dm"):format(h, m) or ("%dh"):format(h)
	elseif m > 0 then
		return ("%dm"):format(m)
	end
	return ("%ds"):format(seconds)
end

-- ─────────────────────────────────────────────────────────────────────────
-- [3] Applying a preset (smooth blend)
-- ─────────────────────────────────────────────────────────────────────────
local terrain = Workspace.Terrain
local originalGrass = terrain:GetMaterialColor(Enum.Material.Grass)

local replaceClasses = skyCfg.replaceClasses or { "Sky", "Atmosphere", "PostEffect" }
local valuesFolderNames = skyCfg.valuesFolderNames or { "Lighting Values", "Lighting Valus" }
local grassValueNames = skyCfg.grassValueNames or { "Grass Color", "GrassColor" }

-- What can blend smoothly, per class.
local TWEEN_PROPS = {
	Atmosphere = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" },
	BloomEffect = { "Intensity", "Size", "Threshold" },
	BlurEffect = { "Size" },
	ColorCorrectionEffect = { "Brightness", "Contrast", "Saturation", "TintColor" },
	DepthOfFieldEffect = { "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity" },
	SunRaysEffect = { "Intensity", "Spread" },
}
-- "Invisible" values: new effects fade in from here, removed ones fade out to here.
local NEUTRAL = {
	Atmosphere = { Density = 0, Offset = 0, Glare = 0, Haze = 0 },
	BloomEffect = { Intensity = 0 },
	BlurEffect = { Size = 0 },
	ColorCorrectionEffect = { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1) },
	DepthOfFieldEffect = { FarIntensity = 0, NearIntensity = 0 },
	SunRaysEffect = { Intensity = 0 },
}

local function isReplaceable(inst: Instance): boolean
	if inst:GetAttribute(FADE_ATTR) then
		return false
	end
	for _, className in replaceClasses do
		if inst:IsA(className) then
			return true
		end
	end
	return false
end

-- The map's own Sky / Atmosphere / effects are parked (not destroyed) when a
-- preset replaces them, so anything that still points at them keeps working.
local mapOriginals: { [Instance]: boolean } = {}
for _, child in Lighting:GetChildren() do
	if isReplaceable(child) then
		mapOriginals[child] = true
	end
end
local parking: Folder? = nil

local function retire(inst: Instance)
	if mapOriginals[inst] then
		if not parking or not parking.Parent then
			parking = Instance.new("Folder")
			parking.Name = "MapOriginalLighting (this device)"
			parking.Parent = cycleFolder
		end
		inst.Parent = parking
	else
		inst:Destroy()
	end
end

-- Two Sky objects look the same when all their pictures are the same.
local SKY_PROPS = { "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SunTextureId", "MoonTextureId" }
local function skyKey(sky: Instance): string
	local parts = {}
	for _, prop in SKY_PROPS do
		local ok, value = pcall(function()
			return tostring((sky :: any)[prop])
		end)
		table.insert(parts, ok and value or "")
	end
	return table.concat(parts, "|")
end

local function findValuesFolder(folder: Instance): Instance?
	for _, name in valuesFolderNames do
		local found = folder:FindFirstChild(name)
		if found then
			return found
		end
	end
	return nil
end

local running: { Tween } = {}
local applyToken = 0

local function play(tween: Tween): Tween
	table.insert(running, tween)
	tween:Play()
	return tween
end

local function stopRunning()
	local list = running
	running = {}
	for _, tween in list do
		tween:Cancel()
	end
end

local function setProps(inst: Instance, props: { [string]: any })
	for name, value in props do
		pcall(function()
			(inst :: any)[name] = value
		end)
	end
end

local function applyPreset(presetName: string, line: { [string]: any }, instant: boolean)
	local folder = lightingFolder:FindFirstChild(presetName)
	if not folder then
		warn(TAG, "preset '" .. presetName .. "' not found in", lightingFolder:GetFullName())
		return
	end

	-- read the panel values first (may take a moment), then change everything at once
	local quality = currentQuality()
	local postEffectsOn = not (quality and quality.postEffects == false)
	local fogAmount = quality and tonumber(quality.fogAmount) or 1

	applyToken += 1
	local token = applyToken
	stopRunning()

	local duration = instant and 0 or tonumber(line.transitionTime) or tonumber(transitionCfg.time) or 6
	local smooth = duration > 0.05
	local info = TweenInfo.new(math.max(duration, 0.05), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	-- what the preset has (first object of each class)
	local templates: { Instance } = {}
	local seen = {}
	for _, child in folder:GetChildren() do
		if isReplaceable(child) and not seen[child.ClassName] then
			seen[child.ClassName] = true
			table.insert(templates, child)
		end
	end

	-- what Lighting has now
	local old: { [string]: { Instance } } = {}
	for _, child in Lighting:GetChildren() do
		if isReplaceable(child) then
			old[child.ClassName] = old[child.ClassName] or {}
			table.insert(old[child.ClassName], child)
		end
	end

	-- ── atmosphere + post effects: fresh copy that blends from the old look ──
	local skyTemplate: Instance? = nil
	for _, template in templates do
		if template:IsA("Sky") then
			skyTemplate = template
			continue
		end
		local props = TWEEN_PROPS[template.ClassName]
		local goal = {}
		if props then
			for _, prop in props do
				goal[prop] = (template :: any)[prop]
			end
		end
		if template:IsA("Atmosphere") and fogAmount ~= 1 then
			goal.Density = (template :: any).Density * fogAmount
		end

		local clone = template:Clone()
		clone:SetAttribute(OWN_ATTR, true)
		if clone:IsA("PostEffect") and not postEffectsOn then
			clone.Enabled = false
		end

		local previous = old[template.ClassName] and table.remove(old[template.ClassName], 1)
		if smooth and props then
			local previousVisible = previous and not (previous:IsA("PostEffect") and not (previous :: any).Enabled)
			if previousVisible then
				for _, prop in props do
					pcall(function()
						(clone :: any)[prop] = (previous :: any)[prop]
					end)
				end
			else
				setProps(clone, NEUTRAL[template.ClassName] or {})
			end
			clone.Parent = Lighting
			if previous then
				retire(previous)
			end
			play(TweenService:Create(clone, info, goal))
		else
			setProps(clone, goal)
			clone.Parent = Lighting
			if previous then
				retire(previous)
			end
		end
	end

	-- ── leftovers the new preset does not have: fade out, then remove ──
	local oldSkies = old.Sky or {}
	old.Sky = nil
	for className, list in old do
		for _, inst in list do
			local neutral = NEUTRAL[className]
			if smooth and neutral then
				-- fade a copy, so a parked map original keeps its own values
				local ghost = inst
				if mapOriginals[inst] then
					ghost = inst:Clone()
					ghost:SetAttribute(OWN_ATTR, true)
					ghost.Parent = Lighting
					retire(inst)
				end
				local tween = play(TweenService:Create(ghost, info, neutral))
				tween.Completed:Once(function()
					ghost:Destroy()
				end)
			else
				retire(inst)
			end
		end
	end

	-- ── sky: a picture cannot blend, so swap it during a short soft dim ──
	local function swapSky()
		for _, sky in oldSkies do
			retire(sky)
		end
		if skyTemplate then
			local sky = skyTemplate:Clone()
			sky:SetAttribute(OWN_ATTR, true)
			sky.Parent = Lighting
		end
	end

	local skyFade = tonumber(transitionCfg.skyFade) or 0
	local skyDim = tonumber(transitionCfg.skyDim) or 0
	local sameSky = skyTemplate ~= nil and #oldSkies == 1 and skyKey(oldSkies[1]) == skyKey(skyTemplate)
	if smooth and skyFade > 0 and skyDim > 0 and not sameSky and (skyTemplate or #oldSkies > 0) then
		local dim = Instance.new("ColorCorrectionEffect")
		dim.Name = "BTSettingsEnvironmentFade"
		dim:SetAttribute(FADE_ATTR, true)
		dim.Parent = Lighting
		local half = skyFade / 2
		TweenService:Create(dim, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Brightness = -skyDim,
		}):Play()
		task.delay(half, function()
			if token == applyToken then
				swapSky()
			end
			local back = TweenService:Create(dim, TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Brightness = 0,
			})
			back.Completed:Once(function()
				dim:Destroy()
			end)
			back:Play()
		end)
	else
		swapSky()
	end

	-- ── Lighting properties from the "Lighting Valus" folder ──
	local lightGoal = {}
	local clockTarget: number? = nil
	local grassTarget: Color3? = nil
	local values = findValuesFolder(folder)
	if values then
		for _, v in values:GetChildren() do
			if not v:IsA("ValueBase") then
				continue
			end
			local name, value = v.Name, (v :: any).Value
			if table.find(grassValueNames, name) then
				if typeof(value) == "Color3" then
					grassTarget = value
				end
			elseif name == "ClockTime" then
				if type(value) == "number" then
					clockTarget = value
				end
			elseif type(value) == "number" or typeof(value) == "Color3" then
				local ok, current = pcall(function()
					return (Lighting :: any)[name]
				end)
				if ok and typeof(current) == typeof(value) then
					lightGoal[name] = value
				end
			end
		end
	end
	if type(line.clockTime) == "number" then
		clockTarget = line.clockTime
	end

	if smooth then
		play(TweenService:Create(Lighting, info, lightGoal))
	else
		setProps(Lighting, lightGoal)
	end

	-- clock: blends the short way (or forward), wrapping past midnight
	if clockTarget then
		local from = Lighting.ClockTime
		local diff = (clockTarget % 24) - from
		if transitionCfg.clockDirection == "forward" then
			if diff < 0 then
				diff += 24
			end
		elseif diff > 12 then
			diff -= 24
		elseif diff < -12 then
			diff += 24
		end
		if smooth and math.abs(diff) > 0.001 then
			local alpha = Instance.new("NumberValue")
			alpha.Changed:Connect(function(a)
				Lighting.ClockTime = (from + diff * a) % 24
			end)
			local tween = play(TweenService:Create(alpha, info, { Value = 1 }))
			tween.Completed:Once(function()
				alpha:Destroy()
			end)
		else
			Lighting.ClockTime = clockTarget % 24
		end
	end

	-- ── grass color ──
	if Settings.applyGrassColor then
		local target = grassTarget or originalGrass
		local from = terrain:GetMaterialColor(Enum.Material.Grass)
		if from ~= target then
			if smooth then
				task.spawn(function()
					local started = os.clock()
					while token == applyToken do
						local a = math.min((os.clock() - started) / duration, 1)
						local eased = TweenService:GetValue(a, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
						terrain:SetMaterialColor(Enum.Material.Grass, from:Lerp(target, eased))
						if a >= 1 then
							break
						end
						task.wait(1 / 20)
					end
				end)
			else
				terrain:SetMaterialColor(Enum.Material.Grass, target)
			end
		end
	end

	-- ── clouds, from the "Clouds = { ... }" part of the preset's ModuleScript ──
	if Settings.applyClouds then
		local clouds = terrain:FindFirstChildOfClass("Clouds")
		local module = folder:FindFirstChildWhichIsA("ModuleScript")
		if clouds and module then
			local ok, data = pcall(require, module)
			local c = ok and type(data) == "table" and data.Clouds
			if type(c) == "table" then
				local goal = {}
				if type(c.Cover) == "number" then
					goal.Cover = math.clamp(c.Cover, 0, 1)
				end
				if type(c.Density) == "number" then
					goal.Density = math.clamp(c.Density, 0, 1)
				end
				if typeof(c.Color) == "Color3" then
					goal.Color = c.Color
				end
				if smooth then
					play(TweenService:Create(clouds, info, goal))
				else
					setProps(clouds, goal)
				end
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────
-- [4] The small notice card
-- ─────────────────────────────────────────────────────────────────────────
local themes = Config.theme and Config.theme.presets or {}
local theme = themes[Config.theme and Config.theme.active] or themes.Dark or {}
local function color(key: string, fallback: Color3): Color3
	local c = theme[key]
	return typeof(c) == "Color3" and c or fallback
end

local fontFamily = Config.fonts and Config.fonts.family or "rbxasset://fonts/families/GothamSSm.json"

local noticeGui: ScreenGui? = nil
local currentCard: Instance? = nil

local function getGui(): ScreenGui
	if noticeGui and noticeGui.Parent then
		return noticeGui
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "BTSettingsEnvironmentNotice"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 60
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	noticeGui = gui
	return gui
end

local function make(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for name, value in props do
		(inst :: any)[name] = value
	end
	inst.Parent = parent
	return inst
end

local function textLabel(parent: Instance, text: string, size: number, textColor: Color3, weight: Enum.FontWeight, order: number)
	local label = make("TextLabel", {
		Name = "Text" .. order,
		BackgroundTransparency = 1,
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.new(),
		FontFace = Font.new(fontFamily, weight),
		Text = text,
		TextSize = size,
		TextColor3 = textColor,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		LayoutOrder = order,
	}, parent)
	make("UISizeConstraint", { MaxSize = Vector2.new(300, math.huge) }, label)
	return label
end

local function isPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

type Toast = { icon: string, header: string, title: string, lines: { string }, color: Color3? }

local function showToast(data: Toast)
	local gui = getGui()
	if currentCard then
		currentCard:Destroy()
		currentCard = nil
	end

	local top = noticeCfg.position ~= "Bottom"
	local offsetY = tonumber(noticeCfg.offsetY) or 10
	local restY = top and offsetY or -offsetY
	local hiddenY = top and restY - 14 or restY + 14
	local background = color("background", Color3.fromRGB(14, 14, 14))
	local accent = data.color or color("accent", Color3.new(1, 1, 1))

	local card = make("CanvasGroup", {
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, top and 0 or 1),
		Position = UDim2.new(0.5, 0, top and 0 or 1, hiddenY),
		Size = UDim2.new(),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		GroupTransparency = 1,
	})
	make("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 2),
		PaddingLeft = UDim.new(0, 2),
		PaddingRight = UDim.new(0, 2),
	}, card)
	local ui = Config.ui or {}
	make("UIScale", {
		Scale = isPhone() and (tonumber(noticeCfg.mobileScale) or 0.9) * (ui.mobileScale or 1) or (ui.desktopScale or 1),
	}, card)

	local body = make("Frame", {
		Name = "Body",
		Size = UDim2.new(),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = background,
		BackgroundTransparency = tonumber(noticeCfg.transparency) or 0.12,
	}, card)
	make("UICorner", { CornerRadius = UDim.new(0, 14) }, body)
	make("UIStroke", {
		Color = color("strokeStrong", Color3.fromRGB(105, 105, 105)),
		Transparency = 0.55,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, body)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 9),
		PaddingBottom = UDim.new(0, 9),
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 16),
	}, body)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
	}, body)

	local iconHolder = make("Frame", {
		Name = "Icon",
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.78,
		LayoutOrder = 1,
	}, body)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, iconHolder)
	make("UIStroke", { Color = accent, Transparency = 0.4, Thickness = 1 }, iconHolder)
	local iconScale = make("UIScale", { Scale = 0.5 }, iconHolder)
	make("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = data.icon,
		TextSize = 18,
		TextColor3 = Color3.new(1, 1, 1),
		FontFace = Font.new(fontFamily),
	}, iconHolder)

	local column = make("Frame", {
		Name = "Texts",
		BackgroundTransparency = 1,
		Size = UDim2.new(),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 2,
	}, body)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 1),
	}, column)
	if data.header ~= "" then
		textLabel(column, data.header, 11, color("textDim", Color3.fromRGB(128, 128, 128)), Enum.FontWeight.Medium, 1)
	end
	textLabel(column, data.title, 16, color("text", Color3.fromRGB(245, 245, 245)), Enum.FontWeight.Bold, 2)
	for i, line in data.lines do
		textLabel(column, line, 11, color("textMuted", Color3.fromRGB(175, 175, 175)), Enum.FontWeight.Regular, 2 + i)
	end

	if type(noticeCfg.soundId) == "string" and noticeCfg.soundId ~= "" then
		local sound = make("Sound", { SoundId = noticeCfg.soundId, Volume = tonumber(noticeCfg.soundVolume) or 0.5 }, card)
		sound:Play()
	end

	card.Parent = gui
	currentCard = card

	-- in: slide + fade, icon pops
	TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
		Position = UDim2.new(0.5, 0, top and 0 or 1, restY),
	}):Play()
	TweenService:Create(iconScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()

	-- a soft light sweep across the card (UIGradient multiplies the
	-- background color, so the color lives in the gradient for a moment)
	if noticeCfg.shine ~= false then
		local glow = background:Lerp(accent, 0.35)
		body.BackgroundColor3 = Color3.new(1, 1, 1)
		local gradient = make("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, background),
				ColorSequenceKeypoint.new(0.5, glow),
				ColorSequenceKeypoint.new(1, background),
			}),
			Rotation = 20,
			Offset = Vector2.new(-1, 0),
		}, body)
		local sweep = TweenService:Create(gradient, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Offset = Vector2.new(1, 0),
		})
		sweep.Completed:Once(function()
			if body.Parent then
				gradient:Destroy()
				body.BackgroundColor3 = background
			end
		end)
		task.delay(0.15, function()
			sweep:Play()
		end)
	end

	-- out
	task.delay(tonumber(noticeCfg.duration) or 4.5, function()
		if currentCard ~= card then
			return
		end
		local out = TweenService:Create(card, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			GroupTransparency = 1,
			Position = UDim2.new(0.5, 0, top and 0 or 1, hiddenY),
		})
		out.Completed:Once(function()
			if currentCard == card then
				currentCard = nil
			end
			card:Destroy()
		end)
		out:Play()
	end)
end

local function showChangeNotice(preset: string, line: { [string]: any })
	if noticeCfg.enabled == false then
		return
	end
	if noticeCfg.respectPopupToggle and Config.notifications then
		if getValue(Config.notifications.controlId) == false then
			return
		end
	end

	local title = type(line.title) == "string" and line.title or preset
	local icon = iconFor(line, preset)
	local lines = {}
	if type(line.message) == "string" and line.message ~= "" then
		table.insert(lines, line.message)
	end
	if noticeCfg.showNext then
		local nextPreset = cycleFolder:GetAttribute("NextPreset")
		local endsAt = cycleFolder:GetAttribute("EndsAt")
		if type(nextPreset) == "string" and type(endsAt) == "number" then
			local nextLine = lineFor(cycleFolder:GetAttribute("NextIndex"), nextPreset)
			local left = endsAt - Workspace:GetServerTimeNow()
			if left > 1 then
				local nextTitle = type(nextLine.title) == "string" and nextLine.title or nextPreset
				table.insert(lines, (noticeCfg.nextFormat or "Next: %s in %s"):format(nextTitle, fmtDuration(left)))
			end
		end
	end

	if noticeCfg.style == "panel" then
		local notify = remotes and remotes:FindFirstChild(Config.names.notify)
		if notify and notify:IsA("BindableEvent") then
			notify:Fire({
				title = title,
				message = #lines > 0 and table.concat(lines, " · ") or (noticeCfg.header or "Environment changed"),
				icon = icon,
			})
			return
		end
	end

	showToast({
		icon = icon,
		header = noticeCfg.header or "ENVIRONMENT CHANGED",
		title = title,
		lines = lines,
		color = typeof(line.color) == "Color3" and line.color or nil,
	})
end

-- ─────────────────────────────────────────────────────────────────────────
-- [5] Following the server
-- ─────────────────────────────────────────────────────────────────────────
local liveEnabled = true
local appliedPreset: string? = nil

do
	local saved = getValue(playerCfg.controlId)
	if type(saved) == "boolean" then
		liveEnabled = saved
	end
end

local function currentPreset(): (string?, { [string]: any }?)
	local preset = cycleFolder:GetAttribute("Preset")
	if type(preset) ~= "string" then
		return nil, nil
	end
	return preset, lineFor(cycleFolder:GetAttribute("Index"), preset)
end

local function applyCurrent(instant: boolean, withNotice: boolean)
	local preset, line = currentPreset()
	if not preset or not line or not liveEnabled then
		return
	end
	local changed = preset ~= appliedPreset
	appliedPreset = preset
	applyPreset(preset, line, instant)
	if changed and withNotice then
		showChangeNotice(preset, line)
	end
end

local function onServerChange()
	local preset = currentPreset()
	if preset and preset ~= appliedPreset then
		applyCurrent(false, true)
	end
end

-- "Live environment" toggle in Settings › Graphics
task.spawn(function()
	local event = remotes and playerCfg.eventName and remotes:WaitForChild(playerCfg.eventName, 30)
	if not event or not event:IsA("BindableEvent") then
		return
	end
	event.Event:Connect(function(value)
		local on = value ~= false
		if on == liveEnabled then
			return
		end
		liveEnabled = on
		if on then
			appliedPreset = nil
			applyCurrent(false, false)
		end
	end)
end)

-- "Reset lighting" puts the map's lighting back; bring the live one back on top
task.spawn(function()
	local resetName = Config.PREFIX .. "GraphicsReset"
	local event = remotes and playerCfg.reapplyAfterLightingReset and remotes:WaitForChild(resetName, 30)
	if not event or not event:IsA("BindableEvent") then
		return
	end
	event.Event:Connect(function()
		if not liveEnabled then
			return
		end
		local activeSky = getValue(skyCfg.activeControlId)
		if activeSky ~= nil and activeSky ~= skyCfg.originalId then
			return -- the player picked their own sky: leave it
		end
		task.delay((tonumber(skyCfg.fadeTime) or 0.4) * 2 + 0.3, function()
			if liveEnabled then
				applyCurrent(false, false)
			end
		end)
	end)
end)

-- Admin command replies (server → this player only)
task.spawn(function()
	local reply = cycleFolder:WaitForChild("AdminReply", 30)
	if not reply or not reply:IsA("RemoteEvent") then
		return
	end
	reply.OnClientEvent:Connect(function(text)
		if type(text) ~= "string" then
			return
		end
		showToast({ icon = "🛠️", header = "ENVIRONMENT · ADMIN", title = string.sub(text, 1, 300), lines = {} })
	end)
end)

-- Wait for the server's first answer, then apply once and follow every change.
if cycleFolder:GetAttribute("ChangeId") == nil then
	cycleFolder:GetAttributeChangedSignal("ChangeId"):Wait()
end
cycleFolder:GetAttributeChangedSignal("ChangeId"):Connect(onServerChange)
applyCurrent(transitionCfg.instantOnJoin ~= false, noticeCfg.showOnJoin == true)
