local function fatalError(message)
    local previousColor = term.getTextColor()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print(message)
    term.setTextColor(previousColor)
    os.sleep(1)
    os.reboot()
end

local programPath = shell.getRunningProgram()
local configPath = fs.combine(fs.getDir(programPath), "controller-config.lua")

if not fs.exists(configPath) then
    fatalError("missing controller config: " .. configPath)
end

local configLoaded, config = pcall(dofile, configPath)
if not configLoaded then
    fatalError("failed to load controller config: " .. tostring(config))
end

local function requireConfigType(path, value, expectedType)
    if type(value) ~= expectedType then
        fatalError(("invalid config '%s': expected %s"):format(path, expectedType))
    end
    return value
end

requireConfigType("config", config, "table")
local peripherals = requireConfigType("peripherals", config.peripherals, "table")
local hoverConfig = requireConfigType("hover", config.hover, "table")
local propulsionConfig = requireConfigType("propulsion", config.propulsion, "table")
local debugConfig = requireConfigType("debug", config.debug, "table")
local safetyConfig = config.safety or {}
requireConfigType("safety", safetyConfig, "table")
local navigationConfig = config.navigation or {}
requireConfigType("navigation", navigationConfig, "table")
local blockReaderConfig = config.blockReader or {}
requireConfigType("blockReader", blockReaderConfig, "table")
local gimbalSensorConfig = config.gimbalSensor or {}
requireConfigType("gimbalSensor", gimbalSensorConfig, "table")
local motorControllers =
    requireConfigType("motorControllers", config.motorControllers, "table")

local BLOCK_READER_SIDE = peripherals.blockReader
if BLOCK_READER_SIDE ~= nil then
    BLOCK_READER_SIDE = requireConfigType("peripherals.blockReader", BLOCK_READER_SIDE, "string")
end
local TELEPORTER_SIDE =
    requireConfigType("peripherals.teleporter", peripherals.teleporter, "string")
local REDSTONE_RELAY_LEFT_SIDE =
    requireConfigType("peripherals.redstoneRelayLeft", peripherals.redstoneRelayLeft, "string")
local REDSTONE_RELAY_RIGHT_SIDE =
    requireConfigType("peripherals.redstoneRelayRight", peripherals.redstoneRelayRight, "string")
local NAVIGATION_TABLE_BLOCK =
    blockReaderConfig.navigationTableBlock ~= nil
    and requireConfigType(
        "blockReader.navigationTableBlock",
        blockReaderConfig.navigationTableBlock,
        "string"
    )
    or (
        config.navigationTableBlock ~= nil
        and requireConfigType("navigationTableBlock", config.navigationTableBlock, "string")
        or "simulated:navigation_table"
    )
local GIMBAL_SENSOR_BLOCK =
    blockReaderConfig.gimbalSensorBlock == nil
    and "simulated:gimbal_sensor"
    or requireConfigType("blockReader.gimbalSensorBlock", blockReaderConfig.gimbalSensorBlock, "string")
local GIMBAL_FORWARD_DIRECTION =
    gimbalSensorConfig.forwardDirection == nil
    and "north"
    or requireConfigType("gimbalSensor.forwardDirection", gimbalSensorConfig.forwardDirection, "string")
local GIMBAL_SCROLL_VALUE_1_AXIS =
    gimbalSensorConfig.scrollValue1Axis == nil
    and "east_west"
    or requireConfigType("gimbalSensor.scrollValue1Axis", gimbalSensorConfig.scrollValue1Axis, "string")
local GIMBAL_PITCH_SIGN = gimbalSensorConfig.pitchSign
if GIMBAL_PITCH_SIGN ~= nil then
    GIMBAL_PITCH_SIGN = requireConfigType("gimbalSensor.pitchSign", GIMBAL_PITCH_SIGN, "number")
end
local GIMBAL_ROLL_SIGN = gimbalSensorConfig.rollSign
if GIMBAL_ROLL_SIGN ~= nil then
    GIMBAL_ROLL_SIGN = requireConfigType("gimbalSensor.rollSign", GIMBAL_ROLL_SIGN, "number")
end
local GIMBAL_PITCH_MAX_ANGLE_DEGREES =
    gimbalSensorConfig.pitchMaxAngleDegrees == nil
    and 45
    or requireConfigType(
        "gimbalSensor.pitchMaxAngleDegrees",
        gimbalSensorConfig.pitchMaxAngleDegrees,
        "number"
    )
local GIMBAL_ROLL_MAX_ANGLE_DEGREES =
    gimbalSensorConfig.rollMaxAngleDegrees == nil
    and 45
    or requireConfigType(
        "gimbalSensor.rollMaxAngleDegrees",
        gimbalSensorConfig.rollMaxAngleDegrees,
        "number"
    )
local GIMBAL_PITCH_ARM_DISTANCE =
    gimbalSensorConfig.pitchArmDistance == nil
    and 12
    or requireConfigType("gimbalSensor.pitchArmDistance", gimbalSensorConfig.pitchArmDistance, "number")
local GIMBAL_ROLL_ARM_DISTANCE =
    gimbalSensorConfig.rollArmDistance == nil
    and 12
    or requireConfigType("gimbalSensor.rollArmDistance", gimbalSensorConfig.rollArmDistance, "number")
local NAVIGATION_COMPLETION_DISTANCE =
    navigationConfig.completionDistance == nil
    and 1.0
    or requireConfigType(
            "navigation.completionDistance",
            navigationConfig.completionDistance,
            "number"
        )

requireConfigType("motorControllers.left", motorControllers.left, "number")
requireConfigType("motorControllers.right", motorControllers.right, "number")
requireConfigType("motorControllers.front", motorControllers.front, "number")
requireConfigType("motorControllers.back", motorControllers.back, "number")

local POWER_CONTROLLER_ID =
    requireConfigType("powerControllerId", config.powerControllerId, "number")
local POWER_RESPONSE_TIMEOUT =
    requireConfigType("powerResponseTimeout", config.powerResponseTimeout, "number")
local UI_REFRESH_INTERVAL =
    requireConfigType("uiRefreshInterval", config.uiRefreshInterval, "number")
local REDSTONE_LOGGING_ENABLED =
    requireConfigType("debug.redstoneLogging", debugConfig.redstoneLogging, "boolean")
local REDSTONE_LOG_PATH =
    requireConfigType("debug.redstoneLogPath", debugConfig.redstoneLogPath, "string")
local MINIMUM_MOTOR_SPEED =
    requireConfigType("propulsion.minimumSpeed", propulsionConfig.minimumSpeed, "number")
local MAXIMUM_MOTOR_SPEED =
    requireConfigType("propulsion.maximumSpeed", propulsionConfig.maximumSpeed, "number")
local MINIMUM_FLIGHT_SPEED =
    requireConfigType("propulsion.minimumFlightSpeed", propulsionConfig.minimumFlightSpeed, "number")
local MAXIMUM_FLIGHT_SPEED =
    requireConfigType("propulsion.maximumFlightSpeed", propulsionConfig.maximumFlightSpeed, "number")

if MINIMUM_MOTOR_SPEED >= MAXIMUM_MOTOR_SPEED then
    fatalError("invalid propulsion range: minimumSpeed must be below maximumSpeed")
