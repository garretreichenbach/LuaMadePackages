-- /lib/gui_lib.lua
-- CargoControl GUI Library
-- Reusable, resize-aware GUI components for LuaMade gfx.

local GUI = {}

local function clamp(v, minV, maxV)
    if v < minV then
        return minV
    end
    if v > maxV then
        return maxV
    end
    return v
end

local function round(n)
    return math.floor(n + 0.5)
end

-- ============================================================================
-- GUIManager: Main controller for GUI rendering and events
-- ============================================================================

local GUIManager = {}
GUIManager.__index = GUIManager

function GUIManager.new()
    local self = setmetatable({}, GUIManager)
    self.components = {}
    self.layers = {
        background = 0,
        grid = 2,
        panels = 4,
        components = 6,
        overlay = 8,
        effects = 10,
    }
    self.width = gfx.getWidth()
    self.height = gfx.getHeight()
    self.frameCount = 0
    self.running = false
    self.frameDelayMs = 33 -- ~30 FPS
    self.layoutCallback = nil
    self.clearConsoleOnStart = true

    self.backgroundColor = { r = 0.03, g = 0.04, b = 0.07, a = 0.88 }
    self.borderColor = { r = 0.22, g = 0.4, b = 0.95, a = 0.85 }

    self:_clearConsole()
    self:_initializeLayers()

    return self
end

function GUIManager:_clearConsole()
    -- Clear terminal text so stale output does not interfere with gfx overlays.
    if term and term.clear and term.setCursorPos then
        term.clear()
        term.setCursorPos(1, 1)
    end
end

function GUIManager:_initializeLayers()
    for name, order in pairs(self.layers) do
        gfx.createLayer(name, order)
    end
end

function GUIManager:_rebuildLayers()
    gfx.clear()
    for name, order in pairs(self.layers) do
        gfx.createLayer(name, order)
    end
end

function GUIManager:_clearDynamicLayers()
    -- Clear per-frame layers to avoid command accumulation hitting gfx limits.
    gfx.clearLayer("grid")
    gfx.clearLayer("panels")
    gfx.clearLayer("components")
    gfx.clearLayer("overlay")
    gfx.clearLayer("effects")
end

function GUIManager:_checkWindowResize()
    local newWidth = gfx.getWidth()
    local newHeight = gfx.getHeight()
    if newWidth ~= self.width or newHeight ~= self.height then
        self.width = newWidth
        self.height = newHeight
        self:_rebuildLayers()
        return true
    end
    return false
end

function GUIManager:_drawBackground()
    gfx.setLayer("background")
    gfx.clearLayer("background")

    gfx.rect(
        0,
        0,
        self.width,
        self.height,
        self.backgroundColor.r,
        self.backgroundColor.g,
        self.backgroundColor.b,
        self.backgroundColor.a,
        true
    )

    gfx.rect(
        2,
        2,
        math.max(0, self.width - 4),
        math.max(0, self.height - 4),
        self.borderColor.r,
        self.borderColor.g,
        self.borderColor.b,
        self.borderColor.a,
        false
    )
end

function GUIManager:_applyLayout()
    if self.layoutCallback then
        self.layoutCallback(self, self.width, self.height)
    end

    for _, component in ipairs(self.components) do
        if component.applyLayout then
            component:applyLayout(self.width, self.height)
        end
    end
end

function GUIManager:addComponent(component)
    table.insert(self.components, component)
    if component.setManager then
        component:setManager(self)
    else
        component.manager = self
    end
end

function GUIManager:removeComponent(component)
    for i, comp in ipairs(self.components) do
        if comp == component then
            table.remove(self.components, i)
            break
        end
    end
end

function GUIManager:update(deltaTime)
    for _, component in ipairs(self.components) do
        if component.update then
            component:update(deltaTime)
        end
    end
end

