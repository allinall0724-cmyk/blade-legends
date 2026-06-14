--!strict
-- CaseOpening (press C): three case buttons, a spinning rarity reel, a result
-- card with stats, and Open Again / Close. Confetti for Legendary+.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UIKit = require(script.Parent.UIKit)
local CaseConfig = require(ReplicatedStorage.Shared.CaseConfig)
local RarityConfig = require(ReplicatedStorage.Shared.RarityConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

local CaseOpening = {}

function CaseOpening.build(ctx: any)
	local panel, body = UIKit.panel("🎁 Cases  [C]", UDim2.fromOffset(640, 480))
	panel.Parent = ctx.root
	local self = { panel = panel }

	local spinning = false
	local lastCaseId = "Basic"

	-- case buttons
	local btnRow = UIKit.create("Frame", {
		Size = UDim2.new(1, -20, 0, 110),
		Position = UDim2.fromOffset(10, 10),
		BackgroundTransparency = 1,
		Parent = body,
	})
	local function openCase(caseId: string)
		if spinning then
			return
		end
		lastCaseId = caseId
		self.startSpin(caseId)
		ctx.event("OpenCase"):FireServer({ caseId = caseId })
	end
	local x = 0
	for _, caseId in CaseConfig.Order do
		local case = CaseConfig.Cases[caseId]
		local btn = UIKit.button(
			("%s\n🪙 %d"):format(case.name, case.cost),
			UDim2.new(0, 196, 1, 0),
			UDim2.fromOffset(x, 0),
			UIKit.Colors.panelLight,
			function()
				openCase(caseId)
			end
		)
		btn.Parent = btnRow
		x += 204
	end

	-- reel
	local reel = UIKit.create("Frame", {
		Name = "Reel",
		Size = UDim2.new(1, -20, 0, 80),
		Position = UDim2.fromOffset(10, 128),
		BackgroundColor3 = Color3.fromRGB(15, 16, 22),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = body,
	}, { UIKit.corner(8) })
	local reelLabel = UIKit.create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = UIKit.Colors.text,
		Text = "Pick a case to open!",
		Parent = reel,
	}, { UIKit.pad(8) })
	-- center pointer
	UIKit.create("Frame", {
		Size = UDim2.fromOffset(3, 80),
		Position = UDim2.new(0.5, -1, 0, 0),
		BackgroundColor3 = UIKit.Colors.accent,
		BorderSizePixel = 0,
		Parent = reel,
	})

	-- result card
	local card = UIKit.create("Frame", {
		Name = "Result",
		Size = UDim2.new(1, -20, 0, 150),
		Position = UDim2.fromOffset(10, 220),
		BackgroundColor3 = UIKit.Colors.panel,
		BorderSizePixel = 0,
		Visible = false,
		Parent = body,
	}, { UIKit.corner(10) })
	local cardStroke = UIKit.create("UIStroke", { Color = UIKit.Colors.accent, Thickness = 3, Parent = card })
	local cardName = UIKit.create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 50),
		Position = UDim2.fromOffset(10, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		Text = "",
		Parent = card,
	})
	local cardStats = UIKit.create("TextLabel", {
		Size = UDim2.new(1, -20, 0, 70),
		Position = UDim2.fromOffset(10, 58),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextColor3 = UIKit.Colors.subtext,
		Text = "",
		TextWrapped = true,
		Parent = card,
	})

	-- action buttons
	local againBtn = UIKit.button("Open Again", UDim2.new(0, 200, 0, 40), UDim2.fromOffset(10, 380), UIKit.Colors.good, function()
		openCase(lastCaseId)
	end)
	againBtn.Parent = body

	-- full-screen flash overlay (added to root so it covers everything)
	local flash = UIKit.create("Frame", {
		Name = "CaseFlash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 100,
		Visible = true,
		Parent = ctx.root,
	}) :: Frame

	local function doFlash(color: Color3)
		flash.BackgroundColor3 = color
		flash.BackgroundTransparency = 0.2
		TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	end

	function self.startSpin(caseId: string)
		spinning = true
		card.Visible = false
		local rng = Random.new()
		task.spawn(function()
			local t = 0
			while spinning and t < 2.0 do
				local id = WeaponConfig.randomOfRarity(
					({ "Common", "Uncommon", "Rare", "Epic", "Legendary" })[rng:NextInteger(1, 5)],
					rng
				)
				local info = WeaponConfig.getInfo(id)
				if info then
					reelLabel.Text = info.name
					reelLabel.TextColor3 = info.rarityColor
				end
				task.wait(0.07)
				t += 0.07
			end
		end)
	end

	-- called by UIManager when CaseResult arrives
	function self.onResult(data: any)
		local info = data.weapon
		task.delay(1.4, function()
			spinning = false
			if not info then
				return
			end
			reelLabel.Text = info.name
			reelLabel.TextColor3 = info.rarityColor
			cardName.Text = info.name .. (data.pity and "  (PITY!)" or "")
			cardName.TextColor3 = info.rarityColor
			cardStroke.Color = info.rarityColor
			cardStats.Text = ("%s • %s • DMG %d • Speed %.2f/s%s"):format(
				info.rarity, info.material, math.floor(info.damage), info.speed,
				info.hasTrail and "  ✨Trail" or ""
			)
			card.Visible = true
			doFlash(info.rarityColor)
			-- confetti for Epic+
			if RarityConfig.indexOf(info.rarity) >= RarityConfig.indexOf("Epic") then
				self.confetti(info.rarityColor)
			end
		end)
	end

	function self.confetti(color: Color3)
		for i = 1, 40 do
			local bit = UIKit.create("Frame", {
				Size = UDim2.fromOffset(8, 8),
				Position = UDim2.fromScale(0.5, 0.4),
				BackgroundColor3 = (i % 2 == 0) and color or UIKit.Colors.accent,
				BorderSizePixel = 0,
				ZIndex = 90,
				Parent = ctx.root,
			}, { UIKit.corner(4) })
			local rng = Random.new()
			local goal = UDim2.fromScale(rng:NextNumber(0, 1), rng:NextNumber(0.7, 1.1))
			TweenService:Create(bit, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { Position = goal, BackgroundTransparency = 1 }):Play()
			task.delay(1.3, function()
				bit:Destroy()
			end)
		end
	end

	function self.open()
		panel.Visible = true
	end
	function self.toggle()
		panel.Visible = not panel.Visible
	end

	return self
end

return CaseOpening
