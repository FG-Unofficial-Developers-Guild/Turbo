--  	Author: Ryan Hagelstrom
--	  	Copyright © 2023
--	  	This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.
--	  	https://creativecommons.org/licenses/by-sa/4.0/
--
-- luacheck: globals onInit onClose customGetEffectsByType customHasEffect customIsHiddenFromTarget customHasEffectCondition
-- luacheck: globals customGetConditionValue customHasEffectCondition customGetConditionValue customGetConditionValueLowest customGetEffectsBonusByType

local getEffectsByType = nil;
local hasEffect = nil;
local getConditionValue = nil;
local getConditionValueLowest = nil;
local getEffectsBonusByType = nil;
local hasEffectCondition = nil;
local isHiddenFromTarget = nil;

function onInit()
    getEffectsByType = EffectManagerPFRPG2.getEffectsByType;
    hasEffect = EffectManagerPFRPG2.hasEffect;
    getConditionValue = EffectManagerPFRPG2.getConditionValue;
    getConditionValueLowest = EffectManagerPFRPG2.getConditionValueLowest;
    getEffectsBonusByType = EffectManagerPFRPG2.getEffectsBonusByType;
    hasEffectCondition = EffectManagerPFRPG2.hasEffectCondition;
    isHiddenFromTarget = EffectManagerPFRPG2.isHiddenFromTarget;

    EffectManagerPFRPG2.getEffectsByType = customGetEffectsByType;
    EffectManagerPFRPG2.hasEffect = customHasEffect;
    EffectManagerPFRPG2.getConditionValue = customGetConditionValue;
    EffectManagerPFRPG2.getConditionValueLowest = customGetConditionValueLowest;
    EffectManagerPFRPG2.getEffectsBonusByType = customGetEffectsBonusByType;
    EffectManagerPFRPG2.hasEffectCondition = customHasEffectCondition;
    EffectManagerPFRPG2.isHiddenFromTarget = customIsHiddenFromTarget;
end

function onClose()
    EffectManagerPFRPG2.getEffectsByType = getEffectsByType;
    EffectManagerPFRPG2.hasEffect = hasEffect;
    EffectManagerPFRPG2.getConditionValue = getConditionValue;
    EffectManagerPFRPG2.getConditionValueLowest = getConditionValueLowest;
    EffectManagerPFRPG2.getEffectsBonusByType = getEffectsBonusByType;
    EffectManagerPFRPG2.hasEffectCondition = hasEffectCondition;
    EffectManagerPFRPG2.isHiddenFromTarget = isHiddenFromTarget;
end

