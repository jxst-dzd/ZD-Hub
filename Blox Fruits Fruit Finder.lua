--[[
    ════════════════════════════════════════════════════════════════════════════
    ZD HUB — ULTIMATE FRUIT FINDER & GACHA AUTOMATION ENGINE
    ════════════════════════════════════════════════════════════════════════════
    Engine Version : 5.0 (High-Performance Multi-Sea Edition)
    Compatible With: Blox Fruits (Sea 1, Sea 2, Sea 3)
    Features:
      • Instant Team Selector ("Marine" / "Pirates")
      • MCP Bridge Client Integration (127.0.0.1:16384 connector)
      • Smart Fruit Hunter (Autonomous Workspace fruit scanner & zero-rollback flyer)
      • Dimension Portal Fast-Travel (Warp through official Sea portals)
      • Leave Portal Ulti Watchdog (Instant escape from Portal V / Dimensional Shift)
      • Blox Fruit Gacha / Cousin Auto Roll
      • Intelligent Devil Fruit Storage Engine (Check if storeable before store)
      • Low-Beli Auto Dropper (Configurable Beli cutoff, default: $1,000,000)
      • In-Game Silent ServerBrowser Hop (3-8 players, visited history, 4-case failure recovery)
      • Native FPS Booster (LowCpu engine from tets 6.lua)
      • 3D White Screen Mode (Set3dRenderingEnabled CPU/GPU freezer)
      • Rich Discord Webhook Reporter (Color-coded rarity embeds)
      • Sleek Minimal HUD Dashboard
    ════════════════════════════════════════════════════════════════════════════
--]]

-- Global reload path for ServerHop auto-reconnection
getgenv().ZD_RELOAD_PATH = "Blox Fruits/Fruit Finder Script.lua"

-- ─── STEP 0: CONFIGURATION TABLE ─────────────────────────────────────────────
getgenv().FruitFinderConfig = getgenv().FruitFinderConfig or {
    SelectTeam          = "Marine",      -- "Marine" or "Pirates"
    SmartTween          = true,          -- Use Universal Smart Tween engine (obstacle avoidance & portals)
    UsePortalFruit      = true,          -- Use Portal Fruit (Move C) warp method if available
    WallSlowdown        = true,          -- Slow down when obstacle/wall/clip is near
    PortalTeleport      = true,          -- Fast-travel through game dimension portals
    LeavePortalUlti     = true,          -- Instantly break out of Portal V (Dimensional Shift)
    FPSBoost            = false,         -- Ultra Low CPU / Low Graphics (from tets 6.lua)
    WhiteScreen         = false,         -- Disables 3D rendering for massive CPU/GPU savings
    CollectFruit        = true,          -- Scan, fly to, and pick up spawned fruits
    NearFruitTPDistance = 50,            -- Safe distance threshold (studs) to TP to handle without rollback
    RandomFruit         = true,          -- Auto buy from Fruit Dealer Cousin (Blox Fruit Gacha)
    AutoCloseGachaUI    = true,          -- Auto escape / close gacha reveal window if still open
    CheckFruitStoreable = true,          -- Check inventory capacity before storing
    Webhook             = "",            -- Discord Webhook URL
    SendWebhookNewItem  = true,          -- Send webhook notification when fruit is found/rolled
    FarmWithHop         = true,          -- Hop server when no fruits remain or after collection
    AutoStoreFruit      = true,          -- Store fruits into player Devil Fruit Storage
    AutoDropFruitLowBeli= true,          -- Drop fruits worth less than LowBeliValue
    LowBeliValue        = 1000000,       -- 1,000,000 Beli threshold for dropping low-tier fruits
    FlightSpeed         = 260,           -- Studs/sec tween flight speed (default: 260)
    IgnoreDroppedFruit  = true,          -- Blacklist fruits dropped due to low-beli or full storage
    ShowMinimalHUD      = true,          -- Toggle minimal HUD overlay
    UseMcpClient        = false          -- Initialize MCP Bridge Server Client (127.0.0.1:16384)
}

local Config = getgenv().FruitFinderConfig

local SETTINGS_FILE = "ZD_Hub/FruitFinder_Settings.json"

local function loadSettingsFromFile()
    pcall(function()
        if isfile and isfile(SETTINGS_FILE) then
            local HttpService = game:GetService("HttpService")
            local decoded = HttpService:JSONDecode(readfile(SETTINGS_FILE))
            if type(decoded) == "table" then
                for k, v in pairs(decoded) do
                    Config[k] = v
                end
            end
        end
    end)
end

local function saveSettingsToFile()
    pcall(function()
        if writefile then
            local HttpService = game:GetService("HttpService")
            if makefolder and not isfolder("ZD_Hub") then makefolder("ZD_Hub") end
            writefile(SETTINGS_FILE, HttpService:JSONEncode(Config))
        end
    end)
end

loadSettingsFromFile()

-- ─── STEP 1: MULTI-EXECUTION GUARD & ENGINE INITIALIZATION ───────────────────
if getgenv().ZD_FRUITFINDER_STOP then
    pcall(getgenv().ZD_FRUITFINDER_STOP)
end
getgenv().ZD_FRUITFINDER_RUNNING = true

-- Connect MCP Client if configured (single connection guard)
if Config.UseMcpClient and not getgenv().ZD_MCP_CONNECTED then
    getgenv().ZD_MCP_CONNECTED = true
    task.spawn(function()
        pcall(function()
            getgenv().BridgeURL = getgenv().BridgeURL or "127.0.0.1:16384"
            loadstring(game:HttpGet("http://" .. getgenv().BridgeURL .. "/connector.luau"))()
            print("[ZD Hub] MCP Bridge Client initialized.")
        end)
    end)
end

-- Wait for Roblox Game & Services
if not game:IsLoaded() then
    game.Loaded:Wait()
end
repeat task.wait(0.2) until game:IsLoaded()

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")
local TeleportService   = game:GetService("TeleportService")
local Lighting          = game:GetService("Lighting")
local UserInputService  = game:GetService("UserInputService")
local CoreGui           = game:GetService("CoreGui")

local localplayer = Players.LocalPlayer
while not localplayer do
    task.wait(0.2)
    localplayer = Players.LocalPlayer
end

-- HTTP Request resolution helper
local httpRequest = (syn and syn.request) 
    or (http and http.request) 
    or http_request 
    or (fluxus and fluxus.request) 
    or request

-- ─── STEP 2: TEAM AUTO-SELECTION ─────────────────────────────────────────────
local function autoSelectTeam()
    if localplayer.Team and localplayer.Team.Name ~= "" and localplayer.Team.Name ~= "Neutral" then
        return
    end

    local targetTeam = Config.SelectTeam or "Marine"
    local isMarine = targetTeam:lower():find("marine") ~= nil
    local remoteTeamName = isMarine and "Marines" or "Pirates"

    -- Method A: Modern Blox Fruits UI (TeamSelection GUI)
    pcall(function()
        local pGui = localplayer:FindFirstChild("PlayerGui")
        if not pGui then return end
        local teamSelection = pGui:FindFirstChild("TeamSelection")
        if teamSelection then
            local btnName = isMarine and "marine" or "pirate"
            local btn = teamSelection:FindFirstChild(btnName, true)
            if btn and (btn:IsA("GuiButton") or btn:IsA("ImageButton") or btn:IsA("TextButton")) then
                if getconnections then
                    for _, conn in ipairs(getconnections(btn.MouseButton1Down)) do
                        pcall(conn.Function)
                    end
                    task.wait(0.05)
                    for _, conn in ipairs(getconnections(btn.MouseButton1Up)) do
                        pcall(conn.Function)
                    end
                    for _, conn in ipairs(getconnections(btn.Activated)) do
                        pcall(conn.Function)
                    end
                    for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do
                        pcall(conn.Function)
                    end
                end
                if firesignal then
                    pcall(function() firesignal(btn.MouseButton1Down) end)
                    pcall(function() firesignal(btn.MouseButton1Up) end)
                    pcall(function() firesignal(btn.Activated) end)
                    pcall(function() firesignal(btn.MouseButton1Click) end)
                end
            end
        end
    end)

    -- Method B: Legacy UI (Main / Main (minimal) ChooseTeam)
    pcall(function()
        local pGui = localplayer:FindFirstChild("PlayerGui")
        if not pGui then return end
        local chooseTeam = (pGui:FindFirstChild("Main (minimal)") and pGui["Main (minimal)"]:FindFirstChild("ChooseTeam"))
            or (pGui:FindFirstChild("Main") and pGui.Main:FindFirstChild("ChooseTeam"))

        if chooseTeam and chooseTeam.Visible then
            local container = chooseTeam:FindFirstChild("Container")
            local targetTeamObj = container and (container:FindFirstChild(remoteTeamName) or container:FindFirstChild("Marines") or container:FindFirstChild("Pirates"))
            local btn = targetTeamObj and targetTeamObj:FindFirstChild("Frame") and targetTeamObj.Frame:FindFirstChild("TextButton")
            if btn then
                if getconnections then
                    for _, conn in ipairs(getconnections(btn.Activated)) do
                        pcall(conn.Function)
                    end
                    for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do
                        pcall(conn.Function)
                    end
                end
                if firesignal then
                    pcall(function() firesignal(btn.MouseButton1Click) end)
                    pcall(function() firesignal(btn.Activated) end)
                end
            end
        end
    end)

    -- Method C: Remote call fallback
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local commF = remotes and remotes:FindFirstChild("CommF_")
        if commF then
            commF:InvokeServer("SetTeam", remoteTeamName)
        end
    end)
end

task.spawn(function()
    while not localplayer.Team or localplayer.Team.Name == "" or localplayer.Team.Name == "Neutral" do
        autoSelectTeam()
        task.wait(0.8)
    end
end)

-- ─── STEP 3: NATIVE FPS BOOSTER (LowCpu Engine from tets 6.lua) ──────────────
local function applyFPSBoost()
    pcall(function()
        local decalsyeeted = true
        local g = game
        local w = g.Workspace
        local l = g.Lighting
        local t = w.Terrain

        t.WaterWaveSize = 0
        t.WaterWaveSpeed = 0
        t.WaterReflectance = 0
        t.WaterTransparency = 0
        l.GlobalShadows = false
        l.FogEnd = 9e9
        l.Brightness = 0

        pcall(function()
            settings().Rendering.QualityLevel = "Level01"
        end)

        local function optimizePart(v)
            pcall(function()
                if v:IsA("Part") or v:IsA("Union") or v:IsA("CornerWedgePart") or v:IsA("TrussPart") then
                    v.Material = Enum.Material.Plastic
                    v.Reflectance = 0
                elseif (v:IsA("Decal") or v:IsA("Texture")) and decalsyeeted then
                    v.Transparency = 1
                elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
                    v.Lifetime = NumberRange.new(0)
                elseif v:IsA("Explosion") then
                    v.BlastPressure = 1
                    v.BlastRadius = 1
                elseif v:IsA("Fire") or v:IsA("SpotLight") or v:IsA("Smoke") or v:IsA("Sparkles") then
                    v.Enabled = false
                elseif v:IsA("MeshPart") then
                    v.Material = Enum.Material.Plastic
                    v.Reflectance = 0
                    v.TextureID = ""
                end
            end)
        end

        for _, v in pairs(g:GetDescendants()) do
            optimizePart(v)
        end

        for _, e in pairs(l:GetChildren()) do
            if e:IsA("BlurEffect") or e:IsA("SunRaysEffect") or e:IsA("ColorCorrectionEffect") 
                or e:IsA("BloomEffect") or e:IsA("DepthOfFieldEffect") then
                e.Enabled = false
            end
        end

        -- Keep newly streamed objects optimized
        w.DescendantAdded:Connect(function(child)
            if Config.FPSBoost then
                task.delay(0.1, function() optimizePart(child) end)
            end
        end)
    end)
end

if Config.FPSBoost then
    task.spawn(applyFPSBoost)
end

-- ─── STEP 4: 3D WHITE SCREEN ENGINE ──────────────────────────────────────────
local function updateWhiteScreen(enabled)
    pcall(function()
        RunService:Set3dRenderingEnabled(not enabled)
    end)
end

if Config.WhiteScreen then
    updateWhiteScreen(true)
end

