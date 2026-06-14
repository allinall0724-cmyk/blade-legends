--!nonstrict
-- InventoryClient: standalone, self-contained inventory. Lives in StarterGui so
-- it never depends on the controller chain. Press I to toggle. Builds its own
-- InventoryGui, lists owned Blades from GetInventory, adds new ones live via
-- NewWeaponReceived, and equips / sells the selected Blade.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- avoid duplicating on respawn
if playerGui:FindFirstChild("InventoryGui") then
	return
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared:WaitForChild("WeaponConfig"))
local RarityConfig = require(Shared:WaitForChild("RarityConfig"))

local Remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 30)
local function ev(name)
	return Remotes:WaitForChild(name, 30)
end
local GetInventory = ev("GetInventory")
local EquipWeapon = ev("EquipWeapon")
local SellWeapon = ev("SellWeapon")
local NewWeaponReceived = ev("NewWeaponReceived")
local TradeAction = ev("TradeAction")

local RARITY_FILTERS = { "ALL", "COMMON", "UNCOMMON", "RARE", "EPIC", "LEGENDARY", "MYTHIC" }

-- ===== build GUI =====
local gui = Instance.new("ScreenGui")
gui.Name = "InventoryGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 5
gui.Enabled = false
gui.Parent = playerGui

local dim = Instance.new("Frame")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
dim.BackgroundTransparency = 0.3
dim.BorderSizePixel = 0
dim.Parent = gui

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(700, 500)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = Color3.fromRGB(245, 245, 250)
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -60, 0, 40)
title.Position = UDim2.fromOffset(20, 10)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.TextScaled = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(35, 35, 45)
title.Text = "MY COLLECTION"
title.Parent = panel

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(36, 36)
closeBtn.Position = UDim2.new(1, -44, 0, 12)
closeBtn.BackgroundColor3 = Color3.fromRGB(220, 70, 70)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextScaled = true
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Text = "X"
closeBtn.Parent = panel
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

-- filter row
local filterRow = Instance.new("Frame")
filterRow.Size = UDim2.new(1, -40, 0, 28)
filterRow.Position = UDim2.fromOffset(20, 54)
filterRow.BackgroundTransparency = 1
filterRow.Parent = panel
local fl = Instance.new("UIListLayout", filterRow)
fl.FillDirection = Enum.FillDirection.Horizontal
fl.Padding = UDim.new(0, 4)

-- grid (left)
local grid = Instance.new("ScrollingFrame")
grid.Size = UDim2.fromOffset(400, 400)
grid.Position = UDim2.fromOffset(20, 88)
grid.BackgroundColor3 = Color3.fromRGB(225, 225, 232)
grid.BorderSizePixel = 0
grid.ScrollBarThickness = 6
grid.CanvasSize = UDim2.new()
grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
grid.Parent = panel
Instance.new("UICorner", grid).CornerRadius = UDim.new(0, 8)
local gl = Instance.new("UIGridLayout", grid)
gl.CellSize = UDim2.fromOffset(80, 80)
gl.CellPadding = UDim2.fromOffset(6, 6)
local gp = Instance.new("UIPadding", grid)
gp.PaddingLeft = UDim.new(0, 6)
gp.PaddingTop = UDim.new(0, 6)

-- detail panel (right)
local detail = Instance.new("Frame")
detail.Size = UDim2.fromOffset(250, 400)
detail.Position = UDim2.fromOffset(430, 88)
detail.BackgroundColor3 = Color3.fromRGB(225, 225, 232)
detail.BorderSizePixel = 0
detail.Parent = panel
Instance.new("UICorner", detail).CornerRadius = UDim.new(0, 8)

local dName = Instance.new("TextLabel")
dName.Size = UDim2.new(1, -16, 0, 50)
dName.Position = UDim2.fromOffset(8, 8)
dName.BackgroundTransparency = 1
dName.Font = Enum.Font.GothamBold
dName.TextScaled = true
dName.TextWrapped = true
dName.TextColor3 = Color3.fromRGB(35, 35, 45)
dName.Text = "Select a Blade"
dName.Parent = detail

