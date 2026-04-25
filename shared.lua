local api = require("api")
local Core = api._NuziCore or require("nuzi-core/core")

local Log = Core.Log
local Runtime = Core.Runtime
local Settings = Core.Settings

local Shared = {}

Shared.CONSTANTS = {
    ADDON_ID = "nuzi-raid",
    LEGACY_ADDON_ID = "polar-raid",
    TITLE = "Nuzi Raid",
    VERSION = "2.0.0",
    BUTTON_ID = "polarRaidSettingsButton",
    WINDOW_ID = "polarRaidSettingsWindow",
    SETTINGS_FILE_PATH = "nuzi-raid/.data/settings.txt",
    LEGACY_SETTINGS_FILE_PATH = "polar-raid/settings.txt",
    LEGACY_LOCAL_SETTINGS_FILE_PATH = "nuzi-raid/settings.txt",
    LEGACY_POLAR_UI_SETTINGS_PATH = "polar-ui/settings.txt",
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
        hp_texture_mode = "stock",
        bar_colors_enabled = true,
        hp_fill_color = { 44, 168, 84, 255 },
        hp_bar_color = { 44, 168, 84, 255 },
        hp_after_color = { 44, 168, 84, 255 },
        mp_fill_color = { 86, 198, 239, 255 },
        mp_bar_color = { 86, 198, 239, 255 },
        mp_after_color = { 86, 198, 239, 255 }
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
        show_role_badge = false,
        hide_dps_role_badge = true,
        use_team_role_colors = false,
        use_role_name_colors = true,
        use_class_name_colors = false,
        show_value_text = true,
        value_text_mode = "missing",
        value_font_size = 12,
        value_offset_x = 0,
        value_offset_y = 0,
        show_status_text = true,
        range_fade_enabled = true,
        range_max_distance = 80,
        range_alpha_pct = 45,
        dead_alpha_pct = 30,
        offline_alpha_pct = 20,
        show_debuff_alert = true,
        prefer_dispel_alert = true,
        show_target_highlight = true,
        show_group_headers = false,
        group_header_font_size = 11,
        bar_style_mode = "shared",
        gap_x = 2,
        gap_y = 2,
        grid_columns = 8,
        bg_enabled = true,
        bg_alpha_pct = 100
    }
}

Shared.CONSTANTS.DEFAULT_SETTINGS = Shared.DEFAULT_SETTINGS
Shared.CONSTANTS.LEGACY_SETTINGS_FILE_PATHS = {
    Shared.CONSTANTS.LEGACY_LOCAL_SETTINGS_FILE_PATH,
    Shared.CONSTANTS.LEGACY_SETTINGS_FILE_PATH
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

local function buildMigratedSettings(legacy)
    local out = Runtime.DeepCopy(Shared.DEFAULT_SETTINGS)
    if type(legacy) ~= "table" then
        return out, false
    end
    if type(legacy.raidframes) == "table" then
        Runtime.MergeInto(out.raidframes, legacy.raidframes)
    end
    if type(legacy.style) == "table" then
        Runtime.MergeInto(out.style, legacy.style)
    end
    if type(legacy.role) == "table" then
        Runtime.MergeInto(out.role, legacy.role)
    end
    if legacy.drag_requires_shift ~= nil then
        out.drag_requires_shift = legacy.drag_requires_shift and true or false
    end
    out.migrated_from_polar_ui = true
    return out, true
end

local function normalizeSettings(settings)
    if type(settings) ~= "table" then
        return false
    end

    local changed = false

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

    if type(settings.raidframes) == "table" and settings.raidframes.right_click_fallback_menu ~= nil then
        settings.raidframes.right_click_fallback_menu = nil
        changed = true
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

local function tryLoadPolarUiMigration()
    local parsed = nil
    parsed = Settings.ReadFlexibleTable(Shared.CONSTANTS.LEGACY_POLAR_UI_SETTINGS_PATH, {
        mode = "serialized_then_flat",
        raw_text_fallback = true
    })
    if type(parsed) ~= "table" or not tableHasEntries(parsed) then
        return nil
    end

    local migrated, didMigrate = buildMigratedSettings(parsed)
    if not didMigrate then
        return nil
    end
    logger:Info("Migrating settings from polar-ui/settings.txt")
    return migrated
end

local function tryLoadApiSeed()
    local current = readApiSettings(Shared.CONSTANTS.ADDON_ID)
    if type(current) == "table" then
        logger:Info("Seeding settings from api.GetSettings(" .. Shared.CONSTANTS.ADDON_ID .. ")")
        return current
    end

    local legacy = readApiSettings(Shared.CONSTANTS.LEGACY_ADDON_ID)
    if type(legacy) == "table" then
        logger:Info("Seeding settings from api.GetSettings(" .. Shared.CONSTANTS.LEGACY_ADDON_ID .. ")")
        return legacy
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

    local polarUiSettings = tryLoadPolarUiMigration()
    if type(polarUiSettings) == "table" then
        return saveLoadedSettings(polarUiSettings, Shared.CONSTANTS.LEGACY_POLAR_UI_SETTINGS_PATH)
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
