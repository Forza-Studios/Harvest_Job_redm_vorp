local npcModel = `re_playercampstrangers_females_01`
local npcCoords = vector3(1051.6591, -1126.4647, 66.8970)
local npcHeading = 308.5460
local blipSprite = -1944395098
local blipTitle = "Harvest Job"

local npcHandle = nil
local blipHandle = nil

-- Interactive prompts for NPC
local promptGroup = GetRandomIntInRange(0, 0xffffff)
local yesPrompt = nil
local noPrompt = nil
local quitPromptGroup = GetRandomIntInRange(0, 0xffffff)
local quitYesPrompt = nil
local quitNoPrompt = nil

-- Harvesting job state
local isJobActive = false
local currentHarvestStep = 1
local harvestBlip = nil
local harvestPromptGroup = GetRandomIntInRange(0, 0xffffff)
local harvestInteractPrompt = nil

-- Config
local infiniteHarvest = true -- Keep generating new harvest locations indefinitely
local maxHarvestsPerJob = 5  -- If infiniteHarvest is false, how many locations to harvest per job

-- Four corners of the harvest compound area
local fieldCorners = {
    vector3(1000.7115, -1030.6256, 66.4072),
    vector3(934.2754, -1051.1338, 58.1463),
    vector3(936.9107, -1087.0284, 57.7580),
    vector3(1012.7185, -1079.8914, 66.6571)
}

local harvestLocations = {}

