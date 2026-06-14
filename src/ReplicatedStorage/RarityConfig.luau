--!strict
-- RarityConfig: the 6 rarity tiers, their multipliers, colors and ordering.
-- Shared between server (stat math, case odds) and client (UI coloring).

local RarityConfig = {}

-- Canonical order, lowest -> highest. Index is the rarity id used in weapon encoding.
RarityConfig.Order = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
}

export type RarityInfo = {
	name: string,
	index: number,
	multiplier: number,
	color: Color3,
	-- minimum tier that gets a particle emitter / trail is decided in WeaponConfig
}

RarityConfig.Data = {
	Common = { name = "Common", index = 1, multiplier = 1, color = Color3.fromRGB(200, 200, 200) },
	Uncommon = { name = "Uncommon", index = 2, multiplier = 1.5, color = Color3.fromRGB(95, 215, 95) },
	Rare = { name = "Rare", index = 3, multiplier = 2.5, color = Color3.fromRGB(70, 140, 255) },
	Epic = { name = "Epic", index = 4, multiplier = 4, color = Color3.fromRGB(175, 80, 255) },
	Legendary = { name = "Legendary", index = 5, multiplier = 7, color = Color3.fromRGB(255, 175, 35) },
	Mythic = { name = "Mythic", index = 6, multiplier = 12, color = Color3.fromRGB(255, 60, 70) },
}

function RarityConfig.fromIndex(index: number): string
	return RarityConfig.Order[index] or "Common"
end

function RarityConfig.indexOf(name: string): number
	return RarityConfig.Data[name] and RarityConfig.Data[name].index or 1
end

function RarityConfig.getColor(name: string): Color3
	local d = RarityConfig.Data[name]
	return d and d.color or Color3.fromRGB(200, 200, 200)
end

function RarityConfig.getMultiplier(name: string): number
	local d = RarityConfig.Data[name]
	return d and d.multiplier or 1
end

-- Rare and above get a particle emitter.
function RarityConfig.hasParticles(name: string): boolean
	return RarityConfig.indexOf(name) >= RarityConfig.indexOf("Rare")
end

-- Legendary and above get a swing trail.
function RarityConfig.hasTrail(name: string): boolean
	return RarityConfig.indexOf(name) >= RarityConfig.indexOf("Legendary")
end

return RarityConfig
