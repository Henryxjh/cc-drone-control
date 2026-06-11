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
local motorControllers =
    requireConfigType("motorControllers", config.motorControllers, "table")

local BLOCK_READER_SIDE =
    requireConfigType("peripherals.blockReader", peripherals.blockReader, "string")
local TELEPORTER_SIDE =
    requireConfigType("peripherals.teleporter", peripherals.teleporter, "string")
local REDSTONE_RELAY_LEFT_SIDE =
    requireConfigType("peripherals.redstoneRelayLeft", peripherals.redstoneRelayLeft, "string")
local REDSTONE_RELAY_RIGHT_SIDE =
    requireConfigType("peripherals.redstoneRelayRight", peripherals.redstoneRelayRight, "string")
local NAVIGATION_TABLE_BLOCK =
    requireConfigType("navigationTableBlock", config.navigationTableBlock, "string")

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

local BASE_THRUST = requireConfigType("hover.baseThrust", hoverConfig.baseThrust, "number")
local BASE_THRUST_REFERENCE_Y =
    requireConfigType("hover.baseThrustReferenceY", hoverConfig.baseThrustReferenceY, "number")
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
local GPS_TIMEOUT = requireConfigType("gpsTimeout", config.gpsTimeout, "number")

if BASE_THRUST < MINIMUM_FLIGHT_SPEED or BASE_THRUST > MAXIMUM_FLIGHT_SPEED then
    fatalError("invalid hover.baseThrust: outside normal flight speed range")
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

local blockReader = peripheral.wrap(BLOCK_READER_SIDE)
if blockReader == nil or not peripheral.hasType(BLOCK_READER_SIDE, "block_reader") then
    fatalError("can't find advancedperipherals:block_reader at " .. BLOCK_READER_SIDE .. "!")
end

if blockReader.getBlockName() ~= NAVIGATION_TABLE_BLOCK then
    fatalError("block reader isn't reading " .. NAVIGATION_TABLE_BLOCK .. "!")
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
local manualControlActive = false
local navigationWasActive = false
local navigationResetPending = false
local manualNavigationPauseUntil = 0

local function moveBackward()
    forwardCommand = -1
end

local function moveForward()
    forwardCommand = 1
end

local function strafeLeft()
    rightCommand = -1
end

local function rotateLeft()
    yawCommand = -1
end

local function moveUp()
    verticalCommand = 1
end

local function strafeRight()
    rightCommand = 1
end

local function rotateRight()
    yawCommand = 1
end

local function moveDown()
    verticalCommand = -1
end

local hoverTargetX
local hoverTargetY
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
    hoverTargetZ = nil
    previousControllerX = nil
    previousControllerY = nil
    previousControllerZ = nil
    previousPitchError = nil
    previousRollError = nil
    previousHoverTime = nil
    hoverTargetYaw = nil
    previousYaw = nil
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
        hoverTargetY = hoverTargetY + 1
    elseif key == keys.leftShift or key == keys.rightShift then
        hoverTargetY = math.max(BASE_THRUST_REFERENCE_Y, hoverTargetY - 1)
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
    if hoverTargetY == nil then
        return nil
    end

    return round(clamp(
        BASE_THRUST + (hoverTargetY - BASE_THRUST_REFERENCE_Y) * THRUST_PER_Y_LEVEL,
        MINIMUM_FLIGHT_SPEED,
        MAXIMUM_FLIGHT_SPEED
    ))
end

