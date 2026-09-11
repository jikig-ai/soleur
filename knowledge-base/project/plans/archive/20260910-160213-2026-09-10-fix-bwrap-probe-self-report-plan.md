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

## Enhancement Summary

**Deepened on:** 2026-09-10 · **Halt gates:** 4.6 / 4.7 / 4.8 / 4.10 / 4.11 pass, 4.9 skipped (no UI
surface) · **Reviewers:** DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer,
observability-coverage, security-sentinel, test-design, CTO, CPO, GDPR gate, C4/ADR gate, plus a
scoped strong-model consult and a mechanical verify-the-negative sweep.

### What review changed, in order of severity

1. **The capture form was wrong twice, and both wrong forms were prescribed to me.** `$?` after
   `if ! cmd` is the *negated* status (measured `A_RC=0`), and a bare assignment aborts under
   `set -e` (measured `SCRIPT_EXIT=125`). Only `VAR="$(…)" || RC=$?` is both safe and rc-preserving.
2. **The sanitizer was fail-open at the new call site.** `VAR="$(f)" || rescue` suspends errexit for
   the whole function body, so a mid-pipeline `sed` death emits a *partially sanitized* value and
   returns 0 — the rescue never fires. This plan's own Sharp Edges stated the mechanism three
   sections earlier and an earlier draft applied it to a different function.
3. **The producer corpus was not a closed negative.** `--env-file` secrets live in `Config.Env` and
   are re-injected into **every** `docker exec`, and runc formats offending env entries into its
   errors. The sanitizer is therefore the load-bearing control, not belt-and-braces — which reopened
   a scope-lock and added four shape-anchored redaction rules.
4. **The change created a third sink and guarded two.** The Sentry POST bypasses Vector's scrubbers
   entirely. Closed vocabulary now crosses it; purity is asserted on all three sinks.
5. **The field set did not discriminate what the plan claimed.** At `rc=1` with an empty message —
   the observed signature — H1 and H2 tied. `cstate`, captured *before* teardown, breaks it.
6. **`$SECONDS` could not express the distinction it was added for.** The whole H3-vs-H4 window is
   sub-second; switched to `date +%s%3N`.
7. **The delivery leg was missing entirely.** The non-blocking canary pages Sentry; the blocking gate
   — the one that stops the founder shipping — did not.
8. **`closes: 8016` contradicted the closure arms**, and `/ship`'s soak gate would have passed
   silently because it excludes `Closes` targets by design. Split into `Closes` + a `Ref`-linked
   follow-through tracker.
9. **Two acceptance criteria could not be satisfied by the implementation they gated**, one used the
   `grep -c` idiom the repo keeps a linter for, and two had no runnable form. Rewritten as executable.
10. **A harness row was written from reasoning and measured false.** "Two consecutive suite runs
    produce byte-identical output" fails on the *untouched* tree — `ci-deploy.test.sh:3558` crosses a
    `date +%s` boundary — so the row would have redded at baseline and been read as a catch. Deleted
    and replaced; every harness row is now calibrated against the pristine tree first.
11. **`ms` was decorative and `err_chars`'s provenance was undefended.** Every mock fixture returned
    instantly, so the sole P2e discriminator had one value across the whole set and a hardcoded
    `ms=0` would have passed the suite. Added a duration fixture (bounded, never exact) and three
    mutation rows covering the two axes the battery never touched — extractor uniqueness and field
    order — both guarding assertions this plan argued for at length and then never proved.

### Premises falsified at plan time

Seven, from three artifacts a reader would ordinarily trust: the issue's headline claim, a
domain-agent advisory's load-bearing fact (bwrap's exit codes — falsified against upstream across all
717 commits), and **an ADR's status line** (ADR-079 still says `#5889` is open; it closed
2026-07-06 with a promote verdict that was never acted on). That last one became adjacent finding 4.

### Verification performed

15/15 negative claims confirmed against implementation files, zero contradictions · all 6 rule IDs
active · all 20 issue/PR citations resolved live, one cross-repo ambiguity caught and qualified · all
knowledge-base and script paths resolve · `origin/main` re-fetched (advanced 2 commits, none touching
the target files) · suite baseline 216/216 · c4-count-parity 10/10 · guard-contract lint green.

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
- **P2e** — A reader can tell an immediate refusal from a killed hung probe. `rc` alone cannot: a
  signal at 40 ms and a signal at 30 s carry the same code and the same empty output. Measured in
  **milliseconds**, not seconds — the whole evidentiary window is sub-second (the 2026-09-09 canary
  had 2.852 s of total life), so integer seconds would collapse the distinction the field exists for.
- **P2h** — When `rc=1` comes back with an empty message, a reader can still separate bwrap's own
  failure from docker's "no such container"/"not running", which share that code. The message is
  what normally separates them and the message is empty on the observed signature, so the canary
  container's state at probe time is the discriminator.
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

### Verify-the-negative sweep (deepen-plan Phase 4.45)

Every negative and absolute claim in this plan was grepped against the implementation file it names.
**15 of 15 CONFIRMS, zero CONTRADICTS.** The load-bearing ones, with their citations:

