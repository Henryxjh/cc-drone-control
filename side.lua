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
        local seq = type(message) == "table" and message.seq or nil
        local x, y, z = gps.locate()
        rednet.send(controller, {
            position,
            x,
            y,
            z,
            side = position,
            seq = seq,
            t = os.epoch("utc"),
        }, "balanceresp")
    end
end
