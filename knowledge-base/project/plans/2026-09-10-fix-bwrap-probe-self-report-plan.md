---
title: "fix(deploy): the blocking bwrap canary probe discards its own diagnostic"
date: 2026-09-10
slug: fix-bwrap-probe-self-report
branch: feat-one-shot-8016-bwrap-probe-self-report
issue: 8016
closes: 8016
lane: single-domain
type: bug
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

The web-platform deploy gate runs a blocking bwrap probe inside the canary container. When it
fails, the deploy rolls back and the record is one fixed string naming the image and tag — nothing
the probe itself observed. Two releases were blocked this way (v0.260.0 on 2026-09-04, v0.264.6 on
2026-09-09) and both left zero evidence of cause.

Two tasks, one PR:

1. **Correct a mis-framing on #8016.** Two different canaries in the same script both use the word
   "sandbox". A passing verdict from the non-blocking one was read as contradicting the blocking
   one. It does not — the two never run on the same code path.
2. **Make the blocking probe self-reporting**, and give it a delivery leg, not just a log line.

## Research Reconciliation — claim vs. measurement

Six premises this plan was handed were falsified at plan time. Recording them because three came
from artifacts a reader would ordinarily trust: the issue, a domain-agent advisory, and an ADR.

| Claim as received | Measured | Plan response |
|---|---|---|
| "The gate's reason string contradicts its own payload" (#8016 headline) | Two distinct canaries. `reason=canary_sandbox_failed` comes from the BLOCKING probe; `sandbox_canary:{verdict:"pass"}` is written by `write_sandbox_canary_state`, called only from `run_faithful_sandbox_canary`, which is invoked only AFTER the blocking probe passes. On a blocking failure it never runs. The block is a standing cross-deploy record in `/mnt/data/ci-deploy-sandbox-canary.json` (`consecutive_pass: 435` is cumulative), so a 31-minute-old `checked_at` is correct by construction. | Task 1 states the mechanism. Both "Suggested direction" theories in #8016 are dead and are not planned. |
| "The `2>&1` merges stderr into stdout, and only `logger` lines reach journald — so the bwrap error message is discarded" | **False.** `webhook` IS in the Vector allowlist, and webhook buffers the command's combined output and logs it at exit, so the merged stream reaches Better Stack. Journald `__SEQNUM 73412441` (`Verifying bwrap sandbox...`) and `73412442` (`Canary sandbox check failed, rolling back...`) are **consecutive**; identical shape on 2026-09-04 (`71777234` → `71777235`). | The probe **never spoke**. Capturing stderr alone would have printed `<empty>` and named nothing. The missing discriminator is the **exit code**. The Task 1 comment must not repeat the discard claim. |
| "2 failures in 6 runs ≈ 33%" | **2 in 83 probe attempts = 2.4%**, 2026-08-13 → 2026-09-10. | The soak arm is far weaker than assumed. Arm 1 becomes primary. |
| Prescribed capture `if ! BWRAP_ERR=$(…); then …` | Errexit-safe, but `$?` in the then-branch of `if ! cmd` is the **negated** status. **Measured `A_RC=0`.** | Would have logged `rc=0` on every failure and looked green. Use `VAR="$(…)" \|\| RC=$?`. |
| Reflexive alternative `BWRAP_ERR="$(cmd)"; BWRAP_RC=$?` | A bare assignment from a failing substitution **aborts** under `set -euo pipefail`. **Measured `SCRIPT_EXIT=125`**, the `RC=$?` line never reached. | Would skip the logger line, the teardown and `final_write_state`, leaving `reason=unhandled` — **less** diagnostic than today. |
| CTO advisory: "bwrap mirrors the shell convention — 125 setup-failed / 126 not-executable / 127 not-found" | **False**, verified twice. Locally every bwrap self-failure returns **1**. Upstream `containers/bubblewrap`: `git log -S125`, `-S126`, `-S127` return **zero commits each** across all 717. | The advisory's conclusion (do not classify) survives on other grounds; its stated reason does not. See `## What rc will say`. |
| ADR-079 line 509: "Status stays `adopting` (Deferral A / #5889 still open)" | **False.** `#5889` is **CLOSED / COMPLETED, 2026-07-06**, with the sweeper verdict *"52 consecutive green canary verdicts … canary proven; promote to blocking in PR3."* The promotion was never made — `ci-deploy.sh` still reads `run_faithful_sandbox_canary \|\| true`. | An earlier draft used "ahead of #5889's soak" as a live reason not to classify. Deleted — it was a closed-issue gate smuggled in as a premise, exactly the class this plan's own Sharp Edges warn about. Filed as **adjacent finding 4**. |
| "`<empty>` distinguishes a silent probe from a consumed message" | Half true. `_cred_err_tail` is **length-preserving** (`tr -c` substitutes, it does not delete; the `sed` replacement is non-empty), so non-empty in ⇒ non-empty out, always. `err_chars=0 ⟺ err="<empty>"` identically. | Keep `err_chars` on the **truncation** property only. The consumed-message rationale is deleted as unreachable. |

## Research Insights

### Premise validation (Phase 0.6)

`#8016` is OPEN, `type/bug`, `priority/p2-medium` — not already closed by a merged PR. `#6560` is
OPEN. Both target files exist with the cited content anchors. `deploy_pipeline_fix` resolves in
`plugins/soleur/skills/ship/SKILL.md` (auto-apply on merge via `apply-deploy-pipeline-fix.yml`, no
separate apply step). `ci-deploy` is in the Vector allowlist. Own-capability claims were verified
rather than asserted (`hr-verify-repo-capability-claim-before-assert`): "the harness can assert on
logger output" and "the repo has no mechanism for this property" were both checked, and both checks
changed the plan. Issue status was re-derived from `gh`, not inherited from an ADR
(`hr-before-asserting-github-issue-status`) — which is how the #5889 staleness surfaced.

### Property list (Phase 0.6b)

- **P1** — A reader arriving at #8016 can tell which canary the gate measured.
- **P2a** — A reader without host access can distinguish "the probe spoke" from "it was silent".
- **P2b** — When the probe is silent, the event still names *how* it terminated.
- **P2c** — A reader can tell a truncated diagnostic from a complete one.
- **P2e** — A reader can tell an immediate refusal (milliseconds) from a killed hung probe
  (seconds). `rc` alone cannot: a signal at 40 ms and a signal at 30 s carry the same code and the
  same empty output. This is the H3-vs-H4 discriminator.
- **P2f** — The emit path is proven by a **green** deploy, not only by a failure.
- **P2g** — A person is **told**, not merely able to query. Capture without delivery fixes nothing.
- **P3** — A regression that drops any of the above reddens the suite.

### Cut list (Phase 0.6b)

| Mechanism | Property | Why cut |
|---|---|---|
| Stale-freshness gate for `sandbox_canary` (#8016 direction 1) | none | The staleness is correct by construction. |
| Payload-misreporting fix (#8016 direction 2) | none | The payload reports a standing cross-deploy record accurately. |
| Fold the detail into the deploy-state `reason` string | P2a/P2b on a second surface | `ci-deploy.test.sh` asserts `reason` by exact equality, the release workflow surfaces it, and #2276/#8016 are tracked by that literal. Frozen. |
| Port ADR-079's 125/126/127 classification into the blocking probe | would change gating | Out of scope. **The two reasons an earlier draft gave were both wrong** — bwrap does not use those codes (falsified upstream), and #5889's soak is not pending (it passed and authorized promotion). The reason that survives on its own: branching on rc without an observed distribution is exactly what #4932 did, and it rolled back every web-platform deploy. This PR is the measurement a future classification needs. The orphaned promotion is filed separately rather than absorbed here. |
| `probe=blocking_legacy` identity token | P2d ("which canary") | The line already carries `bwrap sandbox non-functional`, unique to this probe, and the faithful canary emits `SANDBOX_CANARY_FAIL`. Strictly **worse** for the closure arms: a new token matches only post-merge rows, while the existing literal also matches the two historical occurrences. And #8016's mis-framing came from reading the state file, not the log. |
| Two new mock modes | P3 | The file states its own principle ("Writing one mock (not five) eliminates drift"). Parameterise the existing `bwrap-fail)`. |
| Re-pinning `_cred_err_tail`'s internals from the new call site | P2a | Already pinned with a positive control by `T-7095-3` and `F14`, and the helper's body is not modified. Testing an unmodified dependency twice tests the new code zero times. |
| Reuse `_login_hatch` directly | P2b | It carries a login vocabulary (`_login_kw`, `errno_chars`, `tok`, `docker_ver`). Mirror its shape; do not call it. |
| Invent a new sanitizer | P2a | `_cred_err_tail` exists at the right altitude. A third sanitizer form in one file is debt. |

### Value-proposition measurement (Phase 0.6c)

`--since 720h` against the failure literal returns **2** rows versus **83** `Verifying bwrap
sandbox...` rows — 2.4% on a gate that fires every release. Each occurrence today costs a full
forensic session (this one: 8 Better Stack queries across 4 windows) and still ends without a cause.

### In-repo precedent (the authority greps)

- **`_login_hatch`** — the canonical escape hatch for a blind failed subprocess. Its comments state
  `rc` makes `125/126/127`, **`137` (OOM-killed)** and `124` actionable "from this field ALONE", and
  give the `stderr_chars` / `stdout_chars` disjunction. Field vocabulary (`rc=`, `*_chars=`,
  `err="…"` last-on-line) is taken from here and from `SOLEUR_DEPLOY_CRED_FAIL`. It also documents
  why the count fields are named `_chars` and not `_bytes`.
- **`_cred_err_tail`** — the sanitizer built for free text on a journald line, stating the reason:
  "journald tag `ci-deploy` is allowlisted by vector.toml and shipped to Better Stack UNSCRUBBED, so
  this is a credential boundary". Order is load-bearing: control-strip → `"`→`'` → `dp.` redact →
  **then** tail-200. It documents the negative-substring trap and uses an explicit length test.
- **`sandbox_canary_sentry_event`** — "loud, no-SSH page on a faithful-canary FAIL … never
  journald-only". Env-guarded, best-effort, fail-open. The **non-blocking** canary has this; the
  **blocking** gate does not. That asymmetry is the delivery gap this plan closes.
- **Purity convention (#6497 T-5B-8b)** — a future edit appending raw stderr to a `ci-deploy` logger
  line would ship it off-box "with the whole suite green". Proven with a `SENTINEL_LEAK_CANARY`
  fixture asserted against the FULL capture. Adopted.
- **`create_mock_logger`** writes to `$MOCK_LOGGER_CAPTURE_FILE` when set, else discards. The target
  scenario does **not** set it today, so the rollback line is currently unassertable.
- **`MOCK_ZOT_PULL_FAIL_STDERR`** — the parameterised-mock precedent, one mode over.
- **`ci-deploy-sentry-post-fail-6475.sh`** — same tag, same sink, same credentials; carries both
  contamination byte-forms and the liveness discipline.
- **`final_write_state`** writes `{start_ts,end_ts,exit_code,component,image,tag,reason}`. The
  release workflow consumes it as `REASON=$(echo "$BODY" | jq -r '.reason // "unknown"')` and echoes
  it into an `::error::` line — no enum parse anywhere, which makes the no-enum conclusion stronger
  than an earlier draft claimed (that draft asserted a `case` with a `*)` catch-all; there is no such
  `case`). But `ci-deploy.test.sh` asserts `reason` by exact equality, so it stays frozen.
- **`apps/web-platform/test/infra/vector-pii-scrub.test.sh`** — pins the exact-tag set and the
  deliberate absence of a PRIORITY filter. Note the path: `test/infra/`, not `infra/`.

### Institutional learnings that changed the design

- `learnings/best-practices/2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md` — the
  deliverable is a structured probe whose fields discriminate **all** competing hypotheses. Why `rc`
  is mandatory and why `## Hypotheses` carries UNKNOWN verdicts.
- `learnings/2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed.md` — "a
  guard's assertion and a guard's property drift apart silently". Drives the must-PASS harness rows.
  Adjacent finding 4 is a live instance: a sweeper auto-closed on a PASS that certified the soak,
  not the promotion the soak authorized.
- `learnings/2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`
  — "Assert the reason, never the rc." The extended assertion **adds to** the state-file assertions.
- `learnings/integration-issues/2026-06-02-docker-journald-driver-maps-stdout-to-priority-6-filter-by-pino-level.md`
  — verified not applicable: `host_scripts_journald` carries no PRIORITY filter, pinned by a fixture.

### Baselines taken this session

`bash apps/web-platform/infra/ci-deploy.test.sh` → **216/216 passed, 0 failed**, exit 0, untouched
worktree. `bash plugins/soleur/test/c4-count-parity.test.sh` → 10/10, exit 0. No open `code-review`
issue names either file. No SKILL.md `description:` edit is candidate, so the Phase 1.8 budget check
does not apply. `AGENTS.rules.md` is at B_ALWAYS=45999 against a 46000 REJECT ratchet — **this plan
adds no rule to the corpus**. `#8016` body SHA-256 at plan time:
`c3aea158b8443b13ad7aad0284c5a98add3369dbd694564cd44f67e7697a75b4` (recorded so AC16 has something
to compare against).

### Community / functional discovery

Three registries queried. No Tier 1/2 candidate overlaps shell stderr/exit-code capture.

## What `rc` will say

The plan turns on this field, so the code space is enumerated from sources rather than assumed.
bwrap's half is settled upstream; docker's half is **undocumented** and is measured in Phase 0.

| rc | Meaning |
|---|---|
| 0 | pass |
| 1 | **bwrap's own failure** (setup, bad flag, `execvp`) **or** docker "no such container" / "not running" |
| 126 / 127 | docker/runc could not exec the `bwrap` binary |
| 128 | moby `exitUnknown` fallback |
| 128+n (137, 143) | the exec'd process was **signalled** |
| 255 | bwrap saw an unrecognized wait status ("Weird?" in `propagate_exit_status()`) |

**bwrap: cite, do not measure.** `die()`, `die_with_error()`, `die_with_mount_error()` and
`die_oom()` all end in a literal `exit(1)` in `utils.c`; `EXIT_FAILURE` appears twice, both
`usage(EXIT_FAILURE, stderr)`, which is 1 on glibc. The `execvp` path at the end of `main()` funnels
ENOENT and EACCES to `die_with_error`. Decisive: `git log -S125`, `-S126`, `-S127` over all files and
all 717 commits return **zero commits each** — those codes have never existed in the tree, in any
release from v0.1.0 to v0.12.0. Upstream issue **#701, "Have a specific exit code for when sandboxing
is not possible", is still OPEN**, precisely because bwrap returns a generic 1.

**Where the advisory's claim came from.** bwrap *does* borrow one shell convention and says so in a
bash-citing comment in `propagate_exit_status()`: **128+n for signal deaths**. It borrows bash's
128+n rule and not bash's 126/127 rules. The advisory generalized the half that is real.

**docker exec: measure, do not cite.** The `docker run` reference page's 125/126/127 table is scoped
to `run` in its own first sentence, and `docker exec` has **no exit-status section**. The 126/127
codes come from the daemon stamping the exec record's `ExitCode` via error-*string* matching
(`moby/daemon/exec.go`, `isInvalidCommand`), read back through `ExecInspect` — version-dependent and
string-fragile.

**This strengthens the instrument.** `1` vs `126/127` vs `≥128` vs `255` is a clean four-way split,
and none of it is reachable without the field this PR adds. It also sharpens H3: `--die-with-parent`
kills with SIGKILL, landing squarely in the `128+n` band — the only band bwrap documents.

## Hypotheses

Verdict discipline: the deciding datum for every root-cause hypothesis is the exit code, and that
datum **is not captured today**. So every hypothesis about *why* the probe failed is `UNKNOWN`,
including the ones that feel refuted. Only a hypothesis whose discriminator is visible in the current
code or logs may carry a verdict.

| # | Hypothesis | Discriminator | Verdict |
|---|---|---|---|
| H1 | bwrap could not set up the sandbox (userns / AppArmor / seccomp drift) | `rc=1` **and** a non-empty message — every bwrap self-failure returns 1 and its `die_with_error` path prints `bwrap: …` first. The measured message is empty, which weakens H1 but does not refute it: a process killed before it writes prints nothing. `rc=1` is shared with docker's "no such container", so the message is what separates them. | **UNKNOWN** |
| H2 | `docker exec` infra failure | `rc` in 126/127, or `rc=1` with docker's own text, or `rc=128`. Zero bytes argues against, since docker does print. | **UNKNOWN** |
| H3 | The exec'd child was killed by a signal (OOM / SIGKILL) | `rc` in the `128+n` band. Consistent with **every** measured datum — a signalled process writes nothing. Currently untestable: `kernel` is in **no** Vector allowlist and `system_journald` cuts at `PRIORITY 0-2`, so an OOM-killer line cannot reach Better Stack; and `ci-deploy`'s own `oom_killed:false` describes the **container's main process**, not an exec'd child. | **UNKNOWN** |
| H4 | Container not fully settled when the probe ran | Measured: the canary's first log line was 22:31:54.598 and the rollback marker 22:31:57.450 — **2.852 s of total container life**, health loop breaking on its first iteration. `secs=` is what will separate this from H3. | **UNKNOWN** |
| H5 | A timeout wrapper killed the exec | The probe argv contains no timeout wrapper. Discriminator visible in source. | **REFUTED** |

Both occurrences are byte-for-byte identical in shape: canary healthy, probe invoked, zero output,
rollback. Whatever this is, it is the same thing twice.

## User-Brand Impact

**If this lands broken, the user experiences:** an errexit-unsafe capture aborts `ci-deploy.sh` at
the canary stage. Production keeps serving the previous image (the cutover is downstream), but the
EXIT trap writes `reason=unhandled` and every subsequent release fails red until the change is
reverted. The founder cannot ship, and cannot reach the host to see why. Recovery is a revert plus a
re-release, roughly one release cycle. The change is on the **failure path only**, so no green deploy
exercises it — which is what the success-path twin and the Sentry leg exist to blunt.

**If this leaks, the user's operational data is exposed via:** free text captured inside the canary —
potentially embedding host paths, container ids, overlay digests or internal IPs — reaching journald
tag `ci-deploy`, which `vector.toml` ships to Better Stack. The channel is pre-existing (the same
sink already receives `docker logs soleur-web-platform-canary --tail 30` **unsanitized**), so this is
a new payload class on an existing channel, not a new channel — and per byte it is a strict
*reduction* in what is unsanitized. Mitigation is `_cred_err_tail` plus a leak-canary assertion over
**both** sinks.

**Brand-survival threshold:** single-user incident.

CPO sign-off obtained at plan time: **APPROVE WITH CONDITIONS**, all four folded into the acceptance
criteria. CPO corrected the blast declaration (prod keeps serving; *releases* stop) and the leak
declaration (pre-existing channel), both reflected above. `user-impact-reviewer` applies at review.

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/infra/ci-deploy.sh` | The probe's capture, the `DEPLOY_ROLLBACK` line, the success-path twin, a new `blocking_probe_sentry_event`, and one sentence in `_cred_err_tail`'s header. The NOTE block above the probe and the bwrap argv are **not touched**. |
| `apps/web-platform/infra/ci-deploy.test.sh` | Parameterise the `bwrap-fail)` mock; extend `assert_canary_sandbox_failed_state`; add the purity, success-path and Sentry assertions. |
| `knowledge-base/legal/article-30-register.md` | One additive dated bracket on PA-8 §(g). Contested by one reviewer — see `## Decision challenges`. |

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/project/specs/feat-one-shot-8016-bwrap-probe-self-report/tasks.md` | Task breakdown. The directory exists and is empty, so this is a create. |
| `scripts/followthroughs/bwrap-probe-selfreport-<N>.sh` | The follow-through probe. `<N>` is the new tracker's number, assigned at filing. |
| `scripts/followthroughs/bwrap-probe-selfreport-<N>.test.sh` | Pins the probe's exit-code contract — the convention is explicit that "an exit-code contract nothing drives is a comment". |

`blocking_probe_sentry_event` is a new **function** inside `ci-deploy.sh`, not a new file, modelled
line-for-line on `sandbox_canary_sentry_event` with `op: "blocking-sandbox-probe"`. No new secret: it
reuses the same `SENTRY_INGEST_DOMAIN` / `SENTRY_PROJECT_ID` / `SENTRY_PUBLIC_KEY` guard.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit 200` piped
through `jq --arg path … contains($path)` returns zero matches for both target files.

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)

0.1 Re-read the NOTE block above the probe (anchor `# NOTE: a prior change (#4932) added --unshare-user --proc /proc here to`).
0.2 Confirm `_cred_err_tail` is top-level and therefore in scope at the probe site.
0.3 Re-run the capture-form check — the line the whole PR turns on:
    `bash -c 'set -euo pipefail; f(){ return 137; }; RC=0; V="$(f 2>&1)" || RC=$?; echo "rc=$RC len=${#V}"'`
    Expected `rc=137 len=0`.
0.4 Measure `docker exec`'s exit-code stamping against the **pinned host Docker version** (the
    2026-09-09 rows report `docker_ver=29.3.0`) — undocumented and daemon-stamped. Do **not** measure
    bwrap's codes; cite upstream, which is settled across every release.
0.5 Baseline: `bash apps/web-platform/infra/ci-deploy.test.sh` reports `216/216 passed, 0 failed`.
0.6 Run the live Better Stack query with both contamination byte-forms **now, at /work** — see
    `## Querying without contaminating the answer`. It is the only check that surfaces the JSON
    escaping and the webhook contamination before merge.

### Phase 1 — Test first (RED)

1.1 Set `MOCK_LOGGER_CAPTURE_FILE` in the `assert_canary_sandbox_failed_state` scenario so the
    rollback line becomes assertable. **The export goes INSIDE the scenario's existing
    command-substitution subshell**, with the capture path from the scenario's own `mktemp -d`;
    assertions read it after the subshell returns. Hoisting it to scenario scope would contaminate
    four later scenarios that depend on the same variable.
    Borrow the **line-selection-by-unique-prefix** idea from `assert_ghcr_login_class`, but **not its
    `head -1`** — that helper stops at the first match, and the assembly below requires a count.
    Select with `grep -F`, assert `wc -l` equals 1, then test fields on that single line.
1.2 **Parameterise** the existing `bwrap-fail)` case — do not add modes. The file states its own
    principle at `# Unified docker mock.` and the precedent is one mode over at
    `MOCK_ZOT_PULL_FAIL_STDERR`.

```bash
  bwrap-fail)
    if [[ "${1:-}" == "run" ]]; then echo "abc123"; fi
    if [[ "${1:-}" == "exec" ]]; then
      for arg in "$@"; do
        if [[ "$arg" == *"bwrap"* ]]; then
          # Unparameterised default is byte-identical to today, so the OTHER consumer of this
          # mode (assert_bwrap_canary_failure_rollback) is untouched. `${VAR-default}` uses NO
          # colon on purpose: an explicitly EMPTY value must mean "the probe is silent" — the
          # observed production signature — and `${VAR:-default}` would substitute the default.
          _e="${MOCK_BWRAP_FAIL_STDERR-bwrap: No permissions to create new namespace}"
          if [[ -n "$_e" ]]; then printf '%s\n' "$_e" >&2; fi
          exit "${MOCK_BWRAP_FAIL_RC:-1}"
        fi
      done
    fi
```

Four scenarios, zero new modes:
- **spoken**: both unset → `rc=1`, `err_chars>0`, non-empty `err`.
- **silent**: `MOCK_BWRAP_FAIL_RC=137 MOCK_BWRAP_FAIL_STDERR=` → `rc=137 err_chars=0 err="<empty>"`.
  137 sits outside bwrap's own rc space and docker's 126/127 band, so the fixture cannot be satisfied
  by accident.
- **purity**: `MOCK_BWRAP_FAIL_STDERR` carrying a raw CR, a non-ASCII byte, a `"`, a `dp.st.` token
  and a `SENTINEL_LEAK_CANARY`. This fixture pins redaction/control/quote behaviour — it does **not**
  also pin "exactly 200", because redaction precedes truncation and shrinks the string first, so a
  fixture with a redactable token lands below the clamp.
- **truncation**: a plain over-200 input with **no** redactable token → field length exactly 200.
- **pass-with-chatter**: `MOCK_BWRAP_FAIL_RC=0` with non-empty stderr → the probe succeeds and the
  text is still re-emitted (guards the success-path regression).

Parameterise `assert_canary_sandbox_failed_state` the same way — take the mock env as arguments and
call it per scenario, rather than growing one assert body to cover several signatures.

1.3 Write the Guard Contract assertions. Every fixture is synthesized, never a captured real error
    (`cq-test-fixtures-synthesized-only`). They must fail against the current `ci-deploy.sh`.
1.4 Record the RED output.

### Phase 2 — Capture, log line, delivery (GREEN)

```bash
      echo "Verifying bwrap sandbox..."
      BWRAP_RC=0
      BWRAP_ERR=""
      BWRAP_ERR_SAN=""
      BWRAP_T0=$SECONDS
      # `VAR="$(cmd)" || RC=$?` is the ONLY form that is both errexit-safe and rc-preserving.
      # A bare `VAR="$(cmd)"; RC=$?` aborts under `set -e` before RC is read (measured: the script
      # exits with the command's own code and the next line never runs). And `if ! VAR=$(cmd)` is
      # errexit-safe but `$?` inside the branch is the NEGATED status — measured 0 — so the field
      # would read rc=0 on every single failure.
      BWRAP_ERR="$(docker exec soleur-web-platform-canary bwrap --new-session --die-with-parent --dev /dev --unshare-pid --bind / / -- true 2>&1)" || BWRAP_RC=$?
      PROBE_SECS=$(( SECONDS - BWRAP_T0 ))
      # Safe under errexit only because `_cred_err_tail` terminates on a successful `printf`. That
      # is an invariant of ANOTHER function — its sibling `_doppler_get_observed` ends on a `[[ ]]`
      # test, which WOULD make this an abort vector — so the rescue is explicit rather than
      # inherited, and the mutation matrix drives it.
      BWRAP_ERR_SAN="$(_cred_err_tail "$BWRAP_ERR")" || BWRAP_ERR_SAN="<sanitize_failed>"
      # OUTSIDE the branch, deliberately. Before this change the merged `2>&1` stream reached stdout
      # on BOTH outcomes, so a probe that PASSES while writing a warning was visible — and that is
      # 97.6% of runs. Re-emitting only inside the failure arm would blind exactly the early signal
      # that would precede the next rollback. The SANITIZED value, never the raw one: this stdout
      # reaches journald under the `webhook` tag, which is ALSO on the Vector allowlist, so a raw
      # print would route the same bytes off-box around the redaction just applied. An `if` block,
      # NOT `[[ -n … ]] && printf …` — the latter's false branch returns 1 as the statement's status
      # and trips errexit.
      if [[ -n "$BWRAP_ERR_SAN" ]]; then printf '%s\n' "$BWRAP_ERR_SAN"; fi
      if [[ "$BWRAP_RC" -ne 0 ]]; then
        echo "Canary sandbox check failed, rolling back..."
        logger -t "$LOG_TAG" "DEPLOY_ROLLBACK: bwrap sandbox non-functional in $IMAGE:$TAG rc=$BWRAP_RC secs=$PROBE_SECS err_chars=${#BWRAP_ERR} err=\"${BWRAP_ERR_SAN:-<empty>}\""
        # DELIVERY, not just capture. The NON-blocking faithful canary already pages Sentry on a
        # FAIL via `sandbox_canary_sentry_event` ("loud, no-SSH page … never journald-only"). The
        # BLOCKING gate — the one that actually stops the founder shipping — did not.
        blocking_probe_sentry_event "$BWRAP_RC" "$PROBE_SECS" "$BWRAP_ERR_SAN" || true
        { docker stop soleur-web-platform-canary 2>/dev/null || true; }
        { docker rm soleur-web-platform-canary 2>/dev/null || true; }
        final_write_state 1 "canary_sandbox_failed"
        exit 1
      fi
      # Success-path twin, closed-vocabulary only. This is what makes the FIRST post-merge deploy
      # prove the field format end-to-end instead of proving only that the probe still passes, and
      # it accumulates the duration baseline that gives `secs=` meaning when a failure lands.
      logger -t "$LOG_TAG" "SANDBOX_PROBE_OK: rc=0 secs=$PROBE_SECS"
      echo "Sandbox OK"
```

Field vocabulary (`rc=`, `err_chars=`, `err="…"` last-on-line) is the house convention from
`_login_hatch` and `SOLEUR_DEPLOY_CRED_FAIL`; `${…:-<empty>}` is precedented at
`INNGEST_QUIESCE: is-enabled=${enabled_state:-<empty>}`, and `<`/`>` are literal inside a
double-quoted word. Free text last and double-quoted is the ADR-115 trusted-region convention.

`err_chars` counts **characters**, not bytes — `ci-deploy.sh` deliberately does not export `LC_ALL`,
so `${#VAR}` is locale-sensitive. That is why the field is named `_chars`, matching `_login_hatch`'s
`stderr_chars` / `stdout_chars` / `errno_chars`, and why the plan does not pair it with
`_cred_err_tail`'s 200 clamp as if the two were the same unit (the clamp runs under `LC_ALL=C` and
does bound bytes). It is taken **before** sanitization and carries the **truncation** property only.

