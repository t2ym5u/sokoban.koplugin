-- ---------------------------------------------------------------------------
-- gen_levels.lua — generates Sokoban levels, offline (luajit).
--
--   luajit tools/gen_levels.lua <count> <seed> [min_boxes max_boxes]
--
-- Prints one candidate per line: "<rows joined by |> <pushes> <moves>" where
-- <pushes> is the optimal number of pushes and <moves> a solution in LURD
-- notation that achieves it. tools/build_levels.sh merges several runs,
-- verifies every level with ../solver.lua and writes ../levels_data.lua.
--
-- Method (after Taylor & Parberry, "Procedural generation of Sokoban
-- levels", 2011):
--   1. carve a random room: an open rectangle with random wall cells and
--      short wall segments, keeping the largest connected floor area;
--   2. place the goals;
--   3. breadth-first search *backwards* from the solved position, pulling
--      boxes instead of pushing them, over the whole state space (rooms whose
--      space exceeds a cap are thrown away). The BFS depth of a state is its
--      exact minimum number of pushes to the solution;
--   4. keep the deepest state as the start, preferring the one that makes the
--      solver switch boxes most often (a long single-box shove is dull).
-- Every level is therefore solvable by construction and its push count is
-- optimal; verify_levels.lua re-proves both independently.
-- ---------------------------------------------------------------------------

local here = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = here .. "../?.lua;" .. package.path
local Solver = require("solver")

local COUNT     = tonumber(arg[1]) or 20
local SEED      = tonumber(arg[2]) or 1
local MIN_BOXES = tonumber(arg[3]) or 2
local MAX_BOXES = tonumber(arg[4]) or 5
local STATE_CAP = 250000

math.randomseed(SEED * 7919 + 17)

-- -- Room -------------------------------------------------------------------

local function carveRoom(iw, ih)
    -- grid[r][c] true = floor; interior r,c in 1..ih, 1..iw.
    local floor = {}
    for r = 1, ih do
        floor[r] = {}
        for c = 1, iw do floor[r][c] = true end
    end
    local area = iw * ih
    local walls = math.floor(area * (0.18 + math.random() * 0.14))
    local placed = 0
    while placed < walls do
        local r, c = math.random(ih), math.random(iw)
        local len = math.random() < 0.45 and math.random(2, 3) or 1
        local horiz = math.random() < 0.5
        for k = 0, len - 1 do
            local rr, cc = horiz and r or r + k, horiz and c + k or c
            if rr <= ih and cc <= iw and floor[rr][cc] then
                floor[rr][cc] = false
                placed = placed + 1
            end
        end
    end
    -- Keep the largest component.
    local comp, best, best_n = {}, nil, 0
    local id = 0
    for r = 1, ih do
        for c = 1, iw do
            if floor[r][c] and not comp[r * 100 + c] then
                id = id + 1
                local n, stack = 0, { { r, c } }
                comp[r * 100 + c] = id
                while #stack > 0 do
                    local p = table.remove(stack)
                    n = n + 1
                    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                        local nr, nc = p[1] + d[1], p[2] + d[2]
                        if nr >= 1 and nr <= ih and nc >= 1 and nc <= iw and floor[nr][nc]
                            and not comp[nr * 100 + nc] then
                            comp[nr * 100 + nc] = id
                            stack[#stack + 1] = { nr, nc }
                        end
                    end
                end
                if n > best_n then best, best_n = id, n end
            end
        end
    end
    for r = 1, ih do
        for c = 1, iw do
            if floor[r][c] and comp[r * 100 + c] ~= best then floor[r][c] = false end
        end
    end
    -- Fill dead-end pockets (floor with three wall sides): they only pad the
    -- room and give boxes nowhere to go.
    local changed = true
    while changed do
        changed = false
        for r = 1, ih do
            for c = 1, iw do
                if floor[r][c] then
                    local open = 0
                    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                        local nr, nc = r + d[1], c + d[2]
                        if nr >= 1 and nr <= ih and nc >= 1 and nc <= iw and floor[nr][nc] then
                            open = open + 1
                        end
                    end
                    if open <= 1 and math.random() < 0.8 then
                        floor[r][c] = false
                        best_n = best_n - 1
                        changed = true
                    end
                end
            end
        end
    end
    return floor, best_n
end

-- Room -> rows with a wall border; blank outside the walls.
local function roomRows(floor, iw, ih, marks)
    local rows = {}
    local function isFloor(r, c)
        return r >= 1 and r <= ih and c >= 1 and c <= iw and floor[r][c]
    end
    for r = 0, ih + 1 do
        local t = {}
        for c = 0, iw + 1 do
            local ch
            if isFloor(r, c) then
                ch = marks[r * 100 + c] or " "
            else
                local near = false
                for dr = -1, 1 do
                    for dc = -1, 1 do
                        if isFloor(r + dr, c + dc) then near = true end
                    end
                end
                ch = near and "#" or " "
            end
            t[#t + 1] = ch
        end
        rows[#rows + 1] = table.concat(t)
    end
    -- Trim blank rows/columns and trailing blanks.
    local function blank(s) return not s:find("[^ ]") end
    while #rows > 0 and blank(rows[1]) do table.remove(rows, 1) end
    while #rows > 0 and blank(rows[#rows]) do table.remove(rows) end
    local lead = math.huge
    for _, s in ipairs(rows) do
        local a = s:find("[^ ]")
        if a and a - 1 < lead then lead = a - 1 end
    end
    for i, s in ipairs(rows) do
        rows[i] = s:sub(lead + 1):gsub("%s+$", "")
    end
    return rows
end

-- -- Reverse search ------------------------------------------------------------

local function sortedCopy(t)
    local c = {}
    for i, v in ipairs(t) do c[i] = v end
    table.sort(c)
    return c
end

-- Exhaustive pull-BFS from every solved state. Returns the deepest states.
local function reverseSearch(L, goals)
    local dirs, wall = L.dirs, L.wall
    local info = {}   -- key -> { depth, boxes, pnorm, parent_key, push = {box, k} }
    local queue, head = {}, 1
    local count = 0

    local occ0 = {}
    for _, g in ipairs(goals) do occ0[g] = true end
    -- One solved state per player area.
    local done = {}
    for i = 1, L.w * L.h do
        if not wall[i] and not occ0[i] and not done[i] then
            local seen, minc = Solver.reach(L, occ0, i)
            for c in pairs(seen) do done[c] = true end
            local key = Solver.encode(goals, minc)
            if not info[key] then
                info[key] = { depth = 0, boxes = goals, pnorm = minc }
                queue[#queue + 1] = key
                count = count + 1
            end
        end
    end

    local max_depth = 0
    while head <= #queue do
        local key = queue[head]; head = head + 1
        local st = info[key]
        local occ = {}
        for _, b in ipairs(st.boxes) do occ[b] = true end
        local seen = Solver.reach(L, occ, st.pnorm)
        for bi, b in ipairs(st.boxes) do
            for k = 1, 4 do
                local d = dirs[k]
                -- Player at p = b - d pulls the box at b to p, stepping to p - d.
                local p = b - d
                local p2 = p - d
                if seen[p] and not wall[p2] and not occ[p2] then
                    local nb = {}
                    for j, x in ipairs(st.boxes) do nb[j] = x end
                    nb[bi] = p
                    occ[b] = nil; occ[p] = true
                    local _s, nmin = Solver.reach(L, occ, p2)
                    occ[p] = nil; occ[b] = true
                    local nkey = Solver.encode(nb, nmin)
                    if not info[nkey] then
                        -- Forward: the player at p2 pushes the box at p in
                        -- direction d (k), back onto b.
                        info[nkey] = { depth = st.depth + 1, boxes = sortedCopy(nb), pnorm = nmin,
                                       parent = key, push = { p, k }, player = p2 }
                        queue[#queue + 1] = nkey
                        count = count + 1
                        if st.depth + 1 > max_depth then max_depth = st.depth + 1 end
                        if count > STATE_CAP then return nil end
                    end
                end
            end
        end
    end
    local deepest = {}
    for k, st in pairs(info) do
        if st.depth == max_depth then deepest[#deepest + 1] = k end
    end
    table.sort(deepest)
    return info, deepest, max_depth, count
end

-- -- Main ----------------------------------------------------------------------

-- One goal placement in a room: returns a candidate table or nil.
local function floorCells(floor, iw, ih)
    local cells = {}
    for r = 1, ih do
        for c = 1, iw do
            if floor[r][c] then cells[#cells + 1] = r * 100 + c end
        end
    end
    return cells
end

local function tryGoals(floor, iw, ih, goalcells)
    local marks, used = {}, {}
    for _, g in ipairs(goalcells) do marks[g] = "."; used[g] = true end
    -- Solver.parse needs a player to find the inside; any other floor cell.
    for _, c in ipairs(floorCells(floor, iw, ih)) do
        if not used[c] then marks[c] = "@"; break end
    end
    local rows = roomRows(floor, iw, ih, marks)
    local L = Solver.parse(rows)
    local goals = {}
    for i = 1, L.w * L.h do
        if L.goal[i] and not L.wall[i] then goals[#goals + 1] = i end
    end
    -- One connected room with every goal in it (a wall mutation can split it).
    local inside = 0
    for i = 1, L.w * L.h do if not L.wall[i] then inside = inside + 1 end end
    if #goals ~= #goalcells or inside ~= #floorCells(floor, iw, ih) then return nil end
    local info, deepest, depth = reverseSearch(L, goals)
    if not info then return nil end
    -- The deepest state with no box already home and the most box switches.
    local best_key, best_sw
    for _, key in ipairs(deepest) do
        local st = info[key]
        local home = false
        for _, b in ipairs(st.boxes) do if L.goal[b] then home = true end end
        if not home then
            local occ = {}
            for i, b in ipairs(st.boxes) do occ[b] = i end
            local cur, switches, prev = st, 0, nil
            while cur.parent do
                local b, k = cur.push[1], cur.push[2]
                local id = occ[b]
                if id ~= prev then switches = switches + 1 end
                prev = id
                occ[b] = nil
                occ[b + L.dirs[k]] = id
                cur = info[cur.parent]
            end
            if not best_sw or switches > best_sw then best_key, best_sw = key, switches end
        end
    end
    if not best_key then return nil end
    return { L = L, rows = rows, info = info, key = best_key, depth = depth, switches = best_sw }
end

-- Candidate -> "map", moves.
local function render(cand)
    local L, rows, info = cand.L, cand.rows, cand.info
    local st = info[cand.key]
    local occ, isbox = {}, {}
    for _, b in ipairs(st.boxes) do occ[b] = true; isbox[b] = true end
    local area = {}
    for c in pairs(Solver.reach(L, occ, st.pnorm)) do area[#area + 1] = c end
    table.sort(area)
    local player = area[math.random(#area)]
    local moves, p = {}, player
    local cur = st
    while cur.parent do
        local b, k = cur.push[1], cur.push[2]
        local d = L.dirs[k]
        local w = Solver.walk(L, occ, p, b - d)
        if not w then return nil end
        moves[#moves + 1] = w .. Solver.DIR_CHARS[k]:upper()
        occ[b] = nil; occ[b + d] = true
        p = b
        cur = info[cur.parent]
    end
    local out = {}
    for r = 2, L.h - 1 do
        local t = {}
        local src = rows[r - 1] or ""
        for c = 2, L.w - 1 do
            local i = (r - 1) * L.w + c
            local ch = src:sub(c - 1, c - 1)
            if ch == "" then ch = " " end
            if not L.wall[i] then
                if isbox[i] then ch = L.goal[i] and "*" or "$"
                elseif i == player then ch = L.goal[i] and "+" or "@"
                else ch = L.goal[i] and "." or " " end
            end
            t[#t + 1] = ch
        end
        out[#out + 1] = (table.concat(t):gsub("%s+$", ""))
    end
    return table.concat(out, "|"), table.concat(moves)
end

local MIN_DEPTH = tonumber(arg[5]) or 4
local MAX_DEPTH = tonumber(arg[6]) or math.huge
local PLACEMENTS = tonumber(arg[7]) or 25
local WALL_MUTATION = tonumber(arg[8]) or 0.4

local out, tries = 0, 0
local seen_maps = {}
while out < COUNT do
    tries = tries + 1
    local nboxes = math.random(MIN_BOXES, MAX_BOXES)
    local iw = math.random(5, 9)
    local ih = math.random(5, 8)
    local floor, nfloor = carveRoom(iw, ih)
    local min_floor = 3 * nboxes + 6
    local max_floor = ({ 34, 32, 30, 28, 26, 24 })[nboxes] or 24
    if nfloor >= min_floor and nfloor <= max_floor then
        -- Hill-climb on the goal placement: move one goal at a time and keep
        -- the change when the puzzle gets no shallower.
        local cells = floorCells(floor, iw, ih)
        local goals = {}
        local pool = {}
        for i, c in ipairs(cells) do pool[i] = c end
        for i = 1, nboxes do goals[i] = table.remove(pool, math.random(#pool)) end
        local function score(c) return c and c.depth <= MAX_DEPTH and (c.depth * 4 + c.switches) or -1 end
        local best = tryGoals(floor, iw, ih, goals)
        local best_s = score(best)
        for _ = 1, PLACEMENTS do
            if math.random() < WALL_MUTATION then
                -- Toggle one interior cell that isn't a goal.
                local r, c = math.random(ih), math.random(iw)
                local id = r * 100 + c
                local is_goal = false
                for _, g in ipairs(goals) do if g == id then is_goal = true end end
                if not is_goal then
                    floor[r][c] = not floor[r][c]
                    local cand = tryGoals(floor, iw, ih, goals)
                    local s2 = score(cand)
                    if s2 >= best_s then
                        best, best_s = cand, s2
                        -- keep the goal pool in step with the floor
                        pool = {}
                        local used = {}
                        for _, g in ipairs(goals) do used[g] = true end
                        for _, cell in ipairs(floorCells(floor, iw, ih)) do
                            if not used[cell] then pool[#pool + 1] = cell end
                        end
                    else
                        floor[r][c] = not floor[r][c]
                    end
                end
            else
                local i = math.random(nboxes)
                local j = math.random(#pool)
                goals[i], pool[j] = pool[j], goals[i]
                local cand = tryGoals(floor, iw, ih, goals)
                local s2 = score(cand)
                if s2 >= best_s then
                    best, best_s = cand, s2
                else
                    goals[i], pool[j] = pool[j], goals[i]
                end
            end
        end
        if best_s < 0 then best = nil end
        if best and best.depth >= MIN_DEPTH then
            local map, mv = render(best)
            if map and not seen_maps[map] then
                seen_maps[map] = true
                -- Map last: its rows may start with blanks.
                io.write(best.depth, " ", mv, " ", map, "\n")
                io.flush()
                out = out + 1
                io.stderr:write(string.format("[%d] %d boxes, %d pushes, %d switches (try %d)\n",
                    out, nboxes, best.depth, best.switches, tries))
            end
        end
    end
end
