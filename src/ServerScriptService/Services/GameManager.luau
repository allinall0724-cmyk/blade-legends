--!strict
-- GameManager: top-level orchestrator. Builds the world, owns the casual arena
-- loop, composes the combat damage policy, drives the physical hub boards, and
-- provides the single HUD-push used by every other service.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local RankConfig = require(ReplicatedStorage.Shared.RankConfig)

local DataService = require(script.Parent.DataService)
local CombatService = require(script.Parent.CombatService)
local CaseService = require(script.Parent.CaseService)
local RankService = require(script.Parent.RankService)
local TradeService = require(script.Parent.TradeService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local MonetizationService = require(script.Parent.MonetizationService)
local WorldBuilder = require(script.Parent.WorldBuilder)

local GameManager = {}

local CASUAL_ROUND = 300 -- 5 minutes
local KILL_COINS = 10
local WIN_COINS = 50
local RESPAWN_TIME = 5

local casualMembers: { [number]: boolean } = {}
local roundKills: { [number]: number } = {}
local currentMapIndex = 1

-- ---------------------------------------------------------------------------
-- HUD push: the canonical player state snapshot.
-- ---------------------------------------------------------------------------
local function pushHud(player: Player)
	local prof = DataService.get(player)
	if not prof then
		return
	end
	local equippedInfo = nil
	if prof.equippedWeapon then
		equippedInfo = WeaponConfig.getInfo(prof.equippedWeapon)
	end
	-- rarest (highest-value) Blade + Net Worth for the collection HUD
	local rarestInfo = nil
	local rarestVal = -1
	local netWorth = 0
	for _, id in prof.weapons do
		local v = WeaponConfig.value(id)
		netWorth += v
		if v > rarestVal then
			rarestVal = v
			rarestInfo = WeaponConfig.getInfo(id)
		end
	end
	Net.event("UpdateHUD"):FireClient(player, {
		coins = prof.coins,
		equipped = equippedInfo,
		rarest = rarestInfo,
		netWorth = netWorth,
		rating = prof.rankRating,
		tier = RankConfig.getTierName(prof.rankRating),
		tierColor = RankConfig.getTierColor(prof.rankRating),
		streak = prof.loginStreak,
		kills = prof.totalKills,
		wins = prof.totalWins,
		passes = prof.passes,
		inCasual = casualMembers[player.UserId] == true,
	})
end
GameManager.pushHud = pushHud

-- ---------------------------------------------------------------------------
-- Damage policy: casual members can hit each other; ranked opponents can hit
-- each other. Nothing else takes damage (hub is safe).
-- ---------------------------------------------------------------------------
local function damagePolicy(attacker: Player, victim: Player): boolean
	if casualMembers[attacker.UserId] and casualMembers[victim.UserId] then
		return true
	end
	return RankService.canFight(attacker, victim)
end

-- ---------------------------------------------------------------------------
-- Casual arena
-- ---------------------------------------------------------------------------
local function casualSpawnFor(): CFrame
	return WorldConfig.casualSpawn(math.random(1, WorldConfig.Casual.spawnCount))
end

local function enterCasual(player: Player)
	casualMembers[player.UserId] = true
	roundKills[player.UserId] = roundKills[player.UserId] or 0
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.CFrame = casualSpawnFor()
	end
	CombatService.resetHealth(player)
	pushHud(player)
	Net.event("Notification"):FireClient(player, { text = "Entered Casual Arena! Coins for kills & wins.", color = Color3.fromRGB(255, 160, 60) })
end

local function leaveCasual(player: Player)
	casualMembers[player.UserId] = nil
	roundKills[player.UserId] = nil
	pushHud(player)
end

local function onKillCasual(killer: Player?, victim: Player)
	if not (killer and casualMembers[killer.UserId] and casualMembers[victim.UserId]) then
		return
	end
	-- reward kill
	DataService.addCoins(killer, KILL_COINS, true)
	roundKills[killer.UserId] = (roundKills[killer.UserId] or 0) + 1
	local kProf = DataService.get(killer)
	if kProf then
		kProf.totalKills += 1
	end
	Net.event("KillNotify"):FireClient(killer, { coins = KILL_COINS })
	pushHud(killer)

	Net.event("KillFeed"):FireAllClients({
		killer = killer.DisplayName,
		victim = victim.DisplayName,
		weapon = (function()
			local id = DataService.getEquipped(killer)
			local info = id and WeaponConfig.getInfo(id)
			return info and info.name or "Fists"
		end)(),
	})

	-- Victim death triggers Roblox's auto-respawn (Players.RespawnTime). The
	-- CharacterAdded hook below re-drops casual members at an arena spawn, so we
	-- don't call LoadCharacter here (that would double-spawn).
end

local function endCasualRound()
	-- winner = most kills this round among current members
	local winner: Player? = nil
	local best = -1
	for userId in casualMembers do
		local k = roundKills[userId] or 0
		if k > best then
			best = k
			winner = Players:GetPlayerByUserId(userId)
		end
	end
	if winner and best > 0 then
		DataService.addCoins(winner, WIN_COINS, true)
		pushHud(winner)
		Net.event("Announcement"):FireAllClients({
			text = ("%s won the Casual round with %d kills! (+%d coins)"):format(winner.DisplayName, best, WIN_COINS),
			color = Color3.fromRGB(255, 160, 60),
		})
	end
	-- reset round + rotate map
	for userId in casualMembers do
		roundKills[userId] = 0
	end
	currentMapIndex = (currentMapIndex % #WorldConfig.CasualMaps) + 1
	GameManager._applyCasualTheme(currentMapIndex)
	for userId in casualMembers do
		local p = Players:GetPlayerByUserId(userId)
		if p then
			Net.event("Notification"):FireClient(p, {
				text = "New round: " .. WorldConfig.CasualMaps[currentMapIndex].name,
				color = Color3.fromRGB(255, 200, 120),
			})
		end
	end
end

GameManager._applyCasualTheme = function(_index: number) end

-- ---------------------------------------------------------------------------
-- Physical hub boards
-- ---------------------------------------------------------------------------
local recentPulls: { any } = {}

local function buildBoardUI(boardGui: SurfaceGui)
	-- header + 10 rows
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 50)
	title.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 215, 60)
	title.Text = "🏆 TOP PLAYERS"
	title.Parent = boardGui
	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.Position = UDim2.new(0, 0, 0, 52)
	list.Size = UDim2.new(1, 0, 1, -52)
	list.BackgroundTransparency = 1
	list.Parent = boardGui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 2)
	layout.Parent = list
