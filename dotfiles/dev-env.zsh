# =====================================================================
# 可攜開發環境設定（claude-profile-kit dotfiles/dev-env.zsh）
# 由 bootstrap.sh 安裝到 ~/.claude/dev-env.zsh。
# 必須在 source oh-my-zsh 之後載入（否則 PageUp/PageDown 綁定會被蓋掉）。
# 機密與機器特定設定請放 ~/.zshrc.local（本檔結尾會載入）。
# =====================================================================
[ -n "$ZSH_VERSION" ] || return 0

# 使用者本地執行檔（Claude Code native install 也在這）
export PATH="$HOME/.local/bin:$PATH"

# 本機 IPv6 無路由時，讓 Node 優先走 IPv4（修正 fetch 超時）
export NODE_OPTIONS="--dns-result-order=ipv4first --network-family-autoselection-attempt-timeout=3000"

# ============================================================
# Screen 別名
# ============================================================
alias sl='command screen -ls'                 # 列 session
alias sr='command screen -RR'                 # 智慧 attach/create
alias sn='command screen -S'                  # 新建有名字的 session

# screen 的 socket 目錄（Linux 專用；macOS 用系統預設）
if [[ "$OSTYPE" == linux* ]]; then
    export SCREENDIR="/run/screen/S-$USER"
fi

# ============================================================
# PageUp/PageDown 搜尋歷史（前綴匹配）
# ============================================================
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey "^[[5~" up-line-or-beginning-search    # PageUp = 用游標前的內容往前搜尋
bindkey "^[[6~" down-line-or-beginning-search  # PageDown = 用游標前的內容往後搜尋

# ============================================================
# 自訂 screen window title（只顯示目錄/指令，不顯示 hostname）
# ============================================================
DISABLE_AUTO_TITLE="true"

if [[ "$TERM" == screen* ]]; then
    precmd() {
        print -Pn "\ek%~\e\\"
    }
    preexec() {
        print -Pn "\ek$1\e\\"
    }
fi

# ============================================================
# 機器特定 / 機密設定（不入庫，範例見 repo 的 dotfiles/zshrc.local.example）
# ============================================================
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
