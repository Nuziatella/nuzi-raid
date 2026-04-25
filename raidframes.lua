local api = require("api")
local Require = require("nuzi-core/require")

local function loadModule(name)
    local mod = Require.Addon("nuzi-raid", name)
    return mod
end

local Shared = loadModule("shared")
local Runtime = loadModule("runtime")
local Compat = loadModule("compat")
local Helpers = loadModule("raid_helpers")
local UnitHelpers = loadModule("raid_unit_helpers")
local TeamHelpers = loadModule("raid_team_helpers")
local FormatHelpers = loadModule("raid_format_helpers")
local globals = type(_G) == "table" and _G or nil
local ALIGN_REF = type(ALIGN) == "table" and ALIGN or (globals ~= nil and globals.ALIGN or nil)
local ActivatePopupMenuRef = type(ActivatePopupMenu) == "function" and ActivatePopupMenu or (globals ~= nil and globals.ActivatePopupMenu or nil)
local CreateUnitFrameRef = type(CreateUnitFrame) == "function" and CreateUnitFrame or (globals ~= nil and globals.CreateUnitFrame or nil)
local StatusBarStyleRef = type(STATUSBAR_STYLE) == "table" and STATUSBAR_STYLE or (globals ~= nil and globals.STATUSBAR_STYLE or nil)
local TexturePathRef = type(TEXTURE_PATH) == "table" and TEXTURE_PATH or (globals ~= nil and globals.TEXTURE_PATH or nil)
local WIconRef = type(W_ICON) == "table" and W_ICON or (globals ~= nil and globals.W_ICON or nil)

local RaidFrames = {
    container = nil,
    drag_handle = nil,
    frames = {},
    group_headers = {},
    settings = nil,
    enabled = true,
    active_members = {},
    unit_ids_by_index = {},
    unit_ids_by_name = {},
    current_target_id = nil,
    now_ms = 0,
    popup_anchor_to_cursor = false,
    popup_anchor_hooked = false
}

local MAX_RAID_MEMBERS = 50
local GROUP_SIZE = 5
local HEADER_HEIGHT = 18
local HEADER_GAP = 4
local DRAG_HANDLE_HEIGHT = 14
local BLOODLUST_BUFF_ID = 1482
local BLOODLUST_SCAN_INTERVAL_MS = 450
local BLOODLUST_SCAN_JITTER_MS = 140

local TEAM_ROLE_COLORS = {
    defender = { 255, 210, 70, 255 },
    healer = { 255, 120, 205, 255 },
    attacker = { 255, 95, 95, 255 },
    undecided = { 110, 170, 255, 255 }
}
local DEFAULT_HP_COLOR = { 223, 69, 69, 255 }
local DEFAULT_MP_COLOR = { 86, 198, 239, 255 }
local OFFLINE_BAR_COLOR = { 100, 100, 100, 255 }
local DEAD_BAR_COLOR = { 150, 70, 70, 255 }
local DEFAULT_TEXT_COLOR = { 255, 255, 255, 255 }
local OFFLINE_TEXT_COLOR = { 180, 180, 180, 255 }
local DEAD_TEXT_COLOR = { 220, 150, 150, 255 }
local TARGET_TINT_COLOR = { 255, 230, 120, 72 }
local DEBUFF_BADGE_COLOR = { 255, 68, 68, 235 }
local DISPELLABLE_DEBUFF_BADGE_COLOR = { 255, 210, 72, 235 }
local DEFAULT_BG_COLOR = { 13, 13, 15, 255 }
local RAID_UI_LAYER = "game"
local POPUP_UI_LAYER = "dialog"

local clamp = Helpers.Clamp
local percent01 = Helpers.Percent01
local trim = Helpers.Trim
local safeShow = Helpers.SafeShow
local safeApplyBarTexture = Helpers.SafeApplyBarTexture
local safeSetWidgetTarget = Helpers.SafeSetWidgetTarget
local safeAssignWidgetField = Helpers.SafeAssignWidgetField
local getBarValueTarget = Helpers.GetBarValueTarget
local safeSetExtent = Helpers.SafeSetExtent
local safeSetHeight = Helpers.SafeSetHeight
local safeClickable = Helpers.SafeClickable
local safeAnchor = Helpers.SafeAnchor
local safeSetFontSize = Helpers.SafeSetFontSize
local updateCachedText = Helpers.UpdateCachedText
local updateCachedVisible = Helpers.UpdateCachedVisible
local updateCachedAlpha = Helpers.UpdateCachedAlpha
local updateCachedLabelColor = Helpers.UpdateCachedLabelColor
local updateCachedBarColor = Helpers.UpdateCachedBarColor
local updateCachedDrawableColor = Helpers.UpdateCachedDrawableColor
local updateCachedBarValue = Helpers.UpdateCachedBarValue
local firstNumber = Helpers.FirstNumber
local isRightClick = Helpers.IsRightClick

local function safeEnablePick(widget, enabled)
    if widget == nil or widget.EnablePick == nil then
        return
    end
    pcall(function()
        widget:EnablePick(enabled and true or false)
    end)
end

local function safeRaise(widget)
    if widget == nil or widget.Raise == nil then
        return
    end
    pcall(function()
        widget:Raise()
    end)
end

local function safeSetUiLayer(widget, layer)
    if widget == nil or widget.SetUILayer == nil then
        return
    end
    pcall(function()
        widget:SetUILayer(layer)
    end)
end

local function raisePopupMenu(popup)
    if popup == nil then
        return
    end
    safeSetUiLayer(popup, POPUP_UI_LAYER)
    safeRaise(popup)
    if type(popup.buttons) == "table" then
        for _, button in ipairs(popup.buttons) do
            safeRaise(button)
        end
    end
end

local function disablePopupOwnerInput(owner)
    safeEnablePick(owner, false)
    safeClickable(owner, false)
    if owner ~= nil then
        safeEnablePick(owner.eventWindow, false)
        safeClickable(owner.eventWindow, false)
    end
end

local safeUnitInfo = UnitHelpers.SafeUnitInfo
local safeUnitInfoById = UnitHelpers.SafeUnitInfoById
local hasUsableVitals = UnitHelpers.HasUsableVitals
local safeUnitModifierInfo = UnitHelpers.SafeUnitModifierInfo
local safeUnitClassName = UnitHelpers.SafeUnitClassName
local safeUnitName = UnitHelpers.SafeUnitName
local safeUnitId = UnitHelpers.SafeUnitId
local safeUnitHealth = UnitHelpers.SafeUnitHealth
local safeUnitDistance = UnitHelpers.SafeUnitDistance
local safeUnitOffline = UnitHelpers.SafeUnitOffline
local safeUnitTeamAuthority = UnitHelpers.SafeUnitTeamAuthority
local safeDebuffCount = UnitHelpers.SafeDebuffCount
local hasDispellableDebuff = UnitHelpers.HasDispellableDebuff

local getTeamRoleKey = TeamHelpers.GetTeamRoleKey
local getRaidPopupKind = TeamHelpers.GetRaidPopupKind

local getRolePrefix = FormatHelpers.GetRolePrefix
local getRoleBadge = FormatHelpers.GetRoleBadge
local getClassBadge = FormatHelpers.GetClassBadge
local formatName = FormatHelpers.FormatName
local getUnitState = FormatHelpers.GetUnitState
local getValueText = FormatHelpers.GetValueText
local mergeResourceValues = FormatHelpers.MergeResourceValues
local getClassColor = FormatHelpers.GetClassColor

local function colorOrFallback(settings, key, fallback)
    local style = type(settings) == "table" and settings.style or nil
    if type(style) == "table" and type(style[key]) == "table" then
        return style[key]
    end
    return fallback
end

local function colorChannel01(color, index, fallback)
    local source = type(color) == "table" and color or nil
    return clamp(source ~= nil and source[index] or nil, 0, 255, fallback or 255) / 255
end

local function getTeamRoleColor(settings, roleKey)
    if roleKey == "defender" then
        return colorOrFallback(settings, "defender_role_color", TEAM_ROLE_COLORS.defender)
    end
    if roleKey == "healer" then
        return colorOrFallback(settings, "healer_role_color", TEAM_ROLE_COLORS.healer)
    end
    if roleKey == "attacker" then
        return colorOrFallback(settings, "attacker_role_color", TEAM_ROLE_COLORS.attacker)
    end
    if roleKey == "undecided" then
        return colorOrFallback(settings, "undecided_role_color", TEAM_ROLE_COLORS.undecided)
    end
    return nil
end

local function unitHasBuff(unit, buffId)
    if trim(unit) == "" or api.Unit == nil or api.Unit.UnitBuffCount == nil or api.Unit.UnitBuff == nil then
        return false
    end

    local buffCount = 0
    pcall(function()
        buffCount = api.Unit:UnitBuffCount(unit) or 0
    end)

    for index = 1, tonumber(buffCount) or 0 do
        local buff = nil
        pcall(function()
            buff = api.Unit:UnitBuff(unit, index)
        end)
        if type(buff) == "table" then
            local id = tonumber(buff.buff_id or buff.buffId or buff.id)
            if id == buffId then
                return true
            end
        end
    end
    return false
end

local function isTeamUnit(unit)
    return string.match(tostring(unit or ""), "^team%d+$") ~= nil
end

local function isUnitTeamMember(unit)
    if trim(unit) == "" then
        return false
    end
    if api.Unit ~= nil and api.Unit.UnitIsTeamMember ~= nil then
        local ok, result = pcall(function()
            return api.Unit:UnitIsTeamMember(unit)
        end)
        if ok then
            return result and true or false
        end
    end
    return isTeamUnit(unit)
end

local function getTextureInfo(styleKey)
    if StatusBarStyleRef == nil or type(styleKey) ~= "string" then
        return nil
    end
    return StatusBarStyleRef[styleKey]
end

local function getFirstTextureStyle(key1, key2, key3, key4)
    local style = getTextureInfo(key1)
    if style ~= nil then
        return key1, style
    end
    style = getTextureInfo(key2)
    if style ~= nil then
        return key2, style
    end
    style = getTextureInfo(key3)
    if style ~= nil then
        return key3, style
    end
    style = getTextureInfo(key4)
    if style ~= nil then
        return key4, style
    end
    return nil, nil
end

local function getTexturePath(pathKey)
    if TexturePathRef == nil then
        return nil
    end
    return TexturePathRef[pathKey]
end

