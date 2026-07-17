local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = _dir .. "?.lua;" .. _dir .. "common/?.lua;" .. package.path

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local PluginBase    = require("plugin_base")
local _             = require("gettext")

require("i18n").extend(lrequire("i18n_fr"))
local SokobanScreen = lrequire("screen")

local Sokoban = PluginBase:extend{
    name      = "sokoban",
    menu_text = _("Sokoban"),
    menu_hint = "tools",
}

function Sokoban:createScreen()
    return SokobanScreen:new{ plugin = self }
end

return Sokoban
