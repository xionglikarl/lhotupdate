local M = {}

local global_objects = {
    arg,
    assert,
    bit32,
    collectgarbage,
    coroutine,
    debug,
    dofile,
    error,
    getmetatable,
    io,
    ipairs,
    lfs,
    load,
    loadfile,
    loadstring,
    math,
    module,
    next,
    os,
    package,
    pairs,
    pcall,
    print,
    rawequal,
    rawget,
    rawlen,
    rawset,
    require,
    select,
    setmetatable,
    string,
    table,
    tonumber,
    tostring,
    type,
    unpack,
    utf8,
    xpcall,
}

local updated_func_map = {}
local replaced_obj = {}
local protected = {}

local updated_sig = {}
local function check_updated(new_obj, old_obj, name, deep)
    local signature = string.format("new(%s) old(%s)", tostring(new_obj), tostring(old_obj))
    -- print(string.format("update mod <%s>, <%s>", deep, name))

    if new_obj == old_obj then
        print(string.format("update mod <%s>, same object <%s>", name, deep))
        return true
    end
    if updated_sig[signature] then
        print(string.format("update mod <%s>, object <%s> already updated", name, deep))
        return true
    end
    updated_sig[signature] = true
    return false
end

local function replace_functions(obj)
    if obj == nil then return end
    if protected[obj] then return end
    if replaced_obj[obj] then return end
    replaced_obj[obj] = true
    
    local obj_type = type(obj)    
    if obj_type == "function" then
        for i=1, math.huge do
            local name, value = debug.getupvalue(obj, i)
            if not name then break end
            local new_func = updated_func_map[value]
            if new_func then
                debug.setupvalue(obj, i, new_func)
            else
                replace_functions(value)
            end
        end
    elseif obj_type == "table" then
        for k, v in pairs(obj) do
            local new_k = updated_func_map[k]
            local new_v = updated_func_map[v]
            if new_k then
                obj[k] = nil   
                obj[new_k] = new_v or v
            else
                obj[k] = new_v or v
                replace_functions(k)
            end
            if not new_v then replace_functions(v) end
        end

        local metatable = debug.getmetatable(obj)
        replace_functions(metatable)
    end
end

local function add_self_to_protect()
    M.add_protect{
        M,
        M.reload_mod,
        M.add_protect
    }
end   

function M.reload_mod(mod_name)
    local old_obj = package.loaded[mod_name]  
    
    local file_path = package.searchpath(mod_name, package.path)
    local fh = io.open(file_path)
    local chunk = fh:read("a")
    io.close(fh)
    local env = {}
    local fun = load(chunk, mod_name, "bt", env)
    local ok, new_obj = pcall(fun)

    if new_obj == nil then
        print(string.format("reload_mod <%s> fail, load return nil", mod_name))
        return
    end

    add_self_to_protect()
    updated_func_map = {}
    updated_sig = {}
    M.update_loaded_mod(new_obj, old_obj, mod_name)
    if next(updated_func_map) then
        replaced_obj = {}
        replace_functions(_G)
        replaced_obj = {}
    end
    updated_func_map = {}
    updated_sig = {}
    return package.loaded[mod_name]
end

function M.update_loaded_mod(new_obj, old_obj, mod_name)
    local old_type = type(old_obj) 
    local new_type = type(new_obj) 
    if old_type ~= new_type then 
        print(string.format("reload_mod <%s> fail, load return type is incorrect", mod_name))
        return
    end

    if old_type == "function" then
        M.update_function(new_obj, old_obj, mod_name, "") 
        package.loaded[mod_name] = new_obj
    elseif old_type == "table" then
        M.update_table(new_obj, old_obj, mod_name, "") 
    end
end

function M.update_table(new_table, old_table, mod_name, deep) 
    assert("table" == type(new_table))
    assert("table" == type(old_table))
    if protected[old_table] then return end
    if check_updated(new_table, old_table, mod_name, deep) then return end
   
    for k, v in pairs(new_table) do
        local old_v = old_table[k]
        if old_v == nil then
            old_table[k] = v
        end
        local old_type = type(old_v)
        local new_type = type(v)
        if old_type ~= new_type then
            print(string.format("update_table fail, mod:<%s>, deep:<%s>, key:<%s>, value type is incorrect", 
                mod_name, deep, k))
            return 
        end

        local deep = deep .. "  " ..  k
        if old_type == "function" then
            M.update_function(v, old_v, mod_name, deep) 
        elseif old_type == "table" then
            M.update_table(v, old_v, mod_name, deep) 
        end
    end

    local old_meta = debug.getmetatable(old_table)
    local new_meta = debug.getmetatable(new_table)
    if type(old_meta) == "table" and type(new_meta) == "table" then
        local deep = deep .. "  " .. "metatable" 
        M.update_table(new_meta, old_meta, mod_name, deep)
    end
end

function M.update_function(new_func, old_func, mod_name, deep) 
    assert("function" == type(new_func))
    assert("function" == type(old_func))
    if protected[old_func] then return end
    if check_updated(new_func, old_func, name, deep) then return end

    local old_upvalue_map = {}
    for i=1, math.huge do
        local name, value = debug.getupvalue(old_func, i)         
        if not name then break end
        old_upvalue_map[name] = value
    end

    for i=1, math.huge do
        local name, value = debug.getupvalue(new_func, i)         
        if not name then break end
        local old_value = old_upvalue_map[name]
        if old_value then
            local deep = deep .. "  " .. name
            local new_type = type(value)
            local old_type = type(old_value)
            if new_type ~= old_type then
                print(string.format("update_function fail, mod:<%s>, deep:<%s>, key:<%s>, value type is incorrect", 
                    mod_name, deep, name))
            end

            if old_type == "function" then
                M.update_function(value, old_value, mod_name, deep) 
            elseif old_type == "table" then
                M.update_table(value, old_value, mod_name, deep) 
                debug.setupvalue(new_func, i, old_value)
            else
                debug.setupvalue(new_func, i, old_value)
            end   
        end
    end

    --print("=========func,", old_func, new_func, old_func(1), new_func(1))
    updated_func_map[old_func] = new_func 
end

function M.add_protect(object_array)
    for _, obj in pairs(object_array) do
        protected[obj] = true
    end
end 


return M
