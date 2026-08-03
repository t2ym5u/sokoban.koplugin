local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["gettext"] = function()
    return setmetatable({}, { __call = function(_, s) return s end })
end
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("SokobanBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    describe("new / loadLevel", function()
        it("loads level 1 with the player placed somewhere on the grid", function()
            local b = Board:new()
            assert.are.equal(1, b.level_idx)
            local cell = b.grid[b.player_r][b.player_c]
            assert.is_true(cell == Board.CELL_PLAYER or cell == Board.CELL_PLAY_T)
        end)

        it("wraps level_idx into [1, NUM_LEVELS]", function()
            local b = Board:new()
            b:loadLevel(Board.NUM_LEVELS + 1)
            assert.are.equal(1, b.level_idx)
            b:loadLevel(0)
            assert.are.equal(Board.NUM_LEVELS, b.level_idx)
        end)
    end)

    describe("move", function()
        it("moves the player onto an open floor cell", function()
            local b = Board:new()
            -- Find any direction that leads to floor/target (not wall, not box).
            for _, d in ipairs({ {0,1}, {0,-1}, {1,0}, {-1,0} }) do
                local pr, pc = b.player_r, b.player_c
                local dest = b:getCell(pr + d[1], pc + d[2])
                if dest == Board.CELL_FLOOR or dest == Board.CELL_TARGET then
                    assert.is_true(b:move(d[1], d[2]))
                    assert.are.equal(pr + d[1], b.player_r)
                    assert.are.equal(pc + d[2], b.player_c)
                    assert.are.equal(1, b.moves)
                    return
                end
            end
        end)

        it("refuses to move into a wall", function()
            local b = Board:new()
            for _, d in ipairs({ {0,1}, {0,-1}, {1,0}, {-1,0} }) do
                if b:getCell(b.player_r + d[1], b.player_c + d[2]) == Board.CELL_WALL then
                    assert.is_false(b:move(d[1], d[2]))
                    return
                end
            end
        end)
    end)

    describe("undoMove", function()
        it("restores the previous position after a move", function()
            local b = Board:new()
            for _, d in ipairs({ {0,1}, {0,-1}, {1,0}, {-1,0} }) do
                local dest = b:getCell(b.player_r + d[1], b.player_c + d[2])
                if dest == Board.CELL_FLOOR or dest == Board.CELL_TARGET then
                    local pr, pc = b.player_r, b.player_c
                    b:move(d[1], d[2])
                    assert.is_true(b:undoMove())
                    assert.are.equal(pr, b.player_r)
                    assert.are.equal(pc, b.player_c)
                    assert.are.equal(0, b.moves)
                    return
                end
            end
        end)

        it("returns false when there is no history", function()
            local b = Board:new()
            assert.is_false(b:undoMove())
        end)
    end)

    describe("countBoxes / restart", function()
        it("reports at least one box and matching target count", function()
            local b = Board:new()
            local boxes, targets = b:countBoxes()
            assert.is_true(boxes > 0)
            assert.is_true(targets >= boxes)
        end)

        it("restart reloads the same level fresh", function()
            local b = Board:new()
            for _, d in ipairs({ {0,1}, {0,-1}, {1,0}, {-1,0} }) do
                if b:getCell(b.player_r + d[1], b.player_c + d[2]) == Board.CELL_FLOOR then
                    b:move(d[1], d[2])
                    break
                end
            end
            b:restart()
            assert.are.equal(0, b.moves)
            assert.is_false(b.won)
        end)
    end)

    describe("serialize / load", function()
        it("round-trips grid, player position and counters", function()
            local b = Board:new()
            local data = b:serialize()

            local b2 = Board:new()
            assert.is_true(b2:load(data))
            assert.are.equal(b.player_r, b2.player_r)
            assert.are.equal(b.player_c, b2.player_c)
            assert.are.equal(b.rows, b2.rows)
            assert.are.equal(b.cols, b2.cols)
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
