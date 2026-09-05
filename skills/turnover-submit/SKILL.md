# /turnover-submit [--dry-run] [--status <runId>] <sql-file-or-inline-sql>

Submit a database migration (DDL/DML) to FlightPath's Turnover system from Claude Code, and watch it run to completion — no need to open a browser. This is the CLI counterpart to FlightPath's `/turnover` web page; both end up calling the exact same backend (`submitTurnoverRun`), so behavior (backup-before-DDL, access control, Neon/Supabase support) is identical either way.

## Architecture (read this first)

This skill runs **fully locally**, same shape as `notify-release`:

1. Read per-project config (`.claude/flightpath.json`) — just a FlightPath project id, no secrets.
2. Read the shared personal key from `~/.claude/flightpath-turnover.env` (one key, works across every project the developer has access to — shared across all projects on that developer's machine, same pattern as `notify-release.env`).
3. `POST {flightpathUrl}/api/systems/turnover` with `Authorization: Bearer <key>` — this is FlightPath's token-authenticated submit endpoint (distinct from the browser-session-authenticated `/api/projects/[id]/turnover` the web page uses, but identical access control: owner/admin/member of the project).
4. Poll `GET {flightpathUrl}/api/systems/turnover/{id}` (same bearer auth) every few seconds until the run reaches a terminal status, printing progress the way `gh run watch` does for CI.

There is **no auto-invoke trigger** for this skill (unlike `notify-release`, which fires after a push) — turnover submission is always an explicit, deliberate action a developer takes, not something that should happen silently as a side effect of `git push`.

**Security note:** the key is a personal bearer token equivalent in power to whatever DB access the developer already has via FlightPath (owner/admin get full DDL, member gets the same access `/turnover`'s web form gives them) — treat it like a password. It lives only in `~/.claude/flightpath-turnover.env` (chmod 600), never in a project's own `.env.local` or committed to git.

## Per-project config

`.claude/flightpath.json` at repo root — **safe to commit** (contains no secret, just an id, so the whole team shares one config instead of each developer re-running `init`):

```json
{
  "projectId": "00000000-0000-0000-0000-000000000000",
  "flightpathUrl": "https://flightpath.cancerfree.io"
}
```

## Shared credential

`~/.claude/flightpath-turnover.env` (created once per machine, not per project, chmod 600):

```
FLIGHTPATH_TURNOVER_KEY="tvk_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

Generated on FlightPath's `/turnover` page, "API Key" section — self-service, no admin approval, full key shown exactly once at creation. If it's ever lost or compromised, revoke it there and generate a new one.

## Procedure — main invocation (submit + watch)

1. **Read config**: `.claude/flightpath.json` in cwd. Missing → tell the user to run `/turnover-submit init` first, stop.
2. **Read credential**: `~/.claude/flightpath-turnover.env`. Missing `FLIGHTPATH_TURNOVER_KEY` → tell the user to run `/turnover-submit setup-env` first, stop.
3. **Resolve the SQL**: if the argument is a path to an existing file, read its contents; otherwise treat the argument itself as the SQL text (supports both `/turnover-submit db/migrations/add_col.sql` and `/turnover-submit "ALTER TABLE foo ADD COLUMN bar text;"`).
4. **`--dry-run`**: print the resolved project id, flightpathUrl, and the SQL that would be sent — do NOT actually POST. Useful for checking config/credential are wired up before trusting a real submission.
5. **`--status <runId>`**: skip submission entirely, jump straight to step 7's polling loop for the given run id (for checking on something submitted earlier, e.g. in a previous session).
6. **Submit**: `POST {flightpathUrl}/api/systems/turnover` with header `Authorization: Bearer <key>`, JSON body `{ "projectId": <from config>, "sql": <resolved SQL> }`. On success (201), print the returned `id` and initial `status` (`"queued"`). See Failure modes below for non-2xx handling.
7. **Poll for completion**: `GET {flightpathUrl}/api/systems/turnover/{id}` with the same bearer header, every 5 seconds. Print a short progress line each poll while status is `queued` or `running` (e.g. `⏳ 排隊中...` / `⏳ 執行中...`) — don't spam identical lines every single poll if nothing changed; a single overwritten status line is fine. Stop polling and report the final result when status becomes:
   - `success` → `✅ 執行成功`（附 `applied_at`；若 `backup_ref` 非空，列出備份了哪些 table，並提醒可在 FlightPath 的 turnover 詳情頁做 rollback）
   - `failed` → `❌ 執行失敗：<error_message>`
   - `rolled_back` → `↩️ 已回復`（正常不會在提交後立刻看到這個狀態，出現通常代表這筆 run 是被重新查詢的舊紀錄）
8. **Timeout**: if still `queued`/`running` after ~3 minutes of polling (the worker cron runs every 5 minutes, so this can legitimately happen under load), stop polling and tell the user: `仍在排隊/執行中，可稍後用 /turnover-submit --status <runId> 再查，或到 {flightpathUrl}/turnover/{runId} 看`.

## `/turnover-submit init` — bootstrap a project

Run in the project's repo root.

1. Confirm cwd has `.git` or `package.json` (otherwise wrong directory).
2. If `.claude/flightpath.json` already exists, report it and exit — don't overwrite silently.
3. Ask the user for their FlightPath project's id or URL (they can find it by opening the project's page on FlightPath — the id is in the URL, `https://flightpath.cancerfree.io/projects/<id>`). Accept either the bare UUID or the full URL and extract the UUID from it.
4. Write `.claude/flightpath.json` with that `projectId` and `"flightpathUrl": "https://flightpath.cancerfree.io"`.
5. Check `.gitignore`: if it has a bare `.claude/` line (ignoring the whole directory), change it to `.claude/*` and add `!.claude/flightpath.json` right after, so the config survives being committed (mirrors how `notify-release init` handles its own config file). If `.claude/` isn't gitignored at all, no change needed.
6. Report done, suggest committing `.claude/flightpath.json` so the rest of the team doesn't need to repeat this step.

## `/turnover-submit setup-env` — one-time personal key setup

Only needed once per machine, not per project.

1. Check if `~/.claude/flightpath-turnover.env` already has `FLIGHTPATH_TURNOVER_KEY`. If yes, report and exit.
2. Tell the user: open `https://flightpath.cancerfree.io/turnover`, find the "API Key" section, create a new key (any label), copy the full key — it's shown exactly once.
3. Ask them to paste it.
4. Write `~/.claude/flightpath-turnover.env` with `FLIGHTPATH_TURNOVER_KEY="<pasted value>"`, `chmod 600`.
5. Offer to run a `--dry-run` submission to confirm everything is wired up (needs `init` to have been run too, in some project).

## Failure modes

| Symptom | Cause | What to do |
|---|---|---|
| `.claude/flightpath.json` missing | Project not yet bootstrapped | Run `/turnover-submit init` |
| `~/.claude/flightpath-turnover.env` missing / no `FLIGHTPATH_TURNOVER_KEY` | Machine not yet bootstrapped | Run `/turnover-submit setup-env` |
| `401 UNAUTHORIZED`, `"Missing or malformed Authorization header"` | Env file has a malformed/empty value | Re-run `setup-env`, check the file's quoting |
| `401 UNAUTHORIZED`, `"Invalid or revoked key"` | Key was revoked on the `/turnover` page, or never existed | Generate a new key there, re-run `setup-env` |
| `404 NOT_FOUND`, `"Project not found"` | `.claude/flightpath.json`'s `projectId` is wrong/stale | Re-run `init` with the correct id |
| `403 FORBIDDEN` | The key's owner isn't owner/admin/member on this project | Ask a project owner/admin to add you as a member on FlightPath |
| `422 VALIDATION_ERROR` | Empty SQL, or `projectId` isn't a valid UUID (corrupt config) | Check the SQL argument isn't empty; re-run `init` if the config looks wrong |
| `500 DB_ERROR` on submit | Transient FlightPath-side error, not a problem with the submitted SQL | Retry; if it persists, check FlightPath's own status |
| Poll never leaves `queued` | Worker cron runs every 5 minutes — a brief queue wait is normal | Wait a bit longer, or use `--status` later; if stuck 15+ minutes, flag to a FlightPath admin |
| Submitted successfully but the DDL itself was wrong | Turnover has no review gate (v1) — it runs whatever SQL is submitted | Fix the SQL and submit again; if it already partially applied, check whether `backup_ref` lets you roll back on the FlightPath detail page first |

## Anti-patterns

- Don't cache/reuse a run id across unrelated submissions — each `/turnover-submit` call is a new run, get the id fresh from the submit response.
- Don't put `FLIGHTPATH_TURNOVER_KEY` in a project's own `.env.local` or any file that gets committed — it lives in `~/.claude/flightpath-turnover.env` only, exactly like `notify-release`'s bot token.
- Don't silently retry a failed submission with the same SQL — DDL that failed partway may have left partial state (see the `backup_ref`/rollback note in Failure modes); surface the failure and let the developer decide, don't auto-resubmit.
- Don't fall back to constructing a browser deep-link as a substitute for actually calling the API — if the token endpoint is erroring, surface the error (see Failure modes) rather than telling the user to "just use the web form instead" as if that's this skill working.
