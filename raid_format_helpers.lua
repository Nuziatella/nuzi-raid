local Require = require("nuzi-core/require")

local Helpers = Require.Addon("nuzi-raid", "raid_helpers")
local UnitHelpers = Require.Addon("nuzi-raid", "raid_unit_helpers")

local Format = {}

local clamp = Helpers.Clamp
local trim = Helpers.Trim
local firstNumber = Helpers.FirstNumber
local truthyMatch = Helpers.TruthyMatch

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

function Format.GetRolePrefix(roleKey)
    if roleKey == "defender" then
        return "D "
    end
    if roleKey == "healer" then
        return "H "
    end
    if roleKey == "attacker" then
        return "A "
    end
    return ""
end

function Format.GetRoleBadge(roleKey, hideDps)
    if roleKey == "defender" then
        return "DEF"
    end
    if roleKey == "healer" then
        return "HEAL"
    end
    if roleKey == "attacker" and not hideDps then
        return "DPS"
    end
    return ""
end

function Format.GetClassBadge(className)
    local clean = trim(className)
    if clean == "" then
        return ""
    end
    if string.len(clean) <= 3 then
        return string.upper(clean)
    end
    return string.upper(string.sub(clean, 1, 3))
end

function Format.FormatName(name, maxChars)
    local text = trim(name)
    local limit = clamp(maxChars, 0, 64, 0)
    if limit ~= nil and limit > 0 and string.len(text) > limit then
        return string.sub(text, 1, limit)
    end
    return text
end

function Format.GetUnitState(info, modifier, hp, maxHp, offline)
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

function Format.GetValueText(mode, cur, max, kind)
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

function Format.MergeResourceValues(current, maximum, lastCurrent, lastMaximum)
    local mergedCurrent = firstNumber(current, lastCurrent)
    local mergedMaximum = firstNumber(maximum, lastMaximum)
    if UnitHelpers.HasUsableVitals(mergedCurrent, mergedMaximum) then
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

function Format.GetClassColor(className)
    local clean = trim(className)
    if clean == "" then
        return nil
    end
    local paletteIndex = (hashText(string.lower(clean)) % #CLASS_NAME_COLOR_PALETTE) + 1
    return CLASS_NAME_COLOR_PALETTE[paletteIndex]
end

return Format