| Claim | Verdict | Evidence |
|---|---|---|
| The bwrap argv occurs exactly once | CONFIRMS | `ci-deploy.sh:2948`, `grep -c` = 1 |
| `final_write_state 1 "canary_sandbox_failed"` occurs exactly once | CONFIRMS | `ci-deploy.sh:2954`, `grep -c` = 1 |
| A **second** `DEPLOY_ROLLBACK` emitter exists (so the guard must not select on that token alone) | CONFIRMS | `ci-deploy.sh:2950` and `:3134` — the second is `DEPLOY_ROLLBACK: canary failed for $IMAGE:$TAG (reason=$CANARY_FAIL_REASON)` |
| No consumer parses `reason` as an enum | CONFIRMS | `web-platform-release.yml:800` reads it with `jq -r`; the `case` at `:802` switches on `EXIT_CODE`, **not** `REASON`; targeted greps for `case "$REASON"` / `[[ "$REASON"` / `REASON.*==` return zero |
| `ci-deploy` is allowlisted and `host_scripts_journald` has NO PRIORITY filter | CONFIRMS | `vector.toml:173-178`; every PRIORITY mention inside that block is a comment about other sources |
| `kernel`/`dockerd`/`docker`/`systemd`/`containerd` are in **no** allowlist | CONFIRMS | zero matches as quoted allowlist tokens anywhere in `vector.toml` — this is what makes H3 untestable |
| `_cred_err_tail` is top-level | CONFIRMS | `ci-deploy.sh:1211`, column 0 |
| `SANDBOX_PROBE_OK`, `blocking_probe_sentry_event`, `MOCK_BWRAP_FAIL_STDERR`, `MOCK_BWRAP_FAIL_RC` do not yet exist | CONFIRMS | zero matches each — all four are net-new, no collision |
| `assert_bwrap_canary_failure_rollback` is a second consumer of `MOCK_DOCKER_MODE=bwrap-fail` | CONFIRMS | `ci-deploy.test.sh:2027` and `:2351`, exactly two sites — which is why the mock parameterisation must default byte-identically |
| `T-7095-3` and `F14` already pin `_cred_err_tail`'s bounds | CONFIRMS | `ci-deploy.test.sh:5516-5518` ("≤200 bytes, control-characters stripped, any `dp.st.`-prefixed substring redacted") and `:5467`/`:5485` (redaction provably precedes truncation) — the decline to re-pin is safe |
| Four later scenarios depend on `MOCK_LOGGER_CAPTURE_FILE` | CONFIRMS | `ci-deploy.test.sh:4337`, `:4868`, `:5327`, `:5722` after the first at `:3743` — the subshell-scoping constraint in Phase 1.1 is load-bearing |
| `ci-deploy-sentry-post-fail-6475.sh` carries both contamination byte-forms | CONFIRMS | `:100` server-side, `:101` client-side |
| All three `BETTERSTACK_QUERY_*` secrets are wired | CONFIRMS | `scheduled-followthrough-sweeper.yml:103-105` — no workflow change needed |

### Citation verification (deepen-plan quality gate)

- **Rule IDs.** All six cited (`cq-assert-anchor-not-bare-token`, `cq-test-fixtures-synthesized-only`,
  `hr-before-asserting-github-issue-status`, `hr-observability-layer-citation`,
  `hr-verify-repo-capability-claim-before-assert`, `wg-ui-feature-requires-pen-wireframe`) resolve to
  active `[id: …]` entries in `AGENTS.md`. None appears in `scripts/retired-rule-ids.txt`.
- **Issues and PRs.** All 20 cited numbers resolved live via `gh`, and each state matches the role
  the plan gives it — including the two that changed the plan: `#5889` CLOSED/COMPLETED and `#6560`
  OPEN. `#7278` / PR `#7343` were checked against the `ship/SKILL.md` comment that cites them and are
  verbatim.
- **Cross-repo ambiguity caught.** `#701` was cited bare for the upstream bubblewrap issue; in this
  repository `#701` resolves to a **closed Soleur legal-docs issue**. Qualified to
  `containers/bubblewrap#701` (verified OPEN, title matches).
- **Paths.** Every `knowledge-base/**.md`, script and workflow path in the plan resolves on disk.
- **`origin/main` re-fetched** at deepen time (`35cb10d19`): it advanced 2 commits since the plan's
  baseline, and **none touched** `ci-deploy.sh`, `ci-deploy.test.sh` or `vector.toml`, so every
  content anchor still holds. AC1's argv extraction was run against it and returns exactly one line.

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
release from v0.1.0 to v0.12.0. Upstream issue **`containers/bubblewrap#701`, "Have a specific exit code
for when sandboxing is not possible", is still OPEN** (verified live), precisely because bwrap
returns a generic 1. The repo qualifier is load-bearing: a bare `#701` in this repository resolves
to a closed Soleur legal-docs issue, so an unqualified citation reads as provenance for a claim it
has nothing to do with.

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
| H4 | Container not fully settled when the probe ran | Measured: the canary's first log line was 22:31:54.598 and the rollback marker 22:31:57.450 — **2.852 s of total container life**, health loop breaking on its first iteration. `ms=` is what will separate this from H3. | **UNKNOWN** |
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
potentially embedding host paths, container ids, overlay digests, internal IPs, or (per the corrected
producer-corpus finding) an env entry formatted into a runc error. Three sinks, not two:

1. **journald `ci-deploy` → Vector → Better Stack.** Pre-existing channel — the same sink already
   receives `docker logs soleur-web-platform-canary --tail 30`. Scrubbed by `_cred_err_tail` at the
   producer **and** by Vector's `pii_scrub_string` regex backstop on the leg. (An earlier draft
   repeated the helper's own header claim that this sink is "UNSCRUBBED"; that is stale — the
   backstop does apply to these non-JSON lines. Conservative error, corrected for accuracy.)
2. **journald `webhook` → Better Stack**, via the guarded `printf`. Same scrubbing.
3. **Sentry, via the new `blocking_probe_sentry_event`.** This **is a new channel for this payload
   class** — an earlier draft's "not a new channel" declaration was true of Better Stack and false
   of Sentry, and the CPO sign-off was obtained on that incorrect statement. It also has **no
   backstop**: the POST bypasses Vector entirely, and Sentry's server-side scrubbers key on field
   *names*, not free-text values. That is why only closed vocabulary crosses it.

Mitigation is `_cred_err_tail` (now fail-closed, with four shape-anchored rules added), closed
vocabulary on the Sentry leg, and a leak-canary assertion over **all three** sinks.

**Brand-survival threshold:** single-user incident.

CPO sign-off obtained at plan time: **APPROVE WITH CONDITIONS**, all four folded into the acceptance
criteria. CPO corrected the blast declaration (prod keeps serving; *releases* stop) and the leak
declaration (pre-existing channel), both reflected above. `user-impact-reviewer` applies at review.

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/infra/ci-deploy.sh` | The probe's capture, the `DEPLOY_ROLLBACK` line, the success-path twin, a new `blocking_probe_sentry_event`, `_cred_err_tail`'s **body** (fail-closed pipeline check + four shape-anchored redaction rules) and header, and `write_state`'s optional appended-fields hook. The NOTE block above the probe and the bwrap argv are **not touched**. |
| `apps/web-platform/infra/ci-deploy.test.sh` | Parameterise the `bwrap-fail)` mock; extend `assert_canary_sandbox_failed_state`; add the purity, success-path and Sentry assertions. |
| `knowledge-base/legal/article-30-register.md` | One additive dated bracket on PA-8 §(g). Contested by one reviewer — see `## Decision challenges`. |

