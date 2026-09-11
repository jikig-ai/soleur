---
title: "Retire the personal Sentry auth token: a dedicated read-only org integration for the followthroughs, DC-3 decided on measurement"
date: 2026-09-11
slug: feat-sentry-org-token-retire
branch: feat-one-shot-7946-sentry-org-token-retire
issue: 7946
closes: [7946, 7993]
type: security
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

This is the #7946 half of the plan deepened on 2026-09-09
(`knowledge-base/project/plans/2026-09-09-feat-sentry-org-token-and-snapshot-redaction-plan.md`).
The #7947 half shipped in PR #7975 (merged 2026-09-09T22:35Z); DC-1 split the two, and this branch
carries the credential half alone. The 2026-09-09 research is reused, not re-derived — every fact
this plan builds on was re-verified in this worktree on 2026-09-11, and the three readings that
were still missing on 2026-09-09 were taken live today (Phase 0.2's scope probe, the legacy org
slug's status, and the personal token's actual scope list). Two of those readings change the shape
of the work, and one of them decides DC-3.

**The change.** The sixteen `scripts/followthroughs/` files that name `SENTRY_AUTH_TOKEN` move to a
new name, `SENTRY_ACTIONS_RO_TOKEN`, backed by a **dedicated Sentry Internal Integration**
`actions-read-prd` on `jikigai-eu` with the measured-minimum permission set — Issue & Event =
Read, Organization = Read, Project = Read, everything else No Access — stored as **one GitHub
repository secret** and nowhere else. The sweeper env drops the old name in the same commit, and
the sweeper's missing-secret path — silent today — is made to post on the tracker and red the run.
The one other repo-side reader of the personal token, `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`,
moves to the same secret. A retired-name ban lands as a second rule in the lint that already walks
the followthrough directory, so the canonical vendor env-var name cannot re-enter that population
without a red check. A rotation runbook records the agent-drivable path with its one honest
handoff. ADR-031 gains its fourth credential class and the DC-3 record; the post-mortem gains an
append-only addendum that supersedes its `### Still open` item.

**Why the name is the defect, not the store.** The CI path was never personal — the sweeper already
binds `secrets.SENTRY_IAC_AUTH_TOKEN` under the env name `SENTRY_AUTH_TOKEN`. The hazard is that
this name is the canonical Sentry env-var name, and Doppler `soleur/prd_terraform` exports ~160
names including a **personal** token under exactly it, so any workstation run of a followthrough
under `doppler run -c prd_terraform` binds the personal token silently. A name a personal credential
can satisfy is what gets retired.

**DC-3 is decided here, on a reading rather than on taste.** `inline-read-prd`'s `[event:read,
org:read]` returns **403** on the cron check-in endpoint that three followthroughs call (measured
2026-09-11, with a known-granted control returning 200 on the same URL). No existing read-only
credential covers the followthroughs' surface, so "reuse the existing read-only one" is not
available without widening a shared credential — which both lenses agreed must never happen. The
one remaining zero-mint shape — keep binding `SENTRY_IAC_AUTH_TOKEN` under the new name — satisfies
P1 but fails P2 (a repo-wide-reachable secret carrying `project:admin` and `alerts:write` for a
GET-only class) and ADR-031's own lifecycle-coupling rule. The dedicated integration is forced;
#7993 closes on that record.

**Reviewed 2026-09-11** by a seven-lens panel (DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, CTO devex, and a scoped strong-model consult). Every finding was re-verified in
this worktree before being folded in; the two that changed the plan most are recorded under
`## Research Reconciliation`: the `gh secret set` form the first draft prescribed does not exist
(and the in-repo precedent it copied is silently broken), and the sweeper's "loud fail" on a missing
secret is not loud at all.

## Enhancement Summary

**Deepened on:** 2026-09-11, after the seven-lens plan-review. Six further passes ran in parallel —
a verify-the-negative grep sweep over every repo-state claim, `security-sentinel`,
`observability-coverage-reviewer`, `test-design-reviewer`, `git-history-analyzer` (attribution),
and a `framework-docs-researcher` pass on Sentry's Internal Integration token semantics. Every
finding was re-verified in this worktree before being applied; two reviewer claims were checked
and narrowed rather than inherited.

### Key improvements

1. **A pre-existing command injection on the branch this PR edits.** `scripts/sweep-followthroughs.sh` expands `${!name+x}` on each `secrets=` name with no identifier check; a tracker body can put `a[$(…)]` there and it executes inside the sweeper job holding every forwarded secret. Measured by the security pass. Phase 3.1b now validates the name against `^[A-Z][A-Z0-9_]*$` before any indirect expansion and builds the comment from the validated name only (Guard 3 M5).
2. **The boot-trail keeps a `prd_terraform`-capable key for two values the plan already pins to literals.** After retiring the personal token, the two `if: always()` steps still carried `DOPPLER_TOKEN` solely to fetch `SENTRY_ORG` / `SENTRY_PROJECT`. Phase 3.5 hardcodes both (Rule D pins them anyway) and drops `DOPPLER_TOKEN` from both steps.
3. **Guard 3's RED test was inexpressible as first written.** The host suite `source`s the sweeper and calls `main`, but the `TRUNCATED_SWEEP` verdict — and therefore the `MISSING_SECRET` one — is raised in the `BASH_SOURCE == $0` block outside `main`. Phase 1.3 now runs `bash "$SUT"` end to end against a stub `gh`, and both the varq-ban and sweeper suites gain the ADR-193 floors they lack today.
4. **A set-but-empty binding is the most likely production breakage and Guard 3 could not see it.** `${{ secrets.X }}` on a deleted secret resolves to `""`, which passes the sweeper's set-ness test. Guard 3 gains an empty branch (M6).
5. **Three factual corrections.** `pull_request_target` is a live trigger on two workflows (`cla.yml`, `cla-evidence.yml`), not five, and neither binds a Sentry secret — the real repo-secret vector is a same-repo branch workflow run by a write collaborator. The provisioning jobs already declare `environment: web-platform-infra-apply`, which halves DC-5's stated cost. The `apply-web-platform-infra.yml` trigger block is at `:69-89`, not `:11-30`.
6. **Sentry facts from the vendor's own docs.** Creating an Internal Integration *auto-issues* its first token ("instantly generate an organization-wide authentication token"); up to 20 tokens per integration; token scopes are editable later but whether a permission edit propagates to an existing token is UNVERIFIED — so Phase 2.3's "re-read, and recreate if unchanged" branch stays; `POST /api/0/sentry-apps/{slug}/api-tokens/` exists and needs `org:write`, which is recorded in ADR-031 as a possible future login-free rotation rung and deliberately not minted here. The token's on-disk shape is not fixed across formats (`sntrys_…` vs 64-hex), so the normalise step asserts "non-empty, no whitespace, plausible length" and records the length rather than asserting hex.
7. **Argv exposure closed in two places.** `curl -H "Authorization: Bearer $TOK"` and `env -i … VAR="$(…)"` both put the value in `/proc/*/cmdline`; the probes read the header from a file in the trap directory and the per-script exercise exports inside a `bash -c`.
8. **The MCP fallback's `filename:` resolves under `.playwright-mcp/`**, not the trap directory, because an MCP argument cannot expand `$TOKEN_DIR`. The post-capture Bash call now shreds any file there newer than a pre-capture marker and fails if the expected path is absent.
9. **AC-P1 could pass on a 401.** A JSON-encoded stored value yields a TRANSIENT comment that the negative list did not catch; the assertion now requires the `### Sweeper run:` heading and no `HTTP 40[13]`.

### New considerations recorded

- Dashboard-side deletion of the integration yields daily 401 TRANSIENTs under a green run — recorded honestly as a failure mode with its discriminator (401 vs 403), not instrumented here.
- `/tmp` is tmpfs on this workstation (`findmnt`), so `shred -u` is effective here; the journaled-FS caveat is stated as conditional in the runbook.
- The boot-trail's named skip is now a `::warning::` annotation plus the step-summary write — step summaries are not reachable through `gh run view --log`, annotations are.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited reference | Probe | Result |
|---|---|---|
| #7946 | `gh issue view 7946 --json state,closedByPullRequestsReferences` | OPEN, `priority/p1-high` + `domain/engineering` + `type/security`, zero closing PRs. Live target. |
| #7993 | `gh issue view 7993` | OPEN, `action-required` + `decision-challenge` + `type/question`, p3. Body states DC-1/DC-2 need nothing and DC-3 "lands with #7946". Closes here once DC-3 is recorded. |
| PR #7975 | `gh pr view 7975 --json state,mergedAt` | MERGED 2026-09-09T22:35:53Z, merge commit `f6f5227aa`. Shipped the #7947 half only: `git show --stat` lists no followthrough file, no `ADR-031` edit, no post-mortem edit, no rotation runbook. Nothing of the #7946 half is on `main`. |
| The 2026-09-09 plan | read in full | Phase 3 (#7946) is unshipped; its Phase 0.2 was never run. Its population counts hold today (below). |
| #7797 | `gh issue view 7797` | OPEN (context only, the parent incident). Not a work target. |
| #7945 | issue body of #7946 | The vendor-escalation limb. Explicit Non-Goal. |
| `ADR-031` | `ls decisions/ \| grep ^ADR-031` | Two files. The one meant is `ADR-031-sentry-as-iac.md`. The ordinal collision is already tracked at #6493 and #6960 — no new issue. |
| Post-mortem `### Still open` | `grep -n "Still open" -A 4` | Verbatim at line 533 of `knowledge-base/engineering/operations/post-mortems/bash-x-credential-trace-exposure-postmortem.md`: "The ADR-031 migration is undone — the org-token surface is empty, so this credential class is still a personal token and the next rotation is still gated at an interactive login." |
| "the determination's ADR-031 reference" | `grep -n ADR-031` on the post-mortem and on `knowledge-base/legal/audits/2026-09-07-clo-determination-7797-credential-exposure-art-4-12.md` | The CLO determination file carries **no** `ADR-031` reference. The reference is in the post-mortem's `## Addendum — 2026-09-07 (#7797)` (line 391: "off the *user* auth token onto an org-level Internal Integration (ADR-031's `iac-terraform-prd` shape), which would make the next rotation agent-doable"). That is the sentence the new addendum supersedes. |
| Sixteen scopes on the personal token | live `GET /api/0/` → `.auth.scopes` (2026-09-11) | **Sixteen, exactly as the issue states:** `alerts:read, alerts:write, event:admin, event:read, event:write, org:admin, org:integrations, org:read, org:write, project:admin, project:read, project:releases, project:write, team:admin, team:read, team:write`. The 2026-09-09 plan could not verify this; it is now a reading. |
| Mechanism vs ADR corpus | `grep -l 'Internal Integration\|inline-read-prd' decisions/` | ADR-031 (the 2026-06-17 amendment) already establishes "narrow by adding a dedicated read-only integration, never by shrinking a shared one" and the store discriminator for `SENTRY_ISSUE_RO_TOKEN`. This plan extends that ADR; it contradicts no rejected alternative. |

### Property List (Phase 0.6b)

| # | Property (one observable outcome) |
|---|---|
| P1 | No `scripts/followthroughs/*.sh` execution — in CI or on a workstation — can bind a personal, human-account-scoped Sentry credential. Extended to the one other repo-side reader of that token, `fresh-host-boot-trail.sh`. |
| P2 | The credential those consumers bind carries only the scopes their measured API surface requires. |
| P3 | A rotation of that credential completes end-to-end driven by an agent, with no interactive step beyond the sanctioned auth handoff when the browser profile's session has expired. |
| P4 | ADR-031, the post-mortem's `### Still open` item, its 2026-09-07 addendum's ADR-031 sentence, and #7993's DC-3 all name the shape that exists after this ships. |

### Cut List (Phase 0.6b)

Each row names the authority grepped. Rows marked *(review)* were cut or re-justified by the
2026-09-11 panel.

