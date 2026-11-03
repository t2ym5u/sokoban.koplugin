-- ---------------------------------------------------------------------------
-- hint_cost.lua — how hard the device hint search works (luajit).
--
--   luajit tools/hint_cost.lua [trials per level]
--
-- For every shipped level, plays a random part of the stored solution, then a
-- few random steps (pushes included), and runs the hint search from there
-- exactly as board.lua does (weight 2, HINT_BUDGET). Prints how often a hint
-- is found, the states expanded and the slowest search. The Kobo Aura runs
-- LuaJIT roughly 15-20x slower than a desktop, so the desktop worst case times
-- 20 must stay around a second.
-- ---------------------------------------------------------------------------
local here = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = here .. "../?.lua;" .. here .. "../common/?.lua;" .. package.path
local Levels = dofile(here .. "../levels.lua")
local Board  = dofile(here .. "../board.lua")
local Solver = dofile(here .. "../solver.lua")
local TRIALS = tonumber(arg[1]) or 5
math.randomseed(1)
local D = { u = { -1, 0 }, d = { 1, 0 }, l = { 0, -1 }, r = { 0, 1 } }
local keys = { "u", "d", "l", "r" }
local stats = { found = 0, dead = 0, budget = 0, n = 0, worst = 0, worst_exp = 0, sum_exp = 0 }
for _, band in ipairs(Levels.BANDS) do
    for i = 1, Levels.count(band) do
        local lv = Levels.get(band, i)
        for _ = 1, TRIALS do
            local b = Board:new{ rows = lv.rows, solution = lv.solution, optimal = lv.optimal }
            local k = math.random(0, #lv.solution - 1)
            for j = 1, k do
                local d = D[lv.solution:sub(j, j):lower()]
                b:move(d[1], d[2])
            end
            for _ = 1, math.random(0, 6) do
                local d = D[keys[math.random(4)]]
                b:move(d[1], d[2])
            end
            if not b:isWon() then
                local st = {}
                local t = os.clock()
                local m, why = Solver.solve(b:toRows(), { weight = 2, budget = Board.HINT_BUDGET, stats = st })
                local dt = os.clock() - t
                stats.n = stats.n + 1
                if m then stats.found = stats.found + 1 elseif why == "dead" then stats.dead = stats.dead + 1
                elseif why == "budget" then stats.budget = stats.budget + 1 end
                local e = st.expanded or 0
                stats.sum_exp = stats.sum_exp + e
                if dt > stats.worst then stats.worst = dt end
                if e > stats.worst_exp then stats.worst_exp = e end
            end
        end
    end
end
print(string.format("positions %d: hint found %d, dead %d, over budget %d (unsolvable or too far)",
    stats.n, stats.found, stats.dead, stats.budget))
print(string.format("states expanded: mean %.0f, max %d; slowest search %.3f s (desktop)",
    stats.sum_exp / math.max(stats.n, 1), stats.worst_exp, stats.worst))