## Files to Create

| Path | Purpose |
|---|---|
| `knowledge-base/project/specs/feat-one-shot-8016-bwrap-probe-self-report/tasks.md` | Task breakdown. The directory exists and is empty, so this is a create. |
| `scripts/followthroughs/bwrap-probe-selfreport-<N>.sh` | The follow-through probe. `<N>` is the new tracker's number, assigned at filing. |
| `scripts/followthroughs/bwrap-probe-selfreport-<N>.test.sh` | Pins the probe's exit-code contract — the convention is explicit that "an exit-code contract nothing drives is a comment". |
| `scripts/followthroughs/bwrap-probe-selfreport-check.sh` | The `--dry-run` marker-resolution check named by `discoverability_test.command`. **preflight Check 10 executes that command**, so this file must exist in the same PR or the check fails on a missing script. Deliberately issue-number-free in its filename: the probe above is numbered because the sweeper binds it to a tracker, but this one is a static shape check with no tracker. |

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
    bwrap's codes; cite upstream, which is settled across every release. **In the same run, close the
    env-echo question**: start a throwaway container with a sentinel env var, force each failure in
    the `## What rc will say` table, capture merged output, and grep for the sentinel. That converts
    the corrected producer-corpus paragraph's remaining assumption into a measurement on the exact
    daemon/runc pair in production — the same discipline that overturned the bwrap exit-code claim
    and the `$?`-after-`if !` claim, both times against the plan's own prior belief.
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
          # mode (assert_bwrap_canary_failure_rollback) is untouched. The colon asymmetry below is
          # deliberate, and BOTH halves are load-bearing:
          #   stderr uses `${VAR-default}` (NO colon) — an explicitly EMPTY value must mean "the
          #     probe is silent", the observed production signature; `:-` would substitute the
          #     default and make the silent fixture unreachable.
          #   rc uses `${VAR:-1}` (WITH colon) — an empty value must fall back, because
          #     `exit ""` fails with "numeric argument required".
          # Documented together so the next reader does not "fix" the inconsistency.
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
  The split from the purity fixture is **not** because "a token-bearing input lands below the clamp" —
  that is not generally true (`F14`'s own 340-char fixture with an ~80-char token lands at ~271, still
  above 200). The durable reason: coupling the two makes the expected field length a function of the
  redaction replacement's length, so changing `dp.REDACTED` silently changes what "exactly 200" means.
- **slow**: a duration knob (`/bin/sleep 1.1`, invoked directly so `create_mock_sleep`'s no-op does
  not swallow it) → asserted `ms >= 1000`, while every fast scenario asserts `ms < 1000`. **Bounded,
  never exact** — `ms` is wall-clock-derived and an equality would flake exactly the way
  `ci-deploy.test.sh:3558` was measured to. Without this scenario `ms` has ONE value across the whole
  fixture set, a hardcoded `ms=0` passes the entire suite, and the sole discriminator for P2e is
  decorative — the harness's own F11 lesson (`ci-deploy.test.sh:5497`: "the fixture set has to
  instantiate more than one member of the … axis or the field is decorative") applied to a field this
  plan cites that learning while introducing.
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
      CSTATE="unknown"
      # Milliseconds, not $SECONDS. The H3-vs-H4 split lives entirely in the sub-second region —
      # the 2026-09-09 canary had 2.852 s of TOTAL life — so integer seconds would render a 40 ms
      # refusal and a 900 ms kill identically as 0. `date +%s%3N` is the established idiom in this
      # directory (inngest-enumerate-reminders.sh, inngest-inventory.sh); $SECONDS appears nowhere
      # in this file.
      BWRAP_T0="$(date +%s%3N)"
      # `VAR="$(cmd)" || RC=$?` is the ONLY form that is both errexit-safe and rc-preserving.
      # A bare `VAR="$(cmd)"; RC=$?` aborts under `set -e` before RC is read (measured: the script
      # exits with the command's own code and the next line never runs). And `if ! VAR=$(cmd)` is
      # errexit-safe but `$?` inside the branch is the NEGATED status — measured 0 — so the field
      # would read rc=0 on every single failure.
      BWRAP_ERR="$(docker exec soleur-web-platform-canary bwrap --new-session --die-with-parent --dev /dev --unshare-pid --bind / / -- true 2>&1)" || BWRAP_RC=$?
      PROBE_MS=$(( $(date +%s%3N) - BWRAP_T0 ))
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
        # BEFORE the teardown below, or the answer is destroyed by our own cleanup. `rc=1` is
        # shared between bwrap's own failure and docker's "no such container"/"not running", and
        # on the observed signature the message that would separate them is EMPTY — so without
        # this field H1 and H2 tie on exactly the case this PR exists to diagnose.
        CSTATE="$(docker inspect -f '{{.State.Status}}' soleur-web-platform-canary 2>/dev/null)" || CSTATE="absent"
        [[ -n "$CSTATE" ]] || CSTATE="absent"
        logger -t "$LOG_TAG" "DEPLOY_ROLLBACK: bwrap sandbox non-functional in $IMAGE:$TAG rc=$BWRAP_RC ms=$PROBE_MS cstate=$CSTATE err_chars=${#BWRAP_ERR} err=\"${BWRAP_ERR_SAN:-<empty>}\""
        # DELIVERY, not just capture. The NON-blocking faithful canary already pages Sentry on a
        # FAIL via `sandbox_canary_sentry_event` ("loud, no-SSH page … never journald-only"). The
        # BLOCKING gate — the one that actually stops the founder shipping — did not. This emitter
        # self-reports its own disposition on the credential-independent journald plane, because
        # the SENTRY_* env guard has been false in production before (this file's own comments
        # record "the beacon was silent in precisely the incident it was written to report").
        blocking_probe_sentry_event "$BWRAP_RC" "$PROBE_MS" "$CSTATE" "${#BWRAP_ERR}" || true
        { docker stop soleur-web-platform-canary 2>/dev/null || true; }
        { docker rm soleur-web-platform-canary 2>/dev/null || true; }
        # Sibling KEYS on the state payload — the `reason` STRING stays frozen. The cut list
        # rejected changing the string; it never evaluated additional keys, which break neither
        # the exact-equality test nor the release workflow's `jq -r '.reason'`. This is the
        # SYNCHRONOUS leg: `web-platform-release.yml` already runs `echo "$BODY" | jq .` on the
        # failure branch, so these surface in the failing run with ZERO workflow change — which is
        # the only plane the founder is already looking at. Closed vocabulary only: this payload is
        # echoed into a repo-readable run log, a wider audience than either async sink, so the free
        # text stays on journald.
        PROBE_STATE_FIELDS="probe_rc=$BWRAP_RC probe_ms=$PROBE_MS probe_cstate=$CSTATE probe_err_chars=${#BWRAP_ERR}"
        final_write_state 1 "canary_sandbox_failed"
        exit 1
      fi
      # Success-path twin, closed-vocabulary only. This is what makes the FIRST post-merge deploy
      # prove the field format end-to-end instead of proving only that the probe still passes, and
      # it accumulates the duration baseline that gives `ms=` meaning when a failure lands.
      logger -t "$LOG_TAG" "SANDBOX_PROBE_OK: rc=0 ms=$PROBE_MS err_chars=${#BWRAP_ERR}"
      echo "Sandbox OK"
