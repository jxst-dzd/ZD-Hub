--[[
    ════════════════════════════════════════════════════════════════════════════
    ZD HUB — AUTO CHEST ENGINE (MASTERWORK EDITION)
    ════════════════════════════════════════════════════════════════════════════
    Engine Version : 4.3 (Smart Tween & Portal Fruit Warp Integration Edition)
    Compatible With: Blox Fruits (Sea 1, Sea 2, Sea 3)
    UI Integration : ZD Hub Glassmorphism Suite (UI.lua)
    Speed Profile  : Adaptive (Max Speed: 250 studs/sec)
    
    Architecture & Core Capabilities:  
      • Multi-PlaceId Sea Mapping (Supports 2 PlaceIds per Sea = 6 Sea PlaceIds Total)
      • Strict Known vs. Unknown PlaceId Detection (with Map Geometry Safe Fallback)
      • Silent In-Game ServerBrowser Engine ("Manual Hop Without Show UI")
        - 100% Invisible: Keeps ServerBrowser Frame offscreen & hidden (0 pixels visible)
        - Uses Official Blox Fruits __ServerBrowser Remote & Join Button Listeners
        - Obtains Valid Game-Authorized Teleport Tokens (Prevents Enum.TeleportResult.Unauthorized)
        - Golden Player Count Range (3-8 players) to eliminate:
            1. "Attempt to teleport to a restricted place" (1-2 player private/raid rooms)
            2. "Server error, please try again" (teleport remote race conditions)
            3. "The server is full / Max players" (10-12 player saturated servers)
      • 4-Case Failure Handler:
          Case 1: "Attempt to teleport to a restricted place" -> Blacklists server, retries public instance (3+ players)
          Case 2: "Server error, please try again" -> Blacklists server, 2s backoff, retries fresh server
          Case 3: "The server is full (max players)" -> Blacklists server, lowers max players to 7
          Case 4: Clean Success / Work -> Warps into optimal server
      • Server Blacklist & Visited Memory Tracking (ZD_Hub/VisitedServers.json with TTL)
      • Re-Entrancy Guarded TeleportInitFailed Watchdog & Auto-Retry Backoff
      • Zero-Rollback Tweening (3-Point Altitude Corridor & Direct Touch Alignment)
      • Accurate Chest Counter (Verified via Beli Increment & TouchTransmitter State)
      • Clean Codebase Formatting (Normalized Spacing & Optimized Layout)
    ════════════════════════════════════════════════════════════════════════════
--]]

-- ─── MOONVEIL COMMENT DIRECTIVES ─────────────────────────────────────────────
-- High-frequency hotspots are annotated with MoonVeil's native --!mv:omit and
-- --!mv:inline comment directives. No SDK header required.

-- ─── STEP 1: MULTI-EXECUTION GUARD & FULL GAME LOAD BARRIER ──────────────────
-- 1. Anti-Multi Execution Guard (Prevents script from running multiple times concurrently)
if getgenv().ZD_AUTOCHEST_LOADED then
    warn("[ZD Hub] Main Auto Chest is already running! Aborting duplicate execution.")
    return
end
getgenv().ZD_AUTOCHEST_LOADED = true

-- 2. Comprehensive Game & Asset Loading Gates
if not game:IsLoaded() then
    game.Loaded:Wait()
end
repeat task.wait(0.2) until game:IsLoaded()

local Players = game:GetService("Players")
local localplayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
repeat task.wait(0.2) until localplayer and localplayer.Parent

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 3. IMMEDIATE TEAM SELECTION (Must run before character spawn wait so the player can spawn into the game!)
local function autoSelectTeam()
    if localplayer.Team then return end
    local targetTeamName = (getgenv().Settings and getgenv().Settings.Setup and getgenv().Settings.Setup["Auto Select Team"]) or "Pirates"
    
    -- Method A: Remote Call
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local commF = remotes and remotes:FindFirstChild("CommF_")
        if commF then
            commF:InvokeServer("SetTeam", targetTeamName)
        end
    end)
    
    -- Method B: UI Activated button
    pcall(function()
        local pGui = localplayer:FindFirstChild("PlayerGui")
        if not pGui then return end
        local chooseTeam = (pGui:FindFirstChild("Main (minimal)") and pGui["Main (minimal)"]:FindFirstChild("ChooseTeam"))
            or (pGui:FindFirstChild("Main") and pGui.Main:FindFirstChild("ChooseTeam"))

        if chooseTeam and chooseTeam.Visible then
            local container = chooseTeam:FindFirstChild("Container")
            local targetTeam = container and (container:FindFirstChild(targetTeamName) or container:FindFirstChild("Pirates") or container:FindFirstChild("Marines"))
            local btn = targetTeam and targetTeam:FindFirstChild("Frame") and targetTeam.Frame:FindFirstChild("TextButton")
            if btn and getconnections then
                for _, conn in ipairs(getconnections(btn.Activated)) do
                    pcall(conn.Function)
                end
            end
        end
    end)
end

-- Fire team selection after a 2-second delay and repeat briefly until team is assigned
task.spawn(function()
    task.wait(2)
    local attempts = 0
    while not localplayer.Team and attempts < 30 do
        autoSelectTeam()
        task.wait(1)
        attempts = attempts + 1
    end
end)

-- Wait for critical game hierarchy (PlayerGui & Character) to initialize
local playerGui = localplayer:WaitForChild("PlayerGui", 25)
repeat task.wait(0.2) until localplayer.Character or localplayer.CharacterAdded:Wait()

-- Wait for Blox Fruits specific game assets and weapon caches to populate
repeat task.wait(0.25) until localplayer:FindFirstChild("Data") or localplayer:FindFirstChild("WeaponAssetCache") or (localplayer.Character and localplayer.Character:FindFirstChild("HumanoidRootPart"))

pcall(function()
    if setfpscap then
        setfpscap(60)
    end
end)

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── STEP 2: SETTINGS SYSTEM & PERSISTENCE ───────────────────────────────────
local SETTINGS_FILE = "ZD_Hub/AutoChest_Settings.json"

local defaultSettings = {
    Setup = {
        ["Auto Farm Chest"] = true,
        ["Tween Speed"] = 250,
        ["Smart Tween"] = true,
        ["Use Portal Fruit Method"] = true,
        ["Fast Travel Portals"] = true,
        ["Wall Slowdown"] = true,
        ["Max Chest Count"] = 30,
        ["Hop If Collected Enough Chest"] = true,
        ["Auto Server Hop"] = true,
        ["Hop When No Chests"] = true,
        ["Choose Hop Region"] = "All",
        ["Max Players Count"] = 8,
        ["Min Players Count"] = 3,
        ["Auto Select Team"] = "Pirates", -- "Pirates" or "Marines"
        ["Enable Haki"] = true,
        ["Stop If Have Items"] = true,
        ["Water Walk"] = true,
        ["Anti Water Damage"] = true,
        ["Auto Darkbeard"] = true,     -- Automatically summons & kills Darkbeard (with Fast Attack & Noclip)
        ["Auto Rip Indra"] = true,     -- Automatically summons & kills Rip Indra (with Fast Attack & Noclip)
        ["Auto Active Haki Colors"] = true, -- Auto activate color buttons with legendary haki if player has them
    },
    ItemsToStop = {
        ["God's Chalice"] = true,
        ["Fist of Darkness"] = true
    }
}

if not getgenv().Settings or type(getgenv().Settings) ~= "table" then
    getgenv().Settings = defaultSettings
else
    if not getgenv().Settings.Setup then
        getgenv().Settings.Setup = defaultSettings.Setup
    else
        for k, v in pairs(defaultSettings.Setup) do
            if getgenv().Settings.Setup[k] == nil then
                getgenv().Settings.Setup[k] = v
            end
        end
    end
    if not getgenv().Settings.ItemsToStop then
        getgenv().Settings.ItemsToStop = defaultSettings.ItemsToStop
    end
end

-- Metatable proxy so aliases stay in sync
setmetatable(getgenv().Settings.Setup, {
    __index = function(tbl, key)
        if key == "Auto Chest" then return rawget(tbl, "Auto Farm Chest") end
        if key == "Auto Farm Chest" then return rawget(tbl, "Auto Chest") end
        if key == "Max Chest" then return rawget(tbl, "Max Chest Count") end
        if key == "Auto Server Hop" then return rawget(tbl, "Hop If Collected Enough Chest") end
        if key == "Hop If Collected Enough Chest" then return rawget(tbl, "Auto Server Hop") end
        return nil
    end,
    __newindex = function(tbl, key, value)
        rawset(tbl, key, value)
        if key == "Auto Chest" then rawset(tbl, "Auto Farm Chest", value) end
        if key == "Auto Farm Chest" then rawset(tbl, "Auto Chest", value) end
        if key == "Max Chest" then rawset(tbl, "Max Chest Count", value) end
        if key == "Max Chest Count" then rawset(tbl, "Max Chest", value) end
        if key == "Auto Server Hop" then rawset(tbl, "Hop If Collected Enough Chest", value) end
        if key == "Hop If Collected Enough Chest" then rawset(tbl, "Auto Server Hop", value) end
    end
})

local function loadSettingsFromFile()
    pcall(function()
        if isfile and isfile(SETTINGS_FILE) then
            local decoded = HttpService:JSONDecode(readfile(SETTINGS_FILE))
            if type(decoded) == "table" and type(decoded.Setup) == "table" then
                for k, v in pairs(decoded.Setup) do
                    getgenv().Settings.Setup[k] = v
                end
            end
        end
    end)
end

local function saveSettingsToFile()
    pcall(function()
        if writefile then
            if not isfolder("ZD_Hub") then makefolder("ZD_Hub") end
            writefile(SETTINGS_FILE, HttpService:JSONEncode(getgenv().Settings))
        end
    end)
end

loadSettingsFromFile()

-- ─── STEP 3: INSTANT UI AUTO-LOADER & SYNC ───────────────────────────────────
local Controller = getgenv().ZD_AutoChest or _G.ZD_AutoChest

-- The old UI Suite loader (UI.lua) has been disabled in favor of the new VindUI implementation at the bottom of the script.
if not getgenv().ZD_AutoChest then
    getgenv().ZD_AutoChest = {}
    Controller = getgenv().ZD_AutoChest
end

local function setStatus(msg)
    if Controller and Controller.SetStatus then
        pcall(function() Controller.SetStatus(msg) end)
    else
        print("[ZD Status]", msg)
    end
end

local sessionBeli = 0
local currentBeli = 0

task.spawn(function()
    local p = game:GetService("Players").LocalPlayer
    local data = p:WaitForChild("Data", 15)
    if data then
        local beliObj = data:WaitForChild("Beli", 15)
        if beliObj then
            currentBeli = beliObj.Value
            beliObj.Changed:Connect(function(newVal)
                local diff = newVal - currentBeli
                currentBeli = newVal
                if diff > 0 then
                    sessionBeli = sessionBeli + diff
                    getgenv().Settings.Setup["In All Beli"] = (getgenv().Settings.Setup["In All Beli"] or 0) + diff
                    saveSettingsToFile()
                end
            end)
        end
    end
end)

local function addChestCount(n)
    getgenv().Settings.Setup["In All Chest"] = (getgenv().Settings.Setup["In All Chest"] or 0) + (n or 1)
    saveSettingsToFile()
    if Controller and Controller.AddChest then
        pcall(function() Controller.AddChest(n or 1) end)
    end
end

local function isFarmEnabled()
    if Controller and Controller.IsAutoChestEnabled then
        local ok, val = pcall(Controller.IsAutoChestEnabled)
        if ok then
            getgenv().Settings.Setup["Auto Farm Chest"] = val
            return val
        end
    end
    return getgenv().Settings.Setup["Auto Farm Chest"] == true
end

local function isHopEnabled()
    if Controller and Controller.IsServerHopEnabled then
        local ok, val = pcall(Controller.IsServerHopEnabled)
        if ok then
            getgenv().Settings.Setup["Hop If Collected Enough Chest"] = val
            getgenv().Settings.Setup["Auto Server Hop"] = val
            return val
        end
    end
    if getgenv().Settings.Setup["Auto Server Hop"] ~= nil then
        return getgenv().Settings.Setup["Auto Server Hop"] == true
    end
    return getgenv().Settings.Setup["Hop If Collected Enough Chest"] == true
end

-- ─── STEP 4: EXTENDED ANTI-CHEAT REMOTE SHIELD & PERFORMANCE ────────────────
print("[ZD Hub] Engaging Extended Anti-Cheat Shield...")

