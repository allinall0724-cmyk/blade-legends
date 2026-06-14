--!strict
-- Shop (press B): tabbed store — Passes / Coins / Cases / Cosmetics / Bundles —
-- with a featured Daily Deal, pass benefit checklists, ownership badges and a
-- name-color picker.

local TweenService = game:GetService("TweenService")
local UIKit = require(script.Parent.UIKit)

local Shop = {}

local TABS = { "Passes", "Coins", "Cases", "Cosmetics", "Bundles" }
local CATEGORY_OF_TAB = { Coins = "coins", Cases = "cases", Cosmetics = "cosmetic", Bundles = "bundle" }

function Shop.build(ctx: any)
	local panel, body = UIKit.panel("🛒 Shop  [B]", UDim2.fromOffset(780, 580))
	panel.Parent = ctx.root
	local self = { panel = panel }

	local info: any = nil
	local currentTab = "Passes"

	-- ===== featured daily deal =====
	local featured = UIKit.create("Frame", {
		Size = UDim2.new(1, -20, 0, 84),
		Position = UDim2.fromOffset(10, 8),
		BackgroundColor3 = Color3.fromRGB(45, 38, 18),
		BorderSizePixel = 0,
		Parent = body,
	}, { UIKit.corner(10), UIKit.create("UIStroke", { Color = Color3.fromRGB(255, 200, 70), Thickness = 2.5 }) })
	local featuredTitle = UIKit.create("TextLabel", {
		Size = UDim2.new(0.7, 0, 0, 26),
		Position = UDim2.fromOffset(12, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(255, 215, 90),
		Text = "★ DAILY DEAL",
		Parent = featured,
	})
	local featuredDesc = UIKit.create("TextLabel", {
		Size = UDim2.new(0.7, 0, 0, 40),
		Position = UDim2.fromOffset(12, 36),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = UIKit.Colors.text,
		Text = "",
		Parent = featured,
	})
	local limitedBadge = UIKit.create("TextLabel", {
		Size = UDim2.fromOffset(110, 26),
		Position = UDim2.new(1, -260, 0, 8),
		BackgroundColor3 = Color3.fromRGB(200, 50, 50),
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Text = "LIMITED −30%",
		Parent = featured,
	}, { UIKit.corner(6) })
	task.spawn(function()
		while limitedBadge.Parent do
			TweenService:Create(limitedBadge, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.4 }):Play()
			task.wait(1.3)
		end
	end)
	local featuredBuy = UIKit.button("R$ —", UDim2.fromOffset(130, 56), UDim2.new(1, -142, 0, 14), Color3.fromRGB(230, 180, 40))
	featuredBuy.Parent = featured

	-- ===== tabs =====
	local tabRow = UIKit.create("Frame", {
		Size = UDim2.new(1, -20, 0, 32),
		Position = UDim2.fromOffset(10, 98),
		BackgroundTransparency = 1,
		Parent = body,
	})
	UIKit.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), Parent = tabRow })
	local tabButtons: { [string]: TextButton } = {}

	-- ===== content =====
	local scroll = UIKit.create("ScrollingFrame", {
		Size = UDim2.new(1, -20, 1, -138),
		Position = UDim2.fromOffset(10, 134),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = body,
	})
	UIKit.create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })

	local function buyKey(key: string)
		ctx.event("BuyProduct"):FireServer({ productKey = key })
	end

	-- a product/pass row
	local function productRow(prod: any, owned: boolean, order: number)
		local isDeal = info and prod.key == info.dailyDealKey
		local row = UIKit.create("Frame", {
			Size = UDim2.new(1, -10, 0, 70),
			BackgroundColor3 = UIKit.Colors.panel,
			BorderSizePixel = 0,
			LayoutOrder = order,
			Parent = scroll,
		}, { UIKit.corner(8) })
		if isDeal then
			UIKit.create("UIStroke", { Color = Color3.fromRGB(255, 200, 70), Thickness = 2, Parent = row })
		end
		local title = prod.name
		if prod.badge then
			title = title .. "  ⭐" .. prod.badge
		end
		UIKit.create("TextLabel", {
			Size = UDim2.new(0.62, 0, 0.5, 0), Position = UDim2.fromOffset(12, 6),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UIKit.Colors.text, Text = title, Parent = row,
		})
		UIKit.create("TextLabel", {
			Size = UDim2.new(0.62, 0, 0.42, 0), Position = UDim2.fromOffset(12, 38),
			BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextScaled = true, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UIKit.Colors.subtext,
			Text = isDeal and (prod.desc .. "  (+30% bonus value today!)") or prod.desc, Parent = row,
		})
		local buy = UIKit.button(
			owned and "OWNED" or ("R$ " .. prod.robux),
			UDim2.fromOffset(150, 50), UDim2.new(1, -162, 0, 10),
			owned and UIKit.Colors.panelLight or UIKit.Colors.good,
			function()
				if not owned then buyKey(prod.key) end
			end
		)
		buy.Parent = row
	end

	-- a pass card with benefit checklist
	local function passCard(pass: any, owned: boolean, order: number)
		local h = 64 + #pass.benefits * 20
		local card = UIKit.create("Frame", {
			Size = UDim2.new(1, -10, 0, h),
			BackgroundColor3 = UIKit.Colors.panel,
			BorderSizePixel = 0,
			LayoutOrder = order,
			Parent = scroll,
		}, { UIKit.corner(8), UIKit.create("UIStroke", { Color = pass.tagColor or UIKit.Colors.accent, Thickness = 1.5, Transparency = 0.3 }) })
		UIKit.create("TextLabel", {
			Size = UDim2.new(0.62, 0, 0, 28), Position = UDim2.fromOffset(12, 8),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = pass.tagColor or UIKit.Colors.text, Text = pass.name, Parent = card,
		})
		for i, b in pass.benefits do
			UIKit.create("TextLabel", {
				Size = UDim2.new(0.95, 0, 0, 18), Position = UDim2.fromOffset(16, 36 + (i - 1) * 20),
				BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UIKit.Colors.subtext, Text = "✓ " .. b, Parent = card,
			})
		end
		if owned then
			UIKit.create("TextLabel", {
				Size = UDim2.fromOffset(150, 40), Position = UDim2.new(1, -162, 0, 12),
				BackgroundColor3 = Color3.fromRGB(60, 120, 70), Font = Enum.Font.GothamBold, TextScaled = true,
				TextColor3 = Color3.fromRGB(220, 255, 220), Text = "YOU OWN THIS", Parent = card,
			}, { UIKit.corner(6), UIKit.pad(4) })
		else
			local buy = UIKit.button("R$ " .. pass.robux, UDim2.fromOffset(150, 44), UDim2.new(1, -162, 0, 12), UIKit.Colors.good, function()
				buyKey(pass.key)
			end)
			buy.Parent = card
		end
	end

	local function header(text: string, order: number)
		UIKit.create("TextLabel", {
			Size = UDim2.new(1, -10, 0, 30), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
			TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UIKit.Colors.accent,
			Text = text, LayoutOrder = order, Parent = scroll,
		})
	end

	local function renderTab(tab: string)
		for _, c in scroll:GetChildren() do
			if not c:IsA("UIListLayout") then c:Destroy() end
		end
		if not info then return end
		local order = 1

		if tab == "Passes" then
			for _, pass in info.passes do
				passCard(pass, info.owned and info.owned[pass.key] == true, order)
				order += 1
			end
		else
			local cat = CATEGORY_OF_TAB[tab]
			for _, prod in info.products do
				if prod.category == cat then
					productRow(prod, false, order)
					order += 1
				end
			end
			if tab == "Cosmetics" then
				-- daily claim + name color picker
				header("☀ Daily Reward (streak " .. (info.streak or 0) .. ")", order); order += 1
				local claimRow = UIKit.create("Frame", { Size = UDim2.new(1, -10, 0, 50), BackgroundColor3 = UIKit.Colors.panel, BorderSizePixel = 0, LayoutOrder = order, Parent = scroll }, { UIKit.corner(8) }); order += 1
				local claim = UIKit.button("Claim Daily", UDim2.new(0, 150, 0, 40), UDim2.new(0, 8, 0, 5), UIKit.Colors.accent, function()
					ctx.event("ClaimDaily"):FireServer(); task.wait(0.3); self.refresh()
				end); claim.Parent = claimRow
				if info.nameColorOwned then
					header("🎨 Name Color (click to apply)", order); order += 1
					local swatchRow = UIKit.create("Frame", { Size = UDim2.new(1, -10, 0, 40), BackgroundTransparency = 1, LayoutOrder = order, Parent = scroll }, { UIKit.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) }); order += 1
					for i, col in info.nameColors do
						local sw = UIKit.create("TextButton", { Size = UDim2.fromOffset(34, 34), BackgroundColor3 = col, BorderSizePixel = 0, Text = (i == info.nameColorIdx) and "✓" or "", Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(0, 0, 0), Parent = swatchRow }, { UIKit.corner(6) }) :: TextButton
						sw.Activated:Connect(function()
							ctx.event("PickNameColor"):FireServer({ idx = i }); task.wait(0.2); self.refresh()
						end)
					end
				end
			end
		end
	end

	-- build tab buttons
	for _, tab in TABS do
		local btn = UIKit.button(tab, UDim2.fromOffset(140, 30), UDim2.new(), UIKit.Colors.panelLight, function()
			currentTab = tab
			for name, b in tabButtons do
				local on = name == tab
				b.BackgroundColor3 = on and UIKit.Colors.accent or UIKit.Colors.panelLight
				b.TextColor3 = on and Color3.fromRGB(20, 20, 20) or UIKit.Colors.text
			end
			renderTab(tab)
		end)
		btn.Parent = tabRow
		tabButtons[tab] = btn
	end

	local function updateFeatured()
		if not info or not info.dailyDealKey or info.dailyDealKey == "" then
			featuredDesc.Text = "Check back at midnight UTC for a new deal!"
			return
		end
		-- find the dealt product or pass
		local dealt: any = nil
		for _, p in info.products do
			if p.key == info.dailyDealKey then dealt = p break end
		end
		if not dealt then
			for _, p in info.passes do
				if p.key == info.dailyDealKey then dealt = p break end
			end
		end
		if dealt then
			featuredTitle.Text = "★ DAILY DEAL — " .. dealt.name
			featuredDesc.Text = (dealt.desc or "") .. "  Extra +30% value today only!"
			featuredBuy.Text = "R$ " .. dealt.robux
			featuredBuy.Activated:Once(function()
				buyKey(dealt.key)
			end)
		end
	end

	function self.refresh()
		local ok, result = pcall(function()
			return ctx.func("GetShopInfo"):InvokeServer()
		end)
		if ok and typeof(result) == "table" then
			info = result
		end
		updateFeatured()
		renderTab(currentTab)
		for name, b in tabButtons do
			local on = name == currentTab
			b.BackgroundColor3 = on and UIKit.Colors.accent or UIKit.Colors.panelLight
			b.TextColor3 = on and Color3.fromRGB(20, 20, 20) or UIKit.Colors.text
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
