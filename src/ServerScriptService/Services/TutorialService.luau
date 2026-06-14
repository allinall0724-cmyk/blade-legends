--!strict
-- TutorialService: first-time guided tutorial (+200 bonus coins) and new-player
-- status — the "NEW" tag for the first 30 minutes and the < 10-Blade flag used by
-- trade protection.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local DataService = require(script.Parent.DataService)

local TutorialService = {}

local NEW_TAG_SECONDS = 30 * 60

local STEPS = {
	"Welcome to Blade Legends! You're a Blade Collector. Your goal: find the rarest Blades in existence.",
	"Open your first free Crate!  (Press C, then 🎁 Free Daily Crate)",
	"You got your first Blade! Check your inventory.  (Press I)",
	"Equip your Blade to show it off!  (Select it, then Equip)",
	"Trade with other players to upgrade your collection!  (Press T near a player)",
	"You're ready! Good luck, Collector.  (+200 bonus coins)",
}

-- A player counts as "new" (protected) while they own fewer than 10 Blades.
function TutorialService.isNewPlayer(player: Player): boolean
	local prof = DataService.get(player)
	return prof ~= nil and #prof.weapons < 10
end

function TutorialService.init()
	DataService.onLoaded(function(player)
		local prof = DataService.get(player)
		if not prof then
			return
		end

		-- NEW tag for the first 30 minutes of the session (while still new)
		if #prof.weapons < 10 then
			player:SetAttribute("NewTag", true)
			task.delay(NEW_TAG_SECONDS, function()
				if player.Parent then
					player:SetAttribute("NewTag", false)
				end
			end)
		end

		-- first-time tutorial
		if not prof.tutorialDone then
			prof.tutorialDone = true
			DataService.addCoins(player, 200, false)
			task.delay(3, function()
				if player.Parent then
					Net.event("TutorialStep"):FireClient(player, { steps = STEPS })
				end
			end)
		end
	end)
end

return TutorialService
