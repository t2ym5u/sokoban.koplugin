local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
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
• Tap a cell to step one square towards it, or use the arrow buttons.
• Walk into a box to push it in that direction.
• Boxes can only be pushed — not pulled.
• You cannot push two boxes at once or push a box into a wall.

Plan your moves carefully — getting a box into a corner can make the puzzle unsolvable!
Tap Undo to step back, or Restart to start the level over. ◀ and ▶ switch to the previous or next level.
]])

local GAME_RULES_FR = [[
Sokoban — Règles

Poussez toutes les caisses vers leurs emplacements cibles (cases marquées au sol).

Contrôles :
• Appuyez sur une case pour faire un pas vers elle, ou utilisez les flèches.
• Déplacez-vous pour pousser une caisse dans cette direction.
• Les caisses ne peuvent être que poussées — pas tirées.
• Il est impossible de pousser deux caisses à la fois ou de pousser une caisse contre un mur.

Planifiez vos mouvements avec soin — une caisse coincée dans un coin peut rendre le puzzle impossible !
Appuyez sur Annuler pour revenir en arrière, ou sur Recommencer pour reprendre le niveau. ◀ et ▶ passent au niveau précédent ou suivant.
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
    local is_landscape = self:isLandscape()

    -- Title bar with Options menu
    local title_bar = self:buildTitleBar(_("Sokoban"), function()
        return {
            { text = _("Restart level"), callback = function() self:onRestart() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)

    -- D-pad: a 3x3 cross around Undo, at the controls width like the action
    -- bar. The corners are blank, disabled cells so the arrows line up.
    local function blank() return { text = "", enabled = false, callback = function() end } end
    local dpad = self:buildActionBar({
        { blank(),
          { text = "\xe2\x86\x91", callback = function() self:moveDir(-1, 0) end },
          blank() },
        { { text = "\xe2\x86\x90", callback = function() self:moveDir(0, -1) end },
          { text = _("Undo"),     callback = function() self:onUndo() end },
          { text = "\xe2\x86\x92", callback = function() self:moveDir(0, 1) end } },
        { blank(),
          { text = "\xe2\x86\x93", callback = function() self:moveDir(1, 0) end },
          blank() },
    })

    -- Level navigation around Restart; the level number is in the status.
    local action_bar = self:buildActionBar({
        { text = _("\xe2\x97\x80"), callback = function() self:onPrevLevel() end },
        { text = _("Restart"), callback = function() self:onRestart() end },
        { text = _("\xe2\x96\xb6"), callback = function() self:onNextLevel() end },
    })

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        dpad,
        VerticalSpan:new{ width = Size.span.vertical_default },
        action_bar,
    }

    -- Board widget
    local frame_pad   = Size.padding.large
    local frame_extra = 2 * (frame_pad + Size.border.window)
    local budget_w, budget_h = self:getBoardBudget(title_bar, controls)
    self.board_widget = SokobanBoardWidget:new{
        board      = self.board,
        max_width  = math.max(budget_w - frame_extra, 80),
        max_height = math.max(budget_h - frame_extra, 80),
        cellTapCallback  = function(r, c) self:onCellTap(r, c) end,
    }
    local board_frame = FrameContainer:new{
        padding = frame_pad,
        margin  = 0,
        self.board_widget,
    }

    if is_landscape then
        local content = HorizontalGroup:new{
            align  = "center",
            board_frame,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        }
        self:buildLandscapeLayout(title_bar, content)
    else
        self:buildPortraitLayout(title_bar, board_frame,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
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
        status = self:joinStatus(_("Solved!"),
            T(_("Moves: %1"), self.board.moves),
            T(_("Pushes: %1"), self.board.pushes))
    else
        local total, _unused, done = self.board:countBoxes()
        status = self:joinStatus(self:_levelLabel(),
            T(_("Boxes: %1/%2"), done, total),
            T(_("Moves: %1"), self.board.moves),
            T(_("Pushes: %1"), self.board.pushes))
    end
    ScreenBase.updateStatus(self, status)
end

function SokobanScreen:_levelLabel()
    return T(_("Level %1/%2"), self.board.level_idx, SokobanBoard.NUM_LEVELS)
end

return SokobanScreen
