--!strict
-- MonetizationService: the full three-tier Robux economy — six game passes, the
-- developer-product catalogue (coins / cases / rank / cosmetics / bundles), the
-- receipt processor, chat tags, and the conversion-psychology systems
-- (first-purchase bonus, daily deal, low-coin alert, streak saver, VIP spotlight,
-- starter-pack popup).
--
-- All ids are 0 placeholders — paste real asset ids into PASSES/PRODUCTS after
-- publishing and everything activates automatically. Robux discounts cannot be
-- applied at runtime, so the Daily Deal instead grants +30% bonus value when its
-- featured product is purchased (documented in the shop UI).

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local DataService = require(script.Parent.DataService)
local CaseService = require(script.Parent.CaseService)

local MonetizationService = {}

local rng = Random.new()

-- 10 selectable name-tag colors (idx 1..10; 0 = default white)
MonetizationService.NameColors = {
	Color3.fromRGB(255, 255, 255), Color3.fromRGB(235, 70, 70), Color3.fromRGB(245, 150, 50),
	Color3.fromRGB(245, 220, 70), Color3.fromRGB(90, 220, 120), Color3.fromRGB(70, 220, 230),
	Color3.fromRGB(80, 140, 255), Color3.fromRGB(175, 90, 255), Color3.fromRGB(255, 120, 200),
	Color3.fromRGB(255, 200, 90),
}

local GOLD = Color3.fromRGB(255, 200, 70)

-- ===========================================================================
-- Game passes (six)
-- ===========================================================================
export type PassDef = {
	key: string, name: string, robux: number, id: number,
	tag: string, tagColor: Color3, animatedTag: boolean?, benefits: { string },
}

MonetizationService.PASSES = {
	{ key = "starter", name = "Starter Pack", robux = 149, id = 0, tag = "New Blade", tagColor = Color3.fromRGB(120, 220, 255),
		benefits = { "2x coins for 7 days", "+500 bonus coins now", "3 free Pro Cases", "New Blade chat tag (7 days)" } },
	{ key = "speedDemon", name = "Speed Demon Pass", robux = 199, id = 0, tag = "Swift", tagColor = Color3.fromRGB(120, 200, 255),
		benefits = { "+25% movement speed (permanent)", "+10% dodge speed", "Speed trail effect", "Swift chat tag" } },
	{ key = "coinMagnet", name = "Coin Magnet Pass", robux = 249, id = 0, tag = "Rich", tagColor = GOLD,
		benefits = { "Permanent 2x coin earnings", "Coins float toward you", "Rich chat tag" } },
	{ key = "lucky", name = "Lucky Pass", robux = 299, id = 0, tag = "Lucky", tagColor = Color3.fromRGB(90, 220, 120),
		benefits = { "+50% Legendary chance (all cases)", "Gold sparkle on case screen", "Lucky chat tag" } },
	{ key = "vip", name = "VIP Pass", robux = 799, id = 0, tag = "VIP", tagColor = GOLD, animatedTag = true,
		benefits = { "Coin Magnet + Lucky combined", "+35% movement speed", "Weekly VIP case (7 Rare+)", "VIP lounge access", "Animated VIP tag", "Priority ranked matchmaking" } },
	{ key = "mythicHunter", name = "Mythic Hunter Pass", robux = 999, id = 0, tag = "Mythic Hunter", tagColor = Color3.fromRGB(255, 80, 70), animatedTag = true,
		benefits = { "Permanent 3x coins", "+50% Mythic chance", "Free Mythic weapon now", "Permanent animated aura", "Secret Mythic-only case", "Mythic Hunter chat tag" } },
} :: { PassDef }

-- ===========================================================================
-- Developer products (repeat purchase). `effect` drives grantProduct.
-- category: coins | cases | rank | cosmetic | bundle
-- ===========================================================================
export type ProductDef = {
	key: string, name: string, robux: number, id: number, category: string,
	badge: string?, desc: string, effect: { [string]: any },
}

