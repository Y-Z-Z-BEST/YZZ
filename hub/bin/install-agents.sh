#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════
# install-agents.sh —— 把 agent 本体装进盘内 npm-global\
#
# 运行前提:subst Q: 已指向本盘(由调用方建立),这里只负责:
#   · 把 PATH / npm prefix / npm cache / HOME 全部指到盘内(和 start.cmd 一致)
#   · 逐个 npm install -g,失败不中断,最后汇总
#   · 记录每个包的体积与命令可用性
#
# 为什么必须用 Q: 而不是 E:\YZZ:有些包会把绝对路径烤进产物(不是只靠
# npm 的 %~dp0 相对垫片),走 Q: 装能让这些路径和启动器保持一致。
# ═════════════════════════════════════════════════════════════════════
set -uo pipefail

ROOT="${YZZ_ROOT:-Q:}"
NODE_DIR="$ROOT/runtime/node"
NPM="$NODE_DIR/npm.cmd"

export PATH="$NODE_DIR:$ROOT/npm-global:$ROOT/json-global/bin:$ROOT/runtime/git/bin:$ROOT/runtime/git/usr/bin:$PATH"
export npm_config_prefix="$ROOT/npm-global"
# 缓存默认放盘内;YZZ_NPM_CACHE 可以指向别的机器的缓存来加速首次安装
export npm_config_cache="${YZZ_NPM_CACHE:-$ROOT/temp/npm-cache}"
export NODE_PATH="$ROOT/npm-global/node_modules"
export USERPROFILE="$ROOT/home"
export HOME="$ROOT/home"
export APPDATA="$ROOT/home/AppData/Roaming"
export LOCALAPPDATA="$ROOT/home/AppData/Local"
export XDG_CONFIG_HOME="$ROOT/home/.config"
export XDG_DATA_HOME="$ROOT/home/.local/share"
export TEMP="$ROOT/temp"
export TMP="$ROOT/temp"
mkdir -p "$npm_config_cache" "$TEMP" 2>/dev/null

echo "== 环境 =="
echo "  ROOT       = $ROOT"
echo "  prefix     = $npm_config_prefix"
echo "  HOME       = $HOME"
echo "  node       = $($NODE_DIR/node.exe -v 2>&1)"
echo "  npm        = $("$NPM" -v 2>&1)"
echo

echo "== 连通性 =="
"$NPM" ping 2>&1 | tail -3
echo

# 包名 = agents.tsv 里对应 check_cmd 的来源
# 用法:install-agents.sh            装齐下面全部
#       install-agents.sh pkg1 pkg2  只装指定的(补装/重试)
if (( $# )); then
    PKGS=("$@")
else
    PKGS=(
        "@anthropic-ai/claude-code"
        "@openai/codex"
        "@qwen-code/qwen-code"
        "@github/copilot"
        "opencode-ai"
    )
fi

FAILED=()
for pkg in "${PKGS[@]}"; do
    echo "──────────────────────────────────────────────────────────────"
    echo "== 安装 $pkg =="
    start=$(date +%s)
    if "$NPM" install -g "$pkg" --no-fund --no-audit --loglevel=error 2>&1 | tail -15; then
        printf '   ✅ %s 完成,%d 秒\n' "$pkg" $(( $(date +%s) - start ))
    else
        printf '   ❌ %s 失败,%d 秒\n' "$pkg" $(( $(date +%s) - start ))
        FAILED+=("$pkg")
    fi
done

echo
echo "══════════════ 结果 ══════════════"
du -sh "$ROOT/npm-global" 2>/dev/null
printf '文件数:%s\n' "$(find "$ROOT/npm-global" -type f 2>/dev/null | wc -l)"
echo
echo "== 盘内命令是否可用(每行应是版本号) =="
for c in claude codex qwen copilot opencode gemini; do
    bin="$ROOT/npm-global/$c.cmd"
    if [[ -f "$bin" ]]; then
        printf '  %-10s 存在   ' "$c"
        (cd "$ROOT/workspace" 2>/dev/null || cd "$ROOT"; timeout 60 "$bin" --version 2>&1 | head -1) || echo "(--version 超时/失败)"
    else
        printf '  %-10s ✗ 没有垫片\n' "$c"
    fi
done
echo
if (( ${#FAILED[@]} )); then
    printf '失败的包:%s\n' "${FAILED[*]}"
else
    echo "全部安装命令执行完毕,无失败。"
fi
