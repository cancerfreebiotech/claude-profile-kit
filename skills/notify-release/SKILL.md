---
name: notify-release
description: Email a release notification to active users after a git push. Reads `.claude/notify-release.config.json` from the project root for Supabase project ref + recipient RPC + email templates; sends directly via SendGrid using credentials at `~/.claude/notify-release.env`. Skips silently if the config file is missing. Auto-invoke after a successful `git push` to main when the just-pushed commit bumped `package.json` version and added a CHANGELOG entry. Manually invoke as `/notify-release` or `/notify-release <version>` to resend or test.
---

# /notify-release [--dry-run] [version]

Send a release notification email for a version. Default version is `.version` from `package.json`. If `--dry-run` is passed, query recipients and show preview but don't send.

## Architecture (read this first)

The skill runs **fully locally** — it does NOT call any per-project HTTP endpoint to send. Pipeline:

1. Read per-project config (`.claude/notify-release.config.json`)
2. Query recipients via Supabase MCP (`mcp__claude_ai_Supabase__execute_sql`) using `supabaseProjectRef`
3. Render HTML from CHANGELOG
4. Read SendGrid credentials from `~/.claude/notify-release.env` (shared across all projects)
5. POST directly to `https://api.sendgrid.com/v3/mail/send`

This means **a new project only needs `.claude/notify-release.config.json` + a CHANGELOG** — no backend code, no per-project `RELEASE_NOTIFY_TOKEN`, no Vercel env wiring. The Supabase service role key never leaves Vercel.

The shared SendGrid env file at `~/.claude/notify-release.env`:
```
SENDGRID_API_KEY="SG.xxx..."
SENDGRID_FROM_EMAIL="you@example.com"
SENDGRID_FROM_NAME="Your Team"
```

(Created once, chmod 600, shared by all projects.)

## When to auto-invoke

After a `git push origin main` succeeds AND ALL of:
- The push included a bump in `package.json` `.version`
- There's a matching `## v{VERSION}` entry in the project's CHANGELOG
- The change is **user-facing** (see decision matrix below)

Verify push succeeded with `git status -sb` showing `## main...origin/main` (no `[ahead N]`).

Don't auto-invoke if the config file is missing — that project doesn't use this skill.

### User-facing decision matrix

Look at the commit type prefix in the CHANGELOG title (or commit message):

| Prefix | Default behavior | Reason |
|---|---|---|
| `feat(...)` | **auto-send** | New feature users can see / use |
| `fix(...)` | **auto-send** if the bug was user-visible (saving failed, button broken, page hangs, etc.); **skip** if internal-only (type errors, build warnings, race conditions in worker) | User cares about visible bugs being fixed |
| `chore(...)` | **skip** | Internal housekeeping (deps, refactor, cron cleanup, env tweaks) |
| `docs(...)` | **skip** | Docs/comments/CHANGELOG-only |
| `refactor(...)` | **skip** | Internal restructuring with no behavior change |
| `test(...)` / `style(...)` / `perf(...)` (internal) | **skip** | No user-visible change |
| Mixed or unclear | **ask user**: "this version is `<type>(...)` — auto-send or skip?" | Edge case, surface decision |

When skipping due to non-user-facing, briefly note to the user "skip notify-release: chore-only" so they know it was intentional. They can override with `/notify-release` manually.

When sending, also screen the CHANGELOG body — if every bullet is internal jargon (TS error codes, OAuth flow details, gitignore tweaks), consider:
- Asking the user whether to send as-is
- Or offering to rephrase technical bullets in user-language before send (skill judgment call)

## Per-project config

`.claude/notify-release.config.json` at repo root:

```json
{
  "supabaseProjectRef": "your-supabase-ref",
  "recipientRpc": "get_notification_recipients",
  "recipientFilter": "mfa_only",
  "replyToEmail": "you@example.com",
  "fromName": "Your Name (MyApp)",
  "changelogPath": "docs/CHANGELOG.md",
  "versionSource": "package.json",
  "projectName": "MyApp",
  "projectUrl": "https://myapp.example.com",
  "subjectTemplate": "{projectName} 已更新到 v{version}",
  "greeting": "大家好,",
  "introTemplate": "{projectName} 發布了 v{version}。",
  "signature": "— Your Name",
  "timezone": "Asia/Taipei",
  "language": "zh-TW",
  "releaseTimeLabel": "發布時間"
}
```

