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

term_cols() { local c; c=$(tput cols 2>/dev/null || echo 80); [[ "$c" =~ ^[0-9]+$ ]] || c=80; echo "$c"; }
term_rows() { local r; r=$(tput lines 2>/dev/null || echo 24); [[ "$r" =~ ^[0-9]+$ ]] || r=24; echo "$r"; }

COLS=$(term_cols); ROWS=$(term_rows)

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
trap 'cleanup; exit 130' INT TERM
trap cleanup EXIT

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
_DW_NARROW=('·' '—' '✓' '✗' '●' '⚠' '❯' '◆' '▐'
            '█' '▀' '▄' '▌' '▍' '▎' '░' '▒' '▓'
            '─' '━' '│' '┃' '├' '┤' '┬' '┴' '┼'
            '╭' '╮' '╰' '╯' '│' '↑' '↓' '→' '←')
_dw() {
    local s="$1"
    local na="${s//[ -~]/}"          # 只剩非 ASCII
    local n=$(( ${#s} + ${#na} ))
    local c tmp
    for c in "${_DW_NARROW[@]}"; do
        tmp="${s//"$c"/}"
        (( ${#tmp} < ${#s} )) && n=$(( n - (${#s} - ${#tmp}) ))
    done
    _W=$n
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
TOP=''; BLANK=''; SEP=''; HDR=''; FOOT=''; BOTTOM=''; PAD=''
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
    (( ROWS < 20 || COLS < 50 )) && return 0
    clear
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

    local i
    for i in $(seq 1 12); do
        read -rsn1 -t 0.1 _ 2>/dev/null && break
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
    COLS=$(term_cols); ROWS=$(term_rows)
    local cols="$COLS"
    CW=$(( cols - 8 )); (( CW > 100 )) && CW=100
    # 终端太窄时(COLS<52)不再留左右边距,直接用满宽。
    # ⚠ 这里必须是 $cols,写成 CW=cols 会把字符串 "cols" 赋给 CW,
    #   随后算术运算把它当变量名去求值,报 "cols: unbound variable"。
    #   这个笔误只在窄终端下触发,宽终端永远不会走到,所以长期没被发现。
    (( CW < 44 )) && CW=$cols
    (( CW < 40 )) && CW=40
    LEFT_PAD=$(( (cols - CW) / 2 )); (( LEFT_PAD < 0 )) && LEFT_PAD=0
    ROW_W=$(( CW - 4 ))

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
    (( VIEW_H > n )) && VIEW_H=n
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
    #   前面固定 5 列,中间 1 列,间隙至少 1 列,状态词最宽 6 列(未安装) ——
    #   合计 5 + name_w + 1 + desc_w + 1 + 1 + 6 = name_w + desc_w + 14。
    #   所以 name_w + desc_w 必须 ≤ ROW_W - 14,否则行内容会撑破右边框。
    #
    #   实测:cmd.exe 默认窗口只有 60 来列,CW≈50、ROW_W≈46,
    #   而写死的 14+26=40 > 46-14=32 → 整行溢出、右边框被甩到框外。
    #   便携工具会被插到各种尺寸的终端上,这里必须自适应。
    local avail=$(( ROW_W - 14 ))
    (( avail < 12 )) && avail=12
    local name_w desc_w
    name_w=$(( avail * 35 / 100 )); (( name_w > 14 )) && name_w=14; (( name_w < 8 )) && name_w=8
    desc_w=$(( avail - name_w ));    (( desc_w > 26 )) && desc_w=26; (( desc_w < 6 )) && desc_w=6

    local cur=' '
    (( is_sel == 1 )) && cur='❯'

    _set_state_style "${STATES[$i]}"
    local mark_ch="$_MK" mc="$_MC" stxt="$_LB" sw="$_LW"

    local name="${NAMES[$i]}" desc="${DESCS[$i]}"
    local nw="${NAME_W[$i]}" dw="${DESC_W[$i]}"

    # 超宽才截断,截断后重新量一次宽度
    if (( nw > name_w )); then name="$(trunc_to "$name" "$name_w")"; nw="$(disp_w "$name")"; fi
    if (( dw > desc_w )); then desc="$(trunc_to "$desc" "$desc_w")"; dw="$(disp_w "$desc")"; fi

    local name_pad desc_pad
    printf -v name_pad '%s%*s' "$name" "$(( name_w - nw ))" ''
    printf -v desc_pad '%s%*s' "$desc" "$(( desc_w - dw ))" ''

    # 可见列数 = 5 + name_w + 1 + desc_w(随终端宽度变化,不再写死 46)
    # 选中与非选中必须打印**完全相同**的可见结构,只换颜色码,
    # 否则两条分支差几列,右侧状态就对不齐(实测差 2 列)。
    local left_w=$(( 6 + name_w + desc_w ))
    local gap=$(( ROW_W - left_w - sw - 1 )); (( gap < 1 )) && gap=1
    local filler; printf -v filler '%*s' "$gap" ''

    local left_part
    if (( is_sel == 1 )); then
        left_part="$C_SEL $cur $mark_ch $name_pad $desc_pad$C_RST"
    else
        # 注意:$cur 后不能多留空格 —— 选中分支是 "$cur $mark_ch"
        # (一个空格),非选中也必须正好一个,否则整行宽差 1 列。
        left_part="$C_MUT $cur$C_RST$C_FG $mark_ch $name_pad $desc_pad$C_RST"
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
    local head="─ ◆ YZZ · ${YZZ_EXPAND} "
    local tail=" ${ENV_TXT} ─"
    local hw tw x
    _dw "$head"; hw=$_W
    _dw "$tail"; tw=$_W
    (( CW - 2 - hw - tw < 2 )) && { head='─ ◆ YZZ '; _dw "$head"; hw=$_W; }
    x=$(( CW - 2 - hw - tw )); (( x < 2 )) && x=2
    local dashes; printf -v dashes '%*s' "$x" ''
    dashes=${dashes// /─}

    TOP="${PAD}${C_BRAND}╭${C_RST}${C_BRAND}${head}${C_RST}${C_DIM}${dashes}${C_RST}${C_MUT}${tail}${C_RST}${C_BRAND}╮${C_RST}"$'\n'

    # ── 空行 / 分隔线 / 底边框 ──────────────────────────────────────
    local blank; printf -v blank '%*s' "$inner_w" ''
    BLANK="${PAD}${C_DIM}│${C_RST}${blank}${C_DIM}│${C_RST}"$'\n'
    SEP="${PAD}${C_BRAND}├${C_RST}${C_DIM}${HLINE:0:inner_w}${C_RST}${C_BRAND}┤${C_RST}"$'\n'
    # ⚠ BOTTOM **不带结尾换行**。它是整屏最后打印的东西,如果后面还有 \n,
    #   光标会多前进一行 —— 在「恰好排满」的终端里就触发滚动,把顶边框吃掉。
    #   实测:120x30 的窗口里 29 行内容 + 这个多余的 \n = 30 行,光标越过
    #   最后一行,整屏上滚 1 行,顶边框和字标第一行消失。
    BOTTOM="${PAD}${C_BRAND}╰${C_RST}${C_DIM}${HLINE:0:inner_w}${C_RST}${C_BRAND}╯${C_RST}"

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
            HDR+="${PAD}${C_DIM}│${C_RST}${lp}${C_BRAND}${BANNER[$k]}${C_RST}${rp}${C_DIM}│${C_RST}"$'\n'
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
        ROW_OFF+=("${PAD}${C_DIM}│${C_RST} ${body_off} ${C_DIM}│${C_RST}"$'\n')
        ROW_SEL+=("${PAD}${C_DIM}│${C_RST} ${body_sel} ${C_DIM}│${C_RST}"$'\n')
    done

    # ── 页脚:左侧键位提示(固定),右侧「当前/总数」随选择变化 ────────
    _dw '↑↓ 选择   Enter 进入   q 退出'; KEY_W=$_W
}

# 页脚按当前选择重算(纯内建,零 fork)
build_footer() {
    local sel="$1"
    local pos="$(( sel + 1 ))/${#IDS[@]}"
    local padn
    padn=$(( CW - 3 - KEY_W - ${#pos} )); (( padn < 1 )) && padn=1
    local fp; printf -v fp '%*s' "$padn" ''
    FOOT="${PAD}${C_DIM}│${C_RST} ${C_ACC}↑↓${C_MUT} 选择   ${C_ACC}Enter${C_MUT} 进入   ${C_ACC}q${C_MUT} 退出${fp}${C_MUT}${pos}${C_RST}${C_DIM}│${C_RST}"$'\n'
}

# ── 整屏绘制 ────────────────────────────────────────────────────────
draw_menu() {
    local sel="$1"
    clear
    printf '%s%s' "$TOP" "$BLANK"
    if (( SHOW_ART )); then printf '%s%s' "$HDR" "$BLANK"; fi
    printf '%s' "$SEP"
    local j n=${#ROW_OFF[@]}
    for (( j=0; j<n; j++ )); do
        local idx=$(( SCROLL + j ))
        if (( idx == sel )); then printf '%s' "${ROW_SEL[$j]}"
        else                     printf '%s' "${ROW_OFF[$j]}"; fi
    done
    build_footer "$sel"
    printf '%s%s%s' "$SEP" "$FOOT" "$BOTTOM"
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

# ── 交互 ────────────────────────────────────────────────────────────
main_loop() {
    STTY_SAVED="$(stty -g 2>/dev/null || true)"
    stty -echo -icanon min 1 time 0 2>/dev/null || true
    printf '%s' "$C_HIDE"

    local sel=0 n=${#IDS[@]}
    local shown=-1

    RESIZED=0
    trap 'RESIZED=1' WINCH 2>/dev/null || true

    compute_layout
    build_frame
    draw_menu "$sel"
    shown=$sel

    while true; do
        local k moved=0
        IFS= read -rsn1 k || { printf '%s' "$C_SHOW$C_RST"; echo; return 130; }

        if (( RESIZED )); then
            RESIZED=0
            compute_layout
            build_frame
            draw_menu "$sel"
            shown=$sel
            continue
        fi

        case "$k" in
            $'\e')
                local k2='' k3=''
                IFS= read -rsn1 -t 0.02 k2 2>/dev/null || true
                IFS= read -rsn1 -t 0.02 k3 2>/dev/null || true
                if [[ "$k2" == '[' ]]; then
                    case "$k3" in
                        A) sel=$(( (sel - 1 + n) % n )); moved=1;;
                        B) sel=$(( (sel + 1) % n )); moved=1;;
                    esac
                fi ;;
            k) sel=$(( (sel - 1 + n) % n )); moved=1;;
            j) sel=$(( (sel + 1) % n )); moved=1;;
            q|Q) printf '%s' "$C_SHOW$C_RST"; echo; return 130;;
            ''|$'\n')
                printf '%s' "$C_SHOW$C_RST"
                printf '%s\n' "${IDS[$sel]}" >&3
                return 0;;
        esac

        if (( moved == 1 && sel != shown )); then
            # 先算新的滚动窗口
            local old_scroll=$SCROLL
            if (( sel < SCROLL )); then
                SCROLL=$sel
            elif (( sel >= SCROLL + VIEW_H )); then
                SCROLL=$(( sel - VIEW_H + 1 ))
            fi

            if (( SCROLL != old_scroll )); then
                # 窗口动了 → 整个可见块重画(仍是一次预计算字符串的打印,很快)
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
[[ "${1:-}" == '--list' ]] && { bash "$CHECK"; exit 0; }
[[ "${1:-}" == '--help' || "${1:-}" == '-h' ]] && { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

load_agents
[[ ${#IDS[@]} -eq 0 ]] && { echo "agentbox: 清单里没有可用 agent" >&2; exit 2; }

# ── 输出契约:UI 走 stderr,选择结果走 fd 3 ──────────────────────────
# 背景:启动器用 choice="$(bash agentbox-tui.sh)" 捕获 stdout。
# 如果菜单也画到 stdout,整屏画面会被变量吞掉,终端只剩空白。
# 所以先把原始 stdout 复制到 fd 3,再把 stdout 指向 stderr：
#   · 所有画界面的 printf(未显式重定向)→ stderr → 正常显示
#   · 只把 id 写 fd 3 → 被启动器捕获
# 这样 TUI 既能单独在终端里跑(--list 仍走 stdout),也能被程序调用。
exec 3>&1
exec 1>&2

pick_logo
pick_banner
show_splash
main_loop
exit $?
