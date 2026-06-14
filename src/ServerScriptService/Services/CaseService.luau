--!strict
-- CaseService: server-authoritative case opening. Validates funds, rolls rarity
-- (with the Basic-case pity guarantee and Lucky/VIP boost), mints the weapon,
-- and broadcasts pulls.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local CaseConfig = require(ReplicatedStorage.Shared.CaseConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local RarityConfig = require(ReplicatedStorage.Shared.RarityConfig)
local DataService = require(script.Parent.DataService)

local CaseService = {}

local rng = Random.new()
local lastOpen: { [number]: number } = {} -- userId -> os.clock of last open (rate limit)
local OPEN_COOLDOWN = 0.4

local pulledKey = { Basic = "basic", Pro = "pro", Mythic = "mythic" }

local function legendaryIndex(): number
	return RarityConfig.indexOf("Legendary")
end

local function doOpen(player: Player, caseId: string, free: boolean?)
	local case = CaseConfig.Cases[caseId]
	if not case then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end

	-- rate limit
	local now = os.clock()
	if lastOpen[player.UserId] and now - lastOpen[player.UserId] < OPEN_COOLDOWN then
		return
	end
	lastOpen[player.UserId] = now

	if not free and not DataService.spendCoins(player, case.cost) then
		Net.event("Notification"):FireClient(player, {
			text = "Not enough coins for " .. case.name,
			color = RarityConfig.getColor("Mythic"),
		})
		-- low-coin alert popup if they're more than halfway short
		if profile.coins < case.cost * 0.5 then
			CaseService._onLowCoins(player, case.cost, profile.coins)
		end
		return
	end

	-- determine rarity
	local rarity: string
	local pityHit = false
	if case.pityThreshold and profile.pityCounter >= case.pityThreshold then
		rarity = "Legendary"
		pityHit = true
	else
		rarity = CaseConfig.rollRarity(caseId, rng)
		-- Lucky / VIP: 50% relative boost to Legendary chance via a re-roll on
		-- a near miss. If the player rolled below Legendary, give them a second
		-- weighted chance to upgrade to Legendary.
		if (profile.passes.lucky or profile.passes.vip)
			and RarityConfig.indexOf(rarity) < legendaryIndex()
		then
			local legChance = (case.weights.Legendary or 0) / 100
			if rng:NextNumber() < legChance * 0.5 then
				rarity = "Legendary"
			end
		end
	end

	-- pity bookkeeping (Basic case tracks pity)
	if case.pityThreshold then
		if RarityConfig.indexOf(rarity) >= legendaryIndex() then
			profile.pityCounter = 0
		else
			profile.pityCounter += 1
		end
	end

	-- mint the weapon
	local weaponId = WeaponConfig.randomOfRarity(rarity, rng)
	-- duplicate detector: did they already own this exact Blade?
	local alreadyOwned = false
	for _, owned in profile.weapons do
		if owned == weaponId then
			alreadyOwned = true
			break
		end
	end
	DataService.addWeapon(player, weaponId)
	profile.cratesOpened = (profile.cratesOpened or 0) + 1
	local dupBonus = 0
	if alreadyOwned then
		dupBonus = math.max(1, math.floor(WeaponConfig.value(weaponId) * 0.1))
		DataService.addCoins(player, dupBonus, false)
	end

	-- stats
	local key = pulledKey[caseId]
	if key then
		profile.casesPulled[key] = (profile.casesPulled[key] or 0) + 1
	end

	local info = WeaponConfig.getInfo(weaponId)

	Net.event("CaseResult"):FireClient(player, {
		caseId = caseId,
		weapon = info,
		pity = pityHit,
		coins = profile.coins,
		duplicate = alreadyOwned,
		dupBonus = dupBonus,
	})

	-- recent-pulls ticker to everyone (clients + physical hub board)
	local tickerEntry = {
		player = player.DisplayName,
		weapon = info and info.name or "?",
		rarity = rarity,
		rarityColor = RarityConfig.getColor(rarity),
	}
	Net.event("RecentPull"):FireAllClients(tickerEntry)
	CaseService._onPull(tickerEntry)

	-- server-wide announcement for Legendary+
	if RarityConfig.indexOf(rarity) >= legendaryIndex() then
		Net.event("Announcement"):FireAllClients({
			text = ("%s just unboxed a %s %s!"):format(player.DisplayName, rarity, info and info.name or "weapon"),
			color = RarityConfig.getColor(rarity),
		})
		-- VIP spotlight (special once-per-session VIP-tagged shout)
		CaseService._onLegendary(player, info and info.name or "weapon")
	end

	-- milestones (titles / collection rewards) + HUD refresh
	CaseService._afterPull(player)
	CaseService._pushHud(player)
end

-- set by GameManager so we don't create a circular require
CaseService._pushHud = function(_player: Player) end
CaseService._onPull = function(_entry: any) end
-- conversion hooks (wired to MonetizationService by GameManager)
CaseService._onLowCoins = function(_player: Player, _needed: number, _have: number) end
CaseService._onLegendary = function(_player: Player, _weaponName: string) end
-- called after every successful open (wired to MilestoneService.check)
CaseService._afterPull = function(_player: Player) end

-- Grant `count` free opens of a case (no cost) — used by bundle products / passes.
function CaseService.grant(player: Player, caseId: string, count: number)
	local case = CaseConfig.Cases[caseId]
	if not case then
		return
	end
	count = math.max(0, math.floor(count or 0))
	for _ = 1, count do
		local rarity = CaseConfig.rollRarity(caseId, rng)
		local weaponId = WeaponConfig.randomOfRarity(rarity, rng)
		DataService.addWeapon(player, weaponId)
	end
	if count > 0 then
		Net.event("Notification"):FireClient(player, {
			text = ("Received %d %s open%s!"):format(count, case.name, count == 1 and "" or "s"),
			color = Color3.fromRGB(120, 200, 255),
		})
		CaseService._pushHud(player)
	end
end

function CaseService.init()
	Net.event("OpenCase").OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local caseId = payload.caseId
		if typeof(caseId) ~= "string" or not CaseConfig.Cases[caseId] then
			return
		end
		doOpen(player, caseId)
	end)

	-- daily free crate (one free Basic open per UTC day)
	Net.event("ClaimFreeCrate").OnServerEvent:Connect(function(player)
		local profile = DataService.get(player)
		if not profile then
			return
		end
		local today = os.date("!%Y-%m-%d") :: string
		if profile.beginnerLuckDate == today then
			Net.event("Notification"):FireClient(player, { text = "Free crate already claimed today — come back tomorrow!", color = Color3.fromRGB(230, 180, 60) })
			return
		end
		profile.beginnerLuckDate = today
		doOpen(player, "Basic", true)
	end)

	-- sell a Blade for 20% of its Value in coins
	Net.event("SellBlade").OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local id = payload.weaponId
		if not WeaponConfig.isValidId(id) then
			return
		end
		if DataService.removeWeapon(player, id) then
			local coins = math.max(1, math.floor(WeaponConfig.value(id) * 0.2))
			DataService.addCoins(player, coins, false)
			Net.event("Notification"):FireClient(player, {
				text = ("Sold for %d coins"):format(coins),
				color = Color3.fromRGB(120, 220, 150),
			})
			CaseService._pushHud(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastOpen[player.UserId] = nil
	end)
end

return CaseService
