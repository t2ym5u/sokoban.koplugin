local UndoStack = require("undo_stack")

-- Cell types
local CELL_WALL   = "#"
local CELL_FLOOR  = " "
local CELL_TARGET = "."
local CELL_BOX    = "$"
local CELL_BOX_T  = "*"  -- box on target
local CELL_PLAYER = "@"
local CELL_PLAY_T = "+"  -- player on target

local LEVELS = require("levels")

-- ---------------------------------------------------------------------------
-- SokobanBoard
-- ---------------------------------------------------------------------------

local SokobanBoard = {}
SokobanBoard.__index = SokobanBoard

function SokobanBoard:new(opts)
    opts = opts or {}
    local obj = setmetatable({
        level_idx   = opts.level_idx or 1,
        grid        = nil,
        rows        = 0,
        cols        = 0,
        player_r    = 0,
        player_c    = 0,
        moves       = 0,
        pushes      = 0,
        won         = false,
        undo        = UndoStack:new{ max_size = 1000 },
    }, self)
    obj:loadLevel(obj.level_idx)
    return obj
end

function SokobanBoard:loadLevel(idx)
    idx = ((idx - 1) % #LEVELS) + 1
    self.level_idx = idx
    local raw = LEVELS[idx]

    -- Find dimensions
    local max_cols = 0
    for _, row in ipairs(raw) do
        if #row > max_cols then max_cols = #row end
    end
    local rows = #raw

    -- Build grid
    local grid = {}
    local pr, pc = 1, 1
    for r = 1, rows do
        grid[r] = {}
        local row_str = raw[r]
        for c = 1, max_cols do
            local ch = row_str:sub(c, c)
            if ch == "" then ch = " " end
            grid[r][c] = ch
            if ch == CELL_PLAYER or ch == CELL_PLAY_T then
                pr, pc = r, c
            end
        end
    end

    self.grid      = grid
    self.rows      = rows
    self.cols      = max_cols
    self.player_r  = pr
    self.player_c  = pc
    self.moves     = 0
    self.pushes    = 0
    self.won       = false
    self.undo:clear()
end

function SokobanBoard:getCell(r, c)
    if r < 1 or r > self.rows or c < 1 or c > self.cols then return CELL_WALL end
    return self.grid[r][c]
end

local function isFloor(ch)
    return ch == CELL_FLOOR or ch == CELL_TARGET or ch == CELL_PLAYER or ch == CELL_PLAY_T
end

local function isBox(ch)
    return ch == CELL_BOX or ch == CELL_BOX_T
end

local function isTarget(ch)
    return ch == CELL_TARGET or ch == CELL_BOX_T or ch == CELL_PLAY_T
end

-- Move player in direction (dr, dc). Returns true if a move was made.
function SokobanBoard:move(dr, dc)
    if self.won then return false end
    local pr, pc = self.player_r, self.player_c
    local nr, nc = pr + dr, pc + dc  -- new player pos
    local dest = self:getCell(nr, nc)

    if dest == CELL_WALL then return false end

    local pushed_box = false
    if isBox(dest) then
        -- Try to push the box
        local br, bc = nr + dr, nc + dc
        local behind = self:getCell(br, bc)
        if behind == CELL_WALL or isBox(behind) then return false end
        -- Push the box
        local box_old   = dest
        local behind_old = behind
        -- Save state for undo
        self.undo:push{
            pr = pr, pc = pc, nr = nr, nc = nc, br = br, bc = bc,
            player_old = self.grid[pr][pc],
            dest_old   = box_old,
            behind_old = behind_old,
        }
        -- Move box
        self.grid[br][bc] = isTarget(behind) and CELL_BOX_T or CELL_BOX
        self.grid[nr][nc] = isTarget(box_old) and CELL_PLAY_T or CELL_PLAYER
        self.grid[pr][pc] = isTarget(self.grid[pr][pc]) and CELL_TARGET or CELL_FLOOR
        pushed_box = true
        self.pushes = self.pushes + 1
    else
        -- Simple move
        self.undo:push{
            pr = pr, pc = pc, nr = nr, nc = nc,
            player_old = self.grid[pr][pc],
            dest_old   = dest,
        }
        self.grid[nr][nc] = isTarget(dest) and CELL_PLAY_T or CELL_PLAYER
        self.grid[pr][pc] = isTarget(self.grid[pr][pc]) and CELL_TARGET or CELL_FLOOR
    end

    self.player_r = nr
    self.player_c = nc
    self.moves    = self.moves + 1

    self:_checkWin()
    return true
end

function SokobanBoard:undoMove()
    local entry = self.undo:pop()
    if not entry then return false end

    -- Restore player
    self.grid[entry.pr][entry.pc] = entry.player_old
    -- Restore dest cell
    self.grid[entry.nr][entry.nc] = entry.dest_old
    -- Restore behind cell (if a push was made)
    if entry.br then
        self.grid[entry.br][entry.bc] = entry.behind_old
        self.pushes = math.max(0, self.pushes - 1)
    end
    self.player_r = entry.pr
    self.player_c = entry.pc
    self.moves    = math.max(0, self.moves - 1)
    self.won      = false
    return true
end

function SokobanBoard:restart()
    self:loadLevel(self.level_idx)
end

function SokobanBoard:nextLevel()
    self:loadLevel(self.level_idx + 1)
end

function SokobanBoard:prevLevel()
    local idx = self.level_idx - 1
    if idx < 1 then idx = #LEVELS end
    self:loadLevel(idx)
end

function SokobanBoard:_checkWin()
    -- Win if all boxes are on targets
    for r = 1, self.rows do
        for c = 1, self.cols do
            if self.grid[r][c] == CELL_BOX then
                self.won = false; return
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
            if ch == CELL_BOX or ch == CELL_BOX_T then boxes = boxes + 1 end
            if isTarget(ch) then targets = targets + 1 end
            if ch == CELL_BOX_T then done = done + 1 end
        end
    end
    return boxes, targets, done
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function SokobanBoard:serialize()
    local flat = {}
    for r = 1, self.rows do
        for c = 1, self.cols do
            flat[#flat + 1] = self.grid[r][c]
        end
    end
    return {
        level_idx = self.level_idx,
        rows      = self.rows,
        cols      = self.cols,
        grid      = flat,
        player_r  = self.player_r,
        player_c  = self.player_c,
        moves     = self.moves,
        pushes    = self.pushes,
        won       = self.won,
    }
end

function SokobanBoard:load(data)
    if type(data) ~= "table" or not data.grid then return false end
    self.level_idx = data.level_idx or 1
    self.rows      = data.rows      or 0
    self.cols      = data.cols      or 0
    self.player_r  = data.player_r  or 1
    self.player_c  = data.player_c  or 1
    self.moves     = data.moves     or 0
    self.pushes    = data.pushes    or 0
    self.won       = data.won       or false
    self.grid      = {}
    local idx = 1
    for r = 1, self.rows do
        self.grid[r] = {}
        for c = 1, self.cols do
            self.grid[r][c] = data.grid[idx] or " "
            idx = idx + 1
        end
    end
    self.undo:clear()
    return true
end

SokobanBoard.CELL_WALL   = CELL_WALL
SokobanBoard.CELL_FLOOR  = CELL_FLOOR
SokobanBoard.CELL_TARGET = CELL_TARGET
SokobanBoard.CELL_BOX    = CELL_BOX
SokobanBoard.CELL_BOX_T  = CELL_BOX_T
SokobanBoard.CELL_PLAYER = CELL_PLAYER
SokobanBoard.CELL_PLAY_T = CELL_PLAY_T
SokobanBoard.NUM_LEVELS  = #LEVELS

return SokobanBoard
