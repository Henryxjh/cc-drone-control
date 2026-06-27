local programPath = shell.getRunningProgram()
local programDir = fs.getDir(programPath)
local configPath = fs.combine(programDir, "controller-config.lua")

local function prompt(message, default)
    if default ~= nil then
        write(("%s [%s]: "):format(message, tostring(default)))
    else
        write(message .. ": ")
    end

    local value = read()
    if value == "" and default ~= nil then
        return default
    end
    return value
end

local function promptNumber(message, default)
    while true do
        local value = tonumber(prompt(message, default))
        if value ~= nil then
            return value
        end
        print("Expected a number.")
    end
end

local function promptChoice(message, default, choices)
    while true do
        local value = prompt(message, default)
        for _, choice in ipairs(choices) do
            if value == choice then
                return value
            end
        end
        print("Expected one of: " .. table.concat(choices, ", "))
    end
end

local function loadConfig()
    if not fs.exists(configPath) then
        return {}
    end

    local ok, config = pcall(dofile, configPath)
    if ok and type(config) == "table" then
        return config
    end

    print("Warning: failed to load controller-config.lua")
    return {}
end

local function sign(value)
    return value >= 0 and 1 or -1
end

local function directionVector(direction)
    if direction == "east" then
        return 1, 0
    elseif direction == "west" then
        return -1, 0
    elseif direction == "south" then
        return 0, 1
    elseif direction == "north" then
        return 0, -1
    end
    error("invalid direction: " .. tostring(direction))
end

local function getAxisMaxAngles(data, scrollValue1Axis)
    local scroll1 = math.abs(tonumber(data.ScrollValue1) or 45)
    local scroll2 = math.abs(tonumber(data.ScrollValue2) or 45)

    if scrollValue1Axis == "east_west" then
        return scroll1, scroll2
    end
    return scroll2, scroll1
end

local function axisNameFromVector(x, z)
    if x ~= 0 then
        return "east_west"
    end
    return "south_north"
end

local function readGimbal(reader)
    local data = reader.getBlockData()
    if type(data) ~= "table" or data.id ~= "simulated:gimbal_sensor" then
        return nil, "block reader is not reading simulated:gimbal_sensor"
    end

    local powers = data.Powers
    if type(powers) ~= "table" then
        return nil, "missing Powers in gimbal data"
    end

    return {
        data = data,
        eastWest = (powers.east or 0) - (powers.west or 0),
        southNorth = (powers.south or 0) - (powers.north or 0),
    }
end

local balanceSeq = 0

local function readMotorPositions(motorControllers, timeout)
    balanceSeq = balanceSeq + 1
    local seq = balanceSeq
    local positions = {}
    local remaining = 0

    for _, controllerId in pairs(motorControllers) do
        rednet.send(controllerId, { seq = seq, t = os.epoch("utc") }, "balance")
        remaining = remaining + 1
    end

    local timer = os.startTimer(timeout)
    while remaining > 0 do
        local event, sender, message, protocol = os.pullEvent()
        if event == "timer" and sender == timer then
            break
        end

        if event == "rednet_message" and protocol == "balanceresp" and type(message) == "table" then
            local side = message.side or message[1]
            local x = message.x or message[2]
            local y = message.y or message[3]
            local z = message.z or message[4]

            if motorControllers[side] == sender
                and message.seq == seq
                and positions[side] == nil
                and type(x) == "number"
                and type(y) == "number"
                and type(z) == "number"
            then
                positions[side] = { x = x, y = y, z = z }
                remaining = remaining - 1
            end
        end
    end
    os.cancelTimer(timer)

    if remaining > 0 then
        return nil, "motor balance response timeout"
    end
    return positions
end

