#!/usr/bin/env bash
# =====================================================================
# Claude Code 多 Profile + 跨 profile 共用 memory — 安裝器（冪等）
# =====================================================================
# 用法：  bash install.sh          # 安裝 / 更新
#        bash install.sh --check   # 只檢查現況，不改任何東西
#
# 做的事：
#   1. 檢查 zsh / python3
#   2. 建目錄 ~/.claude/{bin,projects}、~/.claude_profiles
#   3. 安裝 claude-profiles.zsh → ~/.claude/claude-profiles.zsh
#   4. 安裝 claude-share-memory.py → ~/.claude/bin/
#   5. 在 ~/.zshrc 加一行 source（只加一次）
#   6. 語法驗證
# 不會碰任何登入憑證，也不會搬 memory 資料（那是選配，見 INSTALL.md）。
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
RC="${ZDOTDIR:-$HOME}/.zshrc"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

say() { printf '%s\n' "$*"; }

# 1. 依賴檢查 ------------------------------------------------------------
if ! command -v zsh >/dev/null 2>&1; then
    say "❌ 找不到 zsh。這套功能需要 zsh，請先安裝（例：sudo apt install zsh）後再跑。"
    exit 1
fi
say "✅ zsh: $(command -v zsh)"
if command -v python3 >/dev/null 2>&1; then
    say "✅ python3: $(command -v python3)"
else
    say "⚠️  找不到 python3 — 平常切換/共用不受影響，但手動合併腳本 (claude-share-memory.py) 需要它。"
fi

if [ "$CHECK_ONLY" = "1" ]; then
    say ""
    say "── 現況檢查 ──"
    [ -f "$CLAUDE_DIR/claude-profiles.zsh" ] && say "  已安裝 claude-profiles.zsh" || say "  尚未安裝 claude-profiles.zsh"
    [ -f "$CLAUDE_DIR/bin/claude-share-memory.py" ] && say "  已安裝 claude-share-memory.py" || say "  尚未安裝 claude-share-memory.py"
    grep -qF 'claude-profiles.zsh' "$RC" 2>/dev/null && say "  $RC 已有 source 行" || say "  $RC 尚未加 source 行"
    exit 0
fi

# 2. 建目錄 --------------------------------------------------------------
mkdir -p "$CLAUDE_DIR/bin" "$CLAUDE_DIR/projects" "$HOME/.claude_profiles"

# 3~4. 安裝檔案 ----------------------------------------------------------
install -m 0644 "$KIT/claude-profiles.zsh"      "$CLAUDE_DIR/claude-profiles.zsh"
install -m 0755 "$KIT/claude-share-memory.py"   "$CLAUDE_DIR/bin/claude-share-memory.py"
say "✅ 已安裝 $CLAUDE_DIR/claude-profiles.zsh"
say "✅ 已安裝 $CLAUDE_DIR/bin/claude-share-memory.py"

# 5. 在 ~/.zshrc 加 source（冪等）---------------------------------------
touch "$RC"
if grep -qF 'claude-profiles.zsh' "$RC"; then
    say "ℹ️  $RC 已有 source 行，略過。"
else
    {
        printf '\n'
        printf '# Claude Code 多 Profile 身分管理 + 跨 profile 共用 memory\n'
        printf '[ -f "$HOME/.claude/claude-profiles.zsh" ] && source "$HOME/.claude/claude-profiles.zsh"\n'
    } >> "$RC"
    say "✅ 已在 $RC 加入 source 行。"
fi

# 6. 語法驗證 ------------------------------------------------------------
if zsh -n "$CLAUDE_DIR/claude-profiles.zsh"; then
    say "✅ 語法驗證通過。"
else
    say "❌ 語法驗證失敗，請檢查 $CLAUDE_DIR/claude-profiles.zsh"
    exit 1
fi

say ""
say "🎉 安裝完成。開新終端機，或執行： source $RC"
say "   然後試： claude-list   /   claude-switch <profile>   /   claude-switch main"
