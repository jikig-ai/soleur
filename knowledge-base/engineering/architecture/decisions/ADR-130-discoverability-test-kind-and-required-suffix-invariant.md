---
title: "discoverability_test.kind: live-probe vs run-log, and the *-required suffix as an enforceable invariant"
status: accepted
date: 2026-07-20
issue: 6774
supersedes: null
---

# ADR-130: `discoverability_test.kind`, and the `*-required` suffix as an enforceable invariant

## Context

Two guards were found asserting a property they could not verify. They are
recorded in one ADR because they share a defect class — **a check that certifies
a different property than the one it names** — not because they share an
enforcement mechanism. They do not: the first is enforced by preflight Check 10's
guardrails, the second by a parity test over the ruleset surfaces.

### Check 10 cannot verify a run-triggered emitter (#6774)

`plugins/soleur/skills/preflight/SKILL.md` Check 10 rejects every shell-active
token — including `|` — before executing `discoverability_test.command`. That is
correct as injection defence: the plan file is trust-on-PR-review and the command
is handed to `bash -c`.

The consequence is that **no log-grep discoverability test can ever pass**, and
log-grep is the only way to observe an emitter that fires *during a run* rather
than *at an endpoint*. Check 10 assumes a **live probe** — a command that hits a
running endpoint and returns a comparable value, which fits
`curl https://app.soleur.ai/api/inngest`. It does not fit a **run-triggered
emitter**: `SOLEUR_WORKSPACES_LUKS_FSCK` exists only in the log of a cutover run
that has already happened. There is no endpoint to probe.

The blocker is commonly stated as "the pipe". That is not the decisive
constraint. The canonical failing command is
`gh run view <run-id> --log | grep MARKER`, and **`<run-id>` has no subject at
preflight time** — the run has not happened. A perfect argv-based pipeline
executor still could not run it.

Rewriting such a plan's command to be pipe-free would make the gate green while
verifying a **different property** (e.g. "`luks-monitor` is allowlisted in
`vector.toml`" proves routing, not that the marker is emitted or readable). That
is the failure class this work exists to remove, so it was rejected rather than
done.

### The `*-required` suffix claimed teeth it did not have (#6766, #6480)

Three jobs carry the `-required` suffix. `tenant-integration-required` and
`sentry-destroy-required` are in the ruleset's required-contexts list;
`infra-validate-required` is **not**. The suffix therefore reads as a convention
that one member silently breaks — a job name asserting a property it does not
have.

The naive remedy is a trap. `infra-validation.yml` is `pull_request`-path-filtered
with no `merge_group:`, and **a path-filtered workflow posts no status context at
all on a PR it does not match**. A required context that never posts sits at
*"Expected — Waiting for status"* forever, wedging every PR in the repository.
Membership is necessary but not sufficient; **postability** is the other half.

## Decision

### 1. The observability contract gains an explicit kind discriminator

`discoverability_test` accepts an **indented** `kind:` sub-field:

- `kind: live-probe` (or absent) — today's behaviour, byte-for-byte.
- `kind: run-log` — Check 10 returns **SKIP with the marker recorded**, instead
  of a false FAIL.

A gate that cannot observe a property must say *which* property it declines to
observe, and must still assert the checkable remainder. `run-log` is therefore
constrained by seven fail-closed guardrails:

1. Absent `kind` ⇒ `live-probe`. Every existing plan is unaffected.
2. Unknown `kind` value ⇒ **FAIL** (not SKIP, not default).
3. `kind: run-log` requires `marker:` matching `^[A-Za-z0-9_]+$` ⇒ else FAIL.
4. The marker must exist in the codebase **outside planning artifacts** —
   `git grep -F -- "$MARKER" -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'`
   non-empty, else FAIL. The exclusion is load-bearing: the declaring plan is
   itself in the tree, so without it the check is vacuous.
5. The `command` must contain the marker literal under `run-log`, else FAIL — so
   `run-log` cannot certify a command unrelated to the marker.
6. A `kind` token present but unparseable ⇒ FAIL. `kind` is **Form A only**; a
   prose `Kind: run-log` in a Form B block fails loudly rather than silently
   defaulting.
7. `marker:` without `kind: run-log` ⇒ FAIL.

**The SSH reject is never bypassed.** It runs unconditionally for both kinds.
This required splitting the existing fused `rejectReason` into `sshRejectReason`
(always) and `substRejectReason` (live-probe only) — without the split,
`kind: run-log` + `ssh host 'grep MARKER …'` would return SKIP, defeating
`hr-no-ssh-fallback-in-runbooks`. That would have been a **larger** downgrade
than the one direction 3 was rejected for.

Guardrails 4 and 5 together are what make this not a downgrade: they verify that
a real emitter exists and that the command actually names it.

### 2. The `*-required` suffix is promoted from convention to enforced invariant

A parity test asserts, for every `jobs:` child whose effective context name ends
in `-required`:

- **membership** in all three surfaces — `infra/github/ruleset-ci-required.tf`,
  `scripts/ci-required-ruleset-canonical-required-status-checks.json`, and
  `scripts/required-checks.txt`; and
- **postability** — its workflow has no `pull_request.paths:` key and does
  declare `merge_group:`.

**No exemption allowlist is introduced.** An exemption list would recreate the
defect class: a guard certifying that the members it chose to look at are fine.
The enforcement is only honest once `infra-validate-required` is genuinely
required, which is why the ruleset flip (#6480, #6766) ships alongside it rather
than after.

### Caveat, recorded

The aggregator observes **job** results, so a `continue-on-error` step inside
`deploy-script-tests` stays invisible to it. This is a pre-existing property of
`infra-validation.yml`, not a regression introduced here.

## Alternatives Considered

### For decision 1 (#6774)

**Direction 1 — allow a safe-listed pipeline shape** (a single `| grep <literal>`
executed via argv rather than `bash -c`). **Rejected.** The blocker is not the
pipe, it is the absence of a subject: `<run-id>` does not exist at preflight
time. A perfect argv executor still cannot run the command. It also adds a second
execution mode — new attack surface — for zero coverage gain.

**Direction 3 — leave Check 10 live-probe-only and make the SKIP explicit.**
**Rejected.** With no field, Check 10 must *infer* "this is a run-log test" from
the command's shape — which is exactly the "gate implicitly drawing a
distinction" problem the issue names. It cannot record the marker, so nothing
downstream can assert anything. Worst, it degrades toward "any command we cannot
run → SKIP", which **is** the silent downgrade the issue forbids: a genuinely
broken live probe would start passing.

### For decision 2 (#6766)

**Make `deploy-script-tests` itself the required context** (the issue's literal
ask). **Rejected.** It is a 12-minute job that builds an alpine+bubblewrap image;
both existing `-required` precedents are cheap static-named `if: always()`
aggregators. Intent is preserved by making `infra-validate-required` the required
context and folding `deploy-script-tests`' result into it — so its redness still
blocks merge, without putting a 12-minute build on every PR's critical path.

**Flip the ruleset first** ("lowest risk, stops the bleeding", per the issue).
**Rejected as inverted.** Executed as written this is a repo-wide delivery
outage, not a low-risk edit — see Context. The enabling work ships first and the
ruleset flip second, after the context is empirically observed posting.

**An exemption allowlist in the `*-required` detector.** **Rejected** — it would
recreate the "guard that claims teeth it lacks" defect class the ADR exists to
close.
