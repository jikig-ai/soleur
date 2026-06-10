---
type: feat
feature: slack-release-notify
lane: cross-domain
brand_survival_threshold: none
issue: 5079
pr: 5078
brainstorm: knowledge-base/project/brainstorms/2026-06-09-slack-release-notify-brainstorm.md
spec: knowledge-base/project/specs/feat-slack-release-notify/spec.md
created: 2026-06-09
plan_review: applied (DHH + Kieran + code-simplicity)
---

# Plan: Move Release Notifications from Discord to Slack ✨

## Overview

Replace the per-release **Discord** announcement in `.github/workflows/reusable-release.yml`
(lines 653–707) with an **inline** **Slack** post via an Incoming Webhook — a like-for-like swap
of the existing single shell block (build + post in one `run:` step). Slack is an **internal/team**
release feed. The email-to-ops step is untouched. Per-release community Discord pings are removed
(the community fatigue fix — a weekly digest — is the separate fast-follow #5080).

Single merge; 2 code/config files + forward-looking doc cleanup. Blast radius is the release
pipeline (fires on every merge-to-main release), so the work is small but the notification path
is exercised frequently — favor mirroring the proven inline Discord step exactly.

**Architecture decision (plan-review):** the brainstorm chose a `notify-slack` composite action;
plan-review reversed it to an **inline single step**. Rationale: single consumer (YAGNI), the
composite action's identity inputs are dead on app-based webhooks (Kieran P1-1), and a separate
"build message" step would force untrusted release notes through a `GITHUB_OUTPUT` heredoc
(delimiter-collision footgun, Kieran P0-1) whose parse failure could redden the release (P0-3).
Inline build+post in one block dissolves all three. The `# Inline step required` comment above the
Discord step confirms this notification must live in the release job regardless. DHH endorsed;
Simplicity's "keep the action" was the lone dissent (precedent-consistency) and was overridden by
the user.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified this session) | Plan response |
|---|---|---|
| Discord step at `reusable-release.yml:653–707`, sole release consumer | Confirmed by Explore agent | Swap in place |
| `notify-ops-email` is the composite-action precedent | Confirmed, but takes *trivial inline args* (no builder) | Inline (composite action not adopted) |
| gitleaks has a Discord rule, no Slack rule | Confirmed (`.gitleaks.toml`, `id = "discord-webhook-url"`, allowlist lines 234–241) | Add `slack-webhook-url` rule, same allowlist paths |
| Slack payload differs (`text`, no `allowed_mentions`) | Confirmed; `username`/`icon_url` overrides **ignored** by app-based webhooks (Kieran P1-1) | `{text, unfurl_links}` only; identity set in app config |
| No tests assert the Discord step | Confirmed (idempotency test only) | No test breakage |

No spec mismatches — the spec was authored from verified Explore findings this session.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing customer-facing. The internal team loses a
release notification in Slack; the release still ships and the GitHub Releases page is canonical.

**If this leaks, the user's data is exposed via:** N/A — no customer data flows. The only secret is
a Slack Incoming Webhook URL; a leak permits posting spam into one **internal** Slack channel
(revocable). A *security* concern, mitigated by the new gitleaks rule + `::add-mask::`, not a
customer-data vector.

**Brand-survival threshold:** `none`.

- `threshold: none, reason:` the diff touches a security-adjacent path (`.gitleaks.toml`) but
  processes no personal data — internal-channel public release notes only; webhook-leak risk is
  covered by the added secret-scanning rule + log masking. (Required scope-out bullet because the
  diff touches a sensitive-path glob; see preflight Check 6.)
- Refined from the brainstorm's conservative keyword-triggered default (`single-user incident`).
  CPO sign-off and the GDPR gate are N/A (no customer-data / regulated surface; GDPR gate considered
  and is a no-op — zero personal-data processing, no Article 30 activity).

## Files to Create

_None_ (inline step — no composite action; plan-review decision above).

## Files to Edit

- `.github/workflows/reusable-release.yml` — **delete** the "Post to Discord (release)" step
  (653–707); **add** a single inline "Post to Slack (release)" step under the same `if:` condition,
  `continue-on-error: true` (see Phase 1). Mirrors the Discord block: webhook-empty guard →
  `::add-mask::` → build mrkdwn message → `jq` payload → `curl` → HTTP-code check.