end
if MINIMUM_FLIGHT_SPEED < MINIMUM_MOTOR_SPEED or MAXIMUM_FLIGHT_SPEED > MAXIMUM_MOTOR_SPEED then
    fatalError("invalid propulsion range: flight speed exceeds motor speed range")
end
if MINIMUM_FLIGHT_SPEED >= MAXIMUM_FLIGHT_SPEED then
    fatalError("invalid propulsion range: minimumFlightSpeed must be below maximumFlightSpeed")
end
if GIMBAL_FORWARD_DIRECTION ~= "north"
    and GIMBAL_FORWARD_DIRECTION ~= "east"
    and GIMBAL_FORWARD_DIRECTION ~= "south"
    and GIMBAL_FORWARD_DIRECTION ~= "west"
then
    fatalError("invalid gimbalSensor.forwardDirection")
end
if GIMBAL_SCROLL_VALUE_1_AXIS ~= "east_west"
    and GIMBAL_SCROLL_VALUE_1_AXIS ~= "south_north"
then
    fatalError("invalid gimbalSensor.scrollValue1Axis")
end

local BASE_THRUST = requireConfigType("hover.baseThrust", hoverConfig.baseThrust, "number")
local BASE_THRUST_REFERENCE_Y =
    requireConfigType("hover.baseThrustReferenceY", hoverConfig.baseThrustReferenceY, "number")
local MAXIMUM_HOVER_Y =
    hoverConfig.maximumHoverY == nil
    and 320
    or requireConfigType("hover.maximumHoverY", hoverConfig.maximumHoverY, "number")
local THRUST_PER_Y_LEVEL =
    requireConfigType("hover.thrustPerYLevel", hoverConfig.thrustPerYLevel, "number")
local ALTITUDE_KP = requireConfigType("hover.altitudeKp", hoverConfig.altitudeKp, "number")
local ALTITUDE_KD = requireConfigType("hover.altitudeKd", hoverConfig.altitudeKd, "number")
local LEVEL_KP = requireConfigType("hover.levelKp", hoverConfig.levelKp, "number")
local LEVEL_KD = requireConfigType("hover.levelKd", hoverConfig.levelKd, "number")
local HORIZONTAL_KP =
    requireConfigType("hover.horizontalKp", hoverConfig.horizontalKp, "number")
local HORIZONTAL_KD =
    requireConfigType("hover.horizontalKd", hoverConfig.horizontalKd, "number")
local MAX_TILT_ERROR =
    requireConfigType("hover.maxTiltError", hoverConfig.maxTiltError, "number")
local YAW_THRUST_DIFFERENCE =
    requireConfigType("hover.yawThrustDifference", hoverConfig.yawThrustDifference, "number")
local REVERSE_YAW_MIXING =
    requireConfigType("hover.reverseYawMixing", hoverConfig.reverseYawMixing, "boolean")
local YAW_KP = requireConfigType("hover.yawKp", hoverConfig.yawKp, "number")
local YAW_KD = requireConfigType("hover.yawKd", hoverConfig.yawKd, "number")
local MAX_YAW_CORRECTION =
    requireConfigType("hover.maxYawCorrection", hoverConfig.maxYawCorrection, "number")
local MAX_POSE_YAW_JUMP =
    math.rad(hoverConfig.maxPoseYawJumpDegrees == nil
        and 45
        or requireConfigType(
            "hover.maxPoseYawJumpDegrees",
            hoverConfig.maxPoseYawJumpDegrees,
            "number"
        ))
local MAX_POSE_PITCH_JUMP =
    hoverConfig.maxPosePitchJump == nil
    and 1.5
    or requireConfigType("hover.maxPosePitchJump", hoverConfig.maxPosePitchJump, "number")
local MAX_POSE_ROLL_JUMP =
    hoverConfig.maxPoseRollJump == nil
    and 1.5
    or requireConfigType("hover.maxPoseRollJump", hoverConfig.maxPoseRollJump, "number")
local HORIZONTAL_MOVE_SPEED =
    requireConfigType("hover.horizontalMoveSpeed", hoverConfig.horizontalMoveSpeed, "number")
local MAXIMUM_CLIMB_RATE =
    requireConfigType("hover.maximumClimbRate", hoverConfig.maximumClimbRate, "number")
local MAXIMUM_DESCENT_RATE =
    requireConfigType("hover.maximumDescentRate", hoverConfig.maximumDescentRate, "number")
local CONTROLLER_BELOW_POWER_TOLERANCE =
    safetyConfig.controllerBelowPowerTolerance == nil
    and 0.75
    or requireConfigType(
            "safety.controllerBelowPowerTolerance",
            safetyConfig.controllerBelowPowerTolerance,
            "number"
        )
local SAFETY_SHUTDOWN_DELAY =
    safetyConfig.shutdownDelay == nil
    and 1.5
    or requireConfigType("safety.shutdownDelay", safetyConfig.shutdownDelay, "number")
local INVERTED_NORMAL_Y_THRESHOLD =
    safetyConfig.invertedNormalYThreshold == nil
    and -0.1
    or requireConfigType(
            "safety.invertedNormalYThreshold",
            safetyConfig.invertedNormalYThreshold,
            "number"
        )
local BALANCE_TIMEOUT = requireConfigType("balanceTimeout", config.balanceTimeout, "number")
local BALANCE_MAX_PACKET_AGE_TICKS
if config.balanceMaxPacketAgeTicks ~= nil then
    BALANCE_MAX_PACKET_AGE_TICKS =
        requireConfigType("balanceMaxPacketAgeTicks", config.balanceMaxPacketAgeTicks, "number")
elseif config.balanceMaxPacketAgeMs ~= nil then
    BALANCE_MAX_PACKET_AGE_TICKS =
        math.ceil(requireConfigType("balanceMaxPacketAgeMs", config.balanceMaxPacketAgeMs, "number") / 50)
else
    BALANCE_MAX_PACKET_AGE_TICKS = math.ceil(BALANCE_TIMEOUT / 0.05)
end
local BALANCE_MAX_PACKET_AGE_MS = BALANCE_MAX_PACKET_AGE_TICKS * 50
local GPS_TIMEOUT = requireConfigType("gpsTimeout", config.gpsTimeout, "number")

if BASE_THRUST < MINIMUM_FLIGHT_SPEED or BASE_THRUST > MAXIMUM_FLIGHT_SPEED then
    fatalError("invalid hover.baseThrust: outside normal flight speed range")
end
if MAXIMUM_HOVER_Y < BASE_THRUST_REFERENCE_Y then
    fatalError("invalid hover.maximumHoverY: must not be below hover.baseThrustReferenceY")
end
if MAXIMUM_CLIMB_RATE < 0 or MAXIMUM_DESCENT_RATE < 0 then
    fatalError("invalid vertical rate: maximum climb/descent rates must be non-negative")
end
if CONTROLLER_BELOW_POWER_TOLERANCE < 0 or SAFETY_SHUTDOWN_DELAY < 0 then
    fatalError("invalid safety config: tolerance and shutdown delay must be non-negative")
