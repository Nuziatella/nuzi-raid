local api = require("api")
local Core = api._NuziCore or require("nuzi-core/core")

local Log = Core.Log
local Runtime = Core.Runtime
local Settings = Core.Settings

local Shared = {}

Shared.CONSTANTS = {
    ADDON_ID = "nuzi-raid",
    TITLE = "Nuzi Raid",
    VERSION = "2.0.5",
    BUTTON_ID = "nuziRaidSettingsButton",
    WINDOW_ID = "nuziRaidSettingsWindow",
    SETTINGS_FILE_PATH = "nuzi-raid/.data/settings.txt",
    LEGACY_LOCAL_SETTINGS_FILE_PATH = "nuzi-raid/settings.txt",
    SETTINGS_BACKUP_INDEX_FILE_PATH = "nuzi-raid/.data/backups/index.txt",
    LEGACY_SETTINGS_BACKUP_INDEX_FILE_PATH = "nuzi-raid/backups/index.txt",
    SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH = "nuzi-raid/.data/settings_backup_index.txt",
    LEGACY_SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH = "nuzi-raid/settings_backup_index.txt",
    SETTINGS_BACKUP_DIR = "nuzi-raid/.data/backups",
    SETTINGS_BACKUP_FILE_PATH = "nuzi-raid/.data/settings_backup.txt",
    LEGACY_SETTINGS_BACKUP_FILE_PATH = "nuzi-raid/settings_backup.txt"
}

Shared.DEFAULT_SETTINGS = {
    enabled = true,
    drag_requires_shift = true,
    button_x = 90,
    button_y = 420,
    button_size = 48,
    window_x = 520,
    window_y = 90,
    role = {
        tanks = {
            "Abolisher",
            "Skullknight"
        },
        healers = {
            "Cleric",
            "Hierophant"
        }
    },
    style = {
        hp_texture_mode = "raid",
        bar_colors_enabled = true,
        hp_fill_color = { 44, 168, 84, 255 },
        hp_bar_color = { 44, 168, 84, 255 },
        hp_after_color = { 44, 168, 84, 255 },
        mp_fill_color = { 86, 198, 239, 255 },
        mp_bar_color = { 86, 198, 239, 255 },
        mp_after_color = { 86, 198, 239, 255 },
        bloodlust_team_color = { 255, 45, 0, 255 },
        name_color = { 255, 255, 255, 255 },
        value_color = { 255, 255, 255, 255 },
        status_color = { 220, 150, 150, 255 },
        background_color = { 13, 13, 15, 255 },
        target_highlight_color = { 255, 230, 120, 72 },
        debuff_alert_color = { 255, 68, 68, 235 },
        dispellable_debuff_color = { 255, 210, 72, 235 },
        defender_role_color = { 255, 210, 70, 255 },
        healer_role_color = { 255, 120, 205, 255 },
        attacker_role_color = { 255, 95, 95, 255 },
        undecided_role_color = { 110, 170, 255, 255 },
        offline_bar_color = { 100, 100, 100, 255 },
        dead_bar_color = { 150, 70, 70, 255 },
        offline_text_color = { 180, 180, 180, 255 },
        dead_text_color = { 220, 150, 150, 255 }
    },
    raidframes = {
        enabled = true,
        hide_stock = false,
        layout_mode = "party_columns",
        x = 600,
        y = 250,
        alpha_pct = 100,
        width = 100,
        hp_height = 30,
        mp_height = 0,
        name_font_size = 14,
        show_name = true,
        name_max_chars = 0,
        name_padding_left = 2,
        name_offset_x = 0,
        name_offset_y = 0,
        show_role_prefix = false,
        show_class_icon = false,
        icon_size = 12,
        icon_gap = 2,
        icon_offset_x = 0,
        icon_offset_y = 0,
        class_offset_x = 0,
        class_offset_y = 0,
        show_leader_badge = true,
        leader_badge_size = 11,
        show_role_badge = false,
        role_offset_x = 0,
        role_offset_y = 0,
        hide_dps_role_badge = true,
        use_team_role_colors = true,
        use_role_name_colors = true,
        use_class_name_colors = false,
        text_colors_override_role_colors = false,
        show_value_text = true,
        value_text_mode = "missing",
        value_font_size = 12,
        value_offset_x = 0,
        value_offset_y = 0,
        show_status_text = true,
        status_offset_x = 0,
        status_offset_y = 0,
        range_fade_enabled = true,
        range_max_distance = 80,
        range_alpha_pct = 45,
        dead_alpha_pct = 30,
        offline_alpha_pct = 20,
        show_debuff_alert = true,
        debuff_size = 8,
        debuff_offset_x = 0,
        debuff_offset_y = 0,
        prefer_dispel_alert = true,
        show_target_highlight = true,
        show_group_headers = false,
        group_header_font_size = 11,
        bar_style_mode = "shared",
        gap_x = 2,
        gap_y = 2,
        party_columns_per_row = 5,
        party_row_gap = 10,
        grid_columns = 8,
        bg_enabled = true,
        bg_alpha_pct = 100
    }
}