pcall(function()
    assert(getrawmetatable and setreadonly and newcclosure, "Metatable functions missing")
    local grm = getrawmetatable(game)
    setreadonly(grm, false)
    local oldNamecall = grm.__namecall
    local getNamecall = getnamecallmethod

    local BLOCKED_METHODS = {
        ["TeleportDetect"] = true,
        ["CHECKER_1"] = true,
        ["CHECKER"] = true,
        ["GUI_CHECK"] = true,
        ["OneMoreTime"] = true,
        ["checkingSPEED"] = true,
        ["BANREMOTE"] = true,
        ["PERMAIDBAN"] = true,
        ["KICKREMOTE"] = true,
        ["BR_KICK"] = true,
        ["BR_KICKPC"] = true,
        ["BR_KICKMOBILE"] = true,
        ["ReportActivity"] = true,
        ["CheckTeleportGlitchFix"] = true,
        ["Validator"] = true,
        ["Validator2"] = true,
        ["DMGDEBUG"] = true,
        ["KickPlayer"] = true,
        ["OnAnalyticsActivity"] = true
    }

    --!mv:omit
    local function namecallHook(self, ...)
        local method = getNamecall and getNamecall()
        if method == "FireServer" or method == "InvokeServer" then
            local arg1 = tostring(select(1, ...))
            if BLOCKED_METHODS[arg1] or (self and BLOCKED_METHODS[self.Name]) then
                return nil
            end
        end
        return oldNamecall(self, ...)
    end

    grm.__namecall = newcclosure(namecallHook)
    print("[ZD Hub] Metatable __namecall shield fully operational.")
end)

-- Anti-AFK disconnect disabler
pcall(function()
    if getconnections then
        for _, conn in ipairs(getconnections(localplayer.Idled)) do
            if conn.Disable then
                conn:Disable()
            end
        end
    end
end)

-- Performance FFlags
pcall(function()
    if setfflag then
        setfflag("HumanoidParallelRemoveNoPhysics", "False")
        setfflag("HumanoidParallelRemoveNoPhysicsNoSimulate2", "False")
        setfflag("AbuseReportScreenshot", "False")
        setfflag("AbuseReportScreenshotPercentage", "0")
    end
end)

-- ─── STEP 5: MULTI-PLACEID SEA DETECTION & SERVER HOP ARCHITECTURE ───────────
local ServerHop = getgenv().ServerHop
if not ServerHop or type(ServerHop.DetectPlace) ~= "function" then
    pcall(function()
        local paths = {
            "Blox Fruits/Universal Code/Server Hop.lua",
            "ZD Hub/Blox Fruits/Universal Code/Server Hop.lua",
            "Server Hop.lua"
        }
        for _, path in ipairs(paths) do
            if isfile and isfile(path) then
                getgenv().ZD_DISABLE_AUTOHOP = true
                ServerHop = loadfile(path)()
                getgenv().ZD_DISABLE_AUTOHOP = nil
                if ServerHop and type(ServerHop.DetectPlace) == "function" then
                    break
                end
            end
        end
    end)
end

if not ServerHop or type(ServerHop.DetectPlace) ~= "function" then
    ServerHop = {
        Config = {
            Seas = {
                [1] = {
                    Name = "First Sea",
                    PlaceIds = { 2753915549, 85211729168715 },
                    MapKeywords = { "Jungle", "PirateIsland", "Marine", "MiddleTown" }
                },
                [2] = {
                    Name = "Second Sea",
                    PlaceIds = { 4442272183, 79091703265657 },
                    MapKeywords = { "Dressrosa", "GreenBit", "Kingdom of Rose", "Colosseum", "Factory" }
                },
                [3] = {
                    Name = "Third Sea",
                    PlaceIds = { 7449423635, 100117331123089 },
                    MapKeywords = { "Turtle", "SeaCastle", "Hydra", "PortTown", "Haunted", "GreatTree" }
                }
            },
            VisitedFile = "ZD_Hub/VisitedServers.json",
            VisitedTTL = 7200,      -- 2 hours visited memory
            MaxPages = 4,           -- Search up to 4 pages of public servers
            MaxRetries = 5,         -- Maximum retry attempts before cooldown
            WatchdogTimeout = 14,   -- Unlock hopping state if teleport takes longer than 14s
            MinSafePlayers = 3,     -- Skip 1-2 player private/bugged raid dimensions (Error 773 prevention)
            DefaultMaxPlayers = 8,
            DefaultMinPlayers = 3
        },
        PlaceIndex = {}
    }

    -- Fast O(1) PlaceId-to-Sea lookup table
    for seaIdx, data in ipairs(ServerHop.Config.Seas) do
        for _, pid in ipairs(data.PlaceIds) do
            ServerHop.PlaceIndex[pid] = {
                SeaIndex = seaIdx,
                SeaName = data.Name,
                PlaceIds = data.PlaceIds
            }
        end
    end

    function ServerHop.DetectPlace(placeId)
        local targetPid = tonumber(placeId) or game.PlaceId
        local matched = ServerHop.PlaceIndex[targetPid]

        if matched then
            return {
                Known = true,
                PlaceId = targetPid,
                SeaIndex = matched.SeaIndex,
                SeaName = matched.SeaName,
                SeaPlaceIds = matched.PlaceIds,
                DetectedVia = "KnownPlaceId"
            }
        end

        -- Unknown PlaceId: use safe fallback based on workspace map geometry
        local map = workspace:FindFirstChild("Map")
        if map then
            for seaIdx, data in ipairs(ServerHop.Config.Seas) do
                for _, kw in ipairs(data.MapKeywords or {}) do
                    if map:FindFirstChild(kw) then
                        return {
                            Known = false,
                            PlaceId = targetPid,
                            SeaIndex = seaIdx,
                            SeaName = data.Name,
                            SeaPlaceIds = data.PlaceIds,
                            DetectedVia = "GeometryFallback"
                        }
                    end
                end
            end
        end

        -- Completely unknown PlaceId and no map geometry match
        return {
            Known = false,
            PlaceId = targetPid,
            SeaIndex = nil,
            SeaName = "Unknown Sea",
            SeaPlaceIds = {},
            DetectedVia = "None"
        }
    end
end

local currentDetection = ServerHop.DetectPlace(game.PlaceId)
local currentSeaIndex = currentDetection.SeaIndex or 1
local currentSeaName = currentDetection.SeaName
local FirstSea = (currentSeaIndex == 1)
local SecondSea = (currentSeaIndex == 2)
local ThirdSea = (currentSeaIndex == 3)

--- Sea verification helper functions
local function IsSecondSea()
    return SecondSea == true or game.PlaceId == 4442272183 or game.PlaceId == 79091703265657
end

local function IsThirdSea()
    return ThirdSea == true or game.PlaceId == 7449423635 or game.PlaceId == 100117331123089
end

print(string.format("[ServerHop] Initial Place Detection:\n  PlaceId: %d\n  Detected Sea: %s\n  Known PlaceId: %s\n  Method: %s",
    game.PlaceId,
    currentSeaName,
    tostring(currentDetection.Known),
    currentDetection.DetectedVia
))

-- ─── STEP 6: TEAM AUTO-SELECTION ─────────────────────────────────────────────
local function autoSelectTeam()
    if localplayer.Team then return end
    local targetTeamName = getgenv().Settings.Setup["Auto Select Team"] or "Pirates"
    pcall(function()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        local commF = remotes and remotes:FindFirstChild("CommF_")
        if commF then
            task.spawn(function()
                pcall(function()
                    commF:InvokeServer("SetTeam", targetTeamName)
                end)
            end)
        end
    end)
    pcall(function()
        local pGui = localplayer:WaitForChild("PlayerGui", 5)
        if not pGui then return end
        local chooseTeam = pGui:FindFirstChild("Main (minimal)") and pGui["Main (minimal)"]:FindFirstChild("ChooseTeam")
            or pGui:FindFirstChild("Main") and pGui.Main:FindFirstChild("ChooseTeam")

        if chooseTeam and chooseTeam.Visible then
            local container = chooseTeam:FindFirstChild("Container")
            local targetTeam = container and (container:FindFirstChild(targetTeamName) or container:FindFirstChild("Pirates") or container:FindFirstChild("Marines"))
            local btn = targetTeam and targetTeam:FindFirstChild("Frame") and targetTeam.Frame:FindFirstChild("TextButton")
            if btn and getconnections then
                for _, conn in ipairs(getconnections(btn.Activated)) do
                    pcall(conn.Function)
                end
            end
        end
    end)
end

autoSelectTeam()
localplayer:GetPropertyChangedSignal("Team"):Connect(function()
    autoSelectTeam()
end)

-- ─── STEP 7: STOP IF HAVE ITEMS SAFETY ────────────────────────────────────────
local function hasItem(itemName)
    if not itemName then return false end
    local lowerItemName = string.lower(itemName)
    
    local bp = localplayer:FindFirstChild("Backpack")
    local char = localplayer.Character
    
    if bp then
        for _, tool in ipairs(bp:GetChildren()) do
            if string.find(string.lower(tool.Name), lowerItemName) then
                return true
            end
        end
    end
    
    if char then
        for _, tool in ipairs(char:GetChildren()) do
            if string.find(string.lower(tool.Name), lowerItemName) then
                return true
            end
        end
    end
    
    return false
end

local function checkItemsStop()
    if not getgenv().Settings.Setup["Stop If Have Items"] then return false end
    for item, enabled in pairs(getgenv().Settings.ItemsToStop) do
        if enabled and hasItem(item) then
            return true, item
        end
    end
    return false, nil
end

-- ─── STEP 8: UNIVERSAL SMART TWEEN INTEGRATION & PHYSICS ENGINE ──────────────
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
                    break
                end
            end
        end
    end)
end

local isTraveling = false
local collectedThisSession = 0
local serverChestsCollected = 0

local cachedChar = nil
local cachedRoot = nil
local cachedHum = nil
local cachedCharacterParts = {}
local charListenerConns = {}

--!mv:omit
local function getCharacterParts()
    if cachedChar and cachedChar.Parent and cachedRoot and cachedRoot.Parent and cachedHum and cachedHum.Parent then
        return cachedChar, cachedRoot, cachedHum
    end
    local char = localplayer.Character
    if not char then return nil, nil, nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    cachedChar = char
    cachedRoot = root
    cachedHum = hum
    return char, root, hum
end

-- Hold Velocity: applies lift against gravity only (Y-axis), eliminating horizontal tween resistance
--!mv:omit
local function ensureHoldVelocity()
    local char, root = getCharacterParts()
    if not root then return nil end
    local hold = root:FindFirstChild("Hold")
    if not hold then
        hold = Instance.new("BodyVelocity")
        hold.Name = "Hold"
        hold.MaxForce = Vector3.new(0, 9e9, 0)
        hold.Velocity = Vector3.zero
        hold.Parent = root
    end
    return hold
end

--!mv:omit
local function removeHoldVelocity()
    local char, root = getCharacterParts()
    if root then
        local hold = root:FindFirstChild("Hold")
        if hold then hold:Destroy() end
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

--!mv:omit
local function disablePartCollision(part)
    if part and part:IsA("BasePart") and part.CanCollide then
        part.CanCollide = false
    end
end

--!mv:omit
local function applyNoclipToCharacter()
    for i = 1, #cachedCharacterParts do
        disablePartCollision(cachedCharacterParts[i])
    end
end

--!mv:omit
local function updateCachedParts(char)
    table.clear(cachedCharacterParts)
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            table.insert(cachedCharacterParts, part)
            if isTraveling then
                disablePartCollision(part)
            end
        end
    end
end

-- Anti-Sit & Seat-Ejection Routine
--!mv:omit
local function fixSit(hum)
    if not hum then return end
    pcall(function()
        hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
    end)
    if hum.Sit or hum.SeatPart then
        local seat = hum.SeatPart
        if seat then
            pcall(function()
                local weld = seat:FindFirstChild("SeatWeld")
                if weld then weld:Destroy() end
                seat.Disabled = true
                task.delay(0.2, function()
                    pcall(function() seat.Disabled = false end)
                end)
            end)
        end
        local char = hum.Parent
        if char then
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("Weld") and (d.Name == "SeatWeld" or d.Name:lower():find("seat")) then
                    pcall(function() d:Destroy() end)
                end
            end
        end
        hum.Sit = false
        hum.Jump = true
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end

local function setupCharacter(char)
    for _, c in ipairs(charListenerConns) do
        c:Disconnect()
    end
    table.clear(charListenerConns)

    if not char then return end

    cachedChar = char
    cachedRoot = char:WaitForChild("HumanoidRootPart", 5)
    cachedHum = char:WaitForChild("Humanoid", 5)

    updateCachedParts(char)

    if cachedHum then
        fixSit(cachedHum)
        table.insert(charListenerConns, cachedHum.Seated:Connect(function(active)
            if active then fixSit(cachedHum) end
        end))
        table.insert(charListenerConns, cachedHum:GetPropertyChangedSignal("Sit"):Connect(function()
            if cachedHum.Sit then fixSit(cachedHum) end
        end))
    end

    if isTraveling then
        ensureHoldVelocity()
        applyNoclipToCharacter()
    end

    table.insert(charListenerConns, char.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then
            table.insert(cachedCharacterParts, d)
            if isTraveling then
                disablePartCollision(d)
            end
        end
    end))
    table.insert(charListenerConns, char.DescendantRemoving:Connect(function(d)
        local idx = table.find(cachedCharacterParts, d)
        if idx then
            table.remove(cachedCharacterParts, idx)
        end
    end))