local function getHpTextureDescriptor(settings, cfg, member, state)
    if StatusBarStyleRef == nil then
        return nil
    end

    local mode = "raid"
    if type(settings) == "table" and type(settings.style) == "table" then
        mode = tostring(settings.style.hp_texture_mode or "raid")
    end
    local hpHeight = clamp(type(cfg) == "table" and cfg.hp_height or nil, 8, 80, 16)
    local small = hpHeight <= 18

    local pathKey = "RAID"
    local styleKey = nil
    local style = nil

    if mode == "pc" then
        pathKey = "HUD"
        if state ~= nil and (state.offline or state.dead) then
            styleKey, style = getFirstTextureStyle(small and "S_HP_OFFLINE" or "L_HP_OFFLINE", small and "S_HP_PARTY" or "L_HP_PARTY")
        else
            styleKey, style = getFirstTextureStyle(small and "S_HP_PARTY" or "L_HP_PARTY", small and "S_HP_FRIENDLY" or "L_HP_FRIENDLY")
        end
    elseif mode == "npc" then
        pathKey = "HUD"
        if state ~= nil and (state.offline or state.dead) then
            styleKey, style = getFirstTextureStyle(small and "S_HP_OFFLINE" or "L_HP_OFFLINE", small and "S_HP_NEUTRAL" or "L_HP_NEUTRAL")
        else
            styleKey, style = getFirstTextureStyle(small and "S_HP_NEUTRAL" or "L_HP_NEUTRAL", small and "S_HP_HOSTILE" or "L_HP_HOSTILE")
        end
    else
        if state ~= nil and (state.offline or state.dead) then
            styleKey, style = getFirstTextureStyle(small and "S_HP_RAID_OFFLINE" or "HP_RAID_OFFLINE", small and "S_HP_RAID" or "HP_RAID")
        elseif member ~= nil and member.role_key == "defender" then
            styleKey, style = getFirstTextureStyle(small and "S_HP_RAID_TANKER" or "HP_RAID_TANKER", small and "S_HP_RAID" or "HP_RAID")
        elseif member ~= nil and member.role_key == "healer" then
            styleKey, style = getFirstTextureStyle(small and "S_HP_RAID_HEALER" or "HP_RAID_HEALER", small and "S_HP_RAID" or "HP_RAID")
        elseif member ~= nil and member.role_key == "attacker" then
            styleKey, style = getFirstTextureStyle(small and "S_HP_RAID_DEALER" or "HP_RAID_DEALER", small and "S_HP_RAID" or "HP_RAID")
        else
            styleKey, style = getFirstTextureStyle(small and "S_HP_RAID" or "HP_RAID", "HP_RAID")
        end
    end

    if style == nil then
        return nil
    end
    return {
        key = pathKey .. ":" .. tostring(styleKey or ""),
        path = getTexturePath(pathKey),
        style = style
    }
end

local function getMpTextureDescriptor(settings, cfg, state)
    if StatusBarStyleRef == nil then
        return nil
    end

    local mode = "raid"
    if type(settings) == "table" and type(settings.style) == "table" then
        mode = tostring(settings.style.hp_texture_mode or "raid")
    end
    local mpHeight = clamp(type(cfg) == "table" and cfg.mp_height or nil, 0, 40, 0)
    local small = mpHeight <= 5

    local pathKey = "RAID"
    local styleKey = nil
    local style = nil
    if mode == "pc" or mode == "npc" then
        pathKey = "HUD"
        if state ~= nil and (state.offline or state.dead) then
            styleKey, style = getFirstTextureStyle(small and "S_MP_OFFLINE" or "L_MP_OFFLINE", small and "S_MP" or "L_MP")
        else
            styleKey, style = getFirstTextureStyle(small and "S_MP" or "L_MP", "S_MP")
        end
    else
        if state ~= nil and (state.offline or state.dead) then
            styleKey, style = getFirstTextureStyle(small and "S_MP_RAID_OFFLINE" or "MP_RAID_OFFLINE", small and "S_MP_RAID" or "MP_RAID")
        else
            styleKey, style = getFirstTextureStyle(small and "S_MP_RAID" or "MP_RAID", "MP_RAID")
        end
    end

    if style == nil then
        return nil
    end
    return {
        key = pathKey .. ":" .. tostring(styleKey or ""),
        path = getTexturePath(pathKey),
        style = style
    }
end

local function applyBarTextureDescriptor(bar, descriptor)
    if bar == nil or descriptor == nil then
        return
    end
    if descriptor.path ~= nil and bar.statusBar ~= nil and bar.statusBar.SetBarTexture ~= nil then
        pcall(function()
            bar.statusBar:SetBarTexture(descriptor.path, "artwork")
        end)
    end
    safeApplyBarTexture(bar, descriptor.style)
end

local function applyFrameTextures(frame, settings, cfg, member, state)
    if frame == nil then
        return
    end
    local hpDescriptor = getHpTextureDescriptor(settings, cfg, member, state)
    local mpDescriptor = getMpTextureDescriptor(settings, cfg, state)
    local textureKey = tostring(hpDescriptor ~= nil and hpDescriptor.key or "nil") .. "|" .. tostring(mpDescriptor ~= nil and mpDescriptor.key or "nil")
    if frame.__nr_texture_key == textureKey then
        return
    end
    frame.__nr_texture_key = textureKey
    applyBarTextureDescriptor(frame.hpAfterBar, hpDescriptor)
    applyBarTextureDescriptor(frame.hpBar, hpDescriptor)
    applyBarTextureDescriptor(frame.mpAfterBar, mpDescriptor)
    applyBarTextureDescriptor(frame.mpBar, mpDescriptor)
end

local function getFrameHeight(cfg)
    local hpHeight = clamp(cfg.hp_height, 8, 80, 16)
    local mpHeight = clamp(cfg.mp_height, 0, 40, 0)
    local total = hpHeight
    if mpHeight > 0 then
        total = total + mpHeight + 1
    end
    return total
end

local function getLayoutMax(cfg)
    if tostring(cfg.layout_mode or "party_columns") == "party_only" then
        return 5
    end
    return MAX_RAID_MEMBERS
end

local function createColorDrawable(owner, name, r, g, b, a)
    if owner == nil or owner.CreateColorDrawable == nil then
        return nil
    end
    local drawable = nil
    pcall(function()
        drawable = owner:CreateColorDrawable(r, g, b, a, name)
    end)
    return drawable
end

local function savePosition()
    if Shared == nil then
        return
    end
    local settings = Shared.GetSettings()
    local raid = settings.raidframes
    local x = nil
    local y = nil
    local container = RaidFrames.container
    if container ~= nil and type(container.GetOffset) == "function" then
        pcall(function()
            x, y = container:GetOffset()
        end)
    end
    if type(x) == "number" then
        raid.x = x
    end
    if type(y) == "number" then
        raid.y = y
    end
    Shared.SaveSettings()
end

local function applyContainerPosition(cfg)
    local wnd = RaidFrames.container
    if wnd == nil then
        return
    end
    local x = clamp(cfg.x, -4000, 4000, 600)
    local y = clamp(cfg.y, -4000, 4000, 250)
    if wnd.__nr_x == x and wnd.__nr_y == y then
        return
    end
    wnd.__nr_x = x
    wnd.__nr_y = y
    safeAnchor(wnd, "TOPLEFT", "UIParent", "TOPLEFT", x, y)
end

local function ensureContainer()
    if RaidFrames.container ~= nil then
        return RaidFrames.container
    end

    local wnd = api.Interface:CreateEmptyWindow("nuziRaidFramesContainer")
    pcall(function()
        safeSetUiLayer(wnd, RAID_UI_LAYER)
    end)

    local dragHandle = api.Interface:CreateWidget("label", "nuziRaidFramesDragHandle", wnd)
    pcall(function()
        dragHandle:Show(true)
        dragHandle:SetText("Nuzi Raid")
        dragHandle:SetExtent(120, DRAG_HANDLE_HEIGHT)
        if dragHandle.style ~= nil then
            dragHandle.style:SetFontSize(10)
            dragHandle.style:SetColor(0.82, 0.82, 0.82, 0.8)
            if dragHandle.style.SetAlign ~= nil and ALIGN_REF ~= nil and ALIGN_REF.LEFT ~= nil then
                dragHandle.style:SetAlign(ALIGN_REF.LEFT)
            end
        end
        dragHandle:AddAnchor("TOPLEFT", wnd, 0, -DRAG_HANDLE_HEIGHT)
    end)

    function wnd:OnDragStart()
        local settings = Shared ~= nil and Shared.GetSettings() or nil
        local dragRequiresShift = type(settings) == "table" and settings.drag_requires_shift
        if dragRequiresShift and api.Input ~= nil and api.Input.IsShiftKeyDown ~= nil then
            local ok, down = pcall(function()
                return api.Input:IsShiftKeyDown()
            end)
            if not ok or not down then
                return
            end
        end
        if self.StartMoving ~= nil then
            self:StartMoving()
        end
    end

    function wnd:OnDragStop()
        if self.StopMovingOrSizing ~= nil then
            self:StopMovingOrSizing()
        end
        savePosition()
    end

    pcall(function()
        if wnd.SetHandler ~= nil then
            wnd:SetHandler("OnDragStart", wnd.OnDragStart)
            wnd:SetHandler("OnDragStop", wnd.OnDragStop)
        end
        if wnd.RegisterForDrag ~= nil then
            wnd:RegisterForDrag("LeftButton")
        end
        if wnd.EnableDrag ~= nil then
            wnd:EnableDrag(true)
        end
    end)

    RaidFrames.container = wnd
    RaidFrames.drag_handle = dragHandle
    return wnd
end

local function updateContainerExtent(cfg, members)
    local wnd = ensureContainer()
    local frameWidth = clamp(cfg.width, 60, 400, 80)
    local frameHeight = getFrameHeight(cfg)
    local gapX = clamp(cfg.gap_x, 0, 80, 2)
    local gapY = clamp(cfg.gap_y, 0, 80, 2)
    local layout = tostring(cfg.layout_mode or "party_columns")
    local count = #members

    local width = frameWidth
    local height = frameHeight
    if layout == "party_columns" or layout == "party_only" then
        local maxGroup = 1
        for _, member in ipairs(members) do
            local groupIndex = math.floor(((member.index or 1) - 1) / GROUP_SIZE) + 1
            if groupIndex > maxGroup then
                maxGroup = groupIndex
            end
        end
        width = (maxGroup * frameWidth) + ((maxGroup - 1) * gapX)
        height = (GROUP_SIZE * frameHeight) + ((GROUP_SIZE - 1) * gapY)
        if cfg.show_group_headers ~= false then
            height = height + HEADER_HEIGHT + HEADER_GAP
        end
    elseif layout == "single_list" then
        local rows = math.max(1, count)
        width = frameWidth
        height = (rows * frameHeight) + ((rows - 1) * gapY)
        if cfg.show_group_headers ~= false then
            local groupCount = math.max(1, math.ceil(math.max(count, 1) / GROUP_SIZE))
            height = height + (groupCount * (HEADER_HEIGHT + HEADER_GAP))
        end
    else
        local columns = clamp(cfg.grid_columns, 1, 10, 8)
        local rows = math.max(1, math.ceil(math.max(count, 1) / columns))
        local usedColumns = math.min(columns, math.max(count, 1))
        width = (usedColumns * frameWidth) + ((usedColumns - 1) * gapX)
        height = (rows * frameHeight) + ((rows - 1) * gapY)
    end

    width = math.max(32, width)
    height = math.max(24, height)
    local extentKey = tostring(width) .. "|" .. tostring(height)
    if wnd.__nr_extent_key == extentKey then
        return
    end
    wnd.__nr_extent_key = extentKey
    safeSetExtent(wnd, width, height)
