#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════
# selftest.sh —— TUI 版面回归测试(Git Bash 里直接跑,不需要 PTY / Python)
#
# 为什么需要:
#   TUI 的每一列都是手算的,一旦某处宽度算错,表现是右边框碎裂、状态词
#   折行到下一行行首 —— 肉眼很难定位到底哪一行错了。这里把项目自己的
#   硬指标写成断言,改完脚本跑一遍就知道有没有退化:
#
#       每一行的显示宽度 == CW + LEFT_PAD
#
#   CW / LEFT_PAD 是按 compute_layout 的规则**复算**的,不是写死的数字;
#   改了规则记得同步改 expected_cw()。
#
# 覆盖三个正交维度:
#   1. 宽度引擎 —— _dw(纯 bash)与 wc -L 在整组字符串上逐条一致
#   2. 几何     —— 10 种终端尺寸下逐行宽度、边框完整、行数不溢出
#   3. locale   —— LC_ALL=C(模拟最坏环境)时降级路径仍然算得对
#
# 用法:
#   bash selftest.sh            全部尺寸
#   bash selftest.sh 120 30     只测一个尺寸
#
# 退出码:0 全过;1 有断言失败。
# ═════════════════════════════════════════════════════════════════════
set -uo pipefail

# 自检自己也必须跑在 UTF-8 locale 下:它拿 wc -L 当宽度基准,
# 而 wc -L 在没有 UTF-8 locale 时同样会按字节算(和 TUI 踩的是同一个坑)。
_probe='中'
if [[ "${#_probe}" -ne 1 ]]; then
    for _lc in C.UTF-8 C.utf8 en_US.UTF-8; do
        if ( export LC_ALL="$_lc"; [[ "${#_probe}" -eq 1 ]] ) 2>/dev/null; then
            export LC_ALL="$_lc"; break
        fi
    done
fi
unset _probe _lc 2>/dev/null || true

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TUI="$HERE/agentbox-tui.sh"
BASH_BIN="${BASH:-bash}"

PASS=0; FAIL=0
ok()  { PASS=$(( PASS + 1 )); }
bad() { FAIL=$(( FAIL + 1 )); printf '  \033[38;5;203m✗ %s\033[0m\n' "$1"; }
dim() { printf '  \033[38;5;242m%s\033[0m\n' "$1"; }

# ── 期望版面(必须与 compute_layout 保持一致)─────────────────────────
expected_cw() {
    local cols="$1" cw
    if (( cols < 47 )); then cw=$(( cols - 1 )); else cw=$(( cols - 8 )); fi
    (( cw > 100 )) && cw=100
    (( cw > cols - 1 )) && cw=$(( cols - 1 ))
    (( cw < 24 )) && cw=24
    printf '%s' "$cw"
}

# ── 1) 宽度引擎:_dw 必须等于 wc -L ───────────────────────────────────
# 第 16 条坑(没有 UTF-8 locale 时 ${#s} 数字节)就是在这里被抓住的,
# 所以这一项失败优先于任何几何断言。
CORPUS=(
    'hello'
    '开源'
    '开源 · 可自配模型'
    '█   █ █████ █████'
    '↑↓ 选择   Enter 进入'
    '✓ 就绪'
    '✗ 未安装'
    '● 已安装'
    '—'
    '❯ ✓ OpenCode'
    'DeepSeek Harness 网页端'
    '通义千问 · 国产'
    '╭── │ ├─┤ ╰──╯'
    'YZZ · your zero-config zone'
)

check_width_engine() {
    local label="$1"
    printf '── 宽度引擎(%s)──\n' "$label"

    # wc -L 自己先自检:块字符 █ 应算 1 列,量 '█   █' 得 5
    local probe
    probe=$(printf '█   █\n' | wc -L)
    if [[ "$probe" != "5" ]]; then
        bad "wc -L 不可信:量 '█   █' 得 [$probe],应为 5 —— 后续比较无意义"
        return 1
    fi
    ok

    local out
    out=$(printf '%s\n' "${CORPUS[@]}" | "$BASH_BIN" "$TUI" --width-probe 2>/dev/null)
    if [[ -z "$out" ]]; then bad "--width-probe 没有输出"; return 1; fi

    local w s want n=0
    while IFS=$'\t' read -r w s; do
        [[ -z "${w:-}" ]] && continue
        n=$(( n + 1 ))
        want=$(printf '%s\n' "$s" | wc -L)
        if [[ "$w" == "$want" ]]; then ok; else bad "_dw('$s')=$w,但 wc -L=$want"; fi
    done <<< "$out"
    dim "比对 $n 条字符串"
    return 0
}

