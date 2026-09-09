---
title: "fix: confine credential forwarding in the fifteen shipped plugin scripts, pin the Better Stack query destination, and partition the BYOK concurrency outcomes"
date: 2026-09-09
slug: fix-credfwd-plugins-betterstack-pin-byok-fixture
branch: feat-one-shot-7898-7055-credfwd-plugins-bs-pin-byok-fixture
type: fix
issue: 7055
closes: 7055
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-09-09
**Panels run:** six-agent plan review (architecture-strategist, spec-flow-analyzer,
kieran-rails-reviewer, code-simplicity-reviewer, dhh-rails-reviewer, user-impact-reviewer), then a
deepen pass adding observability-coverage-reviewer, security-sentinel, a verify-the-negative sweep
and a post-edit self-audit. Domain review: CTO, CPO, GDPR gate.

### What the deepening actually bought

Almost none of it was elaboration. Nine claims this plan asserted were **falsified by running a
command**, and each correction is recorded inline where the claim used to be:

1. The `readonly DOPPLER_API_PINNED` remedy does not clear the Rule D finding — hoisting the
   multi-line payload does, and the plan had ordered them backwards. Measured on real copies.
2. The repo-wide summary prints live-offender counts, not baseline file lines, so the post-drawdown
   A/B/C figure is **101**, not 103. As written, a blocking criterion would have failed on a correct
   implementation.
3. The linter emits a **conditional** xtrace arm for `provision-doppler.sh`, whose token arrives from
   `read -rs` after the prologue — so "use the conditional arm wherever the linter offers one" would
   have shipped a guard that is open at guard time over an operator's Doppler token.
4. The hosted path is **not** a no-op: `AGENT_ENV_ALLOWLIST` forwards the proxy variables and `HOME`
   into the agent subprocess by design, and the original grep scope could not see a TypeScript
   allowlist.
5. `readRefusalReasonLive` throws, so a promise can **reject** — five outcome classes, not four, and
   the partition must be over `settled` rather than `results`.
6. `AC1` degraded into a repo-wide run, because `targets_from_args()` falls through to
   `all_shell_files()` on an empty path list.
7. Guard 2's glob-crossing mutation row was masked by the pre-existing shape arm, so the row it was
   meant to discriminate stayed green.
8. Guard 3 had one row that a CHECK constraint makes unrunnable and one whose detector does not exist.
9. The runbook premise was refuted by the runbook itself three lines above the edited line:
   `eu-fsn-3` and `eu-central-1a` are the same cluster, not different regions.

### What it removed

The brief's `highwater` task (no such artifact), the per-run-unique fixture (already on `main` at the
flaking commit), the opt-in seam (10 of 12 suites never reach the check), the `DOPPLER_API_PINNED`
constant, and a concurrent control that would have added live-DB contention to the suite being
repaired for intermittent redness.

### What it added

A proxy-aware failure line for the seven customer-facing scripts — the most likely real-world
consequence of shipping, which the plan named and then did not mitigate. Phase 4b, which serializes
the tenant-integration concurrency group so the PR removes a plausible cause rather than renaming a
symptom. And the finding that `record_byok_use_and_check_cap`'s founder-scoped meter genuinely does
pool across sibling delegations, which gives the null-change control a non-trivial target.

## Overview

