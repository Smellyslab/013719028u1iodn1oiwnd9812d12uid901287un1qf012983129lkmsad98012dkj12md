---------------------------------------------------------------------
-- AUTO-ATTACH SYSTEM (Infinite Yield Style)
---------------------------------------------------------------------
-- IMPORTANT: Save this script URL for auto-execute in your executor
local SCRIPT_URL = 'YOUR_SCRIPT_URL_HERE' -- Replace with your actual script URL

-- Prevent multiple instances from running
if getgenv().INSTAKILL_LOADED then
    warn("[Instakill]: Script is already running! Stopping duplicate instance.")
    return
end

-- Mark script as loaded globally
getgenv().INSTAKILL_LOADED = true

-- Wait for game to fully load
if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- Auto-reattach function for server hops and teleports
local function setupAutoReattach()
    -- Try to get the queue_on_teleport function (different executors use different names)
    local queueteleport = queue_on_teleport or 
                         syn and syn.queue_on_teleport or 
                         fluxus and fluxus.queue_on_teleport
    
    if queueteleport then
        -- This code will execute when you teleport/server hop
        queueteleport([[
            -- Wait for game to fully load
            repeat task.wait() until game:IsLoaded()
            task.wait(3) -- Extra wait for stability
            
            -- Clear the loaded flag so script can run again
            if getgenv then
                getgenv().INSTAKILL_LOADED = nil
            end
            
            -- Reload the script from URL
            local success, result = pcall(function()
                return game:HttpGet(']]..SCRIPT_URL..[[')
            end)
            
            if success then
                local loadSuccess, loadError = pcall(function()
                    loadstring(result)()
                end)
                if not loadSuccess then
                    warn("[Instakill Auto-Load]: Failed to execute script: " .. tostring(loadError))
                end
            else
                warn("[Instakill Auto-Load]: Failed to fetch script: " .. tostring(result))
            end
        ]])
        print("[Instakill]: ✅ Auto-reattach enabled! Script will reload on server hop/teleport.")
    else
        warn("[Instakill]: ⚠️ Auto-reattach not supported on this executor.")
        warn("[Instakill]: You'll need to manually add this to your executor's autoexec folder.")
    end
end

-- Call auto-reattach setup
setupAutoReattach()

-- Also set up a connection for when player teleports
game:GetService("Players").LocalPlayer.OnTeleport:Connect(function(State)
    if State == Enum.TeleportState.Started then
        print("[Instakill]: Teleport detected, queueing script reload...")
        setupAutoReattach()
    end
end)

---------------------------------------------------------------------
-- Required services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local COREGUI = game:GetService("CoreGui")

-- Global toggles and variables
ESPenabled = false
teleportForAll = false  -- default toggle (set via UI)
local teleportTime = 5  -- Default time (in seconds) to stick behind each target
local teleportDistance = 1.5  -- Default distance behind target (in studs)
local whitelistedPlayers = {}  -- table of players (by Name) to skip teleporting to
isTeleportLoopActive = false -- Track if teleport loop is running
selectedPlayer = nil -- Store selected player for both whitelist and safety TP

---------------------------------------------------------------------
-- CUSTOM THEME TABLE (Dark Blue with Golden Yellow Accents)
---------------------------------------------------------------------
local DarkBlueGoldTheme = {
    TextColor = Color3.fromRGB(255, 215, 0),  -- Golden yellow text
    Background = Color3.fromRGB(10, 10, 30),   -- Very dark blue background
    Topbar = Color3.fromRGB(20, 20, 50),
    Shadow = Color3.fromRGB(0, 0, 0),

    NotificationBackground = Color3.fromRGB(15, 15, 40),
    NotificationActionsBackground = Color3.fromRGB(30, 30, 60),

    TabBackground = Color3.fromRGB(20, 20, 40),
    TabStroke = Color3.fromRGB(50, 50, 80),
    TabBackgroundSelected = Color3.fromRGB(30, 30, 70),
    TabTextColor = Color3.fromRGB(255, 215, 0),
    SelectedTabTextColor = Color3.fromRGB(255, 255, 255),

    ElementBackground = Color3.fromRGB(15, 15, 35),
    ElementBackgroundHover = Color3.fromRGB(25, 25, 55),
    SecondaryElementBackground = Color3.fromRGB(10, 10, 30),
    ElementStroke = Color3.fromRGB(40, 40, 70),
    SecondaryElementStroke = Color3.fromRGB(30, 30, 60),
            
    SliderBackground = Color3.fromRGB(15, 15, 45),
    SliderProgress = Color3.fromRGB(15, 15, 45),
    SliderStroke = Color3.fromRGB(50, 50, 80),

    ToggleBackground = Color3.fromRGB(20, 20, 40),
    ToggleEnabled = Color3.fromRGB(255, 215, 0),
    ToggleDisabled = Color3.fromRGB(100, 100, 130),
    ToggleEnabledStroke = Color3.fromRGB(220, 190, 0),
    ToggleDisabledStroke = Color3.fromRGB(80, 80, 110),
    ToggleEnabledOuterStroke = Color3.fromRGB(150, 150, 180),
    ToggleDisabledOuterStroke = Color3.fromRGB(50, 50, 70),

    DropdownSelected = Color3.fromRGB(25, 25, 50),
    DropdownUnselected = Color3.fromRGB(15, 15, 35),

    InputBackground = Color3.fromRGB(20, 20, 40),
    InputStroke = Color3.fromRGB(60, 60, 90),
    PlaceholderColor = Color3.fromRGB(200, 200, 200)
}

