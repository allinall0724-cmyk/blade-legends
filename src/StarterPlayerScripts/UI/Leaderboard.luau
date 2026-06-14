--!strict
-- Leaderboard (press L): Top 10 by Net Worth and a separate Rarest Pull board,
-- with the local Collector highlighted and a click-for-collection preview.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(script.Parent.UIKit)
local RarityConfig = require(ReplicatedStorage.Shared.RarityConfig)

local Leaderboard = {}

function Leaderboard.build(ctx: any)
	local panel, body = UIKit.panel("🏆 Leaderboard  [L]", UDim2.fromOffset(640, 540))
	panel.Parent = ctx.root
	local self = { panel = panel }

	local mode = "networth"
	local netEntries: { any } = {}
	local rarestEntries: { any } = {}

	-- toggle buttons
	local tabRow = UIKit.create("Frame", {
		Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 6), BackgroundTransparency = 1, Parent = body,
	}, { UIKit.create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }) })
	local nwBtn = UIKit.button("💰 Net Worth", UDim2.fromOffset(180, 30), UDim2.new(), UIKit.Colors.accent)
	nwBtn.Parent = tabRow
	local rareBtn = UIKit.button("★ Rarest Blade", UDim2.fromOffset(180, 30), UDim2.new(), UIKit.Colors.panelLight)
	rareBtn.Parent = tabRow

	local scroll = UIKit.create("ScrollingFrame", {
		Size = UDim2.new(1, -20, 1, -50), Position = UDim2.fromOffset(10, 46), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = body,
	}) :: ScrollingFrame
	UIKit.create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })

	local function showCollection(userId: number)
		local ok, summary = pcall(function()
			return ctx.func("GetCollection"):InvokeServer(userId)
		end)
		if not ok or typeof(summary) ~= "table" then
			return
		end
		local pop, popBody = UIKit.panel("📦 " .. (summary.name or "?") .. "'s Collection", UDim2.fromOffset(420, 360))
		pop.Parent = ctx.root
		pop.Visible = true
		local lines = { ("Total Blades: %d"):format(summary.total or 0), "" }
		for _, r in RarityConfig.Order do
			local n = summary.byRarity and summary.byRarity[r] or 0
			if n > 0 then
				table.insert(lines, ("%s: %d"):format(r, n))
			end
		end
		table.insert(lines, "")
		table.insert(lines, "Top Blades:")
		for _, info in (summary.top or {}) do
			table.insert(lines, ("• %s (value %d)"):format(info.name, math.floor(info.value or 0)))
		end
		UIKit.create("TextLabel", {
			Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 6), BackgroundTransparency = 1,
			Font = Enum.Font.Gotham, TextSize = 18, TextYAlignment = Enum.TextYAlignment.Top, TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UIKit.Colors.text, Text = table.concat(lines, "\n"), Parent = popBody,
		})
		task.delay(8, function()
			if pop and pop.Parent then pop:Destroy() end
		end)
	end

	local function render()
		for _, c in scroll:GetChildren() do
			if c:IsA("TextButton") then c:Destroy() end
		end
		local entries = (mode == "networth") and netEntries or rarestEntries
		local myId = Players.LocalPlayer.UserId
		if #entries == 0 then
			UIKit.create("TextLabel", {
				Size = UDim2.new(1, -8, 0, 40), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextScaled = true,
				TextColor3 = UIKit.Colors.subtext, Text = "No Collectors yet — open Crates to climb!", Parent = scroll,
			})
			return
		end
		local unit = (mode == "networth") and "NW" or "Value"
		for _, e in entries do
			local mine = e.userId == myId
			local row = UIKit.create("TextButton", {
				Size = UDim2.new(1, -8, 0, 38), BackgroundColor3 = mine and UIKit.Colors.panelLight or UIKit.Colors.panel,
				BorderSizePixel = 0, Text = "", LayoutOrder = e.position, Parent = scroll,
			}, { UIKit.corner(6) }) :: TextButton
			if mine then
				UIKit.create("UIStroke", { Color = UIKit.Colors.accent, Thickness = 2, Parent = row })
			end
			UIKit.create("TextLabel", {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = e.color or UIKit.Colors.text,
				Text = ("  #%d  %s   %s %d   %s"):format(e.position, e.name, unit, e.rating, e.weapon), Parent = row,
			}, { UIKit.pad(6) })
			row.Activated:Connect(function()
				showCollection(e.userId)
			end)
		end
	end

	local function setMode(m: string)
		mode = m
		nwBtn.BackgroundColor3 = (m == "networth") and UIKit.Colors.accent or UIKit.Colors.panelLight
		nwBtn.TextColor3 = (m == "networth") and Color3.fromRGB(20, 20, 20) or UIKit.Colors.text
		rareBtn.BackgroundColor3 = (m == "rarest") and UIKit.Colors.accent or UIKit.Colors.panelLight
		rareBtn.TextColor3 = (m == "rarest") and Color3.fromRGB(20, 20, 20) or UIKit.Colors.text
		render()
	end
	nwBtn.Activated:Connect(function() setMode("networth") end)
	rareBtn.Activated:Connect(function() setMode("rarest") end)

	function self.update(data: any)
		if data.entries then netEntries = data.entries end
		if data.rarestEntries then rarestEntries = data.rarestEntries end
		render()
	end

	function self.open()
		panel.Visible = true
		ctx.event("RequestData"):FireServer()
	end
	function self.toggle()
		if panel.Visible then panel.Visible = false else self.open() end
	end

	return self
end

return Leaderboard
