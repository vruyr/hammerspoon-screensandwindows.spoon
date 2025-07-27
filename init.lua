local obj = {}
obj.__index = obj

function obj:init()
	self._screenWatcher = nil
	self._screenDrawings = {} -- Keys are arbitrary, values are list of hs.drawing objects.
	self._clearDrawingsHotkey = nil
end


function obj:startScreenWatcher()
	if self._screenWatcher then
		self._screenWatcher:stop()
	end
	self._screenWatcher = hs.screen.watcher.new(function()
		self:drawScreenLayout()
	end)
	self._screenWatcher:start()
end


function obj:maximizeFrontmostWindowOnScreenWithMouse()
	local the_window = hs.window.frontmostWindow()
	if not the_window then
		hs.alert.show("No frontmost window to maximize.")
		return
	end

	local screen_frame = hs.mouse.getCurrentScreen():frame()

	the_window:setFrame(screen_frame, 0)

	hs.alert.show(string.format("%d×%d", screen_frame.w, screen_frame.h))
end


function obj:moveFrontmostWindowToMousePosition()
	local the_window = hs.window.frontmostWindow()
	if not the_window then
		hs.alert.show("No frontmost window to move.")
		return
	end

	local mouse_pos = hs.mouse.absolutePosition()
	local screen_frame = hs.mouse.getCurrentScreen():frame()
	local window_frame = the_window:frame()

	window_frame.x = mouse_pos.x - math.ceil(window_frame.w / 2)
	window_frame.y = mouse_pos.y - math.ceil(window_frame.h / 2)
	window_frame = self:fitRectInFrame(window_frame, screen_frame)

	the_window:setFrame(window_frame, 0)

	hs.alert.show(string.format("%d×%d at (%d, %d)",
		window_frame.x,
		window_frame.y,
		window_frame.w,
		window_frame.h
	))
end


function obj:fitRectInFrame(rect, frame)
	rect.w = math.min(rect.w, frame.w)
	rect.h = math.min(rect.h, frame.h)

	rect.x = math.min(frame.x + frame.w - rect.w, math.max(rect.x, frame.x))
	rect.y = math.min(frame.y + frame.h - rect.h, math.max(rect.y, frame.y))

	return rect
end


function obj:registerDrawing(params)
	-- params: {
	--  parts: list of hs.drawing objects,
	--  duration: number, -- how long in seconds to show the drawing
	--  clearHotkey: {
	--    modifiers: list of strings, e.g. {"cmd", "ctrl"},
	--    key: string, -- e.g. "escape"
	--  }
	-- }
	local drawingId = {} -- Unique id for the drawing. Used similar to Symbol("foo") from JS.
	self._screenDrawings[drawingId] = params.drawingParts

	self:addClearDrawingsHotkey()

	hs.timer.doAfter(params.duration, function()
		self:clearDrawing(drawingId)
	end)
end


function obj:clearDrawing(drawingId)
	local drawingParts = self._screenDrawings[drawingId]
	if not drawingParts then
		return
	end
	for _, part in ipairs(drawingParts) do
		part:delete()
	end

	self._screenDrawings[drawingId] = nil

	if next(self._screenDrawings) == nil then
		self:removeClearDrawingsHotkey()
	end

end


function obj:clearAllDrawings()
	for key, drawingParts in pairs(self._screenDrawings) do
		for _, part in ipairs(drawingParts) do
			part:delete()
		end
	end

	self._screenDrawings = {}
	self:removeClearDrawingsHotkey()
end


function obj:addClearDrawingsHotkey()
	if self._clearDrawingsHotkey then
		return
	end

	local modifiers = {}
	local key = "escape"

	self._clearDrawingsHotkey = hs.hotkey.bind(modifiers, key, function()
		self:clearAllDrawings()
	end)
end


function obj:removeClearDrawingsHotkey()
	if self._clearDrawingsHotkey then
		self._clearDrawingsHotkey:delete()
		self._clearDrawingsHotkey = nil
	end
end


