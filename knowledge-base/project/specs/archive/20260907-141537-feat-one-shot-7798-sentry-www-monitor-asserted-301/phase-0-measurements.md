---
title: "Phase 0 measurements — #7798 falsification probe and preconditions"
branch: feat-one-shot-7798-sentry-www-monitor-asserted-301
issue: 7798
date: 2026-09-07
---

# Phase 0 measurements

Every number below was measured in-session on 2026-09-07. Nothing here is
carried over from the plan's own snapshot; where the two disagree, the
disagreement is recorded rather than reconciled silently.

## 0.1 Falsification probe (GATING) — CONFIRMS

The plan's single un-measured load-bearing claim was that Better Stack with
`follow_redirects = false` and `expected_status_codes = [301]` evaluates the
**pre-redirect** 301. Three transient monitors were created against
`https://www.soleur.ai/` with `confirmation_period = 0`, observed, and deleted.

| Probe | Config | Result |
|---|---|---|
| MAIN | `expected_status_codes [301]`, `follow_redirects false` | **`up`** against the live 301, all 4 regions (as/au/eu/us) |
| Control A | `expected_status_codes [200]`, `follow_redirects false` | **`down`** against the same live 301 |
| Control B | `expected_status_codes [301]`, `follow_redirects true` | **HTTP 422, refused at create** |

**Verdict: CONFIRMS.** Control A is the load-bearing half — a monitor reporting
`up` proves nothing on its own, because a vacuous monitor reports `up` too.
Control A differs from MAIN in exactly one token and goes `down`, so the
assertion is genuinely evaluated against the pre-redirect response.

**Control B is a stronger result than the plan anticipated.** Better Stack
refuses the vacuous combination at the API:

```
422 {"errors":{"base":["Cannot follow redirects when expecting a 3xx status code"]}}
```

The vendor makes this issue's defect *unrepresentable*. Guard 1's M1 row
(`follow_redirects false` → `true`) therefore has a second, independent
backstop at apply time — the guard still earns its place by catching it at PR
time instead of via a failed production apply, but M1's stated rationale ("the
probe resolves to the apex 200 and `[301]` can never match") is not what would
actually happen. It would fail to create at all.

Free-tier acceptance of `monitor_type = "expected_status_code"` is answered by
the same probe: **accepted** (HTTP 201). The in-repo "precedent" could not
answer this, being paid-tier-`count`-gated and never applied.

### `remember_cookies = false` is REQUIRED — a plan gap the probe caught

The first create attempt failed:

```
422 {"errors":{"base":["Cannot keep cookies when redirecting when expecting a 3xx status code"]}}
```

`remember_cookies` is present in the pinned provider `BetterStackHQ/better-uptime
0.20.17` (verified via `terraform providers schema -json` from a version-pinned
scratch root) as `optional = true, computed = true`. **Computed is the trap:**
omitting the attribute sends nothing, the API default (`true`) applies, and the
apply fails with the 422 above. The plan's Phase 2 attribute table does not list
it, so the block as specified would not have applied. It is added, with the
error text quoted inline as the reason.

### Cleanup verified

All three transient monitors deleted (HTTP 204). Post-cleanup the workspace
holds exactly its prior three monitors and no `TRANSIENT`-named residue —
asserted, not eyeballed.

## 0.2 Live Sentry state — root cause HOLDS, but two plan figures are STALE

Monitor `1221117` (`soleur-ai-www`), assertion `equals 301`, `status: active`.

Check rows via `/api/0/projects/jikigai-eu/web-platform/uptime/1221117/checks/`:

| Monitor | Last 10 checks |
|---|---|
| `soleur-ai-www` | **10/10 failing** — 9 `failure_incident` + 1 `failure`, every row `httpStatusCode 301`, `assertionFailureData` naming `equals 301` |
| `soleur-ai-acme-carveout-probe` | 10/10 `success` at 404 |
| `soleur-ai-apex` | 10/10 `success` at 200 |

The root cause **holds**: the monitor has never passed a check.

**Correction 1 — `uptimeStatus` is not health, and reading it as health would
have inverted this session's conclusion.** The list endpoint reports
`uptimeStatus: 1` (up) for `soleur-ai-www` *while every check is failing*. The
plan measured `2` earlier the same day. Both readings are real; the field
oscillates. Taken alone it would have "refuted" the issue.

**Correction 2 — the incident is not a single 101-day standing incident.**
`WEB-PLATFORM-11` is presently `status: resolved`, `count: 485`,
`firstSeen: 2026-06-09T20:55:47Z`. The plan states "578 events,
`firstSeen 2026-05-29T10:30:46Z`, still unresolved". Neither the count, the
first-seen, nor the status matches live state.

**The mechanism explains both corrections, and it is a finding the plan does not
have.** `deploy-docs.yml` runs a `Pause soleur_www uptime monitor` /
`… then resume` bracket on every docs deploy. Pausing halts checks, so Sentry
resolves the open downtime issue; resuming restarts the failing checks, and
after `downtimeThreshold: 3` a *new* issue group opens. Runs at
`2026-09-07T09:03:26Z` and `10:15:01Z` bracket the observed
`failure_incident → failure` transition at `10:20:45Z` exactly.

So the defect is not one permanently-red monitor. It is a **recurring cycle of
incidents that every docs deploy masks and re-arms**, which is why the event
count and first-seen drift. Phase 4's removal of the bracket is therefore
load-bearing for more than deleting a stranding hazard: it stops the periodic
laundering of the alarm's own failure record.