function GUIManager:draw()
    self:_checkWindowResize()
    self:_applyLayout()
    self:_drawBackground()
    self:_clearDynamicLayers()

    for _, component in ipairs(self.components) do
        if component:isVisible() then
            component:draw()
        end
    end

    self.frameCount = self.frameCount + 1
end

function GUIManager:_dispatchMouseEvent(e)
    -- Walk component list back-to-front so topmost (last added) gets priority.
    for i = #self.components, 1, -1 do
        local comp = self.components[i]
        if comp:isVisible() and comp.onMouseEvent then
            if comp:onMouseEvent(e) then
                return -- event consumed by a component
            end
        end
    end
end

function GUIManager:run(maxFrames)
    self.running = true
    self.frameCount = 0
    maxFrames = maxFrames or math.huge

    if self.clearConsoleOnStart then
        self:_clearConsole()
    end

    -- Own the mouse so clicks do not reach the terminal text layer.
    input.clear()
    input.consumeMouse()

    while self.running and self.frameCount < maxFrames do
        local deltaTime = self.frameDelayMs / 1000

        -- input.waitFor replaces util.sleep: delivers mouse events while still
        -- yielding for the same frame-delay duration on timeout.
        local e = input.waitFor(self.frameDelayMs)
        if e and e.type == "mouse" then
            self:_dispatchMouseEvent(e)
        end

        self:update(deltaTime)
        self:draw()
    end

    self.running = false
end

function GUIManager:stop()
    self.running = false
end

function GUIManager:setFrameDelayMs(delayMs)
    self.frameDelayMs = math.max(1, math.floor(delayMs or 33))
end

function GUIManager:setBackgroundColor(r, g, b, a)
    self.backgroundColor = { r = r, g = g, b = b, a = a }
end

function GUIManager:setBorderColor(r, g, b, a)
    self.borderColor = { r = r, g = g, b = b, a = a }
end

function GUIManager:setLayoutCallback(callback)
    self.layoutCallback = callback
end

GUI.GUIManager = GUIManager

-- ============================================================================
-- Component: Base class for all UI components
-- ============================================================================

local Component = {}
Component.__index = Component

function Component.new(x, y, width, height)
    local self = setmetatable({}, Component)
    self.x = x or 0
    self.y = y or 0
    self.width = width or 0
    self.height = height or 0
    self.visible = true
    self.manager = nil
    self.layer = "components"
    self.children = nil

    self.relativeRect = nil
    self.layoutCallback = nil

    return self
end

function Component:setManager(manager)
    self.manager = manager
    if self.children then
        for _, child in ipairs(self.children) do
            if child.setManager then
                child:setManager(manager)
            else
                child.manager = manager
            end
        end
    end
end

function Component:setPosition(x, y)
    self.x = x
    self.y = y
end

function Component:setSize(width, height)
    self.width = width
    self.height = height
end

function Component:getPosition()
    return self.x, self.y
end

function Component:getSize()
    return self.width, self.height
end

function Component:setVisible(visible)
    self.visible = visible
end

function Component:isVisible()
    return self.visible
end

function Component:setLayer(layerName)
    self.layer = layerName
end

function Component:setRelativeRect(rx, ry, rw, rh)
    -- Relative rectangle to current canvas: all values normalized in [0, 1].
    self.relativeRect = { rx = rx, ry = ry, rw = rw, rh = rh }
end

function Component:setLayoutCallback(callback)
    self.layoutCallback = callback
end

function Component:applyLayout(canvasW, canvasH)
    if self.relativeRect then
        local rx = clamp(self.relativeRect.rx, 0, 1)
        local ry = clamp(self.relativeRect.ry, 0, 1)
        local rw = clamp(self.relativeRect.rw, 0, 1)
        local rh = clamp(self.relativeRect.rh, 0, 1)
        self.x = round(canvasW * rx)
        self.y = round(canvasH * ry)
        self.width = math.max(0, round(canvasW * rw))
        self.height = math.max(0, round(canvasH * rh))
    end

    if self.layoutCallback then
        self.layoutCallback(self, canvasW, canvasH)
    end

    if self.children then
        for _, child in ipairs(self.children) do
            if child.applyLayout then
                child:applyLayout(canvasW, canvasH)
            end
        end
    end
