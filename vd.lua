--[[
    JAPvd - Violence District (script baru, terinspirasi vd.lua)
    =====================================================================
    Kode ini ditulis ulang dari nol. Referensi hanya dipakai untuk memilih
    fitur yang cocok dengan gameplay Violence District:
      * 5 Survivor vs 1 Killer, repair 5 generator, skill check melingkar
        (jarum merah -> zona putih, tekan E), pallet, vault/window,
        hook/spike, heal teman, exit gate, item parry/flashlight.

    Fitur:
      - ESP/Aura: Killer, Survivor, Zombie/SCP-049-2 (patch CURE), Generator
        (+progress), Exit Gate, Pallet, Hook/Spike, Window/Vault

    PENTING: setelah script diexecute, yang otomatis aktif HANYA ESP.
    Semua fitur bantuan lain (auto skill check/repair/heal/unhook/pallet/
    vault/parry, aim assist, speed, teleport, dsb.) berstatus MATI dan baru
    bekerja jika kamu menyalakannya sendiri dari menu.
      - Auto Skill Check (beta): membaca UI gauge melingkar lalu menekan E
        saat jarum masuk zona sukses
      - Auto Repair/Heal/Unhook: menahan tombol interaksi di dekat target
      - Auto Pallet & Auto Vault lewat ProximityPrompt saat dikejar
      - Auto Parry: mengaktifkan tool saat Killer sangat dekat
      - Aim Assist untuk Killer, Teleport, WalkSpeed/Jump/FOV, Fullbright,
        No Clip, Infinite Jump, Anti-AFK

    Tombol UI : RightShift (tampil/sembunyi)
    Jalankan script ini di dalam game. Jangan jalankan dua kali.

    CATATAN JUJUR: deteksi objek/role memakai nama & atribut yang umum
    (Generator, Pallet, Hook, dst.). Kalau game update dan nama objeknya
    berubah, ubah kata kunci di bagian CONFIG.KEYWORDS di bawah.
]]

-- ============================================================================
-- CONFIG
-- ============================================================================
local CONFIG = {
    ToggleKey = Enum.KeyCode.RightShift,

    InteractKey = Enum.KeyCode.E,      -- tombol repair/heal/unhook di VD
    ParryKey = Enum.KeyCode.R,         -- cadangan bila tool parry tidak aktif
    SkillCheckTolerance = 11,          -- derajat toleransi auto skill check

    MaxESPDistance = 1200,
    DangerDistance = 40, -- jarak peringatan Killer/Zombie terdekat
    AutoRepairRange = 12,
    AutoHealRange = 10,
    AutoUnhookRange = 13,
    ParryDistance = 13,

    WalkSpeed = 20,
    JumpPower = 50,
    FieldOfView = 80,

    -- Patch CURE: survivor bisa berubah menjadi zombie/minion SCP-049-2.
    -- Nama bisa berbeda antar map/update, jadi deteksinya memakai beberapa
    -- kata kunci + atribut/status pada model NPC.
    ZOMBIE_KEYWORDS = {
        -- Sengaja TIDAK memakai "scp-049" polos: itu nama Killer The Cure.
        -- Minionnya adalah SCP-049-2, jadi yang dicari akhiran "-2"/"0492".
        "zombie", "049-2", "049_2", "0492", "plague zombie",
        "infected minion", "cure minion",
    },

    KEYWORDS = {
        Generator = { "generator", "engine", "genset" },
        ExitGate  = { "exitgate", "exit gate", "exit_gate", "escapegate", "exit" },
        Pallet    = { "pallet" },
        Hook      = { "hook", "spike" },
        Window    = { "window", "vault" },
        Locker    = { "locker" },
    },
}

local State = {
    -- Visual: satu-satunya kelompok fitur yang aktif otomatis saat execute.
    KillerESP = true,
    SurvivorESP = true,
    InfectedESP = true,
    ZombieESP = true,
    DangerIndicator = true,
    GeneratorESP = true,
    ExitGateESP = true,
    PalletESP = true,
    HookESP = true,
    WindowESP = true,

    -- Survivor help
    AutoSkillCheck = false,
    AutoRepair = false,
    AutoHeal = false,
    AutoUnhook = false,
    AutoPallet = false,
    AutoVault = false,
    AutoParry = false,

    -- Killer help
    AimAssist = false,

    -- Player / world
    PlayerMods = false,
    NoClip = false,
    InfiniteJump = false,
    Fullbright = false,
    CustomFOV = false,
    AntiAFK = false, -- tidak otomatis; nyalakan manual bila perlu
}

local ESP_STYLE = {
    Killer    = { color = Color3.fromRGB(255, 55, 70),  toggle = "KillerESP" },
    Survivor  = { color = Color3.fromRGB(65, 170, 255), toggle = "SurvivorESP" },
    Infected  = { color = Color3.fromRGB(255, 155, 40), toggle = "InfectedESP" },
    Zombie    = { color = Color3.fromRGB(178, 255, 45), toggle = "ZombieESP" },
    Unknown   = { color = Color3.fromRGB(150, 200, 255), toggle = "SurvivorESP" },
    Generator = { color = Color3.fromRGB(255, 205, 60), toggle = "GeneratorESP" },
    ExitGate  = { color = Color3.fromRGB(70, 230, 255), toggle = "ExitGateESP" },
    Pallet    = { color = Color3.fromRGB(255, 150, 60), toggle = "PalletESP" },
    Hook      = { color = Color3.fromRGB(255, 90, 210), toggle = "HookESP" },
    Window    = { color = Color3.fromRGB(150, 140, 255), toggle = "WindowESP" },
    Locker    = { color = Color3.fromRGB(190, 190, 190), toggle = "WindowESP" },
}

-- ============================================================================
-- SERVICES & PLAYER
-- ============================================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = nil
pcall(function() VirtualInputManager = game:GetService("VirtualInputManager") end)

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Alive = true
local Connections = {}
local function connect(signal, fn)
    local c = signal:Connect(fn)
    table.insert(Connections, c)
    return c
end

local function getCharacter(player)
    player = player or LocalPlayer
    local char = player and player.Character
    if char and char:FindFirstChildOfClass("Humanoid") then
        return char
    end
    return nil
end

local function getRoot(player)
    local char = getCharacter(player)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChildWhichIsA("BasePart")
end

local function getHumanoid(player)
    local char = getCharacter(player)
    return char and char:FindFirstChildOfClass("Humanoid") or nil
end

local function objectPosition(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then
        local ok, pivot = pcall(function() return obj:GetPivot() end)
        if ok and pivot then return pivot.Position end
        local part = obj:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end
    if obj:IsA("Attachment") then return obj.WorldPosition end
    return nil
end

local function distanceFromMe(pos)
    local root = getRoot()
    if not root or not pos then return math.huge end
    return (root.Position - pos).Magnitude
end

local function lower(text)
    return string.lower(tostring(text or ""))
end

local function containsAny(text, words)
    text = lower(text)
    for _, word in ipairs(words) do
        if string.find(text, word, 1, true) then
            return true
        end
    end
    return false
end

-- ============================================================================
-- VIRTUAL INPUT (untuk menahan / menekan tombol interaksi)
-- ============================================================================
local E_Held = false
local function setInteractHeld(held)
    if held == E_Held then return end
    E_Held = held
    if VirtualInputManager then
        pcall(function()
            VirtualInputManager:SendKeyEvent(held, CONFIG.InteractKey, false, game)
        end)
    end
end

local function tapInteract()
    if VirtualInputManager then
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, CONFIG.InteractKey, false, game)
        end)
        task.wait(0.035)
        pcall(function()
            VirtualInputManager:SendKeyEvent(false, CONFIG.InteractKey, false, game)
        end)
    end
end

