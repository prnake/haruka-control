#!/usr/bin/env bash
#
# haruka-control 安装脚本（两种用法，同一个文件）
#
#   1) 仓库里执行：        ./install.sh
#      把身边的 control / control-agent 装到 ~/.local/bin（开发安装）
#
#   2) 一行命令装最新版：  curl -fsSL <raw 地址>/install.sh | bash
#      脚本旁边没有文件时自动切到下载模式：从 GitHub release 拉最新版。
#      也支持钉住版本：    curl -fsSL ... | bash -s -- v1.2.3
#
#   PREFIX=/usr/local/bin ./install.sh   安装到指定目录（两种模式都支持）
#
# 环境变量（fork / 测试用）：HARUKA_GH_BASE、HARUKA_REPO
#
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local/bin}"
GH_BASE="${HARUKA_GH_BASE:-https://github.com}"
REPO="${HARUKA_REPO:-prnake/haruka-control}"
PIN="${1:-${VERSION:-}}"     # 位置参数或 VERSION 环境变量：钉住某个 tag

info() { printf '· %s\n' "$*"; }
ok()   { printf '✓ %s\n' "$*"; }
bad()  { printf '✗ %s\n' "$*" >&2; }

if [ "$(uname -s)" != "Darwin" ]; then
  bad "只支持 macOS：control 依赖 launchctl 管理 launchd 服务"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  bad "缺少 python3（control agent 的 TUI 需要）"
  info "安装方式：xcode-select --install   或   brew install python3"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  bad "缺少 curl（下载模式必需）"
  exit 1
fi

# curl | bash 时脚本在 /dev/fd/63 这类位置，cd 会失败或找不到兄弟文件 ——
# 这正是判断「本地模式 / 下载模式」的依据。
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

if [ -z "$SRC" ] || [ ! -f "$SRC/control" ] || [ ! -f "$SRC/control-agent" ]; then
  # ---------------- 下载模式（curl | bash）----------------
  info "在线安装：从 ${GH_BASE}/${REPO} 的 release 拉取"
  if [ -n "$PIN" ]; then
    tag="$PIN"
  else
    # 不用 GitHub API（免 token / 免限流）：releases/latest 会 302 到 /tag/vX.Y.Z
    tag="$(curl -fsSL --connect-timeout 5 --max-time 15 -o /dev/null -w '%{url_effective}' \
      "${GH_BASE}/${REPO}/releases/latest" | sed -n 's|.*/tag/\(.*\)$|\1|p')"
    if [ -z "$tag" ]; then
      bad "查不到最新版本（网络不通？或 ${REPO} 还没有发布过 release）"
      exit 1
    fi
  fi
  ok "目标版本：${tag}"

  tmp="$(mktemp -d "${TMPDIR:-/tmp}/haruka-install.XXXXXX")"
  # 下载失败也要把临时目录清掉，别往 /tmp 里漏垃圾
  trap 'rm -rf "$tmp"' EXIT
  for f in control control-agent SHA256SUMS; do
    info "下载 ${f}…"
    if ! curl -fsSL --connect-timeout 5 --max-time 60 -o "${tmp}/${f}" \
        "${GH_BASE}/${REPO}/releases/download/${tag}/${f}"; then
      # SHA256SUMS 是可选资产（老 release 没有），缺了不致命
      if [ "$f" = "SHA256SUMS" ]; then
        : > "${tmp}/SHA256SUMS"
        info "该 release 没带 SHA256SUMS，跳过校验"
        continue
      fi
      bad "下载 ${f} 失败（确认 release ${tag} 里有这个资产）"
      exit 1
    fi
  done
  if command -v shasum >/dev/null 2>&1 && [ -s "${tmp}/SHA256SUMS" ]; then
    (cd "$tmp" && grep -E '  (control|control-agent)$' SHA256SUMS | shasum -a 256 -c -) \
      || { bad "SHA256 校验失败"; exit 1; }
    ok "SHA256 校验通过"
  fi
  SRC="$tmp"
else
  info "本地安装：${SRC}"
fi

# ---------------- 两种模式汇合：装文件 ----------------
mkdir -p "$PREFIX"
for f in control control-agent; do
  install -m 0755 "$SRC/$f" "$PREFIX/$f"
  ok "已安装 $PREFIX/$f"
done

case ":$PATH:" in
  *":$PREFIX:"*)
    ok "$PREFIX 已在 PATH 中，可以直接用了"
    ;;
  *)
    info "$PREFIX 不在 PATH 中。把下面这行加到 ~/.zshrc 或 ~/.bashrc："
    printf '\n    export PATH="%s:$PATH"\n\n' "$PREFIX"
    info "然后执行 source ~/.zshrc 或重开终端"
    ;;
esac

printf '\n'
info "试试看："
printf '    control status          查看飞连 / UURemote 状态\n'
printf '    control agent           打开 harness 占用 TUI\n'
printf '    control agent history   浏览历史 Claude Code 会话\n'
printf '    control version         查看版本（control update 升级）\n'