end
if INVERTED_NORMAL_Y_THRESHOLD < -1 or INVERTED_NORMAL_Y_THRESHOLD >= 0 then
    fatalError("invalid safety.invertedNormalYThreshold: expected -1 <= value < 0")
end
if NAVIGATION_COMPLETION_DISTANCE < 0 then
    fatalError("invalid navigation.completionDistance: must be non-negative")
end
if MAX_POSE_YAW_JUMP < 0 or MAX_POSE_PITCH_JUMP < 0 or MAX_POSE_ROLL_JUMP < 0 then
    fatalError("invalid pose jump filter: thresholds must be non-negative")
end
if GIMBAL_PITCH_MAX_ANGLE_DEGREES < 0
    or GIMBAL_ROLL_MAX_ANGLE_DEGREES < 0
    or GIMBAL_PITCH_ARM_DISTANCE <= 0
    or GIMBAL_ROLL_ARM_DISTANCE <= 0
then
    fatalError("invalid gimbal sensor config: angles and distances must be integers")
end
if GIMBAL_PITCH_MAX_ANGLE_DEGREES % 1 ~= 0
    or GIMBAL_ROLL_MAX_ANGLE_DEGREES % 1 ~= 0
    or GIMBAL_PITCH_ARM_DISTANCE % 1 ~= 0
    or GIMBAL_ROLL_ARM_DISTANCE % 1 ~= 0
then
    fatalError("invalid gimbal sensor config: angles and distances must be integers")
end
if BALANCE_TIMEOUT < 0 or BALANCE_MAX_PACKET_AGE_TICKS < 0 or GPS_TIMEOUT < 0 then
    fatalError("invalid communication timeout: values must be non-negative")
end

local redstoneLogPath = fs.combine(fs.getDir(programPath), REDSTONE_LOG_PATH)
local previousRedstoneInputs

local function logRedstoneInputs(inputs)
    if not REDSTONE_LOGGING_ENABLED then
        return
    end

    local changed = previousRedstoneInputs == nil
    if previousRedstoneInputs then
        for name, value in pairs(inputs) do
            if previousRedstoneInputs[name] ~= value then
                changed = true
                break
            end
        end
    end

    if not changed then
        return
    end

    local file = fs.open(redstoneLogPath, "a")
    if file == nil then
        fatalError("failed to open redstone log: " .. redstoneLogPath)
    end

    file.writeLine((
        "[%d] backward=%s forward=%s left=%s right=%s rotateLeft=%s rotateRight=%s up=%s down=%s"
    ):format(
        os.epoch("utc"),
        tostring(inputs.backward),
        tostring(inputs.forward),
        tostring(inputs.left),
        tostring(inputs.right),
        tostring(inputs.rotateLeft),
        tostring(inputs.rotateRight),
        tostring(inputs.up),
        tostring(inputs.down)
    ))
    file.close()

    previousRedstoneInputs = {}
    for name, value in pairs(inputs) do
        previousRedstoneInputs[name] = value
    end
end

local modem = peripheral.find("modem")
if modem == nil or not modem.isWireless() then
    fatalError("can't find ender_modem!")
end

rednet.open(peripheral.getName(modem))

local blockReader
local navigationTableReader
local gimbalSensorReader
local blockReaderStatus

local function loadGimbalSensorAngles(reader)
    local dataOk, data = pcall(reader.getBlockData)
    if not dataOk or type(data) ~= "table" then
        return
    end

    local scroll1 = tonumber(data.ScrollValue1)
    local scroll2 = tonumber(data.ScrollValue2)
    if scroll1 == nil or scroll2 == nil then
        return
    end

    scroll1 = math.floor(math.abs(scroll1) + 0.5)
    scroll2 = math.floor(math.abs(scroll2) + 0.5)

    local eastWestMaxAngle
    local southNorthMaxAngle
    if GIMBAL_SCROLL_VALUE_1_AXIS == "east_west" then
        eastWestMaxAngle = scroll1
        southNorthMaxAngle = scroll2
    else
        eastWestMaxAngle = scroll2
        southNorthMaxAngle = scroll1
    end

    local pitchUsesEastWest =
        GIMBAL_FORWARD_DIRECTION == "east" or GIMBAL_FORWARD_DIRECTION == "west"
    GIMBAL_PITCH_MAX_ANGLE_DEGREES =
        pitchUsesEastWest and eastWestMaxAngle or southNorthMaxAngle
    GIMBAL_ROLL_MAX_ANGLE_DEGREES =
        pitchUsesEastWest and southNorthMaxAngle or eastWestMaxAngle
end

if BLOCK_READER_SIDE == nil then
    blockReaderStatus = "not configured"
elseif not peripheral.hasType(BLOCK_READER_SIDE, "block_reader") then
    blockReaderStatus = "unavailable at " .. BLOCK_READER_SIDE
else
    blockReader = peripheral.wrap(BLOCK_READER_SIDE)
    local ok, blockName = pcall(blockReader.getBlockName)
    if not ok or type(blockName) ~= "string" then
        blockReaderStatus = "failed to read block name"
    elseif blockName == NAVIGATION_TABLE_BLOCK then
        navigationTableReader = blockReader
        blockReaderStatus = "navigation table"
    elseif blockName == GIMBAL_SENSOR_BLOCK then
        gimbalSensorReader = blockReader
        loadGimbalSensorAngles(gimbalSensorReader)
        if GIMBAL_PITCH_SIGN == nil or GIMBAL_ROLL_SIGN == nil then
            blockReaderStatus = "gimbal sensor not calibrated"
        else
            blockReaderStatus = "gimbal sensor"
        end
    else
        blockReaderStatus = "unsupported block: " .. blockName
    end
end

local teleporter = peripheral.wrap(TELEPORTER_SIDE)
if teleporter == nil then
    fatalError("can't find teleporter!")
end

local redstoneRelayLeft = peripheral.wrap(REDSTONE_RELAY_LEFT_SIDE)
local redstoneRelayRight = peripheral.wrap(REDSTONE_RELAY_RIGHT_SIDE)

if redstoneRelayLeft == nil or redstoneRelayRight == nil then
    fatalError("can't find redstone relays!")
end

-- -1 为左旋，0 为不自旋，1 为右旋。
local yawCommand = 0

-- 前后、左右和上下移动命令，范围为 -1 到 1。
local forwardCommand = 0
local rightCommand = 0
local verticalCommand = 0
local allSignalsToggleLatched = false
local powerToggleGesture = { false, false, false, false, nil }
local manualControlActive = false
local previousManualControlActive = false
local navigationWasActive = false
local navigationResetPending = false
local navigationCompleted = false
local completedNavigationTargetX
local completedNavigationTargetY
local completedNavigationTargetZ
local completedNavigationSource
local currentNavigationSource
local customNavigationTargetX
local customNavigationTargetZ
local navigationTableSuppressed = false
local navigationTableClearedAfterSuppression = false
local manualNavigationPauseUntil = 0

