--!strict
-- Net: single source of truth for every RemoteEvent / RemoteFunction in the game.
-- The server calls Net.init() once to create the Remotes folder and instances;
-- both sides then use Net.event()/Net.func() to fetch them (client waits).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

-- RemoteEvents (server <-> client signals).
Net.Events = {
	"OpenCase",          -- client -> server : request a case open {caseId}
	"CaseResult",        -- server -> client : {weaponInfo, caseId}
	"EquipWeapon",       -- client -> server : {weaponId}
	"DiscardWeapon",     -- client -> server : {weaponId}
	"InitiateTrade",     -- client -> server : {targetUserId}
	"TradeAction",       -- client <-> server : {action, ...}
	"EnterRankedQueue",  -- client -> server
	"LeaveQueue",        -- client -> server
	"EnterCasual",       -- client -> server : join/leave casual arena
	"LeaveCasual",       -- client -> server
	"SwingWeapon",       -- client -> server : {targetUserId?, originCFrame}
	"SetBlocking",       -- client -> server : {isBlocking}
	"DodgeRoll",         -- client -> server : {direction}
	"UpdateHUD",         -- server -> client : full HUD state snapshot
	"Notification",      -- server -> client : {text, color?, duration?}
	"KillFeed",          -- server -> client : {killer, victim, weapon}
	"Announcement",      -- server -> client : server-wide banner {text, color?}
	"LeaderboardUpdate", -- server -> client : {entries}
	"MatchState",        -- server -> client : ranked/casual match status
	"RequestData",       -- client -> server : ask for a fresh UpdateHUD push
	"BuyProduct",        -- client -> server : {productKey}
	"ClaimDaily",        -- client -> server : claim daily login reward
	"RecentPull",        -- server -> client : case ticker {player, weapon, rarity}
	"ZoneEnter",         -- server -> client : {zone} -> fade + label + whoosh
	"UseAbility",        -- client -> server : {slot}  slot in Q/E/R/F/G
	"AbilityState",      -- server -> client : {slot, remaining, duration} cooldown UI
	"AbilityFlash",      -- server -> client : {name, color} ability-name flash
	"ComboUpdate",       -- server -> client : {count} combo counter
	"KillNotify",        -- server -> client : {coins?} you-got-a-kill popup
	"PromoPopup",        -- server -> client : {kind,title,body,productKey?,robux?,color?}
	"PickNameColor",     -- client -> server : {idx} choose name-tag color
	"EquipTitle",        -- client -> server : {title} equip an owned title
	"SellBlade",         -- client -> server : {weaponId} sell a Blade for coins
	"TutorialStep",      -- server -> client : {step,text} new-player tutorial
	"ClaimFreeCrate",    -- client -> server : claim the daily free crate
	"TradeFeed",         -- server -> client : {a,aBlade,b,bBlade,legendary} feed entry
}

-- RemoteFunctions (request/response).
Net.Functions = {
	"GetInventory",    -- () -> { weaponId... }  for the requesting player
	"GetCollection",   -- (userId) -> summarised collection for board preview
	"GetShopInfo",     -- () -> passes/products + owned flags
	"GetTitles",       -- () -> { owned, equipped } for the requesting player
	"GetTradeHistory", -- () -> last 20 trades for the requesting player
}

local function remotesFolder(): Instance
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = "RemoteEvents"
			folder.Parent = ReplicatedStorage
		end
		return folder
	else
		return ReplicatedStorage:WaitForChild("RemoteEvents", 30) or ReplicatedStorage
	end
end

-- Server-only: create the folder and every remote instance.
function Net.init()
	assert(RunService:IsServer(), "Net.init() is server-only")
	local folder = remotesFolder()
	for _, name in Net.Events do
		if not folder:FindFirstChild(name) then
			local ev = Instance.new("RemoteEvent")
			ev.Name = name
			ev.Parent = folder
		end
	end
	for _, name in Net.Functions do
		if not folder:FindFirstChild(name) then
			local fn = Instance.new("RemoteFunction")
			fn.Name = name
			fn.Parent = folder
		end
	end
end

function Net.event(name: string): RemoteEvent
	local folder = remotesFolder()
	if RunService:IsServer() then
		return folder:FindFirstChild(name) :: RemoteEvent
	end
	return folder:WaitForChild(name, 30) :: RemoteEvent
end

function Net.func(name: string): RemoteFunction
	local folder = remotesFolder()
	if RunService:IsServer() then
		return folder:FindFirstChild(name) :: RemoteFunction
	end
	return folder:WaitForChild(name, 30) :: RemoteFunction
end

return Net
