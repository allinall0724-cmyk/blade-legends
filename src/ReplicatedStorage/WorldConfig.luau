--!strict
-- WorldConfig: canonical coordinates for every zone. The world builder
-- (GameManager) places geometry here; gameplay services teleport players using
-- the same numbers so spawns always line up with the map.

local WorldConfig = {}

WorldConfig.Hub = {
	center = Vector3.new(0, 5, 0),
	spawn = CFrame.new(0, 5, 20),
	leaderboardBoard = Vector3.new(0, 12, -55),
	showcase = Vector3.new(0, 8, 0),
}

WorldConfig.CaseArea = {
	center = Vector3.new(260, 5, 0),
	spawn = CFrame.new(260, 5, 25),
}

WorldConfig.Trading = {
	center = Vector3.new(0, 5, -260),
	spawn = CFrame.new(0, 5, -235),
}

-- Decorative halls (no gameplay spawns depend on these — purely visited zones).
WorldConfig.WeaponHall = {
	center = Vector3.new(360, 5, 220),
	spawn = CFrame.new(360, 6, 168),
}

WorldConfig.LeaderboardHall = {
	center = Vector3.new(-360, 5, 220),
	spawn = CFrame.new(-360, 6, 168),
}

-- Casual arena: one pad, several spawn rings (12 players).
WorldConfig.Casual = {
	center = Vector3.new(-320, 5, 0),
	radius = 70,
	spawnCount = 12,
}

-- Ranked arena: a small 1v1 pit with two fixed corners.
WorldConfig.Ranked = {
	center = Vector3.new(0, 5, 320),
	spawnA = CFrame.new(-22, 6, 320) * CFrame.Angles(0, math.rad(90), 0),
	spawnB = CFrame.new(22, 6, 320) * CFrame.Angles(0, math.rad(-90), 0),
	lobby = CFrame.new(0, 6, 360),
}

-- Casual arena map variants (cosmetic theming applied to the same pad).
WorldConfig.CasualMaps = {
	{ name = "Colosseum", floor = Color3.fromRGB(210, 190, 150), accent = Color3.fromRGB(180, 150, 100) },
	{ name = "Sky Arena", floor = Color3.fromRGB(200, 230, 255), accent = Color3.fromRGB(255, 255, 255) },
	{ name = "Underground Pit", floor = Color3.fromRGB(70, 65, 75), accent = Color3.fromRGB(120, 80, 60) },
	{ name = "Forest Clearing", floor = Color3.fromRGB(90, 150, 80), accent = Color3.fromRGB(110, 80, 50) },
}

-- Compute the i-th casual spawn CFrame around the ring.
function WorldConfig.casualSpawn(i: number): CFrame
	local n = WorldConfig.Casual.spawnCount
	local angle = (i - 1) / n * math.pi * 2
	local c = WorldConfig.Casual.center
	local x = c.X + math.cos(angle) * WorldConfig.Casual.radius * 0.7
	local z = c.Z + math.sin(angle) * WorldConfig.Casual.radius * 0.7
	return CFrame.new(Vector3.new(x, c.Y + 1, z), c)
end

return WorldConfig
