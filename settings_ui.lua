local api = require("api")
local Require = require("nuzi-core/require")

local function loadModule(name)
    local mod = Require.Addon("nuzi-raid", name)
    return mod
end

local Shared = loadModule("shared")
local Compat = loadModule("compat")
local CreateNuziSlider = nil
local globals = type(_G) == "table" and _G or nil
local ALIGN_REF = type(ALIGN) == "table" and ALIGN or (globals ~= nil and globals.ALIGN or nil)
local BUTTON_BASIC_REF = type(BUTTON_BASIC) == "table" and BUTTON_BASIC or (globals ~= nil and globals.BUTTON_BASIC or nil)
local DEFAULT_CONSTANTS = {
    BUTTON_ID = "nuziRaidSettingsButton",
    WINDOW_ID = "nuziRaidSettingsWindow",
    TITLE = "Nuzi Raid",
    LAUNCHER_ICON = "nuzi-raid/icon.png"
}
local DEFAULT_HP_COLOR = { 44, 168, 84, 255 }
local DEFAULT_MP_COLOR = { 86, 198, 239, 255 }
local COLOR_GROUPS = {
    { tab = "bars", key = "hp_after_color", prefix = "hp_after", id_prefix = "HpAfter", label = "HP afterimage", description = "Missing HP/backfill color behind the live HP bar.", preview = "bar", fallback = DEFAULT_HP_COLOR },
    { tab = "bars", key = "mp_fill_color", alias = "mp_bar_color", prefix = "mp_fill", id_prefix = "MpFill", label = "MP bar", description = "Main MP fill color.", preview = "bar", fallback = DEFAULT_MP_COLOR },
    { tab = "bars", key = "mp_after_color", alias = "mp_fill_color", prefix = "mp_after", id_prefix = "MpAfter", label = "MP afterimage", description = "Missing MP/backfill color behind the live MP bar.", preview = "bar", fallback = DEFAULT_MP_COLOR },
    { tab = "bars", key = "bloodlust_team_color", prefix = "bloodlust_team", id_prefix = "BloodlustTeam", label = "Bloodlust team", description = "Whole HP bar color for bloodlusted raid members.", preview = "bar", fallback = { 255, 45, 0, 255 } },
    { tab = "bars", key = "defender_role_color", prefix = "defender", id_prefix = "Defender", label = "Tank role", description = "Tank HP bar color.", preview = "bar", fallback = { 255, 210, 70, 255 } },
    { tab = "bars", key = "healer_role_color", prefix = "healer", id_prefix = "Healer", label = "Healer role", description = "Healer HP bar color.", preview = "bar", fallback = { 255, 120, 205, 255 } },
    { tab = "bars", key = "attacker_role_color", prefix = "attacker", id_prefix = "Attacker", label = "DPS role", description = "DPS HP bar color.", preview = "bar", fallback = { 255, 95, 95, 255 } },
    { tab = "bars", key = "undecided_role_color", prefix = "undecided", id_prefix = "Undecided", label = "Unknown role", description = "Unassigned HP bar color.", preview = "bar", fallback = { 110, 170, 255, 255 } },
    { tab = "bars", key = "offline_bar_color", prefix = "offline_bar", id_prefix = "OfflineBar", label = "Offline bar", description = "Bar color for offline players.", preview = "bar", fallback = { 100, 100, 100, 255 } },
    { tab = "bars", key = "dead_bar_color", prefix = "dead_bar", id_prefix = "DeadBar", label = "Dead bar", description = "Bar color for dead players.", preview = "bar", fallback = { 150, 70, 70, 255 } },
    { tab = "text", key = "name_color", prefix = "name", id_prefix = "Name", label = "Name text", description = "Default raid member name text.", preview = "text", fallback = { 255, 255, 255, 255 } },
    { tab = "text", key = "value_color", prefix = "value", id_prefix = "Value", label = "HP/MP text", description = "Value and percent text.", preview = "text", fallback = { 255, 255, 255, 255 } },
    { tab = "text", key = "status_color", prefix = "status", id_prefix = "Status", label = "Status text", description = "Dead/offline status text.", preview = "text", fallback = { 220, 150, 150, 255 } },
    { tab = "text", key = "offline_text_color", prefix = "offline_text", id_prefix = "OfflineText", label = "Offline text", description = "Text color for offline players.", preview = "text", fallback = { 180, 180, 180, 255 } },
    { tab = "text", key = "dead_text_color", prefix = "dead_text", id_prefix = "DeadText", label = "Dead text", description = "Text color for dead players.", preview = "text", fallback = { 220, 150, 150, 255 } },
    { tab = "misc", key = "background_color", prefix = "background", id_prefix = "Background", label = "Background", description = "Frame background tint.", preview = "fill", fallback = { 13, 13, 15, 255 } },
    { tab = "misc", key = "target_highlight_color", prefix = "target", id_prefix = "Target", label = "Target highlight", description = "Current target overlay.", preview = "fill", fallback = { 255, 230, 120, 72 } },
    { tab = "misc", key = "debuff_alert_color", prefix = "debuff", id_prefix = "Debuff", label = "Debuff alert", description = "General debuff badge.", preview = "fill", fallback = { 255, 68, 68, 235 } },
    { tab = "misc", key = "dispellable_debuff_color", prefix = "dispel", id_prefix = "Dispel", label = "Dispel alert", description = "Dispellable debuff badge.", preview = "fill", fallback = { 255, 210, 72, 235 } }
}

local SettingsUi = {
    button = nil,
    window = nil,
    window_visible = false,
    controls = {},
    panels = {},
    tab_buttons = {},
    active_tab = "general",
    actions = nil,
    button_icon = nil,
    dragging_launcher = false,
    launcher_just_dragged = false,
    color_page = 1,
    color_page_count = 1,
    color_cards = {},
    color_picker = {
        active_group = nil,
        original_color = nil,
        overlay = nil,
        sliders = {},
        values = {}
    }
}

local BASE_WINDOW_WIDTH = 980
local BASE_WINDOW_HEIGHT = 884
local THEME = {
    title = { 0.98, 0.90, 0.72, 1 },
    heading = { 0.96, 0.88, 0.70, 1 },
    text = { 0.95, 0.93, 0.90, 1 },
    hint = { 0.78, 0.74, 0.68, 1 }
}
local PAGE_DEFS = {
    general = {
        label = "General",
        title = "General",
        summary = "Core behavior, launcher, save path, and status."
    },
    layout = {
        label = "Layout",
        title = "Layout",
        summary = "Party wrapping, compact grid columns, spacing, and headers."
    },
    bars = {
        label = "Bars",
        title = "Bars",
        summary = "Sizing, textures, MP colors, role HP colors, and state bars."
    },
    text = {
        label = "Text",
        title = "Text",
        summary = "Visibility, sizing, placement, and text colors."
    },
    misc = {
        label = "Misc",
        title = "Misc",
        summary = "Target highlight, debuff badge, range fade, and background."
    }
}

local sliderValue
local setStatus
local updateColorPageVisibility
local normalizeHpTextureMode

pcall(function()
    CreateNuziSlider = require("nuzi-core/ui/slider")
end)

local function safeCall(fn)
    local ok, value = pcall(fn)
    if ok then
        return value
    end
    return nil
end

local function clamp(value, minValue, maxValue, fallback)
    local numeric = tonumber(value)
    if numeric == nil then
        numeric = tonumber(fallback) or 0
    end
    if numeric < minValue then
        return minValue
    end
    if numeric > maxValue then
        return maxValue
    end
    return numeric
end

local function getSettings()
    if Shared == nil or Shared.GetSettings == nil then
        return nil
    end
    return Shared.GetSettings()
end

local function getConstants()
    if Shared ~= nil and type(Shared.CONSTANTS) == "table" then
        return Shared.CONSTANTS
    end
    return DEFAULT_CONSTANTS
end

local function safeShow(widget, show)
    if widget ~= nil and widget.Show ~= nil then
        pcall(function()
            widget:Show(show and true or false)
        end)
    end
end

local function safeSetText(widget, text)
    if widget ~= nil and widget.SetText ~= nil then
        pcall(function()
            widget:SetText(tostring(text or ""))
        end)
    end
end

local function assetPath(relativePath)
    local path = tostring(relativePath or "")
    if type(api) == "table" and type(api.baseDir) == "string" and api.baseDir ~= "" then
        local baseDir = string.gsub(api.baseDir, "\\", "/")
        return string.gsub(baseDir .. "/" .. path, "/+", "/")
    end
    return path
end

local function safeSetTexture(drawable, texturePath)
    if drawable == nil or drawable.SetTexture == nil then
        return
    end
    pcall(function()
        drawable:SetTexture(texturePath)
    end)
end

local function createImageDrawable(widget, id, texturePath, layer, width, height)
    if widget == nil then
        return nil
    end
    local drawable = nil
    pcall(function()
        if widget.CreateImageDrawable ~= nil then
            drawable = widget:CreateImageDrawable(id, layer or "artwork")
        elseif widget.CreateDrawable ~= nil then
            drawable = widget:CreateDrawable(id, layer or "artwork")
        end
    end)
    if drawable == nil then
        return nil
    end
    safeSetTexture(drawable, texturePath)
    pcall(function()
        drawable:AddAnchor("TOPLEFT", widget, 0, 0)
    end)
    if drawable.SetExtent ~= nil then
        pcall(function()
            drawable:SetExtent(width or 48, height or 48)
        end)
    end
    safeShow(drawable, true)
    return drawable
end

local function createLabel(id, parent, text, x, y, fontSize, width)
    local label = api.Interface:CreateWidget("label", id, parent)
    label:AddAnchor("TOPLEFT", x, y)
    label:SetExtent(width or 220, 18)
    label:SetText(text)
    pcall(function()
        if label.SetAutoResize ~= nil then
            label:SetAutoResize(false)
        end
        if label.SetLimitWidth ~= nil then
            label:SetLimitWidth(true)
        end
    end)
    if label.style ~= nil then
        local size = tonumber(fontSize) or 13
        local color = THEME.text
        if size >= 18 then
            color = THEME.title
        elseif size >= 15 then
            color = THEME.heading
        elseif size <= 12 then
            color = THEME.hint
        end
        if label.style.SetFontSize ~= nil then
            label.style:SetFontSize(size)
        end
        if label.style.SetAlign ~= nil and ALIGN_REF ~= nil and ALIGN_REF.LEFT ~= nil then
            label.style:SetAlign(ALIGN_REF.LEFT)
        end
        if label.style.SetColor ~= nil then
            label.style:SetColor(color[1], color[2], color[3], color[4])
        end
        if label.style.SetShadow ~= nil then
            label.style:SetShadow(true)
        end
    end
    return label
end

local function createInfoLines(prefix, parent, lines, x, y, fontSize, width, lineHeight)
    local currentY = y
    local height = tonumber(lineHeight) or 18
    for index, text in ipairs(lines or {}) do
        createLabel(tostring(prefix) .. tostring(index), parent, tostring(text or ""), x, currentY, fontSize, width)
        currentY = currentY + height
    end
    return currentY
end

local function safeSetChecked(widget, checked)
    if widget ~= nil and widget.SetChecked ~= nil then
        pcall(function()
            widget:SetChecked(checked and true or false)
        end)
    end
end

local function safeSetExtent(widget, width, height)
    if widget ~= nil and widget.SetExtent ~= nil then
        pcall(function()
            widget:SetExtent(width, height)
        end)
    end
end

local function safeSetHeight(widget, height)
    if widget ~= nil and widget.SetHeight ~= nil then
        pcall(function()
            widget:SetHeight(height)
        end)
    end
end

local function safeAnchor(widget, point, target, targetPoint, x, y)
    if widget == nil or widget.AddAnchor == nil then
        return
    end
    pcall(function()
        if widget.RemoveAllAnchors ~= nil then
            widget:RemoveAllAnchors()
        end
        if targetPoint ~= nil then
            widget:AddAnchor(point, target, targetPoint, x, y)
        else
            widget:AddAnchor(point, target, x, y)
        end
    end)
end

