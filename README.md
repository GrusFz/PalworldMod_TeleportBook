# 前言 | Preface

由于个人技术能力有限，暂时无法独立完成这个 Mod 的开发，因此希望有能力的大佬能够考虑实现这个功能。我相信这将帮助到非常多的玩家。
Due to my current technical limitations, I am unable to complete this mod on my own for now. I sincerely hope skilled mod developers may consider implementing this feature, as I believe it would help a large number of players.

目前游戏中存在一个比较明显的痛点：随着玩家基地不断扩建，建筑物越建越高，动辄十几层甚至几十层。虽然楼梯可以解决垂直移动问题，但每天频繁地上下楼已经成为一件非常痛苦且耗时的事情。相比于反复爬楼，如果能够提供简单易用的基地内快速传送功能，将极大提升游戏体验和建筑玩法的自由度。
There is a clear pain point in the current gameplay: as player bases continue to expand, buildings become taller and taller, often reaching dozens of floors. Although stairs solve vertical movement, going up and down repeatedly every day is tedious and time-consuming. Compared with constant stair climbing, an easy and practical in-base fast teleport feature would greatly improve both gameplay comfort and building freedom.

## 安装方式 | Installation

1. 在 Steam 创意工坊中订阅本 Mod。
1. Subscribe to this mod on the Steam Workshop.
2. 启动游戏。
2. Launch the game.
3. 进入游戏后打开 **Options（设置）**。
3. Open **Options** in-game.
4. 进入 **Mod Management（模组管理）**。
4. Go to **Mod Management**.
5. 找到本 Mod 并启用。
5. Find this mod and enable it.
6. 重启游戏（如有需要）。
6. Restart the game if needed.

## 使用说明 | Usage Guide

### 记录传送点 | Save Teleport Points

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

### 服务器命令传送 | Server Command Teleport

- 在聊天框或服务器命令输入中使用 **`!tp 1`**。
- Use **`!tp 1`** in chat or the server command input.
- `1~9` 对应 `teleports.json` 中的第 1~9 个坐标。
- `1~9` maps to the 1st through 9th coordinates in `teleports.json`.
- 本 Mod 只识别 `!tp` 前缀，不使用 `/tp`。
- This mod only recognizes the `!tp` prefix and does not use `/tp`.

通过这种方式，玩家可以快速在基地不同楼层、功能区或建筑之间进行移动，无需再反复攀爬楼梯。
With this method, players can quickly move between different base floors, functional zones, or buildings without repeatedly climbing stairs.