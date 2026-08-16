# Resume prompt — PR-B #7546 review-fix pass (option 1: work the full list)

Copy everything below the line into a fresh session.

---

/soleur:go Resume PR-B in the EXISTING worktree
`.worktrees/feat-one-shot-7104-apply-verify-repost-pr-b` (same-named branch, draft PR #7546).
Do NOT create a worktree or branch. Do NOT re-run the terraform plan. HEAD is `974a77c43`,
22 commits ahead / 9 behind origin/main, 1 unpushed, tree clean.

This is a REVIEW-FIX pass, not new feature work. A 12-agent review returned 2 P0s (fixed) and
~28 further findings. Read `knowledge-base/project/specs/feat-one-shot-7104-apply-verify-repost-pr-b/session-state.md`
first — but treat its `### Decisions` as INTENT, not accomplishment: this session already found
task 9.1 ticked with half unbuilt and task 7.5 folded into something that cannot discharge it.

## BINDING RULING (soleur:engineering:cto) — do not re-litigate

**(C) sequenced A-then-B.** Ship the bounded recovery (this PR) first; implement the root-cause
readiness probe as Phase 2, blocked on the first firing's forensics. Reasons, all verified:

- The root cause is NOT established. `infra-config-apply.sh:80` does `rm -f "$STATE_FILE"` before
  any work, so a handler that ran and was killed leaves NO frame. Nonce-1 observed a *readable
  stale 13/13 frame* → the handler never reached that line. The "async handler exec was
  disrupted" note is inference.
- A readiness probe cannot be a proof. `webhook.service` is `Type=simple` (active at fork, before
  `hooks.json` parse / `:9000` bind), the bootstrap ALREADY asserts `is-active` at server.tf:164
  and that passed during nonce-1, and `StartLimitIntervalSec=0` + `Restart=on-failure` + the
  handler's own `+3s` `webhook-self-restart` reopen the window after any probe succeeds.
- Blast radius is inverted from the naive read: A repeats a byte-identical, already-authorized,
  nonce-idempotent write; B would put a fail-closed condition inside the SOLE no-SSH delivery
  path for an unreplaceable host (cx33, 0/6 stock). Phase 2's probe must be advisory-with-timeout,
  never a blocking assertion.
- The ≥3-in-30-days trigger is NOT a merge blocker — unfireable at n=1 in ~13 months. Do not build it.
- Do NOT delete the sensing/adjudication/actuation split (it dissolved R20.3–R20.6).

## DONE (committed, verified — do not redo)

- `aefce3b2e` Guard 2 pin extended (counting-`done`, predicate-invoked-once, one-apply-site,
  library sweep) + the gate suite's self-test fixed (it redefined `fail()` in its own subshell,
  so `fail() { :; }` reported 127/0 exit 0 GREEN).
- `2dd55a851` `infra-config-repush-mutation.test.sh`, 17 rows, registered.
- `a23ae8ce0` Phase 10 ticks, ADR-187→189 renumber, five-vs-six correction, AC20 re-derived
  (arm byte-identical, 7269 B, sha256 `83d8e73ee8518502` both sides — do NOT re-derive).
- `974a77c43` **P0-1** red-gate alert re-keyed onto the terminal verdict + a RE-PUSH dispatch arm;
  **P0-2** `$STATUS_RESPONSE` injectable (default = the fixed literal, because the alert step is a
  different process that reads it back). Measured after: 6 concurrent verify runs, 6/6 green
  (was 5/6 RED).

Suites now: gate **130/0**, verify **23/0**. Both must stay green.

## REMAINING — work in this order

### P0-3 (blocking, CTO-elevated)
A *green* recovered run notifies nobody. `op=infra-config-repush-attempted` matches no
`sentry_issue_alert` rule (the code says so itself) and the ledger is created closed. Route every
run where `steps.repush_apply.outcome != 'skipped'` — **green or red** — through
`infra_config_red_alert` (`scripts/infra-config-red-alert.sh:33`). Keep the Sentry breadcrumb.

### Guard hardening — 14 of 22 mutants survived a `test-design-reviewer` battery
My battery reported 17/17; it has an unedited axis: **extractor uniqueness / anchor scope**.
Every structural survivor is an extractor escape, not a logic edit. Fix by converting scalar-count
guards to parsed-YAML structural assertions, and add a row per fix.

- **m18 (top)** — compose: `if:` above `id:` + `.outcome` instead of `.outputs.` + the graded
  literal demoted into a comment → the apply fires whenever the plan step succeeded, REGARDLESS of
  `repush_graded`. Suite 130/0 rc=0. Fix: parse the YAML, assert
  `steps[id=='repush_apply'].if` EQUALS the measured literal (positive equality, not a negative grep).
- **m5** — `repush_plan` `if: false` → recovery unreachable, all green. Nothing pins that a CONSUMER
  consumes `repush_needed`. Fix: assert `steps[id=='repush_plan'].if` contains `repush_needed == 'true'`.
- **m1** — compose G2-1 + G2-5; `done_count` cancels back to 1. Fix: assert `adj_line` is after the
  loop's closing `done` structurally, not by count.
