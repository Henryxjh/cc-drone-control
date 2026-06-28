# 无人机控制器调参说明

所有可调参数位于 `controller-config.lua`。控制器使用 GPS 位置反馈估算速度和姿态，没有加速度传感器与陀螺仪，因此参数过大时容易放大 GPS 噪声。

动力控制器使用有符号电机速度：

- `0`：无推力
- `256`：正向最大推力
- `-256`：反向最大推力

控制器正常飞行输出限制在 `0..256`，避免姿态纠偏过大时产生反向下压力。负速度由动力协议支持，可用于电机安装方向修正或后续特殊动作。

调参时每次只修改一组参数，并先在低空测试。旧的 `0..15` 动力参数不能直接继续使用。

## 动力范围

```lua
propulsion = {
    minimumSpeed = -256,
    maximumSpeed = 256,
    minimumFlightSpeed = 0,
    maximumFlightSpeed = 256,
}
```

正常情况下不要将 `minimumFlightSpeed` 设置为负数。

## 动力控制器通信协议

每个动力控制器在 `side.lua` 中配置自己的 `position` 和 `reverse`：

```lua
local position = "left"
local reverse = false
```

- 主控制器使用 `position` 作为 rednet protocol，消息内容为 `-256..256` 的电机速度
- 动力控制器调用 `electric_motor.setSpeed(speed)`
- `reverse = true` 会反转收到的速度，用于修正电机安装方向
- protocol 为 `balance` 时，主控制器发送 `{seq = n, t = utc_ms}`，动力控制器返回 `{position, x, y, z, side = position, seq = n, t = utc_ms}`
- protocol 为 `speed` 时，动力控制器返回电机当前实际速度

正常悬停时，四台动力控制器接收到的正速度都必须产生向上推力。

控制器 UI 中：

- `Cmd` 表示主控制器下发的目标速度

## 红石输入调试日志

在配置文件中开启：

```lua
debug = {
    redstoneLogging = true,
    redstoneLogPath = "redstone-input.log",
}
```

日志路径相对于 `controller.lua` 所在目录。控制器启动后会记录八路红石输入的初始状态，之后仅在状态发生变化时追加日志，避免每个控制循环都写入文件。

日志示例：

```text
[1750000000000] backward=false forward=true left=false right=false rotateLeft=false rotateRight=false up=false down=false
```

关闭调试时设置：

```lua
redstoneLogging = false
```

## 红石电源组合键

前进、后退、左移、右移四路红石控制信号在约 0.2 秒内全部触发时，控制器会切换一次电源状态。保持四路信号不松开不会重复切换；四路信号全部释放后，才能再次触发。

组合键触发时，前后和左右信号两两互斥，因此不会产生移动命令。旋转与升降信号不参与组合键判断。

红石手动飞行输入全部释放时，控制器会把当前控制器坐标刷新为新的悬停目标，避免继续追逐手动飞行期间累积出来的旧目标点。

Shell 中用 `Space/Shift` 调整悬停高度时，只会修改期望高度；实际用于 PID 的悬停目标高度仍会按
`maximumClimbRate/maximumDescentRate` 逐步移动，避免一次按键造成过大的下降阶跃。

## 姿态传感器校准

`gimbal-calibrate.lua` 是独立测试程序，用于为 `simulated:gimbal_sensor` 生成配置片段。
运行前需要：

- 主控制器能通过无线 modem 访问四个动力控制器
- 四个动力控制器已使用带 `seq` 和 `t` 的新版 `side.lua`
- Block Reader 正在读取 `simulated:gimbal_sensor`
- 无人机保持倾斜且静止，最好同时包含前后和左右两个方向的倾斜

运行：

```lua
shell.run("gimbal-calibrate.lua")
```

程序会询问：

- 姿态传感器 Block Reader 所在方向
- 无人机正向对应传感器的方向，可输入 `n/e/s/w` 或完整 `north/east/south/west`
- `ScrollValue1` 对应的轴，可输入 `ew/sn` 或完整 `east_west/south_north`
- 四个动力控制器 ID 和采样次数

