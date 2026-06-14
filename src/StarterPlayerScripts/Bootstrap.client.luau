--!strict
-- Client entry point. Every require AND every init is isolated in pcall so that
-- a failure in one module can never take down the rest of the client (which was
-- the root cause of the HUD / inventory / equip UI all silently dying while the
-- server kept working).

local Controllers = script.Parent.Controllers

local function safeRequire(name: string): any
	local ok, mod = pcall(require, Controllers[name])
	if not ok then
		warn(("[Blade Legends Client] require %s FAILED: %s"):format(name, tostring(mod)))
		return nil
	end
	return mod
end

local function safeInit(name: string, mod: any)
	if not mod or typeof(mod.init) ~= "function" then
		warn(("[Blade Legends Client] %s has no init()"):format(name))
		return
	end
	local ok, err = pcall(mod.init)
	if not ok then
		warn(("[Blade Legends Client] %s init failed: %s"):format(name, tostring(err)))
	else
		print(("[Blade Legends] %s ready"):format(name))
	end
end

local SoundController = safeRequire("SoundController")
local ZoneController = safeRequire("ZoneController")
local UIManager = safeRequire("UIManager")
local CombatClient = safeRequire("CombatClient")
local InputHandler = safeRequire("InputHandler")

-- UIManager first so screens exist before input/combat reference them
safeInit("SoundController", SoundController)
safeInit("UIManager", UIManager)
safeInit("ZoneController", ZoneController)
safeInit("CombatClient", CombatClient)
safeInit("InputHandler", InputHandler)

print("[Blade Legends] Client bootstrap complete.")
