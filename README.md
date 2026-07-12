# claude-profile-kit

**新機器一鍵建立開發環境**,並在同一台機器上切換多個 **Claude Code 登入身分(profile)**、
讓不同 profile **共用同一份專案 memory**。可攜、冪等安裝,方便在多台機器之間 port。

## 新機器:先裝 Claude Code,其他交給它

一台全新的 Ubuntu/Debian 或 macOS(需先裝 [Homebrew](https://brew.sh)),
只有一個手動步驟:

```bash
# 1. 裝 Claude Code(唯一手動步驟)
curl -fsSL https://claude.ai/install.sh | bash

# 2. 啟動並登入
claude
```

然後把這句話貼給 Claude:

> 請 clone https://github.com/cancerfreebiotech/claude-profile-kit 並照 repo 裡的 BOOTSTRAP.md 把這台新機器的開發環境裝好

Claude 會照 **[BOOTSTRAP.md](BOOTSTRAP.md)** 跑 `bootstrap.sh`(冪等,重跑安全),裝好:

- **zsh + oh-my-zsh**(含 zsh-autosuggestions / zsh-syntax-highlighting 外掛)並設為預設 shell
- **tmux**(Ctrl+x prefix、vi copy-mode、滑鼠、自訂 status bar)與 **screen**(含 `sl`/`sr`/`sn` 別名)
- **tailscale**(只安裝,結尾提示 `tailscale up`,不會自動連線)
- **本 kit**(多 profile 管理 + 跨 profile 共用 memory)
- PageUp/PageDown 前綴歷史搜尋等 shell 自訂功能;機密與機器特定設定走 `~/.zshrc.local`

不透過 Claude 手動跑也可以:

```bash
git clone https://github.com/cancerfreebiotech/claude-profile-kit.git
cd claude-profile-kit
bash bootstrap.sh          # 安裝 / 更新
bash bootstrap.sh --check  # 只檢查現況,不改東西
```

> 已有自訂 `~/.zshrc` 的機器:bootstrap **不會覆蓋**,只印出手動整合指示;
> `~/.zshrc.local` 與內容不同的既有 `~/.tmux.conf` 永遠不會被覆蓋。

## 只裝 kit 本體(profile 管理 + 共用 memory)

```bash
git clone https://github.com/cancerfreebiotech/claude-profile-kit.git
cd claude-profile-kit
bash install.sh
source ~/.zshrc   # 或開新終端機
```

安裝器會把 `claude-profiles.zsh` 放到 `~/.claude/`、把合併腳本放到 `~/.claude/bin/`,
並在 `~/.zshrc` 加一行 `source`(只加一次)。詳見 **[INSTALL.md](INSTALL.md)**。

> 需要 **zsh**;`python3` 只有手動合併腳本會用到。

## 指令

```bash
claude-list             # 列出所有 profile(👉 = 目前視窗使用中),含登入信箱
claude-switch work      # 切到名為 work 的 profile(不存在會自動建目錄)
claude-switch main      # 切回主帳號(預設 ~/.claude)
claude-remove work      # 刪除 profile(需確認,不能刪 main)
claude ...              # 照常啟動;會自動把此 project 的 memory 接上共用正本
```

## 跨 profile 共用 memory

每個 project 的 memory 只存**一份共用正本**在 `~/.claude/projects/<slug>/memory`,
其他 profile 的對應目錄都是指向它的 **symlink**。切到任何 profile、進同一個 project,
讀寫的都是同一份 memory 與 `MEMORY.md`。

`claude` wrapper 在啟動前只做**無損**動作(建 symlink / 升格為正本);遇到多 profile
各自寫過、內容分岔的情況會停下報警,交給合併腳本人工處理:

```bash
python3 ~/.claude/bin/claude-share-memory.py          # dry-run
python3 ~/.claude/bin/claude-share-memory.py --apply  # 實際合併(main 為主 + 補獨有檔)
```

## 安全

- 這個 repo 只含**機制**與**淨化過的設定**,不含任何登入憑證、API key 或 memory 內容。
- 登入 token 在 `~/.claude.json` 與 `~/.claude_profiles/*/.claude.json`,**不要**入庫或跨機器複製;
  新機器上每個 profile 各自重新登入即可。
- 機密(API key、token)與機器特定設定一律放 `~/.zshrc.local`
  (bootstrap 會建立範本、之後永不覆蓋;shell 啟動鏈最後載入,可覆蓋一切預設)。