---------------------------------------------------------------------
-- SCRIPT SETUP & LOGGING FUNCTION
---------------------------------------------------------------------
local function log(message)
    print("[Instakill LOG]: " .. message)
end

---------------------------------------------------------------------
-- TEAM UTILITY FUNCTIONS
---------------------------------------------------------------------
local function getPlayerTeamName(player)
    if player and player.Team then
        return player.Team.Name
    end
    return "No Team"
end

local function getAllTeams()
    local teams = {}
    local teamNames = {}
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Team then
            local teamName = player.Team.Name
            if not teams[teamName] then
                teams[teamName] = {
                    name = teamName,
                    color = player.Team.TeamColor,
                    players = {}
                }
                table.insert(teamNames, teamName)
            end
            table.insert(teams[teamName].players, player.Name)
        end
    end
    
    return teams, teamNames
end

local function printTeamInfo()
    log("=== TEAM ANALYSIS ===")
    local localPlayer = Players.LocalPlayer
    local myTeam = getPlayerTeamName(localPlayer)
    log("Your Team: " .. myTeam)
    
    local teams, teamNames = getAllTeams()
    
    if #teamNames == 0 then
        log("No teams found in this game!")
        return teams, teamNames
    end
    
    for _, teamName in ipairs(teamNames) do
        local team = teams[teamName]
        log("Team: " .. teamName .. " | Players: " .. table.concat(team.players, ", "))
    end
    
    log("=== END TEAM ANALYSIS ===")
    return teams, teamNames
end

local function whitelistTeam(teamName)
    local teams, _ = getAllTeams()
    local team = teams[teamName]
    
    if not team then
        log("ERROR: Team '" .. teamName .. "' not found!")
        return false, 0
    end
    
    local count = 0
    for _, playerName in ipairs(team.players) do
        if playerName ~= Players.LocalPlayer.Name then
            whitelistedPlayers[playerName] = true
            count = count + 1
            log("Whitelisted: " .. playerName .. " (Team: " .. teamName .. ")")
        end
    end
    
    return true, count
end

---------------------------------------------------------------------
-- SAFELY LOAD RAYFIELD UI LIBRARY
---------------------------------------------------------------------
local function loadRayfieldUI()
    log("Attempting to load Rayfield UI library from https://sirius.menu/rayfield ...")
    local success, response = pcall(function()
        return game:HttpGet("https://sirius.menu/rayfield")
    end)

    if not success then
        if string.find(tostring(response), "429") then
            log("ERROR: Rayfield request returned 429 (Too Many Requests). You may be rate-limited. Try again later.")
        else
            log("ERROR: Failed to load Rayfield UI library: " .. tostring(response))
        end
        return nil
    end

    local func, loadErr = loadstring(response)
    if not func then
        log("ERROR: Could not compile Rayfield UI library: " .. tostring(loadErr))
        return nil
    end

    local success2, Rayfield = pcall(func)
    if not success2 then
        log("ERROR: Could not run Rayfield UI library: " .. tostring(Rayfield))
        return nil
    end

    log("Rayfield UI library loaded successfully.")
    return Rayfield
end

-- Helper function: returns the primary part (usually HumanoidRootPart) of a character.
local function getRoot(character)
    return character:FindFirstChild("HumanoidRootPart")
end

