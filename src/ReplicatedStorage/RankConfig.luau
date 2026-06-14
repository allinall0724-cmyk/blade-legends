--!strict
-- RankConfig: competitive tiers, rating math, and season reward table.

local RankConfig = {}

export type Tier = {
	name: string,
	min: number,
	max: number, -- inclusive; math.huge for top tier
	color: Color3,
	seasonReward: number,
}

-- Ordered low -> high.
RankConfig.Tiers = {
	{ name = "Bronze",    min = 0,    max = 999,       color = Color3.fromRGB(150, 95, 50),   seasonReward = 500 },
	{ name = "Silver",    min = 1000, max = 1999,      color = Color3.fromRGB(190, 190, 200), seasonReward = 1000 },
	{ name = "Gold",      min = 2000, max = 2999,      color = Color3.fromRGB(255, 200, 40),  seasonReward = 2500 },
	{ name = "Diamond",   min = 3000, max = 3999,      color = Color3.fromRGB(80, 220, 240),  seasonReward = 5000 },
	{ name = "Legendary", min = 4000, max = 4999,      color = Color3.fromRGB(175, 80, 255),  seasonReward = 10000 },
	{ name = "Mythic",    min = 5000, max = math.huge, color = Color3.fromRGB(255, 90, 60),   seasonReward = 25000 },
}

function RankConfig.getTier(rating: number): Tier
	rating = math.max(0, rating)
	for _, tier in RankConfig.Tiers do
		if rating >= tier.min and rating <= tier.max then
			return tier
		end
	end
	return RankConfig.Tiers[1]
end

function RankConfig.getTierName(rating: number): string
	return RankConfig.getTier(rating).name
end

function RankConfig.getTierColor(rating: number): Color3
	return RankConfig.getTier(rating).color
end

-- Rating delta given a result. winnerRating/loserRating are the two players'
-- ratings; returns the change to apply to `myRating`.
-- Spec:
--   Win vs equal rank:  +25     Win vs higher rank:  +35
--   Loss vs lower rank: -30     Loss vs equal rank:  -20
-- "higher/lower/equal" compared by tier; same tier = equal.
function RankConfig.ratingDelta(myRating: number, oppRating: number, didWin: boolean): number
	local myTier = RankConfig.getTier(myRating)
	local oppTier = RankConfig.getTier(oppRating)
	local oppIsHigher = oppTier.min > myTier.min
	local oppIsLower = oppTier.min < myTier.min

	if didWin then
		if oppIsHigher then
			return 35
		else
			-- equal or lower
			return 25
		end
	else
		if oppIsLower then
			return -30
		else
			-- equal or higher
			return -20
		end
	end
end

-- Matchmaking window (rating points).
RankConfig.MATCH_WINDOW = 200

-- Season length.
RankConfig.SEASON_DAYS = 30
RankConfig.SEASON_SECONDS = RankConfig.SEASON_DAYS * 24 * 60 * 60

-- Reward coins for finishing a season at a given tier name.
function RankConfig.seasonReward(tierName: string): number
	for _, tier in RankConfig.Tiers do
		if tier.name == tierName then
			return tier.seasonReward
		end
	end
	return 0
end

return RankConfig
