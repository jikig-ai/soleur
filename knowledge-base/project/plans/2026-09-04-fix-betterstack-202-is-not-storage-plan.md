---
title: "fix(observability): HTTP 202 from Better Stack is not evidence of storage — give the rung-2 capture a control read, and stop deriving green from an acknowledgement"
date: 2026-09-04
slug: fix-betterstack-202-is-not-storage
branch: feat-one-shot-7855-betterstack-202-not-stored
issue: 7855
closes: 7855
lane: cross-domain
type: fix
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-09-04
**Gates run:** 4.5 (network — fired on a false positive, disposition recorded), 4.6 (user-brand
impact — pass), 4.7 (observability — **halted this plan**, `logs:` was missing, now added), 4.8
(PAT-shaped — pass), 4.9 (UI wireframe — not triggered), 4.10 (encryption posture — not triggered),
4.11 (guard contract — `lint-guard-contract.py` green, 3 entries).
**Review panel:** Kieran, architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer, and
a scoped strong-model advisor. **Deepen agents:** verify-the-negative sweep, Better Stack schema
research, follow-through precedent diff.

### Key improvements

1. **The mechanism changed.** An earlier draft added a fourth state to the shared
   `bs_absence_classify`. That function takes **no arguments** and classifies the *warehouse*, and
   its only production consumer branches on the token as a string with no default arm — so a fourth
   token would have fallen through into the live-channel path. Replaced by a composition in the one
   caller that needs it (C6), which touches no shared contract.
2. **A false safety claim was caught.** The plan asserted source `2734275` was no alarm's positive
   control. It **is** — `ANCHOR_SQL` is an any-foreign-row control on exactly that source. The probe
   marker now carries no `host_name` key, and Guard 2 asserts the **field**, not the source id.
3. **A live credential bypass was found and pulled into scope.** The probe's
   `https://*.betterstackdata.com/*` destination check accepts `https://evil.com/?x=.betterstackdata.com/`,
   because a shell glob crosses `/` and `?`. The plan's own User-Brand Impact had been resting on it.
