---
title: "chore(followthrough): mechanically enforce the ${VAR:?} ban with a CI guard + convert the 14 non-compliant probes"
issue: 6757
branch: feat-one-shot-6757-followthrough-varq-ban-guard
type: chore
lane: single-domain
date: 2026-07-22
brand_survival_threshold: aggregate pattern
---

# 🐛→🔒 Fix #6757 — CI guard for the `${VAR:?}` / `${VAR?}` ban in follow-through probes + convert the 14 offenders

## Enhancement Summary

**Deepened on:** 2026-07-22
**Sections enhanced:** Phase 1 (census), Acceptance Criteria (AC7), Observability (5-field schema), Sharp Edges (+3)
**Review agents used:** code-simplicity-reviewer, Explore (bash non-vacuity)

### Key Improvements
1. **Line-number correctness (both reviewers, independently):** the guard census must run `grep -n` on the RAW file FIRST, then filter full-line comments — piping `grep -v '^#' | grep -n` re-indexes line numbers against the stripped stream and mis-cites every offender. Phase 1.2 corrected.
2. **AC7 de-fanged:** removed a raw `grep ':?}'` that legitimately matches the 3 comment-only files' documentation (would read as a false failure). AC5's comment-stripped canonical census is the real gate.
3. **Observability** brought to the strict 5-field schema (passes deepen-plan Phase 4.7).

### New Considerations Discovered
- Regex is named-var only; positional-param `${1:?}` is uncaught (no live gap — all secrets named). Kept byte-faithful to the documented census; broadening path noted.
- Min-cardinality floor should key on resolved-target-dir, not `$1`-presence.
- A single self-contained `.test.sh` (exec-bit style) is an acceptable simpler equivalent to the two-file shape.

### Mandatory deepen-plan gates
- Phase 4.6 (User-Brand Impact): PASS — section present, threshold `aggregate pattern`.
- Phase 4.7 (Observability): PASS after 5-field schema fix.
- Phase 4.8 (PAT-shaped variable): PASS — `GH_TOKEN` is a follow-through secret name, not a `var.*_token`/`TF_VAR_*` shape; no match.
- Phase 4.9 (UI wireframe): N/A — no UI surface.
- Phase 4.4 (precedent-diff): guard mirrors `scripts/followthrough-exec-bit.test.sh` (cited throughout).

## Overview

`knowledge-base/engineering/operations/runbooks/followthrough-convention.md:24` bans the
`: "${VAR:?msg}"` assertion form (and the colon-less `${VAR?msg}`, which has identical
semantics) in follow-through probes. Under the sweeper's non-interactive shell, that
word-expansion **aborts with status 1** the instant the variable is unset/empty, so any
trailing `|| { echo TRANSIENT; exit 2; }` is dead code and an unprovisioned secret reports
**FAIL (exit 1)** instead of **TRANSIENT (exit 2)**. In the sweeper's exit contract
(`scripts/sweep-followthroughs.sh`; convention §Exit contract) `exit 1 = FAIL = "do NOT close"`,
so the sweeper posts a comment and leaves the tracker open — a probe whose secret is unprovisioned
posts a **daily false-FAIL comment forever**.

The convention is documented but enforced **nowhere mechanically**, so it recurs (provenance:
`wg-when-an-audit-identifies-pre-existing`, surfaced by the #6297 anthropic-admin-key probe which
was compliant by construction and out of scope there).

This plan ships, in **one PR**:

1. A **CI guard** — `scripts/lint-followthrough-varq-ban.sh` — that runs the comment-stripped
   census over `scripts/followthroughs/*.sh` (excluding `*.test.sh`) and FAILs when any
   **executable** line carries the banned form. Registered explicitly in `scripts/test-all.sh`
   (twice: a live-tree run + its mutation `.test.sh`), so it actually gates on every PR.
2. **Conversion of the 14 non-compliant probes** to the documented compliant guard so the
   live-tree run is green at merge.

Guard + conversions land **together** so `main` is never red; the RED-in-history evidence (the
guard catching the real defect) comes from the guard's own `.test.sh` mutation fixtures, which
are independent of the live tree.

## Research Reconciliation — task premise vs. live `main`

Every premise in the task was re-derived against the current worktree at plan time.