Two scoped slices of the credential-forwarding confinement tracker (#7898, which stays open), plus
the fix for the flaky BYOK delegation atomicity assertion (#7055, which this closes).

Slice (a) covers fifteen shell scripts under `plugins/**`. Every credentialed `curl` in them reads
`~/.curlrc` and honours `HTTPS_PROXY` / `ALL_PROXY` before it honours the host it was given, so the
config file and the environment of whoever runs the script decide where the credential goes. Seven
of the fifteen run on an installed user's machine carrying that user's own social tokens; the other
eight are operator-only and carry Jikigai's production credentials, including a Supabase
service-role key that bypasses RLS across every customer's rows. The fix is the same prologue for
both halves — `--disable` first, `--noproxy '*'`, an xtrace refusal, and one real destination pin.

Slice (b) closes the `BETTERSTACK_QUERY_HOST` bare-host gap in `scripts/betterstack-query.sh`. The
existing shape check refuses userinfo, path and scheme smuggling but accepts a wholly substituted
bare host, and the ClickHouse read credential is then sent to whatever that host is, preemptively,
as Basic auth on the first request.

**#7055 is not what its issue body proposes.** The suggested direction — scope the delegation rows
to a per-run unique tenant or workspace — was already the state of the code at the commit that
flaked, and the hourly meter is keyed by `delegation_id`, so no outside writer can reach it. Reading
the assertion order at that commit shows the row lock held and exactly K calls were admitted; what
failed was a count computed by matching one expected error string, so a single call with any other
outcome was silently subtracted from it. The defect is an unpartitioned outcome channel. The fix
keeps every exact equality, adds no retries, and adds a control that measures the delegation-scoping
the issue only assumed.

## Research Insights

### Premise Validation (Phase 0.6)

Both targets are OPEN: #7898 (`type/security`, `priority/p2-medium`) and #7055 (`flaky`,
`priority/p3-low`). Four premises carried by the brief were checked; **three were stale**, and every
correction below is a command's output, not a reading.

| Premise as briefed | Measured reality | Command |
|---|---|---|
| Rule D census "stands at 80 files on current main, not the 67 the issue body records" | **82** path entries | `grep -vE '^\s*#' scripts/lint-shell-trace-credential-refusal-d.baseline.txt \| grep -vE '^\s*$' \| wc -l` |
| "Drive the Rule D baseline AND **its highwater** DOWN" | **No Rule D highwater exists.** No `lint-shell-trace-credential-refusal*.highwater` file; nothing in the linter or its suite references one. It was built and then CUT at review as "strictly subsumed by the repo-wide run" (`knowledge-base/project/specs/archive/20260907-211721-feat-one-shot-7867-7873-7886-betterstack-credfwd-lefthook/tasks.md` › item 2.g2). The baseline file **is** the ratchet. | `grep -rn 'highwater' scripts/ tests/ .github/workflows/` |
| #7055: "scope the delegation rows to a per-run unique tenant/workspace so a concurrent CI run cannot contribute to the same meter" | **Already true at the flaking commit.** See "The #7055 re-diagnosis" below. | `git show 37dc09e6:apps/…/byok-delegation.atomicity.tenant-isolation.test.ts` |
| Better Stack stub values are `stub, h, x, dummy-host, synthetic.example.invalid, 127.0.0.1, empty` | **8 distinct values across 12 suite files** — the list omits `stub.example` (`plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh` › the mirror-retry stub block). The file count (~12) is correct. | `grep -rn 'BETTERSTACK_QUERY_HOST' .` |

Premises that **held**: the 15 `plugins/**` paths are all present in the Rule D baseline; the
out-of-scope sites exist (`apps/web-platform/infra/soleur-host-bootstrap.sh`,
`web-private-nic-guard.sh`, and `apps/web-platform/infra/server.tf` carries nine
`triggers_replace = sha256(...)` blocks that re-provision on merge); `arm-heartbeats.sh` and
`cutover-verify.sh` are baselined; `scripts/betterstack-query.sh` carries the comment block ending
"tracked on #7898 rather than folded into the PR that added this check" immediately above its
`case "$BETTERSTACK_QUERY_HOST" in` shape check.

One correction to the brief's out-of-scope list: it names "the five Resend host scripts", but only
**one** Resend script is in the Rule D baseline (`apps/web-platform/infra/resend-inbound-bootstrap.sh`).
Either way they stay out of scope; the count is not quoted anywhere in this plan or its PR body.

### The measured Rule D census for `plugins/**`

Authoritative, from the guard itself rather than from reading the scripts:

```
python3 scripts/lint-shell-trace-credential-refusal.py $(grep '^plugins/' \
  scripts/lint-shell-trace-credential-refusal-d.baseline.txt | tr '\n' ' ')
→ lint-shell-trace-credential-refusal: 42 violation(s) in 15 scanned file(s)
```

Broken down: **15** Rule A ("binds a live credential but carries no xtrace refusal", one per file),
**26** Rule D transport-confinement, **1** Rule D destination-pin. Per-file Rule D counts:
`provision-doppler.sh` 4; `bsky-community.sh` and `linkedin-setup.sh` 3 each; `bsky-setup.sh`,
`linkedin-community.sh`, `x-community.sh`, `set-role.sh` 2 each; the remaining eight 1 each.

Two consequences the brief did not anticipate, both mechanical:

- **A scoped run reports Rule A as well as Rule D**, because `--changed` and explicit-path modes
  zero both baselines (`scoped = args.changed or args.paths`). The CI step
  `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` is therefore
  red on all 42 the moment any of the 15 files is touched. That step is **advisory**; the
  **blocking** one is the unscoped repo-wide run registered in `scripts/test-all.sh` as
  `scripts/lint-shell-trace-credential-refusal-repo`, which feeds the required `test` aggregate and
  honours both baselines. Fixing Rule D alone satisfies the blocking gate and leaves the advisory
  one red — which is the exact "trains people to re-run red checks" cost #7055 is filed about.
- **The one destination-pin hit is a tokenizer artifact, not a real env-settable destination.**
  `provision-doppler.sh:243` reports "credentialed curl sends to `$DOPPLER_TOKEN`, which is
  env-settable and never compared against a literal". The URL at that call site is the literal
  `https://api.doppler.com/v3/workplace/service_accounts/${SA_SLUG}/identity`; the invocation carries
  a multi-line `-d "{ …escaped JSON… }"` payload that breaks the linter's flag/operand tokenization,
  so `$DOPPLER_TOKEN` is read as a positional operand. It is env-settable by the "never assigned"
  arm, because `read -rs … DOPPLER_TOKEN` is not an assignment shape the linter recognises. The
  remedy is to change the **script**, never the classifier.

All 15 are also present in `scripts/lint-shell-trace-credential-refusal.baseline.txt` (the A/B/C
baseline, which suppresses by file), as a strict subset of its 20 `plugins/` entries.

### Rule D's contract, and the canonical prologue

From `scripts/lint-shell-trace-credential-refusal.py` › `check_rule_d`:

- `CURL_DISABLE_FIRST = re.compile(r"\bcurl\s+--disable(?:\s|$)")` — position is load-bearing;
  `--disable` must be the literal first token after `curl`, because it aborts `~/.curlrc` parsing
  and later is too late.
- `CURL_NOPROXY = re.compile(r"--noproxy\s+'?\*'?")` — presence anywhere in the invocation.
- The destination pin applies only to variables curl reads as a destination that are also
  env-settable, and is satisfied by a literal comparison (`[[ "$V" == "literal" ]]`), a `case` arm
  carrying a literal character, an `=~ ^<literal>` anchor, or comparison against a `readonly`
  literal constant (`_compared_to_literal_const`). A comparison against another variable is **not**
  a pin.

The must-PASS models live at `scripts/fixtures/shell-trace-refusal/compliant-canonical.sh` and
`compliant-ruled-pinned-destination.sh`; the latter demonstrates the
`readonly SINK_URL_PINNED="https://pinned.example/ingest"` + inequality-refusal shape this plan
reuses. The RED fixtures already cover every limb this plan touches, including
`violation-ruled-vacuous-case-pin.sh` and `violation-ruled-disable-not-first.sh`.

### The `BETTERSTACK_QUERY_HOST` gap, and the precedent that already solved it

`scripts/betterstack-query.sh` › the `case "$BETTERSTACK_QUERY_HOST" in` block rejects
`*[[:cntrl:]]*|*@*|*/*|*\?*|*\#*|*:*:*|""` and nothing else, and `run_sql` then sends
`-u "${BETTERSTACK_QUERY_USERNAME}:${BETTERSTACK_QUERY_PASSWORD}"` to
`https://${BETTERSTACK_QUERY_HOST}?output_format_pretty_row_numbers=0`. `--disable` and
`--noproxy '*'` are already present and are irrelevant to this gap. The script is in **neither**
baseline.

The sibling credential already has the fix: `scripts/betterstack-ingest-probe.sh` extracts the
authority (strip scheme, then path, query, fragment, then userinfo, then port) and matches
`case "$_bs_host" in *.betterstackdata.com)`. Its own header records why the naive form failed
(#7855): matching the allowlist against the **whole URL** let
`https://evil.com/?x=.betterstackdata.com/` through, because a shell glob's `*` crosses `/` and `?`.
That trap is the single most important thing to carry across.

Notably, `tests/scripts/test-betterstack-ingest-probe.sh` satisfies that allowlist **with no seam at
all**, using vendor-shaped hosts with a zeroed source id
(`https://s0000000.eu-fsn-3.betterstackdata.com/`).

**The live host is not the documented one.** The runbook
`knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` › the "Query host" bullet
records `eu-fsn-3-connect.betterstackdata.com:443`. Pulled read-only from the config the workflows
actually inject:

```
doppler secrets get BETTERSTACK_QUERY_HOST -p soleur -c prd_terraform --plain
→ eu-central-1a-connect.betterstackdata.com
```

Different hostname, and no `:443`. Both share the `betterstackdata.com` apex, so a suffix allowlist
is the right shape — and that is now **measured rather than inferred from the ingest URL**, which is
what the risk demanded. The must-PASS fixture host is `eu-central-1a-connect.betterstackdata.com`.

**One correction to an earlier draft of this paragraph, which called the runbook line "a different
region" whose "credentials do not work":** that is false by the runbook's own content three lines
above the edited one — its "Region naming" bullet records that `eu-fsn-3` and `eu-central-1a` are the
SAME cluster, the former being the vendor's earlier name, CNAMEd to the latter and resolving to an
identical five-address A set. The line is stale, not wrong-cluster, and the edit is a tidy-up rather
than a rescue. Saying otherwise mattered because the same premise was carrying the claim that the
apex had been *measured* — it has, but the measurement's value is confirming the apex, not catching a
broken host.

### Which suites actually reach the host check

The script's own comment forecasts "an explicit opt-in seam in each of those ~12 suites -- a 13-file
change". Measured per file, that is wrong: **10 of the 12 never execute the real script's host check
at all**, and a further one reaches it only through a `curl` shim. Each substitutes a fake query binary through a seam the *consumer* owns
(`INNGEST_ZOT_BOOT_QUERY_BIN`, `FLIP_ROLLOUT_QUERY_BIN`, `CI_DEPLOY_SENTRY_BQ`,
`ZOT_LOG_7440_QUERY_BIN`, `BETTERSTACK_QUERY_SH`) or writes a fake file at
`scripts/betterstack-query.sh` inside a sandbox repo and invokes it CWD-relative. Their
`BETTERSTACK_QUERY_HOST` value is inert filler satisfying some *other* script's presence check, so
the allowlist cannot break them whatever the value is.

Only two files touch the real check:

- `tests/scripts/test-betterstack-query-archive.sh` — `source`s the real script, and shadows `curl`
  with a shell function ("curl is the real egress boundary — stubbing it also proves no request
  escapes"). No request ever leaves, so its stub host can simply become vendor-shaped.
- `tests/scripts/test-git-data-rung2-evidence-capture.sh` — one arm, labelled in-file "THE ONE ARM
  THAT DOES NOT STUB betterstack-query.sh", runs the real script with `BETTERSTACK_QUERY_HOST=127.0.0.1`
  and **real** `curl`, relying on loopback refusing fast. This is the single case where changing the
  stub value alone would be unsafe: a vendor-shaped host would make it perform a genuine outbound TLS
  handshake at Better Stack's production endpoint carrying fabricated Basic-auth credentials.

So the real change is **3 files, not 13**, and the seam requirement collapses to one arm — which the
repo already knows how to handle by shimming `curl` (`scripts/compound-promote.test.sh` ›
`make_mock_curl()`; `scripts/followthroughs/zot-soak-6122.test.sh`).

### The #7055 re-diagnosis

At the flaking commit `37dc09e6`, line 483 is
`expect(tripped, \`exactly N−K=${N - K} calls raise the hourly marker${diag}\`).toBe(N - K)` — the
issue's citation is exact. Two things follow from reading that block:

1. **The fixture was already per-run unique.** `syntheticEmail()` derives from
   `randomBytes(8).toString("hex")`, `createSyntheticUser()` mints a fresh auth user (and reads back
   the workspace `handle_new_user` auto-creates), and `grantDelegation()` mints a **fresh delegation
   per test**. The hourly meter in `apps/web-platform/supabase/migrations/137_byok_cap_breach_audit_row.sql`
   is keyed by delegation: `WHERE au.delegation_id = p_delegation_id AND au.ts > clock_timestamp() -
   interval '1 hour'`, under `SELECT * INTO v_row FROM public.byok_delegations WHERE id =
   p_delegation_id FOR UPDATE`. No outside writer can reach that meter. The briefed fix is a no-op.
2. **The assertion ORDER names the real defect.** The assertions run
   `allFulfilled` → `admitted === K` → `tripped === N-K` → `audit.length === K`. The failure was on
   the third, so the first two **passed**: all ten calls settled, and exactly K=5 were admitted. The
   `FOR UPDATE` lock held and there was no double-spend. `tripped` was computed as
   `errors.filter(e => e !== null && /byok_delegations:hourly_cap_exceeded/.test(e.message ?? ""))`,
   so **one of the five refusals carried a different error and was silently subtracted**. The defect
   is an unpartitioned error channel: a call whose error is anything other than the hourly marker
   lands in no partition and decrements the count that is asserted.

The hole is still live after migration 137's rewrite, and it is **wider** than the error channel
alone. The current file computes `refused = results.filter(r => r?.refusalReason === HOURLY_REASON)`
while `admitted = error === null && refusalReason === null`. Two disjoint classes land in **neither**
partition:

1. a call returning a non-null `error` — and `allFulfilled` cannot see it, because supabase-js
   `.rpc()` resolves *fulfilled* with `{ data, error }`, so `r.status === "fulfilled"` is true;
2. a call that fulfils cleanly but carries a refusal reason that is not `HOURLY_REASON` — the daily
   cap, the kill switch, or any reason a later migration adds.

Either class reproduces the observed symptom exactly: with one of ten calls in either class, the DB
sees nine, admits K=5 and refuses 4, so `admitted === K` passes and `refused === N-K` fails with 4.
The same blind spot exists on the **ledger** side: `refusedRows(rows, HOURLY_REASON)` filters by
reason too, so a foreign-reason row is excluded from `refusedLedger` in the same way, and
`rows.length === N` is the only thing that catches it — while naming nothing. Both channels have to
be partitioned by *observed* outcome, or the fix is half applied. The current exact-equality
assertions are at
`byok-delegation.atomicity.tenant-isolation.test.ts` › `T5 — concurrency / FOR UPDATE /
no-TOCTOU-double-spend (partitioned)`, on `admitted`, `refused`, `passedRows.length`,
`spendOf(passedRows)` and `refusedLedger.length`.

What remains unknown, and must stay unknown in this plan: **which** error the one non-hourly call
carried. That datum lived in a CI run's output and the `diagIf` banner dumps
`pg_get_functiondef` rather than the error. No hypothesis about it is marked confirmed anywhere
below; Phase 4 builds the instrument that captures it on the next occurrence.

Suite facts: runner is vitest (`npm run test:ci` → `vitest run`), the `unit` project's
`include: ["test/**/*.test.ts", "lib/**/*.test.ts"]` collects the file, the `.tenant-isolation.test.ts`
suffix is load-bearing for the path filter, and the suite runs against the shared live dev Supabase
via `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`. `afterAll` deletes nothing (WORM rows; orphan
acceptance, sweeper deferred as #3934). The required aggregate's PASS clause is in
`scripts/tenant-integration-gate-verdict.sh`:
`if [[ "$detect" == "success" && ( "$suite" == "success" || "$suite" == "skipped" ) ]]`. The
workflow's `concurrency.group` is `tenant-integration-${{ github.ref }}` with
`cancel-in-progress: false`, so runs on **different** refs execute simultaneously against the same
dev project.

### Property List (Phase 0.6b)

1. A credentialed `curl` in a script that runs on an installed user's machine ignores that user's
   `~/.curlrc` and proxy environment.
2. A shell script that binds a live credential refuses to run under `xtrace`.
3. The Rule D suppression list contains only files that are still unremediated.
4. `betterstack-query.sh` never sends the ClickHouse read credential to a host outside the vendor's
   domain.
5. A test that needs a non-vendor host declares that host deliberately, and a test that forgets to
   declare it fails loudly rather than being silently permitted.
6. The BYOK concurrency test's exact-equality counts are reached only when all N calls actually
   reached the database.
7. No writer outside a delegation can move that delegation's hourly meter — demonstrated, not
   asserted.
8. A required check that passed because its suite was skipped says so.

### Cut List (Phase 0.6b)

| Mechanism the brief proposed | Property it would buy | Already covered by |
|---|---|---|
| Drive "the Rule D highwater" down alongside the baseline | 3 | Nothing — the artifact does not exist. The baseline file is the ratchet; growth is blocked by the repo-wide run itself, because a new offender is not in the baseline and so its violations are reported. **Cut: there is nothing to lower.** |
| Scope the delegation rows to a per-run unique tenant/workspace | 7 | `grantDelegation()` (fresh delegation per test) + `createSyntheticUser()` (fresh user and workspace per run) + the `delegation_id`-keyed meter in migration 137. **Cut: already on `main`, and was on `main` at the flaking commit.** |
| A boolean opt-in flag that re-permits arbitrary hosts | 5 | Nothing, but the shape is wrong: a boolean re-opens exactly the hole being closed. Replaced (not cut) by an equality declaration — see Phase 3. |

Property 7 survives the cut as a **demonstration** obligation rather than an implementation one:
the mechanism exists, the evidence that it works does not. That is what the null-change control is
for, and it is the reason the control is load-bearing rather than decorative here.

### Applicable institutional learnings

- `knowledge-base/project/learnings/workflow-patterns/2026-07-18-one-shot-collision-gate-misses-prose-ref-merged-prs.md`
  — a merged PR that cites an issue with prose `Ref #N` creates **no** GitHub link, so both
  `closedByPullRequestsReferences` and `gh pr list --search "linked:issue #N"` return empty and the
  work is invisible to the collision gate. Directly governs how this PR must record its #7898
  progress.
- `knowledge-base/engineering/architecture/decisions/ADR-206-attribute-a-prs-filings-by-the-prs-own-body.md`
  — bare prose mentions of an issue contribute to nothing; the PR body must carry a declared
  attribution line for the gates to read it.
- `knowledge-base/project/learnings/security-issues/2026-09-06-the-file-i-added-to-fix-a-p1-shipped-a-p1.md` — the
  `#7855` class: a destination allowlist compared with an unquoted glob accepted
  `https://evil.com/?x=.betterstackdata.com/`. Match the **extracted authority**, never the whole URL.
- `knowledge-base/project/learnings/2026-09-07-the-class-recurred-in-three-days-and-every-instrument-was-broken.md`
  — a guard's value is measured against the regression it must catch, never against a green tree;
  partitioning is vacuous when a partition can become a singleton that agrees with itself.
- `knowledge-base/engineering/operations/post-mortems/plugin-delivery-path-silent-staleness-postmortem.md`
  — a plugin executing on a user's machine is observability **layer 7**: there is no dashboard, and
  success-shaped failures have no detector by construction.
- `knowledge-base/engineering/architecture/decisions/ADR-193-anti-vacuity-floor-contract.md` — a
  floor reports with `printf >&2` + `exit 1` directly, never through the suite's own verdict
  helpers; the case counter increments at the call site, never inside `$( )`.
- `knowledge-base/engineering/architecture/decisions/ADR-179-bare-plugin-root-anchor-for-customer-facing-executables.md`
  — for customer-facing executables the anchor is the bare `${CLAUDE_PLUGIN_ROOT}`; a `:-` default
  is the vector, because unset it resolves into the customer's own tree.
- `knowledge-base/engineering/architecture/decisions/ADR-040-byok-delegations-resolver-and-grace.md`
  — the merged RPC does `SELECT FOR UPDATE` → grace → expiry → hourly SUM → daily SUM → audit INSERT
  in one transaction under one row lock, precisely to close the split-RPC TOCTOU at the cap boundary.
- `knowledge-base/project/learnings/2026-06-29-required-check-anchors-must-cover-verified-surface-not-inherited-paths.md`
  — once a path-filtered check is REQUIRED, a green result is an authoritative certification and its
  anchors become part of the contract.
- Rule bodies that bind here: `hr-observability-layer-citation` (a failure mode without a layer cite
  is rejected at plan-write time), `hr-verify-repo-capability-claim-before-assert`,
  `hr-weigh-every-decision-against-target-user-impact`, `cq-assert-anchor-not-bare-token`,
  `cq-cite-content-anchor-not-line-number`, `cq-ac-must-not-depend-on-concurrent-sessions`,
  `cq-test-fixtures-synthesized-only`, `wg-use-closes-n-in-pr-body-not-title-to`.

### ADR corpus

Grepped `knowledge-base/engineering/architecture/decisions/` for `--noproxy`, `--disable`, `curlrc`,
`7873`, `7898`, `credential forwarding`, `Rule D`: **no ADR decides this question**, so no rejected
alternative is being re-proposed and nothing needs amending. ADR-052 (container egress allowlist) is
the nearest host-allowlist precedent and contributes one caution — a hostname pin is not
automatically a full boundary. ADR-198 confirms `*.betterstackdata.com` is the real vendor domain
and records that the Better Stack **query** credential is team-scoped, with no per-source read
credential — which is why sending it to a substituted host is worth closing.

Ordinals: the local `decisions/` directory tops out at ADR-212; enumerating every pushed remote ref
shows 1–213 claimed with no gaps. **ADR-214 is the next free ordinal, and it is provisional** —
`/ship` re-verifies against `origin/main` before merge.

### Skill description budget

No `plugins/soleur/skills/*/SKILL.md` `description:` edit is candidate in this plan, so the Phase 1.8
budget check does not fire. (`plugins/soleur/skills/*/scripts/*.sh` are payload, not descriptions.)

### Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit 200` returned
64 issues; none of their bodies contains any path this plan edits (checked per-path with
`jq --arg path … contains($path)` over the 15 plugin scripts' directories, `scripts/betterstack-query.sh`,
`scripts/lint-shell-trace-credential-refusal*`, the BYOK test file, and
`.github/workflows/tenant-integration.yml`).

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality on `main` | Plan response |
|---|---|---|
| Rule D census is 80 files | 82 | Quote 82 → 67. The issue body's "67" becomes true by arithmetic; that is a coincidence of the count, not corroboration. |
| Drive the baseline "AND its highwater" down | No Rule D highwater exists; it was built and cut at review | Drop the highwater task. The baseline file is the ratchet. |
| §6 needs "an allowlist plus an opt-in seam in ~12 suites — a 13-file change" | 10 of 12 suites never reach the check at all | Allowlist + 2 test files. **No seam.** |
| Better Stack query host is `eu-fsn-3-connect…` (runbook) | Live Doppler value is `eu-central-1a-connect.betterstackdata.com` | Pin the apex, fix the runbook line. |
| #7055: scope the delegation rows to a per-run unique tenant/workspace | Already per-run unique at the flaking commit; the meter is keyed by `delegation_id` | Re-diagnose. The defect is an unpartitioned outcome channel. |
| `plugins/**` remediation is a Rule D change | A scoped run reports 15 Rule A violations too, and the advisory CI step bypasses the baselines | Fold Rule A in; draw down both baselines. |
| Five Resend host scripts are out of scope | One Resend script is in the D baseline | Still out of scope; no count is quoted in the PR body. |

## Problem Statement

**#7898 §5.** Fifteen scripts under `plugins/**` ship to installed users and run on their machines.
Every credentialed `curl` in them reads the user's `~/.curlrc` and honours their `HTTPS_PROXY` /
`ALL_PROXY` before it honours the host it was given. Among the credentials forwarded are
`SUPABASE_SERVICE_ROLE_KEY` (RLS-bypassing read/write over `users`, `conversations`, `messages`,
`api_keys`), `DOPPLER_TOKEN`, `FLAGSMITH_MANAGEMENT_API_KEY` and `CF_API_TOKEN`. This is the only
surface in the census where that config file and that environment belong to someone who is not us.

**#7898 §6.** `scripts/betterstack-query.sh` refuses userinfo, path and scheme smuggling in
`BETTERSTACK_QUERY_HOST` and accepts a wholly substituted bare host, then sends the ClickHouse read
credential to it as Basic auth on the first request.

**#7055.** A required check on `main` goes red intermittently because a concurrency assertion counts
outcomes by matching one expected string, so any other outcome is silently subtracted from the count
being asserted.

## Proposed Solution

Three slices, each ending in a state a command can verify.

**A — confine the shipped plugin scripts.** Add the Rule A xtrace-refusal prologue and the Rule D
`--disable` / `--noproxy '*'` prologue to all 15, add one real destination pin in
`provision-doppler.sh`, and remove the 15 from both baselines by hand.

**B — pin the Better Stack query destination.** Extract the authority and match
`*.betterstackdata.com`, following `scripts/betterstack-ingest-probe.sh`. No opt-in seam: the one
test arm that needs a non-vendor host shims `curl` instead, which exercises the guard rather than
skipping it.

**C — partition the BYOK concurrency outcomes and prove the isolation.** Keep every exact equality,
add no retries, add an explicit third partition on both the client and ledger channels, and add a
null-change control that measures the delegation-scoping the issue only assumed.

### The constraint a reviewer may hold this plan to

For slice C: **the exact-equality assertions stay.** `expect(admitted).toBe(K)`,
`expect(refused).toBe(N - K)`, `expect(passedRows.length).toBe(K)`,
`expect(spendOf(passedRows)).toBe(CAP_CENTS)` and `expect(refusedLedger.length).toBe(N - K)` are the
proof that the row lock held; a bound (`>= N - K`) would pass against an RPC that dropped the lock.
**No retry, re-run, or attempt budget may be introduced anywhere in this suite.** A retry would
convert a shared-state defect into an invisible one. If a phase below appears to require either,
the phase is wrong, not the constraint.

## Files to Edit

**The fifteen, written out** — the plan referred to "the 15 paths listed in the issue" and never
enumerated them, which left AC1 and AC2 with no executable form:

```text
plugins/soleur/skills/community/scripts/bsky-community.sh          # customer-facing (7)
plugins/soleur/skills/community/scripts/bsky-setup.sh
plugins/soleur/skills/community/scripts/discord-community.sh
plugins/soleur/skills/community/scripts/linkedin-community.sh
plugins/soleur/skills/community/scripts/linkedin-setup.sh
plugins/soleur/skills/community/scripts/x-community.sh
plugins/soleur/skills/community/scripts/x-setup.sh
plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh     # operator-only (8)
plugins/soleur/skills/flag-create/scripts/create.sh
plugins/soleur/skills/flag-delete/scripts/delete.sh
plugins/soleur/skills/flag-list/scripts/list.sh
plugins/soleur/skills/flag-set-role/scripts/flip.sh
plugins/soleur/skills/provision-doppler/scripts/provision-doppler.sh
plugins/soleur/skills/trigger-cron/scripts/trigger.sh
plugins/soleur/skills/user-set-role/scripts/set-role.sh
```

Also edited: `scripts/lint-shell-trace-credential-refusal-d.baseline.txt`,
`scripts/lint-shell-trace-credential-refusal.baseline.txt`,
`scripts/lint-shell-trace-credential-refusal.test.sh`, `scripts/betterstack-query.sh`,
`tests/scripts/test-betterstack-query-archive.sh`,
`tests/scripts/test-git-data-rung2-evidence-capture.sh`,
`scripts/tenant-integration-gate-verdict.sh`,
`tests/scripts/test-tenant-integration-gate-verdict.sh`,
`.github/workflows/tenant-integration.yml`,
`apps/web-platform/test/server/byok-delegation.atomicity.tenant-isolation.test.ts`,
`knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`.

Created: `knowledge-base/engineering/architecture/decisions/ADR-214-*.md`.

One free fix while in the file: `scripts/lint-shell-trace-credential-refusal.py`'s
`--write-baseline-d` argparse help says it rewrites "Rule D's baseline AND its highwater". No
highwater exists; the help text is a live lie and this PR is the natural place to drop that clause.
It is a help string, not classifier logic, so it does not breach the "do not touch the classifier"
constraint — but AC5 must be re-scoped from "the file is untouched" to "no predicate, regex or
baseline-loading logic is touched", and the diff must show only the help string moving.

## Implementation Phases

### Phase 0 — Preconditions (measure before editing)

0.1 Re-run the census so the drawdown arithmetic is against the tree being edited:
`python3 scripts/lint-shell-trace-credential-refusal.py $(grep '^plugins/' scripts/lint-shell-trace-credential-refusal-d.baseline.txt | tr '\n' ' ')`
— expect `42 violation(s) in 15 scanned file(s)`.

0.2 **The store this plan measured is not the store production reads, and that gap must be closed
with a canary rather than an argument.** Every production caller takes the host from
`secrets.BETTERSTACK_QUERY_HOST` — a GitHub Actions repository secret (`reusable-release.yml`,
`registry-zot-inventory.yml` x4, `registry-host-replace-dispatch.yml`,
`scheduled-zot-restart-loop.yml`, `scheduled-inngest-health.yml`, `apply-web-platform-infra.yml` x2,
`scheduled-followthrough-sweeper.yml`, plus ~25 followthroughs reading it from the env). The value
this plan measured came from Doppler `soleur/prd_terraform`. Confirming that every consumer reads the
same *name* is not confirming the same *value*, and the Actions value is unreadable by construction.

Two facts narrow the residual risk, and both should be stated rather than left to be re-derived: any
value that works today is already a bare `host[:port]`, because the existing shape `case` refuses
everything else; and both candidate hostnames — the runbook's `eu-fsn-3-connect…` and Doppler's
`eu-central-1a-connect…` — match `*.betterstackdata.com` after the port strip. So the only value that
breaks is a bare host outside the vendor apex.

Close it anyway: before merge, `workflow_dispatch` one cheap followthrough that exercises the query
path on this branch and confirm it still returns rows. A canary against the real store beats a
measurement of a different one. Blast radius if skipped and wrong: every one of those workflows exits
2 simultaneously, post-merge, with a message that reads like operator misconfiguration.

0.3 Confirm no plugin skill documents a `bash -x` debug path that the xtrace prologue would break.
Measured: none does — `plugins/soleur/skills/cf-token-scope/SKILL.md` › the `--dry-run` paragraph
states the script "runs no `set -x`", which the prologue reinforces.

0.4 Re-derive the free ADR ordinal across every pushed ref, not `origin/main` alone. Measured at
plan time: enumerating `refs/remotes/*` shows ADR-213 as the highest claimed and the local directory
tops out at ADR-212, so **ADR-214** is free. It is written provisionally; `/ship` re-verifies before
merge.

0.5 ADR-179 anchor form: checked and **compliant** — every `${CLAUDE_PLUGIN_ROOT}` invocation in the
nine owning `SKILL.md` files uses the bare, quoted form. A grep for `CLAUDE_PLUGIN_ROOT:-` does
return one hit in `plugins/soleur/skills/community/SKILL.md`, but it is the sentence *documenting*
that the rejected `:-` default is not used. That is the `cq-assert-anchor-not-bare-token` class in
miniature: a body-grep sees prose, so the documentation of a banned pattern satisfies a search for
the pattern. Anyone re-running this check should read the hit, not count it.

### Phase 1 — Slice B: pin the Better Stack query destination

1.1 In `scripts/betterstack-query.sh`, replace the shape-only `case` with authority extraction then
an allowlist, mirroring `scripts/betterstack-ingest-probe.sh` line-for-line in structure: strip a
path, then a query, then a fragment, then userinfo, then an explicit port, and match the **isolated
host** against `*.betterstackdata.com`. Matching the whole value with a glob is the #7855 defect —
a shell glob's `*` crosses `/` and `?`, which is how `https://evil.com/?x=.betterstackdata.com/` was
accepted. Keep the existing shape arms as a first, cheaper refusal; the allowlist is the pin.

1.2 Rewrite the comment block above it so it states the pin that now exists rather than the residual
that no longer does, and so it names the sanctioned way for a test to exercise the egress path
(shim `curl`), instead of forecasting a seam this plan deliberately does not build.

1.3 `tests/scripts/test-betterstack-query-archive.sh` — change the stub host to a vendor-shaped one
at **all three** sites (`capture_sql`, `run_with_failing_curl`, and the inline `out_rc=$(...)` case);
"change the stub host" is three edits, not one. `curl` is already shadowed as a shell function
there, so nothing dials and the behaviour is unchanged.

1.4 `tests/scripts/test-git-data-rung2-evidence-capture.sh` — add a `curl` shim on `PATH`
(precedent: `scripts/compound-promote.test.sh` › `make_mock_curl()`, which writes the payload to a
capture file) and a vendor-shaped host. **Two things the first draft got wrong here.**

First, it is not "the one arm": the Mode-1-against-the-real-transport section is a *loop* over
`"$_seen"/*.sql` behind a positive-work floor, **plus** a separate verify-the-verifier call — two
invocation sites, both with `BETTERSTACK_QUERY_HOST=127.0.0.1` and real `curl`. Both need the shim
and the host.

Second, and worse: **the allowlist preempts the exit code that arm discriminates on.** Its whole
assertion is `[[ $? -eq 64 ]]`, and 64 comes from flag parsing and archive-table derivation — both
*below* the host `case`. Adding the allowlist makes `127.0.0.1` exit 2 at the host check before the
SQL shape is examined, so `_rejected` stays empty and the loop **passes vacuously** while claiming
"all N queries the SUT builds are admitted as Mode 1 SQL by the real transport". Only the
verify-the-verifier row would go red. Guard 2 needs a row pinning that the refusal must not swallow
the exit-64 discrimination, or the next reviewer re-breaks exactly this coupling.

Leave the other arms alone: they never reach the check.

1.5 Extend the suite with the guard's own cases — see `## Guard Contract` Guard 2.

### Phase 2 — Slice A: confine the fifteen shipped scripts

2.1 For each of the 15, add the xtrace-refusal prologue as the first thing after `set …`. The linter
emits the exact block per file, including which credential names the arm must guard — take its
output as the starting point rather than hand-writing, so the Rule C coverage limb is satisfied by
construction. Three deliberate deviations from the emitted text:

- **Use the conditional arm for the seven community scripts, and the UNCONDITIONAL arm for all
  eight operator scripts — including `provision-doppler.sh`, where the linter offers a conditional
  one that would fail OPEN.** An earlier draft said "use the conditional arm wherever the linter
  offers one" and justified it with "the eight operator scripts acquire credentials at runtime, so
  Rule C forces the unconditional form there". **That was a pattern-match, not a measurement, and it
  was wrong.** Classifying the linter's own emitted blocks gives **8 conditional / 7 unconditional**,
  and the split does not align with customer-facing / operator-only: the eighth conditional is
  `provision-doppler.sh`.

  That one matters, because its conditional guard is **vacuous by construction**.
  `provision-doppler.sh` acquires the operator's workplace-scoped Doppler personal token with
  `read -rs -p "Doppler personal token: " DOPPLER_TOKEN` — *after* the prologue runs. So
  `${DOPPLER_TOKEN:+x}` is empty at guard time, the arm opens, and `bash -x` proceeds to print
  `Authorization: Bearer dp.pt.…` at the three call sites. The linter cannot see this: its `ACQUIRES`
  set knows `doppler secrets get`, `gh auth token` and `_TOKEN="$(`, and does not know `read -rs`, so
  `unconditional_reason` returns `None` and Rule C is satisfied by a guard that never fires. **AC1
  (the linter exits 0) passes over this defect** — which is precisely why the plan states it rather
  than relying on the gate.

  Rule: the seven community scripts get the conditional arm (each gates on an env credential its own
  `check_creds` already requires, so it cannot fail open there, and a founder running `bash -x` with
  no token set keeps full tracing). The eight operator scripts get the unconditional arm. The
  `read -rs` gap in `ACQUIRES` is filed separately — AC5 forbids touching the classifier in this PR.
- **Emit the refusal on stdout, not stderr.** The linter's suggestion string uses `>&2`, but
  `knowledge-base/project/constitution.md` › Code Style › Always requires operator-protection signals
  on stdout: agent runtimes surface stdout and swallow stderr, and the gdpr-gate banner is the cited
  reference implementation. A security refusal the harness swallows leaves the user with `exit 78`
  and no text — materially worse than no refusal, because it reads as an unexplained failure.
  **There is no conflict with Rule A, and this was settled by running the linter rather than by
  reasoning:** a synthesized fixture carrying the canonical `case "$-" in *x*)` block with the
  `printf` on stdout was scanned and returned `OK: 1 scanned file(s), 0 baselined (A/B/C), 0 baselined
  (D)`. Rule A matches the refusal's shape, not its stream.
- **Rewrite the message for the seven customer-facing scripts, from one literal template.** The
  canonical text says "this probe handles live credentials" and cites an internal issue number; the
  user invoked `/soleur:community`, not a probe. `knowledge-base/marketing/brand-guide.md` › Voice ›
  Tone Spectrum requires error messages to be honest *and actionable*.

  A single worked example is not enough here, because the seven differ in credential arity and the
  refusal arm is `-n` over a **concatenation** of `:+x` expansions. Measured from the linter's own
  emitted arms: `bsky-community`, `bsky-setup` and `discord-community` guard 1 credential each;
  `linkedin-community` and `linkedin-setup` guard 2 each; `x-community` and `x-setup` guard 4 each.
  So "unset DISCORD_BOT_TOKEN and re-run" does not generalise — a founder who unsets three of X's
  four still gets `exit 78` with nothing telling them which one remains.

  Use this template verbatim, substituting each file's own guarded list:

  > Refusing to run under `bash -x`: <VAR1>, <VAR2>, … are set, and tracing would print them to your
  > terminal. To trace safely, unset all of them and re-run.

  The remedy must enumerate **every** variable that file's arm tests, not one of them. Keep the
  terse operator wording on the eight operator-only scripts.

2.2 For each credentialed `curl`, make `--disable` the literal first argument and add
`--noproxy '*'`. Position is load-bearing for `--disable` only.

2.3 In `plugins/soleur/skills/provision-doppler/scripts/provision-doppler.sh`, **hoist the multi-line
`-d "{…}"` payloads into variables. That is the remediation.**

An earlier draft said the opposite — "add a `readonly DOPPLER_API_PINNED` equality refusal
unconditionally; the pin is the fix, the hoist is cosmetic" — on the reasoning that satisfying a
tokenizer is the mirror image of baselining a correct file. **Two reviewers falsified that by running
the linter on real copies of the file**, and the result is unambiguous:

| Variant applied to the real file | Linter |
|---|---|
| transport flags + xtrace refusal + `readonly DOPPLER_API_PINNED` + inequality refusal, multi-line payload **retained** | **1 violation — still red** |
| transport flags + xtrace refusal + payload **hoisted**, no pin at all | `OK: 1 scanned file(s), 0 baselined` |

The mechanism: `_adjudicated(var, body)` is called with `var = "DOPPLER_TOKEN"` — the variable the
tokenizer mistook for the destination — and `_pin_re` / `_compared_to_literal_const` both require
`$DOPPLER_TOKEN` itself on one side of the comparison. A constant named `DOPPLER_API_PINNED`
adjudicates a *different variable* and is invisible to the check. There is no pin-shaped remediation
available here, because "pinning `DOPPLER_TOKEN`" would mean comparing a secret to a literal.

So the honest framing, which the plan should carry rather than the reasoning it replaced: **this call
site has no env-settable destination at all.** The URL is the literal
`https://api.doppler.com/v3/workplace/service_accounts/${SA_SLUG}/identity`, and `SA_SLUG` is
assigned from the previous response and adjudicated. The finding is a parse artifact of the
multi-line `-d` payload, and hoisting the payload removes the artifact by making the invocation
single-shaped. Hoisting changes the **script**, not the classifier, so it does not narrow the guard —
which is the distinction that matters and the one the earlier draft blurred.

Do **not** add the `readonly DOPPLER_API_PINNED` constant. It buys nothing the linter recognises,
and a constant that looks like a pin while pinning nothing is worse than no constant: the next reader
takes it for a destination check. (Placement would also have been wrong —
`PROLOGUE_ALLOWED` is `^\s*(?:set|shopt|readonly\s+-\w+)\b`, i.e. `readonly -r`-style flags, so a bare
`readonly NAME=value` above the refusal counts as a prologue command against `PROLOGUE_MAX_CMDS = 0`
and reddens Rule A.)

2.3b The manual-fallback block in the same script `echo`s copy-paste instructions containing an
unconfined `curl -sS -X POST … -H 'Authorization: Bearer $DOPPLER_TOKEN'`. These are strings, so the
linter never sees them and the census is unaffected — but a script that *teaches* the unconfined form
directly undercuts the decision ADR-214 records. Update those printed recipes to carry
`--disable --noproxy '*'` too.

2.4 Draw both baselines down **by hand**, removing exactly the 15 lines from
`scripts/lint-shell-trace-credential-refusal-d.baseline.txt` (82 → 67) and the same 15 from
`scripts/lint-shell-trace-credential-refusal.baseline.txt` (118 → 103, `plugins/` entries 20 → 5).
Do **not** run `--write-baseline-d`: it rewrites the entire file from a full-tree scan, which would
silently re-baseline anything that has drifted in since the file was last written — a drawdown that
quietly becomes a regression.

2.5 **Give the seven community scripts a proxy-aware failure line.** This is the one thing the
plan adds beyond confinement, and it is the most likely real-world consequence of shipping.
`--noproxy '*'` removes the only egress path an enterprise-managed machine has, and every
credentialed curl in the seven is invoked as `$(curl … 2>/dev/null)` — so curl's own diagnostic is
discarded and replaced by a Soleur-authored line that **blames the founder's connectivity**:
`x-community.sh` › "Error: Failed to connect to X API." / "Check your network connection and try
again.", and the same shape in `bsky-community.sh` and `discord-community.sh`. Shipping the flag
without this turns a deliberate bypass into a message that misattributes its own cause.

On a credentialed-curl failure, when any of `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` is non-empty,
print a proxy-specific line instead: name the deliberate bypass, name why it exists, and name the
remedy. Something of the shape — "This request deliberately bypasses your proxy
(`HTTPS_PROXY=…`), because a proxy can redirect a request carrying your platform token. If you need
Soleur to reach <platform> through your proxy, that is not currently supported — please open an
issue." Honest about the trade rather than blaming the network.

**Beside the human line, emit one structured marker on stdout.** A reworded English sentence is not
a detector: on the hosted path the only artifact would be prose inside tool stdout, and on the
customer path nothing survives the session. The marker is what
`agent-runner-query-options.ts`'s always-on `PostToolUse` Bash extractor mirrors to the server logger
and a Sentry breadcrumb, and it is simultaneously the layer-7 in-session signal. Exemplar in the same
tree: `plugins/soleur/skills/git-worktree/scripts/git-repo-readiness-diag.sh` ›
`SOLEUR_GIT_REPO_DIAG`.

Its fields must discriminate all four competing causes **in one event**, or the operator cannot tell
them apart: `surface` (`installed-cli` | `in-sandbox`), `script`, `curl_exit`, `refusal` (78 versus a
curl failure), `proxy_env` (which of `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` / `NO_PROXY` were
non-empty), `curlrc_present` (`$HOME/.curlrc`), `noproxy_applied`. Without `proxy_env` and
`curlrc_present` specifically, "`--noproxy` cut a proxy the caller needed" is indistinguishable from
"`--disable` dropped a curlrc it relied on" from "xtrace refusal" from "ordinary network failure" —
which is the whole diagnostic question this change creates.

Note the interaction with the existing `2>/dev/null` on every one of those call sites: the marker
goes to **stdout**, so the suppression does not swallow it. Do not remove the `2>/dev/null` — it is
what keeps curl's own stderr (which can carry the URL) out of the transcript.

2.6 Re-run the scoped census; it must report `OK`.

### Phase 3 — Slice C: partition the outcomes, then measure the isolation

3.1 In `byok-delegation.atomicity.tenant-isolation.test.ts` › `T5`, partition by *observed* outcome
into **five** disjoint classes, and partition **`settled`, not `results`**.

The fifth class is not padding. `@/server/cost-writer` › `readRefusalReason` returns a three-arm
union — `{kind:"admitted"} | {kind:"refused";reason} | {kind:"unreadable";detail}` — and the test's
`readRefusalReasonLive` wrapper **throws** on the `unreadable` arm, deliberately, because production
is fail-closed. `recordUse` calls it un-caught, so an unreadable PostgREST payload makes the promise
**reject**, and `Promise.allSettled` yields `status:"rejected"`. The existing
`results = settled.map(r => r.status === "fulfilled" ? r.value : null)` then puts `null` into the
array. Partitioning `results` gets this wrong either way: `r?.error !== null` classifies `null` as
**errored** and prints `undefined` for both code and message — a partition naming an outcome it did
not observe — while `r !== null && r.error !== null` drops it into **no** class, falsifying Guard 3's
own "the classes sum to the total". A degraded pooler returning a short or empty payload is exactly
the condition this suite creates, so this is a live candidate for the flake, not a theoretical arm.

The five classes: **rejected** (`status === "rejected"`), **errored** (`error !== null`),
**refused-hourly**, **refused-other**, **admitted**. Assert
`rejected.length === 0` (naming `r.reason.message`), `errored.length === 0` and
`refusedOther.length === 0` **first**, each failure text carrying the offending entry's code and
message. Assert the classes sum to N. Retain the existing `allFulfilled` assertion ahead of them.
Then leave `admitted === K` and `refused === N - K` exactly as they are.

3.2 Do the same on the ledger channel: partition `rows` into reason-`NULL`, reason-hourly and
reason-other, and assert the third is empty. `refusedRows(rows, HOURLY_REASON)` filters by reason,
so a foreign-reason row is excluded there in precisely the way the client-side filter excluded it.

3.3 Fold both new partitions into `willFail` **before** `await diagIf(willFail)` is evaluated, or the
new assertions ship without the diagnostic banner, which is most of their value.

3.4 Add the null-change control as a new `test(...)` in the same file (so the existing path filter
and the `.tenant-isolation.test.ts` suffix already cover it, and no new CI job is created):

**The control is SEQUENTIAL, not concurrent — and that is the design's load-bearing choice.** Two
reviewers converged on the same defect in the first draft, which drove A's and B's calls together in
one `Promise.allSettled`: a control built that way adds a second concurrent fan-out, two more
synthetic users and ~5 more overlapping transactions to *the very suite being repaired for going red
intermittently*. If contention is what reddens T5, a concurrent control raises the rate of the thing
it is meant to help. Concurrency was never required: the property is
`WHERE au.delegation_id = p_delegation_id`, an equality on a primary key, and an equality does not
need two writers to be simultaneous to be tested. Sequential is both cheaper and strictly more
deterministic.

- Mint delegation **A** at `CAP_CENTS` and a sibling delegation **B** under the *same grantor and the
  same workspace*, at a cap with genuine headroom (`B_CAP = M * COST_CENTS`, so all M of B's calls
  are admitted and no arithmetic is left implicit).
- **Step 1 — the outside writer runs first, alone.** Drive B's M calls to completion. **Positive
  control:** B's admitted count is exactly M. Without this the control is vacuous — a B that refuses
  for its own reasons never writes, and the negative control below would then pass by doing nothing.
- **Step 2 — then drive A's N calls,** exactly as T5 does. **Negative control:** A's admitted count
  is exactly K, A's refused count exactly N−K, and A's ledger holds exactly N rows — unchanged by
  B's M committed rows sitting in the same table, under the same workspace and the same grantor,
  inside the same rolling hour.
- **Discriminative power** is carried by Guard 3's mutation row (point B at A's delegation id and the
  negative control must go red), not by a third assertion inside the test body. The first draft's
  third row — "M additional calls against A *do* move A's count" — was also ill-defined: A is pinned
  at `CAP_CENTS`, so it has no headroom and extra calls all refuse, making "move A's count" ambiguous
  about which count. Dropped rather than patched.
- Do **not** carry T5's pooler-serialization limitation banner onto this control: T5 needs genuine
  overlap for its lock proof and therefore inherits that caveat, and this control does not overlap at
  all. Copying the banner would claim a limitation it does not have.

**Three preconditions on B that are not optional, and that the first draft left unstated.**
`064_byok_delegations.sql` › `byok_delegations_active_triple_uidx` is unique on
`(grantor_user_id, grantee_user_id, workspace_id) WHERE revoked_at IS NULL`, and
`grant_byok_delegation` has no `ON CONFLICT`. So B is legal **only** because `grantDelegation()`
mints a fresh grantee per call — not because it shares the grantor and workspace, which is what makes
it a sibling. Additionally: `addMember(grantor.workspaceId, granteeB.id)` must run first or the
`byok_delegations_same_workspace` trigger raises `byok_delegations:cross-tenant`; and B's cap must
satisfy `byok_delegations_hourly_le_daily`. `addMember` failing is loud (it ends in
`expect(error, …).toBeNull()`), but it fails **after** B's user, org, workspace and membership rows
already exist and `afterAll` deletes nothing — so a failed run still grows the #3934 population — and
it surfaces with no `diagIf` banner, because Phase 3.3 wires the banner into T5's `willFail` only.
Wire a banner into the control too.

**What the control must additionally record, because it is the genuinely interesting finding.**
Migration 137 carries a *second* meter, and it does not have this property.
`record_byok_use_and_check_cap` — the founder-cap sibling of the delegation RPC — sums
`WHERE founder_id = p_founder_id AND attribution_shift_reason IS NULL AND ts > now() - interval '1 hour'`,
with **no delegation filter**. Both A's and B's admitted rows carry `founder_id = grantor.id`, so B's
traffic *does* pool into A's founder-scoped hourly meter even though it cannot touch A's
delegation-scoped one. Property 7 is therefore true of the RPC under test and false of its Layer-1
sibling. The control asserts the delegation-scoped isolation and **states the founder-scoped pooling
in a comment beside it**, so the next reader does not generalise "delegations are isolated" past the
predicate that makes it true. Whether the founder-scoped pooling is a defect is out of scope here;
naming it is not.

Cost: one extra delegation, one extra synthetic user (plus the org, workspace and membership rows
that `handle_new_user` creates for it — a different residue class from the WORM `audit_byok_use`
rows the file's banner already accepts), and roughly 15 additional round-trips once B's
`grantDelegation` and the second `auditRowsFor` are counted, not the ~5 an earlier draft claimed.
All sequential, adding **no** concurrent load. Timeout is not at risk: every `test(` in the file
carries its own `120_000`, tests run serially, and T5 today is ~15 round-trips.

### Phase 4 — make the skipped-first-execution visible

The suite was skipped on the PR preceding the failure, so its first execution against that tree was
the post-merge push to `main`. Widening the path filter is **rejected**: the preceding PR touched
`apps/web-platform/scripts/` and markdown, genuinely unrelated to this surface, and per
`2026-06-29-required-check-anchors-must-cover-verified-surface-not-inherited-paths` anchors must
cover the verified surface — not everything, which would run a heavy live-DB suite on every PR.

What is cheap and honest instead: `scripts/tenant-integration-gate-verdict.sh` already distinguishes
the two PASS arms in its stdout, but the check reports the same green either way. On the `skipped`
arm, additionally emit a `::notice::` and a `$GITHUB_STEP_SUMMARY` line saying the heavy suite did
not execute against this tree and that its first execution will therefore be post-merge on `main`.
Extend `tests/scripts/test-tenant-integration-gate-verdict.sh` with rows for both PASS arms.

Retrofitting an ADR-193 anti-vacuity floor to that suite — which it lacks — is a fine change and
belongs to neither issue. **File it; do not absorb it here.**

### Phase 4b — the part of #7055 the partition does not fix

State this plainly, because the plan would otherwise over-claim. **Partitioning the outcomes does not
lower the rate at which T5 goes red.** It converts a bare `expected 5, received 4` into a named
failure carrying the code and message of the outcome that did not fit. That is a large gain in
diagnosability and no gain in frequency, and #7055 is labelled `flaky`. A change that only improves
an error message cannot honestly close a flake ticket.

The plan's own research contains the most plausible cause and it is not in the test file:
`.github/workflows/tenant-integration.yml` › `concurrency.group` is
`tenant-integration-${{ github.ref }}` with `cancel-in-progress: false`. Per-ref grouping means two
runs on **different** refs — another PR, or a PR and the push to `main` — execute the suite
simultaneously against the same shared dev Supabase project. T5 opens ten concurrent transactions
queueing on one row's `FOR UPDATE` through a shared pooler; a second run doing the same thing at the
same moment is exactly the condition under which one of the ten returns a pooler timeout or a
serialization failure instead of the hourly refusal.

So Phase 4b changes the concurrency group to a **ref-independent** constant, serializing the suite
across the whole repository, keeping `cancel-in-progress: false`.

Two honesty constraints on this, both binding:

1. **This is the most plausible cause, not a confirmed one.** The deciding datum — which error the
   one non-hourly call actually carried — lived in a CI run's output and is gone. Nothing in this
   plan may mark it CONFIRMED. Phase 3 is the instrument that captures it on the next occurrence;
   Phase 4b removes the leading environmental candidate at near-zero cost. If a red recurs after
   this ships, it arrives with the outcome named, which is the datum that reopens the question
   properly.
2. **Name the cost.** A repo-wide group serializes tenant-integration runs, so concurrent PRs that
   touch this surface queue rather than overlap. With `cancel-in-progress: false` a queue can form.
   The suite is path-filtered and fires only on `server/`, `migrations/`, `lib/supabase/`,
   `middleware.ts` and the isolation tests, so the population that queues is small — but if queueing
   proves worse than the flake, the revert is one line, and that is the reason to prefer this over
   provisioning a second Supabase project for the suite.

Together, Phase 3 (name the failure) and Phase 4b (remove the leading cause) are what justify
`Closes #7055`. Phase 3 alone would not.

### Phase 5 — record the decision and reconcile the artifacts

5.1 Write **ADR-214** (ordinal provisional) via `/soleur:architecture`.

5.2 Correct the stale query host in
`knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` › the "Query host" bullet.

5.3 Reconcile `model.c4` — see `## Architecture Decision (ADR/C4)`.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| `BETTERSTACK_QUERY_HOST_TEST_PIN=<exact host>` opt-in seam (an equality declaration rather than a boolean) | The threat model is env control over `BETTERSTACK_QUERY_HOST`. Anyone who can set that variable can set the declaration to the same value in the same breath, so the seam is a complete bypass available to precisely the actor it defends against. It buys "fails loud on accidental misconfiguration", which vendor-shaped stubs give for free. Measured need: one test arm, which a `curl` shim covers while *exercising* the guard. |
| A boolean opt-in flag re-permitting arbitrary hosts | Same objection, and strictly worse: it re-opens the exact hole the slice closes. |
| Change all 12 suites' stub values | 10 never reach the check at all, and an eleventh reaches it only through a `curl` shim that never dials. Changing them would be churn that reads as coverage. |
| Weaken the concurrency assertion to `refused >= N - K` | Explicitly excluded. A bound passes against an RPC that dropped the `FOR UPDATE` lock, which is the only thing the test exists to prove. |
| Add a retry or re-run budget to the concurrency test | Explicitly excluded. It would hide the defect rather than fix it, and the defect is real and reproducible in shape. |
| Scope the delegation rows to a per-run unique tenant/workspace | Already the state of the code, and was at the flaking commit. Implementing it would be a no-op presented as a fix. |
| Drive a "Rule D highwater" down | No such artifact exists. |
| Run the null-change control from a genuinely separate writer process | Adds scheduling nondeterminism and a second flake source to prove a property of a SQL `WHERE` clause. The concurrent calls in one `allSettled` already produce overlapping DB transactions — the same mechanism T5 relies on. |
| Widen the `tenant-integration` path filter so the suite always runs | Runs a heavy shared-live-DB suite on every PR to catch a timing artifact; contradicts the verified-surface anchoring rule. |
| Fix Rule D only and leave Rule A | The advisory `--changed` step bypasses both baselines, so it would be red on all 15 touched files — which trains readers to ignore it, the same cost #7055 is filed about. |
| **Extract a shared sourced `curl` prologue helper instead of repeating it 15 times** | **This would vacate the guard.** `CURL_INVOKE = re.compile(r"(?:^\|[\|;&(\`$]\|\s)(?:[\w./-]*/)?curl(?:\s\|$)")` requires start-of-line, whitespace, or one of `\| ; & ( \` $` before `curl`. A helper invoked as `bs_curl -u …` has `_` in front, so it is **not recognised as a curl command at all** — `check_rule_d` would report zero violations across all 26 sites and both baselines would draw down to `OK` because the walker went blind, not because the transport was confined. That is the same "satisfy a tokenizer rather than pin a destination" failure Phase 2.3 rejects, one level up and repo-wide. The flags are per-call-site by construction anyway (the linter's `_curl_commands` notes flags cannot cross a pipeline: they must be on the invocation itself). This is the registered principle **AP-025** — enforce with a self-refusal the artifact *carries*, gated by a walker over every member, not with a helper that must be reached. Repetition ×15 **is** the principle. Secondarily, introducing a `source` would import ADR-179's anchor-plus-identity-preflight obligation into 15 customer-facing executables that reference `CLAUDE_PLUGIN_ROOT` nowhere today. **Recorded explicitly so a later DRY pass does not silently vacate the drawdown with a smaller diff and a green linter.** |
| Split A+B and C into two PRs (CTO recommendation) | Recorded and surfaced rather than adopted: the one-shot batching is deliberate. Mitigated by ordering C last so it can be dropped without unpicking A or B. |

## User-Brand Impact

**The fifteen files are two populations, and the brief's framing ("one user's project key — a
single-user incident") holds for only one of them.** Verified by reading where each script obtains
its credentials:

- **Seven customer-facing**, named literally rather than by glob:
  `community/scripts/bsky-community.sh`, `bsky-setup.sh`, `discord-community.sh`,
  `linkedin-community.sh`, `linkedin-setup.sh`, `x-community.sh`, `x-setup.sh`. These read the
  *user's own* Bluesky, Discord, LinkedIn and X tokens from the user's environment. The glob
  `{bsky,discord,linkedin,x}-*.sh` an earlier draft used is **wrong**: it also matches
  `discord-setup.sh`, which is not among the fifteen — see the blind spot below.
- **Eight operator-only** — `cf-token-scope`, `flag-create|delete|list|set-role`, `provision-doppler`,
  `trigger-cron`, `user-set-role`. Every one is hard-wired to Jikigai's own infrastructure:
  `set-role.sh` › the credential block reads `SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd`,
  the flag scripts read `FLAGSMITH_MANAGEMENT_API_KEY -p soleur -c cli_ops`, `trigger.sh` posts to
  `https://app.soleur.ai/api/internal/trigger-cron`, and `provision-doppler.sh` prompts for the
  operator's own Doppler personal token. No customer ever holds these.

The linter corroborates the split without being asked: it emits the *conditional* refusal arm
(`if [ -n "${BSKY_APP_PASSWORD:+x}" ]`) for the seven env-credential scripts and the *unconditional*
one-liner for the eight that acquire credentials at runtime via `doppler secrets get`.

- **If this lands broken, the user experiences:** `/soleur:community` — the Bluesky, Discord,
  LinkedIn or X post, digest, or setup flow — fails on their own machine, either as an `exit 78`
  refusal or, if `--noproxy '*'` cuts a proxy they legitimately need, as
  `Error: Failed to connect to X API. / Check your network connection and try again.` Note the
  correction: an earlier draft said the user would see "a bare curl connection error with no
  Soleur-authored explanation". The opposite is true and worse — every credentialed curl in the seven
  runs as `$(curl … 2>/dev/null)`, so curl's real diagnostic is discarded and a Soleur-branded line
  **misattributes the cause to the founder's network**. Phase 2.5 is the mitigation.
  Separately, the eight operator-only skills are advertised in the installed roster and on the public
  docs site, so a customer *can* invoke them. Today they fail with an actionable `exit 2`
  ("missing Supabase secrets in `soleur/prd`"). After this change, a customer invoking one under
  xtrace gets `exit 78` and a refusal asserting their machine holds a live credential — which is
  false, since they hold none of these. The message and the exit code both change on a path a
  customer can reach.
- **If this leaks, the user's data is exposed via:** their own `~/.curlrc` or
  `HTTPS_PROXY`/`ALL_PROXY` re-pointing a credentialed `curl` in `community/scripts/*.sh`, sending
  their social-platform tokens to a third party — blast radius is takeover of the founder's own
  Bluesky, Discord, LinkedIn and X presence and the ability to post as them. **Separately and more
  severely:** the identical defect on the eight operator scripts forwards *Jikigai's*
  `SUPABASE_SERVICE_ROLE_KEY` for `soleur/prd`, which bypasses RLS across `users`, `conversations`,
  `messages` and `api_keys` — every row of every Soleur customer — plus the Flagsmith management
  key, the Cloudflare API token and the Inngest trigger secret. The exposure is invisible to us in
  both halves: these scripts execute on someone else's machine (observability layer 7), and a
  forwarded request that succeeds is indistinguishable from a correct one.
- **Brand-survival threshold:** `single-user incident` — and read the scope note, because the label
  understates this one. The enum recognised by the gates is `single-user incident | aggregate pattern
  | none`; there is no higher value, and `aggregate pattern` means a pattern accumulating across
  users over time, which is a different shape, not a more severe one. The customer-facing seven are a
  true single-user incident. The operator-only eight put Soleur's production service-role key on an
  unconfined transport, so one compromised operator environment exposes **every** customer's rows in
  a single event. The declaration is pinned to the enum value that engages the escalation — CPO
  sign-off at plan time and `user-impact-reviewer` at review time — both of which are already engaged
  here. An earlier draft wrote `all-users incident`, which is more accurate as prose and invalid as a
  token: preflight Check 6 matches the value as a discrete token against that three-value enum, so it
  would have failed the ship-time gate.

### Two neighbours the fifteen do not cover

Both are customer-facing, both are reachable from `/soleur:community`, and neither is in the Rule D
baseline — so remediating the fifteen leaves them exactly as they are. Named here rather than left
to be assumed closed:

- **`community/scripts/community-router.sh`** leaks all seven of the founder's platform credentials
  under xtrace. Its `check_auth` does `[[ -n "${!var:-}" ]]` — indirect expansion inside a test — so
  `bash -x` prints `+ [[ -n <the actual bot token> ]]`. This is the exact `EXPANDING_IN_ARM` shape
  the linter's own comments record. It is suppressed by file in the A/B/C baseline and carries no
  Rule D violation, so it is invisible to this PR's drawdown — yet `community/SKILL.md` makes it the
  **first command of every `/soleur:community` sub-command**, which makes it the most-run
  customer-facing file on the surface this section enumerates.
- **`community/scripts/discord-setup.sh`** sends `DISCORD_BOT_TOKEN_INPUT` through an unconfined
  curl. Rule D never sees it because `CREDENTIAL_NAME` matches
  `_(TOKEN|KEY|SECRET|PASSWORD|PAT)` at a word boundary and the `_INPUT` suffix defeats it — so the
  file has zero violations and never entered the baseline. Worse, the Rule A arm the linter *would*
  emit for it guards `${DISCORD_BOT_TOKEN:+x}`, a different variable bound only much later when
  writing `.env`, so the guard would open while `DISCORD_BOT_TOKEN_INPUT` is live.
  `community/SKILL.md` tells a first-run founder to run this script.

Both are **out of scope for this PR** and tracked as follow-ups (see Non-Goals). The reason is
scope discipline, not severity: each needs a hand-written guard rather than the linter's emitted
block, and `discord-setup.sh` additionally exposes a classifier blind spot that AC5 forbids fixing
here. Naming them is what stops the next reader concluding that "the `plugins/**` section of #7898
is closed" means this surface is confined.

### The hosted path

`plugins/soleur` is not only a customer artifact. `.github/workflows/web-platform-release.yml` sets
`vendor_plugin: true`, and `apps/web-platform/Dockerfile` › `COPY _plugin-vendored /opt/soleur/plugin`
puts the same files inside the production image, so they also execute hosted. Per the layer-7
doctrine in `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`, a plan
citing layer 7 for a file that also runs hosted must say what covers the hosted path — "it lives
under `plugins/`" is explicitly not an answer.

An earlier draft claimed both flags were **no-ops** on that path, on the strength of a grep over
`apps/web-platform/infra/`, `apps/web-platform/Dockerfile` and `web-platform-release.yml` finding no
proxy variable and no `curlrc`. **That claim is false, and the grep could not have detected its
falsity** — the mechanism is code, not config. `apps/web-platform/server/agent-env.ts` ›
`AGENT_ENV_ALLOWLIST` forwards `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `http_proxy`, `https_proxy`,
`no_proxy` **and `HOME`** into the agent subprocess that executes the vendored skills, and that file
is explicit that omission from the allowlist is how a variable gets blocked — so inclusion is a
deliberate grant. A grep scoped to Terraform, a Dockerfile and a workflow returns nothing while the
pass-through sits in TypeScript: green, and certifying the opposite of the truth.

Corrected, and it is a **stronger** argument for the change than the one it replaces: a proxy
pass-through channel into the agent subprocess exists by design, `HOME` is forwarded so a `~/.curlrc`
under the container's agent HOME is readable, and `--noproxy '*'` plus `--disable` deliberately close
both. This is a live behaviour change on the hosted path, not an inert one. The single flag that
genuinely cannot fire there is `ALL_PROXY`, which is absent from the allowlist — so the §Problem
Statement's mention of it applies to the installed-user half only.

Two hosted plugin roots exist, and the layer-7-versus-hosted argument turns on enumerating both:
`apps/web-platform/Dockerfile` › `COPY _plugin-vendored /opt/soleur/plugin`, and the prod root
`agent-env.ts` names as `/app/shared/plugins/soleur`.

The acceptance criterion below asserts on `AGENT_ENV_ALLOWLIST`'s membership, not on a grep over
config files that structurally cannot see it.

## Observability

Layer numbering follows `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`
› "The seven observability layers". An earlier draft cited "layer 3 (CI)" five times; **layer 3 is
the Vector journald shipper**, and a GitHub Actions job log is **layer 6** (synchronous
workflow-run log). A reviewer following the wrong number lands in `infra/vector.toml`.

```yaml
liveness_signal:
  what: "repo-wide Rule D/A/B/C lint, registered as scripts/lint-shell-trace-credential-refusal-repo"
  cadence: "per CI run on every PR and every push to main"
  alert_target: "the required `test` aggregate goes red; PR is blocked"
  configured_in: "scripts/test-all.sh (run_suite registration) and .github/workflows/ci.yml (test-scripts -> test)"

error_reporting:
  destination: "no Sentry project for the build-time guard. The shipped scripts have two execution surfaces and they differ: hosted (inside the production image) they reach layers 1-6 via the agent runner; on a customer's own machine they are layer 7, where there is no Soleur-side sink and there MUST NOT be one — routing a self-hosted run's output to our infrastructure would ship repository-derived data to a Soleur vendor. `plugins/soleur/skills/skill-security-scan/scripts/check-telemetry-surface.sh` actively guards that boundary."
  fail_loud: "the linter prints `<path>:<line>: credentialed curl is not transport-confined ...` and exits 1; betterstack-query.sh prints its allowlist refusal on stderr and exits 2; a plugin script under xtrace prints its refusal on STDOUT (constitution: operator-protection signals go to stdout, because agent runtimes swallow stderr) and exits 78"

failure_modes:
  - mode: "a new or edited shell script forwards a credential through an unconfined curl"
    detection: "layer 6 (workflow-run log) — the repo-wide lint; a new offender is not in either baseline, so its violations are reported and the run exits 1"
    alert_route: "required `test` check red on the PR"
  - mode: "one of the 15 remediated scripts regresses (a --disable dropped, a --noproxy removed)"
    detection: "layer 6 (workflow-run log) — the file is no longer baselined, so the repo-wide run reports it; the advisory --changed step reports it on the touching PR as well"
    alert_route: "required `test` check red"
  - mode: "BETTERSTACK_QUERY_HOST is substituted with a non-vendor host in a workflow or followthrough run"
    detection: "layer 6 (workflow-run log) — the script exits 2 and the calling step fails with the refusal in the job log"
    alert_route: "the workflow's own failure; for scheduled followthroughs, the sweeper's notification"
  - mode: "the confinement prologue is ABSENT from what a customer actually receives (delivery regression — the #7490 under-delivery shape)"
    detection: "layer 6 (workflow-run log) — scripts/plugin-delivery-canary.sh, run daily by .github/workflows/scheduled-marketplace-drift.yml > the canary job. It performs a fresh `claude plugin install` of the PUBLISHED plugin and compares every delivered file's sha256 against the repo at the delivered commit, fail-closed. Slice (a)'s whole control is 'the delivered script carries the prologue', which is exactly what that digest quantifies."
    alert_route: "the scheduled workflow's failure"
  - mode: "the confined curl breaks a hosted agent run (--noproxy cuts a proxy the container needs, or --disable drops a curlrc it relies on)"
    detection: "layers 1-6, via an in-surface structured marker. This surface is NOT observable from a host-side static check: AC22 asserts AGENT_ENV_ALLOWLIST still forwards the proxy variables — i.e. that the change is LIVE — not that a confined curl still succeeds inside the sandbox. The seven scripts must emit a single-line marker on stdout beside the human message, which `agent-runner-query-options.ts`'s always-on `PostToolUse` Bash marker extractor mirrors to the server logger (Better Stack) and a Sentry breadcrumb. Exemplar in the same tree: plugins/soleur/skills/git-worktree/scripts/git-repo-readiness-diag.sh > SOLEUR_GIT_REPO_DIAG."
    alert_route: "Sentry breadcrumb on the agent run; Better Stack query by marker"
  - mode: "a user's own ~/.curlrc or proxy env re-points a credentialed curl on THEIR machine"
    detection: "layer 7 (self-hosted CLI stdout) — the marker above is the in-session signal the operator or agent reads. Beyond that this is NOT detectable by us, and must not be: there is no Soleur-side sink for a self-hosted run and adding one would be a data-controller event, not an observability improvement. Scope the negative precisely: what cannot be observed is the USE of a hostile curlrc or proxy at runtime. Whether the confinement SHIPPED is separately detected by the canary above. The control is a build-time guard that removes the capability rather than observing its exercise."
    alert_route: "none exists for runtime use, and none may — stated rather than implied, per hr-observability-layer-citation"
  - mode: "the BYOK concurrency assertion fails on an outcome class other than the hourly refusal"
    detection: "layer 6 (workflow-run log) — the new rejected/errored/refused-other partitions assert to zero first and name the code and message"
    alert_route: "tenant-integration-required check red, with the outcome named in the failure text"
  - mode: "the tenant-integration suite is skipped and the required check passes anyway"
    detection: "layer 6 (workflow-run log) — the gate verdict emits a ::notice:: and a step-summary line naming the skipped arm. A ::notice:: is a non-blocking annotation by design, not an alert."
    alert_route: "visible on the PR checks page; deliberately not an alert"

logs:
  where: "GitHub Actions job logs for CI; Better Stack + Sentry breadcrumbs for the hosted marker; the user's own terminal for the layer-7 path"
  retention: "90 days for Actions logs (repo default); Better Stack per-source retention for the hosted marker; nothing is retained for layer 7"

discoverability_test:
  command: "python3 scripts/lint-shell-trace-credential-refusal.py <the 15 literal paths from `## Files to Edit`>"
  expected_output: "OK: 15 scanned file(s), 0 baselined (A/B/C), 0 baselined (D)"
```

**Why the probe is scoped to the fifteen rather than the repo.** An earlier draft ran the linter
repo-wide and grepped the two baseline counts. That measures two repo-wide aggregates, which carry
exactly the concurrent-PR volatility the draft cited as its reason for dropping the scanned-file
count: any PR that baselines a new offender, or drives a different file out, moves them — and the
counts cannot distinguish "the fifteen were confined" from "fifteen other paths left the baselines",
nor either from a deletion. Scoped mode zeroes both baselines, so the fifteen-path form asserts Rule
A **and** Rule D on exactly the files this PR changes. Same allowlisted verb (`python3`), still no
network and no credentials. The repo-wide run remains an acceptance criterion; it is just not the
probe.

## Encryption Posture

This plan introduces **no** persistent data store and **no** new cross-component connection: no
`.tf`, no `supabase/migrations/*.sql`, no cloud-init and no compose file appears in `## Files to
Edit`. The gate is recorded rather than skipped silently because the plan's prose names two store
classes (Better Stack as a log sink, Supabase as a database) and a reader could reasonably ask.

It does **narrow** one existing connection, so that one is declared:

```yaml
in_transit:
  - connection: "scripts/betterstack-query.sh -> Better Stack ClickHouse read endpoint"
    tls: "HTTPS, enforced by the literal https:// scheme in run_sql's URL; the host is the only
          interpolated part and after this change it must suffix-match *.betterstackdata.com"
    cert_verification: "on — curl's default; the script does not pass -k/--insecure, and it unsets
          CURL_CA_BUNDLE, SSL_CERT_FILE and SSL_CERT_DIR so a caller cannot substitute a trust store"
    does_not_defend: "an attacker who can set BETTERSTACK_QUERY_SH, which re-points the whole script
          rather than its destination and leaves the host pin intact — a strict superset of the seam
          this change closes, named in Non-Goals. Nor does it defend against a compromised vendor
          endpoint, or against the credential being read from the environment by another process on
          the same host."
    disclosed_as: "no change to any published disclosure — the connection and its credential already
          existed; this narrows where the credential may be sent."
```

No `exception` block: no `plaintext-exception` mechanism and no `cert_verification: off` row.

## Guard Contract

### Guard 1 — Rule D/A confinement over the shipped plugin scripts

**Property.** No shell script in this repository forwards a credential through a `curl` that reads
the caller's `~/.curlrc` or honours the caller's proxy environment, except the files an explicit
baseline still records as unremediated — and the fifteen `plugins/**` scripts are no longer among them.

**Assembly.** The chokepoint is `check_file()` in `scripts/lint-shell-trace-credential-refusal.py`,
quantified over the file list `main()` derives (repo-wide when unscoped, the diff when `--changed`),
minus the two baseline sets loaded by `load_baseline()` and `load_baseline_d()`. The members are the
derived file list, never an enumerated one: that is why the guard sees a script added tomorrow. Two
dispatch sites exist and both matter — the unscoped repo-wide run registered in `scripts/test-all.sh`
(blocking, honours baselines) and the `--changed --base origin/main` step in
`.github/workflows/ci.yml` (advisory, zeroes both baselines). A change that greens only one of them
has not satisfied this property.

**Mutation matrix**

| # | Mutation | Must |
|---|---|---|
| 1 | Delete `--disable` from the first remediated call in `user-set-role/scripts/set-role.sh` | RED — repo-wide run reports the file, which is no longer baselined |
| 2 | Keep `--disable` but move it after `-sS` in `flag-set-role/scripts/flip.sh` | RED — position is the property, not presence |
| 3 | Remediate `set-role.sh` fully but leave `trigger-cron/scripts/trigger.sh` unremediated while removing **both** from the baseline (second member after a compliant first) | RED — a check that stops at the first member is the defect class |
| 4 | Make the file walk in `main()` return zero files (guard's own dispatch) | RED — the summary must not report `OK: 0 scanned file(s)` as success |
| 5 | Re-inline one of `provision-doppler.sh`'s hoisted `-d` payloads as a multi-line literal, keeping the transport flags | RED — the destination-pin finding returns. This is the row that pins the *actual* remediation. (The first draft's row 5 — "drop the `readonly DOPPLER_API_PINNED` refusal while keeping the hoist" — was measured GREEN on the real file and has been deleted along with the constant it referenced: a pin on `DOPPLER_API_PINNED` cannot adjudicate `DOPPLER_TOKEN`, so its absence was never detectable.) |
| 6 | Re-add one of the 15 paths to `lint-shell-trace-credential-refusal-d.baseline.txt` | RED — the drawdown assertion (67 entries, and the removed set equals the 15 paths) fails |

**Harness rows**

| # | Edit to the SUITE | Must |
|---|---|---|
| H1 | Delete the `compliant-ruled-pinned-destination.sh` must-PASS row from `scripts/lint-shell-trace-credential-refusal.test.sh` | RED — a suite whose only pin fixture is a violation cannot detect a classifier that rejects everything |
| H2 | Feed the suite a non-canonical but permitted input: a compliant script whose refusal wording differs from `compliant-canonical.sh` (the existing `compliant-noncanonical.sh` shape) | PASS — the contract is a shape, not fixed text |

### Guard 2 — the Better Stack query destination pin

**Property.** `scripts/betterstack-query.sh` never sends `BETTERSTACK_QUERY_USERNAME` /
`BETTERSTACK_QUERY_PASSWORD` to a host outside `*.betterstackdata.com`.

**Scope this property honestly: it is about the script, not the system.** Two production
followthroughs resolve the *query script itself* through an env-settable path —
`scripts/followthroughs/git-data-rung2-evidence-capture.sh` and
`betterstack-roundtrip-latency-7855.sh` both carry
`QUERY="${BETTERSTACK_QUERY_SH:-${REPO_ROOT}/scripts/betterstack-query.sh}"`. `BETTERSTACK_QUERY_SH`
is a strict superset of the seam this slice closes: an actor who can set `BETTERSTACK_QUERY_HOST` can
equally set `BETTERSTACK_QUERY_SH` and receive the injected credentials in a script of their
choosing, **with the host pin fully intact**. That is verbatim the objection used to reject
`BETTERSTACK_QUERY_HOST_TEST_PIN`, applied to a seam that already ships. After this slice the
system-level property is still false; only the script-level one holds. It is named in Non-Goals with
its reason rather than papered over, and ADR-214's corollary is written to acknowledge the shipped
exceptions rather than to be contradicted by two files on the day it lands.

**Assembly.** `run_sql()` is the sole site where the credential is attached (`-u "…:…"`) and the sole
`curl` in the file, and `"https://${BETTERSTACK_QUERY_HOST}?…"` is the sole destination interpolation.
The chokepoint is therefore the refusal block that must dominate every path reaching `run_sql` — not
the `case` block as currently written, which is one arm of it. Any future second egress site would
have to be brought under the same block; the guard's assertion is on the credential's departure, not
on the presence of a `case` statement. The covering suite is
`tests/scripts/test-betterstack-query-archive.sh`, which reaches the real script by `source` and
shadows `curl` as a shell function, so a request that escapes is observable as a shim invocation.

**Mutation matrix**

| # | Mutation | Must |
|---|---|---|
| 1 | `BETTERSTACK_QUERY_HOST=attacker.example` (a bare host that passes every existing shape arm) | RED — refuse, exit non-zero, and the `curl` shim records zero invocations. **Phase 1.5 must add the invocation counter this row needs:** the existing shim in `test-betterstack-query-archive.sh` › `capture_sql()` prints the `-d` argument and returns 0 — it counts nothing and never sees the destination URL. Without the counter this row cannot distinguish "refused" from "sent and ignored". |
| 2 | `BETTERSTACK_QUERY_HOST=betterstackdata.com.attacker.example` | RED — refused; proves the allowlist anchors the vendor apex as a **suffix** rather than matching it anywhere in the value. **The obvious candidate does not work:** `evil.com/?x=.betterstackdata.com` is already refused by the pre-existing shape arm (which rejects `/` and `?`), so it never reaches the allowlist and discriminates nothing. |
| 3 | Replace the authority extraction with a whole-value `case "$BETTERSTACK_QUERY_HOST" in *betterstackdata.com*)` | RED on row 2 — the naive form must be visibly weaker. With the corrected row-2 value this now discriminates; against the first draft's value the mutant stayed green. |
| 4 | Remove the allowlist arm entirely, keeping the old shape check (guard's own dispatch) | RED — and the suite must report a non-zero case count, so a suite that ran nothing cannot pass |
| 5 | `BETTERSTACK_QUERY_HOST=notbetterstackdata.com` — a suffix that matches only if the pattern lacks its leading dot | RED |

**Harness rows**

| # | Edit to the SUITE | Must |
|---|---|---|
| H1 | Remove the `curl` shell-function shim so a real request could escape | RED — the suite must fail closed rather than silently begin dialling |
| H2 | Must-PASS, non-canonical: the live production host `eu-central-1a-connect.betterstackdata.com`, and separately the same host with an explicit `:443` port | PASS — the port strip and the apex are both permitted by contract |

### Guard 3 — the BYOK concurrency partition and its null-change control

**Property.** The concurrency test's exact-equality counts are asserted only over outcomes it has
classified, and no writer outside a given delegation can move that delegation's hourly meter.

**Assembly.** Two channels, and both are members: the client channel (the `UseResult` array from
`Promise.allSettled` over `recordUse`) and the ledger channel (`auditRowsFor(delegationId)`). Each
must be partitioned exhaustively — every element lands in exactly one class and the classes sum to
the total — rather than filtered for one expected value, which is the shape that lost a count. The
exhaustiveness is the structural claim; the current class list (admitted, refused-hourly,
refused-other, errored) is today's membership and will change when a migration adds a refusal reason,
which is why the assertion is `classes.reduce(sum) === N` and not a list of four counts. The
isolation limb quantifies over the meter predicate in migration 137
(`WHERE au.delegation_id = p_delegation_id AND au.ts > clock_timestamp() - interval '1 hour'`), and
the control's members are delegation A and sibling delegation B under one grantor and one workspace.

**Mutation matrix**

| # | Mutation | Must |
|---|---|---|
| 1 | Inject one call whose result carries a non-null `error` | RED on the new `errored.length === 0` assertion, naming the code and message — **not** on `refused === N-K` with a bare count |
| 2 | Inject one call that fulfils with a non-hourly `refusalReason` (second member after the error class) | RED on `refusedOther.length === 0`; proves the partition is by observed outcome, not by one expected string |
| 3 | Inject one ledger row whose `attribution_shift_reason` is `daily_cap_exceeded` | RED on the ledger-side third partition; proves the fix was applied to both channels. **Must be an in-enum value:** `audit_byok_use_attribution_shift_reason_check` permits only NULL, `revoked_post_grace`, `expired`, `consent_withdrawn`, `hourly_cap_exceeded`, `daily_cap_exceeded`, so a genuinely foreign string cannot be inserted at all and the first draft's row was unrunnable. `daily_cap_exceeded` is also the realistic regression. |
| 4 | In the control's step 1, replace B's `delegationId` **and** B's caller with A's — so the outside writer's M rows land on A's own meter | RED on the negative control. **The naive form of this row does not work:** `grantDelegation()` mints a fresh grantee per delegation, and the RPC pins the caller (the sibling test in this file asserts a non-grantee caller raises `42501 caller_not_grantee` and ledgers nothing). B's grantee calling A's delegation therefore reddens the `errored` partition and proves nothing about meter sharing. Both the id and the caller must move together. |
| 5 | Give B a cap with no headroom so every B call refuses and B never writes | RED on the positive control (`B admitted === M`) — a control that passes by doing nothing is vacuous |
| 6 | Delete the whole control `test(...)` block (guard's own dispatch) | RED — **and this requires building the detector, because there is none today.** The vitest file carries no case floor; Phase 4's ADR-193 floor is on the *shell* suite `test-tenant-integration-gate-verdict.sh`, a different file. Add an assertion on the expected test count for this file (vitest reports it) so a silently-deleted control cannot pass as a green run. |
| 7 | Inject an unreadable PostgREST payload so `readRefusalReasonLive` throws and the promise rejects | RED on `rejected.length === 0`, naming the rejection message — not silently absorbed as `errored` with `undefined` fields, and not dropped from every class |

**Harness rows**

| # | Edit to the SUITE | Must |
|---|---|---|
| H1 | Move the new partition assertions *after* `await diagIf(willFail)` without adding them to `willFail` | RED — otherwise the assertions ship without the diagnostic banner and the suite silently loses its evidence |
| H2 | Must-PASS, non-canonical: run the control with `M = 1` instead of the default, and with B's cap set to `2 * M * COST_CENTS` rather than exactly `M * COST_CENTS` | PASS — the contract is "B's writes do not move A's counts", not a specific M or a cap pinned to the boundary. (The first draft's H2 — "B's calls interleave in a different order" — was cut: with a sequential control there is no interleaving, and even concurrently the ordering cannot be produced deterministically, so it asserted the absence of an assertion nobody wrote.) |

## Architecture Decision (ADR/C4)

### ADR

**Create ADR-214** (ordinal provisional; `/ship` re-verifies against `origin/main` and every pushed
ref before merge). Grepping `knowledge-base/engineering/architecture/decisions/` for `--noproxy`,
`--disable`, `curlrc`, `Rule D`, `7873`, `7898` and `credential forwarding` returns nothing, so no
decision is being reversed and nothing needs amending.

**Scope it to the seam corollary alone.** The first draft proposed a four-part confinement doctrine
— xtrace refusal, `--disable` first, `--noproxy '*'`, destination pinning. Two reviewers independently
objected, and they are right: all four are *already encoded executably* in
`scripts/lint-shell-trace-credential-refusal.py`, with two baselines, a RED/must-PASS fixture corpus
and a required CI gate. An ADR narrating what a linter enforces is a second copy that can drift, and
when it drifts the reader has two sources disagreeing with no tiebreak. The executable artifact is
the stronger one; do not restate it in prose.

What is left is a genuine decision the linter does *not* encode, and it is one line:

> **A test seam for a destination pin must never be env-declared.** On this surface the environment
> is the adversary: anyone who can substitute the destination variable can set the declaration to
> match in the same breath, so an env-declared seam is a bypass available to precisely the actor the
> pin defends against. A test that needs a non-vendor destination shims `curl` — which exercises the
> guard — rather than declaring its way past it.

That decides the fork for every future script on this surface, has no executable home today, and was
about to be implemented the other way because `betterstack-query.sh`'s own comment block forecasts
the seam. It belongs in the corpus. The four confinement flags do not.

Write the corollary in two more places while there — `check_rule_d`'s docstring, next to the message
that tells an author to add a destination pin, and the `betterstack-query.sh` comment block that
Phase 1.2 rewrites anyway. Those are where the next person reaching for a seam will actually be
standing.

Slice C is **not** ADR material: ADR-208 already decides the refusal-reason return contract, and
partitioning a test's outcomes is an implementation of that decision rather than a new one.

### C4 views

All three of `model.c4` (691 lines), `views.c4` (74) and `spec.c4` (54) were read, not grepped. The
enumeration:

- **External human actors:** unchanged. The only actor is `founder = actor "Founder / Operator"`;
  this change adds no correspondent, reviewer or recipient.
- **External systems the 15 scripts call:** Bluesky, LinkedIn, X/Twitter and Flagsmith have **no
  element at all**; Cloudflare, Discord, Doppler and Supabase exist as coarse systems whose every
  edge is CI/webapp/infra-scoped, none script-scoped; the Inngest manual-trigger endpoint has no
  edge. This is a **pre-existing** modelling gap — the scripts have zero graph representation today
  and this change does not alter that, since it adds transport flags to calls that are already
  unmodelled. Recorded as a Non-Goal below rather than filed: it is a documentation gap with no
  observable trigger, so it fails the `wg-defer-only-after-inline-triage` second test.
- **Containers/data stores touched:** none added. The shared dev Supabase project the test suite
  writes to has no element and gains none.
- **Access relationships changed:** none. No ownership or tenancy boundary moves.

**One description this change does interact with**, and it is the reason this section is not a bare
"None": `model.c4` › the `github -> betterstack` edge states *"repo-wide it carries a baselined
remainder of 67 files -- including arm-heartbeats.sh"*. The live baseline holds **82**. That prose is
currently false and is forward-dated to exactly this change: `82 − 15 = 67`. Landing slice A makes it
true. The plan therefore does **not** edit that sentence's number — it makes it accurate — but it
does add an acceptance criterion asserting the two agree after the change, so the coincidence is
verified rather than assumed. `arm-heartbeats.sh` stays baselined and stays named, correctly.

`plugins/soleur/test/c4-count-parity.test.sh` (note: **not** under `apps/web-platform/test/`) passes
10/10 on the current tree and gates eight counts, all on the `github -> sentry` and `github -> resend`
edges. The "67 files" figure is **not** among them — it is unguarded prose. Bringing it under the
parity gate is out of scope here and recorded as a Non-Goal.

### Sequencing

The ADR is written in this PR, describing the state slices A and B establish. Nothing about it is
soak-gated, so no `adopting` status is needed.

## Acceptance Criteria

### Pre-merge (PR)

**A note on running these.** Several criteria expect a `grep` to find nothing, and `grep -c`
returning `0` **exits 1**. Under any `set -e` verification wrapper those abort the run and read as a
failed criterion when the criterion actually passed. Write each as
`[[ "$(grep -c … || true)" == "0" ]]`, or use `grep -c … || true` and compare. This applies to
criteria 2, 8, 23 and 24.


1. `python3 scripts/lint-shell-trace-credential-refusal.py <the 15 paths from `## Files to Edit`, written out literally>` exits 0 with `OK: 15 scanned file(s), 0 baselined (A/B/C), 0 baselined (D)`. **The paths must be literal.** Two earlier forms were both defective and both would have passed: deriving them from the D baseline scans nothing once Phase 2.4 empties it of `plugins/` entries, and — worse — `targets_from_args()` falls through to `all_shell_files()` when `args.paths` is empty, so the command silently becomes the repo-wide run, honours both baselines, prints `OK`, exits 0, and certifies nothing about the fifteen while duplicating AC3. Deriving them from `git diff --name-only` is better but still degrades to a repo-wide scan if the diff is empty. `15 scanned file(s)` in the output is the guard against all three.
2. The set removed from each baseline equals exactly the 15 paths — `git diff` on the two baseline files shows 15 deletions each, zero additions, and `grep -c '^plugins/'` returns `0` for the D baseline and `5` for the A/B/C one. (Membership, which a count cannot verify: an equal-sized swap keeps the count and breaks the property.)
3. `python3 scripts/lint-shell-trace-credential-refusal.py` (repo-wide, unscoped) prints `OK: <n> scanned file(s), 101 baselined (A/B/C), 67 baselined (D)` and exits 0. **101, not 103, and the difference is not an error.** That line prints `len(offenders)` — files that are *both* baselined and still violating — not the baseline file's line count. Measured on the current tree it reads `116 baselined (A/B/C), 82 baselined (D)` while the files hold 118 and 82: two A/B/C entries (`apps/web-platform/infra/inngest-bootstrap.sh` and `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh`) are stale, listed but no longer violating. So the printed A/B/C count goes 116 → 101 while the file goes 118 → 103, and AC2's file-level count of 103 is also correct. An earlier draft predicted 103 here by subtracting from the file count instead of from the measured one — a blocking criterion that would have failed on a correct implementation and invited someone to "fix" the drawdown to hit it.
4. `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main` exits 0 — the advisory step is green on this PR's own diff, which is the point of folding Rule A in.
5. No predicate, regex, baseline-loading path or rule function in `scripts/lint-shell-trace-credential-refusal.py` is modified. The only permitted change to that file is dropping the false "AND its highwater" clause from `--write-baseline-d`'s argparse help; `git diff` on it must show that string and nothing else.
6. The four suites carrying this PR's new rows are registered in `scripts/test-all.sh` and green under it: `lint-shell-trace-credential-refusal.test.sh`, `tests/scripts/test-betterstack-query-archive.sh` (Guard 2's rows, with the new invocation counter, case count reported and non-zero), `tests/scripts/test-git-data-rung2-evidence-capture.sh` (with the `curl` shim), and `tests/scripts/test-tenant-integration-gate-verdict.sh` (rows for both PASS arms). Registration is the checkable thing; passing is what AC12 (the full battery) already means.
7. With synthetic `BETTERSTACK_QUERY_USERNAME`/`BETTERSTACK_QUERY_PASSWORD` set, `BETTERSTACK_QUERY_HOST=attacker.example bash scripts/betterstack-query.sh 'SELECT 1'` exits **2** with a refusal naming the allowlist, and the `curl` shim records **zero** invocations. The credentials are load-bearing in the criterion: without them the script exits **3** at the credential-presence guard, which sits above the host `case`, so the "exits non-zero" half ticks while the allowlist is never reached — a vacuous pass.
8. `grep -c 'eu-fsn-3-connect' knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` returns `0`, and the file names `eu-central-1a-connect.betterstackdata.com`.
9. The comment block above the host check in `scripts/betterstack-query.sh` no longer contains the strings `opt-in seam` or `13-file change`, and states the pin that exists.
10. `cd apps/web-platform && doppler run -p soleur -c dev -- env TENANT_INTEGRATION_TEST=1 npm run test:ci -- test/server/byok-delegation.atomicity.tenant-isolation.test.ts --project unit` passes **and reports a non-zero test count**. The count assertion is load-bearing: the file is wrapped in `describe.skipIf(!INTEGRATION_ENABLED)`, so dropping `TENANT_INTEGRATION_TEST=1` makes vitest exit 0 on a fully skipped file. This is Property 8 — a check that passed because its suite was skipped must say so — applied to the plan's own acceptance command.
11. The diff of that test file contains **no** occurrence of `retry`, `retries`, `attempt`, or a second invocation of the same assertion; every pre-existing exact equality in T5 survives (`.toBe(K)`, `.toBe(N - K)`, `.toBe(CAP_CENTS)` all still present, none replaced by `toBeGreaterThanOrEqual`); and the control adds **no** `Promise.allSettled` that mixes A's and B's calls — the two steps are sequential.
12. `bash scripts/test-all.sh` passes (the full battery, at the `/ship` Phase 4 checkpoint), and `bash plugins/soleur/test/c4-count-parity.test.sh` passes 10/10.
13. T5 partitions `settled`, not `results`: `git diff` shows a `rejected` class asserted to zero, and the class sizes asserted to sum to `N`.
14. `.github/workflows/tenant-integration.yml` › `concurrency.group` no longer interpolates `github.ref`, and `cancel-in-progress` is still `false`.
15. `model.c4` › the `github -> betterstack` edge's "baselined remainder of N files" and the live D-baseline count agree — **or** the prose is updated in this PR to match. Stated as a disjunction deliberately: the two agree today only because `82 − 15 = 67`, and unrelated baseline drift landing on `main` before merge would otherwise fail this criterion for something this PR did not cause (`cq-ac-must-not-depend-on-concurrent-sessions`).
16. `ADR-214-*.md` exists (or the ordinal `/ship` re-derived), it decides the seam corollary **only** — it does not restate the four confinement flags — and no other artifact for this branch cites a different ordinal.
17. PR body carries `Closes #7055` on its own line, a prose `Ref #7898` line, and a `## Changelog` section (`plugins/soleur/AGENTS.md` › Pre-Commit Checklist). No closing keyword for #7898 anywhere, including inside code blocks and checkboxes.
18. The **seven** community scripts use the conditional arm and the **eight** operator scripts use the unconditional one: `grep -c ':+x'` returns ≥1 in each of the seven and **exactly 0** in each of the eight — `provision-doppler.sh` included, whose linter-emitted conditional arm would otherwise fail open because `read -rs` binds its token after the prologue.
19. Running each of the seven under `bash -x` with its guarded credentials **unset** does not exit 78; running each of the fifteen under `bash -x` with a credential set exits 78 and prints the refusal on **stdout** (`bash -x <script> 2>/dev/null` still shows it).
20. Each of the seven customer-facing refusals matches the Phase 2.1 template with that file's own guarded variable list substituted — the remedy enumerates **every** variable that file's arm tests, not one of them. Asserted per file, not as "a variable is named": `x-community.sh` and `x-setup.sh` guard four credentials each, and a remedy naming one of four cannot be followed. No occurrence of the word `probe`.
21. The seven carry the proxy-aware failure line AND the structured stdout marker: with `HTTPS_PROXY` set and the endpoint unreachable, each prints a message naming the deliberate bypass (**not** the pre-existing "Check your network connection and try again."), plus one marker line on stdout carrying `surface`, `script`, `curl_exit`, `refusal`, `proxy_env`, `curlrc_present` and `noproxy_applied`. The marker must survive `2>/dev/null` — it is on stdout by design, and the existing stderr suppression stays.
22. `scripts/plugin-delivery-canary.sh` still digests the fifteen: after merge, one canary run reports no finding for any of them, confirming the prologue reaches a customer install rather than only the repo.: with `HTTPS_PROXY` set and the endpoint unreachable, each prints a message naming the deliberate bypass, and **not** the pre-existing "Check your network connection and try again."
23. `AGENT_ENV_ALLOWLIST` in `apps/web-platform/server/agent-env.ts` still contains the proxy names and `HOME` — i.e. the hosted-path behaviour change this plan documents is real and is asserted against the mechanism that produces it, not against a grep over config files that cannot see it.
24. No file under `plugins/**` gains an env-declared destination seam: `git diff origin/main -- plugins/` contains no new `_TEST_PIN`, `_ALLOW_`, or equivalent host-override variable.

### Post-merge

25. A comment is posted on #7898 naming this PR and stating that §5 (`plugins/**`, 15 files) and §6
    (`BETTERSTACK_QUERY_HOST`) are closed, with the remaining sections enumerated. This is the
    mitigation for the prose-`Ref` blind spot: a merged PR that cites an issue in prose creates no
    GitHub link, so both `closedByPullRequestsReferences` and a `linked:issue` search stay empty and
    the work is invisible to the collision gate — which is how an already-done tracker gets
    re-dispatched. Automatable with `gh issue comment`, so it is not an operator step.

## Domain Review

**Domains relevant:** engineering, product

### Engineering (CTO)

**Status:** reviewed

**Assessment:** Ruled *fold Rule A in* — the advisory `--changed` job bypasses both baselines, so a
PR that touches these files and leaves 15 Rule A violations red trains the next reader to ignore
that job, the mirror of the failure the linter's own header warns about; and all 15 sit in both
baselines, so fixing A draws both down in one pass. The coherent scope unit is "credential-forwarding
confinement in the 15 shipped plugin scripts", which contains Rule A; a sixteenth file does not.

**Rejected the `BETTERSTACK_QUERY_HOST_TEST_PIN` seam.** The threat model is env control over
`BETTERSTACK_QUERY_HOST`; anyone who can set that can set the declaration to match in the same
breath, so the seam is a complete bypass available to precisely the actor the pin defends against.
Directed the `127.0.0.1` case to a `curl` shim on `PATH` instead, which exercises the guard rather
than skipping it. Also required rewriting the script's comment block, which currently forecasts the
seam — otherwise the next session implements what this one rejected.

**Corrected slice C in two places, both folded in.** The live hole is wider than the error channel:
a call that fulfils with a *non-hourly* refusal reason also lands in neither partition, and the
**ledger** side has the identical blind spot because `refusedRows(rows, HOURLY_REASON)` filters by
reason too. Both channels are now partitioned in Phase 3. Also required that the new partitions be
folded into `willFail` before `diagIf` is awaited, and that the null-change control assert **B's own
admitted count** — otherwise a sibling that refuses for its own reasons never writes and the negative
control passes by doing nothing. Endorsed the single-process control design: the claim under test is
a property of a SQL `WHERE` predicate, not of process topology, and a second writer process would add
a second flake source while proving nothing further.

**Named a risk the plan had not:** the `*.betterstackdata.com` apex was an inference from the ingest
URL, with ~25 production followthrough scripts breaking at once if wrong. Acted on: the live value
was pulled read-only and is `eu-central-1a-connect.betterstackdata.com`, a different region from the
runbook's. Also flagged that `--write-baseline-d` rewrites the entire baseline from a full-tree scan
and would silently re-baseline drift — Phase 2.4 now removes the 15 lines by hand. And corrected the
`provision-doppler.sh` remedy: the destination pin lands unconditionally, with the payload hoist as
cosmetic, rather than the reverse.

**Dissent recorded, not adopted:** recommended splitting A+B and C into separate PRs. The one-shot
batching is deliberate; mitigated by ordering slice C last. Persisted to `decision-challenges.md`.

### Product (CPO)

**Status:** reviewed — conditional sign-off, all four conditions folded in

**Assessment:** Conditional approval as the plan-time product-owner acknowledgement required by the
threshold. The four conditions, and their disposition:

1. **Split `## User-Brand Impact` by surface and raise the threshold.** Adopted. The seven
   `community/*` scripts carry the user's own tokens; the eight operator-only scripts carry Jikigai's
   `soleur/prd` service-role key. Verified independently by reading each script's credential block.
   The threshold stays at the gate-valid `single-user incident` — see the scope note in that section
   for why the label understates the operator half, and why `all-users incident` (which a draft did
   write) is invalid: preflight Check 6 matches the value as a discrete token against a three-value
   enum. What the CPO asked for and got is the split by surface and the severity stated in prose. The
   escalation the threshold buys — CPO sign-off and `user-impact-reviewer` — is engaged either way.
   This is still a correction to the brief's stated framing, which described the failure mode as
   "one user's project key": that holds for the customer-facing seven and understates the other eight.
2. **Answer the hosted path.** Adopted, and the answer inverted under measurement. `vendor_plugin:
   true` puts the same files in the production image, so the layer-7 citation is conditional on
   execution surface. A first pass concluded both flags were no-ops there; `AGENT_ENV_ALLOWLIST`
   forwards the proxy variables and `HOME` into the agent subprocess by design, and that
   pass-through is TypeScript, which the config-file grep scope could not see. So the flags are a
   live behaviour change on the hosted path — a stronger argument for the change than the one it
   replaced. AC23 asserts against that allowlist rather than against a grep that cannot observe it.
3. **Refusal on stdout, conditional hatch on the seven.** Adopted into Phase 2.1, with the
   constitution's stdout rule cited and the linter re-run as the arbiter rather than an assertion.
4. **Rewrite the refusal text for the customer-facing seven.** Adopted into Phase 2.1 and AC20.

Two follow-ups the CPO asked to file rather than absorb are recorded as Non-Goals below with a
disposition, per `wg-defer-only-after-inline-triage`.

**Note on cohort size:** the external beta cohort is one user, on exactly this surface. The
threshold is not hypothetical.

### Plan review — six agents (2026-09-09)

**Status:** reviewed; mechanical findings applied, Taste/User-Challenge findings persisted to
`knowledge-base/project/specs/<branch>/decision-challenges.md`

**Panel:** architecture-strategist, spec-flow-analyzer, kieran-rails-reviewer,
code-simplicity-reviewer, dhh-rails-reviewer, user-impact-reviewer — the escalated set, because the
threshold is above `single-user incident`.

**What it changed.** Four claims this plan asserted were falsified by reviewers *running commands on
real copies of the files*, and all four are corrected above: the `readonly DOPPLER_API_PINNED`
remedy does not clear the Rule D finding (the payload hoist does, and the plan had ordered them
backwards); the repo-wide summary prints live-offender counts so the post-drawdown A/B/C figure is
101 rather than 103; the linter emits a *conditional* xtrace arm for `provision-doppler.sh` whose
guard is empty at guard time; and the hosted path is not a no-op because `AGENT_ENV_ALLOWLIST`
forwards the proxy variables and `HOME` by design. Also corrected: five outcome classes rather than
four in T5 (`readRefusalReasonLive` throws, so a promise can reject); `AC1` degrading into a
repo-wide run; Guard 2 rows masked by the pre-existing shape arm; Guard 3 rows that were unrunnable
against a CHECK constraint or had no detector; the rung2 arm's exit-64 discrimination being preempted
by the new refusal; and the runbook premise, which the runbook itself refutes three lines above the
edited line.

**What it did not change.** The null-change control stays (mandated), but sequential rather than
concurrent. `Closes #7055` stays, but only because Phase 4b now removes a cause rather than renaming
a symptom. ADR-214 stays, narrowed to the seam corollary. The A+B/C PR split — recommended by three
reviewers — was not adopted; the batching is the operator's instruction and the dissent is recorded.

### Compliance (GDPR gate)

**Status:** reviewed — advisory, no finding blocks this plan

**Assessment:** None of the three surfaces matches the canonical regulated-path regex; the gate was
run manually because the `single-user incident` declaration triggered it. No Critical (Art. 9)
finding. The credential confinement reads as an Art. 32(1)(b) improvement, not a gap, and Art. 33 is
not engaged — this is proactive hardening with no evidence of an exploitation event. The accumulating
synthetic-fixture population is `DL-05`-shaped but the rows are almost certainly not personal data
under Art. 4(1) (fabricated per-run, namespace-guarded), and the gap is already tracked as #3934;
this PR accelerates it rather than creating it. Disposition: no new issue, no
`compliance-posture.md` row. One open question passed to implementation: confirm
`createSyntheticUser()`'s workspace auto-creation via `handle_new_user` fires no side effect outside
the synthetic namespace (nothing suggests it does).

## Test Scenarios

1. A shipped plugin script runs with a hostile `~/.curlrc` present: the credential goes to the coded
   host, not the one the config file names.
2. The same script runs with `HTTPS_PROXY` set: the request does not traverse the proxy.
3. **A community script runs with `HTTPS_PROXY` set and the endpoint unreachable:** the user gets the
   proxy-aware line naming the deliberate bypass, **not** "Check your network connection and try
   again." This is the scenario the change most likely produces in the field, and the one an earlier
   draft named in `## User-Brand Impact` and then never tested.
4. The same script runs under `bash -x` with the credential set: it exits 78 before any request, and
   the refusal is visible on stdout with stderr discarded.
5. A community script runs under `bash -x` with every guarded credential **unset**: it proceeds, so
   the refusal is scoped to the hazard rather than blanket. For `x-community.sh` and `x-setup.sh` all
   **four** guarded variables must be unset — the arm is `-n` over a concatenation, so unsetting
   three of four still exits 78.
6. An operator script runs under `bash -x` with no credential set: it still exits 78 (unconditional
   arm), including `provision-doppler.sh`, whose token arrives interactively after the prologue.
7. `betterstack-query.sh` with the live production host `eu-central-1a-connect.betterstackdata.com`:
   works unchanged.
8. The same, plus an explicit `:443`: works — the port strip runs before the suffix match.
9. `betterstack-query.sh` with `attacker.example`, with `betterstackdata.com.attacker.example`, and
   with `notbetterstackdata.com`: each refused at exit 2, no request, with synthetic credentials set
   so the refusal is reached rather than short-circuited by the credential-presence guard.
10. The rung2 evidence-capture arm still discriminates on `exit 64`: the new host refusal must not
    preempt it into a vacuous pass.
11. T5 with all ten calls healthy: every exact equality passes, unchanged from today.
12. T5 with one call returning a non-null `error`: fails on the errored partition, naming code and
    message — not on `refused` with a bare count.
13. T5 with one call whose payload is unreadable so `readRefusalReasonLive` throws: fails on the
    rejected partition, not absorbed as `errored` with `undefined` fields.
14. T5 with one call returning a non-hourly refusal reason: fails on the refused-other partition.
15. Null-change control, **sequential**: B's M calls run to completion first (B admitted === M), then
    A's N calls run and A's counts are exact. No `Promise.allSettled` mixes the two.
16. Null-change control with B's delegation id **and** caller replaced by A's: the negative control
    fails, proving it can be driven red. Moving the id alone does not work — it raises
    `42501 caller_not_grantee` and ledgers nothing.

## Non-Goals / Out of Scope

#7898 stays **OPEN**. This PR closes §5 and §6 only. Explicitly not addressed, and stated in the PR
body:

- Sites 2 and 3, `apps/web-platform/infra/soleur-host-bootstrap.sh` and
  `web-private-nic-guard.sh`. Both are hashed into `terraform_data` `triggers_replace` blocks in
  `apps/web-platform/infra/server.tf`, so editing either re-provisions the live serving host on
  merge. They belong to a change already taking a host-replacement window.
- The Resend host scripts.
- The YAML scope gap.
- The `CURL_BIN` seam (a known, deliberately deferred follow-up recorded in an archived plan).
- `apps/web-platform/infra/arm-heartbeats.sh` and `cutover-verify.sh`, which are honestly baselined.
- Adding the seven unmodelled external systems (Bluesky, LinkedIn, X, Flagsmith, and script-scoped
  edges for Cloudflare, Doppler, Supabase and the Inngest trigger endpoint) to `model.c4`. A real
  pre-existing gap, unchanged by this PR, with no observable trigger.
- Bringing the `github -> betterstack` edge's "N files" figure under
  `plugins/soleur/test/c4-count-parity.test.sh`. Worth doing; not this PR.
- Deleting the accumulating synthetic-fixture population on the shared dev Supabase — already
  tracked as #3934, and this PR adds to it rather than changing its shape. A comment on #3934 noting
  the increased per-run row rate is the proportionate action and is folded into the post-merge step.

Further findings from the six-agent plan review, each real, each pre-existing, each filed rather
than absorbed:

- **`community/scripts/community-router.sh`** — indirect expansion in a test (`[[ -n "${!var:-}" ]]`)
  prints all seven of the founder's platform credentials under `bash -x`. It is A/B/C-baselined,
  carries no Rule D violation, and is the first command of every `/soleur:community` sub-command.
  Needs a hand-written guard, not the linter's emitted block.
- **`community/scripts/discord-setup.sh`** — `DISCORD_BOT_TOKEN_INPUT` rides an unconfined curl and
  is invisible to Rule D because `CREDENTIAL_NAME` anchors on `_(TOKEN|KEY|SECRET|PASSWORD|PAT)` at a
  word boundary and `_INPUT` defeats it. Fixing the classifier is forbidden here by AC5.
- **`BETTERSTACK_QUERY_SH`** — `scripts/followthroughs/git-data-rung2-evidence-capture.sh` and
  `betterstack-roundtrip-latency-7855.sh` both resolve the query script itself through an env-settable
  path. That is a strict superset of the seam Slice B closes: the same actor gets the injected
  credentials in a script of their choosing with the host pin intact. It is the `CURL_BIN`-seam
  family the brief already scopes out, and ADR-214's corollary is written to acknowledge it rather
  than be contradicted by two shipped files on the day it lands.
- **The `read -rs` gap in the linter's `ACQUIRES` set** — why `provision-doppler.sh` is offered a
  conditional arm that would fail open. Classifier change, forbidden here.
- **The A/B/C baseline has no stale-entry check.** Two entries are listed but no longer violate, and
  nothing detects that. Growth is blocked; shrinkage is unverified, so a re-added suppression after
  merge is undetectable. Guard 1's row 6 is a PR-time check, not a committed test.
- **`record_byok_use_and_check_cap`'s founder-scoped hourly meter pools across sibling delegations**
  (no delegation filter in its SUM). Named in the control's comment; whether it is a defect is a
  separate question.
- **Retrofitting an ADR-193 anti-vacuity floor** to `tests/scripts/test-tenant-integration-gate-verdict.sh`
  and to `tests/scripts/test-betterstack-query-archive.sh` (neither has one; the latter exits 0 on
  zero cases).
- **`model.c4`'s `github -> betterstack` edge says Rule D "blocks on any file the PR touches".** The
  `--changed` job is advisory, not blocking — its own comment in `ci.yml` says so. AC15 corrects the
  count beside this sentence and leaves the sentence; correcting it is a separate prose fix.

Two findings surfaced by the CPO review that are real, pre-existing, and deliberately not absorbed
here — each passes the `wg-defer-only-after-inline-triage` triple test (none is a <30-minute
one-file change, each has a concrete trigger, each is plausible within six months), so each gets a
tracking issue rather than in-plan documentation:

- **The eight operator-only skills ship in the customer payload and are advertised on the public
  docs site.** `plugins/soleur/docs/_data/skills.js` categorises them as "Workflow", so a customer
  invoking `/soleur:user-set-role` gets `missing Supabase secrets in soleur/prd` and
  `/soleur:trigger-cron` POSTs at Soleur production with an empty bearer. Only
  `provision-doppler.sh` carries the ADR-179-shaped monorepo-only refusal. This PR opens all eight
  files but adding the refusal to the other seven is a different change with its own failure modes.
  **File a new issue.** An earlier draft routed this to #2719 on a review suggestion; `gh issue view
  2719` returns "feat: integrate skill-security-auditor pattern into skill-creator + agent-finder",
  which is not this. Verified rather than assumed.
- **`bsky-setup.sh`, `x-setup.sh` and `discord-setup.sh` write the user's tokens into `.env`.**
  Transport confinement does nothing about a `.env` that gets committed. Named here so it is not
  assumed closed by this PR.

## References

- Issues: #7898 (OPEN, `type/security`), #7055 (OPEN, `flaky`). Context, each verified live with
  `gh issue view` / `gh pr view` rather than cited from memory: #7873 (CLOSED — the Rule D origin),
  #7797 (OPEN — the xtrace refusal), #7855 (CLOSED — the glob-crossing allowlist defect), **PR #7914
  (MERGED — "a delegated cap refusal must persist its audit row — migration 137")**, #3934 (OPEN —
  the synthetic-fixture sweeper).
- **Citation correction:** the test file's own docstring attributes the return-status rewrite to
  #7829, and an earlier draft of this plan repeated that. #7829 is actually
  "sentry: byok-cap-exceeded may page nobody — the only rule of 27 with fallthrough_type NoOne" — a
  different piece of work. The change that landed migration 137 is PR #7914. This plan cites #7914;
  the stale attribution in the test docstring is left alone as out of scope, but noted so the next
  reader does not re-inherit it.
- `scripts/lint-shell-trace-credential-refusal.py` › `check_rule_d`, `_destination_vars`,
  `_adjudicated`, `_pin_re`, `_compared_to_literal_const`.
- `scripts/fixtures/shell-trace-refusal/compliant-canonical.sh`,
  `compliant-ruled-pinned-destination.sh`.
- `scripts/betterstack-ingest-probe.sh` › the authority-extraction block (the #7855 precedent).
- `apps/web-platform/supabase/migrations/137_byok_cap_breach_audit_row.sql`.
- `scripts/tenant-integration-gate-verdict.sh`, `.github/workflows/tenant-integration.yml`.
- ADR-040, ADR-193, ADR-198, ADR-206, ADR-208, ADR-179, ADR-052.
