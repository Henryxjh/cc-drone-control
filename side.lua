local controller = 1
local position = "left"

-- 电机安装方向相反时设为 true，使控制器发送的正速度仍产生向上推力。
local reverse = false

local modem = peripheral.find("modem")
if modem == nil or not modem.isWireless() then
    os.reboot()
end

local motor = peripheral.wrap("bottom")
if motor == nil or peripheral.getType("bottom") ~= "electric_motor" then
    os.reboot()
end

rednet.open(peripheral.getName(modem))

local function setSpeed(speed)
    if type(speed) ~= "number" then
        error("speed is not a number")
    end

    if speed >= 0 then
        speed = math.floor(speed + 0.5)
    else
        speed = math.ceil(speed - 0.5)
    end
    if reverse then
        motor.setSpeed(-speed)
    else
        motor.setSpeed(speed)
    end
end

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
        goto continue
    end
    if (sender == controller and rprotocol == position) then
        local success = pcall(setSpeed, message)
        rednet.send(controller, success, position)
        goto continue
    end
    if (sender == controller and rprotocol == "speed") then
        local speed = motor.getSpeed()
        rednet.send(controller, speed, "speedresp")
    end
    ::continue::
end
