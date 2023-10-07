--  	Author: Ryan Hagelstrom
--	  	Copyright © 2023
--	  	This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 International License.
--	  	https://creativecommons.org/licenses/by-sa/4.0/
--
-- luacheck: globals TurboManager _aTurboIgnoreTags onTabletopInit
-- luacheck: globals addCombatEffect unregisterCombatant registerEffect updateRegisteredEffect unregisterEffect setCustomEffectAdded removeCustomEffectAdded
-- luacheck: globals setCustomEffectUpdatedPrevious removeCustomEffectUpdatedPrevious setCustomEffectUpdatedCurrent removeCustomEffectUpdatedCurrent
-- luacheck: globals setCustomEffectDeleted removeCustomEffectDeleted toggleTurbo getMatchedEffects getRulesetEffectManager turboTest
-- The only way this will ever work is if we are very sure that we keep our
-- tables up to date with the known state of the universe. If they get out of sync
-- then the entire house of cards comes crashing down.
local aEffectAdded = {};
local aEffectUpdatedPrevious = {};
local aEffectUpdatedCurrent = {};
local aEffectDeleted = {};

-- Tag is rEffectComp.type uppercase if exists and ignoring conditional tags else
-- the first clause (element) rEffectComp[1] which is everything between the ;
-- The latter is ignored if containing a space.
-- tEffectsCT[Actor CT Node Path][Tags][Effect Node Path]
local tEffectsCT = {};

local tLabelOutstandingLookup = {};

-- tEffectsLookup[Effect Node Path][Tags]  -- The Actor is implied as it is the parent of the effect
local tEffectsLookup = {};

-- Global tags to ignore
_aTurboIgnoreTags = {'', 'IF', 'IFT'};

local function onCustomEffectAdded(nodeEffect)
    for _, fCustomEffectAdded in ipairs(aEffectAdded) do
        fCustomEffectAdded(nodeEffect);
    end
end

local function onCustomEffectUpdatedPrevious(sActor, sTag, sPath)
    if next(aEffectUpdatedPrevious) then
        for _, fCustomEffectUpdatedPrevious in ipairs(aEffectUpdatedPrevious) do
            fCustomEffectUpdatedPrevious(sActor, sTag, sPath);
        end
    end
end

local function onCustomEffectUpdatedCurrent(sActor, sTag, sPath)
    if next(aEffectUpdatedCurrent) then
        for _, fCustomEffectUpdatedCurrent in ipairs(aEffectUpdatedCurrent) do
            fCustomEffectUpdatedCurrent(sActor, sTag, sPath);
        end
    end
end

local function onCustomEffectDeleted(nodeEffect)
    for _, fCustomEffectDeleted in ipairs(aEffectDeleted) do
        fCustomEffectDeleted(nodeEffect);
    end
end

local function updateEffectsTables(sActor, sLabel, sPath)
    local tEffectComps = EffectManager.parseEffect(sLabel);
    for _, sComp in pairs(tEffectComps) do
        local rEffectComp = EffectManager.parseEffectCompSimple(sComp);
        local sTag = rEffectComp.type;
        if sTag == '' then
            sTag = rEffectComp.original;
        end
        sTag = sTag:upper();
        if not StringManager.contains(_aTurboIgnoreTags, sTag) then
            local aTags = tEffectsCT[sActor];
            if not aTags or not aTags[sTag] then
                tEffectsCT[sActor][sTag] = {};
                tEffectsCT[sActor][sTag][sPath] = true;
            else
                tEffectsCT[sActor][sTag][sPath] = true;
            end
            tEffectsLookup[sPath][sTag] = true;
            onCustomEffectUpdatedCurrent(sActor, sTag, sPath);
        end
    end
end

local function updateRegisteredEffectGuarded(nodeLabel)
    local nodeEffect = DB.getChild(nodeLabel, '..');
    local nodeActor = DB.getChild(nodeEffect, '...');
    local sActor = DB.getPath(nodeActor);
    local sLabel = DB.getValue(nodeEffect, 'label', '');
    local sPath = DB.getPath(nodeEffect);

    -- reset what is known about this effect
    if tEffectsLookup[sPath] then
        for sTag, _ in pairs(tEffectsLookup[sPath]) do
            tEffectsCT[sActor][sTag][sPath] = nil;
            if not next(tEffectsCT[sActor][sTag]) then
                tEffectsCT[sActor][sTag] = nil;
            end
            onCustomEffectUpdatedPrevious(sActor, sTag, sPath);
            tEffectsLookup[sPath][sTag] = nil;
        end
    end
    updateEffectsTables(sActor, sLabel, sPath);