程序会读取传感器 `Powers`，同时通过 `balance` 协议读取四个螺旋桨坐标计算真实
`pitchError` 与 `rollError`，再推断传感器轴向和正负号。输出会写入：

```text
gimbal-config-snippet.lua
```

如果输出中的 `pitchSign` 或 `rollSign` 为 `nil`，说明当前倾斜姿态在对应轴上的变化太小。
把无人机调整成更明显的前后/左右倾斜后重新运行。

## Block Reader 自动识别

主控制器不再强制要求 Block Reader 存在。Block Reader 不存在、读取方块不匹配或读取失败时，
控制器仍会继续启动，只是对应功能不可用。

```lua
blockReader = {
    navigationTableBlock = "simulated:navigation_table",
    gimbalSensorBlock = "simulated:gimbal_sensor",
}
```

- 读取到 `navigationTableBlock` 时启用 Navigation Table 自动导航
- 读取到 `gimbalSensorBlock` 时启用姿态传感器；校准配置有效时用于 pitch/roll，yaw 仍由螺旋桨坐标计算
- 读取到其他方块、没有配置 Block Reader 或外设不可用时，不启用任何 Block Reader 功能

主控制器 UI 会显示当前 Block Reader 状态。未支持的方块只会显示为 `unsupported block`，
不会导致程序退出。

姿态传感器读取失败、未校准或输出异常时，主控制器会回退到螺旋桨坐标姿态。

姿态传感器配置：

```lua
gimbalSensor = {
    forwardDirection = "north",
    scrollValue1Axis = "east_west",
    pitchSign = nil,
    rollSign = nil,
    pitchMaxAngleDegrees = 45,
    rollMaxAngleDegrees = 45,
    pitchArmDistance = 12,
    rollArmDistance = 12,
}
```

`pitchSign` 和 `rollSign` 建议使用 `gimbal-calibrate.lua` 生成。任意一个为 `nil` 时，
姿态传感器不会参与主飞控。

`pitchMaxAngleDegrees` 和 `rollMaxAngleDegrees` 是备用值。飞控启动时如果 Block Reader
实际读取到姿态传感器，会自动从方块数据的 `ScrollValue1/2` 读取 power 满量程角度，
并按 `scrollValue1Axis` 和 `forwardDirection` 换算到 pitch/roll 轴。

## Navigation Table 自动导航

当 `simulated:navigation_table` 的 `CurrentStack` 包含物品，并且 `CurrentTarget` 包含有效 X/Z 坐标时，控制器会持续将悬停目标的 X/Z 设置为导航坐标。

```lua
navigation = {
    completionDistance = 1.0,
}
```

- Navigation Table 的 Y 坐标会被忽略
- 当前悬停目标高度保持不变
- 控制器与目标的水平直线距离不超过 `completionDistance` 时，视为导航完成
- 导航完成后，悬停目标 X/Z 会设为当前控制器坐标
- 导航台保持同一个目标时不会重新追踪；目标坐标改变后开始下一次导航
- 自动导航激活期间，检测到任意红石手动控制时暂停本控制周期的自动导航
- Shell 微调按键触发后会短暂暂停自动导航
- 松开手动控制后，只要 Navigation Table 仍有目标，自动导航会恢复
- Navigation Table 变为空时，停止自动导航并将悬停目标 X/Z 设置为当前控制器坐标
- Navigation Table 的清空操作不会改变当前悬停目标高度
- UI 中的 `Navigation target` 显示当前自动导航目标，完成后显示 `COMPLETE`

## 电源控制器自定义导航

电源控制器运行 `power.lua` 后，可以通过终端输入自定义导航坐标：

- `N`：依次输入目标 `X`、`Z` 并发送给主控制器
- `C`：清除自定义目标，主控制器随后恢复 Navigation Table 导航
- `Enter`：切换无人机电源

自定义目标优先于 Navigation Table，并且只控制 X/Z。导航期间保持当前悬停目标高度，
避免进入未加载区域时因地形高度不可预测而自动升降。自定义目标和 Navigation Table
都使用水平直线距离判断是否到达。

