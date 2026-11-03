local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

local SMALL = {
    "#######",
    "#     #",
    "# $ . #",
    "#  @  #",
    "#######",
}

describe("SokobanBoard", function()
    local Board, Levels

    setup(function()
        Board  = dofile(DIR .. "board.lua")
        Levels = dofile(DIR .. "levels.lua")
    end)

    local function first(band)
        local lv = Levels.get(band or "beginner", 1)
        return Board:new{ rows = lv.rows, solution = lv.solution, optimal = lv.optimal,
                          band = band or "beginner", index = 1 }, lv
    end

    local D = { u = { -1, 0 }, d = { 1, 0 }, l = { 0, -1 }, r = { 0, 1 } }
    local function play(b, moves)
        for i = 1, #moves do
            local d = D[moves:sub(i, i):lower()]
            assert.is_true(b:move(d[1], d[2]))
        end
    end

    describe("moves", function()
        it("steps, pushes and refuses walls", function()
            local b = Board:new{ rows = SMALL }
            assert.is_false(b:move(1, 0))           -- wall below
            assert.is_true(b:move(0, -1))           -- step left
            assert.are.equal(1, b.moves)
            assert.is_true(b:move(-1, 0))           -- pushes the box at (3,3) up
            assert.are.equal(1, b.pushes)
            assert.are.equal(Board.CELL_BOX, b:getCell(2, 3))
        end)

        it("undo restores the position, pushes included", function()
            local b = Board:new{ rows = SMALL }
            local before = b:stateKey()
            play(b, "lU")
            assert.is_true(b:undoMove())
            assert.is_true(b:undoMove())
            assert.are.equal(before, b:stateKey())
            assert.are.equal(0, b.moves)
            assert.are.equal(0, b.pushes)
            assert.is_false(b:undoMove())
        end)

        it("wins when every box is home, and restart starts over", function()
            local b = Board:new{ rows = SMALL }
            play(b, "lluRR")
            assert.is_true(b:isWon())
            assert.is_false(b:move(0, -1))
            b:restart()
            assert.is_false(b:isWon())
            assert.are.equal(0, b.moves)
        end)
    end)

    describe("bank levels", function()
        it("the stored solution of a level solves it with its optimal pushes", function()
            for _, band in ipairs(Levels.BANDS) do
                local b, lv = first(band)
                play(b, lv.solution)
                assert.is_true(b:isWon())
                assert.are.equal(lv.optimal, b.pushes)
            end
        end)
    end)

    describe("hints", function()
        it("follows the stored solution from the start", function()
            local b, lv = first("intermediate")
            local step = b:findHint()
            assert.is_not_nil(step)
            local upto = lv.solution:find("[UDLR]")
            assert.are.equal(lv.solution:sub(1, upto), step.moves)
            assert.is_true(b:applyHint(step))
            assert.are.equal(1, b.pushes)
        end)

        it("hints all the way to a win, even after leaving the solution", function()
            local b, lv = first("advanced")
            -- Wander off: a few steps that are not the solution's.
            for _, d in ipairs({ { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }) do b:move(d[1], d[2]) end
            local n = 0
            while not b:isWon() and n < 200 do
                local step, why = b:findHint()
                if not step then
                    -- the wander may have stuck a box: restart and keep going
                    assert.is_truthy(why)
                    b:restart()
                else
                    assert.is_true(b:applyHint(step))
                end
                n = n + 1
            end
            assert.is_true(b:isWon())
        end)

        it("reports a dead position", function()
            local b = Board:new{ rows = {
                "######",
                "#$  .#",
                "# @  #",
                "######",
            } }
            local rest, why = b:plan()
            assert.is_nil(rest)
            assert.are.equal("dead", why)
        end)
    end)

    describe("show solution", function()
        it("steps forward to the solved position and back", function()
            local b, lv = first()
            play(b, lv.solution:sub(1, 1))
            assert.is_true(b:showSolution())
            assert.are.equal(0, b.moves)
            assert.is_false(b:canUndo())
            for _ = 1, #lv.solution do assert.is_true(b:solutionStep(1)) end
            assert.is_false(b:solutionStep(1))
            assert.is_true(b:solutionDone())
            assert.is_false(b:isWon())     -- a shown solution is not a win
            assert.is_true(b:solutionStep(-1))
            assert.are.equal(#lv.solution - 1, b.sol_step)
        end)
    end)

    describe("serialize / load", function()
        it("round-trips the level and the moves made", function()
            local b, lv = first("expert")
            b.band = "expert"
            play(b, lv.solution:sub(1, 7))
            local data = b:serialize()
            local b2 = Board:new()
            assert.is_true(b2:load(data, Levels.get))
            assert.are.equal(b:stateKey(), b2:stateKey())
            assert.are.equal(b.moves, b2.moves)
            assert.are.equal(b.pushes, b2.pushes)
            assert.is_true(b2:undoMove())
        end)

        it("restores a solution on show", function()
            local b = first()
            b:showSolution()
            b:solutionStep(1); b:solutionStep(1)
            local b2 = Board:new()
            assert.is_true(b2:load(b:serialize(), Levels.get))
            assert.is_true(b2:isShowingSolution())
            assert.are.equal(2, b2.sol_step)
        end)

        it("ignores invalid data and saves from 1.2 (whole grid of the old levels)", function()
            local b = Board:new()
            assert.is_false(b:load(nil, Levels.get))
            assert.is_false(b:load({}, Levels.get))
            assert.is_false(b:load({ level_idx = 3, rows = 2, cols = 2, grid = { "#", "#", "#", "@" } }, Levels.get))
        end)
    end)
end)
