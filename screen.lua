local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")
local T               = require("ffi/util").template

local ScreenBase         = require("screen_base")
local SokobanBoard       = lrequire("board")
local SokobanBoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

-- Direction mapping for tap-based movement
-- The player taps a cell to move towards it (one step at a time)
-- Or uses arrow-like buttons

-- ---------------------------------------------------------------------------
-- SokobanScreen
-- ---------------------------------------------------------------------------

local GAME_RULES_EN = _([[
Sokoban — Rules

Push boxes to their target positions (marked squares on the floor).

Controls:
• Tap or swipe to move the player one step.
• Walk into a box to push it in that direction.
• Boxes can only be pushed — not pulled.
• You cannot push two boxes at once or push a box into a wall.

Plan your moves carefully — getting a box into a corner can make the puzzle unsolvable!
Tap Undo to step back, or New to start over.
]])

local GAME_RULES_FR = [[
Sokoban — Règles

Poussez toutes les caisses vers leurs emplacements cibles (cases marquées au sol).

Contrôles :
• Déplacez-vous pour pousser une caisse dans cette direction.
• Les caisses ne peuvent être que poussées — pas tirées.
• Il est impossible de pousser deux caisses à la fois ou de pousser une caisse contre un mur.

Planifiez vos mouvements avec soin — une caisse coincée dans un coin peut rendre le puzzle impossible !
Appuyez sur Annuler pour revenir en arrière, ou sur Nouveau pour recommencer.
]]

local SokobanScreen = ScreenBase:extend{}

function SokobanScreen:init()
    local state = self.plugin:loadState()
    local idx   = self.plugin:getSetting("level_idx", 1)
    self.board  = SokobanBoard:new{ level_idx = idx }
    if not self.board:load(state) then
        -- fresh level
    end
    ScreenBase.init(self)
end

function SokobanScreen:serializeState()
    return self.board:serialize()
end

function SokobanScreen:buildLayout()
    local sw           = DeviceScreen:getWidth()
    local sh = DeviceScreen:getHeight()
    local is_landscape = self:isLandscape()

    local btn_width = is_landscape
        and math.max(math.floor(sw * 0.35), 100)
        or  math.floor(sw * 0.9)

    -- Top bar
    local top_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_width,
        buttons = {{
            { text = _("\xe2\x97\x80"), callback = function() self:onPrevLevel() end },
            { id = "level_btn", text = self:_levelLabel(),
              callback = function() end },
            { text = _("\xe2\x96\xb6"), callback = function() self:onNextLevel() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
            self:makeCloseButtonConfig(),
        }},
    }
    self.level_btn = top_buttons:getButtonById("level_btn")

    -- Board widget
    local margin      = Size.margin.default
    local padding     = Size.padding.large
    local frame_extra = (padding + margin) * 2
    local board_max
    if is_landscape then
        board_max = math.min(sw - math.floor(sw * 0.4) - frame_extra, sh - frame_extra)
    else
        board_max = math.min(sw - frame_extra, sh - 170 - frame_extra)
    end
    board_max = math.max(board_max, 80)

    self.board_widget = SokobanBoardWidget:new{
        board      = self.board,
        max_width  = board_max,
        max_height = board_max,
        onCellTap  = function(r, c) self:onCellTap(r, c) end,
    }

    local board_frame = FrameContainer:new{
        padding = padding,
        margin  = margin,
        self.board_widget,
    }

    -- D-pad buttons
    local dpad_w = math.floor(btn_width * 0.35)
    local dpad = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_width,
        buttons = {
            { { text = "\xe2\x86\x91", callback = function() self:moveDir(-1, 0) end } },
            {
                { text = "\xe2\x86\x90", callback = function() self:moveDir(0, -1) end },
                { text = _("Undo"),     callback = function() self:onUndo() end },
                { text = "\xe2\x86\x92", callback = function() self:moveDir(0, 1) end },
            },
            { { text = "\xe2\x86\x93", callback = function() self:moveDir(1, 0) end } },
        },
    }

    local bottom_buttons = ButtonTable:new{
        shrink_unneeded_width = true,
        width   = btn_width,
        buttons = {{
            { text = _("Restart"), callback = function() self:onRestart() end },
        }},
    }

    if is_landscape then
        local panel = VerticalGroup:new{
            align = "center",
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            dpad,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
        }
        self.layout = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            panel,
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            top_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
            dpad,
            VerticalSpan:new{ width = Size.span.vertical_large },
            bottom_buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end
    self[1] = self.layout
    self:updateStatus()
end

-- Tap on grid: move player one step toward tapped cell
function SokobanScreen:onCellTap(r, c)
    local pr, pc = self.board.player_r, self.board.player_c
    local dr = r - pr
    local dc = c - pc
    -- Move one step in the dominant direction
    if math.abs(dr) >= math.abs(dc) then
        self:moveDir(dr > 0 and 1 or -1, 0)
    else
        self:moveDir(0, dc > 0 and 1 or -1)
    end
end

function SokobanScreen:moveDir(dr, dc)
    local moved = self.board:move(dr, dc)
    if moved then
        self.board_widget:refresh()
        self:updateStatus()
        self.plugin:saveState(self.board:serialize())
        if self.board.won then
            self:showMessage(T(_("Level %1 complete! Moves: %2"), self.board.level_idx, self.board.moves), 3)
        end
    end
end

function SokobanScreen:onUndo()
    self.board:undoMove()
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function SokobanScreen:onRestart()
    self.board:restart()
    self.board_widget:refresh()
    self:updateStatus()
    self.plugin:saveState(self.board:serialize())
end

function SokobanScreen:onNextLevel()
    self.board:nextLevel()
    self.plugin:saveSetting("level_idx", self.board.level_idx)
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function SokobanScreen:onPrevLevel()
    self.board:prevLevel()
    self.plugin:saveSetting("level_idx", self.board.level_idx)
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function SokobanScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.won then
        status = T(_("Solved! Moves: %1  Pushes: %2"), self.board.moves, self.board.pushes)
    else
        local _, _, done = self.board:countBoxes()
        local total = 0
        for r = 1, self.board.rows do
            for c = 1, self.board.cols do
                local ch = self.board.grid[r][c]
                if ch == SokobanBoard.CELL_BOX or ch == SokobanBoard.CELL_BOX_T then
                    total = total + 1
                end
            end
        end
        status = T(_("Boxes: %1/%2  Moves: %3  Pushes: %4"),
            done, total, self.board.moves, self.board.pushes)
    end
    ScreenBase.updateStatus(self, status)
end

function SokobanScreen:_levelLabel()
    return T(_("Level %1/%2"), self.board.level_idx, SokobanBoard.NUM_LEVELS)
end

return SokobanScreen