end

local function ensureGroupHeader(groupIndex)
    if RaidFrames.group_headers[groupIndex] ~= nil then
        return RaidFrames.group_headers[groupIndex]
    end

    local header = api.Interface:CreateWidget("label", "nuziRaidGroupHeader" .. tostring(groupIndex), ensureContainer())
    pcall(function()
        header:Show(true)
        header:SetText("Party" .. tostring(groupIndex))
        header:SetExtent(90, HEADER_HEIGHT)
        if header.style ~= nil then
            header.style:SetFontSize(11)
            header.style:SetColor(0.92, 0.82, 0.35, 1)
            if header.style.SetAlign ~= nil and ALIGN_REF ~= nil and ALIGN_REF.LEFT ~= nil then
                header.style:SetAlign(ALIGN_REF.LEFT)
            end
        end
    end)

    RaidFrames.group_headers[groupIndex] = header
    return header
end

local function createRaidBar(frameId, parent)
    if W_BAR == nil or W_BAR.CreateStatusBarOfRaidFrame == nil then
        return nil
    end
    local bar = nil
    pcall(function()
        bar = W_BAR.CreateStatusBarOfRaidFrame(frameId, parent)
        if bar ~= nil then
            bar:Show(true)
            safeClickable(bar, false)
            safeClickable(bar.statusBar, false)
        end
    end)
    return bar
end

local function createLeaderMark(frameId, parent)
    local mark = nil
    if WIconRef ~= nil and WIconRef.CreateLeaderMark ~= nil then
        pcall(function()
            mark = WIconRef.CreateLeaderMark(frameId .. ".leader", parent)
        end)
    end
    if mark ~= nil then
        safeShow(mark, false)
        safeClickable(mark, false)
        safeClickable(mark.bg, false)
        return mark
    end

    local label = api.Interface:CreateWidget("label", frameId .. ".leader", parent)
    label.__nr_text_leader_mark = true
    pcall(function()
        label:Show(false)
        label:SetText("L")
        if label.SetAutoResize ~= nil then
            label:SetAutoResize(false)
        end
        if label.style ~= nil then
            label.style:SetColor(1, 0.9, 0.35, 1)
            if label.style.SetAlign ~= nil and ALIGN_REF ~= nil and ALIGN_REF.CENTER ~= nil then
                label.style:SetAlign(ALIGN_REF.CENTER)
            end
            if label.style.SetShadow ~= nil then
                label.style:SetShadow(true)
            end
        end
    end)
    return label
end

local function applyLeaderMarkSize(mark, size)
    if mark == nil then
        return
    end
    local markSize = clamp(size, 6, 32, 11)
    safeSetExtent(mark, markSize, markSize)
    if mark.bg ~= nil then
        safeSetExtent(mark.bg, markSize, markSize)
    end
    if mark.__nr_text_leader_mark == true then
        safeSetFontSize(mark, markSize)
    end
end

local function updateLeaderMark(frame, cfg, authority)
    if frame == nil or frame.leaderMark == nil then
        return
    end
    local show = cfg.show_leader_badge ~= false and trim(authority) == "leader"
    if show and frame.leaderMark.SetMark ~= nil then
        pcall(function()
            frame.leaderMark:SetMark(authority, false)
        end)
    elseif show and frame.leaderMark.SetText ~= nil then
        pcall(function()
            frame.leaderMark:SetText("L")
        end)
    end
    updateCachedVisible(frame, "__nr_leader_visible", frame.leaderMark, show)
end

local function anchorPopupToCursor(popup)
    if popup == nil then
        return false
    end

    pcall(function()
        if popup.RemoveAllAnchors ~= nil then
            popup:RemoveAllAnchors()
        end
    end)

    if popup.AnchorToMousePosition ~= nil then
        local ok = pcall(function()
            popup:AnchorToMousePosition()
        end)
        return ok and true or false
    end

    return false
end

local function ensurePopupCursorAnchorHook()
    if RaidFrames.popup_anchor_hooked == true then
        return
    end

    if api == nil or api.On == nil then
        return
    end

    local ok = pcall(function()
        api.On("ShowPopUp", function(popup)
            if RaidFrames.popup_anchor_to_cursor ~= true then
                return
            end

            RaidFrames.popup_anchor_to_cursor = false
            anchorPopupToCursor(popup)
            raisePopupMenu(popup)
        end)
    end)
    if ok then
        RaidFrames.popup_anchor_hooked = true
    end
end

local function runPopupActionAtCursor(action)
    ensurePopupCursorAnchorHook()
    RaidFrames.popup_anchor_to_cursor = true
    local ok, err = pcall(action)
    if RaidFrames.popup_anchor_to_cursor == true then
        RaidFrames.popup_anchor_to_cursor = false
    end
    return ok, err
end

local function getPopupMemberIndex(frame)
    if frame == nil then
        return nil
    end

    local directIndex = tonumber(frame.__raid_member_index or frame.memberIndex or frame.index)
    if directIndex ~= nil then
        return math.floor(directIndex)
    end

    local unit = trim(frame.__raid_unit or frame.target or frame.unit)
    local unitIndex = string.match(unit, "^team(%d+)$")
    if unitIndex ~= nil then
        return tonumber(unitIndex)
    end

    return nil
end

local function activateRaidPopup(owner, popupKind, memberIndex)
    if owner == nil or ActivatePopupMenuRef == nil then
        return false
    end
    if popupKind == "player" then
        return runPopupActionAtCursor(function()
            ActivatePopupMenuRef(owner, "player")
        end)
    end
    if popupKind == "team" then
        if memberIndex == nil then
            return false
        end
        return runPopupActionAtCursor(function()
            ActivatePopupMenuRef(owner, "team", memberIndex)
        end)
    end
    return runPopupActionAtCursor(function()
        ActivatePopupMenuRef(owner, popupKind, memberIndex)
    end)
end

local function showPopupMenuViaRaidManager(frame, memberIndex)
    if memberIndex == nil or Runtime == nil or UIC == nil or UIC.RAID_MANAGER == nil then
        return false
    end

    local manager = Runtime.GetStockContent(UIC.RAID_MANAGER)
    if manager == nil or type(manager.party) ~= "table" then
        return false
    end

    local party = tonumber(frame ~= nil and frame.__raid_party) or math.floor((memberIndex - 1) / GROUP_SIZE) + 1
    local slot = tonumber(frame ~= nil and frame.__raid_slot) or ((memberIndex - 1) % GROUP_SIZE) + 1
    local partyFrame = manager.party[party]
    local memberFrame = partyFrame ~= nil and type(partyFrame.member) == "table" and partyFrame.member[slot] or nil
    if memberFrame == nil or memberFrame.Click == nil then
        return false
    end

    pcall(function()
        if manager.Refresh ~= nil then
            manager:Refresh(memberIndex)
        end
    end)

    local ok = runPopupActionAtCursor(function()
        memberFrame:Click("RightButton")
    end)
    return ok and true or false
end

local function showPopupMenu(frame)
    if frame == nil then
        return false
    end
    local popupKind = getRaidPopupKind(frame)
    local memberIndex = getPopupMemberIndex(frame)
    if popupKind ~= "player" and memberIndex == nil then
        return false
    end

    local owners = {
        frame.popupOwner,
        frame
    }
    for _, owner in ipairs(owners) do
        if activateRaidPopup(owner, popupKind, memberIndex) then
            return true
        end
    end
    return showPopupMenuViaRaidManager(frame, memberIndex)
end

local function targetUnit(unit)
    local target = trim(unit)
    if target == "" then
        return
    end
    if api.Unit ~= nil and api.Unit.TargetUnit ~= nil then
        local ok = pcall(api.Unit.TargetUnit, api.Unit, target)
        if ok then
            return
        end
        ok = pcall(api.Unit.TargetUnit, target)
        if ok then
            return
        end
    end
    if type(TargetUnit) == "function" then
        pcall(TargetUnit, target)
    end
end

local function createEventWindow(frameId, parent)
    if api.Interface == nil or api.Interface.CreateWidget == nil then
        return nil
    end
    local eventWindow = nil
    pcall(function()
        eventWindow = api.Interface:CreateWidget("emptywidget", frameId .. ".eventWindow", parent)
    end)
    if eventWindow == nil then
        pcall(function()
            eventWindow = api.Interface:CreateWidget("button", frameId .. ".eventWindow", parent)
        end)
    end
    if eventWindow == nil then
        return nil
    end
    pcall(function()
        eventWindow:Show(true)
        if eventWindow.SetAlpha ~= nil then
            eventWindow:SetAlpha(0)
        end
        safeSetUiLayer(eventWindow, RAID_UI_LAYER)
        safeEnablePick(eventWindow, true)
        if eventWindow.EnableDrag ~= nil then
            eventWindow:EnableDrag(true)
        end
        if eventWindow.Raise ~= nil then
            eventWindow:Raise()
        end
    end)
    safeClickable(eventWindow, true)
    return eventWindow
end

local function createPopupOwner(frameId, parent)
    if CreateUnitFrameRef == nil then
        return nil
    end
    local owner = nil
    local ok = pcall(function()
        owner = CreateUnitFrameRef(frameId .. ".popup", parent)
    end)
    if not ok or owner == nil then
        return nil
    end
    pcall(function()
        owner:Show(true)
        if owner.SetAlpha ~= nil then
            owner:SetAlpha(0)
        end
        safeSetUiLayer(owner, RAID_UI_LAYER)
        disablePopupOwnerInput(owner)
    end)
    disablePopupOwnerInput(owner)
    return owner
end

local function safeRegisterFrameClicks(widget)
    if widget == nil or widget.RegisterForClicks == nil then
        return
    end
    pcall(function()
        widget:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end)
    pcall(function()
        widget:RegisterForClicks("LeftButton")
    end)
    pcall(function()
        widget:RegisterForClicks("RightButton", false)
    end)
    pcall(function()
        widget:RegisterForClicks("LeftButtonUp")
    end)
    pcall(function()
        widget:RegisterForClicks("RightButtonUp", false)
    end)
end