```

`blocking_probe_sentry_event` mirrors `sandbox_canary_sentry_event`'s env-guard / best-effort /
fail-open shape, with three corrections the sibling does not have:

```bash
blocking_probe_sentry_event() {
  local rc="$1" ms="$2" cstate="$3" err_chars="$4" payload code disp="guard_absent"
  if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
    payload="$(jq -n --arg rc "$rc" --arg ms "$ms" --arg cs "$cstate" --arg ec "$err_chars" \
      '{message: ("blocking bwrap probe failed (rc " + $rc + ", " + $cs + ")"),
        level: "error", platform: "other", logger: "ci-deploy",
        tags: {feature: "agent-sandbox", op: "blocking-sandbox-probe", cstate: $cs},
        extra: {rc: $rc, ms: $ms, err_chars: $ec}}' 2>/dev/null)" \
      || { logger -t "$LOG_TAG" "BLOCKING_PROBE: disposition=payload_failed"; return 0; }
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X POST \
      "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/store/" \
      -H "Content-Type: application/json" \
      -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
      -d "$payload" 2>/dev/null)" || code="000"
    disp="posted"
    [[ "$code" == "000" ]] && logger -t "$LOG_TAG" "BLOCKING_PROBE: Sentry POST failed"
  fi
  logger -t "$LOG_TAG" "BLOCKING_PROBE: disposition=$disp sentry_http=${code:-000}"
}
```

Three deliberate divergences from the sibling, each closing a hole the review found:

1. **`disposition=` is emitted unconditionally**, on the credential-independent journald plane. The
   `SENTRY_*` guard has been false in production — this file's own comments record that it "blanked
   all seven `[[ -n $SENTRY_INGEST_DOMAIN && … ]]` guards and took the host Sentry-dark … 341 unit
   failures over 5.7h paged nobody" — and one of the two blocked releases had a degraded credential
   path (adjacent finding 1). Without this field a reader cannot distinguish "no event was posted"
   from "an event exists and I have not found it".
2. **`sentry_http=` records the status code.** `curl` without `-f` exits **0** on 4xx/5xx, so the
   sibling's `|| logger "… POST failed"` cannot fire on a 429 or a 401 — the dominant rejection
   class. `zot_gate_degraded_event` already carries a `login_http` field in this same file for
   exactly this reason.
3. **A `jq` failure logs before returning 0.** The sibling's `2>/dev/null) || return 0` goes silent.

**Closed vocabulary crosses the Sentry boundary; the free text does not.** The journald leg
additionally traverses Vector's `pii_scrub_string` backstop (email, bearer/basic, OAuth params,
`requirepass`, `scheme://user:pass@`); **the Sentry POST traverses none of it**. `ci-deploy.sh`
already states this policy at `zot_gate_degraded_event` — "ONLY the enum + status code + the
closed-vocabulary hatch cross this boundary — never the raw stderr". `err` therefore stays on the
plane that has the second scrubber.

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
  what: "SANDBOX_PROBE_OK: rc=0 secs= on every passing deploy, and the DEPLOY_ROLLBACK line carrying rc= ms= cstate= err_chars= err= on every failing one"
  cadence: "once per release — 83 probe attempts in the 28 days to 2026-09-10"
  alert_target: "Sentry for the event a person receives; Better Stack Logs (source soleur-inngest-vector-prd) for the queryable record. Naming a log sink alone would be naming a destination, not an alert target."
  configured_in: "apps/web-platform/infra/vector.toml (host_scripts_journald includes ci-deploy); Sentry via the existing SENTRY_* env guard in ci-deploy.sh"
error_reporting:
  destination: "TWO planes. (1) journald tag ci-deploy -> Vector -> Better Stack, the queryable record. (2) Sentry, via blocking_probe_sentry_event modelled on the in-file sandbox_canary_sentry_event, tags {feature: agent-sandbox, op: blocking-sandbox-probe}, extra {rc, ms, err_chars}."
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
  command: "doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 12h --grep 'DEPLOY_ROLLBACK: bwrap sandbox non-functional' --grep 'SANDBOX_PROBE_OK: bwrap sandbox verified'"
  expected_output: "JSONEachRow rows whose decoded .message carries rc= ms= cstate= err_chars= for every deploy in the window (plus bwrap_err= on a rollback row); zero rows across a window with no deploy is real absence, because ci-deploy is on the Vector allowlist"
  credentials_required: "Doppler soleur/prd_terraform BETTERSTACK_QUERY_HOST/USERNAME/PASSWORD — the Better Stack ClickHouse read connection. The property is 'the marker reaches the sink', and the sink has no anonymous read; a grep over the source file would verify the diff, not the delivery."
