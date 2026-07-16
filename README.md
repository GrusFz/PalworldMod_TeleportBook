# 前言 | Preface

**希望官方重视**

目前游戏中存在一个比较明显的痛点：随着玩家基地不断扩建，建筑物越建越高，动辄十几层甚至几十层。虽然楼梯可以解决垂直移动问题，但每天频繁地上下楼已经成为一件非常痛苦且耗时的事情。相比于反复爬楼，如果能够提供简单易用的基地内快速传送功能，将极大提升游戏体验和建筑玩法的自由度。

**For Pocketpair**

There is a clear pain point in the current gameplay: as player bases continue to expand, buildings become taller and taller, often reaching dozens of floors. Although stairs solve vertical movement, going up and down repeatedly every day is tedious and time-consuming. Compared with constant stair climbing, an easy and practical in-base fast teleport feature would greatly improve both gameplay comfort and building freedom.

**声明**

本人是半吊子程序员，该 MOD 全程由伟大的 GPT 5.6 大人制作，所以 Mod 仅提供非常基础的功能，且代码质量堪忧，因此希望有能力的大佬能够考虑做一个完整的“电梯 MOD”。我相信这将帮助到非常多的玩家。下方是我在 N 网找到的一份参考 MOD，可以提供给有能力的大佬继续研发。

- [Nexus 上的参考 MOD](https://www.nexusmods.com/palworld/mods/3669?tab=description)

**Announce**

Due to my current technical limitations, I am unable to complete this mod on my own for now. I sincerely hope skilled mod developers may consider implementing this feature, as I believe it would help a large number of players.

## 安装方式 | Installation

**该 MOD 支持单机/专用服务器 | This mod supports single-player and dedicated server modes.**

### 本地单机安装 | Installation in client

1. 在 Steam 创意工坊中订阅本 Mod。
1. Subscribe to this mod on the Steam Workshop.
2. 在游戏中，正常启用本 MOD。
2. In the game, enable this mod normally.

### 专用服务器安装 | Installation in DS

1. 在 Steam 创意工坊中订阅本 Mod。
1. Subscribe to this mod on the Steam Workshop.
2. 将 MOD 文件放到专用服务器的 `\PalServer\Pal\Binaries\Win64\ue4ss\Mods\TeleportBook` 目录下。
2. Place the MOD files in the `\PalServer\Pal\Binaries\Win64\ue4ss\Mods\TeleportBook` directory on the dedicated server.
3. 将 MOD 文件夹中的 `dwmapi.dll` 拷贝到 `.\PalServer\Pal\Binaries\Win64` 目录下。
3. Copy `dwmapi.dll` from the MOD folder to `.\PalServer\Pal\Binaries\Win64`.

## 使用方式 | Usage

在游戏中到达希望记录的位置后：
After reaching the location you want to save in-game:

- 按下键盘 **G** 键。
- Press **G** on your keyboard.
- 当前角色坐标将被保存到 `teleports.json` 文件中。
- Your current character coordinates will be saved to `teleports.json`.
- 最多可保存 **9 个传送点**。
- You can save up to **9 teleport points**.
- 可在不同楼层、房间或建筑区域记录多个坐标。
- You can record points across different floors, rooms, or building areas.

通过这种方式，玩家可以快速在基地不同楼层、功能区或建筑之间进行移动，无需再反复攀爬楼梯。
With this method, players can quickly move between different base floors, functional zones, or buildings without repeatedly climbing stairs.