| Mechanism | Property it would buy | Why it is cut, and what already covers it |
|---|---|---|
| **Rule E clause 2** — "a file consuming the new credential must name it in its xtrace refusal" (the 2026-09-09 plan's Guard 2 M6/M7 rows) | P1 durability | **Existing Rule C already reds on it, measured twice (planner 2026-09-11, Kieran review 2026-09-11).** `scripts/lint-shell-trace-credential-refusal.py` `check_rule_c` reports "the xtrace refusal does not cover every credential this file references" — and CI runs the lint `--changed --base origin/main`, which **bypasses both baselines** (`scoped = args.changed or args.paths; baseline = set() if scoped`, `:1123-1125`). Mutation on a scratch copy of `sentry-checkins-3859.sh`: consumption renamed, refusal left on the old name → `Unguarded: SENTRY_ACTIONS_RO_TOKEN`, exit 1. Same on `anthropic-admin-key-6297.sh` with the Sentry limb deleted from its three-term predicate. Only `git-data-birth-emitter-6982.sh` of the sixteen is in the A/B/C baseline, and this PR opens it. One residual gap is real and is fixed inline rather than re-implemented: a **single**-credential file whose limb is deleted leaves `[ -n "" ]`, which Rule C's `":+" not in window` branch misreads as an unconditional refusal (reproduced by Kieran). That is a five-line hardening of Rule C (Guard 2 below), not a new rule family. |
| **Rule E clause 1 hosted in the Python lint** | P1 durability | Kept as a property, moved host. The Python lint's rules are per-file properties over a repo-wide population; a directory-scoped name ban needs a `TARGET_DIR`, a cardinality floor and a `.test.sh`-inclusive walk — all of which `scripts/lint-followthrough-varq-ban.sh` already has (`TARGET_DIR`, `VARQ_BAN_MIN_PROBES`, `resolve()` sandbox exemption, a 147-line suite). Lands as a second rule there (Guard 1), indexed from `followthrough-convention.md`'s census so it is findable by someone grepping for the enforcement (CTO). |
| **Phase 3.9 — `secrets=` validation in `.claude/hooks/follow-through-directive-gate.sh`** | none in the list | *(review)* The first draft claimed `scripts/sweep-followthroughs.sh:392` "fails the tracker loudly". **It does not**: `fail()` is a `printf >&2` (`:63`) and the branch `return 0`s — no tracker comment, no `::error::`, run green. Phase 3.1b makes that path loud in this PR (comment on the tracker, `::error::`, run red at exit via the `TRUNCATED_SWEEP` pattern). With that in place a directive naming the retired credential fails visibly at its first sweep, and the write-time gate would buy one day. Cut stands, conditional on 3.1b. |
| **Phase 5 — a dedicated cutover soak probe** | the liveness signal | Not soak-gated: no AC here declares a time-gated close, so `followthrough-convention.md` §Soak does not require enrolment. `scheduled-followthrough-sweeper.yml` carries `workflow_dispatch:` (line 31) and `/soleur:ship` already dispatches every modified workflow post-merge (`ship/SKILL.md:2296`). The post-merge verdict is a dispatch plus a timestamp-gated assertion on the three affected open trackers (AC-P1), not a new probe file that would itself join Guard 1's population. |
| **A committed census fixture** (`followthrough-directive-census.txt`) | none | *(review)* A three-line snapshot kept forever under `specs/`, stale the day after; GitHub's issue-body edit history already provides the reversal source. Replaced by a live query at ship time (AC-P2) plus the before/after table in the PR body; the rewrite payloads are staged in the scratchpad with a resume recipe so a session that dies between merge and rewrite can resume. |
| **The C4 edge-label edit** (`model.c4:644`) | none | *(review)* Adds one credential name to a `technology` string at the cost of a JSON regeneration plus three suites; the existing label is not false (`SENTRY_AUTH_TOKEN` stays the Terraform provider's name) and no actor, system, container or relationship changes. Credential names live in ADR-031. Cut; the "no C4 impact" conclusion is backed by the enumeration in `## Architecture Decision` and a green `c4-count-parity` run. |
| **A throwaway `gh secret set ZZ_DRYRUN_7946`** in the dry run | none | *(review)* `gh secret set --no-store` prints the encrypted value without writing anything, so the dry run can assert the ciphertext length (48 bytes plus plaintext length) with zero prod writes. Cut W2′. |
| **`SENTRY_ISSUE_RO_TOKEN` into the sweeper env** (closing `git-data-rung2-evidence-capture.sh`'s "second channel: SKIPPED") | none in the list | A second Doppler→GitHub copy of a different credential — exactly the two-store coupling DC-3's architecture lens objected to — for a property this issue does not name. Cut; the script documents its own degradation. |
| **A compatibility shim** exporting the old name during cutover | none | Cut on 2026-09-09 and still cut: under `env -i` the sweeper forwards only names a directive lists, so a shim converts a visible fail into a silent TRANSIENT loop. |
| **A throwaway mint to discriminate `project:read` from `alerts:read`** | P2 | Not needed: the scope class is settled by Sentry's own permission source and public docs (below), and `fresh-host-boot-trail.sh`'s endpoint needs `project:read` regardless. One mint, verified post-mint. |
| **Mirroring the new token into Doppler** for local runs | none | Two stores double the rotation surface. The workstation path is the sweeper's own `dry_run` dispatch with the real secret (Phase 3.6); an explicit IaC-mirror assignment is the documented last resort. |
| **Renumbering the duplicated `ADR-031`** | none | Already tracked (#6493, #6960). Flagged in the amendment header only. |

### Live measurements taken 2026-09-11 (the readings the 2026-09-09 plan lacked)

Probe: `curl --disable --noproxy '*' -o /dev/null -w '%{http_code}'` with a bearer read from
Doppler into a shell variable, never printed, under an xtrace refusal. Statuses only.

**Token scopes** (`GET https://jikigai-eu.sentry.io/api/0/` → `.auth.scopes`):

| Credential | Store | Scopes |
|---|---|---|
| `inline-read-prd` (`SENTRY_ISSUE_RO_TOKEN`) | Doppler `soleur/prd` (also present byte-identical in `prd_terraform`) | `[event:read, org:read]` |
| `iac-terraform-prd` (`SENTRY_IAC_AUTH_TOKEN`) | GitHub repo secret; mirrored in Doppler `soleur/prd` | `[alerts:read, alerts:write, event:read, org:read, project:admin, project:read, project:write]` |
| personal (`SENTRY_AUTH_TOKEN`, Doppler `soleur/prd_terraform`, 71 chars) | Doppler `prd_terraform` only | the sixteen listed under Premise Validation, including `org:admin`, `org:integrations`, `event:admin`, `team:admin` |
| Doppler `soleur/prd` `SENTRY_AUTH_TOKEN` (64 chars) | a **different** value — the `web-platform-ci` runtime token | `[org:ci, org:read, project:read, project:releases, project:write]` |

So the ambient hazard is specifically `doppler run -c prd_terraform`; `-c prd` binds the runtime
integration token under the same name, which is over-scoped for a read but is not personal.

**Followthrough endpoint surface under `inline-read-prd` `[event:read, org:read]`**, and the control:

| Endpoint (GET) | Callers | `jikigai-eu` | `jikigai` (legacy slug) | Control (`iac-terraform-prd`) |
|---|---|---|---|---|
| `/api/0/organizations/{org}/` | 1 (`sync-health-residual-5689.sh`) | **200** | **403** | — |
| `/api/0/organizations/{org}/events/` | 9 | **200** | 403 | — |
| `/api/0/organizations/{org}/monitors/{slug}/checkins/` | 3 (`community-monitor-checkin-soak-5728.sh`, `ghcr-minter-live-6031.sh`, `sentry-checkins-3859.sh`) | **403** | 403 | **200** on `jikigai-eu`, 403 on `jikigai` |
| `/api/0/projects/{org}/{project}/issues/` | 1 (`sync-health-residual-5689.sh`) | **200** | 404 | 200 |
| `/api/0/projects/{org}/{project}/events/` — **not a followthrough**; `fresh-host-boot-trail.sh:178` | 1 | **403** | — | 200 |

Hosts differ per consumer and Rule D pins a literal host, so Phase 2.3 re-probes each consumer's
**exact** host + org + path: most followthroughs use `https://sentry.io/api/0` with org
`jikigai-eu` (which the region router serves — 200 above); `anthropic-admin-key-6297.sh` uses
`${SENTRY_HOST}`; the boot-trail uses `https://de.sentry.io` with Doppler-read `SENTRY_ORG` /
`SENTRY_PROJECT` — read 2026-09-11 as `jikigai-eu` / `web-platform`.

**Why the check-in endpoint 403s, from the authority rather than from the status alone.** Sentry's
`MonitorEndpoint` (`src/sentry/monitors/endpoints/base.py`, `master`) declares
`permission_classes = (ProjectAlertRulePermission,)`, whose `scope_map["GET"]` is
`["project:read", "project:write", "project:admin", "alerts:read", "alerts:write"]`
(`src/sentry/api/bases/project.py`). The public reference page for
`GET /api/0/organizations/{organization_id_or_slug}/monitors/{monitor_id_or_slug}/checkins/`
(`docs.sentry.io/api/crons/retrieve-checkins-for-a-monitor/`, fetched 2026-09-11) lists the same
five. `event:read` is not among them. The project events endpoint (`docs.sentry.io/api/events/list-a-projects-error-events/`)
requires one of `project:admin`, `project:read`, `project:write`.

**Derived minimum for the union of both consumers:** `[event:read, org:read, project:read]`.
`project:read` is chosen over `alerts:read` because it is the one scope that satisfies **both** the
check-in endpoint and the boot-trail's project-events endpoint; `alerts:read` would satisfy only the
first and force a second read scope. Dashboard form: Issue & Event = Read, Organization = Read,
Project = Read, everything else No Access. Sentry's permission model may hand back implied scopes
from a selected level; AC-6 asserts the returned `.auth.scopes` is **exactly** that triple — an
implied extra is a finding that blocks the cutover and is recorded, not accepted as a superset.

**The legacy org slug is dead for every credential.** `jikigai` returns 403 for the org endpoint,
the events endpoint and the check-in endpoint under both the read-only and the IaC token, and 404
for project issues. `sentry-checkins-3859.sh` sets `ORG="jikigai"` (its tracker #3859 is CLOSED,
so it is not swept, but the file stays in the population) and `sync-health-residual-5689.sh`
defaults `ORG="${SENTRY_ORG:-jikigai}"` — the sweeper env sets no `SENTRY_ORG`, so that open
tracker (#5689) has posted `TRANSIENT: Sentry issues API returned HTTP 404 (host=sentry.io,
org=jikigai, project=web-platform)` on every sweep, most recently 2026-09-10T20:12Z. That is a
live dark probe this PR opens anyway; both slugs move to `jikigai-eu` here (Phase 3.3). The
`article-30-register.md` PA-8 §(d) 2026-05-21 note records the `jikigai` org as cancelled
vendor-side, which is the reason.

### Repo facts this plan builds on

All verified in this worktree on 2026-09-11 (`hr-when-in-a-worktree-never-read-from-bare`).

- `grep -rl SENTRY_AUTH_TOKEN scripts/followthroughs/ | wc -l` = **16** (fourteen `.sh`, one of them comment-only — `git-data-birth-emitter-6982.sh` — plus `anthropic-admin-key-6297.test.sh` and `zot-soak-6122.test.sh`, which set env stubs such as `SENTRY_AUTH_TOKEN=stub` at `zot-soak-6122.test.sh:141,302` and `anthropic-admin-key-6297.test.sh:279` and mention the name in comments at `:109,:253`). `grep -l 'SENTRY_AUTH_TOKEN:+x' scripts/followthroughs/*.sh | wc -l` = **13** — the `.sh` files whose ADR-202 xtrace refusal names the credential in its predicate; the three `.sh` without one are `git-data-birth-emitter-6982.sh` (comment only) and the two `.test.sh` stubs.
- `.github/workflows/scheduled-followthrough-sweeper.yml:93` — `SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_IAC_AUTH_TOKEN }}`. The sweeper is already org-level; the name is the residual. The workflow carries `workflow_dispatch` with a `dry_run` input (`:31-33`), which `scripts/sweep-followthroughs.sh` honours as `DRY_RUN=1` — "skip close/comment, only print actions" (`:15`, `:483`, `:560`).
- `scripts/sweep-followthroughs.sh` runs each probe under `env -i` forwarding only the directive's `secrets=` names (`:99` parser), re-evaluates trackers closed within `CLOSED_LOOKBACK_DAYS=14` (`:44`), carries its **own unconditional** xtrace refusal (`:33-35`, exit 78), posts verdict comments with `printf '%s' "$body_msg" | gh issue comment "$issue_num" --repo "$REPO" --body-file -` (`:488`, `:565`), and reds the run only on `TRUNCATED_SWEEP` — set inside `main()` (`:578`, `:611`) but **read in the `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` block after `main` returns** (`:698-707`), so a sourced `main` never exits non-zero for it. **Its missing-secret branch is silent** — `fail "issue #$issue_num: required secret '$name' not set in workflow env — leaving issue open"` then `return 0` (`:391-392`), where `fail()` is `printf … >&2` (`:63`). No comment, no annotation, run green. **The same loop expands `${!name+x}` on a name it never validates** (`:384-388` — the only normalisation is `name="${name// /}"`): a directive `secrets=a[$(cmd)]` executes `cmd` inside the sweeper job with every forwarded secret in its env (measured by the security pass). And a name that is **set but empty** — what `${{ secrets.X }}` resolves to when the repo secret is absent — passes the `${!name+x}` set-ness test and is forwarded as `""`. The scheduled cron is `0 18 * * *` (`scheduled-followthrough-sweeper.yml:30`); runs observed at ~20:12 UTC.
- `scripts/sweep-followthroughs.test.sh` drives the SUT with `source "$SUT"` (`:116`, `:439`, `:717`, `:782`, `:831`) and carries **no ADR-193 floor**; neither does `scripts/lint-followthrough-varq-ban.test.sh`. `scripts/lint-shell-trace-credential-refusal.test.sh` carries `MIN_ASSERTIONS=61` (`:584`) as a measured total, not a per-guard tally. `scripts/guard-vacuity-floor.test.sh` derives its population from suites that carry a recognisable floor, so a suite gaining one enrols there.
- **Open trackers whose directive names the retired credential** (`gh issue list --label follow-through --state open --limit 200`, 53 open, queried 2026-09-11): **#6604**, **#6297**, **#5689**. The `--limit 200` is load-bearing (default 30). Closed-within-14-days trackers are enumerated by the same query with `--state closed` at ship time; AC-P2 is the live query, not a snapshot.
- **Rule D drawdown, re-measured.** `scripts/lint-shell-trace-credential-refusal-d.baseline.txt` carries 21 `scripts/followthroughs/` entries; **13 of the 16 migrating files are among them** (`comm -12`), not 21 — eight baselined followthroughs are untouched here. **`apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` is line 27 of the same baseline** (Kieran) and the lint reports its `:177` curl today, so Phase 3.5 remediates it and deletes that line too — 14 baseline lines in all. `--changed` bypasses the baseline (lint `:1119-1125`), so each touched file must reach Rule D form: `--disable` as curl's first argument, `--noproxy '*'`, and every env-settable destination (`$SENTRY_ORG`, `$SENTRY_HOST`, `$API_HOST`) compared against a literal before use. The lint prints the exact remedy per site (run 2026-09-11 on three files: 5 findings).
- Only `git-data-birth-emitter-6982.sh` of the sixteen is in the A/B/C baseline (`lint-shell-trace-credential-refusal.baseline.txt`, 27 followthrough entries). It binds `BETTERSTACK_QUERY_PASSWORD` through `${!v:-}` with no refusal; the lint's own remedy text for it was captured 2026-09-11.
- `scripts/lint-followthrough-varq-ban.sh` (87 lines): walks `$TARGET_DIR/*.sh`, skips `*.test.sh` (`:58`) and full-line comments **for its own rule**, floor `VARQ_BAN_MIN_PROBES` default 10 keyed on the resolved default dir (`:75-77`), exit 0/1/2. Registered in `scripts/test-all.sh` with its `.test.sh`, and `scripts/test-all.sh:1811` runs the lint **live against the production tree** — so Guard 1 and the sixteen-file migration must land in the same commit. Baseline reading this branch: `clean (67 probe(s) scanned)`.
- `scripts/lint-shell-trace-credential-refusal.py` is registered twice in `scripts/test-all.sh` (`:1636` suite, `:1643` repo-wide) and in `.github/workflows/ci.yml:180` as `--changed --base origin/main`.
- `.claude/hooks/follow-through-directive-gate.sh` validates `script=` and `earliest=` only (`:164-225`); it never reads `secrets=`.
- `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh:64` — `SENTRY_AUTH_TOKEN=$(doppler secrets get SENTRY_AUTH_TOKEN --plain -p soleur -c prd_terraform …)`; `:70` masks it with `::add-mask::`; `:178` sends it to `https://de.sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/events/`. Its two callers are the `web_host_create` and `web_host_replace` jobs in `.github/workflows/apply-web-platform-infra.yml` (`:5175-5196`, `:5597-5615`), each with an `env:` block carrying `DOPPLER_TOKEN` and `JOB_STATUS` — and `DOPPLER_TOKEN` is there solely so the script can fetch `SENTRY_ORG` / `SENTRY_PROJECT` (`:71-72`), values read 2026-09-11 as `jikigai-eu` / `web-platform`. Both provisioning jobs already declare `environment: web-platform-infra-apply` (`:5250`, `:5859`). **That workflow fires on `push` to `main` for `apps/web-platform/infra/**` and for itself** (`on:` block at `:69-89`), and its `apply` job runs on push (`:387-391`) — so this PR's merge triggers a production apply (an expected no-op plan; no `.tf` changes) and it is registered as W6. `apps/web-platform/infra/doppler-download-error-channel.test.sh:861-1010` carries reader-scoped assertions on the boot-trail (AC-M0, AC-M8) but pins none of its Doppler reads. `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh:377-383` (AC13) greps the file for `doppler secrets get SENTRY_AUTH_TOKEN .*-c prd_terraform`; it runs from `.github/workflows/infra-validation.yml`, and its per-job awk extraction at `:357-374` (AC8d) is reusable for the workflow-binding assertion. Its own comment explains the history: the repo secret of that name was unset, so a `secrets.*` binding self-skipped silently — the class AC13 exists to prevent.
- **`gh secret set` (gh 2.92.0) reads the value from standard input when `--body` is not given** (`-b, --body string — The value for the secret (reads from standard input if not specified)`); it has **no `--body-file` flag**, and `--body -` stores the literal string `-`. Kieran measured this with `--no-store`: a 30-byte stdin under `--body -` yields a 68-char ciphertext (1-byte plaintext); omitting `--body` yields 104 chars (30 bytes). **`scripts/rotate-x-api-secret-bootstrap.sh:56` uses `--body -` and is therefore silently broken** — a separate defect, filed by this plan (Phase 4.6). `--no-store` prints the encrypted, base64-encoded value instead of storing it, which is the zero-write dry-run probe.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` names the retired credential **three** times (`:57` stub, `:88` Soak table row, `:97` prose) and declares the varq-ban lint "the EXECUTABLE FORM of that doc's canonical census". `scripts/sweep-followthroughs.sh:28` spells the name in its worked `env -i` example. `plugins/soleur/skills/schedule/SKILL.md:76` ships "exposes the GitHub secret `SENTRY_IAC_AUTH_TOKEN` as env `SENTRY_AUTH_TOKEN`" to customers.
- **Other workstation readers of the personal value** (architecture-strategist): `apps/web-platform/infra/cutover-verify.sh:222` reads `SENTRY_AUTH_TOKEN` and its generated baseline header (`:318`) prints `doppler run -p soleur -c prd_terraform --` — an active steer onto the personal token; `scripts/sentry-alert-live-fidelity.sh`, `apps/web-platform/scripts/sentry-monitors-audit.sh`, `apps/web-platform/scripts/configure-sentry-alerts.sh`, `apps/web-platform/scripts/assert-byok-rules-exist.sh` are `${SENTRY_AUTH_TOKEN:?}` readers that CI binds from the IaC secret. All are outside this plan's two consumer classes and are enumerated in the revocation deferral (Phase 4.6), whose recommended shape fixes them at once.
- `knowledge-base/engineering/architecture/diagrams/model.c4:644` — the `github -> sentry` edge's `technology "HTTPS (cron check-in API + Terraform provider, SENTRY_AUTH_TOKEN)"`. That name is the Terraform provider's required env-var name (`.github/workflows/apply-sentry-infra.yml:53`, `apps/web-platform/infra/sentry/main.tf:20`), sentry-cli's, and `next.config.ts:156`'s. Not edited (Cut List).
- ADR-031 amendment precedent: the 2026-06-17 `inline-read-prd` block (`ADR-031-sentry-as-iac.md:284-300`) — permission set, resulting scopes, store and its reason, mint path, host. ADR-031 also states "Sentry secrets stay in GitHub repository secrets" (`:157`) with the `doppler run` consumer as the recorded exception, and the store rule diverges from `AP-008` in `knowledge-base/engineering/architecture/principles-register.md`, which ADR-031 already justifies. **Two** workflows carry `pull_request_target` as a live trigger — `cla.yml` and `cla-evidence.yml` (`awk '/^on:/,/^jobs:/'` on every match; `apply-sentry-infra.yml`, `secret-scan.yml` and `skill-security-scan-pr-trailer.yml` mention it only in comments explaining why they do *not*) — and neither checks out the PR head or binds a Sentry secret, so fork reachability of the new secret is nil. The real repository-secret vector is a same-repo branch workflow run by a write collaborator (two on this public repo). That is the cost sentence the amendment carries.
- **Sentry Internal Integration facts, from the vendor's docs (fetched 2026-09-11).** Creating an internal integration *auto-issues* its first token — `docs.sentry.io/integrations/integration-platform/internal-integration`: "Upon creation, these integrations instantly generate an organization-wide authentication token" — and "You can manage up to 20 tokens per integration". Token scopes "can be edited later" (`docs.sentry.io/api/permissions/`); whether a permission edit propagates to an already-issued token is **UNVERIFIED**, which is why Phase 2.3 re-reads and recreates if unchanged. `POST /api/0/sentry-apps/{slug}/api-tokens/` exists and requires `org:write` (`docs.sentry.io/api/integration/update-an-existing-custom-integration/` for the sentry-apps write scope) — a login-free rotation rung is therefore *possible* with an `org:write` credential, which is a wider grant than the token it would rotate; recorded in ADR-031 as a future option, not taken. Token format is not fixed across generations (`sntrys_<base64>_<sig>` per `getsentry/team-sdks#6`; the three existing integration tokens here are 64 chars), so nothing asserts hex.
- **`@playwright/mcp@0.0.78` resolves `filename:` under its own output directory** (`.playwright-mcp/` in the worktree, gitignored, default umask), and an MCP argument cannot expand `$TOKEN_DIR`; the trap directory is reachable only from the Bash path. `/tmp` is `tmpfs` on this workstation (`findmnt -n -o FSTYPE /tmp`), so `shred -u` of a `mktemp -d` path is effective here.
- The post-mortem's own contract for edits: `## Addendum — 2026-09-08` opens with "Append-only. Nothing above is rewritten; this section supersedes the parts it names." The 2026-09-09 learning `2026-09-09-i-swept-by-literal-when-the-property-was-a-claim.md` records an append-only violation as a session error. This plan appends; it does not edit `### Still open` in place.
- Mint path, still closed by measurement: `POST /api/0/organizations/{org}/sentry-apps/` needs `org:admin` or `org:integrations`, which no org-level Soleur credential carries (only the personal token does — using it to mint its own replacement would be circular and is not done). The dashboard mint at `/settings/developer-settings/new-internal/` is proven automatable with no CAPTCHA, MFA or passkey once the session is authenticated (#5495 / #5496; `2026-06-17-sentry-internal-integration-mint-needs-org-admin-and-skill-backtick-scripts-rule.md`). Sentry Internal Integrations are org-wide; there is no per-project scoping to narrow.
- Browser surfaces: the Playwright MCP **failed to connect in this planning session**; `agent-browser` 0.22.3 is installed and its Bash path is the one where a single trap scope can hold capture, decode, store, verify and shred in one process (Bash tool calls do not share a shell, so a `trap` set in one MCP-adjacent call has fired before the next call runs — spec-flow P0). The shipped PreToolUse interceptor `plugins/soleur/hooks/browser-snapshot-credential-guard.sh` denies any un-piped `agent-browser snapshot`; `agent-browser get value <sel> > "$TOKEN_FILE"` (`agent-browser/SKILL.md:250`) writes the raw value; `browser_evaluate(filename:)` on the MCP path writes it **JSON-encoded**.
- Capture-and-store precedents: `plugins/soleur/skills/cf-token-scope/references/widen-playbook.md` §"Full-power-session leak constraints" (no snapshot or screenshot of the token panel; `filename:` on every `browser_snapshot`; redactor on the file; shred). `scripts/rotate-x-api-secret-bootstrap.sh` for the trap-and-shred shape — but **not** for its `gh secret set` line (see above).
- Highest ADR ordinal on this branch: ADR-216. **No new ADR is claimed** — this plan amends ADR-031.
- `plugins/soleur/test/components.test.ts` `SKILL_DESCRIPTION_WORD_BUDGET = 2400`; no skill `description:` is edited here.
- `python3 plugins/soleur/skills/incident/scripts/redact-engine.py <path>` takes the path as `argv[1]` (usage line verified); stdin redirection alone exits 2.
- Test runners: `bash scripts/test-all.sh scripts`; `bash scripts/lint-orphan-test-suites.sh`; `bash apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`; `bash plugins/soleur/test/c4-count-parity.test.sh`; `bash scripts/lint-legal-registers.sh`; `bash scripts/sweep-followthroughs.test.sh`.

### Institutional learnings that bind this plan

| Learning | Constraint |
|---|---|
| `knowledge-base/project/learnings/2026-06-17-sentry-internal-integration-mint-needs-org-admin-and-skill-backtick-scripts-rule.md` | An API 403 on `sentry-apps/` is the trigger for the dashboard attempt, not operator-only evidence. No bare backtick `scripts/` reference in a skill body. |
| `knowledge-base/engineering/architecture/decisions/ADR-202-enforce-runtime-state-hazards-with-a-carried-self-refusal.md` | Rule C is the "guarded one credential, consumed another" rule; this plan relies on it rather than re-implementing it, and hardens its one measured blind spot. |
| `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` | Exit 0 auto-closes; ambiguity maps to TRANSIENT (2). The `${VAR:?}` form is banned. Sentry-rate soaks pin `start=` after deploy. |
| `knowledge-base/engineering/operations/runbooks/sentry-issue-read.md` | Probe each endpoint; never reason from one endpoint's 200 to another's. (This plan's 0.2 table is that discipline applied, and it found the 403.) |
| `knowledge-base/project/learnings/2026-09-10-six-instruments-reported-could-not-measure-as-clean.md` | For every instrument, state what it prints when it cannot measure. The sweeper's missing-secret path and the boot-trail's unbound case both read as "clean" today; both are made to name the condition. |
| `knowledge-base/project/learnings/2026-09-09-i-swept-by-literal-when-the-property-was-a-claim.md` | Append-only records are appended to, never rewritten; sweeps are by claim, not by literal. |
| `knowledge-base/project/learnings/2026-05-18-vendor-token-mint-and-oci-image-content-carrier-patterns.md` | `browser_evaluate` **with** `filename:`; the value is JSON-encoded on disk and must be decoded before storage. |
| `knowledge-base/project/learnings/2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md` | Derive the edit list from grep, including orphan suites — which is how AC13 in the infra observability suite was found. |
| `knowledge-base/project/learnings/2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md` | Guard 1's floor and its `TARGET_DIR` sandbox exemption are inherited from a lint that already distinguishes the two. |

### Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (65 open) against every planned
path token on 2026-09-11.

- **#3740** — "author sentry-post-merge-smoke.yml automated workflow". Matched on `SENTRY_AUTH_TOKEN` only. **Acknowledge:** a post-merge smoke workflow is a future consumer of the naming convention, not of this credential; the ADR-031 amendment records the new name where its author will read it. Stays open.
- **#7098** — "audit the 56 `run:` bodies whose `set` omits -e". Matched on `apply-web-platform-infra.yml` only. **Acknowledge:** this plan adds two `env:` lines to steps whose `run:` already carries `set -euo pipefail`; it neither fixes nor worsens the audit. Stays open.
- No other overlap.

### Skill Description Budget

No `description:` field is edited. `SKILL_DESCRIPTION_WORD_BUDGET = 2400`, suite green on `main`.
No `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Research Reconciliation — Spec vs. Codebase

| Claim (from #7946, #7993, the brief, the 2026-09-09 plan, or this plan's first draft) | Reality, measured 2026-09-11 | Plan response |
|---|---|---|
| "`scripts/followthroughs/*.sh` consumers read a PERSONAL auth token." | Stale for CI: the sweeper binds `secrets.SENTRY_IAC_AUTH_TOKEN` under the personal-looking name. True for any workstation run under `doppler run -c prd_terraform`. | Retire the **name**; the store stays GitHub repo secrets. |
| "The org-token surface (`/settings/auth-tokens/`) holds zero tokens, so ADR-031 is un-adopted." | Conflates Org Auth Tokens with Internal Integrations (`/settings/developer-settings/`), of which three exist and two are live in the repo. | The ADR-031 amendment states the surface distinction. |
| "DC-3 is a taste fork: two lenses disagree on the same facts." (#7993) | The fork was conditional on Phase 0.2 returning all-200 under `[event:read, org:read]`. It returned **403 on check-ins**. The premise of the reuse arm is false. | DC-3 is decided by the reading, recorded in three places. |
| "The sweeper fails a tracker loudly when a directive names a secret absent from the env." (this plan's first draft; the 2026-09-09 plan) | **False.** `sweep-followthroughs.sh:392` prints to stderr and `return 0`s; no comment, no annotation, run green. Confirmed by two reviewers and by reading the function. | Phase 3.1b makes it loud; AC-P1 is timestamp-gated so a stale comment cannot pass it. |
| "`gh secret set NAME --body-file -` reads the value from stdin; the rotate-x script is the precedent." (first draft) | **Fabricated.** `gh` 2.92.0 has no `--body-file` on `secret set`; stdin is read when `--body` is omitted; `--body -` stores `-`. The precedent at `rotate-x-api-secret-bootstrap.sh:56` is silently broken. | The form is `… \| gh secret set SENTRY_ACTIONS_RO_TOKEN`; the dry run proves it with `--no-store`; the precedent's defect is filed. |
| "The rename drags in a 21-entry Rule D drawdown." (2026-09-09 plan) | **13** of the migrating followthroughs are baselined, plus the boot-trail at line 27 — 14 lines. | Budgeted at 14 in Phases 3.3 and 3.5. |
| "Rule E must red when a file's refusal predicate does not name the new credential." | Existing Rule C already does, with baselines bypassed in CI's `--changed` mode — measured by mutation twice. One blind spot (`[ -n "" ]`). | Rule E clause 2 cut; Rule C hardened (Guard 2). |
| "`sentry-checkins-3859.sh` may need its slug moved (any 404 on `jikigai`)." | The slug is dead for every credential (403/404), and a second, **open** tracker's probe (#5689) has been dark on the same slug daily. | Both files move to `jikigai-eu` in Phase 3.3. |
| "One trap scope holds capture through shred." (first draft) | True only inside one Bash process. On the MCP path the capture is a separate tool call, so a trap set before it has already fired. | The `agent-browser` Bash path is primary; on the MCP path the trap scope begins at the post-capture Bash call and the pre-capture call only creates the 0700 directory. |
| "The decode step is `json.loads`." (first draft) | Surface-dependent: `browser_evaluate(filename:)` JSON-encodes; `agent-browser get value` writes raw text. | One tolerant normalise step, then an assertion on the token's shape. |
| "Rotation is operator-gated: password plus 2FA." (#7946) | True only for the **session**. The mint form itself has no human gate (#5495). | P3 is "no step beyond the sanctioned auth handoff", stated honestly in the runbook. |
| "The determination's ADR-031 reference." (#7946) | The CLO determination audit has none; the reference lives in the post-mortem's 2026-09-07 addendum. | The new addendum supersedes that sentence by name. |
| "No Terraform write." (first draft) | `apply-web-platform-infra.yml` fires its `apply` job on any push to `main` touching `apps/web-platform/infra/**` or itself. | Registered as W6 (expected no-op plan); ship must not re-dispatch that workflow bare. |

## User-Brand Impact

**If this lands broken, the user experiences:** the daily follow-through sweep silently stops
verifying anything Sentry-backed. Concretely: the repo secret exists but the sweeper env key is
mistyped, or the stored value is the JSON-encoded form, or the new token 403s on an endpoint the
probe table missed — every Sentry probe returns TRANSIENT, trackers that should close stay open,
trackers that should fail stay quiet, and `community-monitor-checkin-soak-5728.sh` stops
confirming a scheduled workflow still fires. Or the boot-trail step on the next fresh-host
provision reads "no events" when it actually could not authenticate, and a dark boot is reported
as a clean one. Today the sweeper already has one such silent mode (a missing secret), and this
PR removes it rather than adding to it.

**If this leaks, the user's infrastructure credentials are exposed via:** an agent transcript,
the #7797 class exactly. The mint is a browser session against a page that renders a
freshly-generated token in a readonly textbox — the node class measured to leak on both browser
surfaces (`phase-0-measurement.md` row D) — and the capture-decode-store chain handles the
plaintext on disk. A wrong `filename`, a snapshot of the panel, or a `--body "$TOKEN"` argument
puts a live org-level token into the session log.

**Brand-survival threshold:** single-user incident.

A Soleur operator is non-technical by construction and pays every rotation in attention. The
personal token is bound to one human account with `org:admin`, so its blast radius is that
person's entire Sentry organization — member management, integration creation, project deletion.
Retiring the name that can bind it, and proving the replacement rotates under an agent, removes a
standing exposure and a standing bill. Every control here is judged on whether it holds when the
agent does not remember: the name ban is a lint, the predicate coupling is Rule C, the store is
one repo secret, the sweeper names a missing secret on the tracker, and the runbook's failure
table names a next action for every row.

`requires_cpo_signoff: true` follows from the threshold. Product has no UI surface here; the
sign-off is discharged as on 2026-09-09 — the escalated plan-review panel at plan time and
`user-impact-reviewer` at review time (see `## Domain Review`).

## Non-Goals

- **#7945** — the vendor-escalation limb. Out of scope; no correspondence drafted or referenced.
- **#7980** — the Playwright-MCP residual from #7947. Tracked separately. The mint here is performed under the shipped #7947 discipline, which is the reason the split put #7947 first.
- **#7797 itself.** Context only; its determination is not amended.
- **Revoking the personal token's VALUE in Doppler `soleur/prd_terraform`.** Deferred to its own issue, filed by this plan (Phase 4.6). After this PR the personal value has **no repo-side reader via Doppler** — `fresh-host-boot-trail.sh` was the last — but `SENTRY_AUTH_TOKEN` remains the canonical vendor env name for the Terraform provider, sentry-cli and `next.config.ts`, and a workstation `doppler run -c prd_terraform -- terraform …` still binds the personal value; so do the five workstation readers enumerated under Repo facts, and `cutover-verify.sh:318` actively prints that invocation. "No reader" is a statement about bindings, not reachability: the provisioning job still holds a `DOPPLER_TOKEN` that can read `prd_terraform`. The revocation issue's recommended shape is recorded there: replace the **value** under that name in `prd_terraform` with the `iac-terraform-prd` token (already mirrored in `soleur/prd` as `SENTRY_IAC_AUTH_TOKEN`), so the name stays, the Terraform provider keeps working, and the personal credential behind it goes. Static reachability is re-derived in that PR with a stated command.
- **Renumbering `ADR-031`.** #6493 / #6960.
- **Widening `inline-read-prd` or narrowing `iac-terraform-prd`.** Both are shared credentials; ADR-031's rule is narrow by adding, never by mutating.
- **A Doppler mirror of the new token.** Single store (Cut List).
- **An Actions *environment* secret instead of a repo secret.** Strictly narrower (a same-repo branch workflow cannot reach it) at the same single-store cost, and cheaper than first stated: the two provisioning jobs already declare `environment: web-platform-infra-apply`, so only the sweeper needs a new environment (a repo-settings write plus one `environment:` key). It still diverges from the two sibling Sentry secrets. Recorded as DC-5 in this branch's `decision-challenges.md` with the corrected cost and as a considered alternative in the ADR-031 amendment; not taken here.
- **The `git-data-rung2-evidence-capture.sh` second channel.** Cut List.
- **Fixing `scripts/rotate-x-api-secret-bootstrap.sh:56`.** A separate defect in a separate credential's rotation script; filed, not fixed here.

## DC-3 — Decision

**Decided: mint the dedicated Internal Integration `actions-read-prd`.** Recorded in three places
by this PR: this section; a `## DC-3 — RESOLUTION` entry appended to
`knowledge-base/project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/decision-challenges.md`
(the file #7993 links to, beside the DC-1 resolution it already carries — a pointer to the ADR
record plus the one-line reading, not a third copy of the argument); and the ADR-031 amendment,
which is the canonical record.

**Deciding reason — a measurement, not a preference.** The reuse arm existed only under the
condition "Phase 0.2 shows all four endpoints return 200 under `[event:read, org:read]`". Taken
2026-09-11: three do, the check-in endpoint does not (403, with a known-granted control at 200 on
the same URL, and the scope class confirmed from Sentry's permission source and public docs). The
existing read-only integration is under-scoped for three of the followthroughs, including the one
`## User-Brand Impact` names. The only way to reuse it would be to widen a credential shared with
the no-SSH inline reader, which both lenses agreed is never done. So there is nothing to reuse.

**The other zero-mint shape, and why it is not taken.** The sweeper could simply keep binding
`secrets.SENTRY_IAC_AUTH_TOKEN` under the new name. That satisfies P1 (it is not personal) at zero
mint cost and zero browser session. It fails **P2** — a secret reachable from every workflow in the
repository, from any branch a write collaborator pushes, carrying `project:admin`, `project:write`
and `alerts:write` for a class of consumers that only ever issues GETs — and it couples the
followthroughs' lifecycle to the IaC apply lifecycle, the exact coupling ADR-031's 2026-05-19
revision rejected for `web-platform-ci`. P2 is the stated ask in #7946 ("the measured minimum, not
the inherited maximum"), and P2 alone is what buys the browser session and its leak controls.

**What the decision also settles.** The architecture lens's residual objection — "a fourth
credential class with an identical scope set widens the rotation surface" — dissolves with its
premise: the scope set is not identical (`project:read` is the delta), and the boot-trail's
project-events endpoint needs that same delta, so one new integration retires the personal
token's last two consumer classes together rather than one. The CTO lens's store argument (a CI
consumer takes a GitHub repo secret; a `doppler run` inline consumer takes a Doppler secret;
never copy one into the other) is corroboration and becomes the ADR-031 store discriminator.

**What would have flipped it.** All four endpoints at 200 under `[event:read, org:read]`. It did
not happen; the reading is recorded so the fork is not re-opened from memory.

**#7993 disposition.** DC-1 is resolved and acted on (PR #7975 merged). DC-2 was measured
not-reproduced and is informational. DC-3 is decided above. `Closes #7993`.

## Implementation Phases

Phase order is contract-first: the secret and the integration exist before any file consumes the
new name; the sweeper env, Guard 1 and the file migration land in one commit; directive rewrites and
the sweeper dispatch happen at ship time, after merge, in the same session. Within the PR the diff
is presented as **two commits**: first the Rule D remediation plus the org-slug pins plus the
boot-trail curl fix, all under the old name (a mechanical diff that passes CI on its own); then the
rename plus Guard 1 plus the sweeper env change. Squash-merge collapses them; review reads them apart.

**Headless checkpoints.** A one-shot pipeline halts twice for per-command authorization and
resumes autonomously in between: at Phase 2.1 for W1 and W2, and at Phase 5.2 for W3 and W4. The
plan's existence is not authorization for either (`hr-menu-option-ack-not-prod-write-auth`).

### Phase 0 — Preconditions (read-only; nothing written except the probe record)

**0.1 Re-confirm the populations** on this branch: `grep -rl SENTRY_AUTH_TOKEN scripts/followthroughs/ | wc -l` = 16; `grep -l 'SENTRY_AUTH_TOKEN:+x' scripts/followthroughs/*.sh | wc -l` = 13; the `comm -12` against the Rule D baseline = 13, plus `grep -c fresh-host-boot-trail scripts/lint-shell-trace-credential-refusal-d.baseline.txt` = 1; `bash scripts/lint-followthrough-varq-ban.sh` reports `clean (N probe(s) scanned)` with N ≥ 10 — record N as Guard 1's floor input. Also sweep the repo for **claims** about the old binding that a rename would falsify: `git grep -n 'SENTRY_AUTH_TOKEN' -- '*.test.sh' '*.test.ts' '.github/workflows/*.yml'` and list every hit against the two consumer classes; any test asserting the sweeper binds the old name, or the boot-trail reads Doppler, is added to `## Files to Edit`. (Known today: `soleur-host-bootstrap-observability.test.sh` AC13.) If any count moved, `## Files to Edit` moves with it.

**0.2 Record the endpoint table** in `knowledge-base/project/specs/feat-one-shot-7946-sentry-org-token-retire/phase-0-scope-probe.md` from the 2026-09-11 reading already in hand — statuses and scope names only, no hashes, no values. The only live re-run is Phase 2.3's post-mint probe; a step whose expected outcome is "matches this morning" is not repeated.

**0.3 Confirm the browser surface.** `agent-browser --version` is the primary surface (its Bash path is the one where a single trap scope is real); `mcp__playwright__*` is the fallback and is not assumed — it failed to connect in the planning session. Confirm the #7947 interceptor is live: `jq '.hooks.PreToolUse' plugins/soleur/hooks/hooks.json` names `browser-snapshot-credential-guard.sh`. The mint does not start until one surface is confirmed.

**0.4 Enumerate the trackers and stage the rewrites.** `gh issue list --label follow-through --state open --limit 200 --json number,body` plus `--state closed` filtered to `closedAt` within 14 days; every body matching `secrets=[^ ]*SENTRY_AUTH_TOKEN` gets a rewritten body staged in the scratchpad (`<scratchpad>/directive-rewrites/<n>.md`, the directive's `secrets=` clause with `SENTRY_AUTH_TOKEN` replaced and every other name kept) and the before/after table goes into `session-state.md` with a resume recipe, so a session that dies between merge and Phase 5.2 can resume from the file (`wg-end-of-work-emit-resume-prompt`). Expected on 2026-09-11: #6604, #6297, #5689 open. No fixture is committed (Cut List).

### Phase 1 — RED tests first (`cq-write-failing-tests-before`)

**1.1 Guard 1 cases** in `scripts/lint-followthrough-varq-ban.test.sh`, driving the not-yet-existing retired-name rule over a mktemp sandbox — one case per Guard 1 matrix row (M1-M5) and harness row (H2-H4). M5 is a **sandbox-copy mutation** of the lint that empties rule 2's walk (the varq floor must not be what fires), asserting a diagnostic that names rule 2. **This suite has no ADR-193 floor today**; add one in the canonical shape (`printf >&2` then `exit 1`, call-site counter, conservation check) with `MIN_ASSERTIONS` measured after the rows land, so H1 has a floor to red on and `guard-vacuity-floor.test.sh` enrols the suite.

**1.2 Guard 2 cases** in `scripts/lint-shell-trace-credential-refusal.test.sh` with fixtures under `scripts/fixtures/shell-trace-refusal/`: `violation-empty-predicate-double.sh` (`[ -n "" ]`), `violation-empty-predicate-single.sh` (`[[ -n '' ]]`); the must-PASS non-canonical is the existing `compliant-indirect-unconditional.sh`. M3 is a `mutate_row` on the new predicate (a `sed` copy of the lint with the hardening removed), expecting the M1 fixture to go 1 → 0 reported. Bump `MIN_ASSERTIONS` from 61 to the re-measured total.

**1.3 Guard 3 cases** in `scripts/sweep-followthroughs.test.sh` — **executed with `bash "$SUT"` end to end, never `source "$SUT"; main`**, because the red-run verdict lives in the `BASH_SOURCE == $0` block after `main` returns (the existing T19 greps the SUT's source for the truncation verdict; Guard 3 must not copy that). A stub `gh` whose `issue list` returns a synthesized tracker and whose `issue comment` captures stdin to a file (the T17 shape): M1 a directive naming `SENTRY_AUTH_TOKEN` with only `SENTRY_ACTIONS_RO_TOKEN` in the env → captured comment names the secret and the fix, `::error::` on stderr, `rc != 0`; M2 a second such tracker → both commented, one non-zero exit; M3 a `sed` copy of the SUT with the `MISSING_SECRET=1` assignment deleted → the M1 case's `rc` is 0 (with a `diff` proving the mutation landed); M4 `DRY_RUN=1` → no captured comment, the would-comment and the `::error::` both logged, `rc != 0`; M5 a directive naming `a[$(touch "$T/pwned")]` → refused as malformed, `$T/pwned` absent, comment names the malformed token verbatim-quoted, `rc != 0`; M6 the name bound but **empty** → reported as "bound but empty", `rc != 0`. H2 must-PASS: every `secrets=` name set **and non-empty** → forwarded, no comment from this path. H3: no `secrets=` clause → path not entered. Add the ADR-193 floor this suite also lacks. RED until 3.1b.

**1.4 AC13 retarget** in `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh`: rewrite the row to assert (a) the script reads `SENTRY_ACTIONS_RO_TOKEN` from its environment and names the absence in the summary, (b) `doppler secrets get SENTRY_AUTH_TOKEN` is absent from the script, and (c) **both** `apply-web-platform-infra.yml` boot-trail steps bind `SENTRY_ACTIONS_RO_TOKEN: ${{ secrets.SENTRY_ACTIONS_RO_TOKEN }}` in their `env:` — reusing the AC8d per-job awk extraction at `:357-374`. RED until Phase 3.5.

### Phase 2 — Mint and store (prod writes W1, W2; see `## Production writes`)

**2.1 Mint `actions-read-prd`.** Drive `https://jikigai-eu.sentry.io/settings/developer-settings/new-internal/` with the surface confirmed in 0.3. If the page redirects to login, that single handoff is the sanctioned interactive-auth gate (identical in kind to `cf-token-scope` click-path step 2): the agent stops, states which browser profile's session has expired, and resumes when the profile is authenticated. **No credential is ever typed as an MCP tool-call argument** — MCP arguments are not shell-expanded, so a password on that path would land in the transcript as the argument itself. Then: name `actions-read-prd`; permissions Issue & Event = Read, Organization = Read, Project = Read, everything else No Access; no webhook; save. **Sentry auto-issues the first token on creation** (vendor docs, above), so the Tokens panel is read after saving: the auto-issued token is the one captured; if its one-time display was missed, a second token is created and the first revoked, and the panel count is asserted to be exactly one before Phase 2.3.

Under the #7947 discipline throughout: every `browser_snapshot` carries `filename:` and the file is filtered through `plugins/soleur/skills/agent-browser/scripts/redact-a11y-snapshot.py`; no snapshot or screenshot of the token panel; no `browser_network_requests` / `browser_console_messages` dumps (they carry the session cookie); on the Bash path the interceptor denies any un-piped snapshot.

**2.2 Capture → normalise → store → verify → shred, in one Bash process.** On the `agent-browser` path the whole chain is one Bash tool call: `TOKEN_DIR=$(mktemp -d)`, `chmod 0700`, `trap 'shred -u "$TOKEN_DIR"/* 2>/dev/null || printf "shred failed\n" >&2; rmdir "$TOKEN_DIR" 2>/dev/null' EXIT INT TERM HUP`, then `agent-browser get value <token-textbox-sel> > "$TOKEN_DIR/tok"`, assert the file exists at that exact path and is non-empty, normalise, store, probe, and let the trap shred. On the MCP path the pre-capture call only creates the 0700 directory and a timestamp marker file (no trap can outlive the call); `browser_evaluate(filename: …)` cannot expand `$TOKEN_DIR` and `@playwright/mcp@0.0.78` resolves the name under its own `.playwright-mcp/` output directory — so the post-capture Bash call (where the trap scope begins) first moves the file from the literal path it was written to into `$TOKEN_DIR`, **fails if it is not at that exact path**, and `shred -u`s every file under `.playwright-mcp/` newer than the marker before continuing. The runbook states this as the reason the Bash path is primary.

**Normalise, because the two surfaces write different bytes:** `filename:` JSON-encodes (a 64-char token lands as 66 bytes with quotes); `get value` writes raw text. One tolerant step — `python3 -c 'import sys,json; s=sys.stdin.read(); v=(json.loads(s) if s.lstrip().startswith(chr(34)) else s.strip()); assert isinstance(v,str) and 40<=len(v)<=256 and not any(c.isspace() for c in v), "token shape"; sys.stderr.write("token length %d\n" % len(v)); sys.stdout.write(v)'` — asserts non-empty, whitespace-free and of plausible length, and logs only the length. Nothing asserts hex: Sentry's token format is not fixed across generations (the three existing integration tokens here are 64 chars; org auth tokens are `sntrys_…`), and a format assertion that is wrong would block a rotation with a false diagnosis. Then

    <normalise> < "$TOKEN_DIR/tok" | gh secret set SENTRY_ACTIONS_RO_TOKEN

— the value on **standard input with no `--body`** (`gh secret set` reads stdin when `--body` is omitted; there is no `--body-file`, and `--body -` stores the literal `-`). Never `--body "$TOKEN"`, which is visible in `ps` and under `set -x`. Verify presence with `gh secret list | grep -c '^SENTRY_ACTIONS_RO_TOKEN\b'` = 1; the value assertion is the post-merge dispatch (AC-P1), since GitHub cannot read a secret back. If the write fails, revoke the just-created token in-page before the trap fires, so no live token is left that nobody holds. `/tmp` is tmpfs on this workstation, so `shred -u` of the `mktemp -d` path is effective here; on a journaled or copy-on-write filesystem it is best-effort, the 0700 directory and the seconds-long lifetime are the primary control, and a failed shred is logged, not hidden. **The token never rides argv**: every probe in 2.3 reads its header from a file — `printf 'Authorization: Bearer %s' "$v" > "$TOKEN_DIR/hdr"; curl … -H @"$TOKEN_DIR/hdr"` — which the same trap shreds, so nothing lands in `/proc/*/cmdline`. The rotation script's dry-run mode is a separate flag that cannot see the live capture selector, and `--no-store` appears only on that path (AC-12).

**Dry-run the chain first, with zero writes.** Serve a synthesized page carrying the `ZZQP-SENTINEL-7947` sentinel in a readonly textbox (`python3 -m http.server --bind 127.0.0.1 <port> --directory <mktemp dir>`, exactly as `phase-0-measurement.md` did); run capture and normalise against it and `diff` the normalised output against the sentinel literal (byte-exact, with the shape assertion relaxed to the sentinel's length for the dry run only); run `printf '%s' "$SENTINEL" | gh secret set ZZ_DRYRUN --no-store | wc -c` and assert the ciphertext length equals 48 plus the sentinel's length base64-expanded (the same probe Kieran used to prove `--body -` stores one byte) — **no secret is written**; confirm the sentinel appears in no transcript-visible tool result; confirm the trap removed the directory. Only then run it live.

**2.3 Verify the minted token before any file consumes it.** With the token still in the trap scope: `GET https://jikigai-eu.sentry.io/api/0/` → `.auth.scopes`, sorted, recorded verbatim into `phase-0-scope-probe.md`, and **equal to** `[event:read, org:read, project:read]`; then every consumer's **exact** host + org + path with the new token — `https://sentry.io/api/0/organizations/jikigai-eu/` (5689's org read), `https://sentry.io/api/0/organizations/jikigai-eu/events/`, `https://sentry.io/api/0/organizations/jikigai-eu/monitors/<slug>/checkins/` for each of the three check-in callers' slugs, `https://<regionUrl>/api/0/projects/jikigai-eu/web-platform/issues/` (the host 5689 resolves from `.links.regionUrl`), and `https://de.sentry.io/api/0/projects/jikigai-eu/web-platform/events/` (the boot-trail) — every row **200**. A 403 or a scope mismatch blocks the cutover: edit the integration's permissions in-page, **re-read `.auth.scopes` on the same token**; if the token does not reflect the edit, revoke it, create a new one, and re-run 2.2 (the stored secret is stale otherwise). Record the final set. An implied extra scope is recorded as a finding and resolved before proceeding, never accepted as a superset.

### Phase 3 — GREEN

**3.1 Sweeper env** (`.github/workflows/scheduled-followthrough-sweeper.yml:93`): replace `SENTRY_AUTH_TOKEN: ${{ secrets.SENTRY_IAC_AUTH_TOKEN }}` with `SENTRY_ACTIONS_RO_TOKEN: ${{ secrets.SENTRY_ACTIONS_RO_TOKEN }}` and a comment naming the integration, ADR-031, and that it is deliberately **not** mirrored to Doppler (so the next author does not "fix" the departure from the `BETTERSTACK_*` mirror pattern). The comment must not spell the retired name (AC-8 greps for its absence). The old name is dropped in the **same commit** as 3.2 and 3.3 — no shim. Also update the header comment in `scripts/sweep-followthroughs.sh:28`.

**3.1b Make the missing-secret path loud — and safe** in `scripts/sweep-followthroughs.sh`, in the `secrets=` forwarding loop of `run_one`. Three edits to one branch: (a) **validate before expanding** — `[[ "$name" =~ ^[A-Z][A-Z0-9_]*$ ]] || { record "malformed secret name"; continue; }` runs before any `${!name…}` indirect expansion, closing a pre-existing command injection (a directive `secrets=a[$(cmd)]` currently executes `cmd` inside the job); (b) treat **set-but-empty** as missing — `[[ -z "${!name:-}" ]]` → "bound but empty: repo secret absent or the `secrets.` reference is misspelled" — because that is what `${{ secrets.X }}` resolves to when the secret is gone, and the sweeper's set-ness test forwards it today; (c) **collect every missing or malformed name for the directive**, then post **one** comment on the tracker via the existing `printf '%s' "$body_msg" | gh issue comment … --body-file -` shape (`|| fail "issue #N: missing-secret comment post failed"`, since `||` inside `run_one` would otherwise swallow it), emit `::error::` (also under `DRY_RUN=1`, where only the comment is suppressed and the would-comment is logged), and set `MISSING_SECRET=1`. The `BASH_SOURCE == $0` block reads the flag beside `TRUNCATED_SWEEP` and exits 1 after the sweep completes. The comment body is built from the validated names only — never from `env_args`, `$secrets`, or any value — and names the fix ("add it to the workflow `env:` block or correct the directive's `secrets=` clause"). The branch runs before the open/closed mode split, so a closed-within-14-days tracker naming the retired credential is commented on while closed and reds the run; that is the intended reading and AC-P2 covers it. This is Guard 3.

**3.2 Guard 1** — the retired-name rule in `scripts/lint-followthrough-varq-ban.sh`: a second loop over `"$TARGET_DIR"/*.sh` **including** `*.test.sh` and **including** full-line comments, `grep -nF 'SENTRY_AUTH_TOKEN'`, one violation line per hit citing file:line with the remedy (`use SENTRY_ACTIONS_RO_TOKEN; the retired name binds a personal token under doppler run -c prd_terraform — see ADR-031`). The rule's walk increments its **own** counter (`scanned_rule2`), reported beside `scanned`, so the floor semantics of the varq rule are untouched and H4's reading is unambiguous. Same floor, same exit contract. The header comment gains a `RULE 2` paragraph, and `followthrough-convention.md`'s census gains the retired-name row so the doc indexes the enforcement.

**3.3 Migrate the sixteen files.** For each: consumption `SENTRY_AUTH_TOKEN` → `SENTRY_ACTIONS_RO_TOKEN`; the TRANSIENT presence guard keeps its form verbatim (`if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT: ..." >&2; exit 2; fi`, never `${VAR:?}`); in the 13 files with a predicate, `${SENTRY_AUTH_TOKEN:+x}` → `${SENTRY_ACTIONS_RO_TOKEN:+x}` in the same edit, with the message's parenthetical (Rule C reds otherwise, in CI's `--changed` run). The two `.test.sh` files rename their env stubs and their comments (`:109`, `:253` — Guard 1 bans the name in comments too). The comment in `git-data-birth-emitter-6982.sh` is rewritten to name the consumer (the sweeper) rather than the variable, and that file gains the unconditional refusal the lint prints for it (it binds `BETTERSTACK_QUERY_PASSWORD` through `${!v:-}`, which prints the **value** under `set -x`); its A/B/C baseline line is deleted. **Rule D remediation on the 13 baselined followthroughs** (first commit), using the lint's own per-site remedy text: `curl --disable` first, `--noproxy '*'`, every env-settable destination compared against a literal before use; delete each file's line from `lint-shell-trace-credential-refusal-d.baseline.txt` in the same commit (the baseline's own DRAWDOWN contract). **Org slug:** `sentry-checkins-3859.sh` `ORG="jikigai"` → `"jikigai-eu"`; `sync-health-residual-5689.sh` default → `jikigai-eu` — and since Rule D pins `SENTRY_ORG` against a literal, a caller setting it to anything else is refused rather than silently redirected (`git grep -n 'SENTRY_ORG=' -- .github scripts` shows no caller of that script sets it).

**Exercise every migrated `.sh` once before PR-ready, after commit 1's Rule D pins have landed**, so the curl-flag and destination-pin edits are run, not read. The value must not ride argv (an `env -i VAR="$(…)" …` form puts it in `/proc/*/cmdline`), so: `env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME="$HOME" bash -c 'export SENTRY_ACTIONS_RO_TOKEN="$(doppler secrets get SENTRY_IAC_AUTH_TOKEN -p soleur -c prd --plain)"; <other names the script's directive lists, exported the same way>; exec bash "$0"' scripts/followthroughs/<probe>.sh; echo "rc=$?"` under an xtrace-free shell — `doppler` must be on that PATH or invoked by absolute path. Exit 0, 1 or 2 are all acceptable verdicts **only if the script's Sentry call actually ran**: record the HTTP status each script observed (from its own output) beside `rc`; a script that exited 2 on a *different* missing secret before reaching curl is recorded as `NOT EXERCISED` and re-run with that secret exported. A `curl:` usage error, an HTTP `000`, or a TRANSIENT naming a 4xx is a defect (403 cannot occur under the IaC superset, which is why the superset is used for this shape test and the real secret is used for the value test post-merge). Record per script in `session-state.md`.

**3.4 Guard 2** — Rule C hardening in `scripts/lint-shell-trace-credential-refusal.py` `check_rule_c`: before the `":+" not in window` early return, if the arm window matches `\[\[?\s+-n\s+(""|'')\s+\]\]?` (an empty-string non-emptiness test, either quote style), report "the xtrace refusal tests an empty string and can never fire — restore the `${VAR:+x}` limb or refuse unconditionally". Five lines plus the fixtures from 1.2. No new rule letter, no baseline change.

**3.5 The boot-trail.** `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh`: drop **every** Doppler read — the `SENTRY_AUTH_TOKEN` fetch with its `dop_rc` branch and `::add-mask::` line (a `secrets.*` binding is masked by Actions itself, in the log and in the summary file), and the `SENTRY_ORG` / `SENTRY_PROJECT` fetches, which become the literals `jikigai-eu` / `web-platform` (read from Doppler 2026-09-11; Rule D pins them against literals regardless). Read `SENTRY_ACTIONS_RO_TOKEN` from the environment; when it is empty, emit **both** `echo "::warning::${WEB_HOST_KEY}: Sentry read skipped — SENTRY_ACTIONS_RO_TOKEN is not bound in this step's env (repo secret absent or workflow env not wired); the auto-read did NOT run"` and the same sentence via `tee -a "$GITHUB_STEP_SUMMARY"`, in the shape the script's own HTTP-failure branch already uses — an annotation is reachable from `gh run view --log`, a step summary is not. Exit stays 0 (a skipped read is not a proven dark boot, T10). **Rule D on its `:177` curl** (`--disable --noproxy '*'`, host and org pinned against literals) and delete baseline line 27. In `.github/workflows/apply-web-platform-infra.yml`, both boot-trail steps' `env:` blocks gain `SENTRY_ACTIONS_RO_TOKEN: ${{ secrets.SENTRY_ACTIONS_RO_TOKEN }}` and **lose `DOPPLER_TOKEN`** — it was there only for the three reads just removed, and an `if: always()` step holding a `prd_terraform`-capable credential on every failed or cancelled apply was the wider exposure in those steps, not the read-only token. The step comment says why the read moved off Doppler. `doppler-download-error-channel.test.sh`'s reader-scoped rows (AC-M0, AC-M8) pin the invocation and the anchor, not the Doppler reads, and stay green.

**3.6 Rotation runbook** — `knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md`, beside `cloudflare-service-token-rotation.md`. No SSH limb (`hr-no-ssh-fallback-in-runbooks`). Sections: the closed API path with its measured reason; the browser rung with the `agent-browser` Bash path as primary and the MCP path as fallback, the selector-level recipe, which browser profile holds the Sentry session, and the honest auth-handoff statement; the capture-normalise-store chain from Phase 2.2 **by reference** to a committed script `scripts/rotate-sentry-actions-ro-token.sh` (the bash half lives once; the runbook and Phase 2.2 both invoke it — CTO/simplicity de-duplication); the `.auth.scopes` equality and per-consumer endpoint assertion; the order **store new → dispatch sweep → read verdicts → revoke old** with the note that a save may auto-issue a token, so the panel's count is checked and extras revoked; **cadence**: rotate on incident or on scope change (ADR-031 records no cadence for any Internal Integration token and the expiry check covers Cloudflare only — stated, not implied); the **workstation dry run**: `gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true` runs the real secret at the real scopes with no local credential and no comments posted; the explicit `SENTRY_ACTIONS_RO_TOKEN="$(doppler secrets get SENTRY_IAC_AUTH_TOKEN -p soleur -c prd --plain)" bash scripts/followthroughs/<probe>.sh` assignment is the documented **last resort** with its caveat (a superset that can pass locally and 403 in CI); never an ambient `doppler run`; and a `## Failure modes` table with a **next action** per row: session unauthenticated; permission labels drifted; the form saved but the token panel was missed by the capture selector; two tokens on the panel; `.auth.scopes` not equal to the triple; a consumer's host or org slug moved; `gh secret set` failed; the new token 403s at verification; a probe still TRANSIENTs after the dispatch; the sweeper run is red with `required secret`. The table's row count equals the enumerated list (AC-12).

**3.7 Docs sweep by claim, not by literal.** `followthrough-convention.md` — all three occurrences, the Soak row's `secrets=` cell now reads `SENTRY_ACTIONS_RO_TOKEN`, plus the census row for Guard 1; `plugins/soleur/skills/schedule/SKILL.md:76`; `scripts/sweep-followthroughs.sh:28`; the `env:` comment in the sweeper workflow.

### Phase 4 — ADR, post-mortem, register, deferrals

**4.1 Amend `ADR-031-sentry-as-iac.md`** with a dated block in the shape of the 2026-06-17 `inline-read-prd` amendment: the **fourth credential class** `actions-read-prd`; the permission set selected and the `.auth.scopes` returned; the **store discriminator** (a GitHub Actions consumer takes a GitHub repo secret; a `doppler run` inline consumer takes a Doppler secret; never copy one into the other) and its cost, stated accurately — a repository secret is reachable from any workflow a write collaborator runs on a same-repo branch (two collaborators on this public repo); the two live `pull_request_target` workflows (`cla.yml`, `cla-evidence.yml`) neither check out the PR head nor bind a Sentry secret, so fork reachability is nil; and `event:read` on this org exposes production event context (emails, IPs, breadcrumbs), so the exposure is not cosmetic — which is why the integration is scoped to the narrowest permission set (Internal Integrations are org-wide; there is no project set to narrow) and why the Actions environment secret is recorded as the considered-and-not-taken narrower store, with its real cost: the provisioning jobs already carry `environment: web-platform-infra-apply`, so only the sweeper would need a new environment (DC-5); the AP-008 divergence ADR-031 already justifies; the `POST /api/0/sentry-apps/{slug}/api-tokens/` endpoint (needs `org:write`) as a *possible* future login-free rotation rung, not minted because `org:write` is a wider grant than the token it would rotate; the Org-Auth-Tokens-vs-Internal-Integrations surface distinction; the **DC-3 record** with the 403 reading and the rejected `SENTRY_IAC_AUTH_TOKEN`-under-new-name shape; the rule that narrowing happens by adding a dedicated integration, never by mutating a shared one; the mint path (dashboard; API closed by `org:admin`); the rotation cadence and the dry-run path; the consequence that the new name is unsatisfiable by any Doppler config (a workstation run exits 2 TRANSIENT — fail-closed, by design); and a header note that the `ADR-031` ordinal is duplicated (#6493 / #6960).

**4.2 Post-mortem — append only.** A new `## Addendum — <UTC date> (#7946)` at the end of `bash-x-credential-trace-exposure-postmortem.md`, opening with the file's own idiom ("Append-only. Nothing above is rewritten; this section supersedes the parts it names."), superseding by name (a) `### Still open` — the org-token migration is done for every repo-side consumer of the personal value, the followthroughs and the boot-trail bind `actions-read-prd` at `[event:read, org:read, project:read]`, the next rotation is agent-drivable per the runbook with one auth handoff, and the personal value's revocation is #<deferral>; and (b) the 2026-09-07 addendum's ADR-031 sentence. **Nothing above the new heading changes**: not the `art_33_*` / `art_34_*` frontmatter, not the Art. 4(12) determination, not the asymmetry table (CLO constraint, carried forward).

**4.3 DC-3 resolution** appended to the 2026-09-09 spec's `decision-challenges.md` (`## DC-3 — RESOLUTION: decided by measurement (…)`), in the shape of the DC-1 resolution already there — the one-line reading and a pointer to the ADR-031 record.

**4.4 Legal register** (CLO advisory carried forward from 2026-09-09): one additive dated bracket on **PA-8 §(g)** of `knowledge-base/legal/article-30-register.md` beside the `inline-read-prd` control, every slot filled from the actual mint and the actual diff; one row under `## Completed Compliance Work` in `knowledge-base/legal/compliance-posture.md`; no new PA number; no edit to `plugins/soleur/docs/pages/legal/` or `docs/legal/`. `bash scripts/lint-legal-registers.sh` green.

**4.5 C4 — no edit, with the enumeration.** All three model files were read. External human actors: none change (the operator's role is unchanged). External systems: `sentry` is already a `system` in `model.c4` and is included in both views in `views.c4`; GitHub Actions is already the `github` container. Data stores: none added. Access relationships: the `github -> sentry` edge already exists and its direction, protocol and purpose are unchanged — only which credential rides it, which is not a modeled dimension (ADR-031 holds credential names). The edge label's `SENTRY_AUTH_TOKEN` stays true (it is the Terraform provider's name). `bash plugins/soleur/test/c4-count-parity.test.sh` is run green rather than reasoned about (AC-10).

**4.6 Deferrals — pre-merge, because the post-mortem addendum cites the numbers.** (a) The personal-token revocation issue (`gh issue create`, labels `type/security`, `domain/engineering`, `priority/p2-medium`): the consumer-set re-derivation command, the enumerated workstation readers and the `cutover-verify.sh:318` hint, the recommended shape from `## Non-Goals` (replace the value under the canonical name with the `iac-terraform-prd` token so the Terraform provider keeps working), the `DOPPLER_TOKEN` reachability note, `Ref #7797`, `Ref #7946`, and a re-evaluation trigger (after this PR's first green sweep). (b) The `scripts/rotate-x-api-secret-bootstrap.sh:56` `--body -` defect (`type/bug`, `domain/engineering`, `priority/p2-medium`): the measured ciphertext-length evidence and the fix (`gh secret set X_API_SECRET` with stdin, no `--body`). Both numbers recorded in the post-mortem addendum and the PR body.

### Phase 5 — Verification, then ship-time steps

**5.1** Walk every pre-merge acceptance criterion with its command verbatim.

**5.2 At ship, after merge, in the same session** (`/soleur:ship` post-merge; prod writes W3, W4): rewrite every directive staged in 0.4 — re-running the open and closed-within-14-days queries first, because the set may have moved since 0.4 — via `gh issue edit <n> --body-file <staged>` after diffing the live body against the staged "before"; then `gh workflow run scheduled-followthrough-sweeper.yml`, record the run's `createdAt`, wait for completion, and assert AC-P1 and AC-P2. **Do not** dispatch `apply-web-platform-infra.yml` bare — the push already ran its `apply` job (W6), and a bare dispatch is the `confirm`-gated class its own inputs warn about. The two windows around the rewrite (directives ahead of env; env ahead of directives) are each bounded by this step; a scheduled sweep that fires inside a window now posts a `required secret` comment and reds its run (3.1b) rather than passing silently, and that is the expected reading, not a regression.

## Production writes — each is a per-command-authorized prod write, never assumed

| # | Write | Surface | When | Authorization shape | Reversal |
|---|---|---|---|---|---|
| W1 | Create Internal Integration `actions-read-prd` and one token | Sentry dashboard (`jikigai-eu`), browser-driven | Phase 2.1 (first headless checkpoint) | Named as a prod write before the browser opens; if the session has expired, the operator's own login in the headed browser is the auth handoff and the agent types nothing | Revoke the token / delete the integration in-page |
| W2 | `… \| gh secret set SENTRY_ACTIONS_RO_TOKEN` (stdin, no `--body`) | GitHub repo secrets | Phase 2.2, same checkpoint | Per-command | `gh secret delete SENTRY_ACTIONS_RO_TOKEN` |
| W5 | `gh issue create` ×2 (revocation deferral; rotate-x defect) | GitHub issues | Phase 4.6, **pre-merge** | Per-command | Close |
| W6 | `apply-web-platform-infra.yml` `apply` job, push-triggered by the merge (the boot-trail script and the workflow file are under its `paths:`) | Terraform against production | At merge | Implicit in the merge; expected reading: plan shows nothing to add, change or destroy for the targeted set (no `.tf` changes) | None — a no-op apply |
| W3 | `gh issue edit --body-file` on each tracker naming the retired secret (#6604, #6297, #5689 + any closed-within-14d) | GitHub issue bodies | Phase 5.2 (second headless checkpoint) | Per-issue, after merge | Re-edit from the staged "before" body; GitHub keeps edit history |
| W4 | `gh workflow run scheduled-followthrough-sweeper.yml` | GitHub Actions (posts comments on trackers) | Phase 5.2 | Per-command | None needed — comments are the verdict |

The dry run in Phase 2.2 uses `gh secret set --no-store` and writes nothing. No Doppler write. No
SSH. `hr-menu-option-ack-not-prod-write-auth`: a menu selection or a "proceed" on the plan is not
authorization for any row above.

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md` | Agent-executable rotation with the `## Failure modes` table, the cadence statement and the dry-run path. |
| `scripts/rotate-sentry-actions-ro-token.sh` | The capture-normalise-store-verify-shred chain, once; invoked by Phase 2.2 and cited by the runbook. Carries its own xtrace refusal. |
| `knowledge-base/project/specs/feat-one-shot-7946-sentry-org-token-retire/phase-0-scope-probe.md` | The endpoint table, the pre-mint scope readings and the post-mint `.auth.scopes` — statuses and scope names only, no hashes. |
| `scripts/fixtures/shell-trace-refusal/violation-empty-predicate-double.sh`, `…-single.sh`, and `compliant-unconditional-refusal.sh` if absent | Guard 2 fixtures. Synthesized; no real credential. |

No new lint script, no new `run_suite` line, no new ADR, no new `.test.sh`, no committed census
fixture, no C4 edit.

## Files to Edit

**The sixteen followthrough files** (`grep -rl SENTRY_AUTH_TOKEN scripts/followthroughs/`, count 16): `ac10-workspace-reconcile-sentry-4246.sh`, `ac8-founder-ambiguous-soak-5673.sh`, `accounted-beacon-live-6462.sh`, `anthropic-admin-key-6297.sh`, `anthropic-admin-key-6297.test.sh` (stubs and comments), `community-monitor-checkin-soak-5728.sh`, `deploy-ghcr-pull-recovery-6400.sh`, `ghcr-minter-live-6031.sh`, `git-data-birth-emitter-6982.sh` (comment + new unconditional refusal), `phase3-ga-soak-5274.sh`, `reconcile-ff-only-sentry-4977.sh`, `sentry-checkins-3859.sh` (credential **and** org slug), `sync-health-residual-5689.sh` (credential **and** default org slug), `workspaces-luks-soak-6604.sh`, `zot-soak-6122.sh`, `zot-soak-6122.test.sh` (stubs) — each for consumption, its refusal predicate where present (13), and Rule D form where baselined (13).

**Guards, the sweeper, and their suites:** `scripts/lint-followthrough-varq-ban.sh` + `.test.sh` (Guard 1); `scripts/lint-shell-trace-credential-refusal.py` + `.test.sh` (Guard 2); `scripts/sweep-followthroughs.sh` + `.test.sh` (Guard 3, header comment); `scripts/lint-shell-trace-credential-refusal-d.baseline.txt` (14 lines deleted: 13 followthroughs + the boot-trail); `scripts/lint-shell-trace-credential-refusal.baseline.txt` (the `git-data-birth-emitter-6982.sh` line deleted).

**CI and infra:** `.github/workflows/scheduled-followthrough-sweeper.yml`; `.github/workflows/apply-web-platform-infra.yml` (both boot-trail steps: `SENTRY_ACTIONS_RO_TOKEN` added, `DOPPLER_TOKEN` removed, step comments); `apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` (env read, all Doppler reads removed, `::warning::` + summary skip, Rule D curl); `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` (AC13 retargeted, never deleted). Run, not edited: `apps/web-platform/infra/doppler-download-error-channel.test.sh`.

**Docs and records:** `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` (three occurrences + the Guard 1 census row); `plugins/soleur/skills/schedule/SKILL.md`; `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`; `knowledge-base/engineering/operations/post-mortems/bash-x-credential-trace-exposure-postmortem.md` (append only); `knowledge-base/project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/decision-challenges.md` (append DC-3 resolution); `knowledge-base/legal/article-30-register.md` (PA-8 §(g) bracket); `knowledge-base/legal/compliance-posture.md` (one row).

**Not edited:** `.claude/hooks/follow-through-directive-gate.sh` (Cut List); `git-data-rung2-evidence-capture.sh` (Cut List); `model.c4` / `model.likec4.json` / `views.c4` / `spec.c4` (Cut List); `scripts/rotate-x-api-secret-bootstrap.sh` (filed); any file under `plugins/soleur/docs/pages/legal/` or `docs/legal/`; every other `SENTRY_AUTH_TOKEN` reader outside the two consumer classes (they bind `secrets.SENTRY_IAC_AUTH_TOKEN` or the provider's canonical name — see Non-Goals and the revocation deferral).

No skill `description:` field is edited.

## Guard Contract

### Guard 1 — retired-name rule in `scripts/lint-followthrough-varq-ban.sh`

**Property.** No tracked file under `scripts/followthroughs/` — `.sh` or `.test.sh`, executable line or comment — names `SENTRY_AUTH_TOKEN`, the name under which a workstation `doppler run -c prd_terraform` binds a personal, human-account-scoped Sentry credential.

**Assembly.** The chokepoint is the lint's single directory walk over `"$TARGET_DIR"/*.sh`, with the `.test.sh` skip and the comment drop that the varq rule applies **not** applied for this rule. Members drift (a new probe lands every few days); the walk is structural. The floor keys on the resolved default dir (`resolve()`), so an empty mktemp sandbox is exempt by design and the production path is not. Registered via the existing `run_suite` lines in `scripts/test-all.sh` (`:1811` runs it live against the tree); no second registration surface.

**Mutation matrix** (every row is a suite case; the anti-vacuity count equals five).

| # | Edit | Must |
|---|---|---|
| M1 | Restore `SENTRY_AUTH_TOKEN` on an executable line of one migrated `.sh` | RED, citing file at its true line |
| M2 | Restore it in a **second** file after the first is compliant | RED citing both — the walk does not stop at the first member |
| M3 | Restore it in a `.test.sh` only | RED — proves this rule's walk includes test files, unlike the varq rule's |
| M4 | Restore it inside a full-line comment only | RED — the name in a comment is what the next author copies |
| M5 | On a sandbox copy of the lint, empty rule 2's walk (`sed` the glob to a non-matching pattern) and run it against the production tree | Exit 2 with a diagnostic naming rule 2 — the rule's own dispatch cannot report clean over nothing, and the varq rule's floor (`scanned`) must not be what fires: the floor tests `scanned_rule2` too |

**Harness rows.**

| # | Edit to the SUITE | Must |
|---|---|---|
| H1 | Remove one RED case | Suite RED via the ADR-193 floor this plan adds to the suite (it has none today), `MIN_ASSERTIONS` re-measured after the rows land |
| H2 | Must-PASS, not the canonical: a probe naming `SENTRY_ACTIONS_RO_TOKEN` **and** `BETTERSTACK_API_TOKEN`, plus a comment mentioning "the sweeper's Sentry secret" without the retired literal | Exit 0 |
| H3 | Must-PASS: `TARGET_DIR` at an empty mktemp sandbox | Exit 0 — pins the sandbox exemption so a later "fix" that fires the floor in sandboxes breaks this row and not every other case |
| H4 | Must-PASS: the live production tree after Phase 3.3 | `clean (N probe(s) scanned)` with the varq rule's N at or above the Phase 0.1 reading and `scanned_rule2` ≥ N |

### Guard 2 — Rule C empty-predicate hardening in `scripts/lint-shell-trace-credential-refusal.py`

**Property.** A file whose xtrace refusal is conditional cannot pass Rule C with a predicate that can never be true — `[ -n "" ]` or `[ -n '' ]` in either test syntax, the residue of deleting a single-credential file's only `${VAR:+x}` limb.

**Assembly.** `check_rule_c`'s arm window (`arm_window(lines, preamble_at)`), reached for every scanned file with a preamble; the same population Rules A-D walk. The one chokepoint is the `":+" not in window` early return; the hardening runs before it.

**Mutation matrix** (three suite cases).

| # | Edit | Must |
|---|---|---|
| M1 | Fixture: single-credential file, predicate `[ -n "" ]` | RED, citing the preamble line, message naming the restore-or-refuse-unconditionally remedy |
| M2 | A second fixture in the same run, `[[ -n '' ]]`, after a compliant first | RED citing both — the other syntax and quote style, and the walk does not stop at the first member |
| M3 | A `sed` copy of the lint with the hardening's predicate check removed (`mutate_row`), run over the M1 fixture | The M1 fixture goes from 1 reported to 0 — the dispatch row for THIS check, not the host's |

**Harness rows.**

| # | Edit to the SUITE | Must |
|---|---|---|
| H1 | Remove the M1 case | Suite RED via the host suite's existing `MIN_ASSERTIONS` floor, bumped from 61 to the re-measured total |
| H2 | Must-PASS, not the canonical: the existing `compliant-indirect-unconditional.sh` (no `-n` test at all, `exit 78` in the arm) — it shares the early-return branch the hardening sits in front of | Exit 0 |
| H3 | Must-PASS: the full live tree via `scripts/test-all.sh`'s repo-wide registration | Exit 0 with baselines applied — the hardening must not red an existing baselined file's fixture corpus |

**Rule C's existing coverage, relied on rather than re-implemented (measured 2026-09-11 by the planner and independently by the Kieran review):** consumption renamed with the refusal predicate left on the old name → RED (`Unguarded: SENTRY_ACTIONS_RO_TOKEN`); the Sentry limb deleted from a multi-credential predicate → RED. Both run in CI under `--changed --base origin/main` with baselines bypassed. AC-5 asserts the lint green under that exact invocation.

### Guard 3 — the sweeper's missing-secret path in `scripts/sweep-followthroughs.sh`

**Property.** A tracker whose directive names a secret that the workflow env does not carry — absent, **set but empty**, or not a valid identifier — is reported on the tracker itself and reds the sweeper run, and no name is ever expanded before it is validated. Never a silent `return 0` under a green run; never an indirect expansion of author-controlled text.

**Assembly.** The single `secrets=` forwarding loop in `run_one` (the `env_args+=` / `fail … return 0` branch), which every directive passes through and which sits before the open/closed mode split; and the `BASH_SOURCE == $0` block after `main`, which is where `TRUNCATED_SWEEP` already reds the run — a flag set inside `main` and read there. The comment helper is the existing `gh issue comment … --body-file -` shape at `:488`/`:565`. Every case runs `bash "$SUT"` end to end against a stub `gh`; a sourced `main` cannot observe the exit.

**Mutation matrix** (six suite cases).

| # | Edit | Must |
|---|---|---|
| M1 | A tracker directive names `SENTRY_AUTH_TOKEN`; the env carries only `SENTRY_ACTIONS_RO_TOKEN` | A comment captured on that tracker naming the secret and the fix; `::error::` on stderr; `rc != 0` |
| M2 | A **second** tracker with a missing secret after a compliant first | Both commented; one non-zero exit |
| M3 | A `sed` copy of the SUT with the `MISSING_SECRET=1` assignment deleted (with a `diff` proving the mutation landed) | The M1 case's `rc` is 0 — the dispatch row: the flag is the mechanism |
| M4 | `DRY_RUN=1` with M1's input | No comment captured; the would-comment and the `::error::` both logged; `rc != 0` |
| M5 | A directive naming `a[$(touch "$T/pwned")]` | Refused as malformed **before any expansion** — `$T/pwned` absent, the comment quotes the malformed token, `rc != 0` |
| M6 | The name present in the env but **empty** | Reported as "bound but empty"; `rc != 0` |

**Harness rows.**

| # | Edit to the SUITE | Must |
|---|---|---|
| H1 | Remove the M1 case | Suite RED via the ADR-193 floor this plan adds (the suite has none today) |
| H2 | Must-PASS, not the canonical: a directive whose two `secrets=` names are both set **and non-empty**, one of them not `GH_TOKEN` | Both forwarded; no comment from this path; exit unchanged by this path |
| H3 | Must-PASS: a directive with no `secrets=` clause at all | Path not entered; exit 0 |

## Observability

```yaml
liveness_signal:
  what: the daily follow-through sweep completes with every Sentry-backed probe returning a
        definite verdict (PASS/FAIL) rather than TRANSIENT-missing-secret, on #6604, #6297
        and #5689; a missing secret on any tracker reds the run and posts on the tracker;
        and the next fresh-host provision's boot-trail step reports a Sentry read that ran
        (HTTP 200) rather than a named skip
  cadence: daily (scheduled-followthrough-sweeper.yml, 18:00 UTC); per provisioning dispatch
        (boot-trail)
  alert_target: the tracker issue itself — the sweeper posts a comment and leaves the issue
        open on any non-PASS, now including a missing secret; a red sweeper run; the boot-trail
        writes a named line to GITHUB_STEP_SUMMARY
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml;
        .github/workflows/apply-web-platform-infra.yml (two boot-trail steps)

error_reporting:
  destination:
    - "observability layer 6 — the synchronous workflow-run log plus the sweeper's own issue
       comment (last 4 KB of stdout/stderr; xtrace lines stripped because issue comments do
       NOT pass through the Actions secret masker), and — after 3.1b — a ::error:: annotation
       and a red run on a missing secret"
    - "observability layer 6 — the CI step output of ci.yml:180 (Rule C/D under --changed) and
       the scripts shard of scripts/test-all.sh (Guard 1, Guard 2, Guard 3, repo-wide lint)"
    - "observability layer 6 — GITHUB_STEP_SUMMARY of the provisioning job for the boot-trail"
  fail_loud: yes — a missing secret posts on the tracker and reds the run (3.1b); an empty env
        binding exits 2 TRANSIENT from each script's own presence guard and posts the reason;
        the boot-trail names 'not bound' rather than 'no events'; all three guards exit 2 on
        cannot-evaluate, never 0

failure_modes:
  - mode: the new token 403s on an endpoint, host or org slug the probe table missed
    detection: the affected probe exits 2 TRANSIENT and the sweeper posts the HTTP status
        onto the tracker; pre-merge, AC-6's per-consumer re-probe is the gate
    alert_route: layer 6 — tracker comment plus workflow-run log
  - mode: the stored value is wrong (JSON-encoded, truncated, or the literal '-'), so every
        probe authenticates with garbage
    detection: a 401 TRANSIENT posted on the tracker; pre-merge, the --no-store ciphertext-length
        probe and the shape assertion in the normalise step; post-merge, AC-P1 rejects any
        comment carrying HTTP 401/403
    alert_route: layer 6
  - mode: the repo secret is absent or the secrets. reference is misspelled, so the env key is
        bound but EMPTY (what ${{ secrets.X }} resolves to) — the most likely production breakage
    detection: Guard 3 M6 — the sweeper reports "bound but empty" on the tracker, ::error::, red
        run; without it the set-ness test forwards "" and every probe TRANSIENTs under a green run
    alert_route: layer 6 — tracker comment plus red run
  - mode: a tracker directive carries a malformed secrets= name (an injection attempt or a typo)
    detection: Guard 3 M5 — refused before expansion, quoted in the tracker comment, red run
    alert_route: layer 6
  - mode: the integration or its token is deleted dashboard-side
    detection: HONEST GAP — every Sentry-backed probe posts a 401 TRANSIENT daily under a GREEN
        run, indistinguishable from a network blip except by the 401 (deleted) vs 403 (scope
        edited) discriminator; recorded in the ADR-031 amendment and the runbook's failure table,
        not instrumented here
    alert_route: layer 6 — tracker comment only
  - mode: a tracker still names the retired credential after the cutover
    detection: Guard 3 — a comment on that tracker naming the secret and the fix, ::error::,
        red run; AC-P2 re-runs the census query
    alert_route: layer 6 — tracker comment plus red run
  - mode: a file consumes the new credential while its refusal guards the old one
    detection: existing Rule C, red in ci.yml:180 and the scripts shard (measured)
    alert_route: layer 6 — CI step output
  - mode: a file's only refusal limb is deleted, leaving [ -n "" ]
    detection: Guard 2 reds
    alert_route: layer 6 — CI step output
  - mode: the retired name re-enters scripts/followthroughs/ (new probe copied from an old one)
    detection: Guard 1 reds in the scripts shard
    alert_route: layer 6 — CI step output
  - mode: the boot-trail step runs with the secret unbound on a fresh-host provision
    detection: a ::warning:: annotation (reachable via gh run view --log) plus the named skip
        line in GITHUB_STEP_SUMMARY; the retargeted AC13 asserts both workflow steps bind the
        secret, so an un-wired step is red in infra-validation.yml
    alert_route: layer 6 — annotation, step summary, CI
  - mode: the integration's permissions are edited dashboard-side after the mint
    detection: only at the next sweep (403 TRANSIENT on the tracker) or the next provision;
        recorded as a known gap in the ADR-031 amendment rather than instrumented here
    alert_route: layer 6 — tracker comment
  - mode: Guard 1's directory walk breaks and scans nothing
    detection: the floor exits 2 on the production path (M5)
    alert_route: layer 6 — scripts shard

logs:
  where: workflow-run logs and tracker issue comments (layer 6); GITHUB_STEP_SUMMARY for the
        boot-trail
  retention: GitHub Actions default for run logs; tracker comments are permanent

discoverability_test:
  command: bash scripts/lint-followthrough-varq-ban.sh && python3 scripts/lint-shell-trace-credential-refusal.py scripts/followthroughs/community-monitor-checkin-soak-5728.sh && bash scripts/sweep-followthroughs.test.sh && grep -c '::warning::.*SENTRY_ACTIONS_RO_TOKEN' apps/web-platform/infra/scripts/fresh-host-boot-trail.sh
  expected_output: "clean (N probe(s) scanned) with N >= 10 and scanned_rule2 >= N, then the lint exits 0 on a migrated file with baselines bypassed (explicit path), then the sweeper suite green including Guard 3 M1-M6 against a stub gh, then a count of 1 or more"
```

No limb requires SSH. The runbook has no SSH fallback.

## Infrastructure (IaC)

### Terraform changes

**No `.tf` change.** A Sentry Internal Integration is created by `POST /api/0/organizations/{org}/sentry-apps/`, which requires `org:admin` or `org:integrations`. No org-level Soleur credential carries either (only the personal token being retired does), so the `jianyuan/sentry` provider — which authenticates with `SENTRY_AUTH_TOKEN` = `iac-terraform-prd` — cannot represent the resource. Vendor-imposed, verified live (#5495 / #5496). **But a Terraform apply does run**: `apply-web-platform-infra.yml`'s `apply` job fires on the merge because the boot-trail script and the workflow itself are under its `paths:` filter. Registered as W6; expected reading is a no-op plan.

### Apply path

Browser automation driven by an agent on the `agent-browser` Bash path (MCP fallback), followed by a scripted `gh secret set` from stdin. This is the rung `cf-token-scope` (ADR-130) establishes. `hr-exhaust-all-automated-options-before` is satisfied by measurement: the API rung is closed with a named reason, the dashboard rung is proven open. The one human limb is named: if the browser profile's session has expired, clearing login and MFA is the sanctioned interactive-auth gate; everything after it is automated. A newly appeared gate mid-form is `attempted-blocked-on-tool` and is filed as a tooling retry with a resume recipe, never relabelled as an operator step. `automation-status: VERIFIED` for the form (#5495); the session state is per-run.

### Distinctness / drift safeguards

One store: a GitHub repo secret. Distinct from Doppler `soleur/prd` (`SENTRY_ISSUE_RO_TOKEN`), from `secrets.SENTRY_IAC_AUTH_TOKEN`, and from Doppler `prd_terraform` (the personal value). No Terraform state holds the value. The old env name is dropped from the sweeper in the same commit that migrates the readers; a scheduled sweep inside either window now reds and posts rather than passing. Dashboard-side scope drift after the mint is detected only at the next sweep — stated in the ADR, not instrumented.

### Vendor-tier reality check

Sentry Internal Integrations carry no per-integration billing; `jikigai-eu` already carries three at zero recorded expense. `wg-record-recurring-vendor-expense-before-ready` records nothing new.

## Encryption Posture

Not applicable; recorded rather than silent. Detection set is `.tf`, `supabase/migrations/*.sql`, `cloud-init*.yaml`, `docker-compose*.yaml`; this plan touches none, introduces no persistent store and no new cross-component connection. The credential moves over the existing GitHub-Actions-secret and Sentry HTTPS channels already covered.

## GDPR / Compliance Gate determination

**Hard-rule limb — NOT APPLICABLE.** No path touched matches the canonical regex (`supabase/migrations/`, `lib/auth/`, `server/*auth*`, `app/api/*`, `.sql`). `fresh-host-boot-trail.sh` is under `infra/scripts/`.

**Skill Phase 2.7 expansion limb — FIRES on trigger (b)** (`brand_survival_threshold: single-user incident`). Discharged by the CLO advisory carried forward from the 2026-09-09 plan's `## Domain Review`, whose credential-half findings are unchanged by the split: no new Processing Activity (Art. 30(1)(g) technical-measure fact on a registered activity → one additive dated bracket on PA-8 §(g)); no published-disclosure change; Art. 33/34 not engaged in this shape (an operator's own infrastructure credential is not personal data; the duty is derivative and its trigger — BREACH on the #7797 investigation — has not fired); one `## Completed Compliance Work` row; Vendor Mapping unchanged (Sentry, Functional Software GmbH, DE, existing SCC terms). **No Critical finding**; nothing routes to Active Items; no `compliance/critical` issue.

## Architecture Decision (ADR/C4)

### ADR

**Amend `ADR-031-sentry-as-iac.md`** (Phase 4.1). No new ordinal is claimed; a fourth credential class on an existing taxonomy is an extension of that ADR's `## Decision`, and the DC-3 record with its rejected alternatives belongs in it. The duplicated-ordinal hazard is flagged in the amendment header and tracked at #6493 / #6960.

### C4 views

**No C4 impact**, with the enumeration in Phase 4.5: no external human actor changes; the only external system touched, `sentry`, is already modeled and included in both views; no container or data store is added; the `github -> sentry` access relationship exists and is unchanged in direction, protocol and purpose. The cardinalities `model.c4` embeds on that edge are untouched, and `plugins/soleur/test/c4-count-parity.test.sh` is run green (AC-10) rather than reasoned about.

### Sequencing

The ADR amendment is true at merge: the integration exists and is verified before the migrating commit lands (Phase 2 precedes Phase 3). No `adopting` status.

## Acceptance Criteria

### Pre-merge (PR)

1. `knowledge-base/project/specs/feat-one-shot-7946-sentry-org-token-retire/phase-0-scope-probe.md` records the per-consumer endpoint table with an HTTP status per row per token (pre-mint `inline-read-prd`, control `iac-terraform-prd`, post-mint `actions-read-prd`), the legacy-slug row, and every token's `.auth.scopes` verbatim. It contains no credential value or hash: `python3 plugins/soleur/skills/incident/scripts/redact-engine.py <file>` exits 0 and `grep -cE 'sntrys_|[0-9a-f]{40,}' <file>` returns 0.
2. `grep -rl SENTRY_AUTH_TOKEN scripts/followthroughs/ | wc -l` returns `0`.
3. `comm -3 <(ls scripts/followthroughs/*.sh | grep -v '\.test\.sh$' | xargs grep -l 'SENTRY_ACTIONS_RO_TOKEN' | sort) <(ls scripts/followthroughs/*.sh | grep -v '\.test\.sh$' | xargs grep -l 'SENTRY_ACTIONS_RO_TOKEN:+x' | sort)` prints nothing — every non-test consumer names the new credential in its own refusal, by identity not by count.
4. `grep -hE '^ORG=' scripts/followthroughs/sentry-checkins-3859.sh scripts/followthroughs/sync-health-residual-5689.sh | grep -c 'jikigai-eu'` returns 2; `grep -lE '"jikigai"|:-jikigai\}' scripts/followthroughs/*.sh | wc -l` returns 0.
5. `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` exits 0 — CI's exact invocation; every touched Rule D baseline line is remediated and deleted, never re-suppressed: `LC_ALL=C comm -12 <(git diff --name-only origin/main -- '*.sh' | LC_ALL=C sort) <(sed 's/:.*//' scripts/lint-shell-trace-credential-refusal-d.baseline.txt | grep -v '^#' | LC_ALL=C sort -u) | wc -l` returns 0, over every changed shell file, not only the followthroughs.
6. The ADR-031 amendment records the permission set selected in the form and the exact `.auth.scopes` returned; `phase-0-scope-probe.md` records the post-mint scopes sorted as exactly `alerts:read`-free `[event:read, org:read, project:read]` (no extra, no missing) and every per-consumer endpoint row at 200.
7. `gh secret list | grep -c '^SENTRY_ACTIONS_RO_TOKEN\b'` returns 1. (The value is asserted by AC-P1; the form is asserted by AC-12 and the dry run's `--no-store` ciphertext length recorded in `session-state.md`.)
8. `grep -c 'SENTRY_ACTIONS_RO_TOKEN: \${{ secrets.SENTRY_ACTIONS_RO_TOKEN }}' .github/workflows/scheduled-followthrough-sweeper.yml` returns 1 and `grep -c 'SENTRY_AUTH_TOKEN' .github/workflows/scheduled-followthrough-sweeper.yml` returns 0; `grep -c 'SENTRY_ACTIONS_RO_TOKEN: \${{ secrets.SENTRY_ACTIONS_RO_TOKEN }}' .github/workflows/apply-web-platform-infra.yml` returns 2.
9. `bash scripts/test-all.sh scripts` is green, including `scripts/lint-followthrough-varq-ban` (Guard 1 cases), `scripts/lint-shell-trace-credential-refusal` (Guard 2 cases), `scripts/sweep-followthroughs` (Guard 3 cases) and the repo-wide lint registration; `bash scripts/lint-orphan-test-suites.sh` exits 0 with 0 orphaned. No `run_suite` line is added.
10. `bash plugins/soleur/test/c4-count-parity.test.sh` is green and `git diff --name-only origin/main -- knowledge-base/engineering/architecture/diagrams/` is empty.
11. `bash apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` and `bash apps/web-platform/infra/doppler-download-error-channel.test.sh` are green with AC13 retargeted, not deleted: `grep -c 'SENTRY_ACTIONS_RO_TOKEN' apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` ≥ 2; `grep -c 'doppler' apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` returns 0 (every Doppler read is gone, not only the token's); `grep -cE '^\s*echo "::warning::.*SENTRY_ACTIONS_RO_TOKEN' apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` returns 1 and the suite anchors AC13 on that `echo` call plus the `tee -a "$GITHUB_STEP_SUMMARY"` write carrying the same sentence, not on the sentence alone; `grep -cE 'curl --disable --noproxy' apps/web-platform/infra/scripts/fresh-host-boot-trail.sh` ≥ 1; `awk '/Surface fresh-host Sentry breadcrumb trail/,/run:/' .github/workflows/apply-web-platform-infra.yml | grep -c 'DOPPLER_TOKEN'` returns 0.
12. `knowledge-base/engineering/operations/runbooks/sentry-actions-ro-token-rotation.md` exists; `grep -c '^## Failure modes' <file>` returns 1; `awk '/^## Failure modes/{f=1;next} /^## /{f=0} f && /^\|/' <file> | grep -vc -- '^|[- |]*$'` equals the number of enumerated failure modes in Phase 3.6 (now including "integration or token deleted dashboard-side — 401 vs 403") plus one header row, with every row's last cell non-empty; `grep -c 'ssh ' <file>` returns 0; in `scripts/rotate-sentry-actions-ro-token.sh`: `grep -c -- '--body' ` returns 0, `grep -c 'gh secret set SENTRY_ACTIONS_RO_TOKEN'` returns 1, `grep -c -- '--no-store'` returns 1 and that occurrence is inside the dry-run branch only, `grep -c -- "-H @"` ≥ 1 and `grep -cE 'Bearer \$' ` returns 0 (the header is read from a file, never from argv).
13. Every mutation-matrix row for Guards 1, 2 and 3 has a suite case (5, 3, 6). Each host suite carries an ADR-193 floor — `scripts/lint-followthrough-varq-ban.test.sh` and `scripts/sweep-followthroughs.test.sh` gain one (they have none on `main`), `scripts/lint-shell-trace-credential-refusal.test.sh`'s `MIN_ASSERTIONS` is bumped from 61 — each set to the total re-measured after the rows land, and `bash scripts/guard-vacuity-floor.test.sh` is green with both newly-floored suites in its population.
14. `grep -c 'SENTRY_AUTH_TOKEN' knowledge-base/engineering/operations/runbooks/followthrough-convention.md || true` returns 0 (three occurrences rewritten); `grep -c 'SENTRY_AUTH_TOKEN' plugins/soleur/skills/schedule/SKILL.md scripts/sweep-followthroughs.sh` returns `0` for both.
15. `git diff --numstat origin/main -- knowledge-base/engineering/operations/post-mortems/bash-x-credential-trace-exposure-postmortem.md | awk '{print $2}'` returns 0 — the post-mortem edit is pure append — and the new addendum names `### Still open`, the 2026-09-07 addendum's ADR-031 sentence, and both deferral issue numbers.
16. `knowledge-base/project/specs/feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction/decision-challenges.md` carries a `## DC-3 — RESOLUTION` heading whose body cites the 403 reading and points at ADR-031; `git diff --numstat origin/main -- <file> | awk '{print $2}'` returns 0 (append only).
17. `knowledge-base/legal/article-30-register.md` carries one additive dated bracket on PA-8 §(g) naming `actions-read-prd` and its scopes; `grep -c 'PA-36' <file>` returns 0; `knowledge-base/legal/compliance-posture.md` gains one `## Completed Compliance Work` row; `bash scripts/lint-legal-registers.sh` exits 0; `git diff --name-only origin/main -- plugins/soleur/docs/pages/legal/ docs/legal/` is empty.
18. `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0, invoked as CI invokes it.
19. `python3 scripts/lint-credential-path-literals.py` (full scan) exits 0 — the runbook, the script and the ADR amendment add no resolvable credential path.
20. `cd plugins/soleur && bun test test/components.test.ts` is green (the `schedule/SKILL.md` edit).
21. Both deferral issues exist (revocation with `Ref #7797` and `Ref #7946` and the enumerated readers; the rotate-x defect with the ciphertext-length evidence), and their numbers appear in the post-mortem addendum.
22. `session-state.md` records, for each of the fourteen migrated `.sh`, the `rc` **and the HTTP status the script observed** from one `env -i … bash -c 'export …; exec bash "$0"'` exercise under the IaC superset (Phase 3.3), with no `curl:` usage error, no HTTP `000`, no 4xx TRANSIENT, and no row left at `NOT EXERCISED`.
24. `bash scripts/sweep-followthroughs.test.sh` is green and its Guard 3 cases run the SUT with `bash "$SUT"`: `grep -cE 'bash "\$SUT"' scripts/sweep-followthroughs.test.sh` ≥ 6, and the M5 case's sentinel path is asserted absent after the run.
23. The PR body uses `Closes #7946` and `Closes #7993` (in the body, not the title — `wg-use-closes-n-in-pr-body-not-title-to`).

### Post-merge (automated, ship session, no operator step)

- **AC-P1.** After the directive rewrites, `gh workflow run scheduled-followthrough-sweeper.yml` completes; let `T` be that run's `createdAt`. For each of #6604, #6297 and #5689, `gh issue view <n> --json comments --jq '.comments[-1] | .createdAt + " " + .body'` shows a comment with `createdAt > T` whose body **starts with the `### Sweeper run:` heading** (the open-path verdict shape) and contains none of `required secret`, `bound but empty`, `SENTRY_ACTIONS_RO_TOKEN not set`, `SENTRY_AUTH_TOKEN`, nor `HTTP 401` nor `HTTP 403` — so a JSON-encoded or otherwise garbage stored value, which yields a 401 TRANSIENT, cannot pass; for #5689 it also does not contain `org=jikigai,`. `gh run view <id> --log | grep -cE 'required secret|bound but empty|malformed secret'` returns 0 and the run concluded `success`. A stale pre-dispatch comment cannot satisfy this.
- **AC-P2.** `gh issue list --label follow-through --state open --limit 200 --json body --jq '[.[] | select(.body | test("secrets=[^ ]*SENTRY_AUTH_TOKEN"))] | length'` returns 0, and the same query with `--state closed` restricted to `closedAt` within 14 days returns 0; the PR body carries the before/after `secrets=` table for every rewritten tracker.

## Domain Review

**Domains relevant:** engineering, legal. Operations is folded into `## Infrastructure (IaC)`. Product is NONE on the mechanical UI-surface override (no `components/**`, `app/**/page.tsx`, `app/**/layout.tsx` or UI-surface term in either file list), so `wg-ui-feature-requires-pen-wireframe` does not fire. Marketing, sales, finance, support: not implicated.

### Engineering

**Status:** reviewed. Carried forward from 2026-09-09 (nine lenses) and re-reviewed 2026-09-11 by the escalated panel — DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CTO (devex) and a scoped strong-model consult — with every finding re-verified in this worktree before being applied.

**What the 2026-09-11 panel changed, in order of consequence:**

1. **The store command was fabricated and its precedent is broken.** `gh secret set --body-file -` does not exist; `--body -` stores `-`. Kieran measured it with `--no-store`. Phase 2.2, the runbook, W2 and AC-12 now use stdin with no `--body`; the dry run proves the form with `--no-store`; the `rotate-x` defect is filed (strong-model consult + Kieran).
2. **The "loud fail" the first draft relied on is silent.** The sweeper's missing-secret branch prints to stderr and returns 0 under a green run. Phase 3.1b makes it post on the tracker and red the run (Guard 3); AC-P1 is timestamp-gated so a stale comment cannot pass it (architecture-strategist + spec-flow, independently).
3. **The trap scope is real only inside one Bash process.** The `agent-browser` path is primary; the MCP path's trap begins post-capture (spec-flow P0, consult).
4. **The decode is surface-dependent.** One tolerant normalise step with a shape assertion (consult).
5. **The boot-trail is in the Rule D baseline too** (line 27); its curl is remediated and AC-5 now spans every changed shell file (Kieran).
6. **A production apply runs at merge** — `apply-web-platform-infra.yml` fires on the boot-trail path; registered as W6, and ship is told not to re-dispatch it bare (CTO P0). Two headless checkpoints are named; W5 moved pre-merge (CTO).
7. **AC repairs:** AC-3 identity not count, `.test.sh` excluded; AC-4 command fixed; AC-1 redact-engine path form; AC-6 exact equality; AC-8 comment must not spell the retired name; AC-11 measures the retarget; AC-12 row count derived, not a magic number; AC-15/16 via `--numstat`; AC-13 no meta-rows (Kieran, DHH, spec-flow).
8. **Cuts:** the C4 edge edit, the committed census fixture, the throwaway `ZZ_DRYRUN` secret, Phase 0.2's live re-run (DHH, code-simplicity). Guard matrices trimmed to rows that are suite cases.
9. **Additions:** the zero-mint `SENTRY_IAC_AUTH_TOKEN`-under-new-name alternative and why P2 kills it (architecture-strategist); the workstation dry run via `dry_run=true` dispatch (CTO); the rotation cadence statement; the `[ -n '' ]` single-quote variant; a per-script `env -i` exercise before PR-ready (consult); the closed-within-14-days set in the rewrite and AC-P2 (spec-flow); the enumerated workstation readers in the revocation deferral (architecture-strategist).

**Surfaced, not applied (Taste / User-Challenge, persisted to this branch's `decision-challenges.md`):** land the Rule D remediation as a *separate preceding PR* rather than a first commit (four lenses); an Actions environment secret instead of a repo secret (consult, architecture-strategist).

### Legal (CLO)

**Status:** reviewed (carried forward; the credential-half findings are unaffected by the split). Art. 30: no new PA; one additive dated bracket on PA-8 §(g). Art. 32: no published-disclosure change. Art. 33/34: not engaged in this shape; the two bounding conditions (BREACH on the #7797 investigation; a third party's credential) are recorded in ADR-213 for #7947 and apply to the mint session here by the same logic. Post-mortem edit constraint: append only, nothing above the new heading changes. Vendor expense: none. Internal draft material, not external legal advice.

### Sign-off

`brand_survival_threshold: single-user incident` → `requires_cpo_signoff: true`. Discharged as on 2026-09-09: escalated plan-review at plan time; `user-impact-reviewer` at review time per the review skill's conditional-agent block.

## Test Scenarios

| # | Scenario | Expectation |
|---|---|---|
| T1 | `SENTRY_AUTH_TOKEN` restored on an executable line, in a `.test.sh`, and in a comment (three files) | Guard 1 RED in all three, true line numbers |
| T2 | Guard 1 floor forced above the live count on the production path | Exit 2; `TARGET_DIR` at an empty sandbox exits 0 |
| T3 | A probe naming `SENTRY_ACTIONS_RO_TOKEN` + `BETTERSTACK_API_TOKEN` | Guard 1 exit 0 |
| T4 | A migrated file's consumption renamed but its refusal predicate left on the old name (explicit-path run) | Existing Rule C RED: `Unguarded: SENTRY_ACTIONS_RO_TOKEN` |
| T5 | A single-credential file whose only limb is deleted (`[ -n "" ]`, and `[[ -n '' ]]`) | Guard 2 RED |
| T6 | A genuinely unconditional refusal | Guard 2 exit 0 |
| T7 | A tracker directive naming a secret absent from the env, one bound but empty, and one malformed (`a[$(touch …)]`), each run with `bash "$SUT"` against a stubbed `gh` | Guard 3: comment captured, `::error::`, `rc != 0`; the malformed name never expands (sentinel file absent); under `DRY_RUN=1` no comment, still non-zero |
| T8 | Every consumer's exact host + org + path probed with the new token | 200 on every row; scopes exactly the triple; any deviation blocks the cutover |
| T9 | The dry-run capture chain against the sentinel page with `--no-store` | Sentinel in no transcript-visible tool result; normalise output `diff`-identical to the sentinel; ciphertext length as computed; trap removes the directory; no secret written |
| T10 | The boot-trail script run with `SENTRY_ACTIONS_RO_TOKEN` unset | The `::warning::` annotation plus the named "not bound" line in the summary; exit 0 (skipped read is not a dark boot); no `doppler` call made |
| T11 | Infra observability suite with one workflow step's `env:` line removed | AC13 RED |
| T12 | Each of the fourteen migrated `.sh` run once under `env -i` with the IaC superset | rc ∈ {0,1,2}; no curl usage error; no HTTP 000; no 4xx TRANSIENT |
| T13 | Post-merge dispatch | #6604, #6297, #5689 receive a comment newer than the run; #5689 no longer reports `org=jikigai`; run log has no `required secret` |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The new token 403s on an endpoint, host or slug the table did not cover.** | Every consumer's exact URL probed post-mint with the live token before any file consumes it (Phase 2.3, AC-6); each script's TRANSIENT guard plus the sweeper comment names the status if one slips through. |
| **The stored value is wrong** (JSON-encoded, or the literal `-`, or garbage) and nothing can read it back. | The form is stdin with no `--body`; the normalise step asserts the token's shape; the dry run proves the form with `--no-store`; the post-merge timestamp-gated dispatch is the value assertion. |
| **Renaming re-opens the #7797 class by leaving a refusal on the old name.** | Existing Rule C, running in CI with baselines bypassed, reds on it — measured by mutation twice. AC-3 asserts the coupling by identity. Guard 2 closes the one blind spot. |
| **The Rule D drawdown (14 files) is the largest cost and could stall the PR.** | Budgeted in Phases 3.3 and 3.5 as the first commit, with the lint's own per-site remedy text; AC-5 asserts the lint green under CI's invocation; AC-22 runs every migrated script once. If a file's remediation proves unsafe, the fallback is to keep that file on the old baseline line **and** not rename it — which fails AC-2 and stops the PR rather than shipping a half-cutover. |
| **A scheduled sweep fires inside a cutover window.** | It now posts `required secret` on the affected trackers and reds its run (Guard 3) — the expected reading, bounded by the ship session, not a silent skip. |
| **The mint leaves a live token nobody holds.** | Capture, normalise, write, verify and shred in one Bash process on `EXIT INT TERM HUP`; a failed write revokes the token in-page before the trap fires; the chain is dry-run on the sentinel first with zero writes. |
| **The mint is itself a browser login — the #7947 hazard.** | Performed after #7975 shipped the interceptor and the redactor; `filename:` on every snapshot; no capture of the token panel; nothing typed as an MCP argument. |
| **`fresh-host-boot-trail.sh` silently self-skips again** (the class AC13 was written for). | The retargeted AC13 asserts the workflow binds the secret on both steps; the script names the unbound case in the summary. |
| **The merge runs a production Terraform apply.** | W6, expected no-op (no `.tf` change); ship does not re-dispatch the workflow bare. |
| **A workstation dry run reaches for `doppler run -c prd_terraform` out of habit.** | The new name cannot be satisfied by any Doppler config; the documented dry run is the sweeper's `dry_run=true` dispatch with the real secret; the explicit IaC-mirror assignment is the last resort with its caveat. |
| **Dashboard-side permission drift after the mint goes unnoticed.** | Detected at the next sweep; recorded as a known gap in ADR-031 rather than left implicit. |
| **The post-mortem edit drifts a legal record.** | Append only (AC-15, `--numstat` deletions = 0); nothing above the new heading changes. |

## Alternatives Considered

| Alternative | Why not |
|---|---|
| **Reuse `inline-read-prd` / `SENTRY_ISSUE_RO_TOKEN` and copy it into GitHub secrets** (DC-3's architecture arm). | Its `[event:read, org:read]` returns 403 on the check-in endpoint three followthroughs call (measured with a 200 control). Reuse would require widening a shared credential. Decided against on the reading; recorded as DC-3's resolution. |
| **Keep binding `secrets.SENTRY_IAC_AUTH_TOKEN` under the new name** (zero mint). | Satisfies P1, fails P2: `project:admin`, `project:write` and `alerts:write` on a repo-wide-reachable secret for a GET-only class, and couples the followthroughs to the IaC apply lifecycle — the coupling ADR-031 rejected for `web-platform-ci`. P2 is #7946's stated ask. |
| **A second token on `inline-read-prd`** (same integration, separate token, separate store). | Same 403 — the integration's permission set is the constraint, not the token. |
| **Widen `inline-read-prd` in place to `project:read`.** | Mutates a shared credential consumed by the no-SSH inline reader, contradicting ADR-031's narrow-by-adding rule. |
| **`alerts:read` instead of `project:read` for the check-in endpoint.** | Both satisfy it; only `project:read` also satisfies the boot-trail's project-events endpoint, so `alerts:read` would cost a second read scope for the union. |
| **Mint via the API using the personal token** (which carries `org:integrations`). | Circular: the retiring credential minting its own replacement, and it does nothing for the next rotation. |
| **Mirror the new token into Doppler** as ADR-031 does for the IaC token. | Two stores double the rotation surface; the `dry_run=true` dispatch is a better workstation path. |
| **An Actions environment secret instead of a repo secret.** | Strictly narrower and security-material (`event:read` reaches production event context), but needs a repo-settings write for the sweeper's environment (the provisioning jobs already have one) and diverges from both sibling Sentry secrets. Recorded as DC-5 (Taste); considered in the ADR amendment. |
| **Rule E as a rule family in the Python lint** (2026-09-09 plan). | Clause 2 is existing Rule C; clause 1 is a directory-scoped name ban, which `lint-followthrough-varq-ban.sh` already has the structure for. |
| **Extend `follow-through-directive-gate.sh` to validate `secrets=`.** | Once the sweeper's missing-secret path is loud (3.1b), a write-time gate buys one day. |
| **A dedicated cutover soak probe.** | No soak-gated criterion; the post-merge dispatch plus a timestamp-gated assertion on three named trackers is the verdict, with no new file in Guard 1's population. |
| **A committed census fixture.** | Stale the day after; GitHub keeps body-edit history; the live query is the AC. |
| **Edit the `github -> sentry` C4 label.** | No property, no relationship change, the existing label is not false, and it costs a regeneration plus three suites. |
| **Leave `fresh-host-boot-trail.sh` on the personal token** (out of #7946's literal scope). | It was the last repo-side reader of the personal value via Doppler; leaving it keeps the personal token load-bearing and blocks revocation. Two env lines, a named skip, one curl fix. |
| **Rule D remediation as a separate preceding PR.** | Recommended by four lenses; taken as a separate first *commit* in this PR instead, because a second pipeline tail doubles the operator's spend for a review-readability gain that per-commit review already provides. Recorded as Taste. |
| **Edit `### Still open` in place.** | The file's own contract is append-only, and the 2026-09-09 learning records the violation. |
