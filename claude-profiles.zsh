# =====================================================================
# 🧠 Claude Code 多 Profile 身分管理 + 🔗 跨 Profile 共用專案 memory
# =====================================================================
# 由 ~/claude-profile-kit 安裝（見同目錄 INSTALL.md）。可跨機器攜帶。
# 安裝位置慣例：~/.claude/claude-profiles.zsh，並在 ~/.zshrc 內 source。
#
# 提供指令：
#   claude-switch <name|main>   切換 profile（main = 預設 ~/.claude）
#   claude-list                 列出所有 profile 與登入信箱
#   claude-remove <name>        刪除某個 profile（需確認）
#   claude                      包一層，啟動前自動把此 project 的 memory 接上共用正本
#
# 需要 zsh；在非 zsh（例如 bash）下 source 會安全跳過、不定義任何東西。
# ---------------------------------------------------------------------
[ -n "$ZSH_VERSION" ] || return 0

# --- 切換 profile：main 走預設 ~/.claude，其餘走 ~/.claude_profiles/<name> ---
function claude-switch() {
    local PROFILE="${1:-main}"

    if [ "$PROFILE" = "main" ]; then
        unset CLAUDE_CONFIG_DIR
        echo "🔄 已切回主帳號 (~/.claude)"
    else
        export CLAUDE_CONFIG_DIR="$HOME/.claude_profiles/$PROFILE"

        # 第一次使用自動建立
        if [ ! -d "$CLAUDE_CONFIG_DIR" ]; then
            mkdir -p "$CLAUDE_CONFIG_DIR"
            echo "🆕 已建立新 Profile 目錄: $CLAUDE_CONFIG_DIR"
        fi

        echo "🚀 已切換到 Profile: $PROFILE → $CLAUDE_CONFIG_DIR"
    fi
}

# --- 列出所有 profile（👉 = 目前 shell 使用中） ---
function claude-list() {
    local PROFILE_DIR="$HOME/.claude_profiles"
    local ACTIVE="${CLAUDE_CONFIG_DIR:-main}"
    local dir name email marker

    echo "📋 本機 Claude Profiles（👉 = 目前 shell 使用中）:"

    # 主帳號（~/.claude，登入資訊在 ~/.claude.json）
    marker="  "; [ "$ACTIVE" = "main" ] && marker="👉"
    email=$(grep -o '"emailAddress"[[:space:]]*:[[:space:]]*"[^"]*"' "$HOME/.claude.json" 2>/dev/null | head -1 | cut -d'"' -f4)
    printf "%s %-12s %s\n" "$marker" "main" "${email:-（尚未登入）}"

    # ~/.claude_profiles 底下的 profiles
    for dir in "$PROFILE_DIR"/*(N/); do
        name="${dir:t}"
        marker="  "; [ "$dir" = "$ACTIVE" ] && marker="👉"
        email=$(grep -o '"emailAddress"[[:space:]]*:[[:space:]]*"[^"]*"' "$dir/.claude.json" 2>/dev/null | head -1 | cut -d'"' -f4)
        printf "%s %-12s %s\n" "$marker" "$name" "${email:-（尚未登入）}"
    done
}

# --- 刪除 profile（需輸入 y 確認；不能刪 main） ---
function claude-remove() {
    local PROFILE="$1"
    local PROFILE_DIR="$HOME/.claude_profiles"

    if [ -z "$PROFILE" ]; then
        echo "💡 使用範例: claude-remove work  (刪除 work profile)"
        echo "💡 可先用 claude-list 查看目前有哪些 profile"
        return 1
    fi

    if [ "$PROFILE" = "main" ] || [ "$PROFILE" = "default" ]; then
        echo "⛔ 不能刪除主帳號 (~/.claude)"
        return 1
    fi

    # 防止名稱夾帶路徑（例如 ../foo）誤刪其他目錄
    case "$PROFILE" in
        */*|.|..) echo "⛔ 不合法的 Profile 名稱: $PROFILE"; return 1;;
    esac

    local TARGET="$PROFILE_DIR/$PROFILE"
    if [ ! -d "$TARGET" ]; then
        echo "❌ 找不到 Profile: $PROFILE ($TARGET)"
        return 1
    fi

    local email
    email=$(grep -o '"emailAddress"[[:space:]]*:[[:space:]]*"[^"]*"' "$TARGET/.claude.json" 2>/dev/null | head -1 | cut -d'"' -f4)

    echo "⚠️  即將刪除 Profile: $PROFILE${email:+（$email）}"
    echo "    路徑: $TARGET"
    printf "確定刪除？(y/N) "
    local REPLY
    read -r REPLY
    case "$REPLY" in
        y|Y|yes|YES) ;;
        *) echo "🚫 已取消"; return 1;;
    esac

    rm -rf -- "$TARGET"
    echo "🗑️  已刪除 Profile: $PROFILE"

    # 若刪的是目前使用中的 profile，自動切回主帳號
    if [ "$CLAUDE_CONFIG_DIR" = "$TARGET" ]; then
        unset CLAUDE_CONFIG_DIR
        echo "🔄 該 Profile 正在使用中，已自動切回主帳號 (~/.claude)"
    fi
}

# ---------------------------------------------------------------------
# 🔗 跨 Profile 共用專案記憶 (memory / MEMORY.md)
# 共用正本永遠放在 ~/.claude/projects/<slug>/memory；其他 profile 一律 symlink 過去。
# 啟動 claude 前自動處理（只做無損動作，真遇到分岔就停下報警，不亂併）：
#   • 已連結        → 略過
#   • profile 沒 memory / 空 → 直接建 symlink 指向正本
#   • 只有 profile 有   → 升格成共用正本，再 symlink
#   • 兩邊都有內容(分岔) → 不動，提示改用手動合併腳本
# 手動合併/一次性遷移： python3 ~/.claude/bin/claude-share-memory.py [--apply]
# ---------------------------------------------------------------------
function _claude-share-memory() {
    [ -n "$CLAUDE_CONFIG_DIR" ] || return 0   # main 直接讀正本，免處理
    emulate -L zsh
    setopt local_options null_glob

    local slug="${PWD//[^A-Za-z0-9]/-}"
    local canon="$HOME/.claude/projects/$slug/memory"
    local mine="$CLAUDE_CONFIG_DIR/projects/$slug/memory"

    # 已經連到正本
    [ "$(readlink "$mine" 2>/dev/null)" = "$canon" ] && return 0

    # profile 端已有「實體、非空」memory
    if [ -d "$mine" ] && [ ! -L "$mine" ] && [ -n "$(ls -A "$mine" 2>/dev/null)" ]; then
        if [ -d "$canon" ] && [ -n "$(ls -A "$canon" 2>/dev/null)" ]; then
            echo "⚠️  [$slug] 此 profile 與共用正本各有 memory，未自動合併。"
            echo "    手動合併： python3 ~/.claude/bin/claude-share-memory.py --apply"
            return 0
        fi
        mkdir -p "${canon:h}"
        mv "$mine" "$canon"                # 只有 profile 有 → 升格為共用正本
        ln -sfn "$canon" "$mine"
        echo "🔗 [$slug] 已把此 profile 的 memory 升為共用正本並連結。"
        return 0
    fi

    # profile 端沒有(或空) → 直接連到正本
    mkdir -p "$canon" "${mine:h}"
    [ -d "$mine" ] && [ ! -L "$mine" ] && rmdir "$mine" 2>/dev/null
    ln -sfn "$canon" "$mine"
}

# 包一層 claude：啟動前先確保 memory 已共用
function claude() {
    _claude-share-memory
    command claude "$@"
}
