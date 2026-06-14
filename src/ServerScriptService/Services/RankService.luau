--!strict
-- RankService: ranked queue, 1v1 matchmaking, rating math, and the season loop.
-- A ranked match is first-to-3 kills; every kill is a round (full heal + reset
-- between rounds, no free respawn). Rating is applied on match completion.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local RankConfig = require(ReplicatedStorage.Shared.RankConfig)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local DataService = require(script.Parent.DataService)
local CombatService = require(script.Parent.CombatService)

local RankService = {}

type QueueEntry = { player: Player, rating: number, since: number }
type Match = {
	id: number,
	a: Player,
	b: Player,
	scoreA: number,
	scoreB: number,
	active: boolean,
	roundResetting: boolean,
}

local queue: { QueueEntry } = {}
local activeMatch: { [number]: Match } = {} -- userId -> match
local matchCounter = 0
local WIN_KILLS = 3

-- HUD push hook (set by GameManager)
RankService._pushHud = function(_player: Player) end

-- ---------------------------------------------------------------------------
-- Combat permission: two players may fight if they're in the same ranked match.
-- ---------------------------------------------------------------------------
function RankService.canFight(a: Player, b: Player): boolean
	local m = activeMatch[a.UserId]
	return m ~= nil and m.active and m == activeMatch[b.UserId]
end

local function teleport(player: Player, cf: CFrame)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.CFrame = cf
	end
end

local function equippedWeaponName(player: Player): string
	local id = DataService.getEquipped(player)
	if not id then
		return "Fists"
	end
	local info = WeaponConfig.getInfo(id)
	return info and info.name or "Unknown"
end

-- Fill (or clear) the two name boards on the ranked arena walls.
local function setNameBoards(aName: string, bName: string)
	local world = workspace:FindFirstChild("BladeLegendsWorld")
	local arena = world and world:FindFirstChild("RankedArena")
	if not arena then
		return
	end
	for boardName, who in { RankedNameBoardA = aName, RankedNameBoardB = bName } do
		local board = arena:FindFirstChild(boardName)
		local gui = board and board:FindFirstChild("Gui")
		local label = gui and gui:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.Text = who
		end
	end
end

local function sendMatchState(m: Match)
	for _, p in { m.a, m.b } do
		local prof = DataService.get(p)
		local myScore = (p == m.a) and m.scoreA or m.scoreB
		local oppScore = (p == m.a) and m.scoreB or m.scoreA
		local opp = (p == m.a) and m.b or m.a
		Net.event("MatchState"):FireClient(p, {
			mode = "ranked",
			active = m.active,
			myScore = myScore,
			oppScore = oppScore,
			winKills = WIN_KILLS,
			opponent = opp.DisplayName,
			opponentRating = (DataService.get(opp) or {}).rankRating or 0,
			opponentWeapon = equippedWeaponName(opp),
			myRating = prof and prof.rankRating or 0,
			myWeapon = equippedWeaponName(p),
		})
	end
end

local function startRound(m: Match)
	m.roundResetting = false
	teleport(m.a, WorldConfig.Ranked.spawnA)
	teleport(m.b, WorldConfig.Ranked.spawnB)
	CombatService.resetHealth(m.a)
	CombatService.resetHealth(m.b)
	setNameBoards(m.a.DisplayName, m.b.DisplayName)
	sendMatchState(m)
end

