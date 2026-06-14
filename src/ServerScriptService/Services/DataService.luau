--!strict
-- DataService: authoritative per-player profile store.
-- Owns the in-memory profile cache and all DataStore persistence (pcall + retry).
-- Every other service mutates player state through this module so there is a
-- single place that knows how to save.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)

local DataService = {}

local STORE_NAME = "BladeLegends_Profiles_v1"
local AUTOSAVE_INTERVAL = 120 -- seconds
local MAX_RETRIES = 3

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStore unavailable (Studio API access off?):", result)
	end
end

export type Profile = {
	coins: number,
	weapons: { number }, -- array of weapon ids owned (duplicates allowed)
	equippedWeapon: number?,
	rankRating: number,
	seasonHighRank: string,
	totalKills: number,
	totalWins: number,
	casesPulled: { basic: number, pro: number, mythic: number },
	pityCounter: number,
	pityCounters: { [string]: number },
	lastLoginDate: string,
	loginStreak: number,
	passes: { [string]: boolean },
	rankShieldCharges: number,
	rankBoostPending: boolean,
	starterExpiry: number,
	firstPurchaseDone: boolean,
	mythicHunterGranted: boolean,
	vipWeekKey: string,
	vipCaseOpens: number,
	beginnerLuckDate: string,
	nameColorIdx: number,
	nameColorOwned: boolean,
	joinTime: number,
}

local function defaultProfile(): Profile
	return {
		coins = 250, -- small starter stipend so new players can open a case
		weapons = {},
		equippedWeapon = nil,
		rankRating = 0,
		seasonHighRank = "Bronze",
		totalKills = 0,
		totalWins = 0,
		casesPulled = { basic = 0, pro = 0, mythic = 0 },
		pityCounter = 0,
		pityCounters = {}, -- per-case pity, keyed by case id
		lastLoginDate = "",
		loginStreak = 0,
		-- the six game passes (+ legacy coins2x kept for back-compat)
		passes = {
			coins2x = false, lucky = false, vip = false,
			starter = false, speedDemon = false, coinMagnet = false, mythicHunter = false,
		},
		rankShieldCharges = 0,
		rankBoostPending = false,
		-- monetization bookkeeping
		starterExpiry = 0, -- os.time when the Starter Pack 2x ends
		firstPurchaseDone = false,
		mythicHunterGranted = false,
		vipWeekKey = "",
		vipCaseOpens = 0,
		beginnerLuckDate = "",
		nameColorIdx = 0, -- 0 = default white
		nameColorOwned = false,
		joinTime = 0, -- set on load; drives the first-10-minutes starter popup
	}
end

-- Fill in any missing keys so older saves stay compatible.
local function reconcile(profile: any): Profile
	local base = defaultProfile()
	if typeof(profile) ~= "table" then
		return base
	end
	for key, value in base do
		if profile[key] == nil then
			profile[key] = value
		end
	end
	-- nested tables
	for _, sub in { "casesPulled", "passes", "pityCounters" } do
		if typeof(profile[sub]) ~= "table" then
			profile[sub] = base[sub]
		else
			for k, v in (base[sub] :: any) do
				if profile[sub][k] == nil then
					profile[sub][k] = v
				end
			end
		end
	end
	-- prune any invalid weapon ids
	local cleaned = {}
	for _, id in profile.weapons do
		if WeaponConfig.isValidId(id) then
			table.insert(cleaned, math.floor(id))
		end
	end
	profile.weapons = cleaned
	if profile.equippedWeapon ~= nil and not WeaponConfig.isValidId(profile.equippedWeapon) then
		profile.equippedWeapon = nil
	end
	return profile
end

local cache: { [number]: Profile } = {}
local loaded: { [number]: boolean } = {}

local function keyFor(userId: number): string
	return "player_" .. userId
end

local function tryGet(userId: number): Profile
	if not store then
		return defaultProfile()
	end
	for attempt = 1, MAX_RETRIES do
		local ok, data = pcall(function()
			return (store :: DataStore):GetAsync(keyFor(userId))
		end)
		if ok then
			return reconcile(data)
		else
			warn(("[DataService] GetAsync failed for %d (attempt %d): %s"):format(userId, attempt, tostring(data)))
			task.wait(attempt * 0.5)
		end
	end
	warn("[DataService] giving up loading", userId, "- using fresh profile (will not overwrite on save until next success)")
	return defaultProfile()
end

local function trySave(userId: number, profile: Profile): boolean
	if not store then
		return false
	end
	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(keyFor(userId), function()
				return profile
			end)
		end)
		if ok then
			return true
		else
			warn(("[DataService] Save failed for %d (attempt %d): %s"):format(userId, attempt, tostring(err)))
			task.wait(attempt * 0.5)
		end
	end
	return false
end

-- Public ---------------------------------------------------------------------

function DataService.get(player: Player): Profile?
	return cache[player.UserId]
end

function DataService.isLoaded(player: Player): boolean
	return loaded[player.UserId] == true
