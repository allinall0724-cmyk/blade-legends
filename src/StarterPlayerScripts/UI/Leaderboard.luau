--!strict
-- Leaderboard (press L): ranked standings with the local player highlighted,
-- a live season countdown, and a click-for-collection preview.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(script.Parent.UIKit)
local RarityConfig = require(ReplicatedStorage.Shared.RarityConfig)

local Leaderboard = {}

function Leaderboard.build(ctx: any)
	local panel, body = UIKit.panel("🏆 Leaderboard  [L]", UDim2.fromOffset(640, 540))
	panel.Parent = ctx.root
	local self = { panel = panel }

	local seasonLabel = UIKit.create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(10, 6),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = UIKit.Colors.accent,
		Text = "Season ends in —",
		Parent = body,
	})

	local scroll = UIKit.create("ScrollingFrame", {
		Size = UDim2.new(1, -20, 1, -46),
		Position = UDim2.fromOffset(10, 40),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = body,
	}) :: ScrollingFrame
	UIKit.create("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	local secondsLeft = 0
	local function fmt(s: number): string
		s = math.max(0, math.floor(s))
		local d = math.floor(s / 86400)
		local h = math.floor((s % 86400) / 3600)
		local m = math.floor((s % 3600) / 60)
		return ("%dd %dh %dm"):format(d, h, m)
	end

	task.spawn(function()
		while true do
			task.wait(1)
			if secondsLeft > 0 then
				secondsLeft -= 1
				seasonLabel.Text = "Season ends in " .. fmt(secondsLeft)
			end
		end
	end)

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
		local lines = { ("Total weapons: %d"):format(summary.total or 0), ("Rank: %s (%d)"):format(summary.tier or "?", summary.rating or 0), "" }
		for _, r in RarityConfig.Order do
			local n = summary.byRarity and summary.byRarity[r] or 0
			if n > 0 then
				table.insert(lines, ("%s: %d"):format(r, n))
			end
		end
		table.insert(lines, "")
		table.insert(lines, "Top weapons:")
		for _, info in (summary.top or {}) do
			table.insert(lines, ("• %s (DMG %d)"):format(info.name, math.floor(info.damage)))
		end
		UIKit.create("TextLabel", {
			Size = UDim2.new(1, -20, 1, -10),
			Position = UDim2.fromOffset(10, 6),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextScaled = false,
			TextSize = 18,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = UIKit.Colors.text,
			Text = table.concat(lines, "\n"),
			Parent = popBody,
		})
		task.delay(8, function()
			if pop and pop.Parent then
				pop:Destroy()
			end
		end)
	end

	function self.update(data: any)
		if data.season then
			secondsLeft = data.season.secondsLeft or 0
			seasonLabel.Text = "Season ends in " .. fmt(secondsLeft)
		end
		if not data.entries then
			return
		end
		for _, c in scroll:GetChildren() do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		local myId = Players.LocalPlayer.UserId
		if #data.entries == 0 then
			UIKit.create("TextLabel", {
				Size = UDim2.new(1, -8, 0, 40),
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				TextScaled = true,
				TextColor3 = UIKit.Colors.subtext,
				Text = "No ranked players yet — be the first!",
				Parent = scroll,
			})
		end
		for _, e in data.entries do
			local mine = e.userId == myId
			local row = UIKit.create("TextButton", {
				Size = UDim2.new(1, -8, 0, 38),
				BackgroundColor3 = mine and UIKit.Colors.panelLight or UIKit.Colors.panel,
				BorderSizePixel = 0,
				Text = "",
				LayoutOrder = e.position,
				Parent = scroll,
			}, { UIKit.corner(6) }) :: TextButton
			if mine then
				UIKit.create("UIStroke", { Color = UIKit.Colors.accent, Thickness = 2, Parent = row })
			end
			UIKit.create("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamMedium,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = e.color or UIKit.Colors.text,
				Text = ("  #%d  %s   %s %d   %s"):format(e.position, e.name, e.tier, e.rating, e.weapon),
				Parent = row,
			}, { UIKit.pad(6) })
			row.Activated:Connect(function()
				showCollection(e.userId)
			end)
		end
	end

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

return Leaderboard
