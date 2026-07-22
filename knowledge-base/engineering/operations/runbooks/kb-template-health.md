---
title: kb-template health probe runbook
date: 2026-06-05
owners: engineering/ops
applies_to:
  - apps/web-platform/server/inngest/functions/cron-kb-template-health.ts
related_issues: [3413, 3399, 3401]
brand_survival_threshold: single-user incident
---

# kb-template health probe runbook

**Before debugging the probe code path, check Better Stack
`inngest-heartbeat` last_alive_at** — if >2 min ago, this issue is likely a
substrate-down false-positive (cross-check sibling
`cron-github-app-drift-guard` / `cron-oauth-probe` monitors). When the
Inngest substrate is healthy but this monitor pages alone, the cause is in
the handler logic or a genuine template drift below.

Triage for the hourly kb-template health probe at
`apps/web-platform/server/inngest/functions/cron-kb-template-health.ts`. The
handler mints an installation-scoped Octokit via `createProbeOctokit()` (in
`apps/web-platform/server/github/probe-octokit.ts` — no PAT, no JWT-mint),
calls `GET /repos/{owner}/{repo}` with `owner=KB_TEMPLATE_OWNER` /
`repo=KB_TEMPLATE_NAME` (from `server/github-app.ts`), and asserts the
documented success shape: **`is_template === true` AND `private === false`**.

## Why this probe exists

Every user-account "Create Project" routes through `jikig-ai/kb-template`'s
`/generate` endpoint (user-installation tokens cannot call
`POST /user/repos` — that returns 403; `/generate` is the only path that
accepts them). The template **MUST be public AND `is_template`** — a
cross-account `/generate` call from a user-installation token returns 404
against a private or non-template repo. If an operator deletes/renames/
privatizes the template or drops its `is_template` flag, every user's
onboarding "Create Project" returns an opaque 404/422 (the exact #3401
failure). This probe detects that drift within 60 minutes instead of
post-hoc via a user-filed Sentry error.

## Failure-label families

A failure surfaces under one of two label families — the title prefix tells
you which:

- `[ops/kb-template-broken] kb-template health probe fired` — **template
  drift detected, user-impacting.** One of:
  - `repo_not_found` — `GET /repos` returned 404. The template was deleted,
    renamed, or made private (404 is GitHub's response for both
    not-found and private-without-access).
  - `is_template_dropped` — the repo exists and is readable, but
    `is_template !== true`. Someone un-marked it as a template in the
    GitHub UI.
  - `template_private` — `is_template === true` but `private !== false`.
    The repo was flipped to private.
- `[ci/guard-broken] kb-template health probe malfunctioned` — **the probe
  itself could not assert** (NOT a template-drift signal). Modes:
  - `response_not_object` — `GET /repos` returned a non-object body.
  - `response_missing_fields` — the body is an object but is missing the
    boolean `is_template` or `private` field (an upstream GitHub API shape
    change).
  - `github_api_http` — a non-404 HTTP error from `GET /repos`.
  - `github_api_network` — `GET /repos` threw a network-class error, or the
    probe step itself threw.

**Important:** `ci/guard-broken` does NOT mean user "Create Project" is
broken — it means the probe couldn't get a clean answer. Triage the probe,
not the template, for those modes. `ops/kb-template-broken` is the
user-impacting family.

## Alert response

### 1. Verify the live template state (no dashboard eyeballing)

```bash
gh repo view jikig-ai/kb-template --json isTemplate,visibility
```

Expected healthy output:

```json
{ "isTemplate": true, "visibility": "public" }
```

Map the result to the failure mode:

| `gh repo view` result | Failure mode | Remediation |
|---|---|---|
| Command errors / repo not found | `repo_not_found` | The template was deleted or renamed — see remediation below. |
| `"isTemplate": false` | `is_template_dropped` | **Re-mark as template** (below). |
| `"visibility": "private"` (or `"internal"`) | `template_private` | **Make public** (below). |
| Healthy (`isTemplate:true`, `visibility:public`) but issue still open | guard transient (likely `github_api_network`/`github_api_http`) | No template change needed; confirm the next hourly tick auto-closes the issue. |

