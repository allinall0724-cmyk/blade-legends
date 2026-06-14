--!strict
-- AbilityConfig: the rarity-gated ability ladder shared by client UI and the
-- server combat logic. Slot -> input key, unlock rarity, cooldown, and the
-- per-weapon-category Special (F) and Ultimate (G) names/descriptions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RarityConfig = require(ReplicatedStorage.Shared.RarityConfig)

local AbilityConfig = {}

-- ordered slots, basic first
AbilityConfig.Slots = { "Basic", "PowerStrike", "DashStrike", "AreaSlam", "Special", "Ultimate" }

AbilityConfig.Key = {
	Basic = "LMB",
	PowerStrike = "Q",
	DashStrike = "E",
	AreaSlam = "R",
	Special = "F",
	Ultimate = "G",
}

-- minimum rarity index required to use each slot
AbilityConfig.Unlock = {
	Basic = 1, -- Common
	PowerStrike = 2, -- Uncommon
	DashStrike = 3, -- Rare
	AreaSlam = 4, -- Epic
	Special = 5, -- Legendary
	Ultimate = 6, -- Mythic
}

-- cooldown seconds (Basic uses the weapon's own swing cooldown)
AbilityConfig.Cooldown = {
	PowerStrike = 8,
	DashStrike = 10,
	AreaSlam = 15,
	Special = 12,
	Ultimate = 60,
}

-- damage tuning (multipliers of the weapon's base damage)
AbilityConfig.PowerStrikeMult = 1.5
AbilityConfig.DashStrikeMult = 1.4
AbilityConfig.AreaSlamMult = 1.2
AbilityConfig.AreaSlamRadius = 15

-- map a base weapon type name to a category
local CATEGORY = {
	Sword = "blade", Katana = "blade", Dagger = "blade", Lance = "blade",
	["Battle Axe"] = "blunt", ["War Hammer"] = "blunt", Mace = "blunt",
	["Magic Staff"] = "magic", Wand = "magic",
	Bow = "ranged",
	Spear = "polearm", Scythe = "polearm", Trident = "polearm",
	Gauntlet = "guard", Shield = "guard",
}

function AbilityConfig.categoryOf(baseType: string): string
	return CATEGORY[baseType] or "blade"
end

-- per-category Special (F) and Ultimate (G) flavour
AbilityConfig.Special = {
	blade = { name = "Blade Storm", desc = "Spin rapidly, hitting all nearby enemies 5 times." },
	blunt = { name = "Ground Shatter", desc = "Smash the ground; cracks travel forward dealing heavy damage." },
	magic = { name = "Arcane Burst", desc = "Fire a projectile that explodes on impact." },
	ranged = { name = "Arrow Rain", desc = "Fire 5 arrows in an arc over a wide area." },
	polearm = { name = "Phantom Slash", desc = "Teleport behind the nearest enemy and deal massive damage." },
	guard = { name = "Counter Slam", desc = "Block the next attack and counter for double damage." },
}

AbilityConfig.Ultimate = {
	blade = { name = "Divine Judgment", desc = "Summon 3 spectral swords that attack nearby enemies for 5s." },
	blunt = { name = "Earthquake", desc = "Massive shockwave knocks back & damages all within 30 studs." },
	magic = { name = "Arcane Nova", desc = "Huge explosion centered on you across a large radius." },
	ranged = { name = "Arrow Volley", desc = "20 arrows rain down over a target area." },
	polearm = { name = "Phantom Army", desc = "3 phantom clones appear and attack nearby enemies for 5s." },
	guard = { name = "Fortress", desc = "Become invincible and reflect all damage for 3s." },
}

AbilityConfig.BaseDesc = {
	Basic = { name = "Swing", desc = "Basic melee attack." },
	PowerStrike = { name = "Power Strike", desc = "A stronger swing dealing 1.5x damage." },
	DashStrike = { name = "Dash Strike", desc = "Dash forward and strike the first enemy hit." },
	AreaSlam = { name = "Area Slam", desc = "Shockwave damaging all enemies within 15 studs." },
}

-- Resolve a slot's display name/description for a given weapon category.
function AbilityConfig.info(slot: string, category: string): { name: string, desc: string }
	if slot == "Special" then
		return AbilityConfig.Special[category] or AbilityConfig.Special.blade
	elseif slot == "Ultimate" then
		return AbilityConfig.Ultimate[category] or AbilityConfig.Ultimate.blade
	end
	return AbilityConfig.BaseDesc[slot] or { name = slot, desc = "" }
end

function AbilityConfig.isUnlocked(slot: string, rarityName: string): boolean
	local need = AbilityConfig.Unlock[slot] or 1
	return RarityConfig.indexOf(rarityName) >= need
end

-- Full per-slot list for a weapon (UI + validation).
export type SlotInfo = {
	slot: string,
	key: string,
	name: string,
	desc: string,
	cooldown: number,
	unlocked: boolean,
}

function AbilityConfig.listFor(baseType: string, rarityName: string): { SlotInfo }
	local category = AbilityConfig.categoryOf(baseType)
	local out = {}
	for _, slot in AbilityConfig.Slots do
		local i = AbilityConfig.info(slot, category)
		table.insert(out, {
			slot = slot,
			key = AbilityConfig.Key[slot],
			name = i.name,
			desc = i.desc,
			cooldown = AbilityConfig.Cooldown[slot] or 0,
			unlocked = AbilityConfig.isUnlocked(slot, rarityName),
		})
	end
	return out
end

return AbilityConfig