**Do not touch:** the bwrap flags, `final_write_state 1 "canary_sandbox_failed"`, or
`run_faithful_sandbox_canary`. `rc` must not influence whether the rollback happens.

Then add one sentence to `_cred_err_tail`'s header recording the bwrap probe as its second producer
**and naming its 200-byte clamp**, without changing its body. Run the suite to GREEN.

### Phase 3 — Mutation-prove the guard

Execute every row of `## Guard Contract`, recording the observed result per row. Restore after each.

### Phase 4 — Correct #8016 (append-only)

`gh issue comment 8016 --body-file <file>`. The issue **body is not edited**.

### Phase 5 — File the follow-through tracker and the adjacent findings

Five filings. See `## Closing` and `## Adjacent findings`.

### Phase 6 — The Article 30 bracket

One additive dated bracket on PA-8 §(g). Contested by one reviewer; see `## Decision challenges`.

## Task 1 — the correction comment

**Must state:** (a) the contradiction reading was the operator's own and is **false**, plainly and
without blaming the reader; (b) the two canaries by content anchor — blocking, the block beginning
`echo "Verifying bwrap sandbox..."` whose failure arm calls `final_write_state 1 "canary_sandbox_failed"`;
non-blocking, `run_faithful_sandbox_canary`, invoked as `run_faithful_sandbox_canary || true`, whose
own comment says it "Records a verdict + pages on a faithful FAIL, but never gates/rolls back this
deploy" (#5875 / ADR-079); (c) **why `checked_at` is 31 minutes stale** — the mechanism, not the
fact: `sandbox_canary` is written by `write_sandbox_canary_state`, called only from the faithful
canary, which runs only **after** the blocking probe passes, so on this deploy it never ran; the
block is a standing cross-deploy record and `consecutive_pass: 435` is cumulative, making a
stale-but-passing verdict correct by construction; (d) the re-pointed defect, with the consecutive
`__SEQNUM` evidence from both occurrences; (e) the corrected rate, 2 in 83 (2.4%).

