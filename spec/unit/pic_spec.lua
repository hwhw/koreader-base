local DrawContext = require("ffi/drawcontext")
local BB = require("ffi/blitbuffer")
local Pic = require("ffi/pic")

Pic.color = true

local SAMPLE_JPG = "spec/base/unit/data/sample.jpg"

describe("Pic module", function()
    describe("basic API", function()
        it("should return error on unkonw format", function()
            assert.has_error(function()
                Pic.openDocument("/mnt/yolo.jpgwtffmt")
            end, "Unsupported image format")
        end)
    end)

    describe("JPG support", function()
        local d

        setup(function()
            d = Pic.openDocument(SAMPLE_JPG)
        end)

        it("should load jpg file", function()
            assert.are_not.equal(d, nil)
        end)
        it("should be able to get image size", function()
            local page = d:openPage()
            local dc_null = DrawContext.new()
            assert.are.same({d:getOriginalPageSize()}, {313, 234, 3})
            assert.are_not.equal(page, nil)
            assert.are.same({page:getSize(dc_null)}, {313, 234})
            page:close()
        end)
        it("should return emtpy table of content", function()
            assert.are.same(d:getToc(), {})
        end)
        it("should return 1 as number of pages", function()
            assert.are.same(d:getPages(), 1)
        end)
        it("should return 0 as cache size", function()
            assert.are.same(d:getCacheSize(), 0)
        end)
        it("should render JPG as inverted BB properly", function()
            local page = d:openPage()
            local dc_null = DrawContext.new()
            local tmp_bb = BB.new(d.width, d.height, BB.TYPE_BBRGB24)
            --@TODO check against digest  15.06 2014 (houqp)
            page:draw(dc_null, tmp_bb)
            tmp_bb:invert()
            tmp_bb:writePAM("/home/vagrant/koreader/out.pam")
            local c = tmp_bb:getPixel(0, 0)
            assert.are.same(c.r, 0xB1)
            assert.are.same(c.g, 0xA4)
            assert.are.same(c.b, 0xC2)
            c = tmp_bb:getPixel(1, 0)
            assert.are.same(c.r, 0xB3)
            assert.are.same(c.g, 0xA6)
            assert.are.same(c.b, 0xC4)
            c = tmp_bb:getPixel(2, 0)
            assert.are.same(c.r, 0xB7)
            assert.are.same(c.g, 0xAA)
            assert.are.same(c.b, 0xC8)
            page:close()
        end)

        teardown(function()
            d:close()
        end)
    end)
end)
