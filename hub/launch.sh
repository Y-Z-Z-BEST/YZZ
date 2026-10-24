#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════
# Pocket Agent Hub × AgentBox —— Git Bash 多 agent 启动器
#
# 整合说明:
#   菜单 UI 来自 AgentBox(YZZ 字标 + 半块 logo + 状态探测),
#   外壳与入口约定来自 PocketAgentHub(start.cmd → launch.sh → 菜单)。
#   底层从 Linux/WSL 换成 Git Bash:不需要 WSL、QEMU、管理员权限。
#
# 分工:
#   launch.sh            ← 本文件。调 TUI 拿选择结果,读清单,分发执行。
#   tui/agentbox-tui.sh  ← 纯 UI。只往 stdout 打一个 id,不做 exec。
#   tui/check-agents.sh  ← 状态探测。输出 8 列 TSV 给 UI 用。
#   tui/agents.tsv       ← 清单。改这里 = 改菜单。
#
# 为什么不在 TUI 里 exec:
#   契约 A —— UI 只输出选择结果,执行由外层负责。这样 UI 可以单独测试
#   (--list / 管道),也不会因为 exec 弄脏终端状态。
#
# 原版 launch.sh 的两个问题,这里修掉了:
#   1. 它对整个 cmd 字符串做 "$cmd",等于把一个命令名当整体去找,
#      "bash -l" 这种带参数的写法会直接找不到命令。
#      现在:普通命令按空格安全切分成数组 exec;以 ! 开头的交给 shell
#      (用于 DSH 这种路径里带空格的场景)。
#   2. 原版没有把 agent 的退出码和终端状态处理好,全屏 agent 退出后
#      光标可能还是隐藏的。现在 trap + 显式 restore。
# ═════════════════════════════════════════════════════════════════════
set -uo pipefail

# ── UTF-8 locale 兜底(最先做,越早越好)──────────────────────────────
# start.cmd 用 `bash launch.sh` 启动我们,这是**非登录** shell,不会读
# /etc/profile.d/lang.sh —— 所以 LANG/LC_ALL 可能是空的。那时 bash 的
# ${#s} 数的是字节而不是字符,子脚本(TUI 的整套列宽计算)全部错位:
# 边框短 8~24 列、右边框碎裂、状态词折行到下一行行首。
# 完整复盘见 hub/README.md 第 16 条。这里补好并导出,让 TUI 与
# check-agents.sh / wipe-creds.sh 都继承到。
_probe='中'
if [[ "${#_probe}" -ne 1 ]]; then
    for _lc in C.UTF-8 C.utf8 en_US.UTF-8 zh_CN.UTF-8; do
        if ( export LC_ALL="$_lc"; [[ "${#_probe}" -eq 1 ]] ) 2>/dev/null; then
            export LC_ALL="$_lc"
            unset LANG LC_CTYPE 2>/dev/null || true
            break
        fi
    done
fi
unset _probe _lc 2>/dev/null || true

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TUI="$HERE/tui/agentbox-tui.sh"
LIST="$HERE/tui/agents.tsv"

# 导出项目根目录 —— 清单里的自定义命令可以用 $AGENTBOX_HUB 引用相对位置,
# 这样整套东西拷到 U 盘、换个盘符(甚至换台电脑)都还能跑。
# 这正是「移动便携」的前提:脚本里不许出现写死的绝对路径。
AGENTBOX_HUB="$HERE"
export AGENTBOX_HUB

C_RST=$'\033[0m'; C_DIM=$'\033[38;5;242m'; C_ACC=$'\033[38;5;226m'
C_BAD=$'\033[38;5;203m'

# ── 终端状态保护 ────────────────────────────────────────────────────
STTY_SAVED=""
restore_term() {
    printf '\033[?25h%s' "$C_RST"
    [[ -n "$STTY_SAVED" ]] && stty "$STTY_SAVED" 2>/dev/null
    return 0
}
trap restore_term EXIT

need_tty() {
    if [[ ! -t 0 || ! -t 1 ]]; then
        printf '%sThis launcher needs an interactive terminal.%s\n' "$C_BAD" "$C_RST" >&2
        printf 'Open Git Bash (ideally inside Windows Terminal) and run:\n' >&2
        printf '  bash "%s"\n' "$HERE/launch.sh" >&2
        exit 1
    fi
}

# ── 从清单里取某个 id 的命令字段 ────────────────────────────────────
cmd_of() {
    local want="$1" id name desc cmd rest
    while IFS=$'\t' read -r id name desc cmd rest; do
        [[ -z "${id// }" ]] && continue
        [[ "${id:0:1}" == '#' ]] && continue
        if [[ "$id" == "$want" ]]; then
            printf '%s' "$cmd"
            return 0
        fi
    done < "$LIST"
    return 1
}

# ── 执行一个 agent ──────────────────────────────────────────────────
run_agent() {
    local id="$1" cmd rc
    cmd="$(cmd_of "$id")" || {
        printf '%sUnknown agent id: %s%s\n' "$C_BAD" "$id" "$C_RST" >&2
        return 1
    }

    if [[ "${cmd:0:1}" == '!' ]]; then
        # 开头是 ! → 交给 shell(路径含空格时必须走这条)
        local shellcmd="${cmd:1}"
        restore_term
        clear
        printf '%sLaunching %s%s in %s%s\n\n' "$C_ACC" "$id" "$C_RST" "$PWD" "$C_RST"
        eval "$shellcmd"
        rc=$?
    else
        # 普通命令:按空格安全切分成数组,不做二次解析
        local -a argv=()
        read -r -a argv <<< "$cmd"
        if [[ ${#argv[@]} -eq 0 ]]; then
            printf '%sEmpty command for agent %s%s\n' "$C_BAD" "$id" "$C_RST" >&2
            return 1
        fi
        if ! command -v "${argv[0]}" >/dev/null 2>&1; then
            printf '%s%s%s was not found on PATH.\n' "$C_BAD" "${argv[0]}" "$C_RST"
            printf 'Install it separately, then verify: %s --version\n' "${argv[0]}"
            printf '\n%sPress Enter to return to the hub...%s' "$C_DIM" "$C_RST"
            read -r _ || true
            return 1
        fi
        restore_term
        clear
        printf '%sLaunching %s%s in %s%s\n\n' "$C_ACC" "$id" "$C_RST" "$PWD" "$C_RST"
        "${argv[@]}"
        rc=$?
    fi

    # agent 可能把终端弄乱(尤其全屏 TUI),回来时重置一次
    restore_term
    printf '\n%s%s exited with code %s.%s\n' "$C_DIM" "$id" "$rc" "$C_RST"
    printf '%sPress Enter to return to the hub...%s' "$C_DIM" "$C_RST"
    read -r _ || true
    return 0
}

# ── 主循环 ──────────────────────────────────────────────────────────
main() {
    need_tty
    [[ -r "$TUI"  ]] || { printf 'Missing %s\n' "$TUI" >&2; exit 1; }
    [[ -r "$LIST" ]] || { printf 'Missing %s\n' "$LIST" >&2; exit 1; }

    STTY_SAVED="$(stty -g 2>/dev/null || true)"

    local choice
    while :; do
        if ! choice="$(bash "$TUI")"; then
            break
        fi
        [[ -z "${choice// }" ]] && break
        run_agent "$choice" || true
    done

    restore_term
    printf '%sGoodbye.%s\n' "$C_DIM" "$C_RST"
}

main "$@"
