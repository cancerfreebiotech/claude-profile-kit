# claude-profile-kit

在同一台機器上切換多個 **Claude Code 登入身分(profile)**,並讓不同 profile
**共用同一份專案 memory**。可攜、冪等安裝,方便在多台 Linux 之間 port。

## 快速安裝

```bash
git clone https://github.com/<你的帳號>/claude-profile-kit.git
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

- 這個 repo 只含**機制**,不含任何登入憑證或 memory 內容。
- 登入 token 在 `~/.claude.json` 與 `~/.claude_profiles/*/.claude.json`,**不要**入庫或跨機器複製;
  新機器上每個 profile 各自重新登入即可。
