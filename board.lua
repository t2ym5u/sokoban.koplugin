-- ---------------------------------------------------------------------------
-- board.lua — one Sokoban level in play. Pure Lua, no UI.
--
-- Holds the grid, the moves made (a LURD string, which is also the save and
-- the undo history), hints and the step-through solution.
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Solver = lrequire("solver")

-- Cell types
local CELL_WALL   = "#"
local CELL_FLOOR  = " "
local CELL_TARGET = "."
local CELL_BOX    = "$"
local CELL_BOX_T  = "*"  -- box on target
local CELL_PLAYER = "@"
local CELL_PLAY_T = "+"  -- player on target

-- Hint search budget (push states expanded). From a level's start the stored
-- solution is used, so the search only runs once the player has left it.
-- tools/hint_cost.lua (1846 random mid-game positions): a hint is found in
-- 99% of the solvable ones, the slowest search takes 0.11 s on a desktop,
-- i.e. about 2 s on a Kobo Aura at worst.
local HINT_BUDGET = 3000

local DIRS = { u = { -1, 0 }, d = { 1, 0 }, l = { 0, -1 }, r = { 0, 1 } }

local function dirChar(dr, dc)
    if dr == -1 then return "u" elseif dr == 1 then return "d"
    elseif dc == -1 then return "l" else return "r" end
end

local function isBox(ch)
    return ch == CELL_BOX or ch == CELL_BOX_T
end

local function isTarget(ch)
    return ch == CELL_TARGET or ch == CELL_BOX_T or ch == CELL_PLAY_T
end

-- ---------------------------------------------------------------------------
-- SokobanBoard
-- ---------------------------------------------------------------------------

local SokobanBoard = {}
SokobanBoard.__index = SokobanBoard

function SokobanBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        grid       = {},
        rows       = 0,
        cols       = 0,
        player_r   = 1,
        player_c   = 1,
        moves      = 0,
        pushes     = 0,
        won        = false,
        history    = {},    -- one LURD char per move made
        hints_used = 0,
    }, self)
    if opts.rows then obj:setLevel(opts.rows, opts) end
    return obj
end

-- Starts a level. meta: band, index, daily (a date string or nil), optimal
-- (fewest pushes), solution (LURD string).
function SokobanBoard:setLevel(rows, meta)
    meta = meta or {}
    self.start_rows = rows
    self.band       = meta.band
    self.index      = meta.index
    self.daily      = meta.daily
    self.optimal    = meta.optimal
    self.stored_solution = meta.solution
    self.hints_used = 0
    self:_reset()
end

function SokobanBoard:_reset()
    local raw = self.start_rows or {}
    local max_cols = 0
    for _, row in ipairs(raw) do
        if #row > max_cols then max_cols = #row end
    end
    local grid = {}
    local pr, pc = 1, 1
    for r = 1, #raw do
        grid[r] = {}
        for c = 1, max_cols do
            local ch = raw[r]:sub(c, c)
            if ch == "" then ch = " " end
            grid[r][c] = ch
            if ch == CELL_PLAYER or ch == CELL_PLAY_T then pr, pc = r, c end
        end
    end
    self.grid     = grid
    self.rows     = #raw
    self.cols     = max_cols
    self.player_r = pr
    self.player_c = pc
    self.moves    = 0
    self.pushes   = 0
    self.won      = false
    self.history  = {}
    self.solution = nil
    self.sol_step = nil
    self.hint_box = nil
    self._plan    = nil
end

function SokobanBoard:getCell(r, c)
    if r < 1 or r > self.rows or c < 1 or c > self.cols then return CELL_WALL end
    return self.grid[r][c]
end

function SokobanBoard:isWon() return self.won end

function SokobanBoard:isShowingSolution() return self.solution ~= nil end

function SokobanBoard:canUndo()
    return #self.history > 0 and not self.won and not self.solution
end

-- The current position as XSB rows.
function SokobanBoard:toRows()
    local out = {}
    for r = 1, self.rows do out[r] = table.concat(self.grid[r]) end
    return out
end

