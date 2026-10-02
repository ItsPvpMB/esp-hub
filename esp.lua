--[[
    ESP Hub — Universal player/NPC ESP for Roblox
    - กล่อง + พื้นหลัง / ชื่อ / ระยะทาง / หลอดเลือด / เส้น Tracer
    - จางเมื่อโดนกำแพงบัง (visibility check), เช็คทีม, ระยะสูงสุด
    - สแกน NPC/บอทที่ไม่ใช่ player อัตโนมัติ
    - เปลี่ยนเซิร์ฟเวอร์/เทเลพอร์ตแล้วกลับมาเอง (auto requeue)
    ปุ่มลัด: RCtrl = เปิด/ปิด ESP, End = ปิดสคริปต์ทั้งหมด
    เมนู: Rayfield Gen2
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local FONT = (Drawing and Drawing.Fonts and (Drawing.Fonts.Plex or Drawing.Fonts.UI)) or 0

-- ====== ตั้งค่า ======
-- URL ของสคริปต์นี้บน GitHub: ใช้สำหรับรันซ้ำอัตโนมัติหลังเทเลพอร์ต/เปลี่ยนเซิร์ฟเวอร์
local REQUEUE_URL = "https://raw.githubusercontent.com/ItsPvpMB/esp-hub/main/esp.lua"

-- STATE มาจาก live-reload ของ Real; ถ้ารันที่อื่นให้ใช้ shim ฉุกเฉิน
local STATE = STATE or {
    connect = function(_, signal, fn) return signal:Connect(fn) end,
    onCleanup = function() end,
    alive = function() return true end,
}

-- เปลี่ยนเซิร์ฟเวอร์/เทเลพอร์ตแล้วรันซ้ำอัตโนมัติ
pcall(function()
    if REQUEUE_URL ~= "" then
        queue_on_teleport('loadstring(game:HttpGet("' .. REQUEUE_URL .. '"))()')
    elseif readfile then
        queue_on_teleport(readfile("esp-rayfield.luau"))
    end
end)

local Settings = {
    Enabled = true,
    Boxes = true,
    BoxFill = true,
    Names = true,
    Distance = true,
    HealthBar = true,
    Tracers = false,
    NPCs = true,
    TeamCheck = false,
    TeamColors = false,
    VisibilityCheck = true,
    MaxDistance = 5000,
    AllyColor = Color3.fromRGB(85, 255, 130),
    EnemyColor = Color3.fromRGB(255, 80, 80),
    TextColor = Color3.fromRGB(255, 255, 255),
}
getgenv().ESPSettings = Settings -- ให้เรียกดู/แก้ค่าจากภายนอกได้
local Running = true -- false เมื่อปิดสคริปต์ด้วยปุ่ม End / Unload

--------------------------------------------------------------------
-- Drawing objects (ต่อเป้าหมาย 1 ชุด)
--------------------------------------------------------------------
local Drawings = {}

local function newObj(class, props)
    local d = Drawing.new(class)
    for k, v in pairs(props) do
        d[k] = v
    end
    return d
end

local function createSet(target)
    if Drawings[target] then return end
    Drawings[target] = {
        fill   = newObj("Square", { Filled = true, Transparency = 0.25, Visible = false }),
        box    = newObj("Square", { Thickness = 1.5, Filled = false, Transparency = 1, Visible = false }),
        hpBg   = newObj("Square", { Filled = true, Color = Color3.fromRGB(15, 15, 15), Transparency = 0.55, Visible = false }),
        hpFill = newObj("Square", { Filled = true, Transparency = 1, Visible = false }),
        name   = newObj("Text",   { Size = 13, Center = true, Outline = true, Font = FONT, Transparency = 1, Visible = false }),
        dist   = newObj("Text",   { Size = 12, Center = true, Outline = true, Font = FONT, Transparency = 1, Visible = false }),
        tracer = newObj("Line",   { Thickness = 1, Transparency = 1, Visible = false }),
    }
end

local function removeSet(target)
    local set = Drawings[target]
    if not set then return end
    for _, d in pairs(set) do
        pcall(function() d:Remove() end)
    end
    Drawings[target] = nil
end

local function hideSet(set)
    for _, d in pairs(set) do
        d.Visible = false
    end
end

for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then createSet(player) end
end
STATE.connect(Players.PlayerAdded, function(player)
    if player ~= LocalPlayer then createSet(player) end
end)
STATE.connect(Players.PlayerRemoving, removeSet)

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

--------------------------------------------------------------------
-- ลูปวาด ESP ต่อเฟรม
--------------------------------------------------------------------
local function update()
    if not Running then return end
    local camera = workspace.CurrentCamera
    if not camera or not Settings.Enabled then
        for _, set in pairs(Drawings) do hideSet(set) end
        return
    end

    local camPos = camera.CFrame.Position
    local vp = camera.ViewportSize
    local tracerOrigin = Vector2.new(vp.X / 2, vp.Y)

    for obj, set in pairs(Drawings) do
        local isPlayer = obj:IsA("Player")
        local character, humanoid, root
        if isPlayer then
            character = obj.Character
            humanoid = character and character:FindFirstChildOfClass("Humanoid")
            root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
        else
            character = obj -- โมเดล NPC/บอท
            if not character.Parent then removeSet(obj) continue end
            humanoid = character:FindFirstChildOfClass("Humanoid")
            root = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart
        end

        if not root or not root:IsA("BasePart") then hideSet(set) continue end
        -- ไม่ซ่อนกรอบตอนตาย: บางเกมค้าง Health = 0 หลังเกิดใหม่ ทำให้กรอบหายถาวร
        if isPlayer and Settings.TeamCheck and obj.Team ~= nil and obj.Team == LocalPlayer.Team then hideSet(set) continue end

        local distance = (root.Position - camPos).Magnitude
        if distance > Settings.MaxDistance then hideSet(set) continue end

        local rootPt = camera:WorldToViewportPoint(root.Position)
        if rootPt.Z <= 0 then hideSet(set) continue end

        local color = Settings.EnemyColor
        if isPlayer and Settings.TeamColors and obj.Team ~= nil then
            color = (obj.Team == LocalPlayer.Team) and Settings.AllyColor or obj.TeamColor.Color
        end

        -- เช็คว่ากำแพงบังหรือเปล่า (raycast จากกล้องหาตัวละคร)
        local visible = true
        if Settings.VisibilityCheck then
            rayParams.FilterDescendantsInstances = { character, camera }
            local hit = workspace:Raycast(camPos, root.Position - camPos, rayParams)
            visible = (hit == nil)
        end
        local drawColor = visible and color or Color3.fromRGB(165, 165, 165)

        -- โปรเจกต์มุมทั้ง 8 ของ bounding box ลงจอ
        local ok, boxCf, boxSize = pcall(character.GetBoundingBox, character)
        if not ok then hideSet(set) continue end

        local half = boxSize * 0.5
        local minX, minY = math.huge, math.huge
        local maxX, maxY = -math.huge, -math.huge
        for sx = -1, 1, 2 do
            for sy = -1, 1, 2 do
                for sz = -1, 1, 2 do
                    local corner = (boxCf * CFrame.new(half.X * sx, half.Y * sy, half.Z * sz)).Position
                    local p = camera:WorldToViewportPoint(corner)
                    if p.X < minX then minX = p.X end
                    if p.X > maxX then maxX = p.X end
                    if p.Y < minY then minY = p.Y end
                    if p.Y > maxY then maxY = p.Y end
                end
            end
        end
        minX -= 2; minY -= 2; maxX += 2; maxY += 2

        local w, h = maxX - minX, maxY - minY
        local cx = (minX + maxX) / 2

        set.fill.Size = Vector2.new(w, h)
        set.fill.Position = Vector2.new(minX, minY)
        set.fill.Color = drawColor
        set.fill.Transparency = visible and 0.25 or 0.5
        set.fill.Visible = Settings.BoxFill

        set.box.Size = Vector2.new(w, h)
        set.box.Position = Vector2.new(minX, minY)
        set.box.Color = drawColor
        set.box.Visible = Settings.Boxes

        if Settings.HealthBar and humanoid and humanoid.MaxHealth > 0 then
            local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
            local barW = 4
            set.hpBg.Size = Vector2.new(barW, h)
            set.hpBg.Position = Vector2.new(minX - barW - 3, minY)
            set.hpBg.Visible = true
            local hh = h * ratio
            set.hpFill.Size = Vector2.new(barW, hh)
            set.hpFill.Position = Vector2.new(minX - barW - 3, maxY - hh)
            set.hpFill.Color = Color3.fromHSV(0.33 * ratio, 1, 1)
            set.hpFill.Transparency = 1
            set.hpFill.Visible = true
        else
            set.hpBg.Visible = false
            set.hpFill.Visible = false
        end

        set.name.Text = isPlayer and obj.DisplayName or character.Name
        set.name.Position = Vector2.new(cx, minY - 16)
        set.name.Color = Settings.TextColor
        set.name.Visible = Settings.Names

        set.dist.Text = math.floor(distance + 0.5) .. "m"
        set.dist.Position = Vector2.new(cx, maxY + 2)
        set.dist.Color = Settings.TextColor
        set.dist.Visible = Settings.Distance

        set.tracer.From = tracerOrigin
        set.tracer.To = Vector2.new(cx, maxY)
        set.tracer.Color = drawColor
        set.tracer.Visible = Settings.Tracers
    end
end

STATE.connect(RunService.RenderStepped, update)

--------------------------------------------------------------------
-- NPC/บอท: ตัวละครที่ไม่ใช่ player ของ Roblox
-- เดินหาโมเดลที่มี Humanoid ทั่ว Workspace (ลึกไม่เกิน 5 ชั้น)
--------------------------------------------------------------------
local MAX_SCAN = 30000

local function scanNpcs()
    if not Running then return end
    if not Settings.NPCs then
        for obj in pairs(Drawings) do
            if not obj:IsA("Player") then removeSet(obj) end
        end
        return
    end

    local playerNames = {}
    for _, p in ipairs(Players:GetPlayers()) do
        playerNames[p.Name] = true
    end
    playerNames[LocalPlayer.Name] = true

    local found, seenNames = {}, {}
    local visited = 0
    local camera = workspace.CurrentCamera

    local function walk(container, depth)
        if depth > 5 or visited >= MAX_SCAN then return end
        for _, obj in ipairs(container:GetChildren()) do
            visited += 1
            if visited >= MAX_SCAN then return end
            if obj ~= camera then
                if obj:IsA("Model") then
                    if obj:FindFirstChildOfClass("Humanoid") then
                        -- โมเดลแบบตัวละคร: พิจารณาเป็น NPC แล้วไม่ต้องลงลึกต่อ
                        if obj.Parent and not playerNames[obj.Name] and not seenNames[obj.Name] then
                            local root = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
                            if root and root:IsA("BasePart") then
                                seenNames[obj.Name] = true
                                found[obj] = true
                            end
                        end
                    else
                        walk(obj, depth + 1)
                    end
                elseif obj:IsA("Folder") or obj:IsA("WorldModel") then
                    walk(obj, depth + 1)
                end
            end
        end
    end

    walk(workspace, 1)

    for model in pairs(found) do
        if not Drawings[model] then createSet(model) end
    end
    for obj in pairs(Drawings) do
        if not obj:IsA("Player") and not found[obj] then
            removeSet(obj)
        end
    end
end

pcall(scanNpcs)
task.spawn(function()
    while STATE.alive() and Running do
        task.wait(1)
        pcall(scanNpcs)
    end
end)

--------------------------------------------------------------------
-- ปุ่มลัด + ข้อความแจ้งบนจอ
--------------------------------------------------------------------
local toast = Drawing.new("Text")
toast.Size = 18
toast.Center = true
toast.Outline = true
toast.Font = FONT
toast.Transparency = 1
toast.Visible = false

local toastShowing = false
local function showToast(text, color)
    local camera = workspace.CurrentCamera
    if camera then
        toast.Position = Vector2.new(camera.ViewportSize.X / 2, 70)
    end
    toast.Text = text
    toast.Color = color
    toast.Visible = true
    toastShowing = true
    task.delay(1.5, function()
        if toastShowing then
            toastShowing = false
            pcall(function() toast.Visible = false end)
        end
    end)
end

local function toggleEsp()
    Settings.Enabled = not Settings.Enabled
    local on = Settings.Enabled
    print("[ESP] " .. (on and "เปิด" or "ปิด"))
    showToast(on and "ESP: เปิด" or "ESP: ปิด", on and Color3.fromRGB(120, 255, 140) or Color3.fromRGB(255, 110, 110))
end

--------------------------------------------------------------------
-- ถอนสคริปต์
--------------------------------------------------------------------
local Rayfield, Window, EspTab

local function unload()
    Running = false
    getgenv().ESPSettings = nil
    for _, set in pairs(Drawings) do
        for _, d in pairs(set) do
            pcall(function() d:Remove() end)
        end
    end
    table.clear(Drawings)
    pcall(function() toast:Remove() end)
    -- Rayfield Gen2 แปะ ScreenGui ชื่อ UUID ไว้ใน gethui() และ :Destroy ของมันลบไม่หายจริง
    -- จึงต้องกวาดลบด้วยรูปแบบชื่อ ไม่งั้นหน้าต่างเก่าจะซ้อนทับทุกครั้งที่รันซ้ำ
    pcall(function()
        local containers = {}
        local ok, hui = pcall(function() return gethui and gethui() end)
        if ok and hui then table.insert(containers, hui) end
        table.insert(containers, game:GetService("CoreGui"))
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then table.insert(containers, pg) end
        local uuidPattern = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"
        for _, container in ipairs(containers) do
            for _, g in ipairs(container:GetChildren()) do
                if g:IsA("ScreenGui") then
                    local n = g.Name:lower()
                    if g.Name:match(uuidPattern) or n:find("rayfield", 1, true) or n:find("sirius", 1, true) then
                        g:Destroy()
                    end
                end
            end
        end
    end)
    if Window then pcall(function() Window:Destroy() end) end
    if Rayfield then pcall(function() Rayfield:Destroy() end) end
end

STATE.onCleanup(unload)

-- ปุ่มลัด: RCtrl = สลับเปิด/ปิด ESP, End = ปิดสคริปต์ทั้งหมด (ทำงานแม้เมนูถูกย่อ)
STATE.connect(UserInputService.InputBegan, function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        toggleEsp()
    elseif input.KeyCode == Enum.KeyCode.End then
        print("[ESP] ปิดสคริปต์ทั้งหมดแล้ว (End)")
        unload()
    end
end)

--------------------------------------------------------------------
-- เมนู Rayfield Gen2
--------------------------------------------------------------------
local menuOk, menuErr = pcall(function()
    Rayfield = loadstring(game:HttpGet("https://sirius.menu/gen2"))()
    Window = Rayfield:CreateWindow({
        name = "ESP Hub",
        subtitle = "Universal ESP",
    })
    EspTab = Window:CreateTab({ name = "ESP" })

    -- forgetState ทุกชิ้น: เริ่มค่าเริ่มต้นใหม่ทุกครั้งที่รัน (กันสถานะค้างจากไฟล์เซฟ)
    EspTab:CreateToggle({ name = "เปิดใช้งาน ESP", flag = "EspEnabled", forgetState = true, value = Settings.Enabled, callback = function(v) Settings.Enabled = v end })
    EspTab:CreateDivider()
    EspTab:CreateToggle({ name = "กล่อง (Box)", flag = "EspBoxes", forgetState = true, value = Settings.Boxes, callback = function(v) Settings.Boxes = v end })
    EspTab:CreateToggle({ name = "พื้นหลังกล่อง (Fill)", flag = "EspBoxFill", forgetState = true, value = Settings.BoxFill, callback = function(v) Settings.BoxFill = v end })
    EspTab:CreateToggle({ name = "ชื่อผู้เล่น", flag = "EspNames", forgetState = true, value = Settings.Names, callback = function(v) Settings.Names = v end })
    EspTab:CreateToggle({ name = "ระยะทาง", flag = "EspDistance", forgetState = true, value = Settings.Distance, callback = function(v) Settings.Distance = v end })
    EspTab:CreateToggle({ name = "หลอดเลือด", flag = "EspHealth", forgetState = true, value = Settings.HealthBar, callback = function(v) Settings.HealthBar = v end })
    EspTab:CreateToggle({ name = "เส้น Tracer", flag = "EspTracers", forgetState = true, value = Settings.Tracers, callback = function(v) Settings.Tracers = v end })
    EspTab:CreateToggle({ name = "รวมบอท/NPC (คนที่ไม่ใช่ player)", flag = "EspNPCs", forgetState = true, value = Settings.NPCs, callback = function(v) Settings.NPCs = v end })
    EspTab:CreateDivider()
    EspTab:CreateToggle({ name = "ซ่อนเพื่อนทีมเดียวกัน (Team Check)", flag = "EspTeamCheck", forgetState = true, value = Settings.TeamCheck, callback = function(v) Settings.TeamCheck = v end })
    EspTab:CreateToggle({ name = "ใช้สีตามทีม", flag = "EspTeamColors", forgetState = true, value = Settings.TeamColors, callback = function(v) Settings.TeamColors = v end })
    EspTab:CreateToggle({ name = "จางเมื่อโดนกำแพงบัง", flag = "EspVisibility", forgetState = true, value = Settings.VisibilityCheck, callback = function(v) Settings.VisibilityCheck = v end })
    EspTab:CreateSlider({ name = "ระยะสูงสุด", flag = "EspMaxRange", forgetState = true, range = { 100, 5000 }, increment = 50, value = Settings.MaxDistance, suffix = " studs", callback = function(v) Settings.MaxDistance = v end })
    EspTab:CreateColorPicker({ name = "สีศัตรู", flag = "EspEnemyColor", forgetState = true, color = Settings.EnemyColor, callback = function(c) Settings.EnemyColor = c end })
    EspTab:CreateColorPicker({ name = "สีเพื่อน (ทีมเดียวกัน)", flag = "EspAllyColor", forgetState = true, color = Settings.AllyColor, callback = function(c) Settings.AllyColor = c end })
    EspTab:CreateButton({ name = "ถอนสคริปต์ (Unload)", callback = unload })
end)

if not menuOk then
    warn("[ESP] โหลดเมนู Rayfield ไม่สำเร็จ: " .. tostring(menuErr) .. " — ESP ยังทำงานด้วยค่าเริ่มต้น")
else
    print("[ESP] พร้อมใช้งาน — RCtrl = เปิด/ปิด ESP, End = ปิดสคริปต์ทั้งหมด")
end