| Premise (from task) | Live reality (verified 2026-07-22) | Plan response |
|---|---|---|
| 14 executable-line offenders (exact list) | Census `for f in scripts/followthroughs/*.sh; do case "$f" in *.test.sh) continue;; esac; grep -vE '^\s*#' "$f" \| grep -qE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?' && echo "$f"; done` returns **exactly** the 14 named | Convert those 14 |
| 6 comment-only files must stay excluded (issue said 5; +workspaces-luks-soak-6604) | (all-files-with-form) − (executable-line-form) = **exactly** the 6: anthropic-admin-key-6297, autovacuum-thrash-6168, inngest-rls-drop-6488, workspaces-luks-soak-6604, zot-mirror-connector-6416, zot-soak-6122 | Guard must keep all 6 green |
| Trailing-comment strip risk on the 6 | **All 6 document the ban in FULL-LINE comments** (each match starts with `#` after leading whitespace: lines 31/30/35/40/62/138 respectively) | The canonical `grep -vE '^\s*#'` strip handles all 6 cleanly → **no rewording and no trailing-comment-aware strip needed**. Documented as a Sharp Edge (future-facing limitation only). |
| `scripts/test-all.sh` enumerates suites by hand; `scripts/*.test.sh` not auto-globbed | Confirmed: auto-glob (line 316) covers `scripts/lib/*.test.sh` but **not** `scripts/*.test.sh`; `scripts/lint-orphan-test-suites.sh` (registered line 151) mechanically FAILs any unregistered `scripts/*.test.sh` | Register the new `.test.sh` **explicitly** via `run_suite`; add an AC that greps the run log to confirm both new labels appear |
| The runner job has bash (#6454 class) | `.github/workflows/ci.yml:522` `test-scripts` job `runs-on: ubuntu-latest`, runs `bash scripts/test-all.sh scripts` (line 576); the synthetic `test` aggregator `needs: [..., test-scripts]` (line 625) | Register in the `if want_scripts;` block — it runs in the merge-blocking `test-scripts` shard |
| Canonical BAD / GOOD | `ghcr-minter-live-6031.sh:28` = `: "${SENTRY_AUTH_TOKEN:?…}"` (BAD); `cert-reissue-markers-6698.sh` carries no banned form (GOOD) | Conversion target is the convention's compliant form |
| Issue #6757 state | **OPEN**, title "14 of 40 probes use the banned `${VAR:?}` form" | Premise valid, not stale |
| Pre-existing guard? | None (`ls scripts/ \| grep -iE 'varq\|ban'` → nothing) | Net-new guard |

**Shape of the 14 (surveyed):** all 14 use the **identical** `: "${VAR:?VAR must be set}"`
colon-command assertion form — **none** use the colon-less `${VAR?}` form, **none** are inline
in a larger command, and **none** carry trailing `|| exit 2` dead code. Three guard MULTIPLE
secrets (each line converted separately):

| Probe | Banned lines | Secret(s) |
|---|---|---|
| ac10-workspace-reconcile-sentry-4246.sh | 22 | SENTRY_AUTH_TOKEN |
| ac8-founder-ambiguous-soak-5673.sh | 30 | SENTRY_AUTH_TOKEN |
| **canary-promotion-5875.sh** | 30,31,32 | WEBHOOK_DEPLOY_SECRET, CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET |
| community-monitor-checkin-soak-5728.sh | 35 | SENTRY_AUTH_TOKEN |
| deploy-ghcr-pull-recovery-6400.sh | 29 | SENTRY_AUTH_TOKEN |
| ghcr-minter-live-6031.sh | 28 | SENTRY_AUTH_TOKEN |
| gh-pages-cert-reissue-6657.sh | 22 | GH_TOKEN |
| moved-block-wedge-5887.sh | 29 | GH_TOKEN |
| phase3-ga-soak-5274.sh | 35 | SENTRY_AUTH_TOKEN |
| reconcile-ff-only-sentry-4977.sh | 33 | SENTRY_AUTH_TOKEN |
| sentry-checkins-3859.sh | 20 | SENTRY_AUTH_TOKEN |
| sync-health-residual-5689.sh | 37 | SENTRY_AUTH_TOKEN |
| **zot-login-gate-erofs-repaired-6565.sh** | 52,53,54 | BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD |
| **zot-login-gate-names-failure-6497.sh** | 44,45,46 | BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD |

## User-Brand Impact

**If this lands broken, the user (non-technical founder) experiences:** either (a) the guard
fails to catch a *future* banned-form probe → the false-FAIL-forever bug recurs → a GitHub
tracker posts a **daily false-FAIL comment** and never auto-closes (operator noise / eroded
trust in the sweeper), or (b) the guard **false-trips** on a compliant tree → reddens the
`test-scripts` shard → blocks every merge until fixed.

**If this leaks, the user's data is exposed via:** N/A — no data surface. The change touches
only repo-local bash guards and probe scripts; no secrets, PII, schemas, or runtime data paths.

**Brand-survival threshold:** `aggregate pattern` — the harm is recurring operator-facing
noise accruing across probes/days, not a single-user data incident. No per-PR CPO sign-off
required; diff touches no sensitive path, so no scope-out bullet needed.

## Implementation Phases

### Phase 0 — Preconditions (verify against the live tree at /work start)
- Re-run the canonical census; confirm the 14 offenders and the 6 comment-only exclusions match
  the Research Reconciliation table (guards against drift since plan time).
- Confirm no offender carries trailing `|| { … exit 2; }` dead code (survey shows none).

### Phase 1 — The guard script (`scripts/lint-followthrough-varq-ban.sh`) — NEW
Design (single source of truth for the census; the `.test.sh` drives THIS exact code, never a
re-implementation):
- Accept an optional target-dir arg: `TARGET_DIR="${1:-scripts/followthroughs}"`. Default →
  resolve against `git rev-parse --show-toplevel` (mirror `followthrough-exec-bit.test.sh`'s
  repo-root `cd`); an explicit arg → operate on that dir verbatim (this is how the `.test.sh`
  points it at a sandbox).
- For each `"$TARGET_DIR"/*.sh` where the basename does **not** end in `.test.sh`:
  census = `grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?' "$f" | grep -vE '^[0-9]+:[[:space:]]*#'`.
  Any surviving line is a violation; print `<file>:<line>` for each.
  - **Line-numbering order is load-bearing (deepen-plan finding):** run `grep -n` on the RAW
    file FIRST, then drop full-line-comment hits with `grep -vE '^[0-9]+:[[:space:]]*#'`. Piping
    `grep -vE '^\s*#' | grep -n …` (the canonical *boolean* census order) re-indexes `-n` against
    the comment-stripped stream, so every reported line number is wrong (e.g. ghcr-minter-live's
    real line 28 prints as 4). Detection is identical either way; only the diagnostic `file:line`
    differs, and the guard's whole value is naming the offender accurately.
- **Detection semantics are identical to the canonical census**: `:?\?` = optional colon then
  literal `?`, catching both `${VAR:?}` and `${VAR?}`; the `^[0-9]+:[[:space:]]*#` filter strips
  both column-0 and indented full-line comments (verified against all 6 comment-only files). The
  guard remains a faithful executable form of the documented census.
- Exit **1** if any violation; exit **0** if none; exit **2** on internal error (e.g. dir absent).
- **Minimum-cardinality floor (production run only):** when `$1` is unset (default dir), require
  ≥10 non-test probes scanned, else fail — a broken glob must not pass vacuously (copy the
  exec-bit floor rationale). Skip the floor when an explicit dir is passed (the sandbox is small).

### Phase 2 — The mutation test (`scripts/lint-followthrough-varq-ban.test.sh`) — NEW (non-vacuity core)
Self-contained; builds a `mktemp -d` sandbox **outside** `scripts/followthroughs/` and invokes
the Phase-1 guard with the sandbox path. Assert **both directions** + the comment-collision class:
- **GREEN:** sandbox seeded only with COMPLIANT fixtures (an `if [[ -z "${FOO:-}" ]]; then echo
  "TRANSIENT: FOO not set" >&2; exit 2; fi` file) → guard exits **0**.
- **RED (`:?` form):** add a fixture with an executable `: "${FOO:?msg}"` line → guard exits
  **non-zero**, and its output names that file.
- **RED (colon-less `?` form):** add a fixture with `${BAR?msg}` on an executable line → guard
  exits **non-zero** (proves the `:?\?` breadth; a `:?`-only regex would miss this).
- **Comment-collision GREEN:** a fixture whose banned form appears ONLY in a full-line `#`
  comment → guard exits **0** (proves the `^\s*#` strip; mirrors the 6 real comment-only files).
- **Guard-does-not-flag-its-own-data:** the sandbox is under `mktemp`, so the *live* guard never
  sees fixtures — assert the production run (no arg) still passes with the fixtures present.
- Tempfile ownership: `trap 'rm -rf "$SANDBOX"' EXIT` cleaning **only** the mktemp dir this script
  created (satisfies `scripts/lint-trap-tempfile-ownership.sh`, registered test-all.sh:150).

These fixtures are the **RED-in-history proof**: the guard demonstrably catches the banned form
independent of the (post-conversion, green) live tree — resolving the ordering trap.

### Phase 3 — Register in `scripts/test-all.sh` — EDIT (highest-risk placement)
Add two `run_suite` lines inside the `if want_scripts; then` explicit block (near the existing
`followthrough-exec-bit` / `sweep-followthroughs` lines ~156–161), with a comment citing #6757
and the orphan-suite class:
```bash
run_suite "scripts/followthrough-varq-ban-live" bash scripts/lint-followthrough-varq-ban.sh
run_suite "scripts/followthrough-varq-ban"      bash scripts/lint-followthrough-varq-ban.test.sh
```
- The `-live` line runs the guard against the **real** tree (the actual gate).
- The second line runs the mutation test and satisfies `lint-orphan-test-suites.sh` (its regex
  `^[[:space:]]*run_suite .*[\"' ]scripts/lint-followthrough-varq-ban.test.sh([\"' ]|$)` matches
  `bash scripts/lint-followthrough-varq-ban.test.sh`).
- Both `chmod +x` the new `.sh`/`.test.sh` (the sweeper/CI consume the index mode; exec-bit gate
  only covers `scripts/followthroughs/`, but keep 100755 for consistency).

### Phase 4 — Convert the 14 probes — EDIT
For **every** banned line in the table above, replace
`: "${VAR:?VAR must be set}"` with:
```bash
if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT: VAR not set" >&2; exit 2; fi
```
- Multi-secret files (canary-promotion-5875, zot-login-gate-erofs-repaired-6565,
  zot-login-gate-names-failure-6497) → convert **each** of the 3 lines (three guards, or one
  combined `if [[ -z … || -z … ]]`; prefer three explicit guards so the TRANSIENT message names
  the specific missing secret).
- Preserve each file's existing `set` flags and surrounding logic; missing secret → exit 2
  (TRANSIENT), present-but-failing check → its existing real FAIL/PASS code. Leave no dangling
  dead code (survey confirms none exists to remove).

### Phase 5 — Cross-reference the convention doc — EDIT (loop-closing)
Add one line to `followthrough-convention.md` §Author workflow near the existing ban (line 24):
"Enforced mechanically by `scripts/lint-followthrough-varq-ban.sh` (registered in
`scripts/test-all.sh`, `test-scripts` shard)." — so the convention is now documented **and**
cites its mechanical gate.

