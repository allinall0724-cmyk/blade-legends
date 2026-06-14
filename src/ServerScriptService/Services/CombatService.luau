--!strict
-- CombatService: server-authoritative melee combat.
-- The client only ever sends intent ("I swung", "I'm blocking", "I dodged").
-- The server owns hitboxes, cooldowns, damage, blocking reduction, dodge
-- invulnerability, death and the weapon visuals applied to the character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local RarityConfig = require(ReplicatedStorage.Shared.RarityConfig)
local AbilityConfig = require(ReplicatedStorage.Shared.AbilityConfig)
local DataService = require(script.Parent.DataService)

local CombatService = {}

local MAX_HEALTH = 100
local DODGE_COOLDOWN = 1.0
local DODGE_IFRAMES = 0.4
local BLOCK_REDUCTION = 0.5
local SWING_CONE = 0.25 -- min dot product to count as "in front"

type State = {
	lastSwing: number,
	lastDodge: number,
	blocking: boolean,
	dodgeUntil: number,
	weaponInfo: WeaponConfig.WeaponInfo?,
	tool: Instance?,
	-- abilities
	abilityCd: { [string]: number },
	invincibleUntil: number,
	reflectUntil: number,
	counterUntil: number,
	counterConsumed: boolean,
	comboCount: number,
	comboExpire: number,
}

local states: { [number]: State } = {}

-- Hooks set by GameManager to avoid circular requires.
-- DamagePolicy(attacker, victim) -> boolean : may attacker hurt victim right now?
CombatService.DamagePolicy = function(_attacker: Player, _victim: Player): boolean
	return false
end
-- KillHandlers receive (killer, victim) on a confirmed kill.
CombatService.KillHandlers = {} :: { (killer: Player?, victim: Player) -> () }

function CombatService.onKill(fn: (killer: Player?, victim: Player) -> ())
	table.insert(CombatService.KillHandlers, fn)
end

local function getState(player: Player): State
	local s = states[player.UserId]
	if not s then
		s = {
			lastSwing = 0, lastDodge = 0, blocking = false, dodgeUntil = 0, weaponInfo = nil, tool = nil,
			abilityCd = {}, invincibleUntil = 0, reflectUntil = 0, counterUntil = 0, counterConsumed = false,
			comboCount = 0, comboExpire = 0,
		}
		states[player.UserId] = s
	end
	return s
end

-- ---------------------------------------------------------------------------
-- Weapon visuals: load the Toolbox model (free), tint it, scale it, add fx.
-- Falls back to a generated blade Part when the asset can't be loaded
-- (e.g. Studio API access disabled). Either way the player gets a working Tool.
-- ---------------------------------------------------------------------------
local function buildPlaceholderHandle(info: WeaponConfig.WeaponInfo): BasePart
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.6, 0.6, math.clamp(info.reach * 0.5, 3, 8)) * info.sizeMult
	handle.Color = info.materialColor
	handle.Material = Enum.Material.Metal
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	return handle
end

local function applyVisuals(handle: BasePart, info: WeaponConfig.WeaponInfo)
	-- tint
	for _, d in handle:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = info.materialColor
		end
	end
	handle.Color = info.materialColor

	-- particles for Rare+
	if info.hasParticles then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "RarityFX"
		emitter.Rate = 14
		emitter.Lifetime = NumberRange.new(0.4, 0.8)
		emitter.Speed = NumberRange.new(0.5, 1.5)
		emitter.Color = ColorSequence.new(info.materialColor)
		emitter.LightEmission = 0.6
		emitter.Size = NumberSequence.new(0.4 * info.sizeMult)
		if info.particle == "fire" then
			emitter.Color = ColorSequence.new(Color3.fromRGB(255, 140, 30), Color3.fromRGB(255, 60, 0))
			emitter.Rate = 22
		elseif info.particle == "ice" then
			emitter.Color = ColorSequence.new(Color3.fromRGB(180, 230, 255))
		elseif info.particle == "lightning" then
			emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 180))
			emitter.Rate = 26
		end
		emitter.Parent = handle
	end

	-- swing trail for Legendary+
	if info.hasTrail then
		local a0 = Instance.new("Attachment")
		a0.Name = "TrailA0"
		a0.Position = Vector3.new(0, 0, -handle.Size.Z / 2)
		a0.Parent = handle
		local a1 = Instance.new("Attachment")
		a1.Name = "TrailA1"
		a1.Position = Vector3.new(0, 0, handle.Size.Z / 2)
		a1.Parent = handle
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.3
		trail.Color = ColorSequence.new(info.rarityColor)
		trail.LightEmission = 1
		trail.Parent = handle
	end
