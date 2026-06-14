--!strict
-- Client entry point: initialise UI first (so screens exist), then input + combat.

local Controllers = script.Parent.Controllers

local SoundController = require(Controllers.SoundController)
local ZoneController = require(Controllers.ZoneController)
local UIManager = require(Controllers.UIManager)
local CombatClient = require(Controllers.CombatClient)
local InputHandler = require(Controllers.InputHandler)

local function safe(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(("[Blade Legends Client] %s init failed: %s"):format(name, tostring(err)))
	end
end

safe("SoundController", SoundController.init)
safe("UIManager", UIManager.init)
safe("ZoneController", ZoneController.init)
safe("CombatClient", CombatClient.init)
safe("InputHandler", InputHandler.init)

print("[Blade Legends] Client ready.")
