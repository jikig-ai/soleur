---
title: "feat: upstream — request Devin cloud support for plugin subagents and plugin hooks"
type: chore
date: 2026-09-17
slug: feat-upstream-devin-cloud-parity-asks
branch: feat-devin-upstream-asks-posture
issue: 8160
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: upstream — request Devin cloud support for plugin subagents and plugin hooks

## Overview

Issue #8160 tracks filing and tracking upstream requests to Cognition for the
two Devin Cloud capability gaps Soleur Cloud Mode degrades around: plugin
subagents (`agents/**/*.md` unavailable as cloud subagent types) and
plugin/repo hook dispatch (zero dispatch measured on every registry and
event). This plan produces the committed `upstream-asks.md` evidence package
(two asks + a contract/documentation bundle), a scheduled `docs.devin.ai`
drift watcher that detects when upstream ships or documents the capabilities,
and the filing execution (support email + Devin `/bug`) as a post-merge step
once the package is citeable on `main`.

**Plan-review revision (2026-09-17):** the 7-agent panel cut the proposed
followthrough probe + `soleur:followthrough` directive binding (dead-or-
spamming: missing `follow-through` label makes it inert, malformed `script=`
would die silently, and daily `NOT YET` comments recreate the spam the Cut
List rejected — the drift issue itself plus `Ref #8160` covers the linkage).
This deviates from spec FR5's prescribed directive; the deviation is recorded
here and the spec should be annotated at work time.

## Problem Statement / Motivation

Soleur Cloud Mode (#8159, shipped via PR #8155) degrades honestly around
capabilities only Cognition can close. The measured evidence (two-arm probe,
2026-09-15) is already public at
`knowledge-base/project/specs/feat-devin-cloud-session-parity/cloud-probe.md`
on `origin/main`. Nothing has been filed upstream, no channel is documented in
the repo, and nothing detects when upstream lands a capability — so the
"re-evaluate when Devin ships X" criteria recorded on #8160 and in
`plugins/soleur/devin/INSTRUCTIONS.md` have no trigger.

The hooks ask is the stronger arm because it is a documentation-versus-
measurement discrepancy, not merely a missing feature: Cognition's own docs
claim cloud sessions run `command` hooks for events other than SessionStart/
SessionEnd, while the measured probe observed zero dispatch across plugin
`hooks.json`, repo `.devin/config.json`, `.claude/settings.json`, and a
catch-all `matcher: ""`.

## Proposed Solution

1. **Package** — `knowledge-base/project/specs/feat-devin-upstream-asks-posture/upstream-asks.md`
   carrying three sections: (§1) hook-dispatch defect framed as doc-vs-measured
   discrepancy; (§2) plugin-subagent parity feature request naming the
   web-app vs DRS-sandbox substrate divergence; (§3) contract-semantics
   documentation bundle. Each claim cites the command/probe that produced it
   (upstream-reports convention). A one-line DPA disclaimer closes the package.
   The spec directory was archived at brainstorm-compound; this path is
   recreated for the working artifacts and re-archived at feature compound.
   **Citation discipline:** the email cites a SHA-pinned `blob/<merge-sha>/`
   permalink — the live spec path re-archives at feature compound and would
   404 within days. Filing sections contain no `YYYY-MM-DD HH:MM` timestamps
   (the scrub script flags them as install timestamps).

2. **Scrub gate** — `bash scripts/upstream-report-scrub.sh` exit 0 on the
   package; CLO guardrail checklist applied (capability-delta framing only;
   no org slugs, session IDs, absolute paths, env values, VM internals, or
   founder-identifying data; not framed as a security vulnerability). The
   email is sent **verbatim** from the scrubbed draft — the posted body cannot
   be re-fetched from a mailbox, so the scrubbed draft IS the posted body
   (operator attestation in the posting log).

3. **Detect** — `.github/workflows/scheduled-devin-docs-drift.yml` on the
   `scheduled-marketplace-drift.yml` pattern, with `gate-override:
   new-scheduled-cron-prefer-inngest` justified on the same three clauses
   (subject outside the product, GHA-native permissions, no product secrets).
   Watched surfaces: the `docs.devin.ai` plugin-ecosystem limitations page,
   the Devin CLI changelog, and Cognition's general release-notes surface.
   **Capability anchors carry per-claim polarity** — the hooks arm cannot be
   a presence-anchor ("docs claim hook dispatch" is true today, so it would
   either fire on day 1 or never flip); the correct anchors are claim-text
   *changes*, limitation-admissions, and changelog entries, while the
   subagents arm anchors on the limitations page's current absence claim.
   The changelog surface is an anchor-grep for capability keywords, not a
   raw content-diff (every upstream release would otherwise churn a drift
   issue). Issue egress: label bootstrap + `gh issue list --label` lookup +
   update-in-place (a failed lookup never collapses to create) + **close-on-
   clean** (marketplace-drift's close step — without it, one resolved episode
   leaves an open dedup issue that swallows every later episode as comments).
   The drift-issue body carries `Ref #8160` — that is the tracker linkage.
   Liveness: `sentry-heartbeat` composite with the three `SENTRY_INGEST_*`
   secrets forwarded (a missing forward is a silent dead heartbeat — the
   #7493 defect), backed by a `sentry_cron_monitor` resource in
   `apps/web-platform/infra/sentry/cron-monitors.tf` (required by
   `sentry-monitor-iac-parity.test.ts`; auto-applied post-merge by
   `apply-sentry-infra.yml`).

4. **Register + bookkeeping (pre-merge)** —
   `plugins/soleur/devin/INSTRUCTIONS.md` upstream-requests block gets
   time-invariant wording: "filing package at `<path>`; submission state
   tracked on #8160" — filing state never lives in committed markdown, so no
   second "flip the adjective" PR. Context comments on #8161/#8162 pointing
   at the archived brainstorm; a reconciliation comment on #8159 (issue open
   despite merged PR — likely oversight, operator judgement to close).

5. **File (post-merge)** — operator sends the scrubbed email verbatim to
   `support@cognition.ai` (agent prepares a `mailto:` link with prefilled
   subject/body where the body fits URL limits; otherwise exact paste text).
   Agent composes + attempts Devin `/bug` for §1; hand off with paste text if
   interactive-only. All remaining hops run through one bootstrap script
   `scripts/file-upstream-ask-8160.sh` per
   `hr-multi-step-post-merge-bootstrap-script`: re-scrub any retrievable
   posted body, update the #8160 posting log (destination/date/state +
   verbatim-send attestation), verify the first watcher run.