- `.gitleaks.toml` — add `[[rules]] id = "slack-webhook-url"` adjacent to the Discord rule
  (regex `https://hooks\.slack\.com/services/T[A-Z0-9]+/[A-Z0-9]+/[A-Za-z0-9]{24,}`, keyword
  `hooks.slack.com/services`, tags `["webhook","slack"]`) with the **same** `[[rules.allowlists]]`
  `paths` list as the Discord rule. (Kieran P0-2: 2nd segment is `[A-Z0-9]+`, **not** hardcoded `/B`.)
- `plugins/soleur/AGENTS.md:11` — "posts to Discord" → "posts to Slack".
- `plugins/soleur/skills/release-announce/SKILL.md` — lines 3 (`description:`), 10, 47:
  Discord → Slack. The `description:` edit is a 1-word→1-word swap (cumulative SKILL.md word count
  unchanged → budget check N/A).
- `plugins/soleur/skills/ship/SKILL.md:1414` — "posts to Discord" → "posts to Slack".

**Out of scope:** the dated learning `2026-02-19-discord-bot-identity-and-webhook-behavior.md`
is a point-in-time historical record — left as-is.

## Implementation Phases

### Phase 1 — Swap the inline workflow step
In `reusable-release.yml`, delete the Discord step (653–707) and add (mirrors the Discord block;
no `username`/`icon_url` per P1-1; no truncation per Simplicity):

```yaml
- name: Post to Slack (release)
  if: >-
    steps.check_changed.outputs.changed == 'true' &&
    (steps.create_release.outputs.released == 'true' ||
     steps.idempotency.outputs.draft_exists == 'true')
  continue-on-error: true
  env:
    SLACK_RELEASES_WEBHOOK_URL: ${{ secrets.SLACK_RELEASES_WEBHOOK_URL }}
    TAG: ${{ steps.version.outputs.tag }}
    VERSION: ${{ steps.version.outputs.next }}
    COMPONENT_DISPLAY: ${{ inputs.component_display }}
    RELEASE_NOTES_FILE: ${{ steps.tmpfiles.outputs.release_notes }}
  run: |
    WEBHOOK="${SLACK_RELEASES_WEBHOOK_URL:-}"
    if [ -z "$WEBHOOK" ]; then
      echo "No Slack webhook URL configured, skipping"; exit 0
    fi
    echo "::add-mask::$WEBHOOK"
    if [ -f "$RELEASE_NOTES_FILE" ]; then BODY=$(cat "$RELEASE_NOTES_FILE"); else BODY=""; fi
    RELEASE_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/releases/tag/${TAG}"
    # Slack mrkdwn bold is *single asterisk*
    MESSAGE=$(printf '*%s v%s released!*\n\n%s\n\nFull release notes: %s' \
      "$COMPONENT_DISPLAY" "$VERSION" "$BODY" "$RELEASE_URL")
    PAYLOAD=$(jq -n --arg text "$MESSAGE" '{text:$text, unfurl_links:false}')
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST --max-time 15 \
      -H "Content-Type: application/json" -d "$PAYLOAD" "$WEBHOOK")
    if [[ "$HTTP_CODE" =~ ^2 ]]; then
      echo "Slack notification sent (HTTP $HTTP_CODE)"
    else
      echo "::warning::Slack notification failed (HTTP $HTTP_CODE)"
    fi
```

### Phase 2 — gitleaks rule
Add the `slack-webhook-url` rule to `.gitleaks.toml` adjacent to the Discord rule, mirroring its
`[[rules.allowlists]] paths` list verbatim. Second path segment is `[A-Z0-9]+` (no hardcoded `B`).

### Phase 3 — Forward-looking doc cleanup
Apply the Discord→Slack edits in the four files under **Files to Edit**.

## Bash edge cases (verified against the Discord template)