local function drawPowerUi(message)
    term.clear()
    term.setCursorPos(1, 1)
    print("Drone Controller")
    print("")

    if powerEnabled == nil then
        print("Power: UNKNOWN")
    elseif powerEnabled then
        print("Power: ON")
    else
        print("Power: OFF")
    end

    if powerControllerX == nil then
        print("Power position: UNKNOWN")
    else
        print(("Power position: %.2f %.2f %.2f"):format(
            powerControllerX,
            powerControllerY,
            powerControllerZ
        ))
    end

    if controllerX == nil then
        print("Controller position: UNKNOWN")
    else
        print(("Controller position: %.2f %.2f %.2f"):format(
            controllerX,
            controllerY,
            controllerZ
        ))
    end

    if hoverTargetX == nil then
        print("Hover target: UNKNOWN")
    else
        print(("Hover target: %.2f %.2f %.2f"):format(
            hoverTargetX,
            hoverTargetY,
            hoverTargetZ
        ))
    end

    if currentTargetX == nil or currentTargetZ == nil then
        print("Navigation target: NONE")
    else
        print(("Navigation target: %.2f %.2f"):format(currentTargetX, currentTargetZ))
    end

    local currentHeading = yawToHeading(currentYaw)
    local targetHeading = yawToHeading(hoverTargetYaw)
    if currentHeading == nil then
        print("Heading: UNKNOWN")
    else
        print(("Heading: %.1f deg"):format(currentHeading))
    end
    if targetHeading == nil then
        print("Target heading: UNKNOWN")
    else
        print(("Target heading: %.1f deg"):format(targetHeading))
    end

    local theoreticalHoverSpeed = getTheoreticalHoverSpeed()
    if theoreticalHoverSpeed == nil then
        print("Theoretical hover speed: UNKNOWN")
    else
        print(("Theoretical hover speed: %d"):format(theoreticalHoverSpeed))
    end

    print("")
    print(("Cmd F:%d B:%d"):format(motorSpeed.front, motorSpeed.back))
    print(("Cmd L:%d R:%d"):format(motorSpeed.left, motorSpeed.right))
    print(("Motor range: %d to %d"):format(MINIMUM_MOTOR_SPEED, MAXIMUM_MOTOR_SPEED))

    print("")
    print("Press Enter to toggle power")

    if safetyShutdown then
        local previousColor = term.getTextColor()
        term.setTextColor(colors.red)
        print("")
        print("SAFETY SHUTDOWN: inverted flight detected")
        print("Restore shape, then press Enter to restart")
        term.setTextColor(previousColor)
    end

    if message then
        print("")
        print(message)
    end
end

local function readPropellerPositions()
    local positions = {}
    local remaining = 0

    for _, controllerId in pairs(motorControllers) do
        rednet.send(controllerId, true, "balance")
        remaining = remaining + 1
    end

    local timer = os.startTimer(BALANCE_TIMEOUT)
    while remaining > 0 do
        local event, first, second, third = os.pullEvent()

        if event == "timer" and first == timer then
            break
        end

        if event == "rednet_message" and third == "balanceresp" then
            local sender = first
            local response = second
            local side = type(response) == "table" and response[1]

            if motorControllers[side] == sender
                and type(response[2]) == "number"
                and type(response[3]) == "number"
                and type(response[4]) == "number"
                and positions[side] == nil
            then
                positions[side] = {
                    x = response[2],
                    y = response[3],
                    z = response[4],
                }
                remaining = remaining - 1
            end
        end
    end

    if remaining > 0 then
        return nil
    end

    return positions
end

