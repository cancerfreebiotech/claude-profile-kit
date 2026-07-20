#!/usr/bin/env bash
# =====================================================================
# 新機器開發環境 bootstrap（冪等）— claude-profile-kit
# =====================================================================
# 用法：  bash bootstrap.sh           # 建立 / 更新整套開發環境
#        bash bootstrap.sh --check   # 只檢查現況，不改任何東西
#
# 做的事（全部冪等，重跑安全）：
#   1. 套件：zsh tmux screen git curl（Linux: apt / macOS: brew）
#   2. tailscale（只安裝，不自動連線；結尾提示 tailscale up）
#   3. 預設 shell 改為 zsh
#   4. oh-my-zsh（無人值守；絕不覆蓋既有 ~/.zshrc）
#   5. zsh 外掛：zsh-autosuggestions、zsh-syntax-highlighting
#   6. 部署 dotfiles：~/.zshrc（僅原本沒有 .zshrc 的新機器）、
#      ~/.claude/dev-env.zsh、~/.tmux.conf、~/.zshrc.local 模板（存在絕不覆蓋）
#   7. Claude Code（native installer；已裝則略過）
#   8. 呼叫 install.sh 安裝 kit 本體（多 profile + 共用 memory + notify-release 技能）
#
# 支援平台：Ubuntu/Debian（apt）與 macOS（Homebrew）。
# 機密（API key、token）請放 ~/.zshrc.local，絕不要放進這個 repo。
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RC="${ZDOTDIR:-$HOME}/.zshrc"
MARKER="claude-profile-kit bootstrap"
ME="${USER:-$(id -un)}"
ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

say() { printf '%s\n' "$*"; }

# 0. 平台偵測 ------------------------------------------------------------
case "$(uname -s)" in
    Darwin)
        PLATFORM=macos
        if ! command -v brew >/dev/null 2>&1; then
            say "❌ macOS 需要先安裝 Homebrew：https://brew.sh"
            exit 1
        fi
        ;;
    Linux)
        if command -v apt-get >/dev/null 2>&1; then
            PLATFORM=linux-apt
        else
            say "❌ 目前只支援 apt 系 Linux（Ubuntu/Debian）與 macOS。"
            exit 1
        fi
        ;;
    *)
        say "❌ 不支援的平台：$(uname -s)"
        exit 1
        ;;
esac
say "✅ 平台：$PLATFORM"

SUDO="sudo"
[ "$(id -u)" = "0" ] && SUDO=""

# oh-my-zsh 安裝時若沒有 .zshrc 會生成模板；先記下「原本有沒有」供步驟 6 判斷
RC_EXISTED_BEFORE=0
[ -f "$RC" ] && RC_EXISTED_BEFORE=1

current_shell() {
    if [ "$PLATFORM" = "macos" ]; then
        dscl . -read "/Users/$ME" UserShell 2>/dev/null | awk '{print $2}'
    else
        getent passwd "$ME" | cut -d: -f7
    fi
}

render_tmux() { sed "s|@ZSH_PATH@|$(command -v zsh)|" "$KIT/dotfiles/tmux.conf"; }

tailscale_installed() {
    command -v tailscale >/dev/null 2>&1 || [ -d "/Applications/Tailscale.app" ]
}

claude_installed() {
    command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]
}

