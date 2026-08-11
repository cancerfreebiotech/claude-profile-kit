# 新機器 Bootstrap — 給 Claude Code 的執行指示

使用者剛在一台新機器上裝好 Claude Code（照 README 的一行指令），現在要你把整套開發環境建起來。請照以下步驟執行。

## 前提

- 使用者已裝好 Claude Code 並登入（你正在跑，就代表完成了）。
- 支援平台：Ubuntu/Debian（apt）或 macOS（需已裝 [Homebrew](https://brew.sh)）。
- 過程需要 sudo：先告知使用者可能會被要求輸入密碼。

## 步驟

1. **確認 git**（缺就裝）：
   ```bash
   command -v git || sudo apt-get update && sudo apt-get install -y git   # Linux
   command -v git || brew install git                                     # macOS
   ```

2. **clone 本 repo**（若你不是已經在 repo 目錄裡）：
   ```bash
   git clone https://github.com/cancerfreebiotech/claude-profile-kit.git ~/claude-profile-kit
   cd ~/claude-profile-kit
   ```

3. **跑 bootstrap**（冪等，重跑安全）：
   ```bash
   bash bootstrap.sh
   ```
   它會依序處理：基本套件（zsh/tmux/screen/mosh/git/curl/python3）→ tailscale →
   預設 shell 改 zsh → oh-my-zsh + 兩個外掛 → 部署 dotfiles（`~/.zshrc`、
   `~/.claude/dev-env.zsh`、`~/.tmux.conf`、`~/.zshrc.local` 模板）→
   Claude Code（已裝會略過）→ kit 本體（`install.sh`）。

4. **驗證**：
   ```bash
   bash bootstrap.sh --check     # 應全部 ✅
   zsh -ic 'type claude-switch claude; alias sr; bindkey | grep "5~"'
   TERM=xterm-256color tmux -f ~/.tmux.conf new-session -d \
     && tmux show -g prefix && tmux kill-server        # prefix 應為 C-x
   ```

5. **回報使用者**接下來要做的事：
   - 重新登入（或先 `exec zsh`）讓預設 shell 與新 `.zshrc` 生效
   - `sudo tailscale up` 連上 tailnet（macOS：開 Tailscale.app 登入）
   - 機密（API key、token）與機器特定設定放 `~/.zshrc.local`（永遠不會被覆蓋）
   - 其他 profile：`claude-switch <名稱>` 後在該視窗 `claude` 各自登入
   - 要把舊機器的 memory 搬過來的話，見 INSTALL.md「把舊機器的 memory 資料也帶過去」

## 注意事項

- **不要**複製任何登入憑證（`~/.claude.json`、`~/.claude_profiles/*/.claude.json` 內含 token）；
  每個 profile 在新機器各自重新登入。
- 機器已有自訂 `~/.zshrc` 時，bootstrap **不會覆蓋**，只會印出手動整合指示
  （plugins 行 + 一行 source）——先徵得使用者同意再照指示幫忙加。
- `~/.zshrc.local` 與內容不同的既有 `~/.tmux.conf` 永遠不會被覆蓋。
- bootstrap 不會執行 `tailscale up`（需要使用者本人認證）。
