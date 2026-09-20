#!/usr/bin/env bash
#
# haruka-control 安装脚本
#
#   ./install.sh              安装到 ~/.local/bin
#   PREFIX=/usr/local/bin ./install.sh   安装到指定目录
#
set -euo pipefail

PREFIX="${PREFIX:-$HOME/.local/bin}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

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

for f in control control-agent; do
  if [ ! -f "$SRC/$f" ]; then
    bad "缺少文件：$SRC/$f"
    exit 1
  fi
done

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