# ── 1b) 降级路径:拿不到 UTF-8 locale 时不许崩 ────────────────────────
# 宽度在这种环境下本来就无法精确(纯 bash 只能数字节),这里只要求:
# 进程正常退出、打出提示、界面结构还在 —— 宁可近似也不能白屏。
check_degraded() {
    printf '── 降级路径(LC_ALL=C)──\n'
    local out err rc
    err=$(cd "$HERE" && COLUMNS=120 LINES=30 LC_ALL=C "$BASH_BIN" "$TUI" --dump 2>&1 >/dev/null)
    out=$(cd "$HERE" && COLUMNS=120 LINES=30 LC_ALL=C "$BASH_BIN" "$TUI" --dump 2>/dev/null)
    rc=$?
    (( rc == 0 )) && ok || bad "LC_ALL=C 下 --dump 退出码 $rc"
    [[ -n "$out" ]] && ok || bad "LC_ALL=C 下没有输出"
    [[ "$out" == *╭*╮* ]] && ok || bad "LC_ALL=C 下顶边框缺失"
    [[ "$out" == *╰*╯* ]] && ok || bad "LC_ALL=C 下底边框缺失"
    if [[ "$err" == *'no UTF-8 locale'* || -z "$err" ]]; then
        ok   # 要么确实走了降级并提示,要么本机本来就有 UTF-8 locale(没触发)
    else
        bad "LC_ALL=C 下出现意外 stderr:$err"
    fi
}

# ── 2) 单个尺寸:逐行宽度 + 边框完整 + 行数 ─────────────────────────
check_size() {
    local cols="$1" rows="$2"
    local cw pad expect
    cw=$(expected_cw "$cols")
    pad=$(( (cols - cw) / 2 )); (( pad < 0 )) && pad=0
    expect=$(( cw + pad ))
    printf '── %dx%d  CW=%d PAD=%d ⇒ 每行 %d 列 ──\n' "$cols" "$rows" "$cw" "$pad" "$expect"

    local out
    out=$(cd "$HERE" && COLUMNS="$cols" LINES="$rows" "$BASH_BIN" "$TUI" --dump 2>&1)
    if [[ -z "$out" ]]; then bad "--dump 无输出"; return; fi

    # --dump 必须是纯文本,否则逐格比对不可信
    if printf '%s' "$out" | LC_ALL=C grep -q $'\033'; then
        bad "--dump 输出含 ANSI 转义序列"
    else ok; fi

    local i=0 line w first='' last='' n_lines=0
    while IFS= read -r line; do
        i=$(( i + 1 ))
        [[ -z "${line// /}" ]] && continue
        n_lines=$(( n_lines + 1 ))
        [[ -z "$first" ]] && first="$line"
        last="$line"

        w=$(printf '%s\n' "$line" | wc -L)
        if (( w == expect )); then ok; else bad "第 $i 行宽 $w ≠ $expect"; fi

        # 每行末尾都必须是边框字符(右边框不能被子串顶飞)
        case "$line" in
            *│|*╮|*╯|*┤) ok ;;
            *) bad "第 $i 行末尾不是边框:…${line: -8}" ;;
        esac
    done <<< "$out"

    (( n_lines > rows )) && bad "输出 $n_lines 行 > 终端 $rows 行(会触发滚动吃掉顶边框)"
    case "$first" in *╭*╮) ok ;; *) bad "顶边框不完整:$first" ;; esac
    case "$last"  in *╰*╯) ok ;; *) bad "底边框不完整:$last"  ;; esac
}

# ── main ────────────────────────────────────────────────────────────
[[ -r "$TUI" ]] || { printf 'selftest: 找不到 %s\n' "$TUI" >&2; exit 1; }

printf '══════ YZZ TUI 版面自检 ══════\n'
check_width_engine "自动补 UTF-8 locale" || true
check_degraded

if (( $# == 2 )); then
    check_size "$1" "$2"
else
    # 超宽 / 常规 / 卡在 100 列上限 / 窄屏 / 极窄
    for pair in 160x40 120x30 100x30 96x30 80x24 60x20 46x20 40x15 30x12 24x10; do
        check_size "${pair%x*}" "${pair#*x}"
    done
fi

printf '\n══════ 结果:%d 通过,%d 失败 ══════\n' "$PASS" "$FAIL"
if (( FAIL == 0 )); then
    printf '✅ 版面硬指标全部满足:每行宽 = CW + LEFT_PAD、边框完整、未超终端高度。\n'
else
    exit 1
fi