local function distance(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function readDronePose(motorControllers, timeout)
    local positions, err = readMotorPositions(motorControllers, timeout)
    if not positions then
        return nil, err
    end

    return {
        pitchError = positions.front.y - positions.back.y,
        rollError = positions.left.y - positions.right.y,
        pitchArmDistance = distance(positions.front, positions.back),
        rollArmDistance = distance(positions.left, positions.right),
    }
end

local function addSample(sum, sample)
    for key, value in pairs(sample) do
        sum[key] = (sum[key] or 0) + value
    end
end

local function average(sum, count)
    local result = {}
    for key, value in pairs(sum) do
        result[key] = value / count
    end
    return result
end

local function formatOptionalNumber(value)
    if value == nil then
        return "nil"
    end
    return tostring(value)
end

local config = loadConfig()
local motorControllers = config.motorControllers or {}
local defaultTimeout = config.balanceTimeout or 0.5

print("Gimbal sensor calibration")
print("Keep the drone tilted and static. A diagonal tilt is best, so both pitch and roll can be inferred.")
print("")

local gimbalReaderSide = prompt("Gimbal block reader side", "bottom")
local forwardDirection = promptChoice(
    "Drone forward corresponds to sensor direction",
    "north",
    { "north", "east", "south", "west" }
)
local scrollValue1Axis = promptChoice(
    "ScrollValue1 axis",
    "east_west",
    { "east_west", "south_north" }
)
local sampleCount = promptNumber("Sample count", 10)
local balanceTimeout = promptNumber("Balance timeout seconds", defaultTimeout)

motorControllers.left = tonumber(prompt("Left motor controller id", motorControllers.left))
motorControllers.right = tonumber(prompt("Right motor controller id", motorControllers.right))
motorControllers.front = tonumber(prompt("Front motor controller id", motorControllers.front))
motorControllers.back = tonumber(prompt("Back motor controller id", motorControllers.back))

for _, side in ipairs({ "left", "right", "front", "back" }) do
    if type(motorControllers[side]) ~= "number" then
        error("missing motor controller id: " .. side)
    end
end

local reader = peripheral.wrap(gimbalReaderSide)
if reader == nil or not peripheral.hasType(gimbalReaderSide, "block_reader") then
    error("can't find block_reader at " .. gimbalReaderSide)
end

local modem = peripheral.find("modem")
if modem == nil or not modem.isWireless() then
    error("can't find wireless modem")
end
rednet.open(peripheral.getName(modem))

local forwardX, forwardZ = directionVector(forwardDirection)
local rightX, rightZ = -forwardZ, forwardX
local pitchSensorAxis = axisNameFromVector(forwardX, forwardZ)
local rollSensorAxis = axisNameFromVector(rightX, rightZ)
local sum = {}
local validSamples = 0

for i = 1, sampleCount do
    local gimbal, gimbalErr = readGimbal(reader)
    local pose, poseErr = readDronePose(motorControllers, balanceTimeout)

    if gimbal and pose then
        local eastWestMaxAngle, southNorthMaxAngle =
            getAxisMaxAngles(gimbal.data, scrollValue1Axis)
        local pitchPower = gimbal.eastWest * forwardX + gimbal.southNorth * forwardZ
        local rollPower = gimbal.eastWest * rightX + gimbal.southNorth * rightZ

        addSample(sum, {
            pitchPower = pitchPower,
            rollPower = rollPower,
            pitchError = pose.pitchError,
            rollError = pose.rollError,
            pitchArmDistance = pose.pitchArmDistance,
            rollArmDistance = pose.rollArmDistance,
            eastWestMaxAngle = eastWestMaxAngle,
            southNorthMaxAngle = southNorthMaxAngle,
        })
        validSamples = validSamples + 1
        print(("sample %d/%d ok"):format(i, sampleCount))
    else
        print(("sample %d/%d skipped: %s%s"):format(
            i,
            sampleCount,
            gimbalErr or "",
            poseErr and (" " .. poseErr) or ""
        ))
    end

    sleep(0.05)
end

if validSamples == 0 then
    error("no valid samples")
end

local avg = average(sum, validSamples)
local minimumPower = 1
local minimumError = 0.25
local pitchSign
local rollSign

if math.abs(avg.pitchPower) >= minimumPower and math.abs(avg.pitchError) >= minimumError then
    pitchSign = sign(avg.pitchError / avg.pitchPower)
end
if math.abs(avg.rollPower) >= minimumPower and math.abs(avg.rollError) >= minimumError then
    rollSign = sign(avg.rollError / avg.rollPower)
end

local pitchMaxAngle =
    pitchSensorAxis == "east_west" and avg.eastWestMaxAngle or avg.southNorthMaxAngle
local rollMaxAngle =
    rollSensorAxis == "east_west" and avg.eastWestMaxAngle or avg.southNorthMaxAngle

local snippet = ([[
gimbalSensor = {
    enabled = true,
    blockReader = "%s",
    blockName = "simulated:gimbal_sensor",
    forwardDirection = "%s",
    scrollValue1Axis = "%s",
    pitchAxis = "%s",
    rollAxis = "%s",
    pitchSign = %s,
    rollSign = %s,
    pitchMaxAngleDegrees = %.6f,
    rollMaxAngleDegrees = %.6f,
    pitchArmDistance = %.6f,
    rollArmDistance = %.6f,
}
]]):format(
    gimbalReaderSide,
    forwardDirection,
    scrollValue1Axis,
    pitchSensorAxis,
    rollSensorAxis,
    formatOptionalNumber(pitchSign),
    formatOptionalNumber(rollSign),
    pitchMaxAngle,
    rollMaxAngle,
    avg.pitchArmDistance,
    avg.rollArmDistance
)

local outputPath = fs.combine(programDir, "gimbal-config-snippet.lua")
local file = fs.open(outputPath, "w")
file.write(snippet)
file.close()

print("")
print(("valid samples: %d/%d"):format(validSamples, sampleCount))
print(("avg pitchPower=%.3f pitchError=%.3f"):format(avg.pitchPower, avg.pitchError))
print(("avg rollPower=%.3f rollError=%.3f"):format(avg.rollPower, avg.rollError))
if pitchSign == nil then
    print("pitchSign could not be inferred; tilt more along the drone forward/back axis.")
end
if rollSign == nil then
    print("rollSign could not be inferred; tilt more along the drone left/right axis.")
end
print("")
print("Suggested config:")
print(snippet)
print("Saved to " .. outputPath)
