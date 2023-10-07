--  	Author: Ryan Hagelstrom
--	  	Copyright © 2023
--	  	This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.
--	  	https://creativecommons.org/licenses/by-sa/4.0/
--
-- luacheck: globals onInit onClose customGetEffectsByType customHasEffect  customRegisterEffectCompType
local registerEffectCompType = nil;
local getEffectsByType = nil;
local hasEffect = nil;

local _tEffectCompTypes = {};

function onInit()
    registerEffectCompType = EffectManager.registerEffectCompType;
    getEffectsByType = EffectManager.getEffectsByType;
    hasEffect = EffectManager.hasEffect;

    EffectManager.registerEffectCompType = customRegisterEffectCompType;
    EffectManager.getEffectsByType = customGetEffectsByType;
    EffectManager.hasEffect = customHasEffect;
    if Session.IsHost then
        EffectManager.registerEffectCompType('LIGHT', {bIgnoreExpire = true, bIgnoreTarget = true});
        EffectManager.registerEffectCompType('VISION', {bIgnoreExpire = true, bIgnoreTarget = true});
        EffectManager.registerEffectCompType('VISMAX', {bIgnoreExpire = true, bIgnoreTarget = true});
        EffectManager.registerEffectCompType('VISMOD', {bIgnoreExpire = true, bIgnoreTarget = true});
    end
end

function onClose()
    EffectManager.registerEffectCompType = registerEffectCompType;
    EffectManager.getEffectsByType = getEffectsByType;
    EffectManager.hasEffect = hasEffect;
end

function customRegisterEffectCompType(sEffectCompType, tParams)
    _tEffectCompTypes[sEffectCompType] = tParams;
    registerEffectCompType(sEffectCompType, tParams);
end

function customGetEffectsByType(rActor, sEffectCompType, rFilterActor, bTargetedOnly)
    if not rActor then
        return {};
    end
    local tResults = {};
    local tEffectCompParams = _tEffectCompTypes[sEffectCompType] or {};

    -- Iterate through effects
    for _, v in pairs(TurboManager.getMatchedEffects(rActor, sEffectCompType)) do
        -- Check active
        local nActive = DB.getValue(v, 'isactive', 0);
        local bActive = (tEffectCompParams.bIgnoreExpire and (nActive == 1)) or (not tEffectCompParams.bIgnoreExpire and (nActive ~= 0));

        if bActive then
            -- If effect type we are looking for supports targets, then check targeting
            local bTargetMatch;
            if tEffectCompParams.bIgnoreTarget then
                bTargetMatch = true;
            else
                local bTargeted = EffectManager.isTargetedEffect(v);
                if bTargeted then
                    bTargetMatch = EffectManager.isEffectTarget(v, rFilterActor);
                else
                    bTargetMatch = not bTargetedOnly;
                end
            end

            if bTargetMatch then
                local sLabel = DB.getValue(v, 'label', '');
                local aEffectComps = EffectManager.parseEffect(sLabel);

                -- Look for type/subtype match
                local nMatch = 0;
                for kEffectComp, sEffectComp in ipairs(aEffectComps) do
                    local rEffectComp = EffectManager.parseEffectCompSimple(sEffectComp);
                    if rEffectComp.type == sEffectCompType then
                        nMatch = kEffectComp;
                        if nActive == 1 then
                            table.insert(tResults, rEffectComp);
                        end
                    end
                end -- END EFFECT COMPONENT LOOP

                -- Remove one shot effects
                if (nMatch > 0) and not tEffectCompParams.bIgnoreExpire then
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
    -- RESULTS
    return tResults;
end

function customHasEffect(rActor, sEffect, rTarget, bTargetedOnly, bCheckEffectTargets)
    if not rActor or ((sEffect or '') == '') then
        return false;
    end
    local sLowerEffect = sEffect:lower();

    for _, v in pairs(TurboManager.getMatchedEffects(rActor, sEffect)) do
        local nActive = DB.getValue(v, 'isactive', 0);
        if nActive == 1 then
            local sLabel = DB.getValue(v, 'label', '');
            local bTargeted = false;
            if bCheckEffectTargets then
                bTargeted = EffectManager.isTargetedEffect(v);
            end
            local tEffectComps = EffectManager.parseEffect(sLabel);

            -- Iterate through each effect component looking for a type match
            for _, sEffectComp in ipairs(tEffectComps) do
                local rEffectComp = EffectManager.parseEffectCompSimple(sEffectComp);
                if rEffectComp.original:lower() == sLowerEffect then
                    if bTargeted then
                        if EffectManager.isEffectTarget(v, rTarget) then
                            return true;
                        end
                    elseif not bTargetedOnly then
                        return true;
                    end
                end
            end
        end
    end

    return false;
end
