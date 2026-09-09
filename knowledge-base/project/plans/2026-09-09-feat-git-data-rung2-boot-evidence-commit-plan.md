---
title: "feat(git-data): commit the rung-2 boot evidence that releases the birth hold"
date: 2026-09-09
slug: feat-git-data-rung2-boot-evidence-commit
branch: feat-one-shot-git-data-rung2-boot-evidence
issue: 7025
lane: cross-domain
type: enhancement
closes: none
priority: p1
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

No `spec.md` exists for this branch, so `lane:` had no source to carry forward and was
defaulted to `cross-domain` (TR2 fail-closed). The Phase 2.5 sweep is the real scope signal:
engineering-only.

## Enhancement Summary

**Deepened:** 2026-09-09. **Reviewed by:** a five-agent plan-review panel (DHH, Kieran,
code-simplicity, architecture-strategist, spec-flow-analyzer) plus a learnings sweep. Every
finding below was verified against the repository before being applied.

1. **The exit-path table was incomplete in the dangerous direction.** `rc=2` has two arms and
   the plan mapped one: the DERIVATION FAULT arm is explicitly *"deterministic, NOT transient"*,
   so the prescribed remedy (widen the window) was wrong for it. `rc=78` and the case where
   `doppler run` fails before `exec` — printing **no** `RUNG2_CAPTURE_VERDICT` line at all — were
   both unmapped. All are now routed, and the widening ladder has a floor.
2. **The gate was to be called differently from how CI calls it.** CI passes one argument and
   lets the gate derive the evidence path; the plan passed two, which can verify a different file
   than the one CI checks. Now one argument everywhere.
3. **AC3's "load-bearing" observation is not merge-blocking.** `deploy-script-tests` is absent
   from `scripts/required-checks.txt` and `main` is not branch protected, so a red freshness
   check would not stop a merge. Stated plainly rather than implied.
4. **AC4 would have failed for a benign reason.** Its filter allowed only `plans|specs`, but the
   ship phase also commits `knowledge-base/INDEX.md` and a learning — verified on `723ab68b5`,
   and reproduced in this very session when the pre-commit hook swept `INDEX.md` in. Widened.
5. **AC2 masked its own failure mode.** `live="$(...)"` swallows the return code, leaving the
   ABORT text in the variable and printing nothing — indistinguishable from a stale hash. Now
   mirrors the gate's own `if !` form, and runs after `git fetch origin main` so it tests the
   risk it claims to (a change landing on `main`).
6. **AC5 was a weaker second scanner.** `gitleaks` already runs as a required check and this file
   is a new tracked `.env` under `apps/` that `.gitleaks.toml` does not allowlist. AC5 now asserts
   that gate plus one targeted residual check, and Phase 3 runs gitleaks locally first.
7. **The plan claimed to follow a runbook sequence it does not follow.** The runbook's
   `## After a PASS` path downloads the run's artifact; no artifact exists, so this captures
   locally and post-hoc from the S3 archive. That weakens auditability and is now disclosed in
   the PR body rather than papered over.
8. **The ACs could all pass while the PR body's central claim went unchecked** — the evidence
   file records queries, not rows. **AC7** added for `nft_metadata_drop`, the one measured
   boolean and the sole basis for the #7772 claim.
9. **The journey ended at "mark ready."** Push, CI observation, CPO sign-off, and a post-merge
   verification phase were missing entirely. Added.
10. **The divergence set was justified circularly** (from the gate's own allowlist — the exact
    tautology the capture refuses by name). Re-derived from what the rehearsal root actually
    binds in `rehearsal.tf`.

Two challenges to the brief's prescribed command were **not** applied and are recorded for a
decision in `decision-challenges.md`: `--window '7 DAY'` versus the script's `30 DAY` default,
and whether `--out` should be dropped (its default is absolute and cwd-independent).

## Overview

Produce, and commit in a PR of its own, exactly one file:
`apps/web-platform/infra/git-data-rung2-boot-evidence.env`.

That file's presence is the release condition for `git_data_rung2_rehearsal_gate`
(`tests/scripts/lib/git-data-birth-readiness-gate.sh`). It is the **last remaining machine
hold** on the birth of the git-data host — the host that will store every connected user's
source code. Verified rather than assumed: the birth job `git_data_host_create` in
`.github/workflows/apply-web-platform-infra.yml` sources exactly two interlocks, and the
sibling `git_data_birth_readiness_gate` has already RELEASED — its release condition,
`grep -vE '^[[:space:]]*#' cloud-init-git-data.yml | grep -c 'sentry_dsn'`, measures **2**.

The file is produced **by the capture script**,
`scripts/followthroughs/git-data-rung2-evidence-capture.sh`, and never by hand. The capture
writes its own header stating why it is not auto-committed:

> a route that writes its own gate-releasing evidence is self-approving.

That is why this is a PR and not an auto-commit. Merging it is the second of the two
intentional human gates on the git-data birth; this PR is that gate.

The rehearsal being attested is Actions run `33888071954` (2026-09-04, host
`soleur-git-data-rehearsal-33888071954`). It is **reused, not re-run**: the evidence hash binds
the rehearsal to the cloud-init that would ship today, and that binding still holds.

**What this PR converts.** Before merge the birth is held by two mechanisms, one machine and
one human. After merge it is held by one: the `web-platform-infra-apply` environment approval
on the birth job, plus prose in a different file. That approval is documented in the job's own
comment as approving *before any step runs* — "what they are authorizing is the dispatch, not
its contents" — and the `BIRTH-GIT-DATA` confirm token is explicitly a typo guard, not
authorization. So the reviewer of this PR is the last technical control that reads anything.
This is the designed end state of ADR-149, not a defect, but it is why
`brand_survival_threshold` is `single-user incident` here.

Scope is one file. This PR is deliberately separate from the open PR #7999.

## Research Insights

### Premise Validation (Phase 0.6)

