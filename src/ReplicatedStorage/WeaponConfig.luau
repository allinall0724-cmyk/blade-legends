--!strict
-- WeaponConfig: the heart of Blade Legends' 5,400-weapon combination system.
--
-- A weapon is fully described by four attributes:
--   baseType (1..15)  rarity (1..6)  material (1..10)  size (1..6)
-- These are packed into a single deterministic integer id in [1, 5400] so the
-- whole catalogue can live in a player's inventory as a flat array of numbers.
--
-- Base 3D models are real free Roblox Toolbox assets fetched via the
-- toolbox-service marketplace search API (category 10 = Models). Each id below
-- is the top free result for its keyword.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RarityConfig = require(ReplicatedStorage.Shared.RarityConfig)

local WeaponConfig = {}

-- ---------------------------------------------------------------------------
-- Base weapon types (15). assetId = real Toolbox model id.
-- baseDamage / baseSpeed are the un-scaled stats for a Normal/Common weapon.
-- ---------------------------------------------------------------------------
export type BaseType = {
	name: string,
	assetId: number,
	keyword: string,
	baseDamage: number,
	baseSpeed: number, -- swings per second baseline
	reach: number, -- hitbox studs
}

WeaponConfig.BaseTypes = {
	{ name = "Sword",      assetId = 47433,           keyword = "sword roblox",   baseDamage = 18, baseSpeed = 1.6, reach = 8 },
	{ name = "Katana",     assetId = 15283548889,     keyword = "katana",         baseDamage = 16, baseSpeed = 2.0, reach = 8 },
	{ name = "Battle Axe", assetId = 401083997,       keyword = "battle axe",     baseDamage = 26, baseSpeed = 1.0, reach = 7 },
	{ name = "War Hammer", assetId = 13106821277,     keyword = "war hammer",     baseDamage = 30, baseSpeed = 0.8, reach = 7 },
	{ name = "Spear",      assetId = 8865050093,      keyword = "spear",          baseDamage = 17, baseSpeed = 1.4, reach = 12 },
	{ name = "Magic Staff",assetId = 107585195482186, keyword = "magic staff",    baseDamage = 20, baseSpeed = 1.2, reach = 10 },
	{ name = "Bow",        assetId = 11490959971,     keyword = "bow arrow",      baseDamage = 22, baseSpeed = 1.1, reach = 14 },
	{ name = "Dagger",     assetId = 11746816357,     keyword = "dagger",         baseDamage = 12, baseSpeed = 2.6, reach = 5 },
	{ name = "Scythe",     assetId = 8186983320,      keyword = "scythe",         baseDamage = 24, baseSpeed = 1.1, reach = 9 },
	{ name = "Trident",    assetId = 95617739938869,  keyword = "trident",        baseDamage = 21, baseSpeed = 1.3, reach = 11 },
	{ name = "Mace",       assetId = 78784820401093,  keyword = "club mace",      baseDamage = 25, baseSpeed = 1.0, reach = 6 },
	{ name = "Lance",      assetId = 15445540711,      keyword = "lance",          baseDamage = 23, baseSpeed = 1.1, reach = 13 },
	{ name = "Wand",       assetId = 6265215909,      keyword = "wand",           baseDamage = 14, baseSpeed = 2.2, reach = 9 },
	{ name = "Gauntlet",   assetId = 14913098471,     keyword = "gauntlet fist",  baseDamage = 15, baseSpeed = 2.4, reach = 4 },
	{ name = "Shield",     assetId = 121179389531601, keyword = "shield weapon",  baseDamage = 13, baseSpeed = 1.5, reach = 5 },
}

-- ---------------------------------------------------------------------------
-- Materials (10). color drives the in-game tint; particle is the emitter style.
-- ---------------------------------------------------------------------------
export type Material = {
	name: string,
	color: Color3,
	particle: string, -- "fire" | "sparkle" | "ice" | "lightning" | "none"
}

WeaponConfig.Materials = {
	{ name = "Wood",      color = Color3.fromRGB(120, 80, 40),   particle = "none" },
	{ name = "Stone",     color = Color3.fromRGB(130, 130, 130), particle = "none" },
	{ name = "Iron",      color = Color3.fromRGB(95, 105, 120),  particle = "none" },
	{ name = "Gold",      color = Color3.fromRGB(255, 215, 40),  particle = "sparkle" },
	{ name = "Crystal",   color = Color3.fromRGB(80, 230, 240),  particle = "sparkle" },
	{ name = "Shadow",    color = Color3.fromRGB(60, 30, 80),    particle = "sparkle" },
	{ name = "Fire",      color = Color3.fromRGB(255, 90, 30),   particle = "fire" },
	{ name = "Ice",       color = Color3.fromRGB(140, 210, 255), particle = "ice" },
	{ name = "Lightning", color = Color3.fromRGB(245, 245, 150), particle = "lightning" },
	{ name = "Void",      color = Color3.fromRGB(20, 20, 25),    particle = "sparkle" },
}

-- ---------------------------------------------------------------------------
-- Size modifiers (6).
-- ---------------------------------------------------------------------------
export type SizeMod = { name: string, multiplier: number }

WeaponConfig.Sizes = {
	{ name = "Tiny",     multiplier = 0.5 },
	{ name = "Small",    multiplier = 0.75 },
	{ name = "Normal",   multiplier = 1 },
	{ name = "Large",    multiplier = 1.5 },
	{ name = "Giant",    multiplier = 2 },
	{ name = "Colossal", multiplier = 3 },
}

