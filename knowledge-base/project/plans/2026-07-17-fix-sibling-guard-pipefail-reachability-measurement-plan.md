# fix: measure whether the sibling guard class can be triaged at all (#6578)

```yaml
type: measurement
lane: cross-domain          # no spec.md on this branch — defaulted cross-domain (TR2 fail-closed)
brand_survival_threshold: aggregate pattern
closes: 6578
prior_art: PR #6573 (#6572), merged 2026-07-17
revision: v2 — v1's apparatus was cut after 6-agent review + advisor consult (see Alternatives)
```

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No `spec.md` exists for
> this branch; the input record is the merged #6572 spec dir's `decision-challenges.md`.

## Enhancement Summary

**Deepened:** 2026-07-17 · **Panel:** dhh, kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, cto (devex) + a scoped `fable` advisor consult + learnings-researcher.

**v1 → v2 was a cut, not a polish.** Both review panels fired on the same scope — the
simplification panel called the apparatus over-built; the correctness panel found the apparatus
could not work. Per `plan-review`'s own rule (*both panels on one scope ⇒ prefer delete over fix*),
v1's classifier, 284-row provenance ledger, and 11-rung attestation were cut. Every finding below
was **reproduced by command** before being acted on.

**What the deepen pass changed:**

1. **Cut the apparatus.** R1 eliminates ≤16/284, R2 ~0 → R3 decides everything, and R3 is
   undecidable for the dominant var-fed class without the byte model #6573 retracted. The ledger
   would have been majority-`UNDECIDED` by construction (Reconciliation rows 7-8).
2. **Found the partition nobody had run.** 238 of 284 sites are `*.test.sh` internals; only **46
   are production, across 11 files** (row 9). That makes the production class tractable *without*
   the undecidable window analysis — the useful split was not the one anyone was arguing about.
3. **Caught the plan committing its own cardinal sin.** v1's "202 `|| true` lines make this class
   material" had **zero** overlap with the corpus under test (row 5) — a syntax count sold as a
   relevance count, inside the plan condemning exactly that. v1's producer-kind row summed to 279,
   not 284, and carried no command (row 6). Both cut.
4. **Found that the measurement environment is load-bearing and unnamed.** `grep` in this session
   is a **function shadowing GNU grep with ugrep**, and `ugrep -q` does not early-exit. This
   session's own first probes read 0/200 and 0/50 and would have "proved" the corpus incapable —
   a **false all-clear**, worse than the 230 over-claim. Now AC1's load-bearing negative arm.
5. **Corrected two false premises.** v1 claimed `infra-validation.yml` runs shellcheck (it does not
   — all 16 hits are `# shellcheck source=` directives in comments, row 10) and that a new script
   could "self-assert its own registration" (vacuous — an unregistered script never runs; the
   precedent is a **cross-file** assertion).
6. **Made FR4 honest twice.** The brief's "capture-once closes the empty-read-back hole" is
   imprecise (the file itself calls the FATAL line *"NOT a fail-open guard"*; the **pairing rung**
   closes it), and the hole is **orthogonal to the pipe conversion** — measured identical under
   both forms. FR4 moves into `scan-workflow-mutation.test.sh`, which already owns the sandbox.
7. **Made the escalation executable.** v1 required CPO sign-off "before `/work`" for a trigger only
   knowable *inside* `/work` — a gate demanding time travel. Now a security-rung **auto-forfeit**.
8. **Corrected the blast-radius call.** The repo is **PUBLIC**; a per-site index of live-vacuous
   security rungs is a targeting artifact. v1's "the ledger is inert" was wrong.

**Gates:** 4.6 User-Brand Impact **PASS** (`aggregate pattern`) · 4.7 Observability **PASS** (5
fields, no placeholders, no `ssh` in the discoverability command) · 4.8 PAT-shaped **PASS** (none) ·
4.9 UI-wireframe **SKIP** (0 UI-surface paths) · 4.55 Downtime **SKIP** (no serving surface) ·
4.5 Network-outage **SKIP** — the word `timeout` appears only as `timeout-minutes` (a CI budget),
not a connectivity symptom; the keyword trigger is a false positive here.

**Citations verified live:** `hr-verify-repo-capability-claim-before-assert` + `cq-test-fixtures-synthesized-only`
both ACTIVE in AGENTS.md · ADR-084 exists · #6572 CLOSED, PR #6573 MERGED, #6578 **OPEN**, #6536
CLOSED — all resolve to the cited type and state.