**This is why AC23 must keep both halves.** `uptimeStatus 1` alone is satisfied
*right now* by the broken monitor. Only `uptimeStatus 1` **and** recent checks
`success` distinguishes a fix from a reset.

## 0.3 Better Stack quota — measured live

3 monitors (`app.soleur.ai/health` unmanaged, `soleur dot ai apex`,
`soleur app dashboard`) and 9 heartbeats. This PR's monitor is the **4th of 10**.
12 resources already coexist, so the cap is not a pooled 10 — the plan's
refutation of the pooled-quota theory is re-confirmed against live state.

## 0.4 ADR ordinal

Highest ADR across all **71** `origin/*` refs is **203**. `ADR-204` is free.

## 0.5 `fixtures/dns.tf.pr4a-baseline` — deliberate carve-out

Referenced by four scripts: `apex-single-node-replace-mutation.test.sh`,
`generate-apex-rollback-pr.sh`, `generate-apex-rollback-pr.test.sh`,
`www-apex-canonicalizer-mutation.test.sh`. It carries the stale claim at line
304 (`Runtime drift of the 301 is guarded by sentry_uptime_monitor.soleur_www.`).

**Decision: not edited.** `generate-apex-rollback-pr.sh` uses this file as the
*content it restores* when generating a rollback PR — editing it would change
what a rollback produces, i.e. corrupt a recovery artifact to fix a comment. It
is a frozen pre-cutover baseline and the repo's convention is that migration
fixtures record the old state. Recorded here so the disposition is visible in
the diff rather than silent (AC15).

## 0.6 `hcl_block()` against `uptime-alerts.tf`

The extractor takes `<type> <name> <file>` and is path-agnostic — the awk
program interpolates only `$1`/`$2` and reads `$3`. Verified by running it
against `uptime-alerts.tf` for `betteruptime_monitor.soleur_apex`: extracts the
full 25-line block, header through closing brace. This is the first call site
outside the `dns.tf` / `cf-pages.tf` / `seo-bulk-redirects.tf` trio and it needs
no change.

## 0.7 Pre-change baseline

`apps/web-platform/infra/www-apex-canonicalizer.test.sh` → `OK: 24/24`, exit 0.
The live arm is `EXPECTED_CASES=24`; both arms must still be bumped together.
123 `.test.sh` steps are registered in `infra-validation.yml`.

## Phase 1.4 — mutation battery (AC7)

Run against pristine copies with restore verified byte-identical afterwards. The
unmutated control ran FIRST (green — a red baseline would void every row), and
each row asserted the mutation had landed before reading a verdict.

**16 rows: 15 RED-expected all red, 1 PASS-expected green.**

| # | Mutation | Want | Got |
|---|---|---|---|
| M1 | `follow_redirects` false → true | RED | RED |
| M2 | `expected_status_codes` `[301]` → `[301, 200]` | RED | RED |
| M3 | rename the resource so the extractor finds nothing | RED | RED |
| M4a | codes wrong, `follow_redirects` still correct | RED | RED |
| M4b | `follow_redirects` wrong, codes still correct | RED | RED |
| M5 | add a `count` gate | RED | RED |
| M6a | `pronounceable_name` collides with the apex sibling | RED | RED |
| M6b | `pronounceable_name` deleted | RED | RED |
| M7 | `remember_cookies` false → true | RED | RED |
| M8 | re-add the pause/resume bracket to `deploy-docs.yml` | RED | RED |
| H1a | neuter `pass()` | RED | RED |
| H1b | neuter `fail()` **while a real defect is present** | RED | RED |
| H2 | reformat only — inner spaces in the list, realigned `=` | **PASS** | **PASS** |
| FLOOR | revert the `EXPECTED_CASES` bump | RED | RED |
| OPERAND | degenerate `UPTIME_TF` to empty | RED | RED |
| OPERAND2 | point `UPTIME_TF` at a nonexistent file | RED | RED |

### Two rows were wrong on the first pass, and both were MY errors, not the guard's

**M1/M4b first read as SURVIVED.** The mutation had landed — in the *header
comment* at `uptime-alerts.tf:38`, which quotes `follow_redirects = false` in
prose, not in the config at line 198. The suite strips comments before asserting,
so it correctly ignored it. Re-anchored on the config line (newline + exactly two
spaces + the assignment, which a `#`-prefixed line cannot match) and both go red.
The false survivor is incidentally a positive result for the comment-stripper.

**H1b (`fail()` neutered alone) is an EQUIVALENT mutant, not a gap.** On an
all-green suite `fail` is never called, so neutering it changes nothing. It is
only meaningful compounded with a real defect — which is the state the
`PASS + FAIL == CASES` identity exists to catch — and it reds there.

### Axes NOT edited, stated plainly

- **Population growth.** The guard is scoped to one named resource, so a
  *second*, non-compliant `betteruptime_monitor` added to the file is not caught
  by it. That is deliberate (Guard 1's stated property is about this resource),
  and the repo-wide coverage question is `terraform-target-parity.test.ts`'s.
- **Demotion.** No prose-conditionality axis applies: every assertion reads a
  `.tf` value, not a prescription.
- **Authority/root input.** The extractor's own `awk` program is not mutated,
  only its operands (OPERAND/OPERAND2 cover the path input).
