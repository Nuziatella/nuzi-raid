local api = require("api")

local function loadModule(name)
    local ok, mod = pcall(require, "nuzi-raid/" .. name)
    if ok then
        return mod
    end
    ok, mod = pcall(require, "nuzi-raid." .. name)
    if ok then
        return mod
    end
    return nil
end

local Shared = loadModule("shared")
local Runtime = loadModule("runtime")
local Compat = loadModule("compat")
local Overlay = loadModule("overlay_utils")

local RaidFrames = {
    container = nil,
    drag_handle = nil,
    frames = {},
    group_headers = {},
    settings = nil,
    enabled = true,
    active_members = {},
    current_target_id = nil,
    now_ms = 0
}

local MAX_RAID_MEMBERS = 50
local GROUP_SIZE = 5
local HEADER_HEIGHT = 18
local HEADER_GAP = 4
local DRAG_HANDLE_HEIGHT = 14

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
local OFFLINE_TEXT_COLOR = { 180, 180, 180, 255 }
local DEAD_TEXT_COLOR = { 220, 150, 150, 255 }
local TARGET_TINT_COLOR = { 255, 230, 120, 72 }
local DEBUFF_BADGE_COLOR = { 255, 68, 68, 235 }

local function clamp(value, lo, hi, default)
    local num = tonumber(value)
    if num == nil then
        return default
    end
    if lo ~= nil and num < lo then
        return lo
    end
    if hi ~= nil and num > hi then
        return hi
    end
    return num
end

local function percent01(value, default)
    local pct = clamp(value, 0, 100, default or 100)
    return pct / 100
end

local function trim(value)
    return (tostring(value or ""):gsub("^%s*(.-)%s*$", "%1"))
end

local function safeShow(widget, show)
    Overlay.SafeShow(widget, show)
end

local function safeSetAlpha(widget, alpha)
    Overlay.SafeSetAlpha(widget, alpha)
end

local function safeSetText(widget, text)
    if widget == nil or widget.SetText == nil then
        return
    end
    pcall(function()
        widget:SetText(tostring(text or ""))
    end)
end

local function safeSetExtent(widget, width, height)
    if widget == nil or widget.SetExtent == nil then
        return
    end
    pcall(function()
        widget:SetExtent(width, height)
    end)
end

local function safeSetHeight(widget, height)
    if widget == nil or widget.SetHeight == nil then
        return
    end
    pcall(function()
        widget:SetHeight(height)
    end)
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

local function safeSetColor(drawable, r, g, b, a)
    if drawable == nil or drawable.SetColor == nil then
        return
    end
    pcall(function()
        drawable:SetColor(r, g, b, a)
    end)
end

local function safeSetTextColor(label, rgba)
    if label == nil or label.style == nil or label.style.SetColor == nil then
        return
    end
    local color = rgba or { 255, 255, 255, 255 }
    pcall(function()
        label.style:SetColor(
            clamp(color[1], 0, 255, 255) / 255,
            clamp(color[2], 0, 255, 255) / 255,
            clamp(color[3], 0, 255, 255) / 255,
            clamp(color[4], 0, 255, 255) / 255
        )
    end)
end

local function safeSetFontSize(label, size)
    if label == nil or label.style == nil or label.style.SetFontSize == nil then
        return
    end
    pcall(function()
        label.style:SetFontSize(size)
    end)
end

local function safeApplyBarColor(statusBar, rgba)
    if statusBar == nil or type(rgba) ~= "table" then
        return
    end
    local r = clamp(rgba[1], 0, 255, 255) / 255
    local g = clamp(rgba[2], 0, 255, 255) / 255
    local b = clamp(rgba[3], 0, 255, 255) / 255
    local a = clamp(rgba[4], 0, 255, 255) / 255
    pcall(function()
        if statusBar.SetBarColor ~= nil then
            statusBar:SetBarColor(r, g, b, a)
        elseif statusBar.SetColor ~= nil then
            statusBar:SetColor(r, g, b, a)
        end
    end)
