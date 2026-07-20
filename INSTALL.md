# Claude Code 多 Profile + 跨 Profile 共用 memory / skills — 安裝包

這個資料夾把「在同一台機器上切換多個 Claude Code 登入身分(profile),並讓不同 profile
共用同一份專案 memory 與個人 skills」的整套功能打包起來,方便從一台 Linux port 到另一台。

## 這裡有什麼

| 檔案 | 用途 | 安裝後位置 |
|---|---|---|
| `claude-profiles.zsh` | 全部 zsh function(切換/列出/刪除 profile + 共用 memory/skills 的 `claude` wrapper) | `~/.claude/claude-profiles.zsh` |
| `claude-share-memory.py` | 一次性遷移 / 手動合併多 profile 分岔 memory 的腳本 | `~/.claude/bin/claude-share-memory.py` |
| `install.sh` | 冪等安裝器:放檔案、在 `~/.zshrc` 加一行 source、驗證語法 | — |
| `bootstrap.sh` | **新機器一鍵開發環境**:套件、tailscale、oh-my-zsh、dotfiles、Claude Code,最後呼叫 `install.sh` | — |
| `BOOTSTRAP.md` | 給新機器上 Claude Code 的 bootstrap 執行指示 | — |
| `dotfiles/zshrc` | 新機器 `~/.zshrc` 模板(**只在原本沒有 .zshrc 時**部署) | `~/.zshrc` |
| `dotfiles/dev-env.zsh` | 可攜 shell 自訂(screen 別名、PageUp/PageDown 前綴搜尋、視窗標題等) | `~/.claude/dev-env.zsh` |
| `dotfiles/tmux.conf` | tmux 自訂設定(Ctrl+x prefix 等;`default-shell` 部署時依平台渲染) | `~/.tmux.conf` |
| `dotfiles/zshrc.local.example` | 機密/機器特定設定範例(部署後**永不覆蓋**) | `~/.zshrc.local` |
| `skills/notify-release/SKILL.md` | `/notify-release` 技能:`git push` 後寄發版通知 email(淨化過的機制檔,無金鑰) | `~/.claude/skills/notify-release/SKILL.md` |
| `skills/notify-release/notify-release.env.example` | SendGrid 憑證範本(3 個 key:API key / from email / from name) | `~/.claude/notify-release.env`(0600,**只在缺時建、永不覆蓋**) |
| `skills/notify-release/notify-release.config.example.json` | per-project 設定範本 | 複製到各專案 `.claude/notify-release.config.json` |
| `INSTALL.md` | 本說明 | — |

## 需求

- **zsh**(functions 用到 zsh 專屬語法;非 zsh 會安全跳過不定義)
- **python3**(只有手動合併腳本需要;日常切換/共用不需要)

---

## 新機器?用 bootstrap

如果是一台全新機器(Ubuntu/Debian 或 macOS + Homebrew),不必手動裝上面的需求:
照 README 先裝好 Claude Code,再讓它依 **[BOOTSTRAP.md](BOOTSTRAP.md)** 跑
`bash bootstrap.sh`(冪等),一次裝好 zsh/oh-my-zsh/tmux/screen/tailscale/
dotfiles + 本 kit。注意:

- 機器**已有**自訂 `~/.zshrc` 時,bootstrap 不會覆蓋,只印手動整合指示。
- `~/.zshrc.local`(機密/機器特定設定)部署一次後**永不覆蓋**;
  內容不同的既有 `~/.tmux.conf` 也不會被覆蓋。
- `bash bootstrap.sh --check` 只檢查現況、不改任何東西。

以下章節是**只裝 kit 本體**(profile 管理 + 共用 memory)的流程。

---

## 給 Claude Code 的安裝指示

如果你是新機器上的 Claude Code,使用者要你安裝這套工具,請照做:

1. **跑安裝器**(冪等,可重複執行):
   ```bash
   bash install.sh
   ```
   它會:確認 zsh/python3 → 建 `~/.claude/{bin,projects}` 與 `~/.claude_profiles` →
   複製兩個檔案到 `~/.claude/` → 在 `~/.zshrc` 加一行 `source`(只加一次)→ `zsh -n` 驗證語法。

2. **驗證**安裝成功(在乾淨的互動 zsh 裡確認 function 已載入):
   ```bash
   zsh -ic 'source ~/.claude/claude-profiles.zsh; type claude-switch claude-list claude-remove claude'
   ```
   應看到四個都是 function / shell function。

3. **回報**使用者:要開新終端機或 `source ~/.zshrc` 才生效;之後可用
   `claude-list`、`claude-switch <名稱>`、`claude-switch main`。

