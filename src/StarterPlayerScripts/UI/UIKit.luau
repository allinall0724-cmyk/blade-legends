--!strict
-- UIKit: tiny declarative helper for building GUIs in code, plus a few shared
-- widgets (buttons, panels, rarity coloring) used across every screen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RarityConfig = require(ReplicatedStorage.Shared.RarityConfig)

local UIKit = {}

-- create(class, props, children) -> Instance
function UIKit.create(className: string, props: { [string]: any }?, children: { Instance }?): Instance
	local inst = Instance.new(className)
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

UIKit.Colors = {
	bg = Color3.fromRGB(22, 24, 32),
	panel = Color3.fromRGB(32, 35, 48),
	panelLight = Color3.fromRGB(45, 48, 64),
	accent = Color3.fromRGB(255, 200, 60),
	text = Color3.fromRGB(235, 238, 245),
	subtext = Color3.fromRGB(170, 175, 190),
	good = Color3.fromRGB(90, 220, 120),
	bad = Color3.fromRGB(225, 90, 90),
}

function UIKit.corner(radius: number?): UICorner
	return UIKit.create("UICorner", { CornerRadius = UDim.new(0, radius or 8) }) :: UICorner
end

function UIKit.pad(px: number): UIPadding
	local p = UDim.new(0, px)
	return UIKit.create("UIPadding", { PaddingLeft = p, PaddingRight = p, PaddingTop = p, PaddingBottom = p }) :: UIPadding
end

function UIKit.rarityColor(rarity: string): Color3
	return RarityConfig.getColor(rarity)
end

-- A styled text button. onClick is connected if provided.
function UIKit.button(text: string, size: UDim2, position: UDim2, color: Color3?, onClick: (() -> ())?): TextButton
	local btn = UIKit.create("TextButton", {
		Text = text,
		Size = size,
		Position = position,
		BackgroundColor3 = color or UIKit.Colors.panelLight,
		TextColor3 = UIKit.Colors.text,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		BorderSizePixel = 0,
		AutoButtonColor = true,
	}, { UIKit.corner(8), UIKit.pad(6) }) :: TextButton
	if onClick then
		btn.Activated:Connect(onClick)
	end
	return btn
end

-- A draggable-free modal panel with a title bar and close button.
-- Returns (panel, body) where body is where you add content.
function UIKit.panel(title: string, size: UDim2, onClose: (() -> ())?): (Frame, Frame)
	local panel = UIKit.create("Frame", {
		Name = "Panel",
		Size = size,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = UIKit.Colors.bg,
		BorderSizePixel = 0,
		Visible = false,
	}, {
		UIKit.corner(14),
	}) :: Frame

	local stroke = UIKit.create("UIStroke", { Color = UIKit.Colors.accent, Thickness = 2, Transparency = 0.4 })
	stroke.Parent = panel

	local bar = UIKit.create("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundColor3 = UIKit.Colors.panel,
		BorderSizePixel = 0,
		Parent = panel,
	}, { UIKit.corner(14) })

	UIKit.create("TextLabel", {
		Text = title,
		Size = UDim2.new(1, -50, 1, 0),
		Position = UDim2.fromOffset(14, 0),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = UIKit.Colors.accent,
		Parent = bar,
	})

	local close = UIKit.button("✕", UDim2.fromOffset(34, 34), UDim2.new(1, -40, 0, 5), UIKit.Colors.bad, function()
		panel.Visible = false
		if onClose then
			onClose()
		end
	end)
	close.Parent = bar

	local body = UIKit.create("Frame", {
		Name = "Body",
		Size = UDim2.new(1, 0, 1, -44),
		Position = UDim2.fromOffset(0, 44),
		BackgroundTransparency = 1,
		Parent = panel,
	}) :: Frame

	return panel, body
end

return UIKit