```

> **Superseded 2026-09-11 (#8026):** the block above originally named
> `bash scripts/followthroughs/bwrap-probe-selfreport-check.sh --dry-run` with expected output
> `DRY-RUN OK: markers resolved, both byte-forms present, no live query attempted`. That script and
> its two siblings were deliberately not built — see the archived `tasks.md` §"Deliberately NOT
> built" — so the command named a file the PR does not create, and Check 10 would have FAILed on a
> missing script rather than on the property. The replacement is the read this session actually
> ran against production, declared under `credentials_required` because the sink has no
> unauthenticated form.

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
event**: `rc` separates own-failure / infra / signal, `cstate` breaks the `rc=1` tie between bwrap's
own failure and docker's "no such container", `ms` separates a fast kill from a slow one, and
`err_chars` separates truncated from complete.

**`cstate` is not decoration — without it the claim above is false**, and the plan's own `## Hypotheses`
H1 row says why: "`rc=1` is shared with docker's 'no such container', so **the message is what
separates them**." The observed signature has `err_chars=0`. So on precisely the case this PR exists
to diagnose, an `rc=1` result would have returned a tie between H1 and H2 and the instrument would
have named nothing — the same failure the intake brief's `err`-only proposal would have had. The
discriminator was one `docker inspect` away, and it has to run **before** the teardown or our own
cleanup destroys the answer.

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
| 6 | Stub `sed` to exit non-zero **mid-pipeline** inside `_cred_err_tail`, under the purity scenario | Must red with `err="<sanitize_failed>"` and with the `dp.st.` token absent from all three sinks. An earlier row mutated the helper to `return 1` on its last statement — a mutation nobody would ever make for an unrelated reason, which this matrix's own criterion rejects. The real failure is a mid-pipeline tool death, which under the `\|\|`-suspended errexit lets the helper emit a **partially sanitized** value and return 0. |
| 7 | Pass `$BWRAP_ERR` instead of `${#BWRAP_ERR}` to `blocking_probe_sentry_event` | The raw text crosses the one sink with no Vector backstop. Must red on AC7's POST-body assertion — an assertion scoped to the logger file alone would stay green. |
| 8 | Append a field **after** `err="…"` on the rollback line | The single likeliest unrelated future edit to this line, and the in-file sibling at `ci-deploy.sh:1013` invites it — that emitter runs `… kw=%s tok=%s docker_ver=%s`, i.e. the free-ish field with another `k=v` after it, and the production line in adjacent finding 1 carries a trailing `(registry=ghcr)` parenthetical too. Copying that shape silently destroys the ADR-115 trusted region. AC3's `$` anchor should catch it — this row is what proves the anchor is load-bearing rather than decorative. |
| 9 | Emit the `DEPLOY_ROLLBACK` line **twice** | The assembly argues at length for "assert the count is exactly 1, never `head -1`". Nothing proved that count assertion discriminates. This is the extractor-uniqueness axis; every other row perturbs SUT content. |
| 10 | Change `err_chars=${#BWRAP_ERR}` to `${#BWRAP_ERR_SAN}` | A tidy-up that reads as an improvement ("use the sanitized value consistently") and silently deletes P2c: post-sanitization the field reports 200 beside a 200-character value, making truncation permanently undetectable. One field's provenance carries the whole property. |

**Harness rows.**

| # | Row | Expected |
|---|---|---|
| H1 | Mutate the SUITE, not the script: delete the field anchors from the assertion so it asserts only that a line exists | A meta-check must RED. Without it a vacuous assertion passes forever. |
| H2 | **Must-PASS, non-canonical:** the purity scenario emits a message nothing like the canonical `bwrap: No permissions to create new namespace` — multi-line, non-ASCII, over 200 chars | Must **PASS**. The contract permits any message; the assertion anchors on the field's *structure*, never on the one canonical string. |
| H3 | **Must-PASS, non-canonical:** the silent scenario at rc=137, zero bytes | Must **PASS** with `rc=137 err_chars=0 err="<empty>"`. |
| H4 | Assert `MOCK_LOGGER_CAPTURE_FILE`, `MOCK_BWRAP_FAIL_RC` and `MOCK_BWRAP_FAIL_STDERR` are all unset after the scenario | Catches a hoisted export contaminating the four later scenarios that depend on `MOCK_LOGGER_CAPTURE_FILE`, and the two knobs this PR introduces. **The byte-identical-output half of an earlier draft of this row is deleted: it was MEASURED to fail on an untouched worktree.** Two clean baseline runs differ at `ci-deploy.test.sh:3558` — `PASS: T3 no-cron deploy: zero-wait drain (0s…)` vs `(1s…)`, because `T3_WAIT` is a `date +%s` delta that can cross a second boundary. The row would have reported "a hoisted export contaminated four scenarios" when nothing was hoisted. A harness row that reds at baseline is indistinguishable from a catch. |
| H5 | Per-anchor sweep: delete each field anchor from the assertion **one at a time** (`rc=`, `ms=`, `cstate=`, `err_chars=`, the `err="…"$` tail) | Each deletion must red on its own. H1 deletes them all at once, which cannot show that any individual anchor discriminates — an all-or-nothing meta-check passes while four of five anchors are decorative. |

**Anchor discipline** (`cq-assert-anchor-not-bare-token`): every assertion selects the single line
containing `DEPLOY_ROLLBACK: bwrap sandbox non-functional` and then tests fields **on that selected
line**. A bare `grep -q err_chars` over the whole capture would pass on any line anywhere.

**Consumer contract for the free-text field.** Neither sink can be broken out of — the value sits in
a double-quoted bash word with every `"` mapped to `'` and every control byte collapsed to a space,
so no second journald record can be forged; and the Sentry payload is built with `jq --arg`, which
escapes opaquely. But the value may legitimately *contain* spaces and `=`, so it is forgeable by
substring: a probe output containing the literal `rc=0 ms=0` will appear inside the quoted field.
`err` is therefore the only free-text field and is **last on the line by construction**; every
consumer must anchor on `err="[^"]*"$` and must never substring-match `k=v` tokens across the line.
This is what the ADR-115 trusted-region convention buys, stated explicitly for the next reader.

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
  **Run it against the PURITY scenario's line, not only the default one.** Under the canonical
  fixture (no double quote in the message) the `[^"]*` class is vacuous with respect to the property
  it exists for — and quote-flattening is the one `_cred_err_tail` behaviour AC3 structurally depends
  on that *neither* `T-7095-3` nor `F14` exercises (both inject control bytes and a `dp.st.` token,
  neither injects a `"`). Without a `"` in the input, the anchor proves nothing about breakout.