local function firePrompt(prompt)
    if not prompt then return false end
    if typeof(fireproximityprompt) == "function" then
        local ok = pcall(fireproximityprompt, prompt)
        if ok then return true end
    end
    -- cadangan: tahan E selama prompt butuh ditahan
    task.spawn(function()
        setInteractHeld(true)
        task.wait(math.max(0.1, (prompt.HoldDuration or 0) + 0.08))
        if not (State.AutoRepair or State.AutoHeal or State.AutoUnhook) then
            setInteractHeld(false)
        end
    end)
    return true
end

-- ============================================================================
-- ROLE & OBJECT DETECTION
-- ============================================================================
local function looksZombie(text)
    return containsAny(text, CONFIG.ZOMBIE_KEYWORDS)
end

-- The Cure (SCP-049 versi killer) SELALU masuk kategori Killer.
-- Zombie-nya (SCP-049-2) sudah disaring lebih dulu oleh looksZombie().
local function looksKillerText(text)
    text = lower(text)
    if looksZombie(text) then return false end
    if string.find(text, "killer", 1, true) then return true end
    if containsAny(text, {
        "the cure", "the_cure", "thecure", "plague doctor", "plaguedoctor",
        "scp-049", "scp049",
    }) then
        return true
    end
    return false
end

local function attributesLookZombie(obj)
    if not obj then return false end
    local ok, attrs = pcall(function() return obj:GetAttributes() end)
    if not ok or type(attrs) ~= "table" then return false end
    for name, value in pairs(attrs) do
        if looksZombie(name) or looksZombie(value) then
            return true
        end
        if string.find(lower(name), "zombie", 1, true) and value == true then
            return true
        end
    end
    return false
end

-- Mendukung zombie pemain maupun NPC SCP-049-2 pada patch CURE.
local function holderLooksZombie(holder)
    if not holder then return false end
    if looksZombie(holder.Name) or attributesLookZombie(holder) then
        return true
    end

    local hum = holder:FindFirstChildWhichIsA("Humanoid", true)
    if hum and (looksZombie(hum.Name) or looksZombie(hum.DisplayName) or attributesLookZombie(hum)) then
        return true
    end

    for _, child in ipairs(holder:GetChildren()) do
        local n = lower(child.Name)
        if child:IsA("StringValue") and (looksZombie(n) or looksZombie(child.Value)) then
            return true
        elseif child:IsA("BoolValue") and string.find(n, "zombie", 1, true) and child.Value then
            return true
        elseif attributesLookZombie(child) then
            return true
        end
    end

    -- NPC sering dikelompokkan dalam folder seperti "Zombies"/"SCP-049-2".
    local ancestor = holder.Parent
    for _ = 1, 3 do
        if not ancestor then break end
        if looksZombie(ancestor.Name) or attributesLookZombie(ancestor) then
            return true
        end
        ancestor = ancestor.Parent
    end
    return false
end

local function roleFromNamedValues(holder)
    if not holder then return nil end
    if holderLooksZombie(holder) then return "Zombie" end
    for _, child in ipairs(holder:GetChildren()) do
        local n = lower(child.Name)
        if string.find(n, "role") or string.find(n, "team") or string.find(n, "class") or child:IsA("StringValue") then
            if child:IsA("StringValue") then
                local v = lower(child.Value)
                if looksZombie(v) then return "Zombie" end
                if looksKillerText(v) then return "Killer" end
                if string.find(v, "survivor") then return "Survivor" end
            elseif child:IsA("BoolValue") and child.Value then
                if string.find(n, "zombie") then return "Zombie" end
                if looksKillerText(n) then return "Killer" end
            end
        end
    end
    return nil
end

local function getRole(player)
    if not player then return "Unknown" end

    local ok, attrs = pcall(function() return player:GetAttributes() end)
    if ok and type(attrs) == "table" then
        for name, value in pairs(attrs) do
            local n, v = lower(name), lower(value)
            if looksZombie(v) or (string.find(n, "zombie", 1, true) and value == true) then return "Zombie" end
            if looksKillerText(v) then return "Killer" end
            if string.find(v, "survivor") then return "Survivor" end
            if looksKillerText(n) and value == true then return "Killer" end
        end
    end

    if holderLooksZombie(player) then return "Zombie" end
    if player.Team and looksZombie(player.Team.Name) then return "Zombie" end
    if player.Team and looksKillerText(player.Team.Name) then return "Killer" end
    if player.Team and containsAny(player.Team.Name, { "survivor" }) then return "Survivor" end

    local fromPlayer = roleFromNamedValues(player)
    if fromPlayer then return fromPlayer end

    local char = getCharacter(player)
    if char then
        if holderLooksZombie(char) then return "Zombie" end
        local ok2, cattrs = pcall(function() return char:GetAttributes() end)
        if ok2 and type(cattrs) == "table" then
            for name, value in pairs(cattrs) do
                local n, v = lower(name), lower(value)
                if looksZombie(v) or (string.find(n, "zombie", 1, true) and value == true) then return "Zombie" end
                if looksKillerText(v) then return "Killer" end
                if looksKillerText(n) and value == true then return "Killer" end
            end
        end
        local fromChar = roleFromNamedValues(char)
        if fromChar then return fromChar end
    end

    return "Unknown"
end

-- Status survivor untuk label ESP: DOWNED / HOOKED / CARRIED / INFECTED /
-- INJURED / DEAD. Dibaca generik dari atribut & ValueObject di Player dan
-- Character, karena nama status persisnya bisa berubah antar patch.
local function getPlayerStatus(player)
    local hum = getHumanoid(player)
    if not hum then return "" end
    if hum.Health <= 0 then return "[DEAD]" end

    local found = {}
    local stage = nil
    local function mark(name) found[name] = true end

    local function inspect(text, numericValue)
        text = lower(text)
        if looksZombie(text) then return end
        if containsAny(text, { "downed", "knockeddown", "knocked down", "incapacitated" }) then mark("DOWNED") end
        if containsAny(text, { "hooked", "spiked", "onhook", "onspike", "on_hook", "on_spike" }) then mark("HOOKED") end
        if containsAny(text, { "carried", "beingcarried", "being carried", "pickedup", "picked up" }) then mark("CARRIED") end
        if containsAny(text, { "infected", "pestilence", "infection", "injected", "injection" }) then mark("INFECTED") end

        local foundStage = string.match(text, "stage[^0-9]*(%d+)") or string.match(text, "spikes?[^0-9]*(%d+)")
        if foundStage then
            stage = tonumber(foundStage)
        elseif numericValue and numericValue > 0 and containsAny(text, { "spike", "infection", "pestilence" }) then
            stage = math.floor(numericValue)
        end
    end

    local function inspectAttributes(obj)
        if not obj then return end
        local ok, attrs = pcall(function() return obj:GetAttributes() end)
        if not ok or type(attrs) ~= "table" then return end
        for name, value in pairs(attrs) do
            inspect(tostring(name) .. " " .. tostring(value), (type(value) == "number") and value or nil)
        end
    end

    local function inspectHolder(holder, deep)
        if not holder then return end
        inspect(holder.Name)
        inspectAttributes(holder)
        local children = deep and holder:GetDescendants() or holder:GetChildren()
        for _, inst in ipairs(children) do
            if inst:IsA("StringValue") then
                inspect(inst.Name .. " " .. inst.Value)
            elseif inst:IsA("BoolValue") then
                if inst.Value then inspect(inst.Name) end
            elseif inst:IsA("NumberValue") or inst:IsA("IntValue") then
                inspect(inst.Name, inst.Value)
            else
                inspect(inst.Name)
                inspectAttributes(inst)
            end
        end
    end

    inspectHolder(player, false)
    inspectHolder(getCharacter(player), true)

    local majorStatus = found.HOOKED or found.DOWNED or found.CARRIED
    local parts = {}
    if found.HOOKED then table.insert(parts, "[HOOKED]") end
    if found.DOWNED then table.insert(parts, "[DOWNED]") end
    if found.CARRIED then table.insert(parts, "[CARRIED]") end
    if found.INFECTED then
        table.insert(parts, stage and string.format("[INFECTED STAGE %d]", stage) or "[INFECTED]")
    elseif not majorStatus and hum.Health < hum.MaxHealth then
        table.insert(parts, "[INJURED]")
    end
    return table.concat(parts, " ")