-- ─── STEP 5: MULTI-SEA DETECTION ─────────────────────────────────────────────
local SeaConfig = {
    [1] = { Name = "First Sea",  PlaceIds = { 2753915549, 85211729168715 }, Keywords = { "Jungle", "PirateIsland", "MiddleTown" } },
    [2] = { Name = "Second Sea", PlaceIds = { 4442272183, 79091703265657 }, Keywords = { "Dressrosa", "GreenBit", "Colosseum" } },
    [3] = { Name = "Third Sea",  PlaceIds = { 7449423635, 100117331123089 }, Keywords = { "Turtle", "SeaCastle", "Hydra", "PortTown" } }
}

local function detectSea()
    for seaNum, data in ipairs(SeaConfig) do
        for _, pid in ipairs(data.PlaceIds) do
            if game.PlaceId == pid then
                return seaNum, data.Name
            end
        end
    end
    local map = workspace:FindFirstChild("Map")
    if map then
        for seaNum, data in ipairs(SeaConfig) do
            for _, kw in ipairs(data.Keywords) do
                if map:FindFirstChild(kw) then
                    return seaNum, data.Name
                end
            end
        end
    end
    return 1, "First Sea"
end

local CurrentSeaNum, CurrentSeaName = detectSea()
local FirstSea  = (CurrentSeaNum == 1)
local SecondSea = (CurrentSeaNum == 2)
local ThirdSea  = (CurrentSeaNum == 3)

-- ─── STEP 6: DEVIL FRUIT DATABASE & PRICE CACHE ──────────────────────────────
local StaticFruitData = {
    -- Common
    ["Rocket-Rocket"]   = { Price = 5000,    Rarity = "Common",    Color = 0x95a5a6 },
    ["Spin-Spin"]       = { Price = 7500,    Rarity = "Common",    Color = 0x95a5a6 },
    ["Blade-Blade"]     = { Price = 30000,   Rarity = "Common",    Color = 0x95a5a6 },
    ["Chop-Chop"]       = { Price = 30000,   Rarity = "Common",    Color = 0x95a5a6 },
    ["Spring-Spring"]   = { Price = 60000,   Rarity = "Common",    Color = 0x95a5a6 },
    ["Bomb-Bomb"]       = { Price = 80000,   Rarity = "Common",    Color = 0x95a5a6 },
    ["Smoke-Smoke"]     = { Price = 100000,  Rarity = "Common",    Color = 0x95a5a6 },
    ["Spike-Spike"]     = { Price = 180000,  Rarity = "Common",    Color = 0x95a5a6 },
    -- Uncommon
    ["Flame-Flame"]     = { Price = 250000,  Rarity = "Uncommon",  Color = 0x2ecc71 },
    ["Falcon-Falcon"]   = { Price = 300000,  Rarity = "Uncommon",  Color = 0x2ecc71 },
    ["Eagle-Eagle"]     = { Price = 300000,  Rarity = "Uncommon",  Color = 0x2ecc71 },
    ["Ice-Ice"]         = { Price = 350000,  Rarity = "Uncommon",  Color = 0x2ecc71 },
    ["Sand-Sand"]       = { Price = 420000,  Rarity = "Uncommon",  Color = 0x2ecc71 },
    ["Dark-Dark"]       = { Price = 500000,  Rarity = "Uncommon",  Color = 0x2ecc71 },
    ["Diamond-Diamond"] = { Price = 600000,  Rarity = "Uncommon",  Color = 0x2ecc71 },
    -- Rare
    ["Light-Light"]     = { Price = 650000,  Rarity = "Rare",      Color = 0x3498db },
    ["Rubber-Rubber"]   = { Price = 750000,  Rarity = "Rare",      Color = 0x3498db },
    ["Barrier-Barrier"] = { Price = 800000,  Rarity = "Rare",      Color = 0x3498db },
    ["Ghost-Ghost"]     = { Price = 940000,  Rarity = "Rare",      Color = 0x3498db },
    ["Magma-Magma"]     = { Price = 850000,  Rarity = "Rare",      Color = 0x3498db },
    -- Legendary
    ["Quake-Quake"]     = { Price = 1000000, Rarity = "Legendary", Color = 0x9b59b6 },
    ["Buddha-Buddha"]   = { Price = 1200000, Rarity = "Legendary", Color = 0x9b59b6 },
    ["Love-Love"]       = { Price = 1300000, Rarity = "Legendary", Color = 0x9b59b6 },
    ["Spider-Spider"]   = { Price = 1500000, Rarity = "Legendary", Color = 0x9b59b6 },
    ["Sound-Sound"]     = { Price = 1700000, Rarity = "Legendary", Color = 0x9b59b6 },
    ["Phoenix-Phoenix"] = { Price = 1800000, Rarity = "Legendary", Color = 0x9b59b6 },
    ["Portal-Portal"]   = { Price = 1900000, Rarity = "Legendary", Color = 0x9b59b6 },
    ["Rumble-Rumble"]   = { Price = 2100000, Rarity = "Legendary", Color = 0x9b59b6 },
    ["Lightning-Lightning"]={ Price = 2100000, Rarity = "Legendary", Color = 0x9b59b6 },
    ["Pain-Pain"]       = { Price = 2400000, Rarity = "Legendary", Color = 0x9b59b6 },
    ["Blizzard-Blizzard"]={ Price = 2400000, Rarity = "Legendary", Color = 0x9b59b6 },
    -- Mythical
    ["Gravity-Gravity"] = { Price = 2500000, Rarity = "Mythical",  Color = 0xe74c3c },
    ["Mammoth-Mammoth"] = { Price = 2700000, Rarity = "Mythical",  Color = 0xe74c3c },
    ["T-Rex-T-Rex"]     = { Price = 2700000, Rarity = "Mythical",  Color = 0xe74c3c },
    ["Dough-Dough"]     = { Price = 2800000, Rarity = "Mythical",  Color = 0xe74c3c },
    ["Shadow-Shadow"]   = { Price = 2900000, Rarity = "Mythical",  Color = 0xe74c3c },
    ["Venom-Venom"]     = { Price = 3000000, Rarity = "Mythical",  Color = 0xe74c3c },
    ["Control-Control"] = { Price = 3200000, Rarity = "Mythical",  Color = 0xe74c3c },
    ["Gas-Gas"]         = { Price = 3200000, Rarity = "Mythical",  Color = 0xe74c3c },
    ["Spirit-Spirit"]   = { Price = 3400000, Rarity = "Mythical",  Color = 0xe74c3c },
    ["Dragon-Dragon"]   = { Price = 3500000, Rarity = "Mythical",  Color = 0xf1c40f },
    ["Leopard-Leopard"] = { Price = 5000000, Rarity = "Mythical",  Color = 0xf1c40f },
    ["Kitsune-Kitsune"] = { Price = 8000000, Rarity = "Mythical",  Color = 0xf1c40f },
    ["Yeti-Yeti"]       = { Price = 9000000, Rarity = "Mythical",  Color = 0xf1c40f }
}

local FruitPriceCache = {}

local function refreshFruitPriceCache()
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local commF = remotes and remotes:FindFirstChild("CommF_")
        if commF then
            local liveList = commF:InvokeServer("GetFruits")
            if type(liveList) == "table" then
                for _, item in pairs(liveList) do
                    if item.Name and item.Price then
                        FruitPriceCache[item.Name] = item.Price
                    end
                end
            end
        end
    end)
end

task.spawn(refreshFruitPriceCache)

local function normalizeFruitName(rawName)
    if not rawName then return "Unknown Fruit" end
    local clean = rawName:gsub(" Fruit", "")
    if clean:find("%-") then
        return clean
    end
    return clean .. "-" .. clean
end

local function getFruitInfo(fruitName)
    local norm = normalizeFruitName(fruitName)
    local price = FruitPriceCache[norm] or (StaticFruitData[norm] and StaticFruitData[norm].Price) or 0
    local rarity = (StaticFruitData[norm] and StaticFruitData[norm].Rarity) or "Unknown"
    local color = (StaticFruitData[norm] and StaticFruitData[norm].Color) or 0x3498db

    if price == 0 then
        -- Keyword heuristic
        for k, v in pairs(StaticFruitData) do
            local base = k:split("-")[1]
            if fruitName:lower():find(base:lower()) then
                return v.Price, v.Rarity, v.Color, k
            end
        end
    end
    return price, rarity, color, norm
end

-- ─── STEP 7: DISCORD WEBHOOK ENGINE ──────────────────────────────────────────
local function sendDiscordWebhook(fruitName, price, rarity, color, source)
    if not Config.Webhook or Config.Webhook == "" or not Config.SendWebhookNewItem then
        return
    end

    task.spawn(function()
        pcall(function()
            local formattedPrice = string.format("$%s Beli", tostring(price):reverse():gsub("%d%d%d", "%1,"):reverse():gsub("^,", ""))
            local embed = {
                ["title"] = "🍈 [ZD Hub] Devil Fruit Found!",
                ["description"] = string.format("**%s** has successfully obtained a new Devil Fruit!", localplayer.Name),
                ["color"] = color or 0x2ecc71,
                ["fields"] = {
                    { ["name"] = "Fruit Name",    ["value"] = tostring(fruitName),    ["inline"] = true },
                    { ["name"] = "Rarity",        ["value"] = tostring(rarity),       ["inline"] = true },
                    { ["name"] = "Value",         ["value"] = formattedPrice,        ["inline"] = true },
                    { ["name"] = "Acquired Via",  ["value"] = tostring(source or "World Spawn"), ["inline"] = true },
                    { ["name"] = "Location",      ["value"] = tostring(CurrentSeaName), ["inline"] = true },
                    { ["name"] = "Server Job ID", ["value"] = "```" .. tostring(game.JobId) .. "```", ["inline"] = false }
                },
                ["footer"] = { ["text"] = "ZD Hub · Blox Fruits Fruit Finder Engine" },
                ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }

            local payload = HttpService:JSONEncode({
                ["username"] = "ZD Hub Fruit Radar",
                ["avatar_url"] = "https://cdn.discordapp.com/attachments/1090333333333333333/1100000000000000000/zd_logo.png",
                ["embeds"] = { embed }
            })

            if httpRequest then
                httpRequest({
                    Url = Config.Webhook,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = payload
                })
            end
        end)
    end)
end

-- ─── STEP 8: UNIVERSAL SMART TWEEN INTEGRATION & FLIGHT CONTROLLER ───────────
local SmartTween = getgenv().ZD_SmartTween
if not SmartTween or type(SmartTween.To) ~= "function" then
    pcall(function()
        local paths = {
            "Blox Fruits/Universal Code/Smart Tween.lua",
            "ZD Hub/Blox Fruits/Universal Code/Smart Tween.lua",
            "Universal Code/Smart Tween.lua",
            "Smart Tween.lua",
            "SmartTween.lua"
        }
        for _, path in ipairs(paths) do
            if isfile and isfile(path) then
                if loadfile then
                    SmartTween = loadfile(path)()
                elseif readfile then
                    SmartTween = loadstring(readfile(path))()
                end
                if SmartTween and type(SmartTween.To) == "function" then
                    getgenv().ZD_SmartTween = SmartTween
                    print("[ZD Hub] Universal Smart Tween engine loaded successfully from:", path)
                    break
                end
            end
        end
    end)
end

local isTraveling = false
local activeFlightTween = nil

local function getCharacterParts()
    local char = localplayer.Character
    if not char then return nil, nil, nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    return char, root, hum
end

local function stopFlight()
    if SmartTween and type(SmartTween.Stop) == "function" then
        pcall(function()
            if SmartTween.State and SmartTween.State.IsTweening then
                SmartTween.Stop()
            end
        end)
    end
    if activeFlightTween then
        pcall(function() activeFlightTween:Cancel() end)
        activeFlightTween = nil
    end
    isTraveling = false
    local _, root, hum = getCharacterParts()
    if root then
        local hold = root:FindFirstChild("ZDFlightHold")
        if hold then hold:Destroy() end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
    if hum and hum.PlatformStand then
        hum.PlatformStand = false
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
end

local function applyHoldVelocity(root)
    local hold = root:FindFirstChild("ZDFlightHold")
    if not hold then
        hold = Instance.new("BodyVelocity")
        hold.Name = "ZDFlightHold"
        hold.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        hold.Velocity = Vector3.zero
        hold.Parent = root
    else
        hold.MaxForce = Vector3.new(1e9, 1e9, 1e9)
        hold.Velocity = Vector3.zero
    end
    return hold
end