-- Boxes and player, for comparing positions.
function SokobanBoard:stateKey()
    local t = {}
    for r = 1, self.rows do
        for c = 1, self.cols do
            if isBox(self.grid[r][c]) then t[#t + 1] = r * 1000 + c end
        end
    end
    t[#t + 1] = self.player_r * 1000 + self.player_c
    return table.concat(t, ",")
end

-- The low-level step: no game-state checks. Returns "push", "step" or nil.
function SokobanBoard:_step(dr, dc)
    local pr, pc = self.player_r, self.player_c
    local nr, nc = pr + dr, pc + dc
    local dest = self:getCell(nr, nc)
    if dest == CELL_WALL then return nil end
    local kind = "step"
    if isBox(dest) then
        local br, bc = nr + dr, nc + dc
        local behind = self:getCell(br, bc)
        if behind == CELL_WALL or isBox(behind) then return nil end
        self.grid[br][bc] = isTarget(behind) and CELL_BOX_T or CELL_BOX
        self.pushes = self.pushes + 1
        kind = "push"
    end
    self.grid[nr][nc] = isTarget(dest) and CELL_PLAY_T or CELL_PLAYER
    self.grid[pr][pc] = isTarget(self.grid[pr][pc]) and CELL_TARGET or CELL_FLOOR
    self.player_r, self.player_c = nr, nc
    self.moves = self.moves + 1
    local ch = dirChar(dr, dc)
    self.history[#self.history + 1] = kind == "push" and ch:upper() or ch
    self:_checkWin()
    return kind
end

-- Takes back the last step. Returns true if there was one.
function SokobanBoard:_unstep()
    local ch = table.remove(self.history)
    if not ch then return false end
    local d = DIRS[ch:lower()]
    local dr, dc = d[1], d[2]
    local pr, pc = self.player_r, self.player_c
    local or_, oc = pr - dr, pc - dc
    self.grid[or_][oc] = isTarget(self.grid[or_][oc]) and CELL_PLAY_T or CELL_PLAYER
    if ch ~= ch:lower() then
        -- The box went from (pr, pc) to (pr + dr, pc + dc): bring it back.
        local br, bc = pr + dr, pc + dc
        self.grid[br][bc] = isTarget(self.grid[br][bc]) and CELL_TARGET or CELL_FLOOR
        self.grid[pr][pc] = isTarget(self.grid[pr][pc]) and CELL_BOX_T or CELL_BOX
        self.pushes = self.pushes - 1
    else
        self.grid[pr][pc] = isTarget(self.grid[pr][pc]) and CELL_TARGET or CELL_FLOOR
    end
    self.player_r, self.player_c = or_, oc
    self.moves = self.moves - 1
    self.won = false
    return true
end

-- Move player in direction (dr, dc). Returns true if a move was made.
function SokobanBoard:move(dr, dc)
    if self.won or self.solution then return false end
    local kind = self:_step(dr, dc)
    if not kind then return false end
    self.hint_box = nil
    -- A plan (hint path) survives a move that follows it.
    local plan = self._plan
    local ch = self.history[#self.history]
    if plan and plan.rest:sub(1, 1) == ch then
        plan.rest = plan.rest:sub(2)
        plan.key = self:stateKey()
    else
        self._plan = nil
    end
    return true
end

function SokobanBoard:undoMove()
    if not self:canUndo() then return false end
    self:_unstep()
    self.hint_box = nil
    self._plan = nil
    return true
end

function SokobanBoard:restart()
    if self.solution then return false end
    local hints = self.hints_used
    self:_reset()
    self.hints_used = hints
    return true
end

function SokobanBoard:_checkWin()
    for r = 1, self.rows do
        for c = 1, self.cols do
            if self.grid[r][c] == CELL_BOX then
                self.won = false
                return
            end
        end
    end
    self.won = true
end

function SokobanBoard:countBoxes()
    local boxes, targets, done = 0, 0, 0
    for r = 1, self.rows do
        for c = 1, self.cols do
            local ch = self.grid[r][c]
            if isBox(ch) then boxes = boxes + 1 end
            if isTarget(ch) then targets = targets + 1 end
            if ch == CELL_BOX_T then done = done + 1 end
        end
    end
    return boxes, targets, done
end

-- ---------------------------------------------------------------------------
-- Hints: the next push of a solution from where the player is
-- ---------------------------------------------------------------------------

-- A solution (LURD) from the current position, or nil plus a reason
-- ("dead": a box can never reach a goal; "budget": none found cheaply).
function SokobanBoard:plan()
    local key = self:stateKey()
    if self._plan and self._plan.key == key then return self._plan.rest end
    if #self.history == 0 and self.stored_solution then
        self._plan = { key = key, rest = self.stored_solution }
        return self.stored_solution
    end
    local moves, why = Solver.solve(self:toRows(), { weight = 2, budget = HINT_BUDGET })
    if not moves then return nil, why end
    self._plan = { key = key, rest = moves }
    return moves
end

-- Game-common hint convention (ScreenBase:onHint): the step names the box
-- to push next (r, c) and where it goes (tag), so the first tap marks it and
-- the second walks there and pushes.
function SokobanBoard:findHint()
    if self.won then return nil, "complete" end
    local rest, why = self:plan()
    if not rest then return nil, why end
    local first = rest:find("[UDLR]")
    if not first then return nil, "none" end
    local walk = rest:sub(1, first)
    -- Where the player stands before the push, hence the box.
    local r, c = self.player_r, self.player_c
    for i = 1, #walk - 1 do
        local d = DIRS[walk:sub(i, i)]
        r, c = r + d[1], c + d[2]
    end
    local d = DIRS[walk:sub(-1):lower()]
    local br, bc = r + d[1], c + d[2]
    local step = { kind = "fill", r = br, c = bc, tag = walk:sub(-1), moves = walk,
                   to_r = br + d[1], to_c = bc + d[2] }
    self._last_hint = step
    return step
end

-- Called by ScreenBase:onHint with the hinted cell: marks the box and the
-- square it is pushed onto, for the board widget.
function SokobanBoard:setSelection(r, c)
    local h = self._last_hint
    if h and h.r == r and h.c == c then
        self.hint_box = { r = r, c = c, to_r = h.to_r, to_c = h.to_c }
    end
end

function SokobanBoard:applyHint(step)
    if not step or not step.moves then return false end
    for i = 1, #step.moves do
        local d = DIRS[step.moves:sub(i, i):lower()]
        if not self:move(d[1], d[2]) then return false end
    end
    return true
end

function SokobanBoard:noteHintUsed() self.hints_used = self.hints_used + 1 end
function SokobanBoard:getHintsUsed() return self.hints_used end

-- ---------------------------------------------------------------------------
-- Show solution: gives the level up and steps through the stored solution
-- from the start.
-- ---------------------------------------------------------------------------

function SokobanBoard:showSolution()
    if not self.stored_solution or self.stored_solution == "" then return false end
    local hints = self.hints_used
    self:_reset()
    self.hints_used = hints
    self.solution = self.stored_solution
    self.sol_step = 0
    return true
end

-- dir: 1 forward, -1 back. Returns true if the position changed.
function SokobanBoard:solutionStep(dir)
    if not self.solution then return false end
    if dir > 0 then
        if self.sol_step >= #self.solution then return false end
        local ch = self.solution:sub(self.sol_step + 1, self.sol_step + 1):lower()
        local d = DIRS[ch]
        if not self:_step(d[1], d[2]) then return false end
        self.won = false   -- the solution on show is not a win
        self.sol_step = self.sol_step + 1
        return true
    end
    if self.sol_step <= 0 then return false end
    self:_unstep()
    self.sol_step = self.sol_step - 1
    return true
end

-- Every box home on the solution's last step.
function SokobanBoard:solutionDone()
    return self.solution ~= nil and self.sol_step == #self.solution
end

-- ---------------------------------------------------------------------------
-- Persistence: the level is named by band/index (or carried whole for a
-- level that isn't in the bank), the position by the moves made.
-- ---------------------------------------------------------------------------

SokobanBoard.SAVE_VERSION = 2

function SokobanBoard:serialize()
    return {
        v          = SokobanBoard.SAVE_VERSION,
        band       = self.band,
        index      = self.index,
        daily      = self.daily,
        history    = table.concat(self.history),
        hints_used = self.hints_used,
        sol_step   = self.solution and self.sol_step or nil,
    }
end

-- getLevel(band, index) -> { rows, optimal, solution } or nil.
-- Saves from before the level bank (v1: a whole grid of the old 20 levels)
-- are not restored.
function SokobanBoard:load(data, getLevel)
    if type(data) ~= "table" or data.v ~= SokobanBoard.SAVE_VERSION then return false end
    local lv = data.band and data.index and getLevel and getLevel(data.band, data.index)
    if not lv then return false end
    self:setLevel(lv.rows, { band = data.band, index = data.index, daily = data.daily,
                             optimal = lv.optimal, solution = lv.solution })
    if data.sol_step then
        self:showSolution()
        for _ = 1, data.sol_step do self:solutionStep(1) end
    else
        local h = type(data.history) == "string" and data.history or ""
        for i = 1, #h do
            local d = DIRS[h:sub(i, i):lower()]
            if not d or not self:_step(d[1], d[2]) then break end
        end
    end
    self.hints_used = tonumber(data.hints_used) or 0
    return true
end

SokobanBoard.CELL_WALL   = CELL_WALL
SokobanBoard.CELL_FLOOR  = CELL_FLOOR
SokobanBoard.CELL_TARGET = CELL_TARGET
SokobanBoard.CELL_BOX    = CELL_BOX
SokobanBoard.CELL_BOX_T  = CELL_BOX_T
SokobanBoard.CELL_PLAYER = CELL_PLAYER
SokobanBoard.CELL_PLAY_T = CELL_PLAY_T
SokobanBoard.HINT_BUDGET = HINT_BUDGET

return SokobanBoard