注意事項:
- **不要**複製任何登入憑證(`~/.claude.json`、`~/.claude_profiles/*/.claude.json` 內含 token)。
  新機器上每個 profile 要各自重新登入:`claude-switch <名稱>` 後在該視窗 `claude` 登入一次即可。
- `install.sh` 只會在 `~/.zshrc` 加**一行** source,不會重寫使用者其他設定;重跑也不會重複加。
- 若使用者用非預設的 `ZDOTDIR`,安裝器會寫到 `$ZDOTDIR/.zshrc`。

---

## 手動安裝(不透過 Claude Code)

```bash
cd claude-profile-kit
bash install.sh          # 安裝
bash install.sh --check  # 只檢查現況,不改東西
source ~/.zshrc          # 或開新終端機
```

## 怎麼用

```bash
claude-list                 # 列出所有 profile(👉 = 目前視窗使用中),含登入信箱
claude-switch work          # 切到名為 work 的 profile(不存在會自動建目錄)
claude                      # 照常啟動;wrapper 會自動把此 project 的 memory 與個人 skills 接上共用正本
claude-switch main          # 切回主帳號(預設 ~/.claude)
claude-remove work          # 刪除 work profile(需輸入 y 確認,不能刪 main)
```

## 跨 profile 共用 memory / skills 是怎麼運作的

- 每個 project 的 memory 只存**一份共用正本**在 `~/.claude/projects/<slug>/memory`;
  其他 profile 的對應目錄都是指向它的 **symlink**。所以切到任何 profile、進同一個
  project,讀寫的都是同一份 memory 與 `MEMORY.md`。
- 個人 **skills** 邏輯相同,共用正本在 `~/.claude/skills`(profile 層級共用,不分 project)。
- 每次用 `claude` 啟動時,wrapper `_claude-share-memory` / `_claude-share-skills` 只做
  **無損**動作:已連結就略過;profile 沒有就建 symlink;只有 profile 有就升格為共用正本;
  **兩邊都有內容(分岔)時停下報警、不亂併**——memory 交給下面的腳本人工處理,
  skills 因為通常是刻意安裝、少分岔,手動比對搬檔即可。

### 一次性遷移 / 合併已分岔的 memory

如果新機器上已經有多個 profile 各自寫過同一個 project 的 memory(分岔),用:

```bash
python3 ~/.claude/bin/claude-share-memory.py          # dry-run:只印出打算怎麼併
python3 ~/.claude/bin/claude-share-memory.py --apply  # 實際執行
```

策略是 **main 為主 + 補獨有檔**:同名檔一律以 main(共用正本)版為準、不逐行合併;
只把「正本缺、其他 profile 才有」的檔補進來;正本不存在時以檔案最多的 profile 當底。
被取代的 profile 舊 memory 會改名成 `memory.bak.<時間戳>` 保留(不刪),可回溯。

## notify-release 技能(發版通知 email)

`install.sh` 會把技能裝到 `~/.claude/skills/notify-release/`。技能本身**不含任何金鑰**——
真正的 SendGrid API key 只放在 `~/.claude/notify-release.env`(0600),**絕不入庫**。
安裝器只會在該檔不存在時用範本建立一份 0600 空殼,已存在則不動。

首次設定(每台機器一次):

```bash
# 方式 A：用技能互動式寫入（推薦）
/notify-release setup-env          # 貼上 SendGrid API key、驗證寄件人、display name

# 方式 B：手動編輯安裝器建立的空殼
$EDITOR ~/.claude/notify-release.env
```

每個要用的專案跑一次:

```bash
/notify-release init               # 在專案根 scaffold .claude/notify-release.config.json + memory
```

之後 `git push` 到 main 且該版是 user-facing(feat/fix)時會自動寄送;
也可手動 `/notify-release`、`/notify-release <version>`、`/notify-release --dry-run`。
每個專案的 `.claude/notify-release.config.json`(含真實 Supabase ref)也**不入庫**——
`.gitignore` 已排除 `notify-release.env`、`*.env`、`notify-release.config.json`。

## (選配)把舊機器的 memory 資料也帶過去

安裝器只裝**機制**,不含任何 memory 內容。若要把舊機器累積的 memory 一起搬過來,
在**舊機器**上執行(只搬 memory,不含 session 記錄與憑證):

```bash
rsync -avR --prune-empty-dirs \
  --include='*/' --include='memory/**' --exclude='*' \
  ~/.claude/./projects/  新主機:~/.claude/projects/
```

搬完後在新機器跑一次 `python3 ~/.claude/bin/claude-share-memory.py --apply`,
把各 profile 的 memory 收斂到共用正本並建立 symlink。
