--!strict
-- Trade window: both Collectors' offers side-by-side (up to 8 each) with Value
-- totals + a fairness indicator, Ready toggles, a 5s countdown, and a preset
-- trade-chat. Driven entirely by server "TradeAction" messages.

local UIKit = require(script.Parent.UIKit)

local Trade = {}

local PRESETS = { "Deal?", "Add more?", "That's fair", "No thanks" }

function Trade.build(ctx: any)
	local panel, body = UIKit.panel("🤝 Trade", UDim2.fromOffset(660, 540), function()
		ctx.event("TradeAction"):FireServer({ action = "cancel" })
	end)
	panel.Parent = ctx.root
	local self = { panel = panel }

	local function column(x: number): (Frame, TextLabel, TextLabel)
		local col = UIKit.create("Frame", {
			Size = UDim2.new(0.5, -16, 0, 250), Position = UDim2.fromOffset(x, 8),
			BackgroundColor3 = UIKit.Colors.panel, BorderSizePixel = 0, Parent = body,
		}, { UIKit.corner(8) })
		local head = UIKit.create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
			TextScaled = true, TextColor3 = UIKit.Colors.accent, Text = "—", Parent = col,
		})
		local list = UIKit.create("ScrollingFrame", {
			Size = UDim2.new(1, -8, 1, -52), Position = UDim2.fromOffset(4, 28), BackgroundTransparency = 1,
			BorderSizePixel = 0, ScrollBarThickness = 5, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = col,
		}) :: ScrollingFrame
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), Parent = list })
		local total = UIKit.create("TextLabel", {
			Size = UDim2.new(1, -8, 0, 20), Position = UDim2.new(0, 4, 1, -22), BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.fromRGB(120, 220, 150), Text = "Value: 0 ⬩", Parent = col,
		})
		return list, head, total
	end

	local youList, youHead, youTotal = column(8)
	local themList, themHead, themTotal = column(0)
	local themCol = themList.Parent :: Frame
	themCol.Position = UDim2.new(0.5, 8, 0, 8)
	youHead.Text = "YOU"

	local diffLabel = UIKit.create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 262), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = UIKit.Colors.accent, Text = "", Parent = body,
	})
	local statusLabel = UIKit.create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 288), BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium, TextSize = 15, TextColor3 = UIKit.Colors.text, Text = "", Parent = body,
	})

	-- chat log + preset buttons
	local chatLog = UIKit.create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 56), Position = UDim2.fromOffset(10, 314), BackgroundColor3 = UIKit.Colors.bg,
		BackgroundTransparency = 0.3, Font = Enum.Font.Gotham, TextSize = 13, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UIKit.Colors.subtext, Text = "", Parent = body,
	}, { UIKit.corner(6), UIKit.pad(4) })
	local chatRow = UIKit.create("Frame", {
		Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 376), BackgroundTransparency = 1, Parent = body,
	}, { UIKit.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }) })
	for _, msg in PRESETS do
		local b = UIKit.button(msg, UDim2.fromOffset(150, 28), UDim2.new(), UIKit.Colors.panelLight, function()
			ctx.event("TradeAction"):FireServer({ action = "chat", msg = msg })
		end)
		b.Parent = chatRow
	end
	local chatLines: { string } = {}

	local readyBtn = UIKit.button("Ready", UDim2.new(0, 200, 0, 44), UDim2.new(0, 10, 1, -56), UIKit.Colors.good)
	readyBtn.Parent = body
	local myReady = false
	readyBtn.Activated:Connect(function()
		myReady = not myReady
		ctx.event("TradeAction"):FireServer({ action = "ready", value = myReady })
	end)
	local cancelBtn = UIKit.button("Cancel", UDim2.new(0, 200, 0, 44), UDim2.new(0, 220, 1, -56), UIKit.Colors.bad, function()
		ctx.event("TradeAction"):FireServer({ action = "cancel" })
	end)
	cancelBtn.Parent = body

	local function renderOffers(list: ScrollingFrame, offers: { any }, removable: boolean)
		for _, c in list:GetChildren() do
			if c:IsA("TextButton") or c:IsA("TextLabel") then
				c:Destroy()
			end
		end
		for i, info in offers do
			local cell = UIKit.create("TextButton", {
				Size = UDim2.new(1, -6, 0, 30), BackgroundColor3 = UIKit.Colors.panelLight, BorderSizePixel = 0,
				Font = Enum.Font.GothamMedium, TextScaled = true, TextColor3 = info.rarityColor or UIKit.Colors.text,
				Text = ("%s  ⬩%d"):format(info.name, math.floor(info.value or 0)), LayoutOrder = i, Parent = list,
			}, { UIKit.corner(6) }) :: TextButton
			if removable then
				cell.Activated:Connect(function()
					ctx.event("TradeAction"):FireServer({ action = "removeOffer", index = i })
				end)
			end
		end
	end

	function self.offer(weaponId: number)
		ctx.event("TradeAction"):FireServer({ action = "addOffer", weaponId = weaponId })
	end

	function self.onAction(data: any)
		if data.kind == "invite" then
			panel.Visible = true
			statusLabel.Text = ("%s wants to trade. Accept?"):format(data.from)
			readyBtn.Text = "Accept"
			myReady = false
			local conn
			conn = readyBtn.Activated:Connect(function()
				ctx.event("TradeAction"):FireServer({ action = "accept" })
				readyBtn.Text = "Ready"
				conn:Disconnect()
			end)
		elseif data.kind == "waiting" then
			panel.Visible = true
			statusLabel.Text = ("Waiting for %s to accept..."):format(data.target)
		elseif data.kind == "update" then
			panel.Visible = true
			local view = data.view
			if view then
				themHead.Text = string.upper(view.them.name)
				renderOffers(youList, view.you.offer, true)
				renderOffers(themList, view.them.offer, false)
				local yv, tv = math.floor(view.you.totalValue or 0), math.floor(view.them.totalValue or 0)
				youTotal.Text = "Value: " .. yv .. " ⬩"
				themTotal.Text = "Value: " .. tv .. " ⬩"
				local d = tv - yv
				if d > 0 then
					diffLabel.Text = ("⬆ You're receiving %d more value"):format(d)
					diffLabel.TextColor3 = Color3.fromRGB(120, 220, 150)
				elseif d < 0 then
					diffLabel.Text = ("⬇ You're offering %d more value"):format(-d)
					diffLabel.TextColor3 = Color3.fromRGB(230, 150, 90)
				else
					diffLabel.Text = "⚖ Even trade"
					diffLabel.TextColor3 = UIKit.Colors.accent
				end
				statusLabel.Text = ("You: %s   |   %s: %s"):format(
					view.you.ready and "READY" or "not ready",
					view.them.name,
					view.them.ready and "READY" or (view.them.accepted and "not ready" or "deciding...")
				)
				readyBtn.Text = view.you.ready and "Unready" or "Ready"
				myReady = view.you.ready
			end
		elseif data.kind == "chat" then
			table.insert(chatLines, ("%s: %s"):format(data.from or "?", data.msg or ""))
			while #chatLines > 3 do
				table.remove(chatLines, 1)
			end
			chatLog.Text = table.concat(chatLines, "\n")
		elseif data.kind == "countdown" then
			statusLabel.Text = ("Trading in %d..."):format(data.n)
		elseif data.kind == "closed" then
			statusLabel.Text = data.reason or "Trade closed."
			chatLines = {}
			chatLog.Text = ""
			task.delay(1.5, function()
				panel.Visible = false
			end)
		end
	end

	function self.toggle()
		panel.Visible = not panel.Visible
	end

	return self
end

return Trade
