--[[
A Lua/FFI based API for reading StarDict dictionaries

Note that this is still work in progress.
It does not handle compressed indexes nor compressed
dictionaries yet.
It has no uppercase/lowercase handling.
It has no similarity search (e.g. levenstein).
It has no sophisticated indexing.
It has no stemming.

What works for now is:

local StarDict = require("ffi/stardict")

local dicts = StarDict.list("/path")

local d = StarDict.open("/path/dict") -- without extension
local word = d:lookup_word("hello")
--]]

local ffi = require("ffi")
local bit = require("bit")
local lfs = require("libkoreader-lfs")

require("ffi/posix_h")

--------------------------------------------------------------

local MMapFile = {}
function MMapFile:open(name, size)
    local file = ffi.C.open(name, ffi.C.O_RDONLY)
    if file == -1 then
        error("cannot read file "..name)
    end
    local address = ffi.C.mmap(nil, size, ffi.C.PROT_READ, ffi.C.MAP_PRIVATE, file, 0)
    if address == nil then
        ffi.C.close(file)
        error("cannot mmap file "..name)
    end
    local mmapfile = {
        fd = file,
        mem = address,
        size = size
    }
    setmetatable(mmapfile, self)
    return mmapfile
end

function MMapFile:__gc()
    ffi.C.munmap(self.mem, self.size)
    ffi.C.close(self.fd)
end

local Dictionary = {}

-- what dictionary versions do we handle?
local known_versions = { ["2.4.2"] = true, ["3.0.0"] = true }

function Dictionary:new(o)
    local o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

-- read a dictionary's IFO file
local function parse_ifo(name)
    local data = {}
    local ifo = io.lines(name)
    -- check for magic string
    assert(ifo() == "StarDict's dict ifo file",
        "missing stardict magic in "..name)
    -- read metadata
    for line in ifo do
        local item, value = line:match("^%s*(%a+)%s*=%s*(.*)$")
        if item and value then data[item] = value end
    end
    -- check version
    assert(data.version and known_versions[data.version],
        "unknown/unspecified dictionary version")
    return data
end

local uint8_p = ffi.typeof("uint8_t*")
local function read_netorder_number(address)
    local n = ffi.cast(uint8_p, address)
    return n[3] + n[2]*256 + n[1]*65536 + n[0]*16777216
end

-- iterator for the index
function Dictionary:words()
    local offset = 0
    local mem = ffi.cast("uint8_t*", self.idx.mem)
    local size = self.idx.size
    return function ()
        if offset >= size then return nil end
        local word = ffi.string(mem + offset)
        offset = offset + word:len() + 1
        local word_offset = read_netorder_number(mem + offset)
        local word_size = read_netorder_number(mem + offset + 4)
        offset = offset + 8
        return word, word_offset, word_size
    end
end

-- reader interface for mmap'ed files
local function dict_mmap_reader(dict_mmap)
    local mem = ffi.cast("uint8_t*", dict_mmap.mem)
    local memsize = dict_mmap.size
    return function (offset, size)
        assert(offset + size <= memsize,
            "cannot read requested range")
        return ffi.string(mem + offset, size)
    end
end

-- this parses .dict file "words" into their elements
-- returns a table <type> => <element>
function Dictionary:parse_entry(data)
    local d = {}
    local pos = 1
    local tspos = 1
    while pos <= data:len() do
        local type = nil
        local len = nil
        if self.ifo.sametypesequence then
            -- order of occurring types is predefined
            type = self.ifo.sametypesequence:sub(tspos, 1)
            if tspos == self.ifo.sametypesequence:len() then
                -- last type in sequence does never specify its data length
                len = 1 + data:len() - pos
            end
            tspos = tspos + 1
        else
            type = data:sub(pos, 1)
            pos = pos + 1
        end
        if type:match("%l") then
            item = data:match("(.*)%z", pos)
            if not item then
                item = data:sub(pos) -- till the end
            end
            pos = pos + item:len() + 1
        else
            if not len then
                -- types with uppercase IDs have a length following the type ID
                len = data:byte(pos)*16777216 + data:byte(pos+1)*65536 + data:byte(pos+2)*256 + data:byte(pos+3)
                pos = pos + 4
            end
            item = data:sub(pos, len)
            pos = pos + len
        end
        d[type] = item
    end
    return d
end

function Dictionary:lookup_word(word)
    for w, o, s in self:words() do
        if w == word then
            return self:parse_entry(self.dict_reader(o, s))
        end
    end
end

-- list dictionaries in a directory
-- returns a table containing one metadata table
-- for each dictionary
function Dictionary.list(path)
    local dicts = {}
    for f in lfs.dir(path) do
        if f:match(".*%.ifo$") then
            local fpath = path .. "/" .. f
            local ok, data = pcall(parse_ifo, fpath)
            if ok then
                dicts[fpath] = data
            end
        end
    end
    return dicts
end

-- open a dictionary, return a Dictionary object
function Dictionary.open(name)
    local ifo = parse_ifo(name..".ifo")

    if not lfs.attributes(name..".idx", "mode") and lfs.attributes(name..".idx.gz", "mode") then
        -- we have a gzip'ed idx file
        error(".idx.gz is not yet implemented")
    end
    local idx_size = lfs.attributes(name..".idx", "size")
    assert(idx_size == tonumber(ifo.idxfilesize),
        name..".idx size does not match metadata, file corrupted?")
    local idx = MMapFile:open(name..".idx", idx_size)

    if not lfs.attributes(name..".dict", "mode") and lfs.attributes(name..".dict.dz", "mode") then
        -- we have a dict-zip'ed dict file
        error(".dict.dz is not yet implemented")
    end
    assert(not idx.offsetbits or tonumber(idx.offsetbits) == 32,
        "we can't handle dictionaries with offsetbits != 32 yet")

    local dict_size = lfs.attributes(name..".dict", "size")
    local dict = MMapFile:open(name..".dict", dict_size)
    local dict_reader = dict_mmap_reader(dict)

    return Dictionary:new({
        ifo = ifo,
        idx = idx,
        dict = dict,
        dict_reader = dict_reader
    })
end

return Dictionary