-- flyToDirect: Fallback corridor flight (Ascent -> Ocean/Terrain Cruise -> Descent)
local function flyToDirect(targetCFrame, speedOverride, stopDistance)
    local char, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return false end

    stopFlight()

    -- Sit breaker
    if hum.Sit then
        hum.Sit = false
    end

    local stopDist = tonumber(stopDistance) or 4
    local targetPos = (typeof(targetCFrame) == "CFrame" and targetCFrame.Position) or targetCFrame
    local distance = (targetPos - root.Position).Magnitude
    if distance <= stopDist then return true end

    local speed = tonumber(speedOverride) or tonumber(Config.FlightSpeed) or 260
    local startPos = root.Position
    local finalPos = targetPos + Vector3.new(0, 1.5, 0)
    local waypoints = {}

    -- Waypoint Corridor: Gentle diagonal ramp -> Cruise above water/terrain -> Smooth descent
    if distance > 120 then
        local safeAltitude = math.max(startPos.Y, finalPos.Y, 280)
        local deltaY = math.max(0, safeAltitude - startPos.Y)
        -- Gentle climb slope (<= 35 degrees) prevents vertical anti-cheat triggers
        local requiredClimbDist = math.max(deltaY * 1.4, 60)
        local climbFraction = math.clamp(requiredClimbDist / distance, 0.15, 0.4)
        local climbPoint = startPos:Lerp(finalPos, climbFraction)
        table.insert(waypoints, Vector3.new(climbPoint.X, safeAltitude, climbPoint.Z))

        local deltaYDesc = math.max(0, safeAltitude - finalPos.Y)
        local requiredDescDist = math.max(deltaYDesc * 1.4, 60)
        local descFraction = math.clamp(1 - (requiredDescDist / distance), 0.6, 0.85)
        if descFraction > climbFraction then
            local descentStartPoint = startPos:Lerp(finalPos, descFraction)
            table.insert(waypoints, Vector3.new(descentStartPoint.X, safeAltitude, descentStartPoint.Z))
        end
    end
    table.insert(waypoints, finalPos)

    local hold = applyHoldVelocity(root)
    isTraveling = true

    -- Anti-rollback: PlatformStand disables humanoid gravity and walk collision conflicts
    if hum and not hum.PlatformStand then
        hum.PlatformStand = true
    end

    -- Noclip bypass loop during tween
    local noclipConn
    noclipConn = RunService.Stepped:Connect(function()
        local c = localplayer.Character
        if not c then
            if noclipConn then noclipConn:Disconnect() end
            return
        end
        local r = c:FindFirstChild("HumanoidRootPart")
        if r then
            r.AssemblyLinearVelocity = Vector3.zero
            r.AssemblyAngularVelocity = Vector3.zero
        end
        for _, part in ipairs(c:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end)

    for _, wp in ipairs(waypoints) do
        if not isTraveling then break end
        local _, r, h = getCharacterParts()
        if not r or not h or h.Health <= 0 then break end

        -- Early exit if we have reached proximity to the final target
        if (targetPos - r.Position).Magnitude <= stopDist then
            break
        end

        local wpDist = (wp - r.Position).Magnitude
        if wpDist <= 3 then continue end

        local duration = math.max(0.05, wpDist / speed)
        local lookDir = (wp - r.Position)
        local targetCF = CFrame.new(wp)
        if Vector2.new(lookDir.X, lookDir.Z).Magnitude > 0.5 then
            targetCF = CFrame.lookAt(wp, wp + Vector3.new(lookDir.X, 0, lookDir.Z))
        end

        local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
        activeFlightTween = TweenService:Create(r, tweenInfo, { CFrame = targetCF })

        local completed = false
        local conn = activeFlightTween.Completed:Connect(function()
            completed = true
        end)

        activeFlightTween:Play()

        local startTime = os.clock()
        while isTraveling and not completed and (os.clock() - startTime < duration + 1) do
            if not Config.CollectFruit then
                stopFlight()
                break
            end
            local _, curR, curH = getCharacterParts()
            if not curR or not curH or curH.Health <= 0 then
                stopFlight()
                break
            end
            if (wp - curR.Position).Magnitude <= 3 or (targetPos - curR.Position).Magnitude <= stopDist then
                completed = true
                break
            end
            task.wait(0.04)
        end

        if conn then conn:Disconnect() end
        if activeFlightTween then
            pcall(function() activeFlightTween:Cancel() end)
            activeFlightTween = nil
        end
    end

    if noclipConn then noclipConn:Disconnect() end
    stopFlight()

    local _, finalRoot = getCharacterParts()
    return finalRoot and (finalRoot.Position - targetPos).Magnitude <= math.max(30, stopDist + 5)
end

-- flyTo: Primary navigation method — uses Universal Smart Tween if enabled, falls back to flyToDirect
local function flyTo(targetCFrame, speedOverride, stopDistance)
    local char, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return false end

    if hum.Sit then
        hum.Sit = false
    end

    local stopDist = tonumber(stopDistance) or 4
    local targetPos = (typeof(targetCFrame) == "CFrame" and targetCFrame.Position) or targetCFrame
    local distance = (targetPos - root.Position).Magnitude
    if distance <= stopDist then
        return true
    end

    -- 1. Check if Smart Tween Engine is enabled and available
    local useSmartTween = Config.SmartTween ~= false
    if useSmartTween and SmartTween and type(SmartTween.To) == "function" then
        local configuredSpeed = tonumber(speedOverride) or tonumber(Config.FlightSpeed) or 260
        local usePortals = Config.PortalTeleport ~= false
        local useFruit = Config.UsePortalFruit ~= false
        local wallSlowdown = Config.WallSlowdown ~= false

        SmartTween.Config.DefaultSpeed = configuredSpeed
        SmartTween.Config.PrioritizePortals = usePortals
        SmartTween.Config.PreferPortals = usePortals
        SmartTween.Config.UsePortalFruit = useFruit
        SmartTween.Config.WallSlowdownEnabled = wallSlowdown
        SmartTween.Config.WallSlowdownDistance = 70
        SmartTween.Config.WallSlowdownSpeed = 50

        isTraveling = true

        -- Safety Watchdog during flight (with target proximity early-exit)
        local watchdogActive = true
        task.spawn(function()
            while watchdogActive and SmartTween.State and SmartTween.State.IsTweening do
                if not Config.CollectFruit then
                    SmartTween.Stop()
                    break
                end
                local _, curR = getCharacterParts()
                if curR and (curR.Position - targetPos).Magnitude <= stopDist then
                    SmartTween.Stop()
                    break
                end
                task.wait(0.05)
            end
        end)

        local targetCF = (typeof(targetCFrame) == "CFrame" and targetCFrame) or CFrame.new(targetPos)
        local ok, success = pcall(function()
            return SmartTween.To(targetCF, {
                Speed = configuredSpeed,
                PrioritizePortals = usePortals,
                UsePortalFruit = useFruit,
                WallSlowdownEnabled = wallSlowdown,
                WallSlowdownDistance = 70,
                WallSlowdownSpeed = 50
            })
        end)

        watchdogActive = false
        isTraveling = false
        stopFlight()

        char, root = getCharacterParts()
        if root and ((root.Position - targetPos).Magnitude <= math.max(30, stopDist + 5)) then
            return true
        end
        print("[ZD Hub] SmartTween fallback triggered. Using corridor flight...")
    end

    -- 2. Fallback: Direct Altitude Corridor Flight
    return flyToDirect(targetCFrame, speedOverride, stopDist)
end

-- ─── STEP 9: DIMENSION PORTAL FAST-TRAVEL ────────────────────────────────────
local function checkPortalFastTravel(targetPosition)
    if not Config.PortalTeleport then return end
    local _, root = getCharacterParts()
    if not root then return end

    local commF = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
    if not commF then return end

    local currentDist = (targetPosition - root.Position).Magnitude

    if FirstSea then
        local inUnderwater = root.Position.Y < -2000
        local targetUnderwater = targetPosition.Y < -2000
        if targetUnderwater and not inUnderwater then
            pcall(function() commF:InvokeServer("requestEntrance", Vector3.new(61163.85, 11.68, 1819.78)) end)
            task.wait(0.8)
        elseif inUnderwater and not targetUnderwater then
            pcall(function() commF:InvokeServer("requestEntrance", Vector3.new(3864.68, 4.85, -1926.21)) end)
            task.wait(0.8)
        end
    elseif SecondSea then
        local inCursedShip = root.Position.Z > 25000
        local targetCursedShip = targetPosition.Z > 25000
        if targetCursedShip and not inCursedShip then
            pcall(function() commF:InvokeServer("requestEntrance", Vector3.new(923.2, 126.9, 32852.8)) end)
            task.wait(0.8)
        elseif inCursedShip and not targetCursedShip then
            pcall(function() commF:InvokeServer("requestEntrance", Vector3.new(-6508.5, 89.0, -132.8)) end)
            task.wait(0.8)
        end
    elseif ThirdSea then
        if currentDist > 3500 then
            local portals = {
                { name = "Mansion",       pos = Vector3.new(-12463.87, 374.91, -7523.77) },
                { name = "Castle on Sea", pos = Vector3.new(-5060.4,  318.5,  -3193.2) },
                { name = "Hydra Island",  pos = Vector3.new(5650.9,   1017.3, -350.4) },
                { name = "Tiki Outpost",  pos = Vector3.new(-16798.7, 60.0,   292.0) },
                { name = "Great Tree",    pos = Vector3.new(2284.91,  15.15,  -9054.71) }
            }

            local bestPortal = nil
            local bestDist = currentDist
            for _, p in ipairs(portals) do
                local d = (targetPosition - p.pos).Magnitude
                if d + 1800 < bestDist then
                    bestDist = d
                    bestPortal = p
                end
            end

            if bestPortal then
                pcall(function()
                    commF:InvokeServer("requestEntrance", bestPortal.pos)
                end)
                task.wait(0.8)
            end
        end
    end
end

-- ─── STEP 10: LEAVE PORTAL ULTI / DIMENSIONAL SHIFT ESCAPE ───────────────────
local function checkLeavePortalUlti()
    if not Config.LeavePortalUlti then return end
    local _, root = getCharacterParts()
    if not root then return end

    local commF = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
    if not commF then return end

    local inDimension = false

    -- Check 1: Known Dimensional Shift coordinates
    local dimensionCenter = Vector3.new(-2097.34, 4776.24, -15013.5)
    if (root.Position - dimensionCenter).Magnitude < 1500 then
        inDimension = true
    end

    -- Check 2: Attribute checks
    if localplayer:GetAttribute("CurrentLocation") == "Dimensional Shift" then
        inDimension = true
    end

    -- Check 3: Altitude & Map detection in Third Sea
    if ThirdSea and root.Position.Y > 4000 and root.Position.Z < -12000 then
        inDimension = true
    end

    if inDimension then
        print("[ZD Hub] Trapped in Portal Ulti (Dimensional Shift)! Escaping...")
        pcall(function()
            if ThirdSea then
                commF:InvokeServer("requestEntrance", Vector3.new(-5060.4, 318.5, -3193.2)) -- Castle on Sea
            elseif SecondSea then
                commF:InvokeServer("requestEntrance", Vector3.new(-6508.5, 89.0, -132.8))
            else
                commF:InvokeServer("requestEntrance", Vector3.new(3864.68, 4.85, -1926.21))
            end
        end)
        task.wait(0.5)
    end
end

task.spawn(function()
    while task.wait(1.5) do
        if Config.LeavePortalUlti then
            checkLeavePortalUlti()
        end
    end
end)

-- ─── STEP 11: DEVIL FRUIT INVENTORY & STORAGE SYSTEM ─────────────────────────
local IgnoredFruits = setmetatable({}, { __mode = "k" })
local DroppedFruitLocations = {}
local FruitCollectionAttempts = {}
local StoredFruitsCache = {}
local FullFruitStorageCache = {}
local lastCacheUpdate = 0

local SessionStats = {
    FruitsCollected = 0,
    FruitsStored = 0,
    FruitsDropped = 0,
    FruitsIgnored = 0,
    StartTime = os.time()
}

local function refreshStoredFruits()
    local now = os.clock()
    if now - lastCacheUpdate < 4 and next(StoredFruitsCache) ~= nil then
        return StoredFruitsCache
    end

    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local commF = remotes and remotes:FindFirstChild("CommF_")
        if commF then
            local fruits = commF:InvokeServer("getInventoryFruits")
            if type(fruits) == "table" then
                local newStored = {}
                for _, item in pairs(fruits) do
                    local name = item.Name
                    if name then
                        newStored[name] = true
                        newStored[name:lower()] = true
                        local clean = name:gsub(" Fruit", "")
                        newStored[clean] = true
                        newStored[clean:lower()] = true
                        local base = clean:split("-")[1]
                        if base then
                            newStored[base] = true
                            newStored[base:lower()] = true
                        end
                        FullFruitStorageCache[name] = true
                        FullFruitStorageCache[name:lower()] = true
                        FullFruitStorageCache[clean] = true
                        FullFruitStorageCache[clean:lower()] = true
                        if base then
                            FullFruitStorageCache[base:lower()] = true
                        end
                    end
                end
                StoredFruitsCache = newStored
                lastCacheUpdate = now
            end
        end
    end)
    return StoredFruitsCache
