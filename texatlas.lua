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

local srcdir, padding = ...
assert(srcdir, "expected srcdir")
if type(padding) == 'string' then
	padding = assert(tonumber(padding), "failed to read padding")
else
	padding = 1
end
local srcdir = path(srcdir)
local infos = table()
local totalPixels = 0
local fns = srcdir:rdir():filter(function(fn)
	local srcpath = path(fn)
	return select(2, srcpath:getext()) == 'png'
end)
for _,fn in ipairs(fns) do
	print(fn)
	local img = Image(fn)
	infos:insert{fn=tostring(path(fn)), img=img}
	totalPixels = totalPixels + img.width * img.height
end
infos:sort(function(a,b)
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
local texwidth = rupow2(sqrtTotalPixels)
--local texheight = rupow2(totalPixels/texwidth)	-- this allows for height<width, but meh that's filling up so ...
local texheight = texwidth
print('round up by a bit', texwidth, texheight)
local atlasSize = vec2i(texwidth, texheight)
local atlasRect = box2i(vec2i(0,0), atlasSize-1)

local function writeImages()
	local atlasImg = Image(atlasSize.x, atlasSize.y, 4, 'unsigned char'):clear()
	local wrote = 0
	local failed = 0
	for _,info in ipairs(infos) do
		if info.rect then
			print('writing', info.fn, 'at', info.rect.min)
			atlasImg:pasteInto{
				image = info.img,
				x = info.rect.min.x + padding,
				y = info.rect.min.y + padding
			}
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
	-- clear rects
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

					writeImages()

					error("filled up")
				end
			end
		end
		info.rect = newrect
--		print('inserting', info.fn, 'at', info.rect)
		pos.x = pos.x + imgsize.x
	end

	writeImages()
end

calcRects()