local hoverTargetX
local hoverTargetY
local requestedHoverTargetY
local hoverTargetZ
local previousControllerX
local previousControllerY
local previousControllerZ
local previousPitchError
local previousRollError
local previousHoverTime
local hoverTargetYaw
local previousYaw
local currentYaw
local powerEnabled
local safetyShutdown = false
local unsafePositionSince
local uprightNormalSign
local powerControllerX
local powerControllerY
local powerControllerZ
local controllerX
local controllerY
local controllerZ
local motorSpeed = {
    left = 0,
    right = 0,
    front = 0,
    back = 0,
}
local balanceSeq = 0
local latestPropellerPositions = {}
local poseFilterState = {}
local poseCombinations = {
    { "front", "back", "left" },
    { "front", "back", "right" },
    { "front", "left", "right" },
    { "back", "left", "right" },
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function normalizeAngle(angle)
    while angle > math.pi do
        angle = angle - 2 * math.pi
    end
    while angle < -math.pi do
        angle = angle + 2 * math.pi
    end
    return angle
end

local function yawToHeading(yaw)
    if yaw == nil then
        return nil
    end

    local heading = -math.deg(yaw) % 360
    if heading < 0 then
        heading = heading + 360
    end
    return heading
end

local function round(value)
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function sendMotorSpeed(side, speed)
    local roundedSpeed = round(clamp(speed, MINIMUM_FLIGHT_SPEED, MAXIMUM_FLIGHT_SPEED))
    motorSpeed[side] = roundedSpeed
    rednet.send(motorControllers[side], roundedSpeed, side)
end

local function stopAllMotors()
    for side, controllerId in pairs(motorControllers) do
        motorSpeed[side] = 0
        rednet.send(controllerId, 0, side)
    end
end

local function resetHoverTarget()
    hoverTargetX = nil
    hoverTargetY = nil
    requestedHoverTargetY = nil
    hoverTargetZ = nil
    previousControllerX = nil
    previousControllerY = nil
    previousControllerZ = nil
    previousPitchError = nil
    previousRollError = nil
    previousHoverTime = nil
    hoverTargetYaw = nil
    previousYaw = nil
    poseFilterState.pose = nil
    unsafePositionSince = nil
end

local function waitForPowerResponse()
    local sender, state = rednet.receive("powerresp", POWER_RESPONSE_TIMEOUT)
    if sender == POWER_CONTROLLER_ID and type(state) == "boolean" then
        local wasEnabled = powerEnabled
        powerEnabled = state
        if not state then
            stopAllMotors()
        elseif wasEnabled == false then
            -- 完整重启控制器，以重新加载配置、外设引用和所有控制参数。
            os.reboot()
        end
        return true
    end

    return false
end

local function requestPowerStatus()
    rednet.send(POWER_CONTROLLER_ID, true, "powerstatus")
    return waitForPowerResponse()
end

local function togglePower()
    rednet.send(POWER_CONTROLLER_ID, true, "power")
    return waitForPowerResponse()
end

local function adjustHoverTarget(key)
    if key == keys.q or key == keys.e then
        if hoverTargetYaw == nil then
            return false
        end

        local oneDegree = math.rad(1)
        if key == keys.q then
            hoverTargetYaw = normalizeAngle(hoverTargetYaw + oneDegree)
        else
            hoverTargetYaw = normalizeAngle(hoverTargetYaw - oneDegree)
        end
        manualNavigationPauseUntil = os.epoch("utc") + 250
        return true
    end

    if hoverTargetX == nil or hoverTargetY == nil or hoverTargetZ == nil then
        return false
    end

    if key == keys.w then
        hoverTargetX = hoverTargetX + 1
    elseif key == keys.s then
        hoverTargetX = hoverTargetX - 1
    elseif key == keys.a then
        hoverTargetZ = hoverTargetZ - 1
    elseif key == keys.d then
        hoverTargetZ = hoverTargetZ + 1
    elseif key == keys.space then
        requestedHoverTargetY = math.min(MAXIMUM_HOVER_Y, (requestedHoverTargetY or hoverTargetY) + 1)
    elseif key == keys.leftShift or key == keys.rightShift then
        requestedHoverTargetY = math.max(BASE_THRUST_REFERENCE_Y, (requestedHoverTargetY or hoverTargetY) - 1)
    else
        return false
    end

    manualNavigationPauseUntil = os.epoch("utc") + 250
    return true
end

local function emergencyPowerOff()
    if safetyShutdown then
        return
    end

    safetyShutdown = true
    stopAllMotors()
    rednet.send(POWER_CONTROLLER_ID, false, "powerset")
    powerEnabled = false
    resetHoverTarget()
end

local function updatePowerToggleGesture(backward, forward, left, right)
    local anyInput = backward or forward or left or right
    if not anyInput then
        allSignalsToggleLatched = false
        powerToggleGesture[1] = false
        powerToggleGesture[2] = false
        powerToggleGesture[3] = false
        powerToggleGesture[4] = false
        powerToggleGesture[5] = nil
        return
    end

    if allSignalsToggleLatched then
        return
    end

    local now = os.epoch("utc")
    if powerToggleGesture[5] == nil or now - powerToggleGesture[5] > 200 then
        powerToggleGesture[1] = false
        powerToggleGesture[2] = false
        powerToggleGesture[3] = false
        powerToggleGesture[4] = false
        powerToggleGesture[5] = now
    end

    powerToggleGesture[1] = powerToggleGesture[1] or backward
    powerToggleGesture[2] = powerToggleGesture[2] or forward
    powerToggleGesture[3] = powerToggleGesture[3] or left
    powerToggleGesture[4] = powerToggleGesture[4] or right

    if powerToggleGesture[1]
        and powerToggleGesture[2]
        and powerToggleGesture[3]
        and powerToggleGesture[4]
    then
        allSignalsToggleLatched = true
        rednet.send(POWER_CONTROLLER_ID, true, "power")
    end
end

local function updateManualControlRelease()
    if previousManualControlActive and not manualControlActive then
        if controllerX ~= nil and controllerY ~= nil and controllerZ ~= nil then
            hoverTargetX = controllerX
            hoverTargetY = clamp(controllerY, BASE_THRUST_REFERENCE_Y, MAXIMUM_HOVER_Y)
            requestedHoverTargetY = hoverTargetY
            hoverTargetZ = controllerZ
        end
        manualNavigationPauseUntil = os.epoch("utc") + 500
    end

    previousManualControlActive = manualControlActive
end

local function requestPowerPosition()
    rednet.send(POWER_CONTROLLER_ID, true, "powerpos")

    local sender, response = rednet.receive("powerposresp", POWER_RESPONSE_TIMEOUT)
    if sender ~= POWER_CONTROLLER_ID
        or type(response) ~= "table"
        or response[1] ~= "power"
    then
        powerControllerX = nil
        powerControllerY = nil
        powerControllerZ = nil
        return false
    end

    local x = response[2]
    local y = response[3]
    local z = response[4]
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        powerControllerX = nil
        powerControllerY = nil
        powerControllerZ = nil
        return false
    end

    powerControllerX = x
    powerControllerY = y
    powerControllerZ = z
    return true
end

local function getTheoreticalHoverSpeed()
    local targetY = requestedHoverTargetY or hoverTargetY
    if targetY == nil then
        return nil
    end

    return round(clamp(
        BASE_THRUST + (targetY - BASE_THRUST_REFERENCE_Y) * THRUST_PER_Y_LEVEL,
        MINIMUM_FLIGHT_SPEED,
        MAXIMUM_FLIGHT_SPEED
    ))
end

local function formatPosition(x, y, z)
    if x == nil or y == nil or z == nil then
        return "UNKNOWN"
    end

    return ("%.1f %.1f %.1f"):format(x, y, z)
end

local function truncateLine(value, width)
    value = tostring(value):gsub("\r", " "):gsub("\n", " ")
    width = math.max(1, math.floor(width or 1))
    if #value <= width then
        return value
    end
    if width <= 3 then
        return string.sub(value, 1, width)
    end
    return string.sub(value, 1, width - 3) .. "..."
end

local function printUiLine(label, value, width)
    print(truncateLine(label .. value, width))
end

local function drawPowerUi(message)
    term.clear()
    term.setCursorPos(1, 1)
    local width = term.getSize()

    local powerText
    if powerEnabled == nil then
        powerText = "UNKNOWN"
    elseif powerEnabled then
        powerText = "ON"
    else
        powerText = "OFF"
    end
    printUiLine("Drone Controller PWR:", powerText, width)

    printUiLine("PowerPos: ", formatPosition(powerControllerX, powerControllerY, powerControllerZ), width)
    printUiLine("CtrlPos : ", formatPosition(controllerX, controllerY, controllerZ), width)
    printUiLine("Hover   : ", formatPosition(hoverTargetX, requestedHoverTargetY or hoverTargetY, hoverTargetZ), width)

    local navigationText
    if currentTargetX == nil or currentTargetZ == nil then
        navigationText = "NONE"
    else
        navigationText = ("%.1f %.1f %.1f %s%s"):format(
            currentTargetX,
            currentTargetY or hoverTargetY or 0,
            currentTargetZ,
            currentNavigationSource or "UNKNOWN",
            navigationCompleted and " DONE" or ""
        )
    end
    printUiLine("Nav     : ", navigationText, width)
    printUiLine("Reader  : ", blockReaderStatus or "unknown", width)

    local currentHeading = yawToHeading(currentYaw)
    local targetHeading = yawToHeading(hoverTargetYaw)
    local currentHeadingText = currentHeading == nil and "UNK" or ("%.1f"):format(currentHeading)
    local targetHeadingText = targetHeading == nil and "UNK" or ("%.1f"):format(targetHeading)
    printUiLine("Heading : ", ("%s -> %s"):format(currentHeadingText, targetHeadingText), width)

    local theoreticalHoverSpeed = getTheoreticalHoverSpeed()
    printUiLine("HoverRPM: ", theoreticalHoverSpeed == nil and "UNKNOWN" or tostring(theoreticalHoverSpeed), width)

    printUiLine("", ("Cmd F:%d B:%d"):format(motorSpeed.front, motorSpeed.back), width)
    printUiLine("", ("Cmd L:%d R:%d"):format(motorSpeed.left, motorSpeed.right), width)
    printUiLine("", ("Range %d..%d Enter=Power"):format(MINIMUM_MOTOR_SPEED, MAXIMUM_MOTOR_SPEED), width)

    if safetyShutdown then
        local previousColor = term.getTextColor()
        term.setTextColor(colors.red)
        printUiLine("", "SAFETY: inverted, restore then Enter", width)
        term.setTextColor(previousColor)
    end

    if message then
        print(truncateLine(message, width))
    end
end

local function midpoint(a, b)
    return {
        x = (a.x + b.x) / 2,
        y = (a.y + b.y) / 2,
        z = (a.z + b.z) / 2,
    }
end

local function mirrorAcross(point, center)
    return {
        x = center.x * 2 - point.x,
        y = center.y * 2 - point.y,
        z = center.z * 2 - point.z,
    }
end

local function vectorLength3d(x, y, z)
    return math.sqrt(x * x + y * y + z * z)
end

local function clonePosition(position)
    return {
        x = position.x,
        y = position.y,
        z = position.z,
    }
end

local function makePoseFromPositions(positions)
    local p = {
        front = positions.front and clonePosition(positions.front),
        back = positions.back and clonePosition(positions.back),
        left = positions.left and clonePosition(positions.left),
        right = positions.right and clonePosition(positions.right),
    }

    if p.front == nil then
        p.front = mirrorAcross(p.back, midpoint(p.left, p.right))
    elseif p.back == nil then
        p.back = mirrorAcross(p.front, midpoint(p.left, p.right))
    elseif p.left == nil then
        p.left = mirrorAcross(p.right, midpoint(p.front, p.back))
    elseif p.right == nil then
        p.right = mirrorAcross(p.left, midpoint(p.front, p.back))
    end

    local forwardX = p.front.x - p.back.x
    local forwardY = p.front.y - p.back.y
    local forwardZ = p.front.z - p.back.z
    local rightX = p.right.x - p.left.x
    local rightY = p.right.y - p.left.y
    local rightZ = p.right.z - p.left.z
    local forwardLength = math.sqrt(forwardX * forwardX + forwardZ * forwardZ)
    local rightLength = math.sqrt(rightX * rightX + rightZ * rightZ)
    local forwardLength3d = vectorLength3d(forwardX, forwardY, forwardZ)
    local rightLength3d = vectorLength3d(rightX, rightY, rightZ)

    if forwardLength == 0 or rightLength == 0 or forwardLength3d == 0 or rightLength3d == 0 then
        return nil
    end

    return {
        forwardX = forwardX / forwardLength,
        forwardZ = forwardZ / forwardLength,
        rightX = rightX / rightLength,
        rightZ = rightZ / rightLength,
        normalY = (forwardZ * rightX - forwardX * rightZ) / (forwardLength3d * rightLength3d),
        yaw = math.atan2(forwardZ, forwardX),
        pitchError = p.front.y - p.back.y,
        rollError = p.left.y - p.right.y,
    }
end

local function isFreshPropellerPosition(position, nowMs)
    return position
        and nowMs - position.t <= BALANCE_MAX_PACKET_AGE_MS
        and nowMs - position.receivedAt <= BALANCE_MAX_PACKET_AGE_MS
end

local function buildBestPropellerPose(nowMs)
    local bestPositions
    local bestScore

    for _, combination in ipairs(poseCombinations) do
        local positions = {}
        local oldest = math.huge
        local newest = -math.huge
        local complete = true

        for _, side in ipairs(combination) do
            local position = latestPropellerPositions[side]
            if not isFreshPropellerPosition(position, nowMs) then
                complete = false
                break
            end

            positions[side] = position
            oldest = math.min(oldest, position.t)
            newest = math.max(newest, position.t)
        end

        if complete then
            local score = newest - oldest
            if bestScore == nil or score < bestScore then
                bestPositions = positions
                bestScore = score
            end
        end
    end

    if bestPositions == nil then
        return nil
    end

    return makePoseFromPositions(bestPositions)
end

local function receiveBalanceResponse(sender, response, expectedSeq, nowMs)
    if type(response) ~= "table" then
        return false
    end

    local side = response.side or response[1]
    local x = response.x or response[2]
    local y = response.y or response[3]
    local z = response.z or response[4]
    local seq = response.seq
    local t = response.t

    if motorControllers[side] ~= sender
        or seq ~= expectedSeq
        or type(x) ~= "number"
        or type(y) ~= "number"
        or type(z) ~= "number"
        or type(t) ~= "number"
        or nowMs - t > BALANCE_MAX_PACKET_AGE_MS
    then
        return false
    end

    latestPropellerPositions[side] = {
        x = x,
        y = y,
        z = z,
        seq = seq,
        t = t,
        receivedAt = nowMs,
    }
    return true
end

local function readPropellerPose()
    balanceSeq = balanceSeq + 1
    local seq = balanceSeq
    local currentResponses = 0
    local receivedSides = {}

    for _, controllerId in pairs(motorControllers) do
        rednet.send(controllerId, { seq = seq, t = os.epoch("utc") }, "balance")
    end

    local timer = os.startTimer(BALANCE_TIMEOUT)
    while currentResponses < 3 do
        local event, first, second, third = os.pullEvent()
        local nowMs = os.epoch("utc")

        if event == "timer" and first == timer then
            break
        end

        if event == "rednet_message" and third == "balanceresp" then
            local side = type(second) == "table" and (second.side or second[1])
            if not receivedSides[side] and receiveBalanceResponse(first, second, seq, nowMs) then
                receivedSides[side] = true
                currentResponses = currentResponses + 1
            end
        end
    end

    os.cancelTimer(timer)
    return buildBestPropellerPose(os.epoch("utc"))
end

local function directionVector(direction)
    if direction == "east" then
        return 1, 0
    elseif direction == "west" then
        return -1, 0
    elseif direction == "south" then
        return 0, 1
    end
    return 0, -1
end

local function clonePose(pose)
    return {
        forwardX = pose.forwardX,
        forwardZ = pose.forwardZ,
        rightX = pose.rightX,
        rightZ = pose.rightZ,
        normalY = pose.normalY,
        yaw = pose.yaw,
        pitchError = pose.pitchError,
        rollError = pose.rollError,
    }
end

local function readGimbalSensorPose(basePose)
    if gimbalSensorReader == nil or GIMBAL_PITCH_SIGN == nil or GIMBAL_ROLL_SIGN == nil then
        return nil
    end

    local ok, data = pcall(gimbalSensorReader.getBlockData)
    if not ok or type(data) ~= "table" then
        return nil
    end

    local powers = data.Powers
    if type(powers) ~= "table" then
        return nil
    end

    local eastWest = (powers.east or 0) - (powers.west or 0)
    local southNorth = (powers.south or 0) - (powers.north or 0)
    local forwardX, forwardZ = directionVector(GIMBAL_FORWARD_DIRECTION)
    local rightX = -forwardZ
    local rightZ = forwardX
    local pitchPower = (eastWest * forwardX + southNorth * forwardZ) * GIMBAL_PITCH_SIGN
    local rollPower = (eastWest * rightX + southNorth * rightZ) * GIMBAL_ROLL_SIGN
    local pitchAngle =
        math.rad(clamp(pitchPower / 15, -1, 1) * GIMBAL_PITCH_MAX_ANGLE_DEGREES)
    local rollAngle =
        math.rad(clamp(rollPower / 15, -1, 1) * GIMBAL_ROLL_MAX_ANGLE_DEGREES)
    local pose = clonePose(basePose)

    pose.pitchError = math.sin(pitchAngle) * GIMBAL_PITCH_ARM_DISTANCE
    pose.rollError = math.sin(rollAngle) * GIMBAL_ROLL_ARM_DISTANCE
    return pose
end

local function filterPropellerPose(pose)
    local previousPose = poseFilterState.pose
    if previousPose ~= nil then
        local yawJump = math.abs(normalizeAngle(pose.yaw - previousPose.yaw))
        local pitchJump = math.abs(pose.pitchError - previousPose.pitchError)
        local rollJump = math.abs(pose.rollError - previousPose.rollError)

        if yawJump > MAX_POSE_YAW_JUMP
            or pitchJump > MAX_POSE_PITCH_JUMP
            or rollJump > MAX_POSE_ROLL_JUMP
        then
            return previousPose
        end
    end

    local acceptedPose = clonePose(pose)
    poseFilterState.pose = acceptedPose
    return acceptedPose
end

local function applyCurrentNavigationTarget()
    if currentTargetX == nil or currentTargetZ == nil or navigationCompleted then
        return
    end

    hoverTargetX = currentTargetX
    hoverTargetZ = currentTargetZ
end

local hoverLoop = {}

function hoverLoop.updateControllerPosition()
    local locatedX, locatedY, locatedZ = gps.locate(GPS_TIMEOUT, false)
    if locatedX == nil or locatedY == nil or locatedZ == nil then
        controllerX = nil
        controllerY = nil
        controllerZ = nil
        unsafePositionSince = nil
        return false
    end

    controllerX = locatedX
    controllerY = locatedY
    controllerZ = locatedZ
    return true
end

function hoverLoop.readCurrentPose()
    local propellerPose = readPropellerPose()
    if propellerPose == nil then
        currentYaw = nil
        return nil
    end

    local gimbalPose = readGimbalSensorPose(propellerPose)
    if gimbalPose ~= nil then
        propellerPose = gimbalPose
    end
    propellerPose = filterPropellerPose(propellerPose)

    local normalY = propellerPose.normalY
    if uprightNormalSign == nil and math.abs(normalY) >= 0.25 then
        uprightNormalSign = normalY >= 0 and 1 or -1
    end
    currentYaw = propellerPose.yaw
    return propellerPose
end

function hoverLoop.shouldEmergencyStop(normalY, now)
    local controllerClearlyBelowPower =
        powerControllerY ~= nil
        and controllerY + CONTROLLER_BELOW_POWER_TOLERANCE < powerControllerY
    local inverted =
        uprightNormalSign ~= nil
        and normalY * uprightNormalSign < INVERTED_NORMAL_Y_THRESHOLD
    if controllerClearlyBelowPower and inverted then
        unsafePositionSince = unsafePositionSince or now
        if now - unsafePositionSince >= SAFETY_SHUTDOWN_DELAY then
            return true
        end
    else
        unsafePositionSince = nil
    end

    return false
end

function hoverLoop.ensureHoverTarget()
    if hoverTargetY == nil then
        hoverTargetX = controllerX
        hoverTargetY = clamp(controllerY, BASE_THRUST_REFERENCE_Y, MAXIMUM_HOVER_Y)
        requestedHoverTargetY = hoverTargetY
        hoverTargetZ = controllerZ
    end
end

function hoverLoop.createHoverState(propellerPose, now)
    local state = {
        now = now,
        deltaTime = previousHoverTime and now - previousHoverTime or nil,
        velocityX = 0,
        verticalVelocity = 0,
        velocityZ = 0,
        pitchRate = 0,
        rollRate = 0,
        yawRate = 0,
        pitchError = propellerPose.pitchError,
        rollError = propellerPose.rollError,
        yaw = currentYaw,
        forwardX = propellerPose.forwardX,
        forwardZ = propellerPose.forwardZ,
        rightX = propellerPose.rightX,
        rightZ = propellerPose.rightZ,
    }

    if state.deltaTime and state.deltaTime > 0 then
        state.velocityX = (controllerX - previousControllerX) / state.deltaTime
        state.verticalVelocity = (controllerY - previousControllerY) / state.deltaTime
        state.velocityZ = (controllerZ - previousControllerZ) / state.deltaTime
        state.pitchRate = (state.pitchError - previousPitchError) / state.deltaTime
        state.rollRate = (state.rollError - previousRollError) / state.deltaTime
    end

    return state
end

function hoverLoop.updateHoverTargetFromCommands(state)
    local movementDeltaTime = clamp(state.deltaTime or 0, 0, 0.5)
    local forwardDistance = forwardCommand * HORIZONTAL_MOVE_SPEED * movementDeltaTime
    local rightDistance = rightCommand * HORIZONTAL_MOVE_SPEED * movementDeltaTime
    requestedHoverTargetY = requestedHoverTargetY or hoverTargetY
    hoverTargetX =
        hoverTargetX
        + state.forwardX * forwardDistance
        + state.rightX * rightDistance
    if verticalCommand > 0 then
        requestedHoverTargetY = math.min(
            MAXIMUM_HOVER_Y,
            requestedHoverTargetY + MAXIMUM_CLIMB_RATE * movementDeltaTime
        )
    elseif verticalCommand < 0 then
        requestedHoverTargetY = math.max(
            BASE_THRUST_REFERENCE_Y,
            requestedHoverTargetY - MAXIMUM_DESCENT_RATE * movementDeltaTime
        )
    end
    if requestedHoverTargetY > hoverTargetY then
        hoverTargetY = math.min(
            requestedHoverTargetY,
            hoverTargetY + MAXIMUM_CLIMB_RATE * movementDeltaTime
        )
    elseif requestedHoverTargetY < hoverTargetY then
        hoverTargetY = math.max(
            requestedHoverTargetY,
            hoverTargetY - MAXIMUM_DESCENT_RATE * movementDeltaTime
        )
    end
    hoverTargetZ =
        hoverTargetZ
        + state.forwardZ * forwardDistance
        + state.rightZ * rightDistance

    -- 自动导航仅控制水平位置；任意手动操作会暂停本周期的自动导航。
    local manualNavigationPaused =
        manualControlActive or os.epoch("utc") < manualNavigationPauseUntil
    if not manualNavigationPaused then
        applyCurrentNavigationTarget()
    end

    if hoverTargetYaw == nil or yawCommand ~= 0 then
        hoverTargetYaw = state.yaw
    end
    if state.deltaTime and state.deltaTime > 0 and previousYaw ~= nil then
        state.yawRate = normalizeAngle(state.yaw - previousYaw) / state.deltaTime
    end
end

function hoverLoop.calculateHoverCorrections(state)
    local positionErrorX = hoverTargetX - controllerX
    local positionErrorZ = hoverTargetZ - controllerZ
    local forwardPositionError =
        positionErrorX * state.forwardX + positionErrorZ * state.forwardZ
    local rightPositionError =
        positionErrorX * state.rightX + positionErrorZ * state.rightZ
    local forwardVelocity =
        state.velocityX * state.forwardX + state.velocityZ * state.forwardZ
    local rightVelocity =
        state.velocityX * state.rightX + state.velocityZ * state.rightZ

    local forwardPositionCommand =
        HORIZONTAL_KP * forwardPositionError - HORIZONTAL_KD * forwardVelocity
    local rightPositionCommand =
        HORIZONTAL_KP * rightPositionError - HORIZONTAL_KD * rightVelocity
    local desiredPitchError =
        -clamp(forwardPositionCommand, -MAX_TILT_ERROR, MAX_TILT_ERROR)
    local desiredRollError =
        clamp(rightPositionCommand, -MAX_TILT_ERROR, MAX_TILT_ERROR)

    local altitudeCorrection =
        ALTITUDE_KP * (hoverTargetY - controllerY) - ALTITUDE_KD * state.verticalVelocity
    local hoverThrust =
        BASE_THRUST + (hoverTargetY - BASE_THRUST_REFERENCE_Y) * THRUST_PER_Y_LEVEL
    local collectiveThrust = math.max(BASE_THRUST, hoverThrust + altitudeCorrection)
    local pitchCorrection =
        -LEVEL_KP * (state.pitchError - desiredPitchError) - LEVEL_KD * state.pitchRate
    local rollCorrection =
        -LEVEL_KP * (state.rollError - desiredRollError) - LEVEL_KD * state.rollRate
    local yawCorrection
    if yawCommand == 0 then
        local yawError = normalizeAngle(hoverTargetYaw - state.yaw)
        yawCorrection = clamp(
            -YAW_KP * yawError + YAW_KD * state.yawRate,
            -MAX_YAW_CORRECTION,
            MAX_YAW_CORRECTION
        )
    else
        yawCorrection = yawCommand * YAW_THRUST_DIFFERENCE
    end
    if REVERSE_YAW_MIXING then
        yawCorrection = -yawCorrection
    end

    return {
        altitude = 0,
        hover = collectiveThrust,
        pitch = pitchCorrection,
        roll = rollCorrection,
        yaw = yawCorrection,
    }
end

function hoverLoop.applyHoverCorrections(correction)
    -- 前后桨逆时针旋转，增强时机体向右自旋；左右桨顺时针旋转，增强时向左自旋。
    sendMotorSpeed(
        "front",
        correction.hover + correction.altitude + correction.pitch + correction.yaw
    )
    sendMotorSpeed(
        "back",
        correction.hover + correction.altitude - correction.pitch + correction.yaw
    )
    sendMotorSpeed(
        "left",
        correction.hover + correction.altitude + correction.roll - correction.yaw
    )
    sendMotorSpeed(
        "right",
        correction.hover + correction.altitude - correction.roll - correction.yaw
    )
end

function hoverLoop.rememberHoverState(state)
    previousControllerX = controllerX
    previousControllerY = controllerY
    previousControllerZ = controllerZ
    previousPitchError = state.pitchError
    previousRollError = state.rollError
    previousHoverTime = state.now
    previousYaw = state.yaw
end

local function updateHover()
    if not hoverLoop.updateControllerPosition() then
        return
    end

    local propellerPose = hoverLoop.readCurrentPose()
    if propellerPose == nil then
        return
    end

    if powerEnabled ~= true then
        return
    end

    local now = os.epoch("utc") / 1000
    if hoverLoop.shouldEmergencyStop(propellerPose.normalY, now) then
        emergencyPowerOff()
        return
    end

    hoverLoop.ensureHoverTarget()

    local state = hoverLoop.createHoverState(propellerPose, now)
    hoverLoop.updateHoverTargetFromCommands(state)
    hoverLoop.applyHoverCorrections(hoverLoop.calculateHoverCorrections(state))
    hoverLoop.rememberHoverState(state)
end

local function updateCurrentTarget()
    local x
    local y
    local z
    local source
    if customNavigationTargetX ~= nil and customNavigationTargetZ ~= nil then
        x = customNavigationTargetX
        z = customNavigationTargetZ
        source = "CUSTOM"
    else
        local navigationData
        if navigationTableReader ~= nil then
            local ok, data = pcall(navigationTableReader.getBlockData)
            if ok and type(data) == "table" then
                navigationData = data
            end
        end
        local currentStack = navigationData and navigationData.CurrentStack
        local navigationTableHasData =
            type(currentStack) == "table" and next(currentStack) ~= nil

        if navigationTableSuppressed then
            if not navigationTableHasData then
                navigationTableClearedAfterSuppression = true
            elseif navigationTableClearedAfterSuppression then
                navigationTableSuppressed = false
                navigationTableClearedAfterSuppression = false
            end
        end

        if navigationTableHasData then
            local target = navigationData.CurrentTarget
            x = target and (target.x or target.X or target[1])
            y = target and (target.y or target.Y or target[2])
            z = target and (target.z or target.Z or target[3])
            source = "TABLE"
        end
    end

    if source == "TABLE" and navigationTableSuppressed then
        x = nil
        y = nil
        z = nil
        source = nil
    end

    if type(x) ~= "number" or type(z) ~= "number" then
        if navigationWasActive then
            navigationResetPending = true
        end
        if navigationResetPending and controllerX ~= nil and controllerZ ~= nil then
            hoverTargetX = controllerX
            hoverTargetZ = controllerZ
            navigationResetPending = false
        end
        currentTargetX = nil
        currentTargetY = nil
        currentTargetZ = nil
        currentNavigationSource = nil
        navigationWasActive = false
        navigationCompleted = false
        completedNavigationTargetX = nil
        completedNavigationTargetY = nil
        completedNavigationTargetZ = nil
        completedNavigationSource = nil
        return
    end

    local targetChanged =
        completedNavigationTargetX ~= nil
        and (
            x ~= completedNavigationTargetX
            or y ~= completedNavigationTargetY
            or z ~= completedNavigationTargetZ
            or source ~= completedNavigationSource
        )
    if targetChanged then
        navigationCompleted = false
        completedNavigationTargetX = nil
        completedNavigationTargetY = nil
        completedNavigationTargetZ = nil
        completedNavigationSource = nil
    end

    currentTargetX = x
    currentTargetY = y
    currentTargetZ = z
    currentNavigationSource = source
    navigationResetPending = false

    if not navigationCompleted and controllerX ~= nil and controllerZ ~= nil then
        local distanceX = x - controllerX
        local distanceZ = z - controllerZ
        local completionDistanceSquared =
            NAVIGATION_COMPLETION_DISTANCE * NAVIGATION_COMPLETION_DISTANCE
        if distanceX * distanceX + distanceZ * distanceZ <= completionDistanceSquared then
            hoverTargetX = controllerX
            hoverTargetZ = controllerZ
            if source == "CUSTOM" then
                customNavigationTargetX = nil
                customNavigationTargetZ = nil
                currentTargetX = nil
                currentTargetY = nil
                currentTargetZ = nil
                currentNavigationSource = nil
                navigationCompleted = false
                navigationWasActive = false
                completedNavigationTargetX = nil
                completedNavigationTargetY = nil
                completedNavigationTargetZ = nil
                completedNavigationSource = nil
                navigationTableSuppressed = true
                navigationTableClearedAfterSuppression = false
                rednet.send(POWER_CONTROLLER_ID, true, "customnavclear")
                return
            end

            navigationCompleted = true
            completedNavigationTargetX = x
            completedNavigationTargetY = y
            completedNavigationTargetZ = z
            completedNavigationSource = source
        end
    end

    navigationWasActive = not navigationCompleted
end

local function customNavigationLoop()
    rednet.send(POWER_CONTROLLER_ID, true, "customnavget")

    while true do
        local sender, message = rednet.receive("customnav")
        if sender == POWER_CONTROLLER_ID then
            local accepted = false
            if message == "clear" then
                customNavigationTargetX = nil
                customNavigationTargetZ = nil
                navigationCompleted = false
                navigationTableSuppressed = true
                navigationTableClearedAfterSuppression = false
                accepted = true
            elseif message == false or message == "none" then
                customNavigationTargetX = nil
                customNavigationTargetZ = nil
                navigationCompleted = false
                accepted = true
            elseif type(message) == "table"
                and type(message[1]) == "number"
                and type(message[2]) == "number"
            then
                customNavigationTargetX = message[1]
                -- 兼容旧版 {x, y, z} 消息；新协议使用 {x, z}。
                customNavigationTargetZ =
                    type(message[3]) == "number" and message[3] or message[2]
                navigationCompleted = false
                accepted = true
            end
            rednet.send(POWER_CONTROLLER_ID, accepted, "customnavresp")
        end
    end
end

local function controlLoop()
    while true do
        updateCurrentTarget()

        local backward = redstone.getInput("front")
        local forward = redstone.getInput("back")
        local left = redstoneRelayLeft.getInput("left")
        local rotateLeftInput = redstoneRelayLeft.getInput("top")
        local up = redstoneRelayLeft.getInput("bottom")
        local right = redstoneRelayRight.getInput("right")
        local rotateRightInput = redstoneRelayRight.getInput("top")
        local down = redstoneRelayRight.getInput("bottom")
        manualControlActive =
            backward
            or forward
            or left
            or right
            or rotateLeftInput
            or rotateRightInput
            or up
            or down

        logRedstoneInputs({
            backward = backward,
            forward = forward,
            left = left,
            right = right,
            rotateLeft = rotateLeftInput,
            rotateRight = rotateRightInput,
            up = up,
            down = down,
        })

        updatePowerToggleGesture(backward, forward, left, right)

        yawCommand = 0
        forwardCommand = 0
        rightCommand = 0
        verticalCommand = 0

        if backward and not forward then
            forwardCommand = -1
        end

        if forward and not backward then
            forwardCommand = 1
        end

        if left and not right then
            rightCommand = -1
        end

        if rotateLeftInput and not rotateRightInput then
            yawCommand = -1
        end

        if up and not down then
            verticalCommand = 1
        end

        if right and not left then
            rightCommand = 1
        end

        if rotateRightInput and not rotateLeftInput then
            yawCommand = 1
        end

        if down and not up then
            verticalCommand = -1
        end

        updateManualControlRelease()
        updateHover()
        os.sleep(0.05)
    end
end

local function powerUiLoop()
    drawPowerUi("Syncing power status...")

    local statusAvailable = requestPowerStatus()
    local positionAvailable = requestPowerPosition()
    if statusAvailable and positionAvailable then
        drawPowerUi()
    else
        drawPowerUi("Power controller did not respond")
    end

    local refreshTimer = os.startTimer(UI_REFRESH_INTERVAL)
    while true do
        local event, value = os.pullEvent()

        if event == "key" and value == keys.enter then
            drawPowerUi("Waiting for power controller...")

            if togglePower() then
                drawPowerUi()
            else
                drawPowerUi("Power controller did not respond")
            end
            refreshTimer = os.startTimer(UI_REFRESH_INTERVAL)
        elseif event == "key" and adjustHoverTarget(value) then
            drawPowerUi()
        elseif event == "timer" and value == refreshTimer then
            if safetyShutdown then
                stopAllMotors()
                rednet.send(POWER_CONTROLLER_ID, false, "powerset")
                requestPowerStatus()
            end
            requestPowerStatus()
            requestPowerPosition()
            drawPowerUi()
            refreshTimer = os.startTimer(UI_REFRESH_INTERVAL)
        end
    end
end

parallel.waitForAll(controlLoop, powerUiLoop, customNavigationLoop)
