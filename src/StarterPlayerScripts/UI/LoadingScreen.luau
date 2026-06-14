--!strict
-- LoadingScreen: a black screen with the "BLADE LEGENDS" logo that fades in then
-- out over ~3 seconds when the game first starts.

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local LoadingScreen = {}

function LoadingScreen.show()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "BL_Loading"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 200
	gui.Parent = player:WaitForChild("PlayerGui")

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.new(0, 0, 0)
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local logo = Instance.new("TextLabel")
	logo.Size = UDim2.new(0.8, 0, 0, 90)
	logo.Position = UDim2.new(0.1, 0, 0.4, 0)
	logo.BackgroundTransparency = 1
	logo.Font = Enum.Font.GothamBlack
	logo.TextScaled = true
	logo.TextColor3 = Color3.fromRGB(255, 215, 80)
	logo.TextStrokeColor3 = Color3.fromRGB(120, 60, 0)
	logo.TextStrokeTransparency = 0.4
	logo.TextTransparency = 1
	logo.Text = "⚔ BLADE LEGENDS ⚔"
	logo.Parent = bg

	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.new(0.8, 0, 0, 30)
	sub.Position = UDim2.new(0.1, 0, 0.54, 0)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.Gotham
	sub.TextScaled = true
	sub.TextColor3 = Color3.fromRGB(200, 200, 210)
	sub.TextTransparency = 1
	sub.Text = "collect • fight • trade • climb"
	sub.Parent = bg
	local cons = Instance.new("UITextSizeConstraint")
	cons.MaxTextSize = 22
	cons.Parent = sub

	task.spawn(function()
		TweenService:Create(logo, TweenInfo.new(1), { TextTransparency = 0, TextStrokeTransparency = 0.2 }):Play()
		TweenService:Create(sub, TweenInfo.new(1.2), { TextTransparency = 0.1 }):Play()
		task.wait(1.6)
		TweenService:Create(logo, TweenInfo.new(1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(sub, TweenInfo.new(1), { TextTransparency = 1 }):Play()
		TweenService:Create(bg, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
		task.wait(1.3)
		gui:Destroy()
	end)
end

return LoadingScreen