---------------------------------------------------------------------
-- TELEPORT LOOP FUNCTION (MODIFIED)
---------------------------------------------------------------------
local function teleportLoop()
    isTeleportLoopActive = true
    local localPlayer = Players.LocalPlayer
    if not localPlayer then
        log("ERROR: LocalPlayer not found! Possibly not in a game or not fully loaded.")
        isTeleportLoopActive = false
        return
    end

    -- Log the local player's team.
    local myTeam = getPlayerTeamName(localPlayer)
    log("[ALERT]: Current Team: {" .. myTeam .. "}")

    -- Safely get the local player's character with a timeout.
    local charTimeout = 5
    local character
    do
        local successChar, result = pcall(function()
            return localPlayer.Character or localPlayer.CharacterAdded:Wait(charTimeout)
        end)
        if not successChar or not result then
            log("WARNING: Could not get local player's character within " .. charTimeout .. " seconds. Stopping script.")
            isTeleportLoopActive = false
            return
        end
        character = result
    end

    local root = getRoot(character)
    if not root then
        log("ERROR: HumanoidRootPart not found in local character!")
        isTeleportLoopActive = false
        return
    end

    log("Teleport loop started. Saving original position...")
    local originalCFrame = root.CFrame

    -- Build a list of target players (skipping whitelisted ones).
    local targetPlayers = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= localPlayer and not whitelistedPlayers[plr.Name] then
            if teleportForAll then
                table.insert(targetPlayers, plr)
                log("Player added: " .. plr.Name .. " (Team: " .. getPlayerTeamName(plr) .. ")")
            else
                if plr.Team and localPlayer.Team and plr.Team ~= localPlayer.Team then
                    table.insert(targetPlayers, plr)
                    log("Enemy player found: " .. plr.Name .. " (Team: " .. getPlayerTeamName(plr) .. ")")
                else
                    log("Skipping teammate/neutral player: " .. plr.Name .. " (Team: " .. getPlayerTeamName(plr) .. ")")
                end
            end
        elseif whitelistedPlayers[plr.Name] then
            log("Skipping whitelisted player: " .. plr.Name .. " (Team: " .. getPlayerTeamName(plr) .. ")")
        end
    end

    if #targetPlayers == 0 then
        log("No target players found. Either you're alone, all players are whitelisted, or no enemies are present.")
        isTeleportLoopActive = false
        return
    end

    -- Loop through each target player.
    while isTeleportLoopActive do
        for i, target in ipairs(targetPlayers) do
            if not isTeleportLoopActive then break end
            local targetChar = target.Character
            if targetChar then
                local targetRoot = getRoot(targetChar)
                if targetRoot then
                    local targetHumanoid = targetChar:FindFirstChildOfClass("Humanoid")
                    if not targetHumanoid then
                        log("Target " .. target.Name .. " has no Humanoid. Skipping...")
                        if i == #targetPlayers then break end
                    elseif targetHumanoid.Health <= 0 then
                        log("[ALERT]: Skipping target: \"" .. target.Name .. "\" due to low health (" .. tostring(targetHumanoid.Health) .. ").")
                        if i == #targetPlayers then break end
                    else
                        local targetTeam = getPlayerTeamName(target)
                        log("[ALERT]: Teleporting behind target: \"" .. target.Name .. "\" {TEAM: \"" .. targetTeam .. "\"} with Health: " .. tostring(targetHumanoid.Health))
                        local startTime = tick()
                        while tick() - startTime < teleportTime and isTeleportLoopActive do
                            if targetHumanoid.Health <= 0 then
                                log("[ALERT]: Target \"" .. target.Name .. "\" died mid-teleport (Health: " .. tostring(targetHumanoid.Health) .. "). Moving to next target.")
                                break
                            end
                            -- Use the adjustable teleportDistance variable
                            local targetPos = targetRoot.Position - targetRoot.CFrame.LookVector * teleportDistance
                            local newCFrame = CFrame.new(targetPos, targetRoot.Position)
                            root.CFrame = newCFrame
                            task.wait(0.03)
                        end
                    end
                else
                    log("Target " .. target.Name .. " has no HumanoidRootPart. Skipping...")
                    if i == #targetPlayers then break end
                end
            else
                log("Target " .. target.Name .. " has no character loaded. Skipping...")
                if i == #targetPlayers then break end
            end
        end
        task.wait()
    end

    log("Returning to original position...")
    root.CFrame = originalCFrame
    isTeleportLoopActive = false
    log("Teleport loop ended.")
end