## Technical Considerations

- **Sequencing is load-bearing:** the email cites the package's blob
  permalink on `main`, so filing is post-merge. The PR references but never
  closes #8160 (`Ref #8160`) — the issue stays open as the register until
  capabilities land or Cognition declines.
- **Filing auth boundary:** the agent has no outbound-mail capability; the
  `mailto:` assist or paste text reduces the operator step to one click.
  Delivery itself is unverifiable (a bounce leaves "sent" in the log) —
  recorded honestly in the posting log.
- **Watcher independence:** subject is outside the product, so GHA not
  Inngest (ADR-033 gate override) — the alarm must not die with the web app.
- **Untrusted input:** fetched docs.devin.ai content is sanitized before
  reaching logs, `$GITHUB_OUTPUT`, or issue bodies; body-bound values also
  neutralize backticks/`<!--`/`@` (fence-breakout, directive-grammar,
  mention-spam).
- **Instance-shaped, disposable watcher:** this is a one-off for #8160, NOT
  a general upstream-watch substrate — teardown list below; productizing a
  data-driven watcher is #8253's scope (add `Ref #8253` to the workflow
  header).
- **Sunset/teardown (keyed to #8160 closing):** delete
  `scheduled-devin-docs-drift.yml`, the `sentry_cron_monitor` resource, the
  drift label, and the INSTRUCTIONS.md register row. Nothing else is enrolled.

## Research Insights

**Premise validation (Phase 0.6).** Checked: #8160 OPEN (primary tracker);
#8159 OPEN despite PR #8155 merged 2026-09-16 (reconciliation comment is a
plan step, not a scope change); #8172 OPEN (residual probe arms, out of
scope); `scripts/upstream-report-scrub.sh` present; `cloud-probe.md` resolves
on `origin/main` (`git ls-tree` verified); `support@cognition.ai` verified as
Cognition's documented feature-request channel (docs.devin.ai, fetched this
session — docs literally claim "cloud sessions run `command` hooks for every
event except SessionStart/SessionEnd" and "Subagents … not in cloud
sessions", matching the §1/§2 framing). Nothing stale.

