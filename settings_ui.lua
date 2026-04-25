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
    BUTTON_ID = "polarRaidSettingsButton",
    WINDOW_ID = "polarRaidSettingsWindow",
    TITLE = "Nuzi Raid"
}

local SettingsUi = {
    button = nil,
    window = nil,
    window_visible = false,
    controls = {},
    panels = {},
    tab_buttons = {},
    active_tab = "general",
    actions = nil
}

local sliderValue
local setStatus

pcall(function()
    CreateNuziSlider = require("nuzi-core/ui/slider")
end)

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

local function createLabel(id, parent, text, x, y, fontSize, width)
    local label = api.Interface:CreateWidget("label", id, parent)
    label:AddAnchor("TOPLEFT", x, y)
    label:SetExtent(width or 220, 18)
    label:SetText(text)
    if label.style ~= nil then
        if label.style.SetFontSize ~= nil then
            label.style:SetFontSize(fontSize or 13)
        end
        if label.style.SetAlign ~= nil and ALIGN_REF ~= nil and ALIGN_REF.LEFT ~= nil then
            label.style:SetAlign(ALIGN_REF.LEFT)
        end
    end
    return label
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

local function createSlider(id, parent, text, x, y, minValue, maxValue)
    createLabel(id .. "Label", parent, text, x, y, 13, 170)
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
        slider:AddAnchor("TOPLEFT", x + 180, y - 4)
        slider:SetExtent(180, 26)
        slider:SetMinMaxValues(minValue, maxValue)
        if slider.SetStep ~= nil then
            slider:SetStep(1)
        elseif slider.SetValueStep ~= nil then
            slider:SetValueStep(1)
        end
    end
    local value = createLabel(id .. "Value", parent, "0", x + 370, y, 13, 50)
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

setStatus = function(text)
    safeSetText(SettingsUi.controls.status, text)
end

local function updateTabButtons()
    for key, button in pairs(SettingsUi.tab_buttons) do
        local label = key
        if key == "general" then
            label = "General"
        elseif key == "layout" then
            label = "Layout"
        elseif key == "style" then
            label = "Style"
        end
        safeSetText(button, SettingsUi.active_tab == key and ("[" .. label .. "]") or label)
    end
end