| Reference | Probe | State |
|---|---|---|
| `apps/web-platform/infra/git-data-rung2-boot-evidence.env` | `ls` at branch tip | **ABSENT** — the hold is binding |
| PR #7999 | `gh pr view` | OPEN, not draft — "fix(observability): a stale SQL API connection returns the same 701 as a source that never stored" |
| PR #8002 | `gh pr view` | OPEN, draft, on this branch |
| Issue #7025 | `gh issue view` | OPEN — owns rung 2, and separately owns clearing the DO-NOT-DISPATCH banner, which this PR does **not** do |
| Issue #7204 | `gh issue view` | OPEN — "git-data rung-2 rehearsal dies at stage:luks_open …" |
| Issue #7772 | `gh issue view` | CLOSED — the metadata-egress control shipped |
| Sibling interlock `git_data_birth_readiness_gate` | non-comment `sentry_dsn` count in the cloud-init | **2** → already RELEASED |
| `.gitignore` vs the evidence path | `git check-ignore -v` | exit 1 — **not ignored**. the bare `.env` entry (directly above `_site/`) matches only a file literally named `.env`, so `git add` will work |

Verified by the lead and **not** re-derived here: the user_data hash at this branch tip
(`723ab68b5`) equals `3a2392fb5b0d4fae9d4abeaf5ca10ee682430e473dd9eac1ca3d340ef4ce1725`, and
the divergence list is the `REHEARSAL_DIVERGENCE` literal in
`.github/workflows/git-data-rung2-rehearsal.yml`.

### Property List (Phase 0.6b)

1. `git_data_rung2_rehearsal_gate` stops returning HOLD, so the birth route becomes
   dispatchable.
2. The claim released against is auditable by someone who was not present.
3. The release is a deliberate act of a person, not a side effect of a route writing about
   itself.
4. The release is self-invalidating: if anything that ships to the host changes afterwards, the
   gate re-holds without anyone remembering to check.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | What already covers it |
|---|---|---|
| Re-dispatch the rung-2 rehearsal | (1), (2) | The 2026-09-04 run passed and its hash still binds. A re-run costs a live paid host (~€0.02, ~8 min per the runbook) plus another environment approval, and attests the same bytes. **Cut.** |
| A bespoke freshness check on the committed evidence | (4) | `.github/workflows/infra-validation.yml`'s `Rung-2 evidence freshness (active only once evidence exists)` step is dormant while the file is absent and arms itself the moment it lands. **Cut.** |
| A hand-written or hand-edited `.env` | (1) | Refused by AC1 and by the whole point of the capture. **Cut.** |
| A hand-rolled secret-regex battery in the ACs | exposure control | `.github/workflows/secret-scan.yml` (gitleaks, pinned, blocking on every `pull_request`) already scans this diff. AC5 asserts *that* gate rather than competing with it. **Cut to a targeted residual check.** |
| Transcribing the gate's assertion list into the plan | (1) | The gate is executable and is the authority. `git-data-rung2-rehearsal.md` states the repo convention verbatim: source-of-truth flags "are not restated here, because a second copy drifts." **Cut.** |
| A new ADR | (3) | ADR-149 already records the interlock and its release condition; this satisfies a precondition rather than deciding anything. **Cut** — see Non-Goals for the disposition-row follow-up. |

### Derivation of the divergence set

The eight tokens are **not** derived from the gate's allowlist — that reasoning is the
allowlist-subset-of-allowlist tautology the capture refuses by name. They are derived from what
the rehearsal root actually binds: `apps/web-platform/infra/rung2-rehearsal/rehearsal.tf`,
`module "git_data_userdata"`, the block under the anchor comment `# MAY DIVERGE — identity only.`
That block passes exactly `host_name`, `git_data_volume_id`, `git_data_luks_volume_id`,
`doppler_token`, `doppler_config_name`, `git_transport_pubkey`, `git_provision_pubkey`,
`git_remove_pubkey`. The rehearsal workflow's `REHEARSAL_DIVERGENCE` literal is the same set,
and that literal is what Phase 2 transcribes.

### Verified caveat: `boot_complete`'s booleans

Checked against `apps/web-platform/infra/git-data-bootstrap.sh` rather than restated.

The `boot_complete` emit passes `luks_mounted=yes`, `repo_root=yes`, `hooks_path=yes` and
`provision=yes` as **hardcoded string literals**. The file's own comment above the emit says so:
*"The booleans are all `yes` by construction here; they are emitted because the CONSUMER asserts
on them, so a weakened assert shows up as a false rather than a missing event."*

`nft_metadata_drop` is the **exception** and is genuinely measured: it lists the live chain
`inet soleur_git_data output` and greps it for the link-local metadata address
`169.254.169.254`, defaulting to `no` when `nft` is absent. The in-file comment explains the
anchor: it is anchored on the `daddr`, not the table name, because a table that exists with its
rule flushed is exactly the state being tested for.

The capture's own PASS line carries this caveat, having been rewritten specifically because
"with all four assertions positive" overstated what was checked.

### Authorities read

- `tests/scripts/lib/git-data-birth-readiness-gate.sh` — `git_data_rung2_rehearsal_gate` and
  `git_data_rung2_user_data_sha256`. **The gate is the authority on its own assertions; this
  plan does not transcribe them.** Note that `git_data_rung2_user_data_sha256` carries roughly
  ten of its own fail-closed ABORTs (a payload-count floor of 9, a single-`templatefile` shape
  check, a basename-collision check), any of which also produces HOLD.
- `scripts/followthroughs/git-data-rung2-evidence-capture.sh` — argument parsing and its four
  write-time refusals, the `EXIT` trap that prints `RUNG2_CAPTURE_VERDICT`, the
  `remote(...) UNION ALL s3Cluster(primary, ...) WHERE _row_type = 1` source expression, the
  DERIVATION FAULT arm, and the output writer.
- `apps/web-platform/infra/git-data-bootstrap.sh` — the `boot_complete` emit site.
- `.github/workflows/infra-validation.yml` — the dormant-until-armed freshness step, in job
  `deploy-script-tests`.
- `.github/workflows/apply-web-platform-infra.yml` — job `git_data_host_create` and its two
  interlocks.