**Open decision-challenges:** UC-1 (two-class vs `UNDECIDED`), UC-2 (the FR4 premise correction,
applied), UC-3 (**dhh + cto argue the measurement should not happen at all** — convert the class
blind). All recorded for operator reversal; none auto-applied.

---

## Overview

PR #6573 fixed 7 sites shaped `<producer> | grep -q P` under `set -uo pipefail`. `grep -q` exits on
first match; the producer's next `write()` takes SIGPIPE (rc=141); `pipefail` promotes 141 to the
pipeline status. Its plan promised a follow-up issue citing a site count; the second-opinion gate
rejected the filing and the merged PR **retracted the claim** — the figure was a *syntax* count, not
a *vulnerability* count, and its close-condition was unsatisfiable. #6578 asks: does the sibling
sweep get tracked? It is to be answered with data.

**The question this PR answers is not "how many sites are reachable." It is "can this class be
triaged at all?"** That reframing is the result of plan-time measurement, not preference — see
below. Prior figures (the ~230 count, the 194/233 split) are **hypotheses under test**, never
restated as findings.

## Research Reconciliation — prior claims and this plan's own v1, vs. measured reality

Every row below was **run**, not reasoned. v1 of this plan was cut on the strength of rows 5-8; the
same review pass that produced them reproduced rows 1-4 independently.

| Claim | Measured | Response |
|---|---|---|
| 1. "31 files / 235 sites under `apps/web-platform/infra/**`" | **44 files / 284 sites.**<br>`git grep -lE '\|[[:space:]]*grep[[:space:]]+(-[A-Za-z]*q[A-Za-z]*\|--quiet)' -- 'apps/web-platform/infra/' \| wc -l` → 44; same with `-cE` \| `awk -F: '{s+=$NF} END {print s}'` → 284 | Corpus grew. A static count rots. |
| 2. "~591 repo-wide" | **919 sites / 330 files** (same command, no pathspec) | Confirms drift. Out of scope; stated as a bound with its command. |
| 3. "194 of 233 feed a bounded var (one write, no window)" | **Var-fed ≠ bounded.** No artifact establishes any var's max size. `printf '%s' "$output"` where `$output="$(bash ./ci-deploy.sh)"` is unbounded. | The split's denominator was never established. Under test. |
| 4. "the 4096 B threshold makes 4 sites unreachable" | #6573 **retracted this as "false precision"**: real 8 KB producer 0/200 unperturbed, flat 0/40 from 4 KB→64 KB, yet strace-perturbed it *is* killed. "Scheduling decides it; no byte count does." | Byte counts predict frequency, badly. Not a triage axis. |
| 5. **v1's own "202 `\|\| true` lines make this class material"** | **The 230-error, committed inside the plan condemning it.** 202 is real, but of those, **0** are also `\| grep -q` sites:<br>`git grep -hnE '<shape>' -- 'apps/web-platform/infra/' \| grep -cE '\|\|[[:space:]]*(true\|:)([[:space:]]\|$)'` → **0** | A syntax count sold as a relevance count. v1's W4/W5 rungs pinned an **empty class**. Cut. |
| 6. **v1's producer-kind row (182+31+40+26)** | **= 279, not 284**, and the row carried **no command** — in a table whose header promises every row is replayable. | Cut. Any count without its command is not a finding. |
| 7. **R1's discriminating power** | **≤16 of 284** sites sit in files with no `pipefail` (4 files). Those 4 are also the likeliest sourced helpers inheriting the caller's `pipefail` — so INCAPABLE(R1) may be **empty**. | R1 near-vacuous. |
| 8. **R2's discriminating power** | **~0.** Zero `\|\| true` overlap (row 5), and **32 of 44** shape-bearing files `set -e` — under which `set -e` *is* the rc consumer for a bare pipeline. | R2 near-vacuous. |
| 9. **The corpus is 84% test-harness internals.** Nobody had partitioned it. | **238 of 284 sites are in `*.test.sh`; only 46 are in production infra scripts**, across **11 files** (`ci-deploy.sh` 16, `cron-egress-postapply-assert.sh` 11, `cloud-init-registry.yml` 6, `cron-egress-resolve.sh` 3, + 7 files with 1-2 each).<br>`for f in $(git grep -lE '<shape>' -- 'apps/web-platform/infra/'); do n=$(grep -cE '<shape>' "$f"); case "$f" in *.test.sh) t=$((t+n));; *) p=$((p+n));; esac; done` | **The single most decision-relevant fact in this table, and it reframes the disposition** — see below. |
| 10. **v1's "shellcheck-clean; `infra-validation.yml` runs it"** | **False.** `grep -rn shellcheck .github/workflows/ lefthook.yml \| grep -v 'disable='` → 16 hits, **all `# shellcheck source=` directives in comments**. Shellcheck is enforced **nowhere** in this repo. | v1 asserted a CI capability that does not exist — the `hr-verify-repo-capability-claim-before-assert` shape. AC corrected to a one-time author check. |