local function createFrame(index)
    if RaidFrames.frames[index] ~= nil then
        return RaidFrames.frames[index]
    end

    local frameId = "nuziRaidMember" .. tostring(index)
    local frame = api.Interface:CreateEmptyWindow(frameId)
    pcall(function()
        safeSetUiLayer(frame, RAID_UI_LAYER)
    end)

    frame.bg = createColorDrawable(frame, "background", 0.04, 0.04, 0.05, 0.8)
    frame.targetTint = createColorDrawable(frame, "overlay", 1, 0.9, 0.45, 0.28)
    frame.hpAfterBar = createRaidBar(frameId .. ".hpAfterBar", frame)
    frame.hpBar = createRaidBar(frameId .. ".hpBar", frame)
    frame.mpAfterBar = createRaidBar(frameId .. ".mpAfterBar", frame)
    frame.mpBar = createRaidBar(frameId .. ".mpBar", frame)
    frame.debuffBadge = createColorDrawable(frame, "artwork", 1, 0.27, 0.27, 0.92)
    frame.popupOwner = createPopupOwner(frameId, frame)
    frame.eventWindow = createEventWindow(frameId, frame)
    frame.clickOverlay = nil

    applyFrameTextures(frame, RaidFrames.settings)

    local nameLabel = api.Interface:CreateWidget("label", frameId .. ".name", frame)
    pcall(function()
        nameLabel:Show(true)
        if nameLabel.SetAutoResize ~= nil then
            nameLabel:SetAutoResize(false)
        end
        if nameLabel.SetLimitWidth ~= nil then
            nameLabel:SetLimitWidth(true)
        end
        if nameLabel.style ~= nil then
            nameLabel.style:SetColor(1, 1, 1, 1)
            if nameLabel.style.SetAlign ~= nil and ALIGN_REF ~= nil and ALIGN_REF.LEFT ~= nil then
                nameLabel.style:SetAlign(ALIGN_REF.LEFT)
            end
        end
    end)
    frame.nameLabel = nameLabel

    local valueLabel = api.Interface:CreateWidget("label", frameId .. ".value", frame)
    pcall(function()
        valueLabel:Show(true)
        if valueLabel.SetAutoResize ~= nil then
            valueLabel:SetAutoResize(false)
        end
        if valueLabel.style ~= nil then
            valueLabel.style:SetColor(1, 1, 1, 1)
            if valueLabel.style.SetAlign ~= nil and ALIGN_REF ~= nil and ALIGN_REF.RIGHT ~= nil then
                valueLabel.style:SetAlign(ALIGN_REF.RIGHT)
            end
        end
    end)
    frame.valueLabel = valueLabel

    local statusLabel = api.Interface:CreateWidget("label", frameId .. ".status", frame)
    pcall(function()
        statusLabel:Show(true)
        if statusLabel.SetAutoResize ~= nil then
            statusLabel:SetAutoResize(false)
        end
        if statusLabel.style ~= nil then
            statusLabel.style:SetColor(1, 1, 1, 1)
            if statusLabel.style.SetAlign ~= nil and ALIGN_REF ~= nil and ALIGN_REF.CENTER ~= nil then
                statusLabel.style:SetAlign(ALIGN_REF.CENTER)
            end
        end
    end)
    frame.statusLabel = statusLabel

    local metaLabel = api.Interface:CreateWidget("label", frameId .. ".meta", frame)
    pcall(function()
        metaLabel:Show(true)
        if metaLabel.SetAutoResize ~= nil then
            metaLabel:SetAutoResize(false)
        end
        if metaLabel.style ~= nil then
            metaLabel.style:SetColor(1, 1, 1, 0.95)
            if metaLabel.style.SetAlign ~= nil and ALIGN_REF ~= nil and ALIGN_REF.LEFT ~= nil then
                metaLabel.style:SetAlign(ALIGN_REF.LEFT)
            end
        end
    end)
    frame.metaLabel = metaLabel

    frame.leaderMark = createLeaderMark(frameId, frame)

    local badgeLabel = api.Interface:CreateWidget("label", frameId .. ".badge", frame)
    pcall(function()
        badgeLabel:Show(true)
        if badgeLabel.SetAutoResize ~= nil then
            badgeLabel:SetAutoResize(false)
        end
        if badgeLabel.style ~= nil then
            badgeLabel.style:SetColor(1, 0.9, 0.55, 1)
            if badgeLabel.style.SetAlign ~= nil and ALIGN_REF ~= nil and ALIGN_REF.RIGHT ~= nil then
                badgeLabel.style:SetAlign(ALIGN_REF.RIGHT)
            end
        end
    end)
    frame.badgeLabel = badgeLabel

    local function getClickButton(selfOrButton, button)
        if button ~= nil then
            return button
        end
        return selfOrButton
    end
    local function getClickSource(selfOrButton, button)
        if button ~= nil and type(selfOrButton) == "table" then
            return selfOrButton
        end
        return frame.eventWindow or frame
    end
    local function handleFrameClick(self, button)
        local clickButton = getClickButton(self, button)
        local source = getClickSource(self, button)
        frame.__nr_popup_owner = frame.popupOwner or frame
        if isRightClick(clickButton) then
            showPopupMenu(frame)
            return
        end
        targetUnit((source ~= nil and (source.target or source.unit)) or frame.__raid_unit)
    end
    local function handleFrameMouseUp(self, button)
        local clickButton = getClickButton(self, button)
        frame.__nr_popup_owner = frame.popupOwner or frame
        if isRightClick(clickButton) then
            showPopupMenu(frame)
        end
    end
    frame.OnClick = handleFrameClick

    pcall(function()
        safeClickable(frame, false)
    end)
    pcall(function()
        if frame.eventWindow ~= nil and frame.eventWindow.SetHandler ~= nil then
            frame.eventWindow:SetHandler("OnClick", frame.OnClick)
            frame.eventWindow:SetHandler("OnMouseUp", handleFrameMouseUp)
            safeClickable(frame.eventWindow, true)
            safeRegisterFrameClicks(frame.eventWindow)
        end
    end)

    RaidFrames.frames[index] = frame
    safeShow(frame.targetTint, false)
    safeShow(frame.debuffBadge, false)
    return frame
end