---------------------------------------------------------------------
-- ESP FUNCTION (for each player)
---------------------------------------------------------------------
function ESP(plr)
    task.spawn(function()
        for i, v in pairs(COREGUI:GetChildren()) do
            if v.Name == plr.Name..'_ESP' then
                v:Destroy()
            end
        end
        wait()
        if plr.Character and plr.Name ~= Players.LocalPlayer.Name and not COREGUI:FindFirstChild(plr.Name..'_ESP') then
            local ESPholder = Instance.new("Folder")
            ESPholder.Name = plr.Name..'_ESP'
            ESPholder.Parent = COREGUI
            repeat wait(1) until plr.Character and getRoot(plr.Character) and plr.Character:FindFirstChildOfClass("Humanoid")
            for b, n in pairs(plr.Character:GetChildren()) do
                if n:IsA("BasePart") then
                    local a = Instance.new("BoxHandleAdornment")
                    a.Name = plr.Name
                    a.Parent = ESPholder
                    a.Adornee = n
                    a.AlwaysOnTop = true
                    a.ZIndex = 10
                    a.Size = n.Size
                    a.Transparency = 0.5
                    a.Color = plr.TeamColor
                end
            end
            if plr.Character and plr.Character:FindFirstChild('Head') then
                local BillboardGui = Instance.new("BillboardGui")
                local TextLabel = Instance.new("TextLabel")
                BillboardGui.Adornee = plr.Character.Head
                BillboardGui.Name = plr.Name
                BillboardGui.Parent = ESPholder
                BillboardGui.Size = UDim2.new(0, 100, 0, 150)
                BillboardGui.StudsOffset = Vector3.new(0, 1, 0)
                BillboardGui.AlwaysOnTop = true
                TextLabel.Parent = BillboardGui
                TextLabel.BackgroundTransparency = 1
                TextLabel.Position = UDim2.new(0, 0, 0, -50)
                TextLabel.Size = UDim2.new(0, 100, 0, 100)
                TextLabel.Font = Enum.Font.SourceSansSemibold
                TextLabel.TextSize = 20
                TextLabel.TextColor3 = Color3.new(1, 1, 1)
                TextLabel.TextStrokeTransparency = 0
                TextLabel.TextYAlignment = Enum.TextYAlignment.Bottom
                TextLabel.Text = 'Name: '..plr.Name..' | Health: '..math.floor(plr.Character:FindFirstChildOfClass('Humanoid').Health)
                TextLabel.ZIndex = 10
                local espLoopFunc
                local teamChange
                local addedFunc
                addedFunc = plr.CharacterAdded:Connect(function()
                    if ESPenabled then
                        espLoopFunc:Disconnect()
                        teamChange:Disconnect()
                        ESPholder:Destroy()
                        repeat wait(1) until getRoot(plr.Character) and plr.Character:FindFirstChildOfClass("Humanoid")
                        ESP(plr)
                        addedFunc:Disconnect()
                    else
                        teamChange:Disconnect()
                        addedFunc:Disconnect()
                    end
                end)
                teamChange = plr:GetPropertyChangedSignal("TeamColor"):Connect(function()
                    if ESPenabled then
                        espLoopFunc:Disconnect()
                        addedFunc:Disconnect()
                        ESPholder:Destroy()
                        repeat wait(1) until getRoot(plr.Character) and plr.Character:FindFirstChildOfClass("Humanoid")
                        ESP(plr)
                        teamChange:Disconnect()
                    else
                        teamChange:Disconnect()
                    end
                end)
                local function espLoop()
                    if COREGUI:FindFirstChild(plr.Name..'_ESP') then
                        if plr.Character 
                           and getRoot(plr.Character) 
                           and plr.Character:FindFirstChildOfClass("Humanoid") 
                           and Players.LocalPlayer.Character 
                           and getRoot(Players.LocalPlayer.Character) 
                           and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid") then
                            TextLabel.Text = 'Name: '..plr.Name..' | Health: '..math.floor(plr.Character:FindFirstChildOfClass('Humanoid').Health)
                        end
                    else
                        teamChange:Disconnect()
                        addedFunc:Disconnect()
                        espLoopFunc:Disconnect()
                    end
                end
                espLoopFunc = RunService.RenderStepped:Connect(espLoop)
            end
        end
    end)
end

---------------------------------------------------------------------
-- MAIN EXECUTION FLOW WITH RAYFIELD UI (NO KEY SYSTEM)
---------------------------------------------------------------------
local Rayfield = loadRayfieldUI()
if not Rayfield then
    log("ERROR: Rayfield was not loaded. The script will stop here.")
    return
end

local Window = Rayfield:CreateWindow({
    Name = "Instakill {1.8} -- Made by smelly0001",
    Icon = 0,
    LoadingTitle = "Instakill {v1.8} - made by smelly0001",
    LoadingSubtitle = "Auto-Attach Edition",
    Theme = DarkBlueGoldTheme,
    DisableRayfieldPrompts = false,
    DisableBuildWarnings = false,
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "RayfieldConfigs",
        FileName = "Instakill"
    },
    Discord = {
        Enabled = false,
        Invite = "noinvitelink",
        RememberJoins = true
    }
})

if not Window then
    log("ERROR: Failed to create Rayfield window! Aborting.")
    return