### 2. Remediation

All three remediations are GitHub-UI / `gh`-driven on `jikig-ai/kb-template`:

- **Re-mark as template** (`is_template_dropped`):
  ```bash
  gh repo edit jikig-ai/kb-template --template
  ```
  (or GitHub UI → repo Settings → check "Template repository".)
- **Make public** (`template_private`):
  ```bash
  gh repo edit jikig-ai/kb-template --visibility public --accept-visibility-change-consequences
  ```
  (or GitHub UI → repo Settings → Danger Zone → Change visibility → Public.)
- **Un-rename / restore** (`repo_not_found`): if the repo was renamed,
  rename it back to `kb-template`:
  ```bash
  gh repo rename kb-template --repo jikig-ai/<current-name>
  ```
  If it was deleted, restore it from GitHub's deleted-repo recovery window
  (Settings → restore, available ~90 days) `[human-only: GitHub UI;
  repo-restore has no public REST endpoint]`, or re-create from a clone.

  Note: `KB_TEMPLATE_OWNER` / `KB_TEMPLATE_NAME` are env-overridable
  (`server/github-app.ts`). If the template was intentionally moved to a
  new owner/name, set those env vars in Doppler `prd` instead of un-naming
  the repo — the probe and the create flow both read them.

### 3. Verify recovery

The probe self-heals: the next hourly tick re-runs `GET /repos`, sees the
documented success shape, comments "green … Auto-closing", and closes the
open `[ops/kb-template-broken]` / `[ci/guard-broken]` issue. To verify
without waiting an hour, trigger on-demand (see `inngest-server.md`
"On-demand cron trigger (HTTP)" path):

```bash
# Via the allowlisted manual-trigger event:
inngest send cron/kb-template-health.manual-trigger --data '{}'
```

Then confirm the tracking issue auto-closed:

```bash
gh issue list --repo jikig-ai/soleur --state open -L 200 \
  --search 'in:title "kb-template health"' --json number,title
```

An empty list confirms recovery.

## Substrate-down false-positive cross-check

This probe shares the self-hosted Inngest substrate with ~45 other crons.
If the substrate is down, this monitor cannot tick — but a *missing* tick
reds the `inngest-heartbeat` Better Stack monitor, not this probe's issue
surface (the probe only files an issue when it actually RUNS and sees
drift). So:

- **Issue filed + `inngest-heartbeat` healthy** → genuine template drift or
  a guard malfunction. Triage above.
- **No issue + `inngest-heartbeat` red (>2 min stale)** → substrate down;
  the probe isn't running. This is a "guard-itself-dark" failure mode
  tracked by the heartbeat monitor, NOT a kb-template problem. Do not
  remediate the template.
- **Issue filed AND `inngest-heartbeat` red** → check whether the issue is
  stale (filed before the substrate went down). A fresh substrate-down does
  not file a new kb-template issue, so a recent `[ops/kb-template-broken]`
  issue alongside a red heartbeat means the probe ran, saw drift, filed,
  THEN the substrate degraded — treat the template drift as real.

Mirror of the `github-app-drift.md` runbook's same cross-check; the
`cron-github-app-drift-guard` sibling is the structural precedent for this
probe.

## Cross-references

- `github-app-drift.md` — sibling hourly App-integrity probe (same
  issue-handling + leak-tripwire + Sentry-mirror shape).
- `oauth-probe-failure.md` — sibling user-facing OAuth probe.
- `inngest-server.md` — on-demand cron-trigger (HTTP) path.
- Issue #3401 — the user-facing onboarding break this probe pre-empts.
- PR #3399 — routed user-installation repo create through the template
  `/generate` endpoint (the dependency this probe guards).
