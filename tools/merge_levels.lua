-- ---------------------------------------------------------------------------
-- merge_levels.lua — merges gen_levels.lua outputs into the level bank.
--
--   luajit tools/merge_levels.lua <cap per band> part1.txt part2.txt ...
--
-- Drops duplicates (a level and its rotations/mirror images count as one),
-- re-verifies every level independently of the generator:
--   * the stored LURD solution replays legally and solves the level with the
--     stated number of pushes;
--   * A* (../solver.lua, admissible + consistent heuristic, sound deadlock
--     pruning only) finds no solution with fewer pushes;
-- sorts each band by pushes and prints the body of levels_data.lua.
-- Bands by optimal pushes: beginner <= 12, intermediate 13-22,
-- advanced 23-32, expert >= 33.
-- ---------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = here .. "../?.lua;" .. package.path
local Solver = require("solver")

local CAP = tonumber(arg[1]) or 100

local function splitRows(map)
    local rows = {}
    for row in (map .. "|"):gmatch("([^|]*)|") do rows[#rows + 1] = row end
    return rows
end

-- Padded char grid for transforms.
local function grid(rows)
    local w = 0
    for _, r in ipairs(rows) do if #r > w then w = #r end end
    local g = {}
    for i, r in ipairs(rows) do
        g[i] = {}
        for c = 1, w do
            local ch = r:sub(c, c)
            g[i][c] = ch == "" and " " or ch
        end
    end
    return g, #rows, w
end

local function key(g, h, w, f)
    local out = {}
    local th, tw = f(nil, nil, h, w)
    for r = 1, th do
        local t = {}
        for c = 1, tw do
            local sr, sc = f(r, c, h, w)
            t[c] = g[sr][sc]
        end
        out[r] = table.concat(t)
    end
    return table.concat(out, "|")
end

local TRANSFORMS = {
    function(r, c, h, w) if not r then return h, w end return r, c end,
    function(r, c, h, w) if not r then return h, w end return r, w - c + 1 end,
    function(r, c, h, w) if not r then return h, w end return h - r + 1, c end,
    function(r, c, h, w) if not r then return h, w end return h - r + 1, w - c + 1 end,
    function(r, c, h, w) if not r then return w, h end return c, r end,
    function(r, c, h, w) if not r then return w, h end return h - c + 1, r end,
    function(r, c, h, w) if not r then return w, h end return c, w - r + 1 end,
    function(r, c, h, w) if not r then return w, h end return h - c + 1, w - r + 1 end,
}

-- Canonical form ignores the player's exact square (any square of the same
-- area is the same puzzle): blank it out before comparing.
local function canonical(rows)
    local g, h, w = grid(rows)
    for r = 1, h do
        for c = 1, w do
            if g[r][c] == "@" then g[r][c] = " " elseif g[r][c] == "+" then g[r][c] = "." end
        end
    end
    local best
    for _, f in ipairs(TRANSFORMS) do
        local k = key(g, h, w, f)
        if not best or k < best then best = k end
    end
    return best
end

local function band(p)
    if p <= 12 then return "beginner" elseif p <= 22 then return "intermediate"
    elseif p <= 32 then return "advanced" else return "expert" end
end

local bands = { beginner = {}, intermediate = {}, advanced = {}, expert = {} }
local seen = {}
local dupes, rejected = 0, 0
for i = 2, #arg do
    local f = assert(io.open(arg[i]))
    for line in f:lines() do
        local n, sol, map = line:match("^(%d+) ([UDLRudlr]+) (.+)$")
        if n then
            n = tonumber(n)
            local rows = splitRows(map)
            local ck = canonical(rows)
            if seen[ck] then
                dupes = dupes + 1
            else
                seen[ck] = true
                local ok, pushes = Solver.replay(rows, sol)
                local best = ok and pushes == n and select(2, Solver.solve(rows))
                if ok and pushes == n and best == n then
                    local t = bands[band(n)]
                    t[#t + 1] = { n = n, sol = sol, map = map, len = #sol }
                else
                    rejected = rejected + 1
                    io.stderr:write("REJECT ", line, " replay=", tostring(pushes), " astar=", tostring(best), "\n")
                end
            end
        end
    end
    f:close()
end

for _, id in ipairs({ "beginner", "intermediate", "advanced", "expert" }) do
    local t = bands[id]
    -- Deterministic order: by pushes, then solution length, then map.
    table.sort(t, function(a, b)
        if a.n ~= b.n then return a.n < b.n end
        if a.len ~= b.len then return a.len < b.len end
        return a.map < b.map
    end)
    -- Over the cap: keep an even spread across the band's push range.
    if #t > CAP then
        local kept = {}
        for k = 1, CAP do kept[k] = t[math.floor((k - 1) * #t / CAP) + 1] end
        t = kept
    end
    print("# " .. id .. " " .. #t)
    for _, lv in ipairs(t) do print(lv.n .. " " .. lv.sol .. " " .. lv.map) end
    io.stderr:write(string.format("%s: %d levels, pushes %d-%d\n", id, #t,
        t[1] and t[1].n or 0, t[#t] and t[#t].n or 0))
end
io.stderr:write(string.format("duplicates dropped: %d, rejected: %d\n", dupes, rejected))
