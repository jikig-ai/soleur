---
title: "feat: Codify Supabase retained-log querying on the replacement endpoint, and guard Management API call sites"
date: 2026-08-26
slug: feat-supabase-analytics-logs-endpoint-migration
branch: feat-one-shot-supabase-analytics-logs-endpoint-migration
type: enhancement
lane: cross-domain
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Enhancement Summary

**Deepened:** 2026-08-26 · **Review panel:** 7 agents (DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow-analyzer, CPO, CTO-devex) + CLO and CTO domain
assessments · **Halt gates:** 4.5 skip, 4.6 pass, 4.7 pass, 4.8 pass, 4.9 skip, 4.10 pass,
4.11 pass (`lint-guard-contract.py` → `2 guard entries`), 4.55 skip.

### The five findings that changed the design

1. **The original guard was vacuous.** A `logs.all` string denylist quantifies over the
   empty set once the single prose reference is handled — and `advisors/security`, a
   *different* deprecated path, has live callers. Replaced with a Management-API call-site
   assembly whose host-pin arm has permanent unwaived coverage.
2. **The guard's assembly could not enforce its own PAT-exfil property.** A caller whose
   host has been redirected does not contain the pinned literal, so a literal-keyed assembly
   never enumerates it. The host-pin arm now **inverts the quantifier** (assembly = things
   that carry a PAT or a `/v1/projects/` path; membership = contains the literal).
3. **The plan would have committed production log rows to a public repo.** Fixtures captured
   from a live GDPR exposure window, into `tests/scripts/fixtures/**`, which no existing
   gate covers. Now: capture the envelope, synthesize every row body.
4. **Discoverability was justified backwards.** The MCP cut rested on "the runbook solves
   it" — but the precedent script is found because it is pasted into six agent-facing
   bodies, and its closest sibling (with a runbook, no skill-body mention) is cited in zero.
   Phase 4 now edits the skill bodies, and promotes GATE G-ESCALATE out of a June plan
   blockquote into a runbook with `triggers:` frontmatter (activating a routing surface that
   is inert repo-wide today).
5. **The journey had no terminus.** Cutting window-chunking removed the *remedy* and kept
   only the *detector*, leaving an agent's rational recovery as hand-written curl — the
   exact behaviour the plan exists to retire. The helper now auto-narrows and unions
   per-slice coverage, and the verdict is bound to the **exit code** (3), not only stdout.

### Also corrected in this pass

- The guard is **advisory, not blocking** (`lint-bot-statuses` is absent from
  `required-checks.txt`); every merge-gating claim was removed and promotion filed as a
  tracked issue with its four coupled steps, including the #6049 auto-fabrication trap.
- A sixth failure mode found: a **format-valid but wrong project ref** passes all five other
  checks and prints `COVERED` over another project's data.
- The instrumentation check was **circular** (a "full retained span" query is itself the
  wide window that returns zero); span pinned to a measured 30 days.
- Hand-typed census numbers removed entirely in favour of a `.highwater` ratchet — three
  independent counts disagreed because each used a different pathspec and unit.
- Deprecated-path extraction must be **file-scoped**: the live `advisors/security` call sits
  131 lines below its host literal, so a line-scoped guard finds zero and reports green.
- Mechanical AC repairs: `grep -c` exits 1 on zero matches (kills the step under `set -e`);
  `--numstat` + merge-base + a non-vacuity floor for the append-only check; `--jq .state`;
  `grep -cF` for dotted needles.
- `lint-orphan-test-suites.sh` is **blind to `tests/scripts/`** — registration is now
  asserted directly rather than through a proxy that cannot fail.
- Attribution fix: **#6288 is the issue the Better Stack short-answer bug kept open**, not
  the finding — inherited from a review agent and propagated unverified until this pass.

### Verified live in this pass

ADR-197 free across all 60 `origin/*` refs · commit `924994b2f` on `origin/main` with the
quoted subject · #5697 `OPEN` · #6049 title matches the auto-fabrication citation · all six
cited AGENTS.md rule IDs active · all nine other cited ADRs exist · no PAT-shaped variables ·
scheduled-work precedent (53 Inngest crons vs 13 GH Actions).

## Overview

Supabase removes the Management API endpoint `analytics/endpoints/logs.all` on 2026-09-23,
directing callers to `analytics/endpoints/logs`. No committed caller exists: the traffic
Supabase observed came from an agent issuing the request ad hoc during a retained-log
investigation, reading the request shape out of a knowledge-base evidence document. The
capability lives only as prose, so the next investigation reconstructs a dead endpoint.

Live measurement on 2026-08-26 changed the work twice.

**The replacement is not a rename.** Same parameters, same response envelope — so a path
swap runs and returns HTTP 200 while being wrong. The data model, SQL dialect and timestamp
encoding all changed, and the endpoint reports *every* failure as HTTP 200. Six ways to get
a confident, green, empty-or-wrong answer are catalogued below.

**And the deprecation with live callers is a different one.** The same spec marks
`/advisors/security` deprecated; that path has two live in-repo call sites, where `logs.all`
has none.

Deliverable, in dependency order: a committed, tested, read-only helper on the replacement
endpoint whose output **cannot be a bare zero**; the skill-body wiring that makes an
incident agent actually find it; append-only addenda so the next agent copies working SQL;
and a Management-API call-site guard whose host-pin arm has permanent, unwaived coverage.

**This plan ships as three PRs.** The legal-corpus fix depends on nothing and must not queue
behind a shell-script CI cycle; the poller depends on nothing and has no deadline. See
§Delivery Split.

## Delivery Split

| PR | Contents | Deadline | Blocks on |
|---|---|---|---|
| **PR-A** (legal lane, ships first) | Art. 30 register transcription + cross-reference, `compliance-posture.md` Active Items row, `compliance/critical` issue | none — but it is live now | CLO + `legal-compliance-auditor` only |
| **PR-B** (deadline) | Helper + fixtures + suite + registration, skill-body wiring, three append-only addenda, runbook, ADR-197, the assembly guard | **2026-09-23** | CI |
| **PR-C** (follow-up) | Deprecation spec-diff folded into the existing Supabase workflow | none | — |

Rationale: the register defect is Critical and **independent** — bundling it makes the
independent thing wait on the dependent thing, and puts a statutory register in front of
engineering-shaped reviewers. The addenda stay in PR-B because they cite the runbook PR-B
creates.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (measured 2026-08-26) | Response |
|---|---|---|
| "migrate to `analytics/endpoints/logs`" | Both live; `logs.all` is `"deprecated": true`. Parameters **identical**; same `AnalyticsResponse`. | The drop-in-rename reading is the trap. |
| "the parameter set may differ" | It does **not**. The **data model, SQL dialect, timestamp encoding** differ. | Risk pivots from parameters to query semantics. |
| Two KB documents contain `logs.all` | **One** does (`gate-g-escalate-evidence.md:35`). A **third** document (the post-mortem) carries the stale retention figure. | Three documents in scope; one endpoint reference. |
| "retention ~1–2 days" | Aggregate ~60d. **Per-source it is not**: `edge_logs` = **0 rows over 30 days**; `auth_logs` = 21. | §Retention — resolves the legal question. Never correct the audit's `edge_logs` claim from an aggregate figure. |
| "the `SUPABASE_ACCESS_TOKEN` PAT" | Both names exist in `soleur/prd`, split cleanly: `SUPABASE_PAT` only under `apps/web-platform/scripts/`. | Use `SUPABASE_ACCESS_TOKEN`. Unification out of scope. |
| Host pin "asserted by tests" | True, but four **per-script copies**. A new caller inherits no guard. | Assembly arm added **above** them; the four remain. |
| "no committed caller" | Confirmed for `logs.all`. `/advisors/security` has **2** direct call sites. | §Second-Caller Sweep. |

## Replacement Contract (measured)

Verified against prd ref `pigsfuxruiopinouvjwy`.

**Identical:** `ref` (length 20, `^[a-z]+$`), `sql`, `iso_timestamp_start`,
`iso_timestamp_end`; `AnalyticsResponse` = `{ result: array|null, error: string|object|null }`.

**Changed:** per-source tables (`from postgres_logs`) → one unified stream with a `source`
**column**; BigQuery → **ClickHouse** dialect; `timestamp` integer-microseconds
(`1787750328736000`) → ISO string (`"2026-08-26T13:18:30.551000"`), which silently breaks
`jq` arithmetic and `date -d @…`.

**Six ways to get a false answer — all HTTP 200:**

| # | Input | Response | Why dangerous |
|---|---|---|---|
| A | Old-dialect query on the new endpoint | `result: null`, `error: "Backend error!…"` | Checking status + `result \| length` reads **0 rows**. |
| B | `source = 'totally_not_a_source'` | `error: null`, `[{"c":0}]` | A typo'd/renamed source is indistinguishable from a real zero. |
| C | Over-wide window | `error: null`, **silently truncated** | 24h → 5,158 rows; **61d → 199,361**; **70d → 2,676**; 80d+ → **0**. A *wider* window returning *fewer* rows is impossible for a correct range query. |
| D | `group by source` over 55 days | **HTTP 500**, `error: null`, `result: null` | A 5xx with a null error field; naive `.result \| length` → 0. |
| E | Uninstrumented source | `error: null`, `0` | `edge_logs` returns 0 across 30 days — "never emitted", not "no traffic". |
| F | **Format-valid but wrong `--ref`** | `error: null`, real rows, full coverage | **Every safety mechanism passes.** The verdict prints `COVERED` over another project's data. The most likely 2am error, and the one nothing else here catches. |