- `apps/web-platform/infra/rung2-rehearsal/rehearsal.tf` — the divergence derivation above.
- `scripts/required-checks.txt` — see AC3.
- `.gitleaks.toml` and `.github/workflows/secret-scan.yml` — see AC5.
- `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md` — **this plan
  deliberately does NOT follow its `## After a PASS` sequence.** That sequence is
  `gh run download <run-id> -n git-data-rung2-boot-evidence`, which assumes a PASS artifact
  exists. None does: the 2026-09-04 in-workflow capture reported TRANSIENT ×20 against a stale
  SQL API connection, so it never wrote one. This plan re-captures locally, post-hoc, from the
  S3 archive instead. See Risks — this is a real, disclosed weakening of Property (2).

### Principles satisfied

- **AP-024** (*a verification surface does not actuate*) — the capture senses, adjudicates and
  publishes a verdict, then refuses to commit: *"This file is NOT committed by this script and
  must NOT be committed by a workflow."* This plan supplies the separate, independently
  credentialed human write.
- **AP-026** (*additive evidence must not gate*) — the freshness step fails only on a malformed
  or stale artifact it was handed, never on a missing one. That is why the dormant branch is
  correct rather than lax.

### Open Code-Review Overlap

None. 64 open `code-review` issues were listed; none names `git-data-rung2-boot-evidence`.

### Deepen-pass live verification

Attribution claims probed against `origin/main` rather than carried from the brief:

| Claim | Probe | Result |
|---|---|---|
| `723ab68b5` is the tip the hash was computed at | `git merge-base --is-ancestor 723ab68b5 origin/main` | ancestor — yes |
| PR #7999 corrects the capture's message | `gh pr view 7999 --json files` | touches `scripts/followthroughs/git-data-rung2-evidence-capture.sh` — confirmed |
| #7999 is "preferred but not required" | its 71-line diff grepped for `REHEARSAL_DIVERGENCE`, `--window`, `--out`, `--host-name`, `--evidence-url`, `RUNG2_*` | **zero hits** — it moves nothing this plan depends on. It also touches `.github/workflows/git-data-rung2-rehearsal.yml`, but not the `REHEARSAL_DIVERGENCE` literal, and the workflow is not an input to the user_data hash. Verified, not assumed. |
| No prior attempt at this evidence file to reconcile | `git log --all -- apps/web-platform/infra/git-data-rung2-boot-evidence.env` | empty — the file has never existed on any ref |
| Every AGENTS rule id cited in this plan is active | each id grepped for `[id: <id>]` in `AGENTS.md` | all active; none retired or fabricated |

### Institutional learnings applied

A learnings sweep of `knowledge-base/project/learnings/` surfaced one finding that changed this
plan, plus two that confirmed existing choices.

- **Changed the plan.** *"When a plan's ACs can all pass without the reported symptom being
  closed, the ACs are measuring the implementation rather than the defect."* AC1–AC6 verify the
  file's shape and the gate's verdict; none of them substantiates the PR body's claim about the
  five booleans, because the evidence file records the *queries* and not the *rows*. **AC7 was
  added** and the PR body's "What the rehearsal proved" paragraph was split so the strong claim
  (boots to completion, nothing fatal) is separated from the one that needs a human read
  (`nft_metadata_drop`).
- **Confirmed.** *"A guard that cannot fail is indistinguishable from one that passed."* AC3 is
  falsifiable by construction here: the freshness step is provably in its dormant branch today
  (the file is absent) and must move to its armed branch on this PR. The HOLD→RELEASED
  transition is itself the proof that the predicate can fire.
- **Confirmed.** *"Accepting a plausible-looking artifact without confirming it is the artifact
  asked for."* `RUNG2_SENTRY_CROSSCHECK` must be read from the file, never inferred from the
  absence of a complaint — AC1 greps for the literal `CLEAN` line.

## User-Brand Impact

**If this lands broken, the user experiences:** a git-data host born from a cloud-init whose
boot was never actually proven — the store holding every connected user's source code coming up
with an unmounted LUKS device, a wrong repo root, or the metadata-egress rule not loaded. The
user-visible shape is source code that is missing, unreachable, or resident on the plaintext
volume rather than the encrypted one.

**If this leaks, the user's data is exposed via:** the file lands in a **public** repository.
The vector is the boot telemetry the capture transcribes into the header. Bounded upstream: the
capture refuses any `--host-name` outside `^soleur-git-data-rehearsal-[A-Za-z0-9._-]+$`
precisely because it projects matched rows into a public Actions log, so production
`soleur-git-data` can never be the subject. AC5 is the residual check.

**Brand-survival threshold:** single-user incident.

- `requires_cpo_signoff: true`. Phase 5 step 3 is the step that satisfies it; without a recorded
  sign-off the PR does not move to ready.
- `user-impact-reviewer` runs at review time via the review skill's conditional-agent block.
- What stops being machine-checked on merge is broader than this gate. The *released* sibling
  gate's own message enumerates what it never covered: Doppler scope reachability, address
  registration, the post-apply signal, `GIT_DATA_SSH_HOST` production, the firewall-attachment
  entailment, DC-2's mandated replacement, and clearing the banner. None of those is
  machine-checked anywhere.

## Domain Review

**Domains relevant:** engineering

All eight domains were assessed in one pass. Product, Marketing, Sales, Finance, Legal,
Operations and Support have no implication: one machine-generated evidence file consumed by a CI
gate, no user-facing surface, no revenue or cost line, no personal data, no new vendor.

### Engineering

**Status:** reviewed inline. The technical fork was settled by the lead and re-deriving it would
spend a paid host, so no leader spawn was warranted (`hr-technical-fork-is-not-an-operator-question`).
Five plan-review agents did examine it; their findings are applied throughout.

**Assessment:** high blast radius for a one-line diff, because the diff *is* a release
condition. The controls that make it safe already exist and were read: the gate re-derives the
hash and refuses stale evidence; the divergence allowlist is closed and identity-only; the
evidence URL must name an Actions run in this repository; every required key must appear exactly
once. The residual risk is the *interval* between capture and merge, plus the fact that the
freshness check is observable but not merge-blocking (AC3).

### Product/UX Gate

Not applicable — `## Files to Create` is one `.env`; no route, component or layout is touched.
**Tier:** none.

## Gate assessments that did not fire