Shared.CONSTANTS.DEFAULT_SETTINGS = Shared.DEFAULT_SETTINGS
Shared.CONSTANTS.LEGACY_SETTINGS_FILE_PATHS = {
    Shared.CONSTANTS.LEGACY_LOCAL_SETTINGS_FILE_PATH
}

Shared.state = {
    settings = nil
}

local logger = Log.Create(Shared.CONSTANTS.TITLE)

local function tableHasEntries(value)
    if type(value) ~= "table" then
        return false
    end
    for _ in pairs(value) do
        return true
    end
    return false
end

local function normalizeSettings(settings)
    if type(settings) ~= "table" then
        return false
    end

    local changed = false
    local oldHpBarColor = type(settings.style) == "table" and settings.style.hp_bar_color or nil
    local oldMpBarColor = type(settings.style) == "table" and settings.style.mp_bar_color or nil
    local missingHpFillColor = type(settings.style) == "table" and settings.style.hp_fill_color == nil
    local missingHpAfterColor = type(settings.style) == "table" and settings.style.hp_after_color == nil
    local missingMpFillColor = type(settings.style) == "table" and settings.style.mp_fill_color == nil
    local missingMpAfterColor = type(settings.style) == "table" and settings.style.mp_after_color == nil
    local raidBeforeDefaults = type(settings.raidframes) == "table" and settings.raidframes or nil
    local missingClassOffsetX = raidBeforeDefaults ~= nil and raidBeforeDefaults.class_offset_x == nil
    local missingClassOffsetY = raidBeforeDefaults ~= nil and raidBeforeDefaults.class_offset_y == nil
    local missingRoleOffsetX = raidBeforeDefaults ~= nil and raidBeforeDefaults.role_offset_x == nil
    local missingRoleOffsetY = raidBeforeDefaults ~= nil and raidBeforeDefaults.role_offset_y == nil

    if Runtime.ApplyDefaults(settings, Shared.DEFAULT_SETTINGS) then
        changed = true
    end

    if type(settings.raidframes) ~= "table" then
        settings.raidframes = Runtime.DeepCopy(Shared.DEFAULT_SETTINGS.raidframes)
        changed = true
    end
    if type(settings.style) ~= "table" then
        settings.style = Runtime.DeepCopy(Shared.DEFAULT_SETTINGS.style)
        changed = true
    end
    if type(settings.role) ~= "table" then
        settings.role = Runtime.DeepCopy(Shared.DEFAULT_SETTINGS.role)
        changed = true
    end

    local dragRequiresShift = settings.drag_requires_shift and true or false
    if settings.drag_requires_shift ~= dragRequiresShift then
        settings.drag_requires_shift = dragRequiresShift
        changed = true
    end

    local buttonX = Runtime.Clamp(settings.button_x, 0, 4000, Shared.DEFAULT_SETTINGS.button_x)
    local buttonY = Runtime.Clamp(settings.button_y, 0, 4000, Shared.DEFAULT_SETTINGS.button_y)
    local buttonSize = Runtime.Clamp(settings.button_size, 32, 96, Shared.DEFAULT_SETTINGS.button_size)
    local leaderBadgeSize = Runtime.Clamp(settings.raidframes.leader_badge_size, 6, 32, Shared.DEFAULT_SETTINGS.raidframes.leader_badge_size)
    local partyColumnsPerRow = Runtime.Clamp(settings.raidframes.party_columns_per_row, 1, 10, Shared.DEFAULT_SETTINGS.raidframes.party_columns_per_row)
    local partyRowGap = Runtime.Clamp(settings.raidframes.party_row_gap, 0, 160, Shared.DEFAULT_SETTINGS.raidframes.party_row_gap)
    local gridColumns = Runtime.Clamp(settings.raidframes.grid_columns, 1, 10, Shared.DEFAULT_SETTINGS.raidframes.grid_columns)
    if settings.button_x ~= buttonX then
        settings.button_x = buttonX
        changed = true
    end
    if settings.button_y ~= buttonY then
        settings.button_y = buttonY
        changed = true
    end
    if settings.button_size ~= buttonSize then
        settings.button_size = buttonSize
        changed = true
    end
    if settings.raidframes.leader_badge_size ~= leaderBadgeSize then
        settings.raidframes.leader_badge_size = leaderBadgeSize
        changed = true
    end
    if settings.raidframes.party_columns_per_row ~= partyColumnsPerRow then
        settings.raidframes.party_columns_per_row = partyColumnsPerRow
        changed = true
    end
    if settings.raidframes.party_row_gap ~= partyRowGap then
        settings.raidframes.party_row_gap = partyRowGap
        changed = true
    end
    if settings.raidframes.grid_columns ~= gridColumns then
        settings.raidframes.grid_columns = gridColumns
        changed = true
    end

    if type(settings.raidframes) == "table" and settings.raidframes.right_click_fallback_menu ~= nil then
        settings.raidframes.right_click_fallback_menu = nil
        changed = true
    end

    if type(settings.raidframes) == "table" then
        if settings.raidframes.hide_stock ~= false then
            settings.raidframes.hide_stock = false
            changed = true
        end
        if settings.raidframes.use_team_role_colors ~= true then
            settings.raidframes.use_team_role_colors = true
            changed = true
        end
        if missingClassOffsetX and settings.raidframes.icon_offset_x ~= nil then
            settings.raidframes.class_offset_x = settings.raidframes.icon_offset_x
            changed = true
        end
        if missingClassOffsetY and settings.raidframes.icon_offset_y ~= nil then
            settings.raidframes.class_offset_y = settings.raidframes.icon_offset_y
            changed = true
        end
        if missingRoleOffsetX and settings.raidframes.icon_offset_x ~= nil then
            settings.raidframes.role_offset_x = settings.raidframes.icon_offset_x
            changed = true
        end
        if missingRoleOffsetY and settings.raidframes.icon_offset_y ~= nil then
            settings.raidframes.role_offset_y = settings.raidframes.icon_offset_y
            changed = true
        end
    end

    if type(settings.style) == "table" then
        local textureMode = tostring(settings.style.hp_texture_mode or "raid")
        if textureMode ~= "raid" and textureMode ~= "pc" and textureMode ~= "npc" then
            settings.style.hp_texture_mode = "raid"
            changed = true
        end
        if missingHpFillColor and type(oldHpBarColor) == "table" then
            settings.style.hp_fill_color = Runtime.DeepCopy(oldHpBarColor)
            changed = true
        end
        if missingHpAfterColor and type(oldHpBarColor) == "table" then
            settings.style.hp_after_color = Runtime.DeepCopy(oldHpBarColor)
            changed = true
        end
        if missingMpFillColor and type(oldMpBarColor) == "table" then
            settings.style.mp_fill_color = Runtime.DeepCopy(oldMpBarColor)
            changed = true
        end
        if missingMpAfterColor and type(oldMpBarColor) == "table" then
            settings.style.mp_after_color = Runtime.DeepCopy(oldMpBarColor)
            changed = true
        end
    end

    return changed