local function selectTab(tabKey)
    SettingsUi.active_tab = tabKey
    for key, panel in pairs(SettingsUi.panels) do
        safeShow(panel, key == tabKey)
    end
    updateTabButtons()
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
    SettingsUi.controls.show_target_highlight:SetChecked(raid.show_target_highlight ~= false)
    SettingsUi.controls.show_debuff_alert:SetChecked(raid.show_debuff_alert ~= false)
    SettingsUi.controls.show_class_icon:SetChecked(raid.show_class_icon ~= false)
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
    setSlider(SettingsUi.controls.hp_color_r, SettingsUi.controls.hp_color_r_val, colorValue(style.hp_bar_color, 1, 44))
    setSlider(SettingsUi.controls.hp_color_g, SettingsUi.controls.hp_color_g_val, colorValue(style.hp_bar_color, 2, 168))
    setSlider(SettingsUi.controls.hp_color_b, SettingsUi.controls.hp_color_b_val, colorValue(style.hp_bar_color, 3, 84))
    setSlider(SettingsUi.controls.mp_color_r, SettingsUi.controls.mp_color_r_val, colorValue(style.mp_bar_color, 1, 86))
    setSlider(SettingsUi.controls.mp_color_g, SettingsUi.controls.mp_color_g_val, colorValue(style.mp_bar_color, 2, 198))
    setSlider(SettingsUi.controls.mp_color_b, SettingsUi.controls.mp_color_b_val, colorValue(style.mp_bar_color, 3, 239))
    SettingsUi.controls.layout.__value = tostring(raid.layout_mode or "party_columns")
    SettingsUi.controls.bar_style_mode.__value = tostring(raid.bar_style_mode or "shared")
    SettingsUi.controls.hp_texture_mode.__value = tostring(style.hp_texture_mode or "stock")
    SettingsUi.controls.value_text_mode.__value = tostring(raid.value_text_mode or "percent")
    safeSetText(SettingsUi.controls.layout, tostring(raid.layout_mode or "party_columns"))
    safeSetText(SettingsUi.controls.bar_style_mode, tostring(raid.bar_style_mode or "shared"))
    safeSetText(SettingsUi.controls.hp_texture_mode, tostring(style.hp_texture_mode or "stock"))
    safeSetText(SettingsUi.controls.value_text_mode, tostring(raid.value_text_mode or "percent"))
    safeSetText(SettingsUi.controls.runtime_line_1, runtimeLines ~= nil and runtimeLines[1] or "")
    safeSetText(SettingsUi.controls.runtime_line_2, runtimeLines ~= nil and runtimeLines[2] or "")
    safeSetText(SettingsUi.controls.runtime_status, Compat ~= nil and Compat.GetStatusText() or "")
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
    raid.show_target_highlight = SettingsUi.controls.show_target_highlight:GetChecked()
    raid.show_debuff_alert = SettingsUi.controls.show_debuff_alert:GetChecked()
    raid.show_class_icon = SettingsUi.controls.show_class_icon:GetChecked()
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
    style.hp_bar_color = {
        sliderValue(SettingsUi.controls.hp_color_r, colorValue(style.hp_bar_color, 1, 44)),
        sliderValue(SettingsUi.controls.hp_color_g, colorValue(style.hp_bar_color, 2, 168)),
        sliderValue(SettingsUi.controls.hp_color_b, colorValue(style.hp_bar_color, 3, 84)),
        255
    }
    style.hp_fill_color = {
        style.hp_bar_color[1],
        style.hp_bar_color[2],
        style.hp_bar_color[3],
        255
    }
    style.hp_after_color = {
        style.hp_bar_color[1],
        style.hp_bar_color[2],
        style.hp_bar_color[3],
        255
    }
    style.mp_bar_color = {
        sliderValue(SettingsUi.controls.mp_color_r, colorValue(style.mp_bar_color, 1, 86)),
        sliderValue(SettingsUi.controls.mp_color_g, colorValue(style.mp_bar_color, 2, 198)),
        sliderValue(SettingsUi.controls.mp_color_b, colorValue(style.mp_bar_color, 3, 239)),
        255
    }
    style.mp_fill_color = {
        style.mp_bar_color[1],
        style.mp_bar_color[2],
        style.mp_bar_color[3],
        255
    }
    style.mp_after_color = {
        style.mp_bar_color[1],
        style.mp_bar_color[2],
        style.mp_bar_color[3],
        255
    }
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

