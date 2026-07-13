local Blitbuffer     = require("ffi/blitbuffer")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local GestureRange   = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderText     = require("ui/rendertext")
local UIManager      = require("ui/uimanager")

local gwb      = require("grid_widget_base")
local drawLine = gwb.drawLine

local SokobanBoard = require("board")

local C_BG      = Blitbuffer.COLOR_WHITE
local C_FG      = Blitbuffer.COLOR_BLACK
local C_WALL    = Blitbuffer.COLOR_GRAY_3
local C_FLOOR   = Blitbuffer.COLOR_GRAY_E
local C_TARGET  = Blitbuffer.COLOR_GRAY_D
local C_BOX     = Blitbuffer.COLOR_GRAY_7
local C_BOX_T   = Blitbuffer.COLOR_GRAY_4
local C_PLAYER  = Blitbuffer.COLOR_GRAY_2
local C_OUTSIDE = Blitbuffer.COLOR_WHITE

-- ---------------------------------------------------------------------------
-- SokobanBoardWidget
-- ---------------------------------------------------------------------------

local SokobanBoardWidget = InputContainer:extend{
    board      = nil,
    max_width  = 0,
    max_height = 0,
    cellTapCallback = nil,
}

function SokobanBoardWidget:init()
    local board = self.board
    local rows  = board.rows
    local cols  = board.cols

    local cell = math.floor(math.min(self.max_width / cols, self.max_height / rows))
    cell = math.max(cell, 8)
    self.cell = cell
    self.w    = cell * cols
    self.h    = cell * rows
    self.dimen = Geom:new{ w = self.w, h = self.h }

    local fs = math.max(6, math.floor(cell * 0.55))
    self.sym_face = Font:getFace("cfont", fs)

    self.paint_rect = nil

    self.ges_events = {
        CellTap = { GestureRange:new{ ges = "tap", range = function() return self.paint_rect end } },
    }
end

local function centeredText(bb, text, face, cx, cy, color)
    local m = RenderText:sizeUtf8Text(0, cx * 2, face, text, true, false)
    local tx = cx - math.floor(m.x / 2)
    local ty = cy - math.floor((m.y_bottom - m.y_top) / 2)
    RenderText:renderUtf8Text(bb, tx, ty, face, text, true, false, color or Blitbuffer.COLOR_BLACK)
end

function SokobanBoardWidget:onCellTap(_, ges)
    if not self.paint_rect then return end
    local lx = ges.pos.x - self.paint_rect.x
    local ly = ges.pos.y - self.paint_rect.y
    if lx < 0 or ly < 0 or lx >= self.w or ly >= self.h then return end
    local c = math.floor(lx / self.cell) + 1
    local r = math.floor(ly / self.cell) + 1
    if r >= 1 and r <= self.board.rows and c >= 1 and c <= self.board.cols then
        if self.cellTapCallback then self.cellTapCallback(r, c) end
    end
    return true
end

function SokobanBoardWidget:refresh()
    UIManager:setDirty(self, function()
        return "ui", self.paint_rect or self.dimen
    end)
end

function SokobanBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.w, h = self.h }
    local board = self.board
    local cell  = self.cell
    local thin  = 1

    bb:paintRect(x, y, self.w, self.h, C_BG)

    for r = 1, board.rows do
        for c = 1, board.cols do
            local ch = board.grid[r][c]
            local cx = x + (c - 1) * cell
            local cy = y + (r - 1) * cell
            local pad = math.max(1, math.floor(cell * 0.06))

            if ch == SokobanBoard.CELL_WALL then
                bb:paintRect(cx, cy, cell, cell, C_WALL)
            elseif ch == SokobanBoard.CELL_FLOOR then
                bb:paintRect(cx + pad, cy + pad, cell - 2*pad, cell - 2*pad, C_FLOOR)
            elseif ch == SokobanBoard.CELL_TARGET then
                bb:paintRect(cx + pad, cy + pad, cell - 2*pad, cell - 2*pad, C_TARGET)
                -- Draw target X
                local s = math.max(2, math.floor(cell * 0.2))
                local mx = cx + math.floor(cell / 2)
                local my = cy + math.floor(cell / 2)
                drawLine(bb, mx - s, my - 1, s * 2, 2, C_FG)
                drawLine(bb, mx - 1, my - s, 2, s * 2, C_FG)
            elseif ch == SokobanBoard.CELL_BOX then
                bb:paintRect(cx + pad, cy + pad, cell - 2*pad, cell - 2*pad, C_BOX)
                local bp = math.max(1, math.floor(cell * 0.15))
                drawLine(bb, cx + bp, cy + pad, cell - 2*bp, thin, C_FG)
                drawLine(bb, cx + bp, cy + cell - pad - thin, cell - 2*bp, thin, C_FG)
                drawLine(bb, cx + pad, cy + bp, thin, cell - 2*bp, C_FG)
                drawLine(bb, cx + cell - pad - thin, cy + bp, thin, cell - 2*bp, C_FG)
            elseif ch == SokobanBoard.CELL_BOX_T then
                bb:paintRect(cx + pad, cy + pad, cell - 2*pad, cell - 2*pad, C_BOX_T)
                local bp = math.max(1, math.floor(cell * 0.15))
                drawLine(bb, cx + bp, cy + pad, cell - 2*bp, thin, C_FG)
                drawLine(bb, cx + bp, cy + cell - pad - thin, cell - 2*bp, thin, C_FG)
                drawLine(bb, cx + pad, cy + bp, thin, cell - 2*bp, C_FG)
                drawLine(bb, cx + cell - pad - thin, cy + bp, thin, cell - 2*bp, C_FG)
            elseif ch == SokobanBoard.CELL_PLAYER then
                bb:paintRect(cx + pad, cy + pad, cell - 2*pad, cell - 2*pad, C_FLOOR)
                local pr = math.max(2, math.floor(cell * 0.3))
                bb:paintCircle(cx + math.floor(cell / 2), cy + math.floor(cell / 2), pr, C_PLAYER)
            elseif ch == SokobanBoard.CELL_PLAY_T then
                bb:paintRect(cx + pad, cy + pad, cell - 2*pad, cell - 2*pad, C_TARGET)
                local pr = math.max(2, math.floor(cell * 0.3))
                bb:paintCircle(cx + math.floor(cell / 2), cy + math.floor(cell / 2), pr, C_PLAYER)
            else
                -- Outside/empty
                bb:paintRect(cx, cy, cell, cell, C_OUTSIDE)
            end
        end
    end
end

return SokobanBoardWidget