function obj:drawScreenLayout()
	-- Note that the drawing will appear on fullscreen apps only if
	-- Hammerspoon is not showing a dock icon.
	--
	-- See: https://github.com/Hammerspoon/hammerspoon/issues/1184

	-- Drawing Parameters
	local RECT_STROKE_WIDTH = 2
	local RECT_STROKE_COLOR = {red=1, green=1, blue=1, alpha=0.7}
	local RECT_FILL_COLOR = {red=0, green=0, blue=0, alpha=0.7}
	local RECT_INNER_MARGIN_PX = 10
	local LABEL_TEXT_STYLE = {
		font = { name = "Monaco", size = 12 },
		color = {red=1, green=1, blue=1, alpha=1},
		backgroundColor = nil, -- {red=1, green=1, blue=1, alpha=1}
		paragraphStyle = {
			alignment = "center"
		}
	}
	local DRAWING_OCCUPYED_AREA = 0.7
	local DRAWING_DURATION_SEC = 10
	local DRAWING_LEVEL = "overlay"

	local screens = hs.screen.allScreens()
	local mouseScreen = hs.mouse.getCurrentScreen()
	local mouseScreenFrame = mouseScreen:fullFrame()

	-- Find the bounding box multi-screen layout
	local minX, minY, maxX, maxY = nil, nil, nil, nil
	for _, screen in ipairs(screens) do
		local f = screen:fullFrame()
		minX = minX and math.min(minX, f.x) or f.x
		minY = minY and math.min(minY, f.y) or f.y
		maxX = maxX and math.max(maxX, f.x + f.w) or (f.x + f.w)
		maxY = maxY and math.max(maxY, f.y + f.h) or (f.y + f.h)
	end
	local layoutW = maxX - minX
	local layoutH = maxY - minY

	-- Position and scale of the drawing
	local scale = math.min(
		(mouseScreenFrame.w * DRAWING_OCCUPYED_AREA) / layoutW,
		(mouseScreenFrame.h * DRAWING_OCCUPYED_AREA) / layoutH
	)
	local offsetX = mouseScreenFrame.x + (mouseScreenFrame.w - layoutW * scale) / 2 - minX * scale
	local offsetY = mouseScreenFrame.y + (mouseScreenFrame.h - layoutH * scale) / 2 - minY * scale

	-- All drawings for this run will be stored in this list.
	local drawingParts = {}

	-- Draw all the screen rectangles and their labels
	for i, screen in ipairs(screens) do
		local f = screen:fullFrame()
		local x = f.x * scale + offsetX
		local y = f.y * scale + offsetY
		local w = f.w * scale
		local h = f.h * scale

		local screenDrawingInnerArea = hs.geometry.rect(
			x + RECT_STROKE_WIDTH + RECT_INNER_MARGIN_PX,
			y + RECT_STROKE_WIDTH + RECT_INNER_MARGIN_PX,
			w - (RECT_STROKE_WIDTH + RECT_INNER_MARGIN_PX) * 2,
			h - (RECT_STROKE_WIDTH + RECT_INNER_MARGIN_PX) * 2
		)

		local screenRect = hs.drawing.rectangle(hs.geometry.rect(x, y, w, h))
		screenRect:setStrokeColor(RECT_STROKE_COLOR)
		screenRect:setFillColor(RECT_FILL_COLOR)
		screenRect:setStrokeWidth(RECT_STROKE_WIDTH)
		screenRect:setLevel(DRAWING_LEVEL)
		screenRect:show()
		table.insert(drawingParts, screenRect)

		-- Screen Name
		table.insert(drawingParts, self:drawText{
			text = string.format("%s", screen:name()),
			style = LABEL_TEXT_STYLE,
			frame = screenDrawingInnerArea,
			position = {
				vertical = "center",
				horizontal = "center"
			},
			level = DRAWING_LEVEL,
			show = true
		})

		-- Screen Position
		table.insert(drawingParts, self:drawText{
			text = string.format("%d, %d", f.x, f.y),
			style = LABEL_TEXT_STYLE,
			frame = screenDrawingInnerArea,
			position = {
				vertical = "top",
				horizontal = "left"
			},
			level = DRAWING_LEVEL,
			show = true
		})

		-- Screen Dimensions
		table.insert(drawingParts, self:drawText{
			text = string.format("%d×%d", f.w, f.h),
			style = LABEL_TEXT_STYLE,
			frame = screenDrawingInnerArea,
			position = {
				vertical = "top",
				horizontal = "right"
			},
			level = DRAWING_LEVEL,
			show = true
		})

		-- Screen Number
		table.insert(drawingParts, self:drawText{
			text = string.format("#%d", i),
			style = LABEL_TEXT_STYLE,
			frame = screenDrawingInnerArea,
			position = {
				vertical = "bottom",
				horizontal = "left"
			},
			level = DRAWING_LEVEL,
			show = true
		})

		-- Screen ID
		table.insert(drawingParts, self:drawText{
			text = string.format("ID:%s", screen:id()),
			style = LABEL_TEXT_STYLE,
			frame = screenDrawingInnerArea,
			position = {
				vertical = "bottom",
				horizontal = "right"
			},
			level = DRAWING_LEVEL,
			show = true
		})

		-- hs.console.printStyledtext(string.format(
		-- 	"%s",
		-- 	hs.inspect(labelDimensionsTextSize)
		-- ))
	end

	self:clearAllDrawings()

	self:registerDrawing{
		drawingParts = drawingParts,
		duration = DRAWING_DURATION_SEC
	}
end


function obj:drawText(params)
	-- params: {
	--   text: string,
	--   style: hs.styledtext.style,
	--   frame: hs.geometry.rect,
	--   position: {
	--     vertical: "top" | "bottom" | "center",
	--     horizontal: "left" | "right" | "center",
	-- }
	--   level: "...",
	--   show: boolean
	-- }
	local text = hs.styledtext.new(params.text, params.style)
	local drawingSize = hs.drawing.getTextDrawingSize(text)

	local x, y = nil, nil

	if params.position.horizontal == "left" then
		x = params.frame.x
	elseif params.position.horizontal == "right" then
		x = params.frame.x + params.frame.w - drawingSize.w
	elseif params.position.horizontal == "center" then
		x = params.frame.x + (params.frame.w - drawingSize.w) / 2
	else
		x = params.frame.x
	end

	if params.position.vertical == "top" then
		y = params.frame.y
	elseif params.position.vertical == "bottom" then
		y = params.frame.y + params.frame.h - drawingSize.h
	elseif params.position.vertical == "center" then
		y = params.frame.y + (params.frame.h - drawingSize.h) / 2
	else
		y = params.frame.y
	end

	local drawingRect = hs.geometry.rect(x, y, drawingSize.w, drawingSize.h)
	local drawing = hs.drawing.text(drawingRect, text)

	if params.level then
		drawing:setLevel(params.level)
	end

	if params.show then
		drawing:show()
	end

	return drawing
end


return obj
