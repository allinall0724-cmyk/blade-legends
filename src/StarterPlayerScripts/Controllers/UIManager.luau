--!strict
-- UIManager: builds every screen, owns the single ScreenGui, and routes all
-- server remotes to the right screen. Also renders transient UI: notifications,
-- the announcement banner, the kill feed and recent-pull toasts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local RankConfig = require(ReplicatedStorage.Shared.RankConfig)

local SoundController = require(script.Parent.SoundController)

local uiFolder = script.Parent.Parent.UI
local UIKit = require(uiFolder.UIKit)
local MainHUD = require(uiFolder.MainHUD)
local Inventory = require(uiFolder.Inventory)
local CaseOpening = require(uiFolder.CaseOpening)
local Shop = require(uiFolder.Shop)
local Leaderboard = require(uiFolder.Leaderboard)
local RankedQueue = require(uiFolder.RankedQueue)
local Trade = require(uiFolder.Trade)
local AbilityBar = require(uiFolder.AbilityBar)
local LoadingScreen = require(uiFolder.LoadingScreen)
local Settings = require(uiFolder.Settings)

local UIManager = {}

local screens: { [string]: any } = {}

function UIManager.init()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "BladeLegends"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	-- intro loading screen
	LoadingScreen.show()

	local ctx = {
		root = gui,
		event = Net.event,
		func = Net.func,
		-- shared client state read by several screens
		state = { inCombat = false, equippedId = nil :: number? },
		sound = SoundController,
		offerToTrade = function(weaponId: number)
			if screens.trade then
				screens.trade.offer(weaponId)
			end
		end,
	}
	UIManager.ctx = ctx

	-- build screens — each isolated so one failing screen can't abort the rest
	local function buildScreen(name: string, mod: any)
		local ok, s = pcall(mod.build, ctx)
		if ok then
			screens[name] = s
		else
			warn(("[Blade Legends] screen '%s' build failed: %s"):format(name, tostring(s)))
		end
	end
	buildScreen("hud", MainHUD)
	buildScreen("inventory", Inventory)
	buildScreen("cases", CaseOpening)
	buildScreen("shop", Shop)
	buildScreen("leaderboard", Leaderboard)
	buildScreen("ranked", RankedQueue)
	buildScreen("trade", Trade)
	buildScreen("abilities", AbilityBar)
	buildScreen("settings", Settings)

	-- ===== transient UI =====
	-- notifications (stack, bottom-left above hotkey strip)
	local notifHolder = UIKit.create("Frame", {
		Size = UDim2.fromOffset(360, 300),
		Position = UDim2.new(0, 16, 1, -340),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local notifLayout = UIKit.create("UIListLayout", {
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 4),
		Parent = notifHolder,
	})
	local function notify(payload: any)
		local toast = UIKit.create("TextLabel", {
			Size = UDim2.new(1, 0, 0, payload.small and 24 or 34),
			BackgroundColor3 = UIKit.Colors.panel,
			BackgroundTransparency = 0.1,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextColor3 = payload.color or UIKit.Colors.text,
			Text = tostring(payload.text or ""),
			Parent = notifHolder,
		}, { UIKit.corner(6), UIKit.pad(4) })
		task.delay(payload.duration or 2.5, function()
			TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			task.wait(0.4)
			toast:Destroy()
		end)
	end
	-- let screens raise their own toasts
	ctx.notify = function(text: string, color: Color3?)
		notify({ text = text, color = color or UIKit.Colors.bad, duration = 2.5 })
	end

	-- announcement banner (top center)
	local banner = UIKit.create("TextLabel", {
		Size = UDim2.new(0, 720, 0, 50),
		Position = UDim2.new(0.5, -360, 0, -60),
		AnchorPoint = Vector2.new(0, 0),
		BackgroundColor3 = UIKit.Colors.bg,
		BackgroundTransparency = 0.1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = UIKit.Colors.accent,
		Text = "",
		Visible = false,
		Parent = gui,
	}, { UIKit.corner(10), UIKit.pad(8) })
	local function announce(payload: any)
		banner.Text = tostring(payload.text or "")
		banner.TextColor3 = payload.color or UIKit.Colors.accent
		banner.Visible = true
		banner.Position = UDim2.new(0.5, -360, 0, -60)
		TweenService:Create(banner, TweenInfo.new(0.5), { Position = UDim2.new(0.5, -360, 0, 12) }):Play()
		task.delay(4.5, function()
			TweenService:Create(banner, TweenInfo.new(0.5), { Position = UDim2.new(0.5, -360, 0, -60) }):Play()
			task.wait(0.5)
			banner.Visible = false
		end)
	end

	-- kill feed (top right, below rank)
	local killHolder = UIKit.create("Frame", {
		Size = UDim2.fromOffset(280, 200),
		Position = UDim2.new(1, -296, 0, 76),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIKit.create("UIListLayout", { Padding = UDim.new(0, 3), Parent = killHolder })
	local function killFeed(payload: any)
		local row = UIKit.create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = UIKit.Colors.panel,
			BackgroundTransparency = 0.2,
			Font = Enum.Font.GothamMedium,
			TextScaled = true,
			TextColor3 = UIKit.Colors.text,
			Text = ("%s 🗡 %s"):format(payload.killer or "?", payload.victim or "?"),
			Parent = killHolder,
		}, { UIKit.corner(5), UIKit.pad(3) })
		task.delay(5, function()
			row:Destroy()
		end)
	end

	-- ===== remote routing =====
	local welcomed = false
	local prevEquippedId: number? = nil
	local prevTierMin = -1
	Net.event("UpdateHUD").OnClientEvent:Connect(function(data)
		screens.hud.update(data)
		screens.ranked.updateRank(data)

		-- equip sound when the equipped weapon changes
		local newId = data.equipped and data.equipped.id or nil
		if newId and newId ~= prevEquippedId and prevEquippedId ~= nil then
			SoundController.play("equip", 0.7)
		end
		prevEquippedId = newId

		-- rank-up detection: tier jumped up
		if data.rating then
			local tier = RankConfig.getTier(data.rating)
			if prevTierMin >= 0 and tier.min > prevTierMin then
				SoundController.play("rankUp")
				announce({ text = "RANK UP! You reached " .. tier.name, color = tier.color })
			end
			prevTierMin = tier.min
		end

		-- update shared state for the inventory (equipped badge + combat lock)
		ctx.state.equippedId = newId
		if data.inCasual ~= nil then
			ctx.state.inCombat = data.inCasual == true
		end
		if screens.inventory and screens.inventory.onHud then
			screens.inventory.onHud(data)
		end
		if screens.abilities and screens.abilities.onHud then
			screens.abilities.onHud(data)
		end

		-- one-time welcome message
		if not welcomed then
			welcomed = true
			task.delay(3.2, function()
				announce({
					text = "Welcome to Blade Legends! Open cases, fight in arenas, climb the leaderboard!",
					color = UIKit.Colors.accent,
				})
			end)
		end
	end)
	Net.event("Notification").OnClientEvent:Connect(notify)
	Net.event("Announcement").OnClientEvent:Connect(announce)
	Net.event("KillFeed").OnClientEvent:Connect(killFeed)
	Net.event("CaseResult").OnClientEvent:Connect(function(data)
		SoundController.play("caseOpen", 0.7)
		screens.cases.open()
		screens.cases.onResult(data)
		-- a new weapon arrived: refresh the inventory grid so it shows up
		if screens.inventory and screens.inventory.refresh then
			task.delay(0.2, screens.inventory.refresh)
		end
	end)
	Net.event("RecentPull").OnClientEvent:Connect(function(data)
		notify({ text = ("%s pulled %s"):format(data.player, data.weapon), color = data.rarityColor, duration = 3, small = true })
		-- feed Legendary+ pulls into the top-center HUD ticker
		if (data.rarity == "Legendary" or data.rarity == "Mythic") and screens.hud and screens.hud.addLegendaryPull then
			screens.hud.addLegendaryPull(data)
		end
	end)
	Net.event("LeaderboardUpdate").OnClientEvent:Connect(function(data)
		screens.leaderboard.update(data)
	end)
	Net.event("MatchState").OnClientEvent:Connect(function(data)
		screens.ranked.onMatchState(data)
		screens.ranked.panel.Visible = true
		-- ranked combat lock for the inventory
		if data.ended then
			ctx.state.inCombat = false
		elseif data.active ~= nil then
			ctx.state.inCombat = data.active == true
		end
	end)
	Net.event("TradeAction").OnClientEvent:Connect(function(data)
		screens.trade.onAction(data)
	end)
	Net.event("AbilityState").OnClientEvent:Connect(function(data)
		screens.abilities.onAbilityState(data)
	end)
	Net.event("AbilityFlash").OnClientEvent:Connect(function(data)
		screens.abilities.onFlash(data)
	end)

	-- conversion / promo popups (starter pack, low-coin, streak saver, etc.)
	Net.event("PromoPopup").OnClientEvent:Connect(function(data)
		if typeof(data) ~= "table" then
			return
		end
		local pop = UIKit.create("Frame", {
			Size = UDim2.fromOffset(420, 200),
			Position = UDim2.new(0.5, -210, 0.5, -100),
			BackgroundColor3 = UIKit.Colors.bg,
			BorderSizePixel = 0,
			ZIndex = 60,
			Parent = gui,
		}, { UIKit.corner(12), UIKit.create("UIStroke", { Color = data.color or UIKit.Colors.accent, Thickness = 2.5 }) })
		UIKit.create("TextLabel", {
			Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 10), BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold, TextScaled = true, TextWrapped = true, ZIndex = 61,
			TextColor3 = data.color or UIKit.Colors.accent, Text = tostring(data.title or "Offer"), Parent = pop,
		})
		UIKit.create("TextLabel", {
			Size = UDim2.new(1, -20, 0, 70), Position = UDim2.fromOffset(10, 58), BackgroundTransparency = 1,
			Font = Enum.Font.Gotham, TextSize = 16, TextWrapped = true, ZIndex = 61,
			TextColor3 = UIKit.Colors.text, Text = tostring(data.body or ""), Parent = pop,
		})
		if data.productKey then
			local buy = UIKit.button(("Get it — R$ %s"):format(tostring(data.robux or "")), UDim2.new(0.6, -14, 0, 44), UDim2.new(0, 10, 1, -54), UIKit.Colors.good, function()
				Net.event("BuyProduct"):FireServer({ productKey = data.productKey })
				pop:Destroy()
			end)
			buy.ZIndex = 61
			buy.Parent = pop
		end
		local close = UIKit.button("No thanks", UDim2.new(0.4, -14, 0, 44), UDim2.new(0.6, 4, 1, -54), UIKit.Colors.panelLight, function()
			pop:Destroy()
		end)
		close.ZIndex = 61
		close.Parent = pop
		task.delay(20, function()
			if pop and pop.Parent then
				pop:Destroy()
			end
		end)
	end)

	-- kill popup ("+1 Kill — +N Coins")
	Net.event("KillNotify").OnClientEvent:Connect(function(data)
		SoundController.play("kill", 0.8)
		local txt = "+1 Kill"
		if data and data.coins then
			txt ..= ("  —  +%d Coins"):format(data.coins)
		end
		local pop = UIKit.create("TextLabel", {
			Size = UDim2.fromOffset(360, 50),
			Position = UDim2.new(0.5, -180, 0.32, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextScaled = true,
			TextColor3 = Color3.fromRGB(255, 230, 120),
			TextStrokeTransparency = 0.3,
			Text = txt,
			Parent = gui,
		})
		TweenService:Create(pop, TweenInfo.new(1.2), { Position = UDim2.new(0.5, -180, 0.24, 0), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(1.3, function()
			pop:Destroy()
		end)
	end)

	-- combo counter ("COMBO xN!")
	local comboLabel = UIKit.create("TextLabel", {
		Size = UDim2.fromOffset(300, 56),
		Position = UDim2.new(0.5, -150, 0.18, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 120, 90),
		TextStrokeTransparency = 0.3,
		TextTransparency = 1,
		Text = "",
		Parent = gui,
	})
	Net.event("ComboUpdate").OnClientEvent:Connect(function(data)
		local count = data and data.count or 0
		if count >= 3 then
			comboLabel.Text = ("COMBO x%d!"):format(count)
			comboLabel.TextTransparency = 0
			comboLabel.TextStrokeTransparency = 0.3
			TweenService:Create(comboLabel, TweenInfo.new(1.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)

	-- ask the server for an initial HUD snapshot
	task.defer(function()
		Net.event("RequestData"):FireServer()
	end)

	UIManager.screens = screens
end

-- used by InputHandler
function UIManager.toggle(name: string)
	local s = screens[name]
	if s and s.toggle then
		s.toggle()
	else
		warn(("[Blade Legends] toggle('%s') — screen missing or has no toggle()"):format(name))
	end
end

return UIManager
