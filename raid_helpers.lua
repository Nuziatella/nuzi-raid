local api = require("api")
local Require = require("nuzi-core/require")

local Overlay = Require.Addon("nuzi-raid", "overlay_utils")

local Helpers = {}

function Helpers.Clamp(value, lo, hi, default)
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

function Helpers.Percent01(value, default)
    local pct = Helpers.Clamp(value, 0, 100, default or 100)
    return pct / 100
end

function Helpers.Trim(value)
    return (tostring(value or ""):gsub("^%s*(.-)%s*$", "%1"))
end

function Helpers.SafeShow(widget, show)
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

function Helpers.SafeSetAlpha(widget, alpha)
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

function Helpers.SafeSetText(widget, text)
    if widget == nil or widget.SetText == nil then
        return
    end
    pcall(function()
        widget:SetText(tostring(text or ""))
    end)
end

function Helpers.SafeApplyBarTexture(bar, style)
    if bar == nil or style == nil or bar.ApplyBarTexture == nil then
        return
    end
    pcall(function()
        bar:ApplyBarTexture(style)
    end)
end

function Helpers.SafeAssignWidgetField(widget, key, value)
    if widget == nil or key == nil then
        return
    end
    pcall(function()
        widget[key] = value
    end)
end

function Helpers.GetBarValueTarget(bar)
    if bar == nil then
        return nil
    end
    if bar.statusBar ~= nil then
        return bar.statusBar
    end
    return bar
end

function Helpers.SafeSetExtent(widget, width, height)
    if widget == nil or widget.SetExtent == nil then
        return
    end
    pcall(function()
        widget:SetExtent(width, height)
    end)
end

function Helpers.SafeSetHeight(widget, height)
    if widget == nil or widget.SetHeight == nil then
        return
    end
    pcall(function()
        widget:SetHeight(height)
    end)
end

function Helpers.SafeClickable(widget, clickable)
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

function Helpers.SafeAnchor(widget, point, target, targetPoint, x, y)
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

function Helpers.SafeSetColor(drawable, r, g, b, a)
    if drawable == nil or drawable.SetColor == nil then
        return
    end
    pcall(function()
        drawable:SetColor(r, g, b, a)
    end)
end

function Helpers.SafeSetTextColor(label, rgba)
    if label == nil or label.style == nil or label.style.SetColor == nil then
        return
    end
    local color = rgba or { 255, 255, 255, 255 }
    pcall(function()
        label.style:SetColor(
            Helpers.Clamp(color[1], 0, 255, 255) / 255,
            Helpers.Clamp(color[2], 0, 255, 255) / 255,
            Helpers.Clamp(color[3], 0, 255, 255) / 255,
            Helpers.Clamp(color[4], 0, 255, 255) / 255
        )
    end)
end

function Helpers.SafeSetFontSize(label, size)
    if label == nil or label.style == nil or label.style.SetFontSize == nil then
        return
    end
    pcall(function()
        label.style:SetFontSize(size)
    end)
end

function Helpers.SafeApplyBarColor(statusBar, rgba, afterRgba)
    if statusBar == nil or type(rgba) ~= "table" then
        return
    end
    local r = Helpers.Clamp(rgba[1], 0, 255, 255) / 255
    local g = Helpers.Clamp(rgba[2], 0, 255, 255) / 255
    local b = Helpers.Clamp(rgba[3], 0, 255, 255) / 255
    local a = Helpers.Clamp(rgba[4], 0, 255, 255) / 255
    local afterColor = type(afterRgba) == "table" and afterRgba or rgba
    local ar = Helpers.Clamp(afterColor[1], 0, 255, 255) / 255
    local ag = Helpers.Clamp(afterColor[2], 0, 255, 255) / 255
    local ab = Helpers.Clamp(afterColor[3], 0, 255, 255) / 255
    local aa = Helpers.Clamp(afterColor[4], 0, 255, 255) / 255
    local function applyColor(widget, cr, cg, cb, ca)
        if widget == nil then
            return
        end
        pcall(function()
            if widget.SetBarColor ~= nil then
                widget:SetBarColor(cr, cg, cb, ca)
            end
        end)
        pcall(function()
            if widget.SetColor ~= nil then
                widget:SetColor(cr, cg, cb, ca)
            end
        end)
    end
    pcall(function()
        applyColor(statusBar, r, g, b, a)
        if statusBar.statusBar ~= nil then
            applyColor(statusBar.statusBar, r, g, b, a)
        end
        if statusBar.statusBarAfterImage ~= nil then
            applyColor(statusBar.statusBarAfterImage, ar, ag, ab, aa)
        end
    end)