4. **Three load-bearing numbers were wrong and are now measured:** the poll bound is 16 minutes (not
   ~50, which was the comment's unbounded worst case), the caller population is 39 files / 141 lines
   / 29 invocation sites (not "eight", nor "71 sites"), and ADR-198 carries 3 occurrences of the
   eight-of-nine claim while the cloud-init file carries 4 more that this plan does not edit.
5. **The round-trip readback is grounded, not guessed.** The warehouse column set
   (`dt`, `raw`, `_row_type`, `ingest_time`, …) was measured against live archive rows, and
   `ingest_time` gives a server-side latency figure independent of the runner's clock. One residual
   unknown is named: the `http`-platform table's schema is inferred, not verified.
6. **The follow-through's exit codes were re-mapped to the sweeper's real semantics** — it collapses
   every non-0/1 code into one TRANSIENT arm, so the discrimination lives in the stdout verdict token
   the sweeper embeds in the issue comment.

### New considerations discovered

- The vendor **documents 402 "refused and discarded"** for over-quota, not 202-and-drop. The observed
  behaviour is 202 with nothing stored, so #7811 should not settle on quota without evidence.
- The first successful round-trip write **permanently creates the ClickHouse table**, which retires
  the `CLUSTER_DOESNT_EXIST` discriminator for that source forever. The instrument consumes its own
  discriminator exactly once; recorded in the ADR-192 amendment rather than discovered later.
- A cheaper H5 decider already exists at zero credential cost: correlating the emitter's existing
  Sentry `stage:betterstack_ingest` POST outcome against a CI readback.
- Eleven mechanisms were cut, six of them during review. Two ADR amendments, no new ADR, no ordinal
  claimed.

## Overview

The rung-2 rehearsal for the git-data host cannot reach a verdict because the Better Stack query
it depends on has no table to read. Better Stack creates the ClickHouse table lazily on the first
stored row; no row has ever been stored in source `2734275`, so every read returns a 500 and the
capture reports TRANSIENT twenty times without producing evidence. The birth gate stays held,
correctly, on the missing evidence.

Plan-time measurement changed the shape of this problem. The warehouse has stored **no row from
any producer** since `2026-09-03 12:18:10Z`, and the git-data source was created at
`2026-09-03T21:07:19Z` — roughly nine hours **after** the last stored row in the account. The
git-data source has therefore never had a single opportunity to store a row into a working
warehouse. Its table's absence is fully explained without invoking anything git-data-specific,
and the team-wide condition is already tracked as #7811.

That does not weaken this issue's four remediations; it is the strongest available argument for
them. During a 27-hour warehouse outage this repo's ingest probe kept printing
`INGEST_ACCEPTING http=202` — a token that appears verbatim inside #7811, an issue titled
"Better Stack is accepting no writes". The invariant this work encodes is that **a 2xx from
Better Stack is not evidence of storage**, and the deliverable is the small set of instruments
that would have said so on day one instead of after a multi-day investigation.

The change is deliberately small. The single highest-value edit is one arm of one script: when the
capture's source-liveness anchor fails, it reports *"unreachable or unauthorised"* — a cause the
run did not measure — instead of asking the one question that separates "this source has never
stored a row" from "the warehouse is dark for everyone".

Plan review then found a live defect the plan had been treating as a control: the ingest probe's
destination assertion does not actually pin the destination. Fixing it is in scope, because this
plan's own User-Brand Impact was resting on it.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed); no `spec.md` exists for this
branch, so the frontmatter `lane:` is the fail-closed default rather than a carry-forward.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited | Probe | Result |
|---|---|---|
| Issue #7855 (work target) | `gh issue view 7855` | **OPEN**, label `compliance/critical`, no closing PR. Premise holds. |
| #7204 ("already fixed") | `gh issue view 7204` | **OPEN**. The fix landed; the tracker did not close. Recorded so nothing downstream asserts #7204's status from this prose (`hr-before-asserting-github-issue-status`). |
| #7772 | `gh issue view 7772` | CLOSED. |
| PR #7805 | `gh issue view 7805` | **MERGED**. |
| `scripts/betterstack-query.sh`, `scripts/betterstack-ingest-probe.sh` | `test -f` | Both exist. |
| The emitter cited as `cloud-init-git-data.yml:643` | `git ls-files` | Exists at `apps/web-platform/infra/cloud-init-git-data.yml`; the anchor is the `write_files` entry for `/usr/local/bin/git-data-emit` (`cq-cite-content-anchor-not-line-number`). |
| ADR-198 | `grep -c -i eight` | **3** occurrences in the ADR. `apps/web-platform/infra/cloud-init-git-data.yml` carries **4** more — a different file, treated separately below. |
| Table-name convention | Telemetry API `GET /api/v2/sources` | `table_name` is `soleur_git_data_prd`, team `520508` → `t520508_soleur_git_data_prd_logs`. **Confirmed correct.** |

**One premise is falsified, and it is the load-bearing one.** The issue frames the open question as
a choice between (a) ingest→query latency longer than the capture's polling window and (b) direct
POSTs accepted but not stored for this payload shape, on the strength of a control experiment
against source `2457081` described as "known-good, actively-used". Both halves of that control are
invalid:

1. **Source `2457081` was already dark when it was used as a control.** Measured at
   `2026-09-04 15:56Z`: the hot window (`remote(t520508_soleur_inngest_vector_prd_3_logs)`) holds
   `{"n":0}` with no time filter at all, and the 7-day archive holds 935,481 rows whose newest is
   `2026-09-03 12:18:10` — nothing stored for ~27.6 hours.
2. **Its platform is `vector`, not `http`.** The Telemetry API reports `platform: vector` for
   `2457081` and `platform: http` for `2734275`. A raw HTTP row into a Vector-platform source is
   not the same transport, so even a live `2457081` would not have been a control for a direct POST.

**The silence is common-mode, not per-producer.** Three independent producers stopped together:

| hour (UTC) | `soleur-web-platform` | `soleur-inngest-prd` | unnamed (host-metrics) |
|---|---|---|---|
| 2026-09-03 08:00 | 4228 | 479 | 1996 |
| 2026-09-03 09:00 | 564 | 52 | 190 |
| 2026-09-03 10:00 | — | — | — |
| 2026-09-03 11:00 | 97 | 41 | 195 |
| 2026-09-03 12:00 | 182 | 17 | 48 |
| 2026-09-03 13:00 onward | 0 | 0 | 0 |

Three producers on at least two hosts collapsing in lockstep is one failure at the sink.

**What remains UNKNOWN, stated as unknown.** Why the warehouse stores nothing is not determined
here. `ingesting_paused` is `false` on both sources and retention is 90 days on both. The Telemetry
API exposes no usage or billing endpoint under the credentials available — `GET /api/v2/usage`,
`/api/v2/query/usage` and `/api/v2/source-groups` all return 404 — so the quota hypothesis is **not**
confirmable from the observability layer as currently credentialed.

One **documented** contrast is worth carrying to #7811, stated as documentation rather than as a
diagnosis: Better Stack's HTTP ingest API documents **402** with body `{"error": "Quota exceeded"}`
as the over-quota response, and describes those logs as *refused and discarded*. The observed
behaviour is a **202** with nothing stored. So "silently over quota" is not the vendor's documented
failure mode for this endpoint, and #7811 should not settle on it without evidence. This plan draws
no conclusion from that; it records it.

A second discrepancy is carried across **without** asserting causation, and with a correction: repo
literals for source `2457081` post to `s2457081.eu-fsn-3.betterstackdata.com` while the API reports
that source's `ingesting_host` as `s2457081.eu-central-1a.betterstackdata.com`. This is **not a
novel finding** — `apps/web-platform/infra/git-data.tf` already records it from #7772: *"Do NOT
pattern-match this off the registry's `eu-fsn-3` literal — the two sources sit on different
clusters, and the API reports `eu-central-1a` for 2457081 as well, so the older literal's shape is
not a template for new ones."* Moreover ADR-172 measured its 17 s POST→queryable latency **against
`eu-fsn-3`**, so that endpoint demonstrably worked. "Stale" is an inference, not a measurement, and
this plan's own thesis forbids shipping on one. Measured count, not the earlier estimate of seven:
`eu-fsn-3` appears on **12 lines across 6 named files**, plus `git-data.tf`, `zot-log-shipper.test.sh`,
`.github/workflows/registry-zot-inventory.yml`, `scripts/followthroughs/zot-inventory-marker-7278.sh`,
`tests/scripts/test-betterstack-ingest-probe.sh`, `tests/scripts/test-zot-inventory.sh`, and a legal
corpus surface. **This plan changes none of them** (AC13).

### Measured discriminators available today

`scripts/betterstack-query.sh` runs `curl -sS --fail-with-body`, so the discriminating body is
already on stdout when a read fails. Measured at `2026-09-04 15:54Z`:

| Read | exit | body |
|---|---|---|
| `remote(t520508_soleur_inngest_vector_prd_3_logs)` (control) | 0 | `{"n":0}` |
| `remote(t520508_soleur_git_data_prd_logs)` | 22 | `Code: 701 … Requested cluster … not found. (CLUSTER_DOESNT_EXIST)` |
| `s3Cluster(primary, t520508_soleur_git_data_prd_s3)` | 22 | `Code: 669 … no named collection … (NAMED_COLLECTION_DOESNT_EXIST)` |

The hot and archive arms fail with **different** codes, so a classifier keyed on one arm's string is
half a classifier. The **control read is the discriminator**; the error strings are carried as the
*reason*, never as the decision.

### The live defect plan review found

The ingest probe's destination assertion is `case "$BETTERSTACK_INGEST_URL" in
https://*.betterstackdata.com/*)`. A shell glob `*` crosses `/` and `?`, so the leading wildcard
swallows the whole authority. Measured:

| URL | current pattern |
|---|---|
| `https://evil.com/?x=.betterstackdata.com/` | **ACCEPTS** |
| `https://attacker.example.org/a/.betterstackdata.com/x` | **ACCEPTS** |
| `http://s1.betterstackdata.com/` | rejects (scheme anchor works) |

The scheme anchor holds; the host anchor does not. The probe forwards a bearer ingest token, and
`BETTERSTACK_INGEST_URL` is env-overridable and already exported into host environments elsewhere in
this repo. Phase 2.2 fixes it by extracting the authority before matching.

### Property List (Phase 0.6b)

- **P1.** When the rung-2 capture cannot read its instrument, its output distinguishes "this source
  has never stored a row (or is misaddressed)" from "the warehouse is dark for every producer" from
  "the instrument itself failed". Only the first is evidence about the rehearsal host.
- **P2.** No token this repo emits can be read as "rows are stored" when it was derived from an HTTP
  status alone.
- **P3.** The rung-2 poll budget is a stated multiple of a POST→queryable latency measured against
  the source the capture actually reads.
- **P4.** The claim that eight of nine boot stages reach the queryable channel is backed by a read,
  or restated to what the emitter verifies.
- **P5.** The ingest credential cannot be forwarded to a destination outside the vendor.

### Cut List (Phase 0.6b)

Eleven mechanisms removed. **C6–C11 were cut during plan review, after earlier drafts had adopted
them** — recorded rather than quietly dropped, because most were wrong for reasons worth keeping.

| Cut mechanism | Property claimed | What already covers it / forbids it |
|---|---|---|
| **C1.** New exit codes in `scripts/betterstack-query.sh` for table-absent | P1 | **Forbidden by a standing decision.** `scripts/betterstack-assert-absence.sh` §"WHY A SEPARATE SCRIPT…": *"that file is a pure transport. Its exit vocabulary is already spoken for … Overloading it would make every existing caller's error handling ambiguous."* Measured blast radius, re-derived at deepen time because an earlier draft's figure did not reproduce: **39 non-test scripts, 141 referencing lines, 29 of which actually invoke the script** (`git grep -ln 'betterstack-query' -- scripts/ | grep -v '\.test\.sh$' | wc -l` → 39; the same grep with `-n` → 141). An earlier draft said "eight", attributed to a header that states only *"every existing caller"* and names no number; a later draft said "71 sites", which also did not reproduce. Both miscounts strengthen the cut. |
| **C2.** Build a three-state classifier | P1 | **Already exists.** `bs_absence_classify` emits `TRANSPORT_FAIL` / `INGEST_DARK` / `LIVE` (ADR-192 I-1). |
| **C3.** Make `betterstack-ingest-probe.sh` post a real payload and read it back | P2 | **Explicitly rejected by ADR-192**: *"The probe writes nothing … a probe that wrote its own marker would satisfy that control forever and convert a two-day outage into a permanent blind spot."* |
| **C4.** A new principle that poll budgets derive from measured latency | P3 | **Already decided.** ADR-172 §2: *"The poll budget is a multiple of the measured 17 s POST→queryable latency; below that floor a non-observation is `unknown`, never a verdict."* |
| **C5.** Widen the rung-2 polling window | P3 | **Measured: nothing to fix.** `.github/workflows/git-data-rung2-rehearsal.yml` sets `deadline=$(( SECONDS + 16 * 60 ))` — **16 minutes**, ~56× the measured 17 s. An earlier draft said "~50 min / ~176×", read off the *comment* describing the unbounded attempt-count worst case the deadline exists to cut. Corrected against the literal. |
| **C6.** A fourth state in `bs_absence_classify` | P1 | **Cut at review.** The function takes **no arguments**: it reads `$BS_CONTROL_WINDOW`, queries once, and answers about *the warehouse*. A target-vs-control state needs an arity change to a shared library whose only production consumer, `scripts/zot-restart-loop-alarm.sh`, branches on the token **as a string** at two sites — one `if/if` with no `else` and one `case` with no `*)` arm. A fourth token would fall through both into the live-channel path. The state is available to the caller as the product `(anchor_rc != 0) × bs_absence_classify()`; composing it costs one arm of one script and touches the alarm not at all. |
| **C7.** An enumerator forcing all `betterstack-query.sh` callers through the chokepoint | P1 | **Cut at review.** Population is 39 files / 141 lines / 29 real invocation sites, of which exactly **one file** routes through `bs_absence_classify` today — so the guard is red on day one and greens only via ~38 opt-out declarations in scripts belonging to other issues, at which point it certifies annotation, not behaviour. The repo's only comparable enumerator (`scripts/lint-supabase-deprecated-endpoints.sh`) costs 460 + 606 LOC, and its own suite records that an allowlist *"buys 'this file is not a caller', never 'this file is exempt'"* — the opposite of the opt-out semantics this would need. |
| **C8.** A new ADR for the readback-placement decision | P4 | **Cut at review** — it records a non-decision, and the convention (ADR-096 *"No new ordinal is claimed; this amends ADR-096 in place"*, ADR-164, ADR-116) is to amend when the subject is an existing ADR's subject. Folded into the ADR-198 amendment. Removes the ordinal-collision risk entirely. |
| **C9.** A separate `scripts/betterstack-roundtrip-probe.sh` behind the follow-through | P2 | **Cut at review** — the abstraction is justified only by a second caller, and no phase creates one. `followthrough-convention.md` requires the sweeper's `script=` path to live under `scripts/followthroughs/`; it does not require a second file behind it. Collapsed into one script plus its suite. |
| **C10.** A `--dry-run` arm to satisfy `discoverability_test` | P2 | **Cut at review** — self-defeating. `deepen-plan` Check 10 rejects a command whose first token is outside its allowlist (`doppler` is not on it) and skips execution entirely when `credentials_required` is declared, so the arm's only gate never runs it, while AC-ing it created a live-credential operator step in a pre-merge list. `discoverability_test.command` now points at the suite, whose first token is `bash` — allowlisted, credential-free, and actually executed. |
| **C11.** Correcting the probe's `eu-fsn-3` default in this PR | — | **Cut at review.** `.github/workflows/scheduled-zot-restart-loop.yml` invokes the probe **bare**, and that invocation is the pager that files and re-probes #7811. No test pins the default. Changing it mid-incident makes #7811's own 202 evidence non-comparable, and "stale" is an inference — ADR-172 measured a working POST against `eu-fsn-3`. |

### Applicable institutional learnings

- `knowledge-base/project/learnings/best-practices/2026-05-29-http-verification-gates-must-check-status-not-just-transport.md`
- `knowledge-base/project/learnings/best-practices/2026-07-03-pass-is-not-proof-three-vacuous-green-traps-in-infra-verification.md` — Trap 2 is this shape exactly.
- `knowledge-base/project/learnings/best-practices/2026-06-05-external-cli-exit-0-is-not-proof-validate-the-artifact.md`
- `knowledge-base/project/learnings/best-practices/2026-06-30-adaptive-ci-poll-gate-wall-clock-ceiling-not-attempt-count.md` — already satisfied (C5); cited so it is not regressed.
- `knowledge-base/project/learnings/2026-06-10-betterstack-quota-diagnosis-host-metrics-dominate-generic-http-sink.md` — the region hypothesis is **ruled out for git-data**: both sources are `eu-central-1a`, and the control read succeeds on the same connection that fails for `2734275`.
- `knowledge-base/project/learnings/2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed.md`
- `knowledge-base/project/learnings/2026-08-10-six-times-a-check-certified-something-other-than-what-it-named.md`

### Governing ADRs and principles

- **ADR-172** §2 — readback before trust; poll budget a multiple of measured latency; a readback needs a positive control, and zero control rows means `channel_dark`, never `marker_absent`. Records **POST → queryable = 17 s** (2026-08-06, workstation, `2457081`/`eu-fsn-3`).
- **ADR-192** — the three-state classifier and the non-writing probe. `status: adopting`, so amend-in-place is available.
- **ADR-197** D-1/D-2/D-4; **ADR-199** commitment 3 (distinct tokens when remedies differ) and commitment 2 (positive allowlist; every other token aborts); **ADR-198** (write-only-append capability ceiling, the "eight of nine" claim); **ADR-193** (a floor reports directly, never through the suspect).
- **Principles register** (`knowledge-base/engineering/architecture/principles-register.md`): **AP-021** (a message may name only a cause the run measured) — Phase 1 is textbook AP-021; **AP-023** (anti-vacuity floors); **AP-024** (*a verification surface does not actuate*) — the round-trip probe performs the write it judges, so the carve-out is claimed explicitly in Phase 3.4 rather than by silence.

### Open Code-Review Overlap

**None.** 63 open `code-review` issues fetched; no planned path appears in any body.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (measured) | Plan response |
|---|---|---|
| Remaining candidates are latency or accepted-not-stored | A third explanation accounts for everything: the warehouse has stored nothing from any producer for ~27.6 h (#7811). | Ship instruments, not a root-cause fix for #7811. |
| `2457081` is a known-good control | Dark at the time, and `platform: vector` vs git-data's `http`. | Retired as evidence. |
| Widen the polling window | 16-minute wall clock, ~56× the measured 17 s. | Cut (C5); the "~50 min / ~176×" of an earlier draft came from a comment, not the literal. |
| The capture conflates table-absent with transport-broken | Confirmed, and worse: the `anchor_rc -ne 0` arm emits *"unreachable or unauthorised"*, naming two causes the run never measured. That is what run 33888071954 printed twenty times. | Phase 1 replaces exactly that arm. |
| `bs_absence_classify` can take a fourth state | It takes **no arguments** and classifies the warehouse. Its sole consumer fails open on an unknown token. | Cut (C6); compose in the capture. |
| `2734275` is no absence alarm's positive control | **False.** `ANCHOR_SQL` is an any-foreign-row control on that source (`host_name != '' AND host_name != '<this host>'`), under a heading that names it: *"THE FOREIGN-HOST ANCHOR DIED WITH THE SOURCE SPLIT."* | The marker carries **no `host_name` key**; Guard 2 reddens on the *field*, not only the source id. |
| The capture never considered discriminating these states | **It did, and declined.** Its `export BS_TABLE=` comment block enumerates the three outcomes and says: *"Accepted rather than special-cased: distinguishing the two costs a vendor-error-string match, and a string match on a vendor 500 is exactly the kind of guard that rots silently."* | This plan **reverses** that decision and must be read as a reversal. It answers the objection: the discriminator is a control read, not a string match. Recorded in the ADR-192 amendment. |
| The probe's destination assertion pins the destination | **False.** `https://evil.com/?x=.betterstackdata.com/` is ACCEPTED. | Phase 2.2 fixes it; P5 added to the Property List. |
| The capture's external contract is 0/1/2 | It is **0/1/2 plus 64** for usage errors. | Stated so nobody "tidies" the 64 path. |
| ADR-198's claim appears three times, one in the cloud-init emitter | ADR-198 carries **3**; the cloud-init file carries **4 more**, and this plan does not edit that file. | The amendment covers ADR-198's three. The cloud-init comments are deferred with the ForceNew cost stated. |
| The emitter should verify a row per boot | Readback needs the ClickHouse query connection, which is **team-scoped** — it reads every source in team 520508, not just git-data's. Baking it would put a whole-warehouse read credential on the host. Plus `runcmd` is once-per-instance, ADR-115 bars reboot, and the edit is ForceNew. | Decide **no**, reasoning in the ADR-198 amendment, with a cheaper alternative recorded (below). |

## Hypotheses

| # | Hypothesis | Disposition | Basis |
|---|---|---|---|
| H1 | Wrong table-name convention | **REFUTED** | API `table_name` + team id give the queried name. |
| H2 | Cross-region cluster miss | **REFUTED** | Both `eu-central-1a`; same connection answers for `2457081`, fails for `2734275`. |
| H3 | Ingestion administratively paused | **REFUTED** | `ingesting_paused: false` on both. |
| H4 | Latency exceeds the polling window | **REFUTED** | 16-minute wall clock vs measured 17 s (~56×); table absent >18 h since source creation. |
| H5 | POSTs accepted-not-stored *for this payload shape* | **UNKNOWN** | Untestable while the warehouse stores nothing from any producer. Phase 3's follow-through decides it. |
| H6 | The warehouse accepts and discards writes team-wide | **CONSISTENT, NOT CONFIRMED** | Three producers in lockstep; nothing stored 27.6 h; ingest still 202. No usage endpoint. Tracked as #7811, **not adopted as a finding**. |
| H7 | The `eu-fsn-3` / `eu-central-1a` literal mismatch | **OBSERVED, CAUSATION NOT ESTABLISHED, AND ALREADY RECORDED** | `git-data.tf` documented it in #7772; ADR-172 measured a working POST against `eu-fsn-3`. Reported to #7811. |

## Network-Outage Deep-Dive (gate fired on a false positive — disposition recorded)

`deepen-plan` Phase 4.5's keyword scan fires on this plan: `unreachable` appears 7 times, `SSH`
once, `firewall` once. **All are false positives, and recording that is cheaper than skipping the
gate silently.** Every `unreachable` occurrence is the quoted literal
*"unreachable or unauthorised"* — the string this plan exists to DELETE from the capture, because
it names two causes the run never measured. `SSH` appears only in the `logs` field asserting the
paths need none; `firewall` only in the IaC-skip sentence listing what is not introduced.

This plan diagnoses no connectivity symptom. Nonetheless the layer status for the transport it does
touch, per `hr-ssh-diagnosis-verify-firewall`'s L3→L7 ordering:

| Layer | Status for this plan's paths |
|---|---|
| L3 firewall / egress | **Not implicated, verified by measurement.** The ClickHouse query path answers `{"n":0}` with exit 0 from this session against `2457081`, so egress to Better Stack is open and authenticated. A blocked path would not have produced a successful control read. |
| L3 DNS / routing | **Not implicated.** Both source hosts resolve and answer; the `2734275` failure is an application-layer 500 carrying a ClickHouse error code, not a connect or resolve failure. |
| L7 TLS / proxy | **Not implicated.** `--proto '=https'` is enforced and the reads complete with HTTP status codes, so TLS terminates correctly. |
| L7 application | **This is the whole subject.** The 500 `CLUSTER_DOESNT_EXIST` is an application response to a well-formed authenticated request. |

The one genuinely open network-adjacent question — why the vendor accepts writes it does not store —
belongs to #7811 and is recorded as H6/H7 above, unconfirmed.

## User-Brand Impact

**If this lands broken, the user experiences:** a git-data host declared healthy and born on evidence
that was never read. The concrete artifact is
`apps/web-platform/infra/git-data-rung2-boot-evidence.env` carrying `RUNG2_BOOT_REHEARSAL=PASS`
derived from a warehouse read that returned nothing, which releases the binding hold in
`tests/scripts/lib/git-data-birth-readiness-gate.sh` and lets `git_data_host_create` apply. A host
holding the user's git data would then run with eight of its nine boot stages unobserved, and the
first evidence of a bad boot would be the user's own missing data.

There is a second way this lands broken, which plan review caught: if the round-trip marker carried
a `host_name`, it would satisfy `ANCHOR_SQL` — the capture's own source-liveness control — and the
rehearsal would read a probe's own row as proof that the rehearsal host's channel is live. That
converts this plan from a fix into the failure it exists to remove, at the one source that gates a
host birth.

**If this leaks, the user's workflow is exposed via:** the ingest bearer token. An earlier draft
named the probe's `https://*.betterstackdata.com/` destination assertion as one of the controls
holding that vector closed. **It does not**: measured, that pattern accepts
`https://evil.com/?x=.betterstackdata.com/`, because a shell glob crosses `/` and `?`. The controls
that genuinely hold today are `--proto '=https'` (verified: `http://s1.betterstackdata.com/` is
rejected) and the absence of `-L`. Phase 2.2 makes the host anchor real by extracting the authority
before matching, and Guard 3 drives red on each of the three.

**Brand-survival threshold:** `single-user incident`.

A single git-data host born on unread evidence is a single-user incident by construction: that host
is the store for one operator's repository data, and there is no aggregate pattern to wait for.
`requires_cpo_signoff: true` is set, and `user-impact-reviewer` is invoked at review time.

## Architecture Decision (ADR/C4)

### ADR

**Two amendments, no new ADR** (C8). No ordinal is claimed, which removes the collision risk.

1. **Amend ADR-192** (`status: adopting`) with three additions to `## Decision`: (i) the composed
   `(target read failed) × (control answered)` reading and what it does **not** prove — it is not
   proof the producer is at fault, because a misaddressed source produces the same pair;
   (ii) the narrowed writing rule that actually generalises — **a probe may write to a source only
   if its marker cannot satisfy that source's positive control** — with the old blanket phrasing
   moved to alternatives; (iii) the consequence nobody should rediscover later: **the first
   successful round-trip write creates the ClickHouse table permanently**, so `CLUSTER_DOESNT_EXIST`
   for `2734275` never recurs and the capture's "nothing has EVER written to this source"
   degradation dies with it. The instrument consumes its own discriminator exactly once.
2. **Amend ADR-198** at its **three** occurrences, restating "eight of the nine stages gain a
   queryable second channel" to what the emitter verifies — the stages POST and receive a 2xx — and
   recording the no-on-host-readback decision. The load-bearing fact is that the ClickHouse query
   connection is **team-scoped**: baking it would put a whole-warehouse read credential on the
   git-data host, which fails ADR-198's own capability-ceiling leg. Record the cheaper alternative
   considered and not taken (below). The **four** matching comments in
   `apps/web-platform/infra/cloud-init-git-data.yml` are deferred: that file is `user_data`, so a
   comment edit costs a host replace.

**Cheaper alternative, recorded rather than omitted.** The emitter already mirrors its POST outcome
to Sentry as `stage:betterstack_ingest`. So the correlation *(Sentry: POST returned 2xx at T)* × *(CI
readback: no row at T)* is available today, at zero credential cost and with no write — and it is an
H5 decider. It is weaker than the probe (it fires only when a rehearsal runs) but it is free, and an
ADR that rejects on-host readback without naming it reads as an oversight later.

### C4 views

**No C4 impact.** All three model files were read in full —
`knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`, `spec.c4` — not grepped for
the feature noun. Enumeration checked: **external human actors** (none — every actor is a CI job or
boot script); **external systems / vendors** (Better Stack only, already modelled with its ingest and
query edges; no new vendor, webhook or third-party store); **containers / data stores** (none — no
store created, host and volume unchanged since no `.tf` or cloud-init is edited); **actor↔surface
access relationships** (unchanged — CI already both writes to and reads from Better Stack, so the
round-trip traverses two existing edges). No element description is falsified.

### Sequencing

Phase 1 depends on nothing and is the highest-value change. Phase 3's round-trip cannot be
*validated* until the warehouse stores again, so its live measurement is a follow-through.

## Infrastructure (IaC)

**Skipped deliberately.** No server, service, cron, vendor account, DNS record, secret or firewall
rule is introduced. `apps/web-platform/infra/cloud-init-git-data.yml` is **not** edited — the
no-on-host-readback decision expressed as scope, since an emitter edit is `user_data` ForceNew. The
`## Encryption Posture` gate does not fire for the same reason: no `.tf`, no migration, no cloud-init
edit, no new persistent store, and no new cross-component connection (the round-trip's write and read
edges both already exist from CI). AC14 makes the boundary mechanical.

## Observability

```yaml
liveness_signal:
  what: the rung-2 capture's classification line naming which of three epistemic states the run
        reached, and SOLEUR_BETTERSTACK_ROUNDTRIP verdict=<token> from the follow-through probe
  cadence: per rung-2 rehearsal dispatch for the capture line; daily sweeper for the round-trip
  alert_target: capture log artifact and workflow step summary; the follow-through tracker issue
                for the latency measurement and for a stored-vs-not-stored verdict
  configured_in: scripts/followthroughs/git-data-rung2-evidence-capture.sh,
                 .github/workflows/git-data-rung2-rehearsal.yml,
                 scripts/followthroughs/betterstack-roundtrip-latency-7855.sh,
                 .github/workflows/scheduled-followthrough-sweeper.yml
error_reporting:
  destination: capture log artifact and step summary; verdicts travel in the exit code per
               ADR-197 D-2 and on stdout per the constitution's operator-signal rule
  fail_loud: true — every arm exits non-zero with a named reason; no arm returns 0 on an unproven read
failure_modes:
  - mode: the target read failed while the control answered — this source has never stored a row,
          or is misaddressed
    detection: (anchor_rc != 0) x bs_absence_classify() == LIVE
    alert_route: capture reports TRANSIENT naming the target source, carrying the ClickHouse error
                 code as the reason, and naming BOTH possible causes rather than picking one
  - mode: the warehouse is dark for every producer
    detection: (anchor_rc != 0) x bs_absence_classify() == INGEST_DARK
    alert_route: capture reports TRANSIENT naming #7811 and explicitly not blaming git-data
  - mode: the instrument itself failed
    detection: (anchor_rc != 0) x bs_absence_classify() == TRANSPORT_FAIL
    alert_route: capture names the instrument as the suspect
  - mode: ingest accepts but the row is never queryable (H5 confirmed — vendor data loss)
    detection: follow-through emits ROUNDTRIP_NOT_STORED, its own exit code, while the control read
               answers with rows
    alert_route: the follow-through comments the verdict and keeps the tracker OPEN; distinct exit
                 code from the dark case so the two never render as one daily TRANSIENT
  - mode: nothing to measure yet — the warehouse is still dark
    detection: follow-through emits ROUNDTRIP_DARK, a different exit code
    alert_route: tracker stays open with the dark reason; no latency constant is recorded
  - mode: the credential could be forwarded off-vendor
    detection: Guard 3 in tests/scripts/test-betterstack-roundtrip-latency.sh
    alert_route: CI red at PR time; this mode is prevented, not observed in production
logs:
  where: the rung-2 capture writes to the `git-data-rung2-capture-log` workflow artifact and to
         `$GITHUB_STEP_SUMMARY`; the follow-through's output is captured by
         `.github/workflows/scheduled-followthrough-sweeper.yml` and rendered as a comment on the
         tracker issue. Neither path requires SSH, and neither writes to the git-data host.
  retention: GitHub Actions artifact retention for the capture log (repo default, 90 days) and
             indefinite on the tracker issue for the follow-through comments, which is what makes
             the latency measurement durable once it lands
discoverability_test:
  command: bash tests/scripts/test-betterstack-roundtrip-latency.sh
  expected_output: the suite's final line reports a non-zero case count with passes + fails == cases
                   and exits 0
```

The `discoverability_test` deliberately names the suite rather than a live probe: its first token is
`bash`, which is on `deepen-plan` Check 10's allowlist, it needs no credentials, and Check 10
therefore **executes** it instead of skipping it as `SKIP-DECLARED`. A `doppler run …` command would
have been skipped by the only gate that would have run it (C10).

## Guard Contract

### Guard 1 — the capture never names a cause it did not measure

**Property.** When the capture's source-liveness anchor fails, its output names which of three
epistemic states the run reached and asserts nothing beyond what the pair of reads proves — never
"unreachable or unauthorised", and never "the producer is at fault", when the observation is equally
consistent with a misaddressed source or a dark warehouse.

**Assembly.** Every arm of `scripts/followthroughs/git-data-rung2-evidence-capture.sh` that turns a
failed read into operator-facing text, plus the step-summary text in
`.github/workflows/git-data-rung2-rehearsal.yml`. The chokepoint is the capture's `transient()`
helper — the script already carries a mutation-armed assertion against a bare `exit 2` outside it, so
the chokepoint is real and enforced today. The guard asserts that no `transient()` call site
reachable from a read failure contains a cause-naming phrase the composed reading did not establish,
enumerating call sites by grepping `transient(` in that one file. Scope is this file, not the 39
scripts that call `betterstack-query.sh` (C7).

**Mutation matrix.**

| # | Mutation | Must drive RED because |
|---|---|---|
| 1 | Restore *"the Better Stack query transport exited N (unreachable or unauthorised)"* | It names two causes the run did not measure — the exact string run 33888071954 printed twenty times. AP-021. |
| 2 | Emit the dark-warehouse sentence when `bs_absence_classify` returns `LIVE` | Opposite operator actions; ADR-199 commitment 3. |
| 3 | Make the target-failed-control-answered arm assert the producer is at fault | Over-claims: a misaddressed source (H1) produces the identical pair. |
| 4 | Delete the `BS_TABLE`/`BS_TABLE_S3` override on the classify call | The capture `export`s `BS_TABLE=t520508_soleur_git_data_prd_logs` process-wide, so the "control" would read the **absent target**, always return `TRANSPORT_FAIL`, and collapse three states into one — a silent regression to today's behaviour with the suite otherwise green. |
| 5 | Reorder so the classification line is emitted **before** `bs_absence_classify` runs, using a default | A property about which datum informs a decision cannot be tested by deletion — deletion reds any case that reads the output at all, while moving it reds only a case observing the decision *during* the window the property is about. |
| 6 | Change the arm enumerator's `transient(` pattern to a token present nowhere, so it reports "0 arms checked" and exits 0 | **Targets the guard's own dispatch.** The floor fires on its own emptiness. It must be written in the shape `scripts/guard-vacuity-floor.test.sh` recognises — a bracket or arithmetic test with `-lt`/`-le`/`-ge` polarity against a counter the suite itself increments, reporting with `printf >&2` + `exit 1` and **never** through the suite's `fail()`/verdict helper (a floor routed through the suspect cannot witness the suspect). ADR-193 / AP-023. |

**Harness rows.**

| # | Edit to the SUITE (not the guard) | Expected |
|---|---|---|
| H1 | Make every RED fixture a mutation of the canonical, with the canonical the only must-PASS input | MUST fail the suite's must-PASS floor — that arrangement is satisfiable by a stub. |
| H2 | Success condition `fail == 0` with zero cases executed | MUST fail `passes + fails == cases` (ADR-193 point 3). |
| H3 | A must-PASS non-canonical input: the anchor read succeeds and returns foreign-host rows | MUST PASS with the normal path untouched — without it the matrix cannot detect a guard that rejects everything. |

### Guard 2 — no acknowledgement produces a storage verdict, and no marker satisfies a control

**Property.** No verdict token asserts storage unless that run read a row back out of the warehouse;
and no row this repo writes as a probe can satisfy any positive control that gates a decision.

**Assembly.** Every `emit`/`printf` site producing a `SOLEUR_BETTERSTACK_*` token in
`scripts/betterstack-ingest-probe.sh` and `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh`,
plus the marker payload's **field set**. Derived by grepping the verdict prefix and the marker
builder, never by listing today's tokens.

**Mutation matrix.**

| # | Mutation | Must drive RED because |
|---|---|---|
| 1 | Restore `INGEST_ACCEPTING` as the 2xx token name | The name is the defect — it was printed verbatim inside #7811, an issue titled "Better Stack is accepting no writes". |
| 2 | Emit the stored verdict when the readback returns zero rows | The verdict would rest on the POST status alone. |
| 3 | Add a payload to `scripts/betterstack-ingest-probe.sh` | ADR-192: a writing probe satisfies the absence alarm's any-row control forever. The guard asserts that script posts `--data-raw '[]'` and nothing else. |
| 4 | Add a `host_name` key to the round-trip marker payload | `ANCHOR_SQL` selects `host_name != '' AND host_name != '<this host>'`, so any `host_name` makes the marker foreign-host liveness for the capture — the ADR-192 blind spot at the source that gates a host birth. **The guard asserts the field, not the source id**, because the field is the property. |
| 5 | Point the write at source `2457081` | Its marker would become a permanent positive control for `scripts/betterstack-assert-absence.sh`. |
| 6 | Collapse `ROUNDTRIP_NOT_STORED` and `ROUNDTRIP_DARK` onto one exit code | Different remedies — one is a vendor data-loss finding, one is "wait". ADR-199 commitment 3, applied to this plan's own instrument. |

**Harness rows.**

| # | Edit to the SUITE | Expected |
|---|---|---|
| H1 | Stub the readback to return a row while stubbing the POST to return 500 | MUST fail — a stored verdict needs both legs. |
| H2 | A must-PASS non-canonical input: a readback returning **two** marker rows | MUST PASS — the contract permits at-least-one. |
| H3 | In the capture suite, a fixture where `ANCHOR_SQL`'s result contains a round-trip marker row | MUST NOT read as foreign-host liveness — Guard 2 row 4 asserted from the consumer's side. |

### Guard 3 — the ingest credential's destination is genuinely pinned

**Property.** No probe forwards the bearer ingest token to a destination whose **authority** is not a
`*.betterstackdata.com` host, over any scheme but `https`, or through a redirect.

**Assembly.** Every `curl` invocation passing `Authorization: Bearer` with an ingest token —
`scripts/betterstack-ingest-probe.sh` and the round-trip follow-through. Derived by grepping the
header alongside the token variable.

**Mutation matrix.**

| # | Mutation | Must drive RED |
|---|---|---|
| 1 | Remove `--proto '=https'` | A plaintext override would put the token on the wire. |
| 2 | Add `-L` | A 30x would forward the credential off-vendor. |
| 3 | Revert the authority extraction to the bare glob `https://*.betterstackdata.com/*` | **This is a regression test, not a hypothetical.** Measured today: that pattern ACCEPTS `https://evil.com/?x=.betterstackdata.com/` and `https://attacker.example.org/a/.betterstackdata.com/x`, because a glob crosses `/` and `?`. The row exists because the bypass is live on `origin/main`. |

**Harness row.** A must-PASS non-canonical input: `https://s2457081.eu-fsn-3.betterstackdata.com/`
and `https://s2734275.eu-central-1a.betterstackdata.com/` must both still be accepted — the fix must
not break the two real endpoints.

## Implementation Phases

### Phase 0 — Preconditions (no code)

0.1 Re-run the reads in **Measured discriminators**; if Better Stack renamed either code the design
is unaffected (the control read is the discriminator) but fixtures must be transcribed from the fresh
response, never composed from what the format permits.

0.2 Confirm `bs_absence_classify` still takes no arguments and returns 0/4/2, and that
`scripts/zot-restart-loop-alarm.sh` remains its only production consumer — the composition must not
perturb it.

0.3 Re-read `ANCHOR_SQL` and confirm its foreign-host predicate is unchanged; Guard 2 row 4 and the
marker design both depend on its exact shape.

0.4 Re-run the destination-pattern table in **The live defect plan review found** against the current
file, so the Phase 2.2 fix is written against a measured bypass rather than a remembered one.

### Phase 1 — the capture's composed control read (RED first)

**This is the change that would have diagnosed run 33888071954 on the first attempt.**

1.1 Write Guard 1's matrix and harness rows into
`tests/scripts/test-git-data-rung2-evidence-capture.sh` before touching the capture, including the
run-33888071954 fixture and the reorder case (row 5).

1.2 Replace the `anchor_rc -ne 0` arm in
`scripts/followthroughs/git-data-rung2-evidence-capture.sh`. Source `scripts/lib/betterstack-absence.sh`
and call `bs_absence_classify` **with `BS_TABLE` and `BS_TABLE_S3` overridden to
`t520508_soleur_inngest_vector_prd_3_logs` / `t520508_soleur_inngest_vector_prd_3_s3`** — the shared
control source, named explicitly. The override is load-bearing: the capture `export`s `BS_TABLE` to
git-data's own table process-wide, so an un-overridden call reads the absent target and answers
`TRANSPORT_FAIL` forever. Map the three outcomes, carrying the ClickHouse error code from the
anchor's own body as the reason:

- `LIVE` → the warehouse answers for another source, so this failure is specific to the git-data
  source: it has never stored a row, **or is misaddressed**. Names both; the pair of reads does not
  separate them (AP-021).
- `INGEST_DARK` → the warehouse carries no producer rows at all; names #7811, does not blame git-data.
- `TRANSPORT_FAIL` → the instrument could not answer; names the instrument.

The external contract is unchanged — this arm still exits 2 via `transient()`. **The capture's
contract is 0/1/2 plus 64 for usage errors**; do not "tidy" the 64 path. `rc=3` in the rehearsal
workflow is minted by the workflow's own Doppler self-probe, not by the capture, and must not be
disturbed.

1.3 **Set the control window deliberately, and record two honest limits in code**, as
`scripts/betterstack-assert-absence.sh` does for its own.

The window is a separate knob from the capture's own `WINDOW="30 DAY"`: `bs_absence_classify` reads
`BS_CONTROL_WINDOW`, which defaults to `6h`. Verified: it calls the transport in **mode 2**
(`--since "$BS_CONTROL_WINDOW" --limit 1`), which queries the hot arm **and** the s3 archive arm —
which is exactly why both `BS_TABLE` and `BS_TABLE_S3` must be overridden, not just the first. Pass
the window explicitly rather than inheriting the default silently, so the value is a decision on the
record.

The two limits:

- An `INGEST_DARK` reading cannot distinguish "the warehouse refuses writes" from "every producer on
  the control source stopped at once". It still correctly declines to blame git-data, which is the
  decision the caller needs.
- If the control source is ever retired or renamed, its read fails and the arm reports
  `TRANSPORT_FAIL` — "the instrument could not answer". That is defensible (the instrument genuinely
  cannot answer) but it is not precise, and a future maintainer should know the control source is a
  named dependency of this arm rather than an interchangeable one.

1.4 Add the arm enumerator over `transient(` call sites in that one file, with its zero-arms floor
reporting via `printf >&2` + `exit 1` in the shape `scripts/guard-vacuity-floor.test.sh` derives.

1.5 Give the workflow step summary three differentiated sentences. The TRANSIENT branch already walks
the operator through this three-way distinction *manually* — automating that sentence is the
operator-facing payoff of the whole plan.

### Phase 2 — the probe's verdict contract and its destination pin

2.1 Rename the 2xx verdict token in `scripts/betterstack-ingest-probe.sh` so it cannot be read as
storage, and expand `detail=` to state what the run did **not** establish. Keep `--data-raw '[]'`
literal and the no-payload prohibition, adding a pointer to the round-trip follow-through. No
consumer string-matches the token (verified: the alarm and the zot workflow treat the probe's stdout
as prose), so the rename is safe.

2.2 **Fix the destination assertion.** Extract the authority before matching instead of globbing the
whole URL — strip the `https://` prefix, cut at the first `/` (and defensively at `?`), and match the
remainder against `*.betterstackdata.com`. Keep `--proto '=https'` and the absence of `-L`. This is a
live bypass on `origin/main`, and this plan's own User-Brand Impact was resting on the assertion
holding.

2.3 Update `tests/scripts/test-betterstack-ingest-probe.sh` for the renamed token, Guard 2 rows 1 and
3, and Guard 3 row 3 plus its harness row.

2.4 **Change no ingest-URL literal** (C11).

### Phase 3 — the round-trip follow-through

3.1 Create `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh` as **one** script (C9): POST
one uniquely-marked row to a named source, poll for it until a wall-clock deadline, emit one verdict,
and record the observed POST→queryable latency. It reuses the fixed authority check, `--proto
'=https'` and the no-`-L` rule (Guard 3).

3.2 **The marker payload carries no `host_name` key**, and the script refuses to write to any source
whose positive control its marker could satisfy. `ANCHOR_SQL` selects on `host_name != ''`, so a
marker without that key cannot become foreign-host liveness.

3.3 **Four verdicts, mapped onto the sweeper's three actions — and the mapping is measured, not
assumed.** `scripts/sweep-followthroughs.sh` dispatches on `case "$rc"`: **0** closes the issue,
**1** comments FAIL and leaves it open (reopening a closed one, capped at `REOPEN_MAX=3`), and
**every other code** — 2, 3, 4 alike — takes one identical TRANSIENT arm. So distinct exit codes do
**not** by themselves buy distinct sweeper behaviour, and a design that assumed they would was wrong.

What the sweeper *does* preserve is the script's stdout: it captures the last 4 KB and embeds it in
the issue comment. The discrimination therefore lives in the verdict token, with the exit code
carrying the action:

| Verdict (stdout, load-bearing) | Exit | Sweeper action | Why |
|---|---|---|---|
| `ROUNDTRIP_STORED` | 0 | closes, latency recorded | the measurement completed |
| `ROUNDTRIP_NOT_STORED` | 1 | FAIL comment, stays open, reopens if closed | **the H5 decider.** A confirmed accepted-not-stored is a vendor data-loss finding; exit 1 is right precisely because it must not be quietly retried away, and here "the assertion did not hold" is literally true |
| `ROUNDTRIP_DARK` | 2 | TRANSIENT, retried | nothing to measure yet |
| `ROUNDTRIP_UNKNOWN` | 3 | TRANSIENT, retried | the readback could not answer, or the deadline was below the floor |

Exits 2 and 3 render identically at the sweeper **by design of the sweeper, not by accident of this
script**; the token on stdout is what separates them for the reader, and Guard 2 row 6 asserts the
tokens never collapse. Record this asymmetry in the script header so nobody later "fixes" the
duplicate-looking codes.

Per `scripts/lint-followthrough-varq-ban.sh`, the script must **not** use `${VAR:?msg}` or
`: "${VAR:?}"` for required inputs — that form aborts with status 1, which the sweeper reads as a
FAIL and comments daily. Use `if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT: <reason>" >&2; exit 2;
fi` instead.

3.4 **Deadline and the AP-024 carve-out.** Until a latency is measured for this source, the interim
deadline is a stated multiple of ADR-172's 17 s, and a non-observation **below that floor degrades to
`ROUNDTRIP_UNKNOWN`, never `NOT_STORED`** (ADR-172 §2). A row that arrives after the deadline is
re-read once on the next run before any `NOT_STORED` is emitted, so a latency excursion is not
misattributed as data loss. AP-024 says a verification surface does not actuate; the carve-out
claimed here is that a synthetic canary written solely to be read back is not the production write
being judged — stated explicitly rather than by silence.

3.5 New suite `tests/scripts/test-betterstack-roundtrip-latency.sh` carrying Guard 2's and Guard 3's
matrices with stubbed curl, following the argv-validating stub pattern in
`tests/scripts/test-betterstack-ingest-probe.sh`.

3.6 **Register the suite** in `scripts/test-all.sh` next to its siblings, and regenerate
`plugins/soleur/test/fixture-relative-assert.baseline.txt` in the same commit — that baseline is
row-by-row equality, so a count that moves without a regenerated baseline reddens. Without
registration the new suite is an orphan and Guard 2 and Guard 3 never gate a PR.

3.7 **Wire `BETTERSTACK_LOGS_TOKEN` (and `GIT_DATA_BETTERSTACK_LOGS_TOKEN`) into
`.github/workflows/scheduled-followthrough-sweeper.yml`.** This is **required, not conditional**: the
sweeper's `env:` block carries the query credentials but no ingest token, and the sweeper's own note
records that unset secrets resolve to `""` and probes degrade to fail-safe TRANSIENT — which would
launder an instrument fault into the very state this plan exists to disambiguate. The rehearsal
workflow already carries both secrets, so the credential exists and was simply never routed here.

3.8 File the tracker with the `<!-- soleur:followthrough script=… earliest=… secrets=… -->` directive
and the `follow-through` label. The script **records the measured latency and derived poll budget in
the tracker issue**, and does not commit — the sweeper runs with `contents: read` and cannot push,
and a bot writing to `.github/workflows/` is a mechanism nobody asked for. Changing the poll constant,
if a measurement ever warrants it, is a separate human-authored PR. **No constant changes in this
PR** (C5).

3.9 **The readback predicate is grounded, not guessed — and the one residual unknown is named.**
Deepen-pass measured the real warehouse schema against the control table's archive rather than
composing it from what the format permits (Phase 0.1's rule):

| column | ClickHouse type | use |
|---|---|---|
| `dt` | `DateTime64(6, 'UTC')` | event time — the `WHERE`/`ORDER BY` key |
| `raw` | `String` | the log entry, **double-encoded** JSON (a JSON string containing a JSON document) |
| `_row_type` | `UInt8` | `= 1` selects log rows, excluding metrics/spans whose `raw` has a different shape |
| `ingest_time` | `DateTime64(6, 'UTC')` | **the warehouse's own receive timestamp** |
| `_insert_index`, `_pattern` | `UInt32`, `String` | Better Stack internals; not used |

`ingest_time` is the find that makes the measurement precise: the POST→queryable latency this
follow-through exists to establish is bounded by the probe's own wall clock, but `ingest_time - dt`
gives a **server-side** figure that does not depend on the runner's clock. Record both.

Vendor ingest contract (documented): a single JSON object **or** an array; `dt` and `message` are
reserved and both optional (`dt` defaults to reception time, and accepts UNIX s/ms/ns, RFC 3339 or
ISO 8601); every other key passes through as a custom field. Responses are **202** accepted,
**402** quota exceeded (*"refused and discarded"*), **403** bad token, **406** bad JSON.

**Readback shape — two-stage, because ADR-192 I-2 forbids resting on an unanchored `raw LIKE`.**
Stage 1 is a cheap SQL prefilter; stage 2 is the actual predicate, decoded and field-anchored:

```sql
SELECT dt, ingest_time, raw
FROM s3Cluster(primary, t520508_soleur_git_data_prd_s3)
WHERE _row_type = 1
  AND dt >= now() - INTERVAL <window>
  AND raw LIKE '%<MARKER>%'
ORDER BY dt DESC LIMIT 10 FORMAT JSONEachRow
```

then confirm by decoding twice and matching the **field**, never the bare line:
`jq -r '.raw | fromjson | select(.message | startswith("<MARKER>")) | .message'`. The marker is a
quote-free, escape-free token so the prefilter survives double-encoding. Match on **presence of at
least one row**, never on an exact count — a retry or a duplicate delivery is legitimate, which is
what Guard 2 harness row H2 asserts.

The marker payload is `{"dt": …, "message": "<MARKER> run_id=…"}` and carries **no `host_name`
key** (Guard 2 row 4).

**The one residual unknown, stated as unknown:** the column set above is measured against the
*control* table, which is a `vector`-platform source. Source `2734275` is `http`-platform and its
table does not yet exist, so its schema is *expected* to match and is **not** verified. That is an
inference, and the first live run is what converts it into a measurement — which is precisely why
that run's correct outcome may be `ROUNDTRIP_UNKNOWN` rather than a pass.

### Phase 4 — ADR amendments

4.1 Amend ADR-192 per `### ADR` above, including the permanent-table-creation consequence and the
citation of the capture's own recorded decision that this reverses.

4.2 Amend ADR-198 at its three occurrences; record the team-scoped-read-credential fact and the
Sentry-correlation alternative.

## Files to Edit

- `scripts/followthroughs/git-data-rung2-evidence-capture.sh` — composed control read (Phase 1.2–1.4)
- `.github/workflows/git-data-rung2-rehearsal.yml` — three differentiated step-summary sentences (Phase 1.5)
- `scripts/betterstack-ingest-probe.sh` — verdict rename and the authority fix (Phase 2.1–2.2)
- `tests/scripts/test-git-data-rung2-evidence-capture.sh` — Guard 1 (Phase 1.1)
- `tests/scripts/test-betterstack-ingest-probe.sh` — Guard 2 rows 1/3, Guard 3 row 3 (Phase 2.3)
- `scripts/test-all.sh` — register the new suite (Phase 3.6)
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — regenerate (Phase 3.6)
- `.github/workflows/scheduled-followthrough-sweeper.yml` — add the ingest token, unconditionally (Phase 3.7)
- `knowledge-base/engineering/architecture/decisions/ADR-192-an-empty-warehouse-read-is-three-states-not-one.md`
- `knowledge-base/engineering/architecture/decisions/ADR-198-baking-the-better-stack-ingest-token-into-git-data-user-data.md`

## Files to Create

- `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh` (Phase 3.1)
- `tests/scripts/test-betterstack-roundtrip-latency.sh` (Phase 3.5)

**Explicitly NOT edited:** `apps/web-platform/infra/cloud-init-git-data.yml` (ForceNew),
`scripts/betterstack-query.sh` (C1; 39 scripts / 29 invocation sites depend on its vocabulary),
`scripts/lib/betterstack-absence.sh` (C6; shared arity with a live consumer), and
`scripts/zot-restart-loop-alarm.sh` (untouched precisely because C6 adds no token that could reach
its no-`*)`-arm `case`).

## Conventions This Plan Must Honour

- **`set -euo pipefail` on new scripts.** The two edited scripts deliberately diverge (`set -uo
  pipefail`, no `-e`) because both classify a non-zero `curl` rather than dying on it. The new script
  takes `set -euo pipefail`, capturing every classified curl as `rc=0; out=$(...) || rc=$?`. Any pipe
  inside a command substitution whose failure is classified downstream gets `|| true` plus an explicit
  empty-sentinel check, or the labelled-FAIL branch is unreachable.
- **Operator-protection signals go to stdout.** Verdict lines and the capture's classification
  sentence print to stdout, matching the existing `emit()`. The deliberate exception is Guard 1's
  anti-vacuity floor (`printf >&2` + `exit 1`, ADR-193) — a suite-internal failure, not an operator
  signal.
- **`scripts/lint-diagnosis-claims.sh`** (the AP-021 hook, with a `.highwater`) counts causal prose.
  Phase 1's three sentences and Phase 2.1's expanded `detail=` are exactly what it measures; AC16
  asserts the highwater does not move. **`scripts/lint-followthrough-varq-ban.sh`** applies to the new
  follow-through script.

## Acceptance Criteria

### Pre-merge (PR)

1. `bash tests/scripts/test-git-data-rung2-evidence-capture.sh` passes, reports a non-zero case
   count, and `passes + fails == cases`.
2. Every Guard 1 mutation row, applied one at a time, drives that suite non-zero — six
   applied-and-reverted mutations with the observed exit code recorded.
3. Guard 1 row 4 is verified explicitly: deleting the `BS_TABLE`/`BS_TABLE_S3` override drives the
   suite red. This is the mutation that would silently restore today's behaviour.
4. The run-33888071954 fixture produces exactly one dark-warehouse sentence naming #7811, and its
   output contains no occurrence of `unreachable or unauthorised`.
5. The token from #7811 is gone from the live tree:
   `grep -rl 'INGEST_ACCEPTING' scripts/ tests/ .github/ | wc -l` returns `0`.
   **Note the form:** `grep -c 'INGEST_ACCEPTING' scripts/` — an earlier draft's shape — exits 2 with
   *"Is a directory"* and prints `0`, so a naive "returns 0" check passes *because the command
   errored*. Measured before this AC was frozen. `knowledge-base/` is excluded: ADR-192 quotes the old
   token as history.
6. `grep -c -- "--data-raw '\[\]'" scripts/betterstack-ingest-probe.sh` returns 1 and the header still
   carries its no-payload prohibition.
7. **The destination bypass is closed.** With the fixed check,
   `https://evil.com/?x=.betterstackdata.com/` and `https://attacker.example.org/a/.betterstackdata.com/x`
   are both refused, while `https://s2457081.eu-fsn-3.betterstackdata.com/` and
   `https://s2734275.eu-central-1a.betterstackdata.com/` are both accepted. Asserted in
   `tests/scripts/test-betterstack-ingest-probe.sh`, not by hand.
8. `bash tests/scripts/test-betterstack-ingest-probe.sh` passes with its case count unchanged or higher.
9. `bash tests/scripts/test-betterstack-roundtrip-latency.sh` passes; Guard 2 rows 4, 5 and 6 and all
   three Guard 3 rows each drive it red.
10. Guard 2 harness H3 passes in the capture suite: an `ANCHOR_SQL` result containing a round-trip
    marker does **not** read as foreign-host liveness.
11. The new suite is registered **in the form the orphan detector actually reads**.
    `scripts/lint-orphan-test-suites.sh` anchors on the COMMAND after `bash`, never the free-form
    `run_suite` label, so the AC asserts the command:
    `grep -cE 'run_suite .*[[:space:]]bash[[:space:]]+"?tests/scripts/test-betterstack-roundtrip-latency\.sh"?' scripts/test-all.sh`
    returns 1, and `bash scripts/lint-orphan-test-suites.sh` passes.
    `plugins/soleur/test/fixture-relative-assert.baseline.txt` is regenerated in the same commit via
    `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline`.
12. `.github/workflows/scheduled-followthrough-sweeper.yml` carries `BETTERSTACK_LOGS_TOKEN` in its
    `env:` block.
13. **Scope boundary:** the diff changes zero Better Stack ingest-URL literals.
    `git diff origin/main -- . | grep -E '^[+-].*betterstackdata\.com'` returns nothing **except** the
    test fixtures added by AC7, which are synthetic (`evil.com`, `attacker.example.org`) or the two
    real endpoints asserted as still-accepted.
14. **Scope boundary:**
    `git diff --name-only origin/main | grep -cE 'cloud-init-git-data\.yml|scripts/betterstack-query\.sh|scripts/lib/betterstack-absence\.sh|scripts/zot-restart-loop-alarm\.sh'`
    returns 0.
15. `bash tests/scripts/test-git-data-birth-readiness-gate.sh` and
    `bash tests/scripts/test-betterstack-absence-classifier.sh` both pass unchanged.
16. `scripts/lint-diagnosis-claims.sh` passes and its `.highwater` does not move.
17. The full shell suite runs green at the `/ship` Phase 4 full-battery checkpoint.
18. `python3 scripts/lint-guard-contract.py` passes against this plan.
19. ADR-192 carries the composed reading, the narrowed writing rule, the permanent-table-creation
    consequence, and cites the capture decision it reverses.
20. ADR-198 no longer claims eight of nine stages reach the queryable channel at any of its **three**
    occurrences, and records the team-scoped-credential fact and the Sentry-correlation alternative.
    The four cloud-init comments are untouched and noted as deferred.
21. `bash scripts/check-adr-ordinals.sh` passes. **No new ADR ordinal is claimed.**
22. The PR body uses `Closes #7855`; `user-impact-reviewer` has signed off; CPO sign-off is recorded.

### Post-merge (automated, not operator)

23. The follow-through tracker exists with the `follow-through` label and a `soleur:followthrough`
    directive naming `scripts/followthroughs/betterstack-roundtrip-latency-7855.sh`, and is picked up
    by the sweeper. Verified by the workflow, not a person.
24. On the first sweeper run after the warehouse resumes storing, the follow-through records a
    measured POST→queryable latency for source `2734275` and the derived poll budget **in the tracker
    issue**. Until then it exits with `ROUNDTRIP_DARK`'s code and the tracker stays open. A
    `ROUNDTRIP_NOT_STORED` exit instead confirms H5 and is a distinct, separately-rendered verdict.

## Test Scenarios

| # | Given | When | Then |
|---|---|---|---|
| T1 | Anchor read fails; control classify returns `LIVE` | The capture runs | It names **both** "never stored a row" and "misaddressed", carries the ClickHouse code, and does not name #7811 |
| T2 | Anchor read fails; control classify returns `INGEST_DARK` | The capture runs | It names #7811 and does not blame git-data |
| T3 | Anchor read fails; control classify returns `TRANSPORT_FAIL` | The capture runs | It names the instrument |
| T4 | The run-33888071954 fixture | The capture runs | One dark-warehouse sentence; `unreachable or unauthorised` appears nowhere |
| T5 | The `BS_TABLE`/`BS_TABLE_S3` override removed | The capture suite runs | Non-zero — the control would read the absent target and collapse three states into one |
| T6 | A `transient(` call site naming an unmeasured cause | The arm enumerator runs | Non-zero, naming that call site |
| T7 | An enumerator pattern matching nothing | The arm enumerator runs | Floor fires via stderr, naming the empty population |
| T8 | POST 202 and a readback returning the marker | The follow-through runs | `ROUNDTRIP_STORED`, exit 0, latency recorded |
| T9 | POST 202 and a readback returning nothing past the deadline | The follow-through runs | `ROUNDTRIP_NOT_STORED` on its **own** exit code — the H5 decider |
| T10 | POST 202, readback empty, but the deadline was below the measured floor | The follow-through runs | `ROUNDTRIP_UNKNOWN`, never `NOT_STORED` |
| T11 | A row that arrives after the deadline | The next run re-reads before emitting | `ROUNDTRIP_STORED` with the longer latency, not a false `NOT_STORED` |
| T12 | The warehouse still dark | The follow-through runs | `ROUNDTRIP_DARK` on a distinct exit code; no latency recorded |
| T13 | A `host_name` key added to the marker payload | Guard 2 runs | Non-zero — the marker would satisfy `ANCHOR_SQL` |
| T14 | An `ANCHOR_SQL` result containing a marker row | The capture suite runs | It does not read as foreign-host liveness |
| T15 | `https://evil.com/?x=.betterstackdata.com/` as `BETTERSTACK_INGEST_URL` | The probe runs | Refused before the credential is forwarded |
| T16 | `https://s2734275.eu-central-1a.betterstackdata.com/` | The probe runs | Accepted — the fix must not break the real endpoints |
| T17 | `-L` added to a probe's curl | Guard 3 runs | Non-zero |

## Domain Review

**Domains relevant:** engineering.

### Engineering

**Status:** reviewed
**Assessment:** Confined to shell instruments, their suites, one workflow step, one workflow's env
block and two ADR amendments. Plan review moved the design from an arity change on a shared library
to a composition in one caller, which removed the blast radius, and surfaced a live credential
destination bypass now fixed in scope. Three risks remain and are guarded: a marker polluting the
capture's own positive control (Guard 2 rows 4/5 plus the consumer-side fixture), the classify call
inheriting the capture's `BS_TABLE` (Guard 1 row 4), and the two round-trip failure states collapsing
onto one exit code (Guard 2 row 6).

### Product/UX Gate

Not applicable. No path in Files to Edit or Files to Create matches the UI-surface term list or glob
superset. Product assessed NONE and the mechanical override did not fire.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The marker satisfies the capture's own `ANCHOR_SQL` control | No `host_name` key; Guard 2 row 4 asserts the **field**, and H3 asserts it from the consumer's side. This was a real defect in an earlier draft. |
| The classify call inherits the capture's `BS_TABLE` and always answers `TRANSPORT_FAIL` | Explicit override to the named control tables; Guard 1 row 4. |
| `INGEST_DARK` cannot distinguish a refusing warehouse from every control producer stopping at once | Recorded as an honest limit in code and in the sentence, mirroring `betterstack-assert-absence.sh`. It still correctly declines to blame git-data. |
| The first successful round-trip write permanently creates the table, erasing `CLUSTER_DOESNT_EXIST` for `2734275` | Recorded in the ADR-192 amendment as a designed consequence, not discovered later. The instrument consumes its own discriminator exactly once. |
| The readback predicate is authored blind against a source that never stored a row | Phase 3.9; the first live run is expected to be a measurement, and `ROUNDTRIP_UNKNOWN` is the correct outcome until the shape is confirmed. |
| A latency excursion is misread as vendor data loss | Below-floor degrades to `ROUNDTRIP_UNKNOWN`; a late row is re-read once before any `NOT_STORED` (T10, T11). |
| The new suite is an orphan and its guards never gate | Registered in `scripts/test-all.sh` with the baseline regenerated; AC11. |
| The sweeper cannot POST and the fault is laundered as TRANSIENT | Ingest token wired unconditionally; AC12. |
| Renaming the probe's token breaks a consumer | No consumer string-matches it (verified); AC8 keeps the case count from silently dropping. |
| Scope creep into #7811 | No root cause adopted, zero ingest-URL literals changed (AC13), the live alarm's endpoint untouched (C11). |

## Alternative Approaches Considered

Rows duplicating the Cut List are not repeated here; see `### Cut List` for C1–C11.

| Approach | Verdict |
|---|---|
| Implement readback in the boot emitter | Rejected — the ClickHouse query connection is **team-scoped** (it reads every source in team 520508), so baking it puts a whole-warehouse read credential on the git-data host, failing ADR-198's capability-ceiling leg. `runcmd` is once-per-instance with reboot barred by ADR-115, so a boot readback gets no retry and would extend boot; and the edit is ForceNew. |
| Correlate the emitter's existing Sentry `stage:betterstack_ingest` POST outcome against a CI readback | **Not taken, but recorded** — it is an H5 decider at zero credential cost with no write, and it is weaker only in cadence (it fires when a rehearsal runs). Named in the ADR-198 amendment so the rejection of on-host readback shows the property was pursued to its cheapest shape. |
| Classify table-absence by matching the ClickHouse error string | Rejected — two arms return two different codes, and the capture's own comment already rejected this: *"a string match on a vendor 500 is exactly the kind of guard that rots silently."* The control read answers that objection. |
| Fix #7811 in this PR | Rejected — different issue, different blast radius, root cause not determinable under available credentials. |

## Deferred / Out of Scope

- The `eu-fsn-3` literals (12 lines across 6 files, plus 6 further files and a legal corpus surface)
  and the probe's own default. Reported to #7811; several are `user_data`.
- The four "eight of nine" comments in `apps/web-platform/infra/cloud-init-git-data.yml` — a comment
  edit there costs a host replace.
- The root cause of the team-wide write outage (#7811).
- Closing #7204, whose fix landed but whose tracker is open.
- The dead `BS_CONTROL_ANCHOR=any-row` seam at both `bs_absence_classify` call sites — the library no
  longer reads it. Belongs to whoever next edits that file (C6 keeps this plan out of it).
- Routing the other 38 `betterstack-query.sh` callers through the chokepoint (C7).

## Sharp Edges

- **`bs_absence_classify` takes no arguments.** Anything reading like "add a state for the target
  read" is an arity change to a shared library whose only consumer fails open on an unknown token.
  Compose in the caller.
- **Do not let the classify call inherit `BS_TABLE`.** The capture `export`s it to git-data's own
  table, so an un-overridden control read reads the absent target and answers `TRANSPORT_FAIL`
  forever — three states silently collapsed into one, suite otherwise green.
- **Source `2734275` IS a positive control.** `ANCHOR_SQL` treats any row with a foreign `host_name`
  as proof the source is live. Any row this repo writes there must be invisible to that predicate. An
  earlier draft asserted the opposite and would have shipped the ADR-192 blind spot into the birth
  gate.
- **The probe's destination glob does not pin the host.** `https://*.betterstackdata.com/*` accepts
  `https://evil.com/?x=.betterstackdata.com/`, because a glob crosses `/` and `?`. Match the extracted
  authority, never the whole URL.
- **The poll bound is `deadline=$(( SECONDS + 16 * 60 ))` — 16 minutes.** The step's comment describes
  a ~50-minute unbounded worst case the deadline exists to cut; quoting the comment instead of the
  literal is how an earlier draft got the ratio wrong by 3×.
- **The empty batch in `scripts/betterstack-ingest-probe.sh` is load-bearing.** Its header says so and
  ADR-192 decides so.
- **A `doppler run …` discoverability command is skipped, not executed**, by `deepen-plan` Check 10
  whenever `credentials_required` is declared. Point it at a `bash` suite if the intent is for the
  gate to actually run it.