### The finding that reshaped this plan

Rows 7 and 8 collapse the predicate. If R1 eliminates ≤16 and R2 eliminates ~0, then **R3 (window
existence) decides essentially the whole corpus** — and R3, for the dominant var-fed class, is a
data-flow bound on the var's source, which the plan **cannot decide without exactly the byte model
row 4 retracts**. Four reviewers converged on this independently, each with reproduced numbers.

So a per-site REACHABLE/INCAPABLE ledger over 284 sites would be **majority `UNDECIDED` by
construction**. v1 was building an apparatus architecturally incapable of producing the number its
own scope-gate consumed. **That is the finding**, and it is the honest answer to #6578.

### The partition that reframes the disposition (row 9)

The prior record, v1, and the brief all reasoned over "284 sites" as one population. It is two:

- **238 sites in `*.test.sh`** — test-harness internals. The bug here false-FAILs a test (noise) or
  false-PASSes one (a test that gates nothing). Real, but it is *test* debt.
- **46 sites in 11 production scripts** — `ci-deploy.sh`, `cron-egress-postapply-assert.sh`,
  `cloud-init-registry.yml`, `soleur-host-bootstrap.sh`, `anon-probe.sh`, `server.tf`, and 5 others.
  This is where a silent inversion changes what infra *does*.

**46 sites across 11 files is a tractable set** — comparable to what #6573 converted (7 sites / 1
file) times a small constant, and far inside what a single PR can carry with review. The triage the
prior record wanted may therefore be available after all — not from R1/R2/R3, which collapse, but
from a partition **nobody had run**. That is the measurement paying for itself: the useful split
was not the one anyone was arguing about.

This does **not** presuppose the arm. `B` (Phase 2) still decides whether the production subset can
be scoped smaller than 46. But the disposition rule below is now stated over the **production
denominator**, not over 284 — v1's `≤12 sites / ≤3 files` threshold was being applied to a
population dominated by fixtures, which is its own unmeasured-denominator error.

### Two further corrections that change the shape

**(a) The frame modelled one symptom and missed the other.** `set -e` is set in **32 of 44**
shape-bearing files. A *bare* pipeline `producer | grep -q X` under `set -euo pipefail` does not
invert an `if` — on match it takes SIGPIPE → 141 → `set -e` → **the script aborts mid-run**. That is
a distinct failure mode with no bucket in v1. Any measurement must carry a `symptom`
(`inverts` | `aborts`) axis, not just a class.

**(b) The measurement environment is load-bearing and nobody named it.** Plan-time probe:

```
/bin/grep --version                → grep (GNU grep) 3.12
type grep                          → grep is a function  → dispatches to ugrep 7.5.0
bash slowprod.sh | /bin/grep -q M  → rc=141 PIPESTATUS=141 0   in 1.005s   (early-exit: bug LIVE)
bash slowprod.sh | grep -q M       → rc=0   PIPESTATUS=0 0     in 5.042s   (ugrep drains: no bug)
```

`grep` in this session is a **shell function shadowing GNU grep with ugrep**, and **ugrep `-q` does
not early-exit**. Every reading taken through it is 0/N — including this session's first probes,
which read 0/200 and 0/50 and would have "proved" the whole corpus incapable. **A ledger generated
on such a host would report zero reachable sites and close #6578 with a false all-clear** — an error
in the opposite and far more dangerous direction than the 230 figure. This is the #6536 shape
exactly: *the probe ran somewhere other than the failing site; it establishes capability, not
actuality.* Any measurement MUST pin the grep implementation (absolute path + `--version`) and run
where CI's grep runs. **No verdict may be taken from a host whose `grep` is not the CI `grep`.**

## What this PR ships

The measurement that is **cheap, decidable, and decisive** — and nothing else.

1. **`sigpipe-triage-feasibility.sh`** — a re-runnable probe that reports, each with its command:
   the corpus size; the R1 (`pipefail`) split; the `set -e` split and the resulting `symptom` mix;
   the producer-kind mix; and **the share of var-fed sites whose var source can be bounded by
   data-flow**. That last number is the deliverable: it is the measured answer to *can this class be
   triaged?*