local function applyCommonWindowBehavior(window)
    if window == nil then
        return
    end
    safeCall(function()
        if window.SetCloseOnEscape ~= nil then
            window:SetCloseOnEscape(false)
        end
    end)
    safeCall(function()
        if window.EnableHidingIsRemove ~= nil then
            window:EnableHidingIsRemove(false)
        end
    end)
    safeCall(function()
        if window.SetUILayer ~= nil then
            window:SetUILayer("game")
        end
    end)
end

local function createEmptyChild(id, parent, x, y, width, height)
    if parent == nil then
        return nil
    end
    local widget = nil
    if parent.CreateChildWidget ~= nil then
        widget = safeCall(function()
            return parent:CreateChildWidget("emptywidget", id, 0, true)
        end)
    end
    if widget == nil and api.Interface ~= nil and api.Interface.CreateWidget ~= nil then
        widget = safeCall(function()
            return api.Interface:CreateWidget("emptywidget", id, parent)
        end)
    end
    if widget == nil then
        return nil
    end
    if widget.AddAnchor ~= nil then
        widget:AddAnchor("TOPLEFT", x or 0, y or 0)
    end
    safeSetExtent(widget, width or 100, height or 100)
    safeShow(widget, true)
    return widget
end

local function addPanelBackground(widget, alpha)
    if widget == nil then
        return nil
    end

    local background = nil
    if widget.CreateNinePartDrawable ~= nil and TEXTURE_PATH ~= nil and TEXTURE_PATH.HUD ~= nil then
        background = widget:CreateNinePartDrawable(TEXTURE_PATH.HUD, "background")
        if background ~= nil and background.SetTextureInfo ~= nil then
            background:SetTextureInfo("bg_quest")
        end
    elseif widget.CreateColorDrawable ~= nil then
        background = widget:CreateColorDrawable(0.08, 0.07, 0.05, alpha or 0.86, "background")
    end

    if background ~= nil then
        if background.SetColor ~= nil then
            background:SetColor(0.08, 0.07, 0.05, tonumber(alpha) or 0.86)
        end
        background:AddAnchor("TOPLEFT", widget, 0, 0)
        background:AddAnchor("BOTTOMRIGHT", widget, 0, 0)
    end
    return background
end

local function addPanelAccent(widget, height, alpha)
    if widget == nil or widget.CreateColorDrawable == nil then
        return nil
    end
    local accent = widget:CreateColorDrawable(0.94, 0.80, 0.48, alpha or 0.12, "overlay")
    accent:AddAnchor("TOPLEFT", widget, 0, 0)
    accent:AddAnchor("TOPRIGHT", widget, 0, 0)
    if accent.SetHeight ~= nil then
        accent:SetHeight(height or 44)
    else
        accent:SetExtent(1, height or 44)
    end
    return accent
end

local function addPanelDivider(widget, topInset, leftInset, rightInset, alpha)
    if widget == nil or widget.CreateColorDrawable == nil then
        return nil
    end
    local divider = widget:CreateColorDrawable(0.88, 0.76, 0.46, alpha or 0.16, "overlay")
    divider:AddAnchor("TOPLEFT", widget, leftInset or 18, topInset or 58)
    divider:AddAnchor("TOPRIGHT", widget, rightInset or -18, topInset or 58)
    if divider.SetHeight ~= nil then
        divider:SetHeight(1)
    else
        divider:SetExtent(1, 1)
    end
    return divider
end

local function anchorToUiParent(widget, x, y)
    if widget == nil or widget.RemoveAllAnchors == nil or widget.AddAnchor == nil then
        return
    end
    safeCall(function()
        widget:RemoveAllAnchors()
        widget:AddAnchor("TOPLEFT", "UIParent", tonumber(x) or 0, tonumber(y) or 0)
    end)
end

local function isShiftDown()
    if api ~= nil and api.Input ~= nil and api.Input.IsShiftKeyDown ~= nil then
        local ok, down = pcall(function()
            return api.Input:IsShiftKeyDown()
        end)
        if ok then
            return down and true or false
        end
    end
    return false
end

local function readOffset(widget)
    if widget == nil then
        return nil, nil
    end
    local ok = false
    local x = nil
    local y = nil
    if widget.GetOffset ~= nil then
        ok, x, y = pcall(function()
            return widget:GetOffset()
        end)
    end
    if (not ok or x == nil or y == nil) and widget.GetEffectiveOffset ~= nil then
        ok, x, y = pcall(function()
            return widget:GetEffectiveOffset()
        end)
    end
    if not ok then
        return nil, nil
    end
    return tonumber(x), tonumber(y)
end

local function persistWindowPosition(widget)
    local x, y = readOffset(widget)
    if x == nil or y == nil then
        return
    end
    anchorToUiParent(widget, x, y)
    local settings = getSettings()
    if type(settings) ~= "table" then
        return
    end
    settings.window_x = math.floor(clamp(x, 0, 4000, 520) + 0.5)
    settings.window_y = math.floor(clamp(y, 0, 4000, 90) + 0.5)
    if Shared ~= nil and Shared.SaveSettings ~= nil then
        Shared.SaveSettings()
    end
end

local function attachShiftDrag(widget, moveTarget)
    if widget == nil or widget.SetHandler == nil then
        return
    end
    if widget.RegisterForDrag ~= nil then
        pcall(function()
            widget:RegisterForDrag("LeftButton")
        end)
    end
    if widget.EnableDrag ~= nil then
        pcall(function()
            widget:EnableDrag(true)
        end)
    end
    widget:SetHandler("OnDragStart", function(self)
        if not isShiftDown() then
            return
        end
        local target = moveTarget or self
        SettingsUi.dragging_window = true
        if target.StartMoving ~= nil then
            target:StartMoving()
        end
        if api.Cursor ~= nil and api.Cursor.ClearCursor ~= nil then
            api.Cursor:ClearCursor()
        end
        if api.Cursor ~= nil and api.Cursor.SetCursorImage ~= nil and CURSOR_PATH ~= nil and CURSOR_PATH.MOVE ~= nil then
            api.Cursor:SetCursorImage(CURSOR_PATH.MOVE, 0, 0)
        end
    end)
    widget:SetHandler("OnDragStop", function(self)
        if SettingsUi.dragging_window ~= true then
            return
        end
        SettingsUi.dragging_window = false
        local target = moveTarget or self
        if target.StopMovingOrSizing ~= nil then
            target:StopMovingOrSizing()
        end
        if api.Cursor ~= nil and api.Cursor.ClearCursor ~= nil then
            api.Cursor:ClearCursor()
        end
        persistWindowPosition(target)
    end)
end

local function getLauncherSize()
    local settings = getSettings() or {}
    local size = math.floor(clamp(settings.button_size, 32, 96, 48) + 0.5)
    settings.button_size = size
    return size
end

local function persistLauncherPosition(widget)
    local x, y = readOffset(widget)
    if x == nil or y == nil then
        return
    end
    safeAnchor(widget, "TOPLEFT", "UIParent", "TOPLEFT", x, y)
    local settings = getSettings()
    if type(settings) ~= "table" then
        return
    end
    settings.button_x = math.floor(clamp(x, 0, 4000, 90) + 0.5)
    settings.button_y = math.floor(clamp(y, 0, 4000, 420) + 0.5)
    if Shared ~= nil and Shared.SaveSettings ~= nil then
        Shared.SaveSettings()
    end
end

local function applyLauncherLayout()
    local size = getLauncherSize()
    if SettingsUi.button ~= nil then
        safeSetExtent(SettingsUi.button, size, size)
        safeAnchor(SettingsUi.button, "TOPLEFT", "UIParent", "TOPLEFT",
            tonumber((getSettings() or {}).button_x) or 90,
            tonumber((getSettings() or {}).button_y) or 420
        )
    end
    if SettingsUi.button_icon ~= nil then
        safeSetExtent(SettingsUi.button_icon, size, size)
    end
end

local function attachLauncherDrag(widget)
    if widget == nil or widget.SetHandler == nil then
        return
    end
    if widget.RegisterForDrag ~= nil then
        pcall(function()
            widget:RegisterForDrag("LeftButton")
        end)
    end
    if widget.EnableDrag ~= nil then
        pcall(function()
            widget:EnableDrag(true)
        end)
    end
    widget:SetHandler("OnDragStart", function(self)
        if type(getSettings()) == "table" and getSettings().drag_requires_shift ~= false and not isShiftDown() then
            return
        end
        SettingsUi.dragging_launcher = true
        SettingsUi.launcher_just_dragged = false
        if self.StartMoving ~= nil then
            self:StartMoving()
        end
        if api.Cursor ~= nil and api.Cursor.ClearCursor ~= nil then
            api.Cursor:ClearCursor()
        end
    end)
    widget:SetHandler("OnDragStop", function(self)
        if SettingsUi.dragging_launcher ~= true then
            return
        end
        SettingsUi.dragging_launcher = false
        SettingsUi.launcher_just_dragged = true
        if self.StopMovingOrSizing ~= nil then
            self:StopMovingOrSizing()
        end
        if api.Cursor ~= nil and api.Cursor.ClearCursor ~= nil then
            api.Cursor:ClearCursor()
        end
        persistLauncherPosition(self)
    end)
end

local function createButton(id, parent, text, x, y, width, height)
    local button = api.Interface:CreateWidget("button", id, parent)
    button:AddAnchor("TOPLEFT", x, y)
    button:SetExtent(width or 100, height or 28)
    button:SetText(text)
    if api.Interface ~= nil and api.Interface.ApplyButtonSkin ~= nil and BUTTON_BASIC_REF ~= nil and BUTTON_BASIC_REF.DEFAULT ~= nil then
        pcall(function()
            api.Interface:ApplyButtonSkin(button, BUTTON_BASIC_REF.DEFAULT)
        end)
    end
    return button
end

local function createPanel(id, parent, x, y, width, height)
    local panel = nil
    local ok = pcall(function()
        panel = api.Interface:CreateWidget("emptywidget", id, parent)
    end)
    if (not ok or panel == nil) and api.Interface.CreateWidget ~= nil then
        pcall(function()
            panel = api.Interface:CreateWidget("button", id, parent)
        end)
    end
    if panel ~= nil then
        panel:AddAnchor("TOPLEFT", x, y)
        safeSetExtent(panel, width, height)
        safeShow(panel, false)
    end
    return panel
end

local function createCheckbox(id, parent, text, x, y)
    local box = api.Interface:CreateWidget("button", id, parent)
    box:AddAnchor("TOPLEFT", x, y)
    box:SetExtent(24, 24)
    if box.RegisterForClicks ~= nil then
        pcall(function()
            box:RegisterForClicks("LeftButton")
        end)
    end
    local label = createLabel(id .. "Label", parent, text, x + 34, y + 2, 13, 240)
    local proxy = { button = box, label = label, checked = false, on_click = nil }
    function proxy:SetChecked(v)
        self.checked = v and true or false
        safeSetText(self.button, self.checked and "[X]" or "[ ]")
        safeSetChecked(self.button, self.checked)
    end
    function proxy:GetChecked()
        return self.checked and true or false
    end
    function proxy:SetHandler(eventName, fn)
        if eventName == "OnClick" then
            self.on_click = fn
        end
    end
    local function handleClick(self, button)
        proxy:SetChecked(not proxy:GetChecked())
        setStatus("Unsaved changes. Use Apply or Save.")
        if type(proxy.on_click) == "function" then
            proxy.on_click(self, button)
        end
    end
    if box.SetHandler ~= nil then
        box:SetHandler("OnClick", handleClick)
    end
    if label ~= nil and label.SetHandler ~= nil then
        label:SetHandler("OnClick", function(_, button)
            handleClick(box, button)
        end)
    end
    proxy:SetChecked(false)
    return proxy
end

local function fixedCheckbox(value)
    local checked = value and true or false
    return {
        SetChecked = function() end,
        GetChecked = function()
            return checked
        end
    }
end

