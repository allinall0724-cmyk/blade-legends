--!strict
-- Inventory (press I): scrollable weapon grid on the left, a details/stats panel
-- on the right. Filter buttons + sort dropdown up top. Click a slot to select,
-- then Equip. Equipped slot shows a ✓ badge. Cannot open during combat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(script.Parent.UIKit)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local RarityConfig = require(ReplicatedStorage.Shared.RarityConfig)
local AbilityConfig = require(ReplicatedStorage.Shared.AbilityConfig)

local Inventory = {}

local RARITY_FILTERS = { "All", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
local SORT_MODES = { "Rarity", "Damage", "Newest" }

function Inventory.build(ctx: any)
	local panel, body = UIKit.panel("⚔ Inventory  [I]", UDim2.fromOffset(820, 560))
	panel.Parent = ctx.root
	local self = { panel = panel }

	local cachedIds: { number } = {}
	local rarityFilter = "All"
	local sortMode = "Rarity"
	local selectedId: number? = nil
	local cellsById: { [number]: { frame: Frame, badge: TextLabel, stroke: UIStroke } } = {}

	-- ===== filter buttons row =====
	local filterRow = UIKit.create("Frame", {
		Size = UDim2.new(1, -20, 0, 34),
		Position = UDim2.fromOffset(10, 8),
		BackgroundTransparency = 1,
		Parent = body,
	})
	UIKit.create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 4),
		Parent = filterRow,
	})
	local filterButtons: { [string]: TextButton } = {}
	local function refreshFilterStyles()
		for name, btn in filterButtons do
			local active = name == rarityFilter
			btn.BackgroundColor3 = active and UIKit.Colors.accent or UIKit.Colors.panelLight
			btn.TextColor3 = active and Color3.fromRGB(20, 20, 20) or UIKit.Colors.text
		end
	end

	-- ===== sort dropdown =====
	local sortBtn = UIKit.button("Sort: Rarity ▾", UDim2.fromOffset(150, 30), UDim2.new(1, -160, 0, 46), UIKit.Colors.panelLight)
	sortBtn.Parent = body
	local sortMenu = UIKit.create("Frame", {
		Size = UDim2.fromOffset(150, #SORT_MODES * 30),
		Position = UDim2.new(1, -160, 0, 78),
		BackgroundColor3 = UIKit.Colors.bg,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
		Parent = body,
	}, { UIKit.corner(6), UIKit.create("UIStroke", { Color = UIKit.Colors.accent, Thickness = 1 }), UIKit.create("UIListLayout", {}) })

	-- ===== grid (left) =====
	local scroll = UIKit.create("ScrollingFrame", {
		Size = UDim2.new(0.62, -14, 1, -88),
		Position = UDim2.fromOffset(10, 82),
		BackgroundColor3 = UIKit.Colors.bg,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = body,
	}, { UIKit.corner(8) }) :: ScrollingFrame
	UIKit.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(120, 96),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})
	UIKit.create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), Parent = scroll })

	-- ===== details panel (right) =====
	local details = UIKit.create("Frame", {
		Size = UDim2.new(0.38, -14, 1, -88),
		Position = UDim2.new(0.62, 6, 0, 82),
		BackgroundColor3 = UIKit.Colors.panel,
		BorderSizePixel = 0,
		Parent = body,
	}, { UIKit.corner(8), UIKit.pad(10) })
	local dName = UIKit.create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextWrapped = true,
		TextColor3 = UIKit.Colors.text,
		Text = "Select a weapon",
		Parent = details,
	})
	local dStats = UIKit.create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 120),
		Position = UDim2.fromOffset(0, 48),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = UIKit.Colors.subtext,
		Text = "",
		Parent = details,
	})
	local dAbilTitle = UIKit.create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 172),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UIKit.Colors.accent,
		Text = "",
		Parent = details,
	})
	local dAbilities = UIKit.create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 120),
		Position = UDim2.fromOffset(0, 196),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextColor3 = UIKit.Colors.subtext,
		Text = "",
		Parent = details,
	})
	local equipBtn = UIKit.button("Equip", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 1, -44), UIKit.Colors.good, function()
		if selectedId then
			ctx.event("EquipWeapon"):FireServer({ weaponId = selectedId })
		end
	end)
	equipBtn.Visible = false
	equipBtn.Parent = details
	local offerBtn = UIKit.button("Offer to Trade", UDim2.new(0.6, -4, 0, 32), UDim2.new(0, 0, 1, -84), UIKit.Colors.panelLight, function()
		if selectedId and ctx.offerToTrade then
			ctx.offerToTrade(selectedId)
		end
	end)
	offerBtn.Visible = false
	offerBtn.Parent = details
	local discardBtn = UIKit.button("Discard", UDim2.new(0.4, -4, 0, 32), UDim2.new(0.6, 4, 1, -84), UIKit.Colors.bad, function()
		if selectedId then
			ctx.event("DiscardWeapon"):FireServer({ weaponId = selectedId })
			selectedId = nil
			task.delay(0.2, function()
				if self.refresh then
					self.refresh()
				end
			end)
		end
	end)
	discardBtn.Visible = false
	discardBtn.Parent = details

	local function showDetails(info: any)
		dName.Text = info.name
		dName.TextColor3 = info.rarityColor
		dStats.Text = ("Rarity: %s\nMaterial: %s\nSize: %s\nDamage: %d\nSpeed: %.2f /s")
			:format(info.rarity, info.material, info.size, math.floor(info.damage), info.speed)
		dAbilTitle.Text = "Abilities"
		local lines = {}
		for _, a in AbilityConfig.listFor(info.baseType, info.rarity) do
			local tick = a.unlocked and "●" or "🔒"
			table.insert(lines, ("%s [%s] %s"):format(tick, a.key, a.name))
		end
		dAbilities.Text = table.concat(lines, "\n")
		equipBtn.Visible = true
		offerBtn.Visible = true
		discardBtn.Visible = true
		equipBtn.Text = (ctx.state.equippedId == info.id) and "Equipped ✓" or "Equip"
	end

	local function applySelectionStyles()
		for id, cell in cellsById do
			local isSel = id == selectedId
			cell.stroke.Thickness = isSel and 4 or 2
			cell.stroke.Transparency = isSel and 0 or 0.2
			cell.badge.Visible = id == ctx.state.equippedId
		end
	end

	local function render()
		for _, c in scroll:GetChildren() do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		cellsById = {}

		local items = {}
		for order, id in cachedIds do
			local info = WeaponConfig.getInfo(id)
			if info and (rarityFilter == "All" or info.rarity == rarityFilter) then
				table.insert(items, { info = info, order = order })
			end
		end
		table.sort(items, function(a, b)
			if sortMode == "Damage" then
				return a.info.damage > b.info.damage
			elseif sortMode == "Newest" then
				return a.order > b.order
			else
				if RarityConfig.indexOf(a.info.rarity) ~= RarityConfig.indexOf(b.info.rarity) then
					return RarityConfig.indexOf(a.info.rarity) > RarityConfig.indexOf(b.info.rarity)
				end
				return a.info.damage > b.info.damage
			end
		end)

		if #items == 0 then
			UIKit.create("TextButton", {
				Size = UDim2.fromOffset(360, 40),
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				TextColor3 = UIKit.Colors.subtext,
				TextSize = 16,
				Text = "No weapons — open a case to collect some!",
				Parent = scroll,
			})
			return
		end

		for layoutOrder, item in items do
			local info = item.info
			local cell = UIKit.create("TextButton", {
				BackgroundColor3 = UIKit.Colors.panel,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = true,
				LayoutOrder = layoutOrder,
				Parent = scroll,
			}, { UIKit.corner(8) }) :: TextButton
			local stroke = UIKit.create("UIStroke", { Color = info.rarityColor, Thickness = 2, Transparency = 0.2, Parent = cell }) :: UIStroke
			-- material icon (colored chip)
			UIKit.create("Frame", {
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.fromOffset(6, 6),
				BackgroundColor3 = info.materialColor,
				BorderSizePixel = 0,
				Parent = cell,
			}, { UIKit.corner(4), UIKit.create("UIStroke", { Color = Color3.fromRGB(0, 0, 0), Transparency = 0.5 }) })
			-- equipped badge
			local badge = UIKit.create("TextLabel", {
				Size = UDim2.fromOffset(20, 20),
				Position = UDim2.new(1, -22, 0, 4),
				BackgroundColor3 = UIKit.Colors.good,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextColor3 = Color3.fromRGB(20, 20, 20),
				Text = "✓",
				Visible = info.id == ctx.state.equippedId,
				Parent = cell,
			}, { UIKit.corner(10) }) :: TextLabel
			-- name
			UIKit.create("TextLabel", {
				Size = UDim2.new(1, -10, 0, 34),
				Position = UDim2.fromOffset(5, 26),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextWrapped = true,
				TextColor3 = info.rarityColor,
				Text = info.name,
				Parent = cell,
			})
			-- damage stat
			UIKit.create("TextLabel", {
				Size = UDim2.new(1, -10, 0, 24),
				Position = UDim2.fromOffset(5, 66),
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				TextScaled = true,
				TextColor3 = UIKit.Colors.subtext,
				Text = ("⚔ %d"):format(math.floor(info.damage)),
				Parent = cell,
			})

			cellsById[info.id] = { frame = cell, badge = badge, stroke = stroke }
			cell.Activated:Connect(function()
				selectedId = info.id
				showDetails(info)
				applySelectionStyles()
			end)
		end

		applySelectionStyles()
		-- keep a previously-selected weapon shown
		if selectedId then
			local info = WeaponConfig.getInfo(selectedId)
			if info then
				showDetails(info)
			end
		end
	end

	-- build filter buttons
	for _, name in RARITY_FILTERS do
		local btn = UIKit.button(name, UDim2.fromOffset(name == "All" and 50 or 92, 30), UDim2.new(), UIKit.Colors.panelLight, function()
			rarityFilter = name
			refreshFilterStyles()
			render()
		end)
		btn.Parent = filterRow
		filterButtons[name] = btn
	end
	refreshFilterStyles()

	-- sort dropdown behaviour
	for _, mode in SORT_MODES do
		local opt = UIKit.button(mode, UDim2.new(1, 0, 0, 30), UDim2.new(), UIKit.Colors.bg, function()
			sortMode = mode
			sortBtn.Text = "Sort: " .. mode .. " ▾"
			sortMenu.Visible = false
			render()
		end)
		opt.ZIndex = 21
		opt.Parent = sortMenu
	end
	sortBtn.Activated:Connect(function()
		sortMenu.Visible = not sortMenu.Visible
	end)

	-- ===== public =====
	function self.refresh()
		local ok, ids = pcall(function()
			return ctx.func("GetInventory"):InvokeServer()
		end)
		if ok and typeof(ids) == "table" then
			cachedIds = ids
		end
		render()
	end

	-- called on every HUD push: keep equipped badge + equip button label current
	function self.onHud(_data: any)
		applySelectionStyles()
		if selectedId and panel.Visible then
			local info = WeaponConfig.getInfo(selectedId)
			if info then
				equipBtn.Text = (ctx.state.equippedId == info.id) and "Equipped ✓" or "Equip"
			end
		end
	end

	function self.open()
		if ctx.state.inCombat then
			ctx.event("RequestData"):FireServer()
			if ctx.notify then
				ctx.notify("You can't open the inventory during combat!")
			end
			return
		end
		panel.Visible = true
		self.refresh()
	end
	function self.toggle()
		if panel.Visible then
			panel.Visible = false
			sortMenu.Visible = false
		else
			self.open()
		end
	end

	return self
end

return Inventory
