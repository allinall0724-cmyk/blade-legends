--!strict
-- TradeService: peer-to-peer weapon trading with anti-scam safeguards.
-- Flow: initiate -> accept -> both build offers (<=4 each) -> both Ready ->
-- 3s countdown -> server re-validates ownership -> atomic swap -> log.
-- Either side editing an offer clears both Ready flags.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Net)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local DataService = require(script.Parent.DataService)

local TradeService = {}

local MAX_OFFER = 4
local MAX_DISTANCE = 30 -- studs; must be near each other to start
local COUNTDOWN = 3

type Side = { player: Player, offer: { number }, ready: boolean, accepted: boolean }
type Session = {
	id: number,
	a: Side,
	b: Side,
	countingDown: boolean,
	finished: boolean,
}

local sessions: { [number]: Session } = {} -- userId -> session
local sessionCounter = 0

TradeService._pushHud = function(_player: Player) end

local function sideFor(session: Session, player: Player): (Side?, Side?)
	if session.a.player == player then
		return session.a, session.b
	elseif session.b.player == player then
		return session.b, session.a
	end
	return nil, nil
end

local function buildView(session: Session, forPlayer: Player)
	local mine, theirs = sideFor(session, forPlayer)
	if not mine or not theirs then
		return nil
	end
	local function infos(ids: { number })
		local out = {}
		for _, id in ids do
			table.insert(out, WeaponConfig.getInfo(id))
		end
		return out
	end
	return {
		active = not session.finished,
		sessionId = session.id,
		you = { offer = infos(mine.offer), ready = mine.ready },
		them = {
			name = theirs.player.DisplayName,
			offer = infos(theirs.offer),
			ready = theirs.ready,
			accepted = theirs.accepted,
		},
		countingDown = session.countingDown,
	}
end

local function sync(session: Session)
	Net.event("TradeAction"):FireClient(session.a.player, { kind = "update", view = buildView(session, session.a.player) })
	Net.event("TradeAction"):FireClient(session.b.player, { kind = "update", view = buildView(session, session.b.player) })
end

local function closeSession(session: Session, reason: string?)
	session.finished = true
	for _, side in { session.a, session.b } do
		if sessions[side.player.UserId] == session then
			sessions[side.player.UserId] = nil
		end
		Net.event("TradeAction"):FireClient(side.player, { kind = "closed", reason = reason })
	end
end

-- count how many copies of `id` a player owns
local function ownedCount(player: Player, id: number): number
	local prof = DataService.get(player)
	if not prof then
		return 0
	end
	local n = 0
	for _, wid in prof.weapons do
		if wid == id then
			n += 1
		end
	end
	return n
end

-- validate a side's offer is fully owned (accounting for duplicates)
local function offerIsValid(side: Side): boolean
	local needed: { [number]: number } = {}
	for _, id in side.offer do
		needed[id] = (needed[id] or 0) + 1
	end
	for id, count in needed do
		if ownedCount(side.player, id) < count then
			return false
		end
	end
	return true
end

local function executeTrade(session: Session)
	local a, b = session.a, session.b
	-- final validation
	if not offerIsValid(a) or not offerIsValid(b) then
		closeSession(session, "Trade failed: a weapon was no longer owned.")
		return
	end
	-- remove from givers
	for _, id in a.offer do
		DataService.removeWeapon(a.player, id)
	end
	for _, id in b.offer do
		DataService.removeWeapon(b.player, id)
	end
	-- grant to receivers
	for _, id in a.offer do
		DataService.addWeapon(b.player, id)
	end
	for _, id in b.offer do
		DataService.addWeapon(a.player, id)
	end

	-- log
	print(("[Trade] %s <-> %s | %s gave [%s], %s gave [%s]"):format(
		a.player.Name, b.player.Name,
		a.player.Name, table.concat(a.offer, ","),
		b.player.Name, table.concat(b.offer, ",")
	))

	Net.event("Notification"):FireClient(a.player, { text = "Trade complete!", color = Color3.fromRGB(90, 220, 120) })
	Net.event("Notification"):FireClient(b.player, { text = "Trade complete!", color = Color3.fromRGB(90, 220, 120) })
	TradeService._pushHud(a.player)
	TradeService._pushHud(b.player)
	closeSession(session, "complete")
