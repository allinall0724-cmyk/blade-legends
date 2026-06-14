--!strict
-- Activities (press K): Blade Legends is now collection-first, so Ranked PVP is a
-- "Coming Soon" placeholder. The Casual Arena remains as an optional side activity
-- for earning coins.

local UIKit = require(script.Parent.UIKit)

local RankedQueue = {}

function RankedQueue.build(ctx: any)
	local panel, body = UIKit.panel("⚔ Activities  [K]", UDim2.fromOffset(520, 420))
	panel.Parent = ctx.root
	local self = { panel = panel }

	-- Ranked PVP — Coming Soon placeholder
	local rankedCard = UIKit.create("Frame", {
		Size = UDim2.new(1, -20, 0, 110), Position = UDim2.fromOffset(10, 10),
		BackgroundColor3 = UIKit.Colors.panel, BorderSizePixel = 0, Parent = body,
	}, { UIKit.corner(8), UIKit.create("UIStroke", { Color = Color3.fromRGB(120, 120, 130), Thickness = 1, Transparency = 0.3 }) })
	UIKit.create("TextLabel", {
		Size = UDim2.new(1, -16, 0, 36), Position = UDim2.fromOffset(8, 8), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(150, 150, 160), Text = "🏆 Ranked PVP", Parent = rankedCard,
	})
	UIKit.create("TextLabel", {
		Size = UDim2.new(1, -16, 0, 50), Position = UDim2.fromOffset(8, 46), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = UIKit.Colors.subtext,
		Text = "COMING SOON — competitive ladder is in development. For now, focus on collecting and trading the rarest Blades!", Parent = rankedCard,
	})

	-- Casual Arena — side activity
	local casualCard = UIKit.create("Frame", {
		Size = UDim2.new(1, -20, 0, 150), Position = UDim2.fromOffset(10, 130),
		BackgroundColor3 = UIKit.Colors.panel, BorderSizePixel = 0, Parent = body,
	}, { UIKit.corner(8), UIKit.create("UIStroke", { Color = Color3.fromRGB(255, 160, 60), Thickness = 1.5, Transparency = 0.2 }) })
	UIKit.create("TextLabel", {
		Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 8), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 170, 70), Text = "⚔ Casual Arena (side activity)", Parent = casualCard,
	})
	UIKit.create("TextLabel", {
		Size = UDim2.new(1, -16, 0, 40), Position = UDim2.fromOffset(8, 40), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 15, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = UIKit.Colors.subtext,
		Text = "Optional free-for-all to earn coins for Crates. Not the main focus — collecting is.", Parent = casualCard,
	})

	local inCasual = false
	local casualBtn = UIKit.button("Join Casual Arena", UDim2.new(1, -16, 0, 46), UDim2.new(0, 8, 1, -54), UIKit.Colors.good)
	casualBtn.Parent = casualCard
	casualBtn.Activated:Connect(function()
		if inCasual then
			ctx.event("LeaveCasual"):FireServer()
			inCasual = false
			casualBtn.Text = "Join Casual Arena"
		else
			ctx.event("EnterCasual"):FireServer()
			inCasual = true
			casualBtn.Text = "Leave Casual Arena"
		end
	end)

	-- kept for UIManager compatibility (rank UI removed from HUD)
	function self.updateRank(data: any)
		if data.inCasual ~= nil then
			inCasual = data.inCasual
			casualBtn.Text = inCasual and "Leave Casual Arena" or "Join Casual Arena"
		end
	end
	function self.onMatchState(_data: any) end

	function self.open()
		panel.Visible = true
		ctx.event("RequestData"):FireServer()
	end
	function self.toggle()
		if panel.Visible then
			panel.Visible = false
		else
			self.open()
		end
	end

	return self
end

return RankedQueue