end

local function updateBoardUI(boardGui: SurfaceGui, entries: { any })
	local list = boardGui:FindFirstChild("Rows")
	if not list then
		return
	end
	for _, c in list:GetChildren() do
		if c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	for _, e in entries do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, -8, 0, 34)
		row.Position = UDim2.new(0, 4, 0, 0)
		row.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
		row.BackgroundTransparency = 0.2
		row.Font = Enum.Font.GothamMedium
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = e.color
		row.LayoutOrder = e.position
		row.Text = ("  #%d  %s   [%s %d]   %s"):format(e.position, e.name, e.tier, e.rating, e.weapon)
		row.Parent = list
	end
end

local function updateTickerUI(tickerGui: SurfaceGui)
	for _, c in tickerGui:GetChildren() do
		if c:IsA("TextLabel") or c:IsA("UIListLayout") then
			c:Destroy()
		end
	end
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.Parent = tickerGui
	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, 30)
	header.BackgroundColor3 = Color3.fromRGB(50, 30, 70)
	header.Font = Enum.Font.GothamBold
	header.TextScaled = true
	header.TextColor3 = Color3.fromRGB(255, 255, 255)
	header.Text = "✨ RECENT PULLS"
	header.LayoutOrder = 0
	header.Parent = tickerGui
	for i = #recentPulls, math.max(1, #recentPulls - 7), -1 do
		local e = recentPulls[i]
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, 0, 0, 22)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.Gotham
		row.TextScaled = true
		row.TextColor3 = e.rarityColor or Color3.fromRGB(255, 255, 255)
		row.LayoutOrder = #recentPulls - i + 1
		row.Text = ("%s → %s"):format(e.player, e.weapon)
		row.Parent = tickerGui
	end
end