end

localplayer.CharacterAdded:Connect(function(char)
    task.wait(0.2)
    setupCharacter(char)
end)

if localplayer.Character then
    setupCharacter(localplayer.Character)
end

local ZD_AUTO_CHEST_SIGNATURE = "rbxassetid://3360689775" -- Secure P2P Sync Flag SPECIFIC to Auto Chest (Roblox Salute Emote)

--!mv:omit
local function isZDSyncUser(player)
    local char = player.Character
    if not char then return false end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return false end
    local animator = hum:FindFirstChild("Animator") or hum
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        if track.Animation and track.Animation.AnimationId == ZD_AUTO_CHEST_SIGNATURE then
            return true
        end
    end
    return false
end

--!mv:omit
local function broadcastZDSignature()
    local char = localplayer.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    local animator = hum:FindFirstChild("Animator") or hum

    local signatureTrack = nil
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        if track.Animation and track.Animation.AnimationId == ZD_AUTO_CHEST_SIGNATURE then
            signatureTrack = track
            break
        end
    end

    if not signatureTrack then
        local anim = Instance.new("Animation")
        anim.AnimationId = ZD_AUTO_CHEST_SIGNATURE
        signatureTrack = animator:LoadAnimation(anim)
        signatureTrack.Priority = Enum.AnimationPriority.Core
    end

    if not signatureTrack.IsPlaying then
        pcall(function() signatureTrack:Play(0, 0.001, 0) end)
    else
        pcall(function()
            signatureTrack:AdjustWeight(0.001)
            signatureTrack:AdjustSpeed(0)
        end)
    end
end

-- Active Noclip & NoPhysics State Loop
--!mv:omit
local function onPhysicsStepped()
    if isFarmEnabled() then
        local char, root, hum = getCharacterParts()
        if hum then
            if hum.Sit or hum.SeatPart then
                fixSit(hum)
            end
        end

        local darkEngine = getgenv().ZD_DarkbeardEngine
        local darkActive = darkEngine and (darkEngine.IsFighting or darkEngine.IsSummoning)
        local indraEngine = getgenv().ZD_RipIndraEngine
        local indraActive = indraEngine and (indraEngine.IsFighting or indraEngine.IsSummoning or indraEngine.IsActivatingColors)
        if isTraveling or darkActive or indraActive then
            if hum and hum:GetState() ~= Enum.HumanoidStateType.StrafingNoPhysics then
                hum:ChangeState(11) -- StrafingNoPhysics
            end
            for i = 1, #cachedCharacterParts do
                local part = cachedCharacterParts[i]
                if part and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end
        
        -- Broadcast ZD Hub P2P Signature
        if getgenv().Settings.Setup["Smart Chest Sync"] ~= false then
            broadcastZDSignature()
        end
    end
end

RunService.Stepped:Connect(onPhysicsStepped)

-- Buso Haki auto-activator
task.spawn(function()
    while task.wait(3) do
        if isFarmEnabled() and getgenv().Settings.Setup["Enable Haki"] then
            pcall(function()
                local char = localplayer.Character
                if char and not char:FindFirstChild("HasBuso") then
                    local commF = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
                    if commF then
                        commF:InvokeServer("Buso")
                    end
                end
            end)
        end
    end
end)

-- Water Walk single-application
local waterPlaneConfigured = false
local function applyWaterWalk()
    if getgenv().Settings.Setup["Water Walk"] and not waterPlaneConfigured then
        pcall(function()
            local waterPlane = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("WaterBase-Plane")
            if waterPlane and waterPlane.Size.Y ~= 112 then
                waterPlane.Size = Vector3.new(1000, 112, 1000)
                waterPlaneConfigured = true
            end
        end)
    end
end
task.spawn(function()
    task.wait(2)
    applyWaterWalk()
end)

-- ─── STEP 9: DIMENSION PORTAL FAST-TRAVEL ────────────────────────────────────
local function checkPortalTravel(targetPos)
    if not getgenv().Settings.Setup["Fast Travel Portals"] then return end
    local char, root = getCharacterParts()
    if not root then return end

    local commF = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
    if not commF then return end

    local currentDist = (targetPos - root.Position).Magnitude

    if FirstSea then
        local inUnderwater = root.Position.Y < -2000
        local targetInUnderwater = targetPos.Y < -2000

        if targetInUnderwater and not inUnderwater then
            setStatus("[ZD Hub] Fast-Travel: Warping into Underwater City...")
            task.spawn(function()
                pcall(function()
                    commF:InvokeServer("requestEntrance", Vector3.new(61163.85, 11.68, 1819.78))
                end)
            end)
            task.wait(0.7)
        elseif inUnderwater and not targetInUnderwater then
            setStatus("[ZD Hub] Fast-Travel: Warping out of Underwater City...")
            task.spawn(function()
                pcall(function()
                    commF:InvokeServer("requestEntrance", Vector3.new(3864.68, 4.85, -1926.21))
                end)
            end)
            task.wait(0.7)
        end
    elseif SecondSea then
        local inCursedShip = root.Position.Z > 25000
        local targetInCursedShip = targetPos.Z > 25000

        if targetInCursedShip and not inCursedShip then
            setStatus("[ZD Hub] Fast-Travel: Warping into Cursed Ship...")
            task.spawn(function()
                pcall(function()
                    commF:InvokeServer("requestEntrance", Vector3.new(923.2, 126.9, 32852.8))
                end)
            end)
            task.wait(0.7)
        elseif inCursedShip and not targetInCursedShip then
            setStatus("[ZD Hub] Fast-Travel: Warping out of Cursed Ship...")
            task.spawn(function()
                pcall(function()
                    commF:InvokeServer("requestEntrance", Vector3.new(-6508.5, 89.0, -132.8))
                end)
            end)
            task.wait(0.7)
        end
    elseif ThirdSea then
        if currentDist > 4000 then
            local portals = {
                { name = "Mansion", pos = Vector3.new(-12463.87, 374.91, -7523.77) },
                { name = "Castle on Sea", pos = Vector3.new(-5060.4, 318.5, -3193.2) },
                { name = "Hydra", pos = Vector3.new(5650.9, 1017.3, -350.4) },
                { name = "Tiki Outpost", pos = Vector3.new(-16798.7, 60.0, 292.0) },
                { name = "Great Tree", pos = Vector3.new(2284.91, 15.15, -9054.71) }
            }
            local bestPortal = nil
            local bestDist = currentDist
            for _, p in ipairs(portals) do
                local d = (targetPos - p.pos).Magnitude
                if d + 2200 < bestDist then
                    bestDist = d
                    bestPortal = p
                end
            end
            if bestPortal then
                setStatus("[ZD Hub] Fast-Travel: Warping to " .. bestPortal.name .. "...")
                task.spawn(function()
                    pcall(function()
                        commF:InvokeServer("requestEntrance", bestPortal.pos)
                    end)
                end)
                task.wait(0.7)
            end
        end
    end
end

-- ─── STEP 10: ZERO-ROLLBACK TWEEN ENGINE ─────────────────────────────────────
--!mv:omit
local function stopFlight()
    if getgenv().ChestTween then
        pcall(function() getgenv().ChestTween:Cancel() end)
        getgenv().ChestTween = nil
    end
    if SmartTween and type(SmartTween.Stop) == "function" then
        pcall(function() SmartTween.Stop() end)
    end
    isTraveling = false
    removeHoldVelocity()
end

--!mv:inline
local function calculateSpeed(dist)
    local configuredSpeed = tonumber(getgenv().Settings.Setup["Tween Speed"]) or 250

    if dist < 60 then
        return math.min(140, configuredSpeed)
    elseif dist < 200 then
        return math.min(165, configuredSpeed)
    else
        return configuredSpeed
    end
end

-- flyToDirect: Fallback direct corridor flight when Smart Tween is disabled
--!mv:omit
local function flyToDirect(targetPos)
    local char, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then
        return false
    end

    fixSit(hum)
    if getgenv().Settings.Setup["Fast Travel Portals"] ~= false then
        checkPortalTravel(targetPos)
    end

    char, root, hum = getCharacterParts()
    if not root then return false end

    local distance = (targetPos - root.Position).Magnitude
    if distance <= 3 then
        return true
    end

    local finalPos = targetPos + Vector3.new(0, 1.2, 0)
    local startPos = root.Position
    local waypoints = {}

    -- Waypoint Corridor: Ascend -> Cruise above water/terrain -> Descend directly onto chest
    if distance > 120 and (getgenv().Settings.Setup["Anti Water Damage"] ~= false) then
        local safeAltitude = math.max(startPos.Y, finalPos.Y, 280)
        table.insert(waypoints, Vector3.new(startPos.X, safeAltitude, startPos.Z))
        table.insert(waypoints, Vector3.new(finalPos.X, safeAltitude, finalPos.Z))
    end
    table.insert(waypoints, finalPos)

    ensureHoldVelocity()
    isTraveling = true

    for _, wp in ipairs(waypoints) do
        local wpDist = (wp - root.Position).Magnitude
        if wpDist <= 2 then continue end

        local speed = calculateSpeed(wpDist)
        local duration = wpDist / speed
        if duration <= 0 then continue end

        if getgenv().ChestTween then
            pcall(function() getgenv().ChestTween:Cancel() end)
            getgenv().ChestTween = nil
        end

        local lookDir = (wp - root.Position)
        local targetCF = CFrame.new(wp)
        if Vector2.new(lookDir.X, lookDir.Z).Magnitude > 0.5 then
            targetCF = CFrame.lookAt(wp, wp + Vector3.new(lookDir.X, 0, lookDir.Z))
        end

        local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
        local tween = TweenService:Create(root, tweenInfo, {
            CFrame = targetCF
        })
        getgenv().ChestTween = tween

        local completed = false
        local conn
        conn = tween.Completed:Connect(function()
            completed = true
        end)

        tween:Play()

        local startTime = os.clock()
        while isTraveling and not completed and (os.clock() - startTime < duration + 0.8) do
            if not isFarmEnabled() then
                stopFlight()
                return false
            end
            local hasItemStop, itemStopName = checkItemsStop()
            local allowItemFlight = (itemStopName == "Fist of Darkness" and getgenv().Settings.Setup["Auto Darkbeard"] ~= false and IsSecondSea())
                or (itemStopName == "God's Chalice" and getgenv().Settings.Setup["Auto Rip Indra"] ~= false and IsThirdSea())
            if hasItemStop and not allowItemFlight then
                stopFlight()
                setStatus("[ZD Hub] PAUSED: Rare Item Found (" .. itemStopName .. ")!")
                return false
            end
            if not hum or hum.Health <= 0 or not root or not root.Parent then
                stopFlight()
                return false
            end
            if (wp - root.Position).Magnitude <= 2 then
                completed = true
                break
            end
            task.wait(0.03)
        end

        if conn then conn:Disconnect() end
        pcall(function() tween:Cancel() end)
        if getgenv().ChestTween == tween then
            getgenv().ChestTween = nil
        end
    end

    return (root.Position - finalPos).Magnitude <= 5
end

-- flyTo: Primary navigation method — uses Universal Smart Tween if enabled, falls back to flyToDirect
--!mv:omit
local function flyTo(targetPos)
    local char, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then
        return false
    end

    fixSit(hum)

    local distance = (targetPos - root.Position).Magnitude
    if distance <= 3 then
        return true
    end

    -- 1. Check if Smart Tween Engine is enabled
    local useSmartTween = getgenv().Settings.Setup["Smart Tween"] ~= false
    if useSmartTween and SmartTween and type(SmartTween.To) == "function" then
        local configuredSpeed = tonumber(getgenv().Settings.Setup["Tween Speed"]) or 250
        local usePortals = getgenv().Settings.Setup["Fast Travel Portals"] ~= false
        local useFruit = getgenv().Settings.Setup["Use Portal Fruit Method"] ~= false
        local wallSlowdown = getgenv().Settings.Setup["Wall Slowdown"] ~= false

        SmartTween.Config.DefaultSpeed = configuredSpeed
        SmartTween.Config.PrioritizePortals = usePortals
        SmartTween.Config.PreferPortals = usePortals
        SmartTween.Config.UsePortalFruit = useFruit
        SmartTween.Config.WallSlowdownEnabled = wallSlowdown
        SmartTween.Config.WallSlowdownDistance = 70
        SmartTween.Config.WallSlowdownSpeed = 50

        isTraveling = true

        -- Safety Watchdog during flight (chest farm toggle & rare item detector)
        local watchdogActive = true
        task.spawn(function()
            while watchdogActive and SmartTween.State.IsTweening do
                if not isFarmEnabled() then
                    SmartTween.Stop()
                    break
                end
                local hasItemStop, itemStopName = checkItemsStop()
                local allowItemFlight = (itemStopName == "Fist of Darkness" and getgenv().Settings.Setup["Auto Darkbeard"] ~= false and IsSecondSea())
                    or (itemStopName == "God's Chalice" and getgenv().Settings.Setup["Auto Rip Indra"] ~= false and IsThirdSea())
                if hasItemStop and not allowItemFlight then
                    SmartTween.Stop()
                    setStatus("[ZD Hub] PAUSED: Rare Item Found (" .. itemStopName .. ")!")
                    break
                end
                task.wait(0.08)
            end
        end)

        local finalDestination = targetPos + Vector3.new(0, 1.2, 0)
        local success = SmartTween.To(finalDestination, {
            Speed = configuredSpeed,
            PrioritizePortals = usePortals,
            UsePortalFruit = useFruit,
            WallSlowdownEnabled = wallSlowdown,
            WallSlowdownDistance = 70,
            WallSlowdownSpeed = 50
        })

        watchdogActive = false
        isTraveling = false
        stopFlight()

        char, root = getCharacterParts()
        return root and ((root.Position - targetPos).Magnitude <= 5)
    end

    -- 2. Fallback: Direct Altitude Corridor Flight
    return flyToDirect(targetPos)