local function createSlider(id, parent, text, x, y, minValue, maxValue)
    createLabel(id .. "Label", parent, text, x, y, 13, 134)
    local slider = nil
    if CreateNuziSlider ~= nil then
        local ok, res = pcall(function()
            return CreateNuziSlider(id, parent)
        end)
        if ok then
            slider = res
        end
    end
    if slider == nil and api._Library ~= nil and api._Library.UI ~= nil and api._Library.UI.CreateSlider ~= nil then
        local ok, res = pcall(function()
            return api._Library.UI.CreateSlider(id, parent)
        end)
        if ok then
            slider = res
        end
    end
    if slider ~= nil then
        slider:AddAnchor("TOPLEFT", x + 150, y - 4)
        slider:SetExtent(154, 26)
        slider:SetMinMaxValues(minValue, maxValue)
        if slider.SetStep ~= nil then
            slider:SetStep(1)
        elseif slider.SetValueStep ~= nil then
            slider:SetValueStep(1)
        end
    end
    local value = createLabel(id .. "Value", parent, "0", x + 314, y, 13, 40)
    if slider ~= nil and slider.SetHandler ~= nil then
        slider:SetHandler("OnSliderChanged", function(_, raw)
            local numeric = tonumber(raw)
            if numeric == nil then
                numeric = sliderValue(slider, 0) or 0
            end
            safeSetText(value, tostring(math.floor(numeric + 0.5)))
            setStatus("Unsaved changes. Use Apply or Save.")
        end)
    end
    return slider, value
end

sliderValue = function(slider, fallback)
    if slider ~= nil and slider.GetValue ~= nil then
        local ok, res = pcall(function()
            return slider:GetValue()
        end)
        if ok and res ~= nil then
            return math.floor((tonumber(res) or fallback or 0) + 0.5)
        end
    end
    return fallback
end

local function setSlider(slider, valueLabel, value)
    if slider ~= nil and slider.SetValue ~= nil then
        pcall(function()
            slider:SetValue(tonumber(value) or 0, false)
        end)
    end
    safeSetText(valueLabel, tostring(math.floor((tonumber(value) or 0) + 0.5)))
end

local function colorValue(color, index, fallback)
    if type(color) ~= "table" then
        return fallback
    end
    local value = tonumber(color[index])
    if value == nil then
        return fallback
    end
    if value < 0 then
        return 0
    end
    if value > 255 then
        return 255
    end
    return math.floor(value + 0.5)
end

local function copyColor(color, fallback)
    local source = type(color) == "table" and color or fallback
    return {
        colorValue(source, 1, colorValue(fallback, 1, 255)),
        colorValue(source, 2, colorValue(fallback, 2, 255)),
        colorValue(source, 3, colorValue(fallback, 3, 255)),
        colorValue(source, 4, colorValue(fallback, 4, 255))
    }
end

local function getStyleColor(style, group)
    if type(style) ~= "table" or type(group) ~= "table" then
        return { 255, 255, 255, 255 }
    end
    if type(style[group.key]) == "table" then
        return style[group.key]
    end
    if group.alias ~= nil and type(style[group.alias]) == "table" then
        return style[group.alias]
    end
    return group.fallback
end

local function setColorSliders(group, color)
    if type(group) ~= "table" then
        return
    end
    local prefix = group.prefix
    local fallback = group.fallback or { 255, 255, 255, 255 }
    setSlider(SettingsUi.controls[prefix .. "_r"], SettingsUi.controls[prefix .. "_r_val"], colorValue(color, 1, fallback[1]))
    setSlider(SettingsUi.controls[prefix .. "_g"], SettingsUi.controls[prefix .. "_g_val"], colorValue(color, 2, fallback[2]))
    setSlider(SettingsUi.controls[prefix .. "_b"], SettingsUi.controls[prefix .. "_b_val"], colorValue(color, 3, fallback[3]))
end

local function collectColorSliders(group, style)
    if type(group) ~= "table" or type(style) ~= "table" then
        return
    end
    local prefix = group.prefix
    local fallback = copyColor(getStyleColor(style, group), group.fallback)
    style[group.key] = {
        sliderValue(SettingsUi.controls[prefix .. "_r"], fallback[1]),
        sliderValue(SettingsUi.controls[prefix .. "_g"], fallback[2]),
        sliderValue(SettingsUi.controls[prefix .. "_b"], fallback[3]),
        fallback[4] or 255
    }
end

local function createColorSliderGroup(parent, group, x, y)
    createLabel("nuziRaidColorTitle" .. tostring(group.prefix), parent, tostring(group.label or group.key), x, y, 14, 220)
    y = y + 24
    local idPrefix = tostring(group.id_prefix or group.prefix or "")
    SettingsUi.controls[group.prefix .. "_r"], SettingsUi.controls[group.prefix .. "_r_val"] = createSlider("nuziRaid" .. idPrefix .. "R", parent, "Red", x, y, 0, 255)
    y = y + 32
    SettingsUi.controls[group.prefix .. "_g"], SettingsUi.controls[group.prefix .. "_g_val"] = createSlider("nuziRaid" .. idPrefix .. "G", parent, "Green", x, y, 0, 255)
    y = y + 32
    SettingsUi.controls[group.prefix .. "_b"], SettingsUi.controls[group.prefix .. "_b_val"] = createSlider("nuziRaid" .. idPrefix .. "B", parent, "Blue", x, y, 0, 255)
    return y + 42
end

local function getColorGroupByKey(groupKey)
    local key = tostring(groupKey or "")
    for _, group in ipairs(COLOR_GROUPS) do
        if group.key == key then
            return group
        end
    end
    return nil
end

local function defaultColorForGroup(group)
    return copyColor(type(group) == "table" and group.fallback or nil, { 255, 255, 255, 255 })
end

local function ensureStyleColor(style, group)
    if type(style) ~= "table" or type(group) ~= "table" then
        return { 255, 255, 255, 255 }
    end
    if type(style[group.key]) ~= "table" then
        style[group.key] = copyColor(getStyleColor(style, group), group.fallback)
    end
    if group.alias ~= nil and type(style[group.alias]) ~= "table" then
        style[group.alias] = copyColor(style[group.key], group.fallback)
    end
    return style[group.key]
end

local function syncColorAliases(style)
    if type(style) ~= "table" then
        return
    end
    if type(style.hp_fill_color) == "table" then
        style.hp_bar_color = copyColor(style.hp_fill_color, DEFAULT_HP_COLOR)
    end
    if type(style.mp_fill_color) == "table" then
        style.mp_bar_color = copyColor(style.mp_fill_color, DEFAULT_MP_COLOR)
    end
end

local function setDrawableColor(drawable, color)
    if drawable == nil or drawable.SetColor == nil then
        return
    end
    local resolved = copyColor(color, { 255, 255, 255, 255 })
    pcall(function()
        drawable:SetColor(
            resolved[1] / 255,
            resolved[2] / 255,
            resolved[3] / 255,
            resolved[4] / 255
        )
    end)
end

local function setLabelColor255(label, color)
    if label == nil or label.style == nil or label.style.SetColor == nil then
        return
    end
    local resolved = copyColor(color, { 255, 255, 255, 255 })
    pcall(function()
        label.style:SetColor(
            resolved[1] / 255,
            resolved[2] / 255,
            resolved[3] / 255,
            resolved[4] / 255
        )
    end)
end

local function setStatusBarColor(statusBar, color)
    if statusBar == nil then
        return
    end
    local resolved = copyColor(color, { 255, 255, 255, 255 })
    local rgba = {
        resolved[1] / 255,
        resolved[2] / 255,
        resolved[3] / 255,
        resolved[4] / 255
    }
    pcall(function()
        if statusBar.SetBarColor ~= nil then
            statusBar:SetBarColor(rgba[1], rgba[2], rgba[3], rgba[4])
        elseif statusBar.SetColor ~= nil then
            statusBar:SetColor(rgba[1], rgba[2], rgba[3], rgba[4])
        end
    end)
end

local function formatColorHex(color)
    local resolved = copyColor(color, { 255, 255, 255, 255 })
    return string.format("#%02X%02X%02X", resolved[1], resolved[2], resolved[3])
end

local function formatColorRgba(color)
    local resolved = copyColor(color, { 255, 255, 255, 255 })
    return string.format("%d, %d, %d, %d", resolved[1], resolved[2], resolved[3], resolved[4])
end

local function hsvToRgb(h, s, v)
    local hue = tonumber(h) or 0
    local sat = tonumber(s) or 0
    local val = tonumber(v) or 0
    local i = math.floor(hue * 6)
    local f = (hue * 6) - i
    local p = val * (1 - sat)
    local q = val * (1 - (f * sat))
    local t = val * (1 - ((1 - f) * sat))
    local mod = i - (math.floor(i / 6) * 6)
    local r, g, b = val, t, p
    if mod == 1 then
        r, g, b = q, val, p
    elseif mod == 2 then
        r, g, b = p, val, t
    elseif mod == 3 then
        r, g, b = p, q, val
    elseif mod == 4 then
        r, g, b = t, p, val
    elseif mod == 5 then
        r, g, b = val, p, q
    end
    return {
        math.floor((r * 255) + 0.5),
        math.floor((g * 255) + 0.5),
        math.floor((b * 255) + 0.5),
        255
    }
end

local function paletteCellColor(column, row, columns, rows)
    local rowPct = (row - 1) / math.max(1, (rows or 1) - 1)
    if column == 1 then
        local value = math.floor((((1 - rowPct) * 0.84) + 0.10) * 255 + 0.5)
        return { value, value, value, 255 }
    end
    local hue = (column - 2) / math.max(1, (columns or 2) - 2)
    local saturation = 0.30 + (rowPct * 0.65)
    local value = 1 - (rowPct * 0.58)
    return hsvToRgb(hue, saturation, value)
end

local function createEmptyChild(id, parent, x, y, width, height)
    local child = nil
    pcall(function()
        child = api.Interface:CreateWidget("emptywidget", id, parent)
    end)
    if child == nil then
        pcall(function()
            child = api.Interface:CreateWidget("button", id, parent)
        end)
    end
    if child ~= nil then
        child:AddAnchor("TOPLEFT", x or 0, y or 0)
        safeSetExtent(child, width or 10, height or 10)
        safeShow(child, true)
    end
    return child
end

local function createBareButton(id, parent, x, y, width, height)
    local button = api.Interface:CreateWidget("button", id, parent)
    button:AddAnchor("TOPLEFT", x or 0, y or 0)
    button:SetExtent(width or 80, height or 24)
    button:SetText("")
    safeShow(button, true)
    return button
end

local function createInsetFill(widget, inset, layer)
    if widget == nil or widget.CreateColorDrawable == nil then
        return nil
    end
    local margin = tonumber(inset) or 0
    local fill = widget:CreateColorDrawable(1, 1, 1, 1, layer or "artwork")
    fill:AddAnchor("TOPLEFT", widget, margin, margin)
    fill:AddAnchor("BOTTOMRIGHT", widget, -margin, -margin)
    return fill
end

local function createColorSwatchButton(id, parent, x, y, width, height)
    local button = createBareButton(id, parent, x, y, width, height)
    if button ~= nil and button.CreateColorDrawable ~= nil then
        local bg = button:CreateColorDrawable(0.04, 0.04, 0.04, 0.96, "background")
        bg:AddAnchor("TOPLEFT", button, 0, 0)
        bg:AddAnchor("BOTTOMRIGHT", button, 0, 0)
        button.__nr_fill = createInsetFill(button, 3, "artwork")
        local gloss = button:CreateColorDrawable(1, 1, 1, 0.08, "overlay")
        gloss:AddAnchor("TOPLEFT", button, 3, 3)
        gloss:AddAnchor("TOPRIGHT", button, -3, 3)
        if gloss.SetHeight ~= nil then
            gloss:SetHeight(math.max(4, math.floor((height or 18) * 0.28)))
        end
    end
    return button
end

local function getPreviewTexture(group)
    local key = type(group) == "table" and tostring(group.key or "") or ""
    if string.find(key, "mp", 1, true) ~= nil then
        return STATUSBAR_STYLE ~= nil and STATUSBAR_STYLE.MP_RAID or nil
    end
    return STATUSBAR_STYLE ~= nil and STATUSBAR_STYLE.HP_RAID or nil
end