-- ---------------------------------------------------------------------------
function GameManager.init()
	Net.init()
	pcall(function()
		Players.RespawnTime = RESPAWN_TIME
	end)

	-- build the map
	local refs = WorldBuilder.build()
	buildBoardUI(refs.board)
	if refs.fameBoard then
		buildBoardUI(refs.fameBoard)
	end

	-- casual theme applier (recolors arena floor/walls)
	GameManager._applyCasualTheme = function(index: number)
		local world = workspace:FindFirstChild("BladeLegendsWorld")
		local casual = world and world:FindFirstChild("CasualArena")
		if not casual then
			return
		end
		local theme = WorldConfig.CasualMaps[index]
		for _, p in casual:GetChildren() do
			if p:IsA("BasePart") and p.Name == "CasualFloor" then
				p.Color = theme.floor
			elseif p:IsA("BasePart") and p.Name == "CasualWall" then
				p.Color = theme.accent
			end
		end
	end

	-- wire HUD push into every service
	CaseService._pushHud = pushHud
	RankService._pushHud = pushHud
	TradeService._pushHud = pushHud
	MonetizationService._pushHud = pushHud

	-- conversion-psychology hooks
	CaseService._onLowCoins = MonetizationService.lowCoinAlert
	CaseService._onLegendary = MonetizationService.vipSpotlight
	RankService._onRankedLoss = MonetizationService.streakSaver

	-- physical board updates (hub board + Hall of Fame board)
	LeaderboardService._updateBoard = function(entries)
		updateBoardUI(refs.board, entries)
		if refs.fameBoard then
			updateBoardUI(refs.fameBoard, entries)
		end
	end

	-- case ticker -> physical board
	CaseService._onPull = function(entry)
		table.insert(recentPulls, entry)
		if #recentPulls > 30 then
			table.remove(recentPulls, 1)
		end
		updateTickerUI(refs.recentTicker)
	end

	-- combat policy + kill handler
	CombatService.DamagePolicy = damagePolicy
	CombatService.onKill(onKillCasual)

	-- start each service
	DataService.init()
	CombatService.init()
	CaseService.init()
	RankService.init()
	TradeService.init()
	LeaderboardService.init()
	MonetizationService.init()

	-- remotes: equip / discard / data / casual join
	Net.event("EquipWeapon").OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local id = payload.weaponId
		-- validate ownership (setEquipped only succeeds if the player owns it)
		if WeaponConfig.isValidId(id) and DataService.setEquipped(player, id) then
			CombatService.equip(player) -- builds the Tool, parents to Backpack, EquipTool
			pushHud(player) -- UpdateHUD carries the new equipped name + rarity
			local info = WeaponConfig.getInfo(id)
			if info then
				Net.event("Notification"):FireClient(player, {
					text = "Equipped: " .. info.name,
					color = info.rarityColor,
					duration = 2,
				})
			end
		else
			Net.event("Notification"):FireClient(player, { text = "You don't own that weapon.", color = Color3.fromRGB(220, 90, 90), duration = 2 })
		end
	end)

	Net.event("DiscardWeapon").OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local id = payload.weaponId
		if WeaponConfig.isValidId(id) then
			DataService.removeWeapon(player, id)
			CombatService.equip(player)
			pushHud(player)
		end
	end)

	Net.event("EnterCasual").OnServerEvent:Connect(enterCasual)
	Net.event("LeaveCasual").OnServerEvent:Connect(leaveCasual)
	Net.event("RequestData").OnServerEvent:Connect(pushHud)

	Net.func("GetInventory").OnServerInvoke = function(player)
		local prof = DataService.get(player)
		return prof and prof.weapons or {}
	end
	Net.func("GetShopInfo").OnServerInvoke = function(player)
		return MonetizationService.getShopInfo(player)
	end

	-- push HUD once data loads, and equip the saved weapon (first spawn can race
	-- the deferred profile load, leaving the player unarmed until now)
	DataService.onLoaded(function(player)
		pushHud(player)
		if player.Character then
			CombatService.equip(player)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.5)
			if casualMembers[player.UserId] then
				local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hrp then
					hrp.CFrame = casualSpawnFor()
				end
			end
			pushHud(player)
		end)
	end)
	Players.PlayerRemoving:Connect(leaveCasual)

	-- casual round loop
	task.spawn(function()
		while true do
			task.wait(CASUAL_ROUND)
			local ok, err = pcall(endCasualRound)
			if not ok then
				warn("[GameManager] casual round error:", err)
			end
		end
	end)

	print("[Blade Legends] Server initialised. Weapons in catalogue:", WeaponConfig.TOTAL)
end

return GameManager
