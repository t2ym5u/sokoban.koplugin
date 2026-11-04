local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "common/?.lua;" .. DIR .. "?.lua;" .. package.path

describe("Level bank memory", function()
    it("parses the bank on first use only, and release() drops it", function()
        local Levels = dofile(DIR .. "levels.lua")
        assert.is_false(Levels.isLoaded())
        local n = Levels.count("beginner")
        assert.is_true(n > 0)
        local first = Levels.get("expert", 1)
        assert.is_true(Levels.isLoaded())
        Levels.release()
        assert.is_false(Levels.isLoaded())
        -- Reloading gives the same levels in the same order.
        assert.are.equal(n, Levels.count("beginner"))
        assert.are.same(first, Levels.get("expert", 1))
    end)
end)