end

log("Rayfield window created successfully.")

---------------------------------------------------------------------
-- MAIN TAB
---------------------------------------------------------------------
local MainTab = Window:CreateTab("Main", 4483362458)
if not MainTab then
    log("ERROR: Failed to create Main tab! Aborting.")
    return
end

log("Main tab created successfully.")

local MainSection = MainTab:CreateSection("Teleport Loop Options")

-- New teleport distance slider in Main tab
MainTab:CreateSlider({
    Name = "Teleport Distance",
    Range = {0.5, 10},
    Increment = 0.1,
    Suffix = " studs",
    CurrentValue = 1.5,
    Flag = "TeleportDistanceSlider",
    Callback = function(Value)
        teleportDistance = Value
        log("Teleport distance set to " .. tostring(Value) .. " studs")
    end,
})

---------------------------------------------------------------------
-- WHITELIST TAB (Modified)
---------------------------------------------------------------------
local WhitelistTab = Window:CreateTab("Whitelist", 987654321)
local playerDropdown

-- Function to get all player names
local function getAllPlayerNames()
    local names = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= Players.LocalPlayer then
            table.insert(names, plr.Name)
        end
    end
    return names
end

-- Create the unified dropdown
local function createPlayerDropdown()
    playerDropdown = WhitelistTab:CreateDropdown({
        Name = "Select Player",
        Options = getAllPlayerNames(),
        CurrentOption = "Select a player",
        MultiSelection = false,
        Flag = "PlayerDropdown",
        Callback = function(Option)
            selectedPlayer = typeof(Option) == "table" and Option[1] or tostring(Option)
        end,
    })
end

-- Initial dropdown creation
createPlayerDropdown()

local WhitelistSection = WhitelistTab:CreateSection("Player Management")

-- Buttons
WhitelistTab:CreateButton({
    Name = "Add to Whitelist",
    Callback = function()
        if selectedPlayer and selectedPlayer ~= "Select a player" then
            whitelistedPlayers[selectedPlayer] = true
            log("Added " .. selectedPlayer .. " to whitelist.")
            Rayfield:Notify({
                Title = "Whitelist",
                Content = selectedPlayer .. " has been added to the whitelist.",
                Duration = 3,
                Type = "Success"
            })
        else
            Rayfield:Notify({
                Title = "Error",
                Content = "Please select a valid player.",
                Duration = 3,
                Type = "Error"
            })
        end
    end,
})

WhitelistTab:CreateButton({
    Name = "Remove from Whitelist",
    Callback = function()
        if selectedPlayer and selectedPlayer ~= "Select a player" then
            if whitelistedPlayers[selectedPlayer] then
                whitelistedPlayers[selectedPlayer] = nil
                log("Removed " .. selectedPlayer .. " from whitelist.")
                Rayfield:Notify({
                    Title = "Whitelist",
                    Content = selectedPlayer .. " has been removed from whitelist.",
                    Duration = 3,
                    Type = "Success"
                })
            else
                Rayfield:Notify({
                    Title = "Warning",
                    Content = selectedPlayer .. " is not on the whitelist.",
                    Duration = 3,
                    Type = "Warning"
                })
            end
        else
            Rayfield:Notify({
                Title = "Error",
                Content = "Please select a valid player.",
                Duration = 3,
                Type = "Error"
            })
        end
    end,
})

WhitelistTab:CreateButton({
    Name = "Set Safety TP Target",
    Callback = function()
        if selectedPlayer and selectedPlayer ~= "Select a player" then
            Rayfield:Notify({
                Title = "Safety TP Set",
                Content = "Safety teleport target set to: " .. tostring(selectedPlayer),
                Duration = 3,
                Type = "Info"
            })
        else
            Rayfield:Notify({
                Title = "Error",
                Content = "Please select a valid player first!",
                Duration = 3,
                Type = "Error"
            })
        end
    end,
})

local InfoSection = WhitelistTab:CreateSection("Information & Management")

WhitelistTab:CreateButton({
    Name = "Show Current Players",
    Callback = function()
        local playerList = "Current Players:\n"
        local count = 0
        for _, plr in ipairs(Players:GetPlayers()) do
            local teamName = getPlayerTeamName(plr)
            playerList = playerList .. "• " .. plr.Name .. " (Team: " .. teamName .. ")\n"
            count = count + 1
        end
        playerList = "Total: " .. count .. " players\n\n" .. playerList
        
        Rayfield:Notify({
            Title = "Player List",
            Content = playerList,
            Duration = 8,
            Type = "Info"
        })
    end,
})

