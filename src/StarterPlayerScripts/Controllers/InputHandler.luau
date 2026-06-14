--!strict
-- InputHandler: hotkeys for opening screens and the "E to trade nearest player".

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local UIManager = require(script.Parent.UIManager)

local InputHandler = {}

local TRADE_RANGE = 30

local KEYMAP = {
	[Enum.KeyCode.I] = "inventory",
	[Enum.KeyCode.B] = "shop",
	[Enum.KeyCode.L] = "leaderboard",
	[Enum.KeyCode.C] = "cases",
	[Enum.KeyCode.K] = "ranked",
	[Enum.KeyCode.P] = "settings",
}

function InputHandler.init()
	local player = Players.LocalPlayer

	local function nearestPlayer(): Player?
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			return nil
		end
		local best: Player? = nil
		local bestDist = TRADE_RANGE
		for _, other in Players:GetPlayers() do
			if other ~= player and other.Character then
				local ohrp = other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if ohrp then
					local d = (ohrp.Position - hrp.Position).Magnitude
					if d < bestDist then
						bestDist = d
						best = other
					end
				end
			end
		end
		return best
	end

	print("[Blade Legends] InputHandler bound (I=inventory, B=shop, L=leaderboard, C=cases, K=arenas, P=settings)")

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local screen = KEYMAP[input.KeyCode]
		if screen then
			print("[Blade Legends] menu key:", input.KeyCode.Name, "->", screen)
			UIManager.toggle(screen)
		elseif input.KeyCode == Enum.KeyCode.T then
			-- T initiates a trade with the nearest player (E is the Dash Strike ability)
			local target = nearestPlayer()
			if target then
				Net.event("InitiateTrade"):FireServer({ targetUserId = target.UserId })
			end
		end
	end)
end

return InputHandler