end

local function nearestPlayer(predicate, maxDistance)
    local best, bestDist = nil, maxDistance or math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local root = getRoot(player)
            local hum = getHumanoid(player)
            if root and hum and hum.Health > 0 and (not predicate or predicate(player, hum, root)) then
                local d = distanceFromMe(root.Position)
                if d < bestDist then
                    best, bestDist = player, d
                end
            end
        end
    end
    return best, bestDist
end

local function getKiller()
    return nearestPlayer(function(player)
        return getRole(player) == "Killer"
    end)
end

-- ============================================================================
-- ESP
-- ============================================================================
local Tracked = {} -- [instance] = entry

local function findDisplayPart(obj)
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        return obj:FindFirstChild("HumanoidRootPart", true)
            or obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function makeESP(obj, category, displayName, getExtraText)
    if Tracked[obj] then return Tracked[obj] end
    local style = ESP_STYLE[category]
    if not style then return nil end
    local part = findDisplayPart(obj)
    if not part then return nil end

    local highlight = Instance.new("Highlight")
    highlight.Name = "__VD_ESP"
    highlight.Adornee = obj
    highlight.FillColor = style.color
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.55
    highlight.OutlineTransparency = 0.25
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = obj

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "__VD_ESP_Text"
    billboard.Adornee = part
    billboard.Size = UDim2.fromOffset(170, 42)
    billboard.StudsOffset = Vector3.new(0, 3.2, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = part

    local label = Instance.new("TextLabel")
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 13
    label.TextColor3 = style.color
    label.TextStrokeTransparency = 0.35
    label.Text = displayName or obj.Name
    label.Parent = billboard

    local entry = {
        Object = obj, Category = category, Part = part,
        Highlight = highlight, Billboard = billboard, Label = label,
        Name = displayName or obj.Name, GetExtraText = getExtraText,
    }
    Tracked[obj] = entry
    return entry
end

local function removeESP(obj)
    local entry = Tracked[obj]
    if not entry then return end
    Tracked[obj] = nil
    pcall(function() entry.Highlight:Destroy() end)
    pcall(function() entry.Billboard:Destroy() end)
end

local function clearESP()
    for obj in pairs(Tracked) do removeESP(obj) end
end

local function generatorProgress(obj)
    if not obj then return nil end
    for _, child in ipairs(obj:GetDescendants()) do
        if (child:IsA("NumberValue") or child:IsA("IntValue")) then
            local n = lower(child.Name)
            if string.find(n, "progress") or string.find(n, "percent") or string.find(n, "repair") or string.find(n, "charge") then
                local v = child.Value
                if v <= 1.01 then v = v * 100 end
                return math.clamp(math.floor(v), 0, 100)
            end
        end
    end
    return nil
end

-- Smart Generator ESP: persen + progress bar teks 10 blok.
local function generatorProgressText(obj)
    local progress = generatorProgress(obj)
    if progress == nil then return "" end
    local filled = math.floor((progress / 100) * 10 + 0.5)
    local bar = string.rep("█", filled) .. string.rep("░", 10 - filled)
    return string.format(" - %d%% [%s]", progress, bar)
end

local function isInsidePlayerCharacter(obj)
    for _, player in ipairs(Players:GetPlayers()) do
        local char = player.Character
        if char and (obj == char or obj:IsDescendantOf(char)) then
            return true
        end
    end
    return false
end

local function refreshObjectESP()
    if not Alive then return end

    -- pemain
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = getCharacter(player)
            local hum = getHumanoid(player)
            if char and hum then
                local role = getRole(player)
                local statusText = (role == "Killer") and "" or getPlayerStatus(player)
                local espCategory = role
                -- Survivor yang terinfeksi CURE tampil oranye, sebelum berubah
                -- penuh menjadi Zombie. Survivor normal tetap biru.
                if role ~= "Zombie" and role ~= "Killer" and string.find(statusText, "INFECTED", 1, true) then
                    espCategory = "Infected"
                end

                local entry
                entry = makeESP(char, espCategory, player.Name, function()
                    local h = getHumanoid(player)
                    if not h then return "" end
                    local hpText = string.format(" [%d HP]", math.max(0, math.floor(h.Health)))
                    local status = (entry and entry.StatusText) or statusText
                    if status and status ~= "" then
                        return " " .. status .. hpText
                    end
                    return hpText
                end)
                if entry then
                    entry.Category = espCategory
                    entry.StatusText = statusText
                    entry.Name = (role == "Zombie") and (player.Name .. " [ZOMBIE]") or player.Name
                end
            end
        end
    end

    -- objek map + NPC zombie SCP-049-2 (patch CURE)
    local seen = {}
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if (inst:IsA("BasePart") or inst:IsA("Model")) and not isInsidePlayerCharacter(inst) then
            -- Zombie adalah NPC Model ber-Humanoid, bukan sekadar part bernama
            -- "zombie". Ini menghindari dekorasi/properti map ikut terdeteksi.
            if inst:IsA("Model") and not seen[inst] then
                local npcHumanoid = inst:FindFirstChildWhichIsA("Humanoid", true)
                if npcHumanoid and holderLooksZombie(inst) then
                    seen[inst] = true
                    local zombieEntry = makeESP(inst, "Zombie", "ZOMBIE - " .. inst.Name, function()
                        local h = inst:FindFirstChildWhichIsA("Humanoid", true)
                        if not h then return "" end
                        return string.format(" [%d HP]", math.max(0, math.floor(h.Health)))
                    end)
                    if zombieEntry then
                        zombieEntry.Category = "Zombie"
                        zombieEntry.Name = "ZOMBIE - " .. inst.Name
                    end
                end
            end

            local category = nil
            for cat, words in pairs(CONFIG.KEYWORDS) do
                if containsAny(inst.Name, words) then category = cat break end
            end
            if category then
                local rootObj = inst
                if inst:IsA("BasePart") and inst.Parent and inst.Parent:IsA("Model") and inst.Parent ~= Workspace then
                    rootObj = inst.Parent
                end
                if not seen[rootObj] then
                    seen[rootObj] = true
                    makeESP(rootObj, category, rootObj.Name, function()
                        if category == "Generator" then return generatorProgressText(rootObj) end
                        return ""
                    end)
                end
            end
        end
    end

    -- buang yang sudah hancur
    for obj, entry in pairs(Tracked) do
        if not obj.Parent and not Players:GetPlayerFromCharacter(obj) then
            removeESP(obj)
        end
    end
end

local function updateESP()
    local myPosRoot = getRoot()
    if not myPosRoot then return end

    -- Smart Generator: tandai generator belum selesai yang paling dekat
    -- sebagai [PRIORITAS]. Sengaja tanpa garis penunjuk & tanpa notifikasi.
    local priorityGenerator, priorityDistance = nil, math.huge
    for _, candidate in pairs(Tracked) do
        if candidate.Category == "Generator" then
            local progress = generatorProgress(candidate.Object)
            if progress == nil or progress < 100 then
                local candidatePos = objectPosition(candidate.Object)
                if candidatePos then
                    local candidateDistance = (myPosRoot.Position - candidatePos).Magnitude
                    if candidateDistance < priorityDistance then
                        priorityGenerator, priorityDistance = candidate, candidateDistance
                    end
                end
            end
        end
    end

    for _, entry in pairs(Tracked) do
        local style = ESP_STYLE[entry.Category]
        local pos = objectPosition(entry.Object)
        if style and pos then
            local dist = (myPosRoot.Position - pos).Magnitude
            local visible = State[style.toggle] and dist <= CONFIG.MaxESPDistance
            entry.Highlight.Enabled = visible
            entry.Billboard.Enabled = visible

            local displayColor = style.color
            local prefix = ""
            if entry.Category == "Generator" then
                local progress = generatorProgress(entry.Object)
                if progress and progress >= 100 then
                    displayColor = Color3.fromRGB(70, 255, 130)
                    prefix = "[SELESAI] "
                elseif progress and progress >= 75 then
                    displayColor = Color3.fromRGB(255, 150, 60)
                end
                if entry == priorityGenerator then
                    prefix = "[PRIORITAS] " .. prefix
                end
            end

            if entry.Highlight.FillColor ~= displayColor then
                entry.Highlight.FillColor = displayColor
                entry.Label.TextColor3 = displayColor
            end
            if visible then
                local extra = ""
                if entry.GetExtraText then
                    local ok, result = pcall(entry.GetExtraText)
                    if ok and result then extra = result end
                end
                entry.Label.Text = string.format("%s%s%s\n%dm", prefix, entry.Name, extra, math.floor(dist))
            end
        else
            entry.Highlight.Enabled = false
            entry.Billboard.Enabled = false
        end
    end
end

local function nearestTracked(category, maxDistance)
    local best, bestDist = nil, maxDistance or math.huge
    for _, entry in pairs(Tracked) do
        if entry.Category == category then
            local pos = objectPosition(entry.Object)
            if pos then
                local d = distanceFromMe(pos)
                if d < bestDist then best, bestDist = entry, d end
            end
        end
    end
    return best, bestDist
end

local function teleportTo(position)
    local root = getRoot()
    if not root or not position then return end
    local rotation = root.CFrame - root.CFrame.Position
    root.CFrame = CFrame.new(position + Vector3.new(0, 3, 0)) * rotation
end

-- ============================================================================
-- PROXIMITY PROMPT HELP
-- ============================================================================
local function nearestPrompt(words, maxDistance)
    local best, bestDist = nil, maxDistance or math.huge
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if inst:IsA("ProximityPrompt") and inst.Enabled then
            local text = lower(inst.Name) .. " " .. lower(inst.ActionText) .. " " .. lower(inst.ObjectText)
            if containsAny(text, words) then
                local holder = inst.Parent
                local pos = holder and objectPosition(holder)
                if pos then
                    local d = distanceFromMe(pos)
                    if d < bestDist then best, bestDist = inst, d end
                end
            end
        end
    end
    return best, bestDist
end

-- ============================================================================
-- AUTO SKILL CHECK (membaca gauge melingkar di PlayerGui)
-- ============================================================================
local SkillCheckArmed = true
local LastSkillCheckTap = 0

local function guiCenter(obj)
    return obj.AbsolutePosition + (obj.AbsoluteSize / 2)
end

local function angularDifference(a, b)
    local diff = math.abs(a - b) % (math.pi * 2)
    if diff > math.pi then diff = (math.pi * 2) - diff end
    return diff
end

local function objectAngle(obj, center)
    -- jarum biasanya frame memanjang yang berputar di tengah gauge
    local size = obj.AbsoluteSize
    if obj:IsA("GuiObject") and math.max(size.X, size.Y) > 40 then
        return math.rad(obj.Rotation or 0)
    end
    local c = guiCenter(obj)
    if (c - center).Magnitude < 6 then
        return math.rad(obj.Rotation or 0)
    end
    return math.atan2(c.Y - center.Y, c.X - center.X)
end

local function tryAutoSkillCheck()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return end

    local container, needle, zone = nil, nil, nil
    for _, inst in ipairs(playerGui:GetDescendants()) do
        if inst:IsA("GuiObject") and inst.Visible and inst.AbsoluteSize.X > 0 then
            local n = lower(inst.Name)
            if string.find(n, "skill") and (string.find(n, "check") or string.find(n, "gauge") or string.find(n, "circle")) then
                if not container or inst.AbsoluteSize.X > container.AbsoluteSize.X then
                    container = inst
                end
            end
            if string.find(n, "needle") or string.find(n, "pointer") or string.find(n, "marker") or string.find(n, "cursor") or n == "red" then
                needle = needle or inst
            end
            if string.find(n, "great") then
                zone = inst -- zona terbaik didahulukan
            elseif not zone and (string.find(n, "success") or string.find(n, "good") or string.find(n, "white") or string.find(n, "zone") or string.find(n, "target")) then
                zone = inst
            end
        end
    end

    if not needle or not zone then return end
    local center
    if container then
        center = guiCenter(container)
    else
        center = guiCenter(zone)
    end

    local diff = angularDifference(objectAngle(needle, center), objectAngle(zone, center))
    local tolerance = math.rad(CONFIG.SkillCheckTolerance)

    if diff > tolerance * 1.8 then
        SkillCheckArmed = true
    end

    if SkillCheckArmed and diff <= tolerance and (os.clock() - LastSkillCheckTap) > 0.35 then
        SkillCheckArmed = false
        LastSkillCheckTap = os.clock()
        task.spawn(tapInteract)
    end
end

-- ============================================================================
-- AUTO PARRY / TOOL
-- ============================================================================
local LastParry = 0
local function tryAutoParry(killer, dist)
    if not killer or dist > CONFIG.ParryDistance then return end
    if (os.clock() - LastParry) < 0.85 then return end
    LastParry = os.clock()

    local char = getCharacter()
    local tool = char and char:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function() tool:Activate() end)
    elseif VirtualInputManager then
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, CONFIG.ParryKey, false, game)
        end)
        task.delay(0.04, function()
            pcall(function()
                VirtualInputManager:SendKeyEvent(false, CONFIG.ParryKey, false, game)
            end)
        end)
    end