WhitelistTab:CreateButton({
    Name = "Show Whitelist",
    Callback = function()
        local list = "Whitelisted Players:\n"
        local count = 0
        for name, _ in pairs(whitelistedPlayers) do
            -- Find the player to get their team info
            local playerTeam = "Unknown"
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr.Name == name then
                    playerTeam = getPlayerTeamName(plr)
                    break
                end
            end
            list = list .. "• " .. name .. " (Team: " .. playerTeam .. ")\n"
            count = count + 1
        end
        if count == 0 then
            list = list .. "No players whitelisted."
        else
            list = "Total: " .. count .. " whitelisted\n\n" .. list
        end
        
        Rayfield:Notify({
            Title = "Whitelist Status",
            Content = list,
            Duration = 8,
            Type = "Info"
        })
    end,
})

WhitelistTab:CreateButton({
    Name = "Clear All Whitelist",
    Callback = function()
        local count = 0
        for name, _ in pairs(whitelistedPlayers) do
            count = count + 1
        end
        
        whitelistedPlayers = {}
        log("Cleared entire whitelist (" .. count .. " players removed)")
        
        Rayfield:Notify({
            Title = "Whitelist Cleared",
            Content = "Removed " .. count .. " players from whitelist.",
            Duration = 3,
            Type = "Success"
        })
    end,
})

WhitelistTab:CreateButton({
    Name = "Refresh Player List",
    Callback = function()
        -- Refresh player dropdown
        if playerDropdown then
            playerDropdown:Destroy()
            createPlayerDropdown()
        end
        
        Rayfield:Notify({
            Title = "Refreshed",
            Content = "Player dropdown has been updated.",
            Duration = 3,
            Type = "Info"
        })
    end,
})

---------------------------------------------------------------------
-- PLAYER EVENT HANDLERS (Auto-refresh when players join/leave)
---------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
    log("Player joined: " .. player.Name)
    -- Auto-refresh dropdown when new player joins
    if playerDropdown then
        task.wait(1) -- Wait for player to fully load
        playerDropdown:Destroy()
        createPlayerDropdown()
    end
    
    -- Auto-enable ESP for new player if ESP is active
    if ESPenabled then
        task.wait(2) -- Wait for character to load
        ESP(player)
    end
end)

Players.PlayerRemoving:Connect(function(player)
    log("Player left: " .. player.Name)
    -- Remove from whitelist if they leave
    if whitelistedPlayers[player.Name] then
        whitelistedPlayers[player.Name] = nil
        log("Removed " .. player.Name .. " from whitelist (player left)")
    end
    
    -- Clean up ESP
    if COREGUI:FindFirstChild(player.Name..'_ESP') then
        COREGUI:FindFirstChild(player.Name..'_ESP'):Destroy()
    end
    
    -- Auto-refresh dropdown when player leaves
    if playerDropdown then
        task.wait(0.5)
        playerDropdown:Destroy()
        createPlayerDropdown()
    end
end)

---------------------------------------------------------------------
-- FINAL SCRIPT COMPLETION MESSAGE
---------------------------------------------------------------------
log("=== INSTAKILL {1.8} FULLY LOADED ===")
log("Features Available:")
log("• AUTO-ATTACH: Script will reload on server hop/teleport!")
log("• Teleport Loop (Start/Stop buttons + Q keybind)")
log("• Safety Teleport (X keybind)")
log("• ESP Toggle with real-time health display")
log("• Advanced Team Management System")
log("• Individual Player Whitelisting")
log("• Team-based Whitelisting")
log("• Adjustable teleport distance (0.5-10 studs)")
log("• Adjustable teleport duration (0.5-15 seconds)")
log("• Auto-refresh player lists")
log("• Real-time player join/leave detection")
log("=====================================")

-- Notify user that script is ready
Rayfield:Notify({
    Title = "Script Loaded",
    Content = "Instakill v1.8 is ready to use! Auto-attach enabled.",
    Duration = 5,
    Type = "Success"
})

MainTab:CreateToggle({
    Name = "Teleport for All Players",
    CurrentValue = false,
    Flag = "TeleportAllToggle",
    Callback = function(Value)
        teleportForAll = Value
        if teleportForAll then
            log("Teleport mode set to: ALL PLAYERS")
        else
            log("Teleport mode set to: ENEMY PLAYERS ONLY")
        end
    end,
})

MainTab:CreateToggle({
    Name = "ESP",
    CurrentValue = false,
    Flag = "ESPToggle",
    Callback = function(Value)
        ESPenabled = Value
        if ESPenabled then
            log("ESP enabled.")
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= Players.LocalPlayer then
                    ESP(plr)
                end
            end
        else
            log("ESP disabled.")
            for _, v in pairs(COREGUI:GetChildren()) do
                if string.sub(v.Name, -4) == "_ESP" then
                    v:Destroy()
                end
            end
        end
    end,
})