end

local function updateCachedText(owner, key, widget, value)
    local text = tostring(value or "")
    if owner[key] == text then
        return
    end
    owner[key] = text
    safeSetText(widget, text)
end

local function updateCachedVisible(owner, key, widget, visible)
    local want = visible and true or false
    if owner[key] == want then
        return
    end
    owner[key] = want
    safeShow(widget, want)
end

local function updateCachedAlpha(owner, key, widget, alpha)
    local value = tonumber(alpha) or 1
    if owner[key] == value then
        return
    end
    owner[key] = value
    safeSetAlpha(widget, value)
end

local function updateCachedLabelColor(owner, key, widget, rgba)
    local color = rgba or { 255, 255, 255, 255 }
    local colorKey = table.concat({
        tostring(color[1] or ""),
        tostring(color[2] or ""),
        tostring(color[3] or ""),
        tostring(color[4] or "")
    }, ",")
    if owner[key] == colorKey then
        return
    end
    owner[key] = colorKey
    safeSetTextColor(widget, color)
end

local function updateCachedBarColor(owner, key, bar, rgba)
    local color = rgba or DEFAULT_HP_COLOR
    local colorKey = table.concat({
        tostring(color[1] or ""),
        tostring(color[2] or ""),
        tostring(color[3] or ""),
        tostring(color[4] or "")
    }, ",")
    if owner[key] == colorKey then
        return
    end
    owner[key] = colorKey
    safeApplyBarColor(bar, color)
end

local function updateCachedBarValue(owner, rangeKey, valueKey, bar, maxValue, currentValue)
    if bar == nil then
        return
    end
    local maxNum = math.max(0, tonumber(maxValue) or 0)
    local currentNum = clamp(currentValue, 0, maxNum, 0)
    local rangeToken = "0:" .. tostring(maxNum)
    if owner[rangeKey] ~= rangeToken then
        owner[rangeKey] = rangeToken
        pcall(function()
            if bar.SetMinMaxValues ~= nil then
                bar:SetMinMaxValues(0, maxNum)
            end
        end)
    end
    if owner[valueKey] ~= currentNum then
        owner[valueKey] = currentNum
        pcall(function()
            if bar.SetValue ~= nil then
                bar:SetValue(currentNum)
            end
        end)
    end
end

local function mapRoleId(roleId)
    if tonumber(roleId) == 1 then
        return "defender"
    end
    if tonumber(roleId) == 2 then
        return "attacker"
    end
    if tonumber(roleId) == 3 then
        return "healer"
    end
    return "undecided"
end

local function getTeamRoleKey(name)
    local cleanName = trim(name)
    if cleanName == "" or api.Team == nil or api.Team.GetMemberIndexByName == nil or api.Team.GetRole == nil then
        return nil
    end
    local okIndex, memberIndex = pcall(function()
        return api.Team:GetMemberIndexByName(cleanName)
    end)
    if not okIndex or tonumber(memberIndex) == nil then
        return nil
    end
    local okRole, roleId = pcall(function()
        return api.Team:GetRole(memberIndex)
    end)
    if not okRole then
        return nil
    end
    return mapRoleId(roleId)
end

local function getRolePrefix(roleKey)
    if roleKey == "defender" then
        return "D "
    end
    if roleKey == "healer" then
        return "H "
    end
    if roleKey == "attacker" then
        return "A "
    end
    if roleKey == "undecided" then
        return "U "
    end
    return ""
end

local function formatName(name, maxChars)
    local text = trim(name)
    local limit = clamp(maxChars, 0, 64, 0)
    if limit ~= nil and limit > 0 and string.len(text) > limit then
        return string.sub(text, 1, limit)
    end
    return text
end

