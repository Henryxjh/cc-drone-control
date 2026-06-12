# CC:Tweaked Drone Controller

基于 CC:Tweaked、GPS 与 Rednet 的四旋翼无人机控制脚本。控制器通过四个独立动力控制器
获取螺旋桨坐标并输出电机速度，实现悬停、手动移动、自动导航和安全停机。

项目仍处于实验阶段。请先在低空、小推力环境中测试，并准备可靠的断电方式。

## 功能

- GPS 悬停、水平位置保持、高度保持和航向保持
- 红石输入控制前后、左右、升降和旋转
- Navigation Table 自动导航
- 电源控制器终端输入自定义 X/Z 导航目标
- 导航完成距离、最低和最高悬停高度限制
- 翻转检测、安全断电和电机归零
- 独立配置文件与可选红石输入日志

## 文件

| 文件 | 用途 |
| --- | --- |
| `controller.lua` | 无人机主控制器 |
| `controller-config.lua` | 主控制器配置与 PID 参数 |
| `side.lua` | 单个螺旋桨动力控制器 |
| `power.lua` | 电源控制器与自定义导航终端 |
| `control.md` | 完整部署、协议和调参说明 |
| `calculate_thrust_rate.py` | 根据实测数据计算每格动力增长率 |

## 运行要求

- CC:Tweaked 计算机与无线/末影调制解调器
- 可用的 GPS 网络
- 四个支持有符号速度 `-256..256` 的 `electric_motor`
- 一个电源控制器
- 两个 Redstone Relay
- Advanced Peripherals Block Reader
- `simulated:navigation_table`

## 快速开始

1. 将 `controller.lua` 和 `controller-config.lua` 放入主控制器。
2. 在四个动力控制器中分别放入 `side.lua`，并修改顶部的 `controller`、`position` 和
   `reverse`。
3. 将 `power.lua` 放入电源控制器，并修改顶部的主控制器 ID。
4. 修改 `controller-config.lua` 中的外设方向、计算机 ID、动力范围和悬停参数。
5. 确认正速度产生向上推力，然后从低空开始校准 `baseThrust`。

不要直接使用示例 PID 参数进行高空测试。详细调参顺序见 [control.md](control.md)。

## 自启动

每台 CC:Tweaked 计算机都需要创建 `startup.lua`，在计算机启动时运行对应脚本。

主控制器：

```lua
shell.run("controller.lua")
```

四个动力控制器：

```lua
shell.run("side.lua")
```

电源控制器：

```lua
shell.run("power.lua")
```

`startup.lua` 必须与对应脚本位于同一台计算机中。主控制器在电源从关闭切换到开启后会
自动重启，因此缺少 `startup.lua` 时不会自动恢复控制。

## 控制

主控制器终端：

- `W/S`：调整目标 X
- `A/D`：调整目标 Z
- `Space/Shift`：调整目标高度
- `Q/E`：调整目标航向
- `Enter`：切换电源

电源控制器终端：

- `N`：输入自定义 X/Z 导航目标
- `C`：清除自定义导航并悬停
- `Enter`：切换电源

自定义导航完成后，无人机会悬停并等待 Navigation Table 的 `CurrentStack` 先变为空表
`{}`，再出现新数据后恢复 Navigation Table 导航。

## 安全说明

- 控制器没有加速度传感器或陀螺仪，姿态与速度均由 GPS 坐标估算。
- GPS 或 Rednet 延迟会直接影响稳定性。
- 安全停机会关闭电源并将四个电机速度设为 `0`，恢复形态后需要手动重新开机。
- 更新代码前保留独立的 `controller-config.lua`，避免覆盖实测参数。