end

local function loadModelHandle(info: WeaponConfig.WeaponInfo): BasePart
	local ok, modelOrErr = pcall(function()
		return InsertService:LoadAsset(info.assetId)
	end)
	if ok and modelOrErr then
		local container = modelOrErr :: Instance
		-- find a primary part to use as the handle
		local primary: BasePart? = nil
		local model = container:FindFirstChildWhichIsA("Model")
		if model then
			primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		else
			primary = container:FindFirstChildWhichIsA("BasePart", true)
		end
		if primary then
			-- promote `primary` to the Handle and pull every other part under it
			-- (welded) so they travel with the handle when we detach from the
			-- loaded container. Order matters: reparent BEFORE destroying the
			-- container, otherwise destroying the container destroys the handle.
			local handle = primary
			handle.Name = "Handle"
			for _, part in container:GetDescendants() do
				if part:IsA("BasePart") and part ~= handle then
					part.Anchored = false
					part.CanCollide = false
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = handle
					weld.Part1 = part
					weld.Parent = handle
					part.Parent = handle
				end
			end
			handle.Anchored = false
			handle.CanCollide = false
			handle.Size = handle.Size * info.sizeMult
			handle.Parent = nil -- detach handle (and its now-children) safely
			container:Destroy()
			applyVisuals(handle, info)
			return handle
		end
		container:Destroy()
	end
	-- fallback
	local handle = buildPlaceholderHandle(info)
	applyVisuals(handle, info)
	return handle
end

-- Build a Tool for the player's currently equipped weapon and attach it.
function CombatService.equip(player: Player)
	local state = getState(player)
	local character = player.Character
	if not character then
		return
	end
	-- clear old tool
	if state.tool then
		state.tool:Destroy()
		state.tool = nil
	end
	local backpackTool = player:FindFirstChild("Backpack")
	if backpackTool then
		for _, t in (backpackTool :: Instance):GetChildren() do
			if t:IsA("Tool") then
				t:Destroy()
			end
		end
	end

	local weaponId = DataService.getEquipped(player)
	if not weaponId then
		state.weaponInfo = nil
		return
	end
	local info = WeaponConfig.getInfo(weaponId)
	if not info then
		return
	end
	state.weaponInfo = info

	local tool = Instance.new("Tool")
	tool.Name = info.name
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("WeaponId", weaponId)
	tool:SetAttribute("Rarity", info.rarity)

	local handle = loadModelHandle(info)
	handle.Parent = tool

	-- Put the tool in the Backpack and equip via the Humanoid. This is the
	-- reliable path — parenting a Tool straight to the character only equips it
	-- under some conditions and was why equipping appeared to do nothing.
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		tool.Parent = backpack
	else
		tool.Parent = character
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid:EquipTool(tool)
	end
	state.tool = tool

	-- Mythic passive: a constant aura around the player, visible to everyone.
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		local existing = root:FindFirstChild("MythicAura")
		if existing then
			existing:Destroy()
		end
		if info.rarity == "Mythic" then
			local att = Instance.new("Attachment")
			att.Name = "MythicAura"
			att.Parent = root
			local em = Instance.new("ParticleEmitter")
			em.Color = ColorSequence.new(info.rarityColor, Color3.fromRGB(255, 230, 120))
			em.LightEmission = 1
			em.Rate = 30
			em.Lifetime = NumberRange.new(1, 1.6)
			em.Speed = NumberRange.new(2, 4)
			em.SpreadAngle = Vector2.new(180, 180)
			em.Size = NumberSequence.new(0.7)
			em.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			})
			em.Parent = att
		end
	end
end

