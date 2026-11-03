-- ---------------------------------------------------------------------------
-- solver.lua — Sokoban push-level search. Pure Lua (5.1 / LuaJIT), no UI.
--
-- Used twice:
--   * on the device, for the Hint button when the player has left the stored
--     solution (bounded by a node budget, so it gives up rather than hang a
--     Kobo);
--   * by tools/verify_levels.lua, which proves every shipped level solvable
--     and checks its stored push count is optimal (A* with an admissible
--     heuristic, no budget).
--
-- A position is a list of rows in the usual XSB text format:
--   '#' wall, ' ' floor, '.' goal, '$' box, '*' box on goal,
--   '@' player, '+' player on goal.
-- A solution is a LURD string: lower case = a step, upper case = a push.
-- ---------------------------------------------------------------------------

local Solver = {}

local DIR_CHARS = { "u", "d", "l", "r" }

-- Parses rows into a flat level: w, h, wall[i], goal[i], boxes {i...}, player.
-- Cells are numbered row by row from 1; anything outside the rows is wall.
function Solver.parse(rows)
    local h, w = #rows, 0
    for _, row in ipairs(rows) do
        if #row > w then w = #row end
    end
    -- One cell of wall all round, so neighbours never fall off the grid.
    w, h = w + 2, h + 2
    local L = { w = w, h = h, wall = {}, goal = {}, boxes = {}, player = nil }
    for i = 1, w * h do L.wall[i] = true end
    for r, row in ipairs(rows) do
        for c = 1, #row do
            local ch = row:sub(c, c)
            local i = r * w + c + 1
            if ch ~= "#" then L.wall[i] = false end
            if ch == "." or ch == "*" or ch == "+" then L.goal[i] = true end
            if ch == "$" or ch == "*" then L.boxes[#L.boxes + 1] = i end
            if ch == "@" or ch == "+" then L.player = i end
        end
    end
    L.dirs = { -w, w, -1, 1 }
    -- Floor reachable from the player (boxes ignored): the inside of the
    -- level. Blank cells outside the walls are not floor.
    local inside = {}
    if L.player then
        local stack = { L.player }
        inside[L.player] = true
        while #stack > 0 do
            local p = table.remove(stack)
            for k = 1, 4 do
                local q = p + L.dirs[k]
                if not L.wall[q] and not inside[q] then
                    inside[q] = true
                    stack[#stack + 1] = q
                end
            end
        end
    end
    for i = 1, w * h do
        if not inside[i] then L.wall[i] = true end
    end
    return L
end

-- Push distance from every cell to the nearest goal for a lone box (other
-- boxes ignored): math.huge on "dead" cells, from which no goal is reachable.
-- A lower bound on the pushes that box still needs.
function Solver.goalDistances(L)
    local dist = {}
    local n = L.w * L.h
    for i = 1, n do dist[i] = math.huge end
    local queue, head = {}, 1
    for i = 1, n do
        if L.goal[i] and not L.wall[i] then
            dist[i] = 0
            queue[#queue + 1] = i
        end
    end
    -- Reverse push: a box reaches y from x = y - d if the player could stand
    -- on x - d.
    while head <= #queue do
        local y = queue[head]; head = head + 1
        for k = 1, 4 do
            local d = L.dirs[k]
            local x = y - d
            if not L.wall[x] and not L.wall[x - d] and dist[x] == math.huge then
                dist[x] = dist[y] + 1
                queue[#queue + 1] = x
            end
        end
    end
    return dist
end

-- Box list -> occupancy set.
local function boxSet(boxes)
    local s = {}
    for _, b in ipairs(boxes) do s[b] = true end
    return s
end

-- Flood fill of the player's area. Returns the visited set and its smallest
-- cell (the normalised player position: all cells of one area are the same
-- push-level state).
local function reach(L, occ, from)
    local seen = { [from] = true }
    local stack = { from }
    local minc = from
    local dirs, wall = L.dirs, L.wall
    while #stack > 0 do
        local p = stack[#stack]
        stack[#stack] = nil
        for k = 1, 4 do
            local q = p + dirs[k]
            if not wall[q] and not occ[q] and not seen[q] then
                seen[q] = true
                if q < minc then minc = q end
                stack[#stack + 1] = q
            end
        end
    end
    return seen, minc
end
Solver.reach = reach

local function encode(boxes, pnorm)
    local t = {}
    for k, b in ipairs(boxes) do t[k] = b end
    table.sort(t)
    t[#t + 1] = pnorm
    return table.concat(t, ",")
end
Solver.encode = encode

-- A box that cannot move any more and is not on a goal: the 2x2 squares
-- around a freshly pushed box made only of walls and boxes, one of which is
-- off goal.
local function frozenSquare(L, occ, b)
    local w, wall, goal = L.w, L.wall, L.goal
    local squares = { { b, b + 1, b + w, b + w + 1 }, { b, b - 1, b + w, b + w - 1 },
                      { b, b + 1, b - w, b - w + 1 }, { b, b - 1, b - w, b - w - 1 } }
    for _, sq in ipairs(squares) do
        local blocked, off = true, false
        for _, c in ipairs(sq) do
            if wall[c] then
                -- fine
            elseif occ[c] then
                if not goal[c] then off = true end
            else
                blocked = false
                break
            end
        end
        if blocked and off then return true end
    end
    return false
end

local function heuristic(boxes, gdist)
    local h = 0
    for _, b in ipairs(boxes) do h = h + gdist[b] end
    return h
end

local function isSolved(L, boxes)
    for _, b in ipairs(boxes) do
        if not L.goal[b] then return false end
    end
    return true
end

-- Shortest walk (as "udlr" letters) from a to b avoiding walls and boxes.
local function walk(L, occ, a, b)
    if a == b then return "" end
    local prev = { [a] = 0 }
    local queue, head = { a }, 1
    while head <= #queue do
        local p = queue[head]; head = head + 1
        for k = 1, 4 do
            local q = p + L.dirs[k]
            if not L.wall[q] and not occ[q] and prev[q] == nil then
                prev[q] = p * 4 + (k - 1)
                if q == b then
                    local out = {}
                    local c = q
                    while c ~= a do
                        local code = prev[c]
                        out[#out + 1] = DIR_CHARS[code % 4 + 1]
                        c = math.floor(code / 4)
                    end
                    -- reverse
                    local n = #out
                    for i = 1, math.floor(n / 2) do out[i], out[n - i + 1] = out[n - i + 1], out[i] end
                    return table.concat(out)
                end
                queue[#queue + 1] = q
            end
        end
    end
    return nil
end
Solver.walk = walk

-- Binary heap on (f, h, seq).
local function heapPush(heap, node)
    heap[#heap + 1] = node
    local i = #heap
    while i > 1 do
        local p = math.floor(i / 2)
        local a, b = heap[i], heap[p]
        if a.f < b.f or (a.f == b.f and a.g > b.g) then
            heap[i], heap[p] = b, a
            i = p
        else
            break
        end
    end
end

local function heapPop(heap)
    local top = heap[1]
    local last = heap[#heap]
    heap[#heap] = nil
    local n = #heap
    if n > 0 then
        heap[1] = last
        local i = 1
        while true do
            local l, r, m = 2 * i, 2 * i + 1, i
            if l <= n and (heap[l].f < heap[m].f or (heap[l].f == heap[m].f and heap[l].g > heap[m].g)) then m = l end
            if r <= n and (heap[r].f < heap[m].f or (heap[r].f == heap[m].f and heap[r].g > heap[m].g)) then m = r end
            if m == i then break end
            heap[i], heap[m] = heap[m], heap[i]
            i = m
        end
    end
    return top
end

-- Turns a chain of pushes into a LURD string, walking between them.
local function movesFromPushes(L, boxes, player, pushes)
    local occ = boxSet(boxes)
    local out = {}
    for _, push in ipairs(pushes) do
        local b, k = push[1], push[2]
        local d = L.dirs[k]
        local w = walk(L, occ, player, b - d)
        if not w then return nil end
        out[#out + 1] = w
        out[#out + 1] = DIR_CHARS[k]:upper()
        occ[b] = nil
        occ[b + d] = true
        player = b
    end
    return table.concat(out)
end

-- Solves a position. opts:
--   budget  -- max states expanded (default: none)
--   weight  -- heuristic weight; 1 (default) is A*, optimal in pushes;
--              larger is faster and not optimal (the device hint uses 2)
-- Returns moves (LURD string), pushes  -- or nil, reason
-- ("solved", "dead", "budget", "unsolvable", "invalid").
function Solver.solve(rows, opts)
    opts = opts or {}
    local L = type(rows[1]) == "string" and Solver.parse(rows) or rows
    if not L.player or #L.boxes == 0 then return nil, "invalid" end
    local ngoals = 0
    for i = 1, L.w * L.h do if L.goal[i] and not L.wall[i] then ngoals = ngoals + 1 end end
    if ngoals < #L.boxes then return nil, "invalid" end
    if isSolved(L, L.boxes) then return "", 0 end
    local gdist = Solver.goalDistances(L)
    local weight = opts.weight or 1
    local budget = opts.budget or math.huge

    local start_occ = boxSet(L.boxes)
    for _, b in ipairs(L.boxes) do
        if gdist[b] == math.huge then return nil, "dead" end
        if frozenSquare(L, start_occ, b) then return nil, "dead" end
    end

    local _, pn = reach(L, start_occ, L.player)
    local h0 = heuristic(L.boxes, gdist)
    local root = { boxes = L.boxes, player = L.player, g = 0, f = weight * h0, parent = nil }
    local closed = {}
    local best_g = { [encode(L.boxes, pn)] = 0 }
    local heap = { root }
    local expanded = 0
    local dirs = L.dirs

    while #heap > 0 do
        local node = heapPop(heap)
        local boxes = node.boxes
        local occ = boxSet(boxes)
        local seen, minc = reach(L, occ, node.player)
        local key = encode(boxes, minc)
        if not closed[key] then
            closed[key] = true
            if isSolved(L, boxes) then
                local pushes = {}
                local n = node
                while n.parent do
                    table.insert(pushes, 1, n.push)
                    n = n.parent
                end
                local moves = movesFromPushes(L, L.boxes, L.player, pushes)
                if opts.stats then opts.stats.expanded = expanded end
                return moves, #pushes
            end
            expanded = expanded + 1
            if expanded > budget then
                if opts.stats then opts.stats.expanded = expanded end
                return nil, "budget"
            end
            for bi, b in ipairs(boxes) do
                for k = 1, 4 do
                    local d = dirs[k]
                    local to = b + d
                    if seen[b - d] and not L.wall[to] and not occ[to] and gdist[to] ~= math.huge then
                        local nb = {}
                        for j, x in ipairs(boxes) do nb[j] = x end
                        nb[bi] = to
                        occ[b] = nil; occ[to] = true
                        local frozen = frozenSquare(L, occ, to)
                        local nkey
                        if not frozen then
                            local _s, nmin = reach(L, occ, b)
                            nkey = encode(nb, nmin)
                        end
                        occ[to] = nil; occ[b] = true
                        if not frozen and not closed[nkey] then
                            local g = node.g + 1
                            if not best_g[nkey] or g < best_g[nkey] then
                                best_g[nkey] = g
                                heapPush(heap, {
                                    boxes = nb, player = b, g = g,
                                    f = g + weight * heuristic(nb, gdist),
                                    parent = node, push = { b, k },
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    return nil, "unsolvable"
end

-- Replays a LURD string on rows. Returns true if every move is legal and the
-- level ends solved, plus the push count; or false and a reason.
function Solver.replay(rows, moves)
    local L = Solver.parse(rows)
    local occ = boxSet(L.boxes)
    local p = L.player
    local pushes = 0
    local idx = { u = 1, d = 2, l = 3, r = 4 }
    for i = 1, #moves do
        local ch = moves:sub(i, i)
        local k = idx[ch:lower()]
        if not k then return false, "bad char" end
        local d = L.dirs[k]
        local q = p + d
        if L.wall[q] then return false, "wall at " .. i end
        local is_push = ch:upper() == ch
        if occ[q] then
            if not is_push then return false, "unmarked push at " .. i end
            if L.wall[q + d] or occ[q + d] then return false, "blocked push at " .. i end
            occ[q] = nil; occ[q + d] = true
            pushes = pushes + 1
        elseif is_push then
            return false, "push of nothing at " .. i
        end
        p = q
    end
    for b in pairs(occ) do
        if not L.goal[b] then return false, "not solved" end
    end
    return true, pushes
end

Solver.DIR_CHARS = DIR_CHARS
Solver.isSolved = isSolved
Solver.frozenSquare = frozenSquare

return Solver