WeaponConfig.NORMAL_SIZE_INDEX = 3

-- counts (kept as fields so other modules don't hardcode them)
WeaponConfig.NUM_BASE = #WeaponConfig.BaseTypes -- 15
WeaponConfig.NUM_RARITY = #RarityConfig.Order -- 6
WeaponConfig.NUM_MATERIAL = #WeaponConfig.Materials -- 10
WeaponConfig.NUM_SIZE = #WeaponConfig.Sizes -- 6
WeaponConfig.TOTAL = WeaponConfig.NUM_BASE * WeaponConfig.NUM_RARITY * WeaponConfig.NUM_MATERIAL * WeaponConfig.NUM_SIZE -- 5400

-- ---------------------------------------------------------------------------
-- Encoding: pack (base, rarity, material, size) -> id in [1, TOTAL].
-- ---------------------------------------------------------------------------
function WeaponConfig.encode(baseIdx: number, rarityIdx: number, materialIdx: number, sizeIdx: number): number
	local b = (baseIdx - 1)
	local r = (rarityIdx - 1)
	local m = (materialIdx - 1)
	local s = (sizeIdx - 1)
	return ((b * WeaponConfig.NUM_RARITY + r) * WeaponConfig.NUM_MATERIAL + m) * WeaponConfig.NUM_SIZE + s + 1
end

export type Decoded = {
	id: number,
	baseIdx: number,
	rarityIdx: number,
	materialIdx: number,
	sizeIdx: number,
}

function WeaponConfig.decode(id: number): Decoded?
	if typeof(id) ~= "number" then
		return nil
	end
	id = math.floor(id)
	if id < 1 or id > WeaponConfig.TOTAL then
		return nil
	end
	local z = id - 1
	local sizeIdx = (z % WeaponConfig.NUM_SIZE) + 1
	z = math.floor(z / WeaponConfig.NUM_SIZE)
	local materialIdx = (z % WeaponConfig.NUM_MATERIAL) + 1
	z = math.floor(z / WeaponConfig.NUM_MATERIAL)
	local rarityIdx = (z % WeaponConfig.NUM_RARITY) + 1
	z = math.floor(z / WeaponConfig.NUM_RARITY)
	local baseIdx = z + 1
	return {
		id = id,
		baseIdx = baseIdx,
		rarityIdx = rarityIdx,
		materialIdx = materialIdx,
		sizeIdx = sizeIdx,
	}
end

-- ---------------------------------------------------------------------------
-- Full resolved weapon info (name, stats, visuals) for a given id.
-- ---------------------------------------------------------------------------
export type WeaponInfo = {
	id: number,
	name: string,
	baseType: string,
	assetId: number,
	rarity: string,
	rarityColor: Color3,
	material: string,
	materialColor: Color3,
	particle: string,
	size: string,
	sizeMult: number,
	damage: number,
	speed: number, -- swings per second
	cooldown: number, -- seconds between swings
	reach: number,
	hasParticles: boolean,
	hasTrail: boolean,
}

function WeaponConfig.getInfo(id: number): WeaponInfo?
	local d = WeaponConfig.decode(id)
	if not d then
		return nil
	end
	local base = WeaponConfig.BaseTypes[d.baseIdx]
	local rarity = RarityConfig.Order[d.rarityIdx]
	local rarityData = RarityConfig.Data[rarity]
	local material = WeaponConfig.Materials[d.materialIdx]
	local size = WeaponConfig.Sizes[d.sizeIdx]

	local rarityMult = rarityData.multiplier
	local sizeMult = size.multiplier

	-- BaseDamage = RarityMultiplier x SizeMultiplier x BaseTypeDamage
	local damage = rarityMult * sizeMult * base.baseDamage
	-- Speed = BaseTypeSpeed / SizeMultiplier  (bigger = slower)
	local speed = base.baseSpeed / sizeMult

	-- Name: "[Material] [Size?] [BaseType]" ; omit size when Normal.
	local namePieces = { material.name }
	if d.sizeIdx ~= WeaponConfig.NORMAL_SIZE_INDEX then
		table.insert(namePieces, size.name)
	end
	table.insert(namePieces, base.name)

	return {
		id = id,
		name = table.concat(namePieces, " "),
		baseType = base.name,
		assetId = base.assetId,
		rarity = rarity,
		rarityColor = rarityData.color,
		material = material.name,
		materialColor = material.color,
		particle = material.particle,
		size = size.name,
		sizeMult = sizeMult,
		damage = math.floor(damage * 10 + 0.5) / 10,
		speed = math.floor(speed * 100 + 0.5) / 100,
		cooldown = 1 / speed,
		reach = base.reach,
		hasParticles = RarityConfig.hasParticles(rarity),
		hasTrail = RarityConfig.hasTrail(rarity),
	}
end

-- Convenience: build an id straight from a rarity name + random other attrs.
function WeaponConfig.randomOfRarity(rarityName: string, rng: Random?): number
	local r = rng or Random.new()
	local rarityIdx = RarityConfig.indexOf(rarityName)
	local baseIdx = r:NextInteger(1, WeaponConfig.NUM_BASE)
	local materialIdx = r:NextInteger(1, WeaponConfig.NUM_MATERIAL)
	local sizeIdx = r:NextInteger(1, WeaponConfig.NUM_SIZE)
	return WeaponConfig.encode(baseIdx, rarityIdx, materialIdx, sizeIdx)
end

function WeaponConfig.isValidId(id: any): boolean
	return WeaponConfig.decode(id) ~= nil
end

return WeaponConfig