-- ---------------------------------------------------------------------------
-- Health / name billboard
-- ---------------------------------------------------------------------------
local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.MaxHealth = MAX_HEALTH
	humanoid.Health = MAX_HEALTH

	-- name + rank billboard
	local head = character:WaitForChild("Head", 5)
	if head and not head:FindFirstChild("BL_NameTag") then
		local bg = Instance.new("BillboardGui")
		bg.Name = "BL_NameTag"
		bg.Size = UDim2.fromOffset(180, 44)
		bg.StudsOffset = Vector3.new(0, 2.6, 0)
		bg.AlwaysOnTop = true
		bg.Parent = head

		local name = Instance.new("TextLabel")
		name.Name = "PlayerName"
		name.Size = UDim2.new(1, 0, 0.55, 0)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextScaled = true
		name.TextColor3 = Color3.fromRGB(255, 255, 255)
		name.TextStrokeTransparency = 0.4
		name.Text = player.DisplayName
		name.Parent = bg

		-- health bar
		local barBg = Instance.new("Frame")
		barBg.Name = "HealthBg"
		barBg.Position = UDim2.new(0.1, 0, 0.62, 0)
		barBg.Size = UDim2.new(0.8, 0, 0.22, 0)
		barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		barBg.BorderSizePixel = 0
		barBg.Parent = bg
		local bar = Instance.new("Frame")
		bar.Name = "HealthFill"
		bar.Size = UDim2.new(1, 0, 1, 0)
		bar.BackgroundColor3 = Color3.fromRGB(80, 220, 90)
		bar.BorderSizePixel = 0
		bar.Parent = barBg

		humanoid.HealthChanged:Connect(function(h)
			local frac = math.clamp(h / humanoid.MaxHealth, 0, 1)
			bar.Size = UDim2.new(frac, 0, 1, 0)
			bar.BackgroundColor3 = Color3.fromRGB(
				math.floor(255 * (1 - frac)),
				math.floor(220 * frac),
				70
			)
		end)
	end

	humanoid.Died:Connect(function()
		local killer = CombatService._lastAttacker[player.UserId]
		for _, fn in CombatService.KillHandlers do
			task.spawn(fn, killer, player)
		end
		CombatService._lastAttacker[player.UserId] = nil
	end)

	-- (re)equip weapon shortly after spawn
	task.defer(function()
		CombatService.equip(player)
	end)
end

CombatService._lastAttacker = {} :: { [number]: Player? }

-- forward-declared shared damage path (defined in the abilities section below;
-- assigned at module load, well before any swing is processed at runtime)
local dealDamage: (attacker: Player, victim: Player, amount: number, color: Color3?) -> boolean

-- ---------------------------------------------------------------------------
-- Swing handling: pure server-side hitbox.
-- ---------------------------------------------------------------------------
local function handleSwing(player: Player)
	local state = getState(player)
	local info = state.weaponInfo
	if not info then
		return
	end
	local now = os.clock()
	if now - state.lastSwing < info.cooldown then
		return -- still on cooldown; ignore spam
	end
	state.lastSwing = now

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local myHum = character and character:FindFirstChildOfClass("Humanoid")
	if not hrp or not myHum or myHum.Health <= 0 then
		return
	end

	local origin = hrp.Position
	local look = hrp.CFrame.LookVector

	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		if not CombatService.DamagePolicy(player, other) then
			continue
		end
		local oc = other.Character
		local ohrp = oc and oc:FindFirstChild("HumanoidRootPart") :: BasePart?
		local ohum = oc and oc:FindFirstChildOfClass("Humanoid")
		if not ohrp or not ohum or ohum.Health <= 0 then
			continue
		end
		local toTarget = ohrp.Position - origin
		local dist = toTarget.Magnitude
		if dist > info.reach + 4 then
			continue
		end
		if dist > 0.1 then
			local dir = toTarget.Unit
			if dir:Dot(look) < SWING_CONE then
				continue -- not in front
			end
		end

		-- all defensive handling (dodge i-frames, block, invincibility/reflect,
		-- counter), damage numbers and combo tracking live in dealDamage
		dealDamage(player, other, info.damage, info.rarityColor)
	end
end

local function handleDodge(player: Player)
	local state = getState(player)
	local now = os.clock()
	if now - state.lastDodge < DODGE_COOLDOWN then
		return
	end
	state.lastDodge = now
	state.dodgeUntil = now + DODGE_IFRAMES
end

-- ---------------------------------------------------------------------------
-- Public helpers used by arena services
-- ---------------------------------------------------------------------------
function CombatService.resetHealth(player: Player)
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.Health = hum.MaxHealth
	end
end

function CombatService.getState(player: Player): State
	return getState(player)
end

-- ===========================================================================
-- ABILITIES (server-authoritative). The client only sends {slot}; the server
-- validates rarity unlock + cooldown and applies all damage / effects here.
-- ===========================================================================

