--!strict
-- MainHUD: always-on heads-up display.
--   top-left    : coins
--   top-right   : rank badge + rating
--   bottom-center: equipped weapon (name in rarity color)
--   bottom-right : minimap with a live player dot

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(script.Parent.UIKit)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local MainHUD = {}

function MainHUD.build(ctx: any)
	local root = ctx.root
	local self = {}

	-- coins
	local coinFrame = UIKit.create("Frame", {
		Name = "Coins",
		Size = UDim2.fromOffset(190, 48),
		Position = UDim2.fromOffset(16, 16),
		BackgroundColor3 = UIKit.Colors.panel,
		BorderSizePixel = 0,
		Parent = root,
	}, { UIKit.corner(10) })
	local coinLabel = UIKit.create("TextLabel", {
		Name = "Label",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = UIKit.Colors.accent,
		Text = "🪙 0",
		Parent = coinFrame,
	}, { UIKit.pad(8) })

	-- rank badge
	local rankFrame = UIKit.create("Frame", {
		Name = "Rank",
		Size = UDim2.fromOffset(210, 48),
		Position = UDim2.new(1, -226, 0, 16),
		BackgroundColor3 = UIKit.Colors.panel,
		BorderSizePixel = 0,
		Parent = root,
	}, { UIKit.corner(10) })
	local rankLabel = UIKit.create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(180, 130, 70),
		Text = "Bronze • 0",
		Parent = rankFrame,
	}, { UIKit.pad(8) })

	-- equipped weapon (bottom center)
	local weaponFrame = UIKit.create("Frame", {
		Name = "Equipped",
		Size = UDim2.fromOffset(320, 44),
		Position = UDim2.new(0.5, -160, 1, -64),
		BackgroundColor3 = UIKit.Colors.panel,
		BorderSizePixel = 0,
		Parent = root,
	}, { UIKit.corner(10) })
	local weaponLabel = UIKit.create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = UIKit.Colors.subtext,
		Text = "Unarmed",
		Parent = weaponFrame,
	}, { UIKit.pad(8) })

	-- hotkey hint strip (bottom left)
	UIKit.create("TextLabel", {
		Size = UDim2.fromOffset(420, 26),
		Position = UDim2.new(0, 16, 1, -34),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UIKit.Colors.subtext,
		Text = "[I] Inventory   [B] Shop   [L] Leaderboard   [C] Cases",
		Parent = root,
	})

	-- minimap (bottom right)
	local mapSize = 170
	local mapFrame = UIKit.create("Frame", {
		Name = "Minimap",
		Size = UDim2.fromOffset(mapSize, mapSize),
		Position = UDim2.new(1, -mapSize - 16, 1, -mapSize - 16),
		BackgroundColor3 = Color3.fromRGB(18, 22, 28),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = root,
	}, { UIKit.corner(10) })
	UIKit.create("UIStroke", { Color = UIKit.Colors.accent, Thickness = 1.5, Transparency = 0.5, Parent = mapFrame })
	-- zone markers
	local function marker(name: string, worldPos: Vector3, color: Color3)
		local span = 800 -- world studs mapped to map
		local mx = (worldPos.X / span + 0.5)
		local mz = (worldPos.Z / span + 0.5)
		UIKit.create("Frame", {
			Size = UDim2.fromOffset(10, 10),
			Position = UDim2.fromScale(math.clamp(mx, 0, 1), math.clamp(mz, 0, 1)),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Parent = mapFrame,
		}, { UIKit.corner(5) })
	end
	marker("Hub", WorldConfig.Hub.center, Color3.fromRGB(120, 200, 255))
	marker("Case", WorldConfig.CaseArea.center, Color3.fromRGB(180, 80, 255))
	marker("Casual", WorldConfig.Casual.center, Color3.fromRGB(255, 140, 40))
	marker("Ranked", WorldConfig.Ranked.center, Color3.fromRGB(255, 60, 70))
	marker("Trade", WorldConfig.Trading.center, Color3.fromRGB(60, 220, 160))
	local playerDot = UIKit.create("Frame", {
		Name = "Player",
		Size = UDim2.fromOffset(8, 8),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Parent = mapFrame,
	}, { UIKit.corner(4) })

	RunService.RenderStepped:Connect(function()
		local char = Players.LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local span = 800
			local mx = (hrp.Position.X / span + 0.5)
			local mz = (hrp.Position.Z / span + 0.5)
			playerDot.Position = UDim2.fromScale(math.clamp(mx, 0, 1), math.clamp(mz, 0, 1))
		end
	end)

	function self.update(data: any)
		if data.coins then
			coinLabel.Text = "🪙 " .. tostring(data.coins)
		end
		if data.tier then
			rankLabel.Text = ("🛡 %s • %d"):format(data.tier, math.floor(data.rating or 0))
			if data.tierColor then
				rankLabel.TextColor3 = data.tierColor
			end
		end
		if data.equipped then
			weaponLabel.Text = data.equipped.name
			weaponLabel.TextColor3 = data.equipped.rarityColor or UIKit.Colors.text
		else
			weaponLabel.Text = "Unarmed"
			weaponLabel.TextColor3 = UIKit.Colors.subtext
		end
	end

	return self
end

return MainHUD