2. **A short findings note** at `knowledge-base/engineering/audits/2026-07-17-sigpipe-guard-triage-feasibility.md`
   — the numbers, the commands that produced them, the grep-implementation caveat, and the verdict.
   **Not** a 284-row per-site ledger (see Alternatives).

   > **Its consumer is named, because that directory is otherwise a graveyard:**
   > `knowledge-base/engineering/audits/` holds exactly one file, dated 4.5 months ago, with no
   > inbound route from any skill, workflow, or runbook. This note is read because **#6578's closing
   > comment and the tracking issue both link it** — it is the evidence those close *on*, not a
   > document hoping to be found. The *live* surface is the probe's exit code in CI, not the note.
   > If the tracking arm does not fire and #6578's closure does not cite it, the note has no
   > consumer and should not be committed — put the numbers in the issue and stop.
3. **A disposition for #6578**, driven by the measured verdict (below).
4. **The FR4 pairing test** — see FR4; it is independent of all of the above.

**Not shipped** (all cut at review; see Alternatives): the 11-rung attestation harness, the
per-site provenance ledger, the `--format tsv|md` dual rendering, the AC3 regenerate-and-diff CI
gate, the Phase 4 ≤12-site threshold, the escalation-sign-off rule.

## Disposition rule (fixed HERE, before the numbers are known)

Stated over the **production denominator** (46 sites / 11 files, Reconciliation row 9) — not over
284. The `*.test.sh` subset (238) is dispositioned separately and never blocks the production arm.

Let **P** = production sites surviving the PF (`pipefail`) filter. Let **B** = the share of var-fed
production sites whose var source is bounded by data-flow (Phase 2).

- **Production arm — convert** iff `P ≤ 50 across ≤ 12 files`. Grounded, not arbitrary: the measured
  production set is 46/11 today, so this threshold says *"convert the production class as it stands,
  and re-plan if it has grown materially by /work time."* It is a staleness guard, not a triage gate
  — because triage below 46 requires `B`, and `B` is exactly what the evidence says is undecidable.
  Conversion is per FR4 + UC-3's transform, with the security-rung auto-forfeit below.
- **Production arm — track** iff `P > 50` or `> 12 files`: one issue scoped by the measured count,
  close-condition *`sigpipe-triage-feasibility.sh` reports 0 early-exit-pipe production sites over
  pathspec X* (mechanical, satisfiable, and verified to fail today at file time).
- **Test-harness subset (238):** always **track, never convert here.** Converting 238 fixture sites
  in the same PR as 46 production ones would bury the production diff under 5× its own size in test
  churn. One issue, same mechanical close-condition, scoped `*.test.sh`.