-- case-grant ids are remapped to the 10-case system in Part 3.
MonetizationService.PRODUCTS = {
	-- Quick Coins
	{ key = "coins300", category = "coins", name = "300 Coins", robux = 39, id = 0, desc = "A small pouch of coins.", effect = { coins = 300 } },
	{ key = "coins1000", category = "coins", name = "1000 Coins", robux = 99, id = 0, badge = "BEST VALUE", desc = "Best value coin bundle.", effect = { coins = 1000 } },
	{ key = "coins3500", category = "coins", name = "3500 Coins", robux = 299, id = 0, desc = "A big stack of coins.", effect = { coins = 3500 } },
	{ key = "coins10000", category = "coins", name = "10000 Coins", robux = 749, id = 0, badge = "WHALE DEAL", desc = "A mountain of coins.", effect = { coins = 10000 } },
	-- Case Bundles
	{ key = "case5basic", category = "cases", name = "5 Basic Cases", robux = 49, id = 0, desc = "Five Basic cases.", effect = { cases = { { id = "Basic", n = 5 } } } },
	{ key = "case3pro", category = "cases", name = "3 Pro Cases", robux = 99, id = 0, desc = "Three Pro cases.", effect = { cases = { { id = "Pro", n = 3 } } } },
	{ key = "case1mythic", category = "cases", name = "1 Mythic Case", robux = 149, id = 0, desc = "One Mythic case.", effect = { cases = { { id = "Mythic", n = 1 } } } },
	-- Rank
	{ key = "rankShield", category = "rank", name = "Rank Shield", robux = 99, id = 0, desc = "Protect against one ranked rating loss.", effect = { rank = "shield" } },
	{ key = "rankBoost", category = "rank", name = "Rank Boost", robux = 199, id = 0, desc = "+50 bonus rating on your next ranked win.", effect = { rank = "boost" } },
	{ key = "instantSilver", category = "rank", name = "Instant Bronze→Silver", robux = 299, id = 0, desc = "Skip to 1000 rating (only under 1000).", effect = { rank = "silver" } },
	-- Cosmetic
	{ key = "randomLegendary", category = "cosmetic", name = "Random Legendary Weapon", robux = 199, id = 0, desc = "A guaranteed random Legendary.", effect = { weapon = "Legendary" } },
	{ key = "randomMythic", category = "cosmetic", name = "Random Mythic Weapon", robux = 499, id = 0, desc = "A guaranteed random Mythic.", effect = { weapon = "Mythic" } },
	{ key = "nameColor", category = "cosmetic", name = "Custom Name Color", robux = 149, id = 0, desc = "Pick from 10 name-tag colors.", effect = { nameColor = true } },
	-- Bundles
	{ key = "megaBundle", category = "bundle", name = "Mega Bundle", robux = 299, id = 0, badge = "SAVE 96 R$", desc = "10 Basic + 5 Pro + 2 Mythic cases.", effect = { cases = { { id = "Basic", n = 10 }, { id = "Pro", n = 5 }, { id = "Mythic", n = 2 } } } },
} :: { ProductDef }

local STREAK_BONUS = { [3] = 150, [7] = 500, [30] = 2000 }
local DAILY_BASE = 50
local STARTER_DAYS = 7

MonetizationService._pushHud = function(_player: Player) end

-- ===========================================================================
-- lookups
-- ===========================================================================
local function productByKey(key: string): ProductDef?
	for _, p in MonetizationService.PRODUCTS do
		if p.key == key then return p end
	end
	return nil
end
local function passByKey(key: string): PassDef?
	for _, p in MonetizationService.PASSES do
		if p.key == key then return p end
	end
	return nil
end
local function productById(id: number): ProductDef?
	for _, p in MonetizationService.PRODUCTS do
		if p.id == id and id ~= 0 then return p end
	end
	return nil
end