MainTab:CreateButton({
    Name = "Start Teleport Loop",
    Callback = function()
        log("Start Teleport Loop button clicked.")
        teleportLoop()
    end,
})

MainTab:CreateButton({
    Name = "Stop Teleport Loop",
    Callback = function()
        if isTeleportLoopActive then
            isTeleportLoopActive = false
            log("Teleport Loop stopped by user.")
            Rayfield:Notify({
                Title = "Stopped",
                Content = "Teleport loop has been stopped.",
                Duration = 2,
                Type = "Warning"
            })
        else
            Rayfield:Notify({
                Title = "Info",
                Content = "No active teleport loop to stop.",
                Duration = 2,
                Type = "Info"
            })
        end
    end,
})

---------------------------------------------------------------------
-- SETTINGS TAB
---------------------------------------------------------------------
local SettingsTab = Window:CreateTab("Settings", 6031280882)

local SettingsSection = SettingsTab:CreateSection("Customize Settings")

SettingsTab:CreateSlider({
    Name = "Time Between Teleports",
    Range = {0.5, 15},
    Increment = 0.1,
    Suffix = " sec",
    CurrentValue = 5,
    Flag = "TeleportWaitSlider",
    Callback = function(Value)
        teleportTime = Value
        log("Teleport time set to " .. tostring(Value) .. " seconds")
    end,
})

SettingsTab:CreateKeybind({
    Name = "Start Teleport Loop (Keybind)",
    CurrentKeybind = "Q",
    HoldToInteract = false,
    Flag = "StartLoopKeybind",
    Callback = function(KeybindPressed)
        log("Keybind pressed (" .. tostring(KeybindPressed) .. "). Starting Teleport Loop.")
        teleportLoop()
    end,
})

SettingsTab:CreateKeybind({
    Name = "Safety Teleport (Keybind)",
    CurrentKeybind = "X",
    HoldToInteract = false,
    Flag = "SafetyTeleportKeybind",
    Callback = function()
        -- Safety teleport implementation
        if not selectedPlayer then
            Rayfield:Notify({
                Title = "Error",
                Content = "No player selected for safety TP!",
                Duration = 3,
                Type = "Error"
            })
            return
        end

        local localPlayer = Players.LocalPlayer
        if not localPlayer then return end

        -- Stop active teleport loop
        if isTeleportLoopActive then
            isTeleportLoopActive = false
            Rayfield:Notify({
                Title = "Interrupted",
                Content = "Stopped active teleport loop!",
                Duration = 2,
                Type = "Warning"
            })
            task.wait(0.5)
        end

        local targetPlayer
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr.Name == selectedPlayer then
                targetPlayer = plr
                break
            end
        end
        
        if not targetPlayer then
            Rayfield:Notify({
                Title = "Error",
                Content = "Player '"..tostring(selectedPlayer).."' not found!",
                Duration = 3,
                Type = "Error"
            })
            return
        end

        local targetChar = targetPlayer.Character
        if not targetChar then
            Rayfield:Notify({
                Title = "Error",
                Content = "Target character not loaded!",
                Duration = 3,
                Type = "Error"
            })
            return
        end

        local targetRoot = getRoot(targetChar)
        if not targetRoot then
            Rayfield:Notify({
                Title = "Error",
                Content = "Target missing HumanoidRootPart!",
                Duration = 3,
                Type = "Error"
            })
            return
        end

        local localChar = localPlayer.Character
        if not localChar then
            Rayfield:Notify({
                Title = "Error",
                Content = "Your character not loaded!",
                Duration = 3,
                Type = "Error"
            })
            return
        end

        local localRoot = getRoot(localChar)
        if not localRoot then
            Rayfield:Notify({
                Title = "Error",
                Content = "Missing HumanoidRootPart!",
                Duration = 3,
                Type = "Error"
            })
            return
        end

        -- Use the adjustable teleportDistance variable for safety teleport as well
        local targetPos = targetRoot.Position - targetRoot.CFrame.LookVector * teleportDistance
        localRoot.CFrame = CFrame.new(targetPos, targetRoot.Position)

        Rayfield:Notify({
            Title = "Success",
            Content = "Teleported to " .. targetPlayer.Name,
            Duration = 3,
            Type = "Success"
        })
    end,
})

---------------------------------------------------------------------
-- TEAM TAB (NEW)
---------------------------------------------------------------------
local TeamTab = Window:CreateTab("Teams", 123456789)

local TeamSection = TeamTab:CreateSection("Team Analysis & Management")

