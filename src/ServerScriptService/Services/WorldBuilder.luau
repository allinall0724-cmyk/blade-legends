--!strict
-- WorldBuilder: constructs the entire map at runtime from WorldConfig
-- coordinates. Pure geometry + a few interactive props (portals, board,
-- showcase, vendor signs). No external model dependencies so it always builds.

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)

local WorldBuilder = {}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = props.Parent or Workspace
	return p
end

local function floorPad(name: string, center: Vector3, size: Vector3, color: Color3, parent: Instance): Part
	return part({
		Name = name,
		Size = size,
		Position = center - Vector3.new(0, size.Y / 2, 0),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
end

local function sign(text: string, position: Vector3, color: Color3, parent: Instance)
	local post = part({
		Name = "SignPost",
		Size = Vector3.new(1, 8, 1),
		Position = position,
		Color = Color3.fromRGB(90, 70, 50),
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	local board = part({
		Name = "SignBoard",
		Size = Vector3.new(12, 4, 0.4),
		Position = position + Vector3.new(0, 5, 0),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Parent = parent,
	})
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(400, 130)
	sg.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = text
	label.Parent = sg
	return post
end

-- Build a portal pad that teleports a toucher to `targetCFrame`.
local function portal(name: string, position: Vector3, color: Color3, targetCFrame: CFrame, parent: Instance)
	local pad = part({
		Name = "Portal_" .. name,
		Size = Vector3.new(10, 1, 10),
		Position = position,
		Color = color,
		Material = Enum.Material.Neon,
		Parent = parent,
	})
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Travel"
	prompt.ObjectText = name
	prompt.HoldDuration = 0.2
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = pad
	prompt.Triggered:Connect(function(player)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			hrp.CFrame = targetCFrame
		end
	end)
	-- floating label
	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.fromOffset(160, 40)
	bg.StudsOffset = Vector3.new(0, 4, 0)
	bg.AlwaysOnTop = true
	bg.Parent = pad
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextStrokeTransparency = 0.3
	lbl.TextColor3 = color
	lbl.Text = name
	lbl.Parent = bg
	return pad
end

function WorldBuilder.build(): { board: SurfaceGui, recentTicker: SurfaceGui }
	local world = Instance.new("Folder")
	world.Name = "BladeLegendsWorld"
	world.Parent = Workspace

	-- ground plane (large)
	floorPad("Ground", Vector3.new(0, 5, 30), Vector3.new(4000, 2, 4000), Color3.fromRGB(60, 90, 60), world)

	-- spawn location
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = WorldConfig.Hub.spawn - Vector3.new(0, 2.5, 0)
	spawn.Color = Color3.fromRGB(120, 200, 255)
	spawn.Material = Enum.Material.Neon
	spawn.Neutral = true
	spawn.Parent = world

	-- ===== HUB =====
	local hub = Instance.new("Folder")
	hub.Name = "Hub"
	hub.Parent = world
	floorPad("HubFloor", WorldConfig.Hub.center, Vector3.new(140, 2, 140), Color3.fromRGB(110, 110, 130), hub)

	-- central rotating showcase
	local pedestal = part({
		Name = "ShowcasePedestal",
		Size = Vector3.new(6, 8, 6),
		Position = WorldConfig.Hub.showcase - Vector3.new(0, 4, 0),
		Color = Color3.fromRGB(80, 80, 95),
		Material = Enum.Material.Marble,
		Parent = hub,
	})
	local showcase = part({
		Name = "ShowcaseWeapon",
		Size = Vector3.new(2, 8, 2),
		Position = WorldConfig.Hub.showcase + Vector3.new(0, 6, 0),
		Color = Color3.fromRGB(255, 215, 60),
		Material = Enum.Material.Neon,
		Parent = hub,
	})
	showcase.CanCollide = false
	-- spin it
	task.spawn(function()
		local angle = 0
		while showcase.Parent do
			angle += 0.03
			showcase.CFrame = CFrame.new(WorldConfig.Hub.showcase + Vector3.new(0, 6, 0)) * CFrame.Angles(0, angle, 0)
			task.wait(0.03)
		end
	end)

	-- leaderboard board
	local boardPart = part({
		Name = "LeaderboardBoard",
		Size = Vector3.new(40, 22, 1),
		Position = WorldConfig.Hub.leaderboardBoard,
		Color = Color3.fromRGB(25, 25, 35),
		Material = Enum.Material.SmoothPlastic,
		Parent = hub,
	})
	local boardGui = Instance.new("SurfaceGui")
	boardGui.Name = "BoardGui"
	boardGui.Face = Enum.NormalId.Front
	boardGui.CanvasSize = Vector2.new(800, 440)
	boardGui.Parent = boardPart

	-- recent pulls ticker board (near case area entrance)
	local tickerPart = part({
		Name = "RecentPullsBoard",
		Size = Vector3.new(24, 10, 1),
		Position = WorldConfig.Hub.center + Vector3.new(55, 12, -10),
		Color = Color3.fromRGB(30, 20, 40),
		Material = Enum.Material.SmoothPlastic,
		Parent = hub,
	})
	local tickerGui = Instance.new("SurfaceGui")
	tickerGui.Name = "TickerGui"
	tickerGui.Face = Enum.NormalId.Front
	tickerGui.CanvasSize = Vector2.new(480, 200)
	tickerGui.Parent = tickerPart

	-- vendor signs
	sign("⚔ Blade Legends ⚔", WorldConfig.Hub.center + Vector3.new(-30, 4, 30), Color3.fromRGB(180, 60, 60), hub)
	sign("Press B: Shop", WorldConfig.Hub.center + Vector3.new(30, 4, 30), Color3.fromRGB(60, 140, 200), hub)

	-- portals
	portal("Cases", WorldConfig.Hub.center + Vector3.new(40, 1, 0), Color3.fromRGB(180, 80, 255), WorldConfig.CaseArea.spawn, hub)
	portal("Casual Arena", WorldConfig.Hub.center + Vector3.new(-40, 1, 0), Color3.fromRGB(255, 140, 40), WorldConfig.Casual.center + Vector3.new(0, 4, -WorldConfig.Casual.radius), hub)
	portal("Ranked Arena", WorldConfig.Hub.center + Vector3.new(0, 1, 40), Color3.fromRGB(255, 60, 70), WorldConfig.Ranked.lobby, hub)
	portal("Trading Post", WorldConfig.Hub.center + Vector3.new(0, 1, -40), Color3.fromRGB(60, 220, 160), WorldConfig.Trading.spawn, hub)
	portal("Hub", WorldConfig.CaseArea.center + Vector3.new(0, 1, -20), Color3.fromRGB(120, 200, 255), WorldConfig.Hub.spawn, hub)

	-- ===== CASE AREA =====
	local caseArea = Instance.new("Folder")
	caseArea.Name = "CaseArea"
	caseArea.Parent = world
	floorPad("CaseFloor", WorldConfig.CaseArea.center, Vector3.new(90, 2, 90), Color3.fromRGB(60, 40, 80), caseArea)
	sign("Open Cases Here", WorldConfig.CaseArea.center + Vector3.new(0, 4, -15), Color3.fromRGB(180, 80, 255), caseArea)
	portal("Hub", WorldConfig.CaseArea.center + Vector3.new(0, 1, -35), Color3.fromRGB(120, 200, 255), WorldConfig.Hub.spawn, caseArea)

	-- ===== CASUAL ARENA =====
	local casual = Instance.new("Folder")
	casual.Name = "CasualArena"
	casual.Parent = world
	local casualFloor = floorPad("CasualFloor", WorldConfig.Casual.center, Vector3.new(WorldConfig.Casual.radius * 2, 2, WorldConfig.Casual.radius * 2), WorldConfig.CasualMaps[1].floor, casual)
	casualFloor:SetAttribute("Themeable", true)
	-- low walls
	for _, off in {
		Vector3.new(WorldConfig.Casual.radius, 6, 0),
		Vector3.new(-WorldConfig.Casual.radius, 6, 0),
		Vector3.new(0, 6, WorldConfig.Casual.radius),
		Vector3.new(0, 6, -WorldConfig.Casual.radius),
	} do
		local horizontal = math.abs(off.X) < 1
		part({
			Name = "CasualWall",
			Size = horizontal and Vector3.new(WorldConfig.Casual.radius * 2, 12, 2) or Vector3.new(2, 12, WorldConfig.Casual.radius * 2),
			Position = WorldConfig.Casual.center + off,
			Color = WorldConfig.CasualMaps[1].accent,
			Material = Enum.Material.SmoothPlastic,
			Parent = casual,
		})
	end
	portal("Hub", WorldConfig.Casual.center + Vector3.new(0, 1, -WorldConfig.Casual.radius - 6), Color3.fromRGB(120, 200, 255), WorldConfig.Hub.spawn, casual)

	-- ===== RANKED ARENA =====
	local ranked = Instance.new("Folder")
	ranked.Name = "RankedArena"
	ranked.Parent = world
	floorPad("RankedFloor", WorldConfig.Ranked.center, Vector3.new(70, 2, 70), Color3.fromRGB(80, 40, 45), ranked)
	floorPad("RankedLobby", WorldConfig.Ranked.center + Vector3.new(0, 0, 40), Vector3.new(30, 2, 20), Color3.fromRGB(50, 50, 65), ranked)
	sign("Ranked 1v1 — press L for queue", WorldConfig.Ranked.center + Vector3.new(0, 4, 38), Color3.fromRGB(255, 60, 70), ranked)
	portal("Hub", WorldConfig.Ranked.center + Vector3.new(0, 1, 50), Color3.fromRGB(120, 200, 255), WorldConfig.Hub.spawn, ranked)

	-- ===== TRADING POST =====
	local trading = Instance.new("Folder")
	trading.Name = "TradingPost"
	trading.Parent = world
	floorPad("TradingFloor", WorldConfig.Trading.center, Vector3.new(60, 2, 60), Color3.fromRGB(40, 70, 60), trading)
	sign("Trading Post — press E near a player", WorldConfig.Trading.center + Vector3.new(0, 4, -25), Color3.fromRGB(60, 220, 160), trading)
	portal("Hub", WorldConfig.Trading.center + Vector3.new(0, 1, 28), Color3.fromRGB(120, 200, 255), WorldConfig.Hub.spawn, trading)

	return { board = boardGui, recentTicker = tickerGui }
end

return WorldBuilder
