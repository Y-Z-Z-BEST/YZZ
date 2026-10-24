#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════
# agentbox-tui.sh —— AgentBox 选单(Operate 模式:可扫描性优先)
#
# 设计原则(参考 impeccable 技能的 Operate 模式):
#   · 访问者要完成任务 → 可扫描性、一致性、原生预期 优先于表现力
#   · 品牌活在精确的细节里,不是靠尺寸堆砌
#   · 内容区(agent 列表)必须比状态区(logo)更醒目
#
# 布局(以内容为轴心,整体居中):
#       [ logo 块图 ]
#       ─────────────  (固定内容宽度,不撑满屏)
#       ▐ A G E N T B O X            环境信息(动态探测)
#       ❯ ● DSH          ...        ✓ 就绪
#         ● Codex        ...        ✓ 就绪
#       ─────────────
#       ↑↓ 选择   Enter 进入   q 退出
#
# 契约实现:A stdout 单行 + 退出码 0 / B 读 agents.tsv / C 用启动器环境变量
#           D 由启动器决定 exec / E 处理 Ctrl+C、小终端、命令缺失
#
# 零依赖:仅 bash 内建 + coreutils
# ═════════════════════════════════════════════════════════════════════
set -uo pipefail

# ── UTF-8 locale 兜底(2026-10-27)────────────────────────────────────
# 为什么必须有这一块:start.cmd 用 `bash.exe launch.sh` 启动 TUI,这是
# **非登录、非交互** shell,不会读 /etc/profile.d/lang.sh —— 所以 LANG /
# LC_ALL 可能是空的。那时 bash 的 ${#s} 数的是**字节**而不是字符:
#     ${#'开源'} = 6  (应为 2)
#     ${#'█   █'} = 9 (应为 5)
# 下面所有纯 bash 宽度计算(_dw)会整体算错,后果是每行短 8~24 列、右边框
# 跑出框外、状态词溢出到下一行行首(屏幕左边缘出现 "Key"/"—"/"装" 残片)。
# 这里自动补一个 UTF-8 locale 并自检;真补不上就降级用 wc -L(慢但正确),
# 绝不让界面悄悄画错。完整复盘见 hub/README.md 第 16 条。
_DW_FAST=1
# ⚠ 必须借一个变量来量:写成 ${#中} 是非法替换(${#...} 里只能放变量名,
#   非 ASCII 标识符会让 bash 直接报 "bad substitution")。
_probe='中'
if [[ "${#_probe}" -ne 1 ]]; then
    _lc_ok=''
    for _lc in C.UTF-8 C.utf8 en_US.UTF-8 zh_CN.UTF-8; do
        # 子 shell 里试,避免 locale 无效时给后续每个子进程刷 setlocale 警告
        if ( export LC_ALL="$_lc"; [[ "${#_probe}" -eq 1 ]] ) 2>/dev/null; then
            _lc_ok="$_lc"; break
        fi
    done
    if [[ -n "$_lc_ok" ]]; then
        export LC_ALL="$_lc_ok"
        unset LANG LC_CTYPE 2>/dev/null || true
    else
        _DW_FAST=0
        printf '[warn] no UTF-8 locale available - falling back to wc -L for widths (slower).\n' >&2
        printf '       install one (e.g. C.utf8) or run: LC_ALL=C.UTF-8 bash launch.sh\n' >&2
    fi
    unset _lc_ok _lc
fi
unset _probe

# =====================================================================
# YZZ 品牌释义 -- 三个单词的首字母
#   改这一行就能换整套品牌文案(顶边框会立刻跟着变)
#   候选见 README「YZZ 三词组合」一节
# =====================================================================
YZZ_EXPAND="${YZZ_EXPAND:-your zero-config zone}"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="${AGENTBOX_AGENTS:-$SELF_DIR/agents.tsv}"
CHECK="$SELF_DIR/check-agents.sh"
[[ -r "$LIST" ]] || LIST="$SELF_DIR/tools/agents.tsv"

# ── 配色 ────────────────────────────────────────────────────────────
# 品牌色:紫 #af5fff → 256 色 135;强调黄 #f2f200 → 226
#
# ⚠ 能力检测必须看 **fd 2(stderr)**,不能看 fd 1(stdout)。
#   启动器用 choice="$(bash agentbox-tui.sh)" 捕获 stdout,所以 TUI 的
#   stdout 是管道、不是终端。若用 [[ -t 1 ]] 判断,会误判成"不支持颜色"
#   而走降级分支 —— 那里 C_SEL 是反显 \e[7m、C_RST 是空串,反显永远
#   不复位,后面每一行都被刷成白底(实测:整片白框)。
#   UI 实际写到 stderr,所以终端能力就该问 fd 2。
if [[ -t 2 ]] && [[ "${TERM:-dumb}" != "dumb" ]] && command -v tput >/dev/null 2>&1 \
   && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
    C_BRAND=$'\e[38;5;135m'  # 品牌紫
    C_ACC=$'\e[38;5;226m'    # 强调黄
    C_FG=$'\e[38;5;253m'     # 主文字
    C_MUT=$'\e[38;5;242m'    # 次要文字
    C_DIM=$'\e[38;5;238m'    # 分隔线
    C_OK=$'\e[38;5;78m'      # 就绪(绿)
    C_INST=$'\e[38;5;110m'   # 已安装但未验证登录(浅蓝)—— 和「就绪」区分开
    C_WARN=$'\e[38;5;220m'   # 缺 Key(黄)
    C_BAD=$'\e[38;5;203m'    # 未安装(红)
    C_SEL=$'\e[48;5;236m\e[38;5;255m'   # 选中:深底亮字(与暗色终端和谐)
    C_HIDE=$'\e[?25l'; C_SHOW=$'\e[?25h'
else
    C_BRAND=''; C_ACC=''; C_FG=''; C_MUT=''; C_DIM=''; C_OK=''; C_INST=''; C_WARN=''; C_BAD=''
    C_SEL=$'\e[7m'; C_HIDE=''; C_SHOW=''
fi
# 复位序列**必须始终有效**:降级分支若把它设成空串,反显会泄漏到全文。
# 这一行放在分支外面,是刻意的安全网,不要挪进去。
C_RST=$'\e[0m'

# ── 选中光标字形 ────────────────────────────────────────────────────
# 用 `›`(U+203A)而不是 `❯`(U+276F):后者在 Windows Terminal 里好看,但裸
# conhost 的默认字体没有这个字形,实测会渲染成空心方块(缺字)。`›` 在两者
# 都有字形(conhost 实测),而且都是 1 列宽 —— 这样不必做终端能力猜测。
# 换字形时记得同步进 _DW_NARROW,否则宽度会多算 1 列。
SEL_CUR='›'

# 终端尺寸:stty(真实 PTY 最准) → tput(认 COLUMNS/LINES) → 环境变量 → 默认值。
# 为什么 stty 放第一:启动器用 `choice="$(bash tui.sh)"` 捕获 stdout 时,
# tput 可能拿不到真实几何;而 COLUMNS 兜底是给 --dump 与 selftest.sh 用的
# (无 PTY 时靠它强制尺寸做回归)。
term_dims() {   # 结果写进全局 _TC / _TR,零 fork
    local pair=''
    [[ -t 0 ]] && pair=$(stty size 2>/dev/null)
    if [[ "$pair" =~ ^([0-9]+)\ ([0-9]+)$ ]]; then
        _TR=${BASH_REMATCH[1]}; _TC=${BASH_REMATCH[2]}
    else
        _TC=$(tput cols 2>/dev/null); _TR=$(tput lines 2>/dev/null)
        [[ "$_TC" =~ ^[0-9]+$ ]] || _TC=${COLUMNS:-80}
        [[ "$_TR" =~ ^[0-9]+$ ]] || _TR=${LINES:-24}
    fi
    [[ "$_TC" =~ ^[0-9]+$ ]] || _TC=80
    [[ "$_TR" =~ ^[0-9]+$ ]] || _TR=24
    (( _TC < 20 )) && _TC=20
    (( _TR < 8 ))  && _TR=8
    return 0
}
_TC=80; _TR=24
term_cols() { term_dims; printf '%s\n' "$_TC"; }
term_rows() { term_dims; printf '%s\n' "$_TR"; }