**Property List (Phase 0.6b).** (a) Structured, citeable evidence filings;
(b) continuous detection of upstream capability/doc changes; (c) durable
tracking of filing state + vendor responses; (d) a safe channel-appropriate
submission path.

**Cut List (Phase 0.6b + plan-review).**
- Followthrough sweeper as the drift watcher → cut: sweeper comments on
  every run (no dedup, `sweep-followthroughs.sh` verdict→comment path), spam
  on a months-long watch.
- **Followthrough probe + directive binding → cut at plan-review (both
  panels fired on the same scope):** inert without the `follow-through`
  label on #8160 (sweeper enumerates `--label follow-through`), malformed
  `script=` shorthand would fail the sweeper's path canonicalization
  silently, daily `NOT YET` comments recreate the rejected spam, and the
  probe↔watcher finding-vocabulary contract was unpinned. `Ref #8160` in the
  drift-issue body produces the cross-reference for free.
- Inngest as watcher substrate → cut: subject outside the product (market-
  place-drift gate-override rationale).
- Re-probing cloud behavior before filing → cut: deferred arms belong to
  #8172; the package frames only measured evidence.
- Second "register flip" PR → cut at review: time-invariant wording means
  filing state never enters committed markdown.
- Data-driven multi-vendor watch manifest → deferred to #8253 (instance-
  shaped disposable watcher; generalization is the productization issue's
  design problem).
- Stale-response nudge probe → consciously declined: a vendor reply lands in
  the operator's mailbox where no probe can observe it; the posting log is
  the record.

**Prior-art / conventions (all verified at review).**
- `scripts/upstream-report-scrub.sh` — 0/1/2 exits; file arg or `-` stdin.
- `.github/workflows/scheduled-marketplace-drift.yml` — gate-override header,
  `set +e` + `|| rc=$?`, sanitize(), fail-closed fetch, verdict-as-data,
  label bootstrap + file-or-update + close-on-clean, concurrency group,
  `workflow_dispatch`, `sentry-heartbeat` composite with the three ingest
  secrets forwarded.
- `scripts/followthroughs/cloud-mode-postmerge-evidence-8159.sh` — notify-
  only exit contract + retirement checklist (kept as reference; NOT adopted
  as a mechanism after the review cut).