end

local function isFruitStoreable(fruitTool)
    if not Config.CheckFruitStoreable then
        return true
    end

    local origName = (fruitTool:IsA("Tool") and (fruitTool:GetAttribute("OriginalName") or fruitTool.Name))
        or (fruitTool:IsA("Model") and (fruitTool:GetAttribute("OriginalName") or fruitTool.Name))
        or tostring(fruitTool)

    local normName = normalizeFruitName(origName)
    local clean = origName:gsub(" Fruit", "")
    local base = clean:split("-")[1] or clean

    -- Check known full storage cache first
    if FullFruitStorageCache[normName] or FullFruitStorageCache[origName] 
        or FullFruitStorageCache[clean:lower()] or (base and FullFruitStorageCache[base:lower()]) then
        return false
    end

    local stored = refreshStoredFruits()
    if stored[normName] or stored[origName] or stored[clean] or stored[clean:lower()] 
        or (base and (stored[base] or stored[base:lower()])) then
        FullFruitStorageCache[normName] = true
        FullFruitStorageCache[origName] = true
        return false
    end

    return true
end

local function storeFruit(fruitTool)
    if not fruitTool or not fruitTool.Parent then return false end
    local commF = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
    if not commF then return false end

    local origName = fruitTool:GetAttribute("OriginalName") or fruitTool.Name
    local normName = normalizeFruitName(origName)
    local clean = origName:gsub(" Fruit", "")
    local success = false

    pcall(function()
        local res = commF:InvokeServer("StoreFruit", origName, fruitTool)
        if res == true or not fruitTool.Parent or fruitTool:IsDescendantOf(game) == false then
            success = true
        else
            -- Try normalized format as fallback
            res = commF:InvokeServer("StoreFruit", normName, fruitTool)
            if res == true or not fruitTool.Parent or fruitTool:IsDescendantOf(game) == false then
                success = true
            end
        end
    end)

    task.wait(0.3)
    if not fruitTool.Parent or fruitTool:IsDescendantOf(game) == false then
        success = true
    end

    if success then
        SessionStats.FruitsStored = SessionStats.FruitsStored + 1
        FullFruitStorageCache[normName] = true
        FullFruitStorageCache[origName] = true
        FullFruitStorageCache[clean:lower()] = true
    else
        -- If store failed (e.g. storage full), cache it so we don't try storing or collecting this fruit type again
        FullFruitStorageCache[normName] = true
        FullFruitStorageCache[origName] = true
        FullFruitStorageCache[clean:lower()] = true
        local base = clean:split("-")[1]
        if base then
            FullFruitStorageCache[base:lower()] = true
        end
        print(string.format("[ZD Hub] Fruit capacity full for %s. Cached to prevent future retries.", origName))
    end

    return success
end

local function isFruitIgnored(item)
    if not item then return true end
    if IgnoredFruits[item] then return true end
    if item:GetAttribute("ZD_IgnoredFruit") or item:GetAttribute("ZD_DroppedFruit") then return true end

    local handle = item:FindFirstChild("Handle")
    if handle then
        local hPos = handle.Position
        for _, loc in ipairs(DroppedFruitLocations) do
            if (hPos - loc.Position).Magnitude <= 35 then
                IgnoredFruits[item] = true
                return true
            end
        end
    end
    return false
end

local function dropFruit(fruitTool)
    if not fruitTool or not fruitTool.Parent then return false end
    local eatRemote = fruitTool:FindFirstChild("EatRemote")
    if not eatRemote then return false end

    local char, root, hum = getCharacterParts()
    if hum and char then
        local origName = fruitTool:GetAttribute("OriginalName") or fruitTool.Name
        local dropPos = root and root.Position

        -- 1. Blacklist tool instance immediately
        IgnoredFruits[fruitTool] = true
        pcall(function()
            fruitTool:SetAttribute("ZD_IgnoredFruit", true)
            fruitTool:SetAttribute("ZD_DroppedFruit", true)
        end)

        hum:EquipTool(fruitTool)
        task.wait(0.2)
        pcall(function()
            local pGui = localplayer:FindFirstChild("PlayerGui")
            if pGui and pGui:FindFirstChild("Main") and pGui.Main:FindFirstChild("Dialogue") then
                pGui.Main.Dialogue.Visible = false
            end
        end)

        pcall(function()
            eatRemote:InvokeServer("Drop")
        end)

        SessionStats.FruitsDropped = SessionStats.FruitsDropped + 1

        -- 2. Move player slightly upwards to prevent immediate physical re-touching & picking up
        if root then
            pcall(function()
                root.CFrame = root.CFrame * CFrame.new(0, 20, 0)
            end)
        end

        task.wait(0.3)

        -- 3. Register drop location and blacklist newly created fruit instances at drop location
        if dropPos then
            table.insert(DroppedFruitLocations, {
                Position = dropPos,
                Name = origName,
                Time = os.clock()
            })

            pcall(function()
                for _, item in ipairs(workspace:GetChildren()) do
                    if (item:IsA("Tool") or item:IsA("Model")) and item:FindFirstChild("Handle") then
                        if (item.Handle.Position - dropPos).Magnitude <= 35 then
                            IgnoredFruits[item] = true
                            pcall(function()
                                item:SetAttribute("ZD_IgnoredFruit", true)
                                item:SetAttribute("ZD_DroppedFruit", true)
                                item.Handle.CanTouch = false
                            end)
                        end
                    end
                end
            end)
        end

        task.wait(0.2)
        return true
    end
    return false
end

local function processFruit(fruitTool, source)
    if not fruitTool or not fruitTool.Parent then return end

    local origName = fruitTool:GetAttribute("OriginalName") or fruitTool.Name
    local price, rarity, color = getFruitInfo(origName)
    print(string.format("[ZD Hub] Processing Fruit: %s | Price: $%d | Rarity: %s", origName, price, rarity))

    -- Send Discord Webhook notification
    if Config.SendWebhookNewItem then
        sendDiscordWebhook(origName, price, rarity, color, source)
    end

    local storedSuccess = false

    -- Attempt Auto-Store
    if Config.AutoStoreFruit then
        local storeable = isFruitStoreable(fruitTool)
        if storeable then
            storedSuccess = storeFruit(fruitTool)
            if storedSuccess then
                print("[ZD Hub] Successfully stored fruit:", origName)
            end
        else
            print("[ZD Hub] Fruit storage full for:", origName)
        end
    end

    -- Auto-Drop Low Beli if still in inventory and price < LowBeliValue
    if Config.AutoDropFruitLowBeli and (not storedSuccess) and (price < (Config.LowBeliValue or 1000000)) then
        print(string.format("[ZD Hub] Dropping low beli fruit: %s ($%d < $%d)", origName, price, Config.LowBeliValue))
        dropFruit(fruitTool)
    end
end

-- ─── STEP 12: AUTO RANDOM FRUIT (BLOX FRUIT GACHA / COUSIN / ZIOLES) ─────────
local function closeGachaUI()
    local closed = false

    -- Method 1: Spinner Controller Close (dismisses reveal animation)
    pcall(function()
        local rep = game:GetService("ReplicatedStorage")
        local Spinner = rep:FindFirstChild("Controllers") and rep.Controllers:FindFirstChild("UI") and rep.Controllers.UI:FindFirstChild("Spinner")
        if Spinner then
            local spModule = require(Spinner)
            if spModule and spModule.Close then
                spModule:Close()
                closed = true
            end
        end
    end)

    -- Method 2: Click the red CloseButton or disable SpinnerWindow in PlayerGui
    pcall(function()
        local pGui = localplayer:FindFirstChild("PlayerGui")
        if pGui then
            local sw = pGui:FindFirstChild("SpinnerWindow")
            if sw and sw.Enabled then
                local nav = sw:FindFirstChild("AboveSpinner") and sw.AboveSpinner:FindFirstChild("Navigation")
                local btn = nav and nav:FindFirstChild("CloseButton")
                if btn and btn:IsA("TextButton") and firesignal then
                    pcall(function() firesignal(btn.Activated) end)
                    pcall(function() firesignal(btn.MouseButton1Click) end)
                end
                sw.Enabled = false
                closed = true
            end

            -- Also disable any GachaWindow / ZiolesGacha_Window
            for _, gui in ipairs(pGui:GetChildren()) do
                if gui:IsA("ScreenGui") and (string.find(gui.Name, "Gacha_Window") or string.find(gui.Name, "GachaWindow")) then
                    gui.Enabled = false
                    closed = true
                end
            end
        end
    end)

    -- Method 3: GachaWindow Controller Close
    pcall(function()
        local rep = game:GetService("ReplicatedStorage")
        local GachaWindow = rep:FindFirstChild("Controllers") and rep.Controllers:FindFirstChild("UI") and rep.Controllers.UI:FindFirstChild("GachaWindow")
        if GachaWindow then
            local gwModule = require(GachaWindow)
            if gwModule and gwModule.Close then
                gwModule:Close(true)
                closed = true
            end
        end
    end)

    -- Method 4: DialogueController Close (Zioles NPC conversation)
    pcall(function()
        local rep = game:GetService("ReplicatedStorage")
        local dc = rep:FindFirstChild("DialogueController")
        if dc then
            local dcModule = require(dc)
            if dcModule and dcModule.close then
                dcModule.close()
                closed = true
            end
        end
    end)

    return closed
end

-- Global Escape key listener to close/escape Gacha UI instantly
pcall(function()
    UserInputService.InputBegan:Connect(function(input, gpe)
        if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
            closeGachaUI()
        end
    end)
end)

local function rollRandomFruit()
    if not Config.RandomFruit then return end

    local rolled = false
    local rollResult = nil

    -- Method A: Modern Blox Fruits GachaClient (Update 20+)
    pcall(function()
        local rep = game:GetService("ReplicatedStorage")
        local GachaClient = rep:FindFirstChild("Controllers") and rep.Controllers:FindFirstChild("GachaClient")
        if GachaClient then
            local gcModule = require(GachaClient)
            if gcModule and gcModule.PurchaseGachaAsync then
                -- Pre-check requirements and cooldown if CheckGachaAsync exists
                if gcModule.CheckGachaAsync then
                    local checkRes = gcModule.CheckGachaAsync("ZiolesGacha", "Blox Fruit Gacha")
                    if checkRes and type(checkRes) == "table" then
                        if checkRes.Cooldown and checkRes.Cooldown.RequirementMet == false then
                            print("[ZD Hub] Blox Fruit Gacha cooldown not ready yet.")
                            return
                        end
                        if checkRes.Price and checkRes.Price.RequirementMet == false then
                            print(string.format("[ZD Hub] Blox Fruit Gacha: not enough money ($%s required, $%s current).",
                                tostring(checkRes.Price.Value), tostring(checkRes.Price.Current)))
                            return
                        end
                    end
                end

                local success, res = gcModule.PurchaseGachaAsync("ZiolesGacha")
                if success or res then
                    rolled = true
                    rollResult = res
                    print("[ZD Hub] Blox Fruit Gacha Purchase Success:", tostring(res))
                end
            end
        end
    end)

    -- Method B: Net RemoteFunction direct invocation fallback
    if not rolled then
        pcall(function()
            local rep = game:GetService("ReplicatedStorage")
            local Net = rep:FindFirstChild("Modules") and rep.Modules:FindFirstChild("Net")
            if Net then
                local netModule = require(Net)
                local rf = netModule:RemoteFunction("GachaNetworkRF")
                if rf then
                    local res = rf:InvokeServer({
                        Context = "Purchase",
                        BoxName = "ZiolesGacha"
                    })
                    if res then
                        rolled = true
                        rollResult = res
                        print("[ZD Hub] Blox Fruit Gacha (Net RF) Success:", tostring(res))
                    end
                end
            end
        end)
    end

    -- Method C: Legacy CommF_ Cousin Buy fallback
    if not rolled then
        pcall(function()
            local commF = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
            if commF then
                local res = commF:InvokeServer("Cousin", "Buy")
                if res then
                    rolled = true
                    rollResult = res
                    print("[ZD Hub] Blox Fruit Gacha (Legacy Cousin) Success:", tostring(res))
                end
            end
        end)
    end

    -- Process received fruit & auto escape/close the reveal UI
    if rolled then
        task.wait(0.6)

        -- Auto Escape / Close Gacha UI if open
        if Config.AutoCloseGachaUI ~= false then
            task.spawn(function()
                for _ = 1, 5 do
                    closeGachaUI()
                    task.wait(0.3)
                end
            end)
        end

        -- Check backpack & character for the newly rolled fruit
        local checkContainers = { localplayer:FindFirstChild("Backpack"), localplayer.Character }
        for _, container in ipairs(checkContainers) do
            if container then
                for _, item in ipairs(container:GetChildren()) do
                    if item:IsA("Tool") and (item:FindFirstChild("EatRemote") or item:GetAttribute("OriginalName")) then
                        processFruit(item, "Blox Fruit Gacha (Cousin / Zioles)")
                    end
                end
            end
        end
    else
        -- If already on screen, dismiss any lingering UI
        if Config.AutoCloseGachaUI ~= false then
            closeGachaUI()
        end
    end