### Recipient resolution

The skill resolves recipients based on `recipientFilter`:

| `recipientFilter` | Behavior |
|---|---|
| `mfa_only` (default) | Call `recipientRpc` (default `get_notification_recipients`), keep rows where `has_mfa = true` AND `email` not null |
| `all` | Call `recipientRpc`, keep all rows with non-null `email` |
| `recent_30d` | Run inline SQL `SELECT email FROM users WHERE last_login_at >= now() - interval '30 days' AND email IS NOT NULL` |
| `custom_sql` | Use `recipientSql` field (raw SELECT returning `email` column) |

If the config has no `recipientFilter`, default to `mfa_only`.

## Procedure

1. **Read config** from `.claude/notify-release.config.json`. If missing, exit silently.
2. **Determine version**: if arg passed, use it; else read `versionSource` (default `package.json`) and extract `.version`.
3. **Extract CHANGELOG section**: read `changelogPath`. Find the line matching `^## v{VERSION}` and capture everything until the next `^## ` heading or EOF. If not found, abort with error.
4. **Get commit time**: `git log -1 --format='%cI' HEAD` (ISO 8601 with TZ). Convert to display format in the configured `timezone` (e.g. `2026-05-19 17:57 (Asia/Taipei, UTC+8)`).
5. **Query recipients** via Supabase MCP `execute_sql` with `project_id: supabaseProjectRef`. Apply `recipientFilter` rules above.
6. **Read SendGrid credentials** from `~/.claude/notify-release.env` (parse `KEY="VALUE"` lines, strip quotes). Need `SENDGRID_API_KEY` + `SENDGRID_FROM_EMAIL`. If missing, abort with hint to run `/notify-release setup-env`.
7. **Render HTML body** (see "HTML rendering" section below).
8. **Render subject**: substitute `{projectName}` and `{version}` in `subjectTemplate`.
9. **Dry-run path** (if `--dry-run` flag): print recipient list + rendered body + subject to the user, ask whether to send.
10. **Send**: POST to `https://api.sendgrid.com/v3/mail/send` with a **single `personalizations` entry whose `to` array lists ALL recipients** — one email where everyone can see who else received the notification. This is intentional: these are internal company-wide release notices, so shared visibility is desired (not a privacy concern). Use `curl` via Bash with the API key as Bearer token. (Quota note: SendGrid counts per recipient regardless of batching, so this uses the same quota as separate personalizations — the point is shared visibility, not cost.)
11. **Report**: short message — `📧 寄出: {sent} 人` on full success, or `⚠️ 寄出 {sent}/{total}, 失敗 {failed}` if partial.

### SendGrid request shape

```json
{
  "from": { "email": "<SENDGRID_FROM_EMAIL>", "name": "<config.fromName or SENDGRID_FROM_NAME>" },
  "reply_to": { "email": "<config.replyToEmail>" },
  "subject": "<rendered subject>",
  "content": [{ "type": "text/html", "value": "<rendered HTML>" }],
  "personalizations": [
    { "to": [{ "email": "user1@..." }, { "email": "user2@..." }, { "email": "user3@..." }] }
  ]
}
```

All recipients go in the single personalization's `to` array (everyone is visible to everyone — intended for internal notices).

SendGrid returns 202 on success (empty body). Anything else is an error — capture the response body and surface it.

Cap recipients at 1000 per request. For more, split into multiple requests.

## HTML rendering

Wrap content in this skeleton:

```html
<div style="font-family:-apple-system,'Segoe UI',sans-serif;line-height:1.6;color:#222;max-width:640px">
  <p>{greeting}</p>
  <p>{intro}</p>
  <p><strong>{releaseTimeLabel}</strong>: {commit_time}</p>
  <p>🔗 <a href="{projectUrl}">{projectUrl}</a></p>
  {rendered_changelog}
  <p style="color:#888;margin-top:2em">{signature}</p>
</div>
```

The `projectUrl` line is REQUIRED whenever the config has `projectUrl` — recipients should always get a one-click link to the deployed app. If the config lacks `projectUrl` (older projects), omit the line and suggest the user add the field to `.claude/notify-release.config.json`.

Convert CHANGELOG markdown to HTML by hand (do NOT pull in a markdown library — render directly):