end

-- ============================================================================
-- UI
-- ============================================================================
local function getGuiParent()
    if typeof(gethui) == "function" then
        local ok, gui = pcall(gethui)
        if ok and gui then return gui end
    end
    local coreGui = game:FindService("CoreGui")
    if coreGui then return coreGui end
    return LocalPlayer:WaitForChild("PlayerGui")
end

for _, guiName in ipairs({ "VD_Remake_GUI", "JAPvd_GUI" }) do
    local parent = getGuiParent()
    local old = parent and parent:FindFirstChild(guiName)
    if old then old:Destroy() end
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "JAPvd_GUI"
ScreenGui.DisplayOrder = 999
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = getGuiParent()

-- ============================================================================
-- LOGO & LOADING SCREEN - JAPvd
-- ============================================================================
local LoadingGui = Instance.new("CanvasGroup")
LoadingGui.Name = "JAPvd_Loading"
LoadingGui.Size = UDim2.fromScale(1, 1)
LoadingGui.BackgroundColor3 = Color3.fromRGB(7, 7, 11)
LoadingGui.BackgroundTransparency = 0.03
LoadingGui.BorderSizePixel = 0
LoadingGui.GroupTransparency = 0
LoadingGui.ZIndex = 100
LoadingGui.Parent = ScreenGui

local LoadingPanel = Instance.new("Frame")
LoadingPanel.Name = "Panel"
LoadingPanel.Size = UDim2.fromOffset(430, 318)
LoadingPanel.Position = UDim2.new(0.5, -215, 0.5, -159)
LoadingPanel.BackgroundColor3 = Color3.fromRGB(16, 16, 23)
LoadingPanel.BorderSizePixel = 0
LoadingPanel.ZIndex = 101
LoadingPanel.Parent = LoadingGui
Instance.new("UICorner", LoadingPanel).CornerRadius = UDim.new(0, 16)

local LoadingStroke = Instance.new("UIStroke")
LoadingStroke.Color = Color3.fromRGB(225, 45, 65)
LoadingStroke.Transparency = 0.45
LoadingStroke.Thickness = 1
LoadingStroke.Parent = LoadingPanel

