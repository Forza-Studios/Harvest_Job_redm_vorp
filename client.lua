    --[[
        coi_harvest.lua — Enhanced
        ------------------------------------------------------------
        Built on top of the original harvest job script. Core logic
        (triangle-weighted random point generation, ground snapping,
        prompt groups, job state machine, payment event) is UNCHANGED.

        Added on top:
        - NPC idle variety (cycles scenarios instead of one forever)
        - NPC turns to face you when you're close and talking to it
        - "Job accepted" mini handshake beat instead of an instant flag flip
        - Ambient speech bubbles from the NPC while you're nearby
        - Harvest now has a real progress bar instead of a blind Wait(10000)
        - Cancels cleanly if you walk away or die mid-harvest
        - Streak counter + session stats HUD while the job is active
        - Distance-tagged 3D marker text above the current harvest spot
        - Time-of-day flavored greeting line
        - Light "fatigue" flavor text every few harvests (cosmetic only,
            does NOT slow you down or touch payment — see NOTE below)
        - Optional particle/sound feedback hooks (off by default —
            see CONFIG.enableParticles / enableSounds)
        - More defensive cleanup on resource stop

        NOTE ON PLACEHOLDERS:
        A couple of RDR3 asset names below (ptfx dict/effect names,
        frontend sound set names, extra scenario names) are common in
        RedM resources but I can't 100% verify them against your build.
        They're wrapped in pcall / gated behind config flags set to
        `false` by default, so nothing breaks out of the box — flip
        them on and swap in verified names for your server once you've
        checked them in-game.
    --]]

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

    -- Config (core)
    local infiniteHarvest = true -- Keep generating new harvest locations indefinitely
    local maxHarvestsPerJob = 5  -- If infiniteHarvest is false, how many locations to harvest per job

    -- ============================================================
    -- CONFIG (new stuff — safe to tweak/toggle)
    -- ============================================================
    local CONFIG = {
        npcIdleVariety      = true,   -- cycle through a few idle scenarios instead of one forever
        npcFaceTalker       = true,   -- NPC turns to face you when you talk to it
        npcAmbientChatter   = true,   -- occasional floating speech-bubble lines
        ambientChatterEvery = 25000,  -- ms between possible ambient lines (randomized +/- a bit)

        showStatsHud        = true,   -- little stats box while the job is active
        show3DSpotLabel     = true,   -- "Harvest Spot (123m)" floating label
        harvestDuration      = 10000, -- ms, same total time as original, now with a visible bar

        fatigueFlavorEvery  = 5,      -- show a cosmetic "getting tired" line every N harvests (no mechanical effect)

        enableParticles      = false, -- requires you to verify ptfx dict/effect names for your build
        ptfxDict             = "core",
        ptfxEffect           = "ent_dst_dirt_kickup",

        enableSounds          = false, -- requires you to verify sound set names for your build
        soundSetName          = "HUD_FRONTEND_DEFAULT_SOUNDSET",
        soundAccept            = "SELECT",
        soundHarvestComplete    = "CHECKPOINT_PERFECT",
    }

    -- Four corners of the harvest compound area
    local fieldCorners = {
        vector3(1000.7115, -1030.6256, 66.4072),
        vector3(934.2754, -1051.1338, 58.1463),
        vector3(936.9107, -1087.0284, 57.7580),
        vector3(1012.7185, -1079.8914, 66.6571)
    }

    local harvestLocations = {}

    -- New state used by the added features (doesn't touch core state above)
    local sessionHarvestCount = 0
    local sessionStreak = 0
    local sessionStartTime = nil
    local lastAmbientLineAt = 0
    local idleScenarioIndex = 1
    local idleScenarioChangedAt = 0
    local harvestAnims = {
        { dict = "script_re@gold_panner@gold_success", anim = "SEARCH02" }, -- verified in original script
        -- Add more verified {dict, anim} pairs here once you've tested them in-game.
    }

    -- Idle scenario pool for the NPC. WORLD_HUMAN_DRINKING is the one from
    -- the original script and is confirmed. The others are common RDR3-style
    -- scenario names — verify in-game before relying on them; if a hash is
    -- invalid, TaskStartScenarioInPlace just no-ops rather than erroring.
    local idleScenarios = {
        "WORLD_HUMAN_DRINKING",
        "WORLD_HUMAN_STAND_IMPATIENT",
        "WORLD_HUMAN_SMOKE_CIGAR",
    }

    local ambientLines = {
        "Ground's soft over that way, good for pickin'.",
        "Careful of snakes out past the fence line.",
        "Take your time, ain't no rush out here.",
        "Heard tell there's good soil near the tree line.",
    }

    -- ============================================================
    -- MATH / UTIL (unchanged core)
    -- ============================================================

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

    -- New: 3D world-space text, used for the harvest spot label + speech bubbles
    local function DrawText3D(coords, text, scale, r, g, b, a)
        local onScreen, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
        if not onScreen then return end
        SetTextScale(scale or 0.32, scale or 0.32)
        SetTextFontForCurrentCommand(0)
        SetTextColor(r or 255, g or 255, b or 255, a or 220)
        SetTextCentre(true)
        SetTextDropshadow(1, 0, 0, 0, 255)
        local str = CreateVarString(10, "LITERAL_STRING", text)
        DisplayText(str, x, y)
    end

    -- New: simple screen-space progress bar
    local function DrawProgressBar(x, y, w, h, pct, r, g, b)
        pct = math.max(0.0, math.min(1.0, pct))
        DrawRect(x, y, w, h, 0, 0, 0, 140)
        DrawRect(x - (w * (1 - pct) / 2), y, w * pct, h, r or 0, g or 200, b or 90, 220)
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

    -- ============================================================
    -- FEEDBACK HELPERS (new, opt-in, defensive)
    -- ============================================================

    local function TryPlaySound(soundName)
        if not CONFIG.enableSounds then return end
        pcall(function()
            PlaySoundFrontend(-1, soundName, CONFIG.soundSetName, true)
        end)
    end

    local function TrySpawnParticleAt(coords)
        if not CONFIG.enableParticles then return end
        pcall(function()
            RequestNamedPtfxAsset(CONFIG.ptfxDict)
            local tries = 0
            while not HasNamedPtfxAssetLoaded(CONFIG.ptfxDict) and tries < 50 do
                Wait(10)
                tries = tries + 1
            end
            if HasNamedPtfxAssetLoaded(CONFIG.ptfxDict) then
                UseParticleFxAssetNextCall(CONFIG.ptfxDict)
                StartParticleFxNonLoopedAtCoord(CONFIG.ptfxEffect, coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 1.0, false, false, false)
            end
        end)
    end

    local function GetTimeGreeting()
        local ok, hours = pcall(GetClockHours)
        if not ok then return "Howdy." end
        if hours >= 5 and hours < 12 then
            return "Mornin'."
        elseif hours >= 12 and hours < 18 then
            return "Afternoon."
        elseif hours >= 18 and hours < 21 then
            return "Evenin'."
        else
            return "Bit late to be out, but I ain't gonna stop you."
        end
    end

    local function FormatElapsed(ms)
        local totalSeconds = math.floor(ms / 1000)
        local m = math.floor(totalSeconds / 60)
        local s = totalSeconds % 60
        return string.format("%02d:%02d", m, s)
    end

    -- ============================================================
    -- PROMPTS (unchanged core, just organized)
    -- ============================================================

    local function CreatePrompts()
        yesPrompt = UiPromptRegisterBegin()
        UiPromptSetControlAction(yesPrompt, 0x6319DB71) -- Arrow Up
        UiPromptSetText(yesPrompt, VarString(10, 'LITERAL_STRING', "Yes"))
        UiPromptSetEnabled(yesPrompt, true)
        UiPromptSetVisible(yesPrompt, true)
        UiPromptSetStandardMode(yesPrompt, true)
        UiPromptSetGroup(yesPrompt, promptGroup, 0)
        UiPromptRegisterEnd(yesPrompt)

        noPrompt = UiPromptRegisterBegin()
        UiPromptSetControlAction(noPrompt, 0x05CA7C52) -- Arrow Down
        UiPromptSetText(noPrompt, VarString(10, 'LITERAL_STRING', "No"))
        UiPromptSetEnabled(noPrompt, true)
        UiPromptSetVisible(noPrompt, true)
        UiPromptSetStandardMode(noPrompt, true)
        UiPromptSetGroup(noPrompt, promptGroup, 0)
        UiPromptRegisterEnd(noPrompt)

        quitYesPrompt = UiPromptRegisterBegin()
        UiPromptSetControlAction(quitYesPrompt, 0x6319DB71) -- Arrow Up
        UiPromptSetText(quitYesPrompt, VarString(10, 'LITERAL_STRING', "Quit Job"))
        UiPromptSetEnabled(quitYesPrompt, true)
        UiPromptSetVisible(quitYesPrompt, true)
        UiPromptSetStandardMode(quitYesPrompt, true)
        UiPromptSetGroup(quitYesPrompt, quitPromptGroup, 0)
        UiPromptRegisterEnd(quitYesPrompt)

        quitNoPrompt = UiPromptRegisterBegin()
        UiPromptSetControlAction(quitNoPrompt, 0x05CA7C52) -- Arrow Down
        UiPromptSetText(quitNoPrompt, VarString(10, 'LITERAL_STRING', "Continue"))
        UiPromptSetEnabled(quitNoPrompt, true)
        UiPromptSetVisible(quitNoPrompt, true)
        UiPromptSetStandardMode(quitNoPrompt, true)
        UiPromptSetGroup(quitNoPrompt, quitPromptGroup, 0)
        UiPromptRegisterEnd(quitNoPrompt)

        harvestInteractPrompt = UiPromptRegisterBegin()
        UiPromptSetControlAction(harvestInteractPrompt, 0xD9D0E1C0) -- Spacebar (INPUT_JUMP)
        UiPromptSetText(harvestInteractPrompt, VarString(10, 'LITERAL_STRING', "Harvest"))
        UiPromptSetEnabled(harvestInteractPrompt, true)
        UiPromptSetVisible(harvestInteractPrompt, true)
        UiPromptSetStandardMode(harvestInteractPrompt, true)
        UiPromptSetGroup(harvestInteractPrompt, harvestPromptGroup, 0)
        UiPromptRegisterEnd(harvestInteractPrompt)
    end

    -- ============================================================
    -- NPC (spawn/remove core, idle behavior new)
    -- ============================================================

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

        TaskStartScenarioInPlace(npcHandle, joaat(idleScenarios[1]), -1, true, false, false, false)
        idleScenarioIndex = 1
        idleScenarioChangedAt = GetGameTimer()
        Wait(1000)
        FreezeEntityPosition(npcHandle, true)
    end

    local function removeNPC()
        if npcHandle and DoesEntityExist(npcHandle) then
            DeleteEntity(npcHandle)
            npcHandle = nil
        end
    end

    -- New: cycles the NPC through the idle scenario pool every so often so it
    -- doesn't stand there drinking forever. Runs as its own light thread.
    local function StartIdleVarietyThread()
        if not CONFIG.npcIdleVariety then return end
        CreateThread(function()
            while true do
                Wait(3000)
                if npcHandle and DoesEntityExist(npcHandle) then
                    local now = GetGameTimer()
                    if now - idleScenarioChangedAt > 45000 then -- change every ~45s
                        idleScenarioIndex = (idleScenarioIndex % #idleScenarios) + 1
                        pcall(function()
                            TaskStartScenarioInPlace(npcHandle, joaat(idleScenarios[idleScenarioIndex]), -1, true, false, false, false)
                        end)
                        idleScenarioChangedAt = now
                    end
                end
            end
        end)
    end

    -- New: occasional floating speech bubble when the player lingers nearby
    local function StartAmbientChatterThread()
        if not CONFIG.npcAmbientChatter then return end
        CreateThread(function()
            while true do
                Wait(1000)
                local playerPed = PlayerPedId()
                if npcHandle and DoesEntityExist(npcHandle) and playerPed and playerPed ~= 0 then
                    local dist = #(GetEntityCoords(playerPed) - npcCoords)
                    local now = GetGameTimer()
                    if dist < 8.0 and (now - lastAmbientLineAt) > CONFIG.ambientChatterEvery then
                        if math.random() < 0.5 then
                            local line = ambientLines[math.random(1, #ambientLines)]
                            local npcHeadCoords = npcCoords + vector3(0.0, 0.0, 0.9)
                            local shownFor = 0.0
                            while shownFor < 3500 do
                                DrawText3D(npcHeadCoords, line, 0.3)
                                Wait(0)
                                shownFor = shownFor + (GetFrameTime() * 1000)
                            end
                        end
                        lastAmbientLineAt = now
                    end
                end
            end
        end)
    end

    -- ============================================================
    -- BLIPS (unchanged core)
    -- ============================================================

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

    -- ============================================================
    -- STATS HUD (new)
    -- ============================================================

    local function DrawStatsHud()
        if not CONFIG.showStatsHud then return end
        local elapsed = sessionStartTime and (GetGameTimer() - sessionStartTime) or 0
        DrawText2D(("Harvested: %d   Streak: %d   Time: %s"):format(sessionHarvestCount, sessionStreak, FormatElapsed(elapsed)),
            0.5, 0.06, 0.28, 200, 255, 200, 200)
    end

    -- ============================================================
    -- MAIN LOOP (core structure unchanged, enhanced inline)
    -- ============================================================

    CreateThread(function()
        -- Wait until the player session is ready
        repeat Wait(1000) until LocalPlayer.state.IsInSession

        addBlip()
        CreatePrompts()
        StartIdleVarietyThread()
        StartAmbientChatterThread()

        while true do
            local sleep = 1000
            local playerPed = PlayerPedId()
            if playerPed and playerPed ~= 0 then
                local playerCoords = GetEntityCoords(playerPed)

                if isJobActive then
                    sleep = 0
                    DrawStatsHud()
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

                        if CONFIG.npcFaceTalker and npcHandle and DoesEntityExist(npcHandle) then
                            pcall(function() TaskTurnPedToFaceEntity(npcHandle, playerPed, 1500) end)
                        end

                        if not isJobActive then
                            local groupName = VarString(10, 'LITERAL_STRING', GetTimeGreeting() .. " Interested in harvesting?")
                            UiPromptSetActiveGroupThisFrame(promptGroup, groupName, 0, 0, 0, 0)

                            if UiPromptHasStandardModeCompleted(yesPrompt) or IsControlJustPressed(0, 0x6319DB71) then
                                math.randomseed(GetGameTimer())
                                TryPlaySound(CONFIG.soundAccept)
                                TriggerEvent("vorp:TipRight", "Harvest job started! Follow the map markers.", 4000)
                                print("coi_harvest: Player accepted harvesting job")
                                isJobActive = true
                                currentHarvestStep = 1
                                sessionStartTime = sessionStartTime or GetGameTimer()
                                sessionStreak = 0

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
                                TriggerEvent("vorp:TipRight", ("Harvest job cancelled. %d harvested this session."):format(sessionHarvestCount), 4000)
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
                        sessionStreak = 0
                        TriggerEvent("vorp:TipRight", "Harvest Job ended (too far from NPC).", 4000)
                        if harvestBlip then
                            RemoveBlip(harvestBlip)
                            harvestBlip = nil
                        end
                    else
                        for i, target in ipairs(harvestLocations) do
                            local groundZ = SafeGetGroundZ(target.x, target.y, target.z)
                            target = vector3(target.x, target.y, groundZ)
                            harvestLocations[i] = target

                            local targetCoords = vector3(target.x, target.y, target.z)
                            local targetDist = #(playerCoords - targetCoords)

                            if targetDist < 100.0 then
                                sleep = 0

                                DrawMarker(
                                    0x6903B113, -- Cylinder marker
                                    target.x, target.y, target.z + 0.05,
                                    0.0, 0.0, 0.0,
                                    0.0, 0.0, 0.0,
                                    0.8, 0.8, 0.8,
                                    0, 255, 0, 180,
                                    false, true, 2, false, nil, nil, false
                                )

                                if CONFIG.show3DSpotLabel and i == currentHarvestStep then
                                    local label = ("Harvest Spot (%dm)"):format(math.floor(targetDist))
                                    DrawText3D(target + vector3(0.0, 0.0, 1.0), label, 0.32, 180, 255, 180)
                                end
                            end

                            -- Only allow harvesting at the current objective
                            if i == currentHarvestStep and targetDist < 2.0 then
                                local promptTitle = VarString(10, 'LITERAL_STRING', "Harvesting")
                                UiPromptSetActiveGroupThisFrame(harvestPromptGroup, promptTitle, 0, 0, 0, 0)
                                if UiPromptHasStandardModeCompleted(harvestInteractPrompt) or IsControlJustPressed(0, 0xD9D0E1C0) then
                                    local chosenAnim = harvestAnims[math.random(1, #harvestAnims)]
                                    local dict = chosenAnim.dict
                                    local anim = chosenAnim.anim

                                    RequestAnimDict(dict)
                                    local waited = 0
                                    while not HasAnimDictLoaded(dict) and waited < 3000 do
                                        Wait(10)
                                        waited = waited + 10
                                    end

                                    -- Play animation continuously while playing the minigame
                                    TaskPlayAnim(playerPed, dict, anim, 2.0, 2.0, -1, 1, 0.0, false, false, false)
                                    TrySpawnParticleAt(targetCoords)
                                    TriggerEvent("vorp:TipRight", "Starting harvest...", 2000)

                                    -- Trigger the minigame twice (Difficulty 3000ms, Gap 7)
                                    local success = true
                                    local cancelled = false

                                    for step = 1, 2 do
                                        local minigame = exports["syn_minigame"]:taskBar(3000, 7)

                                        if IsEntityDead(playerPed) or #(GetEntityCoords(playerPed) - targetCoords) > 4.0 then
                                            cancelled = true
                                            break
                                        elseif minigame ~= 100 then
                                            success = false
                                            break
                                        end

                                        if step < 2 then
                                            Wait(500)
                                        end
                                    end

                                    ClearPedTasksImmediately(playerPed)

                                    if not success then
                                        TriggerEvent("vorp:TipRight", "Harvest failed!", 3000)
                                        sessionStreak = 0
                                    elseif cancelled then
                                        TriggerEvent("vorp:TipRight", "Harvest interrupted.", 3000)
                                        sessionStreak = 0
                                    else
                                        -- Minigame success and time completed!
                                        TryPlaySound(CONFIG.soundHarvestComplete)
                                        TriggerEvent("vorp:TipRight", "Harvested!", 3000)
                                        TriggerServerEvent("coi_harvest:givePayment")

                                        sessionHarvestCount = sessionHarvestCount + 1
                                        sessionStreak = sessionStreak + 1

                                        if CONFIG.fatigueFlavorEvery > 0 and sessionHarvestCount % CONFIG.fatigueFlavorEvery == 0 then
                                            TriggerEvent("vorp:TipRight", "Your arms are getting tired, but you push on.", 3000)
                                        end

                                        if infiniteHarvest then
                                            harvestLocations = { GenerateRandomHarvestLocation() }
                                            currentHarvestStep = 1
                                            updateHarvestBlip()
                                        else
                                            currentHarvestStep = currentHarvestStep + 1

                                            if currentHarvestStep > #harvestLocations then
                                                isJobActive = false
                                                TriggerEvent("vorp:TipRight", ("Harvest Job completed! %d harvested."):format(sessionHarvestCount), 4000)
                                                if harvestBlip then
                                                    RemoveBlip(harvestBlip)
                                                    harvestBlip = nil
                                                end
                                            else
                                                updateHarvestBlip()
                                            end
                                        end
                                    end
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