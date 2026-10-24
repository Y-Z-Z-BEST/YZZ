#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════
# bin/dsh.sh —— 在本机找到 DeepSeek Harness 的 CLI 并启动
#
# 为什么需要这个包装脚本:
#   DSH 是「本机安装」的软件,安装位置因机器而异。如果清单里直接写死
#   /e/Software/... 这种绝对路径,把这个项目拷到 U 盘插到别的电脑就废了 ——
#   而那正是这个项目的初衷(移动便携)。
#   所以路径不写在清单里,而是由本脚本在运行时按优先级现找。
#
# 用法:
#   bash bin/dsh.sh           启动 DSH 网页端(默认 --profile web)
#   bash bin/dsh.sh --probe   只探测,找到就 exit 0(供 check-agents.sh 调用)
#   bash bin/dsh.sh --print   打印找到的路径
#
# 查找顺序:
#   1. 环境变量 $DSH_BIN(最高优先级,临时覆盖用)
#   2. 本脚本同级的 bin/dsh.path 文件里写的一行路径
#   3. PATH 上的 dsh 命令
#   4. 常见安装位置
#   5. 项目根目录下的便携版 ./dsh/
# ═════════════════════════════════════════════════════════════════════
set -uo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HUB_DIR="$(cd -- "$SELF_DIR/.." && pwd)"
REL='resources/app/node_modules/@deepseek-ai/dsh/lib/bin.js'

_found=''

# 1) 环境变量
if [[ -n "${DSH_BIN:-}" && -f "${DSH_BIN:-}" ]]; then
    _found="$DSH_BIN"
fi

# 2) bin/dsh.path(用户手工写一行,最省事)
if [[ -z "$_found" && -f "$SELF_DIR/dsh.path" ]]; then
    _line="$(head -1 "$SELF_DIR/dsh.path" 2>/dev/null | tr -d '\r')"
    [[ -n "$_line" && -f "$_line" ]] && _found="$_line"
fi

# 3) PATH 上的 dsh
if [[ -z "$_found" ]]; then
    _p="$(command -v dsh 2>/dev/null || true)"
    [[ -n "$_p" ]] && _found="$_p"
fi

# 4) 常见安装位置。
#    不用 find 全盘扫(太慢),而是枚举已知的安装根目录。
#    Windows 上 DSH 的典型落点:
#      %LOCALAPPDATA%\Programs\deepseek-harness\
#      C:\Program Files\deepseek-harness\
#      以及各盘的 \Software\deepseek-harness\(用户习惯)
if [[ -z "$_found" ]]; then
    _roots=()
    [[ -n "${LOCALAPPDATA:-}" ]] && _roots+=("$LOCALAPPDATA/Programs")
    _roots+=("/c/Program Files" "/c/Program Files (x86)")
    for d in c d e f g; do _roots+=("/$d/Software"); done

    for r in "${_roots[@]}"; do
        [[ -d "$r" ]] || continue
        for name in "DSH NEXT" "deepseek-harness" "DSH"; do
            for cand in "$r/$name/$REL" "$r/deepseek-harness/$name/$REL"; do
                [[ -f "$cand" ]] && { _found="$cand"; break 3; }
            done
        done
    done
fi

# 5) 项目内的便携版
if [[ -z "$_found" ]]; then
    for cand in "$HUB_DIR/dsh/App/$REL" "$HUB_DIR/dsh/$REL" "$HUB_DIR/../DSH/App/$REL"; do
        [[ -f "$cand" ]] && { _found="$cand"; break; }
    done
fi

# ── 输出 ────────────────────────────────────────────────────────────
case "${1:-}" in
    --probe|--print)
        if [[ -n "$_found" ]]; then
            printf '%s\n' "$_found"
            exit 0
        fi
        [[ "${1:-}" == '--probe' ]] && exit 1
        printf 'dsh.sh: 找不到 DeepSeek Harness\n' >&2
        printf '  把下面这一行路径写进 %s 即可:\n' "$SELF_DIR/dsh.path" >&2
        printf '    <你的 DSH 安装目录>/%s\n' "$REL" >&2
        printf '  或者用环境变量:export DSH_BIN=<路径>\n' >&2
        exit 1
        ;;
esac

if [[ -z "$_found" ]]; then
    printf '找不到 DeepSeek Harness(DeepSeek Harness 的 CLI 入口)。\n' >&2
    printf '\n' >&2
    printf '请二选一:\n' >&2
    printf '  1) 把路径写进 %s,内容是一行:\n' "$SELF_DIR/dsh.path" >&2
    printf '     <安装目录>/%s\n' "$REL" >&2
    printf '  2) 设置环境变量 DSH_BIN 指向同一个文件\n' >&2
    printf '\n按 Enter 返回菜单...' >&2
    read -r _ || true
    exit 1
fi

# 不写死 profile —— 让清单决定,这里只负责启动
exec node "$_found" "${@:---profile web}"
