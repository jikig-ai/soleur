---
feature: slack-release-notify
lane: cross-domain
brand_survival_threshold: none
threshold_note: "Brainstorm used the conservative webhook/secret keyword default (single-user incident); refined to `none` at plan time — internal team channel, public release notes, no customer data/auth/cross-tenant surface. Webhook-leak is a security concern handled by the gitleaks rule + ::add-mask::, not a customer-brand vector."
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-06-09-slack-release-notify-brainstorm.md
created: 2026-06-09
---

# Spec: Move Release Notifications from Discord to Slack

## Problem Statement

Release announcements currently post to the community Discord `#releases` channel via the
"Post to Discord (release)" step in `.github/workflows/reusable-release.yml` (lines 653–707).
The operator wants the per-release feed moved to an **internal Slack channel** (team-facing),
and Discord per-release posts removed. Separately, a community member muted `#releases` due to
notification volume — addressed by a deferred weekly-digest fast-follow, not this spec.

## Goals

- G1: Per-release announcements post to an internal Slack channel via an Incoming Webhook.
- G2: The Discord per-release step is removed (true "move", Slack-only).
- G3: Email-to-ops release notification is unchanged.
- G4: The Slack webhook secret is masked in CI logs and caught by secret scanning.
- G5: Release pipeline stays green even if the Slack post fails (non-blocking).

## Non-Goals

- NG1: Weekly community release digest (separate fast-follow issue).
- NG2: Migrating the *other* Discord consumers (community-monitor, content-publisher,
  weekly-analytics crons use `DISCORD_WEBHOOK_URL` for community content — out of scope).
- NG3: Slack App / bot-token / OAuth integration (Incoming Webhook only).
- NG4: Block Kit rich formatting (plain `text` for v1; later enhancement).
- NG5: Any UI surface (pure CI/infra — no wireframes).

## Functional Requirements

> **As-built amendment (plan-review pivot).** FR1/FR2 originally specified a `notify-slack`
> composite action. Plan-review reversed this to an **inline step** in `reusable-release.yml`
> (single consumer / YAGNI; `username`/`icon_url` identity inputs are dead on app-based
> webhooks — Kieran P1-1). See the plan's Decision Log. FR1/FR2 below are amended to the
> as-built design.

- FR1: An inline "Post to Slack (release)" step in `reusable-release.yml` constructs a
  Slack-schema payload (`text`, `unfurl_links: false`; no `username`/`icon_url` — app identity
  is authoritative) and POSTs via `curl`. Slack mrkdwn control chars (`&`, `<`, `>`) in the
  release-notes body are entity-escaped (mass-ping / disguised-link suppression, the
  `allowed_mentions` equivalent).
- FR2: The step runs in place of the Discord step, with the same release context (component
  display, version, tag, release-notes file, release URL) under the existing `if:` condition.
- FR3: The "Post to Discord (release)" step (lines 653–707) is deleted.
- FR4: New GH Actions secret `SLACK_RELEASES_WEBHOOK_URL`, consumed via `secrets.` and passed
  to the action input.
- FR5: The action emits a `::warning::` on non-2xx HTTP and a success log on 2xx (mirrors the
  Discord step's HTTP-code check).

## Technical Requirements

- TR1: `continue-on-error: true` on the invocation so a failed post never fails the release.
- TR2: `echo "::add-mask::$WEBHOOK"` (or equivalent) masks the URL in CI logs.
- TR3 (amended to as-built): Add a gitleaks rule `soleur-slack-webhook-url` to `.gitleaks.toml`
  (regex `https://hooks\.slack\.com/services/T[A-Z0-9]+/[A-Z0-9]+/[A-Za-z0-9_-]{24,}` — second
  segment NOT hardcoded to `B`, per review), with the same allowlist paths as the Discord rule.
  The `soleur-` prefix avoids shadowing the default-pack rule of the same name (same-id child
  rules replace default rules and would drop `/workflows/` detection). Pinned by
  `plugins/soleur/test/gitleaks-rules.test.sh`.
- TR4: Message length guard appropriate to Slack limits (Slack `text` ~40k chars; the existing
  1950-char Discord truncation can be relaxed/removed for Slack).
- TR5: Operator provisioning — the Slack-side Incoming Webhook creation is an operator step
  (workspace admin); the plan must include the exact click-path AND automate the
  `gh secret set SLACK_RELEASES_WEBHOOK_URL` step. Do NOT paste the URL via a `!`-prefixed line
  (`hr-never-paste-secrets-via-bang-prefix`).

## Acceptance Criteria

- AC1: A test/dry release run posts to the Slack channel with correct version, notes, and link.
- AC2 (amended to as-built): `reusable-release.yml` contains no Discord release step; the inline
  "Post to Slack (release)" step runs instead.
- AC3: Email-to-ops still fires on release.
- AC4: gitleaks flags a committed Slack webhook URL.
- AC5: A simulated webhook failure (bad URL) does not fail the release job; a `::warning::` appears.

## Stale-Doc Cleanup

Update references that claim Discord release notifications are functional:
- ~~`knowledge-base/project/learnings/2026-02-19-discord-bot-identity-and-webhook-behavior.md`~~
  — superseded by tasks.md 3.4: historical learning, deliberately left unchanged.
- `release-announce/SKILL.md`, `ship/SKILL.md`, `plugins/soleur/AGENTS.md` if they assert
  Discord release notifications (verify at implementation time; the Discord-removal learning
  notes these previously drifted).
