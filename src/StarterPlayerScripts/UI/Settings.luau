--!strict
-- Settings: a gear button + panel with Music and SFX volume sliders.
-- (Roblox reserves the Escape key for its own menu, so the gear button and the
-- 'P' hotkey toggle this panel instead.)

local UserInputService = game:GetService("UserInputService")

local UIKit = require(script.Parent.UIKit)

local Settings = {}

local function slider(parent: Instance, label: string, y: number, initial: number, onChange: (number) -> ())
	UIKit.create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, y),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UIKit.Colors.text,
		Text = label,
		Parent = parent,
	})
	local track = UIKit.create("Frame", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, y + 28),
		BackgroundColor3 = UIKit.Colors.panelLight,
		BorderSizePixel = 0,
		Parent = parent,
	}, { UIKit.corner(8) })
	local fill = UIKit.create("Frame", {
		Size = UDim2.fromScale(initial, 1),
		BackgroundColor3 = UIKit.Colors.accent,
		BorderSizePixel = 0,
		Parent = track,
	}, { UIKit.corner(8) })
	local handle = UIKit.create("Frame", {
		Size = UDim2.fromOffset(18, 24),
		Position = UDim2.new(initial, -9, 0.5, -12),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Parent = track,
	}, { UIKit.corner(9) })
	local pct = UIKit.create("TextLabel", {
		Size = UDim2.fromOffset(50, 24),
		Position = UDim2.new(1, -50, 0, y),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextColor3 = UIKit.Colors.subtext,
		Text = tostring(math.floor(initial * 100)) .. "%",
		Parent = parent,
	})

	local dragging = false
	local function setFromX(x: number)
		local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
		fill.Size = UDim2.fromScale(rel, 1)
		handle.Position = UDim2.new(rel, -9, 0.5, -12)
		pct.Text = tostring(math.floor(rel * 100)) .. "%"
		onChange(rel)
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

function Settings.build(ctx: any)
	local self = {}
	local sound = ctx.sound

	-- gear button (top-right, left of the rank badge)
	local gear = UIKit.button("⚙", UDim2.fromOffset(40, 40), UDim2.new(1, -272, 0, 18), UIKit.Colors.panel, function()
		self.toggle()
	end)
	gear.Parent = ctx.root

	local panel, body = UIKit.panel("⚙ Settings  [P]", UDim2.fromOffset(420, 280))
	panel.Parent = ctx.root

	local content = UIKit.create("Frame", {
		Size = UDim2.new(1, -40, 1, -30),
		Position = UDim2.fromOffset(20, 14),
		BackgroundTransparency = 1,
		Parent = body,
	})

	slider(content, "🎵 Music Volume", 6, sound and sound.getMusicVolume() or 0.35, function(v)
		if sound then
			sound.setMusicVolume(v)
		end
	end)
	slider(content, "🔊 SFX Volume", 86, sound and sound.getSfxVolume() or 0.5, function(v)
		if sound then
			sound.setSfxVolume(v)
		end
	end)
	UIKit.create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 150),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextWrapped = true,
		TextColor3 = UIKit.Colors.subtext,
		Text = "Controls: LMB swing • RMB block • Shift dodge • Q/E/R/F/G abilities • I/C/B/L/K menus • T trade",
		Parent = content,
	})

	function self.toggle()
		panel.Visible = not panel.Visible
	end

	return self
end

return Settings