GDPR (2.7): no regulated-data surface and no new distribution channel — the repository was
already public. IaC routing (2.8): no infrastructure, no `.tf`, no secret write, no apply step.
ADR/C4 (2.10): no architectural decision; no new external actor, system, container, or access
relationship, and no change to the cardinalities `model.c4` embeds. Encryption Posture (2.11):
no new store or cross-component connection — `scripts/encryption-posture-ledger.json` already
carries separate git-data and rung2-rehearsal entries and this PR moves neither. Guard Contract
(2.12): no guard is written, widened, or relaxed; this supplies an existing guard an input.

## Observability

This PR adds no runtime surface. Every mechanism below already exists; the block cites them
rather than proposing anything new.

```yaml
liveness_signal:
  what: "the `Rung-2 evidence freshness (active only once evidence exists)` step in .github/workflows/infra-validation.yml, job deploy-script-tests — it sources the gate library and runs git_data_rung2_rehearsal_gate against the merge tree"
  cadence: "every pull request touching apps/*/infra/**, plus every push to main"
  alert_target: "a visible check conclusion on the PR — NOT a merge block: deploy-script-tests is absent from scripts/required-checks.txt and main is not branch protected"
  configured_in: ".github/workflows/infra-validation.yml"
error_reporting:
  destination: "GitHub Actions ::error:: annotation on the infra-validation job, plus the gate's own HOLD text on stdout naming the specific refusal"
  fail_loud: true
failure_modes:
  - mode: "a later change to the cloud-init or any of the nine file()-bound payloads invalidates the committed hash"
    detection: "the gate re-derives the live hash with git_data_rung2_user_data_sha256 and prints STALE EVIDENCE naming both hashes"
    alert_route: "red freshness check on the PR that made the change, and the birth job refuses to proceed"
  - mode: "the evidence file is hand-edited in a later PR — a duplicated, removed, or `export `-decorated key"
    detection: "the gate's exactly-once cardinality loop over the four required keys"
    alert_route: "red freshness check; the birth job refuses to proceed"
  - mode: "RUNG2_VAR_DIVERGENCE emptied, or widened past the identity-only allowlist"
    detection: "the gate refuses an empty or whitespace-only value, and refuses any token outside GIT_DATA_RUNG2_DIVERGENCE_ALLOWLIST under set -o noglob"
    alert_route: "red freshness check; the birth job refuses to proceed"
  - mode: "the file is deleted"
    detection: "the freshness step returns to its dormant branch and the birth job's gate call returns HOLD"
    alert_route: "the birth job refuses to proceed — no silent pass is reachable, which is AP-026's shape"
logs:
  where: "GitHub Actions run logs for infra-validation (PR and push-to-main) and for apply-web-platform-infra's git_data_host_create job"
  retention: "GitHub default log retention"
discoverability_test:
  command: "bash -c 'source tests/scripts/lib/git-data-birth-readiness-gate.sh && git_data_rung2_rehearsal_gate apps/web-platform/infra/cloud-init-git-data.yml'"
  expected_output: "a line beginning `git_data_rung2_rehearsal_gate: RELEASED` (it continues with the URL and the declared divergence, then a NOTE), exit 0"
```

The probe takes **one argument, not two** — mirroring the CI call exactly and exercising the
gate's own `$(dirname "$cloud_init")/git-data-rung2-boot-evidence.env` derivation. Passing the
evidence path explicitly would verify a different file than CI checks. No credentials are
required; the gate reads only files in the working tree.

## Files to Create

- `apps/web-platform/infra/git-data-rung2-boot-evidence.env` — written by the capture script,
  never authored or edited by hand.

## Files to Edit

None directly. The pre-commit hook sweeps `knowledge-base/INDEX.md` in alongside the planning
artifacts (a file-count header bump plus two list rows), which is why AC4 filters on
`knowledge-base/` rather than asserting a bare one-file diff.

## Implementation Phases

### Phase 1 — Preconditions (mechanical, read-only)

Run as commands, not as prose confirmations:

```bash
git rev-parse --show-toplevel                       # must be this worktree; --out is relative
test ! -e apps/web-platform/infra/git-data-rung2-boot-evidence.env
git fetch origin main
git status --short                                  # clean apart from planning artifacts
grep -vE '^[[:space:]]*#' apps/web-platform/infra/cloud-init-git-data.yml | grep -c 'sentry_dsn'   # 2
```

The last line re-probes the sibling interlock. This plan and the PR body both claim it has
released; that claim is asserted here rather than remembered.

Do **not** re-run the hash computation and do **not** re-extract the divergence list.

### Phase 2 — Produce the evidence file with the capture

From the worktree root:

```bash
DIV=host_name,git_data_volume_id,git_data_luks_volume_id,doppler_token,doppler_config_name,git_transport_pubkey,git_provision_pubkey,git_remove_pubkey

env -u DOPPLER_TOKEN doppler run -p soleur -c prd_terraform -- \
  bash scripts/followthroughs/git-data-rung2-evidence-capture.sh \
    --host-name soleur-git-data-rehearsal-33888071954 \
    --evidence-url https://github.com/jikig-ai/soleur/actions/runs/33888071954 \
    --window '7 DAY' --divergence "$DIV" \
    --out apps/web-platform/infra/git-data-rung2-boot-evidence.env
```

Expected: `RUNG2_CAPTURE_VERDICT=0`, the file containing `RUNG2_BOOT_REHEARSAL=PASS` and
`RUNG2_SENTRY_CROSSCHECK=CLEAN`, and a stdout PASS line carrying the hardcoded-booleans caveat.

**`--since` is deliberately omitted**, matching the brief. There is no apply timestamp for a
reused 5-day-old run to pin it to. The consequence is real and accepted: `_sentry_window_args`
falls back to a window-derived `--stats-period`, the script prints its "NOT pinned to this run"
warning, and the Sentry read is **wider** than the workflow's would be. If an earlier attempt of
run 33888071954 left a fatal in Sentry inside that window, the consult returns FATAL and the
capture refuses to write — fail-closed, and the remedy is to pass `--since` pinned just after
the 2026-09-04 boot, not to re-dispatch.

#### Every exit path, and where each one leads

The trap prints `RUNG2_CAPTURE_VERDICT=<rc>` on every path the script itself takes. Route by it:

