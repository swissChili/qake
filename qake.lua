#!/usr/bin/env lua
local inspect = require "inspect"

-- Shamelessly stolen from:
-- https://stackoverflow.com/questions/295052/how-can-i-determine-the-os-of-the-system-from-within-a-lua-script
local sep = package.config:sub(1,1)
if sep == "/" then
    local plat = "posix"
elseif sep == "\\" then
    local plat = "windows"
end

bin_fmt = nil

new_env = {
    C = "C",
    c = "C",
    cpp = "Cpp",
    Cpp = "Cpp",
    Cxx = "Cpp",
    CXX = "Cpp",
    CPP = "Cpp",

    __lib_basedirs__ = {},

    __exe_basedirs__ = {},

    __current_dir__ = "/",

    drop_ext = function(file)
        if not file:match("^%.?/") then
            file = "/" .. file
        end
        return file:match("^(.*/).+%..+$")
    end,

    libs = {},
    exes = {},

    platform = plat,

    log = function(...)
        print(os.date("%c") .. ": " .. (...))
    end,

    posix = function(val)
        if new_env.platform == "posix" then
            return val
        else
            return nil
        end
    end,

    windows = function(val)
        if new_env.platform == "windows" then
            return val
        else
            return nil
        end
    end,

    print = function(tbl)
        print(inspect(tbl))
    end,

    exe = function(name)
        --print(debug.getinfo(1).source)
        return function(body)
            new_env.exes[name] = {
                name = name,
                body = body,
                root_dir = new_env.__current_dir__
            }
        end
    end,

    lib = function(name)
        print("lib " .. name .." in: " .. new_env.__current_dir__)
        return function(body)
            local l = {
                type = "lib",
                name = name,
                body = body,
                root_dir = new_env.__current_dir__
            }
            new_env.libs[name] = l
            return l
        end
    end,

    generate = function()
        return {
            libs = new_env.libs,
            exes = new_env.exes
        }
    end,

    import = function(file)
        local old = new_env.__current_dir__
        new_env.__current_dir__ = new_env.drop_ext(file)
        local res = parse_script(file)
        new_env.__current_dir__ = old
        return res
    end,

    pkg = function(name)
        return {
            type = "pkg-config",
            name = name,
        }
    end
}

new_env.__index = new_env

function parse_script(file_name)
    local fn = loadfile(file_name, 't', new_env)
    if fn == nil then
        print("Syntax error in " .. file_name)
    else
        return fn()
    end
end

ninja = {
    rules    = {},
    vars    = {},
    builds    = {},
}

function ninja:add_rule(name, cmd)
    self.rules[name] = cmd
end

function ninja:add_var(k, v)
    self.vars[k] = v
end

function ninja:add_build(out, rule, src, implicit, vars)
    self.builds[out] = {
        rule    = rule,
        src        = src,
        vars    = vars,
        impl    = implicit
    }
end

function ninja:to_file(out)
    local buf = ""

    for k, v in pairs(self.vars) do
        buf = buf .. k .. " = " .. v .. "\n\n"
    end

    for r, k in pairs(self.rules) do
        buf = buf .. "rule " .. r .. "\n  "
        buf = buf .. "command = " .. k .. "\n\n"
    end

    for b, s in pairs(self.builds) do
        print(s.impl[0])
        buf = buf .. "build " .. b .. ": " .. s.rule .. " " .. table.concat(s.src, " ")
        buf = buf .. " | " .. table.concat(s.impl, " ") .. "\n"
        for k, v in pairs(s.vars) do
            buf = buf .. "  " .. k .. " = " .. v .. "\n"
        end
        buf = buf .. "\n"
    end

    return buf
end

local function cwd(file)
    local chr = os.tmpname():sub(1,1)
    if chr == "/" then
      -- linux
      chr = "/[^/]*$"
    else
      -- windows
      chr = "\\[^\\]*$"
    end
    return arg[0]:sub(1, arg[0]:find(chr))..(file or '')
end

local function gen_ninja(script, path)
    local build = ninja

    build:add_var("src_dir", path)
    build:add_var("bin_dir", ".")

    build:add_rule("C", "gcc -o $out $in $objs $flags")
    build:add_rule("Cpp", "g++ -o $out $in $objs $flags")

    build:add_rule("C_static", "gcc -c -o $out $in $objs $flags")
    build:add_rule("Cpp_static", "g++ -c -o $out $in $objs $flags")

    for exe, body in pairs(script.exes) do
        local srcs = {}

        for k, src in pairs(body.body.sources) do
            table.insert(srcs, ("$src_dir" .. body.root_dir .. src))
        end

        local flags = {}
        local objs = {}

        for i, lib in pairs(body.body.libs) do
            if lib.type == "pkg-config" then
                table.insert(flags, "`pkg-config --libs --cflags " .. lib.name .. "`")
            elseif lib.type == "lib" then
                table.insert(srcs, "$bin_dir" .. lib.root_dir .. lib.name .. ".o ")
            end
        end

        v = {
            flags = table.concat(flags, " "),
            objs = table.concat(objs, " ")
        }

        build:add_build(body.name, body.body.lang, srcs, {}, v)
    end

    for lib, body in pairs(script.libs) do
        print(inspect(body.body.sources))
        if body.body.sources then

            local srcs = {}
            local imp = {}


            for k, src in pairs(body.body.sources) do
                table.insert(srcs, ("$src_dir" .. body.root_dir .. src))
            end

            local flags = {}
            local objs = {}

            if body.body.libs then
                for i, lib in pairs(body.body.libs) do
                    if lib.type == "pkg-config" then
                        table.insert(flags, "`pkg-config --libs --cflags " .. lib.name .. "`")
                    elseif lib.type == "lib" then
                        table.insert(srcs, "$bin_dir" .. lib.root_dir .. lib.name .. ".o ")
                    end
                end
            end

            v = {
                flags = table.concat(flags, " "),
                objs = table.concat(objs, " ")
            }

            --print(imp[0])

            build:add_build(
                "$bin_dir"..body.root_dir..body.name..".o",
                body.body.lang .. "_static",
                srcs, imp, v)
        else
            print("is nil")
        end
    end

    return build:to_file("build.ninja")
end


local parsed = parse_script('qakefile')
--print(inspect(parsed))

local f = io.open("build/build.ninja", "w")
io.output(f)

io.write(gen_ninja(parsed, '..'))
