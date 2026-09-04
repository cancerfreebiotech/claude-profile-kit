---
name: litellm-usage
description: Report a user's LiteLLM (ai-stack, cancerfree-arm-free/oci2) usage — calls, tokens, spend by model, and error breakdown for failures. Use when asked to "查一下 XX 的用量/token/model/錯誤" for a LiteLLM user, or to compare usage across the known users (justin, po, davie, walt).
---

# LiteLLM usage report

Runs against the `ai-stack` LiteLLM deployment on this host (cancerfree-arm-free / oci2.cancerfree.io). All queries go through the LiteLLM postgres container — no credentials needed beyond `sudo docker exec`.

## Arguments

Parse from the invocation: one or more people (by first name or full email) and optionally a time window (default `24 hours`, e.g. "過去 3 天" → `3 days`). "all" or no name given means all four known users.

## Known users

Each person has many virtual keys (`key_alias` gets a new one per login/session), so always match by prefix:

| short name | key_alias prefix |
|---|---|
| justin | `user-justin.lee%` |
| po | `user-pohan.chen%` |
| davie | `user-davie.dai%` |
| walt | `user-walt.tsai%` |

For a name not in this table, ask the user for the email, or try `user-<given-name>%` against `metadata->>'user_api_key_alias'` and confirm it matched something before reporting.

## Query 1 — summary (calls / success / fail / tokens / spend)

```bash
sudo docker exec ai-stack-litellm-db-1 psql -U litellm -d litellm -c "
SELECT
  CASE
    WHEN \"metadata\"->>'user_api_key_alias' ILIKE 'user-justin.lee%' THEN 'justin'
    WHEN \"metadata\"->>'user_api_key_alias' ILIKE 'user-pohan.chen%' THEN 'po'
    WHEN \"metadata\"->>'user_api_key_alias' ILIKE 'user-davie.dai%' THEN 'davie'
    WHEN \"metadata\"->>'user_api_key_alias' ILIKE 'user-walt.tsai%' THEN 'walt'
  END AS person,
  count(*) AS calls,
  sum(CASE WHEN status='success' THEN 1 ELSE 0 END) AS ok,
  sum(CASE WHEN status='failure' THEN 1 ELSE 0 END) AS fail,
  sum(total_tokens) AS tokens,
  round(sum(spend)::numeric,4) AS spend_usd
FROM \"LiteLLM_SpendLogs\"
WHERE \"startTime\" >= now() - interval '24 hours'
  AND (\"metadata\"->>'user_api_key_alias' ILIKE 'user-justin.lee%'
    OR \"metadata\"->>'user_api_key_alias' ILIKE 'user-pohan.chen%'
    OR \"metadata\"->>'user_api_key_alias' ILIKE 'user-davie.dai%'
    OR \"metadata\"->>'user_api_key_alias' ILIKE 'user-walt.tsai%')
GROUP BY person
ORDER BY calls DESC;
"
```

Adjust the `interval` and the `ILIKE` filters to match the requested people/window; drop unwanted people from both the CASE and the WHERE.

## Query 2 — per-model token breakdown (for a single named person)

```bash
sudo docker exec ai-stack-litellm-db-1 psql -U litellm -d litellm -c "
SELECT model, count(*) AS calls, sum(prompt_tokens) AS prompt_tok, sum(completion_tokens) AS completion_tok, sum(total_tokens) AS total_tok, round(sum(spend)::numeric,4) AS spend_usd
FROM \"LiteLLM_SpendLogs\"
WHERE \"startTime\" >= now() - interval '24 hours'
  AND \"metadata\"->>'user_api_key_alias' ILIKE 'user-<name>%'
  AND status='success'
GROUP BY model
ORDER BY total_tok DESC;
"
```

Model names carry their provider prefix as actually logged (e.g. `anthropic/hoshi-agent`, `openai/claude-sonnet-4-6`, `openai/grok-4.6`) — this is NOT always the same string as the `model_name` alias the caller requested (LiteLLM logs the resolved deployment, especially after a fallback). Report token counts with this in mind: heavy `hoshi-agent`/`grok-4.6` token volume with $0 spend is normal (self-hosted/subscription backends have no per-token price configured).

## Query 3 — error breakdown for a named person

```bash
sudo docker exec ai-stack-litellm-db-1 psql -U litellm -d litellm -c "
SELECT model, count(*) AS fail_count, max(\"startTime\") AS last_seen
FROM \"LiteLLM_SpendLogs\"
WHERE \"startTime\" >= now() - interval '24 hours'
  AND \"metadata\"->>'user_api_key_alias' ILIKE 'user-<name>%'
  AND status='failure'
GROUP BY model ORDER BY fail_count DESC;
"
```

Then, for each model with a nonzero count, pull one representative error message to classify it:

```bash
sudo docker exec ai-stack-litellm-db-1 psql -U litellm -d litellm -c "
SELECT \"startTime\", \"metadata\"->'error_information'->>'error_message' AS err
FROM \"LiteLLM_SpendLogs\"
WHERE model='<model>' AND \"metadata\"->>'user_api_key_alias' ILIKE 'user-<name>%'
  AND status='failure'
ORDER BY \"startTime\" DESC LIMIT 3;
"
```

Common error classes you'll see, and how to describe them (don't just dump the raw JSON):
- `litellm.RateLimitError ... Limit type: tokens, Remaining: 0` — the per-virtual-key TPM limit was hit (check `LiteLLM_VerificationToken.tpm_limit`/`rpm_limit` for that key_alias). Often a client retry-storm rather than genuine sustained volume — note if many failures cluster in a short burst.
- `invalid_request_error` (e.g. `clear_thinking_...` without `thinking` enabled, or `tool_choice` set with no `tools`) — malformed request from the calling client/tool, not an infra problem. Fallbacks don't help since the same bad request gets retried against the fallback deployment too.
- `Connect call failed` / `ConnectionRefusedError` / `No route to host` — network/service-down issue on this host or a downstream node; worth checking `systemctl status` for the relevant shim and `iptables -L -n` for the docker bridge whitelist if it's "No route to host" specifically.
- `Hosted_vllmException - Cannot connect to host localhost:<port>` on `hoshi-agent`/`claude-proxy-qwen3.6` — this "localhost" is thor1's OWN loopback (nested LiteLLM: this host calls thor1's LiteLLM at `100.116.219.52:4000`, which internally calls thor1's local vLLM) — check `curl http://100.116.219.52:4000/health/readiness` before assuming this host's config is wrong.

## Output format

Give: a summary table (Query 1), then per person if a single person was named — a token-by-model table (Query 2) sorted by token volume, then an error table (Query 3) with each error classified in one line using the categories above. Flag anything that's new/changed since a prior check in this conversation if there's context for that; otherwise just report current numbers plainly.