- **AC4** — `BWRAP_ERR_SAN` is assigned with an errexit rescue (`|| BWRAP_ERR_SAN="<sanitize_failed>"`).
- **AC5** — Sanitization routes through `_cred_err_tail "$BWRAP_ERR"`, and **`ci-deploy.sh` alone**
  (not the diff, which legitimately adds test-side line selection) introduces no new
  `tr -dc`/`cut -c`/`head -1` sanitizer.
- **AC6** — The deploy-state contract is frozen: no change to `final_write_state 1 "canary_sandbox_failed"`.
- **AC7** — Purity, on **all three** sinks. Under the purity scenario, the full
  `$MOCK_LOGGER_CAPTURE_FILE`, the captured `$output`, **and the captured Sentry POST body** each
  contain none of: `SENTINEL_LEAK_CANARY`, a raw CR, an unredacted `dp.st.` token, an `sk_live_`
  key, a `eyJ…` JWT, or a `whsec_`/`re_`/`gh?_` token. Three sinks, not two: the guarded `printf`
  writes to stdout (which reaches Better Stack under the `webhook` tag), and the Sentry POST is a
  sink this PR *creates*. Capture the POST body by stubbing `curl` in the mock, the way
  `ci-deploy-sentry-post-fail-6475.sh`'s scenario does. An AC scoped to the logger file alone would
  go green on a diff that passed the raw variable to Sentry — the "guard's assertion and guard's
  property drift apart" failure this plan cites as its own driving learning.
- **AC7b** — The raw variable never reaches the Sentry call site:
  `! grep -n 'blocking_probe_sentry_event' apps/web-platform/infra/ci-deploy.sh | grep -q 'BWRAP_ERR[^_]'`.
- **AC8** — Silent path: `rc=137`, `err_chars=0`, `err="<empty>"`. The observed production signature,
  untested today.
- **AC9** — Spoken path: `rc=1`, `err_chars` greater than 0, non-empty `err="…"`, anchored on
  structure and never on the canonical fixture string.
- **AC10** — Truncation: an over-200 input with **no** redactable token yields a field of exactly 200,
  and `err_chars` reports the pre-sanitization length. Separate fixture from AC7's, because redaction
  precedes truncation and shrinks a token-bearing input below the clamp.
- **AC11** — Pass path: with `MOCK_BWRAP_FAIL_RC=0` and non-empty stderr, the probe succeeds **and**
  the sanitized text is still re-emitted to `$output`, **and `actual_exit == 0`**. The exit assertion
  is not ceremony: this is the first time in the file's history that `bwrap-fail` mode drives a deploy
  *past* the sandbox gate, through every downstream stage (`ps`, `inspect`, `logs`, zot, cosign). Without
  it the scenario passes even if the deploy dies three stages later for an unrelated reason. This is
  the 97.6% branch.
- **AC12** — The gate is still asserted, not replaced: `reason` equals `canary_sandbox_failed`,
  `exit_code` equals `1`, and the canary `docker stop`/`docker rm` ran.
- **AC13** — The success-path twin exists and **executed**: under the green-path scenario,
  `$MOCK_LOGGER_CAPTURE_FILE` contains exactly one line matching `SANDBOX_PROBE_OK: rc=0 ms=[0-9]+ err_chars=[0-9]+`
  and that line carries no free-text field. Counted on the **capture file, not the source** — an
  earlier draft counted `grep -c 'SANDBOX_PROBE_OK' ci-deploy.sh`, which is the same
  grep-the-file-the-diff-just-edited tautology this plan condemns 120 lines earlier when rejecting it
  as a discoverability test. A count on the capture means the line *ran*; a count on the source means
  the text exists. (Where a source count is genuinely wanted, `|| true` remains load-bearing: `grep -c`
  prints `0` **and exits 1** on no match — the class `scripts/lint-shell-capture-exit.py` exists for.)
  `err_chars=` is on the twin deliberately: `${#BWRAP_ERR}` is computed identically on both paths and
  an integer stays closed-vocabulary, so 83 green deploys per 28 days become a live positive control
  that the capture variable is populated — instead of the field first executing for real during the
  incident it exists to diagnose.
- **AC14** — `blocking_probe_sentry_event` exists, is env-guarded on the same three `SENTRY_*`
  variables as `sandbox_canary_sentry_event`, is invoked with `|| true`, and carries **only** the
  closed vocabulary `rc`, `ms`, `cstate`, `err_chars` — never `err`. A scenario asserts the POST is
  attempted when the DSN components are present and is inert when they are absent, mirroring the
  existing `#7103 R1` assertions for that sibling. Additionally:
  - the `message` field is built from closed vocabulary only. The sibling interpolates its free-text
    arg into `message`, and a faithful copy would too — which makes every distinct bwrap error a
    separate Sentry issue (fingerprinting degrades exactly when it is needed) and puts the payload
    in the issue **title**, i.e. into notification emails and Slack, a wider distribution than the
    event body.
  - it emits `BLOCKING_PROBE: disposition=posted|guard_absent|payload_failed sentry_http=<code>` on
    the credential-independent journald plane, **unconditionally**, plus a `BLOCKING_PROBE`-tagged
    `|| logger "… Sentry POST failed"` fallback.
  - `scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh`'s header enumerates **seven**
    fail-open Sentry sites; this makes eight. Update that count and name the new tag, or the soak's
    own inventory silently drifts.
- **AC15** — Every mutation row 1-10 and harness rows H1/H5 observed RED; H2, H3 and H4 observed
  PASS. **Every harness row was calibrated against the pristine tree first** — a row that reds at
  baseline reports the baseline, not a catch (H4's earlier byte-identical form was measured to do
  exactly that).
  Results recorded in the PR body. `bash apps/web-platform/infra/ci-deploy.test.sh` exits 0 with a
  total strictly greater than the 216 baseline and `0 failed`.
