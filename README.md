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
- [已实现的功能](#已实现的功能)
- [harness 匹配策略](#harness-匹配策略)
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

### 方式一：clone 后一键安装（推荐）

```bash
git clone https://github.com/prnake/haruka-control.git
cd haruka-control
./install.sh
```

`install.sh` 会把两个脚本装到 `~/.local/bin`，并检查 python3 与 PATH。

装到别处：

```bash
PREFIX=/usr/local/bin ./install.sh
```

### 方式二：只下这两个文件

```bash
mkdir -p ~/.local/bin && cd ~/.local/bin

curl -fsSLO https://raw.githubusercontent.com/prnake/haruka-control/main/control
curl -fsSLO https://raw.githubusercontent.com/prnake/haruka-control/main/control-agent

chmod +x control control-agent
```

> 注意：`control-agent` 必须和 `control` 放在**同一个目录**，
> 因为 `control agent` 是在自己所在目录里找它的（`control` 里有路径检查，找不到会明确报错）。

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
control agent --interval 5    # 覆写刷新间隔（秒）
```

当 stdout 不是终端时（比如 `| head`），会自动退化成 `--once` 模式，不会卡住。

**界面**

```
 内存 16.00 GB · 已用 11.79 GB · 压缩 6.06 GB · 空闲 66.03 MB
  HARNESS          进程       内存     CPU   状态
----------------------------------------------------------------
  Claude Code         4    1.17 GB   12.2%   运行中（1 个受保护）
  CodexBar            1   44.05 MB    0.0%   运行中
  Kimi                1   16.47 MB    0.0%   运行中
  Codex               —          —       —   未运行
----------------------------------------------------------------
  合计                6    1.23 GB
```

**键位**

| 键 | 作用 |
| --- | --- |
| `↑` `↓` | 上下移动 |
| `→` / `Enter` / `l` | 进入该 harness 的进程详情 |
| `←` / `Esc` | 返回上级；在主列表按则退出 |
| `k` | **杀掉**选中的目标：harness 行 = 整组，详情里的进程行 = 单个 |
| `s` | 切换排序：内存 → CPU → 名称 |
| `r` | 立即刷新 |
| `q` | 退出 |

> 移动**只支持方向键**，没有 `j`/`k` —— 因为 `k` 已经分配给「杀」了，两者兼用会误操作。

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

### `control-agent`（harness 占用 TUI）

- [x] 14 个 harness 的识别：Claude Code、Codex、CodexBar、Cursor、Windsurf、ZCode、
      Zed、Warp、opencode、amp、Kimi、Droid (Factory)、Harbor、agent-reach
- [x] 按 harness 分组显示：进程数、合计内存、合计 CPU、运行状态
- [x] 顶部显示整机内存概况（总量 / 已用 / **压缩内存** / 空闲），压缩内存是 16 GB 机器上最关键的
- [x] 文件夹式的两层界面：harness 列表 → 单个进程详情（pid / ppid / 内存 / CPU / 运行时长 / 完整路径）
- [x] **杀单个**（详情页选中某进程）与**杀整组**（列表页选中某 harness）
- [x] 杀之前弹确认框，显示将影响的进程数
- [x] 三种排序：内存 / CPU / 名称
- [x] 手动刷新（`r`）与定时自动刷新（`--interval`）
- [x] `--once` / `--json` / `--list` 三种非交互输出，`--json` 可直接喂给别的工具
- [x] 非 tty 自动降级为 `--once`，管道里不会挂住
- [x] 处理 `KEY_RESIZE`，终端窗口缩放不会花屏
- [x] 按**显示宽度**而非字符数计算列宽，中文/全角字符不会让表格错位
- [x] 写入前按显示宽度截断，规避 `curses.error`（写到最后一行/最后一列会抛异常）
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
