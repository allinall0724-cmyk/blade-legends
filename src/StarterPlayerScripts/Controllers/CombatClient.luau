--!strict
-- CombatClient: turns local input into combat intent for the server.
--   LMB        -> swing (server owns the hitbox)
--   hold RMB   -> block (also slows you locally for feel)
--   Q          -> dodge roll (server grants i-frames; client adds the dash)
-- The client never decides damage; it only requests actions.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)

local CombatClient = {}

local NORMAL_SPEED = 16
local BLOCK_SPEED = 8
local DODGE_COOLDOWN = 1.0

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
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			Net.event("SetBlocking"):FireServer({ isBlocking = true })
			local h = humanoid()
			if h then
				h.WalkSpeed = BLOCK_SPEED
			end
		elseif input.KeyCode == Enum.KeyCode.Q then
			local now = os.clock()
			if now - lastDodge < DODGE_COOLDOWN then
				return
			end
			lastDodge = now
			Net.event("DodgeRoll"):FireServer()
			-- local dash in movement direction
			local hrp = rootPart()
			local h = humanoid()
			if hrp and h then
				local moveDir = h.MoveDirection
				if moveDir.Magnitude < 0.1 then
					moveDir = hrp.CFrame.LookVector
				end
				hrp.AssemblyLinearVelocity = moveDir.Unit * 55 + Vector3.new(0, 8, 0)
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
