#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════
# check-agents.sh —— 检测每个 agent 的就绪状态
#
# 契约:读取 agents.tsv,输出每个 agent 的状态。供 TUI 调用。
#
# 状态含义:
#   ✓  ok        命令存在,且凭据齐备
#   ⚠  needkey   命令存在,但缺凭据
#   ✗  missing   命令不存在
#   ─  skip      无需检查(check_cmd 为空)
#
# 用法:
#   ./check-agents.sh              人类可读表格
#   ./check-agents.sh --tsv        追加状态列后重新输出 TSV(供程序解析)
#   ./check-agents.sh --status ID  只输出某个 agent 的状态码
#
# 依赖:仅 bash 内建 + coreutils。零外部依赖。
# ═════════════════════════════════════════════════════════════════════
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="${AGENTBOX_AGENTS:-$SELF_DIR/agents.tsv}"

# 项目根目录 —— 供清单里的自定义探测命令引用(如 bash "$AGENTBOX_HUB/bin/dsh.sh")
AGENTBOX_HUB="${AGENTBOX_HUB:-$(cd -- "$SELF_DIR/.." && pwd)}"
export AGENTBOX_HUB

[[ -r "$LIST" ]] || { echo "check-agents: 读不到清单 $LIST" >&2; exit 2; }

# ── 空字段归一化 ────────────────────────────────────────────────────
# 清单里用 - 占位表示「空」。原因见 agents.tsv 头部:
# bash 的 read 把 tab 当 IFS 空白,连续 tab 会折叠,真空字段会让后面的
# 字段整体左移。所以清单写 -,这里还原成空串。
unplaceholder() {
    case "$1" in
        '-'|'') printf '' ;;
        *)      printf '%s' "$1" ;;
    esac
}

# ── 判断一个 agent 的状态,结果写进全局 _ST ──────────────────────────
# 参数:check_cmd  key_env  key_file
#
# check_cmd 支持**多个候选命令名**(空格或逗号分隔),任一存在即算装上。
# 为什么需要:同一个 agent 在不同发行渠道下命令名不一样,实测:
#     Oh My Pi  → omp / oh-my-pi
#     CodeBuddy → cbc / codebuddy
#     Kilo Code → kilo / kilocode
#   只认一个名字会漏判。
#
# ⚠ 结果写全局 _ST,不用 echo。
#   调用方原本写成 st="$(status_of ...)",每个 agent 一个子 shell;
#   19 个 agent 实测要多花 0.2 秒以上,而且每多一个 agent 就多一份。
status_of() {
    # unplaceholder 也是 echo 式的小函数,这里内联掉,避免 3 次子 shell
    local check_cmd="$1" key_env="$2" key_file="$3"
    [[ "$check_cmd" == '-' ]] && check_cmd=''
    [[ "$key_env"   == '-' ]] && key_env=''
    [[ "$key_file"  == '-' ]] && key_file=''

    # 无需检查
    [[ -z "$check_cmd" ]] && { _ST=skip; return; }

    # 自定义探测:check_cmd 以 ! 开头 = 整行交给 shell,退出码 0 表示已装上。
    #
    # 用途:有些 agent 装在哪里不固定(比如 DSH 因机器而异),不能靠
    # `command -v 名字` 判断,得跑一段会自己去找的脚本。
    # 例如清单里写:
    #     !bash "$AGENTBOX_HUB/bin/dsh.sh" --probe
    #
    # 自定义探测通过就直接判 ok(就绪),不再走下面的凭据检查 ——
    # 因为探测命令由清单作者负责,它能通过就代表「作者认为可用」,
    # 再拿 env/file 去卡它反而是多余的。
    if [[ "${check_cmd:0:1}" == '!' ]]; then
        if eval "${check_cmd:1}" >/dev/null 2>&1; then _ST=ok
        else _ST=missing; fi
        return
    fi

    # 命令是否存在:遍历所有候选名,任一命中即可
    local found=0 b
    for b in ${check_cmd//,/ }; do
        if command -v "$b" >/dev/null 2>&1; then found=1; break; fi
    done
    (( found )) || { _ST=missing; return; }

    # 凭据:env 或 file 任一满足即可
    local have_env=0 have_file=0
    if [[ -n "$key_env" ]]; then
        local IFS=','
        for v in $key_env; do
            [[ -n "${!v:-}" ]] && have_env=1
        done
    fi
    if [[ -n "$key_file" ]]; then
        local expanded="${key_file/#\~/$HOME}"
        [[ -s "$expanded" ]] && have_file=1
    fi

    # 既没声明 env 也没声明 file → 只知道装上了,不知道登没登录。
    # 这里刻意输出 installed 而不是 ok:把「命令存在」说成「就绪」是撒谎,
    # 大部分 agent 装完还要跑一次登录才会真能用。
    if [[ -z "$key_env" && -z "$key_file" ]]; then
        _ST=installed; return
    fi

    if [[ $have_env -eq 1 || $have_file -eq 1 ]]; then _ST=ok; else _ST=needkey; fi
}

# ── 状态码 → 显示标记 ────────────────────────────────────────────────
mark_of() {
    case "$1" in
        ok)        printf '✓' ;;
        installed) printf '●' ;;
        needkey)   printf '⚠' ;;
        missing)   printf '✗' ;;
        *)         printf '─' ;;
    esac
}
label_of() {
    case "$1" in
        ok)        printf '就绪' ;;
        installed) printf '已安装' ;;
        needkey)   printf '缺 Key' ;;
        missing)   printf '未安装' ;;
        *)         printf '无需检查' ;;
    esac
}

# ── 逐行处理 ─────────────────────────────────────────────────────────
emit_tsv=0 human=1
mode_status=""
case "${1:-}" in
    --tsv)    emit_tsv=1; human=0 ;;
    --status) mode_status="${2:-}"; human=0 ;;
    --help|-h)
        sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
        exit 0 ;;
esac

if [[ $human -eq 1 ]]; then
    printf '%-10s %-14s %-26s %s\n' 'ID' 'NAME' 'DESC' 'STATUS'
    printf '%s\n' '──────────────────────────────────────────────────────────────────────'
fi

while IFS=$'\t' read -r id name desc cmd check_cmd key_env key_file; do
    # 跳过注释与空行
    [[ -z "${id// }" ]] && continue
    [[ "${id:0:1}" == '#' ]] && continue

    status_of "$check_cmd" "$key_env" "$key_file"
    st="$_ST"

    if [[ -n "$mode_status" ]]; then
        [[ "$id" == "$mode_status" ]] && { echo "$st"; exit 0; }
        continue
    fi

    if [[ $emit_tsv -eq 1 ]]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$id" "$name" "$desc" "$cmd" "$check_cmd" "$key_env" "$key_file" "$st"
    else
        printf '%-10s %-14s %-26s %s %s\n' "$id" "$name" "$desc" "$(mark_of "$st")" "$(label_of "$st")"
    fi
done < "$LIST"

exit 0
