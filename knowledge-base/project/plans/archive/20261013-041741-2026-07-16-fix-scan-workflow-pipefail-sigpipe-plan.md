---
title: "fix: scan-workflow.test.sh false-reports under pipefail + grep -q SIGPIPE"
date: 2026-07-16
type: fix
issue: 6572
branch: feat-one-shot-6572-scan-workflow-pipefail-sigpipe
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix: `scan-workflow.test.sh` false-reports under `pipefail` + `grep -q` SIGPIPE

> **Lane note:** no `spec.md` exists for this branch, so `lane:` could not be carried forward —
> defaulted to `cross-domain` (TR2 fail-closed). In practice single-domain (engineering).

## Enhancement Summary

**Deepened:** 2026-07-16 · **Panel:** 6 agents (dhh, kieran, code-simplicity,
architecture-strategist, spec-flow-analyzer, cto/devex)

**v2 after plan review.** Every claim below was **measured**, not argued. v1's verification
layer would have reported green on the *unfixed* file — that was the panel's convergent finding
and it is the reason this revision exists.

### Key corrections folded in

1. **v1's ACs were vacuous.** Measured: the unfixed guard false-FAILs **0/400** locally. So
   v1's "run it 200× and expect zero failures" was green on both arms — it re-measured the
   bug's *invisibility*, not the fix. Replaced by a **size-amplified differential** (AC3), the
   only test that discriminates: unfixed 100/100 FAIL vs fixed 100/100 pass.