| Markdown | HTML |
|---|---|
| `## v{ver} — {title}（{date}）` | `<h2 style="margin-top:1.8em;padding-bottom:0.3em;border-bottom:1px solid #ddd">{title}</h2>` (drop `## v{ver} — ` prefix and the `（{date}）` suffix; subject + release time covers those) |
| `### {section}` | `<h3 style="margin-top:1.4em">{section}</h3>` |
| `- bullet` (consecutive lines) | wrap group in `<ul style="padding-left:1.2em">`, each `<li>{bullet}</li>` |
| `**bold**` | `<strong>bold</strong>` |
| `` `code` `` | `<code style="background:#f4f4f4;padding:1px 4px;border-radius:3px;font-size:0.9em">code</code>` |
| Blank line between paragraphs | `<p>{para}</p>` |

The rendered changelog should be readable by non-technical recipients. If the source CHANGELOG has very technical bullets, consider rephrasing during conversion (judgment call — surface to user if rewriting).

Don't include nested markdown headings deeper than `###`.

## Failure modes

| Symptom | Cause | What to do |
|---|---|---|
| Config file missing | Project doesn't use this skill | Exit silently |
| `~/.claude/notify-release.env` missing or no `SENDGRID_API_KEY` | First-time setup incomplete | Run `/notify-release setup-env` or tell user to populate it |
| Supabase MCP returns error for `supabaseProjectRef` | Wrong ref or no access | Show the error; user may need to re-auth Supabase MCP |
| `## v{VERSION}` not found in CHANGELOG | User forgot to write CHANGELOG entry | Abort, tell user |
| SendGrid HTTP 401 | API key invalid / revoked | Tell user to rotate `SENDGRID_API_KEY` in `~/.claude/notify-release.env` |
| SendGrid HTTP 403 with "sender not verified" | `SENDGRID_FROM_EMAIL` not verified on the SG account | Show error; user verifies sender in SendGrid dashboard |
| `sent: 0` after query | No recipients match filter (e.g., no MFA users) | Inform user, but it's not an error |

## Manual invocations

- `/notify-release` — send for the version currently in `package.json`
- `/notify-release 6.4.5` — send for v6.4.5 (extracted from CHANGELOG)
- `/notify-release --dry-run` — preview recipient list and body, don't send
- `/notify-release --dry-run 6.4.5` — combine
- `/notify-release setup-env` — bootstrap the shared `~/.claude/notify-release.env` (first-time only)
- `/notify-release init` — bootstrap a new project to use this skill (see next section)

## `/notify-release setup-env` — one-time shared SendGrid setup

Only needed once per machine, not per project.

1. Check if `~/.claude/notify-release.env` exists and already has `SENDGRID_API_KEY`. If yes, report and exit.
2. Ask user to paste their SendGrid API key (or detect from an existing `vercel env pull` if a project is linked).
3. Ask for `SENDGRID_FROM_EMAIL` (must be a verified sender on the SG account).
4. Ask for `SENDGRID_FROM_NAME` (display name, e.g. "Your Team").
5. Write `~/.claude/notify-release.env` with `chmod 600`.
6. Test: offer to send a dry-run from any linked project.

## `/notify-release init` — bootstrap a new project

Runs in the current project root. Scaffolds the per-project pieces.

### Pre-flight

- Confirm cwd has a `package.json` or `.git` directory (otherwise wrong dir).
- If `.claude/notify-release.config.json` already exists → abort with "already initialized, edit manually".
- Confirm `~/.claude/notify-release.env` exists with `SENDGRID_API_KEY`. If not, prompt the user to run `/notify-release setup-env` first.
- Detect the project's Supabase ref:
  - If `.env.local` has `NEXT_PUBLIC_SUPABASE_URL=https://<ref>.supabase.co`, extract `<ref>`.
  - Otherwise call `mcp__claude_ai_Supabase__list_projects` and let the user pick.

### Ask the user 5 questions (AskUserQuestion)

1. **Project name** (string, e.g., "MyApp", "Acme") — used in subject + intro template.
1b. **Project URL** (e.g., "https://myapp.example.com") — linked in every release email. Try to prefill from the Vercel project / `NEXT_PUBLIC_SITE_URL` / README before asking.
2. **Recipient filter**: pick one — `mfa_only` / `all` / `recent_30d` / `custom_sql`.
   - If `custom_sql`: also prompt for the SELECT statement.
   - If `mfa_only` or `all`: prompt for `recipientRpc` name (default `get_notification_recipients`). Verify the RPC exists via `execute_sql` (`SELECT proname FROM pg_proc WHERE proname = '<name>'`). If missing for `mfa_only`, offer to copy it from another project that already has it.
