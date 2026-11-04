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
local Menu            = require("ui/widget/menu")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local ScreenBase         = require("screen_base")
local DailySeed          = require("daily_seed")
local MenuHelper         = require("menu_helper")
local SokobanBoard       = lrequire("board")
local SokobanBoardWidget = lrequire("board_widget")
local Levels             = lrequire("levels")
local Progress           = lrequire("progress")

local DeviceScreen = Device.screen

local GAME_RULES_EN = [[
Sokoban — Rules

Push every box onto a target (the squares marked with a cross).

• Boxes can only be pushed, never pulled.
• You cannot push two boxes at once, or push a box into a wall.
• A box pushed into a corner, or against a wall with no target along it, is usually stuck for good: plan ahead.

Controls:
• Tap a square to step one square towards it, or use the arrows.
• Walk into a box to push it.
• Undo takes back the last step; Restart puts the level back as it started.
• ◀ and ▶ go to the previous or next level of the difficulty.
• Hint: the first tap marks the box to push next (thick outline) and the square it goes to (dashed); the second tap walks there and pushes it. Hints follow a solution from where you are; if a box is already stuck, Undo or Restart.
• Show solution (menu) gives up the level and lets you step through a solution.

Every level comes with the fewest pushes it can be solved in. "New game" opens the next level you haven't solved yet; "Level" lets you pick any level, solved ones carry a check mark (✓), and a star (★) when solved in the fewest pushes without a hint. The Daily Challenge is the same level for everyone today.

Difficulty: Beginner levels take up to 12 pushes, Intermediate 13 to 22, Advanced 23 to 32, Expert 33 or more.
]]