end

function Helpers.UpdateCachedText(owner, key, widget, value)
    local text = tostring(value or "")
    if owner[key] == text then
        return
    end
    owner[key] = text
    Helpers.SafeSetText(widget, text)
end

function Helpers.UpdateCachedVisible(owner, key, widget, visible)
    local want = visible and true or false
    if owner[key] == want then
        return
    end
    owner[key] = want
    Helpers.SafeShow(widget, want)
end

function Helpers.UpdateCachedAlpha(owner, key, widget, alpha)
    local value = tonumber(alpha) or 1
    if owner[key] == value then
        return
    end
    owner[key] = value
    Helpers.SafeSetAlpha(widget, value)
end

function Helpers.ColorKeyFromRgba(rgba)
    if type(rgba) ~= "table" then
        return ""
    end
    return tostring(rgba[1] or "") .. ","
        .. tostring(rgba[2] or "") .. ","
        .. tostring(rgba[3] or "") .. ","
        .. tostring(rgba[4] or "")
end

function Helpers.UpdateCachedLabelColor(owner, key, widget, rgba)
    local color = rgba or { 255, 255, 255, 255 }
    local colorKey = Helpers.ColorKeyFromRgba(color)
    if owner[key] == colorKey then
        return
    end
    owner[key] = colorKey
    Helpers.SafeSetTextColor(widget, color)
end

function Helpers.UpdateCachedBarColor(owner, key, bar, rgba, afterRgba)
    local color = rgba or { 255, 255, 255, 255 }
    local colorKey = Helpers.ColorKeyFromRgba(color) .. "|" .. Helpers.ColorKeyFromRgba(afterRgba or color)
    if owner[key] == colorKey then
        return
    end
    owner[key] = colorKey
    Helpers.SafeApplyBarColor(bar, color, afterRgba)
end

function Helpers.UpdateCachedDrawableColor(owner, key, drawable, r, g, b, a)
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
    Helpers.SafeSetColor(drawable, r, g, b, a)
end

function Helpers.UpdateCachedBarValue(owner, rangeKey, valueKey, bar, maxValue, currentValue)
    if bar == nil then
        return
    end
    local maxNum = math.max(0, tonumber(maxValue) or 0)
    local currentNum = Helpers.Clamp(currentValue, 0, maxNum, 0)
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

function Helpers.FirstNumber(a, b, c, d, e, f, g, h, i, j, k, l)
    local value = tonumber(a)
    if value ~= nil then
        return value
    end
    value = tonumber(b)
    if value ~= nil then
        return value
    end
    value = tonumber(c)
    if value ~= nil then
        return value
    end
    value = tonumber(d)
    if value ~= nil then
        return value
    end
    value = tonumber(e)
    if value ~= nil then
        return value
    end
    value = tonumber(f)
    if value ~= nil then
        return value
    end
    value = tonumber(g)
    if value ~= nil then
        return value
    end
    value = tonumber(h)
    if value ~= nil then
        return value
    end
    value = tonumber(i)
    if value ~= nil then
        return value
    end
    value = tonumber(j)
    if value ~= nil then
        return value
    end
    value = tonumber(k)
    if value ~= nil then
        return value
    end
    value = tonumber(l)
    if value ~= nil then
        return value
    end
    return nil
end

function Helpers.TruthyMatch(tbl, patterns, depth)
    if type(tbl) ~= "table" then
        return false
    end
    local remaining = Helpers.Clamp(depth, 0, 8, 1)
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
        if remaining > 0 and type(value) == "table" and Helpers.TruthyMatch(value, patterns, remaining - 1) then
            return true
        end
    end
    return false
end

function Helpers.IsRightClick(button)
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

return Helpers