# --check：只檢查現況，不改任何東西 ---------------------------------------
if [ "$CHECK_ONLY" = "1" ]; then
    say ""
    say "── 現況檢查（bootstrap）──"
    for c in zsh tmux screen git curl; do
        command -v "$c" >/dev/null 2>&1 && say "  ✅ $c：$(command -v "$c")" || say "  ❌ 缺 $c"
    done
    tailscale_installed && say "  ✅ tailscale 已安裝" || say "  ❌ tailscale 未安裝"
    case "$(current_shell)" in
        */zsh) say "  ✅ 預設 shell 是 zsh" ;;
        *)     say "  ❌ 預設 shell 不是 zsh（$(current_shell)）" ;;
    esac
    [ -d "$HOME/.oh-my-zsh" ] && say "  ✅ oh-my-zsh 已安裝" || say "  ❌ oh-my-zsh 未安裝"
    for p in zsh-autosuggestions zsh-syntax-highlighting; do
        [ -d "$ZSH_CUSTOM_DIR/plugins/$p" ] && say "  ✅ 外掛 $p 已安裝" || say "  ❌ 外掛 $p 未安裝"
    done
    [ -f "$HOME/.claude/dev-env.zsh" ] && say "  ✅ ~/.claude/dev-env.zsh 已部署" || say "  ❌ ~/.claude/dev-env.zsh 未部署"
    if grep -qF "$MARKER" "$RC" 2>/dev/null; then
        say "  ✅ $RC 是 bootstrap 版"
    elif [ -f "$RC" ]; then
        say "  ⚠️  $RC 存在但不是 bootstrap 版（bootstrap 不會動它，會印手動指示）"
    else
        say "  ❌ $RC 不存在（bootstrap 會部署模板）"
    fi
    if [ ! -f "$HOME/.tmux.conf" ]; then
        say "  ❌ ~/.tmux.conf 不存在"
    elif command -v zsh >/dev/null 2>&1 && render_tmux | cmp -s - "$HOME/.tmux.conf"; then
        say "  ✅ ~/.tmux.conf 已是最新"
    else
        say "  ⚠️  ~/.tmux.conf 存在但與 dotfiles/tmux.conf 不同（bootstrap 不會覆蓋）"
    fi
    [ -f "$HOME/.zshrc.local" ] && say "  ✅ ~/.zshrc.local 已存在" || say "  ❌ ~/.zshrc.local 不存在（bootstrap 會建模板）"
    if claude_installed; then
        say "  ✅ Claude Code 已安裝（$("$HOME/.local/bin/claude" --version 2>/dev/null || claude --version 2>/dev/null || echo 版本未知)）"
    else
        say "  ❌ Claude Code 未安裝"
    fi
    say ""
    bash "$KIT/install.sh" --check
    exit 0
fi

# 1. 套件安裝 ------------------------------------------------------------
say ""
say "── 1/8 基本套件 ──"
if [ "$PLATFORM" = "linux-apt" ]; then
    $SUDO apt-get update
    $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        zsh tmux screen git curl ca-certificates command-not-found python3
else
    for pkg in zsh tmux screen git; do
        if brew list --formula "$pkg" >/dev/null 2>&1; then
            say "ℹ️  $pkg 已安裝（brew），略過。"
        else
            brew install "$pkg"
        fi
    done
fi
say "✅ 基本套件就緒。"

# 2. tailscale -----------------------------------------------------------
say ""
say "── 2/8 tailscale ──"
if tailscale_installed; then
    say "ℹ️  tailscale 已安裝，略過。"
elif [ "$PLATFORM" = "linux-apt" ]; then
    curl -fsSL https://tailscale.com/install.sh | sh
    say "✅ 已安裝 tailscale。"
else
    brew install --cask tailscale-app
    say "✅ 已安裝 Tailscale.app。"
fi

# 3. 預設 shell 改 zsh ----------------------------------------------------
say ""
say "── 3/8 預設 shell ──"
ZSH_BIN="$(command -v zsh)"
case "$(current_shell)" in
    */zsh)
        say "✅ 預設 shell 已是 zsh（$(current_shell)）"
        ;;
    *)
        grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null || printf '%s\n' "$ZSH_BIN" | $SUDO tee -a /etc/shells >/dev/null
        $SUDO chsh -s "$ZSH_BIN" "$ME"
        say "✅ 已把預設 shell 改為 $ZSH_BIN（重新登入後生效）"
        ;;
esac

# 4. oh-my-zsh -----------------------------------------------------------
say ""
say "── 4/8 oh-my-zsh ──"
if [ -d "$HOME/.oh-my-zsh" ]; then
    say "ℹ️  oh-my-zsh 已存在，略過。"
else
    # KEEP_ZSHRC=yes：既有 .zshrc 絕不被 omz 改名/覆蓋（保護傘，不可移除）
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    say "✅ 已安裝 oh-my-zsh。"
fi