-- ===========================================================================
-- chat tag / name color
-- ===========================================================================
local function refreshTag(player: Player)
	local prof = DataService.get(player)
	if not prof then return end
	-- highest-priority owned tag
	local order = { "mythicHunter", "vip", "lucky", "coinMagnet", "speedDemon", "starter" }
	local chosen: PassDef? = nil
	for _, key in order do
		if prof.passes[key] then
			-- starter tag expires after 7 days
			if key == "starter" and (prof.starterExpiry or 0) < os.time() then
				continue
			end
			chosen = passByKey(key)
			break
		end
	end
	if chosen then
		player:SetAttribute("ChatTag", chosen.tag)
		player:SetAttribute("TagColor", chosen.tagColor)
		player:SetAttribute("TagAnimated", chosen.animatedTag == true)
	else
		player:SetAttribute("ChatTag", "")
	end
	player:SetAttribute("NameColorIdx", prof.nameColorIdx or 0)
	local idx = prof.nameColorIdx or 0
	player:SetAttribute("NameColor", (idx >= 1 and MonetizationService.NameColors[idx]) or Color3.fromRGB(255, 255, 255))
end
MonetizationService.refreshTag = refreshTag

-- ===========================================================================
-- conversion-psychology helpers
-- ===========================================================================
local function maybeFirstPurchase(player: Player)
	local prof = DataService.get(player)
	if not prof or prof.firstPurchaseDone then return end
	prof.firstPurchaseDone = true
	-- silent 10% goodwill bonus based on current coins (min 200)
	local bonus = math.max(200, math.floor(prof.coins * 0.1))
	DataService.addCoins(player, bonus, false)
end

