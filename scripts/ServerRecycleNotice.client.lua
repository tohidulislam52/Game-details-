--!strict
--[[
	ServerRecycleNotice
	রাখবেন: StarterPlayer > StarterPlayerScripts > ServerRecycleNotice (LocalScript)

	ServerRecycler-এর ছোট নোটিফিকেশন: স্ক্রিনের উপরে মাঝখানে কয়েক সেকেন্ডের জন্য দেখায়।
	বন্ধ করতে: ServerRecycler-এ CONFIG.SHOW_NOTICE = false করুন (অথবা এই স্ক্রিপ্ট মুছে দিন)।
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local SHOW_SECONDS = 8
local ICON = "🔄"

local player = Players.LocalPlayer

local HIDDEN = UDim2.new(0.5, 0, 0, -160)
local SHOWN = UDim2.new(0.5, 0, 0, 8)
local TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local gui = Instance.new("ScreenGui")
gui.Name = "ServerRecycleNotice"
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.Parent = player:WaitForChild("PlayerGui")

local card = Instance.new("Frame")
card.Name = "Card"
card.AnchorPoint = Vector2.new(0.5, 0)
card.Position = HIDDEN
card.Size = UDim2.new(0.92, 0, 0, 0)
card.AutomaticSize = Enum.AutomaticSize.Y
card.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
card.BackgroundTransparency = 0.12
card.Visible = false
card.Parent = gui

local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(420, math.huge)
sizeLimit.Parent = card

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = card

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 255, 255)
stroke.Transparency = 0.85
stroke.Thickness = 1
stroke.Parent = card

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 9)
padding.PaddingBottom = UDim.new(0, 9)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 36)
padding.Parent = card

local icon = Instance.new("TextLabel")
icon.Name = "Icon"
icon.BackgroundTransparency = 1
icon.Size = UDim2.fromOffset(20, 20)
icon.Font = Enum.Font.GothamMedium
icon.TextSize = 16
icon.Text = ICON
icon.Parent = card

local message = Instance.new("TextLabel")
message.Name = "Message"
message.BackgroundTransparency = 1
message.Position = UDim2.fromOffset(28, 1)
message.Size = UDim2.new(1, -28, 0, 0)
message.AutomaticSize = Enum.AutomaticSize.Y
message.Font = Enum.Font.GothamMedium
message.TextSize = 14
message.TextColor3 = Color3.fromRGB(236, 238, 242)
message.TextXAlignment = Enum.TextXAlignment.Left
message.TextWrapped = true
message.Text = ""
message.Parent = card

local close = Instance.new("TextButton")
close.Name = "Close"
close.BackgroundTransparency = 1
close.AnchorPoint = Vector2.new(0, 0.5)
close.Position = UDim2.new(1, 6, 0.5, 0)
close.Size = UDim2.fromOffset(26, 26)
close.Font = Enum.Font.GothamMedium
close.TextSize = 20
close.TextColor3 = Color3.fromRGB(160, 165, 175)
close.Text = "×"
close.Parent = card

local shown = false
local serial = 0

local function hide(id: number)
	if id ~= serial or not shown then
		return
	end
	shown = false
	local tween = TweenService:Create(card, TWEEN, { Position = HIDDEN })
	tween:Play()
	tween.Completed:Wait()
	if id == serial and not shown then
		card.Visible = false
	end
end

local function show(text: string)
	serial += 1
	local id = serial
	message.Text = text
	card.Visible = true
	if not shown then
		shown = true
		card.Position = HIDDEN
		TweenService:Create(card, TWEEN, { Position = SHOWN }):Play()
	end
	task.delay(SHOW_SECONDS, hide, id)
end

close.Activated:Connect(function()
	hide(serial)
end)

local function onNotice()
	local text = workspace:GetAttribute("ServerRecycleNotice")
	if type(text) == "string" and text ~= "" then
		show(text)
	end
end

local function onMoving()
	local text = player:GetAttribute("ServerRecycleMoving")
	if type(text) == "string" and text ~= "" then
		show(text)
	end
end

workspace:GetAttributeChangedSignal("ServerRecycleNotice"):Connect(onNotice)
player:GetAttributeChangedSignal("ServerRecycleMoving"):Connect(onMoving)
onNotice()
onMoving()
