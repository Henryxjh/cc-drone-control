local controller = 1

local modem = peripheral.find("modem")
if modem == nil or not modem.isWireless() then
    os.reboot()
end

local power = false
local targetX
local targetZ
local statusMessage

redstone.setOutput("top", false)
rednet.open(peripheral.getName(modem))

local function drawUi()
    term.clear()
    term.setCursorPos(1, 1)
    print("Drone Power Controller")
    print("")
    print("Power: " .. (power and "ON" or "OFF"))

    local x, y, z = gps.locate(0.25, false)
    if x == nil then
        print("Position: UNKNOWN")
    else
        print(("Position: %.2f %.2f %.2f"):format(x, y, z))
    end

    if targetX == nil then
        print("Custom target: NONE")
    else
        print(("Custom target: %.2f %.2f"):format(targetX, targetZ))
    end

    print("")
    print("Enter: toggle power")
    print("N: set custom target")
    print("C: clear custom target")

    if statusMessage then
        print("")
        print(statusMessage)
    end
end

local function setPower(enabled)
    power = enabled
    redstone.setOutput("top", power)
end

local function networkLoop()
    while true do
        local sender, message, protocol = rednet.receive()
        if sender == controller and protocol == "powerset" and type(message) == "boolean" then
            setPower(message)
            rednet.send(controller, power, "powersetresp")
            os.queueEvent("power_ui_refresh")
        elseif sender == controller and protocol == "poweroff" then
            setPower(false)
            rednet.send(controller, power, "powersetresp")
            os.queueEvent("power_ui_refresh")
        elseif sender == controller and protocol == "powerstatus" then
            rednet.send(controller, power, "powerresp")
        elseif sender == controller and protocol == "powerpos" then
            local x, y, z = gps.locate()
            rednet.send(controller, {"power", x, y, z}, "powerposresp")
        elseif sender == controller and protocol == "power" then
            setPower(not power)
            rednet.send(controller, power, "powerresp")
            os.queueEvent("power_ui_refresh")
        elseif sender == controller and protocol == "customnavresp" then
            statusMessage = message and "Custom target accepted" or "Custom target rejected"
            os.queueEvent("power_ui_refresh")
        elseif sender == controller and protocol == "customnavget" then
            if targetX == nil then
                rednet.send(controller, false, "customnav")
            else
                rednet.send(controller, {targetX, targetZ}, "customnav")
            end
        end
    end
end

local function readCoordinate(name)
    term.write(name .. ": ")
    return tonumber(read())
end

local function inputCustomTarget()
    term.clear()
    term.setCursorPos(1, 1)
    print("Enter custom navigation target")
    local x = readCoordinate("X")
    local z = readCoordinate("Z")

    if x == nil or z == nil then
        statusMessage = "Invalid coordinate"
        return
    end

    targetX = x
    targetZ = z
    statusMessage = "Sending custom target..."
    rednet.send(controller, {x, z}, "customnav")
end

local function uiLoop()
    drawUi()
    while true do
        local event, key = os.pullEvent()
        if event == "key" and key == keys.enter then
            setPower(not power)
            rednet.send(controller, power, "powerresp")
            statusMessage = nil
            drawUi()
        elseif event == "key" and key == keys.n then
            inputCustomTarget()
            drawUi()
        elseif event == "key" and key == keys.c then
            targetX = nil
            targetZ = nil
            statusMessage = "Clearing custom target..."
            rednet.send(controller, false, "customnav")
            drawUi()
        elseif event == "power_ui_refresh" then
            drawUi()
        end
    end
end

parallel.waitForAll(networkLoop, uiLoop)