- **m2** — `for _i in 1 2 3; do terraform apply … tfplan-repush; done` on one line in one step; both
  "independent producers" agree. Fix: count occurrences per step body + forbid a loop keyword there.
- **m3** — `|| true` on the predicate's condition line → verdict discarded. Fix: forbid `|| true`/`|| :`.
- **m7** — backticks and `xargs`/`env`/`bash -c` wrappers evade `LIB_SWEEP`. (I separately measured
  **11 of 12** write-shaped inputs evade, incl. `doppler run … -- terraform apply` — the shape this
  workflow uses twice.) Fix: invert to an allow-list of the ~6 commands the library legitimately runs.
- **m9 / m15** — `pass=$((pass + 2))` → 260 passed; `GATE_MIN_ASSERTIONS=$pass` → tautology. The floor
  has one producer. Fix: tie `$pass` to emitted `PASS:` lines, or add a second producer.
- **Marker vacuity** — 12 of 17 battery markers appear in a GREEN baseline log, so those rows
  degenerate to `rc == 1`. Fix: `grep -qE "^  FAIL: ${marker}"`; de-duplicate the two collided
  markers (G1-3/G1-6 both `#7104 P4:`; G2-2/G2-4 both `#7104 Guard 2 (5)(6):`).
- **Stub argv values** — m12/m13/m14: the curl HOST, the HMAC VALUE and the Doppler SECRET NAME are
  unpinned (presence-only fidelity). m11: `sleep`/retry cardinality voided. Add value pins + counts.
- **m17 / fixture direction** — production's inline freshness boundary decides staleness BEFORE
  delegating to the predicate, so the predicate's `-lt` is a redundant second evaluation and P4's
  equality arm is UNREACHABLE in production. Add a `start_ts == APPLY_START_EPOCH` fixture and a
  fresh-frame-on-pass-1 case (the `else` arm).
