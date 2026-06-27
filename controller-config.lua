return {
    -- 外设所在方向。
    peripherals = {
        blockReader = "bottom",
        teleporter = "top",
        redstoneRelayLeft = "left",
        redstoneRelayRight = "right",
    },

    blockReader = {
        -- Block Reader 不存在、方块不匹配或读取失败时，控制器仍会继续启动。
        -- 实际连接到导航台或姿态传感器时，控制器会按读取到的方块自动启用对应功能。

        -- 读取到此方块时启用 Navigation Table 自动导航。
        navigationTableBlock = "simulated:navigation_table",

        -- 读取到此方块时启用姿态传感器。
        gimbalSensorBlock = "simulated:gimbal_sensor",
    },

    navigation = {
        -- 与 Navigation Table 目标的水平距离不超过此值时，视为导航完成。
        completionDistance = 1.0,
    },

    gimbalSensor = {
        -- 无人机正向对应姿态传感器的方向：north、east、south、west。
        forwardDirection = "north",

        -- ScrollValue1 对应的传感器轴：east_west 或 south_north。
        scrollValue1Axis = "east_west",

        -- 由 gimbal-calibrate.lua 生成；为 nil 时不会使用姿态传感器参与飞控。
        pitchSign = nil,
        rollSign = nil,

        -- 传感器 power 满量程时对应的角度。
        pitchMaxAngleDegrees = 45,
        rollMaxAngleDegrees = 45,

        -- 前后/左右螺旋桨间距。
        pitchArmDistance = 12,
        rollArmDistance = 12,
    },

    -- 四个动力控制器的计算机 ID。
    motorControllers = {
        left = 2,
        right = 3,
        front = 4,
        back = 5,
    },

    -- 无人机电源控制器的计算机 ID。
    powerControllerId = 6,

    -- 通信与 UI 超时，单位为秒。
    powerResponseTimeout = 1,
    balanceTimeout = 0.25,
    -- 丢弃超过此 tick 数的动力控制器坐标包，1 tick 约为 0.05 秒。
    balanceMaxPacketAgeTicks = 5,
    gpsTimeout = 0.25,
    uiRefreshInterval = 0.5,

    debug = {
        -- 开启后，将红石控制输入的变化写入独立日志文件。
        redstoneLogging = false,
        redstoneLogPath = "redstone-input.log",
    },

    safety = {
        -- 主控制器低于电源控制器超过此高度差时，才视为可能翻转。
        controllerBelowPowerTolerance = 0.75,

        -- 异常姿态必须持续达到此秒数才执行安全停机。
        shutdownDelay = 1.5,

        -- 相对桨平面法向量的 Y 分量低于此值时，才视为已经翻转。
        invertedNormalYThreshold = -0.1,
    },

    propulsion = {
        -- 电机协议支持的完整速度范围。
        minimumSpeed = -256,
        maximumSpeed = 256,

        -- 正常飞行允许的速度范围。最低值保持为 0，避免产生反向下压力。
        minimumFlightSpeed = 0,
        maximumFlightSpeed = 256,
    },

    hover = {
        -- 参考高度时单个动力源的基础悬停速度，范围为 0 到 256。
        baseThrust = 137,

        -- baseThrust 对应的 Y 坐标。
        baseThrustReferenceY = -50,

        -- 允许设置的最大悬停目标世界 Y 坐标。
        maximumHoverY = 320,

        -- 目标 Y 坐标每增加一格，需要增加的基础悬停推力。
        thrustPerYLevel = 0.17,

        -- 高度位置误差和垂直速度阻尼增益。
        altitudeKp = 34.0,
        altitudeKd = 25.5,

        -- 机体倾斜误差和倾斜变化速度阻尼增益。
        levelKp = 51.0,
        levelKd = 12.0,

        -- 水平位置误差和水平速度阻尼增益。
        horizontalKp = 0.15,
        horizontalKd = 0.4,

        -- 水平位置控制允许的最大目标高度差。
        maxTiltError = 0.35,

        -- 自旋时两组反向旋转螺旋桨之间的推力差。
        -- 增大可提升自旋速度，但过大会造成高度波动。
        yawThrustDifference = 17,

        -- 四个动力源旋转方向全部与默认假设相反时设为 true。
        reverseYawMixing = false,

        -- 悬停时的航向保持和自旋速度阻尼增益。
        yawKp = 17.0,
        yawKd = 7.0,

        -- 航向纠偏允许使用的最大差动推力。
        maxYawCorrection = 26,

        -- 单次姿态采样允许的最大航向突变，单位为度；超过则丢弃本轮姿态。
        maxPoseYawJumpDegrees = 45,

        -- 单次姿态采样允许的最大前后/左右高度差突变，单位为格；超过则丢弃本轮姿态。
        maxPosePitchJump = 1.5,
        maxPoseRollJump = 1.5,

        -- 手动移动时悬停目标的水平移动速度，单位为格/秒。
        horizontalMoveSpeed = 1.5,

        -- 手动升降时悬停目标的最大上升率和最大下降率，单位为格/秒。
        maximumClimbRate = 1.0,
        maximumDescentRate = 1.0,
    },
}