local function truthyMatch(tbl, patterns, depth)
    if type(tbl) ~= "table" then
        return false
    end
    local remaining = clamp(depth, 0, 8, 1)
    for key, value in pairs(tbl) do
        local keyText = string.lower(tostring(key or ""))
        local matched = false
        for _, pattern in ipairs(patterns or {}) do
            if string.find(keyText, pattern, 1, true) ~= nil then
                matched = true
                break
            end
        end
        if matched then
            if value == true then
                return true
            end
            if type(value) == "number" and value ~= 0 then
                return true
            end
            if type(value) == "string" then
                local lowered = string.lower(value)
                if lowered == "true" or lowered == "yes" or lowered == "1" then
                    return true
                end
            end
        end
        if remaining > 0 and type(value) == "table" and truthyMatch(value, patterns, remaining - 1) then
            return true
        end
    end
    return false
end

local function safeUnitInfo(unit)
    if api.Unit == nil or api.Unit.UnitInfo == nil then
        return nil
    end
    local ok, info = pcall(function()
        return api.Unit:UnitInfo(unit)
    end)
    if ok and type(info) == "table" then
        return info
    end
    return nil
end

local function safeUnitModifierInfo(unit)
    if api.Unit == nil or api.Unit.UnitModifierInfo == nil then
        return nil
    end
    local ok, info = pcall(function()
        return api.Unit:UnitModifierInfo(unit)
    end)
    if ok and type(info) == "table" then
        return info
    end
    return nil
end

local function safeUnitName(unit, info, unitId)
    if type(info) == "table" then
        local fromInfo = trim(
            info.name
            or info.unitName
            or info.unit_name
            or info.characterName
            or info.character_name
            or info.nickName
            or info.nickname
            or info.nick_name
        )
        if fromInfo ~= "" then
            return fromInfo
        end
    end

    local name = Runtime ~= nil and Runtime.GetUnitName(unit) or ""
    name = trim(name)
    if name ~= "" then
        return name
    end

    if unitId ~= nil and unitId ~= "" then
        name = Runtime ~= nil and Runtime.GetUnitNameById(unitId) or ""
        name = trim(name)
        if name ~= "" then
            return name
        end
    end

    return ""
end

local function safeUnitId(unit)
    local unitId = Runtime ~= nil and Runtime.GetUnitId(unit) or nil
    if unitId == nil then
        return nil
    end
    return tostring(unitId)
end

local function safeUnitHealth(unit)
    if api.Unit == nil then
        return 0, 0, 0, 0
    end
    local hp = 0
    local maxHp = 0
    local mp = 0
    local maxMp = 0
    pcall(function()
        if api.Unit.UnitHealth ~= nil then
            hp = tonumber(api.Unit:UnitHealth(unit)) or 0
        end
        if api.Unit.UnitMaxHealth ~= nil then
            maxHp = tonumber(api.Unit:UnitMaxHealth(unit)) or 0
        end
        if api.Unit.UnitMana ~= nil then
            mp = tonumber(api.Unit:UnitMana(unit)) or 0
        end
        if api.Unit.UnitMaxMana ~= nil then
            maxMp = tonumber(api.Unit:UnitMaxMana(unit)) or 0
        end
    end)
    return hp, maxHp, mp, maxMp
end

local function safeUnitDistance(unit)
    if api.Unit == nil or api.Unit.UnitDistance == nil then
        return nil
    end
    local ok, distance = pcall(function()
        return api.Unit:UnitDistance(unit)
    end)
    if ok and type(distance) == "number" then
        return distance
    end
    return nil
end

local function safeUnitOffline(unit)
    if api.Unit == nil or api.Unit.UnitIsOffline == nil then
        return false
    end
    local ok, offline = pcall(function()
        return api.Unit:UnitIsOffline(unit)
    end)
    return ok and offline and true or false
end

local function safeDebuffCount(unit)
    if api.Unit == nil or api.Unit.UnitDeBuffCount == nil then
        return 0
    end
    local ok, count = pcall(function()
        return api.Unit:UnitDeBuffCount(unit)
    end)
    if ok then
        return tonumber(count) or 0
    end
    return 0
