local api = require("api")
local Require = require("nuzi-core/require")

local Runtime = Require.Addon("nuzi-raid", "runtime")
local Helpers = Require.Addon("nuzi-raid", "raid_helpers")

local Team = {}

local trim = Helpers.Trim

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

function Team.GetTeamRoleKey(name)
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

function Team.SafeTeamPlayerIndex()
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

function Team.GetRaidPopupKind(frame)
    local clickedIndex = frame ~= nil and tonumber(frame.__raid_member_index or frame.memberIndex or frame.index) or nil
    local myIndex = Team.SafeTeamPlayerIndex()
    if clickedIndex ~= nil and myIndex ~= nil and clickedIndex == myIndex then
        return "player"
    end

    local playerName = Runtime ~= nil and Runtime.GetPlayerName ~= nil and trim(Runtime.GetPlayerName()) or ""
    if playerName ~= "" then
        local frameName = frame ~= nil and trim(frame.__raid_name or frame.name or "") or ""
        if frameName ~= "" and frameName == playerName then
            return "player"
        end

        local unit = frame ~= nil and trim(frame.__raid_unit or frame.target or frame.unit or "") or ""
        local unitName = Runtime ~= nil and Runtime.GetUnitName ~= nil and trim(Runtime.GetUnitName(unit)) or ""
        if unitName ~= "" and unitName == playerName then
            return "player"
        end
    end

    return "team"
end

return Team
