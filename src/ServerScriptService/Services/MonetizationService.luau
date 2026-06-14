--!strict
-- MonetizationService: game passes, developer products, the receipt processor,
-- and the daily login streak. All Robux flows are server-side only.
--
-- IDs are 0 placeholders. After publishing, paste the real asset ids into the
-- PASSES / PRODUCTS tables and everything activates automatically.

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local DataService = require(script.Parent.DataService)

local MonetizationService = {}

-- Game passes -----------------------------------------------------------------
export type PassDef = { key: string, name: string, robux: number, id: number, desc: string }

MonetizationService.PASSES = {
	{ key = "coins2x", name = "2x Coins Pass", robux = 149, id = 0, desc = "Doubles all coin earnings, forever." },
	{ key = "lucky",   name = "Lucky Pass",    robux = 299, id = 0, desc = "+50% Legendary chance on every case." },
	{ key = "vip",     name = "VIP Pass",      robux = 499, id = 0, desc = "2x coins, lucky boost, VIP tag & weekly VIP case." },
} :: { PassDef }

-- Developer products ----------------------------------------------------------
export type ProductDef = { key: string, name: string, robux: number, id: number, coins: number?, badge: string?, desc: string }

MonetizationService.PRODUCTS = {
	{ key = "coins500",  name = "500 Coins",          robux = 49,  id = 0, coins = 500,  desc = "A small pouch of coins." },
	{ key = "coins1500", name = "1500 Coins",         robux = 129, id = 0, coins = 1500, badge = "BEST VALUE", desc = "Best value coin bundle." },
	{ key = "coins5000", name = "5000 Coins",         robux = 349, id = 0, coins = 5000, desc = "A hoard of coins." },
	{ key = "rankShield",name = "Instant Rank Shield",robux = 99,  id = 0, desc = "Protects against one ranked rating loss." },
} :: { ProductDef }

-- Daily streak bonuses (day -> coins). Base 50 every day.
local STREAK_BONUS = { [3] = 150, [7] = 500, [30] = 2000 }
local DAILY_BASE = 50

MonetizationService._pushHud = function(_player: Player) end

-- lookup helpers
local function productByKey(key: string): ProductDef?
	for _, p in MonetizationService.PRODUCTS do
		if p.key == key then
			return p
		end
	end
	return nil
end
local function passByKey(key: string): PassDef?
	for _, p in MonetizationService.PASSES do
		if p.key == key then
			return p
		end
	end
	return nil
end
local function productById(id: number): ProductDef?
	for _, p in MonetizationService.PRODUCTS do
		if p.id == id and id ~= 0 then
			return p
		end
	end
	return nil
end

-- Grant the effect of a developer product. Returns true on success.
local function grantProduct(player: Player, def: ProductDef): boolean
	local prof = DataService.get(player)
	if not prof then
		return false
	end
	if def.coins then
		DataService.addCoins(player, def.coins, false)
	elseif def.key == "rankShield" then
		prof.rankShieldCharges = (prof.rankShieldCharges or 0) + 1
	end
	MonetizationService._pushHud(player)
	Net.event("Notification"):FireClient(player, { text = "Purchase delivered: " .. def.name, color = Color3.fromRGB(90, 220, 120) })
	return true
end

-- Apply a game pass to a profile.
local function applyPass(player: Player, key: string)
	local prof = DataService.get(player)
	if not prof then
		return
	end
	prof.passes[key] = true
	MonetizationService._pushHud(player)
end

-- ---------------------------------------------------------------------------
-- Daily login
-- ---------------------------------------------------------------------------
local function todayString(): string
	return os.date("!%Y-%m-%d") :: string
end

local function dayDiff(a: string, b: string): number
	-- both "YYYY-MM-DD"; returns b - a in days (approx via os.time parse)
	local function toTime(s: string): number?
		local y, m, d = s:match("(%d+)-(%d+)-(%d+)")
		if not y then
			return nil
		end
		return os.time({ year = tonumber(y) :: number, month = tonumber(m) :: number, day = tonumber(d) :: number, hour = 12 })
	end
	local ta, tb = toTime(a), toTime(b)
	if not ta or not tb then
		return 99
	end
	return math.floor((tb - ta) / 86400 + 0.5)
end

function MonetizationService.processDailyLogin(player: Player)
	local prof = DataService.get(player)
	if not prof then
		return
	end
	local today = todayString()
	if prof.lastLoginDate == today then
		return -- already claimed today
	end
	local diff = prof.lastLoginDate ~= "" and dayDiff(prof.lastLoginDate, today) or 99
	if diff == 1 then
		prof.loginStreak += 1
	else
		prof.loginStreak = 1
	end
	prof.lastLoginDate = today

	local reward = DAILY_BASE + (STREAK_BONUS[prof.loginStreak] or 0)
	DataService.addCoins(player, reward, false)

	Net.event("Notification"):FireClient(player, {
		text = ("Daily reward: +%d coins (streak %d)"):format(reward, prof.loginStreak),
		color = Color3.fromRGB(255, 215, 60),
		duration = 4,
	})
	MonetizationService._pushHud(player)
end

-- ---------------------------------------------------------------------------
-- Ownership sync on join
-- ---------------------------------------------------------------------------
local function syncPasses(player: Player)
	for _, pass in MonetizationService.PASSES do
		if pass.id ~= 0 then
			task.spawn(function()
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
				end)
				if ok and owns then
					applyPass(player, pass.key)
				end
			end)
		end
	end
end

function MonetizationService.getShopInfo(player: Player)
	local prof = DataService.get(player)
	return {
		passes = MonetizationService.PASSES,
		products = MonetizationService.PRODUCTS,
		owned = prof and prof.passes or {},
		coins = prof and prof.coins or 0,
		streak = prof and prof.loginStreak or 0,
		rankShield = prof and prof.rankShieldCharges or 0,
	}
end

function MonetizationService.init()
	-- receipt processor (developer products)
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local def = productById(receiptInfo.ProductId)
		if not def then
			-- unknown product; accept to avoid infinite reprocessing
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		local ok = grantProduct(player, def)
		if ok then
			DataService.save(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- pass purchase finished
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then
			return
		end
		for _, pass in MonetizationService.PASSES do
			if pass.id == passId and passId ~= 0 then
				applyPass(player, pass.key)
				Net.event("Notification"):FireClient(player, { text = pass.name .. " activated!", color = Color3.fromRGB(120, 200, 255) })
			end
		end
	end)

	-- client buy requests -> prompt the real Robux UI
	Net.event("BuyProduct").OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" or typeof(payload.productKey) ~= "string" then
			return
		end
		local key = payload.productKey
		local prod = productByKey(key)
		local pass = passByKey(key)
		if prod then
			if prod.id ~= 0 then
				MarketplaceService:PromptProductPurchase(player, prod.id)
			else
				Net.event("Notification"):FireClient(player, { text = "This product isn't live yet (no id set).", color = Color3.fromRGB(230, 180, 60) })
			end
		elseif pass then
			if pass.id ~= 0 then
				MarketplaceService:PromptGamePassPurchase(player, pass.id)
			else
				Net.event("Notification"):FireClient(player, { text = "This pass isn't live yet (no id set).", color = Color3.fromRGB(230, 180, 60) })
			end
		end
	end)

	Net.event("ClaimDaily").OnServerEvent:Connect(function(player)
		MonetizationService.processDailyLogin(player)
	end)

	-- on load: sync passes + daily login
	DataService.onLoaded(function(player)
		syncPasses(player)
		MonetizationService.processDailyLogin(player)
	end)
end

return MonetizationService
