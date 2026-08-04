---
module: infra-config delivery channel (apps/web-platform/infra)
date: 2026-08-04
problem_type: logic_error
component: shell_script
symptoms:
  - "follow-through probe returned PASS against a host actively dying at daemon-reload"
  - "two frame writers disagreed: one suppressed a real death, the other invented one"
  - "operator alert titled as a seccomp security incident for a config-delivery failure"
  - "self-run 4-mutation battery reported all-killed; an independent 12 found 10 survivors"
root_cause: wrong_predicate
severity: critical
tags: [positive-control, follow-through, mutation-testing, observability, operator-facing, vacuous-assertion]
issue: 7220
pr: 7221
synced_to: [review, ship]
---

# Every check I shipped certified the wrong property

## Problem

PR-A of #7220 gave `infra-config-apply.sh` a no-SSH fatal-error channel: the handler could fail
but not say how. The implementation passed 133/133 of its own tests, 87/87 registered infra
suites, a self-run mutation battery, and a shellcheck pass.

An 11-agent review panel then found **five P1s, all PR-introduced**. Every one of them — plus
every defect in my own work that preceded them — was the same shape: **a check that was present,
passing, confidently commented, and measuring something adjacent to the thing it was named for.**
Not missing checks. Wrong ones.

## The sharpest instance: a probe that passed against the outage it was built to detect

The follow-through probe existed to prove the new instrument was live in production. Its liveness
control counted handler rows in Better Stack:

```
starting: 19 files to write / writing: … / wrote: … / complete: 19/19 files written
```

**The pre-#7220 handler emits every one of those.** So the control could not distinguish *"the
new instrument is live and healthy"* from *"the new instrument was never delivered"* — which is
precisely the failure mode this channel exists to detect, because the config-delivery channel is
itself the thing that breaks.

Run against production, it returned:

```
PASS: channel is live (40 handler rows from soleur-web-platform in 24h) and reported no fatal.
```

Those 40 rows were `1 starting + 19 writing + 19 wrote + 1 complete` — the exact trace of an apply
that died at `daemon-reload`. And `sweep-followthroughs.sh` **closes the issue on exit 0**. The
probe would have closed #7220 while #7220 was still happening.

### The rule

> A signal that BOTH the old and the new artifact emit can never be a positive control for the
> new one. Only something structurally impossible for the old version can be.

Here there were exactly two candidates: a `SOLEUR_INFRA_CONFIG_FATAL` row (a string no pre-fix
handler can emit) and the `fatal_rc` **key** in the state frame (written unconditionally on the
success path, so its *absence* proves an old handler even when nothing has failed).

**Corollary:** when a probe cannot resolve the ambiguity, `TRANSIENT` is the honest exit. `PASS`
on ambiguity is an auto-close. The rewritten probe now FAILs against production and says why.

## `.final` was never the question — two P1s from one wrong discriminator

The trap had two arms writing one fact, each with its own predicate:

| arm | predicate | consequence |
|---|---|---|
| frame | `rc != 0` **&&** no `.final` sentinel | **suppressed a real death** |
| journald | `rc != 0` | **invented a death** |

- The webhook self-restart is a **second ungranted `sudo`**, running *after* the sentinel exists.
  When it failed, the published frame still said `exit_code:0`, and the gate adjudicates on that
  first — so it **PASSED**. #7220's own shape relocated ~200 lines later, invisible to the
  instrument built for it.
- A `missing_env` partial delivery is the documented #4804 self-heal: it completes, publishes a
  correct frame, and exits 1 for accounting. That emitted `FATAL: line=0 rc=1 cmd=` on the exact
  channel the annotation tells the operator to grep — and the soak hard-FAILs on `line=0`.

The honest predicate is **"did it DIE"**: non-zero **AND** (no frame published **OR** an ERR
actually fired). `fatal_line > 0` is the ERR's own fingerprint; an accounting exit leaves it 0.

The precedent this trap copies (`emit_state` in the inngest cutover-flip script) writes its state
slot and its logger line from **one call with one payload**. Splitting one fact across two
predicates is what let them disagree.

## Reusing an alert's transport reuses its identity

Calling `seccomp_unenforced_alert` with an infra-config detail string looked like reusing a proven
transport. Only `detail` is a parameter. The operator would have received:

- an issue **titled** *"Security profile (seccomp) not enforced on the server"* — a fabricated
  security claim for a config-delivery failure;
- a remediation (*"re-run once the image pull path is healthy"*) that loops forever on a
  deterministic handler fault;
- a dedupe key of `ci/seccomp-unenforced`, so an open seccomp incident **swallows** this alert as
  a comment, and vice versa — two independent P1 classes, one slot;
- a Sentry event tagged `feature:agent-sandbox`, paging the security rule.

