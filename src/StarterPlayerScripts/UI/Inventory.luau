--!strict
-- Inventory (press I): grid of owned weapons with filter + sort, click to equip,
-- right-click for discard / offer-into-trade.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local UIKit = require(script.Parent.UIKit)
local WeaponConfig = require(ReplicatedStorage.Shared.WeaponConfig)
local RarityConfig = require(ReplicatedStorage.Shared.RarityConfig)

local Inventory = {}

local RARITY_FILTERS = { "All", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
local SORT_MODES = { "Newest", "Damage", "Rarity" }

function Inventory.build(ctx: any)
	local panel, body = UIKit.panel("⚔ Inventory  [I]", UDim2.fromOffset(720, 520))
	panel.Parent = ctx.root
	local self = { panel = panel }

	local rarityIdx = 1
	local sortIdx = 1
	local typeIdx = 0 -- 0 = All, else BaseTypes index

	-- controls row
	local controls = UIKit.create("Frame", {
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 8),
		BackgroundTransparency = 1,
		Parent = body,
	})
	local rarityBtn = UIKit.button("Rarity: All", UDim2.fromOffset(180, 36), UDim2.fromOffset(0, 0))
	rarityBtn.Parent = controls
	local typeBtn = UIKit.button("Type: All", UDim2.fromOffset(180, 36), UDim2.fromOffset(188, 0))
	typeBtn.Parent = controls
	local sortBtn = UIKit.button("Sort: Newest", UDim2.fromOffset(180, 36), UDim2.fromOffset(376, 0))
	sortBtn.Parent = controls

	-- scrolling grid
	local scroll = UIKit.create("ScrollingFrame", {
		Size = UDim2.new(1, -20, 1, -58),
		Position = UDim2.fromOffset(10, 52),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = body,
	}) :: ScrollingFrame
	local grid = UIKit.create("UIGridLayout", {
		CellSize = UDim2.fromOffset(160, 92),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scroll,
	})

	local cachedIds: { number } = {}

	local function passesFilter(info: any): boolean
		if rarityIdx > 1 and info.rarity ~= RARITY_FILTERS[rarityIdx] then
			return false
		end
		if typeIdx > 0 and info.baseType ~= WeaponConfig.BaseTypes[typeIdx].name then
			return false
		end
		return true
	end

	local function render()
		for _, c in scroll:GetChildren() do
			if c:IsA("TextButton") then
				c:Destroy()
			end
		end
		-- build info list with original order index for "Newest"
		local items = {}
		for order, id in cachedIds do
			local info = WeaponConfig.getInfo(id)
			if info and passesFilter(info) then
				table.insert(items, { info = info, order = order })
			end
		end
		-- sort
		local mode = SORT_MODES[sortIdx]
		table.sort(items, function(a, b)
			if mode == "Damage" then
				return a.info.damage > b.info.damage
			elseif mode == "Rarity" then
				return RarityConfig.indexOf(a.info.rarity) > RarityConfig.indexOf(b.info.rarity)
			else -- Newest
				return a.order > b.order
			end
		end)

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
			UIKit.create("UIStroke", { Color = info.rarityColor, Thickness = 2, Parent = cell })
			UIKit.create("TextLabel", {
				Size = UDim2.new(1, -10, 0, 38),
				Position = UDim2.fromOffset(5, 4),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextColor3 = info.rarityColor,
				Text = info.name,
				TextWrapped = true,
				Parent = cell,
			})
			UIKit.create("TextLabel", {
				Size = UDim2.new(1, -10, 0, 36),
				Position = UDim2.fromOffset(5, 46),
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				TextScaled = true,
				TextColor3 = UIKit.Colors.subtext,
				Text = ("DMG %d • %s"):format(math.floor(info.damage), info.rarity),
				Parent = cell,
			})

			cell.Activated:Connect(function()
				ctx.event("EquipWeapon"):FireServer({ weaponId = info.id })
			end)
			cell.MouseButton2Click:Connect(function()
				Inventory._contextMenu(ctx, self, info)
			end)
		end
	end

	-- simple right-click context menu
	function Inventory._contextMenu(c: any, slf: any, info: any)
		if slf._menu then
			slf._menu:Destroy()
		end
		local mouse = UserInputService:GetMouseLocation()
		local menu = UIKit.create("Frame", {
			Size = UDim2.fromOffset(160, 96),
			Position = UDim2.fromOffset(mouse.X, mouse.Y - 60),
			BackgroundColor3 = UIKit.Colors.bg,
			BorderSizePixel = 0,
			ZIndex = 50,
			Parent = c.root,
		}, { UIKit.corner(8), UIKit.create("UIStroke", { Color = UIKit.Colors.accent, Thickness = 1 }) })
		local equip = UIKit.button("Equip", UDim2.new(1, -8, 0, 28), UDim2.fromOffset(4, 4), nil, function()
			c.event("EquipWeapon"):FireServer({ weaponId = info.id })
			menu:Destroy()
		end)
		equip.ZIndex = 51
		equip.Parent = menu
		local offer = UIKit.button("Offer in Trade", UDim2.new(1, -8, 0, 28), UDim2.fromOffset(4, 34), UIKit.Colors.panelLight, function()
			if c.offerToTrade then
				c.offerToTrade(info.id)
			end
			menu:Destroy()
		end)
		offer.ZIndex = 51
		offer.Parent = menu
		local discard = UIKit.button("Discard", UDim2.new(1, -8, 0, 28), UDim2.fromOffset(4, 64), UIKit.Colors.bad, function()
			c.event("DiscardWeapon"):FireServer({ weaponId = info.id })
			menu:Destroy()
			task.wait(0.2)
			slf.refresh()
		end)
		discard.ZIndex = 51
		discard.Parent = menu
		slf._menu = menu
		task.delay(4, function()
			if menu and menu.Parent then
				menu:Destroy()
			end
		end)
	end

	rarityBtn.Activated:Connect(function()
		rarityIdx = (rarityIdx % #RARITY_FILTERS) + 1
		rarityBtn.Text = "Rarity: " .. RARITY_FILTERS[rarityIdx]
		render()
	end)
	typeBtn.Activated:Connect(function()
		typeIdx = (typeIdx + 1) % (#WeaponConfig.BaseTypes + 1)
		typeBtn.Text = "Type: " .. (typeIdx == 0 and "All" or WeaponConfig.BaseTypes[typeIdx].name)
		render()
	end)
	sortBtn.Activated:Connect(function()
		sortIdx = (sortIdx % #SORT_MODES) + 1
		sortBtn.Text = "Sort: " .. SORT_MODES[sortIdx]
		render()
	end)

	function self.refresh()
		local ok, ids = pcall(function()
			return ctx.func("GetInventory"):InvokeServer()
		end)
		if ok and typeof(ids) == "table" then
			cachedIds = ids
		end
		render()
	end

	function self.open()
		panel.Visible = true
		self.refresh()
	end
	function self.toggle()
		if panel.Visible then
			panel.Visible = false
		else
			self.open()
		end
	end

	return self
end

return Inventory