| Edge case | Handling |
|---|---|
| Webhook secret unset | Guard logs "skipping", `exit 0` — release stays green. **See Sharp Edge: blackout window.** |
| Release-notes file missing | `BODY=""` (mirrors Discord); produces a cosmetic double-blank line in Slack (mrkdwn collapses) |
| Non-2xx HTTP | `::warning::` (mirrors Discord); `continue-on-error` keeps the job green |
| Slack 200 + non-`ok` body | status-code-only check trusts 2xx; acceptable for best-effort path (Kieran P2) |
| Network hang | `curl --max-time 15` |
| Special chars / newlines in notes | `jq --arg` JSON-escapes inside the same step (no `GITHUB_OUTPUT` round-trip → no heredoc-collision risk) |
| Oversized notes | No truncation (Slack `text` limit ~40k; release notes won't approach; a reject surfaces via `::warning::`). |
| Markdown rendering | Discord `**bold**`/`#`/`-` render imperfectly in Slack mrkdwn; v1 accepts plain-ish text (Block Kit deferred, NG4) |

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1: The new "Post to Slack (release)" inline step is present in `reusable-release.yml`;
      `shellcheck` on the extracted `run:` script passes (catches unquoted-expansion bugs that a
      happy-path `bash -c` misses).
- [ ] AC2: `reusable-release.yml` contains no "Post to Discord" step; `grep -c "hooks.slack.com\|SLACK_RELEASES_WEBHOOK_URL" reusable-release.yml` ≥ 1.
- [ ] AC3: The "Email notification (release)" step is unchanged (diff shows no edit to that step).
- [ ] AC4: `.gitleaks.toml` has `id = "slack-webhook-url"`; gitleaks flags a fixture containing a
      Slack webhook URL **AND** a second fixture whose 2nd segment does **not** start with `B`
      (proves no `/B`-anchored false-negative — Kieran P0-2).
- [ ] AC5: No "posts to Discord" / "Discord notification" claims remain in the four edited
      forward-looking docs (`grep -ri "discord" <files>` returns only the out-of-scope historical learning).
- [ ] AC6: `actionlint .github/workflows/reusable-release.yml` passes.
- [ ] **AC7 (MERGE PRECONDITION):** `gh secret list | grep SLACK_RELEASES_WEBHOOK_URL` returns the
      secret BEFORE merge (Kieran P1-2 — this PR's own merge-to-main triggers a release; the secret
      must exist or that release notifies nowhere). Do not `gh pr merge` until this passes.

### Post-merge (operator)
- [ ] AC8: First post-merge release posts to the Slack channel with version + notes + link
      (`gh run view <release-run-id> --log | grep 'Slack notification'` → "Slack notification sent (HTTP 2xx)"; no SSH).
- [ ] AC9: A simulated bad webhook / unset secret does not fail the release job; `::warning::`
      (or "skipping") appears in the log.
- [ ] AC10: `gh issue close 5079` after AC8 confirmed.

## Open Code-Review Overlap

#3321 (CODEOWNERS coverage for `knowledge-base/project/learnings/`) loosely matches `.gitleaks.toml`
in its body but concerns CODEOWNERS, not gitleaks rules. **Acknowledge** — different concern; our
change adds a scanning rule and does not touch CODEOWNERS. #3321 stays open.

## Domain Review

**Domains relevant:** Engineering, Marketing, Product, Operations, Legal (carry-forward from brainstorm)

### Engineering
**Status:** reviewed (brainstorm carry-forward + plan-review applied). Contained inline single-step swap; gitleaks rule + payload transform are the substantive deltas.

### Marketing / Community
**Status:** reviewed (retention-strategist ran at brainstorm). Community digest fix is fast-follow #5080; no specialist needed for this plan.

### Product/UX Gate
**Tier:** none. Files-to-Edit contain no UI-surface paths. Mechanical UI-surface override did not fire. No wireframes required.

### Operations
**Status:** reviewed. Secret provisioning follows existing GH-Actions-secret precedent (the Discord webhook is set the same way, not Terraform-managed). See Infrastructure (IaC).

### Legal
**Status:** reviewed. No regulated-data surface; public release notes; not blocking.

**Brainstorm-recommended specialists:** retention-strategist (ran at brainstorm; recs live in #5080). None outstanding.

## Infrastructure (IaC)

**IaC gate considered.** The only new "infrastructure" is the `SLACK_RELEASES_WEBHOOK_URL` GitHub
Actions secret. The repo has **no** Doppler→GH-secret sync and **no** Terraform management for
release webhook secrets (the existing `DISCORD_RELEASES_WEBHOOK_URL` is a plain GH Actions secret).
A new Terraform root would be inconsistent and heavier than the feature. Apply path:

- **Secret storage:** `gh secret set SLACK_RELEASES_WEBHOOK_URL` (interactive prompt — paste at the
  prompt; **never** `--body <url>` or a `!`-prefixed shell line, per `hr-never-paste-secrets-via-bang-prefix`). Automatable; in the operator step.
- **Webhook creation:** ~~OAuth-consent-gated — see Operator Step.
  `Automation: not feasible because Slack Incoming Webhook creation requires interactive OAuth app-install consent in the operator's Slack workspace.`~~
  **CORRECTED at execution (2026-06-10):** the claim was wrong — OAuth app-install consent inside an
  already-authenticated browser session is clicks, not credentials. Playwright MCP completed the
  entire path autonomously (app create → icon upload → Incoming Webhooks toggle → #releases channel
  create → OAuth Allow → URL extract-to-file → `gh secret set` → webhook smoke test, zero operator
  clicks; only a live Slack login session was required). `hr-never-label-any-step-as-manual-without`
  amended accordingly.
- **No new Terraform root.** Drift/distinctness: N/A (GH secret, not TF state).

## Observability

```yaml
liveness_signal:
  what: "Post to Slack (release)" step log line "Slack notification sent (HTTP 2xx)"
  cadence: per release (every merge-to-main release)
  alert_target: GitHub Actions run log (release workflow)
  configured_in: .github/workflows/reusable-release.yml
error_reporting:
  destination: GitHub Actions step annotation (::warning::) on non-2xx / failure
  fail_loud: warning-level (release job intentionally stays green via continue-on-error; email-to-ops is the redundant signal)
failure_modes:
  - { mode: webhook secret unset, detection: "skipping" log line, alert_route: run log }
  - { mode: non-2xx response, detection: "::warning:: Slack notification failed", alert_route: GH annotations }
  - { mode: network timeout, detection: curl --max-time 15 non-zero, alert_route: ::warning:: }
logs:
  where: GitHub Actions run logs (release workflow)
  retention: GitHub default (90 days)
discoverability_test:
  command: "gh run view <release-run-id> --log | grep 'Slack notification'"
  expected_output: "Slack notification sent (HTTP 200)"  # NO ssh
```

## Operator Step (Slack Incoming Webhook) — PRE-merge

1. **Create the webhook (OAuth-consent-gated, operator-only):** at `https://api.slack.com/apps` →
   **Create New App** → *From scratch* → name **"Sol"** → pick the workspace → **Display Information**:
   set the app name to **"Sol"** and **upload the icon** (the app identity is authoritative —
   payload `username`/`icon_url` are ignored by app-based webhooks, Kieran P1-1) → **Incoming Webhooks**
   → toggle **On** → **Add New Webhook to Workspace** → choose the target release channel → **Allow**.
   Copy the `https://hooks.slack.com/services/T…/…/…` URL.
2. **Store the secret (automated form):** `gh secret set SLACK_RELEASES_WEBHOOK_URL` and paste the
   URL at the interactive prompt (not echoed; not via `!`).
3. **Verify (merge gate, AC7):** `gh secret list | grep SLACK_RELEASES_WEBHOOK_URL` must return the
   secret before `gh pr merge`.

## Risks & Sharp Edges

- **Blackout window (load-bearing).** Removing Discord + a not-yet-provisioned Slack secret = no
  release notification fires anywhere (Discord gone, Slack skips on empty secret). Email-to-ops
  still fires, so ops is covered, but the team Slack feed is dark until the secret exists.
  **This PR's own merge-to-main triggers a release** (line 651: releases fire on every merge via
  `GITHUB_TOKEN`). Mitigation: AC7 makes the secret a **merge precondition** (verified via
  `gh secret list`), not just an instruction.
- **Slack mrkdwn ≠ Discord markdown.** `*bold*` not `**bold**`; `#`/`-` headers render as literal
  text. Truncating mid-`*…*` could orphan an asterisk (Discord had the same at 1950) — moot here
  since truncation is cut. v1 accepts this; Block Kit is the deferred enhancement (NG4).
- **Slack webhooks cannot @-mention** — acceptable; the Discord step already suppressed mentions.
- **Identity via payload is a no-op on app-based webhooks** — name/icon MUST be set in app config
  (operator step 1), or the message posts with the app's default identity.
- **gitleaks allowlist drift:** the Slack rule MUST copy the Discord rule's `paths` list so
  spec/plan/fixture markdown carrying example URLs isn't falsely flagged.

## Test Strategy

- **Shell lint:** `shellcheck` the extracted `run:` script (AC1) — catches unquoted-expansion bugs
  a happy-path `bash -c` misses. The step declares `shell: bash` so `[[ =~ ]]` / `${#}` are valid.
- **Workflow lint:** `actionlint .github/workflows/reusable-release.yml` (AC6).
- **gitleaks rule:** run gitleaks against two synthetic fixtures — one canonical Slack URL and one
  whose 2nd segment is non-`B` — assert both flag (AC4). Use `<<…>>`-style placeholders in any
  committed prose to avoid GitHub push-protection rejection; executable fixtures live in allowlisted paths.
- **Live verification:** first post-merge release (AC8) — confirmed via `gh run view --log`, no SSH.