- **AC16** — `_cred_err_tail`'s header records its second producer, its new fail-closed contract, and
  its bound — worded as "**bounded to the last 200 characters, which equals 200 bytes only because
  step 1 collapses the input to ASCII under `LC_ALL=C`**". The transitivity is the point: `${#_e}`
  and `${_e:offset}` count characters in the caller's locale, and `ci-deploy.sh` deliberately does
  not export `LC_ALL`, so a future edit that relaxes step 1's `tr` to preserve UTF-8 — a plausible
  edit, since collapsing every non-ASCII byte to a space mangles a non-English diagnostic — silently
  converts a 200-byte bound into a 200-character one, up to 800 bytes, while a header saying
  "200-byte clamp" would still read as true. The clamp also matters at the new call site: a reader
  seeing `err_chars=340` beside a 200-character field has no local explanation otherwise.
- **AC16b** — The deploy-state payload carries the closed-vocabulary sibling keys `probe_rc`,
  `probe_ms`, `probe_cstate`, `probe_err_chars` alongside the **frozen** `reason` string. Verified:
  `ci-deploy.test.sh`'s exact-equality `reason` assertion still passes, `cat-deploy-state.sh`
  tolerates the additions, and no whole-JSON equality assertion breaks. `err` is deliberately
  **absent** here — this payload is echoed into a repo-readable run log by
  `web-platform-release.yml`'s existing `jq .`, a wider audience than either async sink.
- **AC17** — The #8016 comment exists; the issue **body is unedited**, verified against the SHA-256
  recorded in `## Research Insights`
  (`gh issue view 8016 --json body -q .body | sha256sum` equals `c3aea158b8443b13ad7aad0284c5a98add3369dbd694564cd44f67e7697a75b4`);
  and the comment does not assert that the probe's stderr is discarded because only `logger` lines
  reach journald.

**The `_cred_err_tail` scope-lock is deliberately REOPENED, and why.** An earlier draft declined to
touch the helper, citing `T-7095-3` and `F14` as existing coverage. That lock was set when the
helper's only producer was `doppler secrets get` stderr, whose corpus genuinely is Doppler-shaped.
Adding a second producer whose corpus is **the full prd secret set** (see the corrected
producer-corpus paragraph in `## Domain Review`) is exactly the event that should reopen it. Both
existing suites stay green — the changes below are additive.

Two defects the security review found in the helper as applied to the new call site:

1. **Fail-open partial sanitization.** `BWRAP_ERR_SAN="$(_cred_err_tail …)" || BWRAP_ERR_SAN=…`
   places the function inside a `||` list, which **suspends errexit for its entire body**. If `sed`
   dies mid-pipeline (PATH damage, fork failure under memory pressure — the conditions this
   instrument exists to diagnose), the assignment fails, execution continues, and the final
   `printf` emits the value of the *last successful stage*: control-stripped and quote-swapped but
   **not redacted**. `printf` succeeds, the function returns 0, the rescue never fires, and a
   partially-sanitized 200-byte tail ships to every sink. This plan's own `## Sharp Edges` states
   the mechanism — "`run_faithful_sandbox_canary` uses this pattern safely **only** because it is
   invoked as `… || true`, which suspends errexit for the whole function body" — and an earlier
   draft applied that reasoning to one function and not to the one guarding the credential boundary.
   Fix: an explicit pipeline-status check inside the helper, so it is fail-closed regardless of
   caller context. The existing call site's behaviour is unchanged (it aborted before; it now
   returns 1 into a bare assignment, which still aborts).
2. **One vendor prefix is not a ruleset.** `sed -E 's/dp\.[a-z]{2,}\.…/dp.REDACTED/g'` is the
   helper's entire value-shaped ruleset. None of `SUPABASE_SERVICE_ROLE_KEY` (a `eyJ…` JWT),
   `STRIPE_SECRET_KEY` (`sk_live_…`), `STRIPE_WEBHOOK_SECRET` (`whsec_…`), `RESEND_API_KEY` (`re_…`),
   `SENTRY_AUTH_TOKEN` or any GitHub/Cloudflare/Hetzner token carries a `dp.` prefix. Vector's
   `pii_scrub_string` backstop catches none of them either — it is anchored on `userid=` k=v pairs,
   OAuth query params, emails, `Authorization:` framing, `requirepass`, and `scheme://user:pass@`
   DSN userinfo. Every credential above is a **bare high-entropy token** with none of that framing.
   Add four shape-anchored rules, sited so they inherit the existing redaction-before-truncation
   order (each anchors on a vendor-published, self-identifying prefix, so the false-positive surface
   over `bwrap:` / `OCI runtime exec failed` / `Error response from daemon` text is nil):

```bash
    | sed -E 's/\b(sk|pk|rk)_(live|test)_[A-Za-z0-9]{8,}/[redacted-key]/g' \
    | sed -E 's/\bey[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/[redacted-jwt]/g' \
    | sed -E 's/\b(gh[pousr]|sbp|dop_v1|re|whsec|xox[baprs])_[A-Za-z0-9_-]{16,}/[redacted-token]/g'
```