end

local function registerEffectGuarded(nodeEffect, nodeChild)
    local nodeLabel = DB.getChild(DB.getPath(nodeEffect, 'label'));

    -- Empty Effect with no label yet
    if not nodeLabel and not nodeChild then
        DB.addHandler(DB.getPath(nodeEffect), 'onChildAdded', registerEffect);
        tLabelOutstandingLookup[DB.getPath(nodeEffect)] = true;
        return;
    elseif not nodeLabel then
        return;
    end
    local sPath = DB.getPath(nodeEffect);
    local sActor = DB.getPath(DB.getChild(nodeEffect, '...'));

    DB.removeHandler(sPath, 'onChildAdded', registerEffect);
    tLabelOutstandingLookup[sPath] = nil;

    tEffectsLookup[sPath] = {};
    if not tEffectsCT[sActor] then
        tEffectsCT[sActor] = {};
    end

    DB.addHandler(DB.getPath(nodeLabel), 'onUpdate', updateRegisteredEffect);
    DB.addHandler(sPath, 'onDelete', unregisterEffect);

    local sLabel = DB.getValue(nodeEffect, 'label', '');
    if sLabel == '' then
        return;
    end
    updateEffectsTables(sActor, sLabel, sPath);
    if nodeChild == nodeLabel then
        DB.addHandler(DB.getPath(nodeEffect), 'onChildAdded', registerEffect);
    end
    onCustomEffectAdded(nodeEffect);
end

local function unregisterEffectGuarded(nodeEffect)
    local nodeLabel = DB.getChild(nodeEffect, 'label');
    local sPath = DB.getPath(nodeEffect);
    local sActor = DB.getPath(DB.getChild(nodeEffect, '...'));
    onCustomEffectDeleted(nodeLabel);
    for sTag, _ in pairs(tEffectsLookup[sPath]) do
        DB.removeHandler(DB.getPath(nodeLabel), 'onUpdate', updateRegisteredEffect);
        DB.removeHandler(sPath, 'onDelete', unregisterEffect);
        tEffectsCT[sActor][sTag][sPath] = nil;
        if not next(tEffectsCT[sActor][sTag]) then
            tEffectsCT[sActor][sTag] = nil;
        end
    end
    tEffectsLookup[sPath] = nil;
end

local function initRegisterEffects()
    local ctEntries = CombatManager.getCombatantNodes();
    for _, nodeCT in pairs(ctEntries) do
        for _, nodeEffect in pairs(DB.getChildren(nodeCT, 'effects')) do
            registerEffect(nodeEffect);
        end
    end
end

local function destroyEffects()
    for sPath, _ in pairs(tLabelOutstandingLookup) do
        DB.removeHandler(sPath, 'onChildAdded', registerEffect);
        Debug.console('Delete oustanding handler: ' .. sPath);
    end
    for sPath, _ in pairs(tEffectsLookup) do
        local nodeEffect = DB.findNode(sPath)
        unregisterEffectGuarded(nodeEffect);
    end
    tEffectsCT = {};
    tLabelOutstandingLookup = {};
    tEffectsLookup = {};
end

function addCombatEffect(_, nodeEffect)
    registerEffect(nodeEffect);
end
-- Is this called before the nodes delete? Will have to test
function unregisterCombatant(nodeCT)
    tEffectsCT[DB.getPath(nodeCT)] = nil;
end

function registerEffect(nodeEffect, nodeChild)
    registerEffectGuarded(nodeEffect, nodeChild);
end

function updateRegisteredEffect(nodeLabel)
    updateRegisteredEffectGuarded(nodeLabel);
end

function unregisterEffect(nodeEffect)
    unregisterEffectGuarded(nodeEffect);
end

function setCustomEffectAdded(f)
    table.insert(aEffectAdded, f);
end

function removeCustomEffectAdded(f)
    for kCustomEffectAdded, fCustomEffectAdded in ipairs(aEffectAdded) do
        if fCustomEffectAdded == f then
            table.remove(aEffectAdded, kCustomEffectAdded);
        end
    end
end

function setCustomEffectUpdatedPrevious(f)
    table.insert(aEffectUpdatedPrevious, f);
end

function removeCustomEffectUpdatedPrevious(f)
    for kCustomEffectUpdatedPrevious, fCustomEffectUpdatedPrevious in ipairs(aEffectUpdatedPrevious) do
        if fCustomEffectUpdatedPrevious == f then
            table.remove(aEffectUpdatedPrevious, kCustomEffectUpdatedPrevious);
        end
    end
end