local dStats = Instance.new("TextLabel")
dStats.Size = UDim2.new(1, -16, 0, 180)
dStats.Position = UDim2.fromOffset(8, 62)
dStats.BackgroundTransparency = 1
dStats.Font = Enum.Font.Gotham
dStats.TextSize = 16
dStats.TextXAlignment = Enum.TextXAlignment.Left
dStats.TextYAlignment = Enum.TextYAlignment.Top
dStats.TextColor3 = Color3.fromRGB(60, 60, 70)
dStats.Text = ""
dStats.Parent = detail

local function makeBtn(text, y, color)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -16, 0, 36)
	b.Position = UDim2.new(0, 8, 1, y)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Text = text
	b.Visible = false
	b.Parent = detail
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	return b
end
local equipBtn = makeBtn("EQUIP", -128, Color3.fromRGB(70, 180, 90))
local sellBtn = makeBtn("SELL", -86, Color3.fromRGB(210, 100, 70))
local offerBtn = makeBtn("OFFER IN TRADE", -44, Color3.fromRGB(90, 130, 210))

-- ===== state =====
local ids = {}
local selected = nil
local filter = "ALL"
local slotFrames = {}

local function showDetail(info)
	dName.Text = info.name
	dName.TextColor3 = info.rarityColor
	dStats.Text = ("Value: %d\nRarity: %s\nMaterial: %s\nSize: %s\nDamage: %d"):format(
		math.floor(info.value or 0), info.rarity, info.material, info.size, math.floor(info.damage))
	equipBtn.Visible = true
	sellBtn.Visible = true
	offerBtn.Visible = true
end

local function highlight()
	for id, frame in slotFrames do
		local st = frame:FindFirstChildOfClass("UIStroke")
		if st then
			st.Enabled = (id == selected)
		end
	end
end

local function render()
	for _, c in grid:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	slotFrames = {}
	-- newest first
	for i = #ids, 1, -1 do
		local id = ids[i]
		local info = WeaponConfig.getInfo(id)
		if info and (filter == "ALL" or string.upper(info.rarity) == filter) then
			local slot = Instance.new("TextButton")
			slot.BackgroundColor3 = info.rarityColor
			slot.BorderSizePixel = 0
			slot.AutoButtonColor = true
			slot.Text = ""
			slot.LayoutOrder = #ids - i
			slot.Parent = grid
			Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 6)
			local st = Instance.new("UIStroke", slot)
			st.Color = Color3.fromRGB(255, 255, 255)
			st.Thickness = 3
			st.Enabled = false
			local nm = Instance.new("TextLabel")
			nm.Size = UDim2.new(1, -6, 0, 44)
			nm.Position = UDim2.fromOffset(3, 4)
			nm.BackgroundTransparency = 1
			nm.Font = Enum.Font.GothamBold
			nm.TextScaled = true
			nm.TextWrapped = true
			nm.TextColor3 = Color3.fromRGB(255, 255, 255)
			nm.TextStrokeTransparency = 0.4
			nm.Text = info.name
			nm.Parent = slot
			local val = Instance.new("TextLabel")
			val.Size = UDim2.new(1, -4, 0, 16)
			val.Position = UDim2.new(0, 0, 1, -18)
			val.BackgroundTransparency = 1
			val.Font = Enum.Font.GothamBold
			val.TextScaled = true
			val.TextXAlignment = Enum.TextXAlignment.Right
			val.TextColor3 = Color3.fromRGB(255, 255, 230)
			val.Text = "⬩" .. math.floor(info.value or 0)
			val.Parent = slot
			slotFrames[id] = slot
			slot.Activated:Connect(function()
				selected = id
				showDetail(info)
				highlight()
			end)
		end
	end
	highlight()
end

local function refresh()
	local ok, list = pcall(function()
		return GetInventory:InvokeServer()
	end)
	if ok and typeof(list) == "table" then
		ids = list
	end
	render()
end

-- filter buttons
for _, name in RARITY_FILTERS do
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(name == "ALL" and 44 or 86, 26)
	b.BackgroundColor3 = (name == "ALL") and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(210, 210, 218)
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.fromRGB(35, 35, 45)
	b.Text = name
	b.Parent = filterRow
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	b.Activated:Connect(function()
		filter = name
		for _, other in filterRow:GetChildren() do
			if other:IsA("TextButton") then
				other.BackgroundColor3 = (other.Text == name) and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(210, 210, 218)
			end
		end
		render()
	end)