-- Logo utama JAPvd: badge merah dengan monogram JAP + aksen vd.
local LoadingLogo = Instance.new("Frame")
LoadingLogo.Name = "Logo"
LoadingLogo.Size = UDim2.fromOffset(92, 92)
LoadingLogo.Position = UDim2.new(0.5, -46, 0, 28)
LoadingLogo.BackgroundColor3 = Color3.fromRGB(190, 28, 45)
LoadingLogo.BorderSizePixel = 0
LoadingLogo.ZIndex = 102
LoadingLogo.Parent = LoadingPanel
Instance.new("UICorner", LoadingLogo).CornerRadius = UDim.new(0, 22)

local LogoGradient = Instance.new("UIGradient")
LogoGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 65, 82)),
    ColorSequenceKeypoint.new(0.55, Color3.fromRGB(174, 24, 43)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(75, 18, 38)),
})
LogoGradient.Rotation = 35
LogoGradient.Parent = LoadingLogo

local LogoMark = Instance.new("TextLabel")
LogoMark.Size = UDim2.new(1, 0, 0, 48)
LogoMark.Position = UDim2.fromOffset(0, 15)
LogoMark.BackgroundTransparency = 1
LogoMark.Font = Enum.Font.GothamBlack
LogoMark.TextSize = 30
LogoMark.TextColor3 = Color3.fromRGB(255, 255, 255)
LogoMark.TextStrokeTransparency = 0.65
LogoMark.Text = "JAP"
LogoMark.ZIndex = 103
LogoMark.Parent = LoadingLogo

local LogoSubMark = Instance.new("TextLabel")
LogoSubMark.Size = UDim2.new(1, 0, 0, 24)
LogoSubMark.Position = UDim2.fromOffset(0, 55)
LogoSubMark.BackgroundTransparency = 1
LogoSubMark.Font = Enum.Font.GothamBold
LogoSubMark.TextSize = 15
LogoSubMark.TextColor3 = Color3.fromRGB(255, 205, 210)
LogoSubMark.Text = "vd"
LogoSubMark.ZIndex = 103
LogoSubMark.Parent = LoadingLogo

local LoadingTitle = Instance.new("TextLabel")
LoadingTitle.Size = UDim2.new(1, -40, 0, 40)
LoadingTitle.Position = UDim2.new(0, 20, 0, 132)
LoadingTitle.BackgroundTransparency = 1
LoadingTitle.Font = Enum.Font.GothamBlack
LoadingTitle.TextSize = 34
LoadingTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
LoadingTitle.Text = "JAPvd"
LoadingTitle.ZIndex = 102
LoadingTitle.Parent = LoadingPanel

local LoadingSubtitle = Instance.new("TextLabel")
LoadingSubtitle.Size = UDim2.new(1, -40, 0, 22)
LoadingSubtitle.Position = UDim2.new(0, 20, 0, 170)
LoadingSubtitle.BackgroundTransparency = 1
LoadingSubtitle.Font = Enum.Font.GothamBold
LoadingSubtitle.TextSize = 12
LoadingSubtitle.TextColor3 = Color3.fromRGB(255, 105, 120)
LoadingSubtitle.Text = "V I O L E N C E   D I S T R I C T"
LoadingSubtitle.ZIndex = 102
LoadingSubtitle.Parent = LoadingPanel

local LoadingBarBack = Instance.new("Frame")
LoadingBarBack.Name = "LoadingBarBack"
LoadingBarBack.Size = UDim2.new(1, -76, 0, 12)
LoadingBarBack.Position = UDim2.new(0, 38, 0, 216)
LoadingBarBack.BackgroundColor3 = Color3.fromRGB(43, 43, 55)
LoadingBarBack.BorderSizePixel = 0
LoadingBarBack.ZIndex = 102
LoadingBarBack.Parent = LoadingPanel
Instance.new("UICorner", LoadingBarBack).CornerRadius = UDim.new(1, 0)

local LoadingBarFill = Instance.new("Frame")
LoadingBarFill.Name = "Fill"
LoadingBarFill.Size = UDim2.new(0, 0, 1, 0)
LoadingBarFill.BackgroundColor3 = Color3.fromRGB(232, 42, 62)
LoadingBarFill.BorderSizePixel = 0
LoadingBarFill.ZIndex = 103
LoadingBarFill.Parent = LoadingBarBack
Instance.new("UICorner", LoadingBarFill).CornerRadius = UDim.new(1, 0)

local LoadingBarGradient = Instance.new("UIGradient")
LoadingBarGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 75, 90)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 30, 80)),
})
LoadingBarGradient.Parent = LoadingBarFill

local LoadingPercent = Instance.new("TextLabel")
LoadingPercent.Size = UDim2.fromOffset(70, 22)
LoadingPercent.Position = UDim2.new(1, -108, 0, 187)
LoadingPercent.BackgroundTransparency = 1
LoadingPercent.Font = Enum.Font.GothamBold
LoadingPercent.TextSize = 13
LoadingPercent.TextXAlignment = Enum.TextXAlignment.Right
LoadingPercent.TextColor3 = Color3.fromRGB(255, 255, 255)
LoadingPercent.Text = "0%"
LoadingPercent.ZIndex = 102
LoadingPercent.Parent = LoadingPanel

local LoadingStatus = Instance.new("TextLabel")
LoadingStatus.Size = UDim2.new(1, -76, 0, 24)
LoadingStatus.Position = UDim2.new(0, 38, 0, 240)
LoadingStatus.BackgroundTransparency = 1
LoadingStatus.Font = Enum.Font.Gotham
LoadingStatus.TextSize = 13
LoadingStatus.TextXAlignment = Enum.TextXAlignment.Left
LoadingStatus.TextColor3 = Color3.fromRGB(205, 205, 215)
LoadingStatus.Text = "Menyiapkan JAPvd..."
LoadingStatus.ZIndex = 102
LoadingStatus.Parent = LoadingPanel

local LoadingFooter = Instance.new("TextLabel")
LoadingFooter.Size = UDim2.new(1, -40, 0, 20)
LoadingFooter.Position = UDim2.new(0, 20, 1, -34)
LoadingFooter.BackgroundTransparency = 1
LoadingFooter.Font = Enum.Font.Gotham
LoadingFooter.TextSize = 11
LoadingFooter.TextColor3 = Color3.fromRGB(130, 130, 145)
LoadingFooter.Text = "JAPvd  •  tekan RightShift untuk membuka menu"
LoadingFooter.ZIndex = 102
LoadingFooter.Parent = LoadingPanel

local function setLoading(progress, statusText)
    progress = math.clamp(progress, 0, 1)
    TweenService:Create(
        LoadingBarFill,
        TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = UDim2.new(progress, 0, 1, 0) }
    ):Play()
    LoadingPercent.Text = string.format("%d%%", math.floor(progress * 100))
    if statusText then
        LoadingStatus.Text = statusText
    end
end

local function finishLoading()
    setLoading(1, "Selesai. Selamat bermain!")
    task.wait(0.55)
    local fade = TweenService:Create(
        LoadingGui,
        TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { GroupTransparency = 1 }
    )
    fade:Play()
    fade.Completed:Wait()
    LoadingGui:Destroy()
end

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(580, 380)
Main.Position = UDim2.new(0.5, -290, 0.5, -190)
Main.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
Main.BorderSizePixel = 0
Main.Active = true
Main.Visible = false -- ditampilkan setelah loading JAPvd selesai
Main.Parent = ScreenGui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 42)
TopBar.BackgroundColor3 = Color3.fromRGB(112, 22, 32)
TopBar.BorderSizePixel = 0
TopBar.Parent = Main
Instance.new("UICorner", TopBar).CornerRadius = UDim.new(0, 10)

-- Logo kecil JAPvd di top bar menu utama.
local TopLogo = Instance.new("Frame")
TopLogo.Name = "JAPvdLogo"
TopLogo.Size = UDim2.fromOffset(46, 28)
TopLogo.Position = UDim2.fromOffset(8, 7)
TopLogo.BackgroundColor3 = Color3.fromRGB(28, 28, 38)
TopLogo.BorderSizePixel = 0
TopLogo.Parent = TopBar
Instance.new("UICorner", TopLogo).CornerRadius = UDim.new(0, 7)