The documented guard ("range must be ≤24 hours or a validation error is thrown") is **not
enforced** — a 25-hour range returned 200 with data. The empirical cap sits between 61 and
70 days, is undocumented, and can move.

## Retention — and why it does not reopen the GDPR determination

The determination and its Gate-G record state retention was "~1–2 days", making the
2026-06-17 → ~06-27 exposure window uncoverable. Aggregate retention is now ~60 days, which
appeared to reopen it. **Per-source measurement closes it again:**

| Source | Last 30d | 2026-06-26 → 06-28 tail |
|---|---|---|
| `supavisor_logs` | 13,893 | 175,806 |
| `postgres_logs` | 1,482 | 1,723 |
| `auth_logs` | 21 | 0 |
| **`edge_logs`** | **0** | **0** |

The determination's evidentiary claim rests on `edge_logs` and `auth_logs`. `edge_logs` has
produced **zero rows across the entire 30-day live period** — so its zero on the recovered
tail is finding **E**, not evidence of no traffic. The recovered window adds **nothing**.

**Conclusion: the determination's `INCONCLUSIVE` treatment is correct and is *reinforced*.**
No re-opening. Both records get a narrow factual note that explicitly does **not** claim the
change certifies anything.

*(The tail capture was taken at plan time because it expires continuously; per-source
evidence is what settled this. Its **shape** lands as a fixture — see Phase 3.1 for why the
contents must not.)*

## Research Insights

### Premise Validation (Phase 0.6)

No `#N` cited. All five cited artifacts exist. The `git grep` claims hold: `logs.all` and
`analytics/endpoints` each return **one** hit. Two premises failed: "two documents"
(one does; a third carries the retention figure) and "~1–2 day retention".

**Mechanism vs. ADR corpus:** no ADR governs Management API querying or evidence-gathering
for breach determinations. ADR-031 (Sentry-as-IaC) and ADR-096 / ADR-172 (Better Stack)
cover the *other* observability planes. Genuine gap.

**A premise I asserted from an agent's numbers without measuring, and which was wrong.** An
earlier draft stated the assembly was "23 call sites across 12 files". Three independent
counts disagreed (12/23, 19/28, 16/18) because each used a different pathspec and a
different unit. **No hand-typed census survives in this plan** — see Phase 2.1.

### Property List (Phase 0.6b)

1. An investigation needing retained Supabase log evidence can obtain it after 2026-09-23.
2. A zero-row result cannot be read as "no events occurred" unless the window was covered,
   the source is instrumented, **and the project queried is the intended one**.
3. A query that failed cannot be reported as a query that found nothing.
4. A deprecated Management API path cannot enter the repository unnoticed.
5. The PAT cannot be redirected to an attacker-controlled host — including from a new caller.
6. **An agent mid-incident finds the capability without recalling it exists.**

### Cut List (Phase 0.6b)

| Mechanism | Property | What already covers it | Disposition |
|---|---|---|---|
| `logs.all` string denylist | P4 | Vacuous once the one prose hit is handled; also the bare-token-over-prose shape `cq-assert-anchor-not-bare-token` forbids. | **Cut** |
| A fifth per-script host-pin copy | P5 | Four snapshots exist. They cannot see a *new* caller — but they **remain**, since they assert per-invocation argv. | **Cut as a copy**; assembly arm added above them (net **+1**, not −4) |
| ≤24h window chunking | P2 | The cap is unenforced and 61d works. Twelve calls for an assumption measurement contradicts. | **Cut** |
| A hardcoded valid-source list | P2 | Rots. The API answers `group by source`. | **Cut** |
| A retry wrapper on `error` | P3 | Retry masks finding A. | **Cut** |
| An MCP tool | P6 | `2026-05-06-supabase-management-api-bypasses-mcp-oauth.md` records this path failing, with REST + `SUPABASE_ACCESS_TOKEN` as the solution. | **Cut** — but see P6 below; the runbook alone does **not** replace it |
| A separate `.denylist` file | P4 | Three strings do not need a config format + parser. Both cited lint precedents inline their patterns. | **Cut** — inline the array |
| `advisors/performance` denylist entry | P4 | **Zero** non-doc callers; only two SQL comments. Vacuous, exactly like the entry above. | **Cut** |
| A new scheduled workflow (spec-diff) | P4 over time | `scheduled-supabase-advisor-scan.yml` already holds the token, calls this host, and carries dedupe. **And `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` DENIES a new `schedule:` workflow (ADR-033)** — as specced it could not be written. | **Cut the workflow**; fold one step into the existing one (PR-C) |
| A C4 `supabaseMgmtApi` element | none of P1–P6 | A real gap, but predating this plan; `wg-architecture-decision-is-a-plan-deliverable` is satisfied by the ADR. | **Deferred**, tracked |

### The discoverability correction (P6) — the cut that was nearly wrong

The MCP cut was justified as *"discoverability is solved by the runbook, per the
`betterstack-query.sh` precedent."* That reads the precedent backwards, and measurement says so:

- `betterstack-query.sh` is named in **six agent-facing bodies** —
  `plugins/soleur/skills/{incident,reproduce-bug,one-shot,postmerge}/SKILL.md`,
  `plugins/soleur/commands/go.md`,
  `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`.
- Its closest functional sibling `scripts/supabase-advisor-scan.sh` is named in **zero**.

Agents find the first because its invocation is injected into their working context, not
because a runbook exists. The MCP cut stands **only if** the invocation is wired into the
skill bodies. That wiring is Phase 4 and costs four lines.

### Applicable institutional learnings

| Learning | Constraint |
|---|---|
| `2026-05-06-supabase-management-api-bypasses-mcp-oauth.md` | MCP is a known-failed path here. Disqualifies the MCP alternative. |
| `integration-issues/2026-06-16-external-api-shape-ac-must-land-captured-fixture-not-probed-claim.md` | Requires the captured **shape** as a fixture — **not** the captured contents (see Phase 3.1). |
| `2026-08-20-the-check-failed-because-the-thing-it-checked-for-was-there.md` | `grep -q` mid-pipe under `pipefail` takes SIGPIPE and inverts. Use `grep -c` / captured output. |
| `2026-07-06-ac-self-reference-grep-trap-and-verify-config-enabled-state.md` | Absence-greps false-fail on the plan's own artifacts — a reason the string denylist was cut. |
| `cq-test-fixtures-synthesized-only` | **Blocking.** See Phase 3.1. |
| `cq-assert-anchor-not-bare-token` | Killed the string denylist; the replacement must not inherit it (Phase 2.1). |
| `best-practices/2026-07-09-gc-retention-timing-vs-keepset-capacity…md` | Empty telemetry is not absence until instrumentation **and** retention are verified. |
| `2026-06-18-inngest-secrets-env-not-argv…md` | PAT reaches curl via an env-read header; `scrub_pat()` guards print sites. |
| `2026-05-22-dpa-template-pre-draft-and-cross-document-disclosure-drift.md` | Evidence-record edits need multi-agent review and sibling reconciliation in the same edit. |

### Repository conventions (verified)

- **Precedent to mirror:** `scripts/betterstack-query.sh` + `runbooks/betterstack-log-query.md`
  — read-only, ClickHouse-SQL, incident-time, with an explicit unset-creds message
  (*"You are NOT missing Better Stack access… Do NOT conclude 'no access / can't verify'"*)
  and the literal `doppler run` re-invocation. **Its header already documents finding C
  under a different vendor** (`scripts/betterstack-query.sh`, the "ARCHIVE table" note):
  `remote()` is the hot window only — ~40 minutes on 2026-07-15 — so a hot-only query
  silently answers `--since 24h` with 40 minutes of rows, *"not an error, just a short
  answer… the short answer is the bug."*
  **Attribution, verified against that header:** #6288 is the issue the bug **kept open**
  (its soak gate was reading short answers), not the finding itself — #6288's own title is
  a zot restart-loop. Cite it as the victim, not the discovery. *(This plan originally
  carried the wrong framing, inherited from a review agent and propagated unverified; it is
  recorded here because "PR/issue #N introduced X" is wrong far more often than #N's
  existence is.)*
- **House pattern** (`postgrest-reload-schema.sh`): pinned host literal, no env override;
  `scrub_pat()` matching `sbp_[A-Za-z0-9]{20,}`; exit `0`/`1`/`2`.
  (`betterstack-query.sh` uses exit **3** for missing creds — the divergence is noted in
  `--help` rather than refactored.)
- **Test registration:** `--print-suite-globs` returns nine globs; `scripts/*.test.sh` is
  **not** among them, but `scripts/lib/*.test.sh` **is**. Root-`scripts/` helpers register
  via an explicit `run_suite` line (`test-all.sh:1363`).
  `scripts/lint-orphan-test-suites.sh` (ci.yml:178) fails loudly if missed.
- **Ratchet precedent:** `scripts/{alarm-issue-filing-guard,lint-diagnosis-claims,lint-trap-tempfile-ownership}.highwater`
  + a `--check-highwater` mode — a committed, ratchets-down-only baseline.