自定义导航完成后，主控制器会自动清除自定义目标，并通知电源控制器清除其目标显示。
完成后无人机会直接悬停，并忽略 Navigation Table 当前的数据。控制器观察到
Navigation Table 的 `CurrentStack` 变为空表 `{}` 后，会等待它再次包含数据；出现新数据时
解除忽略并导航到导航台目标。忽略期间仍可接收新的自定义导航目标。

电源控制器程序运行期间会保留最近一次输入的自定义目标。主控制器开电重启后会主动重新
同步该目标。主控制器 UI 的导航目标后会显示来源 `CUSTOM` 或 `TABLE`。

## Shell 悬停目标微调

在控制器 UI 中可以通过键盘按格调整当前悬停目标：

- `W` / `S`：X 坐标增加 / 减少一格
- `A` / `D`：Z 坐标减少 / 增加一格
- `Space`：Y 坐标增加一格
- `Shift`：Y 坐标减少一格
- `Q`：悬停目标航向左旋 `1°`
- `E`：悬停目标航向右旋 `1°`

下降操作不会使目标高度低于 `baseThrustReferenceY`，上升操作不会使目标高度超过
`maximumHoverY`。尚未建立对应悬停目标位置或目标航向时，相关微调按键不会生效。

## 推荐调参顺序

1. 校准基础悬停推力。
2. 调整高度保持。
3. 调整机体调平。
4. 调整水平位置保持。
5. 调整航向保持与自旋。
6. 调整手动移动速度。

## 基础悬停推力

```lua
baseThrust = 137
baseThrustReferenceY = -50
maximumHoverY = 320
thrustPerYLevel = 0.17
```

实际基础悬停推力为：

```lua
baseThrust + (targetY - baseThrustReferenceY) * thrustPerYLevel
```

下降时，高度修正后的总推力不会低于 `baseThrust`，这样可以保留姿态纠偏的最低推力余量。

- `baseThrust`：参考高度时的基础悬停速度
- `baseThrustReferenceY`：`baseThrust` 对应的 Y 坐标，当前为 `-50`
- `baseThrustReferenceY` 同时也是最低悬停目标高度；下降操作不会将目标高度降到该值以下
- `maximumHoverY`：允许设置的最大悬停目标世界 Y 坐标
- 持续下降：增大 `baseThrust`
- 持续上升：减小 `baseThrust`
- 仅在高处持续下降：增大 `thrustPerYLevel`
- 仅在高处持续上升：减小 `thrustPerYLevel`

先关闭其他纠偏影响进行校准。建议每次调整 `baseThrust` 约 `1` 到 `4`。

## 高度保持

```lua
altitudeKp = 34.0
altitudeKd = 25.5
```

- `altitudeKp`：根据目标高度误差调整推力
- `altitudeKd`：根据垂直速度抑制上下振荡

症状与调整：

- 上下反复振荡：降低 `altitudeKp`
- 越过目标高度后继续运动：增大 `altitudeKd`
- 返回目标高度太慢：增大 `altitudeKp`
- 推力等级频繁跳动：降低 `altitudeKp` 和 `altitudeKd`
- GPS 抖动导致推力突变：降低 `altitudeKd`

平稳优先可从以下值开始：

```lua
altitudeKp = 17.0
altitudeKd = 14.0
```

## 机体调平

```lua
levelKp = 51.0
levelKd = 12.0
```

- `levelKp`：纠正前后、左右螺旋桨的高度差
- `levelKd`：抑制机体倾斜速度

症状与调整：

- 前后或左右快速摇摆：降低 `levelKp`
- 倾斜后越过水平位置：增大 `levelKd`
- 恢复水平太慢：增大 `levelKp`
- GPS 噪声导致抖动：降低 `levelKd`

螺旋桨距离控制器越远，高度差越容易被 GPS 检测到，通常可以降低 `levelKp`。

平稳优先可从以下值开始：

```lua
levelKp = 26.0
levelKd = 7.0
```

## 水平位置保持

```lua
horizontalKp = 0.15
horizontalKd = 0.4
maxTiltError = 0.35
```