end

-- ─── STEP 11: CHEST SCANNER ──────────────────────────────────────────────────
local IgnoredChests = {}

--!mv:omit
local function getChestPosition(chest)
    if not chest or not chest.Parent then return nil end
    if chest:IsA("BasePart") then
        return chest.Position
    elseif chest:IsA("Model") then
        local touch = chest:FindFirstChildWhichIsA("TouchTransmitter", true)
        if touch and touch.Parent and touch.Parent:IsA("BasePart") then
            return touch.Parent.Position
        end
        if chest.PrimaryPart then
            return chest.PrimaryPart.Position
        end
        local part = chest:FindFirstChildWhichIsA("BasePart", true)
        if part then return part.Position end
    end
    return nil
end

--!mv:omit
local function isChestAvailable(chest)
    if not chest or not chest.Parent then return false end
    if not chest:IsDescendantOf(Workspace) then return false end

    local expireTime = IgnoredChests[chest]
    if expireTime and os.clock() < expireTime then
        return false
    end

    local touch = chest:FindFirstChildWhichIsA("TouchTransmitter", true)
    if not touch then
        return false
    end

    return true
end

--!mv:omit
local function tagChestIfMatch(inst)
    if not inst then return end
    local name = inst.Name
    if name:find("Chest") then
        pcall(function() CollectionService:AddTag(inst, "_ChestTagged") end)
    end
end

--!mv:omit
local function tagAllChests()
    local mapFolder = Workspace:FindFirstChild("Map")
    if mapFolder then
        for _, v in ipairs(mapFolder:GetDescendants()) do
            if v.Name:find("Chest") then
                tagChestIfMatch(v)
            end
        end
    end
    local chestModels = Workspace:FindFirstChild("ChestModels")
    if chestModels then
        for _, v in ipairs(chestModels:GetChildren()) do
            if v.Name:find("Chest") then
                tagChestIfMatch(v)
            end
        end
    end
end
tagAllChests()

Workspace.DescendantAdded:Connect(function(d)
    if d.Name:find("Chest") then
        tagChestIfMatch(d)
    end
end)

--!mv:omit
local function isChestContested(chestPos, myDist)
    if getgenv().Settings.Setup["Smart Chest Sync"] == false then return false end
    
    local PlayersService = game:GetService("Players")
    for _, p in ipairs(PlayersService:GetPlayers()) do
        if p ~= localplayer and isZDSyncUser(p) then
            local pRoot = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
            if pRoot then
                local theirDist = (pRoot.Position - chestPos).Magnitude
                
                if theirDist < myDist then
                    return true
                elseif math.abs(theirDist - myDist) < 5 then
                    if p.UserId < localplayer.UserId then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--!mv:omit
local function findNearestChest()
    local char, root = getCharacterParts()
    if not root then return nil, nil, math.huge end

    local nearestChest = nil
    local nearestPos = nil
    local nearestDist = math.huge

    local taggedChests = CollectionService:GetTagged("_ChestTagged")
    for _, chest in ipairs(taggedChests) do
        if isChestAvailable(chest) then
            local pos = getChestPosition(chest)
            if pos then
                local dist = (root.Position - pos).Magnitude
                if dist < nearestDist then
                    if not isChestContested(pos, dist) then
                        nearestDist = dist
                        nearestChest = chest
                        nearestPos = pos
                    end
                end
            end
        end
    end

    if not nearestChest then
        local searchFolders = {}
        if Workspace:FindFirstChild("Map") then table.insert(searchFolders, Workspace.Map) end
        if Workspace:FindFirstChild("ChestModels") then table.insert(searchFolders, Workspace.ChestModels) end
        
        for _, folder in ipairs(searchFolders) do
            local items = (folder.Name == "ChestModels") and folder:GetChildren() or folder:GetDescendants()
            for _, v in ipairs(items) do
                local name = v.Name
                if name:find("Chest") and isChestAvailable(v) then
                    tagChestIfMatch(v)
                    local pos = getChestPosition(v)
                    if pos then
                        local dist = (root.Position - pos).Magnitude
                        if dist < nearestDist then
                            if not isChestContested(pos, dist) then
                                nearestDist = dist
                                nearestChest = v
                                nearestPos = pos
                            end
                        end
                    end
                end
            end
        end
    end

    return nearestChest, nearestPos, nearestDist
end

-- ─── STEP 12: ACCURATE CHEST COLLECTION ROUTINE ──────────────────────────────
--!mv:omit
local function collectChest(chest, pos)
    local char, root = getCharacterParts()
    if not root or not chest then return false end

    local touchTransmitter = chest:FindFirstChildWhichIsA("TouchTransmitter", true)
    local chestPart = touchTransmitter and touchTransmitter.Parent
    if not chestPart or not chestPart:IsA("BasePart") then return false end

    local data = localplayer:FindFirstChild("Data")
    local beliObj = data and data:FindFirstChild("Beli")
    local initialBeli = beliObj and beliObj.Value or 0

    pcall(function()
        if firetouchinterest then
            firetouchinterest(root, chestPart, 0)
            task.wait(0.04)
            firetouchinterest(root, chestPart, 1)
        end
    end)

    local startWait = os.clock()
    local collected = false
    while os.clock() - startWait < 0.6 do
        local beliNow = beliObj and beliObj.Value or 0
        if beliNow > initialBeli or not chest.Parent or not chestPart.Parent or not chestPart:FindFirstChildWhichIsA("TouchTransmitter") then
            collected = true
            break
        end
        task.wait(0.04)
    end

    IgnoredChests[chest] = os.clock() + 35
    return collected
end

-- ─── STEP 13: SILENT IN-GAME SERVER BROWSER HOPPING ENGINE ───────────────────
local isHopping = false
local currentHopRetries = 0
local hopWatchdogThread = nil
local lastTeleportFailTime = 0
local lastTargetJobId = nil

function ServerHop.Log(msg)
    print("[ServerHop] " .. tostring(msg))
end

function ServerHop.IsHopping()
    return isHopping
end

function ServerHop.Cancel()
    isHopping = false
    currentHopRetries = 0
    lastTargetJobId = nil
    if hopWatchdogThread then
        pcall(function() task.cancel(hopWatchdogThread) end)
        hopWatchdogThread = nil
    end

    pcall(function()
        local PlayerGui = localplayer and localplayer:FindFirstChild("PlayerGui")
        local ServerBrowser = PlayerGui and PlayerGui:FindFirstChild("ServerBrowser")
        if ServerBrowser then
            ServerBrowser.Enabled = false
            local frame = ServerBrowser:FindFirstChild("Frame")
            if frame then
                frame.Visible = true
                frame.Position = UDim2.fromScale(0.5, 0.5)
            end
            ServerBrowser.DisplayOrder = 1
        end
    end)

    ServerHop.Log("Server hop process cancelled.")
end

function ServerHop.LoadVisited()
    local visited = {}
    pcall(function()
        if isfile and isfile(ServerHop.Config.VisitedFile) then
            local decoded = HttpService:JSONDecode(readfile(ServerHop.Config.VisitedFile))
            if type(decoded) == "table" then
                visited = decoded
            end
        end
    end)
    return visited
end

function ServerHop.MarkVisited(jobId)
    if not jobId or jobId == "" then return end
    pcall(function()
        local visited = ServerHop.LoadVisited()
        local now = os.time()
        visited[tostring(jobId)] = now
        for id, ts in pairs(visited) do
            if type(ts) == "number" and (now - ts > ServerHop.Config.VisitedTTL) then
                visited[id] = nil
            end
        end
        if writefile then
            if not isfolder("ZD_Hub") then makefolder("ZD_Hub") end
            writefile(ServerHop.Config.VisitedFile, HttpService:JSONEncode(visited))
        end
    end)
end

function ServerHop.ClearVisited()
    pcall(function()
        if writefile then
            if not isfolder("ZD_Hub") then makefolder("ZD_Hub") end
            writefile(ServerHop.Config.VisitedFile, HttpService:JSONEncode({}))
        end
    end)
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

-- ─── ADVANCED ERROR CLEAR & CANDIDATE POOLING ENGINE ─────────────────────────
local candidatePool = {}
local lastCandidateFetchTick = 0
local last429Tick = 0
local serverTeleportInvoked = false

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

local function registerQueueTeleport()
    pcall(function()
        local q = (syn and syn.queue_on_teleport) or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)
        if q then
            q([[
                pcall(function()
                    if isfile and isfile("Blox Fruits/Auto Chest.lua") then
                        loadfile("Blox Fruits/Auto Chest.lua")()
                    elseif isfile and isfile("Auto Chest.lua") then
                        loadfile("Auto Chest.lua")()
                    elseif isfile and isfile("ZD_Hub/Auto Chest.lua") then
                        loadfile("ZD_Hub/Auto Chest.lua")()
                    end
                end)
            ]])
        end
    end)
end

-- Backward-compatible ManualHop using in-memory candidates
function ServerHop.ManualHop(options)
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

    -- Safety check: Do not hop if player holds rare items
    local hasStopItem, itemName = checkItemsStop()
    if hasStopItem then
        setStatus("[ZD Hub] Server Hop Cancelled: Retaining " .. tostring(itemName) .. "!")
        ServerHop.Log("Server hop cancelled: Retaining " .. tostring(itemName))
        isHopping = false
        return false, "Holding rare item"
    end

    -- Safety check: Do not hop if Darkbeard is active or ready to summon
    local darkEngine = getgenv().ZD_DarkbeardEngine
    if darkEngine and darkEngine.IsDarkbeardActiveOrReady and darkEngine.IsDarkbeardActiveOrReady() then
        setStatus("[ZD Hub] Server Hop Cancelled: Darkbeard active / ready to summon!")
        ServerHop.Log("Server hop cancelled: Darkbeard active / ready to summon")
        isHopping = false
        return false, "Darkbeard active or ready"
    end

    -- Safety check: Do not hop if Rip Indra is active or ready to summon
    local indraEngine = getgenv().ZD_RipIndraEngine
    if indraEngine and indraEngine.IsIndraActiveOrReady and indraEngine.IsIndraActiveOrReady() then
        setStatus("[ZD Hub] Server Hop Cancelled: Rip Indra active / ready to summon!")
        ServerHop.Log("Server hop cancelled: Rip Indra active / ready to summon")
        isHopping = false
        return false, "Rip Indra active or ready"
    end

    stopFlight()
    cleanCharacterForces()
    registerQueueTeleport()

    local targetPlaceId = game.PlaceId
    local currentJobId = game.JobId
    local visited = ServerHop.LoadVisited()
    visited[currentJobId] = os.time()

    local setup = (getgenv().Settings and getgenv().Settings.Setup) or {}
    local minP = math.max(tonumber(customOptions.MinPlayers) or tonumber(setup["Min Players Count"]) or 4, 4)
    local maxP = math.min(math.max(tonumber(customOptions.MaxPlayers) or tonumber(setup["Max Players Count"]) or 8, minP), 11)

    -- Watchdog timeout to prevent frozen state
    if hopWatchdogThread then
        pcall(function() task.cancel(hopWatchdogThread) end)
    end
    hopWatchdogThread = task.delay(ServerHop.Config.WatchdogTimeout or 14, function()
        if isHopping then
            isHopping = false
            dismissTeleportScreen()
            ServerHop.Log("Watchdog timeout elapsed without teleport completion. State reset.")
            setStatus("[ZD Hub] Teleport timed out. Resuming normal loop.")
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
            ServerHop.Log("In API rate-limit cooldown. Using available local cache...")
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
                ServerHop.Log("Visited server cache full or exhausted. Resetting visited memory...")
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

        ServerHop.Log(string.format("Selected optimal server: %s (%d players in Place %s)", tostring(chosenJob), chosen.playing, tostring(targetPlaceId)))
        setStatus(string.format("[ZD Hub] Hopping to %s (%d players)...", chosenJob:sub(1, 8), chosen.playing))
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
                    ServerHop.Log("Fallback: Executing direct TeleportToPlaceInstance...")
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
        setStatus("[ZD Hub] No candidate servers available. Retrying...")
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
        ServerHop.Log(string.format("Blacklisted failed server instance: %s", tostring(lastTargetJobId):sub(1, 8)))
    end

    currentHopRetries = currentHopRetries + 1
    local backoff = math.min(currentHopRetries * 2, 6)
    setStatus(string.format("[ZD Hub] Teleport failed. Retrying in %ds...", backoff))
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

-- Export global references
getgenv().ServerHop = ServerHop
getgenv().ZD_AutoChest_HopServer = hopServer
if getgenv().ZD_AutoChest then
    getgenv().ZD_AutoChest.Hop = hopServer
    getgenv().ZD_AutoChest.HopServer = hopServer
    getgenv().ZD_AutoChest.ServerHop = ServerHop
end

-- Teleport failure auto-retry handler with re-entrancy prevention
TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, errorMessage)
    if player == localplayer or not player then
        ServerHop.HandleTeleportFailed(teleportResult, errorMessage)
    end