end

local function readApiSettings(addonId)
    local normalizedId = tostring(addonId or "")
    if normalizedId == "" then
        return nil
    end

    if type(api) == "table" and type(api.GetSettings) == "function" then
        local ok, candidate = pcall(api.GetSettings, normalizedId)
        if ok and type(candidate) == "table" and tableHasEntries(candidate) then
            return candidate
        end
    end

    if type(api) == "table" and type(api.File) == "table" and type(api.File.GetSettings) == "function" then
        local ok, candidate = pcall(function()
            return api.File:GetSettings(normalizedId)
        end)
        if ok and type(candidate) == "table" and tableHasEntries(candidate) then
            return candidate
        end
    end

    return nil
end

local store = Settings.CreateAddonStore(Shared.CONSTANTS, {
    defaults = Runtime.DeepCopy(Shared.DEFAULT_SETTINGS),
    read_mode = "serialized_then_flat",
    write_mode = "serialized",
    read_raw_text_fallback = true,
    fallback_paths = Shared.CONSTANTS.LEGACY_SETTINGS_FILE_PATHS,
    skip_empty_default_tables = true,
    use_api_settings = false,
    bootstrap_if_missing = false,
    log_name = Shared.CONSTANTS.TITLE,
    normalize = function(settings)
        return normalizeSettings(settings)
    end,
    backups = {
        read_mode = "serialized_then_flat",
        write_mode = "serialized",
        read_raw_text_fallback = true,
        backup_dir = Shared.CONSTANTS.SETTINGS_BACKUP_DIR,
        backup_prefix = "settings",
        index_file_path = Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FILE_PATH,
        index_fallback_file_path = Shared.CONSTANTS.SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH,
        legacy_index_paths = {
            Shared.CONSTANTS.LEGACY_SETTINGS_BACKUP_INDEX_FILE_PATH,
            Shared.CONSTANTS.LEGACY_SETTINGS_BACKUP_INDEX_FALLBACK_FILE_PATH
        },
        latest_backup_file_path = Shared.CONSTANTS.SETTINGS_BACKUP_FILE_PATH,
        legacy_latest_paths = {
            Shared.CONSTANTS.LEGACY_SETTINGS_BACKUP_FILE_PATH
        },
        max_backups = 30
    }
})

