-- /bin/gui_demo.lua
-- Demo of the CargoControl GUI Library with per-frame responsive layout.

local gui = require("/LuaMade/CargoControl/gui_lib")

local manager = gui.GUIManager.new()
manager:setFrameDelayMs(33)

local mainPanel = gui.Panel.new(0, 0, 0, 0, "CargoControl - GUI Demo")
mainPanel:setBackgroundColor(0.1, 0.12, 0.18, 0.8)
mainPanel:setBorderColor(0.4, 0.6, 0.95, 0.9)

local statusPanel = gui.Panel.new(0, 0, 0, 0, "Fleet Status")
statusPanel:setBackgroundColor(0.08, 0.1, 0.15, 0.7)

local statusText1 = gui.Text.new(0, 0, "Active Ships: 5")
statusText1:setColor(0.8, 0.9, 1.0, 1.0)
local statusText2 = gui.Text.new(0, 0, "Cargo Capacity: 1250 / 2000 tons")
statusText2:setColor(0.8, 0.9, 1.0, 1.0)
local statusText3 = gui.Text.new(0, 0, "Average Route Efficiency: 87%")
statusText3:setColor(0.2, 0.95, 0.3, 1.0)

statusPanel:addChild(statusText1)
statusPanel:addChild(statusText2)
statusPanel:addChild(statusText3)

local controlPanel = gui.Panel.new(0, 0, 0, 0, "Control Center")
controlPanel:setBackgroundColor(0.08, 0.1, 0.15, 0.7)

local buttonLayout = gui.VerticalLayout.new(0, 0, 0, 2)

local newRequestBtn = gui.Button.new(0, 0, 18, 3, "New Request")
newRequestBtn:setNormalColor(0.15, 0.5, 0.8, 0.7)
newRequestBtn:setHoverColor(0.2, 0.6, 0.95, 0.8)
newRequestBtn:setOnPress(function()
    lastAction:setText("Last action: New Request")
end)

local assignFleetBtn = gui.Button.new(0, 0, 18, 3, "Assign Fleet")
assignFleetBtn:setNormalColor(0.15, 0.5, 0.8, 0.7)
assignFleetBtn:setHoverColor(0.2, 0.6, 0.95, 0.8)
assignFleetBtn:setOnPress(function()
    lastAction:setText("Last action: Assign Fleet")
end)

local repairBtn = gui.Button.new(0, 0, 18, 3, "Repair Ships")
repairBtn:setNormalColor(0.8, 0.5, 0.15, 0.7)
repairBtn:setHoverColor(0.95, 0.6, 0.2, 0.8)
repairBtn:setOnPress(function()
    lastAction:setText("Last action: Repair Ships")
end)

buttonLayout:addChild(newRequestBtn)
buttonLayout:addChild(assignFleetBtn)
buttonLayout:addChild(repairBtn)
controlPanel:addChild(buttonLayout)

local infoPanel = gui.Panel.new(0, 0, 0, 0, "Information")
infoPanel:setBackgroundColor(0.08, 0.1, 0.15, 0.7)

local infoText1 = gui.Text.new(0, 0, "GUI rescales every draw frame")
infoText1:setColor(0.9, 0.8, 0.3, 1.0)
local infoText2 = gui.Text.new(0, 0, "Console cleared on GUI start")
infoText2:setColor(0.9, 0.8, 0.3, 1.0)

-- Live feedback: updated by button callbacks.
local lastAction = gui.Text.new(0, 0, "Last action: none")
lastAction:setColor(0.5, 1.0, 0.6, 1.0)

infoPanel:addChild(infoText1)
infoPanel:addChild(infoText2)
infoPanel:addChild(lastAction)

mainPanel:addChild(statusPanel)
mainPanel:addChild(controlPanel)
mainPanel:addChild(infoPanel)
manager:addComponent(mainPanel)

manager:setLayoutCallback(function(_, w, h)
    mainPanel:setPosition(4, 4)
    mainPanel:setSize(math.max(20, w - 8), math.max(20, h - 8))

    local innerX = mainPanel.x + 4
    local innerW = math.max(12, mainPanel.width - 8)

    statusPanel:setPosition(innerX, mainPanel.y + 4)
    statusPanel:setSize(innerW, 12)

    statusText1:setPosition(statusPanel.x + 2, statusPanel.y + 3)
    statusText2:setPosition(statusPanel.x + 2, statusPanel.y + 5)
    statusText3:setPosition(statusPanel.x + 2, statusPanel.y + 7)

    controlPanel:setPosition(innerX, statusPanel.y + statusPanel.height + 2)
    controlPanel:setSize(innerW, 16)

    buttonLayout:setPosition(controlPanel.x + 2, controlPanel.y + 3)

    infoPanel:setPosition(innerX, controlPanel.y + controlPanel.height + 2)
    infoPanel:setSize(innerW, 10)

    infoText1:setPosition(infoPanel.x + 2, infoPanel.y + 3)
    infoText2:setPosition(infoPanel.x + 2, infoPanel.y + 5)
    lastAction:setPosition(infoPanel.x + 2, infoPanel.y + 7)
end)

manager:run(math.floor(30000 / 33))