-- floating damage number above a world position (replicates to everyone)
local function spawnDamageNumber(position: Vector3, amount: number, color: Color3?)
	local p = Instance.new("Part")
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CFrame = CFrame.new(position + Vector3.new(math.random(-15, 15) / 10, 3, math.random(-15, 15) / 10))
	p.Parent = workspace
	local bg = Instance.new("BillboardGui")
	bg.Size = UDim2.fromOffset(90, 40)
	bg.AlwaysOnTop = true
	bg.Parent = p
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBlack
	lbl.TextScaled = true
	lbl.TextColor3 = color or Color3.fromRGB(255, 90, 90)
	lbl.TextStrokeTransparency = 0.2
	lbl.Text = "-" .. tostring(math.floor(amount))
	lbl.Parent = bg
	TweenService:Create(p, TweenInfo.new(0.9), { CFrame = p.CFrame + Vector3.new(0, 5, 0) }):Play()
	TweenService:Create(lbl, TweenInfo.new(0.9), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1, function()
		p:Destroy()
	end)
end

local function comboHit(attacker: Player)
	local s = getState(attacker)
	local now = os.clock()
	if now > s.comboExpire then
		s.comboCount = 0
	end
	s.comboCount += 1
	s.comboExpire = now + 5
	Net.event("ComboUpdate"):FireClient(attacker, { count = s.comboCount })
end