Shared.store = store

local function saveLoadedSettings(settings, sourceLabel)
    store.settings = settings
    Shared.state.settings = settings
    local ok = store:Save()
    if not ok then
        logger:Err("Failed to save migrated settings from " .. tostring(sourceLabel))
    end
    return settings
end

local function tryLoadApiSeed()
    local current = readApiSettings(Shared.CONSTANTS.ADDON_ID)
    if type(current) == "table" then
        logger:Info("Seeding settings from api.GetSettings(" .. Shared.CONSTANTS.ADDON_ID .. ")")
        return current
    end

    return nil
end

function Shared.EnsureSettings()
    local settings = store:Ensure()
    Shared.state.settings = settings
    return settings
end

function Shared.GetSettings()
    return Shared.EnsureSettings()
end

function Shared.LoadSettings()
    local settings, meta = store:Load()
    Shared.state.settings = settings

    local hasLoadedFile = type(meta) == "table" and type(meta.source_kind) == "string" and meta.source_kind ~= "none"
    if hasLoadedFile or (type(meta) == "table" and meta.has_primary) then
        return settings
    end

    local apiSeed = tryLoadApiSeed()
    if type(apiSeed) == "table" then
        normalizeSettings(apiSeed)
        return saveLoadedSettings(apiSeed, "api settings")
    end

    settings = Shared.EnsureSettings()
    store:Save()
    return settings
end

function Shared.ResetRaidSettings()
    Shared.EnsureSettings().raidframes = Runtime.DeepCopy(Shared.DEFAULT_SETTINGS.raidframes)
end

function Shared.ResetStyleSettings()
    Shared.EnsureSettings().style = Runtime.DeepCopy(Shared.DEFAULT_SETTINGS.style)
end

function Shared.ResetAllSettings()
    Shared.state.settings = Runtime.DeepCopy(Shared.DEFAULT_SETTINGS)
    store.settings = Shared.state.settings
end

function Shared.SaveSettings()
    local settings = Shared.EnsureSettings()
    store.settings = settings
    return store:Save()
end

function Shared.SaveSettingsBackup()
    return store:SaveBackup()
end

function Shared.ImportLatestBackup()
    local ok, detail = store:ImportLatestBackup()
    if ok then
        Shared.state.settings = store.settings
    end
    return ok, detail
end

return Shared
