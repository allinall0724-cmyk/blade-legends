--!strict
-- MilestoneService: collection milestones + the title system. Milestones award
-- coins / titles (and sometimes a server announcement or an exclusive Blade) the
-- first time their condition is met. Players equip one title shown over their name.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local RarityConfig = require(ReplicatedStorage.Shared.RarityConfig)
local DataService = require(script.Parent.DataService)

local MilestoneService = {}

MilestoneService._pushHud = function(_player: Player) end

local function ownsRarityAtLeast(prof: any, rarityName: string): boolean
	local need = RarityConfig.indexOf(rarityName)
	for _, id in prof.weapons do
		local info = WeaponConfig.getInfo(id)
		if info and RarityConfig.indexOf(info.rarity) >= need then
			return true
		end
	end
	return false
end

-- id, predicate, title, coins, announce, special weapon grant
local MILESTONES = {
	{ id = "blades10", title = "Collector", coins = 200, check = function(p) return #p.weapons >= 10 end },
	{ id = "blades50", title = "Blade Enthusiast", coins = 500, check = function(p) return #p.weapons >= 50 end },
	{ id = "blades100", title = "Blade Master", coins = 1000, check = function(p) return #p.weapons >= 100 end },
	{ id = "firstLegendary", title = "Legend", coins = 300, check = function(p) return ownsRarityAtLeast(p, "Legendary") end },
	{ id = "firstMythic", title = "Mythic Collector", coins = 1000, announce = true, check = function(p) return ownsRarityAtLeast(p, "Mythic") end },
	{ id = "crates500", title = "Crate Addict", coins = 0, grantVoidScythe = true, check = function(p) return (p.cratesOpened or 0) >= 500 end },
}

local function updateTitleAttribute(player: Player)
	local prof = DataService.get(player)
	player:SetAttribute("Title", prof and prof.equippedTitle or "")
end
MilestoneService.updateTitleAttribute = updateTitleAttribute

local function awardTitle(player: Player, prof: any, title: string)
	if not prof.titles[title] then
		prof.titles[title] = true
		if prof.equippedTitle == "" then
			prof.equippedTitle = title
			updateTitleAttribute(player)
		end
	end
end

-- Idempotent: award any newly-completed milestones (flags prevent re-award).
function MilestoneService.check(player: Player)
	local prof = DataService.get(player)
	if not prof then
		return
	end
	prof.milestoneFlags = prof.milestoneFlags or {}
	for _, m in MILESTONES do
		if not prof.milestoneFlags[m.id] and m.check(prof) then
			prof.milestoneFlags[m.id] = true
			if m.coins > 0 then
				DataService.addCoins(player, m.coins, false)
			end
			awardTitle(player, prof, m.title)
			if m.grantVoidScythe then
				-- exclusive Void Colossal Scythe (Mythic): base 9, rarity 6, material 10, size 6
				DataService.addWeapon(player, WeaponConfig.encode(9, 6, 10, 6))
			end
			Net.event("Notification"):FireClient(player, {
				text = ("Milestone! '%s' unlocked%s"):format(m.title, m.coins > 0 and (" (+" .. m.coins .. " coins)") or ""),
				color = Color3.fromRGB(255, 215, 90), duration = 4,
			})
			if m.announce then
				Net.event("Announcement"):FireAllClients({
					text = ("🏆 %s earned the '%s' title!"):format(player.DisplayName, m.title),
					color = Color3.fromRGB(255, 90, 70),
				})
			end
		end
	end
	-- track highest value owned
	local hv = 0
	for _, id in prof.weapons do
		hv = math.max(hv, WeaponConfig.value(id))
	end
	prof.highestValue = hv
	MilestoneService._pushHud(player)
end

function MilestoneService.init()
	Net.event("EquipTitle").OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local title = payload.title
		local prof = DataService.get(player)
		if not prof then
			return
		end
		if title == "" or (typeof(title) == "string" and prof.titles[title]) then
			prof.equippedTitle = title == "" and "" or title
			updateTitleAttribute(player)
			MilestoneService._pushHud(player)
		end
	end)

	Net.func("GetTitles").OnServerInvoke = function(player)
		local prof = DataService.get(player)
		local owned = {}
		if prof then
			for t in prof.titles do
				table.insert(owned, t)
			end
		end
		return { owned = owned, equipped = prof and prof.equippedTitle or "" }
	end

	DataService.onLoaded(function(player)
		MilestoneService.check(player)
		updateTitleAttribute(player)
	end)
end

return MilestoneService