term_dims; COLS=$_TC; ROWS=$_TR

# ── 运行环境标签(动态探测,不写死某个平台)────────────────────────────
# 移植说明:原版把 "WSL2 · Ubuntu 24.04" 写死在闪屏、把 "Linux · WSL2"
# 写死在菜单头。现在从 uname 推导,同一份脚本在 Git Bash / WSL / macOS
# 都能正确显示。这是把底层 Linux 换成 Git Bash 时唯一必须改的语义。
_detect_env() {
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*) printf 'Git Bash';;
        Linux)
            if grep -qi microsoft /proc/version 2>/dev/null; then
                printf 'WSL2 · Linux'
            else
                printf 'Linux'
            fi;;
        Darwin) printf 'macOS';;
        *)      printf 'Shell';;
    esac
}
ENV_SHORT="$(_detect_env)"
unset -f _detect_env
ENV_LONG="$ENV_SHORT"
case "$ENV_SHORT" in
    'Git Bash') ENV_LONG="$ENV_SHORT · Windows";;
esac

# ── 分隔线(预生成,避开 printf %.0s 的 % 字面量陷阱)────────────────
HLINE=''
_i=0; while (( _i < 300 )); do HLINE+='─'; (( _i++ )); done; unset _i
rule() { local n="${1:-$COLS}"; (( n > 300 )) && n=300; (( n < 1 )) && n=1; printf '%s\n' "${HLINE:0:n}"; }

cleanup() { printf '%s' "$C_SHOW$C_RST"; [[ -n "${STTY_SAVED:-}" ]] && stty "$STTY_SAVED" 2>/dev/null; }
# ⚠ 清理钩子只在「真要接管终端」的路径上装(见文件末尾的入口段)。
#   装在这里会让 --list / --width-probe / --dump 的输出末尾多一个 \033[0m,
#   被管道或测试读到就污染最后一行(实测 --width-probe 的最后一条因此解析失败)。

# ── 显示宽度(中文占 2 列,${#} 只数字符)────────────────────────────
# 为什么必须有这组函数:
#   · ${#s} 在中文字符串上返回字符数,但终端里一个汉字占 2 列。
#     直接拿 ${#s} 做居中/右对齐,中文行会整体偏。
#   · printf '%-26s' 的宽度修饰符也按**字符数**补空格,不是显示列,
#     所以中文列会撑到 52 列,把后面的状态文字顶飞。
#   · wc -L 算的是显示宽度(GNU coreutils),中文 2 列、ASCII 1 列、
#     块字符 1 列,实测正确。用它做唯一真源。
#
# 性能:每帧每行调用一次 wc 会有几十毫秒开销,所以把不变的字符串
# (名字、描述、状态词)在 load_agents 时预先算好存进数组,绘制时零调用。
#
# 用 herestring 而不是 `printf '%s' "$s" | wc -L`:后者是一个管道,
# 要额外 fork 一个 printf 子进程。实测本机 `printf|wc` 约 47 ms,
# herestring 版约 34 ms —— 但仍然是每个字符串一次外部进程。
#
# 所以**能不用就不用**:启动路径上量 width 的地方改用下面的 _dw()
# (纯 bash,零 fork),只有字标这种一次性、字符串极少的地方才用 disp_w。
disp_w() { local s="$1"; wc -L <<< "$s"; }

# 纯 bash 显示宽度,结果写进全局 _W。零 fork。
#
# 原理:宽字符(中日韩等)在 UTF-8 里是多字节,而 ASCII 是单字节。
#   宽度 ≈ 字符数 + 非 ASCII 字符数     (ASCII=1 列,宽字符=2 列)
#   `${s//[ -~]/}` 把 ASCII 可打印字符全部删掉,剩下的就是非 ASCII。
#
# ⚠ 这个估算对「非 ASCII 但只占 1 列」的字符会多算 1 列,必须扣回来。
#   实测踩到的就是 ·(U+00B7):
#     '开源 · 可自配模型'  wc -L=17  估算=18   ← 差 1,正是那个 ·
#   终端里默认按窄字符处理的还有整套制表和方块字符(█▀▄▐─│├┤╭╮╰╯…),
#   它们也是非 ASCII 却只占 1 列,同样要扣。下面的列表是穷举过的,
#   加新的装饰字符时记得同步补进来。
_DW_NARROW=('·' '—' '✓' '✗' '●' '⚠' '❯' '›' '◆' '▐'
            '█' '▀' '▄' '▌' '▍' '▎' '░' '▒' '▓'
            '─' '━' '│' '┃' '├' '┤' '┬' '┴' '┼'
            '╭' '╮' '╰' '╯' '↑' '↓' '→' '←')
# ⚠ 这张表**不能有重复项**:同一个字符出现两次就会被扣两次宽度。
#   实测原来 '│' 写了两遍,量 '╭── │ ├─┤ ╰──╯' 时 14 列被算成 13 列。
#   下面的去重是纯 bash(零 fork),防止以后手滑再加一次。
_DW_SEEN=(); _DW_UNIQ=()
for _c in "${_DW_NARROW[@]}"; do
    _dup=0
    for _d in "${_DW_UNIQ[@]}"; do
        [[ "$_c" == "$_d" ]] && { _dup=1; break; }
    done
    (( _dup )) || _DW_UNIQ+=("$_c")
