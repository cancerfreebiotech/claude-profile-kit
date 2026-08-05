# claude-profile-kit

**新機器一鍵建立開發環境**,並在同一台機器上切換多個 **Claude Code 登入身分(profile)**、
讓不同 profile **共用同一份專案 memory 與個人 skills**。可攜、冪等安裝,方便在多台機器之間 port。
另含一份**多 agent 分工的專案模板**,可複製到任何新 project(見下方「專案模板」章節)。

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
- **notify-release 技能**(`git push` 後寄發版通知 email;SendGrid 憑證放 `~/.claude/notify-release.env`,不入庫。詳見 [INSTALL.md](INSTALL.md))
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
claude ...              # 照常啟動;會自動把此 project 的 memory 與個人 skills 接上共用正本
```

## 跨 profile 共用 memory 與 skills

每個 project 的 memory 只存**一份共用正本**在 `~/.claude/projects/<slug>/memory`,
其他 profile 的對應目錄都是指向它的 **symlink**。切到任何 profile、進同一個 project,
讀寫的都是同一份 memory 與 `MEMORY.md`。

個人 **skills** 也是同樣邏輯,共用正本在 `~/.claude/skills`(不分 project,profile 層級共用)。

`claude` wrapper 在啟動前只做**無損**動作(建 symlink / 升格為正本);遇到多 profile
各自寫過、內容分岔的情況會停下報警,不自動亂併:

```bash
# memory 有專用合併腳本(按檔案合併、main 為主 + 補獨有檔)
python3 ~/.claude/bin/claude-share-memory.py          # dry-run
python3 ~/.claude/bin/claude-share-memory.py --apply  # 實際合併

# skills 分岔的情況少見(通常是刻意安裝),手動比對後搬進 ~/.claude/skills 即可
```

## 專案模板:多 agent 分工(`templates/claude-project-template`)

一份可以複製到任何新 project 的 `.claude/` 模板 + `CLAUDE.md`:一個 orchestrator(主 session)
負責判斷與整合,依任務性質委派給不同的專業 subagent,每個角色可以配置不同模型
(走支援 Anthropic Messages 格式的 LLM gateway,例如 LiteLLM,不同模型名字路由到不同 provider)。

| 角色 | 類型 | 用途 |
|---|---|---|
| advisor | native(`advisorModel`) | 策略/高層意見,`/advisor` 觸發 |
| explorer | subagent | Discovery:找相關檔案/既有慣例/可重用實作,唯讀 |
| security-review | subagent | 密鑰/auth/對外端點/WAF 設定的安全審查,唯讀 |
| ui-designer | subagent | 視覺/UI 一致性,含 mobile-friendly 檢查 |
| tech-writer | subagent | 文件/changelog/release notes,含 zh-TW/en/ja 多語系同步 |
| executor | subagent | 沒有特定專業對應的一般實作,預設工作者 |
| verifier | subagent | 完成後獨立驗證,不修不寫,只回報 CONFIRMED/REFUTED/INCONCLUSIVE |
| summarizer | subagent | 整合多個 agent 的產出成一份人看的結論 |

用法:

```bash
cp -r templates/claude-project-template/.claude /path/to/new-project/.claude
cp templates/claude-project-template/CLAUDE.md /path/to/new-project/CLAUDE.md
cd /path/to/new-project
cp .claude/settings.local.json.example .claude/settings.local.json
# 編輯 .claude/settings.json:把 <your-gateway-base-url> 換成你的 gateway 網址
# 編輯 .claude/settings.local.json:貼上真的 auth token(不入庫)
# 編輯 CLAUDE.md:填入專案簡介、技術棧、命名規範、安全性規則、禁止事項
```

**前提**:需要一個 Anthropic-Messages-格式相容的 LLM gateway,且模型別名要用 `claude-*`/`anthropic-*`
開頭(Claude Code 的 model discovery 只認這兩種開頭)。**已知限制**:`ANTHROPIC_BASE_URL` 整個
session 共用,所有 agent 沒辦法各自打不同的 endpoint;若環境變數設了 `CLAUDE_CODE_SUBAGENT_MODEL`
會蓋掉所有 subagent 的 `model:` frontmatter,讓分工模型形同虛設。細節見
[templates/claude-project-template/README.md](templates/claude-project-template/README.md)。

## 安全

- 這個 repo 只含**機制**與**淨化過的設定**,不含任何登入憑證、API key 或 memory 內容。
- 登入 token 在 `~/.claude.json` 與 `~/.claude_profiles/*/.claude.json`,**不要**入庫或跨機器複製;
  新機器上每個 profile 各自重新登入即可。
- 機密(API key、token)與機器特定設定一律放 `~/.zshrc.local`
  (bootstrap 會建立範本、之後永不覆蓋;shell 啟動鏈最後載入,可覆蓋一切預設)。
- notify-release 的 SendGrid key 放 `~/.claude/notify-release.env`、各專案設定放
  `.claude/notify-release.config.json`,兩者都被 `.gitignore` 排除,**絕不入庫**。
