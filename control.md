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
- protocol 为 `balance` 时，动力控制器返回 `{position, x, y, z}`
- protocol 为 `speed` 时，动力控制器返回电机当前实际速度

正常悬停时，四台动力控制器接收到的正速度都必须产生向上推力。

控制器 UI 中：

- `Cmd` 表示主控制器下发的目标速度
- `Real` 表示动力控制器通过 `electric_motor.getSpeed()` 返回的实际速度
- `Real` 为 `?` 表示对应动力控制器未在超时前响应

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
thrustPerYLevel = 0.17
```

实际基础悬停推力为：

```lua
baseThrust + (targetY - baseThrustReferenceY) * thrustPerYLevel
```

- `baseThrust`：参考高度时的基础悬停速度
- `baseThrustReferenceY`：`baseThrust` 对应的 Y 坐标，当前为 `-50`
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
yawKp = 17.0
yawKd = 7.0
maxYawCorrection = 26
```

- `yawThrustDifference`：手动自旋时两组反向旋转螺旋桨的推力差
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
verticalMoveSpeed = 1.0
```

单位为格/秒。

- `horizontalMoveSpeed`：前进、后退和左右平移速度
- `verticalMoveSpeed`：上升和下降速度

这些参数控制悬停目标的移动速度，不直接设置螺旋桨推力。速度过高会造成较大的位置误差和倾斜。

## 通信与刷新参数

```lua
powerResponseTimeout = 1
balanceTimeout = 0.25
gpsTimeout = 0.25
uiRefreshInterval = 0.5
```

- `powerResponseTimeout`：等待电源控制器响应的最长时间
- `balanceTimeout`：等待四个螺旋桨坐标响应的最长时间
- `gpsTimeout`：控制器自身 GPS 定位超时
- `uiRefreshInterval`：控制器 UI 刷新间隔

超时时间过短会导致控制周期经常跳过，过长会降低控制响应速度。网络不稳定时优先略微增大 `balanceTimeout` 和 `gpsTimeout`。

## 平稳优先起始配置

```lua
hover = {
    baseThrust = 137,
    baseThrustReferenceY = -50,
    thrustPerYLevel = 0.17,

    altitudeKp = 17.0,
    altitudeKd = 14.0,

    levelKp = 26.0,
    levelKd = 7.0,

    horizontalKp = 0.08,
    horizontalKd = 0.25,
    maxTiltError = 0.15,

    yawThrustDifference = 17,
    yawKp = 12.0,
    yawKd = 4.0,
    maxYawCorrection = 17,

    horizontalMoveSpeed = 1.0,
    verticalMoveSpeed = 0.75,
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
| 手动移动过于激进 | 降低移动速度参数 |

电源从关闭切换到开启后，控制器会使用新的 GPS 坐标和航向作为悬停目标。

当主控制器的 Y 坐标低于电源控制器的 Y 坐标时，安全保护会关闭电源和四个螺旋桨动力。恢复机体形态后必须按 Enter 手动重新开启电源；安全保护不会自动重新开机。