# 5. zsh 外掛 ------------------------------------------------------------
say ""
say "── 5/8 zsh 外掛 ──"
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    dest="$ZSH_CUSTOM_DIR/plugins/$plugin"
    if [ -d "$dest" ]; then
        say "ℹ️  $plugin 已存在，略過。"
    else
        git clone --depth=1 "https://github.com/zsh-users/$plugin" "$dest"
        say "✅ 已安裝外掛：$plugin"
    fi
done

# 6. 部署 dotfiles --------------------------------------------------------
say ""
say "── 6/8 dotfiles ──"

# 6a. dev-env.zsh：無條件更新（同 install.sh 對 claude-profiles.zsh 的做法）
mkdir -p "$HOME/.claude"
install -m 0644 "$KIT/dotfiles/dev-env.zsh" "$HOME/.claude/dev-env.zsh"
say "✅ 已安裝 ~/.claude/dev-env.zsh"

# 6b. ~/.zshrc：只在「原本就沒有 .zshrc」的新機器整檔部署；既有的不動
if grep -qF "$MARKER" "$RC" 2>/dev/null; then
    say "✅ $RC 已是 bootstrap 版，略過。"
elif [ "$RC_EXISTED_BEFORE" = "0" ]; then
    install -m 0644 "$KIT/dotfiles/zshrc" "$RC"
    say "✅ 已部署 $RC（claude-profile-kit 版）"
else
    say "⚠️  $RC 已有自訂內容，不覆蓋。若要啟用本套設定，請手動："
    say "    1) plugins 行加入：zsh-autosuggestions zsh-syntax-highlighting screen command-not-found history sudo"
    say "    2) 檔尾加一行：[ -f \"\$HOME/.claude/dev-env.zsh\" ] && source \"\$HOME/.claude/dev-env.zsh\""
fi

# 6c. ~/.tmux.conf：渲染 default-shell 後部署；已存在且不同則不覆蓋
if [ ! -f "$HOME/.tmux.conf" ]; then
    render_tmux > "$HOME/.tmux.conf"
    say "✅ 已部署 ~/.tmux.conf（prefix = Ctrl+x）"
elif render_tmux | cmp -s - "$HOME/.tmux.conf"; then
    say "✅ ~/.tmux.conf 已是最新，略過。"
else
    say "⚠️  ~/.tmux.conf 已存在且內容不同，不覆蓋（可自行比對 $KIT/dotfiles/tmux.conf）。"
fi

# 6d. ~/.zshrc.local：機密/機器特定設定，存在絕不覆蓋
if [ -f "$HOME/.zshrc.local" ]; then
    say "ℹ️  ~/.zshrc.local 已存在，不覆蓋。"
else
    install -m 0600 "$KIT/dotfiles/zshrc.local.example" "$HOME/.zshrc.local"
    say "✅ 已建立 ~/.zshrc.local 模板（機密與機器特定設定請放這裡）"
fi

# 7. Claude Code ----------------------------------------------------------
say ""
say "── 7/8 Claude Code ──"
if claude_installed; then
    say "ℹ️  Claude Code 已安裝（$("$HOME/.local/bin/claude" --version 2>/dev/null || claude --version 2>/dev/null || echo 版本未知)）；要更新請跑：claude update"
else
    curl -fsSL https://claude.ai/install.sh | bash
    if [ -x "$HOME/.local/bin/claude" ]; then
        say "✅ 已安裝 Claude Code：$("$HOME/.local/bin/claude" --version)"
    else
        say "❌ Claude Code 安裝失敗（找不到 ~/.local/bin/claude）"
        exit 1
    fi
fi

# 8. kit 本體（多 profile + 共用 memory）----------------------------------
say ""
say "── 8/8 claude-profile-kit 本體 ──"
bash "$KIT/install.sh"

# 9. 總結 ------------------------------------------------------------------
say ""
say "🎉 Bootstrap 完成。接下來："
say "   1. 重新登入（或先 exec zsh）讓預設 shell 與新 .zshrc 生效"
if [ "$PLATFORM" = "macos" ]; then
    say "   2. 開 Tailscale.app 登入，連上 tailnet"
else
    say "   2. sudo tailscale up    # 連上 tailnet"
fi
say "   3. claude                # 首次啟動登入；其他 profile：claude-switch <名稱> 後各自登入"
say "   4. 機密與機器特定設定請編輯 ~/.zshrc.local（永遠不會被覆蓋）"