local TopLogoText = Instance.new("TextLabel")
TopLogoText.Size = UDim2.fromScale(1, 1)
TopLogoText.BackgroundTransparency = 1
TopLogoText.Font = Enum.Font.GothamBlack
TopLogoText.TextSize = 10
TopLogoText.TextColor3 = Color3.fromRGB(255, 255, 255)
TopLogoText.Text = "JAPvd"
TopLogoText.Parent = TopLogo

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -115, 1, 0)
Title.Position = UDim2.fromOffset(62, 0)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 16
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Text = "JAPvd  |  Violence District"
Title.Parent = TopBar

local CloseButton = Instance.new("TextButton")
CloseButton.Size = UDim2.fromOffset(38, 30)
CloseButton.Position = UDim2.new(1, -44, 0, 6)
CloseButton.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
CloseButton.Font = Enum.Font.GothamBold
CloseButton.TextSize = 14
CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseButton.Text = "X"
CloseButton.Parent = TopBar
Instance.new("UICorner", CloseButton).CornerRadius = UDim.new(0, 6)

-- ============================================================================
-- DANGER INDICATOR: panah + peringatan Killer/Zombie terdekat
-- ============================================================================
local DangerLayer = Instance.new("Frame")
DangerLayer.Name = "DangerIndicator"
DangerLayer.Size = UDim2.fromScale(1, 1)
DangerLayer.BackgroundTransparency = 1
DangerLayer.BorderSizePixel = 0
DangerLayer.ZIndex = 5
DangerLayer.Parent = ScreenGui

local DangerArrow = Instance.new("TextLabel")
DangerArrow.Name = "Arrow"
DangerArrow.Size = UDim2.fromOffset(48, 48)
DangerArrow.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
DangerArrow.BackgroundTransparency = 0.3
DangerArrow.Font = Enum.Font.GothamBlack
DangerArrow.TextSize = 24
DangerArrow.Text = "▲"
DangerArrow.Visible = false
DangerArrow.ZIndex = 6
DangerArrow.Parent = DangerLayer
Instance.new("UICorner", DangerArrow).CornerRadius = UDim.new(1, 0)

local DangerLabel = Instance.new("TextLabel")
DangerLabel.Name = "Warning"
DangerLabel.Size = UDim2.fromOffset(280, 36)
DangerLabel.Position = UDim2.new(0.5, -140, 1, -118)
DangerLabel.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
DangerLabel.BackgroundTransparency = 0.3
DangerLabel.Font = Enum.Font.GothamBold
DangerLabel.TextSize = 14
DangerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
DangerLabel.Text = ""
DangerLabel.Visible = false
DangerLabel.ZIndex = 6
DangerLabel.Parent = DangerLayer
Instance.new("UICorner", DangerLabel).CornerRadius = UDim.new(0, 8)

local function updateDangerIndicator()
    if not State.DangerIndicator or not Camera then
        DangerArrow.Visible = false
        DangerLabel.Visible = false
        return
    end

    local nearest, nearestPos, nearestDist = nil, nil, CONFIG.DangerDistance
    for _, entry in pairs(Tracked) do
        if entry.Category == "Killer" or entry.Category == "Zombie" then
            local pos = objectPosition(entry.Object)
            if pos then
                local dist = distanceFromMe(pos)
                if dist < nearestDist then
                    nearest, nearestPos, nearestDist = entry, pos, dist
                end
            end
        end
    end

    if not nearest or not nearestPos then
        DangerArrow.Visible = false
        DangerLabel.Visible = false
        return
    end

    local relative = nearestPos - Camera.CFrame.Position
    local sideAmount = relative:Dot(Camera.CFrame.RightVector)
    local forwardAmount = relative:Dot(Camera.CFrame.LookVector)
    local angle = math.atan2(sideAmount, forwardAmount) -- 0 = depan, +/-pi = belakang
    local degrees = math.deg(angle)

    local directionText = "BELAKANG"
    if degrees >= -25 and degrees <= 25 then
        directionText = "DEPAN"
    elseif degrees > 25 and degrees < 155 then
        directionText = "KANAN"
    elseif degrees < -25 and degrees > -155 then
        directionText = "KIRI"
    end

    local style = ESP_STYLE[nearest.Category]
    local arrowColor = style and style.color or Color3.fromRGB(255, 60, 70)
    local viewport = Camera.ViewportSize
    if viewport.X <= 0 then viewport = Vector2.new(1000, 600) end
    local centerX, centerY = viewport.X / 2, viewport.Y / 2
    local radiusX = math.min(330, math.max(120, centerX - 80))
    local radiusY = math.min(215, math.max(100, centerY - 110))
    local offsetX = math.sin(angle) * radiusX
    local offsetY = -math.cos(angle) * radiusY

    DangerArrow.Position = UDim2.fromOffset(centerX + offsetX - 24, centerY + offsetY - 24)
    DangerArrow.Rotation = degrees
    DangerArrow.TextColor3 = arrowColor
    DangerArrow.Visible = true

    DangerLabel.Text = string.format("⚠ %s %dm - %s", string.upper(nearest.Category), math.floor(nearestDist), directionText)
    DangerLabel.TextColor3 = arrowColor
    DangerLabel.Visible = true
end

local SideBar = Instance.new("Frame")
SideBar.Size = UDim2.new(0, 132, 1, -54)
SideBar.Position = UDim2.fromOffset(8, 48)
SideBar.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
SideBar.BorderSizePixel = 0
SideBar.Parent = Main
Instance.new("UICorner", SideBar).CornerRadius = UDim.new(0, 8)

local SideLayout = Instance.new("UIListLayout")
SideLayout.Padding = UDim.new(0, 6)
SideLayout.Parent = SideBar
local SidePadding = Instance.new("UIPadding")
SidePadding.PaddingTop = UDim.new(0, 8)
SidePadding.PaddingLeft = UDim.new(0, 8)
SidePadding.PaddingRight = UDim.new(0, 8)
SidePadding.Parent = SideBar

local Content = Instance.new("Frame")
Content.Size = UDim2.new(1, -156, 1, -54)
Content.Position = UDim2.fromOffset(148, 48)
Content.BackgroundColor3 = Color3.fromRGB(20, 20, 27)
Content.BorderSizePixel = 0
Content.Parent = Main
Instance.new("UICorner", Content).CornerRadius = UDim.new(0, 8)

local Pages = {}
local TabButtons = {}
local CurrentPage = nil

local function showPage(name)
    CurrentPage = name
    for pageName, page in pairs(Pages) do
        page.Visible = (pageName == name)
    end
    for tabName, button in pairs(TabButtons) do
        button.BackgroundColor3 = (tabName == name)
            and Color3.fromRGB(190, 40, 55)
            or Color3.fromRGB(38, 38, 48)
    end
end

local function createPage(name)
    local page = Instance.new("ScrollingFrame")
    page.Name = name
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.BorderSizePixel = 0
    page.ScrollBarThickness = 4
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.Visible = false
    page.Parent = Content

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7)
    layout.Parent = page
    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 9)
    pad.PaddingLeft = UDim.new(0, 9)
    pad.PaddingRight = UDim.new(0, 9)
    pad.Parent = page

    Pages[name] = page

    local tab = Instance.new("TextButton")
    tab.Size = UDim2.new(1, 0, 0, 34)
    tab.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
    tab.Font = Enum.Font.GothamBold
    tab.TextSize = 13
    tab.TextColor3 = Color3.fromRGB(255, 255, 255)
    tab.Text = name
    tab.Parent = SideBar
    Instance.new("UICorner", tab).CornerRadius = UDim.new(0, 6)
    TabButtons[name] = tab
    tab.MouseButton1Click:Connect(function() showPage(name) end)
    return page
end