local function createPreviewStatusBar(id, parent, group, height)
    if parent == nil or W_BAR == nil or W_BAR.CreateStatusBarOfRaidFrame == nil then
        return nil
    end
    local bar = nil
    pcall(function()
        bar = W_BAR.CreateStatusBarOfRaidFrame(id, parent)
    end)
    if bar == nil then
        return nil
    end
    safeShow(bar, true)
    if bar.Clickable ~= nil then
        pcall(function()
            bar:Clickable(false)
        end)
    end
    if bar.statusBar ~= nil and bar.statusBar.Clickable ~= nil then
        pcall(function()
            bar.statusBar:Clickable(false)
        end)
    end
    local texture = getPreviewTexture(group)
    if texture ~= nil and bar.ApplyBarTexture ~= nil then
        pcall(function()
            bar:ApplyBarTexture(texture)
        end)
    end
    safeAnchor(bar, "TOPLEFT", parent, "TOPLEFT", 0, 0)
    pcall(function()
        bar:AddAnchor("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    end)
    safeSetHeight(bar, height or 18)
    if bar.statusBar ~= nil then
        safeSetHeight(bar.statusBar, height or 18)
        pcall(function()
            if bar.statusBar.SetMinMaxValues ~= nil then
                bar.statusBar:SetMinMaxValues(0, 100)
            end
            if bar.statusBar.SetValue ~= nil then
                bar.statusBar:SetValue(100)
            end
        end)
    end
    return bar
end

local function createColorPreviewFrame(id, parent, group, x, y, width, height)
    local frame = createEmptyChild(id, parent, x, y, width, height)
    if frame == nil then
        return nil
    end
    if frame.CreateColorDrawable ~= nil then
        local bg = frame:CreateColorDrawable(0.06, 0.06, 0.06, 0.86, "background")
        bg:AddAnchor("TOPLEFT", frame, 0, 0)
        bg:AddAnchor("BOTTOMRIGHT", frame, 0, 0)
    end
    frame.__nr_preview_mode = type(group) == "table" and group.preview or "bar"
    if frame.__nr_preview_mode == "text" then
        frame.__nr_preview_label = createLabel(id .. "Text", frame, "Preview Text", 10, 10, 13, (width or 160) - 20)
    elseif frame.__nr_preview_mode == "bar" then
        frame.__nr_preview_label = createLabel(id .. "Text", frame, "Bar Preview", 10, 5, 11, (width or 160) - 20)
        local barHost = createEmptyChild(id .. "BarHost", frame, 10, 24, (width or 160) - 20, 18)
        if barHost ~= nil then
            frame.__nr_preview_bar = createPreviewStatusBar(id .. "StatusBar", barHost, group, 18)
            frame.__nr_preview_statusbar = frame.__nr_preview_bar ~= nil and (frame.__nr_preview_bar.statusBar or frame.__nr_preview_bar) or nil
            if frame.__nr_preview_statusbar == nil then
                frame.__nr_preview_fill = createInsetFill(barHost, 2, "artwork")
            end
        end
    else
        frame.__nr_preview_fill = createInsetFill(frame, 5, "artwork")
    end
    return frame
end

local function updateColorPreview(preview, group, color)
    if preview == nil then
        return
    end
    local mode = preview.__nr_preview_mode or (type(group) == "table" and group.preview) or "bar"
    if mode == "text" then
        setLabelColor255(preview.__nr_preview_label, color)
    elseif mode == "bar" and preview.__nr_preview_statusbar ~= nil then
        setStatusBarColor(preview.__nr_preview_statusbar, color)
    elseif preview.__nr_preview_fill ~= nil then
        setDrawableColor(preview.__nr_preview_fill, color)
    end
end

local function updateColorCardDisplay(card, group, color)
    if type(card) ~= "table" then
        return
    end
    if card.swatch ~= nil and card.swatch.__nr_fill ~= nil then
        setDrawableColor(card.swatch.__nr_fill, color)
    end
    safeSetText(card.hex_label, formatColorHex(color))
    safeSetText(card.rgb_label, formatColorRgba(color))
    updateColorPreview(card.preview, group, color)
end

local function refreshColorPickerDisplay(style)
    local picker = SettingsUi.color_picker or {}
    local group = getColorGroupByKey(picker.active_group)
    if group == nil then
        return
    end
    local color = copyColor(getStyleColor(style, group), group.fallback)
    if picker.title_label ~= nil then
        picker.title_label:SetText("Edit " .. tostring(group.label or "color"))
    end
    safeSetText(picker.hint_label, tostring(group.description or ""))
    if picker.swatch ~= nil and picker.swatch.__nr_fill ~= nil then
        setDrawableColor(picker.swatch.__nr_fill, color)
    end
    safeSetText(picker.hex_label, formatColorHex(color))
    safeSetText(picker.rgb_label, formatColorRgba(color))
    updateColorPreview(picker.preview, group, color)
    picker.silent = true
    for channelIndex = 1, 4 do
        setSlider(picker.sliders[channelIndex], picker.values[channelIndex], colorValue(color, channelIndex, 255))
    end
    picker.silent = false
end

local function refreshColorCards(style)
    for _, group in ipairs(COLOR_GROUPS) do
        local card = SettingsUi.color_cards[group.key]
        if card ~= nil then
            updateColorCardDisplay(card, group, getStyleColor(style, group))
        end
    end
    if SettingsUi.color_picker ~= nil and SettingsUi.color_picker.active_group ~= nil then
        refreshColorPickerDisplay(style)
    end
end

local function applyPickerColor(color)
    local picker = SettingsUi.color_picker or {}
    local group = getColorGroupByKey(picker.active_group)
    local settings = getSettings()
    local style = type(settings) == "table" and settings.style or nil
    if group == nil or type(style) ~= "table" then
        return
    end
    style[group.key] = copyColor(color, group.fallback)
    syncColorAliases(style)
    setStatus("Unsaved changes. Use Apply or Save.")
    refreshColorCards(style)
end

local function setPickerChannel(channelIndex, raw)
    local picker = SettingsUi.color_picker or {}
    if picker.silent == true then
        return
    end
    local group = getColorGroupByKey(picker.active_group)
    local settings = getSettings()
    local style = type(settings) == "table" and settings.style or nil
    if group == nil or type(style) ~= "table" then
        return
    end
    local current = copyColor(getStyleColor(style, group), group.fallback)
    current[channelIndex] = colorValue({ raw }, 1, current[channelIndex] or 255)
    applyPickerColor(current)
end

local function closeColorPicker(commit)
    local picker = SettingsUi.color_picker or {}
    local settings = getSettings()
    local style = type(settings) == "table" and settings.style or nil
    local group = getColorGroupByKey(picker.active_group)
    if not commit and group ~= nil and type(style) == "table" and type(picker.original_color) == "table" then
        style[group.key] = copyColor(picker.original_color, group.fallback)
        syncColorAliases(style)
        refreshColorCards(style)
        setStatus("Color edit canceled.")
    end
    picker.active_group = nil
    picker.original_color = nil
    safeShow(picker.overlay, false)
    if updateColorPageVisibility ~= nil then
        updateColorPageVisibility()
    end
end

local function openColorPicker(group)
    local settings = getSettings()
    local style = type(settings) == "table" and settings.style or nil
    local picker = SettingsUi.color_picker or {}
    if type(style) ~= "table" or type(group) ~= "table" or picker.overlay == nil then
        return
    end
    picker.active_group = group.key
    picker.original_color = copyColor(getStyleColor(style, group), group.fallback)
    safeShow(picker.overlay, SettingsUi.active_tab == tostring(group.tab or ""))
    refreshColorPickerDisplay(style)
    if updateColorPageVisibility ~= nil then
        updateColorPageVisibility()
    end
end

local function ensureColorPicker(parent)
    local picker = SettingsUi.color_picker
    if picker.overlay ~= nil or parent == nil then
        return picker.overlay
    end

    picker.overlay = createEmptyChild("nuziRaidColorPickerOverlay", parent, 18, 70, 738, 690)
    if picker.overlay ~= nil and picker.overlay.CreateColorDrawable ~= nil then
        local veil = picker.overlay:CreateColorDrawable(0.01, 0.01, 0.01, 0.56, "background")
        veil:AddAnchor("TOPLEFT", picker.overlay, 0, 0)
        veil:AddAnchor("BOTTOMRIGHT", picker.overlay, 0, 0)
    end

    picker.panel = createEmptyChild("nuziRaidColorPickerPanel", picker.overlay, 50, 34, 638, 468)
    if picker.panel ~= nil and picker.panel.CreateColorDrawable ~= nil then
        local bg = picker.panel:CreateColorDrawable(0.05, 0.05, 0.055, 0.98, "background")
        bg:AddAnchor("TOPLEFT", picker.panel, 0, 0)
        bg:AddAnchor("BOTTOMRIGHT", picker.panel, 0, 0)
    end

    local panel = picker.panel or picker.overlay
    picker.title_label = createLabel("nuziRaidColorPickerTitle", panel, "Edit color", 18, 16, 18, 310)
    picker.hint_label = createLabel("nuziRaidColorPickerHint", panel, "", 18, 40, 12, 330)
    picker.swatch = createColorSwatchButton("nuziRaidColorPickerSwatch", panel, 420, 20, 188, 62)
    picker.hex_label = createLabel("nuziRaidColorPickerHex", panel, "", 420, 90, 13, 188)
    picker.rgb_label = createLabel("nuziRaidColorPickerRgb", panel, "", 420, 112, 12, 188)
    picker.preview = createColorPreviewFrame("nuziRaidColorPickerPreview", panel, { preview = "bar" }, 420, 144, 188, 76)

    createLabel("nuziRaidColorPaletteTitle", panel, "Palette", 22, 82, 15, 120)
    picker.palette_cells = {}
    local paletteColumns = 12
    local paletteRows = 7
    local cellWidth = 22
    local cellHeight = 18
    local gapX = 4
    local gapY = 4
    local startX = 22
    local startY = 112
    for row = 1, paletteRows do
        for column = 1, paletteColumns do
            local index = ((row - 1) * paletteColumns) + column
            local cell = createColorSwatchButton(
                "nuziRaidColorPickerCell" .. tostring(index),
                panel,
                startX + ((column - 1) * (cellWidth + gapX)),
                startY + ((row - 1) * (cellHeight + gapY)),
                cellWidth,
                cellHeight
            )
            local cellColor = paletteCellColor(column, row, paletteColumns, paletteRows)
            cell.__nr_palette_color = cellColor
            if cell.__nr_fill ~= nil then
                setDrawableColor(cell.__nr_fill, cellColor)
            end
            cell:SetHandler("OnClick", function()
                applyPickerColor(cell.__nr_palette_color)
            end)
            picker.palette_cells[index] = cell
        end
    end

    picker.sliders = {}
    picker.values = {}
    local channels = {
        { label = "Red", index = 1 },
        { label = "Green", index = 2 },
        { label = "Blue", index = 3 },
        { label = "Alpha", index = 4 }
    }
    for channelOffset, channel in ipairs(channels) do
        picker.sliders[channel.index], picker.values[channel.index] = createSlider(
            "nuziRaidColorPicker" .. channel.label,
            panel,
            channel.label,
            22,
            286 + ((channelOffset - 1) * 34),
            0,
            255
        )
        if picker.sliders[channel.index] ~= nil and picker.sliders[channel.index].SetHandler ~= nil then
            picker.sliders[channel.index]:SetHandler("OnSliderChanged", function(_, raw)
                setPickerChannel(channel.index, raw)
            end)
        end
    end

    picker.reset_button = createButton("nuziRaidColorPickerDefault", panel, "Default", 22, 428, 86, 28)
    picker.cancel_button = createButton("nuziRaidColorPickerCancel", panel, "Cancel", 460, 428, 72, 28)
    picker.apply_button = createButton("nuziRaidColorPickerApply", panel, "Apply", 540, 428, 72, 28)
    picker.reset_button:SetHandler("OnClick", function()
        local group = getColorGroupByKey(picker.active_group)
        if group ~= nil then
            applyPickerColor(defaultColorForGroup(group))
        end
    end)
    picker.cancel_button:SetHandler("OnClick", function()
        closeColorPicker(false)
    end)
    picker.apply_button:SetHandler("OnClick", function()
        closeColorPicker(true)
    end)

    safeShow(picker.overlay, false)
    return picker.overlay
end

local function createColorCard(group, parent, x, y, width, height, page)
    local card = createEmptyChild("nuziRaidColorCard" .. tostring(group.key), parent, x, y, width, height)
    if card == nil then
        return nil
    end
    if card.CreateColorDrawable ~= nil then
        local bg = card:CreateColorDrawable(0.055, 0.055, 0.06, 0.88, "background")
        bg:AddAnchor("TOPLEFT", card, 0, 0)
        bg:AddAnchor("BOTTOMRIGHT", card, 0, 0)
    end
    local cardWidth = width or 280
    createLabel("nuziRaidColorCardTitle" .. tostring(group.key), card, tostring(group.label or group.key), 12, 9, 14, cardWidth - 96)
    createLabel("nuziRaidColorCardDesc" .. tostring(group.key), card, tostring(group.description or ""), 12, 31, 11, cardWidth - 104)
    local swatch = createColorSwatchButton("nuziRaidColorCardSwatch" .. tostring(group.key), card, cardWidth - 72, 12, 58, 42)
    local hexLabel = createLabel("nuziRaidColorCardHex" .. tostring(group.key), card, "", 12, 56, 12, 92)
    local rgbaLabel = createLabel("nuziRaidColorCardRgb" .. tostring(group.key), card, "", 12, 76, 11, 160)
    local preview = createColorPreviewFrame("nuziRaidColorCardPreview" .. tostring(group.key), card, group, 12, 98, 164, 48)
    local editBtn = createButton("nuziRaidColorCardEdit" .. tostring(group.key), card, "Edit", cardWidth - 128, 106, 54, 26)
    local resetBtn = createButton("nuziRaidColorCardReset" .. tostring(group.key), card, "Reset", cardWidth - 68, 106, 54, 26)

    local refs = {
        root = card,
        swatch = swatch,
        hex_label = hexLabel,
        rgb_label = rgbaLabel,
        preview = preview,
        page = page or 1
    }
    SettingsUi.color_cards[group.key] = refs

    local function openGroup()
        openColorPicker(group)
    end
    swatch:SetHandler("OnClick", openGroup)
    editBtn:SetHandler("OnClick", openGroup)
    resetBtn:SetHandler("OnClick", function()
        local settings = getSettings()
        local style = type(settings) == "table" and settings.style or nil
        if type(style) ~= "table" then
            return
        end
        style[group.key] = defaultColorForGroup(group)
        syncColorAliases(style)
        refreshColorCards(style)
        setStatus("Unsaved changes. Use Apply or Save.")
    end)

    return refs
end

local function createColorRow(group, parent, x, y, width)
    local rowWidth = width or 340
    local row = createEmptyChild("nuziRaidColorRow" .. tostring(group.key), parent, x, y, rowWidth, 38)
    if row == nil then
        return nil
    end
    if row.CreateColorDrawable ~= nil then
        local bg = row:CreateColorDrawable(0.055, 0.055, 0.06, 0.66, "background")
        bg:AddAnchor("TOPLEFT", row, 0, 0)
        bg:AddAnchor("BOTTOMRIGHT", row, 0, 0)
    end

    createLabel("nuziRaidColorRowTitle" .. tostring(group.key), row, tostring(group.label or group.key), 10, 9, 13, 132)
    local swatch = createColorSwatchButton("nuziRaidColorRowSwatch" .. tostring(group.key), row, 150, 7, 44, 24)
    local hexLabel = createLabel("nuziRaidColorRowHex" .. tostring(group.key), row, "", 204, 10, 12, 70)
    local editBtn = createButton("nuziRaidColorRowEdit" .. tostring(group.key), row, "Edit", rowWidth - 58, 6, 48, 26)

    local refs = {
        root = row,
        swatch = swatch,
        hex_label = hexLabel,
        rgb_label = nil,
        preview = nil,
        page = 1,
        tab = tostring(group.tab or "")
    }
    SettingsUi.color_cards[group.key] = refs

    local function openGroup()
        openColorPicker(group)
    end
    if swatch ~= nil and swatch.SetHandler ~= nil then
        swatch:SetHandler("OnClick", openGroup)
    end
    if editBtn ~= nil and editBtn.SetHandler ~= nil then
        editBtn:SetHandler("OnClick", openGroup)
    end

    return refs
end

local function setColorPage(page)
    SettingsUi.color_page = math.max(1, math.min(tonumber(page) or 1, SettingsUi.color_page_count or 1))
    if updateColorPageVisibility ~= nil then
        updateColorPageVisibility()
    end
end

updateColorPageVisibility = function()
    local picker = SettingsUi.color_picker or {}
    local activeGroup = getColorGroupByKey(picker.active_group)
    local showPicker = activeGroup ~= nil and SettingsUi.active_tab == tostring(activeGroup.tab or "")
    safeShow(picker.overlay, showPicker)
end

setStatus = function(text)
    safeSetText(SettingsUi.controls.status, text)
end

local function updateTabButtons()
    for key, button in pairs(SettingsUi.tab_buttons) do
        local pageDef = PAGE_DEFS[key] or { label = key }
        local label = tostring(pageDef.label or key)
        safeSetText(button, SettingsUi.active_tab == key and ("[" .. label .. "]") or label)
    end
    local activeDef = PAGE_DEFS[SettingsUi.active_tab] or PAGE_DEFS.general
    safeSetText(SettingsUi.controls.page_header_title, activeDef.title or activeDef.label or "")
    safeSetText(SettingsUi.controls.page_header_summary, activeDef.summary or "")
end

local function selectTab(tabKey)
    SettingsUi.active_tab = tabKey
    for key, panel in pairs(SettingsUi.panels) do
        safeShow(panel, key == tabKey)
    end
    updateTabButtons()
    if updateColorPageVisibility ~= nil then
        updateColorPageVisibility()
    end
end

local function createTabButton(id, parent, tabKey, x, y, width)
    local button = createButton(id, parent, "", x, y, width, 28)
    button:SetHandler("OnClick", function()
        selectTab(tabKey)
    end)
    SettingsUi.tab_buttons[tabKey] = button
    return button
end

local function refreshControls()
    local settings = getSettings()
    if type(settings) ~= "table" or type(settings.raidframes) ~= "table" or type(settings.style) ~= "table" then
        return
    end
    local raid = settings.raidframes
    local style = settings.style
    local runtimeLines = Compat ~= nil and Compat.GetRuntimeLines() or nil
    SettingsUi.controls.enabled:SetChecked(settings.enabled)
    SettingsUi.controls.raid_enabled:SetChecked(raid.enabled)
    SettingsUi.controls.hide_stock:SetChecked(raid.hide_stock)
    SettingsUi.controls.use_team_role_colors:SetChecked(raid.use_team_role_colors ~= false)
    SettingsUi.controls.use_role_name_colors:SetChecked(raid.use_role_name_colors ~= false)
    SettingsUi.controls.text_colors_override_role_colors:SetChecked(raid.text_colors_override_role_colors == true)
    SettingsUi.controls.show_target_highlight:SetChecked(raid.show_target_highlight ~= false)
    SettingsUi.controls.show_debuff_alert:SetChecked(raid.show_debuff_alert ~= false)
    SettingsUi.controls.show_class_icon:SetChecked(raid.show_class_icon ~= false)
    SettingsUi.controls.show_leader_badge:SetChecked(raid.show_leader_badge ~= false)
    SettingsUi.controls.show_role_badge:SetChecked(raid.show_role_badge == true)
    SettingsUi.controls.show_status_text:SetChecked(raid.show_status_text ~= false)
    SettingsUi.controls.show_group_headers:SetChecked(raid.show_group_headers ~= false)
    SettingsUi.controls.range_fade_enabled:SetChecked(raid.range_fade_enabled ~= false)
    SettingsUi.controls.bg_enabled:SetChecked(raid.bg_enabled and true or false)
    SettingsUi.controls.show_value_text:SetChecked(raid.show_value_text and true or false)
    SettingsUi.controls.bar_colors_enabled:SetChecked(style.bar_colors_enabled and true or false)
    setSlider(SettingsUi.controls.width, SettingsUi.controls.width_val, raid.width or 80)
    setSlider(SettingsUi.controls.hp_height, SettingsUi.controls.hp_height_val, raid.hp_height or 16)
    setSlider(SettingsUi.controls.mp_height, SettingsUi.controls.mp_height_val, raid.mp_height or 0)
    setSlider(SettingsUi.controls.name_font_size, SettingsUi.controls.name_font_size_val, raid.name_font_size or 11)
    setSlider(SettingsUi.controls.name_max_chars, SettingsUi.controls.name_max_chars_val, raid.name_max_chars or 0)
    setSlider(SettingsUi.controls.value_font_size, SettingsUi.controls.value_font_size_val, raid.value_font_size or 10)
    setSlider(SettingsUi.controls.icon_size, SettingsUi.controls.icon_size_val, raid.icon_size or 12)
    setSlider(SettingsUi.controls.leader_badge_size, SettingsUi.controls.leader_badge_size_val, raid.leader_badge_size or 11)
    setSlider(SettingsUi.controls.button_size, SettingsUi.controls.button_size_val, settings.button_size or 48)
    setSlider(SettingsUi.controls.name_padding_left, SettingsUi.controls.name_padding_left_val, raid.name_padding_left or 0)
    setSlider(SettingsUi.controls.name_offset_x, SettingsUi.controls.name_offset_x_val, raid.name_offset_x or 0)
    setSlider(SettingsUi.controls.name_offset_y, SettingsUi.controls.name_offset_y_val, raid.name_offset_y or 0)
    setSlider(SettingsUi.controls.value_offset_x, SettingsUi.controls.value_offset_x_val, raid.value_offset_x or 0)
    setSlider(SettingsUi.controls.value_offset_y, SettingsUi.controls.value_offset_y_val, raid.value_offset_y or 0)
    setSlider(SettingsUi.controls.class_offset_x, SettingsUi.controls.class_offset_x_val, raid.class_offset_x or raid.icon_offset_x or 0)
    setSlider(SettingsUi.controls.class_offset_y, SettingsUi.controls.class_offset_y_val, raid.class_offset_y or raid.icon_offset_y or 0)
    setSlider(SettingsUi.controls.role_offset_x, SettingsUi.controls.role_offset_x_val, raid.role_offset_x or raid.icon_offset_x or 0)
    setSlider(SettingsUi.controls.role_offset_y, SettingsUi.controls.role_offset_y_val, raid.role_offset_y or raid.icon_offset_y or 0)
    setSlider(SettingsUi.controls.status_offset_x, SettingsUi.controls.status_offset_x_val, raid.status_offset_x or 0)
    setSlider(SettingsUi.controls.status_offset_y, SettingsUi.controls.status_offset_y_val, raid.status_offset_y or 0)
    setSlider(SettingsUi.controls.debuff_offset_x, SettingsUi.controls.debuff_offset_x_val, raid.debuff_offset_x or 0)
    setSlider(SettingsUi.controls.debuff_offset_y, SettingsUi.controls.debuff_offset_y_val, raid.debuff_offset_y or 0)
    setSlider(SettingsUi.controls.debuff_size, SettingsUi.controls.debuff_size_val, raid.debuff_size or 8)
    setSlider(SettingsUi.controls.range_max_distance, SettingsUi.controls.range_max_distance_val, raid.range_max_distance or 80)
    setSlider(SettingsUi.controls.range_alpha_pct, SettingsUi.controls.range_alpha_pct_val, raid.range_alpha_pct or 45)
    setSlider(SettingsUi.controls.party_columns_per_row, SettingsUi.controls.party_columns_per_row_val, raid.party_columns_per_row or 5)
    setSlider(SettingsUi.controls.grid_columns, SettingsUi.controls.grid_columns_val, raid.grid_columns or 8)
    setSlider(SettingsUi.controls.gap_x, SettingsUi.controls.gap_x_val, raid.gap_x or 2)
    setSlider(SettingsUi.controls.gap_y, SettingsUi.controls.gap_y_val, raid.gap_y or 2)
    setSlider(SettingsUi.controls.party_row_gap, SettingsUi.controls.party_row_gap_val, raid.party_row_gap or 10)
    refreshColorCards(style)
    SettingsUi.controls.layout.__value = tostring(raid.layout_mode or "party_columns")
    SettingsUi.controls.bar_style_mode.__value = tostring(raid.bar_style_mode or "shared")
    SettingsUi.controls.hp_texture_mode.__value = normalizeHpTextureMode(style.hp_texture_mode)
    SettingsUi.controls.value_text_mode.__value = tostring(raid.value_text_mode or "percent")
    safeSetText(SettingsUi.controls.layout, tostring(raid.layout_mode or "party_columns"))
    safeSetText(SettingsUi.controls.bar_style_mode, tostring(raid.bar_style_mode or "shared"))
    safeSetText(SettingsUi.controls.hp_texture_mode, SettingsUi.controls.hp_texture_mode.__value)
    safeSetText(SettingsUi.controls.value_text_mode, tostring(raid.value_text_mode or "percent"))
    safeSetText(SettingsUi.controls.runtime_line_1, runtimeLines ~= nil and runtimeLines[1] or "")
    safeSetText(SettingsUi.controls.runtime_line_2, runtimeLines ~= nil and runtimeLines[2] or "")
    safeSetText(SettingsUi.controls.runtime_status, Compat ~= nil and Compat.GetStatusText() or "")
    applyLauncherLayout()
end

local function collectSettings()
    local settings = getSettings()
    if type(settings) ~= "table" or type(settings.raidframes) ~= "table" or type(settings.style) ~= "table" then
        return
    end
    local raid = settings.raidframes
    local style = settings.style
    settings.enabled = SettingsUi.controls.enabled:GetChecked()
    raid.enabled = SettingsUi.controls.raid_enabled:GetChecked()
    raid.hide_stock = SettingsUi.controls.hide_stock:GetChecked()
    raid.use_team_role_colors = SettingsUi.controls.use_team_role_colors:GetChecked()
    raid.use_role_name_colors = SettingsUi.controls.use_role_name_colors:GetChecked()
    raid.text_colors_override_role_colors = SettingsUi.controls.text_colors_override_role_colors:GetChecked()
    raid.show_target_highlight = SettingsUi.controls.show_target_highlight:GetChecked()
    raid.show_debuff_alert = SettingsUi.controls.show_debuff_alert:GetChecked()
    raid.show_class_icon = SettingsUi.controls.show_class_icon:GetChecked()
    raid.show_leader_badge = SettingsUi.controls.show_leader_badge:GetChecked()
    raid.show_role_badge = SettingsUi.controls.show_role_badge:GetChecked()
    raid.show_status_text = SettingsUi.controls.show_status_text:GetChecked()
    raid.show_group_headers = SettingsUi.controls.show_group_headers:GetChecked()
    raid.range_fade_enabled = SettingsUi.controls.range_fade_enabled:GetChecked()
    raid.bg_enabled = SettingsUi.controls.bg_enabled:GetChecked()
    raid.show_value_text = SettingsUi.controls.show_value_text:GetChecked()
    style.bar_colors_enabled = SettingsUi.controls.bar_colors_enabled:GetChecked()
    raid.width = sliderValue(SettingsUi.controls.width, raid.width)
    raid.hp_height = sliderValue(SettingsUi.controls.hp_height, raid.hp_height)
    raid.mp_height = sliderValue(SettingsUi.controls.mp_height, raid.mp_height)
    raid.name_font_size = sliderValue(SettingsUi.controls.name_font_size, raid.name_font_size)
    raid.name_max_chars = sliderValue(SettingsUi.controls.name_max_chars, raid.name_max_chars)
    raid.value_font_size = sliderValue(SettingsUi.controls.value_font_size, raid.value_font_size)
    raid.icon_size = sliderValue(SettingsUi.controls.icon_size, raid.icon_size)
    raid.leader_badge_size = sliderValue(SettingsUi.controls.leader_badge_size, raid.leader_badge_size)
    settings.button_size = sliderValue(SettingsUi.controls.button_size, settings.button_size)
    raid.name_padding_left = sliderValue(SettingsUi.controls.name_padding_left, raid.name_padding_left)
    raid.name_offset_x = sliderValue(SettingsUi.controls.name_offset_x, raid.name_offset_x)
    raid.name_offset_y = sliderValue(SettingsUi.controls.name_offset_y, raid.name_offset_y)
    raid.value_offset_x = sliderValue(SettingsUi.controls.value_offset_x, raid.value_offset_x)
    raid.value_offset_y = sliderValue(SettingsUi.controls.value_offset_y, raid.value_offset_y)
    raid.class_offset_x = sliderValue(SettingsUi.controls.class_offset_x, raid.class_offset_x)
    raid.class_offset_y = sliderValue(SettingsUi.controls.class_offset_y, raid.class_offset_y)
    raid.role_offset_x = sliderValue(SettingsUi.controls.role_offset_x, raid.role_offset_x)
    raid.role_offset_y = sliderValue(SettingsUi.controls.role_offset_y, raid.role_offset_y)
    raid.status_offset_x = sliderValue(SettingsUi.controls.status_offset_x, raid.status_offset_x)
    raid.status_offset_y = sliderValue(SettingsUi.controls.status_offset_y, raid.status_offset_y)
    raid.debuff_offset_x = sliderValue(SettingsUi.controls.debuff_offset_x, raid.debuff_offset_x)
    raid.debuff_offset_y = sliderValue(SettingsUi.controls.debuff_offset_y, raid.debuff_offset_y)
    raid.debuff_size = sliderValue(SettingsUi.controls.debuff_size, raid.debuff_size)
    raid.range_max_distance = sliderValue(SettingsUi.controls.range_max_distance, raid.range_max_distance)
    raid.range_alpha_pct = sliderValue(SettingsUi.controls.range_alpha_pct, raid.range_alpha_pct)
    raid.party_columns_per_row = sliderValue(SettingsUi.controls.party_columns_per_row, raid.party_columns_per_row)
    raid.grid_columns = sliderValue(SettingsUi.controls.grid_columns, raid.grid_columns)
    raid.gap_x = sliderValue(SettingsUi.controls.gap_x, raid.gap_x)
    raid.gap_y = sliderValue(SettingsUi.controls.gap_y, raid.gap_y)
    raid.party_row_gap = sliderValue(SettingsUi.controls.party_row_gap, raid.party_row_gap)
    for _, group in ipairs(COLOR_GROUPS) do
        ensureStyleColor(style, group)
    end
    syncColorAliases(style)
end

local function cycleControlText(key, options)
    local current = tostring(SettingsUi.controls[key].__value or options[1])
    local nextIndex = 1
    for index, option in ipairs(options) do
        if tostring(option) == current then
            nextIndex = index + 1
            break
        end
    end
    if nextIndex > #options then
        nextIndex = 1
    end
    SettingsUi.controls[key].__value = tostring(options[nextIndex])
    safeSetText(SettingsUi.controls[key], SettingsUi.controls[key].__value)
    setStatus("Unsaved changes. Use Apply or Save.")
end

normalizeHpTextureMode = function(mode)
    local value = tostring(mode or "raid")
    if value == "pc" or value == "npc" then
        return value
    end
    return "raid"
end

local function ensureWindow()
    if SettingsUi.window ~= nil then
        return
    end
    local constants = getConstants()
    local wnd = nil
    if api.Interface ~= nil and api.Interface.CreateEmptyWindow ~= nil then
        wnd = safeCall(function()
            return api.Interface:CreateEmptyWindow(constants.WINDOW_ID, "UIParent")
        end)
    end
    if wnd == nil then
        wnd = api.Interface:CreateWindow(constants.WINDOW_ID, constants.TITLE, BASE_WINDOW_WIDTH, BASE_WINDOW_HEIGHT)
    end
    SettingsUi.window = wnd
    applyCommonWindowBehavior(wnd)
    local savedSettings = getSettings() or {}
    anchorToUiParent(
        wnd,
        clamp(savedSettings.window_x, 0, 4000, 520),
        clamp(savedSettings.window_y, 0, 4000, 90)
    )
    attachShiftDrag(wnd)
    if wnd.SetExtent ~= nil then
        pcall(function()
            wnd:SetExtent(BASE_WINDOW_WIDTH, BASE_WINDOW_HEIGHT)
        end)
    end
    if wnd.SetHandler ~= nil then
        wnd:SetHandler("OnCloseByEsc", function()
            SettingsUi.window_visible = false
            safeShow(wnd, false)
        end)
    end

    local shell = createEmptyChild("nuziRaidWindowShell", wnd, 0, 0, BASE_WINDOW_WIDTH, BASE_WINDOW_HEIGHT)
    if shell ~= nil then
        addPanelBackground(shell, 0.94)
        addPanelAccent(shell, 44, 0.08)
        addPanelDivider(shell, 44, 12, -12, 0.12)
    end

    local header = createEmptyChild("nuziRaidHeader", wnd, 0, 0, BASE_WINDOW_WIDTH, 24)
    if header ~= nil then
        addPanelBackground(header, 0.98)
        addPanelAccent(header, 24, 0.10)
        addPanelDivider(header, 24, 10, -10, 0.14)
        attachShiftDrag(header, wnd)
        createLabel("nuziRaidHeaderTitle", header, "Nuzi Raid Settings", 14, 3, 15, 260)
        local headerClose = createButton("nuziRaidHeaderClose", header, "X", BASE_WINDOW_WIDTH - 38, 1, 26, 22)
        if headerClose ~= nil and headerClose.SetHandler ~= nil then
            headerClose:SetHandler("OnClick", function()
                SettingsUi.window_visible = false
                safeShow(wnd, false)
            end)
        end
        SettingsUi.controls.header = header
        SettingsUi.controls.header_close = headerClose
    end

    local navPanel = createEmptyChild("nuziRaidNavPanel", wnd, 12, 38, 168, 834)
    if navPanel ~= nil then
        addPanelBackground(navPanel, 0.88)
        addPanelAccent(navPanel, 42, 0.12)
    end

    local contentPanel = createEmptyChild("nuziRaidContentPanel", wnd, 192, 26, 776, 846)
    if contentPanel ~= nil then
        addPanelBackground(contentPanel, 0.86)
        addPanelAccent(contentPanel, 54, 0.12)
        addPanelDivider(contentPanel, 58, 18, -18, 0.18)
    end

    local navParent = navPanel or wnd
    local contentParent = contentPanel or wnd
    SettingsUi.controls.page_header_title = createLabel("nuziRaidPageHeaderTitle", contentParent, "", 18, 14, 18, 520)
    SettingsUi.controls.page_header_summary = createLabel("nuziRaidPageHeaderSummary", contentParent, "", 18, 40, 12, 720)

    createLabel("nuziRaidNavTitle", navParent, "Nuzi Raid", 14, 12, 18, 132)
    createLabel("nuziRaidNavSubtitle", navParent, "Raid frame settings", 14, 36, 12, 132)
    createLabel("nuziRaidNavSectionTitle", navParent, "Sections", 14, 74, 15, 132)
    createInfoLines("nuziRaidNavHint", navParent, {
        "Settings save to",
        ".data/settings.txt",
        "for reloads/updates."
    }, 14, 754, 12, 140, 17)

    local navY = 106
    createTabButton("nuziRaidTabGeneral", navParent, "general", 10, navY, 146); navY = navY + 36
    createTabButton("nuziRaidTabLayout", navParent, "layout", 10, navY, 146); navY = navY + 36
    createTabButton("nuziRaidTabBars", navParent, "bars", 10, navY, 146); navY = navY + 36
    createTabButton("nuziRaidTabText", navParent, "text", 10, navY, 146); navY = navY + 36
    createTabButton("nuziRaidTabMisc", navParent, "misc", 10, navY, 146)

    local generalPanel = createPanel("nuziRaidGeneralPanel", contentParent, 18, 70, 738, 690)
    local layoutPanel = createPanel("nuziRaidLayoutPanel", contentParent, 18, 70, 738, 690)
    local barsPanel = createPanel("nuziRaidBarsPanel", contentParent, 18, 70, 738, 690)
    local textPanel = createPanel("nuziRaidTextPanel", contentParent, 18, 70, 738, 690)
    local miscPanel = createPanel("nuziRaidMiscPanel", contentParent, 18, 70, 738, 690)
    SettingsUi.panels.general = generalPanel
    SettingsUi.panels.layout = layoutPanel
    SettingsUi.panels.bars = barsPanel
    SettingsUi.panels.text = textPanel
    SettingsUi.panels.misc = miscPanel

    SettingsUi.controls.hide_stock = fixedCheckbox(false)
    SettingsUi.controls.use_team_role_colors = fixedCheckbox(true)

    local leftX = 12
    local rightX = 370
    local yLeft = 12
    local yRight = 12

    createLabel("nuziRaidSectionGeneral", generalPanel, "Core", leftX, yLeft, 15, 160)
    yLeft = yLeft + 26
    SettingsUi.controls.enabled = createCheckbox("nuziRaidEnabled", generalPanel, "Addon enabled", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.raid_enabled = createCheckbox("nuziRaidRaidEnabled", generalPanel, "Replacement frames enabled", leftX, yLeft); yLeft = yLeft + 38

    createLabel("nuziRaidStockHelpTitle", generalPanel, "Stock Raid Frames", leftX, yLeft, 15, 220)
    yLeft = yLeft + 24
    yLeft = createInfoLines("nuziRaidStockHelp", generalPanel, {
        "To hide stock frames:",
        "open Raid Manager, then",
        "uncheck View Raid Info",
        "under Status Display."
    }, leftX, yLeft, 12, 320, 18)

    createLabel("nuziRaidSectionRuntime", generalPanel, "Runtime", rightX, yRight, 15, 160)
    SettingsUi.controls.runtime_line_1 = createLabel("nuziRaidRuntimeLine1", generalPanel, "", rightX, yRight + 28, 12, 330)
    SettingsUi.controls.runtime_line_2 = createLabel("nuziRaidRuntimeLine2", generalPanel, "", rightX, yRight + 46, 12, 330)
    SettingsUi.controls.runtime_status = createLabel("nuziRaidRuntimeStatus", generalPanel, "", rightX, yRight + 64, 12, 330)
    yRight = yRight + 104

    createLabel("nuziRaidSectionLauncher", generalPanel, "Launcher", rightX, yRight, 15, 160)
    yRight = yRight + 26
    SettingsUi.controls.button_size, SettingsUi.controls.button_size_val = createSlider("nuziRaidLauncherSize", generalPanel, "Icon size", rightX, yRight, 32, 96)

    yLeft = 12
    yRight = 12
    createLabel("nuziRaidSectionLayoutMode", layoutPanel, "Layout Mode", leftX, yLeft, 15, 180)
    yLeft = yLeft + 26
    createLabel("nuziRaidLayoutLbl", layoutPanel, "Layout mode", leftX, yLeft, 13, 140)
    SettingsUi.controls.layout = createButton("nuziRaidLayoutBtn", layoutPanel, "", leftX + 150, yLeft - 4, 150, 28)
    SettingsUi.controls.layout:SetHandler("OnClick", function()
        cycleControlText("layout", { "party_columns", "single_list", "compact_grid", "party_only" })
    end)
    yLeft = yLeft + 38
    SettingsUi.controls.show_group_headers = createCheckbox("nuziRaidGroupHeaders", layoutPanel, "Show party headers", leftX, yLeft); yLeft = yLeft + 42

    createLabel("nuziRaidSectionPartyLayout", layoutPanel, "Party Layout", leftX, yLeft, 15, 180)
    yLeft = yLeft + 26
    SettingsUi.controls.party_columns_per_row, SettingsUi.controls.party_columns_per_row_val = createSlider("nuziRaidPartyColumnsPerRow", layoutPanel, "Parties per row", leftX, yLeft, 1, 10); yLeft = yLeft + 32
    SettingsUi.controls.party_row_gap, SettingsUi.controls.party_row_gap_val = createSlider("nuziRaidPartyRowGap", layoutPanel, "Party row gap", leftX, yLeft, 0, 160); yLeft = yLeft + 42
    createInfoLines("nuziRaidPartyLayoutHelp", layoutPanel, {
        "Default is 5 per row:",
        "Party 1-5, then 6-10."
    }, leftX, yLeft, 12, 320, 18)

    createLabel("nuziRaidSectionGridLayout", layoutPanel, "Compact Grid", rightX, yRight, 15, 180)
    yRight = yRight + 26
    SettingsUi.controls.grid_columns, SettingsUi.controls.grid_columns_val = createSlider("nuziRaidGridColumns", layoutPanel, "Grid columns", rightX, yRight, 1, 10); yRight = yRight + 42

    createLabel("nuziRaidSectionSpacing", layoutPanel, "Spacing", rightX, yRight, 15, 160)
    yRight = yRight + 26
    SettingsUi.controls.gap_x, SettingsUi.controls.gap_x_val = createSlider("nuziRaidGapX", layoutPanel, "Column gap", rightX, yRight, 0, 80); yRight = yRight + 32
    SettingsUi.controls.gap_y, SettingsUi.controls.gap_y_val = createSlider("nuziRaidGapY", layoutPanel, "Row gap", rightX, yRight, 0, 80)

    yLeft = 12
    yRight = 12
    createLabel("nuziRaidSectionBars", barsPanel, "Bar Layout", leftX, yLeft, 15, 160)
    yLeft = yLeft + 26
    SettingsUi.controls.width, SettingsUi.controls.width_val = createSlider("nuziRaidWidth", barsPanel, "Frame width", leftX, yLeft, 30, 300); yLeft = yLeft + 32
    SettingsUi.controls.hp_height, SettingsUi.controls.hp_height_val = createSlider("nuziRaidHpHeight", barsPanel, "HP height", leftX, yLeft, 4, 60); yLeft = yLeft + 32
    SettingsUi.controls.mp_height, SettingsUi.controls.mp_height_val = createSlider("nuziRaidMpHeight", barsPanel, "MP height", leftX, yLeft, 0, 40); yLeft = yLeft + 42

    createLabel("nuziRaidSectionBarStyle", barsPanel, "Bar Style", leftX, yLeft, 15, 160)
    yLeft = yLeft + 26
    createLabel("nuziRaidBarStyleLbl", barsPanel, "Style source", leftX, yLeft, 13, 130)
    SettingsUi.controls.bar_style_mode = createButton("nuziRaidBarStyleBtn", barsPanel, "", leftX + 150, yLeft - 4, 150, 28)
    SettingsUi.controls.bar_style_mode:SetHandler("OnClick", function()
        cycleControlText("bar_style_mode", { "shared", "stock" })
    end)
    yLeft = yLeft + 34
    createLabel("nuziRaidTextureLbl", barsPanel, "HP texture", leftX, yLeft, 13, 130)
    SettingsUi.controls.hp_texture_mode = createButton("nuziRaidTextureBtn", barsPanel, "", leftX + 150, yLeft - 4, 150, 28)
    SettingsUi.controls.hp_texture_mode:SetHandler("OnClick", function()
        cycleControlText("hp_texture_mode", { "raid", "pc", "npc" })
    end)
    yLeft = yLeft + 38
    SettingsUi.controls.bar_colors_enabled = createCheckbox("nuziRaidBarColors", barsPanel, "Use custom MP/bar colors", leftX, yLeft)
    createInfoLines("nuziRaidRoleColorHelp", barsPanel, {
        "HP color comes from role,",
        "state, or bloodlust."
    }, leftX, yLeft + 36, 12, 320, 18)

    createLabel("nuziRaidSectionBarColors", barsPanel, "Bar Colors", rightX, yRight, 15, 160)
    do
        local colorIndex = 0
        for _, group in ipairs(COLOR_GROUPS) do
            if tostring(group.tab or "") == "bars" then
                createColorRow(group, barsPanel, rightX, yRight + 28 + (colorIndex * 42), 340)
                colorIndex = colorIndex + 1
            end
        end
    end

    yLeft = 12
    yRight = 12
    createLabel("nuziRaidSectionTextVisibility", textPanel, "Text Visibility", leftX, yLeft, 15, 180)
    yLeft = yLeft + 26
    SettingsUi.controls.use_role_name_colors = createCheckbox("nuziRaidRoleNameColors", textPanel, "Use role colors on names", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.text_colors_override_role_colors = createCheckbox("nuziRaidTextColorsOverride", textPanel, "Text colors override role/class", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.show_value_text = createCheckbox("nuziRaidValueText", textPanel, "Show HP/MP text", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.show_status_text = createCheckbox("nuziRaidStatusText", textPanel, "Show dead/offline text", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.show_class_icon = createCheckbox("nuziRaidClassMeta", textPanel, "Show class text", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.show_leader_badge = createCheckbox("nuziRaidLeaderBadge", textPanel, "Show raid leader badge", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.show_role_badge = createCheckbox("nuziRaidRoleBadge", textPanel, "Show role badge", leftX, yLeft); yLeft = yLeft + 40

    createLabel("nuziRaidSectionTextSize", textPanel, "Text Size", leftX, yLeft, 15, 160)
    yLeft = yLeft + 26
    SettingsUi.controls.name_font_size, SettingsUi.controls.name_font_size_val = createSlider("nuziRaidNameFont", textPanel, "Name font", leftX, yLeft, 6, 32); yLeft = yLeft + 32
    SettingsUi.controls.name_max_chars, SettingsUi.controls.name_max_chars_val = createSlider("nuziRaidNameMaxChars", textPanel, "Name max chars", leftX, yLeft, 0, 32); yLeft = yLeft + 32
    SettingsUi.controls.value_font_size, SettingsUi.controls.value_font_size_val = createSlider("nuziRaidValueFont", textPanel, "Value font", leftX, yLeft, 6, 24); yLeft = yLeft + 32
    SettingsUi.controls.icon_size, SettingsUi.controls.icon_size_val = createSlider("nuziRaidIconSize", textPanel, "Class/role badge", leftX, yLeft, 8, 24); yLeft = yLeft + 32
    SettingsUi.controls.leader_badge_size, SettingsUi.controls.leader_badge_size_val = createSlider("nuziRaidLeaderBadgeSize", textPanel, "Leader badge", leftX, yLeft, 6, 32); yLeft = yLeft + 40

    createLabel("nuziRaidSectionTextColors", textPanel, "Text Colors", leftX, yLeft, 15, 160)
    do
        local colorIndex = 0
        for _, group in ipairs(COLOR_GROUPS) do
            if tostring(group.tab or "") == "text" then
                createColorRow(group, textPanel, leftX, yLeft + 28 + (colorIndex * 42), 340)
                colorIndex = colorIndex + 1
            end
        end
    end

    createLabel("nuziRaidSectionTextPlacement", textPanel, "Text Placement", rightX, yRight, 15, 180)
    yRight = yRight + 26
    SettingsUi.controls.name_padding_left, SettingsUi.controls.name_padding_left_val = createSlider("nuziRaidNamePaddingLeft", textPanel, "Name padding", rightX, yRight, -20, 120); yRight = yRight + 32
    SettingsUi.controls.name_offset_x, SettingsUi.controls.name_offset_x_val = createSlider("nuziRaidNameOffsetX", textPanel, "Name X", rightX, yRight, -120, 120); yRight = yRight + 32
    SettingsUi.controls.name_offset_y, SettingsUi.controls.name_offset_y_val = createSlider("nuziRaidNameOffsetY", textPanel, "Name Y", rightX, yRight, -40, 40); yRight = yRight + 32
    SettingsUi.controls.value_offset_x, SettingsUi.controls.value_offset_x_val = createSlider("nuziRaidValueOffsetX", textPanel, "HP text X", rightX, yRight, -120, 120); yRight = yRight + 32
    SettingsUi.controls.value_offset_y, SettingsUi.controls.value_offset_y_val = createSlider("nuziRaidValueOffsetY", textPanel, "HP text Y", rightX, yRight, -40, 40); yRight = yRight + 32
    SettingsUi.controls.status_offset_x, SettingsUi.controls.status_offset_x_val = createSlider("nuziRaidStatusOffsetX", textPanel, "Status X", rightX, yRight, -120, 120); yRight = yRight + 32
    SettingsUi.controls.status_offset_y, SettingsUi.controls.status_offset_y_val = createSlider("nuziRaidStatusOffsetY", textPanel, "Status Y", rightX, yRight, -40, 40); yRight = yRight + 32
    SettingsUi.controls.class_offset_x, SettingsUi.controls.class_offset_x_val = createSlider("nuziRaidClassOffsetX", textPanel, "Class X", rightX, yRight, -120, 120); yRight = yRight + 32
    SettingsUi.controls.class_offset_y, SettingsUi.controls.class_offset_y_val = createSlider("nuziRaidClassOffsetY", textPanel, "Class Y", rightX, yRight, -40, 40); yRight = yRight + 32
    SettingsUi.controls.role_offset_x, SettingsUi.controls.role_offset_x_val = createSlider("nuziRaidRoleOffsetX", textPanel, "Role X", rightX, yRight, -120, 120); yRight = yRight + 32
    SettingsUi.controls.role_offset_y, SettingsUi.controls.role_offset_y_val = createSlider("nuziRaidRoleOffsetY", textPanel, "Role Y", rightX, yRight, -40, 40); yRight = yRight + 32

    yLeft = 12
    yRight = 12
    createLabel("nuziRaidSectionMisc", miscPanel, "Frame Extras", leftX, yLeft, 15, 160)
    yLeft = yLeft + 26
    SettingsUi.controls.show_target_highlight = createCheckbox("nuziRaidTargetHighlight", miscPanel, "Highlight current target", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.show_debuff_alert = createCheckbox("nuziRaidDebuffAlert", miscPanel, "Show debuff badge", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.bg_enabled = createCheckbox("nuziRaidBgEnabled", miscPanel, "Show frame background", leftX, yLeft); yLeft = yLeft + 42

    createLabel("nuziRaidSectionRangeFade", miscPanel, "Range Fade", leftX, yLeft, 15, 180)
    yLeft = yLeft + 26
    SettingsUi.controls.range_fade_enabled = createCheckbox("nuziRaidRangeFade", miscPanel, "Fade out-of-range members", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.range_max_distance, SettingsUi.controls.range_max_distance_val = createSlider("nuziRaidRangeMaxDistance", miscPanel, "Range distance", leftX, yLeft, 1, 300); yLeft = yLeft + 32
    SettingsUi.controls.range_alpha_pct, SettingsUi.controls.range_alpha_pct_val = createSlider("nuziRaidRangeAlpha", miscPanel, "Faded opacity", leftX, yLeft, 0, 100); yLeft = yLeft + 42

    createLabel("nuziRaidSectionDebuffPlacement", miscPanel, "Debuff Badge", leftX, yLeft, 15, 180)
    yLeft = yLeft + 26
    SettingsUi.controls.debuff_offset_x, SettingsUi.controls.debuff_offset_x_val = createSlider("nuziRaidDebuffOffsetX", miscPanel, "Debuff X", leftX, yLeft, -120, 120); yLeft = yLeft + 32
    SettingsUi.controls.debuff_offset_y, SettingsUi.controls.debuff_offset_y_val = createSlider("nuziRaidDebuffOffsetY", miscPanel, "Debuff Y", leftX, yLeft, -40, 40); yLeft = yLeft + 32
    SettingsUi.controls.debuff_size, SettingsUi.controls.debuff_size_val = createSlider("nuziRaidDebuffSize", miscPanel, "Debuff size", leftX, yLeft, 4, 32); yLeft = yLeft + 42

    createLabel("nuziRaidSectionMiscColors", miscPanel, "Misc Colors", rightX, yRight, 15, 160)
    do
        local colorIndex = 0
        for _, group in ipairs(COLOR_GROUPS) do
            if tostring(group.tab or "") == "misc" then
                createColorRow(group, miscPanel, rightX, yRight + 28 + (colorIndex * 42), 340)
                colorIndex = colorIndex + 1
            end
        end
    end

    createLabel("nuziRaidValueModeLbl", textPanel, "Value format", rightX, 420, 13, 130)
    SettingsUi.controls.value_text_mode = createButton("nuziRaidValueModeBtn", textPanel, "", rightX + 150, 416, 150, 28)
    SettingsUi.controls.value_text_mode:SetHandler("OnClick", function()
        cycleControlText("value_text_mode", { "percent", "curmax", "missing" })
    end)

    ensureColorPicker(contentParent)

    local footerPanel = createEmptyChild("nuziRaidFooterPanel", contentParent, 18, 776, 738, 58)
    if footerPanel ~= nil then
        addPanelBackground(footerPanel, 0.80)
        addPanelAccent(footerPanel, 28, 0.08)
    end
    local footerParent = footerPanel or contentParent
    local buttonY = footerPanel ~= nil and 24 or 800
    local applyButton = createButton("nuziRaidApply", footerParent, "Apply", 16, buttonY, 82, 28)
    local saveButton = createButton("nuziRaidSave", footerParent, "Save", 106, buttonY, 82, 28)
    local backupButton = createButton("nuziRaidBackup", footerParent, "Backup", 196, buttonY, 82, 28)
    local importButton = createButton("nuziRaidImport", footerParent, "Import", 286, buttonY, 82, 28)
    local resetButton = createButton("nuziRaidReset", footerParent, "Reset", 376, buttonY, 82, 28)
    local closeButton = createButton("nuziRaidClose", footerParent, "Close", 466, buttonY, 82, 28)
    SettingsUi.controls.status = createLabel("nuziRaidStatus", footerParent, "", 16, 6, 12, 690)

    local function applyChanges(persist)
        collectSettings()
        local settings = getSettings()
        if type(settings) == "table" and type(settings.raidframes) == "table" and type(settings.style) == "table" then
            settings.raidframes.layout_mode = tostring(SettingsUi.controls.layout.__value or settings.raidframes.layout_mode or "party_columns")
            settings.raidframes.bar_style_mode = tostring(SettingsUi.controls.bar_style_mode.__value or settings.raidframes.bar_style_mode or "shared")
            settings.raidframes.value_text_mode = tostring(SettingsUi.controls.value_text_mode.__value or settings.raidframes.value_text_mode or "percent")
            settings.style.hp_texture_mode = normalizeHpTextureMode(SettingsUi.controls.hp_texture_mode.__value or settings.style.hp_texture_mode)
        end
        if type(SettingsUi.actions) == "table" and type(SettingsUi.actions.apply) == "function" then
            SettingsUi.actions.apply()
        end
        if persist and type(SettingsUi.actions) == "table" and type(SettingsUi.actions.save) == "function" then
            local ok, detail = SettingsUi.actions.save()
            setStatus(ok and ("Saved" .. (detail and detail ~= "" and (": " .. tostring(detail)) or "")) or ("Save failed: " .. tostring(detail)))
        else
            setStatus("Applied")
        end
        refreshControls()
    end

    applyButton:SetHandler("OnClick", function()
        applyChanges(false)
    end)
    saveButton:SetHandler("OnClick", function()
        applyChanges(true)
    end)
    backupButton:SetHandler("OnClick", function()
        if type(SettingsUi.actions) == "table" and type(SettingsUi.actions.backup) == "function" then
            local ok, detail = SettingsUi.actions.backup()
            setStatus(ok and ("Backup saved: " .. tostring(detail or "")) or ("Backup failed: " .. tostring(detail)))
        end
    end)
    importButton:SetHandler("OnClick", function()
        if type(SettingsUi.actions) == "table" and type(SettingsUi.actions.import) == "function" then
            local ok, detail = SettingsUi.actions.import()
            setStatus(ok and "Imported latest backup" or ("Import failed: " .. tostring(detail)))
            refreshControls()
        end
    end)
    resetButton:SetHandler("OnClick", function()
        if type(SettingsUi.actions) == "table" and type(SettingsUi.actions.reset_all) == "function" then
            SettingsUi.actions.reset_all()
            refreshControls()
            setStatus("Reset to defaults")
        end
    end)
    closeButton:SetHandler("OnClick", function()
        SettingsUi.window_visible = false
        safeShow(wnd, false)
    end)

    safeShow(wnd, false)
    SettingsUi.window_visible = false
    selectTab(SettingsUi.active_tab)
    refreshControls()
end

local function ensureButton()
    if SettingsUi.button ~= nil then
        return
    end
    local parent = api.rootWindow
    if parent == nil then
        return
    end
    local constants = getConstants()
    local settings = getSettings() or {}
    local buttonSize = getLauncherSize()
    local button = safeCall(function()
        if api.Interface ~= nil and api.Interface.CreateEmptyWindow ~= nil then
            return api.Interface:CreateEmptyWindow(constants.BUTTON_ID, "UIParent")
        end
        return nil
    end)
    if button == nil then
        button = createButton(constants.BUTTON_ID, parent, "", 0, 0, buttonSize, buttonSize)
    end
    if button == nil then
        return
    end
    SettingsUi.button = button
    safeSetExtent(button, buttonSize, buttonSize)
    safeAnchor(button, "TOPLEFT", "UIParent", "TOPLEFT", tonumber(settings.button_x) or 90, tonumber(settings.button_y) or 420)
    applyCommonWindowBehavior(button)
    pcall(function()
        if button.SetText ~= nil then
            button:SetText("")
        end
        if button.Clickable ~= nil then
            button:Clickable(true)
        end
        if button.EnablePick ~= nil then
            button:EnablePick(true)
        end
        if button.RegisterForClicks ~= nil then
            button:RegisterForClicks("LeftButton")
        end
    end)
    SettingsUi.button_icon = createImageDrawable(
        button,
        constants.BUTTON_ID .. ".icon",
        assetPath(constants.LAUNCHER_ICON or DEFAULT_CONSTANTS.LAUNCHER_ICON),
        "artwork",
        buttonSize,
        buttonSize
    )
    if SettingsUi.button_icon == nil and button.SetText ~= nil then
        button:SetText("NR")
    end
    applyLauncherLayout()
    button:SetHandler("OnClick", function()
        if SettingsUi.dragging_launcher == true or SettingsUi.launcher_just_dragged == true then
            SettingsUi.dragging_launcher = false
            SettingsUi.launcher_just_dragged = false
            return
        end
        SettingsUi.Toggle()
    end)
    attachLauncherDrag(button)
    safeShow(button, true)
end

function SettingsUi.Refresh()
    if SettingsUi.window ~= nil then
        refreshControls()
    end
end

function SettingsUi.Toggle()
    ensureWindow()
    local show = not SettingsUi.window_visible
    safeShow(SettingsUi.window, show)
    SettingsUi.window_visible = show
    if show then
        selectTab(SettingsUi.active_tab)
        refreshControls()
    end
end

function SettingsUi.Init(actions)
    SettingsUi.actions = actions or {}
    ensureButton()
    ensureWindow()
    refreshControls()
end

function SettingsUi.Unload()
    if SettingsUi.button ~= nil and api.Interface ~= nil and api.Interface.Free ~= nil then
        pcall(function()
            api.Interface:Free(SettingsUi.button)
        end)
    end
    if SettingsUi.window ~= nil and api.Interface ~= nil and api.Interface.Free ~= nil then
        pcall(function()
            api.Interface:Free(SettingsUi.window)
        end)
    end
    SettingsUi.button = nil
    SettingsUi.button_icon = nil
    SettingsUi.window = nil
    SettingsUi.window_visible = false
    SettingsUi.dragging_launcher = false
    SettingsUi.launcher_just_dragged = false
    SettingsUi.controls = {}
    SettingsUi.panels = {}
    SettingsUi.tab_buttons = {}
    SettingsUi.color_page = 1
    SettingsUi.color_page_count = 1
    SettingsUi.color_cards = {}
    SettingsUi.color_picker = {
        active_group = nil,
        original_color = nil,
        overlay = nil,
        sliders = {},
        values = {}
    }
end

return SettingsUi