end

local function tryStartCountdown(session: Session)
	if session.a.ready and session.b.ready and not session.countingDown then
		session.countingDown = true
		sync(session)
		task.spawn(function()
			for i = COUNTDOWN, 1, -1 do
				if session.finished or not (session.a.ready and session.b.ready) then
					session.countingDown = false
					if not session.finished then
						sync(session)
					end
					return
				end
				Net.event("TradeAction"):FireClient(session.a.player, { kind = "countdown", n = i })
				Net.event("TradeAction"):FireClient(session.b.player, { kind = "countdown", n = i })
				task.wait(1)
			end
			if not session.finished and session.a.ready and session.b.ready then
				executeTrade(session)
			else
				session.countingDown = false
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
local function distanceBetween(a: Player, b: Player): number
	local ca = a.Character and a.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local cb = b.Character and b.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if ca and cb then
		return (ca.Position - cb.Position).Magnitude
	end
	return math.huge
end

local function initiate(player: Player, targetUserId: number)
	if sessions[player.UserId] then
		return -- already trading
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == player or sessions[target.UserId] then
		return
	end
	if distanceBetween(player, target) > MAX_DISTANCE then
		Net.event("Notification"):FireClient(player, { text = "Get closer to trade.", color = Color3.fromRGB(230, 180, 60) })
		return
	end
	sessionCounter += 1
	local session: Session = {
		id = sessionCounter,
		a = { player = player, offer = {}, ready = false, accepted = true },
		b = { player = target, offer = {}, ready = false, accepted = false },
		countingDown = false,
		finished = false,
	}
	sessions[player.UserId] = session
	sessions[target.UserId] = session
	Net.event("TradeAction"):FireClient(target, { kind = "invite", from = player.DisplayName, fromUserId = player.UserId })
	Net.event("TradeAction"):FireClient(player, { kind = "waiting", target = target.DisplayName })
end

local function handleAction(player: Player, payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local session = sessions[player.UserId]
	local action = payload.action
	if typeof(action) ~= "string" then
		return
	end

	if action == "cancel" or action == "decline" then
		if session then
			closeSession(session, "Trade cancelled.")
		end
		return
	end

	if not session or session.finished then
		return
	end
	local mine, theirs = sideFor(session, player)
	if not mine or not theirs then
		return
	end

	if action == "accept" then
		mine.accepted = true
		sync(session)
	elseif action == "addOffer" then
		local id = payload.weaponId
		if WeaponConfig.isValidId(id) and #mine.offer < MAX_OFFER then
			-- ensure they own enough copies for the new total
			local prospective = (function()
				local c = 0
				for _, wid in mine.offer do
					if wid == id then c += 1 end
				end
				return c + 1
			end)()
			if ownedCount(player, id) >= prospective then
				table.insert(mine.offer, math.floor(id))
				mine.ready = false
				theirs.ready = false
				session.countingDown = false
				sync(session)
			end
		end
	elseif action == "removeOffer" then
		local index = payload.index
		if typeof(index) == "number" and mine.offer[index] then
			table.remove(mine.offer, index)
			mine.ready = false
			theirs.ready = false
			session.countingDown = false
			sync(session)
		end
	elseif action == "ready" then
		if mine.accepted and theirs.accepted then
			mine.ready = payload.value == true
			sync(session)
			tryStartCountdown(session)
		end
	end
end

function TradeService.init()
	Net.event("InitiateTrade").OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then
			return
		end
		local targetUserId = payload.targetUserId
		if typeof(targetUserId) ~= "number" then
			return
		end
		initiate(player, math.floor(targetUserId))
	end)

	Net.event("TradeAction").OnServerEvent:Connect(handleAction)

	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player.UserId]
		if session then
			closeSession(session, "Other player left.")
		end
	end)
end

return TradeService
