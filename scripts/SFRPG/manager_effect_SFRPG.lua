--  	Author: Ryan Hagelstrom
--	  	Copyright © 2023
--	  	This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.
--	  	https://creativecommons.org/licenses/by-sa/4.0/
--
-- luacheck: globals onInit onClose customGetEffectsByType customHasEffect
local getEffectsByType = nil;
local hasEffect = nil;

function onInit()
    getEffectsByType = EffectManagerSFRPG.getEffectsByType;
    hasEffect = EffectManagerSFRPG.hasEffect;

    EffectManagerSFRPG.getEffectsByType = customGetEffectsByType;
    EffectManagerSFRPG.hasEffect = customHasEffect;
end

function onClose()
    EffectManagerSFRPG.getEffectsByType = getEffectsByType;
    EffectManagerSFRPG.hasEffect = hasEffect;
end

function customGetEffectsByType(rActor, sEffectType, aFilter, rFilterActor, bTargetedOnly)
    if not rActor then
        return {};
    end
    local results = {};

    -- Set up filters
    local aRangeFilter = {};
    local aOtherFilter = {};
    if aFilter then
        for _, v in pairs(aFilter) do
            if type(v) ~= 'string' then
                table.insert(aOtherFilter, v);
            elseif StringManager.contains(DataCommon.rangetypes, v) then
                table.insert(aRangeFilter, v);
            else
                table.insert(aOtherFilter, v);
            end
        end
    end

    -- Determine effect type targeting
    -- local bTargetSupport = StringManager.isWord(sEffectType, DataCommon.targetableeffectcomps);

    -- Iterate through effects
    for _, v in pairs(TurboManager.getMatchedEffects(rActor, sEffectType)) do
        -- Check active
        local nActive = DB.getValue(v, 'isactive', 0);
        if (nActive ~= 0) then
            -- Check targeting
            local bTargeted = EffectManager.isTargetedEffect(v);
            if not bTargeted or EffectManager.isEffectTarget(v, rFilterActor) then
                local sLabel = DB.getValue(v, 'label', '');
                local aEffectComps = EffectManager.parseEffect(sLabel);

                -- Look for type/subtype match
                local nMatch = 0;
                for kEffectComp, sEffectComp in ipairs(aEffectComps) do
                    local rEffectComp = EffectManagerSFRPG.parseEffectComp(sEffectComp);
                    -- Handle conditionals
                    if rEffectComp.type == 'IF' then
                        if not EffectManagerSFRPG.checkConditional(rActor, v, rEffectComp.remainder) then
                            break
                        end
                    elseif rEffectComp.type == 'IFT' then
                        if not rFilterActor then
                            break
                        end
                        if not EffectManagerSFRPG.checkConditional(rFilterActor, v, rEffectComp.remainder, rActor) then
                            break
                        end
                        bTargeted = true;

                        -- Compare other attributes
                    else
                        -- Strip energy/bonus types for subtype comparison
                        local aEffectRangeFilter = {};
                        local aEffectOtherFilter = {};

                        local aComponents = {};
                        for _, vPhrase in ipairs(rEffectComp.remainder) do
                            local nTempIndexOR = 0;
                            local aPhraseOR = {};
                            repeat
                                local nStartOR, nEndOR = vPhrase:find('%s+or%s+', nTempIndexOR);
                                if nStartOR then
                                    table.insert(aPhraseOR, vPhrase:sub(nTempIndexOR, nStartOR - nTempIndexOR));
                                    nTempIndexOR = nEndOR;
                                else
                                    table.insert(aPhraseOR, vPhrase:sub(nTempIndexOR));
                                end
                            until nStartOR == nil;

                            for _, vPhraseOR in ipairs(aPhraseOR) do
                                local nTempIndexAND = 0;
                                repeat
                                    local nStartAND, nEndAND = vPhraseOR:find('%s+and%s+', nTempIndexAND);
                                    if nStartAND then
                                        local sInsert = StringManager.trim(vPhraseOR:sub(nTempIndexAND, nStartAND - nTempIndexAND));
                                        table.insert(aComponents, sInsert);
                                        nTempIndexAND = nEndAND;
                                    else
                                        local sInsert = StringManager.trim(vPhraseOR:sub(nTempIndexAND));
                                        table.insert(aComponents, sInsert);
                                    end
                                until nStartAND == nil;
                            end
                        end
                        local j = 1;
                        while aComponents[j] do
                            if StringManager.contains(DataCommon.dmgtypes, aComponents[j]) or StringManager.contains(DataCommon.bonustypes, aComponents[j]) or
                                aComponents[j] == 'all' then
                                -- Skip
                                j=j;
                            elseif StringManager.contains(DataCommon.rangetypes, aComponents[j]) then
                                table.insert(aEffectRangeFilter, aComponents[j]);
                            else
                                table.insert(aEffectOtherFilter, aComponents[j]);
                            end

                            j = j + 1;
                        end

                        -- Check for match
                        local comp_match = false;
                        if rEffectComp.type == sEffectType then

                            -- Check effect targeting
                            if bTargetedOnly and not bTargeted then
                                comp_match = false;
                            else
                                comp_match = true;
                            end

                            -- Check filters
                            if #aEffectRangeFilter > 0 then
                                local bRangeMatch = false;
                                for _, v2 in pairs(aRangeFilter) do
                                    if StringManager.contains(aEffectRangeFilter, v2) then
                                        bRangeMatch = true;
                                        break
                                    end
                                end
                                if not bRangeMatch then
                                    comp_match = false;
                                end
                            end
                            if #aEffectOtherFilter > 0 then
                                local bOtherMatch = false;
                                for _, v2 in pairs(aOtherFilter) do
                                    if type(v2) == 'table' then
                                        local bOtherTableMatch = true;
                                        for _, v3 in pairs(v2) do
                                            if not StringManager.contains(aEffectOtherFilter, v3) then
                                                bOtherTableMatch = false;
                                                break
                                            end
                                        end
                                        if bOtherTableMatch then
                                            bOtherMatch = true;
                                            break
                                        end
                                    elseif StringManager.contains(aEffectOtherFilter, v2) then
                                        bOtherMatch = true;
                                        break
                                    end
                                end
                                if not bOtherMatch then
                                    comp_match = false;
                                end
                            end
                        end

                        -- Match!
                        if comp_match then
                            nMatch = kEffectComp;
                            if nActive == 1 then
                                table.insert(results, rEffectComp);
                            end
                        end
                    end
                end -- END EFFECT COMPONENT LOOP

                -- Remove one shot effects
                if nMatch > 0 then
                    if nActive == 2 then
                        DB.setValue(v, 'isactive', 'number', 1);
                    else
                        local sApply = DB.getValue(v, 'apply', '');
                        if sApply == 'action' then
                            EffectManager.notifyExpire(v, 0);
                        elseif sApply == 'roll' then
                            EffectManager.notifyExpire(v, 0, true);
                        elseif sApply == 'single' then
                            EffectManager.notifyExpire(v, nMatch, true);
                        end
                    end
                end
            end -- END TARGET CHECK
        end -- END ACTIVE CHECK
    end -- END EFFECT LOOP

    return results;