done
_DW_NARROW=("${_DW_UNIQ[@]}")
unset _DW_SEEN _DW_UNIQ _c _d _dup
_dw() {
    if (( _DW_FAST )); then
        local s="$1"
        local na="${s//[ -~]/}"          # 只剩非 ASCII
        local n=$(( ${#s} + ${#na} ))
        local c tmp
        for c in "${_DW_NARROW[@]}"; do
            tmp="${s//"$c"/}"
            (( ${#tmp} < ${#s} )) && n=$(( n - (${#s} - ${#tmp}) ))
        done
        _W=$n
    else
        # 兜底分支:没有 UTF-8 locale 时纯 bash 数不了「字符」(只能数字节),
        # 退回 wc -L —— 注意 wc -L 自己也依赖 locale,所以显式给它一个 UTF-8
        # 环境;真拿不到就只是近似(此时启动时已经打过警告)。
        _W=$(LC_ALL=C.UTF-8 wc -L <<< "$1" 2>/dev/null)
        [[ "$_W" =~ ^[0-9]+$ ]] || _W=$(wc -L <<< "$1" 2>/dev/null)
        [[ "$_W" =~ ^[0-9]+$ ]] || _W=${#1}
    fi
    return 0
}

# 同上,但结果写进全局 _W(不 fork 子 shell,适合循环里用)
disp_w_into() { _dw "$1"; }

# 右补空格到指定显示宽度(用显式空格,不用 printf 宽度修饰符)
pad_to() {
    local s="$1" w="$2" cur n
    cur="$(disp_w "$s")"
    n=$(( w - cur )); (( n < 0 )) && n=0
    printf '%s' "$s"
    (( n > 0 )) && printf '%*s' "$n" ''
}

# 按显示宽度截断(超宽则补 … 之前的部分),不切断多字节字符
trunc_to() {
    local s="$1" w="$2" cur out ch i
    cur="$(disp_w "$s")"
    (( cur <= w )) && { printf '%s' "$s"; return; }
    out=''; cur=0
    for (( i=0; i<${#s}; i++ )); do
        ch="${s:i:1}"
        local cw; cw="$(disp_w "$ch")"
        (( cur + cw > w - 1 )) && break
        out+="$ch"; cur=$(( cur + cw ))
    done
    printf '%s…' "$out"
}

# ── 读清单 + 状态 ───────────────────────────────────────────────────
# 同时缓存显示宽度 —— 绘制时零 wc 调用
IDS=(); NAMES=(); DESCS=(); STATES=()
NAME_W=(); DESC_W=()
load_agents() {
    # ⚠ 必须先把旧数组清空:`r` 刷新会再次调用本函数,数组是 +=' 追加的,
    #   不清就变成「9 项 → 18 项」的重复菜单(实测:按一次 r,列表翻倍)。
    IDS=(); NAMES=(); DESCS=(); STATES=(); NAME_W=(); DESC_W=()

    local statuses=""
    [[ -r "$CHECK" ]] && statuses="$(bash "$CHECK" --tsv 2>/dev/null)"

    # 一次把状态表读进关联数组。
    # ⚠ 原来写成「每行一次 $(printf ... | awk ...)」,19 个 agent 就是
    #   19 个管道 ≈ 19 × 49 ms ≈ 0.9 秒,全都花在起进程上。
    #   这里只解析一遍,查找是纯 bash,零 fork。
    local -A ST=()
    local sid sname sdesc scmd scheck skey skfile sst
    if [[ -n "$statuses" ]]; then
        while IFS=$'\t' read -r sid sname sdesc scmd scheck skey skfile sst; do
            [[ -n "$sid" ]] && ST["$sid"]="$sst"
        done <<< "$statuses"
    fi

    local id name desc cmd check_cmd key_env key_file extra
    while IFS=$'\t' read -r id name desc cmd check_cmd key_env key_file extra; do
        [[ -z "${id// }" ]] && continue
        [[ "${id:0:1}" == '#' ]] && continue
        local st="${ST[$id]:-skip}"
        [[ -z "$st" ]] && st="skip"
        IDS+=("$id"); NAMES+=("$name"); DESCS+=("$desc"); STATES+=("$st")
        # 宽度用纯 bash 算(零 fork)。这里如果用 $(disp_w ...) 就是
        # 19 × 2 = 38 次外部进程,实测 34 ms/次 ≈ 1.3 秒。
        _dw "$name";  NAME_W+=("$_W")
        _dw "$desc";  DESC_W+=("$_W")
    done < "$LIST"
    sort_by_state
    count_states
}

# ── 按就绪程度重排 ──────────────────────────────────────────────────
# 清单里十几个 agent,绝大多数没装。不排序的话列表就是一整片红色 ✗,
# 真正能用的埋在中间。这里把能用的排到前面:
#     ✓ 就绪 → ● 已安装 → ⚠ 缺 Key → ─ 无需检查 → ✗ 未安装
#
# 实现用「按等级分桶」而不是比较排序:等级只有 5 种,扫 5 遍数组即可,
# 而且天然稳定(同等级内保持清单原顺序)。
#
# ⚠ 必须避免 $(...) 取等级 —— 一次子 shell 约 14 ms,19 个 agent × 5 轮
#   就是 1.3 秒的启动延迟。所以等级函数只赋值到全局 _R,不 echo。
_R=0
_state_rank() {
    case "$1" in
        ok)        _R=0 ;;
        installed) _R=1 ;;
        needkey)   _R=2 ;;
        skip)      _R=3 ;;
        *)         _R=4 ;;
    esac
}

sort_by_state() {
    local n=${#IDS[@]}
    (( n < 2 )) && return 0

    local -a order=()
    local i rank
    for rank in 0 1 2 3 4; do
        for (( i=0; i<n; i++ )); do
            _state_rank "${STATES[$i]}"
            (( _R == rank )) && order+=("$i")
        done
    done

    local -a n_ids=() n_names=() n_descs=() n_states=() n_nw=() n_dw=()
    local k
    for k in "${order[@]}"; do
        n_ids+=("${IDS[$k]}");      n_names+=("${NAMES[$k]}")
        n_descs+=("${DESCS[$k]}");  n_states+=("${STATES[$k]}")
        n_nw+=("${NAME_W[$k]}");    n_dw+=("${DESC_W[$k]}")
    done
    IDS=("${n_ids[@]}"); NAMES=("${n_names[@]}"); DESCS=("${n_descs[@]}")
    STATES=("${n_states[@]}"); NAME_W=("${n_nw[@]}"); DESC_W=("${n_dw[@]}")
}

mark()       { case "$1" in ok) printf '✓';; installed) printf '●';; needkey) printf '⚠';; missing) printf '✗';; *) printf '·';; esac; }
mark_color() { case "$1" in ok) printf '%s' "$C_OK";; installed) printf '%s' "$C_INST";; needkey) printf '%s' "$C_WARN";; missing) printf '%s' "$C_BAD";; *) printf '%s' "$C_MUT";; esac; }
# label 的显示宽度只有五种取值,预先算好,避免每帧每行都调 wc
label()      { case "$1" in ok) printf '就绪';; installed) printf '已安装';; needkey) printf '缺 Key';; missing) printf '未安装';; *) printf '—';; esac; }
label_w()    { case "$1" in ok) printf '4';; installed) printf '6';; needkey) printf '6';; missing) printf '6';; *) printf '1';; esac; }

# ── logo:按终端尺寸自动选档(方案 A:半块字符)────────────────────
#
# 素材:logo/y-halfblock-<宽>.txt,由 tools/logo_halfblock.py 从原图渲染。
# 半块字符(▀▄█)把每个字符格拆成上下两半独立控制 → 垂直分辨率翻倍,
# 是「原图 → 字符画」中形状保留最好的一种可用方案。
#
# 尺寸策略(实测调整):
#   · 宽度 ≤ 终端宽度 / 4             → 不抢内容重心
#   · 行数 ≤ 可用高度 × 2 / 3          → 留出呼吸空间,但小终端也能显示
#
# 注意:半块字符下「列数 ≈ 像素宽」,而「字符行数 = 像素高 / 2」。
# 对正方形源图,像素高 = 像素宽 = 列数,所以字符行数 = 列数 / 2。
# 因此这里用「列数」做单位比较,而不是行数 —— 早期版本混用了两种单位,
# 导致 30 行终端里算出 10 < 16 而完全丢弃 logo。
LOGO=()      # 闪屏用的大 logo(方案 A:半块字符)
BANNER=()    # 菜单顶部的品牌字标(YZZ 块字)
BANNER_W=()  # 每个字标行的显示宽度(加载时算一次,避免每帧重复量)
_ROW=''      # make_row 的输出缓冲(不 echo,避免每个子 shell 14ms)

# 布局参数(compute_layout / build_frame 写入,绘制时只读)
LEFT_PAD=0; CW=0; ROW_W=0; AGENT_TOP=0; FOOTER_TOP=0
TOP=''; BLANK=''; SEP=''; SEP_TOP=''; SEP_BOT=''; HDR=''; FOOT=''; BOTTOM=''; PAD=''
KEYHINT=''; KEY_W=0; KEY_SHORT=''; KEY_SHORT_W=0; KEY_MINI=''; KEY_MINI_W=0
TALLY=''; TALLY_W=0
# 状态统计(页脚右侧显示「就绪 2 / 缺 Key 1 / 未安装 6」),只在重载清单时算一次
N_OK=0; N_INST=0; N_WARN=0; N_MISS=0; N_SKIP=0
count_states() {
    N_OK=0; N_INST=0; N_WARN=0; N_MISS=0; N_SKIP=0
    local s
    for s in "${STATES[@]}"; do
        case "$s" in
            ok)        N_OK=$(( N_OK + 1 )) ;;
            installed) N_INST=$(( N_INST + 1 )) ;;
            needkey)   N_WARN=$(( N_WARN + 1 )) ;;
            missing)   N_MISS=$(( N_MISS + 1 )) ;;
            *)         N_SKIP=$(( N_SKIP + 1 )) ;;
        esac
    done
    return 0
}
ROW_SEL=(); ROW_OFF=()
ENV_TXT=''; KEY_W=0
# 滚动视口:清单里可能有十几个 agent,多数终端放不下,只渲染可见窗口
SHOW_ART=1; VIEW_H=0; SCROLL=0
RESIZED=0

