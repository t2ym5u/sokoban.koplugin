local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

-- Level bank integrity: every level is well formed, distinct, and its stored
-- solution replays to a win in exactly its stored push count. (The bands and
-- the optimality of that count live in test_difficulty_spec.lua.)
describe("level bank", function()
    local Levels, Solver
    setup(function()
        Levels = dofile(DIR .. "levels.lua")
        Solver = dofile(DIR .. "solver.lua")
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
end)