local function endMatch(m: Match, winner: Player, loser: Player)
	m.active = false
	activeMatch[m.a.UserId] = nil
	activeMatch[m.b.UserId] = nil
	setNameBoards("—", "—")

	local wProf = DataService.get(winner)
	local lProf = DataService.get(loser)
	if wProf and lProf then
		local wDelta = RankConfig.ratingDelta(wProf.rankRating, lProf.rankRating, true)
		local lDelta = RankConfig.ratingDelta(lProf.rankRating, wProf.rankRating, false)

		wProf.rankRating = math.max(0, wProf.rankRating + wDelta)
		wProf.totalWins += 1

		-- Instant Rank Shield protects against a loss
		if lProf.rankShieldCharges and lProf.rankShieldCharges > 0 then
			lProf.rankShieldCharges -= 1
			Net.event("Notification"):FireClient(loser, {
				text = "Rank Shield absorbed your rating loss!",
				color = RankConfig.getTierColor(lProf.rankRating),
			})
		else
			lProf.rankRating = math.max(0, lProf.rankRating + lDelta)
		end

		-- track season high
		for _, pr in { wProf, lProf } do
			local tierName = RankConfig.getTierName(pr.rankRating)
			if RankConfig.seasonReward(tierName) > RankConfig.seasonReward(pr.seasonHighRank) then
				pr.seasonHighRank = tierName
			end
		end
	end

	-- return both to ranked lobby
	teleport(winner, WorldConfig.Ranked.lobby)
	teleport(loser, WorldConfig.Ranked.lobby)
	CombatService.resetHealth(winner)
	CombatService.resetHealth(loser)

	Net.event("MatchState"):FireClient(winner, { mode = "ranked", ended = true, won = true })
	Net.event("MatchState"):FireClient(loser, { mode = "ranked", ended = true, won = false })
	Net.event("Notification"):FireClient(winner, { text = "Ranked WIN! +rating", color = Color3.fromRGB(90, 220, 90) })
	Net.event("Notification"):FireClient(loser, { text = "Ranked loss", color = Color3.fromRGB(220, 90, 90) })

	RankService._pushHud(winner)
	RankService._pushHud(loser)
end

