# claude-project-template

一份可以複製到任何新 project 的 `.claude/` 模板 + `CLAUDE.md`：一個 orchestrator（主 session）+ 7 個專業分工 subagent + native advisor 設定，模型分配走多 provider 的 LLM gateway（見下方「你需要準備的東西」）。`CLAUDE.md` 沿用 [其他專案] 既有的規範結構（開發原則、Git/版本慣例、風險操作守則），技術棧相關章節留白給各專案自己填。

## 角色一覽

| 角色 | 類型 | 用途 |
|---|---|---|
| advisor | native (`advisorModel`) | 策略/高層意見，`/advisor` 觸發 |
| explorer | subagent | Discovery：找相關檔案/既有慣例/可重用實作，唯讀 |
| security-review | subagent | 密鑰/auth/對外端點/WAF 設定的安全審查，唯讀 |
| ui-designer | subagent | 視覺/UI 一致性，掛 design 相關 skill |
| tech-writer | subagent | 文件/changelog/release notes，掛 document 相關 skill |
| executor | subagent | 沒有特定專業對應的一般實作，預設工作者 |
| verifier | subagent | 完成後獨立驗證，不修不寫，只回報 CONFIRMED/REFUTED/INCONCLUSIVE |
| summarizer | subagent | 整合多個 agent 的產出成一份人看的結論 |

`planner` 不需要另外做——Claude Code 原生的 Plan Mode + 內建 `Plan` agent type 已經在做這件事。

## 用法

用 `apply.sh` 套用（冪等、不覆蓋已存在的檔案，除非加 `--force`）：

```bash
# 有 LLM gateway：agents 保留 claude-proxy-* 別名，另外裝 settings.json/settings.local.json
bash templates/claude-project-template/apply.sh /path/to/new-project --gateway https://your-gateway.example.com

# 沒有 gateway：agents 的 model: 直接改成 Claude 分級（security-review/verifier 用 opus，其餘 sonnet），
# 不建立 settings.json/settings.local.json，session 沿用你現有的 Claude 登入
bash templates/claude-project-template/apply.sh /path/to/new-project --no-gateway
```

跑完後還要手動做的事：填 `CLAUDE.md` 留白章節（專案簡介、技術棧、命名規範、安全性規則、禁止事項）；
`--gateway` 模式要填 `.claude/settings.local.json` 的真實 auth token（這個檔案不進 git）。

新建的 `agents/` 目錄需要重新啟動 `claude` session 才會被偵測到，跑著的 session 不會自動載入。

不想用腳本、手動複製也可以：
```bash
cp -r templates/claude-project-template/.claude /path/to/new-project/.claude
cp templates/claude-project-template/CLAUDE.md /path/to/new-project/CLAUDE.md
```
（沒有 gateway 的話記得把每個 `agents/*.md` 的 `model: claude-proxy-*` 手動改成 `sonnet`/`opus`，並跳過 `settings.json` 的 `ANTHROPIC_BASE_URL` 設定。）

## 你需要準備的東西

這份模板假設你有一個 Anthropic-Messages-格式相容的 LLM gateway（例如 LiteLLM），前面代理你想用的各家模型，並且用 `claude-*` 開頭的別名（因為 Claude Code 的 model discovery 只認 `claude`/`anthropic` 開頭的名字）。`agents/*.md` 裡的 model 名稱（`claude-proxy-opus`、`claude-proxy-sonnet` 等）只是範例，請換成你自己 gateway 實際提供的別名。

**重要限制**：`ANTHROPIC_BASE_URL` 是整個 session 共用的，同一個 session 裡的 agent 沒辦法各自打不同的 endpoint/provider——多模型的「跨 provider」是靠 gateway 幫你把不同 model 名字路由到不同後端做到的，不是 Claude Code 原生支援每個 subagent 各自接一台伺服器。

**已知風險**：`CLAUDE_CODE_SUBAGENT_MODEL`（如果在環境裡被設定）會蓋掉所有 subagent 自己的 `model:` frontmatter，讓這份模板的分工模型形同虛設——用之前先確認沒有這個環境變數。