end

-- ─── STEP 13: WORLD FRUIT DETECTOR & COLLECTOR ───────────────────────────────
local function getSpawnedFruits()
    local fruitList = {}
    for _, item in ipairs(workspace:GetChildren()) do
        if item:IsA("Tool") or (item:IsA("Model") and item:FindFirstChild("Handle")) then
            local isFruit = string.find(item.Name, "Fruit") or item:FindFirstChild("EatRemote") or item:GetAttribute("OriginalName")
            if isFruit and item:FindFirstChild("Handle") then
                -- 1. Check if explicitly ignored or near drop spot
                if Config.IgnoreDroppedFruit and isFruitIgnored(item) then
                    continue
                end

                -- 2. Pre-check: If fruit is low-beli AND storage is known to be full, SKIP completely!
                if Config.IgnoreDroppedFruit and Config.AutoDropFruitLowBeli then
                    local origName = item:GetAttribute("OriginalName") or item.Name
                    local price = getFruitInfo(origName)
                    if price < (Config.LowBeliValue or 1000000) then
                        if not isFruitStoreable(item) then
                            IgnoredFruits[item] = true
                            SessionStats.FruitsIgnored = SessionStats.FruitsIgnored + 1
                            continue
                        end
                    end
                end

                -- 3. Verify not held by another player or our player
                local isHeld = false
                for _, player in ipairs(Players:GetPlayers()) do
                    if player.Character and item:IsDescendantOf(player.Character) then
                        isHeld = true
                        break
                    end
                end
                if not isHeld then
                    table.insert(fruitList, item)
                end
            end
        end
    end
    return fruitList
end

local function collectFruit(fruitInstance)
    if not fruitInstance or not fruitInstance.Parent or not fruitInstance:FindFirstChild("Handle") then
        return false
    end

    -- Prevent infinite retries on buggy/uncollectable fruit
    FruitCollectionAttempts[fruitInstance] = (FruitCollectionAttempts[fruitInstance] or 0) + 1
    if FruitCollectionAttempts[fruitInstance] > 3 then
        print("[ZD Hub] Fruit exceeded max collection attempts. Blacklisting:", fruitInstance.Name)
        IgnoredFruits[fruitInstance] = true
        return false
    end

    local handle = fruitInstance.Handle
    local targetPos = handle.Position

    print("[ZD Hub] Target Fruit Found:", fruitInstance.Name, "at", tostring(targetPos))

    local _, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then
        return false
    end

    local currentDist = (root.Position - handle.Position).Magnitude

    -- ─── STEP A: DIRECT SMOOTH FLIGHT APPROACH TO FRUIT HANDLE ───
    -- Fly smoothly all the way directly to the fruit handle (target proximity 2 studs).
    -- NEVER teleport from 50 studs away — that tripped the server anti-cheat, causing severe rollback & glitchy snaps!
    if currentDist > 2.5 then
        print(string.format("[ZD Hub] Flying smoothly to fruit (distance: %d studs)...", math.floor(currentDist)))

        -- Portal fast-travel optimization for long inter-island moves
        if Config.PortalTeleport and (not Config.SmartTween or not SmartTween or type(SmartTween.To) ~= "function") then
            checkPortalFastTravel(targetPos)
        end

        -- Fly directly to the fruit with a close stop distance of 2 studs
        local targetCF = handle.CFrame * CFrame.new(0, 1.2, 0)
        flyTo(targetCF, Config.FlightSpeed, 2)
        task.wait(0.1)
    end

    -- ─── STEP B: CLOSE-RANGE TOUCH AND PICKUP (ZERO ROLLBACK) ───
    _, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 or not handle or not handle.Parent then
        return false
    end

    currentDist = (root.Position - handle.Position).Magnitude

    -- If slightly above 2.5 studs (e.g. 3-15 studs), smoothly glide the last few studs without snapping
    if currentDist > 2.5 and currentDist <= 25 then
        local glideDuration = math.clamp(currentDist / 80, 0.08, 0.35)
        local targetCF = handle.CFrame * CFrame.new(0, 1.0, 0)
        local glideTween = TweenService:Create(root, TweenInfo.new(glideDuration, Enum.EasingStyle.Linear), { CFrame = targetCF })
        glideTween:Play()
        task.wait(glideDuration + 0.04)
        pcall(function() glideTween:Cancel() end)
    end

    _, root, hum = getCharacterParts()
    if root and handle and handle.Parent then
        currentDist = (root.Position - handle.Position).Magnitude
        if currentDist <= 6 then
            -- Micro-alignment directly touching the handle (under 2 studs is clean and never trips anti-cheat)
            root.CFrame = handle.CFrame * CFrame.new(0, 0.5, 0)
            root.AssemblyLinearVelocity = Vector3.zero

            -- Fire touch interest to guarantee instant pickup
            if firetouchinterest then
                pcall(function()
                    firetouchinterest(root, handle, 0)
                    task.wait(0.04)
                    firetouchinterest(root, handle, 1)
                end)
            end
        else
            warn(string.format("[ZD Hub] Fruit approach fell short (dist: %.1f studs). Retrying smoothly...", currentDist))
            return false
        end
    else
        return false
    end

    task.wait(0.4)

    -- Check if fruit is now in Backpack or Character
    local fruitTool = nil
    local bp = localplayer:FindFirstChild("Backpack")
    local char = localplayer.Character

    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and (t == fruitInstance or t.Name == fruitInstance.Name or t:FindFirstChild("EatRemote")) then
                fruitTool = t
                break
            end
        end
    end
    if not fruitTool and char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") and (t == fruitInstance or t.Name == fruitInstance.Name or t:FindFirstChild("EatRemote")) then
                fruitTool = t
                break
            end
        end
    end

    if fruitTool then
        print("[ZD Hub] Successfully collected fruit:", fruitTool.Name)
        SessionStats.FruitsCollected = SessionStats.FruitsCollected + 1
        processFruit(fruitTool, "World Spawn")
        return true
    end

    return false
end

-- ─── STEP 14: PRODUCTION-GRADE SERVER HOPPING ENGINE (ADVANCED CANDIDATE POOLING) ───
local setHUDStatus -- Forward declaration

local ServerHop = {
    MinPlayers = 4,
    MaxPlayers = 8,
    VisitedFile = "ZD_Hub/VisitedServers.json",
    Config = {
        VisitedFile = "ZD_Hub/VisitedServers.json",
        VisitedTTL  = 7200,      -- 2 hours visited memory
        MaxRetries  = 5,         -- Maximum retry attempts
        WatchdogTimeout = 14,    -- Reset isHopping after 14s
        DefaultMaxPlayers = 8,
        DefaultMinPlayers = 4
    }
}

local isHopping = false
local currentHopRetries = 0
local hopWatchdogThread = nil
local lastTeleportFailTime = 0
local lastTargetJobId = nil
local candidatePool = {}
local lastCandidateFetchTick = 0
local last429Tick = 0
local serverTeleportInvoked = false

local function notifyHopStatus(text)
    pcall(function()
        if type(setHUDStatus) == "function" then
            setHUDStatus(text, nil)
        elseif type(getgenv().ZD_UpdateHUD) == "function" then
            getgenv().ZD_UpdateHUD(text, nil)
        end
    end)
end

local function dismissTeleportScreen()
    pcall(function()
        game:GetService("GuiService"):ClearError()
    end)
    pcall(function()
        local pg = localplayer and localplayer:FindFirstChild("PlayerGui")
        if pg then
            for _, name in ipairs({ "TeleportBlackscreen", "TeleportOverlay", "BlackScreen", "TeleportGui" }) do
                local scr = pg:FindFirstChild(name)
                if scr then scr:Destroy() end
            end
        end
    end)
    pcall(function()
        local core = game:GetService("CoreGui")
        local prompt = core:FindFirstChild("RobloxPromptGui")
        if prompt then
            local promptOverlay = prompt:FindFirstChild("promptOverlay")
            if promptOverlay then
                for _, child in ipairs(promptOverlay:GetChildren()) do
                    if child.Name == "ErrorPrompt" then
                        child.Visible = false
                        for _, desc in ipairs(child:GetDescendants()) do
                            if desc:IsA("GuiButton") then
                                pcall(function()
                                    if firesignal then firesignal(desc.MouseButton1Click) end
                                    if desc.Activate then desc:Activate() end
                                end)
                            end
                        end
                    end
                end
            end
        end
    end)
    pcall(function()
        if localplayer then localplayer:SetAttribute("TeleportInProgress", false) end
    end)
    pcall(function()
        local PlayerScripts = localplayer and localplayer:FindFirstChild("PlayerScripts")
        local PlayerModule = PlayerScripts and PlayerScripts:FindFirstChild("PlayerModule")
        if PlayerModule then
            local controls = require(PlayerModule):GetControls()
            if controls and controls.Enable then controls:Enable() end
        end
    end)
end

dismissTeleportScreen()

-- Auto-dismiss error prompt if it ever appears
pcall(function()
    local CoreGui = game:GetService("CoreGui")
    local promptOverlay = CoreGui:WaitForChild("RobloxPromptGui", 5) and CoreGui.RobloxPromptGui:WaitForChild("promptOverlay", 5)
    if promptOverlay then
        promptOverlay.ChildAdded:Connect(function(child)
            if child.Name == "ErrorPrompt" then
                task.wait(0.05)
                dismissTeleportScreen()
            end
        end)
    end
end)

task.spawn(function()
    while true do
        task.wait(1)
        pcall(function()
            local core = game:GetService("CoreGui")
            local prompt = core:FindFirstChild("RobloxPromptGui")
            local promptOverlay = prompt and prompt:FindFirstChild("promptOverlay")
            local errPrompt = promptOverlay and promptOverlay:FindFirstChild("ErrorPrompt")
            if errPrompt and errPrompt.Visible then
                dismissTeleportScreen()
            end
        end)
    end
end)

local function universalHttpRequest(url)
    local fn = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
    if fn then
        local ok, res = pcall(function()
            return fn({
                Url = url,
                Method = "GET",
                Headers = { ["User-Agent"] = "Roblox/WinInet" }
            })
        end)
        if ok and res then
            local body = res.Body or res.body
            local status = res.StatusCode or res.status_code
            if status == 429 then
                return nil, 429
            end
            if body and body ~= "" then
                return body, status or 200
            end
        end
    end

    local okGet, resGet = pcall(function()
        return game:HttpGet(url)
    end)
    if okGet and resGet and resGet ~= "" then
        return resGet, 200
    end

    return nil, 0
end

local function cleanCharacterForces()
    pcall(function()
        local char = localplayer and localplayer.Character
        if char then
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then
                for _, obj in ipairs(root:GetChildren()) do
                    if obj:IsA("BodyVelocity") or obj:IsA("BodyGyro") or obj:IsA("BodyPosition") or obj:IsA("AlignPosition") or obj:IsA("LinearVelocity") then
                        obj:Destroy()
                    end
                end
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end
    end)
end

function ServerHop.LoadVisited()
    local visited = {}
    pcall(function()
        if isfile and isfile(ServerHop.Config.VisitedFile) then
            local content = readfile(ServerHop.Config.VisitedFile)
            local data = HttpService:JSONDecode(content)
            local now = os.time()
            for jobId, timestamp in pairs(data) do
                if now - timestamp < ServerHop.Config.VisitedTTL then
                    visited[jobId] = timestamp
                end
            end
        end
    end)
    return visited
end

