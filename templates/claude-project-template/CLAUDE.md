# CLAUDE.md — {project}

> 此檔案為 Claude Code 的行為規範。每次執行任務前請先閱讀。

---

## 溝通語言

預設使用繁體中文回覆與討論。程式碼、commit message、技術術語不受此限。

---

## 專案簡介

**{project}** — 建立於 {date}
負責人：{name} ({email})
網址：{url}

完整需求請參考 `PRD.md`（如果有）。

---

## 開發原則（Core Engineering Principles）

> 本節保留英文原文以維持原意。

### Think Before Coding
State your assumptions explicitly. If uncertain, ask. If multiple interpretations exist, present them — don't pick silently.

### Simplicity First
Minimum code that solves the problem. No abstractions for single-use code, no unrequested "flexibility."

### Surgical Changes
Touch only what you must. Don't reformat adjacent code; match existing style. Don't delete pre-existing dead code unless asked.

### General
Reuse existing code/patterns first — read neighbouring files before writing. Check for an existing dependency before adding a new one.

---

## 多 Agent 分工政策

本專案已在 `.claude/agents/` 裝好角色分工。主 session（orchestrator）負責判斷、整合、最終決策——**不要自己動手做所有事**，符合下列情況就委派：

| 情況 | 委派給 |
|---|---|
| 需要先摸清楚現有程式碼/慣例、找可重用的既有實作 | `explorer` |
| 一般實作、bug fix、沒有特別專業要求 | `executor` |
| 觸碰密鑰、auth、對外端點、WAF/tunnel 設定 | `security-review`（先審查，通過才交 `executor` 動手） |
| UI/視覺/排版/RWD 判斷 | `ui-designer` |
| 文件、changelog、release notes（多語系） | `tech-writer` |
| 做完後要獨立檢查是否真的成立 | `verifier` |
| 一次動用超過一個角色、需要整合結論給人看 | `summarizer` |
| 策略/高層決策拿不定主意 | `/advisor` |
| 任務複雜到要先產出結構化計畫 | Plan Mode 或內建 `Plan` agent type（不用另建 subagent） |

**流程**：Discovery（交給 `explorer`，簡單狀況可自己看）→ Plan（不確定才做）→ 執行（委派對應角色）→ Verification（`verifier` 覆核）→ 整合（動用多角色才需要 `summarizer`）。

**規則**：
- 已派出去做唯讀分析的 agent，範圍暫時算它獨占——結果回來前不要自己重複分析同一塊，除非要取消重派。
- `verifier` 打回票後最多重做 2 輪；還沒過就停下來問人，不要自動無限重試——這是緊急上限，不是常規配額。
- 高風險/破壞性操作（見下）一律不因為委派給 subagent 就略過確認，subagent 自己碰到一樣要停下來問。

---

## 高風險與毀滅性操作

- 開發前先用 `pwd` 確認所在目錄；需存取專案以外（上層）目錄前，先詢問並取得同意。
- 涉及刪除檔案、修改 CI、變更依賴等高風險操作前，先說明再執行。
- 執行 `rm -rf` 等**毀滅性／不可逆**指令前，**必須明確取得使用者授權**，不可自行執行。

---

## 技術棧（複製本模板後填入）

- **框架**：
- **語言**：
- **樣式**：
- **UI 元件庫**：
- **資料庫 / Auth**：
- **國際化**：
- **套件管理**：

---

## 檔案與命名規範（複製本模板後填入）

| 類別 | 規則 | 範例 |
|---|---|---|
| | | |

---

## Git 規範

### Git 身份設定（首次使用必做）
```bash
git config user.name
git config user.email
```
若不是操作者本人的帳號，改用當前使用者的姓名與信箱設定——不寫死特定人名。

### Commit Message（Conventional Commits）
```
{type}({scope}): {簡述}
```
type：`feat` / `fix` / `docs` / `style` / `refactor` / `test` / `chore`

### Commit 作者標記（每次 Commit 必填）
```
Co-Authored-By: <目前操作者姓名> <目前操作者 email>
```

### Push 後是否自動確認部署狀態

依專案決定——有些專案要主動輪詢 CI/Actions 結果，有些不用。複製本模板後在此明確寫下這個專案的選擇，不要讓 agent 自己猜。

---

## 版本管理規則

- 格式：`v{MAJOR}.{MINOR}.{PATCH}`（SemVer），從 `v0.0.1` 開始。
- 預設慣例（可依專案調整）：**逢 9 進位**，每一節維持個位數，像里程表一樣逐級進位——`0.8.9 → 0.9.0`、`0.9.9 → 1.0.0`。
- 已發布的版號一律不回改。

---

## 安全性規則（複製本模板後填入）

- 認證方式：
- Session 管理：

---

## 禁止事項速查（複製本模板後填入）

- ❌
