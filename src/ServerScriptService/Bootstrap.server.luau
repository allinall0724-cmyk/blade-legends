--!strict
-- Server entry point. Requires the orchestrator and starts the game.
-- Wrapped so a failure in one service is reported clearly instead of silently
-- killing the whole server thread.

local GameManager = require(script.Parent.Services.GameManager)

local ok, err = pcall(function()
	GameManager.init()
end)

if not ok then
	warn("[Blade Legends] FATAL during init:", err)
end
