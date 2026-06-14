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

local function rebuild()
	-- gather current players sorted by rating
	local list = {}
	for _, player in Players:GetPlayers() do
		local prof = DataService.get(player)
		if prof then
			table.insert(list, { player = player, rating = prof.rankRating })
			-- push to global ordered store (best effort)
			if orderedStore then
				task.spawn(function()
					pcall(function()
						(orderedStore :: OrderedDataStore):SetAsync(tostring(player.UserId), math.floor(prof.rankRating))
					end)
				end)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.rating > b.rating
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
			rating = math.floor(item.rating),
			tier = RankConfig.getTierName(item.rating),
			color = RankConfig.getTierColor(item.rating),
			weapon = equippedName(item.player),
		})
	end
	lastEntries = entries

	-- gold tags
	for _, player in Players:GetPlayers() do
		setGoldTag(player, topSet[player.UserId] == true)
	end

	Net.event("LeaderboardUpdate"):FireAllClients({ entries = entries, season = RankService.getSeasonInfo() })
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