- **No stay-green control** — all 17 rows expect rc=1. Add one `want_rc=0` row (zot's row `n` precedent).
- **`g1_checked >= 4` against a measured 11** — pin it flush at 11. Same for `copied >= 50` vs 268.
- **Guard 3's `-A2`** — key-order dependent; a two-space `id:` or a reordered `if:` fails it OPEN.
  Subsumed by the m18 fix.
- **Duplicate cardinality floor** — the standalone `g1_checked >= 4` cannot fail when the earlier
  clause passed; delete (it inflates the tally by 1, so re-measure `GATE_MIN_ASSERTIONS`).

### Correctness / robustness
- `ledger_body` step lacks `set +e` + terminal `exit 0` (its sibling has both) → a bookkeeping
  failure reds a successful self-heal. Do NOT use `continue-on-error` — it pins `conclusion` to
  `success` and would feed `scripts/followthroughs/moved-block-wedge-5887.sh` green over red.
- Three unguarded `jq` captures in `repush_plan` abort MUTE before their own `::error::`
  (`rc=0; X=$(…) || rc=$?`). The missing `?` on `.resource_changes[]` is load-bearing (it makes
  degraded JSON fail CLOSED) — add a comment so a future "consistency" edit doesn't add `[]?`.
- A refused grade (0 or ≥2) exits green and silent; the backstop then misattributes it as
  "skipped or mis-keyed". Add an `::error::` naming the real cause.
- The decorative address-listing `jq` runs BEFORE the `repush_graded` output write under `set -e`
  → a cosmetic failure vetoes a correctly-graded recovery. Move the write above it, and ASSERT the
  address set instead of printing it (it is already computed).
- The 404 `ALLOW_MISSING_STATUS=true` arm falls through to the tail `verdict=verified` having
  adjudicated nothing. Emit `verdict=unadjudicated`; the backstop already only accepts `verified`.
  This does NOT touch the AC20-frozen region (that arm is under `HTTP_CODE == 404`) — but re-derive
  AC20 after.
- Pin pass 2's `ALLOW_MISSING_STATUS: 'false'` literal in Guard 1 (currently one word from false).
- `${ALLOW_MISSING_STATUS:-false}` — the only var read without a default under `set -u`.
- Nothing asserts pass 2 INVOKES the tested script (`head -1` over a population of 2). Derive from
  the parsed YAML: for each `SCRIPT_STEPS` id, assert its `run` matches `bash .*infra-config-verify\.sh`.
- Guard 1's `SCRIPT_STEPS` is hardcoded — derive it from the steps whose `run` invokes the script.
- Widen traps to `EXIT INT TERM HUP` in the battery's child (per `mktemp`) and parent; register the
  parent's before the second `mktemp -d`. (A killed run leaked 12 entries; I reclaimed them.)
- Binary `tfplan-repush` survives when the apply is skipped: add an `if: always()` cleanup step after
  pass 2, and add `tfplan-repush*` to `apps/web-platform/infra/.gitignore`.
- `outcome != 'skipped'` inverts the null trap on a renamed id → fires on every run.

### Documented corrections (each is a false claim I authored)
- **ADR-189 → ADR-190.** A third branch (`origin/feat-one-shot-7341-…`) took 189, pushed 8.5 min
  before my renumber commit. Re-derive across ALL `origin/*` refs again at merge — task 10.3 stays OPEN.
- ADR: "Backend lock handling is now explicit" is FALSE — `main.tf:19` is `use_lockfile = false`;
  `-lock-timeout` is inert. The concurrency group is the sole serializer.
- ADR + `decision-challenges.md:95`: `#7095` does NOT record a malformed value bricking a host — it
  records a STALE credential serving stale code with the site UP. This inflation carries the CPO
  sign-off threshold.
- `tasks.md`: "seven existing siblings … quiet, exit status is the verdict" — there are EIGHT and
  only ONE is quiet-with-rc-as-verdict. The predicate mirrors one sibling, not seven.
- `infra-validation.yml` step comment: `~85 s … 4 at a time` is a 16-core figure. Measured on a
  4-vCPU public runner: **~157 s at JOBS=2**. (My first correction, "~3.7 min at JOBS=1 on 2 cores",
  was ALSO wrong — public repos get 4-vCPU runners.)
- The plan line badged "R20.2's measurement re-confirmed independently" is false against this PR's
  own output (claims 2 `if:` / 3 `env:` / one `always()`; HEAD has 3 / 7 / 6).
- "residual ADR-187 is 0" is self-refuting (4 narrative hits). Say "0 outside the collision narrative".
- The step comment calls registration "a gate": registration IS hard-gated (required
  `guard-script-fixture-tests`), but `deploy-script-tests` EXECUTION is advisory.
- Battery header cites `cf-tunnel-liveness-gate` as a sibling in "this directory" — it is in
  `scripts/` and named `-mutations.test.sh` (plural). Inherited from zot's header.
- `session-state.md` `### Decisions` and `decision-challenges.md` UC1 still describe the PRUNED
  inline-latched-block design in the present tense — and `/ship` renders decision-challenges into
  the PR body, so the PR would assert a design contradicting the ADR.
- Plan `19,710 bytes` → 19,774 (two sites); R18 header "authoritative" must name R22.
- `tasks.md` 7.5 carries a duplicated marker and a live-reading "Add the ≥3-in-30-days escalation".
  Say plainly it was cut and why (unfireable at the observed rate).
- Three commits (`aefce3b2e`, `2dd55a851`, `a23ae8ce0`) dropped `Co-Authored-By`.
- ADR must ALSO record: R17.8's free win under `use_lockfile = false`; the ADR-072 distinction as
  ADR-186 states it; R20.5's 6 s + 3 s = 9 s measurement; the **fix-at-source alternative** with the
  CTO's three reasons; boundedness is per-RUN (a job re-run produces a fresh eligible re-push); and
  the sunset condition verbatim from the ruling.
- Re-derive the two timeout budgets: `deploy-script-tests` (565 → ~731 s vs 840; the block carries a
  standing "re-derive this if steps are added" instruction and two prior RE-DERIVED entries) and
  `main-health-monitor.yml`'s infra step (15 → 20 min by its own roundup5 rule).
- Guard naming collision: `## Guard Contract` numbering (linted by `scripts/lint-guard-contract.py`)
  vs R22.5's. Rename R22.5's three in code to `WORKFLOW-REF PIN` / `VERBATIM-MOVE GATE` /
  `CARDINALITY PIN`; leave the plan's numbering alone.

### Then
Rebase onto origin/main (9 behind; #7516 added a sibling step to `infra-validation.yml` ~21 lines
from mine — no guard reds, but "suite 39 of 107" goes stale). Re-run: both suites, the battery,
`actionlint`, `lint-orphan-test-suites`, `lint-workflow-errexit-capture`, `lint-guard-contract`,
`test-infra-suite-registration`, and `apps/web-platform/infra/run-registered-suites.sh` on a quiet
machine (that directory has NO required CI status check — it is the one half no gate covers).
Then `/qa` → `/compound` → `/ship` → `/postmerge`. PR body must carry `Closes #7104`.

### File Phase 2 BEFORE merge
An issue for the root-cause readiness probe, blocked explicitly on the first firing of the recovery,
with acceptance criteria: read `preframe_status`, `observed_start_ts`, and pass 2's frame
`restarts[]` (`exec_main_start_ts_before/after`, `nrestarts`) plus the host journal; NAME the
mechanism; then append an advisory-with-timeout MainPID-changed-AND-serving probe to
`infra_config_handler_bootstrap`'s existing inline list (never fail the bootstrap on it).

## TRAPS (each cost time this session)
- Don't edit while a suite/agent is reading the worktree — it invalidates their evidence.
- Spawn review agents REPORT-ONLY at panel scale; apply fixes yourself from one SHA.
- `pgrep -f <pattern>` matches its own command line — use `plugins/soleur/scripts/lib/proc.sh list_runs`.
- Verify the instrument before the finding: my Guard 3 "vacuous" reading was a `\$` escaping bug,
  and my `~3.7 min` correction was wrong about the runner's core count.
- A python `.replace()` over a file whose declaration contains the literal rewrites the declaration
  too — I shipped a self-referential `${VAR:-"$VAR"}` this way.
- Commit each verified unit immediately.
