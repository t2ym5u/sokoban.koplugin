local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

-- Difficulty guarantees of the level bank: a level's difficulty is its
-- optimal push count; each band holds only levels of its documented range,
-- sorted, the ranges are ordered, and the bands get harder on average.
-- (Optimality is proven offline by tools/merge_levels.lua: A* over the full
-- state space takes too long for a unit test; a sample is re-proven here.)
local RANGES = { beginner = { 1, 12 }, intermediate = { 13, 22 }, advanced = { 23, 32 },
                 expert = { 33, 999 } }

describe("Sokoban difficulty bands", function()
    local Levels, Solver
    setup(function()
        Levels = dofile(DIR .. "levels.lua")
        Solver = dofile(DIR .. "solver.lua")
    end)

    it("has four bands, a few hundred levels, sorted by pushes and in their band's range", function()
        local total = 0
        for _, band in ipairs(Levels.BANDS) do
            local n = Levels.count(band)
            assert.is_true(n >= 50, band .. " has " .. n)
            total = total + n
            local prev = 0
            for i = 1, n do
                local lv = Levels.get(band, i)
                assert.is_true(lv.optimal >= RANGES[band][1] and lv.optimal <= RANGES[band][2])
                assert.is_true(lv.optimal >= prev)
                prev = lv.optimal
            end
        end
        assert.is_true(total >= 300, "total " .. total)
    end)

    it("the documented ranges are ordered and do not overlap", function()
        local prev_hi = 0
        for _, band in ipairs(Levels.BANDS) do
            assert.are.equal(prev_hi + 1, RANGES[band][1], band)
            assert.is_true(RANGES[band][2] >= RANGES[band][1])
            prev_hi = RANGES[band][2]
        end
    end)

    it("the bands get harder on average (pushes, and boxes never fewer)", function()
        local prev_push, prev_boxes = 0, 0
        for _, band in ipairs(Levels.BANDS) do
            local n, push, boxes = Levels.count(band), 0, 0
            for i = 1, n do
                local lv = Levels.get(band, i)
                push = push + lv.optimal
                for _, row in ipairs(lv.rows) do boxes = boxes + select(2, row:gsub("[%$%*]", "")) end
            end
            push, boxes = push / n, boxes / n
            assert.is_true(push > prev_push, band)
            assert.is_true(boxes >= prev_boxes, band .. (" boxes %.2f < %.2f"):format(boxes, prev_boxes))
            prev_push, prev_boxes = push, boxes
        end
    end)

    it("A* finds no shorter solution (first level of each band)", function()
        for _, band in ipairs(Levels.BANDS) do
            local lv = Levels.get(band, 1)
            local _m, pushes = Solver.solve(lv.rows)
            assert.are.equal(lv.optimal, pushes)
        end
    end)
end)
