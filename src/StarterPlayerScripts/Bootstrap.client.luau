--!strict
-- Client entry point: initialise UI first (so screens exist), then input + combat.

local Controllers = script.Parent.Controllers

local UIManager = require(Controllers.UIManager)
local CombatClient = require(Controllers.CombatClient)
local InputHandler = require(Controllers.InputHandler)

local function safe(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(("[Blade Legends Client] %s init failed: %s"):format(name, tostring(err)))
	end
end

safe("UIManager", UIManager.init)
safe("CombatClient", CombatClient.init)
safe("InputHandler", InputHandler.init)

print("[Blade Legends] Client ready.")