# 菜单字标:YZZ 块字(5 行)
#
# ⚠ 必须把所有行右补到「统一显示宽度」再交给绘制代码。
#   原因:Y 的两臂向下收拢,Z 的斜笔也收窄,所以原始字标各行宽度不同
#   (实测是 17/16/15/14/17)。绘制时是「逐行居中对齐」的,如果拿每行
#   自己的宽度算左移量,每行会被推不同的距离,整个字标被拆散
#   —— 实测表现为 Y 的左上臂和其余笔画错位、两个字 Z 变形。
#   文件里行尾空格常常被编辑器剥掉,所以不能指望素材本身对齐,
#   必须在加载时补齐(用显示宽度,不是字符数)。
pick_banner() {
    local dir="$SELF_DIR/../logo"; [[ -d "$dir" ]] || dir="$SELF_DIR/logo"
    local f="$dir/yzz-banner.txt"
    [[ -r "$f" ]] || return

    # 宽度一律走 _dw(纯 bash)。块字符 █ 是非 ASCII 但占 1 列,
    # 已经在 _DW_NARROW 里修正过,实测与 wc -L 完全一致。
    local line maxw=0 w
    local -a raw_w=()
    while IFS= read -r line; do
        [[ -z "${line// }" ]] && continue
        BANNER+=("$line")
        _dw "$line"; w=$_W
        raw_w+=("$w")
        (( w > maxw )) && maxw=$w
    done < "$f"
    (( ${#BANNER[@]} == 0 )) && return

    local i padn
    BANNER_W=()
    for i in "${!BANNER[@]}"; do
        padn=$(( maxw - raw_w[i] ))
        (( padn > 0 )) && printf -v "BANNER[$i]" '%s%*s' "${BANNER[$i]}" "$padn" ''
        # 补齐后所有行宽度都等于 maxw,直接缓存,不用再量
        BANNER_W+=("$maxw")
    done
}

pick_logo() {
    local dir="$SELF_DIR/../logo"; [[ -d "$dir" ]] || dir="$SELF_DIR/logo"

    # ⚠ 这里**不能**按 agent 数量预留行数。
    #   闪屏是独立的全屏画面,画完就 clear 掉再画菜单,两者不共存 ——
    #   所以它只需要给自己留够地方,不需要替菜单让位。
    #   (早期版本写成 reserved=$((8 + agent数)),只有 6 个 agent 时没问题;
    #    清单扩到 19 个之后 8+19=27,在 31 行的终端里只剩 4 行,
    #    于是判定「放不下」直接跳过,启动画面的大 Y 就消失了。)
    #
    # 预留:上面 1 空行 + 品牌行 1 + 空行 1 + 展开行 1 + 环境行 1 + 底部留白 1 = 6
    local reserved=6
    local avail=$(( ROWS - reserved ))
    (( avail < 6 )) && return

    local by_w=$(( COLS / 4 ))
    # 行数 ≤ avail*2/3  →  换算成列数上限:(avail*2/3)*2
    local by_h=$(( avail * 2 / 3 * 2 ))
    local want=$by_w
    (( by_h < want )) && want=$by_h
    (( want < 16 )) && want=16
    (( want > 64 )) && want=64

    # 选最接近且不超过的档位
    local best="" c
    for c in 16 20 24 28 32 36 40 48 56 64; do
        [[ -r "$dir/y-halfblock-$c.txt" ]] || continue
        (( c <= want )) && best="$dir/y-halfblock-$c.txt"
    done
    [[ -z "$best" ]] && best="$(ls -1 "$dir"/y-halfblock-*.txt 2>/dev/null | head -1)"
    [[ -z "$best" || ! -r "$best" ]] && return

    # 最后一道保险:实际行数放不下就不用
    local n; n=$(wc -l < "$best")
    (( n + reserved > ROWS )) && return

    while IFS= read -r line; do LOGO+=("$line"); done < "$best"

    # 诊断(AGENTBOX_DEBUG=1 时写日志,不影响界面)
    if [[ "${AGENTBOX_DEBUG:-0}" == "1" ]]; then
        {
            echo "pick_logo: SELF_DIR=$SELF_DIR"
            echo "  dir=$dir  COLS=$COLS ROWS=$ROWS  agents=${#IDS[@]}"
            echo "  reserved=$reserved avail=$avail by_w=$by_w by_h=$by_h want=$want"
            echo "  best=$best  载入 ${#LOGO[@]} 行"
        } >> "${AGENTBOX_DEBUG_LOG:-/tmp/agentbox-debug.log}" 2>&1
    fi
}

# ── 闪屏 ────────────────────────────────────────────────────────────
show_splash() {
    [[ "${AGENTBOX_NO_SPLASH:-0}" == "1" ]] && return 0
    (( NO_SPLASH )) && return 0
    (( ROWS < 20 || COLS < 50 )) && return 0
    printf '%s' "$_CLEAR"
    local l pad
    printf '\n'
    if (( ${#LOGO[@]} > 0 )); then
        local lw
        for l in "${LOGO[@]}"; do
            _dw "$l"; lw=$_W               # 纯 bash,避免 12 次 wc(≈0.4 秒)
            pad=$(( (COLS - lw) / 2 )); (( pad < 0 )) && pad=0
            printf '%*s%s%s%s\n' "$pad" '' "$C_BRAND" "$l" "$C_RST"
        done
    fi
    printf '\n'
    # 品牌行:▐ Y Z Z  ——可见宽度 = 1(▐) + 1(空格) + 5("Y Z Z") = 7
    local brand="Y Z Z"
    local brand_w=$(( 2 + ${#brand} ))
    pad=$(( (COLS - brand_w) / 2 )); (( pad < 0 )) && pad=0
    printf '%*s%s▐%s %s%s%s\n' "$pad" '' "$C_BRAND" "$C_RST" "$C_BRAND" "$brand" "$C_RST"

    # 三词展开
    local exp="$YZZ_EXPAND" ew
    _dw "$exp"; ew=$_W
    pad=$(( (COLS - ew) / 2 )); (( pad < 0 )) && pad=0
    printf '\n%*s%s%s%s\n' "$pad" '' "$C_MUT" "$exp" "$C_RST"

    # 运行环境
    local msg="$ENV_LONG" mw
    _dw "$msg"; mw=$_W
    pad=$(( (COLS - mw) / 2 )); (( pad < 0 )) && pad=0
    printf '%*s%s%s%s\n\n' "$pad" '' "$C_DIM" "$msg" "$C_RST"

    # 闪屏停留 0.64 秒(8 × 0.08):够看清品牌,又不至于每次启动都等一秒多。
    # 任意键提前跳过 —— 老用户不该被自己的启动画面拖住。
    local i
    for i in 1 2 3 4 5 6 7 8; do
        read -rsn1 -t 0.08 _ 2>/dev/null && break
    done
}

# ── 版面计算(只算数字,不画)─────────────────────────────────────────
# 只有启动时和收到 SIGWINCH 后才调用。平时按键完全不碰它。
#
# 竖排预算(不带框的固定行):
#   顶边框 1 + 空行 1 + 分隔线 1 + 分隔线 1 + 页脚 1 + 底边框 1 = 6
# 带字标时再加 N 行块字 + 1 空行。
# 剩下的行全给 agent 列表;不够就自动丢掉字标(小终端优先保证内容可见)。
compute_layout() {
    term_dims; COLS=$_TC; ROWS=$_TR
    local cols="$COLS"
    # 常规宽度 = 终端宽 - 8 列边距,上限 100 列(再宽就不好扫读)。
    # 窄终端(<47 列)改用满宽 -1:把最后一列写满会让终端进入「待换行」态,
    # conhost 这类实现在随后的 \n 之前可能多滚一行,把顶边框吃掉。
    # ⚠ 必须用 $cols,写成 CW=cols 会把字符串 "cols" 赋给 CW,
    #   随后算术运算把它当变量名求值,报 "cols: unbound variable"。
    if (( cols < 47 )); then CW=$(( cols - 1 )); else CW=$(( cols - 8 )); fi
    (( CW > 100 )) && CW=100
    (( CW > cols - 1 )) && CW=$(( cols - 1 ))    # 绝不超过终端宽(留 1 列安全位)
    (( CW < 24 )) && CW=24
    LEFT_PAD=$(( (cols - CW) / 2 )); (( LEFT_PAD < 0 )) && LEFT_PAD=0
    ROW_W=$(( CW - 4 )); (( ROW_W < 12 )) && ROW_W=12

    local n=${#IDS[@]}

    # 先试「带字标」
    SHOW_ART=1
    local fixed=$(( 7 + ${#BANNER[@]} ))
    VIEW_H=$(( ROWS - fixed ))
    if (( ${#BANNER[@]} == 0 || VIEW_H < 4 )); then
        SHOW_ART=0
        fixed=6
        VIEW_H=$(( ROWS - fixed ))
    fi
    (( VIEW_H < 1 )) && VIEW_H=1
    # ⚠ 必须写 $n,不能写 VIEW_H=n —— 那是把字面量字符 "n" 赋给 VIEW_H,
    #   算术里再把它当变量 n 去求值。旧版本只是碰巧在 compute_layout 和
    #   build_frame 里都声明了 local n,才侥幸算对(和 CW=cols 是同一类笔误)。
    #   一旦某处在 n 之前用到 VIEW_H,就会炸 "n: unbound variable"。
    (( VIEW_H > n )) && VIEW_H=$n
    (( VIEW_H < 1 )) && VIEW_H=1

    # 0 基屏幕行号
    if (( SHOW_ART )); then
        AGENT_TOP=$(( 4 + ${#BANNER[@]} ))   # 1顶框 +1空行 +N块字 +1空行 +1分隔
    else
        AGENT_TOP=3                          # 1顶框 +1空行 +1分隔
    fi
    FOOTER_TOP=$(( AGENT_TOP + VIEW_H + 1 )) # agents 之后是分隔线,再一行才是页脚

    (( SCROLL > n - VIEW_H )) && SCROLL=$(( n - VIEW_H ))
    (( SCROLL < 0 )) && SCROLL=0
}

# ── 状态 → 显示样式(赋值到全局,不 echo)────────────────────────────
# ⚠ 这里刻意不用 `mc="$(mark_color "$st")"` 这种写法。
#   一次 $(...) 是一次 fork,实测本机 14 ms。make_row 每条要 4 次,
#   而 build_frame 要生成「可见行数 × 2(选中/普通)」条 ——
#   19 个 agent 时就是 38 条 × 4 = 152 次 fork ≈ 2.1 秒,
#   再加上下面的 pad/trunc,启动要 7 秒才出菜单。
#   改成「函数只赋值到全局变量」后,函数调用不 fork,这段变成零开销。
_MK=''; _MC=''; _LB=''; _LW=0
_set_state_style() {
    case "$1" in
        ok)        _MK='✓'; _MC="$C_OK";   _LB='就绪';   _LW=4 ;;
        installed) _MK='●'; _MC="$C_INST"; _LB='已安装'; _LW=6 ;;
        needkey)   _MK='⚠'; _MC="$C_WARN"; _LB='缺 Key'; _LW=6 ;;
        missing)   _MK='✗'; _MC="$C_BAD";  _LB='未安装'; _LW=6 ;;
        *)         _MK='·'; _MC="$C_MUT";  _LB='—';      _LW=1 ;;
    esac
}

# ── 生成单行字符串(只在 build_frame 时调用)──────────────────────────
# 参数:$1 = 行下标,$2 = 是否选中(1/0)
# 输出:该行的完整可见内容(宽 ROW_W,不含边框)。
#
# 性能:常见路径上零 fork。
#   · 状态样式走 _set_state_style(不 fork)
#   · 补齐用 printf -v(builtin)+ 已缓存的 NAME_W/DESC_W,不调 disp_w
#   · 只有真要截断时才调用 trunc_to(需要逐字符量宽度,会 fork)
#   清单里的名字/描述都控制在 14/26 显示列以内,所以截断分支基本不触发。
make_row() {
    local i="$1" is_sel="$2"

    # ⚠ 名字/描述列宽必须按当前 ROW_W 自适应,不能写死 14/26。
    #   行结构是: 空格+光标+空格+标记+空格 + name + 空格 + desc + 间隙 + 空格 + 状态
    #   前面固定 6 列,状态词最宽 6 列(未安装),间隙至少 1 列 ——
    #   所以 name_w + desc_w + 6 + 1 + sw 必须 ≤ ROW_W,否则右边框被甩到框外。
    #   实测:cmd.exe 默认窗口只有 60 来列,写死 14+26 时整行溢出。
    local avail=$(( ROW_W - 14 ))
    (( avail < 6 )) && avail=6
    local name_w desc_w
    name_w=$(( avail * 35 / 100 )); (( name_w > 14 )) && name_w=14; (( name_w < 8 )) && name_w=8
    desc_w=$(( avail - name_w ));    (( desc_w > 26 )) && desc_w=26; (( desc_w < 6 )) && desc_w=6

    local cur=' '
    (( is_sel == 1 )) && cur="$SEL_CUR"

    _set_state_style "${STATES[$i]}"
    local mark_ch="$_MK" mc="$_MC" stxt="$_LB" sw="$_LW"

    # 极端窄终端(ROW_W 很小)时的硬保证:先砍描述列,再砍名字列,
    # 直到「内容 + 间隙 + 状态」放得下。缺了这一层,窄窗口会把右边框顶飞
    # —— 这是老版本在 40 列终端下的真实故障。
    local left_w=$(( 6 + name_w + desc_w ))
    local gap=$(( ROW_W - left_w - sw - 1 ))
    while (( gap < 1 )); do
        if (( desc_w > 0 )); then   (( desc_w-- ))
        elif (( name_w > 3 )); then (( name_w-- ))
        else break
        fi
        left_w=$(( 6 + name_w + desc_w ))
        gap=$(( ROW_W - left_w - sw - 1 ))
    done
    (( gap < 1 )) && gap=1

    local name="${NAMES[$i]}" desc="${DESCS[$i]}"
    local nw="${NAME_W[$i]}" dw="${DESC_W[$i]}"

    # 超宽才截断,截断后重新量一次宽度
    if (( nw > name_w )); then name="$(trunc_to "$name" "$name_w")"; nw="$(disp_w "$name")"; fi
    if (( desc_w <= 0 )); then
        desc=''; dw=0
    elif (( dw > desc_w )); then
        desc="$(trunc_to "$desc" "$desc_w")"; dw="$(disp_w "$desc")"
    fi

    local name_pad desc_pad
    printf -v name_pad '%s%*s' "$name" "$(( name_w - nw ))" ''
    printf -v desc_pad '%s%*s' "$desc" "$(( desc_w - dw ))" ''

    # 可见列数 = 6 + name_w + desc_w(随终端宽度变化,不再写死 46)。
    # 选中与非选中必须打印**完全相同**的可见结构,只换颜色码,
    # 否则两条分支差几列,右侧状态就对不齐(实测差 2 列)。
    local filler; printf -v filler '%*s' "$gap" ''

    # 可读性分层(2026-10-27):名字用亮色、描述用暗色,扫读时先看名字;
    # 「未安装 / 无需检查」整行连同名字一起压暗 —— 一屏 8 个里 5 个没装时,
    # 满屏红色会把真正能用的那两行淹没(README 的「为什么只有 8 个」讲过这个坑)。
    local namecol="$C_FG" desccol="$C_MUT"
    case "${STATES[$i]}" in
        missing|skip) namecol="$C_DIM"; desccol="$C_DIM" ;;
    esac

    if (( is_sel == 1 )); then
        # 选中行整行涂底色(含间隙与状态),只把状态词换成它自己的前景色;
        # 这样高亮是一条完整的横带,不会出现「左半截有底色、右半截没有」。
        left_part="$C_SEL $cur $mc$mark_ch$C_SEL $name_pad $desc_pad"
    else
        # 注意:$cur 后不能多留空格 —— 选中分支是 "$cur $mark_ch"
        # (一个空格),非选中也必须正好一个,否则整行宽差 1 列。
        left_part="$C_DIM $cur$C_RST$mc $mark_ch$C_RST $namecol$name_pad$C_RST $desccol$desc_pad$C_RST"
    fi
    # 结果写全局 _ROW,不 echo —— 调用方如果用 $(make_row ...),
    # 每行都会 fork 一个子 shell(实测 14 ms),38 行就是 0.5 秒。
    printf -v _ROW '%s%s%s %s%s' "$left_part" "$filler" "$mc" "$stxt" "$C_RST"
}

# ── 预生成整屏各部分的字符串 ────────────────────────────────────────
# 性能要点:交互延迟几乎全部来自 fork。实测本机 Git Bash 里
#     $(printf 'abc' | wc -L)  ≈ 49 ms
#     $(echo hi)               ≈ 14 ms
# 现在的做法是把所有可能变的东西在启动时算成字符串,
# 按键路径上只剩 printf(builtin)和光标定位,零 fork。
build_frame() {
    ENV_TXT="$ENV_LONG"             # 顶边框右端的环境标签
    local inner_w=$(( CW - 2 ))
    printf -v PAD '%*s' "$LEFT_PAD" ''

    # ── 顶边框:╭─ ◆ YZZ · <展开> ───── <环境> ─╮ ───────────────────
    # 窄终端按三档降级:完整 → 去掉三词展开 → 连环境标签也不要。
    # 少了这个降级,29 列以下终端上顶边框会写成 33 列,右边框直接被顶出屏幕。
    local head_full="─ ◆ YZZ · ${YZZ_EXPAND} " tail_full=" ${ENV_TXT} ─"
    local head_short='─ ◆ YZZ ' tail_short=' ─'
    local head='' tail='' hw=0 tw=0 x=0 _lvl
    for _lvl in 1 2 3; do
        case "$_lvl" in
            1) head="$head_full";  tail="$tail_full" ;;
            2) head="$head_short"; tail="$tail_full" ;;
            *) head="$head_short"; tail='' ;;
        esac
        _dw "$head"; hw=$_W
        _dw "$tail"; tw=$_W
        (( CW - 2 - hw - tw >= 2 )) && break
    done
    unset _lvl
    x=$(( CW - 2 - hw - tw )); (( x < 2 )) && x=2
    local dashes; printf -v dashes '%*s' "$x" ''
    dashes=${dashes// /─}

    TOP="${PAD}${C_BRAND}╭${C_RST}${C_BRAND}${head}${C_RST}${C_MUT}${dashes}${C_RST}${C_MUT}${tail}${C_RST}${C_BRAND}╮${C_RST}"$'\n'

    # ── 空行 / 分隔线 / 底边框 ──────────────────────────────────────
    local blank; printf -v blank '%*s' "$inner_w" ''
    BLANK="${PAD}${C_MUT}│${C_RST}${blank}${C_MUT}│${C_RST}"$'\n'

    # 分隔线右端一格用来提示「上面/下面还有内容」:列表被滚动窗口裁掉时
    # 换成 ↑ / ↓,宽度不变。用户不用数页码就知道自己站在列表哪一段。
    local n_all=${#IDS[@]}
    # ⚠ 不要写成 `local a=1 b="$a"`:同一个 local 命令里引用前一个变量,
    #   在 set -u 下会报 "a: unbound variable"(实测 Git Bash)。分成两行。
    local rule_top="${HLINE:0:inner_w}"
    local rule_bot="$rule_top"
    local mark_up='─' mark_dn='─'
    (( SCROLL > 0 )) && mark_up='↑'
    (( SCROLL + VIEW_H < n_all )) && mark_dn='↓'
    if (( inner_w > 1 )); then
        rule_top="${HLINE:0:inner_w-1}${C_MUT}${mark_up}${C_DIM}"
        rule_bot="${HLINE:0:inner_w-1}${C_MUT}${mark_dn}${C_DIM}"
    fi
    SEP_TOP="${PAD}${C_BRAND}├${C_RST}${C_DIM}${rule_top}${C_RST}${C_BRAND}┤${C_RST}"$'\n'
    SEP_BOT="${PAD}${C_BRAND}├${C_RST}${C_DIM}${rule_bot}${C_RST}${C_BRAND}┤${C_RST}"$'\n'
    # ⚠ BOTTOM **不带结尾换行**。它是整屏最后打印的东西,如果后面还有 \n,
    #   光标会多前进一行 —— 在「恰好排满」的终端里就触发滚动,把顶边框吃掉。
    #   实测:120x30 的窗口里 29 行内容 + 这个多余的 \n = 30 行,光标越过
    #   最后一行,整屏上滚 1 行,顶边框和字标第一行消失。
    BOTTOM="${PAD}${C_BRAND}╰${C_RST}${C_MUT}${HLINE:0:inner_w}${C_RST}${C_BRAND}╯${C_RST}"

    # ── 块字(左对齐,与下方 agent 列表同一竖线)──────────────────────
    # 左对齐而不是居中:居中时字标和下面左对齐的列表毫无对齐关系,
    # 看着像浮在框中间。缩进 1 列正好是 agent 行 "│ " 之后的图标位置。
    HDR=''
    if (( SHOW_ART )) && (( ${#BANNER[@]} > 0 )); then
        local k lw pl pr
        pl=1
        for k in "${!BANNER[@]}"; do
            lw="${BANNER_W[$k]}"          # 宽度已在 pick_banner 里缓存
            (( lw == 0 )) && lw="$(disp_w "${BANNER[$k]}")"
            pr=$(( inner_w - pl - lw ));  (( pr < 0 )) && pr=0
            local lp rp
            printf -v lp '%*s' "$pl" ''
            printf -v rp '%*s' "$pr" ''
            HDR+="${PAD}${C_MUT}│${C_RST}${lp}${C_BRAND}${BANNER[$k]}${C_RST}${rp}${C_MUT}│${C_RST}"$'\n'
        done
    fi

    # ── agent 行(每行预生成选中/普通两版)───────────────────────────
    # 注意:只生成 VISIBLE 范围内的行 —— 列表可能比屏幕长很多(19 个 agent
    # 在 24 行终端里放不下),所以这里按 [SCROLL, SCROLL+VIEW_H) 取窗口。
    ROW_SEL=(); ROW_OFF=()
    local i n=${#IDS[@]}
    for (( i=SCROLL; i<SCROLL+VIEW_H && i<n; i++ )); do
        local body_off body_sel
        # make_row 把结果写进全局 _ROW;这里不能写成 "$(make_row ...)",
        # 那样每行都会多 fork 一个子 shell(14 ms × 38 行 ≈ 0.5 秒)。
        make_row "$i" 0; body_off="$_ROW"
        make_row "$i" 1; body_sel="$_ROW"
        ROW_OFF+=("${PAD}${C_MUT}│${C_RST} ${body_off} ${C_MUT}│${C_RST}"$'\n')
        ROW_SEL+=("${PAD}${C_MUT}│${C_RST} ${body_sel} ${C_MUT}│${C_RST}"$'\n')
    done

    # ── 页脚素材:左侧键位提示,右侧状态统计 + 当前/总数 ──────────────
    # 键位提示预生成两档(完整/精简),窄终端自动降级,绝不撑破右边框。
    KEYHINT="${C_ACC}↑↓${C_MUT} 选择   ${C_ACC}Enter${C_MUT} 进入   ${C_ACC}r${C_MUT} 刷新   ${C_ACC}?${C_MUT} 帮助   ${C_ACC}q${C_MUT} 退出"
    _dw '↑↓ 选择   Enter 进入   r 刷新   ? 帮助   q 退出'; KEY_W=$_W
    KEY_SHORT="${C_ACC}↑↓${C_MUT} 选择  ${C_ACC}Enter${C_MUT} 进入  ${C_ACC}r${C_MUT} 刷新  ${C_ACC}?${C_MUT} 帮助"
    _dw '↑↓ 选择  Enter 进入  r 刷新  ? 帮助'; KEY_SHORT_W=$_W
    # 第三档:极窄终端只剩「怎么操作」的最少信息
    KEY_MINI="${C_MUT}↑↓ Enter r ? q"
    _dw '↑↓ Enter r ? q'; KEY_MINI_W=$_W

    # 状态统计:只显示非零项,一眼看出「这台机器上有几个真能用」。
    # 「无需检查」(Bash)不计数 —— 它不是 agent,算进去只会稀释信号。
    # 彩色版和纯文本版同步累加,纯文本那份只用来量宽度(必须精确到列)。
    TALLY=''; local tally_plain=''
    (( N_OK ))   && { TALLY+="${C_OK}✓${N_OK}${C_MUT} ";   tally_plain+="✓${N_OK} "; }
    (( N_INST )) && { TALLY+="${C_INST}●${N_INST}${C_MUT} "; tally_plain+="●${N_INST} "; }
    (( N_WARN )) && { TALLY+="${C_WARN}⚠${N_WARN}${C_MUT} "; tally_plain+="⚠${N_WARN} "; }
    (( N_MISS )) && { TALLY+="${C_BAD}✗${N_MISS}${C_MUT} "; tally_plain+="✗${N_MISS} "; }
    TALLY="${TALLY% }"
    tally_plain="${tally_plain% }"
    _dw "$tally_plain"; TALLY_W=$_W
}

# 页脚按当前选择重算(纯内建,零 fork)
#
# 可见结构:空格 + 键位提示 + 间隙 + 状态统计 + 空格 + 当前/总数 = ROW_W
# 宽度不够时按顺序降级(统计 → 精简键位 → 去掉键位),保证右边框永远对齐。
build_footer() {
    local sel="$1"
    local pos="$(( sel + 1 ))/${#IDS[@]}"
    # 内容区宽度 = CW-2 = ROW_W+2(两条边框之间);再扣掉两侧各一个空格
    # 和 pos 本身,剩下的才是「键位提示 + 状态统计」能用的体积。
    local avail=$(( ROW_W + 2 - 3 - ${#pos} ))   # pos 是纯 ASCII,字符数即列数
    (( avail < 1 )) && avail=1

    local keys="$KEYHINT" kw="$KEY_W"
    local tally="$TALLY"  tw="$TALLY_W"

    # 依次降级:统计 → 精简键位 → 极简键位 → 只留位置 —— 永不撑破右边框
    if (( kw + 1 + tw > avail )); then tally=''; tw=0; fi
    if (( kw > avail )); then keys="$KEY_SHORT"; kw="$KEY_SHORT_W"; fi
    if (( kw + 1 + tw > avail )); then tally=''; tw=0; fi
    if (( kw > avail )); then keys="$KEY_MINI"; kw="$KEY_MINI_W"; fi
    if (( kw > avail )); then keys=''; kw=0; fi

    local gap=$(( avail - kw - tw )); (( gap < 1 )) && gap=1
    local fp; printf -v fp '%*s' "$gap" ''
    FOOT="${PAD}${C_MUT}│${C_RST} ${keys}${fp}${tally} ${C_MUT}${pos}${C_RST} ${C_MUT}│${C_RST}"$'\n'
}

# ── 整屏绘制 ────────────────────────────────────────────────────────
# 直接用 ANSI 清屏,不调外部 clear:少一次 fork,也不依赖 TERM 是否有条目
# (PortableGit 的 terminfo 缺项时,clear 会失败但界面还得画)。
_CLEAR=$'\033[H\033[2J'
draw_menu() {
    local sel="$1"
    printf '%s' "$_CLEAR"
    printf '%s%s' "$TOP" "$BLANK"
    if (( SHOW_ART )); then printf '%s%s' "$HDR" "$BLANK"; fi
    printf '%s' "$SEP_TOP"
    local j n=${#ROW_OFF[@]}
    for (( j=0; j<n; j++ )); do
        local idx=$(( SCROLL + j ))
        if (( idx == sel )); then printf '%s' "${ROW_SEL[$j]}"
        else                     printf '%s' "${ROW_OFF[$j]}"; fi
    done
    build_footer "$sel"
    printf '%s%s%s' "$SEP_BOT" "$FOOT" "$BOTTOM"
}

# ── 单行重绘(零 fork)───────────────────────────────────────────────
# 参数:$1 = agent 下标,$2 = 是否选中
# ⚠ 必须定位到**第 1 列**:ROW_SEL/ROW_OFF 里已经把左边距 $PAD 拼进去了,
#   再定位到 LEFT_PAD 之后会让边距应用两次,整行右移、右边框跑出框架外。
#   这个 bug 的症状很有欺骗性:首次整屏正常,只有按过的行才歪。
row_at() {
    local i="$1" is_sel="$2" txt j
    j=$(( i - SCROLL ))
    (( j < 0 || j >= VIEW_H )) && return 0
    if (( is_sel == 1 )); then txt="${ROW_SEL[$j]}"; else txt="${ROW_OFF[$j]}"; fi
    printf '\033[%d;1H%s' $(( AGENT_TOP + j + 1 )) "$txt"
}

# ── 帮助浮层(? 触发)───────────────────────────────────────────────
# 只画纯文本行,靠 _dw 逐行补到统一宽度 —— 带 ANSI 的字符串不能用 _dw 量
# (转义序列会被当成可见字符)。任意键返回,返回后整屏重绘,所以不擦除。
show_help() {
    local w=$(( CW - 8 )); (( w > 62 )) && w=62; (( w < 26 )) && w=26
    local inner=$(( w - 2 ))
    local -a body=(
        '↑↓ / j k   移动              Home / End  首行 / 末行'
        'PgUp/PgDn  翻页              Enter       启动选中项'
        'r          重新探测状态      ?           本帮助'
        'q / Esc    退出启动器'
        ''
        '✓ 就绪   ● 已安装   ⚠ 缺 Key'
        '✗ 未安装  · 无需检查'
    )
    # 竖排放不下就自尾向前砍行(优先保留键位说明)
    local maxrows=$(( ROWS - 6 )); (( maxrows < 4 )) && maxrows=4
    while (( ${#body[@]} + 2 > maxrows && ${#body[@]} > 1 )); do
        body=("${body[@]:0:${#body[@]}-1}")
    done
    local box_h=$(( ${#body[@]} + 2 ))
    local top_row=$(( (ROWS - box_h) / 2 )); (( top_row < 1 )) && top_row=1
    local left_col=$(( (COLS - w) / 2 )); (( left_col < 0 )) && left_col=0
    local i line pad
    # 先清屏:帮助是模态画面,浮层比框架窄,不清屏会在它旁边留下一代目
    # 菜单的半截文字(实测 "绪" / "ey" 这种碎字),看着像画错了。
    # 返回时 main_loop 会整屏重绘,所以不用担心丢内容。
    printf '%s' "$_CLEAR"
    printf '\033[%d;%dH%s╭%s╮%s' "$top_row" $(( left_col + 1 )) \
        "$C_BRAND" "${HLINE:0:inner}" "$C_RST"
    for i in "${!body[@]}"; do
        line="${body[$i]}"
        _dw "$line"; pad=$(( inner - _W )); (( pad < 0 )) && pad=0
        printf -v line '%s%s%*s' "$line" '' "$pad"
        printf '\033[%d;%dH%s│%s%s%s%s%s│%s' $(( top_row + i + 1 )) $(( left_col + 1 )) \
            "$C_MUT" "$C_FG" "$line" "$C_RST" "$C_MUT" "" "$C_RST"
    done
    printf '\033[%d;%dH%s╰%s╯%s' $(( top_row + box_h - 1 )) $(( left_col + 1 )) \
        "$C_BRAND" "${HLINE:0:inner}" "$C_RST"
    # 任意键关闭(不设超时:用户看完自然会按)
    local _k
    IFS= read -rsn1 _k || true
}

# ── 交互 ────────────────────────────────────────────────────────────
# 读键用 0.25s 超时轮询,是为了让 SIGWINCH(拉窗口)不必等下一次按键才生效:
# 老版本把 RESIZED 检查放在阻塞 read 之后,缩放完不动键盘画面就一直是旧的。
KEY_TIMEOUT=0.25

# 离开 TUI 时清屏:整屏恰好排满时,多打一个 \n 就会上滚一行、把顶边框顶出
# 屏幕(README 第 15 条)。清屏比补 \n 稳,也给启动器留一个干净终端。
quit_clean() {
    printf '%s%s' "$C_SHOW" "$C_RST"
    printf '%s' "$_CLEAR"
}

main_loop() {
    STTY_SAVED="$(stty -g 2>/dev/null || true)"
    stty -echo -icanon min 1 time 0 2>/dev/null || true
    printf '%s' "$C_HIDE"

    local sel=0 n=${#IDS[@]}
    local shown=-1 cur_id='' idle_ticks=0

    RESIZED=0
    # SIGWINCH 在 Windows 控制台下**不可靠**(WT/conhost 不保证把 resize 变成
    # 这个信号送到 MSYS bash)。实测:trap 装了,拉完窗口画面纹丝不动 ——
    # 这条 trap 在老代码里一直是死代码。所以真正生效的是下面「空闲轮询」。
    trap 'RESIZED=1' WINCH 2>/dev/null || true

    compute_layout
    build_frame
    draw_menu "$sel"
    shown=$sel

    while true; do
        local k='' rc=0
        IFS= read -rsn1 -t "$KEY_TIMEOUT" k; rc=$?

        # 空闲轮询终端尺寸:每 4 次读超时(≈1 秒)量一次。
        # 代价是空闲时约 1 次 fork/秒(stty size),换来「拉窗口 1 秒内自动重排」;
        # 有键按下就不量(按键路径仍然零 fork)。
        if (( rc > 128 )); then
            idle_ticks=$(( idle_ticks + 1 ))
            if (( idle_ticks >= 4 )); then
                idle_ticks=0
                term_dims
                (( _TC != COLS || _TR != ROWS )) && RESIZED=1
            fi
        else
            idle_ticks=0
        fi

        # 窗口缩放 → 按新尺寸重排
        # ⚠ 这里有两个坑,都实测踩过:
        #   1) 缩放瞬间 stty 报的仍是旧尺寸 —— 用旧尺寸画新窗口,自动换行会把
        #      整屏切成错位残片,甚至比不画还乱;
        #   2) 二次读数也可能还是旧的(0.12s 不够),所以不能只信一次。
        # 对策:等一小会儿 → 画 → 再等 0.4s 复核 → 变了就再画一次(最多 3 轮)。
        if (( RESIZED )); then
            RESIZED=0
            sleep 0.15
            local guard=0
            while (( guard < 3 )); do
                guard=$(( guard + 1 ))
                compute_layout
                build_frame
                draw_menu "$sel"
                sleep 0.40
                term_dims
                (( _TC == COLS && _TR == ROWS )) && break
            done
            shown=$sel
            continue
        fi
        (( rc > 128 )) && continue          # 超时:继续等键
        if (( rc != 0 )); then
            quit_clean; return 130          # stdin 关闭(被管道调用等)
        fi

        local moved=0 refresh=0 help=0 quit=0
        case "$k" in
            $'\e')
                # 方向键/Home/End/PgUp/PgDn 都是 ESC [ …,单独 Esc = 退出。
                # 20ms 的后续字节窗口:人按 Esc 的手速远慢于这个间隔。
                local k2='' k3='' k4=''
                IFS= read -rsn1 -t 0.02 k2 2>/dev/null || true
                IFS= read -rsn1 -t 0.02 k3 2>/dev/null || true
                if [[ "$k2" != '[' ]]; then
                    quit=1
                else
                    case "$k3" in
                        A) sel=$(( (sel - 1 + n) % n )); moved=1 ;;
                        B) sel=$(( (sel + 1) % n ));     moved=1 ;;
                        H) sel=0;                        moved=1 ;;
                        F) sel=$(( n - 1 ));             moved=1 ;;
                        1|4|5|6|7|8)
                            IFS= read -rsn1 -t 0.02 k4 2>/dev/null || true
                            case "$k3$k4" in
                                5'~') sel=$(( sel - VIEW_H )); (( sel < 0 )) && sel=0; moved=1 ;;
                                6'~') sel=$(( sel + VIEW_H )); (( sel > n - 1 )) && sel=$(( n - 1 )); moved=1 ;;
                            esac ;;
                    esac
                fi ;;
            k|K) sel=$(( (sel - 1 + n) % n )); moved=1 ;;
            j|J) sel=$(( (sel + 1) % n ));     moved=1 ;;
            g)   sel=0;                        moved=1 ;;
            G)   sel=$(( n - 1 ));             moved=1 ;;
            r|R) refresh=1 ;;
            '?') help=1 ;;
            q|Q) quit=1 ;;
            ''|$'\n'|$'\r')
                printf '%s%s' "$C_SHOW" "$C_RST"
                printf '%s\n' "${IDS[$sel]}" >&3
                return 0 ;;
        esac

        if (( quit )); then quit_clean; return 130; fi

        if (( help )); then
            show_help
            draw_menu "$sel"; shown=$sel
            continue
        fi

        if (( refresh )); then
            # 记住选中项 id,重排后仍落回同一项 —— 刷新不该改变用户的位置。
            cur_id="${IDS[$sel]}"
            load_agents
            n=${#IDS[@]}
            compute_layout
            build_frame
            sel=0
            local i2
            for (( i2=0; i2<n; i2++ )); do
                [[ "${IDS[$i2]}" == "$cur_id" ]] && { sel=$i2; break; }
            done
            if (( sel < SCROLL )); then SCROLL=$sel
            elif (( sel >= SCROLL + VIEW_H )); then SCROLL=$(( sel - VIEW_H + 1 )); fi
            draw_menu "$sel"; shown=$sel
            continue
        fi

        if (( moved == 1 && sel != shown )); then
            # 先算新的滚动窗口
            local old_scroll=$SCROLL
            if (( sel < SCROLL )); then
                SCROLL=$sel
            elif (( sel >= SCROLL + VIEW_H )); then
                SCROLL=$(( sel - VIEW_H + 1 ))
            fi

            if (( SCROLL != old_scroll )); then
                # 窗口动了 → 重建(↑/↓ 提示与行内容都变),再整块重画
                build_frame
                local j
                for (( j=0; j<VIEW_H; j++ )); do
                    local idx=$(( SCROLL + j ))
                    (( idx >= n )) && break
                    row_at "$idx" "$(( idx == sel ? 1 : 0 ))"
                done
            else
                # 窗口没动 → 只重画「取消高亮」和「新高亮」两行
                row_at "$shown" 0
                row_at "$sel" 1
            fi

            build_footer "$sel"
            printf '\033[%d;1H%s' $(( FOOTER_TOP + 1 )) "$FOOT"
            shown=$sel
        fi
    done
}

# ── 入口 ────────────────────────────────────────────────────────────
# --list / --help 直接写 stdout(这些是给人或管道看的,不是 UI)
NO_SPLASH=0
DUMP=0
case "${1:-}" in
    --list)      bash "$CHECK"; exit 0 ;;
    --help|-h)   sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --no-splash) NO_SPLASH=1 ;;
    --dump)      DUMP=1; NO_SPLASH=1 ;;   # 纯文本整屏,给 selftest / 文档用
    # 逐行量显示宽度:读 stdin,输出 "<宽度>\t<原行>"。
    # 供 selftest.sh 校验宽度引擎(_dw)与 wc -L 是否一致 —— 这是第 16 条坑
    # (无 UTF-8 locale 时 ${#s} 数字节)的守门员。
    --width-probe)
        while IFS= read -r _line; do
            _dw "$_line"
            printf '%s\t%s\n' "$_W" "$_line"
        done
        exit 0 ;;
esac

load_agents
[[ ${#IDS[@]} -eq 0 ]] && { printf 'agentbox: 清单里没有可用 agent\n' >&2; exit 2; }

# --dump:不带任何 ANSI 地把一屏画到 stdout,然后退出。
# 这样回归测试可以不依赖 PTY,只用 COLUMNS/LINES 就能逐格比对。
if (( DUMP )); then
    C_BRAND=''; C_ACC=''; C_FG=''; C_MUT=''; C_DIM=''
    C_OK=''; C_INST=''; C_WARN=''; C_BAD=''; C_SEL=''; C_RST=''
    _CLEAR=''
    pick_banner
    compute_layout
    build_frame
    draw_menu 0
    exit 0
fi

# ── 输出契约:UI 走 stderr,选择结果走 fd 3 ──────────────────────────
# 背景:启动器用 choice="$(bash agentbox-tui.sh)" 捕获 stdout。
# 如果菜单也画到 stdout,整屏画面会被变量吞掉,终端只剩空白。
# 所以先把原始 stdout 复制到 fd 3,再把 stdout 指向 stderr：
#   · 所有画界面的 printf(未显式重定向)→ stderr → 正常显示
#   · 只把 id 写 fd 3 → 被启动器捕获
# 这样 TUI 既能单独在终端里跑(--list 仍走 stdout),也能被程序调用。
exec 3>&1
exec 1>&2

# 从这里开始才接管终端,装上清理钩子(Ctrl+C / 异常退出都要把光标和 stty 复原)
trap 'cleanup; exit 130' INT TERM
trap cleanup EXIT

pick_logo
pick_banner
show_splash
main_loop
exit $?