- **If `B ≥ 0.8`** (contrary to the evidence's prediction), the ledger the prior record wanted is
  *available* — say so in the note and scope the tracking issue by the measured reachable count
  rather than the whole class.

Thresholds are fixed before measuring so no arm can be rationalized after. **No arm asserts an
unmeasured population**; every count in the note carries its command.

## FR4 — the empty-read-back constraint (corrected twice)

**Correction 1 (from the merged file).** The brief says *"the capture-once-then-match style closes
that hole."* `scan-workflow.test.sh:277-283` says the `[[ -n "$script_code" ]]` FATAL line is
*"NOT a fail-open guard, despite appearances"* — a **diagnostic**. What closes the hole is the
**paired non-vacuity rung** at `:291`. Capture-once alone does not close it.

**Correction 2 (measured at review).** The hole is **orthogonal to the pipe conversion**. An empty
capture at a match⇒fail site takes the `pass` branch **identically** under `grep -q` and under
`grep -F >/dev/null`. The conversion neither opens nor closes it; `grep -q` never guarded it either.
And the corpora barely intersect — 284 pipe sites vs 75 here-string sites. v1 welded the two
together and manufactured a reason from it.

**So FR4 is a real, independently valuable property about *captures*, and it is not a property of
this measurement.** It ships as its own thing:

- **The pinning test** goes into **`scan-workflow-mutation.test.sh`** as an added rung — not a new
  harness. That file already owns the sandbox (`cp "$GUARD" "$PRISTINE"` into `mktemp -d`,
  `:59,:139,:244`), the landing-verified `mutate()` helper (`:180-201`), and the
  mirror-completeness precondition. Building a second sandbox to reach the same file would violate
  this plan's own "do not invent a second fold" discipline.
- **E1:** an empty capture at the `.lints[]?` match⇒fail site exits non-zero.
- **E2 (vacuity of E1):** with the `:291` pairing rung mutated out, the same empty capture
  **passes** — proving E1 pins the pairing and not something incidental.
- This mutates a **sandbox copy**, so AC12 (`scan-workflow.test.sh` passes unchanged) still holds
  and `cq-test-fixtures-synthesized-only` is satisfied.

## User-Brand Impact

**If this lands broken, the user experiences:** an infra guard reporting green while the defect it
exists to catch ships — e.g. the `.lints[]?` rung (a public-table-without-RLS gate) passing
vacuously. The user never sees the guard; they see what it failed to stop.

**If this leaks, the user's data is exposed via:** **the findings note itself, on a public repo.**
`gh repo view --json visibility` → **PUBLIC**. This is the correction v1 got wrong by asserting "no
new exposure surface." A per-site ledger ranking which RLS/exfil-gating guards are *currently
vacuous*, silent-class-first, with a regeneration command, **fixing none of them**, is a targeting
artifact whose value to an attacker rises with the measurement's quality. **Therefore:** the
findings note publishes **counts, classes, and commands only — never a ranked per-site index of
live-vacuous security rungs.** Any site-level detail for a security-gating rung goes in the tracking
issue, not the public audit note. This constraint applies to both arms and is the single reason the
deliverable is a findings note rather than a ledger.

**Brand-survival threshold:** `aggregate pattern`. The defect class is "a green gate that gates
nothing"; the artifact is counts + commands.

> **Escalation, restructured to be executable.** v1 required "CPO sign-off before `/work`" for a
> trigger only knowable *inside* `/work` — a gate demanding time travel, unsatisfiable in headless
> one-shot. Replaced with an **auto-forfeit**: if the convert arm would touch a security-gating rung
> (RLS, auth, exfil seam, credential pinning), `/work` does **not** convert. It forfeits to the
> track-whole arm and files an `action-required` issue carrying the site detail. This keeps `/work`
> headless (ADR-084: persist, do not pause), keeps the gate real, and terminates cleanly.

## Implementation Phases

Probe-first ordering is load-bearing and must not be collapsed on the reasoning that "we already
know the answer" — that belief *is* the thing under test. But the probe is now sized to what it can
actually decide.

### Phase 0 — Preconditions

1. Confirm #6578 OPEN; `2b381815f` on `main`.
2. **Pin the grep implementation.** Record `command -v grep`, `type grep`, `/bin/grep --version`.
   **Abort the measurement** if the resolved `grep` is not GNU grep — a ugrep/BusyBox host reads
   0/N everywhere and yields a false all-clear (see Reconciliation (b)). The probe script must
   assert this itself and exit non-zero, not warn.
3. Read `scan-workflow-mutation.test.sh` in full — it is the precedent for FR4's rung and it owns
   the sandbox this PR reuses. Note `count_false_negatives piped` (`:89-99`) already implements the
   amplified-producer differential; lift it rather than re-authoring.
4. `shellcheck --version` — **a one-time author check only.** Shellcheck is enforced nowhere in this
   repo (Reconciliation row 10); do not add a step claiming otherwise, and do not sweep the repo
   clean as a side quest.
5. **CI budget.** `deploy-script-tests` runs `timeout-minutes: 8` (`infra-validation.yml:287`) and
   its recent runs land at ~445-468s — roughly 12s of slack against 480s, across 57 registered
   `bash *.test.sh` steps. The probe is static (greps + `sed`, no perturbation, no per-site
   execution) so it should cost seconds; **measure it** and, if it exceeds ~10s, register it as its
   own job with its own timeout rather than a step in `deploy-script-tests`. A slow step here
   red-lines 57 unrelated tests and gets deleted angrily, not disabled thoughtfully. (This is why
   v1's perturbation harness was uncostable in that job — a further reason it was cut.)

### Phase 1 — The decidable splits (static, cheap)

`sigpipe-triage-feasibility.sh` emits, each beside the command that produced it:
corpus size; R1 (`pipefail`) split; `set -e` split → `symptom` mix (`inverts` vs `aborts`);
producer-kind mix (streaming-cmd vs var-fed vs other). Every number carries its command or it is
not emitted. `LC_ALL=C` pinned on any `sort`/`comm`.

### Phase 2 — The one number that decides the arm

For each var-fed site, attempt to resolve the var's assignment to a bound:
- literal / fixed-width (`$(git rev-parse HEAD)`, a SHA, a version string) → **bounded**;
- command substitution of an unbounded producer (`$(bash …)`, `$(docker …)`, `$(curl …)`) →
  **unbounded**;
- unresolvable → **undecided**.

Emit **B** = bounded / var-fed. **B is the deliverable.** Do not emit a per-site class.

> **This phase may not conclude `bounded` from shape alone.** "Feeds a var" ⇒ bounded is precisely
> the inference that produced the 194 figure. A site counts as bounded only when the *assignment*
> resolves to a bound — the antecedent, not the implication.

### Phase 3 — Findings note + disposition

Write the note (counts, commands, grep caveat, `B`, verdict). Apply the disposition rule. Present
both dispositions with the data where the rule says triage is unavailable; do not choose silently
between (i) and (ii) — that is UC-3, the operator's call.

### Phase 4 — FR4 rung

Add E1/E2 to `scan-workflow-mutation.test.sh` per FR4. Independent of Phases 1-3; ships regardless
of the arm.

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1** — `bash apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh` exits 0 on a GNU-grep
   host, and **exits non-zero** when `grep` resolves to a non-GNU implementation (verify by running
   it with a ugrep/BusyBox shim first on `PATH`). The negative arm is the load-bearing one.
2. **AC2** — every number in the findings note is accompanied by the command that produced it.
   Verify by re-running each command in the note and matching its output.
3. **AC3** — the note reports `B` and the arm taken, and the arm matches the disposition rule
   mechanically (no post-hoc re-threshold).
4. **AC4** — the note contains **no ranked per-site index of security-gating rungs**; site detail
   for such rungs appears only in the tracking issue. Verify by inspection against the
   User-Brand Impact constraint.
5. **AC5** — no prior unmeasured figure is restated as a finding in the **output artifacts**.
   Scope is the note, the probe script, and the issue/PR bodies — **not** this plan, which is
   required to name the figures it retracts (v1's AC6 flagged its own definition; that is the
   document-what-you-forbid collision, landing inside the AC meant to enforce it):
   ```bash
   for f in knowledge-base/engineering/audits/2026-07-17-sigpipe-guard-triage-feasibility.md \
            apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh; do
     ! grep -nE '(^|[^0-9])(230|233|194|235)([^0-9]|$)' "$f" || exit 1
   done
   ```
6. **AC6** — `scan-workflow-mutation.test.sh` passes with the E1/E2 rungs added, and E2 fails when
   the pairing rung is present (proving E1 is not vacuous).
7. **AC7** — `scan-workflow.test.sh` and `scan-workflow-mutation.test.sh` both pass; the former
   **unchanged** (FR4 mutates a sandbox copy only).
8. **AC8** — `shellcheck` clean on the probe script, run once by the author. **Not a CI gate** —
   shellcheck is enforced nowhere in this repo (Reconciliation row 10). Stated honestly rather than
   implying an automation that does not exist.
9. **AC9** — the probe script is registered in `.github/workflows/infra-validation.yml`, and its
   registration is asserted by **`scan-workflow.test.sh`** — a *cross-file* assertion, mirroring
   how `:95` asserts the mutation harness. (v1 said the new script would "self-assert its own
   registration": vacuous by construction — an unregistered script never runs, so its self-assertion
   never evaluates. The precedent is cross-file; v1 misread it.)
10. **AC10** — if the track-whole arm fires, the issue's close-condition is executable
    (`sigpipe-triage-feasibility.sh` reports 0 early-exit-pipe sites over pathspec X) and is run at
    file time to confirm it *can* fail today.
11. **AC11** — `decision-challenges.md` records UC-1, UC-2, and UC-3.

### Post-merge (operator)

12. **AC12** — `gh issue close 6578` referencing the findings note.
    *Automation: feasible* — executed by `/ship` via `gh` CLI, not by the operator.

## Observability

```yaml
liveness_signal:
  what: sigpipe-triage-feasibility.sh runs as a step in infra-validation.yml
  cadence: every PR touching apps/web-platform/infra/** (path-filtered pull_request)
  alert_target: GitHub Actions job status (deploy-script-tests)
  configured_in: .github/workflows/infra-validation.yml
error_reporting:
  destination: GitHub Actions job log + non-zero exit
  fail_loud: false — deploy-script-tests is an ADVISORY job, confirmed against the live ruleset
    (absent from infra/github/*.tf; the workflow's own comment states it verbatim). A red here is a
    visible signal, not a merge block. v1 declared fail_loud true against this same advisory job.
    The RLS fail-open axis is separately backstopped by the required `test` rollup.
failure_modes:
  - mode: probe runs on a non-GNU grep host and reports a false all-clear
    detection: the probe asserts the grep implementation and exits non-zero (AC1's negative arm)
    alert_route: advisory job red + non-zero exit
  - mode: probe silently unregistered from CI
    detection: scan-workflow.test.sh asserts its registration (cross-file, AC9)
    alert_route: scan-workflow.test.sh is itself registered and required-adjacent
  - mode: a number in the note drifts from the corpus
    detection: AC2 — every number carries its command; re-run reproduces it
    alert_route: manual on re-read; NOT a CI gate (v1's regenerate-and-diff was a treadmill —
      pinned-SHA regeneration is reproducible by construction and can never detect drift, while
      HEAD regeneration reds every future infra PR until someone regenerates)
logs:
  where: GitHub Actions job logs (infra-validation)
  retention: GitHub default (90d)
discoverability_test:
  command: bash apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh
  expected_output: terminal line reporting the triage-feasibility verdict
```

> **Preflight Check 10:** the command carries no shell-active token (no `;`, `&&`, `|`) — Check 10
> executes it and captures the exit code itself. #6573 shipped a discoverability command Check 10
> could not run; do not append `; echo rc=$?`.

## Domain Review

**Domains relevant:** Engineering (CTO/devex)

### Engineering

**Status:** reviewed
**Assessment:** CI-only tooling + an audit note. No product surface, schema, or runtime path.
Primary risks: (a) a measurement taken on a non-CI grep — mitigated by AC1's negative arm, which is
the finding that nearly sank this plan; (b) publishing a targeting artifact on a public repo —
mitigated by the User-Brand Impact constraint and by shipping counts, not a per-site index;
(c) regressing the merged #6572 fix — mitigated by AC7.

**Product/UX Gate:** not applicable. The mechanical UI-surface scan over `## Files to Create` /
`## Files to Edit` matches no UI-surface path. Tier: NONE.

## Architecture Decision (ADR/C4)

**None.** No ownership/tenancy boundary, no new substrate, no resolver or trust-boundary change, no
divergence from an existing ADR. A probe script and an audit note over existing shell guards.

**C4 completeness check** (enumeration, not a keyword grep) — at /work Phase 0, read all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` and confirm for this
change: (a) **external human actors** — none added; (b) **external systems/vendors** — none added
(GitHub Actions is the existing, already-modeled CI substrate); (c) **containers / data stores** —
none touched (the note is a repo file); (d) **actor↔surface access relationships** — none change.
If any turns out already-unmodeled, that is a pre-existing gap: record it, do not expand scope.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --json number,title,body --limit 200`
returned no issue naming `apps/web-platform/infra/scripts/`, `sigpipe-triage-feasibility.sh`, or
`knowledge-base/engineering/audits/`. #3820 (`safe-bash: extend allowlist with grep/find/rg/…`) is
adjacent in vocabulary only — it concerns the hook allowlist, not these guards.

## Alternatives Considered

| Alternative | Why not |
|---|---|
| **v1: classifier + 284-row provenance ledger + 11-rung attestation** | **Cut.** R1 eliminates ≤16, R2 ~0, so R3 decides everything — and R3 is undecidable for the dominant var-fed class without the byte model the plan bans. The apparatus was architecturally incapable of producing the REACHABLE count its own scope-gate consumed; the ledger would have been majority `UNDECIDED` by construction. Four reviewers converged with reproduced numbers. |
| **v1's W2 rung ("bounded ⇒ no window", measured)** | **Cut.** It licensed a *negative existence claim from finite non-observation* — a frequency argument run backwards, banned in the REACHABLE direction and accepted in the INCAPABLE direction. The asymmetry favored making sites disappear: a false REACHABLE costs one conversion; a false INCAPABLE deletes a live silent guard forever. And it pinned the *uncontested* half of the syllogism — the 194 defect was the unestablished **antecedent** (are the vars bounded?), which Phase 2 now targets directly. |
| **v1's W4/W5 (`\|\| true` vs `\|\| ok=0`)** | **Cut.** Zero members in the corpus (Reconciliation row 5). |
| **File the tracking issue with the prior numbers** | What the second-opinion gate rejected; what #6578 exists to resolve. |
| **Convert all sites blind now** (`\| grep -q<f> P` → `\| grep -<f> P >/dev/null`) | **Not rejected — surfaced as UC-3.** Measured semantics-preserving, and it moots the triage question. But it reverses the operator's stated direction (measure first) and the operator already declined this style once on #6573 (UC-1). Per ADR-084 operator direction is the default; this is the operator's call, presented with data. Note the naive `sed` is unsafe: appending `-F` to `-qE` yields conflicting flags — the transform is `-q<flags>` → `-<flags>` + `>/dev/null`, and `-q` on an infinite producer would hang without it. |
| **Byte-threshold triage** | Retracted false precision. Scheduling decides frequency; no byte count does. |
| **Repo-wide scope (919 sites)** | Not the niche the input record named. Stated as a bound with its command; the probe takes `--pathspec`. |
| **Force the brief's strict binary** | Would recreate the 194 figure's defect. Surfaced as UC-1. |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **A verdict taken on a non-CI grep** → false all-clear, the most dangerous outcome available | AC1's negative arm: the probe asserts the grep implementation and exits non-zero. This session's own first probes read 0/200 through a ugrep shim and would have "proved" the corpus incapable. |
| **Publishing a targeting artifact** (public repo) | Counts + commands only; no ranked per-site index of live-vacuous security rungs. Site detail → tracking issue. |
| **Phase 2 concludes `bounded` from shape** → recreates the 194 figure | Phase 2's explicit bar: a site is bounded only when the *assignment* resolves to a bound. |
| **`set -e` symptom missed** (32/44 files) | `symptom` (`inverts` \| `aborts`) is a Phase 1 output axis. |
| **Probe self-matches** — its own source and the note contain the shape it hunts | The note lives outside the default pathspec. The probe does **not**: `infra/scripts/` is genuinely in-corpus (`gen-github-egress-cidr.test.sh:62` carries a live instance). So the probe must strip comments, double-quoted strings, **and heredocs** — heredoc bodies survive all of v1's normalisations and are tracked text `git grep` enumerates. #6573 hit the self-match trap twice; v1 left a third door open. |
| **Normalisation order** | The proven pipeline is `scan-workflow.test.sh:138-142` as a **block**: fold continuations → strip comments → strip strings → fold pipe-newlines → match. Two seds, not one (`:138` folds continuations; `:141` folds multi-line pipes). Order is load-bearing: pipe-folding after string-stripping, continuation-folding before comment-stripping. |
| **`R1`/`R2`/`N1` name collision** | `scan-workflow-mutation.test.sh:27-31` already owns `R1`/`R2`/`N1` meaning RED/GREEN/normalisation rungs. This plan's conditions are renamed **PF / RC / WIN** to avoid two files meaning different things by the same token. |
| **Advisory job** | `deploy-script-tests` confirmed advisory. Stated in Observability rather than claimed as a blocking gate (#6572's "blocking gate" premise did not hold either). |

## Sharp Edges

- **`grep` may not be GNU grep, and the difference is total.** `ugrep -q` does not early-exit; a
  measurement through it reads 0/N everywhere. `type grep` before trusting any pipefail/SIGPIPE
  reading — this session's shell had a `grep` **function** shadowing `/bin/grep`. The failure mode
  is a *green false all-clear*, which no one goes looking for.
- **A negative result from finite non-observation is not proof of impossibility.** #6573's 8 KB
  producer read 0/200 unperturbed, flat 0/40 from 4 KB→64 KB — **and was still killed under
  strace**. Any "never happens" rung is an absence of observation wearing a measurement's clothes.
  Prefer an argument from construction, and label it `structural`, not `measured`.
- **A syntax count sold as a relevance count is the defect this whole lineage is about — and it is
  easy to commit while condemning it.** v1's "202 `|| true` lines make this class material" had
  **zero** overlap with the corpus under test. Every count needs its command *and* its
  intersection with the set actually under discussion.
- **`| grep -q` inside this plan, the note, and the probe's own strings is the
  document-what-you-forbid collision.** #6573 hit it twice; v1's AC6 flagged its own definition.
  Strip comments, strings, **and heredocs**; scope enforcement greps to output artifacts, never to
  the plan that must name what it retracts.
- **A self-assertion of registration is vacuous** — an unregistered script never runs. The
  `scan-workflow.test.sh:95` precedent is a **cross-file** assertion; do not mirror it as a
  self-assertion.
- **A pinned-SHA regenerate-and-diff can never detect drift** (reproducible by construction), and a
  HEAD one reds every future infra PR. Neither is a drift gate; do not ship one believing it is.
- **`git grep -- 'apps/web-platform/infra/**/*.sh'` silently undercounts (5 files vs 44)** — the
  `**` pathspec matches only nested dirs. Use the directory-prefix pathspec. This session's own
  first measurement was wrong this way.
- **`comm`/`sort` without `LC_ALL=C` runs blind** and prints nothing while appearing to pass.
- **Nothing auto-discovers `*.test.sh` under `infra/`** — explicit registration required.
- **Agent convergence is not proof when the agents share a wrong model** — but *divergent* agents
  reproducing the same command's output is evidence. Four reviewers independently reproduced
  44/284/202/0/16 here; that is why v1 was cut rather than defended.
</content>
