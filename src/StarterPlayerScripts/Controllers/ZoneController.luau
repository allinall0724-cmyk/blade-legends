--!strict
-- ZoneController: handles the portal travel experience on the client —
-- fade-to-black over the teleport, a 2-second zone-name label, a whoosh sound,
-- and per-zone fog (purple fog inside the Weapon Hall, cleared elsewhere).

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local SoundController = require(script.Parent.SoundController)

local ZoneController = {}

local DEFAULT_FOG_END = 100000

local function applyZoneFog(zone: string)
	if zone == "Weapon Hall" then
		Lighting.FogStart = 20
		Lighting.FogEnd = 130
		Lighting.FogColor = Color3.fromRGB(70, 40, 110)
	else
		Lighting.FogStart = 0
		Lighting.FogEnd = DEFAULT_FOG_END
		Lighting.FogColor = Color3.fromRGB(192, 192, 192)
	end
end

function ZoneController.init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "BL_Overlay"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.Parent = player:WaitForChild("PlayerGui")

	local black = Instance.new("Frame")
	black.Name = "Fade"
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.BorderSizePixel = 0
	black.ZIndex = 10
	black.Parent = gui

	local label = Instance.new("TextLabel")
	label.Name = "ZoneLabel"
	label.Size = UDim2.new(1, 0, 0, 80)
	label.Position = UDim2.new(0, 0, 0.36, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 230, 160)
	label.TextStrokeTransparency = 0.3
	label.TextTransparency = 1
	label.ZIndex = 11
	label.Text = ""
	label.Parent = gui
	-- keep the label from being huge
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 64
	constraint.Parent = label

	-- expose a generic fade for other systems (loading screen reuse)
	ZoneController.fadeFrame = black

	Net.event("ZoneEnter").OnClientEvent:Connect(function(data)
		local zone = (typeof(data) == "table" and data.zone) or "?"
		SoundController.play("portal")

		-- fade to black over the teleport
		TweenService:Create(black, TweenInfo.new(0.2), { BackgroundTransparency = 0 }):Play()
		task.wait(0.25)
		-- mid-black: apply fog + show the zone label
		applyZoneFog(zone)
		label.Text = zone
		TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		-- fade back in
		TweenService:Create(black, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		task.delay(2, function()
			TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		end)
	end)

	-- start with clear fog
	applyZoneFog("")
end

return ZoneController