- **Guard floor:** `lint-guard-contract.py:73` sets `MIN_MUTATION_ROWS = 3`.

## Open Code-Review Overlap

64 open `code-review` issues queried. Two weak prefix matches, neither on a touched file:
**#3364** (postgres-role guard for `run-migrations.sh` — reinforces keeping the env-var
unification out of scope) and **#3595** (YAML-aware parser for bot-workflow lint parity).
Both **Acknowledge**, not folded in. #3595 is a live caveat: the guard scans workflow YAML
for host literals, so it anchors on **file content**, not YAML structure, sidestepping the
parser gap.

## User-Brand Impact

**If this lands broken, the user experiences:** an incident- or DSAR-time agent runs the
helper, receives `0 rows` with no error (or real rows from the wrong project), and the
founder files a breach determination stating the access-log dimension is clean when it was
never successfully queried. The artifact is a **GDPR determination asserting a false
all-clear**, cross-referenced from the Art. 30 register.

**Second limb — the company's own posture.** An inaccurate Art. 33 notification to a
supervisory authority is founder-level regulatory exposure, not only user-level. The label
below routes to the strictest review path either way, but this limb changes *who* is harmed
if it ships wrong.

**If this leaks, the user's data is exposed via:** the helper carries an account-scoped PAT
and returns production log rows the determination records as capable of embedding personal
data (event payloads, step I/O, tenant identifiers, `event_user`, `worker_ip`). Three
vectors: a redirected host exfiltrating the PAT; rows landing in a CI log or transcript;
and **rows committed as test fixtures into a public repository** (Phase 3.1).

**Brand-survival threshold:** `single-user incident`. `requires_cpo_signoff: true`;
`user-impact-reviewer` runs at review time.

## Implementation Phases

### Phase 0 — Preconditions

0.1 Re-probe both endpoints; confirm the contract differences and all six failure modes.
0.2 Confirm `SUPABASE_ACCESS_TOKEN` resolves from `soleur/prd`.
0.3 Confirm `--print-suite-globs` still excludes `scripts/*.test.sh`.
0.4 Re-derive the next free ADR ordinal across **all** `origin/*` refs (ADR-197 provisional).
0.5 `gh issue view 5697` before asserting its status.

### Phase 1 — Mutation matrix before guards

Author §Guard Contract's rows as executable fixtures **first**, so each guard is proven
drivable-RED before it is written.

### Phase 2 — The assembly guard: `scripts/lint-supabase-deprecated-endpoints.sh`

**The two arms need two different assemblies. This is the plan's most important correction.**

2.1 **Deprecation arm — assembly keyed on the host literal, extraction FILE-scoped.**
    Enumerate tracked non-doc files containing the host literal, then resolve `$API` /
    `${REF}` / `$PROJECT_REF` **within the file** before matching paths.
    **A line-scoped implementation is fail-open and would ship green.** The single live
    `advisors/security` call in `.github/workflows/apply-inngest-rls.yml:238` sits **131
    lines below** its `API="https://api.supabase.com"` at `:107`; the same split holds in
    `apply-inngest-rls-dev.yml` (`:113` vs `:134,157,171`), `anon-probe.sh` (`:30` vs
    `:55,66`) and `supabase-advisor-scan.sh` (`:58` vs `:122,137,159`). Line-scoped, the
    guard finds **zero** deprecated paths, the ratchet reports green, and AC10's
    non-vacuity proof silently inverts — the exact class closed five commits ago by
    `924994b2f fix(gates): close four fail-open gates that reported success while doing
    nothing`.
    Exclude comment lines and non-call occurrences: a large share of host-literal matches
    are comments, an egress-allowlist hostname (no scheme), and *assertion strings* —
    `scan-workflow.test.sh:260,263` asserts on the literal, and
    `cron-supabase-advisor-scan.test.ts:94-95` asserts its **absence** while containing
    `advisors/security`, so a naive guard reddens on the guard-of-the-guard. Counting those
    is `cq-assert-anchor-not-bare-token` — the defect that killed the string denylist,
    re-inherited at scale. Exemptions are dated, inline-justified, and under the same
    anti-vacuity discipline as the rest.

2.2 **Host-pin arm — INVERT the quantifier. An assembly keyed on the pinned literal cannot
    see the redirect it exists to catch.** A caller whose host has been redirected does not
    contain `https://api.supabase.com`, so it is never enumerated and the guard exits 0 on
    it. Under a literal-keyed assembly, `API="${SUPABASE_API_HOST:-https://api.supabase.com}"`
    reddens while `API="${SUPABASE_API_HOST:-https://evil.example.com}"` — the actual exfil
    shape — passes silently. Property 5 would be unenforceable by construction.
    Therefore: **assembly = tracked non-doc files matching
    `/v1/projects/|SUPABASE_ACCESS_TOKEN|SUPABASE_PAT`**, and **membership is the
    assertion** — every member either contains the bare literal `https://api.supabase.com`
    or sits on a short, dated, inline-justified non-caller allowlist. A redirected host is
    then a *missing member*, which the guard can see. Eight tracked non-doc files carry a
    PAT variable or a `/v1/projects/` path with **no** host literal today (e.g.
    `apps/web-platform/scripts/run-migrations.sh`,
    `.github/workflows/scheduled-supabase-advisor-scan.yml`,
    `apps/web-platform/infra/inngest-rls/apply-inngest-rls-dev-workflow.test.sh:169-170`);
    each is triaged into the allowlist with a reason at implementation time.

2.2b **State the pathspec verbatim in the script header, and derive N from it.** Whether
    `*.test.sh` is in or out changes the answer: `tests/scripts/test-supabase-advisor-scan.sh:321`
    is a **third** `advisors/security` occurrence, so "RED on two call sites" is only true
    under a pathspec that excludes it — but excluding `*.test.sh` also drops
    `scan-workflow.test.sh` and `postgrest-reload-schema.test.sh`, the very snapshots this
    layer sits above. Decide explicitly, record the `git grep` invocation (pathspec magic
    included) in the header, and let AC10 assert `RED on exactly N` with N read from it.
2.3 **Denylist, inlined as a commented array** (no separate file): `analytics/endpoints/logs.all`
    (removal 2026-09-23, **no waiver**) and `advisors/security` (deprecated, no announced
    removal, **waived**). `advisors/performance` is **not** listed — zero non-doc callers.
2.4 **Host-pin arm — assert the host span only.** The substring from the scheme through the
    authority must be the literal `https://api.supabase.com`, with **no expansion before the
    first `/v1`**. The existing per-script guards assert their whole `API=` line is
    expansion-free, which is right for a bare shell assignment and **wrong as an assembly
    rule**: path interpolation is legitimate and near-universal. A whole-line check is RED on
    ~8 correctly-pinned files, including the one TypeScript member
    (`apps/web-platform/lib/supabase/service.ts:66`, a template literal whose *path*
    interpolates `${projectRef}`).
2.5 **Anti-vacuity by ratchet, not by magic number.** The guard prints its own enumeration
    count and compares against a committed `scripts/lint-supabase-deprecated-endpoints.highwater`
    with a `--check-highwater` mode, mirroring the three existing ratchets. Ratchets down
    only; the file carries the same *"do not raise this to make a build pass"* header. This
    replaces the earlier `≥12 files / ≥20 call sites` floor, which had three slots of silent
    slack on a PAT-exfil guard and was stated in a different unit than the guard counts.
