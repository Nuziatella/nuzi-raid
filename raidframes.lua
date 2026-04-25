local api = require("api")
local Require = require("nuzi-core/require")

local function loadModule(name)
    local mod = Require.Addon("nuzi-raid", name)
    return mod
end

local Shared = loadModule("shared")
local Runtime = loadModule("runtime")
local Compat = loadModule("compat")
local Overlay = loadModule("overlay_utils")
local globals = type(_G) == "table" and _G or nil
local ALIGN_REF = type(ALIGN) == "table" and ALIGN or (globals ~= nil and globals.ALIGN or nil)
local ActivatePopupMenuRef = type(ActivatePopupMenu) == "function" and ActivatePopupMenu or (globals ~= nil and globals.ActivatePopupMenu or nil)
local CreateUnitFrameRef = type(CreateUnitFrame) == "function" and CreateUnitFrame or (globals ~= nil and globals.CreateUnitFrame or nil)
local StatusBarStyleRef = type(STATUSBAR_STYLE) == "table" and STATUSBAR_STYLE or (globals ~= nil and globals.STATUSBAR_STYLE or nil)

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
local CLASS_NAME_COLOR_PALETTE = {
    { 255, 112, 112, 255 },
    { 255, 178, 82, 255 },
    { 255, 228, 109, 255 },
    { 141, 219, 109, 255 },
    { 92, 213, 189, 255 },
    { 104, 177, 255, 255 },
    { 162, 133, 255, 255 },
    { 242, 126, 214, 255 }
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
    if Overlay ~= nil and Overlay.SafeShow ~= nil then
        Overlay.SafeShow(widget, show)
        return
    end
    if widget ~= nil and widget.Show ~= nil then
        pcall(function()
            widget:Show(show and true or false)
        end)
    end
end

local function safeSetAlpha(widget, alpha)
    if Overlay ~= nil and Overlay.SafeSetAlpha ~= nil then
        Overlay.SafeSetAlpha(widget, alpha)
        return
    end
    if widget ~= nil and widget.SetAlpha ~= nil then
        pcall(function()
            widget:SetAlpha(alpha)
        end)
    end
end

local function safeSetText(widget, text)
    if widget == nil or widget.SetText == nil then
        return
    end
    pcall(function()
        widget:SetText(tostring(text or ""))
    end)
end

local function safeApplyBarTexture(bar, style)
    if bar == nil or style == nil or bar.ApplyBarTexture == nil then
        return
    end
    pcall(function()
        bar:ApplyBarTexture(style)
    end)
end

local function safeSetWidgetTarget(widget, unit, unitId, name)
    if widget == nil or widget.SetTarget == nil then
        return false
    end
    for index = 1, 3 do
        local candidate = nil
        if index == 1 then
            candidate = unit
        elseif index == 2 then
            candidate = unitId
        else
            candidate = name
        end
        local value = trim(candidate)
        if value ~= "" then
            local ok = pcall(function()
                widget:SetTarget(candidate)
            end)
            if ok then
                return true
            end
        end
    end
    return false
end

local function safeAssignWidgetField(widget, key, value)
    if widget == nil or key == nil then
        return
    end
    pcall(function()
        widget[key] = value
    end)
end

local function getBarValueTarget(bar)
    if bar == nil then
        return nil
    end
    if bar.statusBar ~= nil then
        return bar.statusBar
    end
    return bar
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

local function safeClickable(widget, clickable)
    if Overlay ~= nil and Overlay.SafeClickable ~= nil then
        Overlay.SafeClickable(widget, clickable)
        return
    end
    if widget ~= nil and widget.Clickable ~= nil then
        pcall(function()
            widget:Clickable(clickable and true or false)
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
    local function applyColor(widget)
        if widget == nil then
            return
        end
        pcall(function()
            if widget.SetBarColor ~= nil then
                widget:SetBarColor(r, g, b, a)
            end
        end)
        pcall(function()
            if widget.SetColor ~= nil then
                widget:SetColor(r, g, b, a)
            end
        end)
    end
    pcall(function()
        applyColor(statusBar)
        if statusBar.statusBar ~= nil then
            applyColor(statusBar.statusBar)
        end
        if statusBar.statusBarAfterImage ~= nil then
            applyColor(statusBar.statusBarAfterImage)
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
    local colorKey = tostring(color[1] or "") .. ","
        .. tostring(color[2] or "") .. ","
        .. tostring(color[3] or "") .. ","
        .. tostring(color[4] or "")
    if owner[key] == colorKey then
        return
    end
    owner[key] = colorKey
    safeSetTextColor(widget, color)
end

local function updateCachedBarColor(owner, key, bar, rgba)
    local color = rgba or DEFAULT_HP_COLOR
    local colorKey = tostring(color[1] or "") .. ","
        .. tostring(color[2] or "") .. ","
        .. tostring(color[3] or "") .. ","
        .. tostring(color[4] or "")
    if owner[key] == colorKey then
        return
    end
    owner[key] = colorKey
    safeApplyBarColor(bar, color)
end

local function updateCachedDrawableColor(owner, key, drawable, r, g, b, a)
    if drawable == nil then
        return
    end
    local colorKey = tostring(r or "") .. ","
        .. tostring(g or "") .. ","
        .. tostring(b or "") .. ","
        .. tostring(a or "")
    if owner[key] == colorKey then
        return
    end
    owner[key] = colorKey
    safeSetColor(drawable, r, g, b, a)
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
        return "healer"
    end
    if tonumber(roleId) == 3 then
        return "attacker"
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

local function safeTeamPlayerIndex()
    if api.Team ~= nil and api.Team.GetTeamPlayerIndex ~= nil then
        local ok, value = pcall(function()
            return api.Team:GetTeamPlayerIndex()
        end)
        if ok and tonumber(value) ~= nil then
            return tonumber(value)
        end
        ok, value = pcall(function()
            return api.Team.GetTeamPlayerIndex(api.Team)
        end)
        if ok and tonumber(value) ~= nil then
            return tonumber(value)
        end
    end

    local playerName = Runtime ~= nil and Runtime.GetPlayerName ~= nil and Runtime.GetPlayerName() or ""
    playerName = trim(playerName)
    if playerName ~= "" and api.Team ~= nil and api.Team.GetMemberIndexByName ~= nil then
        local ok, value = pcall(function()
            return api.Team:GetMemberIndexByName(playerName)
        end)
        if ok and tonumber(value) ~= nil then
            return tonumber(value)
        end
    end

    return nil
end

local function getRaidPopupKind(frame)
    local clickedIndex = frame ~= nil and tonumber(frame.__raid_member_index or frame.memberIndex or frame.index) or nil
    local myIndex = safeTeamPlayerIndex()
    if clickedIndex ~= nil and myIndex ~= nil and clickedIndex == myIndex then
        return "player"
    end
    return "team"
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

local function getRoleBadge(roleKey, hideDps)
    if roleKey == "defender" then
        return "[D]"
    end
    if roleKey == "healer" then
        return "[H]"
    end
    if roleKey == "attacker" then
        return hideDps and "" or "[A]"
    end
    if roleKey == "undecided" then
        return "[U]"
    end
    return ""
end

local function getClassBadge(className)
    local clean = trim(className)
    if clean == "" then
        return ""
    end
    if string.len(clean) <= 3 then
        return string.upper(clean)
    end
    return string.upper(string.sub(clean, 1, 3))
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

local function safeUnitInfoById(unitId)
    if unitId == nil or api.Unit == nil or api.Unit.GetUnitInfoById == nil then
        return nil
    end
    local ok, info = pcall(function()
        return api.Unit:GetUnitInfoById(unitId)
    end)
    if ok and type(info) == "table" then
        return info
    end
    return nil
end

local function firstNumber(...)
    for index = 1, select("#", ...) do
        local value = tonumber(select(index, ...))
        if value ~= nil then
            return value
        end
    end
    return nil
end

local function isRightClick(button)
    if tonumber(button) == 2 then
        return true
    end
    local text = string.lower(tostring(button or ""))
    return text == "rightbutton"
        or text == "rightbuttonup"
        or text == "rightbuttondown"
        or text == "rbutton"
        or text == "rbuttonup"
        or text == "rbuttondown"
        or string.find(text, "right", 1, true) ~= nil
        or string.find(text, "rbutton", 1, true) ~= nil
        or text == "button2"
end

local function extractVitalsFromInfo(info)
    if type(info) ~= "table" then
        return nil, nil, nil, nil
    end
    local hp = firstNumber(
        info.curHp,
        info.curHP,
        info.currentHp,
        info.currentHP,
        info.hp,
        info.health,
        info.cur_health,
        info.current_health
    )
    local maxHp = firstNumber(
        info.maxHp,
        info.maxHP,
        info.maxHealth,
        info.max_health,
        info.healthMax,
        info.health_max,
        info.hpMax,
        info.hp_max
    )
    local mp = firstNumber(
        info.curMp,
        info.curMP,
        info.currentMp,
        info.currentMP,
        info.mp,
        info.mana,
        info.cur_mana,
        info.current_mana
    )
    local maxMp = firstNumber(
        info.maxMp,
        info.maxMP,
        info.maxMana,
        info.max_mana,
        info.manaMax,
        info.mana_max,
        info.mpMax,
        info.mp_max
    )
    return hp, maxHp, mp, maxMp
end

local function hasUsableVitals(current, maximum)
    return type(current) == "number" and current >= 0 and type(maximum) == "number" and maximum > 0
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

local function safeUnitClassName(unit, info)
    if type(info) == "table" then
        local fromInfo = trim(
            info.className
            or info.class_name
            or info.unitClass
            or info.unit_class
            or info.jobName
            or info.job_name
        )
        if fromInfo ~= "" then
            return fromInfo
        end
    end

    if api.Ability ~= nil and api.Ability.GetUnitClassName ~= nil then
        local ok, value = pcall(function()
            return api.Ability:GetUnitClassName(unit)
        end)
        value = trim(value)
        if ok and value ~= "" then
            return value
        end
    end

    if api.Unit ~= nil and api.Unit.UnitClass ~= nil then
        local okClass, classId = pcall(function()
            return api.Unit:UnitClass(unit)
        end)
        if okClass then
            return trim(classId)
        end
    end

    return ""
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
    return tonumber(unitId) or unitId
end

local function safeUnitHealth(unit, unitId, includeMana)
    if api.Unit == nil then
        return nil, nil, nil, nil
    end
    includeMana = includeMana ~= false
    local hp = nil
    local maxHp = nil
    local mp = nil
    local maxMp = nil
    pcall(function()
        if api.Unit.UnitHealth ~= nil then
            hp = tonumber(api.Unit:UnitHealth(unit))
        end
        if api.Unit.UnitMaxHealth ~= nil then
            maxHp = tonumber(api.Unit:UnitMaxHealth(unit))
        end
        if includeMana and api.Unit.UnitMana ~= nil then
            mp = tonumber(api.Unit:UnitMana(unit))
        end
        if includeMana and api.Unit.UnitMaxMana ~= nil then
            maxMp = tonumber(api.Unit:UnitMaxMana(unit))
        end
    end)

    if hp == nil or maxHp == nil or (includeMana and (mp == nil or maxMp == nil)) then
        local info = safeUnitInfo(unit)
        local infoHp, infoMaxHp, infoMp, infoMaxMp = extractVitalsFromInfo(info)
        hp = firstNumber(hp, infoHp)
        maxHp = firstNumber(maxHp, infoMaxHp)
        if includeMana then
            mp = firstNumber(mp, infoMp)
            maxMp = firstNumber(maxMp, infoMaxMp)
        end
    end

    if hp == nil or maxHp == nil or (includeMana and (mp == nil or maxMp == nil)) then
        local byIdInfo = safeUnitInfoById(unitId)
        local idHp, idMaxHp, idMp, idMaxMp = extractVitalsFromInfo(byIdInfo)
        hp = firstNumber(hp, idHp)
        maxHp = firstNumber(maxHp, idMaxHp)
        if includeMana then
            mp = firstNumber(mp, idMp)
            maxMp = firstNumber(maxMp, idMaxMp)
        end
    end

    return tonumber(hp), tonumber(maxHp), tonumber(mp), tonumber(maxMp)
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

local function safeDebuffInfo(unit, index)
    if api.Unit == nil or api.Unit.UnitDeBuff == nil then
        return nil
    end
    local ok, info = pcall(function()
        return api.Unit:UnitDeBuff(unit, index)
    end)
    if ok and type(info) == "table" then
        return info
    end
    return nil
end

local function hasDispellableDebuff(unit, count)
    local total = clamp(count, 0, 40, 0)
    for index = 1, total do
        local info = safeDebuffInfo(unit, index)
        if truthyMatch(info, { "dispel", "dispell", "cleanse", "purge", "remove", "cure", "removable" }, 2) then
            return true
        end
    end
    return false
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

local function mergeResourceValues(current, maximum, lastCurrent, lastMaximum)
    local mergedCurrent = firstNumber(current, lastCurrent)
    local mergedMaximum = firstNumber(maximum, lastMaximum)
    if hasUsableVitals(mergedCurrent, mergedMaximum) then
        return mergedCurrent, mergedMaximum
    end
    return tonumber(current), tonumber(maximum)
end

local function hashText(value)
    local hash = 0
    local text = tostring(value or "")
    for index = 1, string.len(text) do
        hash = (hash * 33 + string.byte(text, index)) % 2147483647
    end
    return hash
end

local function getClassColor(className)
    local clean = trim(className)
    if clean == "" then
        return nil
    end
    local paletteIndex = (hashText(string.lower(clean)) % #CLASS_NAME_COLOR_PALETTE) + 1
    return CLASS_NAME_COLOR_PALETTE[paletteIndex]
end

local function getHpTextureStyle(settings)
    local mode = "stock"
    if type(settings) == "table" and type(settings.style) == "table" then
        mode = tostring(settings.style.hp_texture_mode or "stock")
    end
    if StatusBarStyleRef == nil then
        return nil
    end
    if mode == "pc" then
        return StatusBarStyleRef.S_HP_PARTY
            or StatusBarStyleRef.S_HP_FRIENDLY
            or StatusBarStyleRef.L_HP_FRIENDLY
    end
    if mode == "npc" then
        return StatusBarStyleRef.S_HP_FRIENDLY
            or StatusBarStyleRef.S_HP_PARTY
            or StatusBarStyleRef.S_HP_NEUTRAL
            or StatusBarStyleRef.S_HP_HOSTILE
            or StatusBarStyleRef.S_HP_PREEMTIVE_STRIKE
    end
    return StatusBarStyleRef.S_HP_PARTY
        or StatusBarStyleRef.S_HP_FRIENDLY
        or StatusBarStyleRef.L_HP_FRIENDLY
end

local function applyFrameTextures(frame, settings)
    if frame == nil then
        return
    end
    local hpStyle = getHpTextureStyle(settings)
    local mpStyle = StatusBarStyleRef ~= nil and StatusBarStyleRef.S_MP or nil
    local textureKey = tostring(hpStyle or "nil") .. "|" .. tostring(mpStyle or "nil")
    if frame.__nr_texture_key == textureKey then
        return
    end
    frame.__nr_texture_key = textureKey
    safeApplyBarTexture(frame.hpBar, hpStyle)
    safeApplyBarTexture(frame.mpBar, mpStyle)
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

local function showPopupMenu(frame)
    if frame == nil or ActivatePopupMenuRef == nil then
        return false
    end
    local owners = {
        frame.__nr_popup_owner,
        frame.popupOwner ~= nil and frame.popupOwner.eventWindow or nil,
        frame.popupOwner,
        frame,
        frame.eventWindow
    }
    local attempted = false
    for _, owner in ipairs(owners) do
        if owner ~= nil then
            if owner.Click ~= nil then
                pcall(function()
                    owner:Click("RightButton")
                end)
                pcall(function()
                    owner:Click("RightButtonUp")
                end)
            end
            local ok = pcall(function()
                ActivatePopupMenuRef(owner, "team")
            end)
            if ok then
                attempted = true
            end
        end
    end
    return attempted
end

local targetUnit

local function showPopupMenuViaTargetFrame(unit)
    if trim(unit) == "" or ActivatePopupMenuRef == nil or Runtime == nil or UIC == nil or UIC.TARGET_UNITFRAME == nil then
        return false
    end
    targetUnit(unit)
    local targetFrame = Runtime.GetStockContent(UIC.TARGET_UNITFRAME)
    if targetFrame == nil then
        return false
    end
    pcall(function()
        ActivatePopupMenuRef(targetFrame, "target")
    end)
    if targetFrame.Click ~= nil then
        pcall(function()
            targetFrame:Click("RightButton")
        end)
        pcall(function()
            targetFrame:Click("RightButtonUp")
        end)
    end
    return true
end

targetUnit = function(unit)
    if trim(unit) == "" then
        return
    end
    pcall(function()
        if TargetUnit ~= nil then
            TargetUnit(unit)
            return
        end
        if api.Unit ~= nil and api.Unit.TargetUnit ~= nil then
            local ok = pcall(function()
                api.Unit:TargetUnit(unit)
            end)
            if not ok then
                api.Unit.TargetUnit(unit)
            end
        end
    end)
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
        if eventWindow.SetUILayer ~= nil then
            eventWindow:SetUILayer("hud")
        end
        if eventWindow.EnablePick ~= nil then
            eventWindow:EnablePick(true)
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
        if owner.SetUILayer ~= nil then
            owner:SetUILayer("hud")
        end
    end)
    safeClickable(owner, false)
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
        if frame.SetUILayer ~= nil then
            frame:SetUILayer("hud")
        end
    end)

    frame.bg = createColorDrawable(frame, "background", 0.04, 0.04, 0.05, 0.8)
    frame.targetTint = createColorDrawable(frame, "overlay", 1, 0.9, 0.45, 0.28)
    frame.hpBar = createRaidBar(frameId .. ".hpBar", frame)
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

    local function handleFrameClick(self, button)
        frame.__nr_popup_owner = frame.popupOwner or frame
        if isRightClick(button) then
            if not showPopupMenu(frame) then
                showPopupMenuViaTargetFrame(frame.__raid_unit)
            end
            return
        end
        targetUnit((self ~= nil and (self.target or self.unit)) or frame.__raid_unit)
    end
    local function handleFrameMouseUp(self, button)
        frame.__nr_popup_owner = frame.popupOwner or frame
        if isRightClick(button) then
            if not showPopupMenu(frame) then
                showPopupMenuViaTargetFrame(frame.__raid_unit)
            end
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
    local iconOffsetX = clamp(cfg.icon_offset_x, -120, 120, 0)
    local iconOffsetY = clamp(cfg.icon_offset_y, -40, 40, 0)

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
        tostring(iconOffsetX),
        tostring(iconOffsetY)
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
        safeSetHeight(getBarValueTarget(frame.hpBar), hpHeight)
    end

    if frame.mpBar ~= nil then
        safeAnchor(frame.mpBar, "TOPLEFT", frame, "TOPLEFT", 0, hpHeight + 1)
        pcall(function()
            frame.mpBar:AddAnchor("TOPRIGHT", frame, "TOPRIGHT", 0, hpHeight + 1)
        end)
        safeSetHeight(frame.mpBar, mpHeight)
        safeSetHeight(getBarValueTarget(frame.mpBar), mpHeight)
        safeShow(frame.mpBar, showMp)
    end

    if frame.nameLabel ~= nil then
        safeSetFontSize(frame.nameLabel, nameFontSize)
        safeSetExtent(frame.nameLabel, math.max(24, width - 24), hpHeight)
        safeAnchor(frame.nameLabel, "LEFT", frame, "LEFT", namePad + nameOffsetX + iconSize + iconGap, nameOffsetY)
    end

    if frame.metaLabel ~= nil then
        safeSetFontSize(frame.metaLabel, iconSize)
        safeSetExtent(frame.metaLabel, math.max(18, iconSize * 3), hpHeight)
        safeAnchor(frame.metaLabel, "LEFT", frame, "LEFT", namePad + iconOffsetX, iconOffsetY)
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

    if frame.badgeLabel ~= nil then
        safeSetFontSize(frame.badgeLabel, iconSize)
        safeSetExtent(frame.badgeLabel, math.max(28, width - 8), hpHeight)
        safeAnchor(frame.badgeLabel, "RIGHT", frame, "RIGHT", -4 + iconOffsetX, iconOffsetY)
    end

    if frame.debuffBadge ~= nil then
        safeAnchor(frame.debuffBadge, "TOPRIGHT", frame, "TOPRIGHT", -1, 1)
        safeSetExtent(frame.debuffBadge, 8, 8)
    end

    if frame.eventWindow ~= nil then
        safeAnchor(frame.eventWindow, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        pcall(function()
            frame.eventWindow:AddAnchor("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        end)
    end
    if frame.popupOwner ~= nil then
        safeAnchor(frame.popupOwner, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        pcall(function()
            frame.popupOwner:AddAnchor("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
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
        class_name = safeUnitClassName(unit, info),
        role_key = getTeamRoleKey(name)
    }
end

local function refreshMemberSnapshot(member, refreshMetadata)
    if type(member) ~= "table" then
        return member
    end
    local info = safeUnitInfo(member.unit)
    local unitId = safeUnitId(member.unit)
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
        return settings.style.hp_fill_color or settings.style.hp_bar_color or DEFAULT_HP_COLOR
    end
    return DEFAULT_HP_COLOR
end

local function getMpColor(settings, cfg)
    if settings ~= nil and type(settings.style) == "table" and settings.style.bar_colors_enabled and tostring(cfg.bar_style_mode or "shared") == "shared" then
        return settings.style.mp_fill_color or settings.style.mp_bar_color or DEFAULT_MP_COLOR
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
    if cfg.use_class_name_colors == true then
        local classColor = getClassColor(member.class_name)
        if classColor ~= nil then
            return classColor
        end
    end
    if cfg.use_role_name_colors ~= false and TEAM_ROLE_COLORS[member.role_key or ""] ~= nil then
        return TEAM_ROLE_COLORS[member.role_key]
    end
    return DEFAULT_TEXT_COLOR
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
    frame.__nr_cached_distance = nil
    frame.__nr_last_distance_ms = nil
    frame.__nr_has_seen_distance = nil
    frame.__nr_offline = nil
    frame.__nr_last_offline_ms = nil
    frame.__nr_static_rendered = false

    assignMemberFields(frame, member, resolvedUnitId, party, slot)
    assignMemberFields(frame.eventWindow, member, resolvedUnitId, party, slot)
    safeSetWidgetTarget(frame.popupOwner, member.unit, resolvedUnitId, member.name)
    assignMemberFields(frame.popupOwner, member, resolvedUnitId, party, slot)
    assignMemberFields(frame.popupOwner ~= nil and frame.popupOwner.eventWindow or nil, member, resolvedUnitId, party, slot)
    return true
end

local function renderMember(frame, settings, cfg, member, refreshMetadata, refreshStatic)
    refreshStatic = refreshStatic == true or refreshMetadata == true or frame.__nr_static_rendered ~= true
    if refreshMetadata == true or member.unit_id == nil or trim(member.name) == "" then
        member = refreshMemberSnapshot(member, refreshMetadata)
    end
    local resolvedUnitId = member.unit_id or frame.__raid_unit_id
    local showMpBar = clamp(cfg.mp_height, 0, 40, 0) > 0
    if applyMemberWidgetBindings(frame, member, resolvedUnitId) then
        refreshStatic = true
    end
    local hp, maxHp, mp, maxMp = safeUnitHealth(member.unit, resolvedUnitId, showMpBar)
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

    if refreshStatic then
        applyFrameTextures(frame, settings)
        frame.__nr_static_rendered = true
    end

    local targetMatch = member.unit_id ~= nil
        and RaidFrames.current_target_id ~= nil
        and tostring(member.unit_id) == tostring(RaidFrames.current_target_id)

    local nameColor = getNameColor(cfg, member, state)
    local hpColor = getHpColor(settings, cfg, member, state)
    local mpColor = showMpBar and getMpColor(settings, cfg) or nil

    local showValue = cfg.show_value_text and statusText == ""
    local showStatus = cfg.show_status_text ~= false and statusText ~= ""
    if refreshMetadata or frame.__nr_debuff_count == nil then
        frame.__nr_debuff_count = safeDebuffCount(member.unit)
        frame.__nr_has_dispellable_debuff = hasDispellableDebuff(member.unit, frame.__nr_debuff_count)
    end
    local showDebuff = cfg.show_debuff_alert ~= false and (tonumber(frame.__nr_debuff_count) or 0) > 0

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

    updateCachedLabelColor(frame, "__nr_name_color", frame.nameLabel, nameColor)
    updateCachedLabelColor(frame, "__nr_meta_color", frame.metaLabel, nameColor)

    if showValue then
        updateCachedText(frame, "__nr_value", frame.valueLabel, getValueText(cfg.value_text_mode, hp, maxHp, "hp"))
    end
    updateCachedVisible(frame, "__nr_value_visible", frame.valueLabel, showValue)
    updateCachedLabelColor(frame, "__nr_value_color", frame.valueLabel, nameColor)

    updateCachedText(frame, "__nr_status", frame.statusLabel, statusText)
    updateCachedVisible(frame, "__nr_status_visible", frame.statusLabel, showStatus)
    updateCachedLabelColor(frame, "__nr_status_color", frame.statusLabel, state.dead and DEAD_TEXT_COLOR or OFFLINE_TEXT_COLOR)

    updateCachedBarColor(frame, "__nr_hp_color", frame.hpBar, hpColor)
    updateCachedBarValue(frame, "__nr_hp_range", "__nr_hp_value", getBarValueTarget(frame.hpBar), maxHp, hp)
    if showMpBar then
        updateCachedBarColor(frame, "__nr_mp_color", frame.mpBar, mpColor)
        updateCachedBarValue(frame, "__nr_mp_range", "__nr_mp_value", getBarValueTarget(frame.mpBar), maxMp, mp)
    end

    updateCachedVisible(frame, "__nr_target_visible", frame.targetTint, cfg.show_target_highlight ~= false and targetMatch)
    updateCachedDrawableColor(
        frame,
        "__nr_target_color",
        frame.targetTint,
        TARGET_TINT_COLOR[1] / 255,
        TARGET_TINT_COLOR[2] / 255,
        TARGET_TINT_COLOR[3] / 255,
        TARGET_TINT_COLOR[4] / 255
    )

    updateCachedVisible(frame, "__nr_debuff_visible", frame.debuffBadge, showDebuff)
    if frame.debuffBadge ~= nil then
        local debuffColor = (cfg.prefer_dispel_alert ~= false and frame.__nr_has_dispellable_debuff == true)
            and DISPELLABLE_DEBUFF_BADGE_COLOR
            or DEBUFF_BADGE_COLOR
        updateCachedDrawableColor(
            frame,
            "__nr_debuff_color",
            frame.debuffBadge,
            debuffColor[1] / 255,
            debuffColor[2] / 255,
            debuffColor[3] / 255,
            debuffColor[4] / 255
        )
    end

    if frame.bg ~= nil then
        local bgAlpha = cfg.bg_enabled and percent01(cfg.bg_alpha_pct, 80) or 0
        updateCachedDrawableColor(frame, "__nr_bg_color", frame.bg, 0.05, 0.05, 0.06, bgAlpha)
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
    RaidFrames.current_target_id = nil
    RaidFrames.now_ms = 0
    RaidFrames.__nr_layout_applied = false
    RaidFrames.__nr_stock_hidden = false
    RaidFrames.__nr_stock_hide_ms = nil
end

return RaidFrames