local function sectionTitle(page, text)
    local item = Instance.new("TextLabel")
    item.Size = UDim2.new(1, 0, 0, 22)
    item.BackgroundTransparency = 1
    item.Font = Enum.Font.GothamBold
    item.TextSize = 14
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.TextColor3 = Color3.fromRGB(255, 120, 130)
    item.Text = text
    item.Parent = page
    return item
end

local function addToggle(page, text, stateKey, default, onChanged)
    State[stateKey] = default
    local holder = Instance.new("TextButton")
    holder.Size = UDim2.new(1, 0, 0, 31)
    holder.BackgroundColor3 = Color3.fromRGB(31, 31, 40)
    holder.Font = Enum.Font.Gotham
    holder.TextSize = 13
    holder.TextXAlignment = Enum.TextXAlignment.Left
    holder.TextColor3 = Color3.fromRGB(240, 240, 240)
    holder.Text = "   " .. text
    holder.AutoButtonColor = true
    holder.Parent = page
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 6)

    local indicator = Instance.new("Frame")
    indicator.Size = UDim2.fromOffset(38, 18)
    indicator.Position = UDim2.new(1, -46, 0.5, -9)
    indicator.BackgroundColor3 = default and Color3.fromRGB(70, 210, 110) or Color3.fromRGB(80, 80, 90)
    indicator.BorderSizePixel = 0
    indicator.Parent = holder
    Instance.new("UICorner", indicator).CornerRadius = UDim.new(1, 0)

    local function render()
        indicator.BackgroundColor3 = State[stateKey] and Color3.fromRGB(70, 210, 110) or Color3.fromRGB(80, 80, 90)
    end
    holder.MouseButton1Click:Connect(function()
        State[stateKey] = not State[stateKey]
        render()
        if onChanged then onChanged(State[stateKey]) end
    end)
    render()
    return holder
end

local function addButton(page, text, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, 32)
    button.BackgroundColor3 = Color3.fromRGB(58, 58, 72)
    button.Font = Enum.Font.GothamBold
    button.TextSize = 13
    button.TextColor3 = Color3.fromRGB(255, 255, 255)
    button.Text = text
    button.Parent = page
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
    button.MouseButton1Click:Connect(callback)
    return button
end

local function addSlider(page, text, minValue, maxValue, default, callback)
    local holder = Instance.new("Frame")
    holder.Size = UDim2.new(1, 0, 0, 45)
    holder.BackgroundColor3 = Color3.fromRGB(31, 31, 40)
    holder.BorderSizePixel = 0
    holder.Parent = page
    Instance.new("UICorner", holder).CornerRadius = UDim.new(0, 6)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -14, 0, 19)
    label.Position = UDim2.fromOffset(8, 2)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.Gotham
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextColor3 = Color3.fromRGB(240, 240, 240)
    label.Parent = holder

    local track = Instance.new("TextButton")
    track.Size = UDim2.new(1, -16, 0, 10)
    track.Position = UDim2.fromOffset(8, 27)
    track.BackgroundColor3 = Color3.fromRGB(65, 65, 78)
    track.Text = ""
    track.AutoButtonColor = false
    track.Parent = holder
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = Color3.fromRGB(220, 55, 75)
    fill.BorderSizePixel = 0
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local value = default
    local function render()
        local alpha = (value - minValue) / (maxValue - minValue)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        label.Text = string.format("%s: %d", text, math.floor(value))
    end
    local function setFromX(x)
        local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X), 0, 1)
        value = minValue + (maxValue - minValue) * alpha
        render()
        callback(value)
    end
    local dragging = false
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromX(input.Position.X)
        end
    end)
    track.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setFromX(input.Position.X)
        end
    end)
    callback(default)
    render()
    return holder
end

-- drag jendela
do
    local dragging, dragStart, frameStart = false, nil, nil
    TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            frameStart = Main.Position
        end
    end)
    TopBar.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            Main.Position = UDim2.new(frameStart.X.Scale, frameStart.X.Offset + delta.X, frameStart.Y.Scale, frameStart.Y.Offset + delta.Y)
        end
    end)
end

-- ============================================================================
-- BUILD UI PAGES
-- ============================================================================
local SurvivorPage = createPage("Survivor")
sectionTitle(SurvivorPage, "Opsional - nyalakan manual (default mati)")
addToggle(SurvivorPage, "Auto Skill Check (beta)", "AutoSkillCheck", false)
addToggle(SurvivorPage, "Auto Repair - tahan E di Generator", "AutoRepair", false)
addToggle(SurvivorPage, "Auto Heal - tahan E di teman luka", "AutoHeal", false)
addToggle(SurvivorPage, "Auto Unhook - selamatkan teman", "AutoUnhook", false)
addToggle(SurvivorPage, "Auto Pallet - jatuhkan saat dikejar", "AutoPallet", false)
addToggle(SurvivorPage, "Auto Vault - lompat window saat dikejar", "AutoVault", false)
addToggle(SurvivorPage, "Auto Parry - aktifkan tool saat Killer dekat", "AutoParry", false)
addSlider(SurvivorPage, "Jarak Auto Parry (stud)", 7, 25, CONFIG.ParryDistance, function(v) CONFIG.ParryDistance = v end)
addSlider(SurvivorPage, "Toleransi Skill Check (derajat)", 5, 25, CONFIG.SkillCheckTolerance, function(v) CONFIG.SkillCheckTolerance = v end)

local VisualPage = createPage("Visuals")
sectionTitle(VisualPage, "ESP / Aura")
addToggle(VisualPage, "Killer ESP (termasuk The Cure)", "KillerESP", true)
addToggle(VisualPage, "Survivor ESP - biru (+ status & HP)", "SurvivorESP", true)
addToggle(VisualPage, "Infected ESP - CURE (+ status & HP)", "InfectedESP", true)
addToggle(VisualPage, "Zombie ESP - CURE / SCP-049-2 (+ HP)", "ZombieESP", true)
addToggle(VisualPage, "Generator ESP (+ progress)", "GeneratorESP", true)
addToggle(VisualPage, "Exit Gate ESP", "ExitGateESP", true)
addToggle(VisualPage, "Hook/Spike ESP", "HookESP", true)
addToggle(VisualPage, "Pallet ESP", "PalletESP", true)
addToggle(VisualPage, "Window/Vault ESP", "WindowESP", true)
addSlider(VisualPage, "Jarak ESP maksimum", 200, 2500, CONFIG.MaxESPDistance, function(v) CONFIG.MaxESPDistance = v end)
addButton(VisualPage, "Refresh ESP Sekarang", function() refreshObjectESP() end)
sectionTitle(VisualPage, "Danger Indicator & Smart Generator")
addToggle(VisualPage, "Danger Indicator Killer/Zombie", "DangerIndicator", true)
addSlider(VisualPage, "Jarak Danger Indicator (stud)", 15, 90, CONFIG.DangerDistance, function(v) CONFIG.DangerDistance = v end)
sectionTitle(VisualPage, "Smart Gen: persen, bar, [PRIORITAS] & [SELESAI]")
sectionTitle(VisualPage, "Tanpa garis penunjuk, tanpa notifikasi.")

local KillerPage = createPage("Killer")
sectionTitle(KillerPage, "Bantuan Killer")
addToggle(KillerPage, "Aim Assist (tahan klik kanan)", "AimAssist", false)
sectionTitle(KillerPage, "Info")
local killerInfo = sectionTitle(KillerPage, "The Cure masuk Killer ESP; Survivor normal biru.")