2.6 `grep -c` semantics throughout — never `grep -q` mid-pipe.
2.7 **Wiring — and it is ADVISORY, stated plainly.** The step lands in the `lint-bot-statuses`
    job, which `.github/workflows/ci.yml:120-121` records as *"ADVISORY — absent from
    `scripts/required-checks.txt` and the ruleset, so a PR can merge with it red."*
    **This plan makes no merge-gating claim.** Promotion is deliberately deferred, not
    forgotten, because `scripts/required-checks.txt` carries an ⚠ AUTO-FABRICATION GUARD
    (#6049): adding a **content-scoped** gate name there makes the bot-PR composite action
    post a fabricated green for it. Promotion therefore requires reproducing the gate in the
    composite action's preflight **and** adding the job to required-checks.txt **and** the
    ruleset **and** re-deriving the ADR-139 `ALLOWED_PATHS ∩ SCAN_DIRS` test — real work,
    filed as a tracked issue with those four steps enumerated. Landing a fifth gate that
    *claims* to block, three commits after `924994b2f fix(gates): close four fail-open gates
    that reported success while doing nothing`, is the failure this paragraph exists to
    prevent.

### Phase 3 — `scripts/supabase-logs-query.sh` + fixtures

3.1 **Fixtures — nine, not six.** Guard 2's assembly quantifies over the fixture directory,
    so **an absent fixture is an uncovered path by construction**. The first six (success,
    dialect-error 200, typo-source zero, wide-window truncation, HTTP 500, per-source tail)
    leave three of the plan's own Test Scenarios with nothing behind them — which would make
    AC6's "coverage ⊂ window" clause **quantify over the empty set**, the same vacuity this
    plan rejected in the string denylist. Add: **zero-rows-with-full-coverage** (→ COVERED),
    **zero-rows-with-partial-coverage** (→ INCONCLUSIVE naming the gap), and
    **window-predates-retention** — the motivating 12-day case, where both monotonicity
    samples return 0 and the probe cannot fire.

    **Capture the envelope, synthesize every row body.** Under
    `tests/scripts/fixtures/supabase-logs/`. **This repository is public
    (`jikig-ai/soleur`, `isPrivate: false`)**, and the captured rows are production log
    lines from the exposure window of an active GDPR determination — the determination's own
    words: event payloads, step I/O, tenant identifiers, `event_user`, `worker_ip`.
    Committing them is a disclosure, git makes it permanent, and **no gate catches it**: the
    `cq-test-fixtures-synthesized-only` enforcement regex at
    `.github/workflows/secret-scan.yml:294` covers
    `apps/web-platform/test/(fixtures|__synthesized__|__goldens__)/`, `**/__goldens__/`,
    `*.snap` and `learnings/*.md` — `tests/scripts/fixtures/**` is **out of scope**.
    "PAT-free by construction" is not the relevant test. The captured-fixture learning
    requires the **shape**; keep the envelope and field names, replace every value.
3.2 **Contract**: `--ref`, `--source` (repeatable), `--since`, `--until`, `--limit`,
    `--json`, `--help`. `--since` / `--until` / `--limit` match `betterstack-query.sh`
    deliberately.
3.3 **Host pin** `API="https://api.supabase.com"` — bare literal, no env override. Becomes a
    member of the Phase 2 assembly.
3.4 **Auth** from `SUPABASE_ACCESS_TOKEN` via an env-read header, never argv-visible;
    `scrub_pat()` at every print site. **On unset creds, mirror `betterstack-query.sh`'s
    message**: state that access is not missing, name the exact
    `doppler run -p soleur -c prd -- scripts/supabase-logs-query.sh …` re-invocation, and say
    explicitly *do not conclude "no access / can't verify"*. The misdiagnosis this prevents
    collides directly with `hr-no-dashboard-eyeball-pull-data-yourself`.
3.5 **Project identity (finding F).** Default `--ref` to the pinned prd literal so it becomes
    a guard-covered constant like the host; validate `^[a-z0-9]{20}$`; and **echo the resolved
    ref and project name on every output path**, success and failure. A format-valid wrong
    ref otherwise passes all five other checks and prints `COVERED` over another project.
3.6 **Instrumentation + source enumeration — one call, pinned span.** Query
    `group by source` over a **pinned `INSTRUMENTATION_SPAN_DAYS=30`** window; that single
    response both (a) validates `--source` against the observed set, killing finding B, and
    (b) supplies the full-span counts that distinguish uninstrumented from empty, killing
    finding E. **The span must be pinned and cited**: an unbounded "full retained span"
    query is exactly the wide window that returns 0 for every source (finding C), so the
    naive version marks everything `UNINSTRUMENTED` and trains agents to ignore it. 30 days
    is chosen from the §Retention table and stated as a constant with that evidence inline.
3.7 **Monotonicity self-check, then AUTO-NARROW — detection without a remedy is a dead end.**
    When the requested window exceeds **7 days**, also issue a deliberately narrower
    sub-window. If the wider returns fewer rows, truncation is detected — and the helper
    **must not stop there**. Cutting ≤24h chunking removed the *remedy* and kept only the
    *detector*; a helper that exits non-zero saying "the cap has moved" leaves an agent two
    rational recoveries: abandon the question, or **hand-write curl against the endpoint —
    reconstructing exactly the ad-hoc behaviour this plan exists to retire.** On detection,
    binary-search the cap the probe just located, re-issue over slices beneath it, and
    **union the per-slice coverage into one verdict**. If auto-narrowing is refused for any
    reason, print the exact slice invocations rather than a bare failure.
    Document the two known false-pass modes: the measured curve is non-monotone in both
    directions, so two samples can land anywhere on it; and if `--limit` binds both calls
    they compare equal and the check passes. **Critically, when the whole window predates
    retention both calls return 0, `0 >= 0` holds, and the check does not fire at all** —
    so it does not detect the motivating 12-day case and must never be described as closing
    finding C. That case is caught by the coverage verdict (3.9), not by this probe.
3.8 **Fail closed, and classify 5xx by re-issuing at half width.** Non-null `.error`,
    `result: null`, or any non-2xx exits non-zero; a row count is **never** printed for a
    failed query. But **HTTP 500 must not be classified "transient" on sight**: finding D is
    deterministic and *window-dependent* (`group by source` over 55 days 500s reproducibly),
    and 3.6's enumeration is the mandatory first call — so a wide incident window 500s
    immediately and a "transient, retry" verdict sends an agent into a loop against a
    deterministically-failing request. Re-issue once at half width: a 500 that survives
    narrowing is genuinely transient (exit 1); one that clears is a window-size failure and
    must be named as such, with the narrowed slices offered.
3.9 **The atomic evidence block — the output contract.** The harm occurs when a count is
    separated from its verdict, because the consumer is an agent transcribing into a
    determination. So count, resolved ref + project, covered window, per-source
    instrumentation status and verdict are **one inseparable block**, not a row count with a
    verdict printed nearby. `INCONCLUSIVE` is the single top-line verdict token;
    `UNINSTRUMENTED` is a *reason* attached to it, never a second token to scan for.
    **`--json` emits one object** — `{verdict, coverage, ref, project, sources, rows}` —
    never a bare array; human mode puts the block on stderr so stdout stays pipeable. This
    matters because the machine path is the one an agent uses, and a `--json` mode that
    suppressed the verdict would make "no bare zero" true only on the human path.

3.9b **Bind the verdict to the EXIT CODE — otherwise the whole contract leaks through `$?`.**
    A verdict that is only a printed line is invisible to `if helper; then echo clean; fi`,
    to `set -e`, and to any agent reading `$?` — and `INCONCLUSIVE`/`UNINSTRUMENTED` exiting
    0 reads as success, which is precisely the false all-clear in §User-Brand Impact,
    re-entered through the one channel nothing else guards. **Exit 3 for
    INCONCLUSIVE/UNINSTRUMENTED**, distinct from 0 (COVERED), 1 (transient) and 2
    (auth/config). Note `betterstack-query.sh` already uses exit 3 for missing creds — the
    divergence is documented in `--help` rather than silently inherited.

3.9c **Every failure mode names the agent's next action.** Today only mode B does (it prints
    the observed source set). Model the rest on it. Mode E is the sharpest: the helper has
    already computed per-source counts, so when `edge_logs` is uninstrumented it can say so
    *and* route — *"`edge_logs` is UNINSTRUMENTED on this project; `postgres_logs` and
    `supavisor_logs` are instrumented over this window and may answer the access question."*
    Without that, the next investigation repeats 2026-06-29's source choice. Mode A must say
    explicitly **"do not hand-write a query — the helper builds the SQL, so a dialect error
    means the helper is stale; file an issue"**, or the agent bypasses the helper and the
    regression this plan exists to prevent returns.
3.10 **Data minimisation** — bounded `--limit` default, no artifact, no output file. Note
    honestly that in an agent session stdout lands in a transcript, so the bounded limit —
    not "stdout only" — is the real control.
3.11 Exit codes per 3.9b; shared verdict logic in `scripts/lib/` (auto-registers).

3.12 **ClickHouse dialect — there is an in-repo precedent; do not invent the idioms.**
     The replacement endpoint requires ClickHouse SQL, and `scripts/betterstack-query.sh`
     already writes it against a different warehouse. Adopt its forms rather than
     translating BigQuery habits:

     - **Time filtering:** `dt >= now() - INTERVAL <n> <unit>` for relative windows,
       `dt >= '<iso>'` for absolute — not BigQuery's `TIMESTAMP_SUB`.
     - **Newest-N presented oldest-first** is a *nested* subquery, and this is the one that
       bears on our coverage math (`betterstack-query.sh:216-218`):
       ```sql
       SELECT ts, msg FROM (
         SELECT ts, msg FROM <src> WHERE <pred> ORDER BY ts DESC LIMIT <n>
       ) ORDER BY ts ASC
       ```
       The inner `ORDER BY … DESC LIMIT` selects **which** rows survive; the outer reorders
       them. Get this wrong and `--limit` silently changes *which* window the returned rows
       describe — which corrupts the `min()`/`max()` coverage report **and** is the
       mechanism behind the monotonicity probe's known false-pass (if `--limit` binds both
       calls they can compare equal regardless of truncation). Compute coverage from an
       aggregate query that is **not** `--limit`-bound, never from the limited row set.
     - **Row-per-line output:** `FORMAT JSONEachRow` is the house form for machine parsing.

     **Vendor-dialect specifics** (researched; treat as leads to confirm at Phase 0, not as
     settled contract):

     - **Structured metadata is a `log_attributes` map, not nested JSON** — bracket access
       with the full dotted key as a string: `log_attributes['request.method']`. Map values
       are **always strings**, so numeric comparison needs `toInt32OrZero(...)`. Keys are
       discoverable at run time: `SELECT arrayJoin(mapKeys(log_attributes)) AS key FROM logs
       WHERE source = '<src>' GROUP BY key`. This is the single biggest unknown the helper
       faces and it is answerable in one call.
     - **BigQuery→ClickHouse:** `UNNEST(x) WITH OFFSET` → `ARRAY JOIN x, arrayEnumerate(x)`;
       `TIMESTAMP_SUB(t, INTERVAL n DAY)` → `subtractDays(t, n)`;
       `REGEXP_CONTAINS(c, p)` → `match(c, p)` (RE2); `SAFE_CAST` → `toStringOrNull` /
       `toInt32OrZero`; `IFNULL` → `ifNull`/`coalesce`. `concat()` **propagates NULL** — wrap
       every nullable argument in `coalesce(x, '')`.
     - **Timestamps:** compare against a parsed value, not a bare string literal —
       `parseDateTime64BestEffort('<iso>', 6)`. `min()`/`max()` need no conversion.
     - **String escaping:** single-quote literals, doubling an embedded `'`;
       `curl --data-urlencode` handles URL-encoding, so escape only for ClickHouse.
     - **Documented `source` values** (13): `auth_logs`, `auth_audit_logs`, `edge_logs`,
       `function_edge_logs`, `function_logs`, `postgrest_logs`, `pgbouncer_logs`,
       `postgres_logs`, `realtime_logs`, `storage_logs`, `supavisor_logs`,
       `database_version_upgrade_logs`, `multigres_logs`. Every source this plan measured on
       the prd ref appears in that list — corroboration, not a substitute for 3.6's runtime
       enumeration, which stays authoritative because the list can drift.

     **One researched claim is CONTRADICTED by this plan's own measurement — do not act on
     it.** Secondary sources state the endpoint rejects `COUNT(*)`. Every probe in this plan
     used `count(*)` (`select source, count(*) as c from logs group by source` and
     `select count(*) as c from logs`) and each returned HTTP 200 with a populated `result`.
     Direct measurement outranks the write-up; `count(*)` is used throughout 3.6. Recorded
     so an implementer who meets the same claim does not "fix" working code. *(Sources also
     claim `SELECT *` is rejected — untested here, and the helper never issues it.)*

