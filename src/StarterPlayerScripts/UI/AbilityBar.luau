--!strict
-- AbilityBar: the bottom-center ability slots (LMB, Q, E, R, F, G). Slots locked
-- for the equipped weapon's rarity are dimmed; active cooldowns show a sweep +
-- countdown; using an ability flashes its name on screen.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(script.Parent.UIKit)
local AbilityConfig = require(ReplicatedStorage.Shared.AbilityConfig)

local AbilityBar = {}

local SLOTS = {
	{ slot = "Basic", key = "LMB" },
	{ slot = "PowerStrike", key = "Q" },
	{ slot = "DashStrike", key = "E" },
	{ slot = "AreaSlam", key = "R" },
	{ slot = "Special", key = "F" },
	{ slot = "Ultimate", key = "G" },
}

function AbilityBar.build(ctx: any)
	local root = ctx.root
	local self = {}

	local SLOT = 62
	local PAD = 6
	local total = #SLOTS * SLOT + (#SLOTS - 1) * PAD

	local holder = UIKit.create("Frame", {
		Name = "AbilityBar",
		Size = UDim2.fromOffset(total, SLOT + 16),
		Position = UDim2.new(0.5, -total / 2, 1, -SLOT - 78),
		BackgroundTransparency = 1,
		Parent = root,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, PAD),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = holder,
	})

	local slotRefs: { [string]: any } = {}

	for _, def in SLOTS do
		local frame = UIKit.create("Frame", {
			Size = UDim2.fromOffset(SLOT, SLOT),
			BackgroundColor3 = UIKit.Colors.panel,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Parent = holder,
		}, { UIKit.corner(8), UIKit.create("UIStroke", { Color = UIKit.Colors.accent, Thickness = 1.5, Transparency = 0.3 }) })

		local keyLabel = UIKit.create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextColor3 = UIKit.Colors.accent,
			Text = def.key,
			Parent = frame,
		})
		local nameLabel = UIKit.create("TextLabel", {
			Size = UDim2.new(1, -4, 0, 28),
			Position = UDim2.fromOffset(2, 24),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			TextSize = 10,
			TextWrapped = true,
			TextColor3 = UIKit.Colors.subtext,
			Text = "",
			Parent = frame,
		})
		-- cooldown sweep (fills from bottom, shrinks as it cools)
		local cdOverlay = UIKit.create("Frame", {
			Name = "CD",
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.fromRGB(10, 10, 14),
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Parent = frame,
		})
		local cdText = UIKit.create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Text = "",
			Visible = false,
			Parent = frame,
		})
		-- lock overlay
		local lockOverlay = UIKit.create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.5,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextColor3 = Color3.fromRGB(200, 200, 200),
			Text = "🔒",
			Visible = false,
			Parent = frame,
		})

		slotRefs[def.slot] = {
			frame = frame,
			keyLabel = keyLabel,
			nameLabel = nameLabel,
			cdOverlay = cdOverlay,
			cdText = cdText,
			lockOverlay = lockOverlay,
			cooling = false,
		}
	end

	-- ability-name flash above the bar
	local flash = UIKit.create("TextLabel", {
		Size = UDim2.fromOffset(420, 50),
		Position = UDim2.new(0.5, -210, 1, -SLOT - 138),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = UIKit.Colors.accent,
		TextStrokeTransparency = 0.3,
		TextTransparency = 1,
		Text = "",
		Parent = root,
	})

	local function setLocked(ref: any, locked: boolean)
		ref.lockOverlay.Visible = locked
		ref.nameLabel.TextColor3 = locked and Color3.fromRGB(110, 110, 120) or UIKit.Colors.subtext
		ref.keyLabel.TextColor3 = locked and Color3.fromRGB(110, 110, 120) or UIKit.Colors.accent
	end

	function self.onHud(data: any)
		local equipped = data.equipped
		for _, def in SLOTS do
			local ref = slotRefs[def.slot]
			if equipped then
				local unlocked = AbilityConfig.isUnlocked(def.slot, equipped.rarity)
				local info = AbilityConfig.info(def.slot, AbilityConfig.categoryOf(equipped.baseType))
				ref.nameLabel.Text = info.name
				setLocked(ref, not unlocked)
			else
				ref.nameLabel.Text = ""
				setLocked(ref, def.slot ~= "Basic")
			end
		end
	end

	function self.onAbilityState(payload: any)
		local ref = slotRefs[payload.slot]
		if not ref or typeof(payload.remaining) ~= "number" then
			return
		end
		local duration = payload.duration or payload.remaining
		ref.cooling = true
		ref.cdText.Visible = true
		ref.cdOverlay.Size = UDim2.fromScale(1, 1)
		TweenService:Create(ref.cdOverlay, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 0) }):Play()
		task.spawn(function()
			local remaining = payload.remaining
			while remaining > 0 and ref.cooling do
				ref.cdText.Text = tostring(math.ceil(remaining))
				task.wait(0.1)
				remaining -= 0.1
			end
			ref.cdText.Visible = false
			ref.cooling = false
		end)
	end

	function self.onFlash(payload: any)
		flash.Text = tostring(payload.name or "")
		flash.TextColor3 = payload.color or UIKit.Colors.accent
		flash.TextTransparency = 0
		flash.TextStrokeTransparency = 0.3
		TweenService:Create(flash, TweenInfo.new(1.1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end

	return self
end

return AbilityBar
