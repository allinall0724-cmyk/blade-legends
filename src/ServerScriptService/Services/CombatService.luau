--!strict
-- CombatService: server-authoritative melee combat.
-- The client only ever sends intent ("I swung", "I'm blocking", "I dodged").
-- The server owns hitboxes, cooldowns, damage, blocking reduction, dodge
-- invulnerability, death and the weapon visuals applied to the character.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

local Net = require(ReplicatedStorage.Shared.Net)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local RarityConfig = require(ReplicatedStorage.Shared.RarityConfig)
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
		s = { lastSwing = 0, lastDodge = 0, blocking = false, dodgeUntil = 0, weaponInfo = nil, tool = nil }
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

		-- target defensive state
		local oState = getState(other)
		if now < oState.dodgeUntil then
			continue -- dodged: invulnerable
		end
		local dmg = info.damage
		if oState.blocking then
			dmg *= (1 - BLOCK_REDUCTION)
		end

		CombatService._lastAttacker[other.UserId] = player
		ohum:TakeDamage(dmg)

		Net.event("Notification"):FireClient(player, {
			text = ("Hit %s for %d"):format(other.DisplayName, math.floor(dmg)),
			color = info.rarityColor,
			duration = 0.8,
			small = true,
		})
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
end

return CombatService