### Phase 4 — Discoverability wiring (do not skip; this is what the MCP cut rests on)

4.1 **Inject the invocation into agent-facing bodies**, beside the existing Better Stack and
    `sentry-issue.sh` entries: `plugins/soleur/skills/incident/SKILL.md` (the "Toolchain:"
    sentence, :35), `plugins/soleur/skills/reproduce-bug/SKILL.md` (:28 tool list),
    `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` (:48), and
    the DSAR runbooks (`dsar-export-failed-job.md`,
    `dsar-manual-supply-excluded-tables.md`) — DSAR is a stated consumer.

4.2 **Promote GATE G-ESCALATE to a runbook — the procedure the helper is built to serve
    currently has no durable home.** Verified: `GATE G-ESCALATE` appears in exactly four
    files, all historical (two plans, the post-mortem, the evidence record). The procedure
    *body* — key-exposure check → *"establish the actual log-retention horizon FIRST"* →
    access-log analysis → the three-way coverage branch → key rotation — exists **only as a
    blockquote inside `2026-06-29-security-inngest-prd-enable-rls-lockdown-plan.md`**, and
    is referenced by zero skills, agents, commands or legal documents. The post-mortem
    already calls it reusable and it was still never promoted. Ship it as
    `runbooks/breach-access-log-investigation.md`, with steps 2 and 3 executing the helper.

4.3 **Give that runbook `triggers:` frontmatter — and note what this activates.**
    `incident/SKILL.md:154` `awk`-scans every runbook for a `triggers:` block to route by
    symptom, and `:164` falls through to *"no runbook matches — proceed to ad-hoc
    response"* when none is found. Measured: **zero of the repository's runbooks carry
    `triggers:`**, so that routing surface is inert for every incident today. This runbook
    would be the first to activate it. (Widening the convention to existing runbooks is out
    of scope and tracked.)

4.4 **Wire the inbound reference** from `knowledge-base/legal/statutory-response-catalog.md`
    §Breach step 4 (`:73`), which routes to `/soleur:incident` — so the breach path reaches
    the procedure rather than depending on recall.

### Phase 5 — Suite + registration

`tests/scripts/test-supabase-logs-query.sh`, fake-curl PATH shim replaying Phase 3.1
fixtures, never touching the network. Explicit `run_suite` line in `scripts/test-all.sh`.

### Phase 6 — Append-only addenda (CLO-ruled)

**Posture: annotate, never correct.** The `logs.all` line at `gate-g-escalate-evidence.md:35`
is a **true statement about what an agent did on 2026-06-29**. Rewriting it to name the
replacement would falsify a historical evidence record to make a grep pass.

6.1 `gate-g-escalate-evidence.md` — dated addendum: endpoint retired 2026-09-23, replacement,
    ClickHouse dialect, **the working replacement SQL**
    (`from logs where source = 'postgres_logs'`), and the helper + runbook. Naming the new
    endpoint while leaving only BigQuery SQL would land the next agent in finding A.
6.2 The determination — dated addendum recording the migration and the retention-posture
    change, **explicitly stating it does not alter the access-log determination** because
    `edge_logs` is uninstrumented. Verdict, Reasoning, Conditions, sign-off untouched. Do
    **not** insert an endpoint reference in order to "correct" one.
6.3 `post-mortems/inngest-prd-rls-disabled-exposure-postmortem.md` — the third document,
    carrying the stale figure at :48 and :126, and a record of follow-up #5697 at :142 (also carried by `plans/2026-07-15-security-soleur-dev-inngest-rls-lockdown-plan.md:404`, so it is a primary but not unique reference).
6.4 Reconcile sibling cross-references across all three in the same edit.
6.5 **No retention TOM in the register** (PR-A): what was measured is revocable vendor-side
    retrievability through an instrument proven untrustworthy — recording it as a technical
    measure would claim a control we do not hold.

### Phase 7 — Runbook + ADR-197

Runbook at `runbooks/supabase-log-query.md`, mirroring `betterstack-log-query.md`'s **entry
point**, leading with the `doppler run` invocation.

ADR-197 scoped to **one invariant, stated above the vendor**: *a zero from any log surface
is not evidence of absence without a coverage and instrumentation assertion.* The repo now
has **two independent vendor proofs** of the class — the Better Stack `remote()`
hot-window (`--since 24h` silently answering with ~40 minutes; it kept #6288 open from
2026-07-10) and this endpoint's non-monotonic cap. Stating it at that altitude is what stops a third surface relearning it.
The ADR also records what the guard's non-vacuity rests on **after** `advisors/*` migrates
(the host-pin arm), so a future reader does not re-litigate it.

### Phase 8 — Learning + tracking issues

Learning generalizing the "a short answer is the bug" class across both log surfaces.

Tracking issues: **`compliance/critical`** — Art. 30 transcription, scoped **wider than one
record**: audit every determination in `legal/audits/` for register transcription, since an
Art. 33(5) record living only inside its own fenced block is a systemic gap; **promote the
guard to blocking** (with the four enumerated steps from 2.7); **`advisors/*`** — *no
replacement path exists in the spec*, so the issue is "monitor for a successor or an
announced removal date", discharged by PR-C's spec diff, **not** "migrate the callers";
**PA-8 register placeholders** (`__TBD_BETTERSTACK_RETENTION__`, `__TBD_OBSERVED_VOLUME__` ×2,
`__TBD_DPA_DATE__`); **C4 `supabaseMgmtApi`** element; **env-var unification**.

**#5697 — annotate, keep OPEN.** Verified `OPEN`, `priority/p2-medium`, `observability`. It
asks to raise retention **or ship logs to a durable sink**; revocable vendor-side
retrievability satisfies neither, and the durable-sink limb is untouched.

**Waiver expiry routes to the poller, not the gate.** Use the `scripts/expenses-verify-by-check.sh`
`verify_by` shape (scheduled, files a report, out-of-band) rather than
`lint-encryption-posture.py`'s blocking `expires_on`. Nobody should learn about a waiver
expiry from a red check on an unrelated PR — and `advisors/*` has no announced removal date,
so an expiry that hard-fails CI would force a migration the vendor has not made possible.

### Phase 9 (PR-C) — Deprecation spec-diff, folded in

One step appended to `.github/workflows/scheduled-supabase-advisor-scan.yml`, which is
`workflow_dispatch:`-only (dispatched by the Inngest function
`apps/web-platform/server/inngest/functions/cron-supabase-advisor-scan.ts`), already holds
`SUPABASE_ACCESS_TOKEN` (:54), already calls this host, and already carries a label-based
dedupe + comment-if-open + auto-close block (:248-280). Folding in avoids a new cron surface
**and** the `new-scheduled-cron-prefer-inngest` hook that would deny a new scheduled
workflow outright.

**Precedent verified (ADR-033):** 53 Inngest cron functions vs 13 GH Actions
`scheduled-*.yml` — Inngest is canonical, and this target is already on it.

**Implementation constraint from that file's own header:** the hook denies the write when
the trigger token appears **even inside a comment**. So the appended step must not
introduce that literal anywhere in the YAML, including explanatory comments — describe the
cadence in prose ("the nightly fire", "the Inngest dispatcher") rather than naming the
trigger key.