end

function Component:pointInBounds(px, py)
    return px >= self.x and px < (self.x + self.width) and py >= self.y and py < (self.y + self.height)
end

function Component:draw()
end

function Component:update(_deltaTime)
end

-- Returns true if the event was consumed (stops further propagation).
function Component:onMouseEvent(_e)
    return false
end

GUI.Component = Component

-- ============================================================================
-- Panel: Container component for grouping other elements
-- ============================================================================

local Panel = setmetatable({}, { __index = Component })
Panel.__index = Panel

function Panel.new(x, y, width, height, title)
    local self = setmetatable(Component.new(x, y, width, height), Panel)
    self.title = title or ""
    self.backgroundColor = { r = 0.1, g = 0.12, b = 0.18, a = 0.8 }
    self.borderColor = { r = 0.4, g = 0.6, b = 0.95, a = 0.9 }
    self.titleColor = { r = 0.8, g = 0.9, b = 1.0, a = 1.0 }
    self.children = {}
    self.layer = "panels"
    return self
end

function Panel:setBackgroundColor(r, g, b, a)
    self.backgroundColor = { r = r, g = g, b = b, a = a }
end

function Panel:setBorderColor(r, g, b, a)
    self.borderColor = { r = r, g = g, b = b, a = a }
end

function Panel:addChild(component)
    table.insert(self.children, component)
    if self.manager and component.setManager then
        component:setManager(self.manager)
    elseif self.manager then
        component.manager = self.manager
    end
end

function Panel:removeChild(component)
    for i, child in ipairs(self.children) do
        if child == component then
            table.remove(self.children, i)
            break
        end
    end
end

function Panel:update(deltaTime)
    for _, child in ipairs(self.children) do
        if child.update then
            child:update(deltaTime)
        end
    end
end

function Panel:onMouseEvent(e)
    -- Forward to children back-to-front so topmost child gets first pick.
    for i = #self.children, 1, -1 do
        local child = self.children[i]
        if child:isVisible() and child.onMouseEvent then
            if child:onMouseEvent(e) then
                return true
            end
        end
    end
    return false
end

function Panel:draw()
    if not self.manager then
        return
    end

    gfx.setLayer(self.layer)
    gfx.rect(
        self.x,
        self.y,
        self.width,
        self.height,
        self.backgroundColor.r,
        self.backgroundColor.g,
        self.backgroundColor.b,
        self.backgroundColor.a,
        true
    )

    gfx.rect(
        self.x,
        self.y,
        self.width,
        self.height,
        self.borderColor.r,
        self.borderColor.g,
        self.borderColor.b,
        self.borderColor.a,
        false
    )

    if self.title ~= "" then
        gfx.text(
            self.x + 3,
            self.y + 2,
            self.title,
            self.titleColor.r,
            self.titleColor.g,
            self.titleColor.b,
            self.titleColor.a,
            1
        )
    end

    for _, child in ipairs(self.children) do
        if child:isVisible() then
            child:draw()
        end
    end
end

GUI.Panel = Panel

-- ============================================================================
-- Button: Interactive button component
-- ============================================================================

local Button = setmetatable({}, { __index = Component })
Button.__index = Button

function Button.new(x, y, width, height, label, onPress)
    local self = setmetatable(Component.new(x, y, width, height), Button)
    self.label = label or "Button"
    self.onPress = onPress or function()
    end
    self.hovered = false
    self.pressed = false

    self.backgroundColor = { r = 0.15, g = 0.5, b = 0.8, a = 0.7 }
    self.hoverColor = { r = 0.2, g = 0.6, b = 0.95, a = 0.8 }
    self.pressedColor = { r = 0.1, g = 0.4, b = 0.7, a = 0.9 }
    self.borderColor = { r = 0.6, g = 0.8, b = 1.0, a = 0.9 }
    self.textColor = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 }
    self.layer = "components"

    return self
