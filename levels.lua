-- ---------------------------------------------------------------------------
-- levels.lua — the level bank (levels_data.lua, built offline by tools/).
--
-- levels_data.lua returns one text: a band header per difficulty
-- ("# beginner 90") and one line per level: its optimal push count, a
-- solution in LURD notation that achieves it, and the map, rows joined by
-- "|". Each band is sorted by optimal pushes, so level 1 is the gentlest of
-- its band. Parsed once, on first use.
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

local Levels = {}

Levels.BANDS = { "beginner", "intermediate", "advanced", "expert" }
Levels.DEFAULT_BAND = "beginner"

local bank

local function splitRows(map)
    local rows = {}
    for row in (map .. "|"):gmatch("([^|]*)|") do rows[#rows + 1] = row end
    return rows
end
Levels.splitRows = splitRows

local function load()
    if bank then return bank end
    bank = {}
    for _, id in ipairs(Levels.BANDS) do bank[id] = {} end
    local chunk = loadfile(_dir .. "levels_data.lua")
    local ok, text = pcall(chunk or error)
    if not ok or type(text) ~= "string" then return bank end
    local band
    for line in text:gmatch("[^\n]+") do
        local b = line:match("^# (%a+)")
        if b then
            band = bank[b]
        elseif band then
            local n, sol, map = line:match("^(%d+) ([UDLRudlr]+) (.+)$")
            if n then
                band[#band + 1] = { optimal = tonumber(n), solution = sol, map = map }
            end
        end
    end
    return bank
end

function Levels.isBand(id)
    for _, b in ipairs(Levels.BANDS) do
        if b == id then return true end
    end
    return false
end

-- Number of levels in a band.
function Levels.count(band)
    local t = load()[band]
    return t and #t or 0
end

-- Level `index` of `band`: { rows, optimal, solution }, or nil.
function Levels.get(band, index)
    local t = load()[band]
    local lv = t and t[index]
    if not lv then return nil end
    if not lv.rows then lv.rows = splitRows(lv.map) end
    return lv
end

-- True once the bank is parsed (for tests).
function Levels.isLoaded()
    return bank ~= nil
end

-- Drops the parsed bank; the next call reads levels_data.lua again (~1-3 ms).
function Levels.release()
    bank = nil
end

return Levels
