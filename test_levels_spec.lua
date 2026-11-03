local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

-- Level bank integrity: every level is well formed, distinct, and its stored
-- solution replays to a win in exactly its optimal push count. (Optimality
-- itself is proven offline by tools/merge_levels.lua: A* over the full state
-- space takes too long for a unit test; a sample is re-proven here.)
describe("level bank", function()
    local Levels, Solver
    setup(function()
        Levels = dofile(DIR .. "levels.lua")
        Solver = dofile(DIR .. "solver.lua")
    end)

    it("has four bands, a few hundred levels, sorted by pushes and in their band's range", function()
        local ranges = { beginner = { 1, 12 }, intermediate = { 13, 22 }, advanced = { 23, 32 },
                         expert = { 33, 999 } }
        local total = 0
        for _, band in ipairs(Levels.BANDS) do
            local n = Levels.count(band)
            assert.is_true(n >= 50, band .. " has " .. n)
            total = total + n
            local prev = 0
            for i = 1, n do
                local lv = Levels.get(band, i)
                assert.is_true(lv.optimal >= ranges[band][1] and lv.optimal <= ranges[band][2])
                assert.is_true(lv.optimal >= prev)
                prev = lv.optimal
            end
        end
        assert.is_true(total >= 300, "total " .. total)
    end)

    it("every level is well formed, fits the screen and is unique", function()
        local seen = {}
        for _, band in ipairs(Levels.BANDS) do
            for i = 1, Levels.count(band) do
                local lv = Levels.get(band, i)
                assert.is_nil(seen[lv.map], band .. " " .. i .. " is a duplicate")
                seen[lv.map] = true
                assert.is_true(#lv.rows <= 12)
                local players, boxes, goals = 0, 0, 0
                for _, row in ipairs(lv.rows) do
                    assert.is_true(#row <= 12)
                    assert.is_nil(row:find("[^# %.%$%*@%+]"))
                    players = players + select(2, row:gsub("[@%+]", ""))
                    boxes = boxes + select(2, row:gsub("[%$%*]", ""))
                    goals = goals + select(2, row:gsub("[%.%*%+]", ""))
                end
                assert.are.equal(1, players)
                assert.are.equal(boxes, goals)
                assert.is_true(boxes >= 2)
            end
        end
    end)

    it("every stored solution replays to a win in the optimal push count", function()
        for _, band in ipairs(Levels.BANDS) do
            for i = 1, Levels.count(band) do
                local lv = Levels.get(band, i)
                local ok, pushes = Solver.replay(lv.rows, lv.solution)
                assert.is_true(ok, band .. " " .. i .. ": " .. tostring(pushes))
                assert.are.equal(lv.optimal, pushes)
            end
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
