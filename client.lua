local npcModel = `re_playercampstrangers_females_01`
local npcCoords = vector3(1051.6591, -1126.4647, 66.8970)
local npcHeading = 308.5460
local blipSprite = -1944395098
local blipTitle = "Harvest Job"

local npcHandle = nil
local blipHandle = nil

local promptGroup = GetRandomIntInRange(0, 0xffffff)
local yesPrompt = nil
local noPrompt = nil

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
            local dist = #(playerCoords - npcCoords)

            if dist < 150.0 then
                if not npcHandle or not DoesEntityExist(npcHandle) then
                    spawnNPC()
                end
                sleep = 500

                -- Prompt player when near the NPC
                if dist < 2.5 then
                    sleep = 0
                    local groupName = VarString(10, 'LITERAL_STRING', "Are you interested in harvesting?")
                    UiPromptSetActiveGroupThisFrame(promptGroup, groupName, 0, 0, 0, 0)

                    if UiPromptHasStandardModeCompleted(yesPrompt) or IsControlJustPressed(0, 0x6319DB71) then
                        TriggerEvent("vorp:TipRight", "Starting harvesting job...", 4000)
                        print("coi_harvest: Player accepted harvesting job")
                        Wait(2000) -- cooldown to avoid double triggers
                    elseif UiPromptHasStandardModeCompleted(noPrompt) or IsControlJustPressed(0, 0x05CA7C52) then
                        TriggerEvent("vorp:TipRight", "Maybe next time.", 4000)
                        print("coi_harvest: Player declined harvesting job")
                        Wait(2000) -- cooldown
                    end
                end
            else
                if npcHandle then
                    removeNPC()
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
        if yesPrompt then UiPromptDelete(yesPrompt) end
        if noPrompt then UiPromptDelete(noPrompt) end
    end
end)