function ServerHop.MarkVisited(jobId)
    if not jobId or jobId == "" then return end
    pcall(function()
        local visited = ServerHop.LoadVisited()
        visited[tostring(jobId)] = os.time()
        if writefile then
            if makefolder and not isfolder("ZD_Hub") then makefolder("ZD_Hub") end
            writefile(ServerHop.Config.VisitedFile, HttpService:JSONEncode(visited))
        end
    end)
end

function ServerHop.ClearVisited()
    pcall(function()
        if writefile then
            if makefolder and not isfolder("ZD_Hub") then makefolder("ZD_Hub") end
            writefile(ServerHop.Config.VisitedFile, HttpService:JSONEncode({}))
        end
    end)
end

local function registerQueueTeleport()
    pcall(function()
        local q = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
        if q then
            q([[
                pcall(function()
                    if isfile and isfile("Blox Fruits/Fruit Finder Script.lua") then
                        loadfile("Blox Fruits/Fruit Finder Script.lua")()
                    elseif isfile and isfile("Fruit Finder Script.lua") then
                        loadfile("Fruit Finder Script.lua")()
                    elseif isfile and isfile("ZD_Hub/Fruit Finder Script.lua") then
                        loadfile("ZD_Hub/Fruit Finder Script.lua")()
                    end
                end)
            ]])
        end
    end)
end

-- Backward-compatible wrappers
function ServerHop.ManualHop(options)
    return ServerHop.Hop(options)
end

function ServerHop.ApiHop(targetPlaceId, options)
    return ServerHop.Hop(options)
end

function ServerHop.Hop(arg1, arg2)
    local customOptions = (arg1 == ServerHop) and arg2 or arg1
    if type(customOptions) ~= "table" then
        customOptions = {}
    end
    if isHopping then
        return false, "Hop already in progress"
    end
    isHopping = true
    serverTeleportInvoked = false

    if stopFlight then pcall(stopFlight) end
    cleanCharacterForces()
    registerQueueTeleport()

    local targetPlaceId = game.PlaceId
    local currentJobId = game.JobId
    local visited = ServerHop.LoadVisited()
    visited[currentJobId] = os.time()

    local minP = math.max(tonumber(customOptions.MinPlayers) or tonumber(ServerHop.MinPlayers) or 4, 4)
    local maxP = math.min(math.max(tonumber(customOptions.MaxPlayers) or tonumber(ServerHop.MaxPlayers) or 8, minP), 11)

    -- Watchdog timeout to prevent frozen state
    if hopWatchdogThread then
        pcall(function() task.cancel(hopWatchdogThread) end)
    end
    hopWatchdogThread = task.delay(ServerHop.Config.WatchdogTimeout or 14, function()
        if isHopping then
            isHopping = false
            dismissTeleportScreen()
            print("[ZD Hub] Hopping watchdog timed out. Resetting state.")
            notifyHopStatus("Hopping timed out. Resuming...")
        end
    end)

    -- STEP 1: Prune existing cached candidate pool
    local validCached = {}
    for _, c in ipairs(candidatePool) do
        if c.id and c.id ~= currentJobId and not visited[c.id] then
            table.insert(validCached, c)
        end
    end
    candidatePool = validCached

    -- STEP 2: Query Roblox Public Servers API if cache is low or expired
    if #candidatePool < 3 or (os.time() - lastCandidateFetchTick > 120) then
        if os.time() - last429Tick < 12 then
            print("[ZD Hub] In API rate-limit cooldown. Using available local cache...")
        else
            local cursor = ""
            local newCandidates = {}
            for page = 1, 3 do
                local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?limit=100&sortOrder=Asc%s", tostring(targetPlaceId), cursor ~= "" and ("&cursor=" .. cursor) or "")
                local body, status = universalHttpRequest(url)

                if status == 429 then
                    last429Tick = os.time()
                    warn("[ZD Hub] Roblox Games API returned HTTP 429 (Rate Limit). Pausing queries for 12s...")
                    break
                end

                if body and body ~= "" then
                    local dataOk, data = pcall(function() return HttpService:JSONDecode(body) end)
                    if dataOk and data and data.data then
                        for _, s in ipairs(data.data) do
                            -- STRICT RULE: Blox Fruits 1-3 player servers are restricted raid rooms that cause Error 773.
                            -- Require s.playing >= 4 and at least 1 open slot.
                            if s.id and s.id ~= currentJobId and not visited[s.id] and s.playing and s.maxPlayers and s.playing >= 4 and (s.maxPlayers - s.playing >= 1) then
                                local score = 0
                                if s.playing >= minP and s.playing <= maxP then
                                    score = math.abs(s.playing - math.floor((minP + maxP) / 2))
                                else
                                    score = 100 + math.abs(s.playing - 6) -- fallback priority
                                end
                                table.insert(newCandidates, {
                                    id = s.id,
                                    playing = s.playing,
                                    maxPlayers = s.maxPlayers,
                                    score = score,
                                })
                            end
                        end

                        cursor = data.nextPageCursor or ""
                        if not cursor or cursor == "" then break end
                    end
                end
                task.wait(0.15)
            end

            -- STEP 3: If candidate pool is still empty because visited is exhausted, reset visited memory and retry once
            if #newCandidates == 0 and next(visited) ~= nil then
                print("[ZD Hub] Visited server cache full or exhausted. Resetting visited memory...")
                visited = {}
                visited[currentJobId] = os.time()
                ServerHop.ClearVisited()
                local cursor2 = ""
                for page = 1, 3 do
                    local url = string.format("https://games.roblox.com/v1/games/%s/servers/Public?limit=100&sortOrder=Asc%s", tostring(targetPlaceId), cursor2 ~= "" and ("&cursor=" .. cursor2) or "")
                    local body, status = universalHttpRequest(url)
                    if status == 429 then break end
                    if body and body ~= "" then
                        local dataOk, data = pcall(function() return HttpService:JSONDecode(body) end)
                        if dataOk and data and data.data then
                            for _, s in ipairs(data.data) do
                                if s.id and s.id ~= currentJobId and s.playing and s.maxPlayers and s.playing >= 4 and (s.maxPlayers - s.playing >= 1) then
                                    table.insert(newCandidates, {
                                        id = s.id,
                                        playing = s.playing,
                                        maxPlayers = s.maxPlayers,
                                        score = (s.playing >= minP and s.playing <= maxP) and math.abs(s.playing - math.floor((minP + maxP) / 2)) or (100 + math.abs(s.playing - 6)),
                                    })
                                end
                            end
                            cursor2 = data.nextPageCursor or ""
                            if not cursor2 or cursor2 == "" then break end
                        end
                    end
                    task.wait(0.15)
                end
            end

            if #newCandidates > 0 then
                table.sort(newCandidates, function(a, b) return a.score < b.score end)
                candidatePool = newCandidates
                lastCandidateFetchTick = os.time()
            end
        end
    end

    -- STEP 4: Select optimal server and dispatch teleport
    if #candidatePool > 0 then
        local chosen = table.remove(candidatePool, 1)
        local chosenJob = chosen.id
        lastTargetJobId = chosenJob

        print(string.format("[ZD Hub] Selected optimal server: %s (%d players in Place %s)", tostring(chosenJob), chosen.playing, tostring(targetPlaceId)))
        notifyHopStatus(string.format("Hopping to %s (%d players)...", chosenJob:sub(1, 8), chosen.playing))
        ServerHop.MarkVisited(chosenJob)

        cleanCharacterForces()

        -- Strategy 1: Use Blox Fruits' official ServerBrowser RemoteFunction (server-authenticated token)
        local sb = ReplicatedStorage:FindFirstChild("__ServerBrowser")
        if sb and sb:IsA("RemoteFunction") then
            local ok = pcall(function()
                sb:InvokeServer("teleport", chosenJob)
            end)
            if ok then
                serverTeleportInvoked = true
            end
        end

        -- Strategy 2: If __ServerBrowser was not available, fall back to direct TeleportToPlaceInstance
        if not serverTeleportInvoked then
            pcall(function()
                TeleportService:TeleportToPlaceInstance(targetPlaceId, chosenJob, localplayer)
            end)
        else
            -- If __ServerBrowser was invoked, wait 5s; only fall back to direct TeleportToPlaceInstance if still in currentJob
            task.delay(5, function()
                if isHopping and game.JobId == currentJobId then
                    print("[ZD Hub] Fallback: Executing direct TeleportToPlaceInstance...")
                    pcall(function()
                        TeleportService:TeleportToPlaceInstance(targetPlaceId, chosenJob, localplayer)
                    end)
                end
            end)
        end
        return true, chosenJob
    else
        warn("[ServerHop] No candidate servers available in Public API. Resetting hop state...")
        isHopping = false
        dismissTeleportScreen()
        notifyHopStatus("No candidate servers available. Retrying...")
        currentHopRetries = currentHopRetries + 1
        local backoff = math.min(currentHopRetries * 2, 6)
        task.delay(backoff, function()
            if not isHopping then
                ServerHop.Hop(customOptions)
            end
        end)
        return false, "No candidate servers"
    end
end

-- ─── 4-CASE TELEPORT FAILURE HANDLER ─────────────────────────────────────────
function ServerHop.HandleTeleportFailed(teleportResult, errorMessage)
    local errStr = tostring(errorMessage or "Unknown error")
    local resStr = tostring(teleportResult or "Unknown")

    if teleportResult == Enum.TeleportResult.IsTeleporting then
        return
    end

    -- If unauthorized occurred while Blox Fruits server remote is handling the teleport, do not abort
    if teleportResult == Enum.TeleportResult.Unauthorized and serverTeleportInvoked then
        return
    end

    warn(string.format("[ServerHop] Teleport failed! Error: %s | Result: %s", errStr, resStr))
    dismissTeleportScreen()
    isHopping = false

    local now = os.clock()
    if now - lastTeleportFailTime < 2.5 then
        return
    end
    lastTeleportFailTime = now

    if lastTargetJobId and lastTargetJobId ~= "" then
        ServerHop.MarkVisited(lastTargetJobId)
        print(string.format("[ZD Hub] Blacklisted failed server instance: %s", tostring(lastTargetJobId):sub(1, 8)))
    end

    currentHopRetries = currentHopRetries + 1
    local backoff = math.min(currentHopRetries * 2, 6)
    notifyHopStatus(string.format("Teleport failed. Retrying in %ds...", backoff))
    task.delay(backoff, function()
        if not isHopping then
            ServerHop.Hop()
        end
    end)
end

local function hopServer()
    return ServerHop.Hop()
end

-- Metatable __call so ServerHop() can be called directly as a function
setmetatable(ServerHop, {
    __call = function(self, ...)
        return ServerHop.Hop(...)
    end
})

TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
    if player == localplayer or not player then
        ServerHop.HandleTeleportFailed(teleportResult, errorMessage)
    end
end)

-- Global exports
getgenv().ServerHop = ServerHop
getgenv().ZD_FruitFinder_HopServer = hopServer
getgenv().ZD_HopServer = hopServer

