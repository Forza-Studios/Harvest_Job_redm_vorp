local npcModel = `mp_a_f_m_saloonband_females_01`
local npcCoords = vector3(1051.6591, -1126.4647, 67.8970)
local npcHeading = 308.5460
local blipSprite = -1944395098
local blipTitle = "Harvest Job"

local npcHandle = nil
local blipHandle = nil

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
    end
end)
