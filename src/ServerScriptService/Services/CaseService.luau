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

local function doOpen(player: Player, caseId: string)
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

	if not DataService.spendCoins(player, case.cost) then
		Net.event("Notification"):FireClient(player, {
			text = "Not enough coins for " .. case.name,
			color = RarityConfig.getColor("Mythic"),
		})
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
	DataService.addWeapon(player, weaponId)

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
	end

	-- refresh HUD
	CaseService._pushHud(player)
end

-- set by GameManager so we don't create a circular require
CaseService._pushHud = function(_player: Player) end
CaseService._onPull = function(_entry: any) end

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

	Players.PlayerRemoving:Connect(function(player)
		lastOpen[player.UserId] = nil
	end)
end

return CaseService