-- ─── STEP 15: SLEEK HUD STATUS OVERLAY ───────────────────────────────────────
local function createStatusHUD()
    pcall(function()
        local gethui = gethui or get_hidden_gui
        local parentGui = (gethui and gethui()) or CoreGui or localplayer:WaitForChild("PlayerGui")
        
        local existing = parentGui:FindFirstChild("ZD_FruitFinder_HUD")
        if existing then existing:Destroy() end

        local hud = Instance.new("ScreenGui")
        hud.Name = "ZD_FruitFinder_HUD"
        hud.ResetOnSpawn = false
        hud.Parent = parentGui

        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 260, 0, 110)
        frame.Position = UDim2.new(0, 20, 0, 20)
        frame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
        frame.BorderSizePixel = 0
        frame.Active = true
        frame.Draggable = true
        frame.Parent = hud

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 10)
        corner.Parent = frame

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(0, 170, 255)
        stroke.Thickness = 1.5
        stroke.Parent = frame

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 28)
        title.BackgroundTransparency = 1
        title.Text = "  ZD HUB · FRUIT FINDER"
        title.TextColor3 = Color3.fromRGB(0, 170, 255)
        title.Font = Enum.Font.GothamBold
        title.TextSize = 13
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.Parent = frame

        local statusLabel = Instance.new("TextLabel")
        statusLabel.Name = "Status"
        statusLabel.Size = UDim2.new(1, -20, 0, 22)
        statusLabel.Position = UDim2.new(0, 10, 0, 32)
        statusLabel.BackgroundTransparency = 1
        statusLabel.Text = "Status: Initializing..."
        statusLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
        statusLabel.Font = Enum.Font.Gotham
        statusLabel.TextSize = 11
        statusLabel.TextXAlignment = Enum.TextXAlignment.Left
        statusLabel.Parent = frame

        local infoLabel = Instance.new("TextLabel")
        infoLabel.Name = "Info"
        infoLabel.Size = UDim2.new(1, -20, 0, 22)
        infoLabel.Position = UDim2.new(0, 10, 0, 56)
        infoLabel.BackgroundTransparency = 1
        infoLabel.Text = string.format("Sea: %s | Team: %s", CurrentSeaName, Config.SelectTeam)
        infoLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
        infoLabel.Font = Enum.Font.Gotham
        infoLabel.TextSize = 10
        infoLabel.TextXAlignment = Enum.TextXAlignment.Left
        infoLabel.Parent = frame

        local statsLabel = Instance.new("TextLabel")
        statsLabel.Name = "Stats"
        statsLabel.Size = UDim2.new(1, -20, 0, 22)
        statsLabel.Position = UDim2.new(0, 10, 0, 80)
        statsLabel.BackgroundTransparency = 1
        statsLabel.Text = "Fruits in Server: 0"
        statsLabel.TextColor3 = Color3.fromRGB(0, 255, 140)
        statsLabel.Font = Enum.Font.GothamMedium
        statsLabel.TextSize = 10
        statsLabel.TextXAlignment = Enum.TextXAlignment.Left
        statsLabel.Parent = frame

        hud.Enabled = Config.ShowMinimalHUD ~= false

        getgenv().ZD_UpdateHUD = function(statusText, statsText)
            pcall(function()
                if statusText then statusLabel.Text = "Status: " .. statusText end
                if statsText then statsLabel.Text = statsText end
            end)
        end
    end)
end

createStatusHUD()

local currentStatusMessage = "Initializing..."
local currentFruitsMessage = "Fruits in Server: 0"
local vindStatusParagraph = nil
local vindAnalyticsParagraph = nil

setHUDStatus = function(text, stats)
    if text then currentStatusMessage = text end
    if stats then currentFruitsMessage = stats end

    if getgenv().ZD_UpdateHUD then
        getgenv().ZD_UpdateHUD(text, stats)
    end
end

