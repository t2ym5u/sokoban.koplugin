local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

-- Same spec in trafficjam, klotski and sokoban (progress.lua is vendored).
describe("Progress (solved / optimal marks)", function()
    local Progress = dofile(DIR .. "progress.lua")

    local function fakePlugin(settings)
        settings = settings or {}
        return {
            settings = settings,
            getSetting = function(self, k, d)
                local v = self.settings[k]
                if v == nil then return d end
                return v
            end,
            saveSetting = function(self, k, v) self.settings[k] = v end,
        }
    end

    it("reads a save from before the optimal marks: solved levels keep their check mark", function()
        local p = Progress.new(fakePlugin{ solved_easy = "0101", solved_hard = "1" })
        assert.is_true(p:isSolved("easy", 2))
        assert.is_false(p:isSolved("easy", 3))
        assert.is_false(p:isOptimal("easy", 2))
        assert.are.equal(2, p:solvedCount("easy"))
        assert.are.equal(0, p:optimalCount("easy"))
        assert.are.equal("✓", p:mark("easy", 2))
        assert.is_nil(p:mark("easy", 1))
        assert.are.equal(1, p:solvedCount("hard"))
        assert.are.equal(0, p:solvedCount("medium"))
    end)

    it("ignores a setting that isn't a string", function()
        local p = Progress.new(fakePlugin{ solved_easy = 12, optimal_easy = true })
        assert.are.equal(0, p:solvedCount("easy"))
        assert.are.equal(0, p:optimalCount("easy"))
    end)

    it("records an optimal win as solved and optimal", function()
        local plugin = fakePlugin()
        local p = Progress.new(plugin)
        p:record("easy", 3, true)
        assert.are.equal("001", plugin.settings.solved_easy)
        assert.are.equal("001", plugin.settings.optimal_easy)
        assert.are.equal("★", p:mark("easy", 3))
        assert.are.equal(1, p:solvedCount("easy"))
        assert.are.equal(1, p:optimalCount("easy"))
    end)

    it("upgrades a check mark to a star on a later optimal win", function()
        local plugin = fakePlugin{ solved_easy = "11" }
        local p = Progress.new(plugin)
        p:record("easy", 2, false)
        assert.are.equal("✓", p:mark("easy", 2))
        p:record("easy", 2, true)
        assert.are.equal("★", p:mark("easy", 2))
        assert.are.equal("11", plugin.settings.solved_easy)
        assert.are.equal("01", plugin.settings.optimal_easy)
        assert.are.equal(2, p:solvedCount("easy"))
        assert.are.equal(1, p:optimalCount("easy"))
    end)

    it("never downgrades a star on a later slower win", function()
        local plugin = fakePlugin()
        local p = Progress.new(plugin)
        p:record("easy", 1, true)
        p:record("easy", 1, false)
        assert.are.equal("★", p:mark("easy", 1))
        assert.are.equal("1", plugin.settings.optimal_easy)
    end)

    it("keeps bands apart and leaves other levels untouched", function()
        local plugin = fakePlugin{ solved_easy = "10100", optimal_easy = "1" }
        local p = Progress.new(plugin)
        p:record("easy", 4, true)
        p:record("hard", 2, false)
        assert.are.equal("10110", plugin.settings.solved_easy)
        assert.are.equal("1001", plugin.settings.optimal_easy)
        assert.are.equal("01", plugin.settings.solved_hard)
        assert.is_nil(plugin.settings.optimal_hard)
    end)

    it("does not rewrite a setting that already has the mark", function()
        local plugin = fakePlugin{ solved_easy = "1", optimal_easy = "1" }
        local writes = 0
        local save = plugin.saveSetting
        plugin.saveSetting = function(...) writes = writes + 1; return save(...) end
        Progress.new(plugin):record("easy", 1, true)
        assert.are.equal(0, writes)
    end)

    it("ignores a win with no level (band or index missing)", function()
        local plugin = fakePlugin()
        local p = Progress.new(plugin)
        p:record(nil, 1, true)
        p:record("easy", nil, true)
        p:record("easy", 0, true)
        assert.is_nil(next(plugin.settings))
    end)
end)
