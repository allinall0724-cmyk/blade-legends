--!strict
-- LeaderboardService: live top-10 board in the hub, golden name tags for the
-- leaders, and a cross-server top-50 backed by an OrderedDataStore.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Net = require(ReplicatedStorage.Shared.Net)
local RankConfig = require(ReplicatedStorage.Shared.RankConfig)
local RarityConfig = require(ReplicatedStorage.Shared.RarityConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local DataService = require(script.Parent.DataService)
local RankService = require(script.Parent.RankService)

local LeaderboardService = {}

local UPDATE_INTERVAL = 60
local GOLD = Color3.fromRGB(255, 215, 60)

local orderedStore: OrderedDataStore? = nil
do
	local ok, s = pcall(function()
		return DataStoreService:GetOrderedDataStore("BladeLegends_Ratings_v1")
	end)
	if ok then
		orderedStore = s
	end
end

local lastEntries: { any } = {}

local function equippedName(player: Player): string
	local id = DataService.getEquipped(player)
	local info = id and WeaponConfig.getInfo(id)
	return info and info.name or "—"
end

-- Top-3 Collectors get a gold aura around their character (Elite Collector).
function LeaderboardService.setEliteGlow(player: Player, on: boolean)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local existing = root:FindFirstChild("EliteGlow")
	if on and not existing then
		local att = Instance.new("Attachment")
		att.Name = "EliteGlow"
		att.Parent = root
		local em = Instance.new("ParticleEmitter")
		em.Color = ColorSequence.new(Color3.fromRGB(255, 215, 80))
		em.LightEmission = 1
		em.Rate = 22
		em.Lifetime = NumberRange.new(1, 1.6)
		em.Speed = NumberRange.new(1, 2.5)
		em.SpreadAngle = Vector2.new(180, 180)
		em.Size = NumberSequence.new(0.6)
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		em.Parent = att
	elseif not on and existing then
		existing:Destroy()
	end
end

local function setGoldTag(player: Player, gold: boolean)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("BL_NameTag")
	local label = tag and tag:FindFirstChild("PlayerName") :: TextLabel?
	if label then
		label.TextColor3 = gold and GOLD or Color3.fromRGB(255, 255, 255)
		label.Text = (gold and "👑 " or "") .. player.DisplayName
	end
end

-- highest-value owned Blade (info) for a profile
local function rarestBlade(prof: any)
	local best, bestV = nil, -1
	for _, id in prof.weapons do
		local v = WeaponConfig.value(id)
		if v > bestV then
			bestV = v
			best = WeaponConfig.getInfo(id)
		end
	end
	return best, math.max(0, bestV)
end

local function rebuild()
	-- gather current players, ranked by Net Worth (collection-first leaderboard)
	local list = {}
	for _, player in Players:GetPlayers() do
		local prof = DataService.get(player)
		if prof then
			local nw = WeaponConfig.netWorth(prof.weapons)
			local rarest, rarestV = rarestBlade(prof)
			table.insert(list, { player = player, netWorth = nw, rarest = rarest, rarestV = rarestV })
			if orderedStore then
				task.spawn(function()
					pcall(function()
						(orderedStore :: OrderedDataStore):SetAsync(tostring(player.UserId), math.floor(nw))
					end)
				end)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.netWorth > b.netWorth
	end)

	local entries = {}
	local topSet: { [number]: boolean } = {}
	for i, item in list do
		if i > 10 then
			break
		end
		topSet[item.player.UserId] = true
		table.insert(entries, {
			position = i,
			name = item.player.DisplayName,
			userId = item.player.UserId,
			-- 'rating'/'tier'/'weapon' kept so existing board/UI formatting works
			rating = math.floor(item.netWorth),
			netWorth = math.floor(item.netWorth),
			tier = "NW",
			color = Color3.fromRGB(120, 220, 150),
			weapon = item.rarest and item.rarest.name or "—",
		})
	end
	lastEntries = entries

	-- separate "Rarest Pull" board: single highest-value Blade per player
	local rarestList = table.clone(list)
	table.sort(rarestList, function(a, b)
		return a.rarestV > b.rarestV
	end)
	local rarestEntries = {}
	for i, item in rarestList do
		if i > 10 then break end
		table.insert(rarestEntries, {
			position = i,
			name = item.player.DisplayName,
			userId = item.player.UserId,
			rating = math.floor(item.rarestV),
			tier = "Value",
			color = item.rarest and item.rarest.rarityColor or Color3.fromRGB(200, 200, 200),
			weapon = item.rarest and item.rarest.name or "—",
		})
	end

	-- Elite Collector glow + gold tag for the top 3 net-worth Collectors
	for _, player in Players:GetPlayers() do
		local rank = 0
		for i, item in list do
			if item.player == player then rank = i break end
		end
		player:SetAttribute("CollectorRank", rank)
		setGoldTag(player, topSet[player.UserId] == true)
		LeaderboardService.setEliteGlow(player, rank >= 1 and rank <= 3)
	end

	Net.event("LeaderboardUpdate"):FireAllClients({ entries = entries, rarestEntries = rarestEntries })
	LeaderboardService._updateBoard(entries)
end

-- Set by GameManager once the physical board exists.
LeaderboardService._updateBoard = function(_entries: { any }) end

function LeaderboardService.getEntries(): { any }
	return lastEntries
end

-- Collection preview summary for a userId (clicking the board).
local function collectionSummary(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	local prof = player and DataService.get(player)
	if not prof then
		return { name = "?", total = 0, byRarity = {}, top = {} }
	end
	local byRarity: { [string]: number } = {}
	local best: { number } = {}
	for _, id in prof.weapons do
		local info = WeaponConfig.getInfo(id)
		if info then
			byRarity[info.rarity] = (byRarity[info.rarity] or 0) + 1
		end
	end
	-- top 5 weapons by damage
	local sorted = table.clone(prof.weapons)
	table.sort(sorted, function(x, y)
		local ix, iy = WeaponConfig.getInfo(x), WeaponConfig.getInfo(y)
		return (ix and ix.damage or 0) > (iy and iy.damage or 0)
	end)
	for i = 1, math.min(5, #sorted) do
		table.insert(best, sorted[i])
	end
	local topInfos = {}
	for _, id in best do
		table.insert(topInfos, WeaponConfig.getInfo(id))
	end
	return {
		name = player and player.DisplayName or "?",
		total = #prof.weapons,
		byRarity = byRarity,
		top = topInfos,
		rating = prof.rankRating,
		tier = RankConfig.getTierName(prof.rankRating),
	}
end

function LeaderboardService.init()
	Net.func("GetCollection").OnServerInvoke = function(_player, userId)
		if typeof(userId) ~= "number" then
			return nil
		end
		return collectionSummary(math.floor(userId))
	end

	task.spawn(function()
		task.wait(5)
		while true do
			local ok, err = pcall(rebuild)
			if not ok then
				warn("[LeaderboardService] rebuild error:", err)
			end
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

-- expose RarityConfig color helper for the board UI builder
LeaderboardService.rarityColor = RarityConfig.getColor

return LeaderboardService