-- ─── STEP 16: MAIN AUTONOMOUS WORKFLOW LOOP ──────────────────────────────────
task.spawn(function()
    print("[ZD Hub] Autonomous Fruit Finder workflow started.")
    setHUDStatus("Waiting for character...", nil)

    repeat task.wait(0.5) until localplayer.Character and localplayer.Character:FindFirstChild("HumanoidRootPart")
    task.wait(1.5)

    -- Step A: Blox Fruit Gacha Roll on spawn
    if Config.RandomFruit then
        setHUDStatus("Checking Blox Fruit Gacha...", nil)
        rollRandomFruit()
        task.wait(1)
    end

    -- Step B: Collect any existing fruits in Backpack / Character to store or drop
    pcall(function()
        local bp = localplayer:FindFirstChild("Backpack")
        if bp then
            for _, item in ipairs(bp:GetChildren()) do
                if item:IsA("Tool") and item:FindFirstChild("EatRemote") then
                    processFruit(item, "Pre-existing Inventory")
                end
            end
        end
    end)

    getgenv().ZD_FRUITFINDER_STOP = function()
        getgenv().ZD_FRUITFINDER_RUNNING = false
        stopFlight()
    end

    -- Step C: Scan Workspace for Spawned Fruits
    while task.wait(1) do
        if not getgenv().ZD_FRUITFINDER_RUNNING then break end

        -- Dismiss any lingering Gacha / Spinner reveal UI if open
        if Config.AutoCloseGachaUI ~= false then
            pcall(function()
                local pGui = localplayer:FindFirstChild("PlayerGui")
                if pGui and pGui:FindFirstChild("SpinnerWindow") and pGui.SpinnerWindow.Enabled then
                    closeGachaUI()
                end
            end)
        end

        setHUDStatus("Scanning for fruits...", nil)
        local fruits = getSpawnedFruits()
        setHUDStatus("Fruits found: " .. #fruits, "Fruits in Server: " .. #fruits)

        if #fruits > 0 and Config.CollectFruit then
            for idx, fruit in ipairs(fruits) do
                if not getgenv().ZD_FRUITFINDER_RUNNING then break end
                if fruit and fruit.Parent and fruit:FindFirstChild("Handle") then
                    if not isFruitIgnored(fruit) then
                        setHUDStatus(string.format("Collecting (%d/%d): %s", idx, #fruits, fruit.Name), nil)
                        pcall(function() collectFruit(fruit) end)
                        task.wait(0.5)
                    end
                end
            end
            -- Re-scan after collection round
            fruits = getSpawnedFruits()
        end

        -- If no fruits remain on the server, decide whether to hop
        if #fruits == 0 then
            print("[ZD Hub] No spawned fruits on this server.")
            setHUDStatus("No fruits found.", "Fruits in Server: 0")

            if Config.RandomFruit then
                pcall(rollRandomFruit)
            end

            if Config.FarmWithHop then
                setHUDStatus("Server hopping in 3s...", nil)
                task.wait(3)
                pcall(function() ServerHop.Hop() end)
                task.wait(6)
                -- Keep loop alive! If teleport is queued/retrying, continue scanning!
            else
                task.wait(10)
            end
        end
    end
end)

-- ─── STEP 17: INJECT GRAPHICAL USER INTERFACE (VindUI) ────────────────────────
task.spawn(function()
    pcall(function()
        local VindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Skinny-yz/VVind-UI/refs/heads/main/src.lua"))()
        pcall(function() VindUI:PreloadIcons({ "Lucide", "Material", "Phosphor", "SF" }) end)

        local Window = VindUI:CreateWindow({
            Title = "ZD Hub",
            Subtitle = "Fruit Finder & Gacha v5.0",
            Icon = "117388387570130",
            Size = UDim2.fromOffset(560, 430),
            MinSize = Vector2.new(460, 320),
            Draggable = true,
            Resizable = true,
            UseBlur = true,
            DefaultTab = "Main",
        })

        -- Custom Draggable Toggle Button (like Auto Chest)
        pcall(function()
            local success, coreGui = pcall(function() return game:GetService("CoreGui") end)
            local parentGui = (success and coreGui) and coreGui or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
            local oldToggle = parentGui:FindFirstChild("ZD_FruitFinder_Toggle")
            if oldToggle then oldToggle:Destroy() end
        end)

        local toggleGui = Instance.new("ScreenGui")
        toggleGui.Name = "ZD_FruitFinder_Toggle"
        toggleGui.ResetOnSpawn = false
        toggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

        local success, coreGui = pcall(function() return game:GetService("CoreGui") end)
        toggleGui.Parent = (success and coreGui) and coreGui or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")

        local toggleBtn = Instance.new("ImageButton")
        toggleBtn.Name = "ToggleBtn"
        toggleBtn.Size = UDim2.new(0, 45, 0, 45)
        toggleBtn.Position = UDim2.new(0.95, -55, 0.22, 0)
        toggleBtn.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        toggleBtn.Image = "rbxassetid://117388387570130"
        toggleBtn.Parent = toggleGui

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = toggleBtn

        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(0, 170, 255)
        stroke.Thickness = 1.5
        stroke.Parent = toggleBtn

        local dragging, dragInput, dragStart, startPos
        local startClickPos = Vector3.new()

        toggleBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startClickPos = input.Position
                startPos = toggleBtn.Position

                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)

        toggleBtn.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)

        local function onDragInputChanged(input)
            if input == dragInput and dragging then
                local delta = input.Position - dragStart
                toggleBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end

        UserInputService.InputChanged:Connect(onDragInputChanged)

        toggleBtn.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if (input.Position - startClickPos).Magnitude < 10 then
                    if Window and Window.Toggle then
                        Window:Toggle()
                    end
                end
            end
        end)

        -- Keybind toggle (RightShift / RightControl)
        UserInputService.InputBegan:Connect(function(input, gpe)
            if not gpe and (input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.RightControl) then
                if Window and Window.Toggle then
                    Window:Toggle()
                end
            end
        end)

        -- VindUI Tabs
        local MainTab = Window:AddTab({ Name = "Main", Icon = "Lucide:apple" })
        local MoveTab = Window:AddTab({ Name = "Movement", Icon = "Lucide:plane" })
        local ServerTab = Window:AddTab({ Name = "Server Hop", Icon = "Lucide:server" })
        local SettingsTab = Window:AddTab({ Name = "Settings", Icon = "Lucide:settings" })
        local StatsTab = Window:AddTab({ Name = "Stats & Profile", Icon = "Lucide:bar-chart-2" })

        -- 1. MAIN TAB: Fruit Hunter & Gacha
        local HunterSubTab = MainTab:AddSubTab({ Name = "Fruit Hunter", Icon = "Lucide:scan" })
        HunterSubTab:AddSection("Fruit Collection Controls")

        HunterSubTab:AddToggle({
            Text = "Auto Collect Fruits",
            Description = "Autonomous workspace fruit hunting & flight",
            Default = Config.CollectFruit,
            Callback = function(v)
                Config.CollectFruit = v
                saveSettingsToFile()
            end
        })

        HunterSubTab:AddSlider({
            Text = "Safe Fruit TP Distance",
            Description = "Only teleport to fruit handle when near (<= 50 studs) to prevent rollback/glitch",
            Min = 15,
            Max = 80,
            Default = Config.NearFruitTPDistance or 50,
            Increment = 5,
            Suffix = " studs",
            Callback = function(v)
                Config.NearFruitTPDistance = v
                saveSettingsToFile()
            end
        })

        HunterSubTab:AddToggle({
            Text = "Ignore Dropped / Full Fruits",
            Description = "Never tween to low-beli fruits that were dropped or can't be stored",
            Default = Config.IgnoreDroppedFruit,
            Callback = function(v)
                Config.IgnoreDroppedFruit = v
                saveSettingsToFile()
            end
        })

        HunterSubTab:AddToggle({
            Text = "Auto Drop Low Beli",
            Description = "Drop fruits worth less than threshold if inventory is full",
            Default = Config.AutoDropFruitLowBeli,
            Callback = function(v)
                Config.AutoDropFruitLowBeli = v
                saveSettingsToFile()
            end
        })

        HunterSubTab:AddSlider({
            Text = "Low Beli Cutoff Threshold",
            Description = "Drop fruits below this value when storage is full",
            Min = 50000,
            Max = 5000000,
            Default = Config.LowBeliValue or 1000000,
            Increment = 50000,
            Suffix = " Beli",
            Callback = function(v)
                Config.LowBeliValue = v
                saveSettingsToFile()
            end
        })

        HunterSubTab:AddButton({
            Text = "Clear Dropped Fruits Blacklist",
            Description = "Reset ignored fruits list on this server",
            Icon = "Lucide:refresh-cw",
            Callback = function()
                table.clear(IgnoredFruits)
                table.clear(DroppedFruitLocations)
                table.clear(FruitCollectionAttempts)
                SessionStats.FruitsIgnored = 0
                VindUI:Notify({
                    Title = "ZD Hub",
                    Text = "Dropped fruit blacklist cleared successfully!",
                    Type = "success",
                    Duration = 3
                })
            end
        })

        HunterSubTab:AddSection("Devil Fruit Storage Engine")

        HunterSubTab:AddToggle({
            Text = "Auto Store Fruit",
            Description = "Automatically store collected/rolled fruits into storage",
            Default = Config.AutoStoreFruit,
            Callback = function(v)
                Config.AutoStoreFruit = v
                saveSettingsToFile()
            end
        })

        HunterSubTab:AddToggle({
            Text = "Check Fruit Storeable",
            Description = "Verify available storage capacity before attempting to store",
            Default = Config.CheckFruitStoreable,
            Callback = function(v)
                Config.CheckFruitStoreable = v
                saveSettingsToFile()
            end
        })

        HunterSubTab:AddButton({
            Text = "Force Refresh Stored Fruits Cache",
            Description = "Re-query server inventory to update stored fruit list",
            Icon = "Lucide:database",
            Callback = function()
                lastCacheUpdate = 0
                refreshStoredFruits()
                VindUI:Notify({
                    Title = "Storage Cache",
                    Text = "Devil fruit storage inventory refreshed!",
                    Type = "info",
                    Duration = 3
                })
            end
        })

        local GachaSubTab = MainTab:AddSubTab({ Name = "Gacha (Cousin)", Icon = "Lucide:gift" })
        GachaSubTab:AddSection("Blox Fruit Gacha Automation")

        GachaSubTab:AddToggle({
            Text = "Auto Buy Random Fruit",
            Description = "Auto roll fruit from Blox Fruit Dealer Cousin when available",
            Default = Config.RandomFruit,
            Callback = function(v)
                Config.RandomFruit = v
                saveSettingsToFile()
            end
        })

        GachaSubTab:AddToggle({
            Text = "Auto Close Gacha UI",
            Description = "Automatically dismiss and escape the Gacha spin reveal animation UI",
            Default = Config.AutoCloseGachaUI ~= false,
            Callback = function(v)
                Config.AutoCloseGachaUI = v
                saveSettingsToFile()
            end
        })

        GachaSubTab:AddButton({
            Text = "Roll Blox Fruit Gacha Now",
            Description = "Attempt to roll a fruit from Cousin immediately",
            Icon = "Lucide:sparkles",
            Callback = function()
                task.spawn(function()
                    VindUI:Notify({ Title = "Gacha", Text = "Attempting to buy fruit from Cousin...", Type = "info", Duration = 2 })
                    rollRandomFruit()
                end)
            end
        })

        GachaSubTab:AddButton({
            Text = "Close Gacha UI (Escape)",
            Description = "Instantly close and escape any active Gacha / Spinner reveal GUI",
            Icon = "Lucide:x",
            Callback = function()
                local closed = closeGachaUI()
                VindUI:Notify({
                    Title = "Gacha UI",
                    Text = closed and "Closed Gacha GUI." or "No Gacha GUI currently open.",
                    Type = closed and "success" or "info",
                    Duration = 2
                })
            end
        })

        -- 2. MOVEMENT TAB
        local FlightSubTab = MoveTab:AddSubTab({ Name = "Flight Controls", Icon = "Lucide:wind" })
        FlightSubTab:AddSection("Smart Navigation Engine")

        FlightSubTab:AddToggle({
            Text = "Smart Tween Engine",
            Description = "Universal Smart Tween engine with 3-waypoint altitude corridor flight",
            Default = Config.SmartTween ~= false,
            Callback = function(v)
                Config.SmartTween = v
                saveSettingsToFile()
            end
        })

        FlightSubTab:AddToggle({
            Text = "Use Portal Fruit Method",
            Description = "Auto-detect Portal fruit and use Move C World Warp when faster",
            Default = Config.UsePortalFruit ~= false,
            Callback = function(v)
                Config.UsePortalFruit = v
                saveSettingsToFile()
            end
        })

        FlightSubTab:AddToggle({
            Text = "Wall Slowdown (Anti-Clip)",
            Description = "Throttle flight speed near walls and obstacles to prevent anti-cheat pushbacks",
            Default = Config.WallSlowdown ~= false,
            Callback = function(v)
                Config.WallSlowdown = v
                saveSettingsToFile()
            end
        })

        FlightSubTab:AddSection("Physics & Flight")

        FlightSubTab:AddSlider({
            Text = "Flight Speed",
            Description = "Zero-rollback flight speed across islands",
            Min = 100,
            Max = 350,
            Default = Config.FlightSpeed or 260,
            Increment = 10,
            Suffix = " studs/s",
            Callback = function(v)
                Config.FlightSpeed = v
                saveSettingsToFile()
            end
        })

        FlightSubTab:AddToggle({
            Text = "Dimension Portal Fast-Travel",
            Description = "Take official game portals (Castle, Hydra, Mansion) to speed up travel",
            Default = Config.PortalTeleport,
            Callback = function(v)
                Config.PortalTeleport = v
                saveSettingsToFile()
            end
        })

        FlightSubTab:AddToggle({
            Text = "Leave Portal Ulti (Dimensional Shift)",
            Description = "Instant breakout when trapped in enemy Portal V dimension",
            Default = Config.LeavePortalUlti,
            Callback = function(v)
                Config.LeavePortalUlti = v
                saveSettingsToFile()
            end
        })

        FlightSubTab:AddButton({
            Text = "Emergency Escape Dimensional Shift",
            Description = "Force warp out of Portal V realm immediately",
            Icon = "Lucide:door-open",
            Callback = function()
                checkLeavePortalUlti()
            end
        })

        -- 3. SERVER HOP TAB
        local HopSubTab = ServerTab:AddSubTab({ Name = "Server Hopping", Icon = "Lucide:server" })
        HopSubTab:AddSection("Hopping Configuration")

        HopSubTab:AddToggle({
            Text = "Auto Server Hop When Done",
            Description = "Automatically hop when all fruits on the server are collected",
            Default = Config.FarmWithHop,
            Callback = function(v)
                Config.FarmWithHop = v
                saveSettingsToFile()
            end
        })

        HopSubTab:AddSlider({
            Text = "Min Players",
            Description = "Skip private/empty servers to prevent error 773",
            Min = 1,
            Max = 12,
            Default = ServerHop.MinPlayers or 3,
            Increment = 1,
            Callback = function(v)
                ServerHop.MinPlayers = v
            end
        })

        HopSubTab:AddSlider({
            Text = "Max Players",
            Description = "Avoid full servers to ensure instant connection",
            Min = 1,
            Max = 12,
            Default = ServerHop.MaxPlayers or 8,
            Increment = 1,
            Callback = function(v)
                ServerHop.MaxPlayers = v
            end
        })

        HopSubTab:AddButton({
            Text = "Instant Server Hop",
            Description = "Hop to a fresh low-player server immediately",
            Icon = "Lucide:plane-takeoff",
            Callback = function()
                task.spawn(function()
                    VindUI:Notify({ Title = "Server Hop", Text = "Finding optimal server...", Type = "info", Duration = 3 })
                    ServerHop.Hop()
                end)
            end
        })

        HopSubTab:AddButton({
            Text = "Clear Visited Servers History",
            Description = "Wipe visited servers cache to allow rejoining previous servers",
            Icon = "Lucide:trash-2",
            Callback = function()
                pcall(function()
                    if writefile and isfile and isfile(ServerHop.VisitedFile) then
                        delfile(ServerHop.VisitedFile)
                    end
                end)
                VindUI:Notify({ Title = "Cache Cleared", Text = "Visited servers history wiped.", Type = "success", Duration = 3 })
            end
        })

        -- 4. SETTINGS TAB
        local OptSubTab = SettingsTab:AddSubTab({ Name = "Optimization", Icon = "Lucide:sliders" })
        OptSubTab:AddSection("Game Optimization & Team")

        OptSubTab:AddDropdown({
            Text = "Auto Select Team",
            Description = "Team assigned automatically upon server join",
            Options = { "Marine", "Pirates" },
            Default = Config.SelectTeam or "Marine",
            Callback = function(v)
                Config.SelectTeam = v
                saveSettingsToFile()
                autoSelectTeam()
            end
        })

        OptSubTab:AddToggle({
            Text = "Native FPS Booster",
            Description = "Optimize rendering textures, decals, and particles",
            Default = Config.FPSBoost,
            Callback = function(v)
                Config.FPSBoost = v
                saveSettingsToFile()
                if v then applyFPSBoost() end
            end
        })

        OptSubTab:AddToggle({
            Text = "3D White Screen Mode",
            Description = "Disables 3D viewport rendering for ultra-low CPU/GPU consumption",
            Default = Config.WhiteScreen,
            Callback = function(v)
                Config.WhiteScreen = v
                saveSettingsToFile()
                updateWhiteScreen(v)
            end
        })

        OptSubTab:AddToggle({
            Text = "Show Minimal Status HUD",
            Description = "Display the floating HUD widget on screen",
            Default = Config.ShowMinimalHUD ~= false,
            Callback = function(v)
                Config.ShowMinimalHUD = v
                saveSettingsToFile()
                local parentGui = (gethui and gethui()) or CoreGui or localplayer:FindFirstChild("PlayerGui")
                local hudObj = parentGui and parentGui:FindFirstChild("ZD_FruitFinder_HUD")
                if hudObj then hudObj.Enabled = v end
            end
        })

        local WebhookSubTab = SettingsTab:AddSubTab({ Name = "Discord Webhook", Icon = "Lucide:bell" })
        WebhookSubTab:AddSection("Discord Webhook Reporter")

        WebhookSubTab:AddTextbox({
            Text = "Discord Webhook URL",
            Description = "Paste your Discord Channel Webhook URL here",
            Placeholder = "https://discord.com/api/webhooks/...",
            Default = Config.Webhook or "",
            Callback = function(text)
                Config.Webhook = text
                saveSettingsToFile()
            end
        })

        WebhookSubTab:AddToggle({
            Text = "Send Webhook on New Fruit",
            Description = "Sends rich color-coded embeds when a fruit is collected or rolled",
            Default = Config.SendWebhookNewItem,
            Callback = function(v)
                Config.SendWebhookNewItem = v
                saveSettingsToFile()
            end
        })

        WebhookSubTab:AddButton({
            Text = "Send Test Webhook Notification",
            Description = "Test your webhook connection with a sample embed",
            Icon = "Lucide:send",
            Callback = function()
                if not Config.Webhook or Config.Webhook == "" then
                    VindUI:Notify({ Title = "Webhook Error", Text = "Please configure a valid Webhook URL first!", Type = "warning", Duration = 3 })
                    return
                end
                sendDiscordWebhook("Dragon-Dragon", 3500000, "Mythical", 0xf1c40f, "Test Notification")
                VindUI:Notify({ Title = "Webhook Sent", Text = "Test notification dispatched to Discord!", Type = "success", Duration = 3 })
            end
        })

        -- 5. STATS & PROFILE TAB
        local ProfileSubTab = StatsTab:AddSubTab({ Name = "Profile", Icon = "Lucide:user" })
        local playerLevel = "?"
        pcall(function() playerLevel = tostring(localplayer.Data.Level.Value) end)

        ProfileSubTab:AddCard({
            UserId = localplayer.UserId,
            Title = localplayer.DisplayName or localplayer.Name,
            Description = string.format("Level: %s | %s | %s", playerLevel, CurrentSeaName, tostring(localplayer.Team and localplayer.Team.Name or Config.SelectTeam))
        })

        local LiveStatsSubTab = StatsTab:AddSubTab({ Name = "Live Stats", Icon = "Lucide:activity" })

        local radarStatsPara = LiveStatsSubTab:AddParagraph({
            Title = "Radar Status",
            Icon = "Lucide:radio",
            Text = "Status: Initializing...\nFruits in Server: 0\nLocation: " .. tostring(CurrentSeaName)
        })

        local sessionStatsPara = LiveStatsSubTab:AddParagraph({
            Title = "Session Analytics",
            Icon = "Lucide:chart-line",
            Text = "Collected: 0 | Stored: 0 | Dropped: 0 | Ignored: 0\nUptime: 0m"
        })

        vindStatusParagraph = radarStatsPara
        vindAnalyticsParagraph = sessionStatsPara

        task.spawn(function()
            while task.wait(1) do
                pcall(function()
                    if vindStatusParagraph and vindStatusParagraph.Set then
                        vindStatusParagraph:Set(string.format("Status: %s\nFruits in Server: %s\nLocation: %s (Sea %d)",
                            tostring(currentStatusMessage),
                            tostring(currentFruitsMessage),
                            tostring(CurrentSeaName),
                            CurrentSeaNum or 1
                        ))
                    end

                    if vindAnalyticsParagraph and vindAnalyticsParagraph.Set then
                        local elapsedSec = os.time() - (SessionStats.StartTime or os.time())
                        local mins = math.floor(elapsedSec / 60)
                        local secs = elapsedSec % 60
                        vindAnalyticsParagraph:Set(string.format("Fruits Collected: %d\nFruits Stored: %d\nFruits Dropped (Low-Beli): %d\nFruits Ignored: %d\nSession Uptime: %dm %ds",
                            SessionStats.FruitsCollected or 0,
                            SessionStats.FruitsStored or 0,
                            SessionStats.FruitsDropped or 0,
                            SessionStats.FruitsIgnored or 0,
                            mins,
                            secs
                        ))
                    end
                end)
            end
        end)

        VindUI:Notify({
            Title = "ZD Hub · Fruit Finder",
            Text = "VindUI successfully initialized! Click the ZD icon or press RightShift to toggle.",
            Type = "success",
            Duration = 4
        })
    end)
end)

print([[
════════════════════════════════════════════════════════════════════════════════
[ZD HUB] Fruit Finder & Gacha Automation Engine Loaded Successfully!
════════════════════════════════════════════════════════════════════════════════
]])