local function applyFrameLayout(frame, cfg)
    if frame == nil then
        return
    end

    local width = clamp(cfg.width, 60, 400, 80)
    local hpHeight = clamp(cfg.hp_height, 8, 80, 16)
    local mpHeight = clamp(cfg.mp_height, 0, 40, 0)
    local totalHeight = getFrameHeight(cfg)
    local showMp = mpHeight > 0
    local nameFontSize = clamp(cfg.name_font_size, 8, 32, 11)
    local valueFontSize = clamp(cfg.value_font_size, 8, 24, 10)
    local namePad = clamp(cfg.name_padding_left, -20, 120, 2)
    local nameOffsetX = clamp(cfg.name_offset_x, -120, 120, 0)
    local nameOffsetY = clamp(cfg.name_offset_y, -40, 40, 0)
    local valueOffsetX = clamp(cfg.value_offset_x, -120, 120, 0)
    local valueOffsetY = clamp(cfg.value_offset_y, -40, 40, 0)
    local iconSize = clamp(cfg.icon_size, 8, 24, 12)
    local iconGap = clamp(cfg.icon_gap, 0, 24, 2)
    local leaderSize = clamp(cfg.leader_badge_size, 6, 32, 11)
    local iconOffsetX = clamp(cfg.icon_offset_x, -120, 120, 0)
    local iconOffsetY = clamp(cfg.icon_offset_y, -40, 40, 0)
    local classOffsetX = clamp(cfg.class_offset_x, -120, 120, iconOffsetX)
    local classOffsetY = clamp(cfg.class_offset_y, -40, 40, iconOffsetY)
    local roleOffsetX = clamp(cfg.role_offset_x, -120, 120, iconOffsetX)
    local roleOffsetY = clamp(cfg.role_offset_y, -40, 40, iconOffsetY)
    local statusOffsetX = clamp(cfg.status_offset_x, -120, 120, 0)
    local statusOffsetY = clamp(cfg.status_offset_y, -40, 40, 0)
    local debuffSize = clamp(cfg.debuff_size, 4, 32, 8)
    local debuffOffsetX = clamp(cfg.debuff_offset_x, -120, 120, 0)
    local debuffOffsetY = clamp(cfg.debuff_offset_y, -40, 40, 0)
    local classReserve = cfg.show_class_icon ~= false and (iconSize + iconGap) or 0
    local leaderReserve = cfg.show_leader_badge ~= false and (leaderSize + iconGap) or 0

    local layoutKey = table.concat({
        tostring(width),
        tostring(hpHeight),
        tostring(mpHeight),
        tostring(nameFontSize),
        tostring(valueFontSize),
        tostring(namePad),
        tostring(nameOffsetX),
        tostring(nameOffsetY),
        tostring(valueOffsetX),
        tostring(valueOffsetY),
        tostring(iconSize),
        tostring(iconGap),
        tostring(leaderSize),
        tostring(iconOffsetX),
        tostring(iconOffsetY),
        tostring(classOffsetX),
        tostring(classOffsetY),
        tostring(roleOffsetX),
        tostring(roleOffsetY),
        tostring(statusOffsetX),
        tostring(statusOffsetY),
        tostring(debuffSize),
        tostring(debuffOffsetX),
        tostring(debuffOffsetY),
        tostring(cfg.show_class_icon ~= false),
        tostring(cfg.show_leader_badge ~= false)
    }, "|")
    if frame.__nr_layout_key == layoutKey then
        return
    end
    frame.__nr_layout_key = layoutKey

    safeSetExtent(frame, width, totalHeight)

    if frame.bg ~= nil then
        safeAnchor(frame.bg, "TOPLEFT", frame, "TOPLEFT", -2, -2)
        pcall(function()
            frame.bg:AddAnchor("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, 2)
        end)
    end
    if frame.targetTint ~= nil then
        safeAnchor(frame.targetTint, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        pcall(function()
            frame.targetTint:AddAnchor("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end)
    end

    if frame.hpAfterBar ~= nil then
        safeAnchor(frame.hpAfterBar, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        pcall(function()
            frame.hpAfterBar:AddAnchor("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        end)
        safeSetHeight(frame.hpAfterBar, hpHeight)
        safeSetHeight(getBarValueTarget(frame.hpAfterBar), hpHeight)
        safeRaise(frame.hpAfterBar)
    end

    if frame.hpBar ~= nil then
        safeAnchor(frame.hpBar, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        pcall(function()
            frame.hpBar:AddAnchor("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        end)
        safeSetHeight(frame.hpBar, hpHeight)
        safeSetHeight(getBarValueTarget(frame.hpBar), hpHeight)
        safeRaise(frame.hpBar)
    end

    if frame.mpAfterBar ~= nil then
        safeAnchor(frame.mpAfterBar, "TOPLEFT", frame, "TOPLEFT", 0, hpHeight + 1)
        pcall(function()
            frame.mpAfterBar:AddAnchor("TOPRIGHT", frame, "TOPRIGHT", 0, hpHeight + 1)
        end)
        safeSetHeight(frame.mpAfterBar, mpHeight)
        safeSetHeight(getBarValueTarget(frame.mpAfterBar), mpHeight)
        safeShow(frame.mpAfterBar, showMp)
        safeRaise(frame.mpAfterBar)
    end

    if frame.mpBar ~= nil then
        safeAnchor(frame.mpBar, "TOPLEFT", frame, "TOPLEFT", 0, hpHeight + 1)
        pcall(function()
            frame.mpBar:AddAnchor("TOPRIGHT", frame, "TOPRIGHT", 0, hpHeight + 1)
        end)
        safeSetHeight(frame.mpBar, mpHeight)
        safeSetHeight(getBarValueTarget(frame.mpBar), mpHeight)
        safeShow(frame.mpBar, showMp)
        safeRaise(frame.mpBar)
    end

    if frame.nameLabel ~= nil then
        safeSetFontSize(frame.nameLabel, nameFontSize)
        safeSetExtent(frame.nameLabel, math.max(24, width - 24), hpHeight)
        safeAnchor(frame.nameLabel, "LEFT", frame, "LEFT", namePad + nameOffsetX + classReserve + leaderReserve, nameOffsetY)
        safeRaise(frame.nameLabel)
    end

    if frame.metaLabel ~= nil then
        safeSetFontSize(frame.metaLabel, iconSize)
        safeSetExtent(frame.metaLabel, math.max(18, iconSize * 3), hpHeight)
        safeAnchor(frame.metaLabel, "LEFT", frame, "LEFT", namePad + classOffsetX, classOffsetY)
        safeRaise(frame.metaLabel)
    end

    if frame.leaderMark ~= nil then
        applyLeaderMarkSize(frame.leaderMark, leaderSize)
        safeAnchor(frame.leaderMark, "LEFT", frame, "LEFT", namePad + nameOffsetX + classReserve, nameOffsetY)
        safeRaise(frame.leaderMark)
    end

    if frame.valueLabel ~= nil then
        safeSetFontSize(frame.valueLabel, valueFontSize)
        safeSetExtent(frame.valueLabel, math.max(28, width - 8), hpHeight)
        safeAnchor(frame.valueLabel, "RIGHT", frame, "RIGHT", -4 + valueOffsetX, valueOffsetY)
        safeRaise(frame.valueLabel)
    end

    if frame.statusLabel ~= nil then
        safeSetFontSize(frame.statusLabel, valueFontSize)
        safeSetExtent(frame.statusLabel, math.max(28, width - 8), hpHeight)
        safeAnchor(frame.statusLabel, "CENTER", frame, "CENTER", statusOffsetX, statusOffsetY)
        safeRaise(frame.statusLabel)
    end

    if frame.badgeLabel ~= nil then
        safeSetFontSize(frame.badgeLabel, iconSize)
        safeSetExtent(frame.badgeLabel, math.max(28, width - 8), hpHeight)
        safeAnchor(frame.badgeLabel, "RIGHT", frame, "RIGHT", -4 + roleOffsetX, roleOffsetY)
        safeRaise(frame.badgeLabel)
    end

    if frame.debuffBadge ~= nil then
        safeAnchor(frame.debuffBadge, "TOPRIGHT", frame, "TOPRIGHT", -1 + debuffOffsetX, 1 + debuffOffsetY)
        safeSetExtent(frame.debuffBadge, debuffSize, debuffSize)
    end

    if frame.popupOwner ~= nil then
        safeAnchor(frame.popupOwner, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        pcall(function()
            frame.popupOwner:AddAnchor("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end)
        disablePopupOwnerInput(frame.popupOwner)
    end
    if frame.eventWindow ~= nil then
        safeAnchor(frame.eventWindow, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        pcall(function()
            frame.eventWindow:AddAnchor("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end)
        safeEnablePick(frame.eventWindow, true)
        safeClickable(frame.eventWindow, true)
        safeRegisterFrameClicks(frame.eventWindow)
        pcall(function()
            if frame.eventWindow.Raise ~= nil then
                frame.eventWindow:Raise()
            end
        end)
    end
end

local function tryHideStockRaidFrames(cfg, force)
    if cfg.hide_stock ~= true or Runtime == nil or UIC == nil or UIC.RAID_MANAGER == nil then
        RaidFrames.__nr_stock_hidden = false
        return
    end
    local now = tonumber(RaidFrames.now_ms) or 0
    if RaidFrames.__nr_stock_hidden == true
        and force ~= true
        and RaidFrames.__nr_stock_hide_ms ~= nil
        and (now - RaidFrames.__nr_stock_hide_ms) < 5000 then
        return
    end
    local stock = Runtime.GetStockContent(UIC.RAID_MANAGER)
    if stock == nil or stock.Show == nil then
        return
    end
    pcall(function()
        stock:Show(false)
    end)
    RaidFrames.__nr_stock_hidden = true
    RaidFrames.__nr_stock_hide_ms = now
end

local function cacheMemberUnitId(index, name, unitId)
    if unitId == nil or unitId == "" then
        return
    end
    local memberIndex = tonumber(index)
    if memberIndex ~= nil then
        RaidFrames.unit_ids_by_index[memberIndex] = unitId
    end
    local cleanName = trim(name)
    if cleanName ~= "" then
        RaidFrames.unit_ids_by_name[string.lower(cleanName)] = unitId
    end
end

local function clearMemberUnitIdCache(index, name)
    local memberIndex = tonumber(index)
    if memberIndex ~= nil then
        RaidFrames.unit_ids_by_index[memberIndex] = nil
    end
    local cleanName = trim(name)
    if cleanName ~= "" then
        RaidFrames.unit_ids_by_name[string.lower(cleanName)] = nil
    end
end

local function getCachedMemberUnitId(index, name)
    local cleanName = trim(name)
    if cleanName ~= "" then
        local unitId = RaidFrames.unit_ids_by_name[string.lower(cleanName)]
        if unitId ~= nil then
            return unitId
        end
    end
    local memberIndex = tonumber(index)
    if memberIndex ~= nil then
        return RaidFrames.unit_ids_by_index[memberIndex]
    end
    return nil
end

local function buildMember(unit, index)
    if not isUnitTeamMember(unit) then
        clearMemberUnitIdCache(index, nil)
        return nil
    end
    local info = safeUnitInfo(unit)
    local unitId = safeUnitId(unit)
    local name = safeUnitName(unit, info, unitId)
    if unitId == nil or unitId == "" then
        unitId = getCachedMemberUnitId(index, name)
        if name == "" and unitId ~= nil then
            name = safeUnitName(unit, info, unitId)
        end
    end
    if name == "" and unitId == nil then
        return nil
    end
    cacheMemberUnitId(index, name, unitId)
    return {
        unit = unit,
        index = index,
        unit_id = unitId,
        name = name,
        info = info,
        class_name = safeUnitClassName(unit, info),
        role_key = getTeamRoleKey(name)
    }
end

local function hideMissingMemberFrame(member)
    if type(member) ~= "table" then
        return
    end
    clearMemberUnitIdCache(member.index, member.name)
    local frame = RaidFrames.frames[member.index]
    if frame ~= nil then
        frame.__nr_last_hp = nil
        frame.__nr_last_max_hp = nil
        frame.__nr_last_mp = nil
        frame.__nr_last_max_mp = nil
        frame.__nr_bound_unit = nil
        frame.__nr_bound_unit_id = nil
        frame.__nr_bound_index = nil
        frame.__nr_static_rendered = false
        frame.__nr_modifier = nil
        frame.__nr_debuff_count = nil
        frame.__nr_has_dispellable_debuff = nil
        frame.__nr_team_authority = nil
        frame.__nr_team_authority_scanned = false
        frame.__nr_cached_distance = nil
        frame.__nr_last_distance_ms = nil
        frame.__nr_has_seen_distance = nil
        frame.__nr_offline = nil
        frame.__nr_last_offline_ms = nil
        frame.__nr_bloodlust_unit_id = nil
        frame.__nr_bloodlust_active = false
        frame.__nr_bloodlust_next_scan_ms = 0
        frame.__raid_unit_id = nil
        frame.__raid_name = nil
        frame.__nr_visible = nil
        frame.__nr_hp_after_visible = nil
        frame.__nr_mp_after_visible = nil
        frame.__nr_leader_visible = nil
        updateCachedVisible(frame, "__nr_visible", frame, false)
        updateCachedVisible(frame, "__nr_hp_after_visible", frame.hpAfterBar, false)
        updateCachedVisible(frame, "__nr_mp_after_visible", frame.mpAfterBar, false)
        updateCachedVisible(frame, "__nr_leader_visible", frame.leaderMark, false)
    end
end

local function refreshMemberSnapshot(member, refreshMetadata)
    if type(member) ~= "table" then
        return member
    end
    if not isUnitTeamMember(member.unit) then
        hideMissingMemberFrame(member)
        member.__nr_missing = true
        member.unit_id = nil
        member.name = ""
        member.info = nil
        return member
    end
    member.__nr_missing = false
    local info = safeUnitInfo(member.unit)
    local unitId = safeUnitId(member.unit)
    if unitId == nil or unitId == "" then
        unitId = getCachedMemberUnitId(member.index, member.name)
    end
    if unitId ~= nil and unitId ~= "" then
        member.unit_id = unitId
    end
    if type(info) == "table" then
        member.info = info
    elseif member.unit_id ~= nil then
        local byIdInfo = safeUnitInfoById(member.unit_id)
        if type(byIdInfo) == "table" then
            member.info = byIdInfo
        end
    end
    local resolvedInfo = member.info
    local resolvedUnitId = member.unit_id
    local name = safeUnitName(member.unit, resolvedInfo, resolvedUnitId)
    if name ~= "" then
        member.name = name
    end
    cacheMemberUnitId(member.index, member.name, member.unit_id)
    if refreshMetadata then
        member.class_name = safeUnitClassName(member.unit, resolvedInfo)
        member.role_key = getTeamRoleKey(member.name)
    end
    return member
end

local function rebuildRoster(cfg)
    local members = {}
    local maxSlots = getLayoutMax(cfg)
    for index = 1, maxSlots do
        local unit = string.format("team%d", index)
        local member = buildMember(unit, index)
        if member ~= nil then
            members[#members + 1] = member
        end
    end
    RaidFrames.active_members = members
    return members
end

local function hasMissingActiveMember(members)
    if type(members) ~= "table" then
        return false
    end
    for _, member in ipairs(members) do
        if type(member) == "table" and not isUnitTeamMember(member.unit) then
            hideMissingMemberFrame(member)
            return true
        end
    end
    return false
end

local function getFrameAlpha(frame, cfg, unit, state)
    local alpha = percent01(cfg.alpha_pct, 100)
    if state.offline then
        alpha = alpha * percent01(cfg.offline_alpha_pct, 20)
    elseif state.dead then
        alpha = alpha * percent01(cfg.dead_alpha_pct, 30)
    elseif cfg.range_fade_enabled ~= false then
        local now = tonumber(RaidFrames.now_ms) or 0
        local distance = frame.__nr_cached_distance
        if distance == nil or frame.__nr_last_distance_ms == nil or (now - frame.__nr_last_distance_ms) >= 250 then
            distance = safeUnitDistance(unit)
            frame.__nr_cached_distance = distance
            frame.__nr_last_distance_ms = now
        end
        local maxDistance = clamp(cfg.range_max_distance, 1, 300, 80)
        if type(distance) == "number" and distance > maxDistance then
            frame.__nr_has_seen_distance = true
            alpha = alpha * percent01(cfg.range_alpha_pct, 45)
        elseif distance == nil and frame.__nr_has_seen_distance == true then
            alpha = alpha * percent01(cfg.range_alpha_pct, 45)
        elseif type(distance) == "number" then
            frame.__nr_has_seen_distance = true
        end
    end
    return alpha
end

local function getCachedOffline(frame, unit)
    local now = tonumber(RaidFrames.now_ms) or 0
    if frame.__nr_offline == nil
        or frame.__nr_last_offline_ms == nil
        or (now - frame.__nr_last_offline_ms) >= 500 then
        frame.__nr_offline = safeUnitOffline(unit)
        frame.__nr_last_offline_ms = now
    end
    return frame.__nr_offline
end

local function getCachedBloodlustState(frame, member, state)
    if frame == nil or type(member) ~= "table" or state.offline or state.dead then
        return false
    end

    local unit = member.unit
    if not isUnitTeamMember(unit) then
        frame.__nr_bloodlust_active = false
        frame.__nr_bloodlust_next_scan_ms = 0
        return false
    end

    local unitId = member.unit_id or frame.__raid_unit_id or unit
    local unitKey = tostring(unitId or "")
    local now = tonumber(RaidFrames.now_ms) or 0
    local nextScan = tonumber(frame.__nr_bloodlust_next_scan_ms) or 0
    if frame.__nr_bloodlust_unit_id == unitKey and nextScan > now then
        return frame.__nr_bloodlust_active == true
    end

    local active = unitHasBuff(unit, BLOODLUST_BUFF_ID)
    local memberIndex = tonumber(member.index or frame.__raid_member_index) or 0
    local jitter = (memberIndex - (math.floor(memberIndex / 8) * 8)) * 20
    if jitter < 0 then
        jitter = 0
    end
    if jitter > BLOODLUST_SCAN_JITTER_MS then
        jitter = BLOODLUST_SCAN_JITTER_MS
    end

    frame.__nr_bloodlust_unit_id = unitKey
    frame.__nr_bloodlust_active = active and true or false
    frame.__nr_bloodlust_next_scan_ms = now + BLOODLUST_SCAN_INTERVAL_MS + jitter
    return frame.__nr_bloodlust_active
end

local function getHpColor(settings, cfg, member, state, bloodlustActive)
    if state.offline then
        return colorOrFallback(settings, "offline_bar_color", OFFLINE_BAR_COLOR)
    end
    if state.dead then
        return colorOrFallback(settings, "dead_bar_color", DEAD_BAR_COLOR)
    end
    if bloodlustActive == true then
        return colorOrFallback(settings, "bloodlust_team_color", { 255, 45, 0, 255 })
    end
    local roleColor = getTeamRoleColor(settings, member.role_key)
    if roleColor ~= nil then
        return roleColor
    end
    if settings ~= nil and type(settings.style) == "table" and settings.style.bar_colors_enabled and tostring(cfg.bar_style_mode or "shared") == "shared" then
        return settings.style.hp_fill_color or settings.style.hp_bar_color or DEFAULT_HP_COLOR
    end
    return DEFAULT_HP_COLOR
end

local function getHpAfterColor(settings, cfg, member, state, bloodlustActive)
    if state.offline or state.dead then
        return getHpColor(settings, cfg, member, state, bloodlustActive)
    end
    if bloodlustActive == true then
        return colorOrFallback(settings, "bloodlust_team_color", { 255, 45, 0, 255 })
    end
    if settings ~= nil and type(settings.style) == "table" and settings.style.bar_colors_enabled and tostring(cfg.bar_style_mode or "shared") == "shared" then
        return settings.style.hp_after_color or settings.style.hp_fill_color or settings.style.hp_bar_color or DEFAULT_HP_COLOR
    end
    local roleColor = getTeamRoleColor(settings, member.role_key)
    if roleColor ~= nil then
        return roleColor
    end
    return DEFAULT_HP_COLOR
end

local function getMpColor(settings, cfg)
    if settings ~= nil and type(settings.style) == "table" and settings.style.bar_colors_enabled and tostring(cfg.bar_style_mode or "shared") == "shared" then
        return settings.style.mp_fill_color or settings.style.mp_bar_color or DEFAULT_MP_COLOR
    end
    return DEFAULT_MP_COLOR
end

local function getMpAfterColor(settings, cfg)
    if settings ~= nil and type(settings.style) == "table" and settings.style.bar_colors_enabled and tostring(cfg.bar_style_mode or "shared") == "shared" then
        return settings.style.mp_after_color or settings.style.mp_fill_color or settings.style.mp_bar_color or DEFAULT_MP_COLOR
    end
    return DEFAULT_MP_COLOR
end

local function updateAfterImageBar(frame, prefix, bar, maxValue, currentValue)
    if frame == nil or bar == nil then
        return
    end

    local maxNum = math.max(0, tonumber(maxValue) or 0)
    local currentNum = clamp(currentValue, 0, maxNum, 0)
    local showBackfill = maxNum > 0 and currentNum < maxNum
    local backfillValue = showBackfill and maxNum or 0
    updateCachedBarValue(frame, "__nr_" .. prefix .. "_after_range", "__nr_" .. prefix .. "_after_bar_value", getBarValueTarget(bar), maxNum, backfillValue)
    updateCachedVisible(frame, "__nr_" .. prefix .. "_after_visible", bar, showBackfill)
end

local function getNameColor(settings, cfg, member, state)
    if state.offline then
        return colorOrFallback(settings, "offline_text_color", OFFLINE_TEXT_COLOR)
    end
    if state.dead then
        return colorOrFallback(settings, "dead_text_color", DEAD_TEXT_COLOR)
    end
    if cfg.text_colors_override_role_colors == true then
        return colorOrFallback(settings, "name_color", DEFAULT_TEXT_COLOR)
    end
    if cfg.use_class_name_colors == true then
        local classColor = getClassColor(member.class_name)
        if classColor ~= nil then
            return classColor
        end
    end
    local roleColor = getTeamRoleColor(settings, member.role_key)
    if cfg.use_role_name_colors ~= false and roleColor ~= nil then
        return roleColor
    end
    return colorOrFallback(settings, "name_color", DEFAULT_TEXT_COLOR)
end

local function updateFramePosition(frame, cfg, member, visibleIndex)
    local layout = tostring(cfg.layout_mode or "party_columns")
    local width = clamp(cfg.width, 60, 400, 80)
    local frameHeight = getFrameHeight(cfg)
    local gapX = clamp(cfg.gap_x, 0, 80, 2)
    local gapY = clamp(cfg.gap_y, 0, 80, 2)
    local showHeaders = cfg.show_group_headers ~= false
    local x = 0
    local y = 0

    if layout == "party_columns" or layout == "party_only" then
        local groupIndex = math.floor(((member.index or 1) - 1) / GROUP_SIZE)
        local slot = ((member.index or 1) - 1) % GROUP_SIZE
        x = groupIndex * (width + gapX)
        y = slot * (frameHeight + gapY)
        if showHeaders then
            y = y + HEADER_HEIGHT + HEADER_GAP
        end
    elseif layout == "single_list" then
        local groupIndex = math.floor(((member.index or 1) - 1) / GROUP_SIZE)
        x = 0
        y = (visibleIndex - 1) * (frameHeight + gapY)
        if showHeaders then
            y = y + ((groupIndex + 1) * (HEADER_HEIGHT + HEADER_GAP))
        end
    else
        local columns = clamp(cfg.grid_columns, 1, 10, 8)
        local col = (visibleIndex - 1) % columns
        local row = math.floor((visibleIndex - 1) / columns)
        x = col * (width + gapX)
        y = row * (frameHeight + gapY)
    end

    if frame.__nr_x == x and frame.__nr_y == y then
        return
    end
    frame.__nr_x = x
    frame.__nr_y = y
    safeAnchor(frame, "TOPLEFT", ensureContainer(), "TOPLEFT", x, y)
end

local function updateGroupHeaders(cfg, members)
    local showHeaders = cfg.show_group_headers ~= false
    local layout = tostring(cfg.layout_mode or "party_columns")
    local width = clamp(cfg.width, 60, 400, 80)
    local gapX = clamp(cfg.gap_x, 0, 80, 2)
    local gapY = clamp(cfg.gap_y, 0, 80, 2)
    local frameHeight = getFrameHeight(cfg)
    local shown = {}
    local positions = {}

    if showHeaders then
        if layout == "party_columns" or layout == "party_only" then
            for _, member in ipairs(members) do
                local groupIndex = math.floor(((member.index or 1) - 1) / GROUP_SIZE) + 1
                if not shown[groupIndex] then
                    shown[groupIndex] = true
                    positions[groupIndex] = { x = (groupIndex - 1) * (width + gapX), y = 0 }
                end
            end
        elseif layout == "single_list" then
            local runningRow = 0
            local seenGroups = {}
            for _, member in ipairs(members) do
                local groupIndex = math.floor(((member.index or 1) - 1) / GROUP_SIZE) + 1
                if not seenGroups[groupIndex] then
                    seenGroups[groupIndex] = true
                    shown[groupIndex] = true
                    positions[groupIndex] = { x = 0, y = runningRow * (frameHeight + gapY) + (groupIndex - 1) * (HEADER_HEIGHT + HEADER_GAP) }
                end
                runningRow = runningRow + 1
            end
        end
    end

    for groupIndex = 1, math.ceil(MAX_RAID_MEMBERS / GROUP_SIZE) do
        local header = RaidFrames.group_headers[groupIndex]
        if shown[groupIndex] then
            header = ensureGroupHeader(groupIndex)
            updateCachedText(header, "__nr_text", header, "Party" .. tostring(groupIndex))
            safeSetFontSize(header, clamp(cfg.group_header_font_size, 8, 24, 11))
            local pos = positions[groupIndex] or { x = 0, y = 0 }
            safeAnchor(header, "TOPLEFT", ensureContainer(), "TOPLEFT", pos.x, pos.y)
            updateCachedVisible(header, "__nr_visible", header, true)
        elseif header ~= nil then
            updateCachedVisible(header, "__nr_visible", header, false)
        end
    end
end

local function assignMemberFields(widget, member, resolvedUnitId, party, slot)
    safeAssignWidgetField(widget, "target", member.unit)
    safeAssignWidgetField(widget, "unit", member.unit)
    safeAssignWidgetField(widget, "unitId", resolvedUnitId)
    safeAssignWidgetField(widget, "index", member.index)
    safeAssignWidgetField(widget, "memberIndex", member.index)
    safeAssignWidgetField(widget, "party", party)
    safeAssignWidgetField(widget, "slot", slot)
end

local function applyMemberWidgetBindings(frame, member, resolvedUnitId)
    local party = math.floor(((tonumber(member.index) or 1) - 1) / GROUP_SIZE) + 1
    local slot = ((tonumber(member.index) or 1) - 1) % GROUP_SIZE + 1

    frame.__raid_unit = member.unit
    frame.__raid_unit_id = resolvedUnitId
    frame.__raid_name = member.name
    frame.__raid_member_index = member.index
    frame.__raid_party = party
    frame.__raid_slot = slot
    frame.__nr_popup_owner = frame.popupOwner or frame

    if frame.__nr_bound_unit == member.unit
        and frame.__nr_bound_unit_id == resolvedUnitId
        and frame.__nr_bound_index == member.index
        and frame.__nr_bound_party == party
        and frame.__nr_bound_slot == slot
        and frame.__nr_bound_popup_owner == frame.popupOwner then
        return false
    end

    frame.__nr_bound_unit = member.unit
    frame.__nr_bound_unit_id = resolvedUnitId
    frame.__nr_bound_index = member.index
    frame.__nr_bound_party = party
    frame.__nr_bound_slot = slot
    frame.__nr_bound_popup_owner = frame.popupOwner
    frame.__nr_last_hp = nil
    frame.__nr_last_max_hp = nil
    frame.__nr_last_mp = nil
    frame.__nr_last_max_mp = nil
    frame.__nr_modifier = nil
    frame.__nr_debuff_count = nil
    frame.__nr_has_dispellable_debuff = nil
    frame.__nr_team_authority = nil
    frame.__nr_team_authority_scanned = false
    frame.__nr_cached_distance = nil
    frame.__nr_last_distance_ms = nil
    frame.__nr_has_seen_distance = nil
    frame.__nr_offline = nil
    frame.__nr_last_offline_ms = nil
    frame.__nr_bloodlust_unit_id = nil
    frame.__nr_bloodlust_active = false
    frame.__nr_bloodlust_next_scan_ms = 0
    frame.__nr_static_rendered = false

    assignMemberFields(frame, member, resolvedUnitId, party, slot)
    assignMemberFields(frame.eventWindow, member, resolvedUnitId, party, slot)
    safeSetWidgetTarget(frame.popupOwner, member.unit, resolvedUnitId, member.name)
    assignMemberFields(frame.popupOwner, member, resolvedUnitId, party, slot)
    assignMemberFields(frame.popupOwner ~= nil and frame.popupOwner.eventWindow or nil, member, resolvedUnitId, party, slot)
    disablePopupOwnerInput(frame.popupOwner)
    return true
end

local function getStockRaidFrame()
    if Runtime ~= nil and UIC ~= nil and UIC.RAID_FRAME ~= nil then
        local stock = Runtime.GetStockContent(UIC.RAID_FRAME)
        if type(stock) == "table" then
            return stock
        end
    end
    if globals ~= nil and type(globals.RaidFrame) == "table" then
        return globals.RaidFrame
    end

    local ok, stock = pcall(function()
        return RaidFrame
    end)
    if ok and type(stock) == "table" then
        return stock
    end
    return nil
end

local function getStockRaidMember(frame, member)
    local memberIndex = tonumber(member ~= nil and member.index) or tonumber(frame ~= nil and frame.__raid_member_index)
    if memberIndex == nil then
        return nil
    end

    local stock = getStockRaidFrame()
    if stock == nil or type(stock.party) ~= "table" then
        return nil
    end

    local party = tonumber(frame ~= nil and frame.__raid_party) or math.floor((memberIndex - 1) / GROUP_SIZE) + 1
    local slot = tonumber(frame ~= nil and frame.__raid_slot) or ((memberIndex - 1) % GROUP_SIZE) + 1
    local partyFrame = stock.party[party]
    if partyFrame == nil or type(partyFrame.members) ~= "table" then
        return nil
    end
    return partyFrame.members[slot]
end

local function readStockStatusBar(resourceBar)
    if resourceBar == nil then
        return nil, nil
    end
    local statusBar = resourceBar.statusBar or resourceBar
    if statusBar == nil then
        return nil, nil
    end

    local current = nil
    if statusBar.GetValue ~= nil then
        local ok, value = pcall(function()
            return statusBar:GetValue()
        end)
        if ok then
            current = tonumber(value)
        end
    end

    local maximum = nil
    if statusBar.GetMinMaxValues ~= nil then
        local ok, _, maxValue = pcall(function()
            return statusBar:GetMinMaxValues()
        end)
        if ok then
            maximum = tonumber(maxValue)
        end
    end

    return current, maximum
end

local function readStockRaidVitals(frame, member, includeMana)
    local stockMember = getStockRaidMember(frame, member)
    if stockMember == nil then
        return nil, nil, nil, nil
    end

    local hp, maxHp = readStockStatusBar(stockMember.hpBar)
    local mp = nil
    local maxMp = nil
    if includeMana ~= false then
        mp, maxMp = readStockStatusBar(stockMember.mpBar)
    end
    return hp, maxHp, mp, maxMp
end

local function preferStockResource(current, maximum, stockCurrent, stockMaximum)
    if hasUsableVitals(current, maximum) then
        return current, maximum
    end
    if hasUsableVitals(stockCurrent, stockMaximum) then
        return stockCurrent, stockMaximum
    end
    return firstNumber(current, stockCurrent), firstNumber(maximum, stockMaximum)
end

local function renderMember(frame, settings, cfg, member, refreshMetadata, refreshStatic)
    refreshStatic = refreshStatic == true or refreshMetadata == true or frame.__nr_static_rendered ~= true
    if refreshMetadata == true or member.unit_id == nil or trim(member.name) == "" then
        member = refreshMemberSnapshot(member, refreshMetadata)
    end
    if member.__nr_missing == true then
        hideMissingMemberFrame(member)
        return
    end
    local resolvedUnitId = member.unit_id or frame.__raid_unit_id
    local showMpBar = clamp(cfg.mp_height, 0, 40, 0) > 0
    if applyMemberWidgetBindings(frame, member, resolvedUnitId) then
        refreshStatic = true
    end
    if member.unit_id == nil and resolvedUnitId ~= nil then
        member.unit_id = resolvedUnitId
        cacheMemberUnitId(member.index, member.name, resolvedUnitId)
    end
    local hp, maxHp, mp, maxMp = safeUnitHealth(member.unit, resolvedUnitId, showMpBar)
    if not hasUsableVitals(hp, maxHp) or (showMpBar and not hasUsableVitals(mp, maxMp)) then
        local stockHp, stockMaxHp, stockMp, stockMaxMp = readStockRaidVitals(frame, member, showMpBar)
        hp, maxHp = preferStockResource(hp, maxHp, stockHp, stockMaxHp)
        if showMpBar then
            mp, maxMp = preferStockResource(mp, maxMp, stockMp, stockMaxMp)
        end
    end
    hp, maxHp = mergeResourceValues(hp, maxHp, frame.__nr_last_hp, frame.__nr_last_max_hp)
    mp, maxMp = mergeResourceValues(mp, maxMp, frame.__nr_last_mp, frame.__nr_last_max_mp)
    if hasUsableVitals(hp, maxHp) then
        frame.__nr_last_hp = hp
        frame.__nr_last_max_hp = maxHp
    end
    if hasUsableVitals(mp, maxMp) then
        frame.__nr_last_mp = mp
        frame.__nr_last_max_mp = maxMp
    end
    local offline = getCachedOffline(frame, member.unit)
    local modifier = frame.__nr_modifier
    if refreshMetadata or modifier == nil then
        modifier = safeUnitModifierInfo(member.unit)
        frame.__nr_modifier = modifier
    end
    local state = getUnitState(member.info, modifier, hp, maxHp, offline)
    local statusText = ""
    if state.offline then
        statusText = "Offline"
    elseif state.dead then
        statusText = "Dead"
    end

    applyFrameTextures(frame, settings, cfg, member, state)
    if refreshStatic then
        frame.__nr_static_rendered = true
    end

    local targetMatch = member.unit_id ~= nil
        and RaidFrames.current_target_id ~= nil
        and tostring(member.unit_id) == tostring(RaidFrames.current_target_id)

    local bloodlustActive = getCachedBloodlustState(frame, member, state)
    local nameColor = getNameColor(settings, cfg, member, state)
    local valueColor = colorOrFallback(settings, "value_color", nameColor)
    local baseStatusColor = state.dead
        and colorOrFallback(settings, "dead_text_color", DEAD_TEXT_COLOR)
        or colorOrFallback(settings, "offline_text_color", OFFLINE_TEXT_COLOR)
    local statusColor = colorOrFallback(settings, "status_color", baseStatusColor)
    local hpColor = getHpColor(settings, cfg, member, state, bloodlustActive)
    local hpAfterColor = getHpAfterColor(settings, cfg, member, state, bloodlustActive)
    local mpColor = showMpBar and getMpColor(settings, cfg) or nil
    local mpAfterColor = showMpBar and getMpAfterColor(settings, cfg) or nil

    local showValue = cfg.show_value_text and statusText == ""
    local showStatus = cfg.show_status_text ~= false and statusText ~= ""
    if refreshMetadata or frame.__nr_debuff_count == nil then
        frame.__nr_debuff_count = safeDebuffCount(member.unit)
        frame.__nr_has_dispellable_debuff = hasDispellableDebuff(member.unit, frame.__nr_debuff_count)
    end
    local showDebuff = cfg.show_debuff_alert ~= false and (tonumber(frame.__nr_debuff_count) or 0) > 0
    if cfg.show_leader_badge ~= false and (refreshMetadata or frame.__nr_team_authority_scanned ~= true) then
        frame.__nr_team_authority = safeUnitTeamAuthority(member.unit)
        frame.__nr_team_authority_scanned = true
    elseif cfg.show_leader_badge == false then
        frame.__nr_team_authority = nil
        frame.__nr_team_authority_scanned = false
    end

    if refreshStatic then
        local displayName = formatName(member.name, cfg.name_max_chars)
        if cfg.show_role_prefix ~= false then
            displayName = getRolePrefix(member.role_key) .. displayName
        end
        local metaText = ""
        if cfg.show_class_icon ~= false then
            metaText = getClassBadge(member.class_name)
        end
        local badgeText = ""
        if cfg.show_role_badge == true then
            badgeText = getRoleBadge(member.role_key, cfg.hide_dps_role_badge ~= false)
        end

        updateCachedText(frame, "__nr_name", frame.nameLabel, displayName)
        updateCachedVisible(frame, "__nr_name_visible", frame.nameLabel, cfg.show_name ~= false and trim(displayName) ~= "")
        updateCachedText(frame, "__nr_meta", frame.metaLabel, metaText)
        updateCachedVisible(frame, "__nr_meta_visible", frame.metaLabel, trim(metaText) ~= "")
        updateCachedText(frame, "__nr_badge", frame.badgeLabel, badgeText)
        updateCachedVisible(frame, "__nr_badge_visible", frame.badgeLabel, trim(badgeText) ~= "")
        updateCachedLabelColor(frame, "__nr_badge_color", frame.badgeLabel, { 255, 230, 120, 255 })
    end

    updateLeaderMark(frame, cfg, frame.__nr_team_authority)

    updateCachedLabelColor(frame, "__nr_name_color", frame.nameLabel, nameColor)
    updateCachedLabelColor(frame, "__nr_meta_color", frame.metaLabel, nameColor)

    if showValue then
        updateCachedText(frame, "__nr_value", frame.valueLabel, getValueText(cfg.value_text_mode, hp, maxHp, "hp"))
    end
    updateCachedVisible(frame, "__nr_value_visible", frame.valueLabel, showValue)
    updateCachedLabelColor(frame, "__nr_value_color", frame.valueLabel, valueColor)

    updateCachedText(frame, "__nr_status", frame.statusLabel, statusText)
    updateCachedVisible(frame, "__nr_status_visible", frame.statusLabel, showStatus)
    updateCachedLabelColor(frame, "__nr_status_color", frame.statusLabel, statusColor)

    updateCachedBarColor(frame, "__nr_hp_after_color", frame.hpAfterBar, hpAfterColor, hpAfterColor)
    updateAfterImageBar(frame, "hp", frame.hpAfterBar, maxHp, hp)
    updateCachedBarColor(frame, "__nr_hp_color", frame.hpBar, hpColor, hpColor)
    updateCachedBarValue(frame, "__nr_hp_range", "__nr_hp_value", getBarValueTarget(frame.hpBar), maxHp, hp)
    if showMpBar then
        updateCachedBarColor(frame, "__nr_mp_after_color", frame.mpAfterBar, mpAfterColor, mpAfterColor)
        updateAfterImageBar(frame, "mp", frame.mpAfterBar, maxMp, mp)
        updateCachedBarColor(frame, "__nr_mp_color", frame.mpBar, mpColor, mpColor)
        updateCachedBarValue(frame, "__nr_mp_range", "__nr_mp_value", getBarValueTarget(frame.mpBar), maxMp, mp)
    else
        updateCachedVisible(frame, "__nr_mp_after_visible", frame.mpAfterBar, false)
    end

    updateCachedVisible(frame, "__nr_target_visible", frame.targetTint, cfg.show_target_highlight ~= false and targetMatch)
    local targetColor = colorOrFallback(settings, "target_highlight_color", TARGET_TINT_COLOR)
    updateCachedDrawableColor(
        frame,
        "__nr_target_color",
        frame.targetTint,
        colorChannel01(targetColor, 1, TARGET_TINT_COLOR[1]),
        colorChannel01(targetColor, 2, TARGET_TINT_COLOR[2]),
        colorChannel01(targetColor, 3, TARGET_TINT_COLOR[3]),
        colorChannel01(targetColor, 4, TARGET_TINT_COLOR[4])
    )

    updateCachedVisible(frame, "__nr_debuff_visible", frame.debuffBadge, showDebuff)
    if frame.debuffBadge ~= nil then
        local debuffColor = (cfg.prefer_dispel_alert ~= false and frame.__nr_has_dispellable_debuff == true)
            and colorOrFallback(settings, "dispellable_debuff_color", DISPELLABLE_DEBUFF_BADGE_COLOR)
            or colorOrFallback(settings, "debuff_alert_color", DEBUFF_BADGE_COLOR)
        updateCachedDrawableColor(
            frame,
            "__nr_debuff_color",
            frame.debuffBadge,
            colorChannel01(debuffColor, 1, DEBUFF_BADGE_COLOR[1]),
            colorChannel01(debuffColor, 2, DEBUFF_BADGE_COLOR[2]),
            colorChannel01(debuffColor, 3, DEBUFF_BADGE_COLOR[3]),
            colorChannel01(debuffColor, 4, DEBUFF_BADGE_COLOR[4])
        )
    end

    if frame.bg ~= nil then
        local bgColor = colorOrFallback(settings, "background_color", DEFAULT_BG_COLOR)
        local bgAlpha = cfg.bg_enabled and percent01(cfg.bg_alpha_pct, 80) or 0
        updateCachedDrawableColor(
            frame,
            "__nr_bg_color",
            frame.bg,
            colorChannel01(bgColor, 1, DEFAULT_BG_COLOR[1]),
            colorChannel01(bgColor, 2, DEFAULT_BG_COLOR[2]),
            colorChannel01(bgColor, 3, DEFAULT_BG_COLOR[3]),
            bgAlpha * colorChannel01(bgColor, 4, DEFAULT_BG_COLOR[4])
        )
        updateCachedVisible(frame, "__nr_bg_visible", frame.bg, cfg.bg_enabled and true or false)
    end

    updateCachedAlpha(frame, "__nr_alpha", frame, getFrameAlpha(frame, cfg, member.unit, state))
    updateCachedVisible(frame, "__nr_visible", frame, true)
end

function RaidFrames.Init(settings)
    RaidFrames.settings = settings
    if Compat ~= nil then
        Compat.Probe(false)
    end
    ensurePopupCursorAnchorHook()
    ensureContainer()
    if type(settings) == "table" and type(settings.raidframes) == "table" then
        applyContainerPosition(settings.raidframes)
    end
end

function RaidFrames.SetEnabled(enabled)
    RaidFrames.enabled = enabled and true or false
    if not RaidFrames.enabled then
        updateCachedVisible(RaidFrames, "__nr_container_visible", RaidFrames.container, false)
        for _, frame in pairs(RaidFrames.frames) do
            updateCachedVisible(frame, "__nr_visible", frame, false)
        end
        for _, header in pairs(RaidFrames.group_headers) do
            updateCachedVisible(header, "__nr_visible", header, false)
        end
    end
end

function RaidFrames.OnUpdate(settings, updateFlags)
    if type(settings) ~= "table" or type(settings.raidframes) ~= "table" then
        updateCachedVisible(RaidFrames, "__nr_container_visible", RaidFrames.container, false)
        return
    end

    local cfg = settings.raidframes
    local flags = type(updateFlags) == "table" and updateFlags or {}
    local updateRoster = flags.update_roster == true or flags.force_roster == true
    local updateMetadata = flags.update_metadata == true or updateRoster
    local updateTarget = flags.update_target == true or RaidFrames.current_target_id == nil

    if not (RaidFrames.enabled and cfg.enabled) then
        updateCachedVisible(RaidFrames, "__nr_container_visible", RaidFrames.container, false)
        for _, frame in pairs(RaidFrames.frames) do
            updateCachedVisible(frame, "__nr_visible", frame, false)
        end
        for _, header in pairs(RaidFrames.group_headers) do
            updateCachedVisible(header, "__nr_visible", header, false)
        end
        return
    end

    ensureContainer()
    RaidFrames.now_ms = RaidFrames.now_ms + (tonumber(flags.elapsed_ms) or 100)

    if updateTarget then
        RaidFrames.current_target_id = safeUnitId("target")
    end

    local members = RaidFrames.active_members
    local rosterRebuilt = false
    if updateRoster or type(members) ~= "table" or #members == 0 then
        members = rebuildRoster(cfg)
        rosterRebuilt = true
    elseif updateMetadata and hasMissingActiveMember(members) then
        members = rebuildRoster(cfg)
        rosterRebuilt = true
    end
    local refreshLayout = rosterRebuilt or flags.force_layout == true or RaidFrames.__nr_layout_applied ~= true
    local refreshStatic = updateMetadata or refreshLayout

    if refreshLayout then
        applyContainerPosition(cfg)
        tryHideStockRaidFrames(cfg, flags.force_roster == true)
    else
        tryHideStockRaidFrames(cfg, false)
    end

    if #members == 0 then
        updateCachedVisible(RaidFrames, "__nr_container_visible", RaidFrames.container, false)
        for _, frame in pairs(RaidFrames.frames) do
            updateCachedVisible(frame, "__nr_visible", frame, false)
        end
        for _, header in pairs(RaidFrames.group_headers) do
            updateCachedVisible(header, "__nr_visible", header, false)
        end
        return
    end

    if refreshLayout then
        updateContainerExtent(cfg, members)
        updateCachedAlpha(RaidFrames, "__nr_container_alpha", RaidFrames.container, percent01(cfg.alpha_pct, 100))
        updateCachedVisible(RaidFrames, "__nr_container_visible", RaidFrames.container, true)
        updateCachedVisible(RaidFrames, "__nr_drag_handle_visible", RaidFrames.drag_handle, true)
    end

    local visibleIndex = 0
    local activeByIndex = refreshLayout and {} or nil
    for _, member in ipairs(members) do
        visibleIndex = visibleIndex + 1
        if activeByIndex ~= nil then
            activeByIndex[member.index] = true
        end
        local existed = RaidFrames.frames[member.index] ~= nil
        local frame = createFrame(member.index)
        local frameNeedsLayout = refreshLayout or not existed or frame.__nr_layout_key == nil
        if frameNeedsLayout then
            applyFrameLayout(frame, cfg)
            updateFramePosition(frame, cfg, member, visibleIndex)
        end
        renderMember(frame, settings, cfg, member, updateMetadata, refreshStatic or frameNeedsLayout)
    end

    if refreshLayout then
        for index = 1, MAX_RAID_MEMBERS do
            local frame = RaidFrames.frames[index]
            if frame ~= nil and not activeByIndex[index] then
                updateCachedVisible(frame, "__nr_visible", frame, false)
            end
        end

        updateGroupHeaders(cfg, members)
        RaidFrames.__nr_layout_applied = true
    end
end

function RaidFrames.Unload()
    if RaidFrames.container ~= nil then
        safeShow(RaidFrames.container, false)
        pcall(function()
            if api.Interface ~= nil and api.Interface.Free ~= nil then
                api.Interface:Free(RaidFrames.container)
            end
        end)
    end

    for _, frame in pairs(RaidFrames.frames) do
        safeShow(frame, false)
        pcall(function()
            if api.Interface ~= nil and api.Interface.Free ~= nil then
                api.Interface:Free(frame)
            end
        end)
    end

    for _, header in pairs(RaidFrames.group_headers) do
        safeShow(header, false)
        pcall(function()
            if api.Interface ~= nil and api.Interface.Free ~= nil then
                api.Interface:Free(header)
            end
        end)
    end

    RaidFrames.container = nil
    RaidFrames.drag_handle = nil
    RaidFrames.frames = {}
    RaidFrames.group_headers = {}
    RaidFrames.settings = nil
    RaidFrames.active_members = {}
    RaidFrames.unit_ids_by_index = {}
    RaidFrames.unit_ids_by_name = {}
    RaidFrames.current_target_id = nil
    RaidFrames.now_ms = 0
    RaidFrames.__nr_layout_applied = false
    RaidFrames.__nr_stock_hidden = false
    RaidFrames.__nr_stock_hide_ms = nil
end

return RaidFrames
