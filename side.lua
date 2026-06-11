local controller = 1
local position = "left"

local modem = peripheral.find("modem")
if modem == nil or not modem.isWireless() then
    os.reboot()
end

rednet.open(peripheral.getName(modem))

while true do
    local sender, message, rprotocol = rednet.receive()
    if (sender == controller and rprotocol == "balance") then
        local x, y, z = gps.locate()
        rednet.send(controller, {position, x, y, z}, "balanceresp")
        goto continue
    end
    if (sender == controller and rprotocol == position) then
        redstone.setAnalogOutput("top", message)
        goto continue
    end
    ::continue::
end