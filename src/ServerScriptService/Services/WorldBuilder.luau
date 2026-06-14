--!strict
-- WorldBuilder: constructs the entire visual world at runtime.
--
-- Strategy: every structure is built from anchored parts so the world ALWAYS
-- renders, even when Studio API access (InsertService) is off. Where a real
-- Roblox Toolbox free model is available it is inserted on top as an
-- enhancement via tryInsert() — failures fall back silently to the part build.
--
-- Coordinates come from the shared WorldConfig so gameplay spawns line up with
-- the geometry. Kept as a module (run once by GameManager at server start) so it
-- can hand back the leaderboard + ticker SurfaceGuis it creates.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local InsertService = game:GetService("InsertService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldConfig = require(ReplicatedStorage.Shared.WorldConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local SoundConfig = require(ReplicatedStorage.Shared.SoundConfig)
local Net = require(ReplicatedStorage.Shared.Net)

local WorldBuilder = {}

-- Real Toolbox free-model asset ids (top result per keyword, category 10).
local ASSETS = {
	colosseum = 99212531250476,
	marketStall = 73415637424967,
	fountain = 99409450961129,
	stonePillar = 124337420,
	woodenChest = 101733285763879,
	gatePortal = 129440560208184,
	torchFire = 72634841680697,
	bannerFlag = 108279041197718,
	treasureChest = 123781273,
	crystalPedestal = 132819132970774,
	skybox = 134508275307153,
}

-- ===========================================================================
-- low-level part helpers
-- ===========================================================================
local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function pointLight(parent: Instance, color: Color3, brightness: number, range: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Parent = parent
	return l
end

-- A single Heartbeat drives every rotating prop (cheaper than many loops).
type Spinner = { part: BasePart, pivot: Vector3, speed: number, angle: number }
local spinners: { Spinner } = {}
local function addSpinner(p: BasePart, pivot: Vector3, speed: number)
	table.insert(spinners, { part = p, pivot = pivot, speed = speed, angle = 0 })
end
RunService.Heartbeat:Connect(function(dt)
	for i = #spinners, 1, -1 do
		local s = spinners[i]
		if s.part.Parent == nil then
			table.remove(spinners, i) -- prop was destroyed (e.g. world rebuild)
		else
			s.angle += s.speed * dt
			s.part.CFrame = CFrame.new(s.pivot) * CFrame.Angles(0, s.angle, 0)
		end
	end
end)

-- ===========================================================================
-- Toolbox insertion (best-effort enhancement)
-- ===========================================================================
local function tryInsert(assetId: number, pos: Vector3, parent: Instance, targetHeight: number?): Model?
	if not assetId or assetId == 0 then
		return nil
	end
	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not result then
		return nil
	end
	local container = result :: Instance
	local model: Model = container:IsA("Model") and container or (container:FindFirstChildWhichIsA("Model") or Instance.new("Model"))
	if model ~= container and not model.Parent then
		-- wrap loose parts
		for _, c in container:GetChildren() do
			c.Parent = model
		end
	end
	-- anchor everything so nothing falls
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	if not model:FindFirstChildWhichIsA("BasePart", true) then
		model:Destroy()
		return nil
	end
	model.Parent = parent
	-- scale to a target height, then sit it on the ground at pos
	pcall(function()
		if targetHeight then
			local ext = model:GetExtentsSize()
			if ext.Y > 0.5 then
				model:ScaleTo(math.clamp(targetHeight / ext.Y, 0.05, 50))
			end
		end
		model:PivotTo(CFrame.new(pos))
		local _, size = model:GetBoundingBox()
		model:PivotTo(CFrame.new(pos + Vector3.new(0, size.Y / 2, 0)))
	end)
	return model
end

-- ===========================================================================
-- reusable structures
-- ===========================================================================
local function torch(pos: Vector3, parent: Instance)
	local post = part({
		Name = "TorchPost",
		Size = Vector3.new(0.6, 5, 0.6),
		Position = pos,
		Color = Color3.fromRGB(70, 50, 35),
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	local bowl = part({
		Name = "TorchBowl",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.6, 1.6, 1.6),
		Position = pos + Vector3.new(0, 2.8, 0),
		Color = Color3.fromRGB(40, 30, 25),
		Material = Enum.Material.Slate,
		Parent = parent,
	})
	bowl.CanCollide = false
	local flame = part({
		Name = "Flame",
		Size = Vector3.new(0.5, 0.5, 0.5),
		Position = pos + Vector3.new(0, 3.4, 0),
		Color = Color3.fromRGB(255, 150, 40),
		Material = Enum.Material.Neon,
		Transparency = 0.3,
		Parent = parent,
	})
	flame.CanCollide = false
	local fire = Instance.new("Fire")
	fire.Heat = 8
	fire.Size = 6
	fire.Color = Color3.fromRGB(255, 150, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 90, 20)
	fire.Parent = flame
	pointLight(flame, Color3.fromRGB(255, 160, 70), 2.2, 26)
end

local function pillar(pos: Vector3, height: number, parent: Instance, withTorch: boolean?)
	local base = part({
		Name = "PillarBase",
		Size = Vector3.new(7, 1.4, 7),
		Position = pos + Vector3.new(0, 0.7, 0),
		Color = Color3.fromRGB(120, 115, 105),
		Material = Enum.Material.Slate,
		Parent = parent,
	})
	local shaft = part({
		Name = "PillarShaft",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, 4.6, 4.6),
		CFrame = CFrame.new(pos + Vector3.new(0, height / 2 + 1.4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(205, 200, 188),
		Material = Enum.Material.Marble,
		Parent = parent,
	})
	local cap = part({
		Name = "PillarCap",
		Size = Vector3.new(7, 1.4, 7),
		Position = pos + Vector3.new(0, height + 2.1, 0),
		Color = Color3.fromRGB(120, 115, 105),
		Material = Enum.Material.Slate,
		Parent = parent,
	})
	if withTorch then
		torch(pos + Vector3.new(0, height + 2.8, 0), parent)
	end
	return cap
end

local function banner(fromPos: Vector3, toPos: Vector3, color: Color3, parent: Instance)
	local mid = (fromPos + toPos) / 2
	local dist = (toPos - fromPos).Magnitude
	-- hanging rope (a thin part oriented along the line between the two points)
	part({
		Name = "BannerRope",
		Size = Vector3.new(0.2, 0.2, dist),
		CFrame = CFrame.new(mid, toPos),
		Color = Color3.fromRGB(60, 45, 30),
		Material = Enum.Material.Fabric,
		Parent = parent,
	})
	-- a couple of cloth banners draped along it, gently waving via TweenService
	for i = 0.25, 0.75, 0.25 do
		local p = fromPos:Lerp(toPos, i)
		local base = p - Vector3.new(0, 2.6, 0)
		local cloth = part({
			Name = "Banner",
			Size = Vector3.new(3, 5, 0.2),
			CFrame = CFrame.new(base),
			Color = color,
			Material = Enum.Material.Fabric,
			CanCollide = false,
			Parent = parent,
		})
		local sway = math.rad(8)
		cloth.CFrame = CFrame.new(base) * CFrame.Angles(0, 0, -sway)
		local tween = TweenService:Create(
			cloth,
			TweenInfo.new(2 + i, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ CFrame = CFrame.new(base) * CFrame.Angles(0, 0, sway) }
		)
		tween:Play()
	end
end

-- ---------------------------------------------------------------------------
-- decorative props / scenery
-- ---------------------------------------------------------------------------
local function lampPost(pos: Vector3, color: Color3, parent: Instance)
	part({ Name = "LampBase", Size = Vector3.new(1.2, 1, 1.2), Position = pos + Vector3.new(0, 0.5, 0), Color = Color3.fromRGB(40, 40, 45), Material = Enum.Material.Metal, Parent = parent })
	part({ Name = "LampPole", Size = Vector3.new(0.5, 10, 0.5), Position = pos + Vector3.new(0, 5.5, 0), Color = Color3.fromRGB(55, 55, 60), Material = Enum.Material.Metal, Parent = parent })
	local lantern = part({ Name = "LampLight", Size = Vector3.new(1.8, 2.2, 1.8), Position = pos + Vector3.new(0, 11, 0), Color = color, Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false, Parent = parent })
	pointLight(lantern, color, 2.4, 26)
end

local function barrel(pos: Vector3, parent: Instance)
	part({
		Name = "Barrel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(3.4, 2.6, 2.6),
		CFrame = CFrame.new(pos + Vector3.new(0, 1.7, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(95, 65, 35),
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})
	for _, y in { 0.7, 2.7 } do
		part({
			Name = "BarrelHoop",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(3.5, 2.8, 2.8),
			CFrame = CFrame.new(pos + Vector3.new(0, y, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(60, 50, 45),
			Material = Enum.Material.Metal,
			Transparency = 0.1,
			Parent = parent,
		})
	end
end

local function crate(pos: Vector3, parent: Instance)
	part({ Name = "Crate", Size = Vector3.new(3.5, 3.5, 3.5), Position = pos + Vector3.new(0, 1.75, 0), Color = Color3.fromRGB(120, 85, 45), Material = Enum.Material.WoodPlanks, Parent = parent })
	for _, e in { Vector3.new(0, 1.75, 0) } do
		part({ Name = "CrateTrim", Size = Vector3.new(3.7, 0.4, 3.7), Position = pos + e + Vector3.new(0, 1.55, 0), Color = Color3.fromRGB(80, 55, 30), Material = Enum.Material.Wood, Parent = parent })
	end
end

local function bench(pos: Vector3, yaw: number, parent: Instance)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	part({ Name = "BenchSeat", Size = Vector3.new(7, 0.6, 2.4), CFrame = cf * CFrame.new(0, 2, 0), Color = Color3.fromRGB(110, 80, 50), Material = Enum.Material.Wood, Parent = parent })
	for _, sx in { -2.8, 2.8 } do
		part({ Name = "BenchLeg", Size = Vector3.new(0.5, 2, 2.2), CFrame = cf * CFrame.new(sx, 1, 0), Color = Color3.fromRGB(80, 58, 38), Material = Enum.Material.Wood, Parent = parent })
	end
	part({ Name = "BenchBack", Size = Vector3.new(7, 2.4, 0.5), CFrame = cf * CFrame.new(0, 3.4, -1), Color = Color3.fromRGB(110, 80, 50), Material = Enum.Material.Wood, Parent = parent })
end

-- a simple non-functional mannequin "NPC" built from parts
local function mannequin(pos: Vector3, yaw: number, shirt: Color3, parent: Instance)
	local m = Instance.new("Model")
	m.Name = "NPC"
	m.Parent = parent
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	local skin = Color3.fromRGB(225, 190, 160)
	part({ Name = "Torso", Size = Vector3.new(2.4, 3, 1.2), CFrame = cf * CFrame.new(0, 4, 0), Color = shirt, Material = Enum.Material.Fabric, Parent = m })
	part({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), CFrame = cf * CFrame.new(0, 6.2, 0), Color = skin, Material = Enum.Material.SmoothPlastic, Parent = m })
	for _, sx in { -1.6, 1.6 } do
		part({ Name = "Arm", Size = Vector3.new(0.9, 3, 0.9), CFrame = cf * CFrame.new(sx, 4, 0), Color = shirt, Material = Enum.Material.Fabric, Parent = m })
	end
	for _, sx in { -0.7, 0.7 } do
		part({ Name = "Leg", Size = Vector3.new(1, 3, 1), CFrame = cf * CFrame.new(sx, 1.5, 0), Color = Color3.fromRGB(50, 50, 70), Material = Enum.Material.Fabric, Parent = m })
	end
end

-- a grand entrance archway (two big columns + ornate lintel + glow)
local function grandArch(pos: Vector3, yaw: number, parent: Instance)
	local cf = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
	for _, sx in { -10, 10 } do
		part({ Name = "ArchColumn", Size = Vector3.new(4, 26, 4), CFrame = cf * CFrame.new(sx, 13, 0), Color = Color3.fromRGB(210, 200, 180), Material = Enum.Material.Marble, Parent = parent })
		part({ Name = "ArchColumnBase", Size = Vector3.new(6, 2, 6), CFrame = cf * CFrame.new(sx, 1, 0), Color = Color3.fromRGB(150, 140, 120), Material = Enum.Material.Slate, Parent = parent })
	end
	part({ Name = "ArchLintel", Size = Vector3.new(28, 5, 5), CFrame = cf * CFrame.new(0, 27, 0), Color = Color3.fromRGB(190, 175, 150), Material = Enum.Material.Marble, Parent = parent })
	local crest = part({ Name = "ArchCrest", Size = Vector3.new(8, 4, 1), CFrame = cf * CFrame.new(0, 31, 0), Color = Color3.fromRGB(255, 215, 80), Material = Enum.Material.Neon, Parent = parent })
	pointLight(crest, Color3.fromRGB(255, 215, 90), 3, 40)
	-- title on the lintel
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(560, 100)
	sg.Adornee = nil
	local titlePart = part({ Name = "ArchTitle", Size = Vector3.new(24, 4, 0.4), CFrame = cf * CFrame.new(0, 27, 2.6), Color = Color3.fromRGB(30, 26, 22), Material = Enum.Material.Slate, Parent = parent })
	sg.Parent = titlePart
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(255, 215, 90)
	lbl.Text = "⚔ BLADE LEGENDS ⚔"
	lbl.Parent = sg
end

-- a sky dome over an area (large inverted-looking sphere)
local function skyDome(center: Vector3, radius: number, color: Color3, parent: Instance)
	local dome = part({
		Name = "SkyDome",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(radius * 2, radius * 2, radius * 2),
		Position = center + Vector3.new(0, radius * 0.2, 0),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.35,
		CanCollide = false,
		CastShadow = false,
		Parent = parent,
	})
	return dome
end

-- alternating-color tile floor (checkerboard) over a square area
local function tileFloor(center: Vector3, span: number, tile: number, a: Color3, b: Color3, parent: Instance)
	local half = math.floor(span / tile / 2)
	for ix = -half, half do
		for iz = -half, half do
			local pos = center + Vector3.new(ix * tile, 0.15, iz * tile)
			part({
				Name = "FloorTile",
				Size = Vector3.new(tile - 0.2, 0.3, tile - 0.2),
				Position = pos,
				Color = ((ix + iz) % 2 == 0) and a or b,
				Material = Enum.Material.Marble,
				Parent = parent,
			})
		end
	end
end

-- scattered grass + flower patches
local function grassPatch(pos: Vector3, parent: Instance)
	part({ Name = "Grass", Size = Vector3.new(6, 0.6, 6), Position = pos + Vector3.new(0, 0.3, 0), Color = Color3.fromRGB(70, 130, 60), Material = Enum.Material.Grass, Parent = parent })
	local flowerColors = { Color3.fromRGB(230, 90, 110), Color3.fromRGB(240, 220, 90), Color3.fromRGB(170, 110, 230) }
	for i = 1, 5 do
		local off = Vector3.new(math.random(-25, 25) / 10, 0.9, math.random(-25, 25) / 10)
		part({ Name = "FlowerStem", Size = Vector3.new(0.2, 1.2, 0.2), Position = pos + off, Color = Color3.fromRGB(60, 120, 50), Material = Enum.Material.Grass, Parent = parent })
		part({ Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.new(0.7, 0.7, 0.7), Position = pos + off + Vector3.new(0, 0.7, 0), Color = flowerColors[(i % 3) + 1], Material = Enum.Material.SmoothPlastic, CanCollide = false, Parent = parent })
	end
end

-- looped ambient sound anchored to a zone
local function ambientSound(name: string, pos: Vector3, volume: number, parent: Instance)
	local id = SoundConfig.ambienceId(name)
	if id == "" then
		return
	end
	local emitter = part({ Name = "AmbiencePart", Size = Vector3.new(1, 1, 1), Position = pos, Transparency = 1, CanCollide = false, Parent = parent })
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = true
	s.Volume = volume
	s.RollOffMaxDistance = 220
	s.RollOffMinDistance = 30
	s.Parent = emitter
	s:Play()
end

-- glowing portal arch with a neon "door", proximity teleport and floating label
local function portal(name: string, position: Vector3, color: Color3, target: CFrame | Vector3, parent: Instance, facePoint: Vector3?)
	local targetCFrame: CFrame = if typeof(target) == "Vector3" then CFrame.new(target) else target :: CFrame
	local model = Instance.new("Model")
	model.Name = "Portal_" .. name
	model.Parent = parent

	local yaw = 0
	if facePoint then
		local dir = (facePoint - position)
		yaw = math.atan2(dir.X, dir.Z)
	end
	local baseCF = CFrame.new(position) * CFrame.Angles(0, yaw, 0)

	-- two posts
	for _, sx in { -5, 5 } do
		part({
			Name = "ArchPost",
			Size = Vector3.new(2, 16, 2),
			CFrame = baseCF * CFrame.new(sx, 8, 0),
			Color = Color3.fromRGB(90, 85, 80),
			Material = Enum.Material.Slate,
			Parent = model,
		})
	end
	-- lintel
	part({
		Name = "ArchTop",
		Size = Vector3.new(14, 3, 3),
		CFrame = baseCF * CFrame.new(0, 17.5, 0),
		Color = Color3.fromRGB(75, 70, 65),
		Material = Enum.Material.Slate,
		Parent = model,
	})
	-- solid wall behind the arch so you can't see the destination zone through it
	part({
		Name = "PortalWall",
		Size = Vector3.new(24, 22, 1.5),
		CFrame = baseCF * CFrame.new(0, 11, -1),
		Color = Color3.fromRGB(55, 52, 50),
		Material = Enum.Material.Slate,
		Parent = model,
	})
	-- glowing neon door
	local door = part({
		Name = "PortalDoor",
		Size = Vector3.new(9, 15, 0.6),
		CFrame = baseCF * CFrame.new(0, 8.5, -0.2),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.35,
		CanCollide = false,
		Parent = model,
	})
	pointLight(door, color, 3, 30)

	-- pad in front for the prompt
	local pad = part({
		Name = "PortalPad",
		Size = Vector3.new(10, 1, 6),
		CFrame = baseCF * CFrame.new(0, 0.5, 4),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		Parent = model,
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
			-- tell the client to fade to black + show the zone label + whoosh,
			-- then teleport mid-fade so the swap is hidden.
			local zoneRemote = Net.event("ZoneEnter")
			if zoneRemote then
				zoneRemote:FireClient(player, { zone = name })
			end
			task.wait(0.22)
			if hrp and hrp.Parent then
				hrp.CFrame = targetCFrame
			end
		end
	end)

	-- floating label
	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.fromOffset(190, 46)
	bg.StudsOffset = Vector3.new(0, 11, 0)
	bg.AlwaysOnTop = true
	bg.Adornee = door
	bg.Parent = door
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextStrokeTransparency = 0.3
	lbl.TextColor3 = color
	lbl.Text = name
	lbl.Parent = bg
	return model
end

local function signBoard(text: string, position: Vector3, color: Color3, parent: Instance, faceYaw: number?)
	local cf = CFrame.new(position) * CFrame.Angles(0, faceYaw or 0, 0)
	local board = part({
		Name = "Sign",
		Size = Vector3.new(16, 4.5, 0.5),
		CFrame = cf,
		Color = Color3.fromRGB(45, 38, 30),
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(480, 135)
	sg.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = sg
	return board
end

-- a circular flat plaza disc
local function disc(name: string, center: Vector3, diameter: number, thickness: number, color: Color3, material: Enum.Material, parent: Instance): Part
	return part({
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(thickness, diameter, diameter),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
		Parent = parent,
	})
end

local function fountain(center: Vector3, parent: Instance)
	-- try the real toolbox fountain first
	local inserted = tryInsert(ASSETS.fountain, center, parent, 14)
	if inserted then
		pointLight(inserted:FindFirstChildWhichIsA("BasePart", true) :: Instance, Color3.fromRGB(150, 210, 255), 2, 30)
		return
	end
	-- part-based tiered fountain fallback
	disc("FountainBase", center + Vector3.new(0, 0.5, 0), 22, 1.5, Color3.fromRGB(150, 145, 135), Enum.Material.Marble, parent)
	disc("FountainPool", center + Vector3.new(0, 1.2, 0), 18, 1, Color3.fromRGB(90, 170, 230), Enum.Material.Glass, parent).Transparency = 0.25
	disc("FountainTier2", center + Vector3.new(0, 3, 0), 10, 1.2, Color3.fromRGB(160, 155, 145), Enum.Material.Marble, parent)
	disc("FountainTier3", center + Vector3.new(0, 5, 0), 5, 1, Color3.fromRGB(170, 165, 155), Enum.Material.Marble, parent)
	local spout = part({
		Name = "FountainSpout",
		Size = Vector3.new(1, 4, 1),
		Position = center + Vector3.new(0, 6.5, 0),
		Color = Color3.fromRGB(170, 165, 155),
		Material = Enum.Material.Marble,
		Parent = parent,
	})
	-- water particles
	local emitterPart = part({
		Name = "WaterJet",
		Size = Vector3.new(0.5, 0.5, 0.5),
		Position = center + Vector3.new(0, 8, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = parent,
	})
	local att = Instance.new("Attachment")
	att.Parent = emitterPart
	local water = Instance.new("ParticleEmitter")
	water.Texture = "rbxassetid://242201991"
	water.Color = ColorSequence.new(Color3.fromRGB(170, 220, 255))
	water.Rate = 60
	water.Lifetime = NumberRange.new(1.2, 1.8)
	water.Speed = NumberRange.new(6, 9)
	water.SpreadAngle = Vector2.new(25, 25)
	water.Acceleration = Vector3.new(0, -20, 0)
	water.Size = NumberSequence.new(0.8)
	water.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	water.Parent = att
	pointLight(spout, Color3.fromRGB(150, 210, 255), 1.5, 24)
end

-- a crystal pedestal with a slowly rotating item + glow + name label
local function crystalPedestal(pos: Vector3, label: string, accent: Color3, parent: Instance, weaponInfo: WeaponConfig.WeaponInfo?)
	tryInsert(ASSETS.crystalPedestal, pos, parent, 4)
	part({
		Name = "PedestalBase",
		Size = Vector3.new(4, 1, 4),
		Position = pos + Vector3.new(0, 0.5, 0),
		Color = Color3.fromRGB(70, 70, 85),
		Material = Enum.Material.Slate,
		Parent = parent,
	})
	part({
		Name = "PedestalColumn",
		Size = Vector3.new(2.4, 4, 2.4),
		Position = pos + Vector3.new(0, 3, 0),
		Color = Color3.fromRGB(90, 90, 110),
		Material = Enum.Material.Marble,
		Parent = parent,
	})
	local crystal = part({
		Name = "Crystal",
		Size = Vector3.new(2, 2, 2),
		Position = pos + Vector3.new(0, 6, 0),
		Color = accent,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CanCollide = false,
		Parent = parent,
	})
	pointLight(crystal, accent, 2.4, 22)

	-- the showcased item: tinted blade-ish part (uses weapon material color)
	local itemColor = weaponInfo and weaponInfo.materialColor or accent
	local item = part({
		Name = "ShowItem",
		Size = Vector3.new(0.5, 5, 0.5),
		Position = pos + Vector3.new(0, 9, 0),
		Color = itemColor,
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = parent,
	})
	addSpinner(item, pos + Vector3.new(0, 9, 0), 1.2)

	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.fromOffset(170, 40)
	bg.StudsOffset = Vector3.new(0, 4, 0)
	bg.AlwaysOnTop = true
	bg.Adornee = crystal
	bg.Parent = crystal
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextStrokeTransparency = 0.4
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.Text = label
	lbl.Parent = bg
end

-- a SurfaceGui board (tall dark stone with gold trim) -> returns the SurfaceGui
local function bigBoard(name: string, center: Vector3, size: Vector3, parent: Instance, faceYaw: number?): SurfaceGui
	local cf = CFrame.new(center) * CFrame.Angles(0, faceYaw or 0, 0)
	-- gold trim frame
	part({
		Name = name .. "Trim",
		Size = size + Vector3.new(2, 2, -0.2),
		CFrame = cf * CFrame.new(0, 0, 0.1),
		Color = Color3.fromRGB(200, 165, 70),
		Material = Enum.Material.Metal,
		Parent = parent,
	})
	local board = part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = Color3.fromRGB(22, 22, 30),
		Material = Enum.Material.Slate,
		Parent = parent,
	})
	local sg = Instance.new("SurfaceGui")
	sg.Name = "BoardGui"
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(800, 440)
	sg.Parent = board
	return sg
end

-- a chest built from parts (lid + body + lock), optionally toolbox-augmented
local function chest(pos: Vector3, color: Color3, accent: Color3, parent: Instance, fancy: boolean, assetId: number?)
	if assetId then
		tryInsert(assetId, pos, parent, 5)
	end
	part({
		Name = "ChestBody",
		Size = Vector3.new(6, 4, 4),
		Position = pos + Vector3.new(0, 2, 0),
		Color = color,
		Material = Enum.Material.WoodPlanks,
		Parent = parent,
	})
	part({
		Name = "ChestLid",
		Size = Vector3.new(6.2, 1.6, 4.2),
		Position = pos + Vector3.new(0, 4.3, 0),
		Color = color,
		Material = Enum.Material.Wood,
		Parent = parent,
	})
	for _, sx in { -2.6, 0, 2.6 } do
		part({
			Name = "ChestBand",
			Size = Vector3.new(0.4, 5.6, 4.3),
			Position = pos + Vector3.new(sx, 2.8, 0),
			Color = accent,
			Material = Enum.Material.Metal,
			Parent = parent,
		})
	end
	local lock = part({
		Name = "ChestLock",
		Size = Vector3.new(1, 1.4, 0.6),
		Position = pos + Vector3.new(0, 3.2, 2.2),
		Color = accent,
		Material = Enum.Material.Metal,
		Parent = parent,
	})
	if fancy then
		pointLight(lock, accent, 2, 18)
		-- golden sparkles
		local att = Instance.new("Attachment")
		att.Parent = lock
		local sp = Instance.new("ParticleEmitter")
		sp.Color = ColorSequence.new(Color3.fromRGB(255, 215, 90))
		sp.LightEmission = 1
		sp.Rate = 18
		sp.Lifetime = NumberRange.new(1, 2)
		sp.Speed = NumberRange.new(1, 3)
		sp.SpreadAngle = Vector2.new(180, 180)
		sp.Size = NumberSequence.new(0.4)
		sp.Parent = att
	end
end

-- ===========================================================================
-- lighting / atmosphere
-- ===========================================================================
local function setupLighting()
	Lighting.GlobalShadows = true
	Lighting.Ambient = Color3.fromRGB(80, 70, 60)
	Lighting.OutdoorAmbient = Color3.fromRGB(90, 80, 70)
	Lighting.Brightness = 2
	Lighting.ColorShift_Top = Color3.fromRGB(255, 220, 180)
	Lighting.ClockTime = 15
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)

	-- atmosphere
	local existingAtmos = Lighting:FindFirstChildOfClass("Atmosphere")
	if existingAtmos then
		existingAtmos:Destroy()
	end
	local atmos = Instance.new("Atmosphere")
	atmos.Density = 0.25
	atmos.Offset = 0.25
	atmos.Color = Color3.fromRGB(199, 170, 140)
	atmos.Decay = Color3.fromRGB(150, 130, 110)
	atmos.Glare = 0.2
	atmos.Haze = 1.6
	atmos.Parent = Lighting

	-- skybox: try the toolbox fantasy skybox, else a warm default Sky
	local gotSky = false
	local ok, result = pcall(function()
		return InsertService:LoadAsset(ASSETS.skybox)
	end)
	if ok and result then
		local sky = result:FindFirstChildWhichIsA("Sky", true)
		if sky then
			for _, s in Lighting:GetChildren() do
				if s:IsA("Sky") then
					s:Destroy()
				end
			end
			sky.Parent = Lighting
			gotSky = true
		end
		result:Destroy()
	end
	if not gotSky and not Lighting:FindFirstChildOfClass("Sky") then
		local sky = Instance.new("Sky")
		sky.SunAngularSize = 14
		sky.Parent = Lighting
	end

	-- subtle bloom + sun rays for the published-game feel
	if not Lighting:FindFirstChildOfClass("BloomEffect") then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 0.5
		bloom.Size = 24
		bloom.Threshold = 1.1
		bloom.Parent = Lighting
	end
	if not Lighting:FindFirstChildOfClass("SunRaysEffect") then
		local rays = Instance.new("SunRaysEffect")
		rays.Intensity = 0.1
		rays.Spread = 0.5
		rays.Parent = Lighting
	end
end

-- ===========================================================================
-- zones
-- ===========================================================================
local function buildHub(world: Instance): (SurfaceGui, SurfaceGui)
	local hub = Instance.new("Model")
	hub.Name = "Hub"
	hub.Parent = world
	local center = WorldConfig.Hub.center

	-- circular stone plaza
	disc("HubPlaza", center - Vector3.new(0, 1, 0), 170, 2, Color3.fromRGB(120, 116, 108), Enum.Material.Slate, hub)
	disc("HubPlazaInlay", center - Vector3.new(0, 0.4, 0), 120, 1.2, Color3.fromRGB(150, 140, 120), Enum.Material.Marble, hub)
	disc("HubPlazaCore", center + Vector3.new(0, 0.1, 0), 40, 1, Color3.fromRGB(180, 160, 110), Enum.Material.Marble, hub)

	-- fountain a bit off-center so the showcase owns the middle
	fountain(center + Vector3.new(0, 0, 34), hub)

	-- 4 pillars at compass points with torches
	local R = 64
	for _, ang in { 45, 135, 225, 315 } do
		local rad = math.rad(ang)
		local p = center + Vector3.new(math.cos(rad) * R, 0, math.sin(rad) * R)
		pillar(p, 22, hub, true)
	end
	-- decorative banners strung between adjacent pillars
	local pillarPts = {}
	for _, ang in { 45, 135, 225, 315 } do
		local rad = math.rad(ang)
		table.insert(pillarPts, center + Vector3.new(math.cos(rad) * R, 22, math.sin(rad) * R))
	end
	local bColors = { Color3.fromRGB(180, 60, 60), Color3.fromRGB(60, 110, 200), Color3.fromRGB(200, 170, 60), Color3.fromRGB(90, 170, 90) }
	for i = 1, #pillarPts do
		local a = pillarPts[i]
		local b = pillarPts[i % #pillarPts + 1]
		banner(a, b, bColors[i], hub)
	end

	-- central rotating legendary sword on a crystal pedestal
	local showcasePos = center + Vector3.new(0, 0, 0)
	part({
		Name = "ShowcasePedestal",
		Size = Vector3.new(6, 6, 6),
		Position = showcasePos + Vector3.new(0, 3, 0),
		Color = Color3.fromRGB(80, 80, 95),
		Material = Enum.Material.Marble,
		Parent = hub,
	})
	local crystalTop = part({
		Name = "ShowcaseCrystal",
		Size = Vector3.new(4, 1.5, 4),
		Position = showcasePos + Vector3.new(0, 6.5, 0),
		Color = Color3.fromRGB(120, 220, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CanCollide = false,
		Parent = hub,
	})
	-- the rotating "legendary sword": glowing gold blade + crossguard + grip
	local swordPivot = showcasePos + Vector3.new(0, 12, 0)
	local blade = part({
		Name = "ShowcaseSword",
		Size = Vector3.new(0.6, 9, 1.6),
		Position = swordPivot,
		Color = Color3.fromRGB(255, 215, 70),
		Material = Enum.Material.Neon,
		CanCollide = false,
		Parent = hub,
	})
	pointLight(blade, Color3.fromRGB(255, 210, 90), 3, 34)
	addSpinner(blade, swordPivot, 0.8)

	-- leaderboard board (tall dark stone, gold trim)
	local boardGui = bigBoard(
		"LeaderboardBoard",
		center + Vector3.new(0, 13, -76),
		Vector3.new(40, 24, 1.4),
		hub,
		0
	)

	-- recent pulls ticker board
	local tickerGui = bigBoard(
		"RecentPullsBoard",
		center + Vector3.new(60, 11, -40),
		Vector3.new(22, 12, 1.2),
		hub,
		math.rad(35)
	)
	tickerGui.CanvasSize = Vector2.new(480, 220)

	-- six glowing portal arches around the plaza, facing center
	local portalR = 72
	local portalDefs = {
		{ name = "Cases", ang = 90, color = Color3.fromRGB(70, 130, 255), target = WorldConfig.CaseArea.spawn },
		{ name = "Leaderboard Hall", ang = 30, color = Color3.fromRGB(255, 200, 70), target = WorldConfig.LeaderboardHall.spawn },
		{ name = "Weapon Hall", ang = 330, color = Color3.fromRGB(180, 90, 255), target = WorldConfig.WeaponHall.spawn },
		{ name = "Trading Post", ang = 270, color = Color3.fromRGB(245, 220, 80), target = WorldConfig.Trading.spawn },
		{ name = "Ranked Arena", ang = 210, color = Color3.fromRGB(255, 70, 80), target = WorldConfig.Ranked.lobby },
		{ name = "Casual Arena", ang = 150, color = Color3.fromRGB(90, 220, 120), target = CFrame.new(WorldConfig.Casual.center + Vector3.new(0, 4, -(WorldConfig.Casual.radius - 10))) },
	}
	for _, d in portalDefs do
		local rad = math.rad(d.ang)
		local pos = center + Vector3.new(math.cos(rad) * portalR, 0, math.sin(rad) * portalR)
		portal(d.name, pos, d.color, d.target, hub, center)
	end

	-- ===== extra hub polish =====
	-- sky dome overhead
	skyDome(center + Vector3.new(0, 0, 0), 240, Color3.fromRGB(150, 180, 230), hub)
	-- decorative checkerboard inlay over the core plaza
	tileFloor(center + Vector3.new(0, 0, 0), 60, 7.5, Color3.fromRGB(180, 165, 120), Color3.fromRGB(150, 135, 100), hub)
	-- grand entrance archway at the spawn point
	grandArch(WorldConfig.Hub.spawn.Position + Vector3.new(0, 0, 6), math.rad(180), hub)
	-- lamp posts ringing the plaza
	for _, ang in { 20, 70, 110, 160, 200, 250, 290, 340 } do
		local rad = math.rad(ang)
		lampPost(center + Vector3.new(math.cos(rad) * 56, 0, math.sin(rad) * 56), Color3.fromRGB(255, 200, 120), hub)
	end
	-- props: barrels, crates, benches near the edges
	barrel(center + Vector3.new(48, 0, 18), hub)
	barrel(center + Vector3.new(50, 0, 22), hub)
	crate(center + Vector3.new(46, 0, 24), hub)
	crate(center + Vector3.new(-48, 0, -16), hub)
	barrel(center + Vector3.new(-50, 0, -20), hub)
	bench(center + Vector3.new(-30, 0, 50), math.rad(0), hub)
	bench(center + Vector3.new(30, 0, 50), math.rad(0), hub)
	bench(center + Vector3.new(0, 0, 58), math.rad(0), hub)
	-- decorative NPC mannequins at key points
	mannequin(center + Vector3.new(-18, 0, 40), math.rad(200), Color3.fromRGB(80, 110, 200), hub)
	mannequin(center + Vector3.new(18, 0, 40), math.rad(160), Color3.fromRGB(200, 90, 90), hub)
	mannequin(center + Vector3.new(40, 0, -8), math.rad(250), Color3.fromRGB(110, 180, 110), hub)
	mannequin(center + Vector3.new(-40, 0, -8), math.rad(290), Color3.fromRGB(180, 160, 80), hub)
	-- grass + flower patches around the plaza edge
	for _, ang in { 35, 100, 145, 215, 305 } do
		local rad = math.rad(ang)
		grassPatch(center + Vector3.new(math.cos(rad) * 82, 0, math.sin(rad) * 82), hub)
	end
	-- ambient wind/birds
	ambientSound("hub", center + Vector3.new(0, 10, 0), 0.25, hub)

	return boardGui, tickerGui
end

local function buildCaseRoom(world: Instance)
	local m = Instance.new("Model")
	m.Name = "CaseArea"
	m.Parent = world
	local c = WorldConfig.CaseArea.center

	-- dark dramatic room
	part({ Name = "CaseFloor", Size = Vector3.new(90, 2, 90), Position = c - Vector3.new(0, 1, 0), Color = Color3.fromRGB(35, 30, 45), Material = Enum.Material.Slate, Parent = m })
	for _, wall in {
		{ off = Vector3.new(0, 12, -45), size = Vector3.new(90, 26, 2) },
		{ off = Vector3.new(0, 12, 45), size = Vector3.new(90, 26, 2) },
		{ off = Vector3.new(-45, 12, 0), size = Vector3.new(2, 26, 90) },
		{ off = Vector3.new(45, 12, 0), size = Vector3.new(2, 26, 90) },
	} do
		part({ Name = "CaseWall", Size = wall.size, Position = c + wall.off, Color = Color3.fromRGB(28, 24, 36), Material = Enum.Material.Slate, Parent = m })
	end
	part({ Name = "CaseCeiling", Size = Vector3.new(90, 2, 90), Position = c + Vector3.new(0, 25, 0), Color = Color3.fromRGB(20, 18, 28), Material = Enum.Material.Slate, Parent = m })

	signBoard("✨ Case Opening ✨  (press C)", c + Vector3.new(0, 8, -43), Color3.fromRGB(180, 120, 255), m, 0)

	-- three ornate chests in a row, progressively grander, with colored spotlights
	local chestDefs = {
		{ x = -22, name = "Basic", color = Color3.fromRGB(120, 90, 60), accent = Color3.fromRGB(150, 150, 160), light = Color3.fromRGB(255, 255, 255), fancy = false, asset = ASSETS.woodenChest },
		{ x = 0, name = "Pro", color = Color3.fromRGB(90, 70, 120), accent = Color3.fromRGB(180, 120, 255), light = Color3.fromRGB(180, 110, 255), fancy = false, asset = ASSETS.woodenChest },
		{ x = 22, name = "Mythic", color = Color3.fromRGB(120, 95, 40), accent = Color3.fromRGB(255, 200, 70), light = Color3.fromRGB(255, 200, 80), fancy = true, asset = ASSETS.treasureChest },
	}
	for _, d in chestDefs do
		local pos = c + Vector3.new(d.x, 0, 0)
		chest(pos, d.color, d.accent, m, d.fancy, d.asset)
		-- spotlight from ceiling
		local lampPart = part({ Name = "CaseSpot", Size = Vector3.new(2, 0.5, 2), Position = c + Vector3.new(d.x, 24, 0), Color = d.light, Material = Enum.Material.Neon, Parent = m })
		local sl = Instance.new("SpotLight")
		sl.Face = Enum.NormalId.Bottom
		sl.Color = d.light
		sl.Brightness = 6
		sl.Range = 40
		sl.Angle = 60
		sl.Parent = lampPart
		-- chest name label
		local bg = Instance.new("BillboardGui")
		bg.Size = UDim2.fromOffset(150, 36)
		bg.StudsOffset = Vector3.new(0, 7, 0)
		bg.AlwaysOnTop = true
		bg.Adornee = lampPart
		bg.Parent = lampPart
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextScaled = true
		lbl.TextColor3 = d.light
		lbl.Text = d.name .. " Case"
		lbl.Parent = bg
	end

	-- recent pulls ticker on the wall
	local ticker = bigBoard("CaseRoomTicker", c + Vector3.new(0, 12, 43), Vector3.new(30, 12, 1.2), m, math.rad(180))
	ticker.Name = "CaseRoomTickerGui"
	local hdr = Instance.new("TextLabel")
	hdr.Size = UDim2.fromScale(1, 1)
	hdr.BackgroundTransparency = 1
	hdr.Font = Enum.Font.GothamBold
	hdr.TextScaled = true
	hdr.TextColor3 = Color3.fromRGB(255, 220, 120)
	hdr.Text = "Recent Pulls appear on the Hub board"
	hdr.Parent = ticker

	-- red carpet leading to the chests
	part({ Name = "Carpet", Size = Vector3.new(14, 0.3, 70), Position = c + Vector3.new(0, 0.15, 8), Color = Color3.fromRGB(140, 25, 30), Material = Enum.Material.Fabric, Parent = m })
	part({ Name = "CarpetTrim", Size = Vector3.new(16, 0.2, 72), Position = c + Vector3.new(0, 0.1, 8), Color = Color3.fromRGB(200, 165, 70), Material = Enum.Material.Metal, Parent = m })
	for _, z in { -44, 44 } do
		part({ Name = "GoldTrim", Size = Vector3.new(90, 1, 1), Position = c + Vector3.new(0, 1, z), Color = Color3.fromRGB(200, 165, 70), Material = Enum.Material.Metal, Parent = m })
	end
	-- dramatic side curtains (neon-edged drapes)
	for _, sx in { -43, 43 } do
		for _, z in { -28, -8, 12, 32 } do
			part({ Name = "Curtain", Size = Vector3.new(0.6, 22, 8), Position = c + Vector3.new(sx, 12, z), Color = Color3.fromRGB(120, 25, 35), Material = Enum.Material.Neon, Transparency = 0.1, Parent = m })
		end
	end
	-- star-like point lights across the ceiling
	for _ = 1, 24 do
		local star = part({ Name = "Star", Size = Vector3.new(0.6, 0.6, 0.6), Position = c + Vector3.new(math.random(-40, 40), 23.5, math.random(-40, 40)), Color = Color3.fromRGB(255, 255, 230), Material = Enum.Material.Neon, CanCollide = false, Parent = m })
		pointLight(star, Color3.fromRGB(255, 250, 220), 0.7, 12)
	end
	-- floating ambient particles
	local fxPart = part({ Name = "RoomFX", Size = Vector3.new(1, 1, 1), Position = c + Vector3.new(0, 12, 0), Transparency = 1, CanCollide = false, Parent = m })
	local fxAtt = Instance.new("Attachment")
	fxAtt.Parent = fxPart
	local fx = Instance.new("ParticleEmitter")
	fx.Color = ColorSequence.new(Color3.fromRGB(200, 150, 255))
	fx.LightEmission = 1
	fx.Rate = 14
	fx.Lifetime = NumberRange.new(4, 7)
	fx.Speed = NumberRange.new(0.5, 1.5)
	fx.SpreadAngle = Vector2.new(180, 180)
	fx.Size = NumberSequence.new(0.4)
	fx.Transparency = NumberSequence.new(0.4)
	fx.Parent = fxAtt
	-- neon "CASE OPENING ROOM" sign above the entrance
	local signPart = part({ Name = "NeonSign", Size = Vector3.new(34, 4, 0.6), Position = c + Vector3.new(0, 22, 39), Color = Color3.fromRGB(180, 120, 255), Material = Enum.Material.Neon, Parent = m })
	pointLight(signPart, Color3.fromRGB(180, 120, 255), 2, 30)
	local ssg = Instance.new("SurfaceGui")
	ssg.Face = Enum.NormalId.Back
	ssg.CanvasSize = Vector2.new(560, 80)
	ssg.Parent = signPart
	local sl2 = Instance.new("TextLabel")
	sl2.Size = UDim2.fromScale(1, 1)
	sl2.BackgroundTransparency = 1
	sl2.Font = Enum.Font.GothamBold
	sl2.TextScaled = true
	sl2.TextColor3 = Color3.fromRGB(255, 255, 255)
	sl2.Text = "CASE OPENING ROOM"
	sl2.Parent = ssg

	portal("Hub", c + Vector3.new(0, 0, 40), Color3.fromRGB(120, 200, 255), WorldConfig.Hub.spawn, m, c)
end

local function buildCasualArena(world: Instance)
	local m = Instance.new("Model")
	m.Name = "CasualArena"
	m.Parent = world
	local c = WorldConfig.Casual.center
	local r = WorldConfig.Casual.radius

	-- sand/dirt floor (named CasualFloor so GameManager can re-theme it)
	part({ Name = "CasualFloor", Size = Vector3.new(r * 2, 2, r * 2), Position = c - Vector3.new(0, 1, 0), Color = WorldConfig.CasualMaps[1].floor, Material = Enum.Material.Sand, Parent = m })

	-- try the toolbox colosseum as a centerpiece shell
	tryInsert(ASSETS.colosseum, c, m, 60)

	-- stepped spectator seating ring (3 tiers)
	for tier = 1, 3 do
		local ringR = r + tier * 6
		local height = tier * 3
		local seg = 28
		for i = 0, seg - 1 do
			local ang = i / seg * math.pi * 2
			local p = c + Vector3.new(math.cos(ang) * ringR, height - 1, math.sin(ang) * ringR)
			part({
				Name = "Seating",
				Size = Vector3.new(8, 2, 5),
				CFrame = CFrame.new(p, Vector3.new(c.X, p.Y, c.Z)),
				Color = WorldConfig.CasualMaps[1].accent,
				Material = Enum.Material.Slate,
				Parent = m,
			})
		end
	end
	-- arena walls (named CasualWall for theming)
	for _, off in {
		Vector3.new(r, 6, 0), Vector3.new(-r, 6, 0), Vector3.new(0, 6, r), Vector3.new(0, 6, -r),
	} do
		local horizontal = math.abs(off.X) < 1
		part({
			Name = "CasualWall",
			Size = horizontal and Vector3.new(r * 2, 12, 2) or Vector3.new(2, 12, r * 2),
			Position = c + off,
			Color = WorldConfig.CasualMaps[1].accent,
			Material = Enum.Material.Slate,
			Parent = m,
		})
	end
	-- ambient red atmosphere lights around the edge
	for _, ang in { 0, 60, 120, 180, 240, 300 } do
		local rad = math.rad(ang)
		local p = c + Vector3.new(math.cos(rad) * (r - 4), 8, math.sin(rad) * (r - 4))
		local lp = part({ Name = "ArenaLight", Size = Vector3.new(1, 3, 1), Position = p, Color = Color3.fromRGB(255, 70, 70), Material = Enum.Material.Neon, Parent = m })
		pointLight(lp, Color3.fromRGB(255, 80, 70), 2, 30)
	end

	-- kill feed board on the wall
	local kf = bigBoard("CasualKillFeed", c + Vector3.new(0, 14, -r), Vector3.new(26, 12, 1.2), m, 0)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.fromRGB(255, 120, 120)
	lbl.Text = "⚔ CASUAL ARENA ⚔\nKills appear in your HUD feed"
	lbl.Parent = kf

	-- partial open-top roof rim (colosseum style) sitting atop the top seating tier
	local roofR = r + 20
	for i = 0, 31 do
		local ang = i / 32 * math.pi * 2
		local p = c + Vector3.new(math.cos(ang) * roofR, 13, math.sin(ang) * roofR)
		part({ Name = "RoofRim", Size = Vector3.new(10, 3, 6), CFrame = CFrame.new(p, Vector3.new(c.X, p.Y, c.Z)), Color = Color3.fromRGB(120, 110, 95), Material = Enum.Material.Slate, Parent = m })
	end
	-- entrance tunnel players walk through (a short roofed corridor on the hub side)
	for _, sx in { -7, 7 } do
		part({ Name = "TunnelWall", Size = Vector3.new(2, 12, 22), Position = c + Vector3.new(sx, 6, -r - 11), Color = Color3.fromRGB(90, 82, 70), Material = Enum.Material.Slate, Parent = m })
	end
	part({ Name = "TunnelRoof", Size = Vector3.new(16, 2, 22), Position = c + Vector3.new(0, 12, -r - 11), Color = Color3.fromRGB(80, 72, 62), Material = Enum.Material.Slate, Parent = m })
	-- arena floor markings (concentric neon rings + center cross)
	disc("ArenaRingOuter", c + Vector3.new(0, 0.2, 0), r * 1.2, 0.4, Color3.fromRGB(220, 180, 120), Enum.Material.Neon, m).Transparency = 0.5
	disc("ArenaRingInner", c + Vector3.new(0, 0.25, 0), r * 0.5, 0.4, Color3.fromRGB(220, 120, 90), Enum.Material.Neon, m).Transparency = 0.5
	part({ Name = "ArenaCross", Size = Vector3.new(r * 1.1, 0.3, 1.5), Position = c + Vector3.new(0, 0.3, 0), Color = Color3.fromRGB(230, 200, 150), Material = Enum.Material.Neon, Transparency = 0.4, Parent = m })
	part({ Name = "ArenaCross", Size = Vector3.new(1.5, 0.3, r * 1.1), Position = c + Vector3.new(0, 0.3, 0), Color = Color3.fromRGB(230, 200, 150), Material = Enum.Material.Neon, Transparency = 0.4, Parent = m })
	ambientSound("casual", c + Vector3.new(0, 10, 0), 0.3, m)

	portal("Hub", c + Vector3.new(0, 0, -r - 10), Color3.fromRGB(120, 200, 255), WorldConfig.Hub.spawn, m, c)
end

local function buildRankedArena(world: Instance)
	local m = Instance.new("Model")
	m.Name = "RankedArena"
	m.Parent = world
	local c = WorldConfig.Ranked.center

	part({ Name = "RankedFloor", Size = Vector3.new(70, 2, 70), Position = c - Vector3.new(0, 1, 0), Color = Color3.fromRGB(45, 38, 45), Material = Enum.Material.Slate, Parent = m })
	-- glowing center circle
	disc("RankedCircle", c + Vector3.new(0, 0.2, 0), 24, 0.6, Color3.fromRGB(255, 70, 80), Enum.Material.Neon, m).Transparency = 0.2
	-- two elevated opposing spawn platforms
	for _, def in {
		{ cf = WorldConfig.Ranked.spawnA, color = Color3.fromRGB(80, 120, 255) },
		{ cf = WorldConfig.Ranked.spawnB, color = Color3.fromRGB(255, 90, 90) },
	} do
		local p = def.cf.Position
		part({ Name = "SpawnPlatform", Size = Vector3.new(14, 2, 14), Position = p - Vector3.new(0, 1, 0), Color = def.color, Material = Enum.Material.Metal, Parent = m })
		pointLight(part({ Name = "PlatGlow", Size = Vector3.new(12, 0.4, 12), Position = p - Vector3.new(0, 0.2, 0), Color = def.color, Material = Enum.Material.Neon, Parent = m }), def.color, 2, 24)
	end
	-- dramatic spotlight from above
	local spot = part({ Name = "RankedSpot", Size = Vector3.new(3, 0.5, 3), Position = c + Vector3.new(0, 40, 0), Color = Color3.fromRGB(255, 255, 255), Material = Enum.Material.Neon, Parent = m })
	local sl = Instance.new("SpotLight")
	sl.Face = Enum.NormalId.Bottom
	sl.Brightness = 8
	sl.Range = 60
	sl.Angle = 45
	sl.Color = Color3.fromRGB(255, 240, 220)
	sl.Parent = spot
	-- rank badges on the surrounding walls
	for _, wall in { Vector3.new(0, 12, -35), Vector3.new(0, 12, 35), Vector3.new(-35, 12, 0), Vector3.new(35, 12, 0) } do
		local horizontal = math.abs(wall.X) < 1
		part({ Name = "RankedWall", Size = horizontal and Vector3.new(70, 24, 2) or Vector3.new(2, 24, 70), Position = c + wall, Color = Color3.fromRGB(30, 26, 32), Material = Enum.Material.Slate, Parent = m })
	end
	local tiers = { { "Bronze", Color3.fromRGB(150, 95, 50) }, { "Silver", Color3.fromRGB(190, 190, 200) }, { "Gold", Color3.fromRGB(255, 200, 40) }, { "Diamond", Color3.fromRGB(80, 220, 240) }, { "Legend", Color3.fromRGB(175, 80, 255) }, { "Mythic", Color3.fromRGB(255, 90, 60) } }
	for i, t in tiers do
		local badge = part({ Name = "RankBadge", Size = Vector3.new(4, 4, 0.4), Position = c + Vector3.new(-25 + (i - 1) * 10, 16, -34.5), Color = t[2], Material = Enum.Material.Neon, Parent = m })
		pointLight(badge, t[2], 1.5, 12)
	end
	signBoard("⚔ RANKED 1v1 ⚔  (press K)", c + Vector3.new(0, 8, 34), Color3.fromRGB(255, 80, 90), m, math.rad(180))

	-- fully enclosing dark roof
	part({ Name = "RankedRoof", Size = Vector3.new(74, 2, 74), Position = c + Vector3.new(0, 24, 0), Color = Color3.fromRGB(20, 18, 22), Material = Enum.Material.Slate, Parent = m })
	-- glowing floor pattern under the center circle (rune cross + ring)
	part({ Name = "RuneLine", Size = Vector3.new(36, 0.3, 1.4), Position = c + Vector3.new(0, 0.25, 0), Color = Color3.fromRGB(255, 60, 80), Material = Enum.Material.Neon, Transparency = 0.3, Parent = m })
	part({ Name = "RuneLine", Size = Vector3.new(1.4, 0.3, 36), Position = c + Vector3.new(0, 0.25, 0), Color = Color3.fromRGB(255, 60, 80), Material = Enum.Material.Neon, Transparency = 0.3, Parent = m })
	disc("RuneRing", c + Vector3.new(0, 0.22, 0), 34, 0.3, Color3.fromRGB(180, 40, 60), Enum.Material.Neon, m).Transparency = 0.4
	-- electric energy particles climbing the four walls
	for _, off in { Vector3.new(0, 12, -34), Vector3.new(0, 12, 34), Vector3.new(-34, 12, 0), Vector3.new(34, 12, 0) } do
		local ep = part({ Name = "EnergyFX", Size = Vector3.new(1, 1, 1), Position = c + off, Transparency = 1, CanCollide = false, Parent = m })
		local att = Instance.new("Attachment")
		att.Parent = ep
		local em = Instance.new("ParticleEmitter")
		em.Color = ColorSequence.new(Color3.fromRGB(255, 90, 110), Color3.fromRGB(255, 200, 220))
		em.LightEmission = 1
		em.Rate = 26
		em.Lifetime = NumberRange.new(0.8, 1.4)
		em.Speed = NumberRange.new(6, 10)
		em.SpreadAngle = Vector2.new(12, 12)
		em.Acceleration = Vector3.new(0, 14, 0)
		em.Size = NumberSequence.new(0.5)
		em.Parent = att
	end
	-- two player-name boards on opposite walls (RankService fills these per match)
	for _, def in { { name = "RankedNameBoardA", z = -34, color = Color3.fromRGB(90, 130, 255) }, { name = "RankedNameBoardB", z = 34, color = Color3.fromRGB(255, 90, 90) } } do
		local bp = part({ Name = def.name, Size = Vector3.new(28, 6, 0.6), Position = c + Vector3.new(0, 20, def.z), Color = Color3.fromRGB(25, 22, 28), Material = Enum.Material.Slate, Parent = m })
		local bsg = Instance.new("SurfaceGui")
		bsg.Name = "Gui"
		bsg.Face = def.z < 0 and Enum.NormalId.Front or Enum.NormalId.Back
		bsg.CanvasSize = Vector2.new(560, 120)
		bsg.Parent = bp
		local bl = Instance.new("TextLabel")
		bl.Name = "Label"
		bl.Size = UDim2.fromScale(1, 1)
		bl.BackgroundTransparency = 1
		bl.Font = Enum.Font.GothamBold
		bl.TextScaled = true
		bl.TextColor3 = def.color
		bl.Text = "—"
		bl.Parent = bsg
	end
	ambientSound("ranked", c + Vector3.new(0, 10, 0), 0.18, m)

	portal("Hub", c + Vector3.new(0, 0, 44), Color3.fromRGB(120, 200, 255), WorldConfig.Hub.spawn, m, c)
end

local function buildTradingPost(world: Instance)
	local m = Instance.new("Model")
	m.Name = "TradingPost"
	m.Parent = world
	local c = WorldConfig.Trading.center

	part({ Name = "TradingFloor", Size = Vector3.new(70, 2, 70), Position = c - Vector3.new(0, 1, 0), Color = Color3.fromRGB(110, 95, 70), Material = Enum.Material.Cobblestone, Parent = m })

	-- market stalls around the edges (toolbox + part fallback)
	local stallSpots = { Vector3.new(-24, 0, -20), Vector3.new(24, 0, -20), Vector3.new(-24, 0, 20), Vector3.new(24, 0, 20) }
	for _, off in stallSpots do
		local pos = c + off
		if not tryInsert(ASSETS.marketStall, pos, m, 10) then
			-- part stall: 4 posts + striped canopy + counter
			for _, px in { -3, 3 } do
				for _, pz in { -2, 2 } do
					part({ Name = "StallPost", Size = Vector3.new(0.6, 8, 0.6), Position = pos + Vector3.new(px, 4, pz), Color = Color3.fromRGB(80, 55, 35), Material = Enum.Material.Wood, Parent = m })
				end
			end
			part({ Name = "StallCanopy", Size = Vector3.new(8, 0.6, 6), Position = pos + Vector3.new(0, 8.3, 0), Color = Color3.fromRGB(190, 70, 70), Material = Enum.Material.Fabric, Parent = m })
			part({ Name = "StallCounter", Size = Vector3.new(8, 3, 1.2), Position = pos + Vector3.new(0, 1.5, 2), Color = Color3.fromRGB(95, 65, 40), Material = Enum.Material.WoodPlanks, Parent = m })
		end
	end

	-- two trading podiums facing each other in the center
	for _, def in { { x = -8, color = Color3.fromRGB(90, 200, 150) }, { x = 8, color = Color3.fromRGB(200, 180, 80) } } do
		part({ Name = "TradePodium", Size = Vector3.new(5, 4, 5), Position = c + Vector3.new(def.x, 2, 0), Color = Color3.fromRGB(70, 60, 45), Material = Enum.Material.WoodPlanks, Parent = m })
		local top = part({ Name = "PodiumTop", Size = Vector3.new(5.4, 0.6, 5.4), Position = c + Vector3.new(def.x, 4.3, 0), Color = def.color, Material = Enum.Material.Neon, Parent = m })
		pointLight(top, def.color, 1.5, 16)
	end

	-- hanging lanterns with warm glow
	for _, off in { Vector3.new(-12, 12, -12), Vector3.new(12, 12, -12), Vector3.new(-12, 12, 12), Vector3.new(12, 12, 12), Vector3.new(0, 12, 0) } do
		local lantern = part({ Name = "Lantern", Size = Vector3.new(1.4, 2, 1.4), Position = c + off, Color = Color3.fromRGB(255, 200, 110), Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false, Parent = m })
		pointLight(lantern, Color3.fromRGB(255, 200, 110), 2, 22)
		part({ Name = "LanternString", Size = Vector3.new(0.1, 6, 0.1), Position = c + off + Vector3.new(0, 4, 0), Color = Color3.fromRGB(40, 30, 20), Parent = m })
	end

	-- colorful striped awnings + signage + lanterns over every stall
	local awningColors = { Color3.fromRGB(200, 70, 70), Color3.fromRGB(70, 130, 200), Color3.fromRGB(80, 180, 120), Color3.fromRGB(210, 170, 70) }
	local stallNames = { "Blades", "Charms", "Curios", "Relics" }
	for i, off in { Vector3.new(-24, 0, -20), Vector3.new(24, 0, -20), Vector3.new(-24, 0, 20), Vector3.new(24, 0, 20) } do
		local pos = c + off
		-- awning (angled striped canopy)
		part({ Name = "Awning", Size = Vector3.new(10, 0.5, 7), CFrame = CFrame.new(pos + Vector3.new(0, 8.6, 0)) * CFrame.Angles(math.rad(-18), 0, 0), Color = awningColors[i], Material = Enum.Material.Fabric, Parent = m })
		part({ Name = "AwningStripe", Size = Vector3.new(10, 0.55, 1.6), CFrame = CFrame.new(pos + Vector3.new(0, 8.62, 2.2)) * CFrame.Angles(math.rad(-18), 0, 0), Color = Color3.fromRGB(245, 240, 235), Material = Enum.Material.Fabric, Parent = m })
		-- stall sign
		local sp = part({ Name = "StallSign", Size = Vector3.new(8, 2, 0.4), Position = pos + Vector3.new(0, 10.5, 0), Color = Color3.fromRGB(60, 45, 30), Material = Enum.Material.Wood, Parent = m })
		local ssg = Instance.new("SurfaceGui")
		ssg.Face = Enum.NormalId.Front
		ssg.CanvasSize = Vector2.new(280, 70)
		ssg.Parent = sp
		local sl = Instance.new("TextLabel")
		sl.Size = UDim2.fromScale(1, 1)
		sl.BackgroundTransparency = 1
		sl.Font = Enum.Font.GothamBold
		sl.TextScaled = true
		sl.TextColor3 = awningColors[i]
		sl.Text = stallNames[i]
		sl.Parent = ssg
		-- a lantern on the stall
		local lan = part({ Name = "StallLantern", Size = Vector3.new(1, 1.6, 1), Position = pos + Vector3.new(3.5, 7.5, 2.5), Color = Color3.fromRGB(255, 200, 110), Material = Enum.Material.Neon, CanCollide = false, Parent = m })
		pointLight(lan, Color3.fromRGB(255, 200, 110), 1.6, 16)
	end
	-- hanging decorative items strung between the front stalls
	for i = 0.2, 0.8, 0.2 do
		local p = (c + Vector3.new(-24, 11, -20)):Lerp(c + Vector3.new(24, 11, -20), i)
		part({ Name = "HangingItem", Size = Vector3.new(1, 1.4, 1), Position = p, Color = Color3.fromRGB(180, 150, 90), Material = Enum.Material.Metal, CanCollide = false, Parent = m })
	end
	-- enclosing roof + low perimeter walls
	part({ Name = "TradingRoof", Size = Vector3.new(72, 2, 72), Position = c + Vector3.new(0, 20, 0), Color = Color3.fromRGB(70, 55, 40), Material = Enum.Material.WoodPlanks, Parent = m })
	for _, off in { Vector3.new(0, 10, -35), Vector3.new(0, 10, 35), Vector3.new(-35, 10, 0), Vector3.new(35, 10, 0) } do
		local horizontal = math.abs(off.X) < 1
		part({ Name = "TradingWall", Size = horizontal and Vector3.new(72, 20, 2) or Vector3.new(2, 20, 72), Position = c + off, Color = Color3.fromRGB(95, 80, 60), Material = Enum.Material.Brick, Parent = m })
	end
	ambientSound("trading", c + Vector3.new(0, 10, 0), 0.22, m)

	signBoard("🤝 TRADING POST  (press T near a player)", c + Vector3.new(0, 9, -33), Color3.fromRGB(255, 220, 90), m, 0)
	portal("Hub", c + Vector3.new(0, 0, 33), Color3.fromRGB(120, 200, 255), WorldConfig.Hub.spawn, m, c)
end

local function buildWeaponHall(world: Instance)
	local m = Instance.new("Model")
	m.Name = "WeaponHall"
	m.Parent = world
	local c = WorldConfig.WeaponHall.center

	-- long hall floor
	part({ Name = "HallFloor", Size = Vector3.new(40, 2, 130), Position = c - Vector3.new(0, 1, 0), Color = Color3.fromRGB(45, 35, 60), Material = Enum.Material.Marble, Parent = m })
	-- walls + ceiling
	for _, def in {
		{ p = Vector3.new(-20, 14, 0), s = Vector3.new(2, 30, 130) },
		{ p = Vector3.new(20, 14, 0), s = Vector3.new(2, 30, 130) },
		{ p = Vector3.new(0, 14, -65), s = Vector3.new(40, 30, 2) },
		{ p = Vector3.new(0, 14, 65), s = Vector3.new(40, 30, 2) },
	} do
		part({ Name = "HallWall", Size = def.s, Position = c + def.p, Color = Color3.fromRGB(36, 28, 50), Material = Enum.Material.Slate, Parent = m })
	end
	part({ Name = "HallCeiling", Size = Vector3.new(40, 2, 130), Position = c + Vector3.new(0, 29, 0), Color = Color3.fromRGB(28, 22, 40), Material = Enum.Material.Slate, Parent = m })
	-- purple atmosphere lights
	for z = -55, 55, 22 do
		local lp = part({ Name = "HallGlow", Size = Vector3.new(2, 0.5, 2), Position = c + Vector3.new(0, 28, z), Color = Color3.fromRGB(170, 90, 255), Material = Enum.Material.Neon, Parent = m })
		pointLight(lp, Color3.fromRGB(170, 90, 255), 2.5, 30)
	end

	-- pedestals down each side, one per base weapon type (15)
	local purple = Color3.fromRGB(180, 100, 255)
	local rows = math.ceil(#WeaponConfig.BaseTypes / 2)
	local startZ = -((rows - 1) * 16) / 2
	for i, base in WeaponConfig.BaseTypes do
		local side = (i % 2 == 0) and 1 or -1
		local row = math.floor((i - 1) / 2)
		local pos = c + Vector3.new(side * 12, 0, startZ + row * 16)
		-- a representative weapon info (Epic, Iron, Normal) for this base type
		local sample = WeaponConfig.getInfo(WeaponConfig.encode(i, 4, 3, 3))
		crystalPedestal(pos, base.name, purple, m, sample)
		-- glowing base ring + rising sparkles
		local glowBase = part({ Name = "PedestalGlow", Size = Vector3.new(4.6, 0.3, 4.6), Position = pos + Vector3.new(0, 1.1, 0), Color = purple, Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false, Parent = m })
		pointLight(glowBase, purple, 1.6, 14)
		local att = Instance.new("Attachment")
		att.Parent = glowBase
		local em = Instance.new("ParticleEmitter")
		em.Color = ColorSequence.new(purple)
		em.LightEmission = 1
		em.Rate = 10
		em.Lifetime = NumberRange.new(1.5, 2.5)
		em.Speed = NumberRange.new(1, 2)
		em.Acceleration = Vector3.new(0, 2, 0)
		em.SpreadAngle = Vector2.new(20, 20)
		em.Size = NumberSequence.new(0.35)
		em.Parent = att
		-- weapon name plate (SurfaceGui on the column)
		local plate = part({ Name = "NamePlate", Size = Vector3.new(3.4, 1, 0.3), Position = pos + Vector3.new(0, 2.2, 1.3), Color = Color3.fromRGB(40, 30, 55), Material = Enum.Material.Slate, Parent = m })
		local psg = Instance.new("SurfaceGui")
		psg.Face = Enum.NormalId.Front
		psg.CanvasSize = Vector2.new(220, 64)
		psg.Parent = plate
		local pl = Instance.new("TextLabel")
		pl.Size = UDim2.fromScale(1, 1)
		pl.BackgroundTransparency = 1
		pl.Font = Enum.Font.GothamBold
		pl.TextScaled = true
		pl.TextColor3 = Color3.fromRGB(220, 180, 255)
		pl.Text = base.name
		pl.Parent = psg
	end

	-- animated-glow entrance sign
	local hallSign = signBoard("⚔ WEAPON COLLECTION ⚔", c + Vector3.new(0, 10, -63), Color3.fromRGB(200, 130, 255), m, 0)
	local glowLight = pointLight(hallSign, Color3.fromRGB(190, 110, 255), 1.5, 26)
	TweenService:Create(glowLight, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Brightness = 4 }):Play()
	-- tag the hall so the client can apply purple fog while inside
	m:SetAttribute("FogZone", true)
	ambientSound("weaponHall", c + Vector3.new(0, 10, 0), 0.2, m)
	portal("Hub", c + Vector3.new(0, 0, -63), Color3.fromRGB(120, 200, 255), WorldConfig.Hub.spawn, m, c)
end

local function buildLeaderboardHall(world: Instance): SurfaceGui
	local m = Instance.new("Model")
	m.Name = "LeaderboardHall"
	m.Parent = world
	local c = WorldConfig.LeaderboardHall.center

	-- marble hall of fame
	part({ Name = "FameFloor", Size = Vector3.new(60, 2, 80), Position = c - Vector3.new(0, 1, 0), Color = Color3.fromRGB(210, 205, 195), Material = Enum.Material.Marble, Parent = m })
	for _, def in {
		{ p = Vector3.new(-30, 14, 0), s = Vector3.new(2, 30, 80) },
		{ p = Vector3.new(30, 14, 0), s = Vector3.new(2, 30, 80) },
		{ p = Vector3.new(0, 14, -40), s = Vector3.new(60, 30, 2) },
		{ p = Vector3.new(0, 14, 40), s = Vector3.new(60, 30, 2) },
	} do
		part({ Name = "FameWall", Size = def.s, Position = c + def.p, Color = Color3.fromRGB(60, 55, 50), Material = Enum.Material.Marble, Parent = m })
	end
	part({ Name = "FameCeiling", Size = Vector3.new(60, 2, 80), Position = c + Vector3.new(0, 29, 0), Color = Color3.fromRGB(45, 42, 38), Material = Enum.Material.Slate, Parent = m })
	-- gold pillars
	for _, x in { -22, 22 } do
		for _, z in { -28, 0, 28 } do
			pillar(c + Vector3.new(x, 0, z), 22, m, false)
		end
	end

	-- top-3 portrait frames on the back wall with spotlights
	for i = 1, 3 do
		local x = (i - 2) * 16
		local frame = part({ Name = "PortraitFrame", Size = Vector3.new(11, 15, 0.6), Position = c + Vector3.new(x, 15, -39), Color = Color3.fromRGB(200, 165, 70), Material = Enum.Material.Metal, Parent = m })
		part({ Name = "PortraitInner", Size = Vector3.new(9, 13, 0.4), Position = c + Vector3.new(x, 15, -38.7), Color = Color3.fromRGB(30, 30, 40), Material = Enum.Material.Slate, Parent = m })
		local rank = Instance.new("BillboardGui")
		rank.Size = UDim2.fromOffset(120, 40)
		rank.StudsOffset = Vector3.new(0, 9, 0)
		rank.AlwaysOnTop = true
		rank.Adornee = frame
		rank.Parent = frame
		local rl = Instance.new("TextLabel")
		rl.Size = UDim2.fromScale(1, 1)
		rl.BackgroundTransparency = 1
		rl.Font = Enum.Font.GothamBold
		rl.TextScaled = true
		rl.TextColor3 = Color3.fromRGB(255, 215, 80)
		rl.Text = "#" .. i
		rl.Parent = rank
		local spot = part({ Name = "PortraitSpot", Size = Vector3.new(1.5, 0.4, 1.5), Position = c + Vector3.new(x, 28, -34), Color = Color3.fromRGB(255, 245, 210), Material = Enum.Material.Neon, Parent = m })
		local sl = Instance.new("SpotLight")
		sl.Face = Enum.NormalId.Bottom
		sl.Brightness = 5
		sl.Range = 30
		sl.Angle = 50
		sl.Color = Color3.fromRGB(255, 240, 210)
		sl.Parent = spot
	end

	-- full leaderboard board in the center
	local boardGui = bigBoard("FameLeaderboard", c + Vector3.new(0, 13, 39), Vector3.new(36, 22, 1.4), m, math.rad(180))

	-- velvet rope barrier in front of the top-3 portrait wall
	for px = -28, 28, 7 do
		local postPos = c + Vector3.new(px, 0, -30)
		part({ Name = "RopePost", Size = Vector3.new(0.6, 4, 0.6), Position = postPos + Vector3.new(0, 2, 0), Color = Color3.fromRGB(200, 165, 70), Material = Enum.Material.Metal, Parent = m })
		part({ Name = "RopeBall", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), Position = postPos + Vector3.new(0, 4.2, 0), Color = Color3.fromRGB(220, 185, 90), Material = Enum.Material.Metal, Parent = m })
		if px < 28 then
			part({ Name = "VelvetRope", Size = Vector3.new(7, 0.4, 0.4), Position = postPos + Vector3.new(3.5, 3.4, 0), Color = Color3.fromRGB(150, 30, 50), Material = Enum.Material.Fabric, Parent = m })
		end
	end
	-- golden trophy on top of the leaderboard board
	local boardTop = c + Vector3.new(0, 25, 39)
	part({ Name = "TrophyBase", Size = Vector3.new(4, 1.2, 4), Position = boardTop, Color = Color3.fromRGB(90, 70, 40), Material = Enum.Material.Wood, Parent = m })
	part({ Name = "TrophyStem", Size = Vector3.new(1, 2.5, 1), Position = boardTop + Vector3.new(0, 1.8, 0), Color = Color3.fromRGB(235, 200, 90), Material = Enum.Material.Metal, Parent = m })
	local cup = part({ Name = "TrophyCup", Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), Position = boardTop + Vector3.new(0, 4, 0), Color = Color3.fromRGB(255, 215, 80), Material = Enum.Material.Neon, Parent = m })
	pointLight(cup, Color3.fromRGB(255, 215, 90), 2.5, 26)
	for _, sx in { -2.2, 2.2 } do
		part({ Name = "TrophyHandle", Size = Vector3.new(0.6, 2.4, 0.6), Position = boardTop + Vector3.new(sx, 4, 0), Color = Color3.fromRGB(235, 200, 90), Material = Enum.Material.Metal, Parent = m })
	end
	ambientSound("leaderboard", c + Vector3.new(0, 10, 0), 0.18, m)

	signBoard("🏆 HALL OF FAME 🏆", c + Vector3.new(0, 26, -39), Color3.fromRGB(255, 215, 80), m, 0)
	portal("Hub", c + Vector3.new(0, 0, 39), Color3.fromRGB(120, 200, 255), WorldConfig.Hub.spawn, m, c)
	return boardGui
end

-- ===========================================================================
-- public entry
-- ===========================================================================
function WorldBuilder.build(): { board: SurfaceGui, recentTicker: SurfaceGui, fameBoard: SurfaceGui? }
	-- clear any prior build (hot reload safety)
	local old = Workspace:FindFirstChild("BladeLegendsWorld")
	if old then
		old:Destroy()
	end

	setupLighting()

	local world = Instance.new("Folder")
	world.Name = "BladeLegendsWorld"
	world.Parent = Workspace

	-- big ground plane
	part({ Name = "Ground", Size = Vector3.new(4000, 2, 4000), Position = Vector3.new(0, 3.9, 30), Color = Color3.fromRGB(70, 95, 65), Material = Enum.Material.Grass, Parent = world })

	-- spawn location in the hub
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = WorldConfig.Hub.spawn - Vector3.new(0, 2.5, 0)
	spawn.Color = Color3.fromRGB(120, 200, 255)
	spawn.Material = Enum.Material.Neon
	spawn.Neutral = true
	spawn.Parent = world

	local board, ticker = buildHub(world)
	buildCaseRoom(world)
	buildCasualArena(world)
	buildRankedArena(world)
	buildTradingPost(world)
	buildWeaponHall(world)
	local fameBoard = buildLeaderboardHall(world)

	-- slow day/night cycle: one full sweep every 10 minutes
	task.spawn(function()
		local CYCLE = 600 -- seconds for a full 24h
		while world.Parent do
			local t = (os.clock() % CYCLE) / CYCLE -- 0..1
			Lighting.ClockTime = t * 24
			-- warm at dawn/dusk, cooler at night
			local night = math.clamp(math.abs(Lighting.ClockTime - 12) / 12, 0, 1)
			Lighting.Brightness = 2.4 - night * 1.2
			Lighting.OutdoorAmbient = Color3.fromRGB(90, 80, 70):Lerp(Color3.fromRGB(40, 40, 60), night)
			task.wait(1)
		end
	end)

	return { board = board, recentTicker = ticker, fameBoard = fameBoard }
end

return WorldBuilder