local function updateHover()
    local locatedX, locatedY, locatedZ = gps.locate(GPS_TIMEOUT, false)
    if locatedX == nil or locatedY == nil or locatedZ == nil then
        controllerX = nil
        controllerY = nil
        controllerZ = nil
        unsafePositionSince = nil
        return
    end
    controllerX = locatedX
    controllerY = locatedY
    controllerZ = locatedZ

    local propellerPositions = readPropellerPositions()
    if propellerPositions == nil then
        currentYaw = nil
        return
    end

    local forwardX = propellerPositions.front.x - propellerPositions.back.x
    local forwardY = propellerPositions.front.y - propellerPositions.back.y
    local forwardZ = propellerPositions.front.z - propellerPositions.back.z
    local forwardLength = math.sqrt(forwardX * forwardX + forwardZ * forwardZ)
    local rightX = propellerPositions.right.x - propellerPositions.left.x
    local rightY = propellerPositions.right.y - propellerPositions.left.y
    local rightZ = propellerPositions.right.z - propellerPositions.left.z
    local rightLength = math.sqrt(rightX * rightX + rightZ * rightZ)
    local forwardLength3d =
        math.sqrt(forwardX * forwardX + forwardY * forwardY + forwardZ * forwardZ)
    local rightLength3d =
        math.sqrt(rightX * rightX + rightY * rightY + rightZ * rightZ)

    if forwardLength == 0 or rightLength == 0 or forwardLength3d == 0 or rightLength3d == 0 then
        currentYaw = nil
        unsafePositionSince = nil
        return
    end

    local normalY =
        (forwardZ * rightX - forwardX * rightZ) / (forwardLength3d * rightLength3d)
    if uprightNormalSign == nil and math.abs(normalY) >= 0.25 then
        uprightNormalSign = normalY >= 0 and 1 or -1
    end

    forwardX = forwardX / forwardLength
    forwardZ = forwardZ / forwardLength
    rightX = rightX / rightLength
    rightZ = rightZ / rightLength
    currentYaw = math.atan2(forwardZ, forwardX)

    if powerEnabled ~= true then
        return
    end

    local now = os.epoch("utc") / 1000
    local controllerClearlyBelowPower =
        powerControllerY ~= nil
        and controllerY + CONTROLLER_BELOW_POWER_TOLERANCE < powerControllerY
    local inverted =
        uprightNormalSign ~= nil
        and normalY * uprightNormalSign < INVERTED_NORMAL_Y_THRESHOLD
    if controllerClearlyBelowPower and inverted then
        unsafePositionSince = unsafePositionSince or now
        if now - unsafePositionSince >= SAFETY_SHUTDOWN_DELAY then
            emergencyPowerOff()
            return
        end
    else
        unsafePositionSince = nil
    end

    if hoverTargetY == nil then
        hoverTargetX = controllerX
        hoverTargetY = math.max(controllerY, BASE_THRUST_REFERENCE_Y)
        hoverTargetZ = controllerZ
    end

    local deltaTime = previousHoverTime and now - previousHoverTime or nil
    local velocityX = 0
    local verticalVelocity = 0
    local velocityZ = 0
    local pitchRate = 0
    local rollRate = 0
    local yawRate = 0

    local pitchError = propellerPositions.front.y - propellerPositions.back.y
    local rollError = propellerPositions.left.y - propellerPositions.right.y

    if deltaTime and deltaTime > 0 then
        velocityX = (controllerX - previousControllerX) / deltaTime
        verticalVelocity = (controllerY - previousControllerY) / deltaTime
        velocityZ = (controllerZ - previousControllerZ) / deltaTime
        pitchRate = (pitchError - previousPitchError) / deltaTime
        rollRate = (rollError - previousRollError) / deltaTime
    end

    local movementDeltaTime = clamp(deltaTime or 0, 0, 0.5)
    local forwardDistance = forwardCommand * HORIZONTAL_MOVE_SPEED * movementDeltaTime
    local rightDistance = rightCommand * HORIZONTAL_MOVE_SPEED * movementDeltaTime
    hoverTargetX = hoverTargetX + forwardX * forwardDistance + rightX * rightDistance
    if verticalCommand > 0 then
        hoverTargetY = hoverTargetY + MAXIMUM_CLIMB_RATE * movementDeltaTime
    elseif verticalCommand < 0 then
        hoverTargetY = math.max(
            BASE_THRUST_REFERENCE_Y,
            hoverTargetY - MAXIMUM_DESCENT_RATE * movementDeltaTime
        )
    end
    hoverTargetZ = hoverTargetZ + forwardZ * forwardDistance + rightZ * rightDistance

    -- 自动导航仅控制水平位置；任意手动操作会暂停本周期的自动导航。
    local manualNavigationPaused =
        manualControlActive or os.epoch("utc") < manualNavigationPauseUntil
    if currentTargetX ~= nil and currentTargetZ ~= nil and not manualNavigationPaused then
        hoverTargetX = currentTargetX
        hoverTargetZ = currentTargetZ
    end

    local yaw = currentYaw
    if hoverTargetYaw == nil or yawCommand ~= 0 then
        hoverTargetYaw = yaw
    end
    if deltaTime and deltaTime > 0 and previousYaw ~= nil then
        yawRate = normalizeAngle(yaw - previousYaw) / deltaTime
    end

    local positionErrorX = hoverTargetX - controllerX
    local positionErrorZ = hoverTargetZ - controllerZ
    local forwardPositionError = positionErrorX * forwardX + positionErrorZ * forwardZ
    local rightPositionError = positionErrorX * rightX + positionErrorZ * rightZ
    local forwardVelocity = velocityX * forwardX + velocityZ * forwardZ
    local rightVelocity = velocityX * rightX + velocityZ * rightZ

    local forwardPositionCommand =
        HORIZONTAL_KP * forwardPositionError - HORIZONTAL_KD * forwardVelocity
    local rightPositionCommand =
        HORIZONTAL_KP * rightPositionError - HORIZONTAL_KD * rightVelocity
    local desiredPitchError =
        -clamp(forwardPositionCommand, -MAX_TILT_ERROR, MAX_TILT_ERROR)
    local desiredRollError =
        clamp(rightPositionCommand, -MAX_TILT_ERROR, MAX_TILT_ERROR)

    local altitudeCorrection =
        ALTITUDE_KP * (hoverTargetY - controllerY) - ALTITUDE_KD * verticalVelocity
    local hoverThrust =
        BASE_THRUST + (hoverTargetY - BASE_THRUST_REFERENCE_Y) * THRUST_PER_Y_LEVEL
    local pitchCorrection =
        -LEVEL_KP * (pitchError - desiredPitchError) - LEVEL_KD * pitchRate
    local rollCorrection =
        -LEVEL_KP * (rollError - desiredRollError) - LEVEL_KD * rollRate
    local yawCorrection
    if yawCommand == 0 then
        local yawError = normalizeAngle(hoverTargetYaw - yaw)
        yawCorrection = clamp(
            -YAW_KP * yawError + YAW_KD * yawRate,
            -MAX_YAW_CORRECTION,
            MAX_YAW_CORRECTION
        )
    else
        yawCorrection = yawCommand * YAW_THRUST_DIFFERENCE
    end
    if REVERSE_YAW_MIXING then
        yawCorrection = -yawCorrection
    end

    -- 前后桨逆时针旋转，增强时机体向右自旋；左右桨顺时针旋转，增强时向左自旋。
    sendMotorSpeed(
        "front",
        hoverThrust + altitudeCorrection + pitchCorrection + yawCorrection
    )
    sendMotorSpeed(
        "back",
        hoverThrust + altitudeCorrection - pitchCorrection + yawCorrection
    )
    sendMotorSpeed(
        "left",
        hoverThrust + altitudeCorrection + rollCorrection - yawCorrection
    )
    sendMotorSpeed(
        "right",
        hoverThrust + altitudeCorrection - rollCorrection - yawCorrection
    )

    previousControllerX = controllerX
    previousControllerY = controllerY
    previousControllerZ = controllerZ
    previousPitchError = pitchError
    previousRollError = rollError
    previousHoverTime = now
    previousYaw = yaw