- `horizontalKp`：根据水平位置误差生成目标倾角
- `horizontalKd`：根据水平速度抑制漂移与越过目标
- `maxTiltError`：限制自动水平纠偏允许的最大倾斜程度

症状与调整：

- 围绕悬停点来回摆动：降低 `horizontalKp`
- 水平速度过快或越过目标：增大 `horizontalKd`
- 返回悬停点太慢：略微增大 `horizontalKp`
- 机体倾斜过大：降低 `maxTiltError`
- 水平纠偏几乎无效：增大 `maxTiltError`

平稳优先可从以下值开始：

```lua
horizontalKp = 0.08
horizontalKd = 0.25
maxTiltError = 0.15
```

## 自旋与航向保持

```lua
yawThrustDifference = 17
reverseYawMixing = false
yawKp = 17.0
yawKd = 7.0
maxYawCorrection = 26
```

- `yawThrustDifference`：手动自旋时两组反向旋转螺旋桨的推力差
- `reverseYawMixing`：四个动力源旋转方向全部与默认假设相反时设为 `true`
- `yawKp`：悬停时保持目标航向的力度
- `yawKd`：抑制当前自旋角速度
- `maxYawCorrection`：航向保持允许使用的最大差动推力

症状与调整：

- 手动自旋太慢：增大 `yawThrustDifference`
- 手动自旋方向错误：将 `yawThrustDifference` 改为负数
- 悬停时缓慢持续自旋：增大 `yawKp`
- 松开旋转输入后停止太慢：增大 `yawKd`
- 航向左右快速抖动：降低 `yawKp` 和 `yawKd`
- 航向纠偏造成高度波动：降低 `maxYawCorrection`

没有旋转输入时，控制器会锁定当前航向。手动旋转期间会释放航向锁定，松开后锁定新的航向。

## 手动移动速度

```lua
horizontalMoveSpeed = 1.5
maximumClimbRate = 1.0
maximumDescentRate = 1.0
```

单位为格/秒。

- `horizontalMoveSpeed`：前进、后退和左右平移速度
- `maximumClimbRate`：上升时目标高度每秒最多增加的格数
- `maximumDescentRate`：下降时目标高度每秒最多减少的格数

这些参数控制悬停目标的移动速度，不直接设置螺旋桨推力。速度过高会造成较大的位置误差和倾斜。

## 通信与刷新参数

```lua
powerResponseTimeout = 1
balanceTimeout = 0.25
balanceMaxPacketAgeTicks = 5
gpsTimeout = 0.25
uiRefreshInterval = 0.5
```

- `powerResponseTimeout`：等待电源控制器响应的最长时间
- `balanceTimeout`：等待本轮螺旋桨坐标响应的最长时间
- `balanceMaxPacketAgeTicks`：丢弃动力控制器坐标包的最大年龄，单位为 tick，1 tick 约为 0.05 秒
- `gpsTimeout`：控制器自身 GPS 定位超时
- `uiRefreshInterval`：控制器 UI 刷新间隔

主控制器会给每轮 `balance` 请求分配 `seq`，只接收同一轮 `seq` 的响应。响应包里的 `t` 使用 `os.epoch("utc")`，超过 `balanceMaxPacketAgeTicks` 对应时间的包会被丢弃。

姿态计算不再强制等待四个螺旋桨坐标全部返回，而是从最近未过期坐标中选择时间跨度最小的 3 个非共线点，按机体对称关系补齐缺失的第四点，再计算航向、俯仰误差和横滚误差。这样可以降低单个动力控制器响应延迟过高对控制周期的影响。

计算出的航向、俯仰误差或横滚误差如果相对上一帧突变超过 `maxPoseYawJumpDegrees`、`maxPosePitchJump` 或 `maxPoseRollJump`，本轮会沿用上一帧已接受姿态，避免单帧异常数据进入安全停机和 PID 输出。

超时时间过短会导致控制周期经常跳过，过长会降低控制响应速度。网络不稳定时优先略微增大 `balanceTimeout`、`balanceMaxPacketAgeTicks` 和 `gpsTimeout`。