Mirror `scheduled-marketplace-drift.yml`'s hardening: bootstrap the label before
`gh issue create`; capture `gh issue list` **and its exit code** and refuse to file when the
lookup itself failed (`:633`) rather than collapsing failure into `""`. **The fetch must fail
loudly**: a failed or shape-changed spec fetch treated as "no drift" reintroduces this
plan's own defect class one layer up.

## Files to Create

- `scripts/supabase-logs-query.sh`, `scripts/lib/<verdict-helper>.sh`
- `scripts/lint-supabase-deprecated-endpoints.sh` + `.highwater`
- `tests/scripts/test-supabase-logs-query.sh`, `tests/scripts/test-lint-supabase-deprecated-endpoints.sh`
- `tests/scripts/fixtures/supabase-logs/*.json` *(synthesized bodies)*
- `knowledge-base/engineering/operations/runbooks/supabase-log-query.md` *(the helper's
  entry point — how to run it)*
- `knowledge-base/engineering/operations/runbooks/breach-access-log-investigation.md`
  *(Phase 4.2 — the GATE G-ESCALATE procedure the helper serves, with `triggers:`
  frontmatter. Distinct from the above: one documents the tool, the other the investigation.)*
- `knowledge-base/engineering/architecture/decisions/ADR-197-*.md` *(provisional)*
- `knowledge-base/project/learnings/integration-issues/<date>-<topic>.md`

## Files to Edit

- `knowledge-base/legal/statutory-response-catalog.md` — §Breach step 4 (`:73`) references
  the new investigation runbook

- `.github/workflows/ci.yml` — advisory step in `lint-bot-statuses`
- `scripts/test-all.sh` — `run_suite` lines
- `plugins/soleur/skills/incident/SKILL.md`, `plugins/soleur/skills/reproduce-bug/SKILL.md`,
  `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` *(Phase 4)*
- `knowledge-base/engineering/operations/runbooks/dsar-export-failed-job.md`,
  `dsar-manual-supply-excluded-tables.md`
- The three evidence documents *(append-only)*
- **PR-A only:** `knowledge-base/legal/article-30-register.md`, `compliance-posture.md`
- **PR-C only:** `.github/workflows/scheduled-supabase-advisor-scan.yml`

## Second-Caller Sweep

| Surface | Caller of `logs.all`? | Evidence |
|---|---|---|
| Committed scripts / workflows / Terraform / app code | **No** | `git grep 'logs\.all'` → 1 hit, prose in a KB doc. |
| Doppler-stored PAT used by a non-repo cron | **Unknown — not clean** | A repo grep cannot exclude it. **Action before 2026-09-23:** pull Supabase's own Management API request log for `logs.all` over the last 30 days and attribute the traffic, or record it as accepted-unknown with the blast radius named. The spec-diff poller diffs the *spec*, not traffic — nothing else in this plan detects this. |
| Self-hosted host unit | **No** | No unit references `api.supabase.com`; host telemetry ships to Better Stack via Vector. |
| Vector / Better Stack ingestion path | **No** | Writes to Better Stack, reads via `betterstack-query.sh`. Never calls `api.supabase.com`. |

**Adjacent deprecation with live callers.** `/advisors/security`: **two direct call sites** —
`.github/workflows/apply-inngest-rls.yml:238` and `scripts/supabase-advisor-scan.sh:159`.
Blast radius is wider: `scheduled-supabase-advisor-scan.yml:107` invokes that script on a
schedule, so removal breaks a *recurring* gate.
(`cron-supabase-advisor-scan.test.ts:95` asserts the opposite property and is not a caller.)
`/advisors/performance` has **zero** non-doc callers. **No replacement path exists in the
spec** for either.

## Acceptance Criteria

*(Every `grep -c` below is wrapped `|| true` and compared with `[[ ]]`: **`grep -c` exits 1
on zero matches**, so a satisfied absence assertion would otherwise kill the step under
`set -e`. `-F` is used wherever the needle contains dots, so `api.supabase.com` cannot match
`apiXsupabaseYcom`.)*

### Pre-merge (PR-B)

1. `bash scripts/supabase-logs-query.sh --help` exits 0 and documents every flag, the
   `doppler run` invocation, and the exit-code table including the `betterstack-query.sh`
   divergence.
2. `[[ "$(grep -cF 'API="https://api.supabase.com"' scripts/supabase-logs-query.sh || true)" -eq 1 ]]`
   and, mirroring the working assertion in `scan-workflow.test.sh:259-273`:
   `api_line="$(grep -E '^\s*API=' scripts/supabase-logs-query.sh)"` contains no
   `${` / `$(` / `$VAR`.
3. `[[ "$(grep -cF 'SUPABASE_API_HOST' scripts/supabase-logs-query.sh || true)" -eq 0 ]]`.
4. `bash tests/scripts/test-supabase-logs-query.sh` prints `Results: <N> passed, 0 failed`,
   exits 0 with **no network route**, and `N` meets the floor asserted from the suite's own
   emitted count line (not a prose number).
5. Fixture replay catches all six failure modes, including **F** (format-valid wrong ref).
6. **No input produces a bare zero.** Asserted over the **`--json`** path by name: the
   emitted object always carries `verdict`, `coverage`, `ref`, `project`.
7. **Verdict is bound to the exit code:** every zero-row fixture exits **3**
   (INCONCLUSIVE/UNINSTRUMENTED), never 0. Asserted per fixture.
8. `INCONCLUSIVE` is the only top-line verdict token; `UNINSTRUMENTED` appears only as a
   reason.
9. **A window wider than the cap still yields an answer**: the auto-narrow fixture returns a
   unioned per-slice coverage verdict, not a bare failure.
10. **Write-boundary sweep** (`hr-write-boundary-sentinel-sweep-all-write-sites`): the helper
    contains no `tee`, no `>`/`>>` redirect to a path, no `$GITHUB_OUTPUT`,
    `$GITHUB_STEP_SUMMARY`, `upload-artifact` or `mktemp`. This is the only mechanical check
    on the data-minimisation claim in §Encryption Posture.
11. **No production log row is committed.** Every value in
    `tests/scripts/fixtures/supabase-logs/*.json` is synthesized. No existing gate covers
    `tests/scripts/fixtures/**`, so this AC is the sole control.
12. `bash scripts/lint-supabase-deprecated-endpoints.sh` exits 0 on the tree as merged and
    emits a parseable census line; `--check-highwater` exits 0 against the committed
    `.highwater`.
13. Removing the `advisors/security` waiver drives the guard **RED on exactly N call sites**,
    N derived from the pathspec recorded in the script header (see 2.2b — the answer is 2 or
    3 depending on whether `*.test.sh` is in scope; the pathspec decides, not prose).
14. **A deprecated path on a line not containing the host literal is still RED** — the
    file-scoped-extraction proof (2.1). A line-scoped guard passes this tree with zero
    findings.
15. **A caller carrying a PAT or a `/v1/projects/` path but no host literal is RED or
    allowlisted** — the inverted-quantifier proof (2.2).
16. The host-pin arm is **PASS** on all currently-compliant files, including
    `apps/web-platform/lib/supabase/service.ts:66` (path-interpolating template literal).
17. `bash tests/scripts/test-lint-supabase-deprecated-endpoints.sh` exits 0 and drives the
    guard RED on every §Guard Contract row.
18. **Suite registration asserted directly, not via the orphan lint.**
    `scripts/lint-orphan-test-suites.sh` keys on the `*.test.sh` suffix and has **no
    producer loop for `tests/scripts/`** — its own header records this as a known gap, and an
    unregistered `tests/scripts/test-*.sh` probe measures as `covered, 0 orphaned`, exit 0.
    So assert the invariant itself:
    ```bash
    for s in test-supabase-logs-query.sh test-lint-supabase-deprecated-endpoints.sh; do
      grep -qE "^[[:space:]]*run_suite .*[[:space:]]bash[[:space:]]+[\"']?tests/scripts/${s}[\"']?([[:space:]]|\$)" \
        scripts/test-all.sh || { echo "UNREGISTERED: $s"; exit 1; }
    done
    ```
    Anchored on the **command**, not the label. *(Closing the linter's own `tests/scripts/`
    gap is tracked separately.)*
19. **Discoverability:** `supabase-logs-query.sh` appears at least once in each of
    `plugins/soleur/skills/incident/SKILL.md`, `plugins/soleur/skills/reproduce-bug/SKILL.md`
    and `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`.
20. `runbooks/breach-access-log-investigation.md` exists, carries a `triggers:` frontmatter
    block, and names the helper; `statutory-response-catalog.md` §Breach references it.
21. **Append-only, with a non-vacuity floor** (a typo'd path yields empty numstat and a
    green check otherwise; and the base must be the merge-base, since `main` moves during
    the PR and any other commit touching these files would render as a deletion):
    ```bash
    git diff --numstat "$(git merge-base origin/main HEAD)" -- \
      <gate-g-path> <audit-path> <postmortem-path> \
    | awk '{a+=$1; d+=$2; n++} END{printf "files=%d added=%d deleted=%d\n",n,a,d; exit (n!=3 || d>0 || a==0)}'
    ```
22. `[[ "$(grep -cF 'from logs where source' <gate-g-path> || true)" -ge 1 ]]` — the addendum
    carries working SQL, not just a renamed endpoint.
