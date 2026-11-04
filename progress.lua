-- ---------------------------------------------------------------------------
-- progress.lua — which levels of each band are solved, and which of those
-- were solved in the fewest moves (the level's known optimum). Pure Lua.
--
-- Kept in the plugin settings as two strings per band, one "0"/"1" character
-- per level:
--   solved_<band>   solved at least once (the format since 1.0.0)
--   optimal_<band>  solved at least once in the optimum, with no hint
-- An optimal solve also marks the level solved. A later solve never clears a
-- mark, so a slower solve can't downgrade an optimal one. Saves from before
-- optimal_<band> existed read as "solved, none optimal".
--
-- The same file ships in trafficjam, klotski and sokoban (vendored, not in
-- game-common: three consumers with their own move metric).
-- ---------------------------------------------------------------------------

local Progress = {}
Progress.__index = Progress

-- Level-list marks: optimal outranks solved.
Progress.MARK_SOLVED  = "✓"
Progress.MARK_OPTIMAL = "★"

-- plugin: anything with getSetting(key, default) / saveSetting(key, value).
function Progress.new(plugin)
    return setmetatable({ plugin = plugin }, Progress)
end

function Progress:_map(kind, band)
    local s = self.plugin:getSetting(kind .. "_" .. band, "")
    return type(s) == "string" and s or ""
end

function Progress:_set(kind, band, index)
    local s = self:_map(kind, band)
    if s:sub(index, index) == "1" then return end
    if #s < index then s = s .. string.rep("0", index - #s) end
    s = s:sub(1, index - 1) .. "1" .. s:sub(index + 1)
    self.plugin:saveSetting(kind .. "_" .. band, s)
end

local function count(s)
    local _, n = s:gsub("1", "")
    return n
end

function Progress:isSolved(band, index)
    return self:_map("solved", band):sub(index, index) == "1"
end

function Progress:isOptimal(band, index)
    return self:_map("optimal", band):sub(index, index) == "1"
end

function Progress:solvedCount(band)
    return count(self:_map("solved", band))
end

function Progress:optimalCount(band)
    return count(self:_map("optimal", band))
end

-- Records a win of level `index` of `band`; `optimal` true when it was played
-- in the optimum without help. Only ever adds marks.
function Progress:record(band, index, optimal)
    if not band or not index or index < 1 then return end
    self:_set("solved", band, index)
    if optimal then self:_set("optimal", band, index) end
end

-- The level-list mark of a level: ★, ✓ or nil.
function Progress:mark(band, index)
    if self:isOptimal(band, index) then return Progress.MARK_OPTIMAL end
    if self:isSolved(band, index) then return Progress.MARK_SOLVED end
    return nil
end

return Progress