3. **From name** (e.g., "Your Name (MyApp)", "MyApp Updates").
4. **Reply-To email** (default `you@example.com`).

### Generate `.claude/notify-release.config.json`

Use the template at the end of this skill, substituting answers.

### Update `.gitignore`

- If `.claude/` line exists (without `*`), change to `.claude/*` so wildcards work.
- Add `!.claude/notify-release.config.json` right after.

### Generate memory file

At `~/.claude/projects/<slug>/memory/feedback_notify_release_after_push.md` where `<slug>` is the cwd path with `/` replaced by `-` (e.g., `/home/you/proj/myapp` → `-home-you-proj-myapp`). Use the memory template at the end of this skill. Add a one-line entry to that project's `MEMORY.md` (create if missing).

### Report a final checklist

```
✅ Generated:
  - .claude/notify-release.config.json (Supabase ref: <ref>, recipients: <filter>)
  - .gitignore (selective un-ignore for the config)
  - Memory: feedback_notify_release_after_push.md

📋 Notes:
  - SendGrid credentials are shared from ~/.claude/notify-release.env (no per-project setup)
  - No backend code added to this project — sending happens entirely from Claude Code
  - If recipientFilter is mfa_only and the RPC doesn't exist, copy from another project that already has it
  - First send: try `/notify-release --dry-run` to verify recipient list looks right
```

## Templates

### `.claude/notify-release.config.json`

```json
{
  "$comment": "Config for the user-level /notify-release skill. Generated by /notify-release init.",
  "supabaseProjectRef": "{{supabaseRef}}",
  "recipientRpc": "{{recipientRpc}}",
  "recipientFilter": "{{recipientFilter}}",
  "replyToEmail": "{{replyToEmail}}",
  "fromName": "{{fromName}}",
  "changelogPath": "docs/CHANGELOG.md",
  "versionSource": "package.json",
  "projectName": "{{projectName}}",
  "projectUrl": "{{projectUrl}}",
  "subjectTemplate": "{projectName} 已更新到 v{version}",
  "greeting": "大家好,",
  "introTemplate": "{projectName} 發布了 v{version}。",
  "signature": "— Your Name",
  "timezone": "Asia/Taipei",
  "language": "zh-TW",
  "releaseTimeLabel": "發布時間"
}
```

### Memory file `feedback_notify_release_after_push.md`

```markdown
---
name: notify-release-after-push
description: After a successful `git push origin main` in {{projectName}}, automatically invoke the [[notify-release]] skill to email release notes to active users when the commit is user-facing (feat/fix). Skip auto-trigger for chore/docs/refactor.
metadata:
  type: feedback
---

After every successful `git push origin main` in this repo, automatically run the [[notify-release]] skill IF the commit is user-facing.

**Why:** The team wants to get notified about every user-facing release. Set up via `/notify-release init` on {{initDate}}.

**How to apply:**
- Trigger condition: ALL of (1) `git push origin main` exited 0, (2) version bumped in `package.json`, (3) `## v{VERSION}` section exists in `docs/CHANGELOG.md`, (4) commit is user-facing per the type matrix in [[notify-release]] SKILL.md
- When auto-sending: invoke without confirmation, report `📧 寄出: N 人`
- When skipping: note "skip notify-release: chore-only" to the user
- On failure: surface error but don't block (push already happened)
- Manually replay a missed version: `/notify-release <version>`
```

## Anti-patterns

- Don't ask the user "send to N recipients?" on every auto-invoke; the trigger context (user just authorized a push) implies authorization. Only confirm if explicitly --dry-run, or if something looks wrong (empty changelog, malformed config).
- Don't reuse the same email body for multiple version pushes if they happen in quick succession — each push gets its own email. Or, if the user batches several pushes and asks for a combined notification, send one email spanning multiple `## v{ver}` sections.
- Don't include `## v{ver} — ...` header in the HTML body verbatim; it duplicates the subject line. Strip it.
- Don't reintroduce a per-project HTTP endpoint — the whole point of this version is that new projects need zero backend code.
- Don't put `SENDGRID_API_KEY` into a project's `.env.local` — it lives in `~/.claude/notify-release.env` only.