TeamTab:CreateButton({
    Name = "Analyze All Teams",
    Callback = function()
        printTeamInfo()
        
        local teams, teamNames = getAllTeams()
        local teamInfo = "Teams Found:\n"
        
        if #teamNames == 0 then
            teamInfo = teamInfo .. "No teams detected in this game."
        else
            for _, teamName in ipairs(teamNames) do
                local team = teams[teamName]
                teamInfo = teamInfo .. "• " .. teamName .. " (" .. #team.players .. " players)\n"
            end
        end
        
        Rayfield:Notify({
            Title = "Team Analysis",
            Content = teamInfo,
            Duration = 6,
            Type = "Info"
        })
    end,
})

-- Dynamic team dropdown
local selectedTeam = nil
local teamDropdown = nil

local function updateTeamDropdown()
    local _, teamNames = getAllTeams()
    if #teamNames == 0 then
        teamNames = {"No teams found"}
    end
    
    if teamDropdown then
        teamDropdown:Destroy()
    end
    
    teamDropdown = TeamTab:CreateDropdown({
        Name = "Select Team to Whitelist",
        Options = teamNames,
        CurrentOption = "Select a team",
        MultiSelection = false,
        Flag = "TeamDropdown",
        Callback = function(Option)
            selectedTeam = typeof(Option) == "table" and Option[1] or tostring(Option)
        end,
    })
end

-- Initial team dropdown
updateTeamDropdown()

TeamTab:CreateButton({
    Name = "Refresh Team List",
    Callback = function()
        updateTeamDropdown()
        Rayfield:Notify({
            Title = "Refreshed",
            Content = "Team list has been updated.",
            Duration = 2,
            Type = "Info"
        })
    end,
})

TeamTab:CreateButton({
    Name = "Whitelist Selected Team",
    Callback = function()
        if selectedTeam and selectedTeam ~= "Select a team" and selectedTeam ~= "No teams found" then
            local success, count = whitelistTeam(selectedTeam)
            if success then
                Rayfield:Notify({
                    Title = "Team Whitelisted",
                    Content = "Added " .. count .. " players from team '" .. selectedTeam .. "' to whitelist.",
                    Duration = 4,
                    Type = "Success"
                })
            else
                Rayfield:Notify({
                    Title = "Error",
                    Content = "Failed to whitelist team '" .. selectedTeam .. "'.",
                    Duration = 3,
                    Type = "Error"
                })
            end
        else
            Rayfield:Notify({
                Title = "Error",
                Content = "Please select a valid team first.",
                Duration = 3,
                Type = "Error"
            })
        end
    end,
})

TeamTab:CreateButton({
    Name = "Whitelist My Team",
    Callback = function()
        local localPlayer = Players.LocalPlayer
        if not localPlayer or not localPlayer.Team then
            Rayfield:Notify({
                Title = "Error",
                Content = "You are not on a team!",
                Duration = 3,
                Type = "Error"
            })
            return
        end
        
        local myTeamName = localPlayer.Team.Name
        local success, count = whitelistTeam(myTeamName)
        
        if success then
            Rayfield:Notify({
                Title = "Team Whitelisted",
                Content = "Added " .. count .. " teammates to whitelist.",
                Duration = 4,
                Type = "Success"
            })
        else
            Rayfield:Notify({
                Title = "Error",
                Content = "Failed to whitelist your team.",
                Duration = 3,
                Type = "Error"
            })
        end
    end,
})

TeamTab:CreateButton({
    Name = "Whitelist Enemy Teams",
    Callback = function()
        local localPlayer = Players.LocalPlayer
        if not localPlayer then
            Rayfield:Notify({
                Title = "Error",
                Content = "LocalPlayer not found!",
                Duration = 3,
                Type = "Error"
            })
            return
        end
        
        local myTeamName = getPlayerTeamName(localPlayer)
        local teams, teamNames = getAllTeams()
        local totalWhitelisted = 0
        local enemyTeams = {}
        
        for _, teamName in ipairs(teamNames) do
            if teamName ~= myTeamName then
                local success, count = whitelistTeam(teamName)
                if success then
                    totalWhitelisted = totalWhitelisted + count
                    table.insert(enemyTeams, teamName)
                end
            end
        end
        
        if totalWhitelisted > 0 then
            Rayfield:Notify({
                Title = "Enemy Teams Whitelisted",
                Content = "Added " .. totalWhitelisted .. " players from enemy teams to whitelist.",
                Duration = 4,
                Type = "Success"
            })
        else
            Rayfield:Notify({
                Title = "Info",
                Content = "No enemy teams found to whitelist.",
                Duration = 3,
                Type = "Info"
            })
        end
    end,
})