end

function customHasEffect(rActor, sEffect, rTarget, bTargetedOnly, bIgnoreEffectTargets)
    if not sEffect or not rActor then
        return false;
    end
    local sLowerEffect = sEffect:lower();

    -- Iterate through each effect
    local aMatch = {};
    for _, v in pairs(TurboManager.getMatchedEffects(rActor, sEffect)) do
        local nActive = DB.getValue(v, 'isactive', 0);
        if nActive ~= 0 then
            -- Parse each effect label
            local sLabel = DB.getValue(v, 'label', '');
            local bTargeted = EffectManager.isTargetedEffect(v);
            local aEffectComps = EffectManager.parseEffect(sLabel);

            -- Iterate through each effect component looking for a type match
            local nMatch = 0;
            for kEffectComp, sEffectComp in ipairs(aEffectComps) do
                local rEffectComp = EffectManagerSFRPG.parseEffectComp(sEffectComp);
                -- Check conditionals
                if rEffectComp.type == 'IF' then
                    if not EffectManagerSFRPG.checkConditional(rActor, v, rEffectComp.remainder) then
                        break
                    end
                elseif rEffectComp.type == 'IFT' then
                    if not rTarget then
                        break
                    end
                    if not EffectManagerSFRPG.checkConditional(rTarget, v, rEffectComp.remainder, rActor) then
                        break
                    end

                    -- Check for match
                elseif rEffectComp.original:lower() == sLowerEffect then
                    if bTargeted and not bIgnoreEffectTargets then
                        if EffectManager.isEffectTarget(v, rTarget) then
                            nMatch = kEffectComp;
                        end
                    elseif not bTargetedOnly then
                        nMatch = kEffectComp;
                    end
                end

            end

            -- If matched, then remove one-off effects
            if nMatch > 0 then
                if nActive == 2 then
                    DB.setValue(v, 'isactive', 'number', 1);
                else
                    table.insert(aMatch, v);
                    local sApply = DB.getValue(v, 'apply', '');
                    if sApply == 'action' then
                        EffectManager.notifyExpire(v, 0);
                    elseif sApply == 'roll' then
                        EffectManager.notifyExpire(v, 0, true);
                    elseif sApply == 'single' then
                        EffectManager.notifyExpire(v, nMatch, true);
                    end
                end
            end
        end
    end

    if #aMatch > 0 then
        return true;
    end
    return false;
end