| Signal | Meaning | Action |
|---|---|---|
| `=0` | PASS. The file is written. | Continue to Phase 3. |
| `=1` | FAIL — the host reported a fatal. | **Stop, do not commit.** File an issue titled `fix(git-data): rung-2 rehearsal 33888071954 reports a fatal on re-read`, label `type/infra`, and leave PR #8002 draft with a comment naming the issue. Do not re-dispatch. |
| `=2` **and** the output says `TRANSIENT` | No verdict. The rows live only in the S3 archive, so a too-narrow window is indistinguishable from a dark boot. | **Widen**: `--window '30 DAY'`, then `'2 MONTH'`. Read the TRANSIENT text first — the `<var> is unset` arm is a credential problem that widening cannot fix, and the control-read-also-failed and account-wide-dark arms (#7811) are not window-shaped either. **Floor:** if `2 MONTH` still returns TRANSIENT, stop, do not commit, and file against #7811. Never re-dispatch a rehearsal on a TRANSIENT reading — that spends a live paid host on a query problem. |
| `=2` **and** the output says `DERIVATION FAULT` | **Not transient.** The script's own words: *"deterministic, NOT transient … re-dispatching reproduces it identically, so do not wait for it to clear."* The render inputs or the module payload set are unresolvable in this tree. | **Do not widen and do not retry.** Read the fail-closed diagnostic, which names the offending file, and fix the tree. |
| `=64` | An argument refusal. | Read it. The host-name, evidence-url and window refusals fire *before* any network call; the `--divergence` refusal fires on the PASS path *after* every query has run, so it costs the full read. |
| `=78` | The xtrace-with-live-credential refusal. | Disable shell tracing and re-run. |
| **No `RUNG2_CAPTURE_VERDICT=` line at all** | `doppler run` failed before exec, so the trap never armed. This is the exact ambiguity the sentinel exists to remove. | Treat as a wrapper failure, never as a rehearsal FAIL. Check the Doppler token, project and config, then re-run. |

`RUNG2_SENTRY_CROSSCHECK` has five reachable values: `CLEAN`, `FATAL`, `UNAVAILABLE`, and
`NOT_RUN` (the `${_SENTRY_VERDICT:-NOT_RUN}` default). **Only `CLEAN` proceeds.** AC1 requires it,
and there is no waiver path in this plan: `UNAVAILABLE` and `NOT_RUN` mean the second channel did
not run or could not be trusted, and at this threshold that is a stop-and-re-capture with the
Sentry reader available, not a note in the PR body.

Do not edit the produced file — not whitespace, not a comment. If it is wrong, re-run the
capture. If a re-run is needed after a file already exists, delete it first so Phase 1's
`test ! -e` precondition is honest.

### Phase 3 — Verify before committing

```bash
# 1. The gate, called exactly as CI calls it (one argument).
source tests/scripts/lib/git-data-birth-readiness-gate.sh
git_data_rung2_rehearsal_gate apps/web-platform/infra/cloud-init-git-data.yml

# 2. gitleaks, locally, before pushing — this is a REQUIRED check and the file is a new
#    tracked .env under apps/, which .gitleaks.toml's allowlist does NOT cover.
gitleaks detect --config .gitleaks.toml --no-git \
  --source apps/web-platform/infra/git-data-rung2-boot-evidence.env
```

`RELEASED` is the pass; a `HOLD` names its own refusal.

**Adjudicating a HOLD.** The gate's STALE EVIDENCE text instructs "re-run the rung-2 rehearsal",
which this plan otherwise forbids. Resolve it by cause, not by reflex:

- Hash mismatch because `main` moved under the branch → rebase onto the fetched `origin/main`
  and re-run Phase 2. The rehearsal itself is still valid if the moved files do not change what
  boots.
- Hash mismatch because a file that genuinely ships to the host changed → the rehearsal is
  legitimately stale and a re-run *is* correct. This is the one case that justifies spending a
  host, and it is an escalation to the lead, not a decision to take inline.
- Any non-hash HOLD (key cardinality, URL shape, divergence) → the file was mangled after the
  capture wrote it. Delete it and re-run Phase 2.

If gitleaks flags anything, stop. Do not widen `.gitleaks.toml` to make it pass.

### Phase 4 — Commit

```bash
git add apps/web-platform/infra/git-data-rung2-boot-evidence.env
git commit -m "feat(git-data): rung-2 boot evidence releasing the birth hold"
```

**Commit the planning artifacts under `knowledge-base/project/{plans,specs}/` BEFORE this
commit**, so the evidence commit is `HEAD` when AC4 runs. Then run AC4.

### Phase 5 — Push, sign off, and mark ready

1. `git push -u origin feat-one-shot-git-data-rung2-boot-evidence`. The branch is currently
   unpushed; nothing before this point exists on the remote.
2. Wait for CI. Read AC3 observation 2 and AC5 explicitly — see AC3 on why waiting for the merge
   queue to enforce them is not sufficient.
3. **CPO sign-off** (`requires_cpo_signoff: true`). Record it as a PR comment naming the
   `## User-Brand Impact` framing above and acknowledging that after merge the birth is held by
   one blind environment approval plus prose. Without this comment the PR does not move to ready.
4. Set PR #8002's body to the draft below and mark it ready.

### Phase 6 — After merge

`wg-after-a-pr-merges-to-main-verify-all`. The merge changes `main`'s gate verdict, so it is
verified rather than assumed:

1. The `push: branches:[main]` run of `infra-validation.yml` is green and its freshness step
   prints `rung-2 evidence is valid for the current template.`
2. Re-run the `discoverability_test` command against `main` and confirm `RELEASED`.
3. Comment on #7025 naming which precondition closed and which remain — specifically that the
   DO-NOT-DISPATCH banner (ADR-149 item 8) is still up and still owns the issue.

## Acceptance Criteria

### Pre-merge

**AC1 — The file exists, has the shape the capture produces, and asserts a clean pass.**

```bash
EV=apps/web-platform/infra/git-data-rung2-boot-evidence.env
head -1 "$EV" | grep -c 'git-data-rung2-evidence-capture.sh'   # 1
grep -c 'self-approving' "$EV"                                 # 1
grep -c '^# Captured (UTC) : 2026-' "$EV"                      # 1
grep -c '^# QUERY:' "$EV"                                      # 3  (anchor + host-rows + Sentry cross-check)
grep -c '^# QUERY_FATAL:' "$EV"                                # 1
grep -c '^RUNG2_BOOT_REHEARSAL=PASS$' "$EV"                    # 1
grep -c '^RUNG2_SENTRY_CROSSCHECK=CLEAN$' "$EV"                # 1
```

> **AC1 amended at /work (2026-09-09):** the `# QUERY:` expectation was authored as `2` and the
> capture emits **3**. ARTIFACT 4 (the Sentry cross-check) writes a `# QUERY:` line too —
> `# QUERY: sentry-issue.sh --host-events … --stats-period 7d` — which the plan-time count
> overlooked. The artifact is correct and was NOT edited; the criterion was wrong and is corrected
> here rather than satisfied by a looser grep. All three lines were enumerated and each is a
> distinct, legitimate artifact query.

**These checks establish the file's SHAPE, not its authorship.** Nothing in this plan proves the
capture wrote it — a forger copies the header first. The `# Captured (UTC)` stamp and the
`# QUERY:` lines are included because they are the parts a hand-forger is least likely to
reproduce faithfully, not because they are proof. The real provenance control is the human
reading this PR. Cite the `self-approving.` sentence as the anchor, never a line number
(`cq-cite-content-anchor-not-line-number`).

`RUNG2_CAPTURE_VERDICT=0` is recorded in Phase 2 as a session-transcript observation. It is
**not** an acceptance criterion — a reviewer cannot check it after the session ends.

**AC2 — The recorded hash equals what the gate's own function computes against the merge tree.**

The capture sets `RUNG2_TEMPLATE_SHA256` from `git_data_rung2_user_data_sha256`, so producer and
consumer share one derivation. This AC covers the residual: a template change landing on `main`
between capture and merge. It therefore runs **after** `git fetch origin main` and a rebase, not
against a stale local HEAD.

```bash
git fetch origin main && git rebase origin/main
source tests/scripts/lib/git-data-birth-readiness-gate.sh
if ! live="$(git_data_rung2_user_data_sha256 apps/web-platform/infra/cloud-init-git-data.yml)"; then
  printf '%s\n' "$live"; exit 1          # the function prints its ABORT on stdout and returns 1
fi
claimed="$(grep -E '^[[:space:]]*RUNG2_TEMPLATE_SHA256[[:space:]]*=' \
  apps/web-platform/infra/git-data-rung2-boot-evidence.env \
  | head -1 | sed 's/^[^=]*=[[:space:]]*//; s/[[:space:]]*$//' | tr 'A-F' 'a-f')"
[[ "$live" == "$claimed" ]] && echo MATCH || echo "MISMATCH live=$live claimed=$claimed"
```

The `if !` form and the extraction pipeline mirror the gate's own code exactly. A bare
`live="$(...)"` swallows the return code, leaving the ABORT paragraph in `$live` and printing
nothing — indistinguishable from a stale hash. Expected: `MATCH`, value
`3a2392fb5b0d4fae9d4abeaf5ca10ee682430e473dd9eac1ca3d340ef4ce1725`.

**AC3 — The gate transitions from HOLD to RELEASED, observed in CI.**

1. *Locally*, the `discoverability_test` command exits 0 and prints a line beginning
   `git_data_rung2_rehearsal_gate: RELEASED`. This is a working-copy proxy.
2. *In CI on this PR*, the `Rung-2 evidence freshness (active only once evidence exists)` step
   logs `rung-2 evidence is valid for the current template.` — **not** its dormant line
   `no rung-2 evidence committed yet — this check is dormant by design (#7025).` — and is green.
   It fires on two independent counts: `on.pull_request.paths` includes `apps/*/infra/**`, and
   the step's job declares neither `needs:` nor `if:`.

Observation 2 is the faithful one — it runs the gate against the tree that would merge. **It is
not a merge gate.** The step lives in job `deploy-script-tests`, which is absent from
`scripts/required-checks.txt` (the register's own AP-024 row says so), and `main` is not branch
protected. A red freshness check would not block `gh pr merge`. **Read the check conclusion
explicitly before merging; do not rely on the queue to enforce it.** That gap is precisely why
this PR is a human gate.

The gate's assertions are not transcribed here — it is executable and is its own authority, and
`git-data-rung2-rehearsal.md` states the convention: a second copy drifts. Note only that a HOLD
can also originate inside `git_data_rung2_user_data_sha256`'s own fail-closed aborts, which are
about the tree rather than the evidence.

**AC4 — The evidence commit contains exactly one changed file.**

```bash
git show --name-only --format= HEAD    # exactly: apps/web-platform/infra/git-data-rung2-boot-evidence.env
git fetch origin main
git diff --name-only origin/main...HEAD | grep -vE '^knowledge-base/' | wc -l   # 1
```

The first command requires the evidence commit to be `HEAD`, which Phase 4 guarantees by
committing the planning artifacts first. The filter excludes all of `knowledge-base/` rather
than just `plans|specs`, because the ship phase also commits `knowledge-base/INDEX.md` and a
learning file on the feature branch — verified on `723ab68b5`, which carries both. Nothing under
`scripts/`, `tests/`, `.github/`, or elsewhere in `apps/` may appear; in particular none of
PR #7999's changes.

**AC5 — No credential or secret material reaches the public repository.**

The binding check is the **`gitleaks scan`** job in `.github/workflows/secret-scan.yml`, which is
a required check and runs on every `pull_request`. `.gitleaks.toml`'s top-level allowlist covers
only `plugins/soleur/skills/.*/test/fixture/\.env\.example$`, so a new tracked `.env` under
`apps/` is scanned by the **full default pack** with no exemption. Phase 3 runs it locally first
so this is not discovered on the remote.

- `gitleaks scan` is green on this PR. **This is the criterion.**
- `.gitleaks.toml` is unmodified in this PR (`git diff --name-only origin/main...HEAD` must not
  list it). Making a red scan pass by widening the allowlist is not an outcome.
- Residual targeted check, for the one thing a shape-based scanner would not flag — that a
  Better Stack source identifier was expanded into the transcribed SQL. Verified upstream:
  `_bs_source` escapes them as the literal tokens `$BS_TABLE` / `$BS_TABLE_S3`, so they reach the
  file unexpanded.

  ```bash
  EV=apps/web-platform/infra/git-data-rung2-boot-evidence.env
  grep -c 'remote($BS_TABLE)' "$EV"                        # 3  — literal, not expanded
  grep -c 's3Cluster(primary, $BS_TABLE_S3)' "$EV"         # 3  — literal, not expanded
  grep -cE 'remote\([0-9]|t[0-9]{6}_soleur' "$EV"          # 0  — no source id, no table name
  ```

  > **AC5 amended at /work (2026-09-09):** the first count was authored as `1` and measures **3** —
  > the anchor, host-rows and fatal queries each carry `remote($BS_TABLE)`. Only the count was
  > wrong; the artifact was not edited. The load-bearing assertion is the LAST line, and it
  > measures `0` as specified — but note its coverage is naming-convention-dependent: the
  > `remote\([0-9]` alternative is dead against this source (the expanded form is
  > `t520508_soleur_git_data_prd_logs`, which does not start with a digit), so all the weight
  > sits on `t[0-9]{6}_soleur`, and that hardcodes a six-digit team id. The positive
  > `$BS_TABLE`/`$BS_TABLE_S3` counts above are the convention-independent half: they assert the
  > tokens SURVIVED unexpanded rather than enumerating what an expansion would look like.

**AC7 — The `nft_metadata_drop` reading is taken by a direct Better Stack read — not from the
capture output, and not from the evidence file.**

The evidence file records the *queries*, not the *rows*. So nothing in it substantiates "all
five booleans were `yes`" — and the capture's PASS predicate does not turn on them either
(`boot_complete` reached, no `level:fatal`). Four of the five are hardcoded literals anyway.

The one that carries information is `nft_metadata_drop`, because it is measured on the host and
it is the entire basis for the #7772 claim in the PR body.

**Neither committed artifact can supply it.** The `.env` records queries rather than rows, and
the capture's `__HOSTROWS__` SELECT projects only `luks_mounted, repo_root, hooks_path,
provision` — the same four its false-assertion arm greps. `nft_metadata_drop` is in the emit
(`git-data-bootstrap.sh`) and in neither reader. So read it directly, record the SQL in the PR
body next to the pasted row, and paste the observed `boot_complete` row.

```bash
# NOT in the .env, and NOT in the capture's stdout — the host-rows SELECT omits it.
# Direct read; record this SQL in the PR body alongside the row.
#   SELECT JSONExtractString(raw,'stage') AS stage,
#          JSONExtractString(raw,'nft_metadata_drop') AS nft_metadata_drop
#   FROM (remote($BS_TABLE) UNION ALL s3Cluster(primary, $BS_TABLE_S3))
#   WHERE host_name = 'soleur-git-data-rehearsal-33888071954' AND stage = 'boot_complete'
# Expect: nft_metadata_drop=yes
```

If the observed value is `no`, the metadata-egress control did not load on that host. The
capture still PASSes (the false arm cannot fire against hardcoded siblings, and this boolean is
not part of its predicate), so **this is a check the human must make** — it is exactly the class
the file cannot self-report. Do not carry the #7772 sentence in the PR body without it.

**AC6 — The PR closes no issue.**

```bash
gh pr view 8002 --json body -q .body | grep -ciE '\b(closes|fixes|resolves) #'   # 0
gh pr view 8002 --json body -q .body | grep -c 'Ref #7025'                       # 1
```

Merging releases a precondition. It does not complete #7025 (which still owns the
DO-NOT-DISPATCH banner) and does not by itself resolve #7204.

### Post-merge

The three checks in Phase 6. `## Post-merge` is not "none": the merge changes `main`'s gate
verdict, and an unverified state change is the thing this whole route exists to refuse.

## PR body (draft)

Body for PR #8002. Written to carry the four mandatory statements and to avoid the ship gate's
checklist-shaped tokens.

---

Commits one file: `apps/web-platform/infra/git-data-rung2-boot-evidence.env`. Nothing else.

**Merging this file RELEASES the git-data birth hold.** While it is absent from `main`,
`git_data_rung2_rehearsal_gate` returns HOLD and the `git_data_host_create` job in
`apply-web-platform-infra.yml` refuses to proceed. The evidence file is deliberately **not**
auto-committed by any workflow, for the reason its own header states: a route that writes its own
gate-releasing evidence is self-approving. This pull request is the human approval — the second
of the two intentional human gates on the birth of the host that will store every connected
user's source code.

**Read this before approving: what is left afterwards.** The sibling interlock
`git_data_birth_readiness_gate` has already released (its release condition, the non-comment
`sentry_dsn` count in the cloud-init, measures 2). So this is the last machine hold. After merge
the birth is held by the `web-platform-infra-apply` environment approval and by prose in the
birth runbook. That approval is documented in the job's own comment as happening *before any
step runs* — "what they are authorizing is the dispatch, not its contents" — and
`BIRTH-GIT-DATA` is a typo guard, not authorization. The already-released sibling gate also
enumerates, in its own message, what it never covered: Doppler scope reachability, address
registration, the post-apply signal, `GIT_DATA_SSH_HOST` production, the firewall-attachment
entailment, DC-2's mandated replacement, and clearing the banner. None of those is
machine-checked anywhere. Reviewing this PR is the last technical read.

**The file was produced by the capture, not written by hand.**
`scripts/followthroughs/git-data-rung2-evidence-capture.sh` wrote it, with the queries that
produced it transcribed into its header. It records `RUNG2_BOOT_REHEARSAL=PASS` and
`RUNG2_SENTRY_CROSSCHECK=CLEAN`. One honest caveat about provenance: it was captured
**locally and post-hoc from the S3 archive**, not downloaded as the rehearsal run's artifact.
The runbook's `## After a PASS` sequence assumes `gh run download`, but the 2026-09-04 run wrote
no artifact — it reported TRANSIENT ×20 against a stale SQL API connection. The only tie from
this file back to that run is the `RUNG2_EVIDENCE_URL` the gate requires to be an Actions run in
this repository, which the gate's own comment is candid does not make the pointer unforgeable.

**The capture's own caveat, because it is the honest reading of this evidence.**
`boot_complete`'s booleans `luks_mounted`, `repo_root`, `hooks_path` and `provision` are
hardcoded literals in `apps/web-platform/infra/git-data-bootstrap.sh` — `yes` by construction at
that point in the script. So this attests that **the final stage was REACHED and that nothing
reported a fatal**, not that four invariants were independently measured. `nft_metadata_drop` is
the exception: it is measured, by listing the live nftables chain `inet soleur_git_data output`
and grepping it for the link-local metadata address, defaulting to `no` when `nft` is missing.

**What the rehearsal proved.** Actions run
[33888071954](https://github.com/jikig-ai/soleur/actions/runs/33888071954), host
`soleur-git-data-rehearsal-33888071954`, reported `stage:boot_complete` with `luks_mounted`,
`repo_root`, `hooks_path`, `provision` and `nft_metadata_drop` all `yes`, and no `level:fatal`
anywhere in the run. Read against the caveat above, that decomposes into two different strengths
of claim, and they should not be blurred:

- **The rendered cloud-init boots to completion on a real Hetzner host, with nothing fatal.**
  This is what the capture's PASS predicate actually asserts, and it is what says the LUKS fix
  tracked in #7204 holds — the run reaches the final stage rather than dying at
  `stage:luks_open` the way the 2026-07-31 rehearsal did.
- **`nft_metadata_drop=yes`, so the metadata-egress control from #7772 loaded.** This is the one
  boolean of the five that is measured rather than hardcoded, and it is therefore the only one
  that carries information. Note that it is **not** part of the capture's pass predicate and the
  evidence file records the queries rather than the rows, and the capture's host-rows query does
  not project this column either — so this value was read directly from Better Stack by a person,
  with the query recorded beside it. It is not self-reported by any committed artifact.

Observed `boot_complete` row, pasted from the capture run: `<paste it here at Phase 5>`.

**The evidence is dated 2026-09-04 and is REUSED, not re-run.** `RUNG2_TEMPLATE_SHA256` binds
the rehearsal to the cloud-init template and the nine `file()`-bound payloads that compose
`user_data`. Recomputed at this tip with the gate's own `git_data_rung2_user_data_sha256`, it
still matches `3a2392fb…4ce1725` — so the boot that was proven is the boot that would happen. A
fresh rehearsal costs a live paid host and another environment approval and would prove the same
thing. The binding is self-invalidating: `infra-validation.yml`'s rung-2 freshness step is
dormant while the file is absent and arms itself the moment it lands, so the next change moving
any of those ten files turns this evidence red on the pull request that made it. Note that this
step runs in `deploy-script-tests`, which is not in `scripts/required-checks.txt` — read its
conclusion, do not assume the queue enforces it.

**Why the 2026-09-04 run originally read TRANSIENT ×20.** The Better Stack SQL API connection
was provisioned 2026-06-01 and could not see source 2734275, created 2026-09-03. A stale
connection returns the same `701 CLUSTER_DOESNT_EXIST` as a source that never stored a row. The
connection was re-provisioned on 2026-09-09 and the query credentials rotated in Doppler
`soleur/prd_terraform`; reads work now. PR #7999 corrects the capture's message so that reading
is no longer produced. Merging #7999 first is preferred but not required — it changes what the
capture *says*, not what this evidence *is*.

Ref #7025, Ref #7204, Ref #7772. Deliberately no `Closes` — this releases a precondition, it
does not complete any of them. ADR-149's item-8 disposition rows still describe the pre-merge
state and are named as follow-up work under #7025 rather than amended here, to keep this diff at
one file.

---

## Risks

- **Post-hoc local capture weakens Property (2).** The runbook's artifact route produces evidence
  *inside* the audited Actions run. This route produces it on a workstation five days later, tied
  to that run only by a hand-passed `--evidence-url`. Disclosed in the PR body. The compensating
  control is the gate's repo-scoped Actions-URL requirement plus the reviewer.
- **The freshness check is observable but not merge-blocking.** `deploy-script-tests` is not in
  `scripts/required-checks.txt` and `main` is not branch protected, so a red AC3 observation 2
  does not stop a merge. Read it explicitly.
- **The 2-day window margin.** `--window '7 DAY'` covers a rehearsal 5 days old. Widening is free
  and re-dispatch is forbidden; the ladder and its floor are in the Phase 2 table.
- **A concurrent change to any of the ten `user_data` inputs.** The runbook's framing is sharper
  than "rebase and re-verify": *"the remedy is a full re-rehearsal — another paid host and another
  approval."* That is a reason to merge promptly once green, and why AC2 runs after a rebase onto
  fetched `origin/main`.
- **Scope creep from PR #7999.** AC4's `origin/main...HEAD` check is the guard; run it rather than
  reading the diff by eye.
- **`gitleaks` on a new tracked `.env` under `apps/`.** Not allowlisted, scanned by the full
  default pack, and required. Phase 3 runs it locally before the push.

## Alternative Approaches Considered

Superseded by the Cut List above, which carries the same rows with their evidence. The two not
listed there:

| Approach | Why not |
|---|---|
| Fold this into PR #7999 | #7999 changes a message; this releases a hold on the birth of the user source-code host. They deserve independent review and independent revert. |
| `Closes #7025` in the PR body | #7025 also owns clearing the DO-NOT-DISPATCH banner. Auto-closing at merge would assert a resolved state before the banner is cleared and before any birth has run. |

## Non-Goals

- Clearing the DO-NOT-DISPATCH banner in
  `knowledge-base/engineering/operations/runbooks/git-data-birth.md`. Separate hold; #7025 owns it.
- **Amending ADR-149's item-8 and #7025 disposition rows**, which describe the pre-merge state
  ("the evidence file is deliberately not committed, both interlocks still hold, and the banner
  stays up") and become stale at the merge instant. Excluded to keep this diff at one file, per
  AC4. Owner: #7025, alongside item 8. Phase 6 step 3 records this on the issue so it is not
  left to memory.
- Dispatching a birth. Releasing the gate makes the birth possible; the environment approval is a
  separate control this PR does not touch.
- Fixing the `--verify-only` branch of the capture, which still prints the superseded "all four
  assertions positive" sentence.
- Anything in PR #7999's diff.
