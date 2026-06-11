local controller = 1

local modem = peripheral.find("modem")
if modem == nil or not modem.isWireless() then
    os.reboot()
end

local power = false
redstone.setOutput("top", false)

rednet.open(peripheral.getName(modem))

while true do
    local sender, message, rprotocol = rednet.receive()
    if sender == controller and rprotocol == "powerset" and type(message) == "boolean" then
        power = message
        redstone.setOutput("top", power)
        rednet.send(controller, power, "powersetresp")
        goto continue
    end
    if sender == controller and rprotocol == "poweroff" then
        power = false
        redstone.setOutput("top", false)
        rednet.send(controller, power, "powersetresp")
        goto continue
    end
    if sender == controller and rprotocol == "powerstatus" then
        rednet.send(controller, power, "powerresp")
        goto continue
    end
    if (sender == controller and rprotocol == "powerpos") then
        local x, y, z = gps.locate()
        rednet.send(controller, {"power", x, y, z}, "powerposresp")
        goto continue
    end
    if (sender == controller and rprotocol == "power") then
        if power then
            power = false
        else
            power = true
        end
        redstone.setOutput("top", power)
        rednet.send(controller, power, "powerresp")
        goto continue
    end
    ::continue::
end
