local api = require("api")
local Require = require("nuzi-core/require")

local Runtime = Require.Addon("nuzi-raid", "runtime")
local Helpers = Require.Addon("nuzi-raid", "raid_helpers")

local Unit = {}

local trim = Helpers.Trim
local clamp = Helpers.Clamp
local firstNumber = Helpers.FirstNumber
local truthyMatch = Helpers.TruthyMatch

local function callApiUnit(methodName, unit)
    if api.Unit == nil or type(api.Unit[methodName]) ~= "function" then
        return nil
    end

    local ok, value = pcall(function()
        return api.Unit[methodName](api.Unit, unit)
    end)
    if ok then
        return value
    end

    ok, value = pcall(function()
        return api.Unit[methodName](unit)
    end)
    if ok then
        return value
    end
    return nil
end

function Unit.SafeUnitInfo(unit)
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

function Unit.SafeUnitInfoById(unitId)
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

function Unit.ExtractVitalsFromInfo(info)
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

function Unit.HasUsableVitals(current, maximum)
    return type(current) == "number" and current >= 0 and type(maximum) == "number" and maximum > 0
end

function Unit.SafeUnitModifierInfo(unit)
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

function Unit.SafeUnitClassName(unit, info)
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

function Unit.SafeUnitName(unit, info, unitId)
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

function Unit.SafeUnitId(unit)
    local unitId = Runtime ~= nil and Runtime.GetUnitId(unit) or nil
    if unitId == nil then
        return nil
    end
    return tonumber(unitId) or unitId
end

function Unit.SafeUnitHealth(unit, unitId, includeMana)
    if api.Unit == nil then
        return nil, nil, nil, nil
    end
    includeMana = includeMana ~= false
    local hp = firstNumber(callApiUnit("UnitHealth", unit))
    local maxHp = firstNumber(callApiUnit("UnitMaxHealth", unit))
    local mp = nil
    local maxMp = nil
    if includeMana then
        mp = firstNumber(callApiUnit("UnitMana", unit))
        maxMp = firstNumber(callApiUnit("UnitMaxMana", unit))
    end

    if hp == nil or maxHp == nil or (includeMana and (mp == nil or maxMp == nil)) then
        local info = Unit.SafeUnitInfo(unit)
        local infoHp, infoMaxHp, infoMp, infoMaxMp = Unit.ExtractVitalsFromInfo(info)
        hp = firstNumber(hp, infoHp)
        maxHp = firstNumber(maxHp, infoMaxHp)
        if includeMana then
            mp = firstNumber(mp, infoMp)
            maxMp = firstNumber(maxMp, infoMaxMp)
        end
    end

    if hp == nil or maxHp == nil or (includeMana and (mp == nil or maxMp == nil)) then
        local byIdInfo = Unit.SafeUnitInfoById(unitId)
        local idHp, idMaxHp, idMp, idMaxMp = Unit.ExtractVitalsFromInfo(byIdInfo)
        hp = firstNumber(hp, idHp)
        maxHp = firstNumber(maxHp, idMaxHp)
        if includeMana then
            mp = firstNumber(mp, idMp)
            maxMp = firstNumber(maxMp, idMaxMp)
        end
    end

    return tonumber(hp), tonumber(maxHp), tonumber(mp), tonumber(maxMp)
end

function Unit.SafeUnitDistance(unit)
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

function Unit.SafeUnitOffline(unit)
    if api.Unit == nil or api.Unit.UnitIsOffline == nil then
        return false
    end
    local ok, offline = pcall(function()
        return api.Unit:UnitIsOffline(unit)
    end)
    return ok and offline and true or false
end

function Unit.SafeUnitTeamAuthority(unit)
    local authority = callApiUnit("UnitTeamAuthority", unit)
    authority = trim(authority)
    if authority == "" or authority == "looting" then
        return nil
    end
    return authority
end

function Unit.SafeDebuffCount(unit)
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

function Unit.SafeDebuffInfo(unit, index)
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

function Unit.HasDispellableDebuff(unit, count)
    local total = clamp(count, 0, 40, 0)
    for index = 1, total do
        local info = Unit.SafeDebuffInfo(unit, index)
        if truthyMatch(info, { "dispel", "dispell", "cleanse", "purge", "remove", "cure", "removable" }, 2) then
            return true
        end
    end
    return false
end

return Unit
