# Signed-GET verify steps must tolerate non-JSON bodies

**Date:** 2026-04-15
**Category:** CI / release observability
**Related issues:** #2214, #2215 (shipped together)
**Related PRs:** #2187 (introduced the defect), #2226 (fix)

## Problem

Release workflow run [24411905995](https://github.com/jikig-ai/soleur/actions/runs/24411905995) (web-platform v0.35.11) crashed at the new `Verify deploy script completion` step on the first poll attempt with:

```text
jq: parse error: Invalid numeric literal at line 1, column 5
```

The step polls `https://deploy.soleur.ai/hooks/deploy-status` (a signed GET on adnanh/webhook) and pipes the response body into three `jq -r` calls to extract `exit_code`, `reason`, `tag`. GitHub Actions `run:` blocks use `shell: /usr/bin/bash -e {0}`; any command substitution whose command fails propagates through `-e` and terminates the step.

In this specific release the underlying cause was that the `/hooks/deploy-status` endpoint had not yet been provisioned on the live host — `hcloud_server.web` has `lifecycle { ignore_changes = [user_data] }`, so cloud-init changes from PR #2187 never re-applied. adnanh/webhook returned `Hook not found` (plaintext), `jq` choked on the first character, and `-e` killed the step before the existing `case` retry logic could run.

## Root cause

Two coupled defects, one workflow pattern:

1. **Workflow brittleness (#2214):** Any signed-GET verify step that ingests the response body through `jq` without pre-validating it is JSON will crash on any non-JSON body — not just endpoint-missing. Cloudflare edge errors (HTML 503), webhook listener restarts (connection refused → Cloudflare returns an HTML error page), cold-starts, and auth misconfiguration all produce plaintext/HTML bodies. Under `bash -e`, each of these terminates the step during the first poll instead of retrying.
2. **State-vs-reality drift (#2215):** The `ignore_changes = [user_data]` lifecycle on `hcloud_server.web` means cloud-init changes from feature PRs don't land on existing servers. The `terraform_data.deploy_pipeline_fix` resource bridges that gap via `remote-exec`, but only when `terraform apply` runs. Between a merge that adds a new hook and the operator's next apply, prod runs with the old `hooks.json`.

The two defects combine to produce a fast-crash instead of a graceful 120s timeout with a clear error message.

## Fix

Added a `jq -e .` pre-check before the field parsers:

```yaml
if ! echo "$BODY" | jq -e . >/dev/null 2>&1; then
  echo "Attempt $i/$STATUS_POLL_MAX_ATTEMPTS: HTTP $HTTP_CODE, non-JSON body (endpoint not ready)"
  sleep "$STATUS_POLL_INTERVAL_S"
  continue
fi
EXIT_CODE=$(echo "$BODY" | jq -r '.exit_code // -99')
# ... existing field parsers unchanged
```

The `2>/dev/null` suppresses jq's parse-error output (exit 5), and `-e` is the behavior toggle — valid JSON exits 0, non-JSON (or `null`/`false`) exits non-zero.

Terraform apply (#2215) was a routine re-provisioning — `triggers_replace` already captured the drifted hash (new `cat-deploy-state.sh` + modified `hooks.json.tmpl`), so plain `apply` replaced `deploy_pipeline_fix` without `-replace`.

## Why not alternatives

- **Drop `bash -e` from the step shell:** Disables defensive behavior for every other command (curl, cat, sleep, sed) in the loop. The current incident is scoped to jq; the fix should be too. See `2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md` for why quiet failure-absorption in deploy-adjacent shell is a critical-severity anti-pattern.
- **`set +e` / `set -e` toggling around each `jq -r`:** Brittle — any future maintainer editing the block has to preserve the toggle correctly. Mixes with `continue` semantics.
- **`jq empty` instead of `jq -e .`:** `jq empty` succeeds on any valid JSON including `null`. Combined with the existing `// -99` defaults, a `null` body would yield `EXIT_CODE=-99`, hit the `*)` fast-fail branch, and fail the release — worse than "retry until timeout with a clear non-ready message."

## Edge cases verified (jq 1.8.1, bash 5.x)

| Input | `jq -e .` exit | Outcome |
|---|---|---|
| Valid JSON object (e.g., `{"exit_code":0,...}`) | 0 | passes guard, field parsers run |
| Valid JSON object missing `exit_code` | 0 | passes guard, `// -99` default → `*)` fast-fail (desirable: server-side regression) |
| `null` literal | 1 | retry branch (intentional) |
| Non-JSON plaintext (`Hook not found`) | 5 | retry branch |
| HTML error page | 5 | retry branch |
| Empty body | (pre-existing `[ -z "$BODY" ]` branch) | retry branch |
| Empty JSON object `{}` / `[]` | 0 | passes guard → falls through → `*)` fast-fail |

Note: `{}` and `[]` pass `jq -e .` (their output is truthy), contradicting an early analysis that predicted retry. In practice `cat-deploy-state.sh` never emits empty objects, so this case is theoretical. If it ever became real we'd want fast-fail anyway (server-side regression).

## Pattern to apply elsewhere

Any CI step that polls a JSON-producing endpoint under `bash -e` needs the `jq -e .` guard. Candidates to audit:

- Future release workflow steps that poll observability endpoints
- Any webhook verify step added to `web-platform-deploy.yml` or staging workflows
- Any healthcheck that conditionally parses JSON fields

The pattern:

```bash
if ! echo "$BODY" | jq -e . >/dev/null 2>&1; then
  echo "non-JSON body, retrying"
  sleep "$INTERVAL"
  continue
fi
# ... parse fields
```

Do NOT use `jq empty` here — it's too permissive.

## Session Errors

Captured per AGENTS.md workflow-gate ("Every session error MUST produce either an AGENTS.md rule, a skill instruction edit, or a hook"):

- **Plan filename prescription drift** — plan/tasks.md prescribed the learning as `2026-04-14-...-must-tolerate-non-json.md`, but the actual file was created as `2026-04-15-...-tolerate-non-json-bodies.md` (date bumped mid-session, slug tightened). Review quality-analyst flagged the mismatch. **Recovery:** updated tasks.md to reference the actual filename post-hoc. **Prevention:** plan skill should prescribe directory + topic only, not exact filenames with dates, since dates can drift across session boundaries.
- **Reviewer false-positive on "broken link"** — pattern-recognition-specialist claimed `runtime-errors/2026-02-13-...` was broken; verification via Glob confirmed both directory and file exist. **Recovery:** verified before acting on the finding. **Prevention:** reviewer agent prompts should instruct "before reporting a broken link, verify via Glob/Read" — currently an implicit assumption.
- **Acceptance-criteria checkboxes mixed pre-merge and post-merge actions without distinction** — plan's `## Acceptance Criteria` subsections for #2214/#2215 contained both pre-merge items (workflow edit, commit) and post-merge items (terraform apply, verification of live endpoint) in the same flat list. Review quality-analyst flagged ambiguity. **Recovery:** added `(post-merge action)` / `(ship applies)` suffixes. **Prevention:** plan skill's acceptance-criteria template should separate pre-merge from post-merge items into distinct subsections when a PR has post-merge operator actions.
- **PreToolUse security-reminder hook on YAML edit caused retry** — first Edit of `.github/workflows/web-platform-release.yml` surfaced an advisory reminder about GitHub Actions workflow injection; the edit did not appear to apply on first pass. **Recovery:** grep-verified state, retried; second attempt succeeded. **Prevention:** none — advisory hook is working as designed. When the hook fires, always grep-verify before retrying (already implied, but worth noting).

## References

- `.github/workflows/web-platform-release.yml` — the fixed step.
- `apps/web-platform/infra/server.tf` — `terraform_data.deploy_pipeline_fix`, the bridge that sidesteps `ignore_changes = [user_data]`.
- `knowledge-base/project/learnings/2026-04-06-terraform-data-connection-block-no-auto-replace.md` — `terraform_data` replacement semantics.
- `knowledge-base/project/learnings/2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md` — `agent = true` requirement for provisioner SSH.
- `knowledge-base/project/learnings/runtime-errors/2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md` — justification for keeping `bash -e` and scoping tolerance to specific commands.
- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — signed-GET call pattern and reason taxonomy.
