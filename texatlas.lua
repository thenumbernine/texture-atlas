#!/usr/bin/env luajit
--[[
build a texture atlas from a directory of images
--]]
local path = require 'ext.path'
local table = require 'ext.table'
local tolua = require 'ext.tolua'
local vec2i = require 'vec-ffi.vec2i'
local box2i = require 'vec-ffi.box2i'
local Image = require 'image'
local cmdline = require 'ext.cmdline'.validate{
	srcdir = {desc='Where to read files from.'},
	size = {desc='(optional) What texture atlas size to first attempt.  Size is automatic and will keep doubling until a size that fits all textures is found.'},
	padding = {desc='(optional) What border to use between subimages.  Default is 1.'},
	borderTiled = {desc="(optional) A string-prefix to match to filenames, files that match this will have their pixels copied into the 'padding' area such that the image will blend tiled instead of to a border."},
	resample = {desc='(optional) Whether to resample all images to a specific size before adding them.'},
}(...)

local srcdir = path(assert(cmdline.srcdir, "expected srcdir=..."))

local padding = cmdline.padding
	and assert(tonumber(cmdline.padding), "failed to determine padding from "..tolua(cmdline.padding))
	or 1

-- this is optionally a set of prefixes for which whatever files prefix matches this, those files are tiled with a 1px border instead of padded.
local borderTiled = table(cmdline.borderTiled) --:mapi(function(v) return true, v end):setmetatable(nil)

local resample
if cmdline.resample then
	resample = vec2i(table.unpack(cmdline.resample))
end

local infos = table()
local totalPixels = 0
table.wrapfor(srcdir:rdir())
:mapi(function(vs)
	return vs[1]
end)
:filter(function(fn)
	return select(2, fn:getext()) == 'png'
end)
:sort(function(a,b) return a.path < b.path end)
:mapi(function(fn)
	print(fn)
	local img = Image(fn.path)
	print(fn, 'src channels', img.channels)
	img = img:rgba()
	if resample then	-- TODO pattern match, same as borderTiled
		img = img:resize(resample:unpack())
	end
	infos:insert{fn=fn.path, img=img}
	totalPixels = totalPixels + img.width * img.height
end)
infos:sort(function(a,b)
	if a.img.height == b.img.height then
		return a.fn < b.fn
	end
	-- sort by min width?
	--return a.img.width < b.img.width
	-- sort by min height?
	return a.img.height < b.img.height
	-- sort by min volume?
	--return a.img.width * a.img.height < b.img.width * b.img.height
end)
print('total pixels', totalPixels)
local sqrtTotalPixels = math.ceil(math.sqrt(totalPixels))
print('sqrt total pixels', sqrtTotalPixels)

local function rupow2(x)
	return 2^math.ceil(math.log(x,2))
end

local atlasSize
if cmdline.size then
	atlasSize = vec2i(table.unpack(cmdline.size))
else
	local texwidth = rupow2(sqrtTotalPixels)
	--local texheight = rupow2(totalPixels/texwidth)	-- this allows for height<width, but meh that's filling up so ...
	local texheight = texwidth
	print('round up by a bit', texwidth, texheight)
	atlasSize = vec2i(texwidth, texheight)
end

while true do
	print("trying with size " ..atlasSize)
	local atlasRect = box2i(vec2i(0,0), atlasSize-1)
	local filledup

	local function writeImages()
		local atlasImg = Image(atlasSize.x, atlasSize.y, 4, 'unsigned char'):clear()
		local wrote = 0
		local failed = 0
		for _,info in ipairs(infos) do
			if info.rect then
				print('writing', info.fn, 'at', info.rect.min)
				if borderTiled:find(nil, function(prefix) return info.fn:sub(1,#prefix) == prefix end) then
					-- padding is wrapped
					atlasImg:pasteInto{
						image = info.img:tile(
							info.img.width+2*padding,
							info.img.height+2*padding,
							padding,
							padding),
						x = info.rect.min.x,
						y = info.rect.min.y,
					}
				else
					-- padding is transparent
					atlasImg:pasteInto{
						image = info.img,
						x = info.rect.min.x + padding,
						y = info.rect.min.y + padding,
					}
				end
				wrote = wrote + 1
			else
				failed = failed + 1
			end
		end
		atlasImg:save'atlas.png'
		path'atlas.lua':write(
			tolua(
				infos:mapi(function(info)
					if not info.rect then return nil end
					return {
						pos={
							info.rect.min.x + padding,
							info.rect.min.y + padding,
						},
						size={
							info.img.width,
							info.img.height
						},
					}, info.fn
				end):setmetatable(nil)
			)
		)
		print("wrote "..wrote.." images")
		print("failed to write "..failed.." images")
	end

	local function touchesAny(rect)
		if not atlasRect:contains(rect) then
			print("failed by "..rect.." being outside "..atlasRect)
			return true
		end
		for _,info in ipairs(infos) do
			if info.rect
			and info.rect:touches(rect) then
				print("failed by "..rect.." touching "..info.rect)
				return true
			end
		end
	end

	local function calcRects()
		-- clear all rects
		for _,info in ipairs(infos) do
			info.rect = nil
		end
		local pos = vec2i(0,0)
		for _,info in ipairs(infos) do
			local img = info.img
			local imgsize = vec2i(img.width, img.height) + 2 * padding
			local newrect
			while true do
				newrect = box2i(
					pos,
					pos + imgsize - 1)	-- [incl,incl]
	--print("testing touch of "..newrect)
				if not touchesAny(newrect) then
					break
				end
	--print('testing at', pos)
				pos.x = pos.x + imgsize.x
				if pos.x + imgsize.x >= atlasSize.x then
					pos.x = 0

					pos.y = 0
					for _,info2 in ipairs(infos) do
						if info2.rect then
							pos.y = math.max(pos.y, info2.rect.max.y+1)
						end
					end
					if pos.y + imgsize.y >= atlasSize.y then
						filledup = true
						return
					end
				end
			end
			info.rect = newrect
	--		print('inserting', info.fn, 'at', info.rect)
			pos.x = pos.x + imgsize.x
		end

		writeImages()
	end

	filledup = false
	calcRects()
	if not filledup then break end
	if atlasSize.x > atlasSize.y then
		atlasSize.y = atlasSize.y * 2
	else
		atlasSize.x = atlasSize.x * 2
	end
	print("filled up ...")
end