`operator-digest` harvests action-required issues **by title**. The one surface the alert exists
to serve would have shown a non-technical founder a breach that did not happen.

Two adjacent operator-facing defects from the same step:

- **An alert firing on ANY gate failure must not assert facts true of only one branch.** On
  `000/502/503` the listener is DOWN, `-replace` on the handler bootstrap **is** the documented
  route back, and "app health is unaffected" is not something that step can assert. The alert said
  the opposite of the gate.
- **A guardrail that forbids a command PREFIX without naming a TARGET is uncheckable.** The same
  workflow legitimately prescribes `-replace=terraform_data.infra_config_handler_bootstrap` 55
  lines up. A reader who takes "never `-replace`" literally is stranded; one who notices the stock
  justification cannot apply to a `terraform_data` resource goes hunting for a target — and
  nothing named `hcloud_server.web` as the one that destroys the host.

## My own mutation battery was the false confidence

I ran 4 mutations, reported all killed, and said so in a commit message. An independent pass ran
12 I had not imagined; **10 survived**, including:

- replacing the **entire fatal annotation** with a hardcoded string literal — **53/0 green**,
  because there was ONE fatal fixture and every assertion grepped that fixture's own values.
  Population-of-one: `1-of-1` is indistinguishable from `all-of-1`;
- hardcoding `files_written` to `0` — the one number that tells the operator *your files did land*
  was never exercised at a non-zero value;
- keying `fatal_mode` on `fatal_rc` instead of `fatal_line` — no fixture crossed that seam.

And **nothing asserted the assertions RAN**: deleting the new arms left both suites exiting 0
(apply 144→110, gate 61→40). Both suites now carry an assertion-count floor.

Two more of mine in the same family:

- the `-O` ownership guard on the handoff file shipped with **no test** — only mutating it out
  revealed that;
- the secret-leak arm was **vacuous**: the handler never reads the probe variable, and the failing
  command's source text names no secret-bearing variable, so the absence assertions held by
  fixture construction and would have passed against a handler that fully expanded
  `$BASH_COMMAND`. The real property is a bash invariant, now pinned directly, plus an assertion
  that the handler contains no `eval` — the one construct that voids it. **The sanitizer is not a
  redactor**: its charset `A-Za-z0-9 ._:/=-` preserves a `dp.st.…` token intact.

## Measurement discipline, in both directions

- **A RED that was not mine.** `git-data-runcmd-rehearsal` failed and I nearly filed it as a
  regression. My branch was **9 commits behind**, and #7197 had grown that suite by 482 lines — I
  was running the old 19-assertion version. An A/B against a pristine `origin/main` worktree
  (36/0 vs 19) settled it in one command.
- **Same commit, different results.** 10-failed then 0-failed in different worktrees. Not flake: a
  fresh worktree lacks `.terraform` state.
- **Phase 0.1 was worth doing.** Re-measuring the bash trap semantics on the *target image's*
  bash (5.2.21, via `docker run ubuntu:24.04`) rather than the dev box's 5.3.9 returned identical
  results — and that identity is itself the record worth keeping.

## Solution

```bash
# ONE predicate, computed once, feeding BOTH arms.
local died=0
if [[ "$rc" -ne 0 ]] && { [[ ! -f "${STATE_FILE}.final" ]] || [[ "$f_line" -gt 0 ]]; }; then
  died=1
fi
```

A death after a successful publish now **corrects** the frame (`exit_code`, `reason`,
attribution) while preserving the `files[]`/`restarts[]` the run earned.

```bash
# The probe's positive control must be impossible for the old artifact.
if printf '%s' "$frame" | jq -e 'has("fatal_rc")' >/dev/null 2>&1; then
  exit 0   # new handler, genuinely healthy
fi
exit 1     # old handler on the host — silence is unverified, not clean
```

## Prevention

- For any probe/guard, ask: **what would this report if the thing it verifies were never
  deployed?** If the answer is the same as "healthy", the control is wrong.
- For any alert, ask: **what title and dedupe key does the operator actually see?** Reusing a
  transport reuses an identity.
- For any guardrail, ask: **does it name a target, or only a command?** A prohibition you cannot
  check against a concrete object is not enforceable.
- For any mutation battery you wrote yourself: **it measures the mutations you imagined.** Ask an
  independent pass to find the vacuity you missed, and never re-run your own list.
- Before filing a RED as a regression: **A/B against pristine `origin/main`**, and check how far
  behind the branch is.

## Session Errors

1. **Two `Write` calls blocked by `hr-all-infrastructure-provisioning-servers`** (flagged
   `systemctl` in prose). Recovery: sanctioned `iac-routing-ack` opt-out with rationale.
   **Prevention:** an infra plan whose subject IS a systemd verb needs the ack up front.
2. **`betterstack-query.sh --since` rejects the `Z`-suffixed ISO form its own header advertises.**
   Recovery: `--since 1h`. **Prevention:** tracked as D1; the header is the bug.
