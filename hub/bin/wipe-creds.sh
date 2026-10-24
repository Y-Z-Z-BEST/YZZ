#!/usr/bin/env bash
# ═════════════════════════════════════════════════════════════════════
# bin/wipe-creds.sh —— 擦除登录凭据,保留配置
#
# 背景(这是本便携方案最别扭、但必须解决的一点):
#   便携启动器把 USERPROFILE 指到盘内的 home\,
#   于是你在某台机器上登录 agent 时,凭据**必然会**写到盘里。
#   但用户的选择是「不带凭据,每台机器重新登录」,
#   所以退出时必须把凭据擦掉 —— 否则盘一丢账号就裸奔。
#
# 擦什么:只擦「登录凭据」,不碰配置。
#   配置(模型选择/MCP/主题/会话历史)是要跟着盘走的,删了等于白便携。
#
# 用法:
#   bash bin/wipe-creds.sh          擦除并打印结果
#   bash bin/wipe-creds.sh --check  只检查有哪些,不删(DRY RUN)
#
# 环境变量:
#   KEEP_CREDS=1   整个脚本直接跳过(在自己机器上想保持登录时用)
# ═════════════════════════════════════════════════════════════════════
set -uo pipefail

if [[ "${KEEP_CREDS:-0}" == '1' ]]; then
    printf '  KEEP_CREDS=1,跳过凭据擦除\n'
    exit 0
fi

DRY=0
[[ "${1:-}" == '--check' ]] && DRY=1

H="${HOME:-}"
if [[ -z "$H" ]]; then
    printf '  wipe-creds: HOME 未设置,无从下手,跳过\n' >&2
    exit 0
fi

# ── 凭据文件清单 ────────────────────────────────────────────────────
# 只列「登录态」,不列配置文件。加新 agent 时记得同步这里。
CREDS=(
    ".claude/.credentials.json"          # Claude Code
    ".codex/auth.json"                   # Codex CLI
    ".gemini/oauth_creds.json"           # Gemini CLI
    ".gemini/google_accounts.json"       # Gemini CLI 账号映射
    ".qwen/oauth_creds.json"             # Qwen Code
    ".config/gh/hosts.yml"               # GitHub CLI / Copilot CLI 的 token
    ".local/share/opencode/auth.json"    # OpenCode
    ".dsh/.credentials.yaml"             # DeepSeek Harness
    ".aider.model.settings.yml"          # Aider 里可能存 api key
)

removed=0; failed=0; found=0

for rel in "${CREDS[@]}"; do
    f="$H/$rel"
    [[ -e "$f" ]] || continue
    found=$((found + 1))
    if (( DRY )); then
        printf '  [将擦除] %s  (%s 字节)\n' "$rel" "$(wc -c < "$f" 2>/dev/null || echo '?')"
        continue
    fi
    if rm -f "$f" 2>/dev/null && [[ ! -e "$f" ]]; then
        printf '  已擦除   %s\n' "$rel"
        removed=$((removed + 1))
    else
        # 擦不掉通常是 agent 进程还没退干净、文件被占用
        printf '  ⚠ 擦除失败(可能仍被占用): %s\n' "$rel" >&2
        failed=$((failed + 1))
    fi
done

if (( found == 0 )); then
    printf '  没有发现凭据文件\n'
elif (( DRY )); then
    printf '  共 %d 个待擦除(DRY RUN,未实际删除)\n' "$found"
else
    printf '  完成:%d 个已擦除' "$removed"
    (( failed > 0 )) && printf ',%d 个失败' "$failed"
    printf '\n'
fi

# 擦除失败要明确返回非 0,让上层能提示用户「手动检查」
(( failed > 0 )) && exit 1
exit 0
