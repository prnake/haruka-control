# haruka-control

macOS 上的进程与开机自启管理小工具，两个子命令：

- **`control fl|uu on|off|status`** —— 一键开关「飞连 (CorpLink)」和「UURemote」，连 launchd 服务和开机自启一起处理。
- **`control agent`** —— 一个 TUI，实时查看并清理各个 AI coding harness（Claude Code / Codex / Cursor / ZCode / Zed / Kimi …）的内存与 CPU 占用。

纯 bash + Python 3 标准库，无第三方依赖。

---

## 目录

- [为什么需要它](#为什么需要它)
- [下载 & 安装指南](#下载--安装指南)
- [快速上手](#快速上手)
- [命令详解](#命令详解)
  - [control status](#control-status)
  - [control fl/uu off](#control-fluu-off)
  - [control fl/uu on](#control-fluu-on)
  - [control agent（TUI）](#control-agenttui)
    - [会话是怎么和进程对上的](#会话是怎么和进程对上的)
    - [control agent history（历史会话浏览）](#control-agent-history历史会话浏览)
- [已实现的功能](#已实现的功能)
- [harness 匹配策略](#harness-匹配策略)
- [终端兼容性：界面为什么全是 ASCII](#终端兼容性界面为什么全是-ascii)
- [隐私边界](#隐私边界)
- [安全设计](#安全设计)
- [常见问题](#常见问题)
- [卸载](#卸载)
- [许可](#许可)

---

## 为什么需要它

### 飞连 / UURemote 杀不掉

这两个 App 的**每一个** launchd 服务都是 `KeepAlive=1` + `RunAtLoad=1`：

```
$ pgrep -f CorpLink | xargs kill       # 杀掉
$ pgrep -f CorpLink                    # 毫秒级又被 launchd 拉回来
```

所以「任务管理器里点结束进程」是无效的。正确顺序必须是：

1. `launchctl bootout` —— 先把服务从 launchd 卸载
2. `launchctl disable` —— 再禁止开机自启，否则重启就回来了
3. `kill` —— 最后才杀进程

`control off` 就是按这个顺序做的，三步一次完成。

### harness 内存越堆越多

同时开 Claude Code、Cursor、Codex、Zed……每个都拖着一串 node / helper 进程，
`ps aux | grep` 又长又难读，还容易误伤系统服务（macOS 自己就有
`CursorUIViewService`、`AMPDeviceDiscoveryAgent` 这种名字撞车的）。`control agent`
把它们按 harness 分组，一眼看清谁在吃内存，然后按键清掉。

---

## 下载 & 安装指南

### 环境要求

| 项目 | 要求 |
| --- | --- |
| 系统 | macOS（依赖 `launchctl`、`ps` 的 BSD 行为） |
| Shell | bash 3.2+（macOS 自带即可） |
| Python | python3（`control agent` 的 TUI 需要，只用标准库 `curses`） |
| 权限 | 关飞连/UURemote 时需要 `sudo`（它们的守护进程以 root 运行） |

不需要 pip、不需要 brew、不需要 Node。

### 方式一：一行命令安装最新版（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/prnake/haruka-control/main/install.sh | bash
```

脚本会从 GitHub release 拉最新版本、做 SHA256 校验，然后装到 `~/.local/bin`。
`install.sh` 身边没有 `control` 文件时自动进入这个下载模式，所以同一份脚本既能
`curl | bash` 也能在仓库里直接跑。

钉住某个版本（比如排查回归）：

```bash
curl -fsSL https://raw.githubusercontent.com/prnake/haruka-control/main/install.sh | bash -s -- v1.2.3
```

装到别处：`curl … | PREFIX=/usr/local/bin bash`（或 clone 后 `PREFIX=… ./install.sh`）。

### 方式二：clone 后安装（开发 / 离线）

```bash
git clone https://github.com/prnake/haruka-control.git
cd haruka-control
./install.sh
```

clone 装出来的是仓库当前代码（版本号 `0.0.0-dev`），适合改代码验证；
日常使用建议用方式一 —— release 里的 `control` 带真实版本号，`control update`
和启动检测都依赖它。

### 方式三：手动下载 release 文件

```bash
mkdir -p ~/.local/bin && cd ~/.local/bin

base=https://github.com/prnake/haruka-control/releases/latest/download
curl -fsSLO "$base/control"
curl -fsSLO "$base/control-agent"
curl -fsSLO "$base/SHA256SUMS" && shasum -a 256 -c --ignore-missing SHA256SUMS

chmod +x control control-agent
```

> 注意：`control-agent` 必须和 `control` 放在**同一个目录**，
> 因为 `control agent` 是在自己所在目录里找它的（`control` 里有路径检查，找不到会明确报错）。

### 升级：control update 与启动检测

```bash
control update          # 检查并安装最新 release（--force 忽略比较强制重装）
control version         # 查看当前版本
```

- `control update` 会把新版的 `control` / `control-agent` 下到临时目录，过
  SHA256SUMS 校验，再原子替换（先写 `.new` 再 `mv`，不会覆盖到正在运行的半截脚本）。
  装到哪由「正在运行的 control 在哪」决定，`PREFIX` 装到别处的用户一样能用。
- 每次交互式启动会顺带检查新版：**每 24 小时最多联网一次**（上次失败则 1 小时后重试），
  结果缓存在 `~/.cache/haruka-control/update-state`；已知有新版时每次启动都提示一行，
  但不再联网。管道 / 脚本里（非 tty）不检查，不影响速度。
- 设 `HARUKA_NO_UPDATE_CHECK=1` 彻底关闭启动检测。
- 在仓库检出里跑 `./control update` 会被拒绝（防止覆盖源码），开发升级用 `git pull && ./install.sh`。

### 把 ~/.local/bin 加进 PATH

macOS 默认的 PATH 里**没有** `~/.local/bin`，不加的话会提示 `command not found`。

先确认：

```bash
echo $PATH | tr ':' '\n' | grep -q "$HOME/.local/bin" && echo "已有" || echo "需要添加"
```

需要的话，按你的 shell 追加一行：

```bash
# zsh（macOS 默认）
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc

# bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

### 验证安装

```bash
control --help          # 应打印用法
control version         # 应打印版本（curl 安装的应不是 0.0.0-dev）
control status          # 应打印飞连 / UURemote 状态
control agent --list    # 应列出 14 个 harness 及其匹配规则
```

---

## 快速上手

```bash
control status              # 先看看现在什么情况

sudo control off            # 飞连 + UURemote 全关（含禁止开机自启）

control fl status           # 只看飞连
sudo control fl off         # 只关飞连
sudo control uu off         # 只关 UURemote

sudo control fl off --no-persist   # 临时关一下，重启后自动恢复

control on                  # 全部恢复

control agent               # 打开 harness 占用 TUI
```

---

## 命令详解

### control status

```bash
control status        # = control all status
control fl status
control uu status
```

输出三部分：**进程**（按可执行文件聚合的数量 / 内存 / 属主）、**system 域服务**、
**gui 域服务**。服务状态有四种：

| 显示 | 含义 |
| --- | --- |
| `运行中` | 已加载且正在跑 |
| `已停用 (重启后会恢复)` | 已 bootout，但没 disable，重启会回来 |
| `已禁用 (重启也不会恢复)` | 已 disable |
| `? 未查询（需要管理员）` | 查 system 域需要 sudo |

另外会自动检查 `launchctl list` 里有没有**清单外的** corplink / uuremote 服务
（App 升级后可能新增），有就提示出来，方便补进脚本。

> `sudo control fl status` 能看到完整的 system 域状态。

### control fl/uu off

```bash
sudo control off                # = control all off
sudo control fl off
sudo control uu off
```

执行顺序：

1. `launchctl bootout` —— 卸载 daemon（system 域）、agent（gui 域）、用户级 plist、LaunchServices 注册项
2. `launchctl disable` —— **默认执行**，禁止开机自启
3. `SIGTERM` → 等 1 秒 → 还有残留就 `SIGKILL`
4. 复查，把还活着的进程列出来（可能是 SIP 保护的组件）

选项：

| 选项 | 说明 |
| --- | --- |
| `--no-persist` | **不**禁止开机自启，只关这一次，重启后自动恢复 |
| `--soft` | 只杀进程，完全不动 launchd 服务（仅供调试：KeepAlive 会立刻拉回来） |
| `-y`, `--yes` | 跳过确认（非交互环境必须加，否则报错退出） |
| `-n`, `--dry-run` | 只打印将要执行的操作，不做任何修改、也不申请 sudo |

> 关飞连会**立即断开公司内网 / VPN**。如果你正通过 SSH 或远程桌面连到本机，会话会中断；
> 设备受企业管控时还可能触发合规告警。脚本在动手前会把这个提示打出来。

### control fl/uu on

```bash
sudo control on
sudo control fl on
sudo control uu on
```

`launchctl enable` → `launchctl bootstrap` 重新加载服务 → `open -a` 拉起 App。
plist 文件不存在的服务会跳过并说明原因。

### control agent（TUI）

```bash
control agent                 # 打开 TUI
control agent --once          # 打印一次表格后退出（非交互，可管道）
control agent --json          # 输出 JSON
control agent --list          # 列出识别到的 harness 及匹配规则
control agent history         # 浏览 / 搜索所有历史的 Claude Code 会话，回车恢复
control agent --interval 5    # 覆写刷新间隔（秒）
```

当 stdout 不是终端时（比如 `| head`），会自动退化成 `--once` 模式，不会卡住。

**界面**

```
内存 16.00 GB | 已用 12.29 GB | 压缩 6.92 GB | 空闲 65.28 MB
  HARNESS          进程       内存     CPU   状态
--------------------------------------------------------------
  Claude Code         4    1.07 GB   33.1%   运行中（1 个受保护）
  CodexBar            1   26.80 MB    0.0%   运行中
  Kimi                1    9.97 MB    0.0%   运行中
  Codex               -          -       -   未运行
```

TUI 里每个 harness 还带一条内存占比条，按 `Enter` 进入详情：

```
  > Claude Code 的进程（4）
      PID       内存     CPU  运行时长   保护   工作目录
  -----------------------------------------------------------------
     7026  397.06 MB   11.5%  07:45:47          /Users/pka/Documents
  ▸ 16929  329.58 MB    3.9%  07:28:11          /Users/pka/Downloads/env-management
    18465  318.75 MB    3.6%  07:24:05          /Users/pka/Downloads/new-api
     8124  121.97 MB    0.6%  07:45:16          /Users/pka/Downloads/new-api

  --- 会话 a1b2c3d4 (确认)   模型 claude-sonnet-5   消息 480 ---
  输入 524,866   输出 571,228   缓存读 50,429,568   缓存写 0
  合计 51,525,662 tokens     目录 /Users/pka/Documents
  标题 重构配置解析
  最近提问
    10:41  给 parse_config 加上默认值
    11:02  这个函数为什么空输入会崩
    11:15  把 README 的安装步骤改成中文
```

**工作目录**这一列是回答「这个进程在哪个项目里干活」的关键 —— 同名的 `claude`
进程可能有四五个，只有目录能区分它们。它是通过 `lsof -a -p <pid> -d cwd` 查的，
单次约 30 ms，所以只在进入详情视图时查一次并缓存，不会每帧都跑。

**会话面板**显示选中进程正在跑的那个会话：token 用量（输入 / 输出 / 缓存读 / 缓存写）、
会话标题、以及最近 3 条提问。只在选中行变化时算一次并缓存（单次 15–30 ms），
所以上下移动选择时不会卡。按 `t` 可以收起它，把纵向空间还给进程列表。

> 只显示 token 数，**不估算金额** —— 各家模型计价不一且随时会变，
> 猜一个单价出来比不显示更容易误导。

### 会话是怎么和进程对上的

Claude Code 把每个会话的完整记录存在 `~/.claude/projects/<项目>/<sessionId>.jsonl`，
每条 assistant 记录里带 `message.usage`；所有提问另有全局流水
`~/.claude/history.jsonl`（`project` / `sessionId` / `timestamp` / `display`）。

一个 jsonl 文件里没有 pid，`lsof` 又看不到打开的会话文件，所以对应关系靠**时间**：

1. 由 `ps` 的 `etime`（已运行时长）反推进程的启动时刻；
2. 在**同目录**的会话里找「首次活动时刻」与它最接近的那个。

实测四个在跑的 claude 进程，偏差分别是 +14s / +4s / +73s / +23s。

**为什么不能用「该目录下最近活动的会话」**：实测同目录下同时跑着两个 claude，
那个朴素启发式会把它们映射到**同一个**会话，token 数直接翻倍。启动时间才是每个
进程独有的。

面板上的标记有诚实性含义：

| 标记 | 含义 |
| --- | --- |
| `确认` | 偏差在容差内，且没有第二个同样接近的候选 |
| `推测` | 偏差超容差，或存在同样接近的第二候选 —— 这时会**显示偏差秒数**让人自己判断 |

`claude --resume` / `--continue` 复用的旧会话，首次活动远早于进程启动，必然落到
`推测`。另外只有斜杠命令（`/resume`、`/model`）的会话会被跳过：这类命令不产生
assistant 轮次，于是落盘文件根本不存在，但它们在 `history.jsonl` 里是一条**独立的
新会话 id** —— 不排掉的话，`--resume` 启动的进程会认领这个什么都没有的空壳。

### 键位

| 键 | 作用 |
| --- | --- |
| 方向键 ↑ ↓ | 上下移动 |
| → / `Enter` / `l` | 进入该 harness 的进程详情（含工作目录与会话面板） |
| ← / `Esc` | 返回上级；在主列表按则退出 |
| `k` | **杀掉**选中的目标：harness 行 = 整组，详情里的进程行 = 单个 |
| `t` | 切换详情页的会话面板（token 用量 / 标题 / 最近提问） |
| `s` | 切换排序：内存 → CPU → 名称 |
| `H` | 打开历史会话浏览（见下节，`Esc` 原路返回） |
| `r` | 立即刷新 |
| `q` | 退出 |

> 移动**只支持方向键**，没有 `j`/`k` —— 因为 `k` 已经分配给「杀」了，两者兼用会误操作。

> 列表是按内存实时排序的，而内存每帧都在变。选中项因此**锚定在具体的进程/harness 上，
> 而不是行号上** —— 排序变化时选择会跟着目标走，不会滑到相邻的另一行。
> 这一点对 `k` 尤其重要：否则「选中的」和「杀掉的」可能不是同一个。

### control agent history（历史会话浏览）

`--once` / 详情面板看的是**正在跑**的进程，`control agent history` 看的是磁盘上的
**全部**历史会话 —— 不管现在跑没跑，装过 Claude Code 以来的每一次对话都在。
数据来自 `~/.claude/projects/*/*.jsonl`（事实来源，保证「一个字没敲就退出」的会话
也不漏）+ `~/.claude/history.jsonl`（补精确项目路径、提问列表）。

```
 claude 会话历史（11/87）                                                          时间新→旧
------------------------------------------------------------------------------------------------------------
  时间        标题 / 最近提问                                           项目                       大小
  ---------------------------------------------------------------------------------------------------------
  09-22 12:19 Claude Code 历史对话查找与打开                            ~/Library/Mobile Docum   1.05 MB
  09-22 11:35 control-agent-token-usage                                 ~/Documents              5.07 MB
  09-16 16:27 commit & push 对应修改                                    ~/Downloads/haruka-pa    3.20 MB
  ...
  --- 2df1a766   /Users/pka/Library/Mobile Documents/.../haruka-control ---
  模型 glm-5.3-highspeed   消息 82   输入 208,760   输出 122,868
  缓存读 7,644,480   缓存写 0   合计 7,976,108 tokens
  最近提问
    control agent history ；需要能够查找所有历史的claude code的对话，并且用户按回车后可以自动打开
```

**打开就是秒的**：首次进入只做目录扫描（87 个会话 <10ms），标题和 token 统计按
可见行懒加载，每帧最多解析 2 个文件（单个 15–100ms），翻页时再补新露出来的行。

- **Enter 恢复会话**：先弹确认框定「用哪个模型」和「授权模式」，回车才真的进去。

  ```
   +------------------------------------------------------------------------------+
   | 恢复会话 8b4d06a1                                         2026-09-22 14:16   |
   | ~/Library/Mobile Documents/com~apple~CloudDocs/.../haruka-control            |
   | ---------------------------------------------------------------------------- |
   |   模型    < opus >                        glm-5.3-highspeed                  |
   |   模式    < auto >                        低风险操作自动放行                 |
   | ---------------------------------------------------------------------------- |
   | 将执行  claude --resume 8b4d06a1-62ff-4659-81d3-26d8bd222d04                 |
   |         --model opus --permission-mode auto                                  |
   | 方向键 上下换行 左右改值   Enter 恢复会话   Esc 取消                         |
   +------------------------------------------------------------------------------+
  ```

  模型候选**不写死**，而是从 `~/.claude/settings.json` 的 `env` 读 —— 也就是
  `/model` 选择器里那几条「Custom Opus/Sonnet/Haiku/Fable model」：用户把
  `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU,FABLE}_MODEL` 这些别名槽位映射到自己的
  模型上（这台机器上是 glm-5.3-highspeed / deepseek-v4-flash / claude-fable-5-1）。
  写死 id 在这里没有意义：同一份代码在不同人机器上映射到的模型完全不同。

  传的是**别名**（`opus` / `sonnet` / `haiku` / `fable`），由 claude 自己按 env
  解析 —— 和 `/model` 选择器走同一条路；把 `glm-5.3-highspeed[1M]` 这种带 `[1M]`
  后缀的串直接塞给 `--model` 语义不明。别名看不出实际用哪个模型，所以右边的说明
  写它解析成什么。两个槽位指向同一个模型是常态（如 opus 和 sonnet 都指向
  glm-5.3-highspeed），这也是别名必须当主标签、模型名只能当说明的原因。
  `settings.json` 里一个槽位都没配时退回裸别名。

  第一项「沿用会话原模型」= 不传 `--model`，右边标出该会话当前用的模型名。
  授权模式三选一：`默认`（不传旗标，用 claude 自己的默认）/ `auto` / `允许一切`
  （`--permission-mode bypassPermissions`），首次进入预选 `auto`。

  选择记在 `~/.cache/haruka-control/resume-prefs`，下次打开按上次的预选（改主意
  照样能改；偏好里的模型已从配置里删掉时会自动退回「沿用」）；`Esc` 取消不写。
  确认后的 `exec` 与命令拼接见下条。
- **恢复就是一个 `exec`**：TUI 把自己换成 `claude --resume <sessionId>` 进程
  （带上确认框选出来的旗标），退出对话后看到的就是原来的 shell —— 和手敲命令的
  体验一致，不会落回一个空壳。恢复前会先 `cd` 到该会话的项目目录（取自
  `history.jsonl` 的原始路径；项目目录已被删时读会话文件头部的 `cwd` 记录兜底）。
- **`/` 搜索**：关键词命中 标题 / 该会话的**全部提问** / 项目路径 / 会话 id，
  多个词按空格分隔、AND 语义。中文输入可用 —— curses 的 `getch` 一次只吐一个
  字节，中文要凑满 3 个 UTF-8 字节才是一个字，这里做了字节缓冲再解码。
- `s` 切换排序（时间新→旧 / 时间旧→新 / 大小），`t` 收起详情面板，`r` 重新扫描，
  `g` / `G` 跳首尾，PgUp / PgDn 翻页；agent TUI 里按 `H` 也能进这里，`Esc` 原路返回。
- 管道里自动退化成一次性表格（最近 30 条），不挂终端。

> 为什么不把 projects/ 的目录名解码成项目路径：Claude Code 的目录名是 cwd 里的
> `/` 换成 `-`，这个变换**不可逆**（`com~apple~CloudDocs` 编码后是
> `com-apple-CloudDocs`，和本来就带 `-` 的路径撞车）。`history.jsonl` 的 `project`
> 字段存的是原始路径，所以一律优先从那里取，目录名解码只做兜底。

---

## 已实现的功能

### `control`（服务与进程管理）

- [x] `status` / `on` / `off` 三个动作，支持 `fl`、`uu`、`all` 三种目标
- [x] 按 `bootout → disable → kill` 的正确顺序关闭，不会被 KeepAlive 拉回来
- [x] **默认禁止开机自启**，重启后不会自动恢复（`--no-persist` 可关掉这个行为）
- [x] `SIGTERM` 优雅退出，1 秒后仍有残留则升级为 `SIGKILL`
- [x] 关闭后复查，把杀不掉的进程（SIP 保护等）明确列出来
- [x] `--dry-run` 空跑预览，且不会触发 sudo 提示
- [x] 非交互环境（管道、脚本）强制要求 `-y`，避免误触发
- [x] 清单外服务检测：`launchctl list` 里出现新的 corplink/uuremote 服务会告警
- [x] 兼容 `sudo` 调用：用 `SUDO_USER` / `SUDO_UID` 定位真实用户与 gui 域
- [x] 兼容 `launchctl print-disabled` 的两种输出格式（`=> true` 与 `=> disabled|enabled`）
- [x] 颜色输出仅在 tty 下启用，重定向到文件时自动关闭
- [x] 操作前打印风险提示（断内网 / 断远程连接 / 合规告警）
- [x] `--help` 直接由脚本头部的注释块生成，不会和实现脱节
- [x] `control update` 自更新：从 GitHub release 下载 + SHA256 校验 + 原子替换（先写 `.new` 再 `mv`），装到「正在运行的 control」所在目录
- [x] 交互式启动自动检查新版：每 24h 联网一次（失败 1h 后重试），已知新版每次提示但不重复联网；非 tty 不检查；`HARUKA_NO_UPDATE_CHECK=1` 可关
- [x] `curl -fsSL … | bash` 一行安装：install.sh 自动识别本地 / 下载模式，支持钉版本、SHA256 校验
- [x] GitHub Actions：push tag `v*.*.*` 自动打版本号、自检、发布 release（含 SHA256SUMS）；PR / push 有 macOS 语法冒烟

### `control-agent`（harness 占用 TUI）

- [x] 14 个 harness 的识别：Claude Code、Codex、CodexBar、Cursor、Windsurf、ZCode、
      Zed、Warp、opencode、amp、Kimi、Droid (Factory)、Harbor、agent-reach
- [x] 按 harness 分组显示：进程数、合计内存、合计 CPU、运行状态
- [x] 顶部显示整机内存概况（总量 / 已用 / **压缩内存** / 空闲），压缩内存是 16 GB 机器上最关键的
- [x] 文件夹式的两层界面：harness 列表 → 单个进程详情（pid / 内存 / CPU / 运行时长 / 受保护 / **工作目录**）
- [x] 详情页显示每个进程的**工作目录**（`lsof` 按需查询 + 缓存），同名的多个 `claude` 靠它区分
- [x] 详情页显示选中进程的**会话面板**：token 用量（输入/输出/缓存读/缓存写）、会话标题、最近 3 条提问
- [x] `control agent history` / `H` 键：浏览并搜索**所有历史** Claude Code 会话，Enter 在当前终端 `claude --resume` 恢复
- [x] 恢复前弹确认框选**模型 + 授权模式**（默认 / auto / 允许一切），模型候选从 `~/.claude/settings.json` 的别名槽位读（不写死 id），「将执行」行实时显示最终命令
- [x] 确认框记住上次的模型 / 模式（`~/.cache/haruka-control/resume-prefs`），常用组合不必每次重选
- [x] 历史搜索命中 标题/全部提问/项目路径/会话 id，多词 AND，中文可用（curses 字节流缓冲拼 UTF-8）
- [x] 历史列表懒加载：进入只做目录扫描（<10ms），标题/token 按可见行逐帧补齐
- [x] 进程 → 会话的对应靠「`etime` 反推启动时间 vs 会话首次活动时间」，而不是「目录下最近活动的会话」（后者在同目录多会话时会把 token 数翻倍）
- [x] 对应关系区分 `确认` / `推测`，推测时显示偏差秒数；`--resume` 复用的旧会话不会冒充确定结果
- [x] 只有斜杠命令（`/resume`、`/model`）的空壳会话会被跳过，不会被 `--resume` 启动的进程认领
- [x] 会话数据按需解析 + 缓存（单次 15–30 ms），只算当前选中行，上下移动不卡
- [x] `t` 键收起会话面板，把纵向空间还给进程列表
- [x] **不估算费用**：各家计价不一，猜一个单价出来比不显示更容易误导
- [x] 选中项**锚定在进程/harness 上而非行号上**，实时排序变化时不会滑到相邻行（对 `k` 的安全性尤其重要）
- [x] **杀单个**（详情页选中某进程）与**杀整组**（列表页选中某 harness）
- [x] 杀之前弹确认框，显示将影响的进程数
- [x] 三种排序：内存 / CPU / 名称
- [x] 手动刷新（`r`）与定时自动刷新（`--interval`）
- [x] `--once` / `--json` / `--list` 三种非交互输出，`--json` 可直接喂给别的工具
- [x] 非 tty 自动降级为 `--once`，管道里不会挂住
- [x] 处理 `KEY_RESIZE`，终端窗口缩放不会花屏
- [x] 按**显示宽度**而非字符数计算列宽，中文/全角字符不会让表格错位
- [x] 写入前按显示宽度截断，规避 `curses.error`（写到最后一行/最后一列会抛异常）
- [x] **结构性字符全部用 ASCII**，不依赖 `█ ░ ─ ↑ ↓ ·` 这类歧义宽度字符（见下）
- [x] 路径匹配失败时的兜底：识别不到就 `control agent --list` 看规则再补 `HARNESSES`
---

## harness 匹配策略

分类**全部基于完整路径**，不用名字子串匹配 —— 因为 macOS 系统服务里有好几个撞名的：

| 名字 | 系统里真实存在的干扰项 | 处理 |
| --- | --- | --- |
| `cursor` | `CursorUIViewService.xpc` | Cursor 只按路径匹配，关闭裸名匹配 |
| `amp` | `AMPDeviceDiscoveryAgent` | 同上 |
| `droid` | `AirDroid` | 走完整路径 |

三层防御：

1. **硬排除前缀** —— `/System/`、`/usr/libexec/`、`/usr/sbin/`、`/sbin/`、`/usr/lib/`
   下的进程永远不是 harness。
2. **兜底黑名单** —— 万一有系统服务落在非系统路径，`CursorUIViewService`、
   `AMPDeviceDiscoveryAgent`、`AirDroid` 也一律排除。
3. **匹配必须带 `/`** —— `paths` 和 `argv` 里的模式都要求包含 `/`，
   避免 `/Zed.app/` 这类模式退化成裸名匹配。

匹配规则三种，命中任一即算：

- `paths` —— `comm`（可执行文件完整路径）的子串，如 `/.claude/`
- `names` —— basename 的**精确**匹配，如 `kimi-webbridge`
- `argv` —— 完整命令行的子串，如 `/@anthropic-ai/claude`

### 一个踩过的坑：macOS `ps` 会截断 `comm`

如果同一次 `ps` 里既请求 `comm` 又请求 `command`，macOS 会把 `comm` **截断到 16 字符**：

```
ps -Ao pid=,comm=              → /Users/pka/.kimi-webbridge/bin/kimi-webbridge   ✓
ps -Ao pid=,comm=,command=     → /Users/pka/.kimi                                ✗
```

结果是所有路径匹配全部失效（Kimi 明明在跑却显示「未运行」）。
`control-agent` 因此分两次 `ps` 调用，再按 pid 合并。

> 补充：`comm` 有时也会只给一个裸名 —— macOS 拿不到完整可执行路径时会退回
> `p_comm` 那个 16 字节字段，实测四个 `claude` 进程的 `comm` 全都是 `claude`。
> 这时是 `names=("claude",)` 的兜底在起作用。所以详情视图不显示 `comm`，
> 而是显示工作目录。

---

## 终端兼容性：界面为什么全是 ASCII

进度条最初用的是 `█` (U+2588) 和 `░` (U+2591)，分隔线用 `─` (U+2500)。
在有些终端里，进度条整个糊成一片，看起来像乱码。

原因不是编码（`locale` 是 `en_US.UTF-8`），而是 **East Asian Width**：

| 字符 | 码位 | EAW 类别 | 说明 |
| --- | --- | --- | --- |
| `█` | U+2588 | **Ambiguous** | 终端自己决定按 1 列还是 2 列渲染 |
| `─` | U+2500 | **Ambiguous** | 同上 |
| `↑` `↓` `·` `—` | U+2191/2193/00B7/2014 | **Ambiguous** | 同上 |
| 汉字 | — | Wide | 一定是 2 列，安全 |

把「歧义字符按两列渲染」打开时（CJK 字体配置里很常见），每个 `█` 实际占 2 列，
而代码按 1 列算 —— 24 个 `█` 会撑成 48 列，把右边的文字全部盖掉。

所以现在**结构性字符一律 ASCII**（`#` `-` `>` `|`），只有中文是非 ASCII 的，
而中文是 Wide 类别，宽度在任何终端里都没有歧义。进度条的代码里留了注释说明这段历史。

同理，早先版本用 emoji `🔒` 标记受保护进程，也换成了 `[保护]` —— emoji 的宽度不固定，
而且不是所有终端都能渲染。

这条规则作用于**所有写屏字符串**（curses 的 `addstr` 与 `print`），注释和文档字符串
里不受限 —— 那些是给人读的，不参与列宽计算。比如 `fmt_bytes()` 在取不到数值时
返回的是 ASCII 的 `-` 而不是 `—`，因为那个值会进右对齐的标题栏，
而 `dwidth()` 会把 `—` 算作 1 列、把整个右对齐块带偏一个字符。

---

## 隐私边界

会话面板会把你**真实的提问原文**显示在屏幕上 —— 数据来自本机的
`~/.claude/history.jsonl`，只用于渲染当前终端，**不联网、不写日志、不落盘**。

需要留意的是：那个文件里存的是历次提问的完整原文，其中可能包含你当时粘贴过的
密钥、token 或内部地址（`control agent` 无法分辨，只是照原样显示）。所以：

- 在共享屏幕 / 录屏 / 截图时，注意详情页的「最近提问」区域；
- 不需要时按 `t` 收起面板。

本仓库的 README 与示例输出一律使用**合成内容**，不含任何真实提问。

---

## 安全设计

TUI 里按 `k` 有可能杀掉**正在运行这个 TUI 的那个会话** —— 比如你在 Claude Code 里跑
`control agent`，然后顺手把 Claude Code 整组杀掉，TUI 自己也跟着死。

所以 `control-agent` 会：

1. 从自己的 pid 出发，沿 `ppid` 一路向上走到 pid 1，把整条**祖先链**标记为受保护；
2. 受保护的进程在列表里显示为 `运行中（N 个受保护）`；
3. 按 `k` 时自动跳过它们，并在确认框里说明跳过了几个；
4. 如果整组**全部**受保护，直接拒绝执行并提示
   「受保护：这些进程属于当前会话，杀掉会终止你自己」。

实测：4 个 claude 进程中只有当前会话那 1 个（pid 7026）被标记为受保护。

---

## 常见问题

**Q：`control agent` 提示找不到 `control-agent`？**
两者必须在同一目录。`control agent` 是在 `control` 自己的目录里找 `control-agent` 的。

**Q：`off` 之后重启，飞连又自己回来了？**
说明用了 `--no-persist`，或者 App 自己重新注册了服务（企业 MDM 下发的配置有可能这样）。
`control fl status` 看服务是不是「已禁用」；如果 plist 被重新创建，`sudo control fl off` 再跑一次。

**Q：`off` 之后还有进程活着？**
通常是 SIP 保护的组件，或者 App 在这期间被重新启动了。`status` 会把残留的进程列出来。

**Q：某个 harness 一直显示「未运行」，但它明明开着？**
`control agent --list` 看它的匹配规则，对照 `ps -Ao pid=,comm= | grep -i 关键词` 的实际路径，
把新路径补进 `control-agent` 的 `HARNESSES`。

**Q：`status` 里 system 域显示「未查询」？**
查 system 域需要管理员权限，用 `sudo control fl status`。

**Q：会话面板显示「推测」或者「没有找到匹配的会话」？**
按上面「会话是怎么和进程对上的」那节：`推测` 表示靠时间对不准（`--resume` 复用的旧
会话最常见），面板会同时显示偏差秒数供你判断；`没有找到匹配的会话` 表示那个目录在
`~/.claude/history.jsonl` 里没有任何记录 —— 比如刚 `cd` 进一个新目录还没提问过。
两种情况下 token 面板都只是不给，不会瞎编。

**Q：token 数比我在别处看到的小？**
这里只统计**当前这一个会话**，不是这台机器的总量。缓存读（`cache_read`）通常是最大
的一项，因为每轮都会把整个上下文读进来 —— 所以「合计」远大于输入+输出是正常的。

**Q：会不会显示成美元？**
不会，见上面「不估算费用」。

**Q：支持 Linux 吗？**
不支持。依赖 `launchctl` 和 macOS `ps` 的具体行为。

---

## 卸载

```bash
rm -f ~/.local/bin/control ~/.local/bin/control-agent
```

如果关过飞连/UURemote 又不想手动恢复：

```bash
sudo control on
```

（请在删除脚本**之前**执行。）

---

## 许可

MIT
