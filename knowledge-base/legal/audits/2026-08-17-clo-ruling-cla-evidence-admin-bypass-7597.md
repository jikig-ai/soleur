---
title: "CLO ruling — admin bypass of the cla-evidence required check to land PR #7597"
type: clo-ruling
date: 2026-08-17
issue: 7597
pr: 7597
attestation-authority: clo
status: APPROVED (CLO-agent-ruled, Soleur-as-tenant-zero v1)
disposition: DISCHARGED
signed_off_at: 2026-08-17
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; operator retains an optional veto)"
tier_classification: "Tier 3 (internal control record). No document under `docs/legal/**` changed; none of the five mirror/SHA/heading gates are engaged. No Art. 30 amendment — the processing activity is unchanged."
semver: "N/A — TC_VERSION unaffected"
brand_survival_threshold: single-user incident
written_against: "the measured run history and the R2 step output, not the plan"
re_evaluation_triggers:
  - "A recurrence of this outage class in a quarter where the `allowlist/<principal>/<quarter>.json` canonical record has NOT yet been written (i.e. early in a quarter, before the first allowlisted PR). The zero-loss finding below depends entirely on the Q3 record already existing; it does not generalise."
  - "A recurrence while a third-party contributor has an unsigned CLA in flight. The signature path (`build-record.ts`, `issue_comment`) was never exercised during this window; if it were, real evidence would be lost and this ruling would not cover it."
  - "First arms-length (non-Jikigai) contributor. The bypass record's whole function is to document why a merge landed without a signature; with a sole allowlisted owner-principal it is near-vestigial, and its evidentiary weight rises sharply once contributors are external."
  - "Any change making `cla-evidence` non-required, or removing OrganizationAdmin / RepositoryRole-5 from ruleset 13044280/13304872 bypass_actors. Ground (a) of this ruling rests on the bypass being a configured exception."
---

# CLO ruling — admin bypass of `cla-evidence` on PR #7597

## Disposition: APPROVED, conditions discharged.

## What happened

PR #7566 replaced `Setup Bun` with `Setup Node.js` in `.github/workflows/cla-evidence.yml`
but left two `bun run` call sites in place. From 2026-08-16T23:38Z, the
`Record allowlist-bypass (per-quarter canonical)` step exited 127
(`bun: command not found`) on every `pull_request_target` event. `cla-evidence` is a
required status check via ruleset 13304872 (`CLA Required`), so every PR opening or
syncing after that time was blocked.

Because `pull_request_target` executes the workflow file from the base branch, the
remediation PR (#7597) could not pass the check it repairs. Closed loop.

## Measured exposure: NIL

This is the load-bearing finding. It was measured, not assumed.

1. **The bypass record for this quarter already exists.** The step writes a
   per-quarter canonical record under conditional PUT. The last successful run before
   the break (31978969901, 23:23:31Z) reported:
   `worm-duplicate-quarter status=409 key=allowlist/deruelle/2026-q3.json attempt=1 (worm-idempotent)`.
   Every run in the dark window would have been the same 409 no-op. No record was
   missed because none was writable.
2. **No merges landed in the window.** Last merge before the break: #7566 at
   23:27:13Z. Zero merges between 23:38Z and restoration.
3. **The signature path was never reached.** Every `issue_comment` run in the window
   has conclusion `skipped`. No contributor signed; `build-record.ts` was not invoked.
4. **The enforceable gate held green throughout.** `cla-check` — the upstream
   `contributor-assistant/github-action` in `cla.yml`, which is the mechanism that
   actually conditions merge on a licence grant — returned `success` on every run
   during the window. `cla-evidence` is a sidecar to it, as its own header states.

The outage is therefore a **merge-control availability failure**, not an evidence
failure. No records were lost; no backfill is owed or possible (the target key is
occupied and under Object Lock).

## Why the bypass is not a circumvention

Ruleset 13304872 configures `OrganizationAdmin` and `RepositoryRole` 5 as
`bypass_actors` with `bypass_mode: pull_request`. Admin bypass on a pull request is a
designed exception of this control, not a defeat of it. The alternative exits —
disabling the ruleset, or force-pushing to main — are circumventions and were not used.

## Reasoning expressly NOT relied upon

"The layer is already recording nothing, so one more unrecorded merge is immaterial."
That shape is rejected: it treats an accumulating harm as a sunk cost and licenses
indefinite continuation. It is also inapplicable here, because the premise is false —
the layer is recording nothing because nothing remains recordable this quarter.

## Scope of this ruling

Authority for bypassing a required evidence check whose **measured** evidence loss is
nil. Not authority for bypassing one where records are actually being dropped. See
`re_evaluation_triggers`.

## GDPR posture

No Art. 33 notification duty. Art. 4(12) requires destruction, loss, alteration,
unauthorised disclosure of, or access to personal data processed. A record that was
never created is not a record that was lost; the confidentiality and integrity of the
existing R2 store were untouched throughout, and Object Lock held. No Art. 30
amendment: PA-7's purposes, categories, recipients, retention and TOMs are unchanged
by a transient CI outage.

Note for the record, correcting a premise raised at ruling time: this surface **does**
process personal data. PA-7 §(c) is explicit — GitHub username, signature timestamp,
pull-request reference. The absence of a notification duty here follows from there
being no loss, not from an absence of personal data.

## Condition A — pre-merge de-risking (discharged before the merge, not after)

The ruling flagged a residual risk: `tsx` depends on esbuild's platform binary, CI runs
`npm ci --ignore-scripts`, and the local direct-execution check had run against a tree
where install scripts *did* run — so it did not test the CI condition. Because
`pull_request_target` makes the fix unverifiable on its own PR, this was measured
directly instead:

```
# apps/web-platform/{package.json,package-lock.json} copied to a clean dir
npm ci --ignore-scripts        -> rc=0
./node_modules/.bin/tsx --version -> tsx v4.22.4 / node v22.22.2, rc=0
./node_modules/.bin/tsx probe.ts  -> TSX_EXEC_OK 42, rc=0
```

esbuild ships its platform binary as an optionalDependency rather than a postinstall
download, so `--ignore-scripts` does not prevent it resolving. The fix therefore works
under the exact CI install condition. Post-merge verification of the first real
`pull_request_target` run remains required.
