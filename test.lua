local M = {}

local hotupdate = require("hotupdate")


local test_mod_name = "test_mod"
local test_mod_map = {
    ["test_mod"] = "test_mod",
    ["test_mod2"] = "sub.test_mod2"
}

function M.test(mod_name)
    local mod_path = test_mod_map[mod_name] 
    M.ensure_mod_path(mod_path)
    local old_script = [[
        local M = {}
        function M.a(a)
            print("a")
            return a + 1
        end
        return M
    ]]
    M.write_file(mod_path, old_script)
    package.loaded[mod_path] = nil
    local old_mod = require(mod_path)
    assert(2 == old_mod.a(1))

    local new_script = [[
        local M = {}
        function M.a(a)
            print("b")
            return a + 2
        end
        return M
    ]]
    M.write_file(mod_path, new_script)
    hotupdate.reload_mod(mod_path)
    assert(3 == old_mod.a(1))
end

function M.ensure_mod_path(mod_path)
    local mod_path = string.gsub(mod_path, "%.", "/")
    local _,_,dir,_ = string.find(mod_path, "([%w/]+)/(%w+)")
    if dir then
        os.execute("mkdir -p " .. dir)
    end
end

function M.write_file(mod_path, str)
    local mod_path = string.gsub(mod_path, "%.", "/")
    local fp = io.open(mod_path .. ".lua", "w") 
    fp:write(str)
    fp:close()
end


return M