-- luacheck: push ignore 561
-- Added aTraitFilter for saves and bLeaveOneShots for not removing one shot effects
function customGetEffectsByType(rActor, sEffectType, aFilter, rFilterActor, bTargetedOnly, aTraitFilter, bLeaveOneShots)
    -- aTraitFilter no long needed?
    if not rActor then
        return {};
    end
    local results = {};
    local aTempFilter = {};

    GlobalDebug.consoleObjects('EffectManagerPFRPG2.getEffectsByType.  Starting data - rActor, sEffectType, aFilter, rFilterActor, bTargetedOnly, aTraitFilter',
                               rActor, sEffectType, aFilter, rFilterActor, bTargetedOnly, aTraitFilter);

    -- Special handling for saves and skill checks.  aFilter could contain the save/skill name and a table of traits.
    local sSaveType = nil;
    local sInitialResult = nil;
    local isBasicSave = false;
    local sSkillType = nil;
    local sProficiency = nil;
    local sDistance = nil;
    local aLocalFilter = UtilityManager.copyDeep(aFilter);
    if aLocalFilter then
        if aLocalFilter['save'] and aLocalFilter['save'] ~= '' then
            sSaveType = aLocalFilter['save'];
            aLocalFilter['save'] = nil;
        end
        if aLocalFilter['initialresult'] and aLocalFilter['initialresult'] ~= '' then
            sInitialResult = aLocalFilter['initialresult'];
            aLocalFilter['initialresult'] = nil;
        end
        if aLocalFilter['basicsave'] then
            isBasicSave = aLocalFilter['basicsave'];
            aLocalFilter['basicsave'] = nil;
        end
        if (aLocalFilter['skill'] or '') ~= '' then
            sSkillType = aLocalFilter['skill'];
            aLocalFilter['skill'] = nil;
        end
        if (aLocalFilter['distance'] or '') ~= '' then
            sDistance = aLocalFilter['distance'];
            aLocalFilter['distance'] = nil;
        end
        -- If we have traits in the filter, use them as the filter.  Otherwise assume the filters are in the base filter.
        if aLocalFilter['traits'] and #aLocalFilter['traits'] > 0 then
            -- Strip secondary names from the trait filter - experimental to see if there are any issues.
            -- This is to allow trait matching for activity names, e.g.Treat Wounds (Expert) activity with "Treat Wounds" activity name trait.
            for _, sTraitName in pairs(aLocalFilter['traits']) do
                local sTraitNameWithoutSubcategory = StringManager.trim(string.gsub(sTraitName, '%(.-%)', ''));
                table.insert(aTempFilter, sTraitNameWithoutSubcategory);
            end
            --			aTempFilter = aLocalFilter["traits"];
            --			aLocalFilter["traits"] = nil;
        else
            -- TODO - does this sometimes breaks with complex filters?
            aTempFilter = aLocalFilter;
        end
    end
    GlobalDebug.consoleObjects(
        'EffectManagerPFRPG2.getEffectsByType.  Done checking for save/skill data.  sSaveType, sInitialResult, isBasicSave, sSkillType, sDistance,' ..
        'aTempFilter, aLocalFilter = ',
        sSaveType, sInitialResult, isBasicSave, sSkillType, sDistance, aTempFilter, aLocalFilter);

    -- Set up filters
    local aRangeFilter = {};
    local aOtherFilter = {};
    if aTempFilter then
        for _, v in pairs(aTempFilter) do
            if type(v) ~= 'string' then
                table.insert(aOtherFilter, v);
            elseif StringManager.contains(DataCommon.rangetypes, v) then
                table.insert(aRangeFilter, string.lower(v));
            elseif StringManager.contains(DataCommon.proficiencyLevels, v) then
                sProficiency = v;
            else
                table.insert(aOtherFilter, string.lower(v));
            end
        end
    end

    GlobalDebug.consoleObjects('EffectManagerPFRPG2.getEffectsByType. Filters aRangeFilter, aOtherFilter = ', aRangeFilter, aOtherFilter);

    -- Determine effect type targeting
    -- local bTargetSupport = StringManager.isWord(sEffectType, DataCommon.targetableeffectcomps);

    -- Iterate through effects
    local aEffectsDBNodes = TurboManager.getMatchedEffects(rActor, sEffectType);
    --local sActorType, nodeActor = ActorManager.getTypeAndNode(rActor);

    --	local aEffectsDBNodes = DB.getChildren(ActorManager.getCTNode(rActor), "effects");
    --	GlobalDebug.consoleObjects("EffectManagerPFRPG2.getEffectsByType. sActorType, nodeActor = ", sActorType, nodeActor);
    --	if sActorType == "pc" then
    --		GlobalDebug.consoleObjects("EffectManagerPFRPG2.getEffectsByType.  Effects node children = ", DB.getChildren(nodeActor, "effects"));
    --		for _,vCharEffectNode in pairs(DB.getChildren(nodeActor, "effects")) do
    --			table.insert(aEffectsDBNodes, vCharEffectNode);
    --		end
    --		if (rActor.nodeActionEffects or "") ~= "" then
    --			local nodeActionEffects = DB.findNode(rActor.nodeActionEffects);
    --			if nodeActionEffects then
    --				for _,vActionEffectNode in pairs(DB.getChildren(nodeActionEffects)) do
    --					table.insert(aEffectsDBNodes, vActionEffectNode);
    --				end
    --			end
    --		end
    --	end

    GlobalDebug.consoleObjects('EffectManagerPFRPG2.getEffectsByType.  About to parse through all effects.  aEffectsDBNodes = ', aEffectsDBNodes);

    --	for _,v in pairs(DB.getChildren(ActorManager.getCTNode(rActor), "effects")) do
    for _, v in pairs(aEffectsDBNodes) do
        -- Check active
        local nActive = DB.getValue(v, 'isactive', 0);
        if (nActive ~= 0) then
            -- Check targeting
            local bTargeted = EffectManager.isTargetedEffect(v);
            GlobalDebug.consoleObjects('EffectManagerPFRPG2.getEffectsByType.  Checking effect - v, bTargeted = ', v, bTargeted);
            if not bTargeted or EffectManager.isEffectTarget(v, rFilterActor) then
                local sLabel = DB.getValue(v, 'label', '');
                local aEffectComps = EffectManager.parseEffect(sLabel);

                -- getEffectsWithVariables no longer needed as character effects with variabes are pushed via the character sheet to the CT.
                --				GlobalDebug.consoleObjects("EffectManagerPFRPG2.getEffectsByType.  Before getEffectsWithVariables - aEffectComps = ", aEffectComps);
                --				aEffectComps = AutomationManagerPFRPG2.getEffectsWithVariables(nodeActor, aEffectComps);
                --				GlobalDebug.consoleObjects("EffectManagerPFRPG2.getEffectsByType.  After getEffectsWithVariables - aEffectComps = ", aEffectComps);

                -- Look for type/subtype match
                local nMatch = 0;
                for kEffectComp, sEffectComp in ipairs(aEffectComps) do
                    local rEffectComp = EffectManagerPFRPG2.parseEffectComp(sEffectComp);
                    GlobalDebug.consoleObjects('EffectManagerPFRPG2.getEffectsByType.  Effect components - sEffectComp, rEffectComp = ', sEffectComp,
                                               rEffectComp);
                    -- Handle conditionals
                    if rEffectComp.type == 'IF' then
                        if not EffectManagerPFRPG2.checkConditional(rActor, v, rEffectComp.remainder) then
                            break
                        end
                    elseif rEffectComp.type == 'IFT' then
                        GlobalDebug.consoleObjects('EffectManagerPFRPG2.getEffectsByType. Have an IFT effect.  rEffectComp = ', rEffectComp);
                        if not rFilterActor then
                            break
                        end
                        GlobalDebug.consoleObjects(
                            'EffectManagerPFRPG2.getEffectsByType.  About to check conditional.  rFilterActor, v, rEffectComp.remainder, rActor = ',
                            rFilterActor, v, rEffectComp.remainder, rActor);
                        if not EffectManagerPFRPG2.checkConditional(rFilterActor, v, rEffectComp.remainder, rActor) then
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
                            -- PFRPG2 - change "all magic" to just magic. Some creatures have conditional saves vs all magic.
                            if vPhrase:lower() == 'all magic' then
                                vPhrase = 'magic';
                            end
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
                                        table.insert(aComponents, string.lower(sInsert));
                                        nTempIndexAND = nEndAND;
                                    else
                                        local sInsert = StringManager.trim(vPhraseOR:sub(nTempIndexAND));
                                        table.insert(aComponents, string.lower(sInsert));
                                    end
                                until nStartAND == nil;
                            end
                        end
                        GlobalDebug.consoleObjects('EffectManagerPFRPG2.getEffectsByType.  Filtering effect type components.  aComponents = ', aComponents);
                        local j = 1;
                        while aComponents[j] do
                            -- Remove from the filter components any individual matching clauses - e.g. save name, save result, basic save type, damage type, etc..
                            -- Process damage types that overcome the effect type - begin with a !
                            local sDamageTypeName = string.gsub(aComponents[j], '!', '');
                            if (rEffectComp.type ~= 'SAVE' and rEffectComp.type ~= 'SAVERESULT') and
                                (StringManager.contains(DataCommon.dmgtypes, sDamageTypeName) or StringManager.contains(DataCommon.bonustypes, aComponents[j]) or
                                    aComponents[j] == 'all') then
                                -- Skip
                                j=j;
                            elseif (rEffectComp.type == 'SAVE' or rEffectComp.type == 'SAVERESULT' or rEffectComp.type == 'SAVEDAMAGEPER') and
                                (sSaveType == aComponents[j] or sInitialResult == aComponents[j] or
                                    StringManager.contains(DataCommon.bonustypes, aComponents[j]) or aComponents[j] == 'all' or
                                    (isBasicSave and aComponents[j] == 'basic')) then
                                -- Skip - testing save or SAVERESULT effect descriptors
                                j=j;
                            elseif rEffectComp.type == 'SKILL' and
                                (sSkillType == aComponents[j] or StringManager.contains(DataCommon.bonustypes, aComponents[j])) then
                                -- This is a skill based effect - keep processing.
                                j=j;
                            elseif (rEffectComp.type == 'PCROLL') then
                                -- Skip filtering of PCROLL effects - we want to return all PCROLL effects.
                                j=j;
                            elseif (rEffectComp.type == 'TRAIT') then
                                -- Skip filtering of TRAIT effects - we want to return all TRAIT effects.
                                j=j;
                            elseif StringManager.contains(DataCommon.proficiencyLevels, aComponents[j]) and sProficiency == aComponents[j] then
                                -- Skip filtering of proficiency
                                j=j;
                            elseif string.find(aComponents[j], '^dist%d+') then
                                -- Skip filtering of distance if within distance
                                -- Also skip if distance is not available - e.g. not using tokens on a map.
                                if sDistance then
                                    local sEffectDistance = string.match(aComponents[j], '^dist(%d+)');
                                    if (sEffectDistance or '') ~= '' then
                                        local nEffectDistance = tonumber(sEffectDistance);
                                        local nDistance = tonumber(sDistance);
                                        -- If activity distance is outside the effect distance then add to filter (i.e. it won't match), otherwise skip (match)
                                        if nDistance > nEffectDistance then
                                            table.insert(aEffectOtherFilter, aComponents[j]);
                                        end
                                    end
                                end
                            elseif StringManager.contains(DataCommon.rangetypes, aComponents[j]) then
                                table.insert(aEffectRangeFilter, aComponents[j]);
                            else
                                table.insert(aEffectOtherFilter, aComponents[j]);
                            end

                            j = j + 1;
                        end

                        -- Do additional check for save types in aEffectOtherFilter - this means we have not matched an effect to the save type - we should not process any filters.
                        local bProcessFilters = true;
                        if rEffectComp.type == 'SAVE' or rEffectComp.type == 'SAVERESULT' or rEffectComp.type == 'SAVEDAMAGEPER' then
                            for _, sFilterString in pairs(aEffectOtherFilter) do
                                if StringManager.contains(DataCommon.savetypes, sFilterString) then
                                    -- We have a save type in the filter - means we should not process this effect as it hasn't matched the save type.
                                    bProcessFilters = false;
                                    break
                                end
                            end
                        end

                        -- Do additional check for result level in aEffectOtherFilter - this means we have not matched the initial result level to the effect result level
                        -- - we should not process any filters.
                        if rEffectComp.type == 'SAVERESULT' or rEffectComp.type == 'SAVEDAMAGEPER' then
                            for _, sFilterString in pairs(aEffectOtherFilter) do
                                if StringManager.contains(DataCommon.checkresultlevels, sFilterString) or sFilterString == 'basic' then
                                    -- We have either a result level in the filter, or a basic save tag - means we should not process this effect as it
                                    -- hasn't matched the result level or is not a basic save.
                                    bProcessFilters = false;
                                    break
                                end
                            end
                        end

                        -- Do additional check for the proficiency level in aEffectOtherFilter - this means we have not matched the effect proficiency
                        -- level to the action proficiency level - we should not process any filters.
                        for _, sFilterString in pairs(aEffectOtherFilter) do
                            if StringManager.contains(DataCommon.proficiencyLevels, sFilterString) then
                                -- We have a proficiency level in the filter - means we should not process this effect as
                                -- it hasn't matched the proficiency level in the earlier check.
                                bProcessFilters = false;
                                break
                            end
                        end

                        -- Check for match
                        GlobalDebug.consoleObjects(
                            'EffectManagerPFRPG2.getEffectsByType.  Effect components - checking for match. bProcessFilters, bTargetedOnly, bTargeted, rEffectComp, ' ..
                            'aEffectRangeFilter, aEffectOtherFilter = ',
                            bProcessFilters, bTargetedOnly, bTargeted, rEffectComp, aEffectRangeFilter, aEffectOtherFilter);

                        local comp_match = false;
                        if rEffectComp.type:lower() == sEffectType:lower() and bProcessFilters then

                            -- Check effect targeting
                            if bTargetedOnly and not bTargeted then
                                comp_match = false;
                            else
                                comp_match = true;
                            end

                            -- Check filters
                            if #aEffectRangeFilter > 0 then
                                GlobalDebug.consoleObjects(
                                    'EffectManagerPFRPG2.getEffectsByType. Checking for aEffectRangeFilter matches.  aEffectRangeFilter, aOtherFilter, comp_match = ',
                                    aEffectRangeFilter, aOtherFilter, comp_match);
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
                                GlobalDebug.consoleObjects(
                                    'EffectManagerPFRPG2.getEffectsByType. Checking for aEffectOtherFilter matches.  aEffectOtherFilter, aOtherFilter, comp_match = ',
                                    aEffectOtherFilter, aOtherFilter, comp_match);
                                local bOtherMatch = false;
                                for _, v2 in pairs(aOtherFilter) do
                                    GlobalDebug.consoleObjects('EffectManagerPFRPG2.getEffectsByType. Checking for aEffectOtherFilter matches. v2 = ', v2);
                                    if type(v2) == 'table' then
                                        if #v2 > 0 then
                                            local bOtherTableMatch = true;
                                            for _, v3 in pairs(v2) do
                                                if not StringManager.contains(aEffectOtherFilter, v3) then
                                                    bOtherTableMatch = false;
                                                    break
                                                end
                                            end
                                            GlobalDebug.consoleObjects(
                                                'EffectManagerPFRPG2.getEffectsByType. After checking for aEffectOtherFilter matches with table. bOtherTableMatch = ',
                                                bOtherTableMatch);
                                            if bOtherTableMatch then
                                                bOtherMatch = true;
                                                break
                                            end
                                        end
                                    else
                                        if StringManager.contains(aEffectOtherFilter, v2) then
                                            bOtherMatch = true;
                                            break
                                        end
                                        -- Check for "recall knowledge" effect filter - which can be applied to any recall knowledge activity
                                        if StringManager.contains(aEffectOtherFilter, 'recall knowledge') then
                                            if string.find(v2, '^recall knowledge') then
                                                bOtherMatch = true;
                                                break
                                            end
                                        end
                                    end
                                end
                                GlobalDebug.consoleObjects(
                                    'EffectManagerPFRPG2.getEffectsByType. After checking for aEffectOtherFilter matches. bOtherMatch = ', bOtherMatch);
                                if not bOtherMatch then
                                    comp_match = false;
                                end
                            end
                        end

                        GlobalDebug.consoleObjects('EffectManagerPFRPG2.getEffectsByType. After filter checks - comp_match = ', comp_match);

                        -- *** no longer needed.  If I'd realised a way to work it into the framework to start with, it would have been much easier! ***
                        -- At this point we should have a matched or unmatched effect based off damagetype, bonustype, range and another filter (e.g. save type).
                        -- Do a final filter if aTraitFilter exists.
                        -- Currently only for saves.
                        --						if comp_match and rEffectComp.type == "SAVE" then
                        --							GlobalDebug.consoleObjects("EffectManagerPFRPG2.getEffectsByType.  We have a saving throw - checking for effect descriptors
                        --                              that don't match with a bonus or save type.
                        --                              These might be a trait descriptor.  aTraitFilter, rEffectComp.remainder = ", aTraitFilter, rEffectComp.remainder);
                        --							local temp_match = true;
                        --							for _,sEffectDescriptor in ipairs(rEffectComp.remainder) do
                        --								GlobalDebug.consoleObjects("EffectManagerPFRPG2.getEffectsByType.  Checking sEffectDescriptor for bonus or save type.
                        --                                  sEffectDescriptor = ", sEffectDescriptor);
                        --								if StringManager.contains(DataCommon.bonustypes, sEffectDescriptor) or StringManager.contains(DataCommon.savetypes, sEffectDescriptor)
                        --                                 or sEffectDescriptor == "all" then
                        --									-- Skip - we have a valid bonus type or save name - already processed earlier.
                        --									GlobalDebug.consoleObjects("EffectManagerPFRPG2.getEffectsByType.  Matched to a bonus type or save name or all.  Skipping...");
                        --								else
                        --									-- We have at least one descriptor that isn't a bonus type or save name.  We now need to have a match.
                        --									GlobalDebug.consoleObjects("EffectManagerPFRPG2.getEffectsByType.  We have at least one unassigned effect descriptor -
                        --                                      assume this is a trait to match against.");
                        --									temp_match = false;
                        --									if aTraitFilter then
                        --										if StringManager.contains(aTraitFilter, sEffectDescriptor) then
                        --											temp_match = true;
                        --											break;
                        --										end
                        --									end
                        --								end
                        --							end
                        --							comp_match = temp_match;
                        --							GlobalDebug.consoleObjects("EffectManagerPFRPG2.getEffectsByType.  Exiting trait filter check.  comp_match = ", comp_match);
                        --						end

                        -- Match!
                        if comp_match then
                            nMatch = kEffectComp;
                            if nActive == 1 then
                                table.insert(results, rEffectComp);
                            end
                        end
                    end
                end -- END EFFECT COMPONENT LOOP

                -- Remove one shot effects - only if bLeaveOneShots is false
                if nMatch > 0 and not bLeaveOneShots then
                    GlobalDebug.consoleString('EffectManager: getEffectsByType.  Removing one shot effects.');
                    -- per round usage.  apply = onceperround or twiceperround
                    local sEffectApply = DB.getValue(v, 'apply', '');
                    local bUnSkip = true;
                    if sEffectApply == 'onceperround' or sEffectApply == 'twiceperround' then
                        bUnSkip = false;
                    end

                    if nActive == 2 and bUnSkip then
                        EffectManagerPFRPG2.setEffectActive(v.getNodeName());
                        -- DB.setValue(v, "isactive", "number", 1);
                    else
                        if sEffectApply == 'action' then
                            EffectManager.notifyExpire(v, 0);
                        elseif sEffectApply == 'roll' then
                            EffectManager.notifyExpire(v, 0, true);
                        elseif sEffectApply == 'single' then
                            EffectManager.notifyExpire(v, nMatch, true);
                        elseif sEffectApply == 'onceperround' or sEffectApply == 'twiceperround' then
                            EffectManagerPFRPG2.updatePerRoundEffectUsage(v.getNodeName());
                        end
                    end
                end
            end -- END TARGET CHECK
        end -- END ACTIVE CHECK
    end -- END EFFECT LOOP

    GlobalDebug.consoleObjects('EffectManagerPFRPG2.getEffectsByType.  Returning - results = ', results);

    return results;
end
-- luacheck: pop
-- Iterate through each effect

function customHasEffect(rActor, sEffect, rTarget, bTargetedOnly, bIgnoreEffectTargets)
    GlobalDebug.consoleObjects('EffectManagerPFRPG2.hasEffect. rActor, sEffect, rTarget, bTargetedOnly, bIgnoreEffectTargets = ', rActor, sEffect, rTarget,
                               bTargetedOnly, bIgnoreEffectTargets);
    if not sEffect or not rActor then
        return false;
    end
    local sLowerEffect = sEffect:lower();

    -- Iterate through each effect
    local aEffectsDBNodes = TurboManager.getMatchedEffects(rActor, sEffect);

    local _, nodeActor = ActorManager.getTypeAndNode(rActor);

    --	local aEffectsDBNodes = DB.getChildren(ActorManager.getCTNode(rActor), "effects");
    --	EffectManagerPFRPG2.hasEffect. sActorType, nodeActor = ", sActorType, nodeActor);
    --	if sActorType == "pc" then
    --		EffectManagerPFRPG2.hasEffect.  Effects node children = ", DB.getChildren(nodeActor, "effects"));
    --		for _,vCharEffectNode in pairs(DB.getChildren(nodeActor, "effects")) do
    --			table.insert(aEffectsDBNodes, vCharEffectNode);
    --		end
    --		if (rActor.nodeActionEffects or "") ~= "" then
    --			local nodeActionEffects = DB.findNode(rActor.nodeActionEffects);
    --			if nodeActionEffects then
    --				for _,vActionEffectNode in pairs(DB.getChildren(nodeActionEffects)) do
    --					table.insert(aEffectsDBNodes, vActionEffectNode);
    --				end
    --			end
    --		end
    --	end

    GlobalDebug.consoleObjects('EffectManagerPFRPG2.hasEffect.  About to parse through all effects.  aEffectsDBNodes = ', aEffectsDBNodes);

    local aMatch = {};
    for _, v in pairs(aEffectsDBNodes) do
        local nActive = DB.getValue(v, 'isactive', 0);
        if nActive ~= 0 then
            -- Parse each effect label
            local sLabel = DB.getValue(v, 'label', '');
            local bTargeted = EffectManager.isTargetedEffect(v);
            local aEffectComps = EffectManager.parseEffect(sLabel);

            aEffectComps = AutomationManagerPFRPG2.getEffectsWithVariables(nodeActor, aEffectComps);

            -- Iterate through each effect component looking for a type match
            local nMatch = 0;
            for kEffectComp, sEffectComp in ipairs(aEffectComps) do
                local rEffectComp = EffectManagerPFRPG2.parseEffectComp(sEffectComp);
                GlobalDebug.consoleObjects('EffectManagerPFRPG2.hasEffect.  Looking for a match - rEffectComp = ', rEffectComp);
                -- Check conditionals
                if rEffectComp.type == 'IF' then
                    if not EffectManagerPFRPG2.checkConditional(rActor, v, rEffectComp.remainder) then
                        break
                    end
                elseif rEffectComp.type == 'IFT' then
                    GlobalDebug.consoleObjects('EffectManagerPFRPG2.hasEffect. Have an IFT effect.  rEffectComp = ', rEffectComp);
                    if not rTarget then
                        break
                    end
                    if not EffectManagerPFRPG2.checkConditional(rTarget, v, rEffectComp.remainder, rActor) then
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
                GlobalDebug.consoleObjects('EffectManagerPFRPG2.hasEffect. We have a matched effect/condition, checking for one-off effects - nMatch, v = ',
                                           nMatch, v);
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

function customIsHiddenFromTarget(rActor, rTarget)
    -- Determine if rActor is hidden to rTarget.  Could be one of two situations:
    -- 1) rActor has an untargeted hidden effect - therefore is hidden to all.
    -- 2) rActor has a hidden effect that is targeted to one or more creatures in the CT.
    -- Do this without using standard effect checks so that we aren't creating infinite loops when using this in other effect code.

    local bIsHidden = EffectManagerPFRPG2.hasEffect(rTarget, 'hidden', rActor);
    GlobalDebug.consoleObjects('EffectManager.isHiddenFromTarget = ', bIsHidden);

    if 1 == 1 then
        return bIsHidden;
    end

    -- First check to see if rActor has a hidden effect - targeted or untargeted
    -- local aEffectsDBNodes = ActorManager.getEffects(rActor);
    -- local aMatch = {};
    -- for _, v in pairs(aEffectsDBNodes) do
    --     local nActive = DB.getValue(v, 'isactive', 0);
    --     if nActive ~= 0 then
    --         -- Parse each effect label
    --         local sLabel = DB.getValue(v, 'label', '');
    --     end
    -- end
end

function customHasEffectCondition(rActor, sEffect)
    return EffectManagerPFRPG2.hasEffect(rActor, sEffect, nil, false, true);
end

function customGetConditionValue(rActor, aEffectType, bModOnly, aFilter, rFilterActor, bTargetedOnly, aTraitFilter)
    -- Used for tracking conditions values - only the highest applies.  e.g. Frightened: 3 and Frightened: 1 do not add together.
    GlobalDebug.consoleObjects('EffectsManagerPFRPG2 - getMaxEffectsBonus.  rActor, aEffectType, bModOnly, aFilter, rFilterActor = ', rActor, aEffectType,
                               bModOnly, aFilter, rFilterActor);
    if not rActor or not aEffectType then
        return 0;
    end

    -- MAKE BONUS TYPE INTO TABLE, IF NEEDED
    if type(aEffectType) ~= 'table' then
        aEffectType = {aEffectType};
    end

    -- START WITH AN EMPTY MODIFIER TOTAL
    local nTotalMod = 0;

    for _, v in pairs(aEffectType) do
        -- GET THE MODIFIERS FOR THIS MODIFIER TYPE
        local aEffectsByType = EffectManagerPFRPG2.getEffectsByType(rActor, v, aFilter, rFilterActor, bTargetedOnly, aTraitFilter);
        -- Return all bonuses and penalties.
        -- local effbonusbytype, bonuses, penalties, nEffectSubCount = getEffectsBonusByType(rActor, v, true, aFilter, rFilterActor, bTargetedOnly, aTraitFilter, true);

        GlobalDebug.consoleObjects('EffectsManagerPFRPG2 - getMaxEffectsBonus.  After getEffectsByType - aEffectsByType = ', aEffectsByType);

        -- Iterate through each bonus and find the max.
        for _, v2 in pairs(aEffectsByType) do
            if v2.mod > nTotalMod then
                nTotalMod = v2.mod;
            end
        end
    end

    return nTotalMod;
end

function customGetConditionValueLowest(rActor, aEffectType, bModOnly, aFilter, rFilterActor, bTargetedOnly, aTraitFilter)
    -- Used for tracking the lowest condition values - e.g. HIDDENDC: 10 and HIDDENDC: 8 do not add together and should return 8.  nil returned if no conditions match.
    GlobalDebug.consoleObjects('EffectsManagerPFRPG2.getConditionValueLowest - starting.  rActor, aEffectType, bModOnly, aFilter, rFilterActor = ', rActor,
                               aEffectType, bModOnly, aFilter, rFilterActor);
    if not rActor or not aEffectType then
        return nil;
    end

    -- MAKE BONUS TYPE INTO TABLE, IF NEEDED
    if type(aEffectType) ~= 'table' then
        aEffectType = {aEffectType};
    end

    -- START WITH AN EMPTY MODIFIER TOTAL
    local nTotalMod = 999;

    for _, v in pairs(aEffectType) do
        -- GET THE MODIFIERS FOR THIS MODIFIER TYPE
        local aEffectsByType = EffectManagerPFRPG2.getEffectsByType(rActor, v, aFilter, rFilterActor, bTargetedOnly, aTraitFilter);
        -- Return all bonuses and penalties.
        -- local effbonusbytype, bonuses, penalties, nEffectSubCount = getEffectsBonusByType(rActor, v, true, aFilter, rFilterActor, bTargetedOnly, aTraitFilter, true);

        GlobalDebug.consoleObjects('EffectsManagerPFRPG2.getConditionValueLowest.  After getEffectsByType - aEffectsByType = ', aEffectsByType);

        -- Iterate through each bonus and find the max.
        for _, v2 in pairs(aEffectsByType) do
            if v2.mod < nTotalMod then
                nTotalMod = v2.mod;
            end
        end
        if nTotalMod == 999 then
            nTotalMod = nil;
        end
    end

    return nTotalMod;
end

function customGetEffectsBonusByType(rActor, aEffectType, bAddEmptyBonus, aFilter, rFilterActor, bTargetedOnly, aTraitFilter, bReturnBonusesAndPenalties)
    -- bReturnBonusesAndPenalties added to allow separate return of bonus and penalties - so that other effects can adjust the maximum bonus or worst penalty.
    -- This is because PFRPG2 treats bonuses and penalties of the same type as separate - bonuses don't stack, penalties
    -- don't stack, but they don't adjust the max bonus or max penalty.
    GlobalDebug.consoleObjects(
        'EffectManagerPFRPG2.getEffectsBonusByType.  Starting - rActor, aEffectType, bAddEmptyBonus, aFilter, ' ..
        'rFilterActor, bTargetedOnly, aTraitFilter, bReturnBonusesAndPenalties = ',
        rActor, aEffectType, bAddEmptyBonus, aFilter, rFilterActor, bTargetedOnly, aTraitFilter, bReturnBonusesAndPenalties);
    if not rActor or not aEffectType then
        if bReturnBonusesAndPenalties then
            return {}, {}, {}, 0;
        else
            return {}, 0;
        end
    end

    -- MAKE BONUS TYPE INTO TABLE, IF NEEDED
    if type(aEffectType) ~= 'table' then
        aEffectType = {aEffectType};
    end

    -- PER EFFECT TYPE VARIABLES
    local results = {};
    local bonuses = {};
    local penalties = {};
    local nEffectCount = 0;

    GlobalDebug.consoleObjects('EffectManagerPFRPG2.getEffectsBonusByType.  aEffectType = ', aEffectType);

    for _, v in pairs(aEffectType) do
        -- LOOK FOR EFFECTS THAT MATCH BONUSTYPE
        local aEffectsByType = EffectManagerPFRPG2.getEffectsByType(rActor, v, aFilter, rFilterActor, bTargetedOnly, aTraitFilter);
        GlobalDebug.consoleObjects('EffectManagerPFRPG2.getEffectsBonusByType.  aEffectsByType = ', aEffectsByType);

        -- ITERATE THROUGH EFFECTS THAT MATCHED
        for _, v2 in pairs(aEffectsByType) do
            -- LOOK FOR ENERGY OR BONUS TYPES
            local dmg_type = nil;
            local mod_type = nil;
            if v2.type == 'SAVERESULT' then
                mod_type = 'nostack';
            else
                for _, v3 in pairs(v2.remainder) do
                    v3 = string.lower(v3);
                    if StringManager.contains(DataCommon.dmgtypes, v3) or StringManager.contains(DataCommon.immunetypes, v3) or v3 == 'all' then
                        dmg_type = v3;
                        break
                    elseif StringManager.contains(DataCommon.bonustypes, v3) then
                        mod_type = v3;
                        break
                    end
                end
            end

            -- IF MODIFIER TYPE IS UNTYPED, THEN APPEND MODIFIERS
            -- (SUPPORTS DICE)
            if dmg_type or not mod_type then
                -- ADD EFFECT RESULTS
                local new_key = dmg_type or '';
                local new_results = results[new_key] or {dice = {}, mod = 0, remainder = {}};

                -- BUILD THE NEW RESULT
                for _, v3 in pairs(v2.dice) do
                    table.insert(new_results.dice, v3);
                end
                if bAddEmptyBonus then -- This results in stacking.
                    new_results.mod = new_results.mod + v2.mod;
                else
                    new_results.mod = math.max(new_results.mod, v2.mod);
                end
                for _, v3 in pairs(v2.remainder) do
                    table.insert(new_results.remainder, v3);
                end

                -- SET THE NEW DICE RESULTS BASED ON ENERGY TYPE
                results[new_key] = new_results;

                -- OTHERWISE, TRACK BONUSES AND PENALTIES BY MODIFIER TYPE
                -- (IGNORE DICE, ONLY TAKE BIGGEST BONUS AND/OR PENALTY FOR EACH MODIFIER TYPE)
            else
                local bStackable = StringManager.contains(DataCommon.stackablebonustypes, mod_type);
                if v2.mod >= 0 then
                    if bStackable then
                        bonuses[mod_type] = (bonuses[mod_type] or 0) + v2.mod;
                    else
                        bonuses[mod_type] = math.max(v2.mod, bonuses[mod_type] or 0);
                    end
                elseif v2.mod < 0 then
                    if bStackable then
                        penalties[mod_type] = (penalties[mod_type] or 0) + v2.mod;
                    else
                        penalties[mod_type] = math.min(v2.mod, penalties[mod_type] or 0);
                    end
                end

            end

            -- INCREMENT EFFECT COUNT
            nEffectCount = nEffectCount + 1;
        end
    end

    GlobalDebug.consoleObjects('getEffectsBonusByType - results, bonuses, penalties = ', results, bonuses, penalties);

    if bReturnBonusesAndPenalties then
        -- results should contain untyped bonuses/penalties or damage entries - these are both stackable.
        GlobalDebug.consoleObjects('getEffectsBonusByType: returning seperated bonuses and penalties. results, bonuses, penalties, nEffectCount = ', results,
                                   bonuses, penalties, nEffectCount);
        return results, bonuses, penalties, nEffectCount;
    end
    -- COMBINE BONUSES AND PENALTIES FOR NON-ENERGY TYPED MODIFIERS
    for k2, v2 in pairs(bonuses) do
        if results[k2] then
            results[k2].mod = results[k2].mod + v2;
        else
            results[k2] = {dice = {}, mod = v2, remainder = {}};
        end
    end
    for k2, v2 in pairs(penalties) do
        if results[k2] then
            results[k2].mod = results[k2].mod + v2;
        else
            results[k2] = {dice = {}, mod = v2, remainder = {}};
        end
    end

    GlobalDebug.consoleObjects('getEffectsBonusByType: returning results, nEffectCount = ', results, nEffectCount);

    return results, nEffectCount;
end
