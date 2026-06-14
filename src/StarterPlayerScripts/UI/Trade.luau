--!strict
-- Trade window: both players' offers side-by-side, ready toggles, countdown.
-- Driven entirely by server "TradeAction" messages so the client can't fake a
-- trade — it only renders state the server sends.

local UIKit = require(script.Parent.UIKit)

local Trade = {}

function Trade.build(ctx: any)
	local panel, body = UIKit.panel("🤝 Trade", UDim2.fromOffset(640, 460), function()
		ctx.event("TradeAction"):FireServer({ action = "cancel" })
	end)
	panel.Parent = ctx.root
	local self = { panel = panel }

	-- two columns
	local function column(title: string, x: number): (Frame, TextLabel)
		local col = UIKit.create("Frame", {
			Size = UDim2.new(0.5, -16, 1, -110),
			Position = UDim2.fromOffset(x, 8),
			BackgroundColor3 = UIKit.Colors.panel,
			BorderSizePixel = 0,
			Parent = body,
		}, { UIKit.corner(8) })
		local head = UIKit.create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextColor3 = UIKit.Colors.accent,
			Text = title,
			Parent = col,
		})
		local list = UIKit.create("ScrollingFrame", {
			Size = UDim2.new(1, -8, 1, -36),
			Position = UDim2.fromOffset(4, 32),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 5,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			Parent = col,
		}) :: ScrollingFrame
		UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), Parent = list })
		return list, head
	end

	local youList = column("You", 8)
	local themList = column("Them", 0)
	-- place the "Them" column in the right half
	local themCol = themList.Parent :: Frame
	themCol.Position = UDim2.new(0.5, 8, 0, 8)

	local statusLabel = UIKit.create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.new(0, 10, 1, -96),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = UIKit.Colors.text,
		Text = "",
		Parent = body,
	})

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
				Size = UDim2.new(1, -6, 0, 36),
				BackgroundColor3 = UIKit.Colors.panelLight,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamMedium,
				TextScaled = true,
				TextColor3 = info.rarityColor or UIKit.Colors.text,
				Text = info.name,
				LayoutOrder = i,
				Parent = list,
			}, { UIKit.corner(6) }) :: TextButton
			if removable then
				cell.Activated:Connect(function()
					ctx.event("TradeAction"):FireServer({ action = "removeOffer", index = i })
				end)
			end
		end
	end

	-- offer a weapon from inventory (called by Inventory context menu)
	function self.offer(weaponId: number)
		ctx.event("TradeAction"):FireServer({ action = "addOffer", weaponId = weaponId })
	end

	-- handle server messages
	function self.onAction(data: any)
		if data.kind == "invite" then
			panel.Visible = true
			statusLabel.Text = ("%s wants to trade. Accept?"):format(data.from)
			readyBtn.Text = "Accept"
			myReady = false
			-- temporary: accept binds to ready button once
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
				renderOffers(youList, view.you.offer, true)
				renderOffers(themList, view.them.offer, false)
				statusLabel.Text = ("You: %s   |   %s: %s"):format(
					view.you.ready and "READY" or "not ready",
					view.them.name,
					view.them.ready and "READY" or (view.them.accepted and "not ready" or "deciding...")
				)
				readyBtn.Text = view.you.ready and "Unready" or "Ready"
				myReady = view.you.ready
			end
		elseif data.kind == "countdown" then
			statusLabel.Text = ("Trading in %d..."):format(data.n)
		elseif data.kind == "closed" then
			statusLabel.Text = data.reason or "Trade closed."
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
