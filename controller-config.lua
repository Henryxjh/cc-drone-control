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

    -- 四个螺旋桨控制器的计算机 ID。
    propellerControllers = {
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

    hover = {
        -- Y=0 时单个螺旋桨的基础悬停推力，范围为 0 到 15。
        baseThrust = 8,

        -- 目标 Y 坐标每增加一格，需要增加的基础悬停推力。
        thrustPerYLevel = 0.01,

        -- 高度位置误差和垂直速度阻尼增益。
        altitudeKp = 2.0,
        altitudeKd = 1.5,

        -- 机体倾斜误差和倾斜变化速度阻尼增益。
        levelKp = 3.0,
        levelKd = 0.7,

        -- 水平位置误差和水平速度阻尼增益。
        horizontalKp = 0.15,
        horizontalKd = 0.4,

        -- 水平位置控制允许的最大目标高度差。
        maxTiltError = 0.35,

        -- 自旋时两组反向旋转螺旋桨之间的推力差。
        -- 增大可提升自旋速度，但过大会造成高度波动。
        yawThrustDifference = 1,

        -- 悬停时的航向保持和自旋速度阻尼增益。
        yawKp = 1.0,
        yawKd = 0.4,

        -- 航向纠偏允许使用的最大差动推力。
        maxYawCorrection = 1.5,

        -- 手动移动时悬停目标的水平和垂直移动速度，单位为格/秒。
        horizontalMoveSpeed = 1.5,
        verticalMoveSpeed = 1.0,
    },
}