3. **First-draft plan rated `threshold: none`** on a change activating a deploy→root escalation
   chain. Recovery: review panel raised it. **Prevention:** grep the diff for privilege verbs
   before rating a threshold.
4. **Greps on Better Stack output returned nothing** — the payload is double-encoded JSON.
   **Prevention:** decode with `jq -r '.raw|fromjson'` before grepping; never the raw line.
5. **Read a failing suite run as clean** — `run-registered-suites.sh` prints `RED`, not `FAIL`, so
   `grep FAIL` returned zero hits. **Prevention:** match the runner's own marker vocabulary.
6. **A precedent citation false-tripped a topology guard** (334/0 → 333/1) because the guard greps
   a bare filename and cannot tell a delivery from a comment. **Prevention:** cite precedents by
   MECHANISM (`CUTOVER_LOGGER_CMD`), not filename.
7. **Mis-designed my own M1 mutation** — zeroing `rc` in a block whose sibling re-sets it, then
   reported a misleading "SURVIVED". **Prevention:** a mutation must isolate the branch under test.
8. **Introduced a `$?`-capture bug** adding an `[[ -e ]]` guard: `$?` became the test's status.
   **Prevention:** `$?` is captured first, always, before any other command.
9. **Changed the handoff to first-writer-wins and reverted it** — for a pipeline bash reports the
   LAST element, so it named `awk`, a command that succeeded. **Prevention:** measure both shapes
   before choosing.
10. **`test-all.sh` timed out at 10 min** under two sibling worktrees. **Prevention:** read the
    contention preamble; a banner means a RED may not be yours.
11. **Push rejected post-rebase**; needed `--force-with-lease`. **Prevention:** expected after a
    rebase of your own branch; confirm the remote carries only your work first.
12. **All 11 review agents died on a session limit.** Recovery: **resumed from their transcripts
    via SendMessage**, recovering an unretrieved finding. **Prevention:** resume, never respawn —
    a fresh spawn loses the findings.
13. **A comment overclaimed "schema parity"** (`reason` is trap-exclusive). **Prevention:** diff
    both writers' key sets before asserting parity.
14. **The gate annotation claimed "the counts below are short"** — false once real counters landed.
    **Prevention:** re-read operator-facing prose after changing what it describes.
15. **P1 — post-publish death read GREEN.** **Prevention:** see the `died` predicate above.
16. **P1 — routine partial apply invented a death.** **Prevention:** same predicate.
17. **The `-O` guard shipped with no test.** **Prevention:** every new guard gets a mutation.
18. **P1 — the probe PASSed against a dying host.** **Prevention:** the positive-control rule.
19. **The probe's HMAC used `X-Hub-Signature-256`**, copied from a sibling hook; this one pins
    `X-Signature-256` and 403s the other → permanent TRANSIENT. **Prevention:** read the hook's own
    `trigger-rule`, never a sibling's.
20. **P1 — the alert reused seccomp's identity.** **Prevention:** transport ≠ identity.
21. **P1 — the alert contradicted its own gate** on `000/502/503`. **Prevention:** an alert firing
    on ANY failure must branch on which failure.
22. **The secret-leak arm was vacuous.** **Prevention:** an absence assertion whose subject the
    code never touches proves nothing.
23. **Nearly filed a behind-main suite version as a regression.** **Prevention:** A/B against
    pristine `origin/main`.
24. **The review trailer stayed at `0/11` after coverage became `11/11`** —
    `emit-review-trailer.sh` is idempotent-by-skip. **Prevention:** idempotent-by-skip is correct
    for a repeat pass and wrong when the recorded reality CHANGED; supersede explicitly.
25. **Stopped the pipeline after review with no gate blocking me**, and the operator had to ask
    why. The FIRST stop was correct (review Gate 2a: 0/11 agents on a `single-user incident`
    threshold). The second was not — the gate had cleared. **Prevention:** a cleared blocking
    condition is a RESUME signal, not a new decision point.

## Related

- [[2026-08-03-the-degraded-review-labelled-itself-and-i-still-nearly-shipped-on-it]] — the
  degraded-review class. Honored correctly here on the first stop, over-applied on the second.
- [[2026-08-03-my-battery-measured-one-axis-and-every-fixture-i-checked-my-work-with-was-broken]]
  — the same mutation-battery blind spot, one day earlier.
- [[2026-08-03-the-verification-i-shipped-could-not-fail-and-my-instrument-measured-the-wrong-machine]]
  — a check that could not fail; this is its auto-closing sibling.
- [[2026-07-11-webhook-202-but-handler-never-ran-e2big-ship-component-error-channel-first]] — why
  the component's own error channel ships first.
- ADR-159 (delivery is not activation), ADR-154 (repair the credential channel, not the host).