23. **`python3 scripts/lint-guard-contract.py <plan>` exits 0 AND reports `2 guard entries`
    for this file.** The count is load-bearing: a plan whose Guard Contract the linter cannot
    parse reports `0 guard entries` and still exits 0 — the vacuous shape, and exactly what a
    malformed fence in this plan produced during review.
24. `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0.
25. ADR-197 file exists and the ordinal is re-verified free across all `origin/*` refs
    immediately before merge.

### Pre-merge (PR-A)

26. `[[ "$(grep -cF 'inngest-prd-rls-reachability' knowledge-base/legal/article-30-register.md || true)" -ge 1 ]]`
    (was `0`). The transcription is dated 2026-08-26, so a reader does not infer the
    cross-reference existed since 2026-06-29.
27. `compliance-posture.md` carries an Active Items row referencing the `compliance/critical`
    issue.
28. **No retention TOM and no new placeholder**, anchored on **added lines only** (plain
    `git diff` includes context lines, so an unchanged neighbour would false-fail):
    ```bash
    [[ "$(git diff "$(git merge-base origin/main HEAD)" -- knowledge-base/legal/article-30-register.md \
       | grep -cE '^\+[^+].*(60[- ]day|retention.*Supabase|__TBD_)' || true)" -eq 0 ]]
    ```
29. `gh issue view 5697 --json state --jq .state` returns `OPEN` (the bare `--json state`
    form returns `{"state":"OPEN"}` and would never string-match).

### Post-merge

30. CI green on `main`. **The new lint step is advisory and does not gate merges** — see 2.7.

All criteria execute from a shell or in CI.

## Guard Contract

### Guard 1 — Management API deprecation + host-pin assembly

**Property.** No tracked file calls a Supabase Management API path Supabase has marked
deprecated (except under a waiver), and every such call site pins the host span to the
literal `https://api.supabase.com` so no env-controlled value can redirect a PAT-bearing
request.

**Assembly.** Computed at run time: tracked non-doc lines matching the host literal **AND**
`/v1/`, excluding comment lines. The host-literal-alone predicate over-matches by a large
margin on comments, an egress-allowlist hostname and test-assertion strings — counting those
is the bare-token-over-prose defect that killed the string denylist. The four existing
per-script snapshots **remain** (they assert per-invocation argv); this is the layer above
them, so the net is **+1 mechanism, not −4**. Anti-vacuity is a committed `.highwater`
ratchet, not a hand-set floor.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove the `advisors/security` waiver | **RED on two real call sites** — the live non-vacuity proof |
| 2 | Add a new caller of `analytics/endpoints/logs.all` | RED |
| 3 | Add a new caller with `API="${SUPABASE_API_HOST:-…}"` (host span interpolated) | RED |
| 4 | Add a **second** non-compliant caller after a compliant one | RED, **both** reported |
| 5 | Delete a call site so the enumeration count drops | RED via `--check-highwater` — the ratchet makes a vanished site a diff, not rounding |
| 6 | Add a compliant caller whose **path** interpolates `${REF}` | **PASS** — the false-positive control; a guard that reddens here asserts on the wrong span |
| 7 | *(harness)* Run against a fixture tree with zero deprecated paths | **PASS** — must-PASS non-canonical input, proving the guard does not reject everything |

*(Row count trimmed toward `MIN_MUTATION_ROWS = 3`. A "rename the host literal" row was
**removed as undrivable**: a file that drops the literal leaves an assembly enumerated by it.
The ratchet in row 5 is the honest backstop, and the chokepoint limitation is documented in
the ADR rather than papered over by an unsatisfiable row.)*

### Guard 2 — the helper cannot emit a bare zero

**Property.** `supabase-logs-query.sh` never reports a row count without an inseparable
coverage verdict naming the resolved project, and never reports zero rows for a query that
failed, was truncated, targeted an uninstrumented source, or hit the wrong project.

**Assembly.** The script's **single result-rendering function** — every output path, success
and failure, human and `--json`, routes through it. The suite quantifies over the fixture
directory, so a fixture added later is covered automatically.

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `.error != null` check | RED (dialect-error fixture reports 0 rows) |
| 2 | Delete the monotonicity self-check | RED (wide-window fixture passes silently) |
| 3 | Delete the source/instrumentation call | RED (typo-source reports a clean zero; `edge_logs` reports `COVERED`) |
| 4 | Drop the resolved ref/project from the block | RED (finding F fixture prints `COVERED` with no project identity) |
| 5 | **Move** the verdict emission from before the row-count print to after the empty-result early return | RED — the verdict must be emitted *inside* the window where a zero is rendered, not merely present in the file |
| 6 | Make `--json` emit a bare array | RED (AC5 asserts the object over the machine path) |
| 7 | Treat HTTP 500 as a zero-row success | RED |
| 8 | **Make `INCONCLUSIVE`/`UNINSTRUMENTED` exit 0** | RED — the verdict must reach `$?`, not only stdout; an exit-0 INCONCLUSIVE is the false all-clear re-entering through the one channel nothing else guards |
| 9 | Add a write site to the helper (`tee`, `> path`, `$GITHUB_OUTPUT`, `upload-artifact`) | RED — the write-boundary sweep is the only mechanical check on the data-minimisation claim |
| 10 | Delete the auto-narrow arm, leaving detection only | RED — the wide-window fixture must still return a unioned answer, not a bare failure |
| 11 | *(harness)* Add a well-formed non-canonical success fixture | **PASS** — must-PASS input the contract permits |
| 12 | *(harness)* A legitimately narrow-but-old window whose sub-window naturally returns fewer rows | **PASS** — the monotonicity false-**positive** control; a check that fires here makes the tool unusable for the 12-day journey and would ship green |

## Observability

```yaml
liveness_signal:
  what: the deprecation-assembly lint step in the ADVISORY `lint-bot-statuses` job, plus the
        two suites run by `scripts/test-all.sh` via their explicit `run_suite` lines
  cadence: every push and every PR
  alert_target: "PR annotation on a red advisory step — NOT a required check. Promotion to
                 blocking is tracked (Phase 8) and deliberately out of scope here."
  configured_in: .github/workflows/ci.yml (lint-bot-statuses), scripts/test-all.sh
error_reporting:
  destination: stderr with the house `::error::` prefix; CI surfaces it as a step annotation
  fail_loud: true — a non-null `error` field, a null `result`, or any non-2xx is ALWAYS an
             error exit, never a zero-row success
failure_modes:
  - mode: query rejected by the ClickHouse dialect (HTTP 200 + error field)
    detection: the script tests `.error != null` before reading `.result`
    alert_route: non-zero exit naming the dialect
  - mode: log source does not exist or was renamed
    detection: 30-day `group by source` enumeration validates `--source`
    alert_route: exit 2 with the observed source set
  - mode: source exists but never emitted
    detection: pinned 30-day span count compared against the windowed count
    alert_route: INCONCLUSIVE with an UNINSTRUMENTED reason; never rendered as `0`
  - mode: window exceeds the undocumented range cap and is silently truncated
    detection: monotonicity sub-window probe when the window exceeds 7 days
    alert_route: non-zero exit naming the truncation
  - mode: upstream 5xx with a null error field
    detection: HTTP status checked independently of the body
    alert_route: exit 1 (transient)
  - mode: format-valid but wrong project ref
    detection: pinned prd default; resolved ref + project echoed on every output path
    alert_route: the evidence block names the project on success as well as failure
  - mode: a deprecated Management API path enters the repo
    detection: Guard 1 over the host-literal + /v1/ assembly
    alert_route: red advisory CI step (annotation, not a merge block)
  - mode: a new caller ships without a host pin
    detection: Guard 1's host-span arm, same pass
    alert_route: red advisory CI step
logs:
  where: script stderr and CI step annotations. No artifact and no output file; note that in
         an agent session stdout lands in the transcript, so the bounded `--limit` default —
         not "stdout only" — is the operative data-minimisation control
  retention: GitHub Actions log retention for CI invocations only
discoverability_test:
  command: bash tests/scripts/test-supabase-logs-query.sh
  expected_output: "Results: <N> passed, 0 failed" with exit 0, offline
  credentials_required: none — replays synthesized fixtures through a PATH-shimmed fake curl
```

### Observability-layer citation (`hr-observability-layer-citation`)

This surface fits **none of layers 1–6** (server/host-side producers) and only partly
layer 7 (customer-executed `plugins/` code). Layer 7's own rule is that *a citation whose
only signal is stdout does not survive the session* — and §3.10 forbids the helper from
writing any file. That tension is real and is resolved deliberately, not ignored:

- **Row contents stay unpersisted** (personal data; the bounded `--limit` is the control).
- **The verdict is made durable** as a redacted, non-row-bearing **evidence stanza** —
  window requested, window covered, per-source counts, instrumentation status, verdict,
  resolved ref + project, timestamp, helper commit. That stanza is safe to persist, is what
  the Phase 4.2 runbook instructs pasting into the record, and is what makes a reviewer able
  to reproduce the finding. Without it the terminal step of the journey — turning a verdict
  into an Art. 33(5) record — is undefined, which is how the 2026-06-29 record came to
  inline findings as prose in the first place.

### Principle alignment (`principles-register.md`)

- **AP-021 (diagnostic honesty, ADR-166)** — *never collapse "could not check" into "clean"*.
  Binds PR-C's poller: it must discriminate `SPEC_UNREADABLE` from `no_drift`, asserting
  HTTP 200 **and** `content-type: application/json` **and** `jq -e 'type=="object"'`, plus a
  **parse floor** (the spec must yield ≥N paths and ≥1 `deprecated: true` — `logs.all` is a
  known-live positive control until 2026-09-23, then `advisors/security`). A spec parsing to
  zero deprecated paths is channel-dark, never no-drift. Enforced by
  `scripts/lint-diagnosis-claims.sh`.
- **AP-022 (workflow errexit clearing, ADR-170)** — PR-C captures a curl exit status, and a
  `run:` block with no `shell:` key is invoked `bash -e {0}`. Clear errexit explicitly.
  Enforced by `scripts/lint-workflow-errexit-capture.py`.
- **AP-023 (anti-vacuity floors, ADR-193)** — this plan adds three floors (the census
  ratchet, the fixture-count floor, the suite pass-count floor). They are auto-discovered by
  **shape** by `scripts/guard-vacuity-floor.test.sh`, so they must report via
  `printf >&2` + `exit 1`, move their counter at the call site, never run inside `$( )`, and
  derive their population by shape rather than listing it.
- **AP-024 (a verification surface does not actuate, ADR-189)** — met by construction: the
  helper senses and publishes a verdict; it writes nothing.

## Architecture Decision (ADR/C4)

### ADR

**Create ADR-197** *(provisional; re-verify across all `origin/*` refs before merge)* —
scoped to one invariant stated **above the vendor**: *a zero from any log surface is not
evidence of absence without a coverage and instrumentation assertion.* Two independent
vendor proofs: the Better Stack `remote()` hot window (silently answering ~40 minutes for
`--since 24h`, which kept #6288 open from 2026-07-10) and this endpoint's non-monotonic cap. Records the six failure modes, the
guard's chokepoint **and its documented limitation**, and what non-vacuity rests on after
`advisors/*` migrates.

### C4 views

The enumeration ran against all three model files. `model.c4` models Supabase only as
`database "Supabase PostgreSQL"` and `database "Supabase PostgreSQL (Inngest)"`; the
**Management API control plane is absent**, while the sibling observability planes
(`betterstack`, `sentry`) are modelled as `system` with `#external`. No new external actor;
this plan adds a caller of that unmodelled edge.

**Deferred, tracked.** The gap predates this plan and serves none of P1–P6, and
`wg-architecture-decision-is-a-plan-deliverable` is satisfied by the ADR. Deferring avoids
adding a model element plus two render tests to a deadline PR. The enumeration above is the
citation the completeness mandate requires.

## Encryption Posture

```yaml
in_transit:
  - connection: helper -> Supabase Management API (api.supabase.com)
    tls: TLS 1.2+ via curl's system trust store; HTTPS is part of the pinned literal
    cert_verification: on (no --insecure, no --proxy-insecure)
    does_not_defend: a compromised local trust store; an attacker already holding the PAT;
                     log-row contents once returned to the caller's terminal or transcript
    disclosed_as: internal control-plane call to an existing processor; no new sub-processor
at_rest:
  - store: none — the helper persists nothing and writes no artifact. Test fixtures carry
           synthesized values only (Phase 3.1).
```

No `exception` block: no plaintext store, no disabled certificate verification.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The migration is treated as a path rename and ships a silently-wrong tool | All six failure modes are replayable fixtures and ACs 4–6, not prose warnings. |
| **Production log rows committed to a public repo** | Phase 3.1 synthesizes every row body; AC7 asserts it. No existing gate covers `tests/scripts/fixtures/**`, so the AC is the only control. |
| **The guard is mistaken for a merge gate** | 2.7 and the Observability block state plainly that it is advisory; promotion is a tracked issue with four enumerated steps. |
| The guard goes vacuous when `advisors/*` migrates | The host-pin arm stays non-vacuous over the whole assembly; the ADR records this explicitly. |
| The enumeration silently shrinks | `.highwater` ratchet (AC9), not a hand-set floor with slack. |
| The host-pin arm false-positives on legitimate path interpolation | 2.4 scopes the assertion to the host span; Guard 1 row 6 is the must-PASS control. |
| The instrumentation check marks everything `UNINSTRUMENTED` | Span pinned to a measured 30 days (3.6), not "full retained span". |
| Monotonicity is treated as closing finding C | 3.7 documents the false-pass mode; the ADR states it is a heuristic. |
| **A wrong-project query reads as clean** | Pinned prd default + resolved ref/project echoed on every output path (3.5); Guard 2 row 4. |
| The verdict is separated from the count when transcribed | The atomic evidence block (3.9); `--json` emits one object. |
| An agent never finds the helper | Phase 4 skill-body wiring; AC14. The MCP cut depends on this. |
| Waiver expiry breaks unrelated PRs | Expiry routes to the poller via the `verify_by` shape, never the gate. |
| A non-repo cron still calls `logs.all` on 2026-09-23 | Named as **unknown, not clean**; a pre-deadline traffic attribution is scheduled in §Second-Caller Sweep. |
| Legal work delays the deadline PR | PR-A ships independently and first. |

## Alternative Approaches Considered

| Alternative | Verdict |
|---|---|
| Do nothing — no committed caller breaks on 2026-09-23 | **Rejected.** The prose *is* the caller, and it leaves `advisors/*` unguarded. |
| A `logs.all` string-denylist lint | **Rejected** — vacuous once the prose hit is handled; the forbidden bare-token shape. |
| Runbook only, no script | **Rejected** — a runbook cannot enforce enumeration, monotonicity, project identity or the error check. |
| Script + runbook, no skill-body wiring | **Rejected on measurement** — the sibling with a runbook and no skill-body mention is cited in zero agent bodies. |
| An MCP tool | **Rejected** with evidence (recorded OAuth failure), **conditional on Phase 4 landing**. |
| ≤24h chunking | **Rejected** — twelve calls to honour an unenforced cap. |
| A new scheduled workflow for the spec diff | **Rejected** — a PreToolUse hook denies new `schedule:` workflows (ADR-033); fold into the existing one. |
| A separate `.denylist` config file | **Rejected** — three strings; both cited precedents inline their patterns. |
| Migrating the `advisors/*` callers here | **Rejected** — *no replacement path exists*; monitoring is the only available action. |
| Promoting the guard to a required check in this PR | **Rejected for this PR** — the auto-fabrication guard makes it four coupled steps; tracked. |
| Unify `SUPABASE_ACCESS_TOKEN` / `SUPABASE_PAT` | **Rejected** — touches `run-migrations.sh`. Tracked as debt. |
| Bundling the Art. 30 fix | **Rejected** — independent work, different review lane; PR-A. |

## Test Scenarios

Every scenario names an **exit code**, because §3.9b makes the exit code part of the verdict
contract — a scenario that asserts only printed text cannot catch an INCONCLUSIVE that
exits 0.

1. Dialect-error fixture → non-zero, no row count, and the *"do not hand-write a query"*
   guidance printed.
2. HTTP 500 fixture → re-issued at half width; clears → named a window-size failure;
   survives → exit 1 (transient). Never a bare "transient, retry" on the first 500.
3. Typo-source fixture → exit 2 at enumeration, observed source set printed.
4. Wide-window fixture (>7d, truncating) → probe fires, **auto-narrow returns a unioned
   coverage verdict**, not a bare failure.
5. Window ≤7d → probe **not** issued (no doubled API cost).
6. Narrow-but-old window whose sub-window legitimately returns fewer rows → probe does
   **not** fire (false-positive control).
7. `edge_logs` fixture → `INCONCLUSIVE`, `UNINSTRUMENTED` reason, **exit 3**, and the routing
   line naming which sources *are* instrumented.
8. Zero rows, full coverage, instrumented, correct project → `VERDICT: COVERED`, **exit 0**.
9. Zero rows, partial coverage → `INCONCLUSIVE` naming the gap, **exit 3**.
10. **Window predates retention** (the motivating 12-day case; both samples 0, probe cannot
    fire) → `INCONCLUSIVE`, **exit 3** — caught by coverage, not by monotonicity.
11. **Wrong-but-valid ref** → resolved ref + project in the block; never a bare `COVERED`.
12. Malformed `--ref` (19 chars, uppercase, non-`[a-z0-9]`) → exit 2 before any request.
    A 20-char ref containing digits is **accepted** (refs are not contractually alpha-only).
13. Missing `SUPABASE_ACCESS_TOKEN` → exit 2 with the `doppler run` re-invocation and the
    "do not conclude no access / can't verify" line.
14. `sbp_` token in a response body → redacted at every print site.
15. `SUPABASE_API_HOST=https://evil.example.com` → recorded argv contains `api.supabase.com`.
16. `--json` → one object carrying `verdict`, `coverage`, `ref`, `project`; never a bare array.
17. Write-boundary sweep over the helper source (AC10).
18. Fixture-synthesis assertion (AC11).
19. Guard 1 and Guard 2 mutation matrices — all rows, including the file-scoped-extraction
    and inverted-quantifier proofs.
20. Direct `run_suite` registration assertion (AC18) — **not** the orphan lint, which is
    blind to `tests/scripts/`.