end

-- buttons
equipBtn.Activated:Connect(function()
	if selected then
		EquipWeapon:FireServer({ weaponId = selected })
	end
end)
offerBtn.Activated:Connect(function()
	if selected then
		TradeAction:FireServer({ action = "addOffer", weaponId = selected })
	end
end)
sellBtn.Activated:Connect(function()
	if not selected then
		return
	end
	local info = WeaponConfig.getInfo(selected)
	if not info then
		return
	end
	local coins = math.max(1, math.floor((info.value or 0) * 0.2))
	-- confirmation
	local confirm = Instance.new("Frame")
	confirm.Size = UDim2.fromOffset(320, 150)
	confirm.Position = UDim2.fromScale(0.5, 0.5)
	confirm.AnchorPoint = Vector2.new(0.5, 0.5)
	confirm.BackgroundColor3 = Color3.fromRGB(250, 250, 252)
	confirm.BorderSizePixel = 0
	confirm.ZIndex = 10
	confirm.Parent = gui
	Instance.new("UICorner", confirm).CornerRadius = UDim.new(0, 10)
	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.new(1, -20, 0, 90)
	txt.Position = UDim2.fromOffset(10, 8)
	txt.BackgroundTransparency = 1
	txt.Font = Enum.Font.Gotham
	txt.TextSize = 15
	txt.TextWrapped = true
	txt.ZIndex = 11
	txt.TextColor3 = Color3.fromRGB(40, 40, 50)
	txt.Text = ("Are you sure? This Blade is worth %d. You will receive %d coins."):format(math.floor(info.value or 0), coins)
	txt.Parent = confirm
	local yes = Instance.new("TextButton")
	yes.Size = UDim2.new(0.5, -14, 0, 38)
	yes.Position = UDim2.new(0, 10, 1, -46)
	yes.BackgroundColor3 = Color3.fromRGB(210, 100, 70)
	yes.Font = Enum.Font.GothamBold
	yes.TextScaled = true
	yes.ZIndex = 11
	yes.TextColor3 = Color3.fromRGB(255, 255, 255)
	yes.Text = "Sell"
	yes.Parent = confirm
	Instance.new("UICorner", yes).CornerRadius = UDim.new(0, 8)
	yes.Activated:Connect(function()
		SellWeapon:FireServer({ weaponId = selected })
		-- remove locally
		for i, id in ids do
			if id == selected then
				table.remove(ids, i)
				break
			end
		end
		selected = nil
		equipBtn.Visible = false
		sellBtn.Visible = false
		offerBtn.Visible = false
		dName.Text = "Select a Blade"
		dStats.Text = ""
		confirm:Destroy()
		render()
	end)
	local no = Instance.new("TextButton")
	no.Size = UDim2.new(0.5, -14, 0, 38)
	no.Position = UDim2.new(0.5, 4, 1, -46)
	no.BackgroundColor3 = Color3.fromRGB(180, 180, 190)
	no.Font = Enum.Font.GothamBold
	no.TextScaled = true
	no.ZIndex = 11
	no.TextColor3 = Color3.fromRGB(40, 40, 50)
	no.Text = "Cancel"
	no.Parent = confirm
	Instance.new("UICorner", no).CornerRadius = UDim.new(0, 8)
	no.Activated:Connect(function()
		confirm:Destroy()
	end)
end)

closeBtn.Activated:Connect(function()
	gui.Enabled = false
end)

-- toggle with I
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.I then
		gui.Enabled = not gui.Enabled
		if gui.Enabled then
			refresh()
		end
	end
end)

-- live add of new Blades
NewWeaponReceived.OnClientEvent:Connect(function(data)
	if data and data.weaponId then
		table.insert(ids, data.weaponId)
		if gui.Enabled then
			render()
		end
	end
end)

-- initial load
task.spawn(refresh)

print("[Blade Legends] InventoryClient ready (press I)")