**Must NOT state** that the bwrap stderr is discarded because only `logger` lines reach journald.
That is false, and writing it would replace one wrong claim with another inside the artifact whose
purpose is correcting a wrong claim.

## Observability

Layer citation (`hr-observability-layer-citation`): this is the **container-readiness / deploy-gate
surface**, non-inspectable — the probe runs inside an ephemeral canary container and the host is not
reachable from a keyboard. Its layer is **journald tag `ci-deploy` → Vector (`host_scripts_journald`,
exact-value `SYSLOG_IDENTIFIER` allowlist, deliberately **no** PRIORITY filter) → Better Stack
Logs**, the carrier ADR-096 names as authoritative for a Sentry-dark host, **plus Sentry** for the
page. `observability-coverage-reviewer` applies.

```yaml
liveness_signal:
  what: "SANDBOX_PROBE_OK: rc=0 secs= on every passing deploy, and the DEPLOY_ROLLBACK line carrying rc= secs= err_chars= err= on every failing one"
  cadence: "once per release — 83 probe attempts in the 28 days to 2026-09-10"
  alert_target: "Sentry for the event a person receives; Better Stack Logs (source soleur-inngest-vector-prd) for the queryable record. Naming a log sink alone would be naming a destination, not an alert target."
  configured_in: "apps/web-platform/infra/vector.toml (host_scripts_journald includes ci-deploy); Sentry via the existing SENTRY_* env guard in ci-deploy.sh"
error_reporting:
  destination: "TWO planes. (1) journald tag ci-deploy -> Vector -> Better Stack, the queryable record. (2) Sentry, via blocking_probe_sentry_event modelled on the in-file sandbox_canary_sentry_event, tags {feature: agent-sandbox, op: blocking-sandbox-probe}, extra {rc, secs, err}."
  fail_loud: false
  rationale: "fail_loud refers to the EMITTER, not the audience: a telemetry failure must never abort a deploy, the contract both _login_hatch and sandbox_canary_sentry_event state. It is NOT a reason to leave the founder untold — plane 2 answers that. The gate's own verdict is still carried by final_write_state, untouched."
failure_modes:
  - mode: "bwrap could not set up the sandbox inside the canary"
    detection: "in-surface: rc=1 from the probe's own exec plus its message in err (every bwrap self-failure returns 1 — settled upstream)"
    alert_route: "Sentry event op=blocking-sandbox-probe; Better Stack on the literal `bwrap sandbox non-functional`, which also matches the two historical occurrences"
  - mode: "docker exec infra failure (container absent, not running, exec format)"
    detection: "in-surface: rc in 126/127, or rc=1 with docker's own text, or rc=128 on the moby exitUnknown fallback"
    alert_route: "same event and line; separated from the row above by the message"
  - mode: "the exec'd child was killed by a signal (OOM / SIGKILL)"
    detection: "in-surface: rc in the 128+n band with err_chars=0. Undetectable today: the kernel OOM channel is dark (kernel is in no Vector allowlist and system_journald cuts at PRIORITY 0-2), and ci-deploy's own oom_killed describes the container's main process, not an exec'd child."
    alert_route: "same event and line"
  - mode: "an immediate refusal is mistaken for a killed hung probe, or the reverse"
    detection: "in-surface: secs= on the same line. rc alone cannot separate a signal at 40ms from a signal at 30s, and that is exactly the H3-vs-H4 split."
    alert_route: "same event and line"
  - mode: "a verbose failure is truncated and read as complete"
    detection: "err_chars greater than the 200 clamp beside a 200-character err value"
    alert_route: "same line"
  - mode: "the probe starts warning on stderr while still passing — the early signal before a rollback"
    detection: "the guarded re-emit fires on the PASS path too, so the text reaches the webhook journald tag exactly as it did before this change"
    alert_route: "Better Stack, webhook tag"
logs:
  where: "Better Stack Logs (soleur-inngest-vector-prd), hot window plus s3 archive arm"
  retention: "archive rows resolve back to at least 2026-08-13 as measured this session (~28 days)"
discoverability_test:
  command: "bash scripts/followthroughs/bwrap-probe-selfreport-check.sh --dry-run"
  expected_output: "DRY-RUN OK: markers resolved, both byte-forms present, no live query attempted"
```

