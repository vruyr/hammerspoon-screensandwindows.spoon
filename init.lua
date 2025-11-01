local utils = require("utils")

local obj = {}
obj.__index = obj

function obj:init()
	self._screenWatcher = nil
	self._screenDrawings = {} -- Keys are arbitrary, values are list of hs.drawing objects.
	self._clearDrawingsHotkey = nil
	self._moveAndMaximizeAlert = nil
	self._windowReizeAlert = nil
	self._numberOfTimesToTryToResize = 10 -- an arbitrary number
	self._didSystemChecksPass = nil
	self._moveMouseToCenterOfNextScreenLastTimeCalled = 0
	self._shrinkingCircleAnimation = nil
	self._previousLayout = nil


	local hotkeySettingsActual = hs.execute(
		hs.spoons.resourcePath("symbolichotkeys.swift") .. " 79 81"
	)
	local hotkeySettingsExpected = {
		"ON  Move left a space: Control-Left",
		"ON  Move right a space: Control-Right",
	}
	hotkeySettingsExpected = table.concat(hotkeySettingsExpected, "\n") .. "\n"
	self._didSystemChecksPass = (
		hotkeySettingsActual == hotkeySettingsExpected
	)
	print("Hotkeys:\n\n" .. hotkeySettingsActual)
	local msg = "Keyboard Shortcuts in System Settings are "
	if self._didSystemChecksPass then
		print(msg .. "configured as expected.")
	else
		print(msg .. "not configured to expectation.")
		print("Expected:\n\n" .. hotkeySettingsExpected)
	end

	self._NOFITICATION_SUCCESS = {
		style = {
			-- Rectangle
			fillColor   = { white = 0, green=0.1, alpha = 0.9 },
			strokeColor = { green=1, alpha=1 },
			strokeWidth = 2,
			radius      = 12,

			-- Text
			textColor       = { white = 1, alpha = 1 },
			textFont        = ".AppleSystemUIFont",
			textSize        = 27,
			textStyle       = nil,
			padding         = nil,
			atScreenEdge    = 0,
			fadeInDuration  = 0.15,
			fadeOutDuration = 0.15,
		},
		durationSec = 2,
	}

	self._NOFITICATION_FAILURE = {
		style = {
			-- Rectangle
			fillColor   = { white = 0, red=0.1, alpha = 0.9 },
			strokeColor = { red=1, alpha=1 },
			strokeWidth = 2,
			radius      = 12,

			-- Text
			textColor       = { white = 1, alpha = 1 },
			textFont        = ".AppleSystemUIFont",
			textSize        = 27,
			textStyle       = nil,
			padding         = nil,
			atScreenEdge    = 0,
			fadeInDuration  = 0.15,
			fadeOutDuration = 0.15,
		},
		durationSec = 5,
	}

	local function showNotification(params, msgFmt, ...)
		local msg = string.format(msgFmt, ...)
		local style = params.style
		local screen = hs.mouse.getCurrentScreen() or hs.screen.primaryScreen()
		local durationSec = params.durationSec
		return hs.alert.show(msg, style, screen, durationSec)
	end

	self._show_notification_success = function(msgFmt, ...)
		return showNotification(self._NOFITICATION_SUCCESS, msgFmt, ...)
	end

	self._show_notification_failure = function(msgFmt, ...)
		return showNotification(self._NOFITICATION_FAILURE, msgFmt, ...)
	end
end


function obj:didSystemChecksPass()
	return self._didSystemChecksPass
end


function GenFrameContentString(f)
	return string.format("%d,%d,%d,%d", f.x, f.y, f.w, f.h)
end


function GenScreenLayoutContentString(screen)
	return string.format(
		"%s:%s:%s:%s",
		screen:id(),
		screen:name(),
		GenFrameContentString(screen:fullFrame()),
		GenFrameContentString(screen:frame()),
		screen:currentMode().desc
	)
end


function obj:startScreenWatcher()
	if self._screenWatcher then
		self._screenWatcher:stop()
	end
	self._screenWatcher = hs.screen.watcher.new(function()
		local screens = hs.screen.allScreens()
		local currentLayout = ""
		for _, screen in ipairs(screens) do
			currentLayout = currentLayout .. GenScreenLayoutContentString(screen) .. ";"
		end
		if self._previousLayout ~= currentLayout then
			self._previousLayout = currentLayout
			self:drawScreenLayout(screens)
		end
	end)
	self._screenWatcher:start()
end