end

function Button:setLabel(label)
    self.label = label
end

function Button:setOnPress(callback)
    self.onPress = callback or function()
    end
end

function Button:setNormalColor(r, g, b, a)
    self.backgroundColor = { r = r, g = g, b = b, a = a }
end

function Button:setHoverColor(r, g, b, a)
    self.hoverColor = { r = r, g = g, b = b, a = a }
end

function Button:setPressedColor(r, g, b, a)
    self.pressedColor = { r = r, g = g, b = b, a = a }
end

function Button:update(_deltaTime)
end

function Button:onMouseEvent(e)
    if not e.insideCanvas then
        self.hovered = false
        self.pressed = false
        return false
    end

    local inside = self:pointInBounds(e.uiX, e.uiY)

    if e.pressed and e.button == "left" then
        if inside then
            self.pressed = true
            self.hovered = true
            return true
        end
    elseif e.released and e.button == "left" then
        local wasPressed = self.pressed
        self.pressed = false
        self.hovered = inside
        if wasPressed and inside then
            self.onPress()
            return true
        end
    else
        -- Continuous hover tracking on mouse move / drag.
        self.hovered = inside
        if not inside then
            self.pressed = false
        end
    end

    return false
end

function Button:draw()
    if not self.manager then
        return
    end

    gfx.setLayer(self.layer)

    local color = self.backgroundColor
    if self.pressed then
        color = self.pressedColor
    elseif self.hovered then
        color = self.hoverColor
    end

    gfx.rect(self.x, self.y, self.width, self.height, color.r, color.g, color.b, color.a, true)
    gfx.rect(
        self.x,
        self.y,
        self.width,
        self.height,
        self.borderColor.r,
        self.borderColor.g,
        self.borderColor.b,
        self.borderColor.a,
        false
    )

    local labelLen = string.len(self.label)
    local centerX = self.x + math.max(0, math.floor((self.width - labelLen) * 0.5))
    local centerY = self.y + math.floor(self.height * 0.5)

    gfx.text(
        centerX,
        centerY,
        self.label,
        self.textColor.r,
        self.textColor.g,
        self.textColor.b,
        self.textColor.a,
        1,
        self.width,
        self.height,
        "center",
        false
    )
end

GUI.Button = Button

-- ============================================================================
-- Text: Simple text display component
-- ============================================================================

local Text = setmetatable({}, { __index = Component })
Text.__index = Text

function Text.new(x, y, content)
    local self = setmetatable(Component.new(x, y, 0, 1), Text)
    self.content = content or ""
    self.color = { r = 1.0, g = 1.0, b = 1.0, a = 1.0 }
    self.scale = 1
    self.maxWidth = nil
    self.maxHeight = nil
    self.align = "left"
    self.wrap = false
    self.layer = "components"

    self:updateSize()
    return self
end

function Text:setText(content)
    self.content = content or ""
    self:updateSize()
end

function Text:setColor(r, g, b, a)
    self.color = { r = r, g = g, b = b, a = a }
end

function Text:setScale(scale)
    self.scale = math.max(1, math.floor(scale or 1))
    self:updateSize()
end

function Text:setLayout(maxWidth, maxHeight, align, wrap)
    self.maxWidth = maxWidth
    self.maxHeight = maxHeight
    self.align = align or "left"
    self.wrap = wrap == true
end

function Text:updateSize()
    local lines = 1
    for _ in string.gmatch(self.content, "\n") do
        lines = lines + 1
    end
    self.width = string.len(self.content) * self.scale
    self.height = lines * self.scale
end

function Text:draw()
    if not self.manager then
        return
    end

    gfx.setLayer(self.layer)
    gfx.text(
        self.x,
        self.y,
        self.content,
        self.color.r,
        self.color.g,
        self.color.b,
        self.color.a,
        self.scale,
        self.maxWidth,
        self.maxHeight,
        self.align,
        self.wrap
    )