Mirroring these into `vector.toml`'s `pii_scrub_string` would cover the Better Stack leg for **every**
producer on that source, not just this one — but that carries its own independent justification
(`pull_failure_event`'s recorded Authorization-header concern) and a different blast radius, so it is
**adjacent finding 5**, not this PR.

**`err_chars` is a pre-redaction length oracle — accepted, on the record.** It reports the true
length of the unredacted output on sinks that leave the box. Given the corpus the signal is
negligible and the truncation-discrimination value is high (P2c depends on it), so this is a
decision rather than an omission.

### Post-merge (fully automated — no separate apply step)

- **AC18** — `apply-deploy-pipeline-fix.yml` auto-applies on merge because `ci-deploy.sh` is a
  `terraform_data.deploy_pipeline_fix` trigger file. `/ship` Phase 5.5 surfacing this is expected.
- **AC19** — The first post-merge release is triaged by the table below, and the follow-through
  probe's window starts at the merge date so no step depends on memory.
- **AC20** — Within 24h of that release, a field-isolated Better Stack read returns at least one
  `SANDBOX_PROBE_OK` row carrying `rc=0 ms=`. This is what the success-path twin exists for. An
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
`rc=128` → H2; `rc` in the `128+n` band → H3, and `ms=` then splits an immediate refusal from a
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
| `reason=canary_sandbox_failed` **with** `rc=`/`ms=`/`err=` on the line | Genuine, and now diagnosable. Read the fields. |
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

5. **Two existing observability controls are blind in a way their own soak certifies as green.**
   Consolidated into one tracker because they are the same class — a control whose success condition
   cannot express its dominant failure.
   (a) **All seven `*_sentry_event` emitters in `ci-deploy.sh` use `curl` without `-f`/`--fail`**, so
   the shared `|| logger "… Sentry POST failed"` detector exits 0 on any HTTP 4xx/5xx. A Sentry 429
   (rate-limit) or 401 (bad key) is indistinguishable from success: no logger line, no Better Stack
   row. `scripts/followthroughs/ci-deploy-sentry-post-fail-6475.sh` exists solely to soak those lines
   and defines SOUND as "zero 'Sentry POST failed' lines from ci-deploy" — so it reports **green
   vacuously for the entire HTTP-rejection class**. The remedy is the `%{http_code}` capture this PR
   adds at its own new site; the seven existing sites need the same, plus a corrected SOUND
   definition. In-repo precedent: `zot_gate_degraded_event` already carries a `login_http` field.
   (b) **Vector's `pii_scrub_string` catches no bare high-entropy token shape.** It is anchored on
   `userid=` k=v pairs, OAuth query params, emails, `Authorization:` framing, `requirepass`, and
   `scheme://user:pass@` DSN userinfo — none of which frames an `sk_live_…`, `eyJ…` JWT, `whsec_…`,
   `re_…` or `gh?_…` token. This PR adds four shape-anchored rules at one producer
   (`_cred_err_tail`); mirroring them into the sink transform would cover **every** producer on that
   source. Independently justified by `pull_failure_event`'s recorded finding that a 401/403 daemon
   error can echo a registry Authorization header.

**Net-issue-flow.** This PR closes 1 and files **6** — the five above plus the `follow-through`
diagnosis tracker — so it is net **+5**. Use `<!-- gate-override: net-issue-flow -->` in the PR body
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

**Producer corpus — CORRECTED. An earlier draft's "recorded negative" was not a closed one.**

Three producers can write to the captured stream: the **docker client/daemon**
(`Error response from daemon: Container <id> is not running` / `No such container`), **runc**
(`OCI runtime exec failed: …`, AppArmor/seccomp denials naming `soleur-bwrap`), and **bwrap** itself
(`bwrap: Creating new namespace failed: Operation not permitted`, which fails *before* executing its
payload — and the payload is `true`, which produces no output on any path).

On **end-user personal data** the negative holds: no request context, no database read, no HTTP
header, no session, and the canary has never served a request. PA-8 §(c) does not change.

On **operator credentials it does not hold**, and the earlier draft's reasoning was factually wrong.
It claimed "the `ENV_FILE` was consumed by the daemon at `docker run` time". It was not. `--env-file`
is parsed into `Container.Config.Env`, which the daemon **persists for the container's lifetime** and
merges into the OCI process spec of **every subsequent `docker exec`**. So the probe's exec target
runs with the full prd secret set live in its environment — `SUPABASE_SERVICE_ROLE_KEY`,
`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `BYOK_ENCRYPTION_KEY`, `SENTRY_AUTH_TOKEN`,
`RESEND_API_KEY` and the rest. Nothing was consumed.

That relocates the question from "can it be re-serialised?" to "does any producer in the corpus
format an env entry into an error?" — and one does: runc's `populateProcessEnvironment` validates
every entry in `process.env` and formats offending entries with Go's `%q`, including a `%q=%q`
name/value form. The daemon returns runc's stderr verbatim, prefixed `OCI runtime exec failed: …`,
and `2>&1` captures it. This shape has not been observed firing. The point is that the corpus is
bounded by **observation, not by architecture**, which makes the sanitizer the **load-bearing
control** rather than belt-and-braces — and is why the `_cred_err_tail` scope-lock is reopened above.
This repo has already written the same finding down for the nearest-neighbour producer:
`pull_failure_event`'s header records that "a 401/403 daemon error can echo the registry
Authorization header", and its chosen remedy was to let **no** raw docker stderr reach a Sentry
payload — only a four-value enum. That precedent, not `sandbox_canary_sentry_event`, is the right
model for a docker-subprocess producer on that sink.

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
- **A determinism claim is an experiment, not a deduction — and this plan failed its own rule once.**
  An earlier harness row asserted "two consecutive full-suite runs produce byte-identical output".
  Measured on the untouched worktree, they do not: `ci-deploy.test.sh:3558` emits
  `zero-wait drain (0s…)` or `(1s…)` depending on whether a `date +%s` delta crosses a second
  boundary. The row would have redded at baseline and been read as a catch. **Calibrate every harness
  row against the pristine tree before Phase 3 records a verdict** — a row that reds on a clean tree
  reports the tree, and that is indistinguishable from finding a defect. The plan's own Sharp Edges
  say "any plan turning on shell exit-code semantics must run the experiment rather than reason about
  it"; determinism is the same class and an earlier draft reasoned instead.
- **A field with one value across the whole fixture set is decorative, however well justified.** Under
  the mock every probe returns instantly, so `ms` was 0 everywhere and a hardcoded `ms=0` would have
  passed the entire suite — while `ms` is the *sole* discriminator for the H3-vs-H4 split it was added
  for. The harness already records this lesson at `ci-deploy.test.sh:5497` ("the fixture set has to
  instantiate more than one member of the … axis or the field is decorative") and this plan cited that
  learning family while reproducing the defect on a new field. Bound the second value (`ms >= 1000`),
  never pin it — wall-clock equality is how `:3558` flakes.
- **A mutation battery can measure depth on one axis and report it as breadth.** Six rows perturbing
  the emitted line's content is one axis explored six ways. The axes an earlier draft never touched
  were **extractor uniqueness** (does the "exactly one match" count actually discriminate?) and
  **field order** (is the `$` anchor load-bearing or decorative?) — both now rows 8 and 9, and both
  guarding assertions the plan argued for at length and then never proved.
- **A plan whose `## User-Brand Impact` is empty or omits the threshold fails `deepen-plan` Phase 4.6.**
- **`/ship` Phase 3.7 WILL fire** because the diff touches `ci-deploy.sh`, and Phase 5.5 will surface
  the `deploy_pipeline_fix` auto-apply. Both correct and expected: a deploy-gate change cannot be
  validated by any deploy except the first post-merge one.
