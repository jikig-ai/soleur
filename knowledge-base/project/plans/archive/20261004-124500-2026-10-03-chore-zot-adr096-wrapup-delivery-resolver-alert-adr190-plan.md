---
title: "Zot / ADR-096 wrap-up: running-host delivery decision, resolver self-heal diagnosis, ghcr_blocked alert, ADR-190 acceptance"
type: chore
date: 2026-10-03
slug: zot-adr096-wrapup-delivery-resolver-alert-adr190
branch: feat-one-shot-zot-adr096-wrapup-9393-9390-9391-9392
issue: 9393
closes: none (every PR uses Ref; #9393, #9392 and #9390 stay open by decision, #9391 closes after the first apply creates the alert)
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: cross-domain
---

# Zot / ADR-096 wrap-up

## Enhancement Summary

**Deepened on:** 2026-10-03
**Research agents used:** learnings-researcher, code-simplicity-reviewer, CTO (devex lens), kieran-rails-reviewer (generic correctness), observability-coverage-reviewer, architecture-strategist, terraform-architect, spec-flow-analyzer; live reads of Better Stack, Sentry and GitHub state.

### Key improvements
1. The resolver fix is no longer sold as the cause: SIGPIPE is hardly reachable on a small listing, so the change is three-valued (present, absent, unreadable), keeps the event before the loader re-run, matches the real `default drop` rule (the old check matched the LOG rule's prefix), and adds `read_retried`, `log_present`, `host` and recency fields; the same defect in the loader's Phase 4 is fixed as its own commit.
2. web-2 delivery is rebirth-only (#9372), not "replace": ADR-263's discriminate step would power a plain replace off. The #9372 image must come from a post-PR-1 commit.
3. PR-2 paging uses the measured sibling combination (300/900/1800), not an unprecedented 60/900/1800; `#9391` closes at the first apply, not at merge.
4. Runbook and ADR text is keyed to observable state with a removal trigger, so it does not rot when the pause ends; ADR-169 gets the one sentence that merge no longer delivers a registry change during the pause.
5. O2 now carries the plan-time reads (no registry render change since the pause; #9385, #9397, #9440 accumulated), the re-pause owner, and a dated re-evaluation (2026-10-17) for #9393 and #9390; #9392 has an explicit exit criterion.

### New considerations discovered
- A fresh host's first `ci-deploy` row can read `ghcr_blocked=0` and page once (reborn web-2).
- `ghcr_blocked=unknown` and a dark web-host stream are silent by design; the runbook must say silence is not health.
- Both mutation matrices were trimmed to the load-bearing rows (simplicity review); the Guard Contract minimums are kept.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this branch.

## Overview

Close out the remaining Zot / ADR-096 follow-ups that are code, doc or infrastructure changes: the
delivery path for the cron-egress artifacts to hosts that are already running (#9393), the host
hosts-file deny line (#9390), a Better Stack alert for a lost host deny (#9391), the unrouted
self-heal event (#9392), and the ADR-190 status flip. Operational items (PR #9450 cleanup, the Sentry
monitor mute read, #9291) are listed as non-code follow-ups and carry no code here.

The work is **two PRs plus one held item**, grouped by code area and by merge path:

| Unit | Scope | Why this boundary |
|---|---|---|
| **PR-1** (this branch, draft #9451) | #9393 decision recorded in the runbook + ADR-096, #9392 resolver fix and diagnostic fields, ADR-190 `adopting` to `accepted` | No `.github/workflows/` edit, so the agent admin-merge path stays available. One code area: the cron-egress runbook and resolver. |
| **PR-2** (new branch `feat-one-shot-9391-ghcr-blocked-alert`) | #9391 Better Stack Logs alert (closes after the first apply, not at merge) | Edits `.github/workflows/` (two `-target` lines, one validation step), so it merges only through queued auto-merge. Keeping it out of PR-1 stops a ~35 min CI cycle and BEHIND resyncs from holding the doc and resolver fixes hostage. |
| **Held** | #9390 `docker.pkg.github.com` in the hosts-file deny | Any byte change to `cloud-init-registry.yml` is a ForceNew replace of the sole pull path and, while the push-apply workflows are paused, would leave a hidden pending replace. Decision D3 below. |

## Research Reconciliation — Spec vs. Codebase

| Brief / issue claim | Reality (measured 2026-10-03) | Plan response |
|---|---|---|
| "re-enable that workflow on a safe trigger" (#9393 brief) | `gh workflow enable` is binary: there is no trigger subset. `apply-web-platform-infra.yml` AND `apply-deploy-pipeline-fix.yml` are both `disabled_manually` since 2026-10-01T21:30Z, a deliberate hold for the plaintext-wipe cutover (PR #9348 body: "Both push-apply workflows stay paused until after it merges"; `workspaces-luks-cutover-6604.md` step d/h). | D1: do not re-enable from this plan. It is a production-write approval that goes to the operator (O2). |
| #9393: "running web-2 does not receive ... until its next replace" | True, and wider: `deploy_pipeline_fix_web2`'s carrier (`apply-deploy-pipeline-fix.yml`) is paused too, so extending that resource would deliver nothing today. web-1 is also undelivered (pause). | D2: web-2 is rebirth-only; web-1 is delivered by the first unpaused apply. Runbook rewritten. |
| #9392: "~15 a day", "297 events" | Sentry issue 127244085 reads 335 events (first seen 2026-06-11, last 2026-10-03T16:27Z), about 9 in the last 24h and about 2.9 a day on average; the issue is `ongoing`, never routed. | D4: diagnose before routing; the SIGPIPE candidate is code-reachable but unproven (see D4). |
| #9392: events say which host | They do not: the event `extra` carries only `remediation`; no host, no exit codes. Both web hosts run a resolver. | D4 adds the discriminating fields. |
| #9391: "Better Stack alert on ghcr_blocked=0 ... no dependency on the registry replace" | Live rows exist: 1481 registry `SOLEUR_ZOT_DISK` rows (14d) all `ghcr_blocked=1`; web `GHCR_DENY` rows 42 (web-2) + 43 (web-1) at `=1`, and exactly one real `=0` row (web-1, 2026-09-30T13:28Z, before the deny reached it): the positive control. Rows from `SYSLOG_IDENTIFIER=doppler` QUOTE the marker (issue and PR bodies shipped by inngest): the false-positive class the predicate must exclude. | D5: two-arm predicate, exact-message equality on the `ci-deploy` arm, head-scoped envelope arm on the registry. |
| ADR-190: "adopting until the #7556 soak returns PASS" | #7556 closed `COMPLETED` 2026-10-01T22:06:46Z by the sweeper with verdict `PASS deadlines_ns=1800000000000 config_starts=8 patch_rows=33 long_ok=7 other5xx=1`. | D6: flip with the verdict and its stated scope recorded. |
| #9390 trigger "when #8714 5.6 is prepared" | 5.6 flipped ADR-096 to Accepted on 2026-10-02 without the line. That trigger is spent; the remaining trigger is "next planned registry-host replace". | D3: hold with a written recipe. |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #9393, #9390, #9391, #9392 all `OPEN`, no closing PR;
#9291 `OPEN` (surface only); #7556 `CLOSED` 2026-10-01T22:06Z with a PASS sweeper comment; PR #9385
(carve) `MERGED` 2026-10-01T22:32Z; PR #9348 (PR B, held) `OPEN` draft; both apply workflows
`disabled_manually`; `cron_egress_firewall` is in the SSH apply `-target` set
(`apply-web-platform-infra.yml`, the "Terraform apply (SSH-provisioned resources, over the bridge)"
step); `hcloud_server.web` carries `ignore_changes = [user_data, ...]` (so web `cloud-init.yml` byte
edits never replace a running web host) while `hcloud_server.registry` deliberately carries none
(`zot-registry.tf`). Held: every cited artifact exists. Stale: the "safe trigger" premise and the
"~15 a day" figure.

**Mechanism-vs-ADR check (0.6 item 4).** ADR-096 amendment 2026-10-02 already lists #9390/#9391/#9392/#9393
as tracked outside the ADR; ADR-169/ADR-190 define the registry replace dispatcher. No ADR rejects
the chosen mechanisms. ADR-218 asks the next Logs alert to name its signal class, show no existing
alert covers it, and probe the predicate: carried into PR-2.

**Property List (Phase 0.6b).**

1. P1: a reader of the cron-egress runbook can tell, per host, which firewall artifacts are live and what closes the gap, without SSH.
2. P2: a lost hosts-file GHCR deny on any web host or the registry host reaches a human within one heartbeat or one release.
3. P3: when the egress self-heal fires, one Sentry event says which host, which rule was missing, and whether the "missing" read was a failed read.
4. P4: the ADR corpus states ADR-190's true status and the evidence for it.
5. P5: nothing in this wrap-up changes a running production host while the apply workflows are paused, and nothing creates a hidden pending replace of the registry host.

**Cut List (Phase 0.6b).**

| Mechanism | Property it would buy | Cut because |
|---|---|---|
| Extend `terraform_data.deploy_pipeline_fix_web2` with the three cron-egress artifacts (issue option 1) | P1 for web-2 | Its carrier is paused too (delivers nothing today); adds a live-container assertion to a job that is fail-closed for web-1 remediation; web-2 is a weight-0 standby (ADR-143 D2) that must be reborn before pooling (ADR-263, `lb-weight-gate.sh` Condition B). Grepped authority: `server.tf` header of `deploy_pipeline_fix_web2`, `lb-weight-gate.sh`. |
| New narrow apply workflow for `cron_egress_firewall` | P1 for web-1 | Bypasses an operator hold with a bespoke production write path, edits `.github/workflows/`. |
| Route `op=enforcement_missing` into the existing Sentry rule now | P3 | The group has been `ongoing` since 2026-06-11, so a first-seen/reappeared/regression rule never emails for it; routing buys nothing until the cause is known. Also avoids a `frequency_minutes` collision. |
| A new heartbeat field or periodic web-host probe (#9291's alternative) | P2 | #9291 is surface-only; the per-release `GHCR_DENY` row plus the registry heartbeat already feed the alert. |
| A second poller (`scheduled-zot-restart-loop.yml` verdict) for `ghcr_blocked` | P2 | Covers the registry only; one Logs alert covers both with one predicate. |

**Institutional learnings applied.** `2026-10-02-drift-autoclose-closed-issues-for-hosts-it-never-realigned`
(issue #9382 stays open); `2026-09-27-a-status-flip-sweep-must-include-the-legal-registers-that-state-the-mechanism`
(sweep done: no `knowledge-base/legal` file names ADR-190); `2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument`
(the resolver's self-heal must not read "could not measure" as "rules missing": the core of D4);
`2026-10-01-an-alert-guard-pinned-the-declaration-and-the-command-text-not-the-consumer`
(the PR-2 guard reads the needle from the emitters' own source); `best-practices/2026-07-11-cron-egress-sentinel-needs-runbook-row-and-infra-glob-fires-apply`
(`apps/web-platform/infra/**` fires the apply; any new ASSERT-FAILED sentinel needs a runbook row, none is added here).

**Measured at plan time (commands named).**
`gh api repos/jikig-ai/soleur/actions/workflows/{280110019,274867255} --jq .state` returned `disabled_manually` for both;
`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 14d --grep "ghcr_blocked=" --limit 3000`, decoded:
registry heartbeat 1481 rows `=1`, web-1 `GHCR_DENY` 43 at `=1` and 1 at `=0` (2026-09-30T13:28:45Z), web-2 42 at `=1`, plus 63 `doppler`-identifier rows that merely quote the marker;
`scripts/betterstack-query.sh --since 14d --grep "enforcement rules missing"` returned 0 rows (the resolver's stdout is not shipped; Sentry is the only channel);
`doppler run -p soleur -c prd -- scripts/sentry-issue.sh 127244085` read the issue (HTTP 200, count 335, 24h hourly buckets 0-2, no host tag on events).

## Decisions

Every fork below was decided in the plan, per the standing rule that technical forks are not operator questions.

**D1: #9393, re-enable the apply workflows? No, from this plan.** The disable is the operator's documented hold for the
sole-copy plaintext-wipe window (PR B #9348 states both stay paused until it merges; the cutover runbook ends the pause after PR B).
There is no "safe trigger" subset: enabling restores push-apply of every merged infra change. That is a production-write
authorization, so it is the one approval this wrap-up routes to the operator (O2, with a recommendation, not a technical question).
Nothing in PR-1 or PR-2 depends on it: both are inert until an apply runs, and both land at the first apply after the pause ends.

**D2: #9393, delivery path.** Accept rebirth-only delivery for **web-2** (NOT a plain replace: ADR-263's `discriminate` step refuses the live plaintext web-2 volume and a plain `web-host-replace` would power the host off until #9372 runs); rely on the first unpaused apply for **web-1**; no new
Terraform delivery code.
- web-2: weight-0 standby, no user traffic, plaintext volume empty, never pooled (ADR-143 D2); it must be reborn before it can be
  pooled (#9372, ADR-263, the `lb-weight-gate.sh` LUKS coupling), and a reborn host boots from the baked image whose host scripts and
  `cloud-init.yml` carry the carve (`/opt/soleur/host-scripts/`, content-hash check named in #9372). The #9372 rebirth is the closing event, and its `image_tag` must be built from a commit AT OR AFTER PR-1, because PR-1 edits `cron-egress-resolve.sh` and `cron-egress-nftables.sh`, both baked host scripts (`host_scripts_content_hash` moves; recorded as a comment on #9372).
  The host-process deny from #9169 already reaches web-2 through `deploy_pipeline_fix_web2`; only the bridge-container layer and the probe are late.
- web-1: `terraform_data.cron_egress_firewall` hashes the carve file, the resolver and the post-apply assertion, and is in the SSH apply target
  set, so the first apply that runs (the post-PR-B `manual-rerun`, or any push) delivers it with the live positive and negative container probe.
- Runbook: rewrite both "Known residual" sections, keyed to OBSERVABLE state with an "as of 2026-10-03" stamp and #9393 named as the removal trigger (the pause is transient and the text must not rot when it ends): the apply workflow's enabled state, the closing event per host, and what is silent meanwhile (`ghcr_deny_lost`, `ghcr_deny_probe_blind`). Never suggest a plain web-2 replace. No SSH step is added.
- #9393 stays open with re-evaluation criteria: closes when the web-1 delivery apply is green and #9372's rebirth has run. Dated re-evaluation: 2026-10-17 (two days after the wipe's earliest date); if both apply workflows are still paused then, O2 is asked again. The close condition is two readable facts: an apply run after PR-1 whose `cron_egress_firewall` provisioner executed green, and the #9372 rebirth run. `--add-blocked-by 9372` is a link, not a trigger, so the date is the only prompt; this residual chain can stall behind the wipe's safety check and that is stated, not hidden.

**D3: #9390, hold; do not implement in this wrap-up.** Editing the registry runcmd copy is a user_data ForceNew replace of the sole
pull path (ADR-169). `registry-host-replace-dispatch.yml` fires on merge and dispatches the paused apply workflow, so merging now would fail the
dispatch and leave a pending replace that nothing re-fires (this holds for ANY registry-render-touching PR during the pause, not only #9390: the runbook states it). Value is defense in depth for a name no host pulls from. The recipe is recorded
below so it is a mechanical edit when the trigger arrives; trigger = the push-apply pause is lifted AND (a registry render change is otherwise due
OR a standalone replace is authorized) AND `scripts/registry-replace-preflight.sh` reads clean. Tracking stays on #9390 with a comment and a dated re-evaluation (2026-10-17, with #9393's), so the three-part trigger has a watcher.

**D4: #9392, fix the read, add the discriminating fields, do not route.** `cron-egress-resolve.sh` checks the chain with
`nft list chain ... | grep -q ...` under `set -euo pipefail`; a `grep -q` early exit can SIGPIPE `nft` (pipeline status 141, read as "missing").
That is code-reachable, but a chain listing this small is written in one flush, so SIGPIPE is hardly reachable on the live host (plan-review, CTO and correctness seats, both independently).
Likelier causes are netlink contention (an `nft` read failing with rc 1 against the loader or a Docker restart, which `pipefail` turns into "missing") or Docker reprogramming `DOCKER-USER`.
So the change is a fix of the read plus an instrument, and the fix is NOT presented as the cause:
- capture each listing into a variable with the status initialised first (`rc_jump=0; out="$(nft ... 2>/dev/null)" || rc_jump=$?`; an uninitialised `rc` aborts under `set -u`), match with a glob test (no pipeline, no `grep -q`);
- the verdict is three-valued per rule: present, absent, unreadable (nonzero status with no usable listing). Unreadable is retried once; if still unreadable the loader re-run still happens (it is idempotent, and failing open is worse) but the event carries `read_failed=true` so a failed read is never reported as an absent rule;
- the second rule is matched on what it is: the resolver today greps `egress-blocked`, which is the LOG rule's prefix, not the `counter drop` rule (comment `soleur-egress: default drop`). The decision becomes "jump absent OR default-drop absent", and `log_present` (the old `egress-blocked` match) is reported as its own field, so the field named `drop_present` means a drop. The loader installs the chain's rules together, so this is equal in practice and stricter in principle;
- extract the check into a function called as a BARE statement that sets globals (under `set -e`, a function called from `if` or `||` ignores errexit, which would make a mutation of the status capture vacuous); the event call stays a top-level literal `sentry_event "<message>" "enforcement_missing" "$extra"` because `sentry-egress-ghcr-deny-alert-op-contract.test.ts` parses it by regex;
- the event keeps its message (same Sentry group) and gains `extra`: `host`, `jump_present`, `drop_present`, `log_present`, `rc_jump`, `rc_drop`, `read_failed`, `read_retried`, `docker_since`, `loader_since`. A read that fails once and succeeds on retry still emits no event, but `read_retried` rides on the next event so a transient flap is visible in aggregate. Competing hypotheses become distinguishable in one event: a failed read (`read_failed`, nonzero `rc_*`), a Docker restart (`docker_since` just before the tick), a loader run racing the tick (`loader_since`), or a real external flush (both rules absent, all statuses 0, nothing recent). `uptime_s` is cut (a boot is visible in both timestamps). The two `systemctl show` reads use `timeout 2` and run BEFORE the event post, which stays before the loader re-run and before `fail` exactly as today, so a failed self-heal (the case that most needs the event) still posts; worst case 4 s against the probe's 30 s budget. A `jq` failure while building `extra` falls back to a minimal `{remediation:...}` object so it can never abort before the post;
- the same defect exists in the loader: `cron-egress-nftables.sh` Phase 4 runs `if ! nft list chain ip filter DOCKER-USER | grep -q 'jump SOLEUR-EGRESS'` under `set -euo pipefail`, and a false "missing" there inserts a DUPLICATE jump rule (self-heal re-runs this loader every time). Apply the same capture-then-match there (in scope, same area, same hash);
- no Sentry rule change (Cut List). **Exit criterion (#9392 stays open until it is applied):** once the delivering apply is proven (workflow run log), read the events of the next 7 days. If 3 or more events carry the new fields, classify them by the field table above and decide routing (a dominant `read_failed`/nonzero `rc_*` means read contention, fixed by D4; events within 60 s of `docker_since` or `loader_since` mean an upstream effect; both rules absent with nothing recent means a real flush). If 0 events arrive in 7 days AFTER delivery is proven, close as fixed; absence counts only with that delivery proof. web-2 keeps the old event shape until #9372, so web-2-origin events are the ones with no `host` field.

**D5: #9391, one native Logs alert, two arms, `higher_than 0`.** ADR-218 recipe, sibling of `registry_store_not_luks` and `bwrap_probe_rollback`.
Arm W: `SYSLOG_IDENTIFIER = 'ci-deploy'` AND `message = 'GHCR_DENY ghcr_blocked=0'` (exact equality; `unknown` deliberately does not alert).
Arm R: the registry envelope `startsWith(raw, '{"message":"SOLEUR_ZOT_DISK ')`, message position 1, and ` ghcr_blocked=0 ` positioned before ` zot_last_err=`
(head-scoped, the sibling's shape). No `host_name` conjunct, on purpose (web-1 appears as `soleur-web-platform` and, before 2026-09-19, `soleur-inngest-prd`; web-2 as `soleur-web-2`).
Paging copies `registry_store_not_luks` (`check_period 300`, `query_period 900`, `recovery_period 1800`), the measured sibling for a 900 s window; no sibling uses 60/900/1800 and provider acceptance of that combination is unmeasured. The `incident_cause` says the incident auto-resolves after 30 quiet minutes, which is not the cause being found. A first `ci-deploy` row on a freshly born host (the reborn web-2) can read `=0` before the deny is in place and page once: named in the runbook decode, not suppressed. `higher_than 0` is safe for the registry because 1481 of 1481 live registry rows read `1`, including the 2026-09-22 replace boot. This is the tenth Logs alert; the free-tier cap is
still unmeasured and a refusal on count would surface at the main-plan apply, which is why the ADR-218 amendment names it.

**D6: ADR-190 flip.** Frontmatter `status: accepted`; `## Status` records the PASS verdict, the run time, and its scope (the deadline sub-mode only; `unexpected EOF` is out of scope and stays
excluded; "a clean week of this size is a tripwire, not proof: DELIVERY is the causal evidence"). Past-tense the sentence "Grading is deferred to a soak". Include the
sweep result for legal registers and the other files that cite ADR-190 (`scripts/registry-replace-preflight.sh`, `plugins/soleur/test/zot-http-deadlines-required.test.sh`,
`.github/workflows/reusable-release.yml`, `.github/workflows/registry-host-replace-dispatch.yml`): none state "adopting".

**D7: PR split.** PR-1 and PR-2 as in the Overview. PR-2 is rebased after PR-1 merges, because both add a section to `cron-egress-blocked.md`.

**D8: review-round amendments to D4 (2026-10-03, PR #9451 review).** Recorded here because they change D4's text:
(a) the loader re-runs FIRST, under `timeout -k 2 60` (egress is open until it does, and a wedged loader must still reach the event), then the event posts BEFORE `fail`; the `extra` is built after the loader (it carries the probe's pre-heal rule states, which live in the resolver shell, plus `loader_rc`, 12 keys);
(b) nft's own ENOENT (rc 1 and an `Error: No such file or directory` first line: a deleted table or chain) is an `absent` rule, not `unreadable`; a missing binary (rc 127) or another error ending in the same words stays unreadable;
(c) the default-drop LOG rule (matched on its own comment) joins the heal condition, and the jump is matched by its target token, so `jump SOLEUR-EGRESS-OLD` is not ours;
(d) the loader no longer dies on a persistently unreadable DOCKER-USER chain: it inserts the jump anyway and WARNs, because a duplicate jump is inert and a missing one leaves egress open until the next tick (fails toward enforcement);
(e) the retry sleep seam is one name, `NFT_RETRY_SLEEP`, in both scripts, clamped to a single digit;
(f) `cron-egress-postapply-assert.sh` matches the drop rule on its comment instead of the log prefix (same defect class, same rule);
(g) the behavioural suite is standalone (`cron-egress-self-heal.test.sh`, promoted in `guard-vacuity-floor.test.sh`) and EXECUTES the heal block, not only the extracted functions.

## Does merging this alone mutate production?

Answer for each PR (first line of each PR body):
- **Today: no.** Both apply workflows are `disabled_manually`, so a merge touching `apps/web-platform/infra/**` fires no apply.
- **After the pause is lifted (O2): yes, and the merge click is the authorization** (`hr-menu-option-ack-not-prod-write-auth`). PR-1's own change reaches `terraform_data.cron_egress_firewall` (web-1, SSH, live probes) through `apply-web-platform-infra.yml`, but that apply's `-target` graph also pulls `hcloud_server.web["web-1"]` transitively and carries every merge since the pause; the workflow's own `host_creates` and `reboot_updates` guards are what bound a surprise host change, so cite them rather than assert "only"; `apply-deploy-pipeline-fix.yml`'s `paths:` list names none of the cron-egress files, so it cannot apply this change (enumerated at plan time, not assumed). PR-2 reaches Better Stack API resources only, through the main plan's `-target` list; no host is touched.
- ADR-190 and the runbooks are documentation: no production effect.

## Implementation Phases

### PR-1 — runbook decisions, resolver fix, ADR-190 (this branch)

**Phase 1: optional timing evidence (before any code; not a precursor to Phase 3).** With no host tag and about 9 events a day the signal is weak, so treat it as supporting evidence only. Read Sentry issue 127244085 through the documented path
(`doppler run -p soleur -c prd -- scripts/sentry-issue.sh <id>`), take its hourly `stats` buckets (the issue read returns 24h and 30d series; do not add a second reader), and compare them with `ci-deploy` row times from
`scripts/betterstack-query.sh --grep DEPLOY_SCRIPT_SHA`: buckets clustered on deploy hours point at a Docker or loader effect, an even spread points at a
read race. Record counts only (never event bodies) in the PR body. This is evidence for the PR text, not a gate on the fix: D4's fix is correct under both readings.

**Phase 2: tests first (`cq-write-failing-tests-before`).** In `apps/web-platform/infra/cron-egress-firewall.test.sh` add a behavioral section that extracts
the new function from the resolver by its definition anchor (as `cron-egress-ghcr-probe.test.sh` does), puts an `nft` shim on `PATH`, and drives rows: both rules present;
jump absent; drop absent; both absent; shim fails (rc 1, empty); the SIGPIPE reproducer (the shim prints the matching line, sleeps 0.3 s, then writes 200 KB, so the OLD
pipeline form reads rc 141 and the new form reads the match); noisy chain text around the needle. A row floor and a `PASS + FAIL == CASES` accounting like the sibling suite.
RED first against the unchanged resolver, for the right reason: the OLD-form 141 row deliberately inlines the old pipeline as a labelled control (the one permitted logic copy, because the old form no longer exists to extract), and the extraction carries a non-vacuity check (the extracted function is at least N lines) as the sibling suite does, so an empty extraction cannot go RED by "command not found".

**Phase 3: the resolver change.** `apps/web-platform/infra/cron-egress-resolve.sh`, the "Self-heal" block (anchor: the comment `# --- Self-heal: assert the enforcement rules are still live`):
extract `enforcement_probe` (three-valued, bare-statement call, statuses initialised to 0), capture-then-match, build the extra with `jq -nc` (jq is already a hard dependency of the script), `systemctl show` reads wrapped in `timeout 2` with `unknown` fallbacks, before the event post (post stays before the loader re-run and before `fail`); a `jq` or `systemctl` failure while building the extra falls back to a minimal extra and never aborts before the post. Also `cron-egress-nftables.sh` Phase 4 (same capture-then-match, same D4 reasoning), as its OWN commit with its own test row so it can be reverted alone: it changes whether self-heal inserts a duplicate jump rule, independent of the diagnosis. Side effect to state in the PR: both files are baked into the web image and the fresh-host scripts (`server.tf` `host_script_files`, Dockerfile), which is the desired fresh-host parity.
Keep the `CRON_EGRESS_FROM_LOADER` skip, the loader re-run, the literal top-level `sentry_event "<message>" "enforcement_missing" "$extra"` call, and the event message byte-identical. The file is hashed by `terraform_data.cron_egress_firewall`, so merge re-fires that provisioner at the next apply: expected.

**Phase 4: runbook.** `cron-egress-blocked.md`: rewrite "Known residual: running web-2" and "Known residual: web-1 until the apply workflow runs" per D2; add a decode table for the new
`enforcement_missing` fields to "Related signals" and keep the sentence that the op is not routed, now pointing at the re-evaluation criteria in D4 (a first read of events carrying
`rc_jump`, after delivery). Keep "no SSH" wording. State that while the push-apply workflows are paused, ANY merge that changes a registry render input leaves a pending replace that nothing re-fires. The "Deeper diagnosis" step 3 text is updated to say the event now names the cause class.

**Phase 5: ADRs.** ADR-190 per D6, with the scope caveat (deadline sub-mode only, a tripwire not proof) as the FIRST sentence of `## Status`. ADR-169: the one dated sentence above. ADR-096 residual list: update the #9393 bullet to the decision (web-2 rebirth-only, web-1 at first unpaused apply), and write the #9391 and #9390 bullets as "tracked in the issue, see its state" so they do not go stale when PR-2 or the held change lands. No new ADR (see Architecture Decision).

**Phase 6: tracking edits (no file).** `gh issue comment` on #9393 (decision + closing events), #9390 (held, trigger evaluation, link to the recipe), #9392 (fix landed, what to read next);
`gh issue edit 9393 --add-blocked-by 9372`. Not closing any of the three.

### PR-2 — Better Stack alert for `ghcr_blocked=0` (separate branch)

**Phase 1: live-probe the final SQL** with the `$BS_TABLE` hot union `$BS_TABLE_S3` archive, 14-day window, counts only: (1) as written: expected 1 (web-1, 2026-09-30) unless the
deny regressed since; (2) arm R positive control: needle `ghcr_blocked=0` changed to `ghcr_blocked=1`: expected about 1481, proving the arm is live SQL; (3) a variant that drops the `SYSLOG_IDENTIFIER` conjunct and the exact-equality: returns more than (1) because of the `doppler`-identifier quoting rows (63 at plan time), proving the scoping is what excludes them. Record the counts in the ADR-218 amendment (no separate probe file).

**Phase 2: guard first.** `apps/web-platform/test/infra/ghcr-blocked-alert.test.sh`, modelled on `bwrap-probe-rollback-alert.test.sh`: reads the needles from the emitters' own source
(`ci-deploy.sh` `GHCR_DENY ghcr_blocked=` logger line, `cloud-init-registry.yml` heartbeat line), pins both arms' exact shape (including that the emitter writes ` zot_last_err=` after the head, since a missing field would silence the head-scope), `higher_than 0`, `treat_as_zero`, `paused = false`, the source pin, both `-target=` lines, the runbook anchor, and a mutation battery with a row floor.

**Phase 3: Terraform.** `betterstack-logs-alerts.tf`: new `#9391` section: `locals` (SQL, runbook URL), `logtail_exploration.ghcr_deny_lost`, `logtail_exploration_alert.ghcr_deny_lost`, paging copied from `bwrap_probe_rollback`
(`check_period 300`, `query_period 900`, `recovery_period 1800`, the measured `registry_store_not_luks` combination; the registry arm needs the wider window, the web arm is per release) with an `incident_cause` that says resolution is not a fix.
`.github/workflows/apply-web-platform-infra.yml`: the two `-target=` lines beside `bwrap_probe_rollback`. `.github/workflows/infra-validation.yml`: one step running the guard.
`apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`: the `values = [local.vector_prd_source_id]` count `9` to `10` and the surrounding comment (the sibling PR did `8` to `9`; re-derive with `grep -c` before editing).

**Phase 4: docs.** ADR-218 amendment (tenth alert; signal class; not covered by an existing alert; probe result; free-tier cap still unmeasured; enforcement by the guard only). `betterstack-log-query.md` standing-alarm row.
`cron-egress-blocked.md`: a "Host hosts-file deny lost (`ghcr_blocked=0`)" decode section (row sources, what `unknown` means (it does not alert, so a blind web-host probe is silent: silence is not health), why the alert resolves after quiet minutes without the cause being found, and
that while the push-apply workflows are paused a lost deny on a web host cannot be repaired by the usual apply path, so it goes up as an approval request, not a host step).

### Held — #9390 recipe (not implemented now)

Add `docker.pkg.github.com` to the `for h in ghcr.io pkg-containers.githubusercontent.com; do` list at exactly six sites, byte-identical: `cloud-init-registry.yml` (copy R, runcmd entry near the
`ghcr.io` sinkhole loop), `cloud-init.yml` (copy A, the web runcmd entry), `server.tf` `local.ghcr_deny_sh` and `local.ghcr_deny_assert_sh` (copy B), `web-ghcr-deny.test.sh`, `zot-image-fetch.test.sh`.
Copy B changes re-fire `zot_consumer_probe_install` (web-1) and `deploy_pipeline_fix_web2` (web-2) at the next apply; copy R forces the registry replace (the reason it is held). The `ci-deploy.sh`
`GHCR_DENY` probe stays `ghcr.io`-only (registry parity). Open it as its own PR so a failed replace is attributable.

## Non-code follow-ups (parent session; no code planned)

- **O1: PR #9450** (archives the egress-carve plan and spec): confirm it merged with the Monitor tool, then run `worktree-manager.sh cleanup-merged` to remove `.worktrees/chore-archive-9275`.
- **O2: the pause (new, from D1).** One approval request to the operator, in plain words: "Both infrastructure apply workflows have been switched off since 2026-10-01 21:30 UTC for the data-wipe window; the wipe has not started and its safety check is currently failing, so the earliest it can run is about 2026-10-15.
  Until they are switched back on, no infrastructure change reaches any server (the firewall carve, the new alert, daily range updates). Switching them on early is safe for the data volume because the volume still exists; the runbook already says to switch them off again at the moment the wipe is authorized.
  Recommendation: switch them on now, after a read-only look at what would be applied (the plan of every merge since 2026-10-01, including any registry change that was dispatched into the pause), because the first apply after a long pause is a big-bang event." Read at plan time (2026-10-03, `git log origin/main` over the registry render inputs and `gh run list` of the registry dispatcher): no registry render input has changed since the pause began, so no hidden pending registry replace exists; infra merges since the pause are #9385 (carve), #9397 (LUKS follow-ups) and #9440 (git-data), which the first apply will also deliver. Re-run both reads on the day. The re-pause for the wipe is owned by the wipe procedure itself (cutover runbook step d, "Re-pause (d) before re-dispatching D"); add a line to #9348's hold list saying so. Do not enable without an explicit yes. If it is a yes, the first apply is the delivery event for D2 (web-1) and starts the D4 re-evaluation.
- **O3: Sentry monitor mute state** for `cron-egress-resolve` and `cron-github-cidr-refresh`. The issue read path works (HTTP 200 on 2026-10-03 through `scripts/sentry-issue.sh` under `-c prd`); the monitor endpoints are a different scope, so probe with the documented path and never print a token.
  Read recipe: #8704 and `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` (read-only `GET organizations/jikigai-eu/monitors/`; confirm `environments[].isMuted`, not only the top-level flag). A 403 there is a scope difference from the issue read, not an outage. Implied change only if a monitor is muted: nothing in code (the runbook already says to check the environment is not muted, #8704). An unmute is a Sentry write (the monitor REST PUT, which the Terraform provider cannot express) and needs the write-capable token plus a per-command go-ahead, so a mute is reported to the operator as a finding and an approval request, never fixed silently.
- **O4: #9291**, surface only: it is a decision the operator may object to; no action, no code.
- **O5: delivery evidence** after O2: the apply run whose provisioner ran green is the proof for web-1, per the runbook's own wording. Then read events carrying `rc_jump` for D4's re-evaluation.

## Files to Edit

PR-1:
- `apps/web-platform/infra/cron-egress-resolve.sh`
- `apps/web-platform/infra/cron-egress-nftables.sh` (Phase 4 capture-then-match; its test `cron-egress-nftables.test.sh` gets a matching row)
- `apps/web-platform/infra/cron-egress-firewall.test.sh`
- `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`
- `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md`
- `knowledge-base/engineering/architecture/decisions/ADR-169-what-authorizes-destroying-the-sole-pull-path.md` (one dated sentence: while the push-apply workflows are paused a merge no longer delivers a registry user_data change; the dispatch fails and nothing re-fires it)
- `knowledge-base/engineering/architecture/decisions/ADR-190-zot-http-deadlines-sized-to-largest-layer.md`
- `plugins/soleur/test/preflight-discoverability-test.test.ts` (`BASELINE_DECLARED_PROBES` +1 for this plan's declared probe; re-count with the test's own rule)
- if the behavioral rows move them: `plugins/soleur/test/fixture-relative-assert.baseline.txt`, `scripts/guard-vacuity-floor.test.sh` (verify with their own runners; do not guess)

PR-2:
- `apps/web-platform/infra/betterstack-logs-alerts.tf`
- `.github/workflows/apply-web-platform-infra.yml`
- `.github/workflows/infra-validation.yml`
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md`
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
- `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`

## Files to Create

- PR-1: none beyond this plan and its `tasks.md`.
- PR-2: `apps/web-platform/test/infra/ghcr-blocked-alert.test.sh`.

Glob verification (`hr-when-a-plan-specifies-relative-paths-e-g`): every path above was checked with `git ls-files` at plan time except the two files in "Files to Create".

## Open Code-Review Overlap

2 open scope-outs touch a file this plan edits: #8735 and #7942 (both on `.github/workflows/infra-validation.yml`, PR-2).
- **Acknowledge** both: different concerns (the failure-email path for cancelled jobs; two unwired mutation batteries). PR-2 adds one step and does not touch either area. They stay open.
- #2197 names `server.tf`; this plan edits no `server.tf` line (the held #9390 recipe would): **Acknowledge**, unrelated billing concern.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "#9393: running web-2 does not receive the cron-egress firewall artifacts (carved CIDR file, resolver) until its next replace ... Decide the path yourself (re-enable that workflow on a safe trigger, or deliver the artifacts another way), and update the web-1 residual note in the cron-egress-blocked runbook if it changes. No ssh fallbacks in runbooks." [brief] | D1, D2, PR-1 Phase 4, Phase 6 | mapped |
| 2 | "#9390 (docker.pkg.github.com in the hosts-file GHCR deny, at the next registry-host replace)" [brief] | D3, Held recipe | mapped (held by decision; trigger written) |
| 3 | "#9391 (Better Stack alert on ghcr_blocked=0)" [brief] | D5, PR-2 | mapped |
| 4 | "#9392 (op=enforcement_missing fires ~15x/day, routed by no Sentry rule)" [brief] | D4, PR-1 Phases 1-4 | mapped |
| 5 | "Group by code area and handle in as few PRs as sensible." [brief] | Overview table, D7 | mapped |
| 6 | "A Sentry frequency_minutes value can collide across parallel PRs, so re-derive the unused set before merge." [brief] | Sharp Edges; neither PR adds a `sentry_alert` | mapped |
| 7 | "ADR-190 is still `status: adopting`: do the adopting -> accepted follow-on" [brief] | D6, PR-1 Phase 5 | mapped |
| 8 | "list the operational items 1, 3, 6 as non-code follow-ups" [brief] | Non-code follow-ups O1, O3, O4 | mapped |
| 9 | "Re-read the Sentry monitor mute state ... plan only any code/doc change it implies." [brief] | O3 | mapped (no code implied) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| D1 (do not re-enable from the plan) | "Decide the path yourself (re-enable that workflow on a safe trigger, or deliver the artifacts another way)" | asked |
| D2 + runbook rewrite | "update the web-1 residual note in the cron-egress-blocked runbook if it changes" | asked |
| D3 held recipe | "(docker.pkg.github.com in the hosts-file GHCR deny, at the next registry-host replace)" | asked |
| D4 fix + fields | "op=enforcement_missing fires ~15x/day, routed by no Sentry rule" | asked |
| D4 `extra` fields `host`, `rc_*`, `read_failed`, `docker_since`, `loader_since`; loader Phase 4 fix | — | inferred — justification: the event carries no host and no read status today, so the SIGPIPE candidate from #9392 cannot be separated from a real flap without them (blind-surface rule, `hr-observability-as-plan-quality-gate`) |
| D5 alert, two arms | "Better Stack alert on ghcr_blocked=0" | asked |
| D5 exact-equality and head-scoped predicates | — | inferred — justification: 63 live rows quote the marker under `SYSLOG_IDENTIFIER=doppler`; without the scoping the alert pages on issue text |
| D6 ADR-190 flip | "do the adopting -> accepted follow-on (its gating issue closed 2026-10-01)" | asked |
| O2 approval request | "The only things that go to the operator are real approvals (merge authority, spend, anything destructive)" | asked (the pause lift is a production write) |
| ADR-096 bullet edit, ADR-218 amendment | — | inferred — justification: both ADRs enumerate these residuals and the alert count; leaving them stale is the "recorded architecture lags the change" defect |
| `preflight-discoverability-test.test.ts` baseline bump | — | inferred — justification: this plan declares a credentialed probe, and that test pins the corpus count |
| `betterstack-send-failed-alert-mutation.test.sh` 9 to 10 | — | inferred — justification: it asserts the exact count of `vector_prd_source_id` pins, which PR-2 raises |

### Split Assessment

- Subsystems touched: 4 across both PRs (`apps/web-platform`, `knowledge-base`, `.github`, `plugins`); per PR: PR-1 3, PR-2 3
- Planned files: 7 (PR-1) + 8 (PR-2) | Estimated changed lines: about 330 (PR-1), about 650 (PR-2, mostly the guard)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — PR-1 / PR-2 boundary is the `.github/workflows/` edit (merge-path difference), already adopted.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: infrastructure and documentation change on an existing surface. No user-facing page, no pricing or legal text, no new vendor. (The only vendor-facing item, Better Stack, is already a processor for the same log source.)

## User-Brand Impact

- **If this lands broken, the user experiences:** a resolver regression on web-1 could make the egress self-heal re-run the firewall loader every minute or never run it, so container egress is briefly too closed (the app's outbound calls fail for every user) until the next tick or an apply rollback. A broken alert only fails to page.
- **Fail-open window (named in review):** a rule lost mid-life leaves container egress open until the loader re-runs; the re-run now comes first in the heal path (only the probe sits in front of it, about 1 s) and a loader that cannot read the chain inserts the jump anyway rather than skipping it. The loader run itself includes its nested resolver pass before the jump is re-installed, so the window is bounded by the loader's own run, which is cut at 60 s (`timeout`), not by the 60 s tick.
- **If this leaks, the user's workflow is exposed via:** nothing user-specific. The new Sentry fields are a hostname, exit codes and unit timestamps; the Logs alert reads existing rows. A lost hosts-file deny exposes host-process egress to `ghcr.io`, which is what the alert exists to detect.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** no per-user data path changes and delivery goes through the gated apply whose live container probes fail the apply on an inert or over-closed ruleset, so this is an availability-pattern risk rather than a single-user incident.

## Observability

```yaml
liveness_signal:
  what: Better Stack source 2457081 rows: registry SOLEUR_ZOT_DISK heartbeat (ghcr_blocked field) and the per-release web-host GHCR_DENY row
  cadence: registry every 5 minutes; web hosts once per release
  alert_target: team email via the native Logs alert soleur-ghcr-deny-lost-prd (paid-tier policy escalation is the existing ternary)
  configured_in: apps/web-platform/infra/betterstack-logs-alerts.tf (PR-2)
error_reporting:
  destination: Sentry project web-platform, feature=cron-egress-firewall, op=enforcement_missing (resolver sentry_event, DSN from the unit environment)
  fail_loud: the event now names the host, which rule was absent, each nft read's exit status, and docker/loader recency; unset Sentry env logs a WARN to the journal only (the resolver's stdout is not shipped), so Sentry is this event's only channel
failure_modes:
  - mode: hosts-file GHCR deny lost on a web host or the registry host
    detection: layer vector (journald, SYSLOG_IDENTIFIER=ci-deploy, `GHCR_DENY ghcr_blocked=0`) matched by the PR-2 alert; the registry arm is a direct POST of the SOLEUR_ZOT_DISK heartbeat to the same source, which fits none of the seven layers and is covered by the alert itself
    alert_route: Better Stack Logs alert, team email; decode in cron-egress-blocked.md
  - mode: egress enforcement rules missing at a resolver tick (cause unknown: failed read, docker restart, loader race, external flush)
    detection: in-surface Sentry event emitted from the host itself, with rc_jump, rc_drop, read_failed, jump_present, drop_present, docker_since, loader_since separating all four hypotheses in one event
    alert_route: none by decision D4 (re-evaluated after the first events carrying the new fields). Layers: tick liveness is the Sentry monitor check-in cron-egress-resolve; the enforcement_missing event is a direct store-API POST from the host (no named layer, named here as such)
  - mode: carved firewall artifacts not delivered to a running host while the apply workflows are paused
    detection: workflow run log of the first unpaused apply (provisioner executed green) is the proof; ghcr_deny_lost and ghcr_deny_probe_blind are silent there, so silence is not evidence
    alert_route: runbook known-residual sections; O2 approval request
  - mode: web-host ghcr_blocked=unknown (getent fails or hangs) or a dark web-host log stream
    detection: layer vector; the PR-2 alert does NOT fire on unknown and treat_as_zero reads a dark stream as healthy, so a blind web-host probe is silent; the registry has a sibling watcher (scheduled-zot-restart-loop SILENT/INGEST_DARK), web hosts have none
    alert_route: none by decision; named in the runbook decode so silence is not read as health
logs:
  where: Better Stack source 2457081 (journald via Vector, registry direct POST); Sentry events for the resolver; the resolver's own stdout is NOT shipped
  retention: Better Stack hot table plus S3 archive (scripts/betterstack-query.sh unions both); Sentry project default
discoverability_test:
  command: bash scripts/betterstack-query.sh --since 3d --grep GHCR_DENY --limit 5
  expected_output: GHCR_DENY
  credentials_required: "BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD via Doppler soleur/prd_terraform (run under `doppler run -p soleur -c prd_terraform --`) — Better Stack log content has no unauthenticated read path (the ingest token is write-only), so no keyless probe verifies the same property"
```

Probe scope: this probe reads the feeding pipeline for PR-2's alert (the `GHCR_DENY` rows). PR-1's new Sentry fields cannot be read until the delivering apply has run; until then PR-1's observable is the issue read `scripts/sentry-issue.sh --latest-event 127244085` (credentialed, same waiver class), re-run after delivery to confirm `rc_jump` is present. **Owner and trigger of that read:** the #9392 exit criterion (the runbook's decision rule): after the first green `apply-web-platform-infra.yml` run whose SSH apply step ran, whoever picks up #9392 runs that read and the 7-day count; the re-evaluation date 2026-10-17 is recorded on #9392, #9393 and #9390. The alert's armed state is read back separately (`paused=false`).

## Infrastructure (IaC)

### Terraform changes

Existing root `apps/web-platform/infra/`, file `betterstack-logs-alerts.tf`: `logtail_exploration.ghcr_deny_lost` and `logtail_exploration_alert.ghcr_deny_lost` on the already-pinned `BetterStackHQ/logtail` provider; no new provider, variable or sensitive input (the source id is the existing literal `local.vector_prd_source_id`). PR-1 changes no Terraform: the resolver file is already a `file()` input of `terraform_data.cron_egress_firewall`.

### Apply path

Existing infra workflow (`apply-web-platform-infra.yml`: the main plan's `-target` list for the alert, the SSH step for the resolver). Better Stack API writes only for the alert, no downtime. The resolver re-delivery re-runs the `cron_egress_firewall` provisioner on web-1 with its live probes. Both are inert while the workflows are paused and land at the first apply after (O2).

### Distinctness / drift safeguards

Better Stack Logs is prd-only (`-prd` names, like every sibling). The guard pins the names, the exploration linkage, the source literal, the predicate arms, the paging values and both `-target=` lines. State is the existing R2-backed root; the alert holds no secret.

### Vendor-tier reality check

Free tier: no escalation policy (team email only, the existing `betterstack_paid_tier` ternary). The Logs alert count cap is undocumented and this is the tenth alert; a refusal on count appears at the main-plan apply and is recorded in the ADR-218 amendment.

## Architecture Decision (ADR/C4)

### ADR

- Amend `ADR-218` (PR-2): the tenth Logs alert, signal class, the existing-alert comparison, the probe result, the unmeasured cap.
- Amend `ADR-096`'s residual list (PR-1): the #9393 bullet records the web-2 rebirth-only decision and web-1 first-unpaused-apply delivery.
- Flip `ADR-190` to `accepted` (PR-1), recording the soak verdict and its scope. No new ADR: no ownership boundary, substrate, or trust boundary changes; D2 is a delivery-timing decision for an already-recorded topology.

### C4 views

No C4 change. Read all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) and checked: external human actor `founder` (already receives `betterstack -> founder` and `sentry -> founder`); external systems `betterstack`, `sentry`, `ghcr`, `github`, `doppler` (all modeled, edges present: `zotRegistry -> betterstack`, `hetzner -> betterstack`, `hetzner -> sentry`); containers `hetzner` (web hosts) and `zotRegistry`; no actor-to-surface access relationship changes. The `betterstack -> founder` edge prose enumerates monitors and heartbeats, not Logs-alert counts, and the 43-rule Sentry count is unchanged because no `sentry_alert` is added. `bash plugins/soleur/test/c4-count-parity.test.sh` was green at plan time (`Failed: 0`) and must be re-run in each PR.

### Sequencing

None needed; all three ADR edits describe current state.

## Encryption Posture

```yaml
# No persistent store is introduced: the Better Stack alert and exploration are configuration objects on
# an existing log source, and the resolver change adds fields to an existing Sentry event. No new
# cross-component connection is introduced; the two connections below are existing paths that carry new content.
at_rest: []
in_transit:
  - connection: resolver host script -> Sentry ingest (existing event POST; new fields host, rc_*, read_failed, docker_since, loader_since)
    enforced_at: apps/web-platform/infra/cron-egress-resolve.sh sentry_event (https:// URL, curl default verification)
    tls: HTTPS, curl/OpenSSL default minimum (TLS 1.2+)
    cert_verification: on
    does_not_defend: a compromised host holding the Sentry public ingest key can post forged events (the key is public by design)
    disclosed_as: not-publicly-claimed
  - connection: Terraform logtail provider -> Better Stack Telemetry API (existing apply path; two new resources)
    enforced_at: apps/web-platform/infra/main.tf provider "logtail" (HTTPS API endpoint; token from Doppler prd_terraform)
    tls: HTTPS, provider Go TLS default minimum (TLS 1.2+)
    cert_verification: on
    does_not_defend: a leaked provider token can create or delete alerts; the alert holds no secret and no user data
    disclosed_as: not-publicly-claimed
```

## Guard Contract

### Guard 1 — ghcr-blocked-alert drift guard (PR-2, `apps/web-platform/test/infra/ghcr-blocked-alert.test.sh`)

**Property.** The alert fires on a `ghcr_blocked=0` row from any web host's `ci-deploy` marker or the registry heartbeat head, and never on a row that merely quotes the marker, and the resources are applied by the main plan.

**Assembly.** Everything the property quantifies over: the two predicate arms inside `local.ghcr_deny_lost_sql`; the emitters whose literal the arms match (`ci-deploy.sh` `GHCR_DENY ghcr_blocked=` logger line, `cloud-init-registry.yml` `SOLEUR_ZOT_DISK ... ghcr_blocked=$GHCR_BLOCKED ... zot_last_err=` line); the exploration source pin (`local.vector_prd_source_id`, itself pinned to the Vector sink URI); the alert's paging values; BOTH `-target=` lines in `apply-web-platform-infra.yml` (the only enforcement for `logtail_*` resources, `terraform-target-parity.test.ts` checks `terraform_data` only); the `infra-validation.yml` step that runs this guard; the runbook anchor named in the alert. Chokepoint: the single `locals` heredoc is the only place predicate text lives; the resource site only flattens it.

**Mutation matrix.**

| # | Edit (must go RED) | Targets |
|---|---|---|
| M1 | drop the `SYSLOG_IDENTIFIER = 'ci-deploy'` conjunct, or loosen `JSONExtractString(raw,'message') = 'GHCR_DENY ghcr_blocked=0'` to `startsWith`/`LIKE` | the quoting-row exclusion and exactness |
| M2 | arm R: remove the head-scope `position(...) < position(' zot_last_err=')` | head-scoping |
| M3 | change the emitter literal in a COPY of `ci-deploy.sh` (`GHCR_DENY ghcr_blocked=` to `GHCR_STATE ghcr_blocked=`) | the guard reads the consumer's own needle, not a pinned string |
| M4 | remove ONE of the two `-target=` lines | enforcement of delivery |
| M5 | add a second arm member after a compliant first: a third `OR (...)` that matches `ghcr_blocked=1` | a check that stops at the first member |
| M6 | the guard's own dispatch: make its row loop iterate zero rows (empty table) | a guard that reports 0 checked and exits 0 |
| M7 | `higher_than 0` to `higher_than 1`; `on_missing_data` to anything but `treat_as_zero`; `paused = true` | paging semantics |

**Harness rows.** (a) Edit the SUITE: delete the `assert` that reads the emitter needle; the pass-count floor must RED. (b) A must-PASS input that is not the canonical: the alert block reformatted (whitespace, reordered locals) with identical semantics must stay GREEN, so a guard that rejects everything is caught.

**Anchor.** The predicate's needles are read from the emitters' own source (outside the `.tf`), and the live-probe result is recorded in the ADR-218 amendment (outside the guard and the `.tf`); one diff that weakens predicate and guard together still has to contradict the emitters' literals.

### Guard 2 — enforcement probe behavioral rows (PR-1, `apps/web-platform/infra/cron-egress-firewall.test.sh`)

**Property.** A tick reads "enforcement missing" only when the jump rule or the drop rule is actually absent from a successfully read chain listing, and a failed read is reported as a failed read, never as a missing rule.

**Assembly.** The two `nft list chain` reads in the resolver (the `DOCKER-USER` jump and the `SOLEUR-EGRESS` drop), the matcher for each, the status capture for each, the loader's own Phase 4 read of the `DOCKER-USER` jump (a third site of the same defect; the test asserts no `nft ... | grep -q` pipeline remains in either file), the event `extra` that carries both verdicts and both statuses, and every call site of the check in the resolver (there is one: the self-heal block; a second site would be the defect, so the test greps for exactly one). Chokepoint: the extracted function; the call site only consumes it.

**Mutation matrix.**

| # | Edit (must go RED) | Targets |
|---|---|---|
| M1 | restore `nft ... \| grep -q` (pipeline form) in either read | SIGPIPE row: rc 141 must not read as missing |
| M2 | delete the `\|\| rc_jump=$?` capture (function called as a bare statement) so a failing `nft` aborts under `set -e` | a failed read is recorded, not fatal |
| M3 | add a THIRD required rule to the check after the compliant two, absent from the shim | the table has a row where only the third is absent, and it must read missing |
| M4 | the test's own dispatch: the shim always prints both rules | the rows "jump absent", "drop absent" and "both absent" must RED |
| M5 | an unreadable read (rc 1, empty) reported as "absent" instead of `read_failed=true` | the three-valued verdict |

**Harness rows.** (a) SUITE edit: remove the SIGPIPE reproducer's sleep; the row that proves the OLD form reads 141 must RED (the reproducer is itself checked, so a shim that cannot trigger SIGPIPE cannot certify the fix). (b) Must-PASS non-canonical input: a chain listing with extra rules, counters and comments around the needle must read present. (c) Row floor and `PASS + FAIL == CASES`, as in the sibling suite.

**Anchor.** The event message and tags are asserted against the sentry-alert contract test (`apps/web-platform/test/sentry-egress-ghcr-deny-alert-op-contract.test.ts` already pins that `enforcement_missing` is NOT in the routed filter); a change to the routing needs that test edited in the same diff, which a message-only edit cannot do silently.

## Acceptance Criteria

### Pre-merge (PR-1)

- [ ] `cron-egress-resolve.sh` has no `nft ... | grep -q` pipeline in the self-heal block and exactly one call site of the extracted check; the event message string and `feature`/`op` tags are unchanged.
- [ ] The new `extra` fields (`host`, `jump_present`, `drop_present` (the `default drop` rule), `log_present`, `rc_jump`, `rc_drop`, `read_failed`, `read_retried`, `docker_since`, `loader_since`) are asserted by the test; the mutation rows M1-M5 of Guard 2 each go RED when applied to a scratch copy.
- [ ] The test is RED against the unchanged resolver before the change (recorded in the PR body) and GREEN after.
- [ ] `cron-egress-blocked.md` has no sentence implying the apply workflow "runs" without naming the pause, names both closing events, adds no SSH step, and decodes each new field.
- [ ] ADR-190 frontmatter `status: accepted`; `## Status` cites the PASS verdict with its scope; `grep -n "adopting" ADR-190` finds no present-tense claim.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` green; `python3 scripts/lint-guard-contract.py` green on this plan; `python3 scripts/lint-infra-no-human-steps.py --changed` (the gate's own invocation, not a hand-listed path set) green.
- [ ] `BASELINE_DECLARED_PROBES` re-counted and bumped with a dated justification comment.
- [ ] No `.github/workflows/` file is edited in PR-1. PR body: `Ref #9393`, `Ref #9392`, `Ref #9390`; none closed.

### Pre-merge (PR-2)

- [ ] The ADR-218 amendment records the three live-probe counts of PR-2 Phase 1 (counts only). PR-2's branch is cut from `main` AFTER PR-1 merges (both edit `cron-egress-blocked.md`).
- [ ] `ghcr-blocked-alert.test.sh` passes; mutation rows M1-M7 each go RED on a scratch copy; the 9 to 10 count edit in the send-failed mutation test is made and that suite is green.
- [ ] Both `-target=` lines and the `infra-validation.yml` step exist; `terraform validate` is green in CI.
- [ ] ADR-218 amendment and both runbook edits present. PR body: `Ref #9391` (not `Closes`: nothing is live while the apply workflows are paused, and #9393's own rule is that delivery closes, not merge; #9391 closes once the first apply has created the alert).
- [ ] No `sentry_alert` is added. If a later edit adds one, re-derive the unused `frequency_minutes` set from `main` immediately before merge (a literal copied from a sibling PR is stale once either lands).

### Post-merge (parent session)

- [ ] PR-1 and PR-2 merged by queued auto-merge (PR-2) or the normal path (PR-1); `gh pr view <n> --json mergedAt`.
- [ ] After O2 (if approved): the apply run for the delivering merge concluded success with the `cron_egress_firewall` provisioner executed; then read the first events carrying `rc_jump` and record the D4 conclusion on #9392. Without O2: record "undelivered, paused" on #9393.
- [ ] #9391 is closed after the first apply has created the alert (read it back, `paused=false`); #9393, #9392 and #9390 remain open with updated criteria comments.

## Test Scenarios

- Resolver: both rules present reports ok and posts nothing; jump absent reports missing with `jump_present=false`; drop absent reports missing with `drop_present=false`; `nft` failing with rc 1 and empty output reports `rc_jump=1` and never silently ok; the SIGPIPE reproducer reads present under the new form and rc 141 under the old form.
- Alert (PR-2, against live data via the probe): the web-1 row of 2026-09-30 matches; a `doppler`-identifier row quoting the marker does not; `ghcr_blocked=1` and `unknown` do not.
- ADR-190: the flip leaves the other ADR-190 consumers (`registry-replace-preflight.sh`, `zot-http-deadlines-required.test.sh`) green.

## Dependencies & Risks

- **Pause (O2).** Nothing here is delivered until the apply workflows run again; merging stays safe because everything is inert while paused. Risk: the pause lasting to the wipe's earliest date leaves web-1 on the old allow list and no probe, with silence not evidence (documented in the runbook).
- **Delivery contains the live probe.** At the first apply the web-1 provisioner re-runs with positive and negative container probes. A carve that wrongly cuts `github.com` fails the apply (the intended guard), taints the resource and must be fixed forward, never `gh run rerun --failed`.
- **SIGPIPE may not be the cause.** The plan does not claim it is: the fields exist to find out. If events continue unchanged after delivery, D4's re-evaluation reads them and decides routing.
- **Free-tier alert-count cap** for the tenth Logs alert is unmeasured; a refusal at the main-plan apply would block that plan until resolved (the same risk every recent sibling accepted); named in ADR-218.
- **`.github/workflows/` edits (PR-2)** merge only via queued auto-merge; a BEHIND sync restarts about 35 minutes of CI, and `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` conflict with most merges: take main's, run `python3 scripts/regenerate-shard-manifest.py --incremental --write`, commit the merge, then judge lint.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled here; keep it filled.
- `check-deploy-script-parity.sh` calls doppler itself: never wrap it in `doppler run`.
- `web-fresh-boot-zot-8651.sh` assumes `gh run list` is newest-first; do not reorder its input in any test helper.
- The main checkout's `apps/web-platform/node_modules` is stale, so a local typecheck fails spuriously; rely on CI, and skip local full test batteries.
- Never edit `cloud-init-registry.yml` as a side effect of another change: any byte is a registry replace (D3).
- Do not use `pkill -f`: source `plugins/soleur/scripts/lib/proc.sh` and use `kill_mine`. Never `git stash` in a worktree.
- The Sentry event `message` must not change: a new message creates a new issue group and orphans the 335-event history that D4's re-evaluation reads.
- When counting `values = [local.vector_prd_source_id]` for the PR-2 mutation test, run the `grep -c` on current `main` first; the literal in this plan is a plan-time observation.
- Commits end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`; PR bodies end with the generated-with-Claude-Code line.

## References

- Issues: #9393, #9390, #9391, #9392, #9291 (surface only), #9372, #9382, #6604, #9348, #7556.
- PRs: #9385 (carve), #9376 (sibling alert), #9414 (ADR-096 Accepted), #9450 (archive, open).
- ADRs: ADR-096, ADR-143, ADR-169, ADR-190, ADR-218, ADR-263.
- Code: `apps/web-platform/infra/cron-egress-resolve.sh`, `apps/web-platform/infra/server.tf` (`cron_egress_firewall`, `deploy_pipeline_fix_web2`), `apps/web-platform/infra/betterstack-logs-alerts.tf`, `apps/web-platform/infra/ci-deploy.sh` (`GHCR_DENY`), `apps/web-platform/infra/cloud-init-registry.yml` (heartbeat).
- Runbooks: `cron-egress-blocked.md`, `betterstack-log-query.md`, `sentry-issue-read.md`, `workspaces-luks-cutover-6604.md`, `registry-host-replace-dispatch.md`.