end

local function updateCurrentTarget()
    local navigationData = blockReader.getBlockData()
    local currentStack = navigationData and navigationData.CurrentStack

    if type(currentStack) ~= "table" or next(currentStack) == nil then
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
        navigationWasActive = false
        return
    end

    local target = navigationData.CurrentTarget
    local x = target and (target.x or target.X or target[1])
    local y = target and (target.y or target.Y or target[2])
    local z = target and (target.z or target.Z or target[3])

    if type(x) ~= "number" or type(z) ~= "number" then
        currentTargetX = nil
        currentTargetY = nil
        currentTargetZ = nil
        navigationWasActive = false
        return
    end

    currentTargetX = x
    currentTargetY = y
    currentTargetZ = z
    navigationWasActive = true
    navigationResetPending = false
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
        local allSignalsActive =
            backward
            and forward
            and left
            and right
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

        if allSignalsActive and not allSignalsToggleLatched then
            allSignalsToggleLatched = true
            rednet.send(POWER_CONTROLLER_ID, true, "power")
        elseif not allSignalsActive then
            allSignalsToggleLatched = false
        end

        yawCommand = 0
        forwardCommand = 0
        rightCommand = 0
        verticalCommand = 0

        if backward and not forward then
            moveBackward()
        end

        if forward and not backward then
            moveForward()
        end

        if left and not right then
            strafeLeft()
        end

        if rotateLeftInput and not rotateRightInput then
            rotateLeft()
        end

        if up and not down then
            moveUp()
        end

        if right and not left then
            strafeRight()
        end

        if rotateRightInput and not rotateLeftInput then
            rotateRight()
        end

        if down and not up then
            moveDown()
        end

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
            local positionUpdated = requestPowerPosition()
            drawPowerUi(positionUpdated and nil or "Power position unavailable")
            refreshTimer = os.startTimer(UI_REFRESH_INTERVAL)
        end
    end
end

parallel.waitForAll(controlLoop, powerUiLoop)