local function GetTriangleArea(a, b, c)
    return 0.5 * math.abs(a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
end

local function GetRandomPointInTriangle(p1, p2, p3)
    local r1 = math.random()
    local r2 = math.random()
    local sqrtR1 = math.sqrt(r1)
    
    local x = (1 - sqrtR1) * p1.x + (sqrtR1 * (1 - r2)) * p2.x + (sqrtR1 * r2) * p3.x
    local y = (1 - sqrtR1) * p1.y + (sqrtR1 * (1 - r2)) * p2.y + (sqrtR1 * r2) * p3.y
    local z = (1 - sqrtR1) * p1.z + (sqrtR1 * (1 - r2)) * p2.z + (sqrtR1 * r2) * p3.z
    
    return vector3(x, y, z)
end

local function DrawText2D(txt, x, y, scale, r, g, b, a)
    local str = CreateVarString(10, "LITERAL_STRING", txt)
    SetTextFontForCurrentCommand(0)
    SetTextScale(scale, scale)
    SetTextColor(r or 255, g or 255, b or 255, a or 255)
    SetTextCentre(true)
    DisplayText(str, x, y)
end

local function SafeGetGroundZ(x, y, defaultZ)
    local status, success, groundZ = pcall(GetGroundZFor_3dCoord, x, y, 1000.0, true)
    if status and success and groundZ > 30.0 and groundZ < 100.0 then
        return groundZ
    end
    return defaultZ
end

local function GenerateRandomHarvestLocation()
    local pA, pB, pC, pD = fieldCorners[1], fieldCorners[2], fieldCorners[3], fieldCorners[4]
    
    local areaABC = GetTriangleArea(pA, pB, pC)
    local areaACD = GetTriangleArea(pA, pC, pD)
    local totalArea = areaABC + areaACD
    
    local point
    if math.random() < (areaABC / totalArea) then
        point = GetRandomPointInTriangle(pA, pB, pC)
    else
        point = GetRandomPointInTriangle(pA, pC, pD)
    end
    
    local groundZ = SafeGetGroundZ(point.x, point.y, point.z)
    return vector3(point.x, point.y, groundZ)
end

local function CreatePrompts()
    -- Yes Prompt (Arrow Up)
    yesPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(yesPrompt, 0x6319DB71) -- Arrow Up
    local strYes = VarString(10, 'LITERAL_STRING', "Yes")
    UiPromptSetText(yesPrompt, strYes)
    UiPromptSetEnabled(yesPrompt, true)
    UiPromptSetVisible(yesPrompt, true)
    UiPromptSetStandardMode(yesPrompt, true)
    UiPromptSetGroup(yesPrompt, promptGroup, 0)
    UiPromptRegisterEnd(yesPrompt)

    -- No Prompt (Arrow Down)
    noPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(noPrompt, 0x05CA7C52) -- Arrow Down
    local strNo = VarString(10, 'LITERAL_STRING', "No")
    UiPromptSetText(noPrompt, strNo)
    UiPromptSetEnabled(noPrompt, true)
    UiPromptSetVisible(noPrompt, true)
    UiPromptSetStandardMode(noPrompt, true)
    UiPromptSetGroup(noPrompt, promptGroup, 0)
    UiPromptRegisterEnd(noPrompt)

    -- Quit Yes Prompt (Arrow Up)
    quitYesPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(quitYesPrompt, 0x6319DB71) -- Arrow Up
    local strQuitYes = VarString(10, 'LITERAL_STRING', "Quit Job")
    UiPromptSetText(quitYesPrompt, strQuitYes)
    UiPromptSetEnabled(quitYesPrompt, true)
    UiPromptSetVisible(quitYesPrompt, true)
    UiPromptSetStandardMode(quitYesPrompt, true)
    UiPromptSetGroup(quitYesPrompt, quitPromptGroup, 0)
    UiPromptRegisterEnd(quitYesPrompt)

    -- Quit No Prompt (Arrow Down)
    quitNoPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(quitNoPrompt, 0x05CA7C52) -- Arrow Down
    local strQuitNo = VarString(10, 'LITERAL_STRING', "Continue")
    UiPromptSetText(quitNoPrompt, strQuitNo)
    UiPromptSetEnabled(quitNoPrompt, true)
    UiPromptSetVisible(quitNoPrompt, true)
    UiPromptSetStandardMode(quitNoPrompt, true)
    UiPromptSetGroup(quitNoPrompt, quitPromptGroup, 0)
    UiPromptRegisterEnd(quitNoPrompt)

    -- Harvest Action Prompt (E Key)
    harvestInteractPrompt = UiPromptRegisterBegin()
    UiPromptSetControlAction(harvestInteractPrompt, 0x760A9C6F) -- E Key (INPUT_CONTEXT)
    local strHarvest = VarString(10, 'LITERAL_STRING', "Harvest")
    UiPromptSetText(harvestInteractPrompt, strHarvest)
    UiPromptSetEnabled(harvestInteractPrompt, true)
    UiPromptSetVisible(harvestInteractPrompt, true)
    UiPromptSetStandardMode(harvestInteractPrompt, true)
    UiPromptSetGroup(harvestInteractPrompt, harvestPromptGroup, 0)
    UiPromptRegisterEnd(harvestInteractPrompt)
end

local function spawnNPC()
    if npcHandle and DoesEntityExist(npcHandle) then
        return
    end

    if not IsModelValid(npcModel) then
        print("coi_harvest: Invalid NPC model " .. tostring(npcModel))
        return
    end

    if not HasModelLoaded(npcModel) then
        RequestModel(npcModel)
        repeat Wait(10) until HasModelLoaded(npcModel)
    end

    npcHandle = CreatePed(npcModel, npcCoords.x, npcCoords.y, npcCoords.z - 1.0, npcHeading, false, false, false, false)
    repeat Wait(10) until DoesEntityExist(npcHandle)

    SetRandomOutfitVariation(npcHandle, true)
    PlaceEntityOnGroundProperly(npcHandle)
    SetEntityCanBeDamaged(npcHandle, false)
    SetBlockingOfNonTemporaryEvents(npcHandle, true)
    
    TaskStartScenarioInPlace(npcHandle, joaat("WORLD_HUMAN_DRINKING"), -1, true, false, false, false)
    Wait(1000)
    FreezeEntityPosition(npcHandle, true)
end

local function removeNPC()
    if npcHandle and DoesEntityExist(npcHandle) then
        DeleteEntity(npcHandle)
        npcHandle = nil
    end
end

local function addBlip()
    if blipHandle then
        RemoveBlip(blipHandle)
    end

    blipHandle = BlipAddForCoords(1664425300, npcCoords.x, npcCoords.y, npcCoords.z)
    SetBlipSprite(blipHandle, blipSprite, true)
    SetBlipName(blipHandle, blipTitle)
end

local function removeBlip()
    if blipHandle then
        RemoveBlip(blipHandle)
        blipHandle = nil
    end
end

local function updateHarvestBlip()
    if harvestBlip then
        RemoveBlip(harvestBlip)
        harvestBlip = nil
    end

    if isJobActive and harvestLocations[currentHarvestStep] then
        local loc = harvestLocations[currentHarvestStep]
        harvestBlip = BlipAddForCoords(1664425300, loc.x, loc.y, loc.z)
        SetBlipSprite(harvestBlip, blipSprite, true)
        BlipAddModifier(harvestBlip, joaat("BLIP_MODIFIER_MP_COLOR_8")) -- Green color modifier
        SetBlipName(harvestBlip, "Harvest Location")
    end
end

CreateThread(function()
    -- Wait until the player session is ready
    repeat Wait(1000) until LocalPlayer.state.IsInSession

    addBlip()
    CreatePrompts()

    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        if playerPed and playerPed ~= 0 then
            local playerCoords = GetEntityCoords(playerPed)

            if isJobActive then
                sleep = 0
                DrawText2D("HARVEST JOB ACTIVE", 0.5, 0.03, 0.45, 0, 255, 0, 220)
            end

            -- Handle NPC spawning and initial job offering
            local dist = #(playerCoords - npcCoords)
            if dist < 150.0 then
                if not npcHandle or not DoesEntityExist(npcHandle) then
                    spawnNPC()
                end
                sleep = 500

                -- Prompt player when near the NPC
                if dist < 2.5 then
                    sleep = 0
                    if not isJobActive then
                        local groupName = VarString(10, 'LITERAL_STRING', "Are you interested in harvesting?")
                        UiPromptSetActiveGroupThisFrame(promptGroup, groupName, 0, 0, 0, 0)

                        if UiPromptHasStandardModeCompleted(yesPrompt) or IsControlJustPressed(0, 0x6319DB71) then
                            -- Initialize random seed
                            math.randomseed(GetGameTimer())
                            TriggerEvent("vorp:TipRight", "Harvest job started! Follow the map markers.", 4000)
                            print("coi_harvest: Player accepted harvesting job")
                            isJobActive = true
                            currentHarvestStep = 1
                            
                            -- Populate harvestLocations dynamically inside the field corners
                            if infiniteHarvest then
                                harvestLocations = { GenerateRandomHarvestLocation() }
                            else
                                harvestLocations = {}
                                for i = 1, maxHarvestsPerJob do
                                    table.insert(harvestLocations, GenerateRandomHarvestLocation())
                                end
                            end
                            
                            updateHarvestBlip()
                            Wait(2000)
                        elseif UiPromptHasStandardModeCompleted(noPrompt) or IsControlJustPressed(0, 0x05CA7C52) then
                            TriggerEvent("vorp:TipRight", "Maybe next time.", 4000)
                            print("coi_harvest: Player declined harvesting job")
                            Wait(2000)
                        end
                    else
                        local groupName = VarString(10, 'LITERAL_STRING', "Do you want to quit the harvest job?")
                        UiPromptSetActiveGroupThisFrame(quitPromptGroup, groupName, 0, 0, 0, 0)

                        if UiPromptHasStandardModeCompleted(quitYesPrompt) or IsControlJustPressed(0, 0x6319DB71) then
                            isJobActive = false
                            if harvestBlip then
                                RemoveBlip(harvestBlip)
                                harvestBlip = nil
                            end
                            TriggerEvent("vorp:TipRight", "Harvest job cancelled.", 4000)
                            print("coi_harvest: Player quit harvesting job")
                            Wait(2000)
                        elseif UiPromptHasStandardModeCompleted(quitNoPrompt) or IsControlJustPressed(0, 0x05CA7C52) then
                            TriggerEvent("vorp:TipRight", "Continue harvesting!", 3000)
                            Wait(2000)
                        end
                    end
                end
            else
                if npcHandle then
                    removeNPC()
                end
            end

            -- Handle active harvest job checkpoints
            if isJobActive then
                local npcDist = #(playerCoords - npcCoords)
                if npcDist > 200.0 then
                    isJobActive = false
                    TriggerEvent("vorp:TipRight", "Harvest Job ended (too far from NPC).", 4000)
                    if harvestBlip then
                        RemoveBlip(harvestBlip)
                        harvestBlip = nil
                    end
                else
                    for i, target in ipairs(harvestLocations) do
                        -- Dynamically snap the Z coordinate to the ground once collision loads
                        local groundZ = SafeGetGroundZ(target.x, target.y, target.z)
                        target = vector3(target.x, target.y, groundZ)
                        harvestLocations[i] = target

                        local targetCoords = vector3(target.x, target.y, target.z)
                        local targetDist = #(playerCoords - targetCoords)

                        if targetDist < 100.0 then
                            sleep = 0 -- Marker rendering requires 0ms wait to prevent blinking

                            -- Draw cylinder ring marker on ground (Green)
                            DrawMarker(
                                0x6903B113, -- Cylinder marker
                                target.x, target.y, target.z + 0.05,
                                0.0, 0.0, 0.0,
                                0.0, 0.0, 0.0,
                                0.8, 0.8, 0.8,
                                0, 255, 0, 180,
                                false, true, 2, false, nil, nil, false
                            )
                        end

                        -- Only allow harvesting at the current objective
                        if i == currentHarvestStep and targetDist < 2.0 then
                            local promptTitle = VarString(10, 'LITERAL_STRING', "Harvesting")
                            UiPromptSetActiveGroupThisFrame(harvestPromptGroup, promptTitle, 0, 0, 0, 0)
                            if UiPromptHasStandardModeCompleted(harvestInteractPrompt) or IsControlJustPressed(0, 0x760A9C6F) then
                                local dict = "script_re@gold_panner@gold_success"
                                local anim = "SEARCH02"

                                RequestAnimDict(dict)
                                while not HasAnimDictLoaded(dict) do
                                    Wait(10)
                                end

                                TaskPlayAnim(playerPed, dict, anim, 2.0, 2.0, 10000, 1, 0.0, false, false, false)
                                
                                TriggerEvent("vorp:TipRight", "Harvesting...", 10000)
                                Wait(10000)
                                
                                ClearPedTasksImmediately(playerPed)
                                
                                TriggerEvent("vorp:TipRight", "Harvested!", 3000)
                                TriggerServerEvent("coi_harvest:givePayment")
                                
                                if infiniteHarvest then
                                    -- Continuously generate a new harvest location
                                    harvestLocations = { GenerateRandomHarvestLocation() }
                                    currentHarvestStep = 1
                                    updateHarvestBlip()
                                else
                                    -- Move to the next coordinate in the stack
                                    currentHarvestStep = currentHarvestStep + 1

                                    if currentHarvestStep > #harvestLocations then
                                        isJobActive = false
                                        TriggerEvent("vorp:TipRight", "Harvest Job completed!", 4000)
                                        if harvestBlip then
                                            RemoveBlip(harvestBlip)
                                            harvestBlip = nil
                                        end
                                    else
                                        updateHarvestBlip()
                                    end
                                end
                                Wait(1000)
                            end
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        removeNPC()
        removeBlip()
        if harvestBlip then
            RemoveBlip(harvestBlip)
            harvestBlip = nil
        end
        if yesPrompt then UiPromptDelete(yesPrompt) end
        if noPrompt then UiPromptDelete(noPrompt) end
        if quitYesPrompt then UiPromptDelete(quitYesPrompt) end
        if quitNoPrompt then UiPromptDelete(quitNoPrompt) end
        if harvestInteractPrompt then UiPromptDelete(harvestInteractPrompt) end
    end
end)