## Files to Create
- `scripts/lint-followthrough-varq-ban.sh` (the guard; parameterized census)
- `scripts/lint-followthrough-varq-ban.test.sh` (mutation both-directions + comment-collision)

## Files to Edit
- `scripts/test-all.sh` (+2 `run_suite` lines in `want_scripts` block)
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` (+1 cross-ref line)
- The 14 probes under `scripts/followthroughs/` (per the table): ac10-workspace-reconcile-sentry-4246.sh,
  ac8-founder-ambiguous-soak-5673.sh, canary-promotion-5875.sh, community-monitor-checkin-soak-5728.sh,
  deploy-ghcr-pull-recovery-6400.sh, ghcr-minter-live-6031.sh, gh-pages-cert-reissue-6657.sh,
  moved-block-wedge-5887.sh, phase3-ga-soak-5274.sh, reconcile-ff-only-sentry-4977.sh,
  sentry-checkins-3859.sh, sync-health-residual-5689.sh, zot-login-gate-erofs-repaired-6565.sh,
  zot-login-gate-names-failure-6497.sh

## Acceptance Criteria (Pre-merge / PR)

1. `scripts/lint-followthrough-varq-ban.sh` exists, is `100755`, and takes an optional target-dir arg.
2. **Non-vacuity — RED both directions on fixtures:** `bash scripts/lint-followthrough-varq-ban.test.sh`
   exits 0, and internally proves: banned `:?` fixture → guard non-zero; banned colon-less `?`
   fixture → guard non-zero; compliant fixture → guard 0; full-line-comment-only fixture → guard 0.
3. **Guard is actually RUN (registration confirmed, not assumed):**
   `bash scripts/test-all.sh scripts 2>&1 | grep -E 'scripts/followthrough-varq-ban(-live)?'`
   shows BOTH `--- scripts/followthrough-varq-ban-live ---` and `--- scripts/followthrough-varq-ban ---`
   each followed by `[ok]`.
4. **Orphan-suite gate passes:** `bash scripts/lint-orphan-test-suites.sh` → "orphan test suites: none".
5. **Live tree green after conversion:** the canonical census
   `for f in scripts/followthroughs/*.sh; do case "$f" in *.test.sh) continue;; esac; grep -vE '^\s*#' "$f" | grep -qE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?' && echo "$f"; done`
   returns **empty** (0 executable hits across the 14).
6. **The 6 comment-only files still excluded / guard green:** `bash scripts/lint-followthrough-varq-ban.sh`
   exits 0 (anthropic-admin-key-6297, autovacuum-thrash-6168, inngest-rls-drop-6488,
   workspaces-luks-soak-6604, zot-mirror-connector-6416, zot-soak-6122 remain untouched and pass).
7. **Semantics preserved:** each of the 14 now guards its secret(s) with
   `if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT…" >&2; exit 2; fi`; multi-secret files convert
   all lines. No banned form remains on any **executable** line — verified by AC5's canonical
   census returning empty. (Do NOT assert a raw `grep ':?}' scripts/followthroughs/*.sh` is empty:
   3 of the 6 comment-only files — autovacuum-thrash-6168, inngest-rls-drop-6488,
   workspaces-luks-soak-6604 — carry the literal `${VAR:?}` in a full-line *comment* that
   legitimately survives a raw grep; the comment-stripped census is the correct gate.)
8. **Whole-suite exit gate:** `bash scripts/test-all.sh scripts` exits 0.
9. **No fixture leakage:** the guard's fixtures live under `mktemp` (never `scripts/followthroughs/`);
   `git status` shows no new tracked file under `scripts/followthroughs/`.
10. Convention doc cross-references the new guard.

## Observability

This is a CI-gate change (repo-root `scripts/`, outside the plan Phase 2.9 code/infra trigger set
— no `apps/*/server`, `apps/*/infra`, `plugins/*/scripts`, no new runtime infra). The 5-field
schema is declared for completeness; the guard's liveness is its CI run, fail-loud with no
dashboard and no SSH.

```yaml
liveness_signal:
  what: two run_suite lines execute the guard (live tree) + its mutation test on every CI run
  cadence: every PR push and every merge to main (ci.yml test-scripts job, line 522)
  alert_target: the synthetic `test` required check (needs test-scripts) reddens on failure
  configured_in: scripts/test-all.sh want_scripts block + .github/workflows/ci.yml:522/576