local TeleportPage = createPage("Teleport")
sectionTitle(TeleportPage, "Teleport Cepat")
addButton(TeleportPage, "Ke Generator Terdekat", function()
    local entry = nearestTracked("Generator")
    if entry then teleportTo(objectPosition(entry.Object)) end
end)
addButton(TeleportPage, "Ke Exit Gate Terdekat", function()
    local entry = nearestTracked("ExitGate")
    if entry then teleportTo(objectPosition(entry.Object)) end
end)
addButton(TeleportPage, "Ke Hook/Spike Terdekat", function()
    local entry = nearestTracked("Hook")
    if entry then teleportTo(objectPosition(entry.Object)) end
end)
addButton(TeleportPage, "Ke Killer", function()
    local killer = getKiller()
    local root = killer and getRoot(killer)
    if root then teleportTo(root.Position) end
end)
addButton(TeleportPage, "Ke Survivor Terluka (HP terendah)", function()
    local best, bestHp = nil, math.huge
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and getRole(player) ~= "Killer" then
            local hum, root = getHumanoid(player), getRoot(player)
            if hum and root and hum.Health > 0 and hum.Health < bestHp then
                best, bestHp = root, hum.Health
            end
        end
    end
    if best then teleportTo(best.Position) end
end)

local MiscPage = createPage("Misc")
sectionTitle(MiscPage, "Player & Dunia")
addToggle(MiscPage, "Pakai WalkSpeed/JumpPower custom", "PlayerMods", false)
addSlider(MiscPage, "WalkSpeed", 16, 60, CONFIG.WalkSpeed, function(v) CONFIG.WalkSpeed = v end)
addSlider(MiscPage, "JumpPower", 50, 130, CONFIG.JumpPower, function(v) CONFIG.JumpPower = v end)
addToggle(MiscPage, "No Clip", "NoClip", false)
addToggle(MiscPage, "Infinite Jump", "InfiniteJump", false)
addToggle(MiscPage, "Custom FOV", "CustomFOV", false)
addSlider(MiscPage, "Field of View", 60, 120, CONFIG.FieldOfView, function(v) CONFIG.FieldOfView = v end)

local LightingBackup = nil
addToggle(MiscPage, "Fullbright", "Fullbright", false, function(enabled)
    if enabled then
        if not LightingBackup then
            LightingBackup = {
                Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
                FogEnd = Lighting.FogEnd, GlobalShadows = Lighting.GlobalShadows,
                Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
            }
        end
        Lighting.Brightness = 2
        Lighting.ClockTime = 14.5
        Lighting.FogEnd = 100000
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(200, 200, 200)
        Lighting.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
    elseif LightingBackup then
        for key, value in pairs(LightingBackup) do
            pcall(function() Lighting[key] = value end)
        end
    end
end)
addToggle(MiscPage, "Anti AFK (manual)", "AntiAFK", false)

local SettingsPage = createPage("Settings")
sectionTitle(SettingsPage, "Pengaturan")
local statusLabel = sectionTitle(SettingsPage, "Status: berjalan")
addButton(SettingsPage, "Sembunyikan / Tampilkan UI (RightShift)", function()
    Main.Visible = not Main.Visible
end)

local function unloadScript()
    Alive = false
    setInteractHeld(false)
    clearESP()
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    pcall(function() ScreenGui:Destroy() end)
    statusLabel.Text = "Status: berhenti"
end
addButton(SettingsPage, "UNLOAD SCRIPT", unloadScript)
CloseButton.MouseButton1Click:Connect(unloadScript)

showPage("Survivor")

-- ============================================================================
-- MAIN LOOPS
-- ============================================================================
connect(UserInputService.InputBegan, function(input, gameProcessed)
    if input.KeyCode == CONFIG.ToggleKey and not UserInputService:GetFocusedTextBox() then
        Main.Visible = not Main.Visible
    end
    if State.InfiniteJump and input.KeyCode == Enum.KeyCode.Space and not gameProcessed then
        local hum = getHumanoid()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

connect(LocalPlayer.Idled, function()
    if State.AntiAFK then
        local virtualUser = nil
        pcall(function() virtualUser = game:GetService("VirtualUser") end)
        if virtualUser then
            pcall(function() virtualUser:CaptureController() end)
            pcall(function() virtualUser:ClickButton2(Vector2.new()) end)
        end
    end
end)

-- pemindaian objek berkala
task.spawn(function()
    while Alive do
        pcall(refreshObjectESP)
        task.wait(1.5)
    end
end)

-- loop bantuan (skill check, repair, parry, pallet, vault)
local PromptCooldown = 0
task.spawn(function()
    while Alive do
        local shouldHold = false
        pcall(function()
            local killer, killerDist = getKiller()

            if State.AutoSkillCheck then
                tryAutoSkillCheck()
            end

            if State.AutoParry then
                tryAutoParry(killer, killerDist)
            end

            if State.AutoRepair then
                local entry, dist = nearestTracked("Generator", CONFIG.AutoRepairRange)
                if entry then shouldHold = true end
            end

            if not shouldHold and State.AutoHeal then
                local target = nearestPlayer(function(player, hum)
                    return getRole(player) ~= "Killer" and hum.Health < hum.MaxHealth
                end, CONFIG.AutoHealRange)
                if target then shouldHold = true end
            end

            if os.clock() > PromptCooldown then
                if State.AutoUnhook then
                    local prompt = nearestPrompt({ "unhook", "unspike", "rescue", "release", "save" }, CONFIG.AutoUnhookRange)
                    if prompt then
                        firePrompt(prompt)
                        PromptCooldown = os.clock() + 0.8
                    end
                end
                if State.AutoPallet and killer and killerDist < 24 then
                    local prompt = nearestPrompt({ "pallet", "drop" }, 8)
                    if prompt then
                        firePrompt(prompt)
                        PromptCooldown = os.clock() + 1
                    end
                end
                if State.AutoVault and killer and killerDist < 19 then
                    local prompt = nearestPrompt({ "vault", "window" }, 7)
                    if prompt then
                        firePrompt(prompt)
                        PromptCooldown = os.clock() + 0.8
                    end
                end
            end
        end)
        -- Auto repair/heal memakai tahan E; fitur lain tidak menahan tombol
        if State.AutoRepair or State.AutoHeal then
            setInteractHeld(shouldHold)
        else
            setInteractHeld(false)
        end
        task.wait(0.06)
    end
end)

-- loop per frame: ESP, mods, aim assist, no clip
local LastESPUpdate = 0
connect(RunService.Heartbeat, function()
    if not Alive then return end
    Camera = Workspace.CurrentCamera or Camera

    if os.clock() - LastESPUpdate > 0.12 then
        LastESPUpdate = os.clock()
        pcall(updateESP)
        pcall(updateDangerIndicator)
    end

    local hum = getHumanoid()
    if hum then
        if State.PlayerMods then
            hum.WalkSpeed = CONFIG.WalkSpeed
            hum.JumpPower = CONFIG.JumpPower
            hum.UseJumpPower = true
        end
        if State.NoClip then
            local char = getCharacter()
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide = false end
                end
            end
        end
    end

    if State.CustomFOV and Camera then
        Camera.FieldOfView = CONFIG.FieldOfView
    end

    if State.AimAssist and Camera and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        local target = nearestPlayer(function(player)
            return getRole(player) ~= "Killer"
        end, 220)
        local root = target and getRoot(target)
        if root then
            local goal = CFrame.new(Camera.CFrame.Position, root.Position + Vector3.new(0, 1.5, 0))
            Camera.CFrame = Camera.CFrame:Lerp(goal, 0.18)
        end
    end
end)

-- ============================================================================
-- LOADING SEQUENCE JAPvd (muncul setiap script diexecute)
-- ============================================================================
task.spawn(function()
    setLoading(0.08, "Menyiapkan JAPvd...")
    task.wait(0.35)

    setLoading(0.28, "Memuat logo & antarmuka...")
    task.wait(0.4)

    setLoading(0.52, "Memindai pemain, zombie, generator & objek map...")
    pcall(refreshObjectESP)
    task.wait(0.35)

    setLoading(0.76, "Mengaktifkan ESP saja - fitur lain tetap mati...")
    task.wait(0.4)

    setLoading(0.92, "Finalisasi JAPvd...")
    task.wait(0.3)

    finishLoading()
    if Alive then
        Main.Visible = true
    end
    print("[JAPvd] ESP aktif (termasuk Zombie CURE). Fitur lain mati sampai dinyalakan manual - RightShift untuk menu.")
end)