end

-- Yields until the player's profile is loaded (or they leave). Returns nil if
-- the player left before loading finished.
function DataService.waitFor(player: Player): Profile?
	local start = os.clock()
	while not loaded[player.UserId] do
		if not player.Parent then
			return nil
		end
		if os.clock() - start > 30 then
			break
		end
		task.wait(0.1)
	end
	return cache[player.UserId]
end

local onLoadedCallbacks: { (player: Player, profile: Profile) -> () } = {}
function DataService.onLoaded(fn: (player: Player, profile: Profile) -> ())
	table.insert(onLoadedCallbacks, fn)
end

function DataService.load(player: Player)
	local userId = player.UserId
	local profile = tryGet(userId)
	profile.joinTime = os.time()
	cache[userId] = profile
	loaded[userId] = true
	for _, fn in onLoadedCallbacks do
		task.spawn(fn, player, profile)
	end
end

function DataService.save(player: Player): boolean
	local profile = cache[player.UserId]
	if not profile then
		return false
	end
	return trySave(player.UserId, profile)
end

function DataService.unload(player: Player)
	DataService.save(player)
	cache[player.UserId] = nil
	loaded[player.UserId] = nil
end

-- Economy helpers ------------------------------------------------------------

function DataService.getCoins(player: Player): number
	local p = cache[player.UserId]
	return p and p.coins or 0
end

-- Highest coin multiplier the player's passes grant (does not stack — takes max).
function DataService.coinMultiplier(player: Player): number
	local p = cache[player.UserId]
	if not p then
		return 1
	end
	local mult = 1
	local passes = p.passes
	if passes.mythicHunter then
		mult = math.max(mult, 3)
	end
	if passes.coinMagnet or passes.vip or passes.coins2x then
		mult = math.max(mult, 2)
	end
	if passes.starter and p.starterExpiry and os.time() < p.starterExpiry then
		mult = math.max(mult, 2)
	end
	return mult
end

-- Adds coins, applying the pass coin multiplier when `applyMultiplier` is true.
function DataService.addCoins(player: Player, amount: number, applyMultiplier: boolean?): number
	local p = cache[player.UserId]
	if not p then
		return 0
	end
	local mult = applyMultiplier and DataService.coinMultiplier(player) or 1
	p.coins = math.max(0, math.floor(p.coins + amount * mult))
	return p.coins
end

-- Returns true if the player had enough and the coins were deducted.
function DataService.spendCoins(player: Player, amount: number): boolean
	local p = cache[player.UserId]
	if not p or p.coins < amount then
		return false
	end
	p.coins -= amount
	return true
end

-- Weapons --------------------------------------------------------------------

function DataService.addWeapon(player: Player, weaponId: number): boolean
	local p = cache[player.UserId]
	if not p or not WeaponConfig.isValidId(weaponId) then
		return false
	end
	table.insert(p.weapons, math.floor(weaponId))
	if p.equippedWeapon == nil then
		p.equippedWeapon = math.floor(weaponId)
	end
	return true
end

function DataService.hasWeapon(player: Player, weaponId: number): boolean
	local p = cache[player.UserId]
	if not p then
		return false
	end
	for _, id in p.weapons do
		if id == weaponId then
			return true
		end
	end
	return false
end

-- Remove a single instance of weaponId. Returns true if one was removed.
function DataService.removeWeapon(player: Player, weaponId: number): boolean
	local p = cache[player.UserId]
	if not p then
		return false
	end
	for i, id in p.weapons do
		if id == weaponId then
			table.remove(p.weapons, i)
			if p.equippedWeapon == weaponId and not DataService.hasWeapon(player, weaponId) then
				p.equippedWeapon = p.weapons[1]
			end
			return true
		end
	end
	return false
end

function DataService.setEquipped(player: Player, weaponId: number?): boolean
	local p = cache[player.UserId]
	if not p then
		return false
	end
	if weaponId == nil then
		p.equippedWeapon = nil
		return true
	end
	if DataService.hasWeapon(player, weaponId) then
		p.equippedWeapon = math.floor(weaponId)
		return true
	end
	return false
end

function DataService.getEquipped(player: Player): number?
	local p = cache[player.UserId]
	return p and p.equippedWeapon
end

-- Lifecycle ------------------------------------------------------------------

function DataService.init()
	-- Defer the initial load of already-present players until the end of this
	-- frame so every other service has registered its onLoaded() hook first
	-- (matters for the local player in Studio, who is present at server start).
	task.defer(function()
		for _, player in Players:GetPlayers() do
			task.spawn(DataService.load, player)
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		DataService.load(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		DataService.unload(player)
	end)

	-- periodic autosave
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				task.spawn(DataService.save, player)
			end
		end
	end)

	-- best-effort save on server shutdown
	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end
		for _, player in Players:GetPlayers() do
			task.spawn(DataService.save, player)
		end
		task.wait(2)
	end)
end

return DataService
