--!strict
-- RankedQueue (press K): enter/leave the ranked queue, see your rank + estimated
-- wait, the pre-match lobby (both players' rank & weapon), and live match score.
-- Also hosts the Casual arena join/leave toggle.

local UIKit = require(script.Parent.UIKit)

local RankedQueue = {}

function RankedQueue.build(ctx: any)
	local panel, body = UIKit.panel("⚔ Arenas  [K]", UDim2.fromOffset(520, 460))
	panel.Parent = ctx.root
	local self = { panel = panel }

	local status = UIKit.create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 90),
		Position = UDim2.fromOffset(10, 8),
		BackgroundColor3 = UIKit.Colors.panel,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = UIKit.Colors.text,
		Text = "Ranked: idle",
		TextWrapped = true,
		Parent = body,
	}, { UIKit.corner(8), UIKit.pad(8) })

	local rankLine = UIKit.create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.fromOffset(10, 104),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextColor3 = UIKit.Colors.subtext,
		Text = "Your rank: Bronze (0)",
		Parent = body,
	})

	local queued = false
	local enterBtn = UIKit.button("Enter Ranked Queue", UDim2.new(1, -20, 0, 50), UDim2.fromOffset(10, 144), UIKit.Colors.good)
	enterBtn.Parent = body
	enterBtn.Activated:Connect(function()
		if queued then
			ctx.event("LeaveQueue"):FireServer()
		else
			ctx.event("EnterRankedQueue"):FireServer()
		end
	end)

	-- casual toggle
	local inCasual = false
	local casualBtn = UIKit.button("Join Casual Arena", UDim2.new(1, -20, 0, 50), UDim2.fromOffset(10, 204), UIKit.Colors.panelLight)
	casualBtn.Parent = body
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

	local hint = UIKit.create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 120),
		Position = UDim2.fromOffset(10, 268),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextScaled = false,
		TextSize = 16,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = UIKit.Colors.subtext,
		Text = "Ranked is 1v1, first to 3 kills. Matched within 200 rating.\nClick to swing • Hold RMB to block • Q to dodge roll.",
		Parent = body,
	})

	-- update HUD-derived rank
	function self.updateRank(data: any)
		if data.tier then
			rankLine.Text = ("Your rank: %s (%d)"):format(data.tier, math.floor(data.rating or 0))
		end
		if data.inCasual ~= nil then
			inCasual = data.inCasual
			casualBtn.Text = inCasual and "Leave Casual Arena" or "Join Casual Arena"
		end
	end

	-- ranked match state
	function self.onMatchState(data: any)
		if data.queued ~= nil then
			queued = data.queued
			enterBtn.Text = queued and "Leave Queue" or "Enter Ranked Queue"
			if queued then
				status.Text = "Searching for opponent...\nEstimated wait: ~15s"
			else
				status.Text = "Ranked: idle"
			end
			return
		end
		if data.ended then
			status.Text = data.won and "🏆 You won the ranked match!" or "Ranked match lost."
			queued = false
			enterBtn.Text = "Enter Ranked Queue"
			return
		end
		if data.active ~= nil then
			-- lobby / in-match
			status.Text = ("VS %s  [%s %d]\nWeapon: %s\nScore  %d — %d  (first to %d)"):format(
				data.opponent or "?",
				"R", math.floor(data.opponentRating or 0),
				data.opponentWeapon or "?",
				math.floor(data.myScore or 0), math.floor(data.oppScore or 0),
				data.winKills or 3
			)
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

return RankedQueue