end

local function getUnitState(info, modifier, hp, maxHp, offline)
    local dead = false
    if not offline and tonumber(maxHp) ~= nil and tonumber(maxHp) > 0 and tonumber(hp) ~= nil and tonumber(hp) <= 0 then
        dead = true
    end
    if not dead then
        dead = truthyMatch(info, { "dead", "death", "ghost" }, 1)
            or truthyMatch(modifier, { "dead", "death", "ghost" }, 1)
    end
    return {
        offline = offline and true or false,
        dead = dead and true or false
    }
end

local function getValueText(mode, cur, max, kind)
    local current = tonumber(cur) or 0
    local total = math.max(0, tonumber(max) or 0)
    local textMode = tostring(mode or "percent")
    local resource = tostring(kind or "hp")
    if textMode == "curmax" then
        return string.format("%d/%d", math.floor(current + 0.5), math.floor(total + 0.5))
    end
    if textMode == "missing" and resource == "hp" then
        local missing = total - current
        if missing < 0 then
            missing = 0
        end
        return string.format("-%d", math.floor(missing + 0.5))
    end
    if total <= 0 then
        return "0%"
    end
    return string.format("%d%%", math.floor(((current / total) * 100) + 0.5))
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
    if RaidFrames.container ~= nil and RaidFrames.container.GetOffset ~= nil then
        pcall(function()
            x, y = RaidFrames.container:GetOffset()
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
        if wnd.SetUILayer ~= nil then
            wnd:SetUILayer("hud")
        end
    end)

    local dragHandle = api.Interface:CreateWidget("label", "nuziRaidFramesDragHandle", wnd)
    pcall(function()
        dragHandle:Show(true)
        dragHandle:SetText("Nuzi Raid")
        dragHandle:SetExtent(120, DRAG_HANDLE_HEIGHT)
        if dragHandle.style ~= nil then
            dragHandle.style:SetFontSize(10)
            dragHandle.style:SetColor(0.82, 0.82, 0.82, 0.8)
            if dragHandle.style.SetAlign ~= nil then
                dragHandle.style:SetAlign(ALIGN.LEFT)
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
            if header.style.SetAlign ~= nil then
                header.style:SetAlign(ALIGN.LEFT)
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
            if bar.Clickable ~= nil then
                bar:Clickable(false)
            end
        end
    end)
    return bar
end

local function targetUnit(unit)
    if trim(unit) == "" then
        return
    end
    pcall(function()
        if TargetUnit ~= nil then
            TargetUnit(unit)
            return
        end
        if api.Unit ~= nil and api.Unit.TargetUnit ~= nil then
            api.Unit.TargetUnit(unit)
        end
    end)
end

