--!strict
-- MainHUD: collection-focused heads-up display.
--   top-left     : coins
--   top-right    : rarest Blade owned (name in rarity color) + Net Worth
--   top-center   : "Recent Legendary Pull" ticker (last 3 across the server)
--   bottom-center: currently displayed Blade name + rarity
--   bottom-right : minimap

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(script.Parent.UIKit)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local MainHUD = {}

function MainHUD.build(ctx: any)
	local root = ctx.root
	local self = {}

	-- coins (top-left)
	local coinFrame = UIKit.create("Frame", {
		Name = "Coins", Size = UDim2.fromOffset(190, 48), Position = UDim2.fromOffset(16, 16),
		BackgroundColor3 = UIKit.Colors.panel, BorderSizePixel = 0, Parent = root,
	}, { UIKit.corner(10) })
	local coinLabel = UIKit.create("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextScaled = true, TextColor3 = UIKit.Colors.accent, Text = "🪙 0", Parent = coinFrame,
	}, { UIKit.pad(8) })

	-- rarest Blade owned + Net Worth (top-right)
	local rarestFrame = UIKit.create("Frame", {
		Name = "Rarest", Size = UDim2.fromOffset(250, 56), Position = UDim2.new(1, -266, 0, 16),
		BackgroundColor3 = UIKit.Colors.panel, BorderSizePixel = 0, Parent = root,
	}, { UIKit.corner(10) })
	UIKit.create("TextLabel", {
		Size = UDim2.new(1, -12, 0, 16), Position = UDim2.fromOffset(8, 4), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UIKit.Colors.subtext, Text = "★ RAREST BLADE", Parent = rarestFrame,
	})
	local rarestLabel = UIKit.create("TextLabel", {
		Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(8, 20), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UIKit.Colors.text, Text = "—", Parent = rarestFrame,
	})
	local worthLabel = UIKit.create("TextLabel", {
		Size = UDim2.new(1, -12, 0, 14), Position = UDim2.fromOffset(8, 42), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(120, 220, 150), Text = "Net Worth: 0", Parent = rarestFrame,
	})

	-- Legendary pull ticker (top-center)
	local ticker = UIKit.create("Frame", {
		Name = "LegendaryTicker", Size = UDim2.fromOffset(420, 64), Position = UDim2.new(0.5, -210, 0, 14),
		BackgroundColor3 = UIKit.Colors.panel, BackgroundTransparency = 0.15, BorderSizePixel = 0, Parent = root,
	}, { UIKit.corner(8) })
	UIKit.create("TextLabel", {
		Size = UDim2.new(1, -8, 0, 16), Position = UDim2.fromOffset(4, 2), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.fromRGB(255, 200, 80),
		Text = "✨ RECENT LEGENDARY PULLS", Parent = ticker,
	})
	local tickerList = UIKit.create("Frame", {
		Size = UDim2.new(1, -8, 1, -20), Position = UDim2.fromOffset(4, 18), BackgroundTransparency = 1, Parent = ticker,
	}, { UIKit.create("UIListLayout", { Padding = UDim.new(0, 1) }) })
	local pulls: { any } = {}

	function self.addLegendaryPull(entry: any)
		table.insert(pulls, 1, entry)
		while #pulls > 3 do
			table.remove(pulls)
		end
		for _, c in tickerList:GetChildren() do
			if c:IsA("TextLabel") then c:Destroy() end
		end
		for _, e in pulls do
			UIKit.create("TextLabel", {
				Size = UDim2.new(1, 0, 0, 13), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				TextColor3 = e.rarityColor or Color3.fromRGB(255, 220, 120),
				Text = ("%s → %s"):format(e.player or "?", e.weapon or "?"), Parent = tickerList,
			})
		end
	end

	-- displayed Blade (bottom center)
	local weaponFrame = UIKit.create("Frame", {
		Name = "Equipped", Size = UDim2.fromOffset(320, 44), Position = UDim2.new(0.5, -160, 1, -64),
		BackgroundColor3 = UIKit.Colors.panel, BorderSizePixel = 0, Parent = root,
	}, { UIKit.corner(10) })
	local weaponLabel = UIKit.create("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextScaled = true, TextColor3 = UIKit.Colors.subtext, Text = "No Blade equipped", Parent = weaponFrame,
	}, { UIKit.pad(8) })

	-- hotkey hint strip (bottom left)
	UIKit.create("TextLabel", {
		Size = UDim2.fromOffset(440, 26), Position = UDim2.new(0, 16, 1, -34), BackgroundTransparency = 1,
		Font = Enum.Font.Gotham, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UIKit.Colors.subtext, Text = "[I] Inventory   [C] Crates   [B] Shop   [L] Leaderboard   [T] Trade",
		Parent = root,
	})

	-- minimap (bottom right)
	local mapSize = 170
	local mapFrame = UIKit.create("Frame", {
		Name = "Minimap", Size = UDim2.fromOffset(mapSize, mapSize),
		Position = UDim2.new(1, -mapSize - 16, 1, -mapSize - 16), BackgroundColor3 = Color3.fromRGB(18, 22, 28),
		BorderSizePixel = 0, ClipsDescendants = true, Parent = root,
	}, { UIKit.corner(10) })
	UIKit.create("UIStroke", { Color = UIKit.Colors.accent, Thickness = 1.5, Transparency = 0.5, Parent = mapFrame })
	local function marker(worldPos: Vector3, color: Color3)
		local span = 800
		UIKit.create("Frame", {
			Size = UDim2.fromOffset(10, 10),
			Position = UDim2.fromScale(math.clamp(worldPos.X / span + 0.5, 0, 1), math.clamp(worldPos.Z / span + 0.5, 0, 1)),
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, BorderSizePixel = 0, Parent = mapFrame,
		}, { UIKit.corner(5) })
	end
	marker(WorldConfig.Hub.center, Color3.fromRGB(120, 200, 255))
	marker(WorldConfig.CaseArea.center, Color3.fromRGB(180, 80, 255))
	marker(WorldConfig.Casual.center, Color3.fromRGB(255, 140, 40))
	marker(WorldConfig.Trading.center, Color3.fromRGB(60, 220, 160))
	local playerDot = UIKit.create("Frame", {
		Name = "Player", Size = UDim2.fromOffset(8, 8), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, Parent = mapFrame,
	}, { UIKit.corner(4) })
	RunService.RenderStepped:Connect(function()
		local char = Players.LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local span = 800
			playerDot.Position = UDim2.fromScale(math.clamp(hrp.Position.X / span + 0.5, 0, 1), math.clamp(hrp.Position.Z / span + 0.5, 0, 1))
		end
	end)

	function self.update(data: any)
		if data.coins then
			coinLabel.Text = "🪙 " .. tostring(data.coins)
		end
		if data.rarest then
			rarestLabel.Text = data.rarest.name
			rarestLabel.TextColor3 = data.rarest.rarityColor or UIKit.Colors.text
		else
			rarestLabel.Text = "—"
			rarestLabel.TextColor3 = UIKit.Colors.subtext
		end
		if data.netWorth ~= nil then
			worthLabel.Text = "Net Worth: " .. tostring(math.floor(data.netWorth))
		end
		if data.equipped then
			weaponLabel.Text = data.equipped.name .. (data.equipped.value and ("  ⬩ " .. tostring(data.equipped.value)) or "")
			weaponLabel.TextColor3 = data.equipped.rarityColor or UIKit.Colors.text
		else
			weaponLabel.Text = "No Blade equipped"
			weaponLabel.TextColor3 = UIKit.Colors.subtext
		end
	end

	return self
end

return MainHUD
