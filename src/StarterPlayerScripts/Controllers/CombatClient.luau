--!strict
-- CombatClient: turns local input into combat intent for the server.
--   LMB         -> swing (server owns the hitbox)
--   hold RMB    -> block (also slows you locally for feel)
--   Left Shift  -> dodge roll (server grants i-frames; client adds the dash)
--   Q/E/R/F/G   -> abilities (server validates rarity + cooldown)
-- The client never decides damage; it only requests actions.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local SoundController = require(script.Parent.SoundController)

local CombatClient = {}

local NORMAL_SPEED = 16
local BLOCK_SPEED = 8
local DODGE_COOLDOWN = 1.0

local ABILITY_KEYS = {
	[Enum.KeyCode.Q] = "PowerStrike",
	[Enum.KeyCode.E] = "DashStrike",
	[Enum.KeyCode.R] = "AreaSlam",
	[Enum.KeyCode.F] = "Special",
	[Enum.KeyCode.G] = "Ultimate",
}

function CombatClient.init()
	local player = Players.LocalPlayer
	local lastDodge = 0

	local function humanoid(): Humanoid?
		local char = player.Character
		return char and char:FindFirstChildOfClass("Humanoid")
	end
	local function rootPart(): BasePart?
		local char = player.Character
		return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Net.event("SwingWeapon"):FireServer()
			SoundController.play("swing", 0.6)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			Net.event("SetBlocking"):FireServer({ isBlocking = true })
			local h = humanoid()
			if h then
				h.WalkSpeed = BLOCK_SPEED
			end
		elseif input.KeyCode == Enum.KeyCode.LeftShift then
			local now = os.clock()
			if now - lastDodge < DODGE_COOLDOWN then
				return
			end
			lastDodge = now
			Net.event("DodgeRoll"):FireServer()
			local hrp = rootPart()
			local h = humanoid()
			if hrp and h then
				local moveDir = h.MoveDirection
				if moveDir.Magnitude < 0.1 then
					moveDir = hrp.CFrame.LookVector
				end
				hrp.AssemblyLinearVelocity = moveDir.Unit * 55 + Vector3.new(0, 8, 0)
			end
		else
			local slot = ABILITY_KEYS[input.KeyCode]
			if slot then
				Net.event("UseAbility"):FireServer({ slot = slot })
				SoundController.play("ability", 0.6)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			Net.event("SetBlocking"):FireServer({ isBlocking = false })
			local h = humanoid()
			if h then
				h.WalkSpeed = NORMAL_SPEED
			end
		end
	end)
end

return CombatClient
