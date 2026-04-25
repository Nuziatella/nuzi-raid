local api = require("api")
local Core = api._NuziCore or require("nuzi-core/core")

local Events = Core.Events
local Log = Core.Log
local Require = Core.Require
local RuntimeMath = Core.Runtime

local addon = {
    name = "Nuzi Raid",
    author = "Nuzi",
    version = "2.0.0",
    desc = "Custom raid frames"
}

local logger = Log.Create(addon.name)
local events = Events.Create({
    logger = logger
})
local teamEvents = Events.CreateEventWindow({
    id = "nuziRaidTeamEvents",
    logger = logger
})

local moduleErrors = {}

local function appendModuleErrors(name, errors)
    if type(errors) ~= "table" or #errors == 0 then
        moduleErrors[#moduleErrors + 1] = string.format("%s: unknown load failure", tostring(name))
        return
    end
    moduleErrors[#moduleErrors + 1] = string.format(
        "%s: %s",
        tostring(name),
        Require.DescribeErrors(errors)
    )
end

local modules, failures = Require.AddonSet("nuzi-raid", {
    "shared",
    "raidframes",
    "settings_ui",
    "runtime",
    "compat"
})

for name, failure in pairs(failures or {}) do
    appendModuleErrors(name, failure.errors)
end

local Shared = modules.shared
local RaidFrames = modules.raidframes
local SettingsUi = modules.settings_ui
local Runtime = modules.runtime
local Compat = modules.compat

local vitalsElapsedMs = 0
local metadataElapsedMs = 0
local rosterElapsedMs = 0
local rosterForceElapsedMs = 0

local UPDATE_INTERVALS = {
    vitals_ms = 100,
    metadata_ms = 900,
    roster_ms = 500,
    force_roster_ms = 2000
}

local function modulesReady()
    return Shared ~= nil and RaidFrames ~= nil and SettingsUi ~= nil and Runtime ~= nil and Compat ~= nil
end

local function logModuleErrors()
    if #moduleErrors == 0 then
        return
    end
    for _, detail in ipairs(moduleErrors) do
        logger:Err("Module load error: " .. tostring(detail))
    end
end

local function logRuntimeSummary()
    local runtime = Compat.Get()
    local caps = runtime.caps or {}
    logger:Info(string.format(
        "Runtime raidframes=%s sliders=%s raid_manager=%s target_frame=%s",
        caps.raidframes_supported and "yes" or "no",
        caps.slider_factory and "yes" or "no",
        caps.stock_raid_manager and "yes" or "no",
        caps.stock_target_frame and "yes" or "no"
    ))
    for _, warning in ipairs(runtime.warnings or {}) do
        logger:Info(warning)
    end
    for _, blocker in ipairs(runtime.blockers or {}) do
        logger:Err(tostring(blocker))
    end
end

local function applyAll()
    local settings = Shared.GetSettings()
    RaidFrames.SetEnabled(settings.enabled)
    RaidFrames.OnUpdate(settings, {
        update_vitals = true,
        update_metadata = true,
        update_roster = true,
        force_roster = true,
        update_target = true
    })
    SettingsUi.Refresh()
end

local function buildActions()
    return {
        apply = function()
            applyAll()
            return true, "Applied"
        end,
        save = function()
            return Shared.SaveSettings()
        end,
        backup = function()
            return Shared.SaveSettingsBackup()
        end,
        import = function()
            local ok, detail = Shared.ImportLatestBackup()
            if ok then
                applyAll()
            end
            return ok, detail
        end,
        reset_raid = function()
            Shared.ResetRaidSettings()
            applyAll()
            return true, "Raid settings reset"
        end,
        reset_style = function()
            Shared.ResetStyleSettings()
            applyAll()
            return true, "Style settings reset"
        end,
        reset_all = function()
            Shared.ResetAllSettings()
            applyAll()
            return true, "All settings reset"
        end
    }
end

local function onUpdate(dt)
    local delta = RuntimeMath.NormalizeDeltaMs(dt)
    vitalsElapsedMs = vitalsElapsedMs + delta
    metadataElapsedMs = metadataElapsedMs + delta
    rosterElapsedMs = rosterElapsedMs + delta
    rosterForceElapsedMs = rosterForceElapsedMs + delta

    local updateVitals = vitalsElapsedMs >= UPDATE_INTERVALS.vitals_ms
    local updateMetadata = metadataElapsedMs >= UPDATE_INTERVALS.metadata_ms
    local updateRoster = rosterElapsedMs >= UPDATE_INTERVALS.roster_ms
    local forceRoster = rosterForceElapsedMs >= UPDATE_INTERVALS.force_roster_ms
    local updateTarget = updateVitals

    if not updateVitals and not updateMetadata and not updateRoster then
        return
    end

    if updateVitals then
        vitalsElapsedMs = 0
    end
    if updateMetadata then
        metadataElapsedMs = 0
    end
    if updateRoster then
        rosterElapsedMs = 0
    end
    if forceRoster then
        rosterForceElapsedMs = 0
    end

    local ok, err = pcall(function()
        RaidFrames.OnUpdate(Shared.GetSettings(), {
            update_vitals = updateVitals,
            update_metadata = updateMetadata,
            update_roster = updateRoster,
            force_roster = forceRoster,
            update_target = updateTarget
        })
    end)
    if not ok then
        logger:Err("RaidFrames.OnUpdate failed: " .. tostring(err))
    end
end

local function onUiReloaded()
    vitalsElapsedMs = 0
    metadataElapsedMs = 0
    rosterElapsedMs = 0
    rosterForceElapsedMs = 0
    Compat.Probe(true)
    RaidFrames.Unload()
    SettingsUi.Unload()
    RaidFrames.Init(Shared.GetSettings())
    RaidFrames.SetEnabled(Shared.GetSettings().enabled)
    SettingsUi.Init(buildActions())
    applyAll()
end

local function refreshRaidFrames(flags)
    if Shared == nil or RaidFrames == nil then
        return
    end
    local ok, err = pcall(function()
        RaidFrames.OnUpdate(Shared.GetSettings(), flags or {
            update_vitals = true,
            update_metadata = false,
            update_roster = false,
            force_roster = false,
            update_target = false
        })
    end)
    if not ok then
        logger:Err("Event-driven refresh failed: " .. tostring(err))
    end
end

local function onTeamRosterChanged()
    refreshRaidFrames({
        update_vitals = true,
        update_metadata = true,
        update_roster = true,
        force_roster = true,
        update_target = true
    })
end

local function onChatMessage(_, _, _, senderName, message)
    local raw = tostring(message or "")
    local playerName = Runtime.GetPlayerName()
    if playerName ~= nil and senderName ~= nil and tostring(senderName) ~= "" and tostring(senderName) ~= tostring(playerName) then
        return
    end
    if raw == "!pr" or raw == "!polarraid" or raw == "!nuziraid" then
        SettingsUi.Toggle()
    end
end

local function onLoad()
    if not modulesReady() then
        logModuleErrors()
        logger:Err("Failed to load one or more modules")
        return
    end

    Shared.LoadSettings()
    Compat.Probe(true)
    logRuntimeSummary()
    RaidFrames.Init(Shared.GetSettings())
    RaidFrames.SetEnabled(Shared.GetSettings().enabled)
    SettingsUi.Init(buildActions())
    applyAll()

    events:On("UPDATE", onUpdate)
    events:On("UI_RELOADED", onUiReloaded)
    events:On("CHAT_MESSAGE", onChatMessage)
    events:OptionalOn("TEAM_MEMBERS_CHANGED", onTeamRosterChanged)
    teamEvents:OptionalOn("TEAM_MEMBER_DISCONNECTED", onTeamRosterChanged)
    teamEvents:OptionalOn("TEAM_ROLE_CHANGED", onTeamRosterChanged)

    logger:Info("Loaded v" .. tostring(addon.version) .. ". Use the NR button for settings.")
end

local function onUnload()
    events:ClearAll()
    teamEvents:ClearAll()
    if RaidFrames ~= nil then
        RaidFrames.Unload()
    end
    if SettingsUi ~= nil then
        SettingsUi.Unload()
    end
end

addon.OnLoad = onLoad
addon.OnUnload = onUnload

return addon