function obj:maximizeFrontmostWindowOnScreenWithMouse()
	local theWindow = hs.window.frontmostWindow()
	if not theWindow then
		self._show_notification_failure("No frontmost window to maximize.")
		return
	end

	local screenFrame = hs.mouse.getCurrentScreen():frame()

	self:setWindowFrame(theWindow, screenFrame)

	if self._moveAndMaximizeAlert then
		hs.alert.closeSpecific(self._moveAndMaximizeAlert)
	end
	self._moveAndMaximizeAlert = self._show_notification_success(
		"%d×%d", screenFrame.w, screenFrame.h
	)
end


function obj:moveFrontmostWindowToMousePosition()
	local theWindow = hs.window.frontmostWindow()
	if not theWindow then
		self._show_notification_failure("No frontmost window to move.")
		return
	end

	local mousePos = hs.mouse.absolutePosition()
	local screenFrame = hs.mouse.getCurrentScreen():frame()
	local windowFrame = theWindow:frame()

	windowFrame.x = mousePos.x - math.ceil(windowFrame.w / 2)
	windowFrame.y = mousePos.y - math.ceil(windowFrame.h / 2)
	windowFrame = self:fitRectInFrame(windowFrame, screenFrame)

	self:setWindowFrame(theWindow, windowFrame)

	if self._moveAndMaximizeAlert then
		hs.alert.closeSpecific(self._moveAndMaximizeAlert)
	end
	self._moveAndMaximizeAlert = self._show_notification_success(
		"%d×%d at (%d, %d)",
		windowFrame.x,
		windowFrame.y,
		windowFrame.w,
		windowFrame.h
	)
end


function obj:fitRectInFrame(rect, frame)
	rect.w = math.min(rect.w, frame.w)
	rect.h = math.min(rect.h, frame.h)

	rect.x = math.min(frame.x + frame.w - rect.w, math.max(rect.x, frame.x))
	rect.y = math.min(frame.y + frame.h - rect.h, math.max(rect.y, frame.y))

	return rect
end


function obj:setWindowFrame(window, frame)
	if window:isFullScreen() then
		window:setFullscreen(false)
		hs.timer.doAfter(1, function()
			self:setWindowFrame(window, frame)
		end)
		return
	end

	local attempts = 0
	while attempts <= self._numberOfTimesToTryToResize and window:frame() ~= frame do
		window:setFrame(frame, 0)
		attempts = attempts + 1
	end

	if attempts ~= 1 then
		print("Had " .. attempts .. " attempts at setting window frame.")
	end
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