error_reporting:
  destination: GitHub Actions job log for the test-scripts shard (non-zero exit + [FAIL] line)
  fail_loud: yes — guard exits 1 on violation; test exits non-zero on any assertion failure; no swallow
failure_modes:
  - mode: banned ${VAR:?}/${VAR?} form reintroduced in a follow-through probe
    detection: scripts/lint-followthrough-varq-ban.sh (-live run) exits 1, naming file:line
    alert_route: test-scripts shard red → synthetic `test` check red → merge blocked
  - mode: guard logic regresses (regex narrows, comment-strip breaks)
    detection: scripts/lint-followthrough-varq-ban.test.sh mutation assertions fail
    alert_route: test-scripts shard red → merge blocked
  - mode: a new scripts/*.test.sh is left unregistered (orphan-suite class)
    detection: scripts/lint-orphan-test-suites.sh exits 1
    alert_route: test-scripts shard red → merge blocked
logs:
  where: GitHub Actions run logs for the test-scripts job (run_suite label + [ok]/[FAIL] lines)
  retention: GitHub Actions default (90 days)
discoverability_test:
  command: bash scripts/test-all.sh scripts 2>&1 | grep -E 'scripts/followthrough-varq-ban(-live)?'
  expected_output: two labels "--- scripts/followthrough-varq-ban-live ---" and "--- scripts/followthrough-varq-ban ---", each followed by an [ok] line
```

## Domain Review

**Domains relevant:** none

Infrastructure/tooling change — a CI guard + mechanical bash conversions enforcing an existing
documented convention. No UI surface (no files under `components/**`, `app/**`), no product,
legal, finance, ops, or data-model implications.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (61 open) intersected against
`scripts/followthroughs`, `test-all.sh`, `lint-orphan`, `followthrough-convention`, `6757`
returned **zero** body matches.

## Architecture Decision (ADR/C4)

Skip — no architectural decision. The ban is an existing decision recorded in
`followthrough-convention.md`; this plan mechanically *enforces* it (guard) and *cleans up*
existing violations (conversions). No ownership/tenancy/substrate/trust-boundary change; a
competent engineer reading the current ADRs + C4 would not be misled about the system after
this ships. (Checked: no external actor/system/data-store/access-relationship introduced.)

## Sharp Edges

- **Trailing-comment strip is full-line-only (currently non-triggering).** The census strip
  `grep -vE '^\s*#'` removes only full-line comments. A future *compliant* probe that documents
  the banned form in a **trailing** `# … ${VAR:?} …` comment on an executable line would
  false-trip the guard. All 6 current comment-only files use full-line comments (verified), so
  this does not fire today. Convention is to document the ban in full-line comments; the guard is
  kept byte-identical to the documented census deliberately (the guard IS the census). If a
  trailing-comment case ever appears, reword to a full-line comment rather than complicating the
  strip.
- **`scripts/*.test.sh` is NOT auto-globbed by test-all.sh.** The new `.test.sh` MUST be
  registered by an explicit `run_suite` line or it silently never gates (the #5417/#6734 orphan
  class) — and `lint-orphan-test-suites.sh` will fail CI if it isn't. AC3 + AC4 verify the
  registration actually took, not "picked up automatically."
- **The `-live` run and the `.test.sh` are BOTH required.** The `.test.sh` alone proves the guard
  *can* catch the form (fixtures) but never checks the real tree; the `-live` line alone would go
  green forever after conversion with no RED-in-history proof. Register both.
- **Ordering trap:** guard registered + conversions in the same commit means no RED moment in the
  live tree's history — this is intended; the RED evidence is the `.test.sh` mutation fixtures.
  Land guard + all 14 conversions in ONE PR so `main` is never red.
- **Multi-secret probes convert every line.** canary-promotion-5875 (3), the two zot-login-gate
  probes (3 each) — a per-file single-line edit would leave a live `${VAR:?}` and keep the
  `-live` run red.
- **Regex is named-var only (deepen-plan finding; no live gap).** `\$\{[A-Za-z_][A-Za-z0-9_]*:?\?`
  requires the parameter name to start with a letter/underscore, so a positional-param assertion
  `: "${1:?}"` / `${9:?}` (same abort-status-1 semantics) is NOT caught. All 14 offenders and every
  probe secret are **named** vars, so there is no live gap — the regex is kept byte-faithful to the
  documented canonical census deliberately. If a future probe ever guards a positional param,
  broaden the first char class to `[A-Za-z0-9_]` (safe: still won't match `${VAR:-}`).
- **Min-cardinality floor keys on the resolved target dir, not arg presence (deepen-plan finding).**
  Gate the ≥10 floor on "resolved TARGET_DIR == default `scripts/followthroughs`", NOT on `$1`
  being unset — otherwise a future caller passing the real dir explicitly
  (`lint-followthrough-varq-ban.sh scripts/followthroughs`) silently bypasses the vacuity floor.
- **Two-file vs self-contained is acceptable either way.** The plan prescribes guard `.sh` +
  companion `.test.sh` (the task's stated shape). A single self-contained `.test.sh` with an
  internal census *function* driven over both the mktemp fixtures (both-directions RED) and the
  live tree (the gate) — mirroring `followthrough-exec-bit.test.sh` — is an equally valid,
  slightly simpler alternative; /work may collapse to it PROVIDED it keeps (a) the both-directions
  mutation proof and (b) a live-tree assertion, and registers the `.test.sh` via `run_suite`.

## Risks & Mitigations

- **Guard false-negative (misses a form):** mitigated by the colon-less-`?` RED fixture in AC2 —
  a `:?`-only regex would pass that fixture, so the test would go red if the regex narrowed.
- **Guard false-positive on the 6 comment-only files:** mitigated by AC6 (live run over the real
  tree exits 0) + the comment-collision GREEN fixture in AC2.
- **Silent non-registration:** mitigated by AC3 (grep the run log for both labels) + AC4
  (orphan-suite linter).
- **Conversion changes probe semantics:** the compliant form is a strict improvement — unset
  secret now yields TRANSIENT (retry) instead of FAIL (false comment); present-but-failing checks
  are untouched. No probe's PASS/real-FAIL logic changes.