-- Daily deal: one product at "30% off" (granted as +30% value). Refreshes at UTC midnight.
local dailyDeal = { key = "", dayKey = "" }
local function refreshDailyDeal()
	local dayKey = os.date("!%Y-%m-%d") :: string
	if dailyDeal.dayKey == dayKey and dailyDeal.key ~= "" then return end
	dailyDeal.dayKey = dayKey
	dailyDeal.key = MonetizationService.PRODUCTS[rng:NextInteger(1, #MonetizationService.PRODUCTS)].key
end

function MonetizationService.lowCoinAlert(player: Player, needed: number, currentCoins: number)
	-- pick the smallest coin product that covers the shortfall
	local best: ProductDef? = nil
	for _, p in MonetizationService.PRODUCTS do
		if p.effect.coins and (currentCoins + p.effect.coins) >= needed then
			if not best or p.robux < (best :: ProductDef).robux then
				best = p
			end
		end
	end
	best = best or productByKey("coins10000")
	if best then
		Net.event("PromoPopup"):FireClient(player, {
			kind = "lowcoin", title = "Need more coins?",
			body = ("You're short for that case. Grab %s to get there!"):format(best.name),
			productKey = best.key, robux = best.robux, color = GOLD,
		})
	end
end

function MonetizationService.streakSaver(player: Player)
	local prof = DataService.get(player)
	if not prof or (prof.loginStreak or 0) < 7 then return end
	Net.event("PromoPopup"):FireClient(player, {
		kind = "streak", title = "Protect your streak!",
		body = ("You're on a %d-day streak. A Rank Shield keeps your rating safe."):format(prof.loginStreak),
		productKey = "rankShield", robux = 99, color = Color3.fromRGB(120, 200, 255),
	})
end

local vipSpotlightDone: { [number]: boolean } = {}
function MonetizationService.vipSpotlight(player: Player, weaponName: string)
	local prof = DataService.get(player)
	if not prof or not prof.passes.vip then return end
	if vipSpotlightDone[player.UserId] then return end
	vipSpotlightDone[player.UserId] = true
	Net.event("Announcement"):FireAllClients({
		text = ("⭐ VIP %s just pulled a Legendary %s! ⭐"):format(player.DisplayName, weaponName),
		color = GOLD,
	})
end

-- ===========================================================================
-- grant effects
-- ===========================================================================
local function grantWeaponOfRarity(player: Player, rarity: string)
	local id = WeaponConfig.randomOfRarity(rarity, rng)
	DataService.addWeapon(player, id)
	local info = WeaponConfig.getInfo(id)
	Net.event("Notification"):FireClient(player, { text = "Received: " .. (info and info.name or rarity), color = info and info.rarityColor or GOLD })
end

local function grantProduct(player: Player, def: ProductDef): boolean
	local prof = DataService.get(player)
	if not prof then return false end
	local bonusMult = (def.key == dailyDeal.key) and 1.3 or 1 -- daily-deal +30% value

	local e = def.effect
	if e.coins then
		DataService.addCoins(player, math.floor(e.coins * bonusMult), false)
	end
	if e.cases then
		for _, c in e.cases do
			CaseService.grant(player, c.id, math.floor(c.n * bonusMult))
		end
	end
	if e.rank == "shield" then
		prof.rankShieldCharges = (prof.rankShieldCharges or 0) + 1
	elseif e.rank == "boost" then
		prof.rankBoostPending = true
	elseif e.rank == "silver" then
		if prof.rankRating < 1000 then
			prof.rankRating = 1000
		end
	end
	if e.weapon then
		grantWeaponOfRarity(player, e.weapon)
	end
	if e.nameColor then
		prof.nameColorOwned = true
		if prof.nameColorIdx == 0 then
			prof.nameColorIdx = 1
		end
	end

	maybeFirstPurchase(player)
	refreshTag(player)
	MonetizationService._pushHud(player)
	Net.event("Notification"):FireClient(player, { text = "Purchase delivered: " .. def.name, color = Color3.fromRGB(90, 220, 120) })
	return true
end

local function applyPass(player: Player, key: string, isFreshPurchase: boolean?)
	local prof = DataService.get(player)
	if not prof then return end
	prof.passes[key] = true

	if isFreshPurchase then
		if key == "starter" then
			prof.starterExpiry = os.time() + STARTER_DAYS * 86400
			DataService.addCoins(player, 500, false)
			CaseService.grant(player, "Pro", 3)
		elseif key == "mythicHunter" and not prof.mythicHunterGranted then
			prof.mythicHunterGranted = true
			grantWeaponOfRarity(player, "Mythic")
		end
		maybeFirstPurchase(player)
	end

	refreshTag(player)
	MonetizationService._pushHud(player)
end
MonetizationService.applyPass = applyPass

-- ===========================================================================
-- daily login
-- ===========================================================================
local function todayString(): string
	return os.date("!%Y-%m-%d") :: string
end
local function dayDiff(a: string, b: string): number
	local function toTime(s: string): number?
		local y, m, d = s:match("(%d+)-(%d+)-(%d+)")
		if not y then return nil end
		return os.time({ year = tonumber(y) :: number, month = tonumber(m) :: number, day = tonumber(d) :: number, hour = 12 })
	end
	local ta, tb = toTime(a), toTime(b)
	if not ta or not tb then return 99 end
	return math.floor((tb - ta) / 86400 + 0.5)
end

function MonetizationService.processDailyLogin(player: Player)
	local prof = DataService.get(player)
	if not prof then return end
	local today = todayString()
	if prof.lastLoginDate == today then return end
	local diff = prof.lastLoginDate ~= "" and dayDiff(prof.lastLoginDate, today) or 99
	if diff == 1 then prof.loginStreak += 1 else prof.loginStreak = 1 end
	prof.lastLoginDate = today
	local reward = DAILY_BASE + (STREAK_BONUS[prof.loginStreak] or 0)
	DataService.addCoins(player, reward, false)
	Net.event("Notification"):FireClient(player, {
		text = ("Daily reward: +%d coins (streak %d)"):format(reward, prof.loginStreak),
		color = GOLD, duration = 4,
	})
	MonetizationService._pushHud(player)
end

-- ===========================================================================
-- ownership sync + shop info
-- ===========================================================================
local function syncPasses(player: Player)
	for _, pass in MonetizationService.PASSES do
		if pass.id ~= 0 then
			task.spawn(function()
				local ok, owns = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
				end)
				if ok and owns then
					applyPass(player, pass.key, false)
				end
			end)
		end
	end
end

function MonetizationService.getShopInfo(player: Player)
	refreshDailyDeal()
	local prof = DataService.get(player)
	return {
		passes = MonetizationService.PASSES,
		products = MonetizationService.PRODUCTS,
		owned = prof and prof.passes or {},
		coins = prof and prof.coins or 0,
		streak = prof and prof.loginStreak or 0,
		rankShield = prof and prof.rankShieldCharges or 0,
		dailyDealKey = dailyDeal.key,
		nameColors = MonetizationService.NameColors,
		nameColorOwned = prof and prof.nameColorOwned or false,
		nameColorIdx = prof and prof.nameColorIdx or 0,
		starterExpiry = prof and prof.starterExpiry or 0,
	}
end

-- ===========================================================================
function MonetizationService.init()
	refreshDailyDeal()

	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		local def = productById(receiptInfo.ProductId)
		if not def then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if grantProduct(player, def) then
			DataService.save(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		if not wasPurchased then return end
		for _, pass in MonetizationService.PASSES do
			if pass.id == passId and passId ~= 0 then
				applyPass(player, pass.key, true)
				Net.event("Notification"):FireClient(player, { text = pass.name .. " activated!", color = Color3.fromRGB(120, 200, 255) })
			end
		end
	end)

	Net.event("BuyProduct").OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" or typeof(payload.productKey) ~= "string" then return end
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

	Net.event("PickNameColor").OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then return end
		local idx = payload.idx
		local prof = DataService.get(player)
		if prof and prof.nameColorOwned and typeof(idx) == "number" and idx >= 1 and idx <= #MonetizationService.NameColors then
			prof.nameColorIdx = math.floor(idx)
			refreshTag(player)
			MonetizationService._pushHud(player)
		end
	end)

	Net.event("ClaimDaily").OnServerEvent:Connect(function(player)
		MonetizationService.processDailyLogin(player)
	end)

	DataService.onLoaded(function(player)
		syncPasses(player)
		MonetizationService.processDailyLogin(player)
		refreshTag(player)
		-- starter-pack popup once, within the first 10 minutes, if not owned
		task.delay(35, function()
			local prof = DataService.get(player)
			if player.Parent and prof and not prof.passes.starter and (os.time() - (prof.joinTime or 0)) < 600 then
				local p = passByKey("starter")
				Net.event("PromoPopup"):FireClient(player, {
					kind = "starter", title = "Starter Pack — Best Value for New Blades!",
					body = "2x coins (7d) + 500 coins + 3 Pro Cases + chat tag.",
					productKey = "starter", robux = p and p.robux or 149, color = GOLD,
				})
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		vipSpotlightDone[player.UserId] = nil
	end)

	-- chat tags (best-effort via TextChatService)
	pcall(function()
		local TextChatService = game:GetService("TextChatService")
		TextChatService.OnIncomingMessage = function(message: TextChatMessage)
			local props = Instance.new("TextChatMessageProperties")
			local src = message.TextSource
			if src then
				local plr = Players:GetPlayerByUserId(src.UserId)
				local tag = plr and plr:GetAttribute("ChatTag")
				if plr and typeof(tag) == "string" and tag ~= "" then
					local col = plr:GetAttribute("TagColor")
					local hex = typeof(col) == "Color3" and (col :: Color3):ToHex() or "FFCC44"
					props.PrefixText = ("<font color='#%s'>[%s]</font> %s"):format(hex, tag, message.PrefixText)
				end
			end
			return props
		end
	end)
end

return MonetizationService