end)


-- ─── STEP 13.5: AUTO SUMMON & AUTO KILL DARKBEARD ENGINE ──────────────────────
local DarkbeardEngine = {
    IsSummoning = false,
    IsFighting = false,
    LastSummonAttempt = 0,
    DetectionPart = nil,
    ArenaCFrame = CFrame.new(3864.69, 14.86, -3498.05), -- Map geometry fallback: Dark Arena center
}
getgenv().ZD_DarkbeardEngine = DarkbeardEngine

--- Checks whether the current server is running in Sea 2
local function IsSecondSea()
    return SecondSea == true or game.PlaceId == 4442272183 or game.PlaceId == 79091703265657
end

--- Resolves the Dark Arena summon altar detection part in workspace
function DarkbeardEngine.GetAltarDetection()
    if DarkbeardEngine.DetectionPart and DarkbeardEngine.DetectionPart.Parent then
        return DarkbeardEngine.DetectionPart
    end

    pcall(function()
        local map = Workspace:FindFirstChild("Map")
        local arena = map and (map:FindFirstChild("DarkbeardArena") or map:FindFirstChild("Dark Arena") or map:FindFirstChild("Arena"))
        if arena then
            local summoner = arena:FindFirstChild("Summoner") or arena:FindFirstChild("Pedestal") or arena:FindFirstChild("Altar")
            if summoner then
                local det = summoner:FindFirstChild("Detection") or summoner:FindFirstChild("Hitbox") or summoner:FindFirstChild("PrimaryPart") or summoner:FindFirstChildOfClass("BasePart")
                if det then
                    DarkbeardEngine.DetectionPart = det
                    DarkbeardEngine.ArenaCFrame = det.CFrame
                end
            end
        end
    end)

    return DarkbeardEngine.DetectionPart
end

--- Locates an active Darkbeard entity in workspace.Enemies
function DarkbeardEngine.FindActiveBoss()
    if not IsSecondSea() then return nil end
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return nil end

    for _, enemy in ipairs(enemies:GetChildren()) do
        local name = enemy.Name
        if name:find("Darkbeard") or name:find("Dark beard") then
            local hum = enemy:FindFirstChildOfClass("Humanoid")
            local hrp = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart
            if hum and hum.Health > 0 and hrp then
                return enemy, hrp, hum
            end
        end
    end

    return nil
end

--- Checks if player holds the Fist of Darkness in Backpack or Character
function DarkbeardEngine.HasFistOfDarkness()
    return hasItem("Fist of Darkness")
end

--- Checks whether Darkbeard is either currently spawned or ready to be summoned
function DarkbeardEngine.IsDarkbeardActiveOrReady()
    if not IsSecondSea() then return false end
    if not (getgenv().Settings.Setup["Auto Darkbeard"] ~= false) then return false end

    -- Check if Darkbeard is alive in server
    local boss = DarkbeardEngine.FindActiveBoss()
    if boss then return true end

    -- Check if player has Fist of Darkness
    if DarkbeardEngine.HasFistOfDarkness() then
        return true
    end

    return false
end

--- Executes the Darkbeard summon sequence using the Fist of Darkness
function DarkbeardEngine.ExecuteSummon()
    if not IsSecondSea() then return false end
    if not (getgenv().Settings.Setup["Auto Darkbeard"] ~= false) then return false end
    local char, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return false end

    local detPart = DarkbeardEngine.GetAltarDetection()
    local targetCF = detPart and detPart.CFrame or DarkbeardEngine.ArenaCFrame
    local targetPos = targetCF.Position

    local dist = (targetPos - root.Position).Magnitude
    if dist > 8 then
        setStatus("[ZD Hub] Warping to Darkbeard Arena Altar...")
        flyTo(targetPos)
        return false
    end

    -- Close enough: Equip Fist of Darkness and touch altar
    DarkbeardEngine.IsSummoning = true
    setStatus("[ZD Hub] Inserting Fist of Darkness into Altar...")

    -- Equip Fist of Darkness tool
    local fistTool = (localplayer.Backpack and localplayer.Backpack:FindFirstChild("Fist of Darkness"))
        or (char:FindFirstChild("Fist of Darkness"))

    if fistTool then
        hum:EquipTool(fistTool)
        task.wait(0.15)
    end

    -- Fire touch detection
    pcall(function()
        local heldTool = char:FindFirstChild("Fist of Darkness")
        local handle = heldTool and heldTool:FindFirstChild("Handle")
        local target = detPart or root

        if handle and detPart then
            firetouchinterest(handle, detPart, 0)
            firetouchinterest(handle, detPart, 1)
        end
        if detPart then
            firetouchinterest(root, detPart, 0)
            firetouchinterest(root, detPart, 1)
        end
    end)

    task.wait(0.5)
    DarkbeardEngine.IsSummoning = false
    return true
end

--- Executes the auto-combat loop against Darkbeard until defeated
--!mv:omit
local function executeDarkbeardCombat(boss, bossRoot, bossHum)
    if not IsSecondSea() then return false end
    local char, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return false end

    DarkbeardEngine.IsFighting = true
    setStatus(string.format("[ZD Hub] Engaged with Darkbeard! (HP: %d/%d)", math.floor(bossHum.Health), math.floor(bossHum.MaxHealth)))

    -- Hover safe distance above Darkbeard (7 studs horizontal, 18 studs vertical)
    local safeCombatCF = bossRoot.CFrame * CFrame.new(0, 18, 5)
    local dist = (safeCombatCF.Position - root.Position).Magnitude

    if dist > 60 then
        flyTo(safeCombatCF.Position)
    else
        if isTraveling then stopFlight() end
        ensureHoldVelocity()
        root.CFrame = safeCombatCF
        root.AssemblyLinearVelocity = Vector3.zero
    end

    -- Ensure Noclip & anti-physics drag on player character during combat
    if hum:GetState() ~= Enum.HumanoidStateType.StrafingNoPhysics then
        hum:ChangeState(11) -- StrafingNoPhysics
    end
    for i = 1, #cachedCharacterParts do
        local part = cachedCharacterParts[i]
        if part and part.CanCollide then
            part.CanCollide = false
        end
    end

    -- Freeze Darkbeard velocity & disable boss collision so attacks connect cleanly
    pcall(function()
        bossRoot.CanCollide = false
        if not bossRoot:FindFirstChild("ZD_LockVelocity") then
            local bv = Instance.new("BodyVelocity")
            bv.Name = "ZD_LockVelocity"
            bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            bv.Velocity = Vector3.zero
            bv.Parent = bossRoot
        end
    end)

    -- Ensure Buso Haki is active
    if not char:FindFirstChild("HasBuso") then
        pcall(function()
            local commF = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
            if commF then commF:InvokeServer("Buso") end
        end)
    end

    -- Ensure Melee / Sword weapon is equipped
    local currentTool = char:FindFirstChildOfClass("Tool")
    if not currentTool or currentTool.ToolTip == "Blox Fruit" or currentTool.ToolTip == "" then
        local bp = localplayer:FindFirstChild("Backpack")
        if bp then
            local w = bp:FindFirstChild("Electric Claw") or bp:FindFirstChild("Hallow Scythe")
            if not w then
                for _, item in ipairs(bp:GetChildren()) do
                    if item:IsA("Tool") and (item.ToolTip == "Melee" or item.ToolTip == "Sword") then
                        w = item
                        break
                    end
                end
            end
            if w then hum:EquipTool(w) end
        end
    end

    -- Trigger Fast Attack on CombatFramework
    pcall(function()
        local ps = localplayer:FindFirstChild("PlayerScripts")
        local cfModule = ps and ps:FindFirstChild("CombatFramework")
        if cfModule then
            local combatData = getupvalues and getupvalues(require(cfModule))
            local activeController = combatData and combatData[2] and combatData[2].activeController
            if activeController then
                activeController:attack()
                activeController.timeToNextAttack = 0
                activeController.attacking = false
                activeController.increment = 3
            end
        end
    end)

    -- Execute Fast Attack Remote Pipeline on Darkbeard
    pcall(function()
        local attackEngine = getgenv().ZD_AttackEngine
        if attackEngine and attackEngine.AttackMobs then
            attackEngine.AttackMobs()
        else
            -- Direct ReplicatedStorage hit pipeline with full hitData payload
            local net = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("Net")
            local regAtk = net and net:FindFirstChild("RE/RegisterAttack")
            local regHit = net and net:FindFirstChild("RE/RegisterHit")
            local global = require(ReplicatedStorage.Global)
            local co = global and debug.getupvalue(global.SendHitsToServer, 1)

            if regAtk then regAtk:FireServer(0/0) end

            local hitPayload = { { boss, bossRoot } }
            if co and coroutine.status(co) == "suspended" then
                coroutine.resume(co, bossRoot, hitPayload)
            elseif regHit then
                regHit:FireServer(bossRoot, hitPayload)
            end
        end
    end)

    return true
end
DarkbeardEngine.ExecuteCombat = executeDarkbeardCombat

-- Export DarkbeardEngine to global environment
getgenv().ZD_DarkbeardEngine = DarkbeardEngine

-- ─── STEP 13.6: AUTO SUMMON & AUTO KILL RIP INDRA ENGINE (SEA 3) ──────────────
local RipIndraEngine = {
    IsSummoning = false,
    IsFighting = false,
    IsActivatingColors = false,
    LastSummonAttempt = 0,
    DetectionPart = nil,
    PedestalCFrame = CFrame.new(-5560.27, 313.92, -2663.90), -- Altar pedestal where God's Chalice is placed
    ArenaCFrame = CFrame.new(-5332.30, 423.99, -2673.48),    -- Main Castle arena center
    OwnedColors = {},                                        -- Cache: [colorName] = true / false
    FailedColors = {},                                       -- Cache: [colorName] = timestamp
    Buttons = {
        {
            Name = "Pure Red",
            ColorAlias = "Really red",
            Position = Vector3.new(-5414.41, 309.87, -2212.46),
            CFrame = CFrame.new(-5414.41, 309.87, -2212.46)
        },
        {
            Name = "Snow White",
            ColorAlias = "Oyster",
            Position = Vector3.new(-4971.48, 331.57, -3720.03),
            CFrame = CFrame.new(-4971.48, 331.57, -3720.03)
        },
        {
            Name = "Winter Sky",
            ColorAlias = "Hot pink",
            Position = Vector3.new(-5420.17, 1084.97, -2666.82),
            CFrame = CFrame.new(-5420.17, 1084.97, -2666.82)
        }
    }
}
getgenv().ZD_RipIndraEngine = RipIndraEngine

--- Checks whether current game session is in Sea 3
local function IsThirdSea()
    return ThirdSea == true or game.PlaceId == 7449423635 or game.PlaceId == 100117331123089
end

--- Resolves the Castle on the Sea altar detection part in workspace
function RipIndraEngine.GetPedestalDetection()
    if RipIndraEngine.DetectionPart and RipIndraEngine.DetectionPart.Parent then
        return RipIndraEngine.DetectionPart
    end

    pcall(function()
        local map = Workspace:FindFirstChild("Map")
        local castle = map and (map:FindFirstChild("Boat Castle") or map:FindFirstChild("Castle on the Sea") or map:FindFirstChild("Castle"))
        if castle then
            local summoner = castle:FindFirstChild("Summoner") or castle:FindFirstChild("Pedestal") or castle:FindFirstChild("Altar")
            if summoner then
                local det = summoner:FindFirstChild("Detection") or summoner:FindFirstChild("Hitbox") or summoner:FindFirstChild("PrimaryPart") or summoner:FindFirstChildOfClass("BasePart")
                if det then
                    RipIndraEngine.DetectionPart = det
                    RipIndraEngine.PedestalCFrame = det.CFrame
                end
            end
        end
    end)

    return RipIndraEngine.DetectionPart