local function createFrame(index)
    if RaidFrames.frames[index] ~= nil then
        return RaidFrames.frames[index]
    end

    local frameId = "nuziRaidMember" .. tostring(index)
    local frame = api.Interface:CreateEmptyWindow(frameId)
    pcall(function()
        if frame.SetUILayer ~= nil then
            frame:SetUILayer("hud")
        end
    end)

    frame.bg = createColorDrawable(frame, "background", 0.04, 0.04, 0.05, 0.8)
    frame.targetTint = createColorDrawable(frame, "overlay", 1, 0.9, 0.45, 0.28)
    frame.hpBar = createRaidBar(frameId .. ".hpBar", frame)
    frame.mpBar = createRaidBar(frameId .. ".mpBar", frame)
    frame.debuffBadge = createColorDrawable(frame, "artwork", 1, 0.27, 0.27, 0.92)

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
            if nameLabel.style.SetAlign ~= nil then
                nameLabel.style:SetAlign(ALIGN.LEFT)
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
            if valueLabel.style.SetAlign ~= nil then
                valueLabel.style:SetAlign(ALIGN.RIGHT)
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
            if statusLabel.style.SetAlign ~= nil then
                statusLabel.style:SetAlign(ALIGN.CENTER)
            end
        end
    end)
    frame.statusLabel = statusLabel

    frame.OnClick = function(self)
        targetUnit(self.__raid_unit or "")
    end

    pcall(function()
        if frame.SetHandler ~= nil then
            frame:SetHandler("OnClick", frame.OnClick)
        end
        if frame.RegisterForClicks ~= nil then
            frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
        tostring(valueOffsetY)
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

    if frame.hpBar ~= nil then
        safeAnchor(frame.hpBar, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        pcall(function()
            frame.hpBar:AddAnchor("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        end)
        safeSetHeight(frame.hpBar, hpHeight)
    end

    if frame.mpBar ~= nil then
        safeAnchor(frame.mpBar, "TOPLEFT", frame, "TOPLEFT", 0, hpHeight + 1)
        pcall(function()
            frame.mpBar:AddAnchor("TOPRIGHT", frame, "TOPRIGHT", 0, hpHeight + 1)
        end)
        safeSetHeight(frame.mpBar, mpHeight)
        safeShow(frame.mpBar, showMp)
    end

    if frame.nameLabel ~= nil then
        safeSetFontSize(frame.nameLabel, nameFontSize)
        safeSetExtent(frame.nameLabel, math.max(24, width - 24), hpHeight)
        safeAnchor(frame.nameLabel, "LEFT", frame, "LEFT", namePad + nameOffsetX, nameOffsetY)
    end

    if frame.valueLabel ~= nil then
        safeSetFontSize(frame.valueLabel, valueFontSize)
        safeSetExtent(frame.valueLabel, math.max(28, width - 8), hpHeight)
        safeAnchor(frame.valueLabel, "RIGHT", frame, "RIGHT", -4 + valueOffsetX, valueOffsetY)
    end

    if frame.statusLabel ~= nil then
        safeSetFontSize(frame.statusLabel, valueFontSize)
        safeSetExtent(frame.statusLabel, math.max(28, width - 8), hpHeight)
        safeAnchor(frame.statusLabel, "CENTER", frame, "CENTER", 0, 0)
    end

    if frame.debuffBadge ~= nil then
        safeAnchor(frame.debuffBadge, "TOPRIGHT", frame, "TOPRIGHT", -1, 1)
        safeSetExtent(frame.debuffBadge, 8, 8)
    end
end

local function tryHideStockRaidFrames(cfg)
    if cfg.hide_stock ~= true or Runtime == nil or UIC == nil or UIC.RAID_MANAGER == nil then
        return
    end
    local stock = Runtime.GetStockContent(UIC.RAID_MANAGER)
    if stock == nil or stock.Show == nil then
        return
    end
    pcall(function()
        stock:Show(false)
    end)
end

local function buildMember(unit, index)
    local info = safeUnitInfo(unit)
    local unitId = safeUnitId(unit)
    local name = safeUnitName(unit, info, unitId)
    if name == "" and unitId == nil then
        return nil
    end
    return {
        unit = unit,
        index = index,
        unit_id = unitId,
        name = name,
        info = info,
        role_key = getTeamRoleKey(name)
    }
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
            alpha = alpha * percent01(cfg.range_alpha_pct, 45)
        end
    end
    return alpha
end

local function getHpColor(settings, cfg, member, state)
    if state.offline then
        return OFFLINE_BAR_COLOR
    end
    if state.dead then
        return DEAD_BAR_COLOR
    end
    if cfg.use_team_role_colors ~= false and TEAM_ROLE_COLORS[member.role_key or ""] ~= nil then
        return TEAM_ROLE_COLORS[member.role_key]
    end
    if settings ~= nil and type(settings.style) == "table" and settings.style.bar_colors_enabled and tostring(cfg.bar_style_mode or "shared") == "shared" then
        return settings.style.hp_bar_color or settings.style.hp_fill_color or DEFAULT_HP_COLOR
    end
    return DEFAULT_HP_COLOR
end

local function getMpColor(settings, cfg)
    if settings ~= nil and type(settings.style) == "table" and settings.style.bar_colors_enabled and tostring(cfg.bar_style_mode or "shared") == "shared" then
        return settings.style.mp_bar_color or settings.style.mp_fill_color or DEFAULT_MP_COLOR
    end
    return DEFAULT_MP_COLOR
end

local function getNameColor(cfg, member, state)
    if state.offline then
        return OFFLINE_TEXT_COLOR
    end
    if state.dead then
        return DEAD_TEXT_COLOR
    end
    if cfg.use_role_name_colors ~= false and TEAM_ROLE_COLORS[member.role_key or ""] ~= nil then
        return TEAM_ROLE_COLORS[member.role_key]
    end
    return { 255, 255, 255, 255 }
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

local function renderMember(frame, settings, cfg, member, refreshMetadata)
    local hp, maxHp, mp, maxMp = safeUnitHealth(member.unit)
    local offline = safeUnitOffline(member.unit)
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

    frame.__raid_unit = member.unit
    frame.__raid_unit_id = member.unit_id

    local displayName = formatName(member.name, cfg.name_max_chars)
    if cfg.show_role_prefix ~= false then
        displayName = getRolePrefix(member.role_key) .. displayName
    end

    local targetMatch = member.unit_id ~= nil
        and RaidFrames.current_target_id ~= nil
        and tostring(member.unit_id) == tostring(RaidFrames.current_target_id)

    local nameColor = getNameColor(cfg, member, state)
    local hpColor = getHpColor(settings, cfg, member, state)
    local mpColor = getMpColor(settings, cfg)

    local showName = cfg.show_name ~= false and trim(displayName) ~= ""
    local showValue = cfg.show_value_text and statusText == ""
    local showStatus = cfg.show_status_text ~= false and statusText ~= ""
    if refreshMetadata or frame.__nr_debuff_count == nil then
        frame.__nr_debuff_count = safeDebuffCount(member.unit)
    end
    local showDebuff = cfg.show_debuff_alert ~= false and (tonumber(frame.__nr_debuff_count) or 0) > 0

    updateCachedText(frame, "__nr_name", frame.nameLabel, displayName)
    updateCachedVisible(frame, "__nr_name_visible", frame.nameLabel, showName)
    updateCachedLabelColor(frame, "__nr_name_color", frame.nameLabel, nameColor)

    if showValue then
        updateCachedText(frame, "__nr_value", frame.valueLabel, getValueText(cfg.value_text_mode, hp, maxHp, "hp"))
    end
    updateCachedVisible(frame, "__nr_value_visible", frame.valueLabel, showValue)
    updateCachedLabelColor(frame, "__nr_value_color", frame.valueLabel, nameColor)

    updateCachedText(frame, "__nr_status", frame.statusLabel, statusText)
    updateCachedVisible(frame, "__nr_status_visible", frame.statusLabel, showStatus)
    updateCachedLabelColor(frame, "__nr_status_color", frame.statusLabel, state.dead and DEAD_TEXT_COLOR or OFFLINE_TEXT_COLOR)

    updateCachedBarColor(frame, "__nr_hp_color", frame.hpBar ~= nil and frame.hpBar.statusBar or nil, hpColor)
    updateCachedBarValue(frame, "__nr_hp_range", "__nr_hp_value", frame.hpBar ~= nil and frame.hpBar.statusBar or nil, maxHp, hp)
    updateCachedBarColor(frame, "__nr_mp_color", frame.mpBar ~= nil and frame.mpBar.statusBar or nil, mpColor)
    updateCachedBarValue(frame, "__nr_mp_range", "__nr_mp_value", frame.mpBar ~= nil and frame.mpBar.statusBar or nil, maxMp, mp)

    updateCachedVisible(frame, "__nr_target_visible", frame.targetTint, cfg.show_target_highlight ~= false and targetMatch)
    if frame.targetTint ~= nil then
        safeSetColor(
            frame.targetTint,
            TARGET_TINT_COLOR[1] / 255,
            TARGET_TINT_COLOR[2] / 255,
            TARGET_TINT_COLOR[3] / 255,
            TARGET_TINT_COLOR[4] / 255
        )
    end

    updateCachedVisible(frame, "__nr_debuff_visible", frame.debuffBadge, showDebuff)
    if frame.debuffBadge ~= nil then
        safeSetColor(
            frame.debuffBadge,
            DEBUFF_BADGE_COLOR[1] / 255,
            DEBUFF_BADGE_COLOR[2] / 255,
            DEBUFF_BADGE_COLOR[3] / 255,
            DEBUFF_BADGE_COLOR[4] / 255
        )
    end

    if frame.bg ~= nil then
        local bgAlpha = cfg.bg_enabled and percent01(cfg.bg_alpha_pct, 80) or 0
        safeSetColor(frame.bg, 0.05, 0.05, 0.06, bgAlpha)
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
    ensureContainer()
    if type(settings) == "table" and type(settings.raidframes) == "table" then
        applyContainerPosition(settings.raidframes)
    end
end

function RaidFrames.SetEnabled(enabled)
    RaidFrames.enabled = enabled and true or false
    if not RaidFrames.enabled then
        safeShow(RaidFrames.container, false)
        for _, frame in pairs(RaidFrames.frames) do
            safeShow(frame, false)
        end
        for _, header in pairs(RaidFrames.group_headers) do
            safeShow(header, false)
        end
    end
end

function RaidFrames.OnUpdate(settings, updateFlags)
    if type(settings) ~= "table" or type(settings.raidframes) ~= "table" then
        safeShow(RaidFrames.container, false)
        return
    end

    local cfg = settings.raidframes
    local flags = type(updateFlags) == "table" and updateFlags or {}
    if not (RaidFrames.enabled and cfg.enabled) then
        safeShow(RaidFrames.container, false)
        for _, frame in pairs(RaidFrames.frames) do
            safeShow(frame, false)
        end
        for _, header in pairs(RaidFrames.group_headers) do
            safeShow(header, false)
        end
        return
    end

    ensureContainer()
    applyContainerPosition(cfg)
    tryHideStockRaidFrames(cfg)
    RaidFrames.now_ms = RaidFrames.now_ms + 100

    if flags.update_target == true or RaidFrames.current_target_id == nil then
        RaidFrames.current_target_id = safeUnitId("target")
    end

    local members = RaidFrames.active_members
    if flags.update_roster == true or flags.force_roster == true or type(members) ~= "table" or #members == 0 then
        members = rebuildRoster(cfg)
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

    updateContainerExtent(cfg, members)
    updateCachedAlpha(RaidFrames, "__nr_container_alpha", RaidFrames.container, percent01(cfg.alpha_pct, 100))
    updateCachedVisible(RaidFrames, "__nr_container_visible", RaidFrames.container, true)
    updateCachedVisible(RaidFrames, "__nr_drag_handle_visible", RaidFrames.drag_handle, true)

    local visibleIndex = 0
    local activeByIndex = {}
    local refreshMetadata = flags.update_metadata == true or flags.update_roster == true or flags.force_roster == true
    for _, member in ipairs(members) do
        visibleIndex = visibleIndex + 1
        activeByIndex[member.index] = true
        local frame = createFrame(member.index)
        applyFrameLayout(frame, cfg)
        updateFramePosition(frame, cfg, member, visibleIndex)
        renderMember(frame, settings, cfg, member, refreshMetadata)
    end

    for index = 1, MAX_RAID_MEMBERS do
        local frame = RaidFrames.frames[index]
        if frame ~= nil and not activeByIndex[index] then
            updateCachedVisible(frame, "__nr_visible", frame, false)
        end
    end

    updateGroupHeaders(cfg, members)
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
    RaidFrames.current_target_id = nil
    RaidFrames.now_ms = 0
end

return RaidFrames
