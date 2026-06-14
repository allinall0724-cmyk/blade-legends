--!strict
-- Shop (press B): game passes, coin bundles (developer products), and a daily
-- free-coins claim slot.

local UIKit = require(script.Parent.UIKit)

local Shop = {}

function Shop.build(ctx: any)
	local panel, body = UIKit.panel("🛒 Shop  [B]", UDim2.fromOffset(680, 540))
	panel.Parent = ctx.root
	local self = { panel = panel }

	local scroll = UIKit.create("ScrollingFrame", {
		Size = UDim2.new(1, -20, 1, -16),
		Position = UDim2.fromOffset(10, 8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = body,
	}) :: ScrollingFrame
	UIKit.create("UIListLayout", {
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	local function header(text: string, order: number)
		UIKit.create("TextLabel", {
			Size = UDim2.new(1, -10, 0, 34),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UIKit.Colors.accent,
			Text = text,
			LayoutOrder = order,
			Parent = scroll,
		})
	end

	local function itemRow(title: string, desc: string, robux: number, owned: boolean, badge: string?, order: number, onBuy: () -> ())
		local row = UIKit.create("Frame", {
			Size = UDim2.new(1, -10, 0, 70),
			BackgroundColor3 = UIKit.Colors.panel,
			BorderSizePixel = 0,
			LayoutOrder = order,
			Parent = scroll,
		}, { UIKit.corner(8) })
		UIKit.create("TextLabel", {
			Size = UDim2.new(0.62, 0, 0.5, 0),
			Position = UDim2.fromOffset(12, 6),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UIKit.Colors.text,
			Text = badge and (title .. "  ⭐" .. badge) or title,
			Parent = row,
		})
		UIKit.create("TextLabel", {
			Size = UDim2.new(0.62, 0, 0.42, 0),
			Position = UDim2.fromOffset(12, 38),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UIKit.Colors.subtext,
			Text = desc,
			TextWrapped = true,
			Parent = row,
		})
		local buy = UIKit.button(
			owned and "OWNED" or ("R$ " .. robux),
			UDim2.new(0, 150, 0, 50),
			UDim2.new(1, -162, 0, 10),
			owned and UIKit.Colors.panelLight or UIKit.Colors.good,
			function()
				if not owned then
					onBuy()
				end
			end
		)
		buy.Parent = row
	end

	function self.refresh()
		for _, c in scroll:GetChildren() do
			if not c:IsA("UIListLayout") then
				c:Destroy()
			end
		end
		local ok, info = pcall(function()
			return ctx.func("GetShopInfo"):InvokeServer()
		end)
		if not ok or typeof(info) ~= "table" then
			return
		end

		-- daily slot
		header("☀ Daily Reward", 1)
		local dailyRow = UIKit.create("Frame", {
			Size = UDim2.new(1, -10, 0, 64),
			BackgroundColor3 = UIKit.Colors.panel,
			BorderSizePixel = 0,
			LayoutOrder = 2,
			Parent = scroll,
		}, { UIKit.corner(8) })
		UIKit.create("TextLabel", {
			Size = UDim2.new(0.62, 0, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UIKit.Colors.text,
			Text = ("Login streak: %d days\nDay 3:+150  Day 7:+500  Day 30:+2000"):format(info.streak or 0),
			Parent = dailyRow,
		})
		local claim = UIKit.button("Claim", UDim2.new(0, 150, 0, 46), UDim2.new(1, -162, 0, 9), UIKit.Colors.accent, function()
			ctx.event("ClaimDaily"):FireServer()
			task.wait(0.3)
			self.refresh()
		end)
		claim.Parent = dailyRow

		-- passes
		header("🎟 Game Passes", 3)
		local order = 4
		for _, pass in info.passes do
			local owned = info.owned and info.owned[pass.key] == true
			itemRow(pass.name, pass.desc, pass.robux, owned, nil, order, function()
				ctx.event("BuyProduct"):FireServer({ productKey = pass.key })
			end)
			order += 1
		end

		-- products
		header("🪙 Coin Bundles", order)
		order += 1
		for _, prod in info.products do
			itemRow(prod.name, prod.desc, prod.robux, false, prod.badge, order, function()
				ctx.event("BuyProduct"):FireServer({ productKey = prod.key })
			end)
			order += 1
		end
	end

	function self.open()
		panel.Visible = true
		self.refresh()
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

return Shop