2. **v1's AC7 was proven vacuous** — `git diff … | grep '^\+…'` prints only `+` lines, so it
   cannot compare against main and **exits 0 on the very `-F`→`-E` drift it claimed to catch**
   (the plan's own #1 risk, left unmitigated). Mechanized — but the count-equality form v2
   specified ALSO false-FAILs this diff (it forbids adding a check; it hits the
   document-what-you-forbid collision; and an unpinned `LC_ALL` makes `comm` run blind).
   Final form compares `(flag, pattern)` pairs under `LC_ALL=C`; see AC4.
3. **v1 overclaimed the fail-open — and v2's correction was itself false-precise (fixed at
   /work).** A producer needs a **second `write()`** for a window to exist at all, so a
   single-stdio-block (≤4096 B) producer is structurally safe. But v2 then read that as an
   *arming threshold* ("crossing 4096 B arms it"), which review falsified: unperturbed, the
   8035 B producer is **0/200** locally, and a bisection is flat 0/40 from 4 KB to 64 KB.
   **Scheduling decides the race, not a byte count.** Perturb the SAME 8035 B producer (run
   it under `strace`) and it IS killed by SIGPIPE — the window is real; and #6572's CI log
   (`grep: write error: Broken pipe`, same tree, re-run passed) is the race being lost in
   production. It only becomes deterministic past the pipe buffer (~100 KB). The issue's own
   text was the most accurate artifact here ("Runner scheduling/buffering appears to decide
   it"); the plan replaced that honest uncertainty with a false size model. The 7-site scope
   stands on guard-writability + idiom uniformity + future growth — never on a threshold.
4. **v1's self-check was evadable** — the narrow pattern missed `--quiet` and `-m1 -q`. The
   guard against "a gate that gates nothing" was itself partly vacuous. Broadened and verified
   against 5 unsafe + 4 safe forms.
5. **v1's mutation ACs could not run.** `SCRIPT` is hardcoded (`:29`), so "scratch copy" is
   impossible and every mutation edits **tracked source**. This is not theoretical — it dirtied
   the tree during this session and needed `git checkout --`. Added the `SCRIPT_OVERRIDE` seam
   + AC7 (clean tree).
6. **"Capture-once introduces a new fail-open" was FALSE — measured at /work.** Delete the
   guard, point `$SCRIPT` at an all-comment file: the `.lints[]?` check does take its `pass`
   branch, but the non-vacuity check immediately after catches the empty capture and the run
   still exits 1. The `FATAL` line stays — as a DIAGNOSTIC (one accurate message instead of
   five confusing downstream FAILs), not as a fail-open guard. In a file whose thesis is that
   every warning it carries is true, shipping a false hazard claim would have been the worst
   possible addition.
7. **"Reversed v1's no-debt call" — itself reversed at review; nothing filed.** v2 sized a
   middle tier (~31 sibling guards / ~230 sites) and resolved to file a tracking issue. The
   CONCUR gate dissented and was right: that is a SYNTAX count, not a vulnerability count
   (194/233 sites feed a bounded var = one write = no window), the proposed close trigger could
   never fire (the enumeration matches this PR's own comments), and the claimed criterion is
   defeated by its own text. See the Alternatives table.

### Deliberately not done

No research fan-out. The panel's convergent finding was that v1 wrapped good diagnosis in
~250 lines of restatement; adding "Research Insights" to a 7-line bash fix would undo the cuts
just applied. Deepen value here was **gate verification + negative-claim verification** — every
`cannot`/`never`/`unreachable` claim in this plan is backed by a measurement in-session, not by
docs or recall.

### Gates

4.6 User-Brand Impact **PASS** (threshold `none` + required scope-out bullet — diff matches the
sensitive-path regex via `apps/[^/]+/infra/`) · 4.7 Observability **PASS** (5/5 fields,
ssh-free) · 4.8 PAT-shape **PASS** · 4.4 precedent-diff **PASS** (here-string is in-repo idiom,
`deploy-status-fanout-verify.test.sh:244`) · 4.5 network-outage **SKIP** · 4.55 downtime
**SKIP** · 4.9 UI-wireframe **SKIP**.

> Both 4.9 and 4.5 *appeared* to fire on a whole-file grep and are **false positives** — the only
> hits are this plan's own prose documenting the **absence** of UI files and of ssh. Scoped to
> their real triggers (Files-to-Edit; network semantics) both are 0. That is precisely the
> AC-self-reference trap this plan guards against, encountered live while verifying it.

**Open decision:** `cto` challenges the operator-stated preference for option 3 (capture-once)
in favour of option 1 (`| grep -F P >/dev/null`). **Not applied** — it contradicts stated
direction, and `dhh` argued the opposite. Recorded for the operator in
`knowledge-base/project/specs/feat-one-shot-6572-scan-workflow-pipefail-sigpipe/decision-challenges.md` (UC-1).

## Overview

**The headline is not the noise — it is that this guard can silently pass.**
`apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh` sets `set -uo pipefail`
(`:25`) and has 7 checks shaped `<producer> | grep -q <pattern>`. `grep -q` exits on first
match; if the producer is still writing when the read end closes it takes SIGPIPE (rc=141),
and `pipefail` promotes 141 to the pipeline status — **inverting the `if`**.

At the 4 sites where *match ⇒ pass* this is the reported #6572 symptom: a false FAIL on a
correct tree. At the 3 sites where *match ⇒ fail* the same defect is a **false PASS** —
including `:200`, which the file's own comment calls "**THE headline assertion**" (the
`.lints[]?` fail-open that a 401 body parses to 0 through). A guard whose headline assertion
can silently pass is the exact "green gate that gates nothing" defect this file's header is a
manifesto against.

Fix: capture each producer once into a variable, match via **here-string**
(`grep -q PAT <<<"$var"`) — no pipe, no producer to SIGPIPE, producer runs once.

**Close condition (#6572):** no `script_code | grep -q` form remains under `pipefail` in that file.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified) | Response |
|---|---|---|
| Issue's **preferred** fix, option 3: `code="$(script_code)"; printf '%s' "$code" \| grep -q …` — "one producer run, **no early close**" | **FALSE — option 3 as written does not fix the bug.** `printf` is still a producer feeding a pipe `grep -q` closes early. Measured **100/100** false-negatives at 1.3 MB. | Adopt option 3's *capture-once* half (the stated goal); replace its *match* half with a here-string. Measured **0/100** at every size. |
| Issue: "a **blocking** gate (a **required** step in `infra-validation.yml`)" | **Partly false.** The step (`infra-validation.yml:529`) is in job `deploy-script-tests` (`:282`) — **advisory**: absent from the live `CI Required` ruleset (21 contexts, via `gh api repos/:owner/:repo/rulesets`), absent from `scripts/required-checks.txt`, and not a `needs:` of the `infra-validate-required` rollup (`:263` — `needs: [detect-changes, validate]`). | Urgency is **noise + latent fail-open**, not merge-blocked. Fix still justified. "Required step" in the issue means *hand-enumerated* (the file's header says "EXPLICIT step"), not *required check*. |
| v1 plan: "**three** of the seven sites fail OPEN" | **Overclaimed on reachability.** SIGPIPE needs the producer to issue a **second `write()`** after the reader closes; output under one stdio block (4096 B) is a single write that always lands in the 64 KB pipe buffer first — SIGPIPE is *unreachable*, not merely unlikely. Measured producers: `script_code` **8035 B** (reachable); `advisor_block` **1591 B**, `rung3_gate` **36 B**, `API=` line **73 B** (all unreachable — **0/300** each). | Only **`:200`** is a *currently reachable* fail-open. `:157`/`:268` are fail-open in **polarity** but size-unreachable today. Corrected throughout; the 7-site scope is re-justified below on other grounds. |

## Root Cause

Mechanism: **producer size × match position × scheduling.** Verified on bash 5.3.9 (CI runner
is `ubuntu-24.04` → bash 5.2; here-strings are bash 2.05b+, safe on both).

| Shape | 1.3 MB producer |
|---|---|
| `producer \| grep -q P` (current) | rc=141 → **100/100 false-negative** |
| `printf '%s' "$code" \| grep -q P` (**issue's option 3**) | rc=141 → **100/100 false-negative** |
| `grep -q P <<<"$code"` (**chosen**) | **0/100** |
| `grep P <(producer)` / `grep P >/dev/null` | 0/100 |

Why it is intermittent at the real size, and why **local runs cannot prove anything**:

| Producer | `printf \| grep -q` false-negatives |
|---|---|
| 1591 B / 4096 B / 8035 B / 16 000 B | **0/300** each |
| ~24 KB | 3/100 |
| 1.3 MB | 100/100 |

The **whole unfixed guard** false-FAILs **0/400** locally. It nonetheless fails on CI, because
CI scheduling deschedules the producer mid-write. `script_code` at 8035 B = 2–3 `write()`s →
reachable; everything under 4096 B → unreachable. `strip-log-injection` is the observed
symptom because its match is at **line 5 of 192** — earliest match, longest remaining write.

Confirmed present: `scripts/supabase-advisor-scan.sh:49` carries
`. "${SCRIPT_DIR}/lib/strip-log-injection.sh"` on the branch **and** `origin/main`.

### Site inventory (polarity × reachability)

| Site | Producer (bytes) | Match ⇒ | SIGPIPE ⇒ | Reachable today |
|---|---|---|---|---|
| `:200` | `script_code` (8035) | **fail** | **false PASS** | **YES — the headline assertion** |
| `:207` | `script_code` (8035) | pass | false FAIL | YES |
| `:284` | `script_code` (8035) | pass | false FAIL | **YES — the observed symptom** |
| `:157` | `grep '^\s*API='` (73) | **fail** | false PASS | no (single write) |
| `:225` `:231` | `advisor_block` (1591) | pass | false FAIL | no (single write) |
| `:268` | `rung3_gate` (36) | **fail** | false PASS | no (single write) |

**Why convert all 7, not just the 3 reachable ones:** (a) the Phase 2 guard asserts *zero*
residual — a 3-site fix needs a 4-site allowlist, which rots; (b) `advisor_block` is 1591 B
today and grows with the advisor rung — crossing 4096 B silently arms `:225`/`:231`; (c) two
idioms side-by-side invites a future check to copy the unsafe one. The justification is
uniformity + future-growth, **not** "3 sites fail open today."

**Out of scope, documented:** six `| head -1` sites (`:262`, `:381`, `:383`, `:392`, `:393`,
`:408`) are the identical early-exit class. They are safe **by rc-discard** — each sits in an
unchecked command substitution whose exit status nothing reads — not by design. The close
condition covers `grep -q` only; this plan does not claim to fix the `head` class.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — a CI shape guard with no
  runtime surface. A botched edit shows as a red (advisory) `deploy-script-tests` job.
- **If this leaks, the user's data/workflow/money is exposed via:** no vector. The file reads
  tracked files and runs a local hook probe; no secrets, no PAT, no network call.
- **Brand-survival threshold:** `none`
- **`threshold: none, reason:`** test-only shape guard two hops from user data — it asserts the
  *shape* of `scripts/supabase-advisor-scan.sh`, whose *behaviour* is independently proven by
  `tests/scripts/test-supabase-advisor-scan.sh` (registered in `scripts/test-all.sh:161`); the
  RLS enforcement path is untouched. (Bullet required: the diff matches the canonical
  sensitive-path regex via `apps/[^/]+/infra/`.)

## Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh` | `SCRIPT_OVERRIDE` seam; capture-once + non-empty guard; convert 7 sites to here-string; add residual-shape self-check; update the 2 comment blocks whose mechanism prose changes (`:192-198`, `:275-282`). |

**Files to Create:** none. Scope is one file (see Alternatives for the rejected sweep).

## Implementation Phases

### Phase 0 — Preconditions

1. Confirm the shape at `:284` and `set -uo pipefail` at `:25` still present.
2. Confirm the here-string idiom is **in-repo precedent, not invented**:
   `git grep -n '<<<' -- 'apps/web-platform/infra/*.test.sh'` → expect
   `deploy-status-fanout-verify.test.sh:244` = `grep -q 'v1.2.3' <<<"$POSTBODIES"` (verbatim
   match for the prescribed form). Also `apps/web-platform/scripts/preflight-worm-cascade-contradiction.test.sh`.
3. Baselines on `origin/main`, asserted later by AC1/AC4: residual shape count = **7**;
   flag counts = **16** `grep -qF`, **12** `grep -qE`.

### Phase 1 — Mutation seam (must precede the ACs that use it)

`SCRIPT` is hardcoded at `:29` from `BASH_SOURCE`-derived `REPO_ROOT` (`:27`) with no override,
so **"point the guard at a scratch copy" is impossible** — every mutation test must edit
tracked source, and an interrupted run leaves the tree dirty. (This is not theoretical: it
happened during this planning session and had to be reverted with `git checkout --`.)

Add the seam, preserving the default exactly:

```bash
SCRIPT="${SCRIPT_OVERRIDE:-$REPO_ROOT/scripts/supabase-advisor-scan.sh}"
```

Mutation tests then run `SCRIPT_OVERRIDE=/tmp/scratch-scan.sh bash <guard>` and never touch
tracked source. No production behaviour changes (unset → identical path).

### Phase 2 — Capture once, convert the 7 sites

1. Replace the `script_code()` function (`:199`) with a single lowercase capture — lowercase to
   match its peers `advisor_block` / `rung3_gate`; uppercase would read as a path constant like
   `SCRIPT`/`WORKFLOW`. Keep the comment block (`:192-198`); update only the *mechanism* prose,
   never the two anchoring rationales:

   ```bash
   script_code="$(grep -vE '^\s*#' "$SCRIPT")"
   [[ -n "$script_code" ]] || { printf 'FATAL: script_code empty (grep -v failed?)\n' >&2; exit 1; }
   ```

   The non-empty guard is load-bearing: capture-once consolidates seven independent failure
   points into one variable, and an empty `script_code` makes `:200` take its `pass` branch —
   a *new* fail-open. `set -uo pipefail` has no `-e`, so the assignment fails silently without
   it. Mirrors the file's own `FATAL` precedent at `:45-46`.

2. Rewrite each site, **preserving polarity and flags exactly**:
   - `:157` → `grep -qE '\$\{|\$\(|\$[A-Za-z_]' <<<"$(grep -E '^\s*API=' "$SCRIPT")"`
   - `:200` → `grep -qF '.lints[]?' <<<"$script_code"`
   - `:207` → `grep -qF '.lints[]' <<<"$script_code"`
   - `:225` → `grep -qE 'code" != "200"' <<<"$advisor_block"`
   - `:231` → `grep -qF 'has("lints")' <<<"$advisor_block"`
   - `:268` → `grep -qE '(^|[^_])\bok\b|advisor' <<<"$rung3_gate"`
   - `:284` → `grep -qE '^[[:space:]]*\.[[:space:]].*lib/'"$lib"'\.sh' <<<"$script_code"`
3. Update the `:275-282` comment block only where it describes piping.

> **Do not** replace the ERE sites with bash `[[ =~ ]]`. Verified: `=~` anchors `^` at **string**
> start, not line start, so `:284`'s per-line anchor breaks silently while looking simpler.
> The `-F` at `:196-198` is load-bearing (`grep -E` makes `[]?`'s `]` optional → would match the
> *correct* `.lints[]` and false-FAIL permanently).

### Phase 3 — Residual-shape self-check

Assert zero residual early-exit-pipe forms. Idiomatic here — `:63` already asserts this file's
own registration in `infra-validation.yml`; cohesion beats bolting it onto the unrelated
behavioural harness.

```bash
# Forbids <producer> | grep -q… (incl. -qF/-qE/--quiet/-m1 -q): grep -q exits on first
# match, SIGPIPEs the producer, and pipefail promotes 141 to the pipeline status (#6572).
# Match against a here-string instead. Safe forms (grep -c, >/dev/null) are not matched.
pipe_grep_q='[|][[:space:]]*grep([[:space:]]+-[a-zA-Z0-9]+)*[[:space:]]+(-[a-zA-Z]*q[a-zA-Z]*|--quiet)([[:space:]]|$)'
residual="$(grep -vE '^[[:space:]]*#' "${BASH_SOURCE[0]}" | grep -cE "$pipe_grep_q")"
```

Two review findings folded in, both verified this session:

- **Evasion (was a real hole):** the v1 narrow pattern missed `--quiet` and `-m1 -q`. The
  pattern above catches `-q`, `-qF`, `-qE`, `--quiet`, `-m1 -q` — and correctly does **not**
  match `grep -c`, `grep -E … >/dev/null`, a here-string, or the guard's own `grep -cE` line.
- **No fragment-building.** v1 concatenated `'…'"q"` to dodge self-matching. Verified
  unnecessary: the pattern **cannot** match its own source line (its first `|` is followed by
  `]`, not whitespace-then-`grep`) — self-match count **0**, measured, including when
  concatenated into its own target. A comment claiming a hazard that does not exist would put
  one false warning in a file whose value is that every warning is true.

`grep -c` returns rc=1 on zero matches; harmless here — `set -uo pipefail` carries no `-e` and
the status lands in an unchecked assignment (verified: guard exits 0 with `residual=0`).

### Phase 4 — Verify

1. Run the guard → `all checks passed`.
2. Run the **size-amplified differential** (AC3) — the only test that distinguishes fixed from unfixed.
3. Run both mutation tests (AC5, AC6) via `SCRIPT_OVERRIDE`, one per polarity.

## Acceptance Criteria

### Pre-merge (PR)

Every AC below is **mechanically checkable and discriminating**. v1 shipped six that pass
identically on the fixed and unfixed file; those are cut or rebuilt.

- **AC1 (close condition):** residual shape count is **0** on HEAD (baseline **7** on `origin/main`):
  ```bash
  RE='[|][[:space:]]*grep([[:space:]]+-[a-zA-Z0-9]+)*[[:space:]]+(-[a-zA-Z]*q[a-zA-Z]*|--quiet)([[:space:]]|$)'
  grep -vE '^[[:space:]]*#' apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh | grep -cE "$RE"   # 0
  ```
- **AC2:** `bash apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh` prints `all checks passed`, exits 0, on a clean tree.
- **AC3 (mechanism proof — THE discriminating AC):** build a scratch scan-script whose code
  keeps the `strip-log-injection` source at code line 5 and appends ≥1 MB of **non-comment**
  padding (`script_code` strips `^\s*#`, so comment padding is a no-op). Then:
  - the **unfixed** shape (`producer | grep -q`) false-FAILs **100/100**;
  - the **fixed** shape (`grep -q <<<"$var"`) passes **100/100**.

  Same host, same input, same site → a real differential. *(v1's AC6 ran the guard 200× on an
  unmodified tree; measured **0/400** false-FAILs on the **unfixed** file, i.e. green on both
  arms — it re-measured the bug's invisibility rather than the fix.)*
- **AC4 (flag drift — mechanized):** every `(flag, pattern)` pair on `origin/main` still
  exists on HEAD **with the same flag**. Empty output = no drift:
  ```bash
  F=apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh
  pairs() { grep -vE '^[[:space:]]*#' | grep -oE "grep -q[FE]? '[^']*'" | LC_ALL=C sort -u; }
  LC_ALL=C comm -23 <(git show "origin/main:$F" | pairs) <(pairs < "$F")   # must be empty
  ```
  Three corrections over the count-equality form AC4 originally specified, each found by
  running it rather than reading it:
  1. **Pairs, not counts.** Counting `grep -q[FE]?` occurrences forbids *adding* a check —
     this PR legitimately adds one (the mutation-harness wiring assertion), so the count form
     false-FAILs a correct diff. AC4's intent is "no `-F`→`-E` drift on the sites being
     rewritten"; pairing the flag to its pattern says exactly that and allows additions.
  2. **Comments stripped.** The fix's own prose names `grep -q`, so a whole-file scan hits
     the "assert must-not-contain X, then document X" collision the file's header warns
     about — which the original AC4 walked straight into.
  3. **`LC_ALL=C` pinned.** A locale `sort` makes `comm` read its input as unsorted, and the
     set-diff is then undefined — the guard runs blind while printing nothing. Observed here.

  Mutation-verified both halves: empty on the real diff; REDs on an injected `-qF`→`-qE`.
  *(v1's AC7 was `git diff … | grep -E '^\+.*grep -q'` — proven vacuous: it prints only `+`
  lines, so it cannot compare against main, and it exits 0 on the very `-qF`→`-qE` drift it
  claimed to catch. That drift is the Risks table's #1 named risk, so v1 left it unmitigated.)*
- **AC5 (fail-closed polarity, mutation):** with the `strip-log-injection` source line removed
  from a scratch copy, `SCRIPT_OVERRIDE=<scratch> bash <guard>` prints
  `FAIL sources lib/strip-log-injection.sh` and exits 1.
- **AC6 (fail-open polarity, mutation):** with `.lints[]?` injected at **code line 1** of a
  scratch copy, `SCRIPT_OVERRIDE=<scratch> bash <guard>` prints
  `FAIL script never uses the fail-open .lints[]? idiom` and exits 1. Injection position is
  pinned because it is load-bearing: at end-of-file this mutation is **100% vacuous** (the
  unfixed file also "passes"), and even at early injection the unfixed file evades ~13% of the
  time over 200 runs. Pair with AC3's amplified tail to make it deterministic.
- **AC7:** no mutation AC touches tracked source — `git status --short` is clean after Phase 4
  (guaranteed by the `SCRIPT_OVERRIDE` seam, not by a "remember to restore" step).

**Cut from v1** (all green-by-construction or ceremony): `bash -n` (subsumed — an unparseable
file cannot run AC2); the 200×-determinism loop (vacuous, above); every `200/200` qualifier
(repetition cannot rescue a non-discriminating test); "self-check does not self-match"
(circular — cited AC1 as its own proof; now covered by Phase 3's measured control);
"exactly one file changed" (paraphrases Files to Edit); "PR body says `Closes #6572`" (ship's
job). The Test Scenarios table is cut wholesale — 6 of its 8 rows restated ACs.

### Post-merge (operator)

None. Single tracked file; no infra apply, no secret, no deploy, no migration.
`deploy-script-tests` exercises it automatically on this PR (the diff touches `apps/*/infra/**`,
in the workflow's `paths:` filter).

## Observability

```yaml
liveness_signal:
  what: "deploy-script-tests runs the guard; prints `all checks passed` (exit 0) or `N check(s) FAILED` (exit 1)"
  cadence: "every pull_request matching the paths: filter in .github/workflows/infra-validation.yml (apps/*/infra/**, infra/**, + 8 named files incl. scripts/supabase-advisor-scan.sh)"
  alert_target: "GitHub Actions PR check surface (ADVISORY — not a required context; see Research Reconciliation)"
  configured_in: ".github/workflows/infra-validation.yml:529 (job `deploy-script-tests`, key at :282)"
error_reporting:
  destination: "GitHub Actions job log + non-zero job conclusion on the PR"
  fail_loud: "yes — exits 1 and names each failing check; never exits 0 on a detected failure"
failure_modes:
  - mode: "guard false-FAILs a correct tree (the #6572 symptom, rc=141 under pipefail)"
    detection: "AC3 size-amplified differential — unfixed shape 100/100 FAIL, fixed 100/100 ok"
    alert_route: "red deploy-script-tests job on the PR"
  - mode: "guard false-PASSes while the forbidden idiom IS present (fail-open at :200)"
    detection: "AC6 — .lints[]? pinned at code line 1 + amplified tail, must FAIL"
    alert_route: "red deploy-script-tests job on the PR"
  - mode: "the SIGPIPE-prone shape regresses back in (incl. --quiet / -m1 -q evasions)"
    detection: "AC1 / Phase 3 self-check — residual must be 0 (baseline 7 on main)"
    alert_route: "red deploy-script-tests job on the PR"
  - mode: "flag semantics drift (-F -> -E) while rewriting sites"
    detection: "AC4 — flag-count equality vs origin/main (16 -qF, 12 -qE)"
    alert_route: "red deploy-script-tests job on the PR"
  - mode: "guard silently unwired from infra-validation.yml"
    detection: "pre-existing in-file check at :63 asserts its own registration"
    alert_route: "red deploy-script-tests job on the PR"
logs:
  where: "GitHub Actions run logs, Infra Validation / deploy-script-tests"
  retention: "90 days (repo default)"
discoverability_test:
  # No `;` / `$?` / pipes: preflight Check 10 EXECUTES this command and refuses any
  # shell-active token, so the original `…test.sh; echo rc=$?` form was unrunnable by
  # the very gate that verifies it — declared-verifiable but unverifiable. The runner
  # captures the exit code itself, so the suffix was redundant as well as fatal.
  command: "bash apps/web-platform/infra/supabase-advisor/scan-workflow.test.sh"
  expected_output: "all checks passed"
```

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Single-file shell correctness fix to a CI shape guard; no runtime surface,
schema, dependency, or infra resource. The one design call (here-string vs. process
substitution vs. bash-native) was settled empirically and against in-repo precedent
(`deploy-status-fanout-verify.test.sh:244`). Blast radius bounded to an advisory CI job. The
load-bearing risk is semantic drift while rewriting 7 sites — now mechanically gated by AC4.

### Product/UX Gate

Not applicable. Mechanical UI-surface override does not fire — Files to Edit contains no
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`, and no UI-surface term.
Product: **NONE**.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200`, matched against all
three planned paths → zero hits.

## Architecture Decision (ADR/C4)

**Skipped — no architectural decision.** A bug fix on an existing surface: no ownership/tenancy
boundary, no substrate, no resolver/trust boundary, no ADR reversed.

**C4 completeness:** no `.c4` change. The plan adds no external human actor, no external
system/vendor (zero network calls), no container/data store, and no actor↔surface access
relationship. The subsystem's C4 representation is the existing `github -> sentry`
cron-monitor edge whose live count (49) this file already asserts at `:407-413` — unchanged,
since no `sentry_cron_monitor` is added or removed.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Semantic drift** across 7 hand-rewrites (`-F`→`-E` would false-FAIL permanently). *The plan's #1 risk.* | **AC4** — mechanized flag-count equality vs `origin/main` (16 `-qF`, 12 `-qE`). v1's AC7 could not catch this (proven vacuous). |
| **Polarity inversion** (`then fail` rewritten as `then pass`). | AC5 + AC6 are mutation tests, one per polarity. |
| **Capture-once creates a new single fail-open** if `script_code` is empty (`:200` would take `pass`). | Non-empty `FATAL` guard immediately after capture (Phase 2.1). |
| **Mutation tests dirty tracked source** — `SCRIPT` is hardcoded, no scratch-copy path. *Happened this session.* | `SCRIPT_OVERRIDE` seam (Phase 1) + **AC7** asserts a clean tree. |
| **Self-check evaded** by `--quiet` / `-m1 -q`. | Phase 3 pattern verified against all 5 unsafe forms and 4 safe forms. |
| Diff matches the sensitive-path regex via `apps/[^/]+/infra/` → preflight Checks 6 + 10 fire. | `## User-Brand Impact` carries the `threshold: none, reason:` bullet; `## Observability` carries the 5-field schema with an ssh-free `discoverability_test`. |
| **Guard is advisory**, so a regression is visible but not merge-blocking. | Pre-existing and out of scope — promoting `deploy-script-tests` to required needs dropping `paths:`, adding `merge_group:`, and registering in two places, putting ~50 test steps on every PR. Already scoped in **#6480**. Do not fold in. **The advisory-only exposure is narrower than it reads:** the RLS fail-open axis IS backstopped by a required check — `tests/scripts/test-supabase-advisor-scan.sh` (which tests 401 / empty / HTML-502 / `.lints`-renamed / clean directly) → `test-all.sh:161` → ci.yml `test-scripts` → the `test` rollup, which IS in the canonical required set. Advisory-only genuinely applies to the cross-file drift axes (cron agreement, slug, `model.c4` count, liveness forge-proofing, issue-filing). So this guard is structural early-warning, not the last line of defence on security. |

## Alternative Approaches Considered

| Alternative | Verdict |
|---|---|
| **Issue's option 3 verbatim** (`printf \| grep -q`) | **Rejected — does not fix the bug.** 100/100 false-negatives at 1.3 MB. Its capture-once half is adopted; its match half replaced. |
| **Option 1** (`\| grep -F P >/dev/null`) | **Not adopted — but recorded as an open User-Challenge** (see below). Correct (0/100) and a smaller, blind-applicable transform. Rejected here only because the operator's brief explicitly prefers capture-once; the decision is surfaced, not silently made. |
| **Option 2a** (`grep -q … <(script_code)`) | Rejected. Correct (process-substitution status is outside the pipeline status) but spawns a producer per check and is rarer in-repo than the here-string. |
| **bash-native** `[[ == *P* ]]` / `[[ =~ ]]` | Rejected. Verified incapable of `:284`'s per-line-anchored ERE (`=~` anchors at string start). Mixing idioms across 7 sites invites the drift AC4 guards. |
| **Remove `set -o pipefail`** | Rejected. Verified it "works" and would satisfy the close condition's wording — but games the letter while exposing the file's 5 command-substitution pipelines to silent failure. |
| **Convert only the 3 reachable sites** (`:200`/`:207`/`:284`) | Rejected — but it is the *literal* close condition and a real option. Rejected because the Phase 3 zero-residual guard would need a 4-site allowlist, `advisor_block` (1591 B) grows toward the 4096 B threshold, and two idioms side-by-side invite copying the unsafe one. |
| **Repo-wide sweep** of `\| grep -q` under `pipefail` | **Rejected for THIS PR** — measured **153 files / 591 sites** set `pipefail` and carry the shape; a different PR with a blast radius orders of magnitude larger than this fix. |
| **Repo-wide lint** forbidding the shape | Rejected — reachability is producer-size × match-position × scheduling, none of which a lint can see; unacceptable false-positive rate across 591 mostly-safe sites. |
| **File nothing** (v1's call: "a tracking issue would imply a debt that does not exist") | **Reversed by v2, then reversed BACK at review — v1's conclusion was right, for reasons v1 never gave.** v2 measured ~31 sibling guards / ~230 sites under `apps/web-platform/infra/**` carrying the shape and resolved to file a tracking issue. The CONCUR gate DISSENTed, and the dissent held on inspection — I verified all three grounds: (1) **the count is a SYNTAX count, not a vulnerability count** — 194 of 233 non-comment sites feed `printf`/`echo` of a bounded shell variable, i.e. ONE write, so no second write, so no window at all; calling those "silent passes" is simply false. (2) **The proposed close trigger could never fire** — the enumeration matches 5 COMMENT lines, including this PR's own documentation of the bug, so reaching 0 would mean deleting the guard's own comments. (3) **The `cross-cutting-refactor` criterion is defeated by its own literal text**, which names `apps/web-platform/` as a top-level directory — every candidate lives under it, so they are RELATED by that definition. Filing an issue asserting a 230-site defect population nobody has measured would be exactly the false precision this PR's review spent its time removing. **Not filed.** The real predicate is per-site: *can this producer emit ≥2 writes before the match, AND is its polarity match⇒fail?* Measuring that is its own task, not a by-product of a one-file fix. The class is real — #6572's CI log proves the shape bites at 8 KB — but its population here is unmeasured, and this plan now says so instead of guessing. (The dissent's own model was wrong: it claimed a 64 KB pipe-buffer threshold, which the CI log and a `strace`-perturbed 8 KB producer both refute. Its procedural criticisms stand regardless — a right verdict can rest on a wrong reason, and both were checked separately.) |

## Sharp Edges

- **The issue's preferred fix is a no-op.** `printf '%s' "$var" | grep -q` is *not* SIGPIPE-safe —
  `printf` is still a producer feeding a pipe `grep -q` closes early. Capture-once fixes the
  *re-run* cost, not the *SIGPIPE*. Implementing "option 3" verbatim ships a fix that still flakes.
- **`grep -q` only exits early when it MATCHES.** So the correct script never flakes on the
  *negative* checks today (`.lints[]?` absent → grep reads to EOF), and those checks become
  fail-open **exactly when a real regression appears**. The guard is least reliable precisely
  when it matters most.
- **SIGPIPE needs a second `write()`.** Under one stdio block (4096 B) the producer's single
  write always lands in the 64 KB pipe buffer before `grep -q` can exit — the bug is
  *unreachable*, not rare. This is why 4 of the 7 sites are safe today and why any claim about
  which sites are at risk must cite producer bytes, not polarity alone.
- **A local green proves nothing here.** The unfixed guard passes **0/400** locally and still
  fails on CI. Any AC that runs the guard on an unmodified tree — at any iteration count —
  is green on both arms. Only a size-amplified differential (AC3) discriminates.
- **`SCRIPT` is hardcoded** (`:29`, from `BASH_SOURCE`-derived `REPO_ROOT`): without the
  `SCRIPT_OVERRIDE` seam, every mutation test edits tracked source, and an interrupted run
  leaves the tree dirty. This bit this planning session.
- **`scan-workflow.test.sh` is not run by `scripts/test-all.sh`** (that runs the *behavioural
  harness*, `tests/scripts/test-supabase-advisor-scan.sh`, at `:161`). Its only runner is
  `infra-validation.yml:529` — verifying this fix via `test-all.sh` exercises nothing.
</content>
