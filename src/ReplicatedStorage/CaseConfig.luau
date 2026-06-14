--!strict
-- CaseConfig: the 3 case types, their cost and rarity weights, plus the pity rule.
-- Weights are expressed as percentages and validated to sum to 100 at require time.

local CaseConfig = {}

export type Case = {
	id: string,
	name: string,
	cost: number,
	weights: { [string]: number }, -- rarity name -> percent
	-- pity: after `pityThreshold` pulls without a Legendary, force one.
	pityThreshold: number?,
}

CaseConfig.Cases = {
	Basic = {
		id = "Basic",
		name = "Basic Case",
		cost = 100,
		pityThreshold = 50,
		weights = {
			Common = 60,
			Uncommon = 30,
			Rare = 8,
			Epic = 1.9,
			Legendary = 0.1,
		},
	},
	Pro = {
		id = "Pro",
		name = "Pro Case",
		cost = 500,
		weights = {
			Common = 30,
			Uncommon = 35,
			Rare = 25,
			Epic = 8,
			Legendary = 1.8,
			Mythic = 0.2,
		},
	},
	Mythic = {
		id = "Mythic",
		name = "Mythic Case",
		cost = 2000,
		weights = {
			Rare = 40,
			Epic = 35,
			Legendary = 20,
			Mythic = 5,
		},
	},
}

-- Display order for UI.
CaseConfig.Order = { "Basic", "Pro", "Mythic" }

-- Roll a rarity name from a case's weight table using the supplied RNG.
function CaseConfig.rollRarity(caseId: string, rng: Random): string
	local case = CaseConfig.Cases[caseId]
	if not case then
		return "Common"
	end
	local total = 0
	for _, w in case.weights do
		total += w
	end
	local pick = rng:NextNumber(0, total)
	local acc = 0
	-- iterate in a stable order so behaviour is deterministic for a given roll
	local order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
	for _, rarity in order do
		local w = case.weights[rarity]
		if w then
			acc += w
			if pick <= acc then
				return rarity
			end
		end
	end
	return "Common"
end

-- Validate weights at load time (helps catch typos early — logs a warning).
do
	for id, case in CaseConfig.Cases do
		local total = 0
		for _, w in case.weights do
			total += w
		end
		if math.abs(total - 100) > 0.001 then
			warn(("[CaseConfig] %s weights sum to %.2f, expected 100"):format(id, total))
		end
	end
end

return CaseConfig