-- the single authoritative damage path used by swings and every ability
-- (assigns the forward-declared upvalue above so handleSwing can use it)
function dealDamage(attacker: Player, victim: Player, amount: number, color: Color3?): boolean
	local now = os.clock()
	local oc = victim.Character
	local ohrp = oc and oc:FindFirstChild("HumanoidRootPart") :: BasePart?
	local ohum = oc and oc:FindFirstChildOfClass("Humanoid")
	if not ohrp or not ohum or ohum.Health <= 0 then
		return false
	end
	local oState = getState(victim)
	if now < oState.dodgeUntil then
		return false
	end
	-- invincibility (+ optional reflect)
	if now < oState.invincibleUntil then
		if now < oState.reflectUntil then
			local ac = attacker.Character
			local ahum = ac and ac:FindFirstChildOfClass("Humanoid")
			local ahrp = ac and ac:FindFirstChild("HumanoidRootPart") :: BasePart?
			if ahum and ahum.Health > 0 then
				CombatService._lastAttacker[attacker.UserId] = victim
				ahum:TakeDamage(amount)
				if ahrp then
					spawnDamageNumber(ahrp.Position, amount, Color3.fromRGB(255, 210, 90))
				end
			end
		end
		return false
	end
	-- counter window (guard's Counter Slam)
	if now < oState.counterUntil and not oState.counterConsumed then
		oState.counterConsumed = true
		local ac = attacker.Character
		local ahum = ac and ac:FindFirstChildOfClass("Humanoid")
		local ahrp = ac and ac:FindFirstChild("HumanoidRootPart") :: BasePart?
		if ahum and ahum.Health > 0 then
			CombatService._lastAttacker[attacker.UserId] = victim
			ahum:TakeDamage(amount * 2)
			if ahrp then
				spawnDamageNumber(ahrp.Position, amount * 2, Color3.fromRGB(120, 220, 255))
			end
		end
		return false
	end
	local dmg = amount
	if oState.blocking then
		dmg *= (1 - BLOCK_REDUCTION)
	end
	CombatService._lastAttacker[victim.UserId] = attacker
	ohum:TakeDamage(dmg)
	spawnDamageNumber(ohrp.Position, dmg, color)
	comboHit(attacker)
	return true
end

local function enemiesInRadius(attacker: Player, center: Vector3, radius: number): { Player }
	local out = {}
	for _, other in Players:GetPlayers() do
		if other == attacker then
			continue
		end
		if not CombatService.DamagePolicy(attacker, other) then
			continue
		end
		local oc = other.Character
		local ohrp = oc and oc:FindFirstChild("HumanoidRootPart") :: BasePart?
		local ohum = oc and oc:FindFirstChildOfClass("Humanoid")
		if ohrp and ohum and ohum.Health > 0 and (ohrp.Position - center).Magnitude <= radius then
			table.insert(out, other)
		end
	end
	return out
end

local function nearestEnemy(attacker: Player, fromPos: Vector3, maxRange: number): Player?
	local best: Player? = nil
	local bestD = maxRange
	for _, other in Players:GetPlayers() do
		if other == attacker or not CombatService.DamagePolicy(attacker, other) then
			continue
		end
		local oc = other.Character
		local ohrp = oc and oc:FindFirstChild("HumanoidRootPart") :: BasePart?
		local ohum = oc and oc:FindFirstChildOfClass("Humanoid")
		if ohrp and ohum and ohum.Health > 0 then
			local d = (ohrp.Position - fromPos).Magnitude
			if d < bestD then
				bestD = d
				best = other
			end
		end
	end
	return best
end

local function knockback(victim: Player, fromPos: Vector3, force: number)
	local oc = victim.Character
	local ohrp = oc and oc:FindFirstChild("HumanoidRootPart") :: BasePart?
	if ohrp then
		local dir = ohrp.Position - fromPos
		if dir.Magnitude < 0.1 then
			dir = Vector3.new(0, 1, 0)
		end
		ohrp.AssemblyLinearVelocity = dir.Unit * force + Vector3.new(0, 30, 0)
	end
end

-- expanding neon shockwave ring
local function ringEffect(center: Vector3, color: Color3, maxR: number)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.CanCollide = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.2
	p.Size = Vector3.new(1, 4, 4)
	p.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = workspace
	TweenService:Create(p, TweenInfo.new(0.6), { Size = Vector3.new(1, maxR * 2, maxR * 2), Transparency = 1 }):Play()
	task.delay(0.7, function()
		p:Destroy()
	end)
end

local function explosionFX(center: Vector3, color: Color3, size: number)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.1
	p.Size = Vector3.new(2, 2, 2)
	p.Position = center
	p.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 4
	light.Range = size * 1.5
	light.Parent = p
	TweenService:Create(p, TweenInfo.new(0.5), { Size = Vector3.new(size, size, size), Transparency = 1 }):Play()
	task.delay(0.6, function()
		p:Destroy()
	end)
end

-- server-authoritative projectile (moves a neon part, AoE on first contact)
local function spawnProjectile(attacker: Player, startPos: Vector3, dir: Vector3, speed: number, lifetime: number, hitRadius: number, damage: number, color: Color3)
	local proj = Instance.new("Part")
	proj.Shape = Enum.PartType.Ball
	proj.Size = Vector3.new(2.2, 2.2, 2.2)
	proj.Color = color
	proj.Material = Enum.Material.Neon
	proj.Anchored = true
	proj.CanCollide = false
	proj.Position = startPos
	proj.Parent = workspace
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 3
	light.Range = 12
	light.Parent = proj
	task.spawn(function()
		local t = 0
		local step = dir.Unit * speed * 0.03
		while t < lifetime and proj.Parent do
			proj.Position += step
			t += 0.03
			local hit = enemiesInRadius(attacker, proj.Position, hitRadius + 2)
			if #hit > 0 then
				explosionFX(proj.Position, color, hitRadius * 2)
				for _, e in hit do
					dealDamage(attacker, e, damage, color)
				end
				break
			end
			task.wait(0.03)
		end
		proj:Destroy()
	end)
end

-- frontal cone melee used by Power Strike / Ground Shatter
local function meleeCone(attacker: Player, reach: number, dmg: number, color: Color3)
	local char = attacker.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local origin = hrp.Position
	local look = hrp.CFrame.LookVector
	for _, other in Players:GetPlayers() do
		if other == attacker or not CombatService.DamagePolicy(attacker, other) then
			continue
		end
		local oc = other.Character
		local ohrp = oc and oc:FindFirstChild("HumanoidRootPart") :: BasePart?
		local ohum = oc and oc:FindFirstChildOfClass("Humanoid")
		if not ohrp or not ohum or ohum.Health <= 0 then
			continue
		end
		local to = ohrp.Position - origin
		local dist = to.Magnitude
		if dist > reach + 4 then
			continue
		end
		if dist > 0.1 and to.Unit:Dot(look) < SWING_CONE then
			continue
		end
		dealDamage(attacker, other, dmg, color)
	end
end

-- 3 orbiting cosmetic parts that follow the player for `duration`
local function orbitVisual(player: Player, count: number, color: Color3, duration: number, shape: Enum.PartType)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local parts = {}
	for i = 1, count do
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = Vector3.new(0.6, 4, 0.6)
		p.Color = color
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = false
		p.Parent = workspace
		parts[i] = p
	end
	task.spawn(function()
		local t = 0
		while t < duration and hrp.Parent do
			for i, p in parts do
				local ang = t * 4 + (i / count) * math.pi * 2
				p.CFrame = CFrame.new(hrp.Position + Vector3.new(math.cos(ang) * 6, 2, math.sin(ang) * 6)) * CFrame.Angles(math.rad(90), 0, 0)
			end
			t += 0.05
			task.wait(0.05)
		end
		for _, p in parts do
			p:Destroy()
		end
	end)
end

local function fortressBubble(player: Player, duration: number, color: Color3)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local bubble = Instance.new("Part")
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.new(9, 9, 9)
	bubble.Color = color
	bubble.Material = Enum.Material.ForceField
	bubble.Transparency = 0.3
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble.Parent = workspace
	task.spawn(function()
		local t = 0
		while t < duration and hrp.Parent do
			bubble.Position = hrp.Position
			t += 0.05
			task.wait(0.05)
		end
		bubble:Destroy()
	end)
end

-- effect dispatch
local function runEffect(player: Player, slot: string, info: WeaponConfig.WeaponInfo, category: string)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp then
		return
	end
	local s = getState(player)
	local color = info.rarityColor
	local base = info.damage

	if slot == "PowerStrike" then
		task.delay(0.3, function()
			meleeCone(player, info.reach + 2, base * AbilityConfig.PowerStrikeMult, color)
		end)
	elseif slot == "DashStrike" then
		local dir = hum and hum.MoveDirection or hrp.CFrame.LookVector
		if dir.Magnitude < 0.1 then
			dir = hrp.CFrame.LookVector
		end
		hrp.AssemblyLinearVelocity = dir.Unit * 90 + Vector3.new(0, 10, 0)
		task.spawn(function()
			local hitOne = false
			for _ = 1, 12 do
				task.wait(0.03)
				if hitOne or not hrp.Parent then
					break
				end
				local hit = enemiesInRadius(player, hrp.Position, info.reach)
				if #hit > 0 then
					dealDamage(player, hit[1], base * AbilityConfig.DashStrikeMult, color)
					hitOne = true
				end
			end
		end)
	elseif slot == "AreaSlam" then
		ringEffect(hrp.Position, color, AbilityConfig.AreaSlamRadius)
		for _, e in enemiesInRadius(player, hrp.Position, AbilityConfig.AreaSlamRadius) do
			dealDamage(player, e, base * AbilityConfig.AreaSlamMult, color)
		end
	elseif slot == "Special" then
		if category == "blade" then
			task.spawn(function()
				for _ = 1, 5 do
					if not hrp.Parent then break end
					ringEffect(hrp.Position, color, 10)
					for _, e in enemiesInRadius(player, hrp.Position, 10) do
						dealDamage(player, e, base * 0.6, color)
					end
					task.wait(0.18)
				end
			end)
		elseif category == "blunt" then
			local center = hrp.Position + hrp.CFrame.LookVector * info.reach
			explosionFX(center, color, 12)
			for _, e in enemiesInRadius(player, center, info.reach + 4) do
				dealDamage(player, e, base * 2, color)
			end
		elseif category == "magic" then
			spawnProjectile(player, hrp.Position + hrp.CFrame.LookVector * 3 + Vector3.new(0, 2, 0), hrp.CFrame.LookVector, 85, 2, 12, base * 1.8, color)
		elseif category == "ranged" then
			local target = hrp.Position + hrp.CFrame.LookVector * 30
			for _ = 1, 5 do
				local off = Vector3.new(math.random(-12, 12), 0, math.random(-12, 12))
				explosionFX(target + off, color, 6)
				for _, e in enemiesInRadius(player, target + off, 8) do
					dealDamage(player, e, base * 0.8, color)
				end
			end
		elseif category == "polearm" then
			local tgt = nearestEnemy(player, hrp.Position, 70)
			if tgt and tgt.Character then
				local thrp = tgt.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if thrp then
					hrp.CFrame = thrp.CFrame * CFrame.new(0, 0, 4)
					explosionFX(thrp.Position, color, 8)
					dealDamage(player, tgt, base * 2.5, color)
				end
			end
		elseif category == "guard" then
			s.counterUntil = os.clock() + 2.5
			s.counterConsumed = false
			Net.event("Notification"):FireClient(player, { text = "Counter ready! Next hit is reflected x2", color = color, duration = 2.5 })
		end
	elseif slot == "Ultimate" then
		if category == "blade" then
			orbitVisual(player, 3, color, 5, Enum.PartType.Block)
			task.spawn(function()
				local t = 0
				while t < 5 and hrp.Parent do
					for _, e in enemiesInRadius(player, hrp.Position, 14) do
						dealDamage(player, e, base * 0.5, color)
					end
					t += 0.5
					task.wait(0.5)
				end
			end)
		elseif category == "blunt" then
			explosionFX(hrp.Position, color, 34)
			ringEffect(hrp.Position, color, 30)
			for _, e in enemiesInRadius(player, hrp.Position, 30) do
				knockback(e, hrp.Position, 90)
				dealDamage(player, e, base * 2.5, color)
			end
		elseif category == "magic" then
			explosionFX(hrp.Position, color, 28)
			for _, e in enemiesInRadius(player, hrp.Position, 25) do
				dealDamage(player, e, base * 3, color)
			end
		elseif category == "ranged" then
			local target = hrp.Position + hrp.CFrame.LookVector * 30
			task.spawn(function()
				for _ = 1, 4 do
					if not hrp.Parent then break end
					explosionFX(target + Vector3.new(math.random(-14, 14), 0, math.random(-14, 14)), color, 8)
					for _, e in enemiesInRadius(player, target, 18) do
						dealDamage(player, e, base * 0.4, color)
					end
					task.wait(0.4)
				end
			end)
		elseif category == "polearm" then
			orbitVisual(player, 3, color, 5, Enum.PartType.Block)
			task.spawn(function()
				local t = 0
				while t < 5 and hrp.Parent do
					for _, e in enemiesInRadius(player, hrp.Position, 16) do
						dealDamage(player, e, base * 0.5, color)
					end
					t += 0.5
					task.wait(0.5)
				end
			end)
		elseif category == "guard" then
			s.invincibleUntil = os.clock() + 3
			s.reflectUntil = os.clock() + 3
			fortressBubble(player, 3, color)
			Net.event("Notification"):FireClient(player, { text = "FORTRESS! Invincible & reflecting for 3s", color = color, duration = 3 })
		end
	end
end

local function handleAbility(player: Player, slot: string)
	if typeof(slot) ~= "string" or not AbilityConfig.Cooldown[slot] then
		return -- only Q/E/R/F/G are abilities (Basic is the swing path)
	end
	local state = getState(player)
	local info = state.weaponInfo
	if not info then
		return
	end
	-- rarity gate
	if not AbilityConfig.isUnlocked(slot, info.rarity) then
		Net.event("Notification"):FireClient(player, { text = AbilityConfig.Key[slot] .. " ability locked for this rarity", color = Color3.fromRGB(220, 120, 60), duration = 1.5, small = true })
		return
	end
	-- cooldown
	local cd = AbilityConfig.Cooldown[slot] or 0
	local now = os.clock()
	local last = state.abilityCd[slot] or -999
	if now - last < cd then
		return
	end
	state.abilityCd[slot] = now

	-- character must be alive
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		state.abilityCd[slot] = -999 -- refund
		return
	end

	local category = AbilityConfig.categoryOf(info.baseType)
	local aInfo = AbilityConfig.info(slot, category)
	Net.event("AbilityFlash"):FireClient(player, { name = aInfo.name, color = info.rarityColor })
	Net.event("AbilityState"):FireClient(player, { slot = slot, remaining = cd, duration = cd })

	local ok, err = pcall(runEffect, player, slot, info, category)
	if not ok then
		warn("[CombatService] ability effect error:", err)
	end
end

function CombatService.init()
	local function hook(player: Player)
		getState(player)
		if player.Character then
			setupCharacter(player, player.Character)
		end
		player.CharacterAdded:Connect(function(char)
			setupCharacter(player, char)
		end)
	end
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(player)
		states[player.UserId] = nil
		CombatService._lastAttacker[player.UserId] = nil
	end)

	Net.event("SwingWeapon").OnServerEvent:Connect(function(player)
		handleSwing(player)
	end)
	Net.event("SetBlocking").OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		getState(player).blocking = payload.isBlocking == true
	end)
	Net.event("DodgeRoll").OnServerEvent:Connect(function(player)
		handleDodge(player)
	end)
	Net.event("UseAbility").OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		handleAbility(player, payload.slot)
	end)
end

return CombatService