-- Called by CombatService on every confirmed kill.
local function onKill(killer: Player?, victim: Player)
	if not killer then
		return
	end
	local m = activeMatch[victim.UserId]
	if not m or not m.active or m ~= activeMatch[killer.UserId] then
		return -- not a kill in this ranked match
	end
	if m.roundResetting then
		return
	end
	if killer == m.a then
		m.scoreA += 1
	else
		m.scoreB += 1
	end
	local kProf = DataService.get(killer)
	if kProf then
		kProf.totalKills += 1
	end

	if m.scoreA >= WIN_KILLS then
		endMatch(m, m.a, m.b)
	elseif m.scoreB >= WIN_KILLS then
		endMatch(m, m.b, m.a)
	else
		-- Round won. The loser dies and auto-respawns; startRound() runs from the
		-- CharacterAdded hook once they're back. A fallback timer covers the rare
		-- case where respawn never fires.
		m.roundResetting = true
		sendMatchState(m)
		task.delay(8, function()
			if m.active and m.roundResetting then
				startRound(m)
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Queue + matchmaking
-- ---------------------------------------------------------------------------
local function removeFromQueue(player: Player)
	for i = #queue, 1, -1 do
		if queue[i].player == player then
			table.remove(queue, i)
		end
	end
end

local function enterQueue(player: Player)
	if activeMatch[player.UserId] then
		return
	end
	removeFromQueue(player)
	local prof = DataService.get(player)
	if not prof then
		return
	end
	table.insert(queue, { player = player, rating = prof.rankRating, since = os.clock() })
	Net.event("MatchState"):FireClient(player, { mode = "ranked", queued = true, rating = prof.rankRating })
end

local function tryMatchmake()
	-- sort by rating so nearest ratings are adjacent
	table.sort(queue, function(x, y)
		return x.rating < y.rating
	end)
	local i = 1
	while i < #queue do
		local a = queue[i]
		local b = queue[i + 1]
		if a and b and math.abs(a.rating - b.rating) <= RankConfig.MATCH_WINDOW then
			-- create match
			matchCounter += 1
			local m: Match = {
				id = matchCounter,
				a = a.player,
				b = b.player,
				scoreA = 0,
				scoreB = 0,
				active = true,
				roundResetting = false,
			}
			activeMatch[a.player.UserId] = m
			activeMatch[b.player.UserId] = m
			-- remove both from queue
			table.remove(queue, i + 1)
			table.remove(queue, i)
			-- pre-match lobby then start
			sendMatchState(m)
			task.delay(4, function()
				if m.active then
					startRound(m)
				end
			end)
		else
			i += 1
		end
	end
end

local function abandon(player: Player)
	removeFromQueue(player)
	local m = activeMatch[player.UserId]
	if m and m.active then
		local other = (m.a == player) and m.b or m.a
		endMatch(m, other, player)
	end
end

-- ---------------------------------------------------------------------------
-- Season loop
-- ---------------------------------------------------------------------------
local DataStoreService = game:GetService("DataStoreService")
local seasonStore: GlobalDataStore? = nil
do
	local ok, s = pcall(function()
		return DataStoreService:GetDataStore("BladeLegends_Season_v1")
	end)
	if ok then
		seasonStore = s
	end
end

local function getSeasonStart(): number
	if not seasonStore then
		return os.time()
	end
	local ok, val = pcall(function()
		return (seasonStore :: GlobalDataStore):GetAsync("seasonStart")
	end)
	if ok and typeof(val) == "number" then
		return val
	end
	-- initialise
	local now = os.time()
	pcall(function()
		(seasonStore :: GlobalDataStore):SetAsync("seasonStart", now)
	end)
	return now
end

local function endSeason()
	-- grant rewards to everyone online, reset ratings
	for _, player in Players:GetPlayers() do
		local prof = DataService.get(player)
		if prof then
			local reward = RankConfig.seasonReward(prof.seasonHighRank)
			if reward > 0 then
				DataService.addCoins(player, reward, false)
			end
			if prof.seasonHighRank == "Mythic" then
				-- exclusive Mythic season weapon
				local id = WeaponConfig.randomOfRarity("Mythic")
				DataService.addWeapon(player, id)
			end
			prof.rankRating = 0
			prof.seasonHighRank = "Bronze"
			RankService._pushHud(player)
		end
	end
	Net.event("Announcement"):FireAllClients({
		text = "A new Ranked Season has begun! Ratings reset — climb again!",
		color = Color3.fromRGB(255, 200, 60),
	})
	if seasonStore then
		pcall(function()
			(seasonStore :: GlobalDataStore):SetAsync("seasonStart", os.time())
		end)
	end
end

function RankService.getSeasonInfo(): { secondsLeft: number, length: number }
	local start = RankService._seasonStart or os.time()
	local elapsed = os.time() - start
	return {
		secondsLeft = math.max(0, RankConfig.SEASON_SECONDS - elapsed),
		length = RankConfig.SEASON_SECONDS,
	}
end

function RankService.init()
	RankService._seasonStart = getSeasonStart()

	CombatService.onKill(onKill)

	-- When a player in an active match respawns, drop them at their corner and
	-- heal. If a round was waiting on the loser to respawn, start it now.
	local function onCharacterAdded(player: Player, char: Model)
		local m = activeMatch[player.UserId]
		if not m or not m.active then
			return
		end
		char:WaitForChild("HumanoidRootPart", 5)
		if m.roundResetting then
			startRound(m)
		else
			teleport(player, (player == m.a) and WorldConfig.Ranked.spawnA or WorldConfig.Ranked.spawnB)
			CombatService.resetHealth(player)
		end
	end
	for _, p in Players:GetPlayers() do
		p.CharacterAdded:Connect(function(c)
			onCharacterAdded(p, c)
		end)
	end
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function(c)
			onCharacterAdded(p, c)
		end)
	end)

	Net.event("EnterRankedQueue").OnServerEvent:Connect(function(player)
		enterQueue(player)
	end)
	Net.event("LeaveQueue").OnServerEvent:Connect(function(player)
		abandon(player)
		Net.event("MatchState"):FireClient(player, { mode = "ranked", queued = false })
	end)

	Players.PlayerRemoving:Connect(abandon)

	-- matchmaking + season tick
	task.spawn(function()
		while true do
			task.wait(2)
			if #queue >= 2 then
				tryMatchmake()
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(60)
			local elapsed = os.time() - (RankService._seasonStart or os.time())
			if elapsed >= RankConfig.SEASON_SECONDS then
				endSeason()
				RankService._seasonStart = os.time()
			end
		end
	end)
end

return RankService