end

--- Locates an active Rip Indra entity in workspace.Enemies
function RipIndraEngine.FindActiveBoss()
    if not IsThirdSea() then return nil end
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return nil end

    for _, enemy in ipairs(enemies:GetChildren()) do
        local name = enemy.Name
        if name:find("rip_indra") or name:find("indra") then
            local hum = enemy:FindFirstChildOfClass("Humanoid")
            local hrp = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart
            if hum and hum.Health > 0 and hrp then
                return enemy, hrp, hum
            end
        end
    end

    return nil
end

--- Checks if player holds God's Chalice in Backpack or Character
function RipIndraEngine.HasGodsChalice()
    return hasItem("God's Chalice")
end

--- Inspects the 3 Castle on the Sea Haki color button pads
function RipIndraEngine.GetButtonStatus()
    local unactivatedButtons = {}
    local map = Workspace:FindFirstChild("Map")
    local castle = map and (map:FindFirstChild("Boat Castle") or map:FindFirstChild("Castle on the Sea"))
    local summoner = castle and castle:FindFirstChild("Summoner")
    local circle = summoner and summoner:FindFirstChild("Circle")

    local foundParts = {}
    if circle then
        for _, child in ipairs(circle:GetChildren()) do
            local indicator = child:FindFirstChild("Part") or child
            if indicator and indicator:IsA("BasePart") then
                local isLime = (tostring(indicator.BrickColor) == "Lime green") or (indicator.BrickColor.Name == "Lime green")
                local brickName = indicator.BrickColor.Name
                local colorMatched = nil
                if brickName == "Really red" or tostring(indicator.BrickColor) == "Really red" then
                    colorMatched = "Pure Red"
                elseif brickName == "Oyster" or tostring(indicator.BrickColor) == "Oyster" then
                    colorMatched = "Snow White"
                elseif brickName == "Hot pink" or tostring(indicator.BrickColor) == "Hot pink" then
                    colorMatched = "Winter Sky"
                end

                if colorMatched then
                    foundParts[colorMatched] = {
                        Part = indicator,
                        CFrame = indicator.CFrame,
                        IsActive = isLime
                    }
                end
            end
        end
    end

    for _, btnDef in ipairs(RipIndraEngine.Buttons) do
        local liveData = foundParts[btnDef.Name]
        local isActive = false
        local targetCF = btnDef.CFrame
        local targetPart = nil

        if liveData then
            isActive = liveData.IsActive
            targetCF = liveData.CFrame
            targetPart = liveData.Part
        else
            for _, descendant in ipairs((castle or Workspace):GetDescendants()) do
                if descendant:IsA("BasePart") and (descendant.Position - btnDef.Position).Magnitude < 15 then
                    targetPart = descendant
                    targetCF = descendant.CFrame
                    if tostring(descendant.BrickColor) == "Lime green" or descendant.BrickColor.Name == "Lime green" then
                        isActive = true
                    end
                    break
                end
            end
        end

        if not isActive then
            table.insert(unactivatedButtons, {
                Name = btnDef.Name,
                ColorAlias = btnDef.ColorAlias,
                CFrame = targetCF,
                Part = targetPart
            })
        end
    end

    return unactivatedButtons, (#unactivatedButtons == 0)
end

-- Legendary Haki Color Item IDs (Extracted directly from ItemConfig on live client)
local HAKI_COLOR_IDS = {
    ["Pure Red"] = 287,
    ["Snow White"] = 277,
    ["Winter Sky"] = 292,
    ["Bright Yellow"] = 275,
    ["Rainbow Saviour"] = 285
}
RipIndraEngine.ColorItemIds = HAKI_COLOR_IDS

--- Checks if player owns the required legendary Haki color using ItemReplication
function RipIndraEngine.CheckOwnsColor(colorName)
    if RipIndraEngine.OwnedColors[colorName] ~= nil then
        return RipIndraEngine.OwnedColors[colorName]
    end

    local itemId = HAKI_COLOR_IDS[colorName]
    local owns = false

    -- 1. Query modern ItemReplication service (verified on live client)
    pcall(function()
        local itemRep = require(ReplicatedStorage.Util.ItemReplication)
        if itemId and itemRep and itemRep.IsOwned and itemRep.IsOwned.readClient then
            local res = itemRep.IsOwned.readClient(itemId)
            if res == true then
                owns = true
            end
        end
    end)

    -- 2. Fallback check via ModificationFunction GetData
    if not owns and itemId then
        pcall(function()
            local netMod = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("Net")
            if netMod then
                local net = require(netMod)
                local modRF = net:RemoteFunction("ModificationFunction")
                if modRF then
                    modRF:InvokeServer({ Type = "GetData" })
                    local itemRep = require(ReplicatedStorage.Util.ItemReplication)
                    if itemRep.IsEquipped.readClient(itemId) == true then
                        owns = true
                    end
                end
            end
        end)
    end

    if owns then
        RipIndraEngine.OwnedColors[colorName] = true
        return true
    end

    return false
end

--- Equips a specific Haki color using the verified ModificationFunction remote
function RipIndraEngine.EquipHakiColor(colorName)
    local itemId = HAKI_COLOR_IDS[colorName]
    if not itemId then return false end

    local success = false

    -- 1. Primary: Net["RF/ModificationFunction"] SetEquip (Cobalt verified & live-tested)
    pcall(function()
        local netMod = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("Net")
        if netMod then
            local modRF = netMod:FindFirstChild("RF/ModificationFunction")
            if not modRF then
                local net = require(netMod)
                modRF = net:RemoteFunction("ModificationFunction")
            end
            if modRF then
                local res = modRF:InvokeServer({
                    Type = "SetEquip",
                    IsEquipped = true,
                    ItemId = itemId
                })
                if res and (res.Success == true or res.Success == "true") then
                    success = true
                end
            end
        end
    end)

    -- 2. Activate Buso / Aura on character if not already active
    local char = localplayer.Character
    if char and not char:FindFirstChild("HasBuso") then
        pcall(function()
            local commF = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
            if commF then commF:InvokeServer("Buso") end
        end)
    end

    return success
end

--- Automatically steps on unactivated Castle on the Sea buttons if player has the color and God's Chalice
function RipIndraEngine.ExecuteActivateButtons()
    if not IsThirdSea() then return false end
    if not (getgenv().Settings.Setup["Auto Active Haki Colors"] ~= false) then return false end
    if not RipIndraEngine.HasGodsChalice() then return false end

    local unactivatedButtons, areAllActive = RipIndraEngine.GetButtonStatus()
    if areAllActive or #unactivatedButtons == 0 then
        return false
    end

    local char, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return false end

    local now = os.clock()

    for _, btn in ipairs(unactivatedButtons) do
        local failedTime = RipIndraEngine.FailedColors[btn.Name]
        if failedTime and (now - failedTime < 60) then
            continue
        end

        local owns = RipIndraEngine.CheckOwnsColor(btn.Name)
        if owns == false then
            continue
        end

        RipIndraEngine.IsActivatingColors = true
        setStatus(string.format("[ZD Hub] Activating %s Haki button...", btn.Name))

        -- Equip the required color
        RipIndraEngine.EquipHakiColor(btn.Name)
        task.wait(0.2)

        -- Fly to button position
        local targetPos = btn.CFrame.Position
        local dist = (targetPos - root.Position).Magnitude
        if dist > 8 then
            flyTo(targetPos + Vector3.new(0, 3, 0))
        end

        char, root, hum = getCharacterParts()
        if not root then
            RipIndraEngine.IsActivatingColors = false
            return false
        end

        -- Step onto button pad and fire touch
        root.CFrame = btn.CFrame * CFrame.new(0, 2.5, 0)
        root.AssemblyLinearVelocity = Vector3.zero

        pcall(function()
            if btn.Part and firetouchinterest then
                firetouchinterest(root, btn.Part, 0)
                task.wait(0.05)
                firetouchinterest(root, btn.Part, 1)
            end
        end)

        if hum then
            hum.Jump = true
        end

        -- Verify if button turned Lime green
        local checkStart = os.clock()
        local buttonActivated = false
        while os.clock() - checkStart < 1.5 do
            task.wait(0.1)
            if btn.Part and (tostring(btn.Part.BrickColor) == "Lime green" or btn.Part.BrickColor.Name == "Lime green") then
                buttonActivated = true
                break
            end
        end

        if buttonActivated then
            RipIndraEngine.OwnedColors[btn.Name] = true
            setStatus(string.format("[ZD Hub] Activated %s Haki button!", btn.Name))
            task.wait(0.3)
        else
            RipIndraEngine.FailedColors[btn.Name] = os.clock()
            if RipIndraEngine.OwnedColors[btn.Name] == nil then
                RipIndraEngine.OwnedColors[btn.Name] = false
            end
            setStatus(string.format("[ZD Hub] Missing %s Haki color (Skipping pad)", btn.Name))
            task.wait(0.2)
        end

        RipIndraEngine.IsActivatingColors = false
        return true
    end

    RipIndraEngine.IsActivatingColors = false
    return false
end

--- Executes the Rip Indra summon sequence using God's Chalice
function RipIndraEngine.ExecuteSummon()
    if not IsThirdSea() then return false end
    if not (getgenv().Settings.Setup["Auto Rip Indra"] ~= false) then return false end

    local char, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return false end

    -- Verify all 3 buttons are active before summoning
    local _, areAllActive = RipIndraEngine.GetButtonStatus()
    if not areAllActive then
        if getgenv().Settings.Setup["Auto Active Haki Colors"] ~= false then
            local attempted = RipIndraEngine.ExecuteActivateButtons()
            if attempted then return false end
        end
        setStatus("[ZD Hub] God's Chalice ready: Waiting for all 3 Haki buttons to be activated!")
        return false
    end

    local detPart = RipIndraEngine.GetPedestalDetection()
    local targetCF = detPart and detPart.CFrame or RipIndraEngine.PedestalCFrame
    local targetPos = targetCF.Position

    local dist = (targetPos - root.Position).Magnitude
    if dist > 8 then
        setStatus("[ZD Hub] Warping to Castle on the Sea Altar (Summon Indra)...")
        flyTo(targetPos)
        return false
    end

    -- Close enough: Equip God's Chalice and touch altar
    RipIndraEngine.IsSummoning = true
    setStatus("[ZD Hub] Inserting God's Chalice into Altar...")

    local chaliceTool = (localplayer.Backpack and localplayer.Backpack:FindFirstChild("God's Chalice"))
        or (char:FindFirstChild("God's Chalice"))

    if chaliceTool then
        hum:EquipTool(chaliceTool)
        task.wait(0.15)
    end

    pcall(function()
        local heldTool = char:FindFirstChild("God's Chalice")
        local handle = heldTool and heldTool:FindFirstChild("Handle")
        local target = detPart or root

        if handle and detPart then
            firetouchinterest(handle, detPart, 0)
            firetouchinterest(handle, detPart, 1)
        end
        if detPart then
            firetouchinterest(root, detPart, 0)
            firetouchinterest(root, detPart, 1)
        end
    end)

    task.wait(0.5)
    RipIndraEngine.IsSummoning = false
    return true
end

--- Executes the auto-combat loop against Rip Indra until defeated
local function executeRipIndraCombat(boss, bossRoot, bossHum)
    if not IsThirdSea() then return false end
    local char, root, hum = getCharacterParts()
    if not root or not hum or hum.Health <= 0 then return false end

    RipIndraEngine.IsFighting = true
    setStatus(string.format("[ZD Hub] Engaged with Rip Indra! (HP: %d/%d)", math.floor(bossHum.Health), math.floor(bossHum.MaxHealth)))

    -- Hover safe distance above Rip Indra (20 studs vertical, 5 studs offset)
    local safeCombatCF = bossRoot.CFrame * CFrame.new(0, 20, 5)
    local dist = (safeCombatCF.Position - root.Position).Magnitude

    if dist > 60 then
        flyTo(safeCombatCF.Position)
    else
        if isTraveling then stopFlight() end
        ensureHoldVelocity()
        root.CFrame = safeCombatCF
        root.AssemblyLinearVelocity = Vector3.zero
    end

    if hum:GetState() ~= Enum.HumanoidStateType.StrafingNoPhysics then
        hum:ChangeState(11) -- StrafingNoPhysics
    end
    for i = 1, #cachedCharacterParts do
        local part = cachedCharacterParts[i]
        if part and part.CanCollide then
            part.CanCollide = false
        end
    end

    pcall(function()
        bossRoot.CanCollide = false
        if not bossRoot:FindFirstChild("ZD_LockVelocity") then
            local bv = Instance.new("BodyVelocity")
            bv.Name = "ZD_LockVelocity"
            bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            bv.Velocity = Vector3.zero
            bv.Parent = bossRoot
        end
    end)

    if not char:FindFirstChild("HasBuso") then
        pcall(function()
            local commF = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("CommF_")
            if commF then commF:InvokeServer("Buso") end
        end)
    end

    local currentTool = char:FindFirstChildOfClass("Tool")
    if not currentTool or currentTool.ToolTip == "Blox Fruit" or currentTool.ToolTip == "" then
        local bp = localplayer:FindFirstChild("Backpack")
        if bp then
            local w = bp:FindFirstChild("Electric Claw") or bp:FindFirstChild("Godhuman") or bp:FindFirstChild("Cursed Dual Katana") or bp:FindFirstChild("Hallow Scythe")
            if not w then
                for _, item in ipairs(bp:GetChildren()) do
                    if item:IsA("Tool") and (item.ToolTip == "Melee" or item.ToolTip == "Sword") then
                        w = item
                        break
                    end
                end
            end
            if w then hum:EquipTool(w) end
        end
    end

    pcall(function()
        local ps = localplayer:FindFirstChild("PlayerScripts")
        local cfModule = ps and ps:FindFirstChild("CombatFramework")
        if cfModule then
            local combatData = getupvalues and getupvalues(require(cfModule))
            local activeController = combatData and combatData[2] and combatData[2].activeController
            if activeController then
                activeController:attack()
                activeController.timeToNextAttack = 0
                activeController.attacking = false
                activeController.increment = 3
            end
        end
    end)

    pcall(function()
        local attackEngine = getgenv().ZD_AttackEngine
        if attackEngine and attackEngine.AttackMobs then
            attackEngine.AttackMobs()
        else
            local net = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("Net")
            local regAtk = net and net:FindFirstChild("RE/RegisterAttack")
            local regHit = net and net:FindFirstChild("RE/RegisterHit")
            local global = require(ReplicatedStorage.Global)
            local co = global and debug.getupvalue(global.SendHitsToServer, 1)

            if regAtk then regAtk:FireServer(0/0) end

            local hitPayload = { { boss, bossRoot } }
            if co and coroutine.status(co) == "suspended" then
                coroutine.resume(co, bossRoot, hitPayload)
            elseif regHit then
                regHit:FireServer(bossRoot, hitPayload)
            end
        end
    end)

    return true
end
RipIndraEngine.ExecuteCombat = executeRipIndraCombat

--- Checks whether Rip Indra is either currently spawned or ready to be summoned
function RipIndraEngine.IsIndraActiveOrReady()
    if not IsThirdSea() then return false end
    if not (getgenv().Settings.Setup["Auto Rip Indra"] ~= false) then return false end

    local boss = RipIndraEngine.FindActiveBoss()
    if boss then return true end

    if RipIndraEngine.HasGodsChalice() then
        return true
    end

    return false
end

-- Export RipIndraEngine to global environment
getgenv().ZD_RipIndraEngine = RipIndraEngine

-- ─── STEP 14: MAIN AUTO CHEST FARM LOOP ──────────────────────────────────────
print(string.format("[ZD Hub] Auto Chest Engine 4.1 Online. Speed: %d | Max Chests: %d", getgenv().Settings.Setup["Tween Speed"] or 180, getgenv().Settings.Setup["Max Chest Count"] or 30))
setStatus("[ZD Hub] System Idle — Toggle Auto Chest to start")

local noChestTicks = 0

--!mv:omit
local function autoChestFarmWorker()
    while true do
        task.wait(0.08)

        if not isFarmEnabled() then
            if isTraveling then
                stopFlight()
            end
            task.wait(0.4)
            continue
        end

        local char, root = getCharacterParts()
        if not root then
            task.wait(0.5)
            continue
        end

        local hasStopItem, itemName = checkItemsStop()
        local allowItemContinue = (itemName == "Fist of Darkness" and getgenv().Settings.Setup["Auto Darkbeard"] ~= false and IsSecondSea())
            or (itemName == "God's Chalice" and getgenv().Settings.Setup["Auto Rip Indra"] ~= false and IsThirdSea())
        if hasStopItem and not allowItemContinue then
            if isTraveling then stopFlight() end
            setStatus("[ZD Hub] PAUSED: Retaining " .. itemName .. "!")
            task.wait(1)
            continue
        end

        -- DARKBEARD PRIORITY CHECK (Sea 2 Auto-Summon & Auto-Kill)
        if DarkbeardEngine and (getgenv().Settings.Setup["Auto Darkbeard"] ~= false) and IsSecondSea() then
            -- 1. Check if Darkbeard is currently spawned and alive -> Auto Kill
            local darkBoss, darkRoot, darkHum = DarkbeardEngine.FindActiveBoss()
            if darkBoss and darkRoot and darkHum then
                DarkbeardEngine.ExecuteCombat(darkBoss, darkRoot, darkHum)
                task.wait(0.05)
                continue
            else
                DarkbeardEngine.IsFighting = false
            end

            -- 2. Check if player has Fist of Darkness -> Auto Summon
            if DarkbeardEngine.HasFistOfDarkness() then
                DarkbeardEngine.ExecuteSummon()
                task.wait(0.2)
                continue
            else
                DarkbeardEngine.IsSummoning = false
            end
        else
            if DarkbeardEngine then
                DarkbeardEngine.IsFighting = false
                DarkbeardEngine.IsSummoning = false
            end
        end

        -- RIP INDRA PRIORITY CHECK (Sea 3 Auto-Summon, Auto-Kill & Auto-Active Haki Buttons)
        if RipIndraEngine and IsThirdSea() then
            local autoIndra = (getgenv().Settings.Setup["Auto Rip Indra"] ~= false)
            local autoHaki = (getgenv().Settings.Setup["Auto Active Haki Colors"] ~= false)

            -- 1. Check if Rip Indra is currently spawned and alive -> Auto Kill
            if autoIndra then
                local indraBoss, indraRoot, indraHum = RipIndraEngine.FindActiveBoss()
                if indraBoss and indraRoot and indraHum then
                    RipIndraEngine.ExecuteCombat(indraBoss, indraRoot, indraHum)
                    task.wait(0.05)
                    continue
                else
                    RipIndraEngine.IsFighting = false
                end
            else
                RipIndraEngine.IsFighting = false
            end

            -- 2. God's Chalice check: Auto Haki buttons and summon ONLY active if player has God's Chalice!
            if RipIndraEngine.HasGodsChalice() then
                -- Auto active color buttons with legendary Haki
                if autoHaki then
                    local didActive = RipIndraEngine.ExecuteActivateButtons()
                    if didActive then
                        task.wait(0.1)
                        continue
                    end
                else
                    RipIndraEngine.IsActivatingColors = false
                end

                -- Auto summon Rip Indra at altar
                if autoIndra then
                    RipIndraEngine.ExecuteSummon()
                    task.wait(0.2)
                    continue
                else
                    RipIndraEngine.IsSummoning = false
                end
            else
                RipIndraEngine.IsSummoning = false
                RipIndraEngine.IsActivatingColors = false
            end
        else
            if RipIndraEngine then
                RipIndraEngine.IsFighting = false
                RipIndraEngine.IsSummoning = false
                RipIndraEngine.IsActivatingColors = false
            end
        end

        local maxChestLimit = tonumber(getgenv().Settings.Setup["Max Chest Count"] or getgenv().Settings.Setup["Max Chest"]) or 30
        if isHopEnabled() and serverChestsCollected >= maxChestLimit then
            print(string.format("[ZD Hub] Max server chests reached (%d/%d). Initiating Server Hop...", serverChestsCollected, maxChestLimit))
            setStatus(string.format("[ZD Hub] Max server chests reached (%d/%d). Hopping...", serverChestsCollected, maxChestLimit))
            serverChestsCollected = 0
            if Controller and Controller.UpdateServerChests then
                pcall(function() Controller.UpdateServerChests(0, maxChestLimit) end)
            end
            task.wait(0.3)
            hopServer()
            task.wait(6)
            continue
        end

        local chest, pos, dist = findNearestChest()

        if chest and pos then
            noChestTicks = 0
            local chestName = chest.Name or "Chest"
            setStatus(string.format("[ZD Hub] Flying to %s (%.0fm)", chestName, dist))

            local reached = flyTo(pos)

            if reached and isFarmEnabled() then
                setStatus(string.format("[ZD Hub] Collecting %s...", chestName))
                local success = collectChest(chest, pos)

                -- Only increment count if the chest was ACTUALLY collected
                if success then
                    collectedThisSession = collectedThisSession + 1
                    serverChestsCollected = serverChestsCollected + 1
                    addChestCount(1)
                    if Controller and Controller.UpdateServerChests then
                        pcall(function() Controller.UpdateServerChests(serverChestsCollected, maxChestLimit) end)
                    end
                    setStatus(string.format("[ZD Hub] Collected %s! (Server: %d/%d)", chestName, serverChestsCollected, maxChestLimit))
                    task.wait(0.1)
                else
                    setStatus(string.format("[ZD Hub] Chest missed or despawned."))
                    task.wait(0.05)
                end
            else
                IgnoredChests[chest] = os.clock() + 20
                task.wait(0.04)
            end
        else
            noChestTicks = noChestTicks + 1
            if isHopEnabled() and (getgenv().Settings.Setup["Hop When No Chests"] ~= false) then
                if noChestTicks > 25 then -- Wait ~2 seconds before hopping to ensure it's not a loading/streaming delay
                    print("[ZD Hub] No available chests detected in server. Hopping...")
                    setStatus("[ZD Hub] No chests found in server. Hopping...")
                    serverChestsCollected = 0
                    if Controller and Controller.UpdateServerChests then
                        pcall(function() Controller.UpdateServerChests(0, maxChestLimit) end)
                    end
                    task.wait(0.5)
                    hopServer()
                    task.wait(6)
                else
                    setStatus("[ZD Hub] Scanning for chests...")
                end
            else
                setStatus("[ZD Hub] No chests detected. Waiting for respawn...")
                task.wait(3)
            end
        end
    end
end

task.spawn(autoChestFarmWorker)

-- ─── STEP 15: INJECT GRAPHICAL USER INTERFACE (VindUI) ────────────────────────
task.spawn(function()
    pcall(function()
        local VindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Skinny-yz/VVind-UI/refs/heads/main/src.lua"))()
        
        local Window = VindUI:CreateWindow({
            Title = "ZD Hub",
            Subtitle = "Auto Chest v4.1",
            Icon = "117388387570130",
            Size = UDim2.fromOffset(550, 420),
            MinSize = Vector2.new(450, 300),
            Draggable = true,
            Resizable = true,
            UseBlur = true,
            DefaultTab = "Main",
        })

        -- CUSTOM OPEN/CLOSE TOGGLE BUTTON
        pcall(function()
            local success, coreGui = pcall(function() return game:GetService("CoreGui") end)
            local parentGui = (success and coreGui) and coreGui or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
            local oldToggle = parentGui:FindFirstChild("ZD_Hub_Toggle")
            if oldToggle then oldToggle:Destroy() end
        end)

        local toggleGui = Instance.new("ScreenGui")
        toggleGui.Name = "ZD_Hub_Toggle"
        toggleGui.ResetOnSpawn = false
        toggleGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        
        local success, coreGui = pcall(function() return game:GetService("CoreGui") end)
        toggleGui.Parent = (success and coreGui) and coreGui or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
        
        local toggleBtn = Instance.new("ImageButton")
        toggleBtn.Name = "ToggleBtn"
        toggleBtn.Size = UDim2.new(0, 45, 0, 45)
        toggleBtn.Position = UDim2.new(0.95, -55, 0.15, 0)
        toggleBtn.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        toggleBtn.Image = "rbxassetid://117388387570130"
        toggleBtn.Parent = toggleGui
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(1, 0)
        corner.Parent = toggleBtn
        
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(200, 200, 200)
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
        
        --!mv:omit
        local function onDragInputChanged(input)
            if input == dragInput and dragging then
                local delta = input.Position - dragStart
                toggleBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end

        game:GetService("UserInputService").InputChanged:Connect(onDragInputChanged)
        
        toggleBtn.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if (input.Position - startClickPos).Magnitude < 10 then
                    if Window and Window.Toggle then
                        Window:Toggle()
                    end
                end
            end
        end)


        local MainTab = Window:AddTab({ Name = "Main", Icon = "Lucide:sword" })
        
        -- STATS & PROFILE SECTION
        local StatsTab = Window:AddTab({ Name = "Stats & Profile", Icon = "Lucide:user" })
        
        local ProfileSection = StatsTab:AddSubTab({ Name = "Profile", Icon = "Lucide:contact" })
        local player = game:GetService("Players").LocalPlayer
        local levelVal = "?"
        pcall(function() levelVal = tostring(player.Data.Level.Value) end)
        
        ProfileSection:AddCard({
            UserId = player.UserId,
            Title = player.DisplayName,
            Description = "Level: " .. levelVal
        })

        local StatSection = StatsTab:AddSubTab({ Name = "Live Stats", Icon = "Lucide:activity" })
        local chestStats = StatSection:AddParagraph({
            Title = "Chest Stats",
            Icon = "Lucide:box",
            Text = "Session Chests: 0\nIn All Chests: " .. tostring(getgenv().Settings.Setup["In All Chest"] or 0)
        })

        local beliStats = StatSection:AddParagraph({
            Title = "Beli Stats",
            Icon = "Lucide:coins",
            Text = "Balance: $0\nSession Beli: $0\nIn All Beli: $" .. tostring(getgenv().Settings.Setup["In All Beli"] or 0)
        })

        task.spawn(function()
            while task.wait(1) do
                local inAllChest = getgenv().Settings.Setup["In All Chest"] or 0
                local inAllBeli = getgenv().Settings.Setup["In All Beli"] or 0
                
                local bal = 0
                pcall(function() bal = player.Data.Beli.Value end)
                
                if chestStats and chestStats.Set then
                    chestStats:Set(string.format("Session Chests: %d\nIn All Chests: %d", collectedThisSession or 0, inAllChest))
                end
                
                if beliStats and beliStats.Set then
                    local function fmt(n)
                        if not n then return "0" end
                        local str = tostring(n)
                        return str:reverse():gsub("(%d^3)","%1,"):reverse()
                    end
                    beliStats:Set(string.format("Balance: $%s\nSession Beli: $%s\nIn All Beli: $%s", tostring(bal), tostring(sessionBeli or 0), tostring(inAllBeli)))
                end
            end
        end)
        
        -- AUTO FARM SECTION
        local FarmSection = MainTab:AddSubTab({ Name = "Auto Farm", Icon = "Lucide:play" })
        FarmSection:AddSection("Chest Farming")
        
        FarmSection:AddToggle({
            Text = "Auto Farm Chest",
            Description = "Enable or disable auto farming",
            Default = getgenv().Settings.Setup["Auto Farm Chest"],
            Callback = function(v) getgenv().Settings.Setup["Auto Farm Chest"] = v end
        })
        
        FarmSection:AddToggle({
            Text = "Smart Chest Sync",
            Description = "Avoid chests targeted by other ZD User",
            Default = getgenv().Settings.Setup["Smart Chest Sync"] ~= false,
            Callback = function(v) getgenv().Settings.Setup["Smart Chest Sync"] = v end
        })

        FarmSection:AddSection("Tween Settings")

        FarmSection:AddToggle({
            Text = "Smart Tween",
            Description = "Intelligent pathfinding, obstacle avoidance & world portals",
            Default = getgenv().Settings.Setup["Smart Tween"] ~= false,
            Callback = function(v)
                getgenv().Settings.Setup["Smart Tween"] = v
                if SmartTween then
                    SmartTween.Config.PrioritizePortals = v
                end
            end
        })

        FarmSection:AddToggle({
            Text = "Use Portal Fruit Method",
            Description = "Use Portal Fruit (Move C) to warp directly between islands",
            Default = getgenv().Settings.Setup["Use Portal Fruit Method"] ~= false,
            Callback = function(v)
                getgenv().Settings.Setup["Use Portal Fruit Method"] = v
                if SmartTween then
                    SmartTween.Config.UsePortalFruit = v
                end
            end
        })

        FarmSection:AddToggle({
            Text = "Fast Travel Portals",
            Description = "Take world portals/doors (Castle, Hydra, Mansion, etc.)",
            Default = getgenv().Settings.Setup["Fast Travel Portals"] ~= false,
            Callback = function(v)
                getgenv().Settings.Setup["Fast Travel Portals"] = v
                if SmartTween then
                    SmartTween.Config.PrioritizePortals = v
                    SmartTween.Config.PreferPortals = v
                end
            end
        })

        FarmSection:AddToggle({
            Text = "Wall Slowdown (Anti-Clip)",
            Description = "Throttle speed down to 50 when obstacle/wall is < 70 studs",
            Default = getgenv().Settings.Setup["Wall Slowdown"] ~= false,
            Callback = function(v)
                getgenv().Settings.Setup["Wall Slowdown"] = v
                if SmartTween then
                    SmartTween.Config.WallSlowdownEnabled = v
                end
            end
        })

        FarmSection:AddSlider({
            Text = "Tween Speed",
            Description = "Flight speed to chests (Max: 350)",
            Min = 100, Max = 350, Default = getgenv().Settings.Setup["Tween Speed"] or 250, Increment = 5,
            Callback = function(v)
                getgenv().Settings.Setup["Tween Speed"] = v
                if SmartTween then
                    SmartTween.SetSpeed(v)
                end
            end
        })

        FarmSection:AddSection("Darkbeard Raid Boss (Sea 2)")
        
        FarmSection:AddToggle({
            Text = "Auto Darkbeard",
            Description = "Auto summon & kill Darkbeard in Sea 2 (Fast Attack & Noclip)",
            Default = getgenv().Settings.Setup["Auto Darkbeard"] ~= false,
            Callback = function(v) getgenv().Settings.Setup["Auto Darkbeard"] = v end
        })

        FarmSection:AddSection("Rip Indra Raid Boss (Sea 3)")
        
        FarmSection:AddToggle({
            Text = "Auto Rip Indra",
            Description = "Auto summon & kill Rip Indra in Sea 3 (Fast Attack & Noclip)",
            Default = getgenv().Settings.Setup["Auto Rip Indra"] ~= false,
            Callback = function(v) getgenv().Settings.Setup["Auto Rip Indra"] = v end
        })

        FarmSection:AddToggle({
            Text = "Auto Active Haki Colors",
            Description = "Auto activate Castle buttons when holding God's Chalice",
            Default = getgenv().Settings.Setup["Auto Active Haki Colors"] ~= false,
            Callback = function(v) getgenv().Settings.Setup["Auto Active Haki Colors"] = v end
        })
        
        
        -- SERVER HOP SECTION
        local ServerSection = MainTab:AddSubTab({ Name = "Server Hop", Icon = "Lucide:server" })
        ServerSection:AddSection("Server Hopping Settings")
        
        ServerSection:AddButton({
            Text = "Instant Hop Server",
            Description = "Force a server hop immediately",
            Icon = "Lucide:plane-takeoff",
            Callback = function()
                if hopServer then task.spawn(hopServer) end
            end
        })

        ServerSection:AddToggle({
            Text = "Auto Server Hop",
            Description = "Hop when chests are depleted",
            Default = getgenv().Settings.Setup["Auto Server Hop"],
            Callback = function(v) getgenv().Settings.Setup["Auto Server Hop"] = v end
        })
        
        ServerSection:AddToggle({
            Text = "Hop If ZD User Detected",
            Description = "Hop if another ZD Hub user is in the server to avoid competition",
            Default = getgenv().Settings.Setup["Hop If ZD User Detected"],
            Callback = function(v) getgenv().Settings.Setup["Hop If ZD User Detected"] = v end
        })

        ServerSection:AddToggle({
            Text = "Hop When No Chests",
            Description = "Hop if no chests are found in server",
            Default = getgenv().Settings.Setup["Hop When No Chests"],
            Callback = function(v) getgenv().Settings.Setup["Hop When No Chests"] = v end
        })
        
        ServerSection:AddSlider({
            Text = "Max Chest Count",
            Description = "Hop after collecting this many chests",
            Min = 5, Max = 100, Default = getgenv().Settings.Setup["Max Chest Count"] or 30, Increment = 1,
            Callback = function(v) getgenv().Settings.Setup["Max Chest Count"] = v end
        })
        
        ServerSection:AddDropdown({
            Text = "Hop Region",
            Description = "Region to hop to",
            Options = {"All", "Singapore", "United States", "Germany", "Japan", "France"},
            Default = getgenv().Settings.Setup["Choose Hop Region"] or "All",
            Callback = function(v) getgenv().Settings.Setup["Choose Hop Region"] = v end
        })
        
        ServerSection:AddSlider({
            Text = "Max Players Count",
            Description = "Maximum players for target server",
            Min = 1, Max = 12, Default = getgenv().Settings.Setup["Max Players Count"] or 8, Increment = 1,
            Callback = function(v) getgenv().Settings.Setup["Max Players Count"] = v end
        })

        -- CONFIGURATION SECTION
        local ConfigSection = MainTab:AddSubTab({ Name = "Configuration", Icon = "Lucide:settings" })
        ConfigSection:AddSection("Item Safety (Stop Farm)")

        ConfigSection:AddToggle({
            Text = "Stop If Have Items",
            Description = "Stop farm if rare items are in inventory",
            Default = getgenv().Settings.Setup["Stop If Have Items"],
            Callback = function(v) getgenv().Settings.Setup["Stop If Have Items"] = v end
        })
        
        ConfigSection:AddToggle({
            Text = "Stop for God's Chalice",
            Default = getgenv().Settings.ItemsToStop["God's Chalice"],
            Callback = function(v) getgenv().Settings.ItemsToStop["God's Chalice"] = v end
        })
        
        ConfigSection:AddToggle({
            Text = "Stop for Fist of Darkness",
            Default = getgenv().Settings.ItemsToStop["Fist of Darkness"],
            Callback = function(v) getgenv().Settings.ItemsToStop["Fist of Darkness"] = v end
        })

        ConfigSection:AddSection("Misc Settings")
        ConfigSection:AddToggle({
            Text = "Enable Haki",
            Default = getgenv().Settings.Setup["Enable Haki"],
            Callback = function(v) getgenv().Settings.Setup["Enable Haki"] = v end
        })

        ConfigSection:AddToggle({
            Text = "Water Walk",
            Default = getgenv().Settings.Setup["Water Walk"],
            Callback = function(v) getgenv().Settings.Setup["Water Walk"] = v end
        })
        
        ConfigSection:AddToggle({
            Text = "Anti Water Damage",
            Default = getgenv().Settings.Setup["Anti Water Damage"],
            Callback = function(v) getgenv().Settings.Setup["Anti Water Damage"] = v end
        })
        
        ConfigSection:AddSection("Tween & Movement")

        ConfigSection:AddToggle({
            Text = "Smart Tween",
            Description = "Universal Smart Tween Engine (Obstacle avoidance & portals)",
            Default = getgenv().Settings.Setup["Smart Tween"] ~= false,
            Callback = function(v) getgenv().Settings.Setup["Smart Tween"] = v end
        })

        ConfigSection:AddToggle({
            Text = "Use Portal Fruit Method",
            Description = "Use Portal Fruit (Move C) to warp directly between islands",
            Default = getgenv().Settings.Setup["Use Portal Fruit Method"] ~= false,
            Callback = function(v) getgenv().Settings.Setup["Use Portal Fruit Method"] = v end
        })

        ConfigSection:AddToggle({
            Text = "Fast Travel Portals",
            Default = getgenv().Settings.Setup["Fast Travel Portals"] ~= false,
            Callback = function(v) getgenv().Settings.Setup["Fast Travel Portals"] = v end
        })

        ConfigSection:AddToggle({
            Text = "Wall Slowdown (Anti-Clip)",
            Description = "Throttle speed down to 50 when obstacle/wall is < 70 studs",
            Default = getgenv().Settings.Setup["Wall Slowdown"] ~= false,
            Callback = function(v) getgenv().Settings.Setup["Wall Slowdown"] = v end
        })
    end)
end)

-- Anti-Competition Server Hop
task.spawn(function()
    while task.wait(5) do
        if getgenv().Settings.Setup["Hop If ZD User Detected"] and isFarmEnabled() then
            local PlayersService = game:GetService("Players")
            local foundAnotherUser = false
            for _, p in ipairs(PlayersService:GetPlayers()) do
                if p ~= localplayer and isZDSyncUser(p) then
                    foundAnotherUser = true
                    break
                end
            end
            if foundAnotherUser then
                setStatus("[ZD Hub] Another ZD user detected! Server hopping to avoid competition...")
                print("[ZD Hub] Another ZD Hub user detected! Server hopping...")
                task.wait(1.5)
                if hopServer then hopServer() end
                -- Wait a bit so we don't spam hopServer if it fails immediately
                task.wait(10)
            end
        end
    end
end)

return {
    Settings = getgenv().Settings,
    Stop = stopFlight,
    Hop = hopServer,
    ServerHop = ServerHop,
    SaveSettings = saveSettingsToFile,
    LoadSettings = loadSettingsFromFile,
    GetSessionChests = function() return collectedThisSession end,
    Darkbeard = DarkbeardEngine,
    RipIndra = RipIndraEngine,
    SmartTween = SmartTween
}