The honest position: **preflight Check 10 cannot execute the read that would actually prove this.**
It forbids shell substitution and admits only allowlisted first tokens, ruling out the `doppler run`
wrapper the ClickHouse credentials require. An earlier draft answered that with a `grep -c` over the
source file the same diff just edited — which cannot fail if Vector drops the tag, if
`apply-deploy-pipeline-fix.yml` never lands the change, or if the line never leaves the box. That is
not a discoverability test; it is a tautology wearing one's name. So the sandboxed probe is a
**dry-run of the follow-through script's marker resolution**, and the real live read is the
follow-through probe, which runs on a schedule under credentials the sweeper already holds — exactly
the shape Check 10 blocks inline. The transport leg is independently established: measured (83 rows
of this script's own journald output pulled this session) and drift-guarded by
`apps/web-platform/test/infra/vector-pii-scrub.test.sh`.

### Affected-surface observability (Phase 2.9.2)

Every `detection` names an **in-surface** signal — a field emitted from the probe's own exec, not a
host-side inference. The field set discriminates all four competing root-cause hypotheses in **one
event**: `rc` separates own-failure / infra / signal, `secs` separates a fast kill from a slow one,
and `err_chars` separates truncated from complete. A single boolean would not; neither would `err`
alone, which was the intake brief's proposal and which the measured evidence shows would have
rendered `<empty>` and named nothing.

## Guard Contract

### Guard 1 — the blocking probe's rollback event carries its own diagnostic and reaches a person

**Property.** Every rollback taken by the blocking bwrap probe emits exactly one `DEPLOY_ROLLBACK`
journald line carrying, on that same line, the probe's exit code, its wall-clock duration, its
pre-sanitization output length, and its sanitized output or the `<empty>` sentinel — and fires one
Sentry event carrying the same values. On the pass path the probe's output is still re-emitted.

**Assembly.** The chokepoint is the single `logger -t "$LOG_TAG" "DEPLOY_ROLLBACK: bwrap sandbox
non-functional …"` call site inside the `echo "Verifying bwrap sandbox..."` block, plus the
`blocking_probe_sentry_event` call beside it. A **second** `DEPLOY_ROLLBACK` emitter exists in the
same file (the canary-health rollback, `DEPLOY_ROLLBACK: canary failed for $IMAGE:$TAG (reason=…)`)
which this guard must **not** claim — which is why it selects on `bwrap sandbox non-functional`
rather than on `DEPLOY_ROLLBACK` alone, asserts the match count is exactly 1 (never `head -1`, which
would stop at the first and make the count assertion vacuous), and asserts every field on that line.

**Mutation matrix.** Six rows, not the eleven an earlier draft carried: two reviewers independently
observed that "delete the literal the assertion greps for, watch it redden" proves `grep` works, not
that the guard holds. What survives is the set where the mutation is something a future edit would
plausibly do for an unrelated reason.

| # | Mutation | Why it must red |
|---|---|---|
| 1 | Revert the capture to `if ! docker exec … ; then BWRAP_RC=$?` | `rc` reads **0** on a failure. This is the measured, nearly-shipped defect — both the intake brief and the CTO advisory prescribed it — and it is the reason this matrix exists. First on purpose. |
| 2 | Restore the bare `BWRAP_ERR="$(docker exec …)"` without `\|\| BWRAP_RC=$?` | The script aborts under `set -e`; the logger line, the Sentry event, the teardown and `final_write_state` never run, and the EXIT trap writes `reason=unhandled`. The suite must catch the **state-file** regression, not just a missing field. |
| 3 | Drop the `:-<empty>` sentinel, under the silent scenario | Renders `err=""`. The distinction the issue asked for is gone. |
| 4 | Replace `_cred_err_tail "$BWRAP_ERR"` with the raw `$BWRAP_ERR`, under the purity scenario | `SENTINEL_LEAK_CANARY` and the raw CR reach the logger line **and** stdout; purity must red on both sinks. |
| 5 | Move the guarded `printf` from before the branch to inside the failure arm | A probe that PASSES while writing to stderr is silently swallowed — 97.6% of runs, and the early signal that would precede the next rollback. A delete-only battery cannot see this; only the pass-with-chatter scenario can. |
| 6 | Make `_cred_err_tail` return non-zero on its last statement | The rescue `\|\| BWRAP_ERR_SAN="<sanitize_failed>"` must be what keeps the script alive. Without it the abort vector is real and inherited from another function's internals. |

**Harness rows.**

| # | Row | Expected |
|---|---|---|
| H1 | Mutate the SUITE, not the script: delete the field anchors from the assertion so it asserts only that a line exists | A meta-check must RED. Without it a vacuous assertion passes forever. |
| H2 | **Must-PASS, non-canonical:** the purity scenario emits a message nothing like the canonical `bwrap: No permissions to create new namespace` — multi-line, non-ASCII, over 200 chars | Must **PASS**. The contract permits any message; the assertion anchors on the field's *structure*, never on the one canonical string. |
| H3 | **Must-PASS, non-canonical:** the silent scenario at rc=137, zero bytes | Must **PASS** with `rc=137 err_chars=0 err="<empty>"`. |
| H4 | Assert `MOCK_LOGGER_CAPTURE_FILE` is unset after the scenario, and that two consecutive full-suite runs produce byte-identical output | Catches a hoisted export contaminating the four later scenarios that depend on the same variable. |

**Anchor discipline** (`cq-assert-anchor-not-bare-token`): every assertion selects the single line
containing `DEPLOY_ROLLBACK: bwrap sandbox non-functional` and then tests fields **on that selected
line**. A bare `grep -q err_chars` over the whole capture would pass on any line anywhere.

## Acceptance Criteria

### Pre-merge

Sixteen, down from an earlier draft's twenty-eight, and every one rewritten to be **executable**.
The previous set failed its own bar: one criterion was unsatisfiable against the plan's own code, two
had no runnable form, and one used the exact `grep -c` idiom the repo keeps a linter for.

- **AC1** — The bwrap argv is unchanged. Not a diff grep — the Phase 2 rewrite touches that very
  line, so both the `-` and `+` sides contain `--unshare-pid` and a diff grep returns 2, making the
  criterion unsatisfiable against the implementation it gates. Assert the **property**:

  ```bash
  _argv() { git show "$1:apps/web-platform/infra/ci-deploy.sh" \
            | grep -o 'bwrap --new-session[^)]*-- true'; }
  [[ "$(_argv origin/main)" == "$(_argv :)" ]]
  ```

- **AC2** — Every capture line carries the rc rescue:

  ```bash
  ! grep -n 'BWRAP_ERR="\$(docker exec' apps/web-platform/infra/ci-deploy.sh \
    | grep -qv '|| BWRAP_RC=\$?'
  ```

- **AC3** — Field presence, order, quoting and free-text-last, asserted on the **emitted** line where
  the quotes are real, not on the source where they are backslash-escaped:

  ```bash
  line="$(grep -F 'DEPLOY_ROLLBACK: bwrap sandbox non-functional' "$MOCK_LOGGER_CAPTURE_FILE")"
  [[ "$(printf '%s\n' "$line" | wc -l)" == "1" ]]
  printf '%s' "$line" | grep -qE 'rc=[0-9]+ secs=[0-9]+ err_chars=[0-9]+ err="[^"]*"$'
  ```

  One anchored regex verifies all four properties at once, including the ADR-115 trusted region.
- **AC4** — `BWRAP_ERR_SAN` is assigned with an errexit rescue (`|| BWRAP_ERR_SAN="<sanitize_failed>"`).
- **AC5** — Sanitization routes through `_cred_err_tail "$BWRAP_ERR"`, and **`ci-deploy.sh` alone**
  (not the diff, which legitimately adds test-side line selection) introduces no new
  `tr -dc`/`cut -c`/`head -1` sanitizer.
- **AC6** — The deploy-state contract is frozen: no change to `final_write_state 1 "canary_sandbox_failed"`.
- **AC7** — Purity, on **both** sinks. Under the purity scenario the full `$MOCK_LOGGER_CAPTURE_FILE`
  **and** the captured `$output` contain neither `SENTINEL_LEAK_CANARY`, nor a raw CR, nor an
  unredacted `dp.st.` token. Two sinks because the guarded `printf` writes to stdout, which this
  plan's own measurements show also reaches Better Stack.
- **AC8** — Silent path: `rc=137`, `err_chars=0`, `err="<empty>"`. The observed production signature,
  untested today.
- **AC9** — Spoken path: `rc=1`, `err_chars` greater than 0, non-empty `err="…"`, anchored on
  structure and never on the canonical fixture string.
- **AC10** — Truncation: an over-200 input with **no** redactable token yields a field of exactly 200,
  and `err_chars` reports the pre-sanitization length. Separate fixture from AC7's, because redaction
  precedes truncation and shrinks a token-bearing input below the clamp.
- **AC11** — Pass path: with `MOCK_BWRAP_FAIL_RC=0` and non-empty stderr, the probe succeeds **and**
  the sanitized text is still re-emitted to `$output`. This is the 97.6% branch.
- **AC12** — The gate is still asserted, not replaced: `reason` equals `canary_sandbox_failed`,
  `exit_code` equals `1`, and the canary `docker stop`/`docker rm` ran.
- **AC13** — The success-path twin exists: exactly one `SANDBOX_PROBE_OK: rc=0 secs=` logger line
  carrying **no** free-text field, asserted by a green-path scenario. Count via
  `n="$(grep -c 'SANDBOX_PROBE_OK' apps/web-platform/infra/ci-deploy.sh || true)"; [[ "$n" == "1" ]]`
  — the `|| true` is load-bearing, because `grep -c` prints `0` **and exits 1** on no match, which is
  the exact class `scripts/lint-shell-capture-exit.py` exists to prevent.
- **AC14** — `blocking_probe_sentry_event` exists, is env-guarded on the same three `SENTRY_*`
  variables as `sandbox_canary_sentry_event`, is invoked with `|| true`, and carries `rc`, `secs` and
  `err`. A scenario asserts the POST is attempted when the DSN components are present and is inert
  when they are absent — mirroring the existing `#7103 R1` assertions for that sibling.
- **AC15** — Every mutation row 1-6 and harness row H1 observed RED; H2, H3 and H4 observed PASS.
  Results recorded in the PR body. `bash apps/web-platform/infra/ci-deploy.test.sh` exits 0 with a
  total strictly greater than the 216 baseline and `0 failed`.
- **AC16** — `_cred_err_tail`'s header records its second producer **and its 200-byte clamp** in one
  sentence naming the bwrap probe call site. The clamp matters at the new site: a reader seeing
  `err_chars=340` beside a 200-character field has no local explanation otherwise. This is the GDPR
  gate's Art. 32 remediation — the only control that makes a future Doppler-scoped tightening of the
  helper a visible decision rather than an invisible regression.
- **AC17** — The #8016 comment exists; the issue **body is unedited**, verified against the SHA-256
  recorded in `## Research Insights`
  (`gh issue view 8016 --json body -q .body | sha256sum` equals `c3aea158b8443b13ad7aad0284c5a98add3369dbd694564cd44f67e7697a75b4`);
  and the comment does not assert that the probe's stderr is discarded because only `logger` lines
  reach journald.

**Deliberately not an AC.** A previous draft carried five sub-assertions re-pinning
`_cred_err_tail`'s internals. Those are already pinned, with a positive control, by `T-7095-3`
(anchor `# T-7095-3 — the err tail's THREE bounds`) and `F14` (anchor
`# --- #7095 R3 (F14): redaction MUST precede truncation`), and this PR does not modify the helper's
body. AC5 plus AC7 is the whole obligation at this call site.

### Post-merge (fully automated — no separate apply step)

- **AC18** — `apply-deploy-pipeline-fix.yml` auto-applies on merge because `ci-deploy.sh` is a
  `terraform_data.deploy_pipeline_fix` trigger file. `/ship` Phase 5.5 surfacing this is expected.
- **AC19** — The first post-merge release is triaged by the table below, and the follow-through
  probe's window starts at the merge date so no step depends on memory.
- **AC20** — Within 24h of that release, a field-isolated Better Stack read returns at least one
  `SANDBOX_PROBE_OK` row carrying `rc=0 secs=`. This is what the success-path twin exists for. An
  earlier draft grepped `Verifying bwrap sandbox`, which rides the `webhook` tag and is emitted
  **identically by the pre-change script** — a positive control that passes whether or not the change
  deployed, which is the #7220 failure verbatim.

## Closing #8016, and the follow-through that actually closes it

**The contradiction this section used to carry.** `closes: 8016` while the arms say "wait ~2 weeks,
then close". Both cannot be true: if the PR closes #8016 at merge, both arms are dead — the sweeper
skips non-OPEN issues and nobody is watching. Resolved by splitting the tracker.

- **`Closes #8016`** covers the **instrumentation**, verifiable at merge.
- **A new `follow-through`-labelled tracker** covers the **diagnosis**, referenced from the PR body
  as **`Ref #<N>`**.

`Ref` is load-bearing. `/ship` Phase 5.5's Soak-Gated Follow-Through Enrollment Gate extracts
`(Ref|Tracks) #<n>` and **deliberately excludes `Closes`/`Fixes`** (the #7278 / PR #7343 carve-out).
This plan sat exactly in that blind spot — the soak tracker and the closes target were the same issue
— so the gate would have passed silently on an unenrolled soak.

### Follow-through enrollment (Phase 2.9.1)

- **Script:** `scripts/followthroughs/bwrap-probe-selfreport-<N>.sh`, modelled on
  `scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh`.
- **Directive** in the tracker body:
  `<!-- soleur:followthrough script=scripts/followthroughs/bwrap-probe-selfreport-<N>.sh earliest=<merge-date>T00:00:00Z secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->`
- **No workflow change** — all three secrets are already wired in
  `.github/workflows/scheduled-followthrough-sweeper.yml`.
- **Exit semantics — NOTIFY-ONLY, never auto-close.** **2 = NOT YET**, **5 = ACTION REQUIRED** (a
  rollback line was found; post it), **3 = CANNOT ESTABLISH** (query/auth failure, or zero
  `ci-deploy` liveness in the window). **Never 0, never 1**, with the sibling `.test.sh` asserting
  that invariant. Adjacent finding 4 is why this matters: a sweeper that can auto-close on a PASS
  certifying the *soak* rather than the *promotion* is how ADR-079's Deferral A went orphaned for two
  months.
- The window starts at the merge date, so the probe **also covers the first-post-merge-deploy watch**.

### The two arms

**Arm 1 — the next occurrence names a cause. Primary.** At roughly 3 releases/day and 2.4%, expected
within about two weeks. `rc=1` with a message → H1, and the message names which; `rc` in 126/127 or
`rc=128` → H2; `rc` in the `128+n` band → H3, and `secs=` then splits an immediate refusal from a
killed hung probe. The kernel OOM channel must be opened before a signal verdict can be confirmed —
adjacent finding 3.

**Arm 2 — soak. Weak; do not lead with it.** At p=2.4%, 95% confidence that the true rate is below
2.4% needs on the order of 120 clean probe attempts — roughly 40 days at the observed cadence.

### Querying without contaminating the answer

Every Better Stack read **must** field-isolate on the journald identifier. A bare payload substring is
self-contaminating: inngest ships GitHub-webhook rows into the same Better Stack source and those
rows embed issue and PR bodies verbatim, so a marker this PR writes into the #8016 comment, the PR
body, this plan and `tasks.md` comes back as "hits" that are not deploys. **Observed in this very
session:** a `--grep 'bwrap'` pull returned the webhook payload of PR #8026, whose title contains this
branch name. `ci-deploy-sentry-post-fail-6475.sh` carries both byte-forms:

- server-side (`raw LIKE` against the unescaped column): `SYSLOG_IDENTIFIER":"ci-deploy`
- client-side (over JSONEachRow stdout, inner quotes backslash-escaped):
  `SYSLOG_IDENTIFIER\":\"ci-deploy\"`

AND both, then `grep -F 'bwrap sandbox non-functional'` — chosen because it matches the two
**historical** occurrences as well as every future one. Run this live at `/work`, not post-merge.

### Triage table for the first post-merge release

Mechanical and three-way, derived from the plan's own blast analysis rather than from "somebody
watches". Goes in the PR body as well as here.

| Observed | Verdict |
|---|---|
| `reason=unhandled` | **This change broke it.** An errexit abort skipped the handler. Revert first, investigate second. |
| `reason=canary_sandbox_failed` **with** `rc=`/`secs=`/`err=` on the line | Genuine, and now diagnosable. Read the fields. |
| `reason=canary_sandbox_failed` **without** those fields | The change did not reach the host. Check `apply-deploy-pipeline-fix.yml`. |

## Adjacent findings — file separately, do not bundle

A discovered defect in a different subsystem stays its own issue.

1. **`docker login ghcr.io` fails and the classifier discards the evidence.** Verbatim, 2026-09-09
   22:31:07 and 22:31:08, tag `ci-deploy`:
   `PRELUDE: docker login ghcr.io FAILED with baked/first creds class=unclassified rc=1 stderr_chars=70 errno_chars=7 stdout_chars=0 kw= tok=Error docker_ver=29.3.0 (registry=ghcr)`
   and `PRELUDE: docker login ghcr.io STILL FAILED after Doppler re-fetch (stage=relogin_failed) — private pull may fail-closed`.
   Note `stderr_chars=70` with `class=unclassified` and `kw=` empty: 70 bytes of stderr existed, were
   counted, and were not logged — the same self-report defect as the bwrap probe, one layer up.
   Survived only because the zot mirror took over. Related to open **#6560**.
2. **`IMAGE_VERIFY_FAIL: result=cosign_absent … mode=warn`**, 2026-09-09 22:31:49, 417 chars, tail
   `detail=Unable to find image 'ghcr.io/sigstore/cosign/cosign@sha256:57c0e93a…' locally docker:
   Error response from daemon: error from registry: denied`. Signature verification failing in warn
   mode, so unsigned images ship without blocking. Root cause is the same ghcr.io auth failure as
   finding 1, but the warn-mode pass-through is its own decision.
3. **The Vector journald allowlist does not match its own documentation, in two places.**
   (a) `vector.toml` claims the canary container is excluded from `app_container_journald` "as an
   implicit consequence of exact-value matching", pinned by a fixture. Measured: 4 rows with
   `CONTAINER_NAME=soleur-web-platform-canary` reached Better Stack in a 25-second window on
   2026-09-09. (b) Source 4's comment claims Source 2 catches "Kernel oops, OOM-killer, networking
   drops"; Source 2 cuts at `PRIORITY 0-2` and the standard `Out of memory: Killed process …` line is
   emitted at `err`/`warning`, so it is dropped — and `kernel` is in no identifier allowlist either.
   Two independent blocks. Consequence: **H3 is untestable**. Consolidate (a) and (b) into one tracker.
4. **ADR-079's Deferral A is orphaned, and this is the most load-bearing of the four.** `#5889`
   ("Soak: promote faithful sandbox canary dark→blocking") is **CLOSED / COMPLETED, 2026-07-06**, and
   its closing sweeper comment reads *"PASS: 52 consecutive green canary verdicts over 3d … canary
   proven; promote to blocking in PR3."* The promotion was never made — `ci-deploy.sh` still reads
   `run_faithful_sandbox_canary || true`. There is no open successor tracker, and **ADR-079 line 509
   still says "Status stays `adopting` (Deferral A / #5889 still open)"**, which is false and is what
   misled an earlier draft of this plan into citing a closed soak as a live gate. This matters more
   than findings 1 and 2 because the faithful canary is the thing that would have named the cause of
   both blocked releases had it been promoted when its own soak said to. It is also a live instance
   of this plan's own cited learning: a sweeper auto-closed on a PASS that certified the soak, not
   the promotion.

**Net-issue-flow.** This PR closes 1 and files **5** — the four above plus the `follow-through`
diagnosis tracker — so it is net **+4**. Use `<!-- gate-override: net-issue-flow -->` in the PR body
with one justification line per filing; "a discovered defect in another subsystem that must stay its
own issue" is an explicitly-blessed reason in
`plugins/soleur/skills/ship/scripts/net-issue-flow.sh`. Findings 3 and 4 carry additional
justifications: 3 is why H3 is untestable, and 4 is a correction to an ADR that actively misleads
readers today. The follow-through tracker is mandated by the follow-through convention, because the
diagnosis is wall-clock gated and `Closes` alone would strand it.

## Decision challenges

Surfaced rather than decided, per ADR-084. Mirrored to
`knowledge-base/project/specs/feat-one-shot-8016-bwrap-probe-self-report/decision-challenges.md` so
`/ship` renders them into the PR body.

1. **The Article 30 bracket (Phase 6).** Two reviewers split. DHH: the plan promotes a
   `Suggestion` into a hard pre-merge gate while declaring it is not promoting, and the substance is
   thin because the channel already carries `docker logs … --tail 30` **unsanitized**, making this a
   strict *reduction* in unsanitized bytes per byte. Kieran: justified and not creep — PA-8 §(g)
   already carries three dated brackets so the plan follows an established additive contract; the
   three deferral costs it cites (#6474, #7455, #7500) are all real, all closed, and all are literally
   currency-correction work caused by a register lagging the code; and one paragraph appended to a
   file already in the neighbourhood is cheaper than an issue plus a triage plus a future PR. The
   plan currently **retains** the bracket on Kieran's reasoning. Cutting it removes one file from the
   diff and one filing justification.
2. **Plan length.** Two reviewers argued the gate-mandated sections (Encryption Posture,
   Infrastructure IaC, Architecture Decision, Domain Review) are ceremony that will not change what
   ships. They are retained because `deepen-plan` halts on their absence, but compressed. If the
   operator wants them gone, the gates are what to change, not this plan.

## Architecture Decision (ADR/C4)

**No ADR required for this change.** ADR-079's exit-code classification clause is scoped entirely to
the non-blocking faithful canary; recording `rc` while leaving the rollback branch behaviourally
identical stays inside it. No ADR governs the `DEPLOY_ROLLBACK` line format — zero hits across the
decisions directory; the only provenance is an archived pre-ADR spec's FR-A5, which explicitly
anticipated "health check failure details" on that line. Next free ordinal is **ADR-216** (highest
claimed across all `refs/remotes/origin/*` is ADR-215; highest on `origin/main` is ADR-213), recorded
only so a plan-review reversal need not re-derive it.

**ADR-079 line 509 is factually wrong and is corrected by adjacent finding 4, not by this plan.** The
correction belongs with the orphaned-promotion tracker, where the decision about whether to finally
promote the faithful canary can be made on its own evidence rather than folded into a diagnostics PR.

**No C4 impact.** All three of `model.c4`, `views.c4` and `spec.c4` read in full. External human
actors: `founder` (modelled) and `publicReader` (modelled but not reached — `DEPLOY_ROLLBACK` has no
consumer, so the `github → publicReader` edge is not engaged). External systems: `betterstack` and
`sentry`, both modelled, and the `hetzner → sentry` edge already enumerates "ci-deploy.sh's
deploy/sandbox-canary/cosign-verify/zot-fallback events" — the new event joins that existing
enumeration rather than creating an edge. Containers/data stores: `hetzner` (modelled; the canary is
ephemeral and below the model's altitude); no data store written. Access relationships: none change.
No element description is falsified — the `hetzner → betterstack` edge's claim that the app
container's pino stream is "the HIGHEST-SENSITIVITY payload on this edge" still holds, since bwrap
stderr is host-local sandbox error text carrying no user identifiers. Count parity
(`plugins/soleur/test/c4-count-parity.test.sh`) is green pre-change at 10/10, and all seven gated
cardinalities live on `github → sentry` and `github → resend` edges this diff does not touch.

## Encryption Posture

Skipped by the Phase 2.11 detection: no persistent store is introduced (no `.tf`, no migration, no
cloud-init, no compose file) and no new cross-component connection is created. The journald → Vector
→ Better Stack path and the Sentry POST path both already exist and already carry this script's
output; only the payload of existing lines changes.

## Domain Review

**Domains relevant:** engineering, product.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Complexity small (hours), no prerequisites, tech debt slightly reduced. Scope-lock
holds. Findings folded in: the `set -e` hazard is the highest risk in the diff and would delete the
diagnostic the PR already has; `<empty>` alone is an insufficient discriminator; the existing
`bwrap-fail` mock would never exercise the observed production signature. **Both of the advisory's
own load-bearing claims were falsified** — its prescribed capture form was measured to yield `rc=0`,
and its bwrap exit-code claim was falsified against upstream source across all 717 commits. Its
*conclusion* — keep classification out of this PR — survives on the #4932 ground alone.

### Product (CPO)

**Status:** reviewed
**Assessment:** `single-user incident` confirmed — not an outage (prod keeps serving; the cutover is
downstream) and not lower (shipping is the founder's core loop, and a founder with no route to the
host has zero recourse). Current-state risk dominates decisively: a recurring un-diagnosable block
with no recourse is worse than a one-time loud failure with an obvious revert, and gating harder buys
nothing because the change is validated only by the first post-merge deploy regardless. Verdict
**APPROVE WITH CONDITIONS**; all four folded into the acceptance criteria.

### Product/UX Gate

Not applicable. The mechanical UI-surface scan over `## Files to Edit` and `## Files to Create`
matches no UI-surface path. Tier: NONE. `wg-ui-feature-requires-pen-wireframe` does not fire.
**Brainstorm-recommended specialists:** none. **Skipped specialists:** none.

### GDPR / Compliance Gate

*Advisory only. Not legal review; findings are heuristic.*

Invoked under Phase 2.7 trigger (b) — the `single-user incident` threshold — even though the
canonical path regex misses. Under the gate's own taxonomy **zero mandatory checks fire**. Two
findings at **Suggestion**, deliberately not promoted.

**Producer corpus — the recorded negative, not an inherited assumption.** Exactly three producers can
write to the captured stream, and none has a channel to end-user personal data. **Docker
client/daemon**: `Error response from daemon: Container <id> is not running` / `No such container`;
`docker exec` does not re-serialise the target's environment, and the `ENV_FILE` was consumed by the
daemon at `docker run` time. **runc**: `OCI runtime exec failed: …` or an AppArmor/seccomp denial
naming `soleur-bwrap`; it echoes the argv it was handed, which is fixed and literal here, plus host
paths and numeric uid/gid. **bwrap**: `bwrap: Creating new namespace failed: Operation not permitted`
and similar; it fails **before** executing its payload, and the payload is `true`, which produces no
output on any path. No request context, no database read, no HTTP header, no session, and the canary
has never served a request. Operator/infrastructure diagnostic data, not personal data — so PA-8 §(c)
does not change.

**Finding 1 — `GDPR-Art-5(2)`, Suggestion.** Payload class on an existing channel changes from
author-fixed strings to captured subprocess output; PA-8 has recorded this shape twice (#7440,
#7500). Remedy: one additive dated bracket on PA-8 **§(g) TOMs** — not §(c), §(d) or §(e). Its
recipient cite (Better Stack source 2457081, tag `ci-deploy`) matches what §(d) already records.
Contested — see `## Decision challenges`.

**Finding 2 — `GDPR-Art-32`, Suggestion.** `_cred_err_tail`'s header scopes it to one producer and
its only value-shaped rule is `dp\.[a-z]{2,}\.`-anchored. The register has already reasoned in
writing (#7440) that "the failure mode of a name-anchored denylist is silent leakage". The zot remedy
there was an allowlist over a structured header object; that construction is **not available** here
(unstructured free text, no key set), so the plan does not require an unimplementable control. The
available remedy is making the mismatch visible — **AC16**.

**Not required:** no `compliance-posture.md` row, no `docs/legal/**` lockstep, no DPIA, no breach
row, no Vendor DPA row, no Art. 13 update. Chapter V is not engaged (Better Stack s.r.o. is
CZ-established; PA-8 §(e) records the transfer as intra-EU). **Pre-existing and stated for the
record:** PA-8 records the Better Stack Art. 28(3) processor instrument as NOT EXECUTED (#7717
correction, tracked at **#7529**). Not a reason to block, but a plan that increases what flows down
that pipe should not do so silently. **Gate staleness:** `POSTURE_FAIL: >90d stale rules — 123 days
since last-verified`; advisory, exit 0, refresh tracked at #7255.

## Infrastructure (IaC)

**No new infrastructure.** The Phase 2.8 detection scan was run over the plan body and the change and
returned no hit in any category: no remote-shell invocation, no unit-management command, no
secret-write command, no vendor-console step, no import of a resource that should have been declared.
No new resource, secret, vendor or persistent runtime process. `ci-deploy.sh` is an existing
`terraform_data.deploy_pipeline_fix` trigger file whose delivery to the host is already automated
end-to-end by `apply-deploy-pipeline-fix.yml` on merge, so this plan adds no apply path and requires
none.

## Sharp Edges

- **`$?` after `if ! cmd` is the NEGATED status, not the command's.** Measured: `A_RC=0` when the
  probe returned 125. Both the intake brief and the CTO advisory prescribed a variant of this form; a
  plan that shipped it would have logged `rc=0` on every failure and looked green doing it. The
  measurement was 20 lines and took under a minute. Any plan turning on shell exit-code semantics
  must run the experiment rather than reason about it.
- **A bare `VAR="$(cmd)"` under `set -e` aborts the script**, and the assignment's status IS the
  substitution's status. Measured `SCRIPT_EXIT=125`, with the following `RC=$?` never reached. Here
  that would skip the logger line, the Sentry event, the teardown and `final_write_state`, leaving
  `reason=unhandled` — strictly less diagnostic than doing nothing. `run_faithful_sandbox_canary`
  uses this pattern safely **only** because it is invoked as `… || true`, which suspends errexit for
  the whole function body. Do not copy it by analogy into a site with no such context.
- **Three artifacts a reader would ordinarily trust were each wrong here.** The issue's headline
  claim, a domain-agent advisory's load-bearing fact, and an ADR's status line. The ADR one is the
  most dangerous: ADR-079 still says "#5889 still open" and it has been closed since 2026-07-06, so a
  plan that inherits status from an ADR rather than from `gh` builds on a two-month-stale premise.
  `hr-before-asserting-github-issue-status` exists for exactly this and it earned its keep.
- **Consecutive `__SEQNUM` separates "discarded" from "never produced".** Ordering a journald burst by
  `dt` cannot: webhook flushes buffered stdout in batches, so many lines share a near-identical
  timestamp and `sort` orders them arbitrarily. Two adjacent seqnums with nothing between them is a
  proof of absence; two adjacent timestamps is not.
- **A bare payload grep against Better Stack is self-contaminating.** inngest ships GitHub-webhook
  rows into the same source, embedding issue and PR bodies verbatim — so any marker this PR writes
  into an issue comment or PR body comes back as a "hit". Observed here: `--grep 'bwrap'` returned
  PR #8026's webhook payload. Field-isolate on `SYSLOG_IDENTIFIER` in **both** byte-forms.
- **A positive control must be impossible for the OLD artifact.** An earlier AC grepped
  `Verifying bwrap sandbox`, which the pre-change script emits identically and which rides a
  different journald tag — it would have passed whether or not the change deployed.
- **An AC that gates an implementation must be satisfiable by it.** An earlier AC1 required a diff
  grep for `--unshare-pid` to return 0, while Phase 2 rewrites that exact line — so both diff sides
  carry the token and the grep returns 2. The invariant wanted was *the argv is unchanged*, which is
  an equality check between two `git show` extractions, not a diff-shaped proxy.
- **`grep -c` prints `0` and exits 1 on no match** — in a `set -e` step that kills the step at the
  moment the criterion passes. This is the repo's own documented scar; `scripts/lint-shell-capture-exit.py`
  opens by naming it. Every count AC uses `|| true` plus a string compare.
- **`${#VAR}` counts characters, not bytes, under a UTF-8 locale**, and `ci-deploy.sh` deliberately
  does not export `LC_ALL`. `_login_hatch` documents this and names its fields `_chars`; an earlier
  draft named the field `_bytes` and asserted the thing the file explicitly declines to assert — and
  paired it with `_cred_err_tail`'s clamp, which runs under `LC_ALL=C` and is a genuine byte bound.
- **A failure rate quoted from remembered runs is usually wrong by an order of magnitude.** 2-in-6
  (33%) versus 2-in-83 (2.4%) is the difference between "soak a week" and "soak 40 days".
- **A guard's mock must exercise the OBSERVED signature, not a plausible one.** The existing
  `bwrap-fail` mock emits text and exits 1; production emitted nothing, twice.
- **Capture removes the channel the bytes used to travel on — including on the SUCCESS path.** The
  reflexive fix re-emits inside the failure arm, which silently swallows a warning from a *passing*
  probe — 97.6% of runs, and precisely the early signal that would precede the next rollback. The
  re-emit must sit outside the branch and carry the sanitized value, because the stdout it writes to
  is itself an allowlisted journald tag.
- **A cited helper's convenience (`head -1`) can defeat the assertion that cites it.** The
  line-selection precedent stops at the first match, which makes a "there is exactly one" assertion
  vacuous. Select, count, then test fields on the single line.
- **Redaction precedes truncation, so a fixture cannot pin both at once.** A token-bearing input
  shrinks below the 200 clamp during redaction, so "exactly 200" needs its own fixture with no
  redactable token.
- **`${_e: -200}` does not clamp** — bash yields the EMPTY string for a negative offset larger than
  the string. `_cred_err_tail` documents this and uses an explicit length test.
- **A plan whose `## User-Brand Impact` is empty or omits the threshold fails `deepen-plan` Phase 4.6.**
- **`/ship` Phase 3.7 WILL fire** because the diff touches `ci-deploy.sh`, and Phase 5.5 will surface
  the `deploy_pipeline_fix` auto-apply. Both correct and expected: a deploy-gate change cannot be
  validated by any deploy except the first post-merge one.