- Upstream-report convention (pencil #4859, claude-code #7490): measured
  evidence + producing commands, scrub local artifact and posted body, track
  URLs/status, withdraw what cannot be reproduced.

## Open Code-Review Overlap

None — the probe/`test-all.sh` edit was cut at plan-review, so #7942's
`*.mutation.sh` scope-out no longer intersects the planned files.

## User-Brand Impact

Carried forward from the brainstorm (`USER_BRAND_CRITICAL`).

- **If this lands broken, the user experiences:** a mis-scoped upstream
  filing that leaks account/session internals or overstates the ask —
  damaging Jikigai's credibility with the vendor it depends on for Cloud
  Mode remediation.
- **If this leaks, the user's [data / workflow / money] is exposed via:** a
  filing that embeds Jikigai-credentialed session details, org identifiers,
  or implies Cognition processes user personal data without an Art. 28 DPA.
- **Brand-survival threshold:** `single-user incident`

CPO reviewed this framing at brainstorm time (Phase 0.5); `requires_cpo_signoff`
is set accordingly. `user-impact-reviewer` will run at review time.

## Observability

```yaml
liveness_signal:
  what:            "Sentry Crons monitor for scheduled-devin-docs-drift (missed check-in)"
  cadence:         "daily"
  alert_target:    "Sentry Crons missed-check-in alert + filed drift issue on detection"
  configured_in:   "apps/web-platform/infra/sentry/cron-monitors.tf (sentry_cron_monitor resource) + .github/workflows/scheduled-devin-docs-drift.yml"

error_reporting:
  destination:     "GitHub issue filed-or-updated by the workflow on drift verdict; ::error:: annotation on check failure"
  fail_loud:       "fetch failure / unparseable docs surface is a filed finding, never silent green (fail-closed)"

failure_modes:
  - mode:          "docs.devin.ai unreachable or returns error page"
    detection:     "fetch_failed-class finding filed as drift issue"
    alert_route:   "issue notification"
  - mode:          "watcher workflow silently dead (60-day schedule disable, perms revoked)"
    detection:     "Sentry Crons missed check-in (the sweeper dies in the same mass-disable — the heartbeat is the only independent backstop)"
    alert_route:   "Sentry alert"
  - mode:          "upstream ships a capability (the detection the watch exists for)"
    detection:     "capability-anchor mismatch → drift issue carrying Ref #8160"
    alert_route:   "issue notification + automatic cross-reference on #8160"
  - mode:          "filing step never executed (operator email unsent)"
    detection:     "none automated — the posting log on #8160 stays 'pending send'; residual accepted (mailbox is unobservable)"
    alert_route:   "posting log state on #8160"

logs:
  where:           "GitHub Actions run logs for scheduled-devin-docs-drift.yml"
  retention:       "GitHub default run-log retention"

discoverability_test:
  command:         "bash -c 'gh run list --workflow=scheduled-devin-docs-drift.yml --limit 3'"
  expected_output: "at least one completed run listed for the workflow"
  credentials_required: "GH_TOKEN read access to this repo's Actions — no unauthenticated probe reads run state"
```

## Encryption Posture

```yaml
at_rest: []
in_transit:
  - connection:        "GHA runner -> docs.devin.ai (public, read-only GET)"
    enforced_at:       "https scheme in the workflow's URL constants"
    tls:               "TLS 1.2+ (curl default)"
    cert_verification: "on (curl default)"
    does_not_defend:   "content authenticity beyond TLS CA trust; fetched content treated as untrusted input"
    disclosed_as:      "not-publicly-claimed"
```

## Guard Contract

### Guard 1 — docs.devin.ai capability drift check

**Property.** Any capability-relevant content change on the watched
docs.devin.ai surfaces — or the check's inability to observe them — produces
a filed finding; the check never reports green on a state it could not see.

**Assembly.** The watched set is the URL list in the workflow's fetch step
(limitations page + CLI changelog + release-notes surface). Every fetched
document flows through the single `check` step's sanitize → assert →
findings → verdict pipeline. Three chokepoints, named: the fetch step (all
inputs enter), the issue file-or-update step (verdicts exit), and the
close-on-clean step (episodes terminate). Capability anchors are polarity-
aware per claim — a polarity-inverted anchor is the deepest failure here (a
watch structurally blind while reporting healthy).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Upstream edits the limitations page to admit hooks don't dispatch (hooks-arm anchor flips) | RED — capability drift issue filed |
| 2 | Fetch returns 404 / HTML error page / truncated body (guard's own observation path broken) | RED — fetch_failed finding filed, never green |
| 3 | A SECOND watched surface (changelog) gains a capability entry while the first is unchanged | RED — per-surface independence |
| 4 | Harness row: issue egress removed or `issues: write` revoked while check emits a drift verdict | RED — workflow run fails loud (::error::), no silent verdict |
| 5 | Drift resolves upstream (docs reverted) while a drift issue is open | close-on-clean fires — a permanently open episode suppresses later filings otherwise |
| 6 | Must-PASS (non-canonical): docs unchanged AND an unrelated section appended to the limitations page | informational drift at most — NOT a capability-verdict conflation |

**Anchor.** The capability anchors are *claims in the fetched live document*,
not a stored hash — a weakening must move upstream's published doc, outside
this commit's reach. The anchor list lives in the workflow file protected by
PR review; there is no self-certifying stored value.

## Implementation Phases

#### Phase 1: Evidence package

- Recreate `knowledge-base/project/specs/feat-devin-upstream-asks-posture/`
  and write `upstream-asks.md`: three sections per spec FR1–FR3, each claim
  citing its producing command/probe, closing with the DPA disclaimer line.
- Verify every cited repo path resolves on `origin/main`. No `YYYY-MM-DD
  HH:MM` strings in filing sections.

#### Phase 2: Disclosure gate

- `bash scripts/upstream-report-scrub.sh <package>` → exit 0.
- Manual CLO checklist: no org slugs, session IDs, absolute paths, env
  values, VM internals, founder-identifying data, billing posture;
  capability-delta framing; DPA disclaimer present.

#### Phase 3: Drift watcher + monitor

- `.github/workflows/scheduled-devin-docs-drift.yml` on the marketplace-drift
  pattern: gate-override header (+ `Ref #8253` disposable note), polarity-
  aware capability anchors, `set +e` + `|| rc=$?`, sanitize() incl.
  fence/comment/mention neutralization for body-bound values, fail-closed
  fetch, verdict-as-data, label bootstrap + file-or-update + **close-on-
  clean**, concurrency group, `workflow_dispatch`, sentry-heartbeat with the
  three `SENTRY_INGEST_*` forwards.
- `apps/web-platform/infra/sentry/cron-monitors.tf`: `sentry_cron_monitor`
  resource for the workflow's slug (crontab matches the workflow cron +
  sibling margin convention).
- `actionlint` the workflow file.

#### Phase 4: Register + bookkeeping (pre-merge)

- `plugins/soleur/devin/INSTRUCTIONS.md` upstream-requests block →
  time-invariant "filing package at `<path>`; submission state tracked on
  #8160".
- Comment on #8161 + #8162 pointing at the archived brainstorm/spec as
  context for their deferred re-evaluations.
- Comment on #8159: issue still open despite merged PR #8155 — flag for
  operator reconciliation (close is their judgement).

#### Phase 5: Filing + tracking (post-merge)

- `scripts/file-upstream-ask-8160.sh` (committed in this PR): updates the
  #8160 posting log, re-scrubs any retrievable posted body, verifies the
  first watcher run — the scriptable hops collapsed into one bootstrap.
- Operator: `mailto:` link (agent-prepared) or paste → send email verbatim
  to `support@cognition.ai`.
- Agent: compose + attempt Devin `/bug` for §1; paste handoff if interactive.
- Posting log records: destinations, dates, verbatim-send attestation,
  `/bug` outcome, delivery-unverifiable note.

## Files to Create

- `knowledge-base/project/specs/feat-devin-upstream-asks-posture/upstream-asks.md`
- `.github/workflows/scheduled-devin-docs-drift.yml`
- `scripts/file-upstream-ask-8160.sh`

## Files to Edit

- `plugins/soleur/devin/INSTRUCTIONS.md` (upstream-requests register)
- `apps/web-platform/infra/sentry/cron-monitors.tf` (`sentry_cron_monitor`)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `upstream-asks.md` exists with all three sections; every capability
  claim cites a producing command/probe or a `docs.devin.ai` page + fetch
  date; no `YYYY-MM-DD HH:MM` timestamp strings; DPA disclaimer + #8159/#8155
  citations present
- [ ] `bash scripts/upstream-report-scrub.sh knowledge-base/project/specs/feat-devin-upstream-asks-posture/upstream-asks.md` exits 0
- [ ] `scheduled-devin-docs-drift.yml` exists, passes `actionlint`, carries
  the `gate-override: new-scheduled-cron-prefer-inngest` header, requests
  only `contents: read` + `issues: write`, and implements: polarity-aware
  anchors, file-or-update dedup (failed lookup never creates), close-on-clean,
  sanitize() on all body-bound values, sentry-heartbeat with the three
  `SENTRY_INGEST_*` forwards
- [ ] `apps/web-platform/infra/sentry/cron-monitors.tf` declares
  `sentry_cron_monitor` for the workflow slug (sentry-monitor-iac-parity
  suite green)
- [ ] `INSTRUCTIONS.md` register shows time-invariant wording ("submission
  state tracked on #8160") — no "filed" claim
- [ ] `scripts/file-upstream-ask-8160.sh` exists and covers posting-log
  update + posted-body re-scrub + watcher-run verify
- [ ] PR body uses `Ref #8160` (not `Closes`)

### Post-merge (operator / filing)

- [ ] Email sent verbatim to `support@cognition.ai` (mailto assist or paste);
  `/bug` outcome recorded
- [ ] `file-upstream-ask-8160.sh` run: posting log updated on #8160
  (destination/date/state + verbatim-send attestation + delivery-unverifiable
  note); `/bug` body re-scrubbed where retrievable
- [ ] `gh run list --workflow=scheduled-devin-docs-drift.yml --limit 1`
  shows ≥1 completed run
- [ ] `apply-sentry-infra.yml` applied the new cron monitor (auto on merge)

## Test Scenarios

- Given unchanged upstream docs, when the watcher runs, then verdict green
  and no issue filed.
- Given a flipped capability anchor (synthetic fixture), when the check
  runs, then a capability-drift finding is emitted.
- Given an unreachable docs.devin.ai (mock fetch failure), when the check
  runs, then a fetch_failed finding is filed — never silent green.
- Given an open drift issue and reverted upstream docs, when the check runs,
  then close-on-clean closes the episode.
- Given a failed `gh issue list` lookup, when the check has a verdict, then
  no issue is created (dedup guard).

## Success Metrics

- Both asks and the bundle are in Cognition's support queue with a recorded
  submission state on #8160.
- The watcher files a drift issue within one week of an upstream
  capability-visible doc change (daily cadence).
- No CLO-guardrail violations in any posted body (scrub exit 0 on the sent
  draft).

## Dependencies & Risks

- **Operator mailbox is the auth boundary** — `mailto:` assist + verbatim
  send; delivery unverifiable (bounce = stale "sent", accepted).
- **`/bug` may be interactive** — composed body prepared regardless.
- **Doc-visible detection only** — a capability shipped without a docs or
  changelog change is invisible; page redesigns produce informational drift
  (intended sensitivity; re-check anchors on any drift).
- **Anchor polarity** — the hooks arm anchors on claim-text *change*, not
  presence (docs already claim dispatch); a polarity-inverted anchor is the
  worst failure mode (blind while reporting healthy) and is why the Guard
  Contract names it.
- **Mintlify-class markup fragility** — prose anchors may drift on
  rewording; each false anchor-drift files one issue (loud, not silent).
- **#8159 issue-state nuance** — open despite merged PR; a reconciliation
  comment is a plan step, not scope.
- **Teardown discipline** — the watcher is disposable; the teardown list is
  keyed to #8160 closing so it does not become a permanent 16th scheduled
  workflow filing drift on every docs edit.

## Domain Review

Carried forward from the brainstorm's `## Domain Assessments` (leaders ran at
brainstorm Phase 0.5; no named specialists required).

**Domains relevant:** Product, Legal, Engineering

### Product

**Status:** reviewed (brainstorm + plan-review advisory)
**Assessment:** CPO — two asks + bundle under #8160 per upstream-report
precedent; plan delivers decided scope faithfully; bookkeeping steps
(#8161/#8162 context, #8159 reconciliation) added per advisory.

### Legal

**Status:** reviewed (brainstorm + gdpr-gate Phase 2.7)
**Assessment:** CLO — clean to file; capability-delta text only; scrub
org/session IDs and env internals; one-line DPA disclaimer; not a security-
vulnerability framing. gdpr-gate: no regulated-data surfaces; Chapter-V
suggestion noted (filing channel is vendor-contact, not processing — already
encoded by the scrub + disclaimer).

### Engineering

**Status:** reviewed (brainstorm + plan-review advisory)
**Assessment:** CTO — `support@cognition.ai` + `/bug` channel; doc-vs-measured
framing; docs-drift watch. Plan-review CTO advisory folded in: Sentry monitor
provisioning, teardown list, permalink citation, bootstrap script for
post-merge hops, disposable-vs-data-driven decision (disposable; #8253 owns
generalization).

**Brainstorm-recommended specialists:** none.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Single combined mega-ask | Separate asks get separate triage; hooks deserves its own defect channel |
| Public issue tracker filing | Cognition has no public tracker (verified); documented channel is support email |
| Followthrough sweeper as watcher (and probe+directive binding) | Cut at plan-review — inert without label / malformed script= / daily-comment spam; `Ref #8160` in the drift issue covers linkage |
| Second register-flip PR | Time-invariant register wording; filing state never enters committed markdown |
| Active re-probe before filing | Deferred arms belong to #8172; package frames only measured evidence |
| Wait for Cognition DPA first (#8161) | Filing is not personal-data processing (CLO); no dependency |
| Data-driven multi-vendor watch manifest | Over-scope for a p3 chore; #8253 owns productization — watcher declared disposable |

## References & Research

- Spec: `knowledge-base/project/specs/archive/20260917-155554-feat-devin-upstream-asks-posture/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/archive/20260917-155554-2026-09-17-devin-upstream-asks-cognition-brainstorm.md`
- Evidence: `knowledge-base/project/specs/feat-devin-cloud-session-parity/cloud-probe.md` (on `origin/main`)
- Capability matrix + register: `plugins/soleur/devin/INSTRUCTIONS.md` §Cloud Mode
- Scrub: `scripts/upstream-report-scrub.sh`
- Watcher pattern: `.github/workflows/scheduled-marketplace-drift.yml`
- Issues: #8160 (primary), #8159/#8155 (parent), #8172 (residual arms),
  #8161/#8162 (parked), #8253 (productization), #8254 (guard defect),
  #7942 (overlap — resolved moot by the probe cut)
