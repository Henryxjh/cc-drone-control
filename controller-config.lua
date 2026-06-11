return {
    -- 外设所在方向。
    peripherals = {
        blockReader = "bottom",
        teleporter = "top",
        redstoneRelayLeft = "left",
        redstoneRelayRight = "right",
    },

    -- Block Reader 必须读取的方块注册名。
    navigationTableBlock = "simulated:navigation_table",

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
    gpsTimeout = 0.25,
    uiRefreshInterval = 0.5,

    debug = {
        -- 开启后，将红石控制输入的变化写入独立日志文件。
        redstoneLogging = false,
        redstoneLogPath = "redstone-input.log",
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

        -- 手动移动时悬停目标的水平移动速度，单位为格/秒。
        horizontalMoveSpeed = 1.5,

        -- 手动升降时悬停目标的最大上升率和最大下降率，单位为格/秒。
        maximumClimbRate = 1.0,
        maximumDescentRate = 1.0,
    },
}