## 平稳优先起始配置

```lua
hover = {
    baseThrust = 137,
    baseThrustReferenceY = -50,
    maximumHoverY = 320,
    thrustPerYLevel = 0.17,

    altitudeKp = 17.0,
    altitudeKd = 14.0,

    levelKp = 26.0,
    levelKd = 7.0,

    horizontalKp = 0.08,
    horizontalKd = 0.25,
    maxTiltError = 0.15,

    yawThrustDifference = 17,
    reverseYawMixing = false,
    yawKp = 12.0,
    yawKd = 4.0,
    maxYawCorrection = 17,

    maxPoseYawJumpDegrees = 45,
    maxPosePitchJump = 1.5,
    maxPoseRollJump = 1.5,

    horizontalMoveSpeed = 1.0,
    maximumClimbRate = 0.75,
    maximumDescentRate = 0.75,
}
```

## 常见问题快速对照

| 现象 | 优先调整 |
| --- | --- |
| 整体持续上升或下降 | `baseThrust` |
| 高处悬停推力不足 | `thrustPerYLevel` |
| 上下反复振荡 | 降低 `altitudeKp`，调整 `altitudeKd` |
| 前后或左右摇摆 | 降低 `levelKp`，调整 `levelKd` |
| 水平位置来回摆动 | 降低 `horizontalKp`、`maxTiltError` |
| 水平漂移停止太慢 | 增大 `horizontalKd` |
| 悬停时自旋 | 增大 `yawKp` 或 `yawKd` |
| 航向左右抖动 | 降低 `yawKp`、`yawKd` |
| 自旋造成高度变化 | 降低 `yawThrustDifference` 或 `maxYawCorrection` |
| 姿态偶发跳变 | 降低 `maxPoseYawJumpDegrees`、`maxPosePitchJump`、`maxPoseRollJump` |
| 大幅机动时姿态经常丢失 | 增大 `maxPoseYawJumpDegrees`、`maxPosePitchJump`、`maxPoseRollJump` |
| 手动移动过于激进 | 降低移动速度参数 |

电源从关闭切换到开启后，主控制器会自动重启并重新加载 `controller-config.lua`。电源控制器保持开启；主控制器启动后会使用新的 GPS 坐标和航向作为悬停目标。

## 翻转安全停机

```lua
safety = {
    controllerBelowPowerTolerance = 0.75,
    shutdownDelay = 1.5,
    invertedNormalYThreshold = -0.1,
}
```

控制器启动后会根据四个螺旋桨坐标记录正常朝上的桨平面方向。仅当以下条件同时满足时，
安全保护才会关闭电源和四个螺旋桨动力：

1. 主控制器低于电源控制器超过 `controllerBelowPowerTolerance`
2. 桨平面相对启动姿态已经翻转，法向量 Y 分量低于 `invertedNormalYThreshold`
3. 异常状态持续时间达到 `shutdownDelay`

- `controllerBelowPowerTolerance`：过滤水平移动倾斜和 GPS 抖动造成的小幅高度交叉
- `shutdownDelay`：过滤短暂倾斜；设置过大将延迟真正翻转后的停机
- `invertedNormalYThreshold`：负数越小，机体必须翻转得越严重才会停机
- 长时间水平移动仍会误触发时，优先略微增大 `controllerBelowPowerTolerance`
- 正常水平移动的机体仍然朝上，因此即使持续移动也不会触发安全停机
- 开启控制器电源时，应确保机体处于正常朝上的形态

恢复机体形态后必须按 Enter 手动重新开启电源；安全保护不会自动重新开机。

## 计算每格动力增长率

使用 `calculate_thrust_rate.py`，传入至少两个实测的 `高度,悬停动力` 数据点：

```bash
python3 calculate_thrust_rate.py --reference-y=-50 -- -50,137 0,145.5 50,154
```

`--` 用于分隔选项与负高度测量点。脚本会执行线性拟合并输出可直接填入配置文件的 `baseThrust`、`baseThrustReferenceY` 和 `thrustPerYLevel`。