local GAME_RULES_FR = [[
Sokoban — Règles

Poussez toutes les caisses sur les cibles (les cases marquées d'une croix).

• Les caisses se poussent, elles ne se tirent jamais.
• Impossible de pousser deux caisses à la fois, ou une caisse contre un mur.
• Une caisse poussée dans un coin, ou contre un mur sans cible le long, est en général bloquée pour de bon : réfléchissez avant de pousser.

Commandes :
• Touchez une case pour faire un pas vers elle, ou utilisez les flèches.
• Avancez contre une caisse pour la pousser.
• Annuler reprend le dernier pas ; Recommencer remet le niveau dans son état de départ.
• ◀ et ▶ passent au niveau précédent ou suivant de la difficulté.
• Astuce : le premier appui marque la caisse à pousser (contour épais) et la case où elle va (pointillés) ; le second fait le trajet et la pousse. Les astuces suivent une solution depuis la position actuelle ; si une caisse est déjà bloquée, annulez ou recommencez.
• Voir la solution (menu) abandonne le niveau et permet de parcourir une solution pas à pas.

Chaque niveau indique le plus petit nombre de poussées qui le résout. « Nouvelle partie » ouvre le prochain niveau pas encore résolu ; « Niveau » permet de choisir n'importe quel niveau, les niveaux résolus sont cochés (✓), et reçoivent une étoile (★) s'ils l'ont été avec le moins de poussées possible, sans astuce. Le Défi du jour est le même niveau pour tout le monde aujourd'hui.

Difficulté : les niveaux Débutant se font en 12 poussées au plus, Intermédiaire de 13 à 22, Avancé de 23 à 32, Expert en 33 ou plus.
]]

local BAND_LABELS = {
    beginner     = _("Beginner"),
    intermediate = _("Intermediate"),
    advanced     = _("Advanced"),
    expert       = _("Expert"),
}

local SokobanScreen = ScreenBase:extend{}

function SokobanScreen:init()
    self.progress = Progress.new(self.plugin)
    self.board = SokobanBoard:new()
    if not self.board:load(self.plugin:loadState(), Levels.get) then
        local band = self:_getBand()
        self:_startLevel(band, self:_nextUnsolved(band))
    end
    ScreenBase.init(self)
end

function SokobanScreen:serializeState()
    return self.board:serialize()
end

function SokobanScreen:_save()
    self.plugin:saveState(self.board:serialize())
end

-- ---------------------------------------------------------------------------
-- Levels and progress
-- ---------------------------------------------------------------------------

function SokobanScreen:_getBand()
    local b = self.plugin:getSetting("difficulty", Levels.DEFAULT_BAND)
    return Levels.isBand(b) and b or Levels.DEFAULT_BAND
end

-- Solved / solved-in-the-fewest-pushes levels: see progress.lua.
function SokobanScreen:isLevelSolved(band, index)
    return self.progress:isSolved(band, index)
end

-- A win marks the level solved, and optimal too when it took the fewest
-- pushes with no hint. Marks are never taken back.
function SokobanScreen:_markSolved()
    local b = self.board
    self.progress:record(b.band, b.index, b:isOptimalWin())
end

-- The first level of the band not solved yet (other than the one on the
-- board), or the one after the current level once they are all solved.
function SokobanScreen:_nextUnsolved(band)
    local total = Levels.count(band)
    local cur = self.board.band == band and self.board.index or nil
    for i = 1, total do
        if i ~= cur and not self:isLevelSolved(band, i) then return i end
    end
    if total == 0 then return nil end
    return cur and (cur % total) + 1 or 1
end

function SokobanScreen:_startLevel(band, index, daily)
    local lv = index and Levels.get(band, index)
    if not lv then return false end
    self.board:setLevel(lv.rows, { band = band, index = index, daily = daily,
                                   optimal = lv.optimal, solution = lv.solution })
    self.hint_cell = nil
    self:_save()
    return true
end

function SokobanScreen:_relayout()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function SokobanScreen:buildLayout()
    local is_landscape = self:isLandscape()

    local title_bar = self:buildTitleBar(_("Sokoban"), function()
        local items = {
            { text = _("New game"), callback = function() self:onNewGame() end },
            self:makeDailyButtonConfig(),
            { text = T(_("Difficulty: %1"), BAND_LABELS[self:_getBand()]),
              callback = function() self:openDifficultyMenu() end },
            { text = self:_levelButtonText(), callback = function() self:openLevelMenu() end },
        }
        if not self.board:isShowingSolution() and not self.board:isWon() then
            items[#items + 1] = { text = _("Show solution"), callback = function() self:onShowSolution() end }
        end
        items[#items + 1] = { text = _("Restart level"), callback = function() self:onRestart() end }
        items[#items + 1] = self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR)
        return items
    end)

    -- D-pad: a 3x3 cross around Undo, at the controls width like the action
    -- bar. The corners are blank, disabled cells so the arrows line up.
    -- Greyed out once the round is over (a win, or the solution on show).
    local live = not self:isRoundOver()
    local function blank() return { text = "", enabled = false, callback = function() end } end
    local function arrow(text, dr, dc)
        return { text = text, enabled = live, callback = function() self:moveDir(dr, dc) end }
    end
    local dpad = self:buildActionBar({
        { blank(), arrow("\xe2\x86\x91", -1, 0), blank() },
        { arrow("\xe2\x86\x90", 0, -1),
          { id = "undo_btn", text = _("Undo"), callback = function() self:onUndo() end },
          arrow("\xe2\x86\x92", 0, 1) },
        { blank(), arrow("\xe2\x86\x93", 1, 0), blank() },
    })
    -- buildActionBar would swap this bar for "New game" too once the round
    -- is over; only the bar below should.
    dpad:setRoundOverButtons(nil)
    self.undo_btn = dpad:getButtonById("undo_btn")

    -- The bar that turns into "New game" (or the solution steps) once the
    -- round is over: built last, so refreshActionBar swaps this one.
    local prev    = { text = "\xe2\x97\x80", callback = function() self:onPrevLevel() end }
    local nxt     = { text = "\xe2\x96\xb6", callback = function() self:onNextLevel() end }
    local restart = { id = "restart_btn", text = _("Restart"), callback = function() self:onRestart() end }
    local hint    = { text = _("Hint"), callback = function() self:onHint() end }
    local action_bar = self:buildActionBar(is_landscape
        and { { prev, nxt }, { restart, hint } }
        or  { prev, restart, hint, nxt })
    self.restart_btn = action_bar:getButtonById("restart_btn")

    self.status_text:setMaxWidth(self:getControlsWidth())
    local controls = VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        dpad,
        VerticalSpan:new{ width = Size.span.vertical_default },
        action_bar,
    }

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
    self:_updateButtons()

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

-- ---------------------------------------------------------------------------
-- Interaction
-- ---------------------------------------------------------------------------

-- After anything that changed the position: the save, the level marked
-- solved on a win, one repaint.
function SokobanScreen:_afterMove()
    self.hint_cell = nil
    local b = self.board
    if b:isWon() then self:_markSolved() end
    self:_save()
    if b:isWon() then
        -- the arrows grey out and the bar turns into "New game"
        self:_relayout()
        return
    end
    self:_updateButtons()
    self.board_widget:refresh()
    self:updateStatus()
end

-- Tap on grid: move player one step toward tapped cell
function SokobanScreen:onCellTap(r, c)
    local pr, pc = self.board.player_r, self.board.player_c
    local dr = r - pr
    local dc = c - pc
    if dr == 0 and dc == 0 then return end
    if math.abs(dr) >= math.abs(dc) then
        self:moveDir(dr > 0 and 1 or -1, 0)
    else
        self:moveDir(0, dc > 0 and 1 or -1)
    end
end

function SokobanScreen:moveDir(dr, dc)
    if self.board:move(dr, dc) then self:_afterMove() end
end

function SokobanScreen:onUndo()
    if self.board:undoMove() then self:_afterMove() end
end

function SokobanScreen:onRestart()
    if self.board:isShowingSolution() then return end
    self.board:restart()
    self:_afterMove()
end

-- ◀ / ▶: the previous / next level of the current difficulty.
function SokobanScreen:_stepLevel(delta)
    local band = self:_getBand()
    local total = Levels.count(band)
    if total == 0 then return end
    local cur = (self.board.band == band and not self.board.daily and self.board.index) or 0
    local idx = ((cur - 1 + delta) % total) + 1
    if cur == 0 then idx = delta > 0 and 1 or total end
    self:_startLevel(band, idx)
    self:_relayout()
end

function SokobanScreen:onNextLevel() self:_stepLevel(1) end
function SokobanScreen:onPrevLevel() self:_stepLevel(-1) end

-- Hints: say why there is none when a box is stuck or no solution turns up
-- cheaply, rather than the generic "no hint" line.
function SokobanScreen:onHint()
    local b = self.board
    if not b:isWon() and not b:isShowingSolution() then
        local rest, why = b:plan()
        if not rest then
            self.hint_cell = nil
            self:updateStatus((why == "dead" or why == "unsolvable")
                and _("A box is stuck: undo or restart.")
                or  _("No hint from here: undo or restart."))
            return
        end
    end
    local used = b:getHintsUsed()
    ScreenBase.onHint(self)
    -- A hint shown, even one only marked, rules out the optimal mark.
    if (self.hint_cell or b:getHintsUsed() > used) and not b.hint_seen then
        b:noteHintSeen()
        self:_save()
    end
    if b:isWon() then
        self:_markSolved()
        self:_save()
        self:_relayout()
        return
    end
    self:_updateButtons()
    self:refreshActionBar()
end

function SokobanScreen:describeHintStep(_step, level)
    if level == 1 then
        return _("Push the marked box.")
    end
    return _("Box pushed.")
end

function SokobanScreen:onShowSolution()
    if not self.board:showSolution() then
        self:updateStatus(_("No hint is available here."))
        return
    end
    self.hint_cell = nil
    self:_save()
    self:_relayout()
end

function SokobanScreen:onSolutionStep(dir)
    if self.board:solutionStep(dir) then
        self:_save()
        self.board_widget:refresh()
        self:updateStatus()
    end
end

function SokobanScreen:onNewGame()
    local band = self:_getBand()
    self:_startLevel(band, self:_nextUnsolved(band))
    self:_relayout()
end

-- Today's level: picked from the bank by the daily seed, so everyone playing
-- the same difficulty gets the same one today.
function SokobanScreen:onDailyGame()
    local band = self:_getBand()
    local total = Levels.count(band)
    if total == 0 then return end
    local plugin = self.plugin
    local key = (plugin.getPluginId and plugin:getPluginId() or plugin.name) .. "_" .. band
    local index
    DailySeed.run(key, function() index = math.random(total) end)
    self:_startLevel(band, index, os.date("%Y-%m-%d"))
    self:_relayout()
end

function SokobanScreen:openDifficultyMenu()
    local items = {}
    for _i, id in ipairs(Levels.BANDS) do
        items[#items + 1] = {
            id   = id,
            text = BAND_LABELS[id] .. " · " .. T(_("Solved: %1/%2 · minimum: %3"),
                self.progress:solvedCount(id), Levels.count(id), self.progress:optimalCount(id)),
        }
    end
    MenuHelper.openPickerMenu{
        title      = _("Difficulty"),
        items      = items,
        -- Wide enough for "Intermédiaire · Résolus : 600/600 · au minimum : 600".
        width_ratio = 0.9,
        current_id = self:_getBand(),
        parent     = self,
        on_select  = function(id)
            self.plugin:saveSetting("difficulty", id)
            self:onNewGame()
        end,
    }
end

-- Every level of the current difficulty, opened on the page of the level in
-- play; solved ones carry a check mark, a star if solved in the fewest pushes.
function SokobanScreen:openLevelMenu()
    local band = self:_getBand()
    local total = Levels.count(band)
    if total == 0 then return end
    local cur = (self.board.band == band and not self.board.daily) and self.board.index or nil
    local menu
    local item_table = {}
    for i = 1, total do
        local lv = Levels.get(band, i)
        local nboxes = select(2, lv.map:gsub("[%$%*]", ""))
        item_table[i] = {
            text      = T("%1 · %2 · %3", i, T(_("%1 boxes"), nboxes), T(_("%1 pushes"), lv.optimal)),
            mandatory = self.progress:mark(band, i),
            checked   = i == cur,
            callback  = function()
                UIManager:close(menu)
                self:_startLevel(band, i)
                self:_relayout()
            end,
        }
    end
    menu = Menu:new{
        title                  = T("%1 · %2", _("Level"), BAND_LABELS[band]),
        item_table             = item_table,
        width                  = math.floor(DeviceScreen:getWidth() * 0.8),
        height                 = math.floor(DeviceScreen:getHeight() * 0.9),
        disable_footer_padding = true,
        show_parent            = self,
    }
    if cur then menu:switchItemTable(nil, item_table, cur) end
    UIManager:show(menu)
    return menu
end

-- ---------------------------------------------------------------------------
-- Round over: a win, or the solution on show (one-way).
-- ---------------------------------------------------------------------------

function SokobanScreen:isRoundOver()
    return self.board:isWon() or self.board:isShowingSolution()
end

function SokobanScreen:getRoundOverButtons()
    local new_game = { text = _("New game"), callback = function() self:onNewGame() end }
    if self.board:isShowingSolution() then
        local back = { text = _("Step back"),    callback = function() self:onSolutionStep(-1) end }
        local fwd  = { text = _("Step forward"), callback = function() self:onSolutionStep(1) end }
        if self:isLandscape() then
            return { { back, fwd }, { new_game } }
        end
        return { { back, fwd, new_game } }
    end
    return { new_game }
end

-- ---------------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------------

function SokobanScreen:_levelButtonText()
    local b = self.board
    if b.daily or not b.index or b.band ~= self:_getBand() then
        return T(_("Level: %1"), "–")
    end
    return T(_("Level: %1"), T("%1/%2", b.index, Levels.count(b.band)))
end

function SokobanScreen:updateStatus(msg)
    local b = self.board
    local status
    if msg then
        status = msg
    elseif b:isShowingSolution() then
        status = T(_("Solution: move %1/%2"), b.sol_step, #b.solution)
    elseif b:isWon() then
        if b:isOptimalWin() then
            status = T(_("Solved! %1 pushes, the fewest possible."), b.pushes)
        elseif b.hint_seen or b:getHintsUsed() > 0 then
            status = T(_("Solved with hints: %1 pushes (fewest: %2)."), b.pushes, b.optimal or "?")
        else
            status = T(_("Solved! %1 pushes (fewest: %2)."), b.pushes, b.optimal or "?")
        end
    else
        local total, _unused, done = b:countBoxes()
        local where
        if b.daily then
            where = _("Daily Challenge")
        elseif b.index then
            where = T(_("No. %1"), b.index)
        end
        -- One line in portrait: the difficulty and level number are in the
        -- menu, the move count comes with the win.
        status = self:joinStatus(
            where,
            T(_("Boxes: %1/%2"), done, total),
            T(_("Pushes: %1"), b.pushes))
    end
    ScreenBase.updateStatus(self, status)
    self:refreshActionBar()
end

function SokobanScreen:_updateButtons()
    if self.undo_btn then self.undo_btn:enableDisable(self.board:canUndo()) end
    if self.restart_btn then self.restart_btn:enableDisable(self.board:canUndo()) end
end

-- The level bank is only needed while a game is open: drop it when the
-- screen closes (the next game reads it again).
function SokobanScreen:onCloseWidget()
    Levels.release()
end

return SokobanScreen
