#!/usr/bin/env bash
# =====================================================================
# claude-project-template 套用器（冪等）
# =====================================================================
# 用法：
#   bash apply.sh [target-dir] --gateway <base-url>   # 有 LLM gateway，
#                                                      # agents 保留 claude-proxy-* 別名
#   bash apply.sh [target-dir] --no-gateway            # 沒有 gateway，
#                                                      # agents 的 model: 改填 Claude 分級
#
# target-dir 預設是目前目錄。
#
# 做的事（全部冪等，重跑安全，不覆蓋已存在的檔案，除非加 --force）：
#   1. 複製 agents/*.md → <target>/.claude/agents/
#   2. 複製 CLAUDE.md → <target>/CLAUDE.md
#   3a. --gateway：複製 settings.json（套用 base-url）+ settings.local.json.example
#       → settings.local.json（範本，需自己填 token）；agents 的 model: 不動。
#   3b. --no-gateway：不建立 settings.json / settings.local.json（session 用你
#       現有的 Claude 登入即可）；把每個 agent 的 model: 從 `claude-proxy-*`
#       改成直接可用的 Claude 分級 —— security-review / verifier 用 opus
#       （重要性/懷疑態度優先），其餘用 sonnet。
set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="."
GATEWAY_MODE=""
GATEWAY_URL=""
FORCE=0

say() { printf '%s\n' "$*"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --gateway)
            GATEWAY_MODE="gateway"
            GATEWAY_URL="${2:-}"
            [ -n "$GATEWAY_URL" ] || { say "❌ --gateway 需要接 base-url"; exit 1; }
            shift 2
            ;;
        --no-gateway)
            GATEWAY_MODE="no-gateway"
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        -*)
            say "❌ 未知參數：$1"
            exit 1
            ;;
        *)
            TARGET="$1"
            shift
            ;;
    esac
done

if [ -z "$GATEWAY_MODE" ]; then
    say "❌ 必須指定 --gateway <base-url> 或 --no-gateway。"
    say "   有 Anthropic-Messages 相容的 LLM gateway（例如 LiteLLM）就用 --gateway，"
    say "   只想用你現有的 Claude 登入、不同角色一樣走 Claude 分級（opus/sonnet）就用 --no-gateway。"
    exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"
say "目標專案：$TARGET"
say "模式：$([ "$GATEWAY_MODE" = gateway ] && echo "接 gateway（$GATEWAY_URL）" || echo "不接 gateway（用現有 Claude 登入）")"
say ""

# 1. agents/*.md ----------------------------------------------------------
mkdir -p "$TARGET/.claude/agents"
COPIED_AGENTS=()
for f in "$TEMPLATE_DIR"/.claude/agents/*.md; do
    name="$(basename "$f")"
    dest="$TARGET/.claude/agents/$name"
    if [ -f "$dest" ] && [ "$FORCE" != 1 ]; then
        say "  ⚠️  $name 已存在，略過（用 --force 覆蓋）"
        continue
    fi
    cp "$f" "$dest"
    COPIED_AGENTS+=("$name")
    say "  ✅ 已裝 .claude/agents/$name"
done

# 沒接 gateway：把剛複製的 agent 的 model: 從 claude-proxy-* 改成直接可用的 Claude 分級
if [ "$GATEWAY_MODE" = "no-gateway" ]; then
    for name in "${COPIED_AGENTS[@]:-}"; do
        [ -n "$name" ] || continue
        dest="$TARGET/.claude/agents/$name"
        case "$name" in
            security-review.md|verifier.md) model="opus" ;;
            *) model="sonnet" ;;
        esac
        sed -i.bak -E "s/^model: claude-proxy-.*/model: $model/" "$dest" && rm -f "$dest.bak"
        say "  ↳ $name model: → $model"
    done
fi

# 2. CLAUDE.md --------------------------------------------------------------
if [ -f "$TARGET/CLAUDE.md" ] && [ "$FORCE" != 1 ]; then
    say "  ⚠️  CLAUDE.md 已存在，略過（用 --force 覆蓋）"
else
    cp "$TEMPLATE_DIR/CLAUDE.md" "$TARGET/CLAUDE.md"
    say "  ✅ 已裝 CLAUDE.md（記得填：專案簡介、技術棧、命名規範、安全性規則、禁止事項）"
fi

# 3. gateway 設定 -------------------------------------------------------------
if [ "$GATEWAY_MODE" = "gateway" ]; then
    mkdir -p "$TARGET/.claude"
    if [ -f "$TARGET/.claude/settings.json" ] && [ "$FORCE" != 1 ]; then
        say "  ⚠️  .claude/settings.json 已存在，略過（用 --force 覆蓋）"
    else
        sed -E "s#<your-gateway-base-url>#$GATEWAY_URL#" \
            "$TEMPLATE_DIR/.claude/settings.json" > "$TARGET/.claude/settings.json"
        say "  ✅ 已裝 .claude/settings.json（ANTHROPIC_BASE_URL=$GATEWAY_URL）"
    fi
    if [ -f "$TARGET/.claude/settings.local.json" ]; then
        say "  ⚠️  .claude/settings.local.json 已存在，不動（可能已有真實 permission/token 設定）"
    else
        cp "$TEMPLATE_DIR/.claude/settings.local.json.example" "$TARGET/.claude/settings.local.json"
        say "  🆕 已建立 .claude/settings.local.json 範本 — 請填入真的 ANTHROPIC_AUTH_TOKEN（不進 git）"
    fi
else
    say "  ℹ️  --no-gateway：不建立 settings.json / settings.local.json，session 沿用你現有的 Claude 登入。"
fi

say ""
say "🎉 套用完成。新增/修改的 .claude/agents 需要重開 claude session 才會生效（跑著的 session 不會自動載入）。"
say "   還要手動做的事：填 CLAUDE.md 留白章節；$([ "$GATEWAY_MODE" = gateway ] && echo "填 settings.local.json 的 ANTHROPIC_AUTH_TOKEN" || echo "確認沒設 CLAUDE_CODE_SUBAGENT_MODEL 環境變數（會蓋掉 agent 的 model: frontmatter）")。"