function obj:drawScreenLayout(screens)
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

	local drawScreen = hs.mouse.getCurrentScreen() or hs.screen.primaryScreen()
	local drawScreenFrame = drawScreen:fullFrame()

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
		(drawScreenFrame.w * DRAWING_OCCUPYED_AREA) / layoutW,
		(drawScreenFrame.h * DRAWING_OCCUPYED_AREA) / layoutH
	)
	local offsetX = drawScreenFrame.x + (drawScreenFrame.w - layoutW * scale) / 2 - minX * scale
	local offsetY = drawScreenFrame.y + (drawScreenFrame.h - layoutH * scale) / 2 - minY * scale

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

		-- Screen Mode
		table.insert(drawingParts, self:drawText{
			text = screen:currentMode().desc,
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


function obj:addSpaceToScreen(screen, closeMC)
	-- Returns one of:
	--   Success: (spaceId, spaceIndex, spaceCount)
	--   Failure: (nil, nil, nil, errorText)

	if not screen then
		return nil, nil, nil, "ERROR: addSpaceToScreen was called with nil screen."
	end
	local screenUUID = screen:getUUID()
	local spacesBefore, err = hs.spaces.spacesForScreen(screenUUID)
	if not spacesBefore then
		return nil, nil, nil, "Failed to retrieve spaces for a screen: " .. tostring(err)
	end
	local ok, err = hs.spaces.addSpaceToScreen(screenUUID, closeMC)
	if not ok then
		return nil, nil, nil, "Failed to add a new space: " .. tostring(err)
	end
	local spacesAfter, err = hs.spaces.spacesForScreen(screenUUID)
	if not spacesAfter then
		return nil, nil, nil, "Failed to retrieve spaces for a screen: " .. tostring(err)
	end
	local newSpace = nil
	local newSpaceIndex = nil
	for index, space in ipairs(spacesAfter) do
		if not hs.fnutils.contains(spacesBefore, space) then
			newSpace = space
			newSpaceIndex = index
			break
		end
	end
	if not newSpace then
		return nil, nil, nil, "ERROR: Could not find the newly added space."
	end
	return newSpace, newSpaceIndex, #spacesAfter
end


function obj:addSpaceToScreenWithMouseAndSwitchToIt()
	-- Returns one of:
	--   Success: (newSpaceId, screen)
	--   Failure: (nil, screen, err)

	local screenWithMouse = hs.mouse.getCurrentScreen()
	if not screenWithMouse then
		return nil, nil, "No screen found under the mouse cursor."
	end
	local newSpaceId, newSpaceIndex, spaceCount, err = self:addSpaceToScreen(screenWithMouse, false)
	if not newSpaceId then
		return nil, screenWithMouse, "Failed to create a new space: " .. tostring(err)
	end

	local ok, err = hs.spaces.gotoSpace(newSpaceId)
	if not ok then
		return nil, screenWithMouse, "Failed to switch spaces: " .. tostring(err)
	end

	return newSpaceId, screenWithMouse
end


function obj:removeCurrentSpaceOnScreenWithMouse()
	if not self:didSystemChecksPass() then
		return nil, "The system configuration does not match expectation."
	end

	local screenWithMouse = hs.mouse.getCurrentScreen()
	if not screenWithMouse then
		return nil, "No screen found under the mouse cursor."
	end

	local screenWithMouseUuid = screenWithMouse:getUUID()
	local spaces, err = hs.spaces.spacesForScreen(screenWithMouseUuid)
	if not spaces then
		return nil, "Failed to retrieve spaces for a screen: " .. tostring(err)
	end
	local userSpaces = hs.fnutils.filter(spaces, function(space)
		local spaceType, err = hs.spaces.spaceType(space)
		if not spaceType then
			print("Failed to determine space type: ", space, hs.inspect(err))
			return false
		end
		return spaceType == "user"
	end)

	if #userSpaces < 2 then
		return nil, "Cannot remove the last user space on this screen."
	end

	local currentSpace, err = hs.spaces.activeSpaceOnScreen(screenWithMouseUuid)
	if not currentSpace then
		return nil, "Failed to get the current space for screen: " .. tostring(err)
	end

	local currentSpaceIndex = hs.fnutils.indexOf(spaces, currentSpace)
	local arrowKeyCode = (
		#spaces == currentSpaceIndex  -- if we are on the last space
		and hs.keycodes.map.left      -- switch to the previous space
		or hs.keycodes.map.right      -- otherswise to the next space
	)

	-- Moving the mouse to top of the scren will have Mission Control show previews.
	local mousePreviousPosition = hs.mouse.absolutePosition()
	hs.mouse.absolutePosition(screenWithMouse:fullFrame().topleft)

	hs.spaces.openMissionControl()

	hs.timer.doAfter(hs.spaces.MCwaitTime, function()
		hs.mouse.absolutePosition(mousePreviousPosition)

		-- Sending key events to Dock to switch spaces.
		-- The key combination is asserted during initalization.
		hs.application.launchOrFocus("Dock")
		hs.eventtap.event.newKeyEvent(hs.keycodes.map.ctrl, true):post()
		hs.eventtap.event.newKeyEvent(arrowKeyCode, true):post()
		hs.eventtap.event.newKeyEvent(arrowKeyCode, false):post()
		hs.eventtap.event.newKeyEvent(hs.keycodes.map.ctrl, false):post()

		local spaceChangeWatcher
		spaceChangeWatcher = hs.spaces.watcher.new(function()
			-- Even if `hs.spaces.removeSpace` fails,
			-- there is nothing much we can do.
			hs.spaces.removeSpace(currentSpace, true)
			spaceChangeWatcher:stop()
			spaceChangeWatcher = nil
		end)
		spaceChangeWatcher:start()
	end)

	return true
end


function obj:moveMouseToCenterOfNextScreen()
	-- If called multiple times within one second, cycles through screens.
	-- Otherwise, move to the screen of the frontmost window.

	local now = hs.timer.secondsSinceEpoch()
	local elapsed = now - self._moveMouseToCenterOfNextScreenLastTimeCalled

	local nextScreen

	if elapsed > 1 then
		nextScreen = hs.window.frontmostWindow():screen()
	else
		local currentScreen = hs.mouse.getCurrentScreen()
		nextScreen = (
			(currentScreen and currentScreen:next())
			or currentScreen
			or hs.screen.primaryScreen()
		)
	end

	self._moveMouseToCenterOfNextScreenLastTimeCalled = now

	if not nextScreen then
		self._show_notification_failure("Failed to find a screen to move the mouse to.")
		return
	end

	local nextFrame = nextScreen:frame()
	local nextMousePos = hs.geometry.new(nextFrame).center

	hs.mouse.absolutePosition(nextMousePos)
	self:startShrinkingCircleAnimation{
		centerPoint = nextMousePos,
		radiusFrom = 0.6 * (math.min(nextFrame.w, nextFrame.h) / 2),
		radiusTo = 16,
		animationDurationSec = 0.25,
		animationFrameRate = 30,
		strokeColor = {red = 1, green = 0, blue = 0, alpha = 1},
		strokeWidth = 1,
	}
end


function obj:startShrinkingCircleAnimation(params)
	-- params.centerPoint: {x: number, y: number}
	-- params.radiusFrom: number
	-- params.radiusTo: number
	-- params.animationDurationSec: number
	-- params.animationFrameRate: number
	-- params.strokeColor: {red: number, green: number, blue: number, alpha: number}
	-- params.strokeWidth: number

	if self._shrinkingCircleAnimation then
		self._shrinkingCircleAnimation.cancelled = true
		self._shrinkingCircleAnimation = nil
	end

	local theAnimation = {
		cancelled = false,
	}

	coroutine.wrap(function()
		local radius = params.radiusFrom

		local circle = hs.drawing.circle(hs.geometry.rect(
			params.centerPoint.x - radius,
			params.centerPoint.y - radius,
			radius * 2,
			radius * 2
		))

		circle:setStrokeColor(params.strokeColor)
		circle:setStrokeWidth(params.strokeWidth)
		circle:setFill(false)
		circle:setLevel("overlay")
		circle:show()

		local animationSteps = math.ceil(params.animationFrameRate * params.animationDurationSec)
		local radiusStep = (params.radiusFrom - params.radiusTo) / animationSteps
		local animationFrameDurationSec = params.animationDurationSec / animationSteps

		while not theAnimation.cancelled and radius > params.radiusTo do
			coroutine.applicationYield(animationFrameDurationSec)
			radius = radius - radiusStep

			circle:setSize(hs.geometry.size(radius * 2, radius * 2))
			circle:setTopLeft(hs.geometry.point(
				params.centerPoint.x - radius,
				params.centerPoint.y - radius
			))
		end

		circle:delete()
	end)()

	self._shrinkingCircleAnimation = theAnimation

	-- We don't need to clean up `self._shrinkingCircleAnimation` when the animation ends,
	-- because it has no state. The coroutine will die naturally.
end


obj.windowSizeFractions = {
	-- Must be sorted in ascending order.
	{ label = "1/4",  value = 1/4 },
	{ label = "1/3",  value = 1/3 },
	{ label = "1/2",  value = 1/2 },
	{ label = "2/3",  value = 2/3 },
	{ label = "3/4",  value = 3/4 },
	{ label = "Full", value = 1   },
}


function obj:resizeWindowToNextSize(window, direction, dimension)
	local widthOrHeight = dimension == "width" and "w" or "h"

	if not window then
		return nil, "resizeWindowToNextSize: no window provided."
	end

	local sizeSeekIndexFirst
	local sizeSeekIndexLast
	local sizeSeekStep

	-- Set up seek direction
	if direction == "grow" then
		-- First item larger than current size
		sizeSeekIndexFirst = 1
		sizeSeekIndexLast = #self.windowSizeFractions
	elseif direction == "shrink" then
		-- Last item smaller than current size
		sizeSeekIndexFirst = #self.windowSizeFractions
		sizeSeekIndexLast = 1
	else
		return nil, "resizeWindowToNextSize: direction must be \"shrink\" or \"grow\"."
	end

	-- Grow: 1, Shrink: -1
	sizeSeekStep = sizeSeekIndexFirst > sizeSeekIndexLast and -1 or 1

	-- Window and Screen Frames
	local screen = window:screen() or hs.mouse.getCurrentScreen() or hs.screen.primaryScreen()
	local screenFrame = screen:frame()
	local windowFrame = window:frame()

	local size = windowFrame[widthOrHeight]

	local nextSize

	nextSize = self.windowSizeFractions[sizeSeekIndexLast]
	for i = sizeSeekIndexFirst, sizeSeekIndexLast, sizeSeekStep do
		local candidateSize = self.windowSizeFractions[i].value * screenFrame[widthOrHeight]
		if math.floor((candidateSize - size) * sizeSeekStep) > 0 then
			nextSize = self.windowSizeFractions[i]
			break
		end
	end
	size = math.floor(screenFrame[widthOrHeight] * nextSize.value)

	if size ~= windowFrame[widthOrHeight] then
		windowFrame[widthOrHeight] = size
		self:setWindowFrame(window, self:fitRectInFrame(windowFrame, screenFrame))
	end

	local verb = sizeSeekStep == 1 and "Grown" or "Shrunk"
	if self._windowReizeAlert then
		hs.alert.closeSpecific(self._windowReizeAlert)
	end
	self._windowReizeAlert = self._show_notification_success("%s to %s\n%d×%d", verb, nextSize.label, windowFrame.w, windowFrame.h)
	return true
end


return obj