end

GUI.Text = Text

-- ============================================================================
-- HorizontalLayout: Arranges children left-to-right
-- ============================================================================

local HorizontalLayout = setmetatable({}, { __index = Component })
HorizontalLayout.__index = HorizontalLayout

function HorizontalLayout.new(x, y, height, spacing)
    local self = setmetatable(Component.new(x, y, 0, height or 0), HorizontalLayout)
    self.spacing = spacing or 2
    self.children = {}
    self.layer = "components"
    return self
end

function HorizontalLayout:addChild(component)
    table.insert(self.children, component)
    if self.manager and component.setManager then
        component:setManager(self.manager)
    elseif self.manager then
        component.manager = self.manager
    end
    self:recalculateLayout()
end

function HorizontalLayout:removeChild(component)
    for i, child in ipairs(self.children) do
        if child == component then
            table.remove(self.children, i)
            self:recalculateLayout()
            break
        end
    end
end

function HorizontalLayout:recalculateLayout()
    local currentX = self.x
    for _, child in ipairs(self.children) do
        child:setPosition(currentX, self.y)
        currentX = currentX + child.width + self.spacing
    end
    self.width = math.max(0, currentX - self.x - self.spacing)
end

function HorizontalLayout:setPosition(x, y)
    Component.setPosition(self, x, y)
    self:recalculateLayout()
end

function HorizontalLayout:update(deltaTime)
    for _, child in ipairs(self.children) do
        if child.update then
            child:update(deltaTime)
        end
    end
end

function HorizontalLayout:onMouseEvent(e)
    for i = #self.children, 1, -1 do
        local child = self.children[i]
        if child:isVisible() and child.onMouseEvent then
            if child:onMouseEvent(e) then
                return true
            end
        end
    end
    return false
end

function HorizontalLayout:draw()
    for _, child in ipairs(self.children) do
        if child:isVisible() then
            child:draw()
        end
    end
end

GUI.HorizontalLayout = HorizontalLayout

-- ============================================================================
-- VerticalLayout: Arranges children top-to-bottom
-- ============================================================================

local VerticalLayout = setmetatable({}, { __index = Component })
VerticalLayout.__index = VerticalLayout

function VerticalLayout.new(x, y, width, spacing)
    local self = setmetatable(Component.new(x, y, width or 0, 0), VerticalLayout)
    self.spacing = spacing or 1
    self.children = {}
    self.layer = "components"
    return self
end

function VerticalLayout:addChild(component)
    table.insert(self.children, component)
    if self.manager and component.setManager then
        component:setManager(self.manager)
    elseif self.manager then
        component.manager = self.manager
    end
    self:recalculateLayout()
end

function VerticalLayout:removeChild(component)
    for i, child in ipairs(self.children) do
        if child == component then
            table.remove(self.children, i)
            self:recalculateLayout()
            break
        end
    end
end

function VerticalLayout:recalculateLayout()
    local currentY = self.y
    for _, child in ipairs(self.children) do
        child:setPosition(self.x, currentY)
        currentY = currentY + child.height + self.spacing
    end
    self.height = math.max(0, currentY - self.y - self.spacing)
end

function VerticalLayout:setPosition(x, y)
    Component.setPosition(self, x, y)
    self:recalculateLayout()
end

function VerticalLayout:update(deltaTime)
    for _, child in ipairs(self.children) do
        if child.update then
            child:update(deltaTime)
        end
    end
end

function VerticalLayout:onMouseEvent(e)
    for i = #self.children, 1, -1 do
        local child = self.children[i]
        if child:isVisible() and child.onMouseEvent then
            if child:onMouseEvent(e) then
                return true
            end
        end
    end
    return false
end

function VerticalLayout:draw()
    for _, child in ipairs(self.children) do
        if child:isVisible() then
            child:draw()
        end
    end
end

GUI.VerticalLayout = VerticalLayout

return GUI