function setCustomEffectUpdatedCurrent(f)
    table.insert(aEffectUpdatedCurrent, f);
end

function removeCustomEffectUpdatedCurrent(f)
    for kCustomEffectUpdatedCurrent, fCustomEffectUpdatedCurrent in ipairs(aEffectUpdatedCurrent) do
        if fCustomEffectUpdatedCurrent == f then
            table.remove(aEffectUpdatedCurrent, kCustomEffectUpdatedCurrent);
        end
    end
end

function setCustomEffectDeleted(f)
    table.insert(aEffectDeleted, f);
end

function removeCustomEffectDeleted(f)
    for kCustomEffectDeleted, fCustomEffectDeleted in ipairs(aEffectDeleted) do
        if fCustomEffectDeleted == f then
            table.remove(aEffectDeleted, kCustomEffectDeleted);
        end
    end
end

function toggleTurbo()
    if OptionsManager.isOption('TURBO', 'on') then
        initRegisterEffects();
    else
        destroyEffects();
    end
end

-- Keep a table of all the tags on all the actors and the database node path
-- Searching only effects that have the tag that is being searched for is highly
-- probable to match unless filtered by a filter or conditional. Far more efficient
-- than a liner search of everything. In summary returns mostly empty sets or sets
-- with very few elements.
function getMatchedEffects(rActor, sTag)
    local aReturn = {};
    if sTag == 'XDMQPVZ' then
        local _, sRuleset = getRulesetEffectManager();
        local rMessage = {};
        rMessage.icon = 'Turbo';
        rMessage.font = 'systemfont';
        rMessage.text = 'Turbo Active using ruleset effect manager: ' .. sRuleset;
        Comm.addChatMessage(rMessage);
    end
    local nodeCT = ActorManager.getCTNode(rActor);
    if nodeCT and OptionsManager.isOption('TURBO', 'on') then
        local sActor = DB.getPath(nodeCT);
        local aEffectPaths = {};
        local aTags = tEffectsCT[sActor];
        sTag = sTag:upper();
        if aTags and aTags[sTag] then
            aEffectPaths = tEffectsCT[sActor][sTag];
        end
        for sEffectPath, _ in pairs(aEffectPaths) do
            table.insert(aReturn, DB.findNode(sEffectPath));
        end
    else
        if not nodeCT then
            Debug.console('Can\'t find CT node: ', rActor);
        end
        aReturn = DB.getChildren(nodeCT, 'effects');
    end
    return aReturn;
end

function onInit()
    Comm.registerSlashHandler('turbo_test', turboTest);
    CombatManager.setCustomAddCombatantEffectHandler(addCombatEffect);
    CombatManager.setCustomDeleteCombatantHandler(unregisterCombatant);

    OptionsManager.registerOption2('TURBO', false, 'option_header_game', 'option_Turbo', 'option_entry_cycler',
                                   {labels = 'option_val_off', values = 'off', baselabel = 'option_val_on', baseval = 'on', default = 'on'});

    OptionsManager.registerCallback('TURBO', toggleTurbo);
end

function getRulesetEffectManager()
    local Manager;
    local sRuleset = User.getRulesetName()
    if sRuleset == '5E' then
        Manager = EffectManager5E;
    elseif sRuleset == '4E' then
        Manager = EffectManager4E;
    elseif sRuleset == '3.5E' or sRuleset == 'PFRPG' then
        Manager = EffectManager35E;
    elseif sRuleset == '2E' then
        Manager = EffectManagerADND;
    elseif sRuleset == 'PFRPG2' then
        Manager = EffectManagerPFRPG2;
    elseif sRuleset == 'SFRPG' then
        Manager = EffectManagerSFRPG;
    else
        sRuleset = 'CoreRPG';
        Manager = EffectManager;
    end
    return Manager, sRuleset;
end

function turboTest()
    local fManager, _ = getRulesetEffectManager();
    local aCombatNodes = CombatManager.getCombatantNodes();
    if next(aCombatNodes) then
        local nodeCT = ActorManager.getCTNode(aCombatNodes[1]);
        local rEffect = {sUnits = '', nDuration = 0, nInit = 0, sName = 'XDMQPVZ:1', sApply = 'action', sSource = '', nGMOnly = 1};
        EffectManager.addEffect('', '', nodeCT, rEffect, false);
        local rActor = ActorManager.resolveActor(nodeCT);
        fManager.getEffectsByType(rActor, 'XDMQPVZ');
    end
end

function onTabletopInit()
    initRegisterEffects();
end

function onClose()
    destroyEffects();
    OptionsManager.unregisterCallback('TURBO', toggleTurbo);
end