local function ensureWindow()
    if SettingsUi.window ~= nil then
        return
    end
    local constants = getConstants()
    local wnd = api.Interface:CreateWindow(constants.WINDOW_ID, constants.TITLE, 960, 860)
    SettingsUi.window = wnd
    wnd:AddAnchor("CENTER", "UIParent", 0, 0)
    if wnd.SetExtent ~= nil then
        pcall(function()
            wnd:SetExtent(960, 860)
        end)
    end
    if wnd.SetHandler ~= nil then
        wnd:SetHandler("OnCloseByEsc", function()
            SettingsUi.window_visible = false
            safeShow(wnd, false)
        end)
    end

    createLabel("polarRaidHint", wnd, "Standalone raid frames. Tabs split live settings by category; Save persists changes.", 24, 46, 12, 540)
    SettingsUi.controls.runtime_line_1 = createLabel("polarRaidRuntimeLine1", wnd, "", 24, 62, 12, 540)
    SettingsUi.controls.runtime_line_2 = createLabel("polarRaidRuntimeLine2", wnd, "", 24, 78, 12, 540)
    SettingsUi.controls.runtime_status = createLabel("polarRaidRuntimeStatus", wnd, "", 24, 94, 12, 700)

    createTabButton("polarRaidTabGeneral", wnd, "general", 24, 122, 130)
    createTabButton("polarRaidTabLayout", wnd, "layout", 164, 122, 130)
    createTabButton("polarRaidTabStyle", wnd, "style", 304, 122, 130)

    local generalPanel = createPanel("polarRaidGeneralPanel", wnd, 24, 160, 910, 540)
    local layoutPanel = createPanel("polarRaidLayoutPanel", wnd, 24, 160, 910, 540)
    local stylePanel = createPanel("polarRaidStylePanel", wnd, 24, 160, 910, 540)
    SettingsUi.panels.general = generalPanel
    SettingsUi.panels.layout = layoutPanel
    SettingsUi.panels.style = stylePanel

    local leftX = 12
    local rightX = 448
    local yLeft = 12
    local yRight = 12

    createLabel("polarRaidSectionToggles", generalPanel, "General", leftX, yLeft, 15, 160)
    yLeft = yLeft + 26
    SettingsUi.controls.enabled = createCheckbox("polarRaidEnabled", generalPanel, "Addon enabled", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.raid_enabled = createCheckbox("polarRaidRaidEnabled", generalPanel, "Replacement frames enabled", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.hide_stock = createCheckbox("polarRaidHideStock", generalPanel, "Try hide stock raid frames", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.use_team_role_colors = createCheckbox("polarRaidRoleColors", generalPanel, "Use team role colors on HP bars", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.use_role_name_colors = createCheckbox("polarRaidRoleNameColors", generalPanel, "Use team role colors on names", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.show_target_highlight = createCheckbox("polarRaidTargetHighlight", generalPanel, "Highlight current target", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.show_debuff_alert = createCheckbox("polarRaidDebuffAlert", generalPanel, "Show debuff alert badge", leftX, yLeft); yLeft = yLeft + 30
    SettingsUi.controls.show_class_icon = createCheckbox("polarRaidClassMeta", generalPanel, "Show class short text", leftX, yLeft); yLeft = yLeft + 30

    createLabel("polarRaidSectionDisplay", generalPanel, "Display", rightX, yRight, 15, 160)
    yRight = yRight + 26
    SettingsUi.controls.show_role_badge = createCheckbox("polarRaidRoleBadge", generalPanel, "Show role badge", rightX, yRight); yRight = yRight + 30
    SettingsUi.controls.show_status_text = createCheckbox("polarRaidStatusText", generalPanel, "Show status text for dead/offline", rightX, yRight); yRight = yRight + 30
    SettingsUi.controls.show_group_headers = createCheckbox("polarRaidGroupHeaders", generalPanel, "Show party headers", rightX, yRight); yRight = yRight + 30
    SettingsUi.controls.range_fade_enabled = createCheckbox("polarRaidRangeFade", generalPanel, "Fade out-of-range members", rightX, yRight); yRight = yRight + 30
    SettingsUi.controls.bg_enabled = createCheckbox("polarRaidBgEnabled", generalPanel, "Show frame background", rightX, yRight); yRight = yRight + 30
    SettingsUi.controls.show_value_text = createCheckbox("polarRaidValueText", generalPanel, "Show HP/MP text on bars", rightX, yRight); yRight = yRight + 30
    SettingsUi.controls.bar_colors_enabled = createCheckbox("polarRaidBarColors", generalPanel, "Use custom HP/MP colors", rightX, yRight); yRight = yRight + 30

    yLeft = 12
    createLabel("polarRaidSectionSizing", layoutPanel, "Sizing", leftX, yLeft, 15, 120)
    yLeft = yLeft + 26
    SettingsUi.controls.width, SettingsUi.controls.width_val = createSlider("polarRaidWidth", layoutPanel, "Frame width", leftX, yLeft, 30, 300); yLeft = yLeft + 32
    SettingsUi.controls.hp_height, SettingsUi.controls.hp_height_val = createSlider("polarRaidHpHeight", layoutPanel, "HP height", leftX, yLeft, 4, 60); yLeft = yLeft + 32
    SettingsUi.controls.mp_height, SettingsUi.controls.mp_height_val = createSlider("polarRaidMpHeight", layoutPanel, "MP height", leftX, yLeft, 0, 40); yLeft = yLeft + 32
    SettingsUi.controls.name_font_size, SettingsUi.controls.name_font_size_val = createSlider("polarRaidNameFont", layoutPanel, "Name font size", leftX, yLeft, 6, 32); yLeft = yLeft + 32
    SettingsUi.controls.name_max_chars, SettingsUi.controls.name_max_chars_val = createSlider("polarRaidNameMaxChars", layoutPanel, "Name max chars (0 = full)", leftX, yLeft, 0, 32); yLeft = yLeft + 32
    SettingsUi.controls.value_font_size, SettingsUi.controls.value_font_size_val = createSlider("polarRaidValueFont", layoutPanel, "Value/status font size", leftX, yLeft, 6, 24); yLeft = yLeft + 32
    SettingsUi.controls.icon_size, SettingsUi.controls.icon_size_val = createSlider("polarRaidIconSize", layoutPanel, "Class/badge text size", leftX, yLeft, 8, 24); yLeft = yLeft + 32

    yRight = 12
    createLabel("polarRaidSectionLayoutModes", stylePanel, "Modes", leftX, yRight, 15, 120)
    yRight = yRight + 26
    createLabel("polarRaidLayoutLbl", stylePanel, "Layout mode", leftX, yRight, 13, 140)
    SettingsUi.controls.layout = createButton("polarRaidLayoutBtn", stylePanel, "", leftX + 180, yRight - 4, 160, 28)
    SettingsUi.controls.layout:SetHandler("OnClick", function()
        cycleControlText("layout", { "party_columns", "single_list", "compact_grid", "party_only" })
    end)
    createLabel("polarRaidLayoutHelp", stylePanel, "Party columns, single list, compact grid, or one party only.", leftX + 350, yRight, 12, 500)
    yRight = yRight + 34

    createLabel("polarRaidBarStyleLbl", stylePanel, "Bar style source", leftX, yRight, 13, 140)
    SettingsUi.controls.bar_style_mode = createButton("polarRaidBarStyleBtn", stylePanel, "", leftX + 180, yRight - 4, 160, 28)
    SettingsUi.controls.bar_style_mode:SetHandler("OnClick", function()
        cycleControlText("bar_style_mode", { "shared", "stock" })
    end)
    createLabel("polarRaidBarStyleHelp", stylePanel, "Shared uses addon colors; stock follows the client raid bar styling.", leftX + 350, yRight, 12, 500)
    yRight = yRight + 34

    createLabel("polarRaidTextureLbl", stylePanel, "HP texture mode", leftX, yRight, 13, 140)
    SettingsUi.controls.hp_texture_mode = createButton("polarRaidTextureBtn", stylePanel, "", leftX + 180, yRight - 4, 160, 28)
    SettingsUi.controls.hp_texture_mode:SetHandler("OnClick", function()
        cycleControlText("hp_texture_mode", { "stock", "pc", "npc" })
    end)
    createLabel("polarRaidTextureHelp", stylePanel, "Chooses which stock texture family the HP bar fill should use.", leftX + 350, yRight, 12, 500)
    yRight = yRight + 34

    createLabel("polarRaidValueModeLbl", stylePanel, "Value text mode", leftX, yRight, 13, 140)
    SettingsUi.controls.value_text_mode = createButton("polarRaidValueModeBtn", stylePanel, "", leftX + 180, yRight - 4, 160, 28)
    SettingsUi.controls.value_text_mode:SetHandler("OnClick", function()
        cycleControlText("value_text_mode", { "percent", "curmax", "missing" })
    end)
    createLabel("polarRaidValueModeHelp", stylePanel, "Shows percent, current/max, or missing HP text on the frame.", leftX + 350, yRight, 12, 500)

    local colorX = 12
    local colorY = yRight + 58
    createLabel("polarRaidSectionColors", stylePanel, "Colors", colorX, colorY, 15, 120)
    colorY = colorY + 26
    SettingsUi.controls.hp_color_r, SettingsUi.controls.hp_color_r_val = createSlider("polarRaidHpColorR", stylePanel, "HP color R", colorX, colorY, 0, 255); colorY = colorY + 32
    SettingsUi.controls.hp_color_g, SettingsUi.controls.hp_color_g_val = createSlider("polarRaidHpColorG", stylePanel, "HP color G", colorX, colorY, 0, 255); colorY = colorY + 32
    SettingsUi.controls.hp_color_b, SettingsUi.controls.hp_color_b_val = createSlider("polarRaidHpColorB", stylePanel, "HP color B", colorX, colorY, 0, 255); colorY = colorY + 32
    SettingsUi.controls.mp_color_r, SettingsUi.controls.mp_color_r_val = createSlider("polarRaidMpColorR", stylePanel, "MP color R", colorX, colorY, 0, 255); colorY = colorY + 32
    SettingsUi.controls.mp_color_g, SettingsUi.controls.mp_color_g_val = createSlider("polarRaidMpColorG", stylePanel, "MP color G", colorX, colorY, 0, 255); colorY = colorY + 32
    SettingsUi.controls.mp_color_b, SettingsUi.controls.mp_color_b_val = createSlider("polarRaidMpColorB", stylePanel, "MP color B", colorX, colorY, 0, 255)

    local buttonY = 736
    local applyButton = createButton("polarRaidApply", wnd, "Apply", 24, buttonY, 82, 28)
    local saveButton = createButton("polarRaidSave", wnd, "Save", 114, buttonY, 82, 28)
    local backupButton = createButton("polarRaidBackup", wnd, "Backup", 204, buttonY, 82, 28)
    local importButton = createButton("polarRaidImport", wnd, "Import", 294, buttonY, 82, 28)
    local resetButton = createButton("polarRaidReset", wnd, "Reset", 384, buttonY, 82, 28)
    local closeButton = createButton("polarRaidClose", wnd, "Close", 474, buttonY, 82, 28)
    SettingsUi.controls.status = createLabel("polarRaidStatus", wnd, "", 590, buttonY + 4, 12, 330)

    local function applyChanges(persist)
        collectSettings()
        local settings = getSettings()
        if type(settings) == "table" and type(settings.raidframes) == "table" and type(settings.style) == "table" then
            settings.raidframes.layout_mode = tostring(SettingsUi.controls.layout.__value or settings.raidframes.layout_mode or "party_columns")
            settings.raidframes.bar_style_mode = tostring(SettingsUi.controls.bar_style_mode.__value or settings.raidframes.bar_style_mode or "shared")
            settings.raidframes.value_text_mode = tostring(SettingsUi.controls.value_text_mode.__value or settings.raidframes.value_text_mode or "percent")
            settings.style.hp_texture_mode = tostring(SettingsUi.controls.hp_texture_mode.__value or settings.style.hp_texture_mode or "stock")
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
    local button = createButton(constants.BUTTON_ID, parent, "NR", 0, 0, 34, 28)
    SettingsUi.button = button
    local settings = getSettings() or {}
    button:AddAnchor("TOPLEFT", "UIParent", tonumber(settings.button_x) or 90, tonumber(settings.button_y) or 420)
    button:SetHandler("OnClick", function()
        SettingsUi.Toggle()
    end)
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
    SettingsUi.window = nil
    SettingsUi.window_visible = false
    SettingsUi.controls = {}
    SettingsUi.panels = {}
    SettingsUi.tab_buttons = {}
end

return SettingsUi
