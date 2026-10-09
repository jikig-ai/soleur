---
title: "fix: argv-bearer sweep S3, workflow YAML and composite actions off the process command line"
date: 2026-10-09
slug: argv-bearer-sweep-s3-workflow-yaml-and-composites
branch: feat-one-shot-argv-bearer-sweep-s3
issue: 9597
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

Spec lacks valid lane: defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-09
**Gates run (mechanically):** User-Brand Impact 4.6 (section present, threshold `single-user incident`); Observability 4.7 (all five fields present, `python3` is an allowlisted probe verb, no `ssh`, the command runs in about 0.5 s against the lint, `expected_output` is the literal `OK:`); PAT sweep 4.8 (no hit); Guard Contract 4.11 (`lint-guard-contract.py` green, 2 entries); Scope Check 4.12 (one unfenced section, `Recommendation:` present, no block marker); rule-id check (`cq-write-failing-tests-before` and `hr-observability-layer-citation` active; `wg-architecture-decision-is-a-plan-deliverable` migrated and active); issue and PR citation check (#9597, #7797, #9755, #9756, #9757, #8593, #8800, #3321, #9294 open; #9674, #9753, #9736, #9632 merged; PRs 9785, 9794, 9787, 9529, 7999, 9784, 9801, 9811 open). Not triggered: UI wireframe 4.9, Encryption Posture 4.10 (no store or connection), Downtime 4.55 (no serving surface goes offline), network-outage 4.5 (no trigger term as a symptom; the strings only name existing code).
**Reviewers (already run before this pass, report-only):** DHH, Kieran, code-simplicity, architecture-strategist, spec-flow and CPO; their findings are in "Plan Review Revisions". This pass added targeted verification instead of repeating those seats.

### Key Improvements

1. The ADR ordinal in D12 was wrong against live state: `origin/main` tops out at ADR-277, but open PRs 9529 and 9787 already carry ADR-278 and ADR-279 files. The ordinal is now 280 (provisional) and the check is "every open PR's files", not only the refs.
2. A precedent diff against the two existing in-tree stdin-config wrappers (`_bearer_curl`/`_sig_curl` in `scripts/cutover-inngest.sh` and the `check-deploy-script-parity.sh` HMAC block) is recorded under "Precedent diff", so the library is a deliberate generalization with named differences, not a fresh pattern.
3. Every citation was re-resolved live (state, merge, ADR ordinal, push-path filters) in this pass; none was carried from memory.

### New Considerations Discovered

- `version-bump-and-release.yml` calls `reusable-release.yml` (confirmed in the workflow text), so the plugin-test edit does fire a release run; the plan already says so, and this pass found no way to avoid it.
- The ADR ordinal race is real on this branch: two open PRs hold the next two ordinals.

## Overview

Slice S3 of the argv-credential sweep (tracker #9597, parent #7797). S1 (#9674) widened Rule E to workflow, composite-action and
cloud-init YAML; S2 (#9753) converted the ops, runner and plugin scripts. S3 moves the credentials that **workflow YAML which cannot
fire production on merge** (dispatch, schedule and pull_request triggers only) and the **two composite actions**
(`notify-ops-email`, `anthropic-preflight`) still put on curl's argument list onto curl's stdin config, through one tested shared
helper, `scripts/lib/bearer-curl.sh`. It also owns the two Better Stack reader callers that discard the reader's stderr
(`scheduled-inngest-health.yml`, `git-data-cutover.yml`), tracked in #9757.

The PR carries `Ref #9597` and `Ref #7797` (never `Closes`; only S5 closes #9597). S4 (push-triggered production-class files, the held-back
cutover HMAC sites, heartbeat-URL path secrets) and S5 (`apply-web-platform-infra.yml`, `cloud-init-registry.yml`) are **not planned here**.

**What the measurements changed (details in "Research Reconciliation" and "Stub holders").**

1. The slice is **13 files / 20 Rule E sites** at `02986587cd`, re-derived with the lint, not carried over. After the partition below it converts
   **12 files / 19 sites** and holds back **1 file / 1 site** (`workspaces-luks-cutover.yml`). All counts in this plan are derived from the
   partition; if Phase 0 moves a site into or out of the held-back set, re-derive them (baseline 28/61 minus the converted rows) and amend the plan.
2. That hold-back is the apply-exposure finding. Converting the one Hetzner read in `workspaces-luks-cutover.yml` with the pattern's first
   two flags (`--disable --noproxy`) is impossible without editing `apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh`: its curl stub
   exits 64 on any flag it does not model. Measured on a scratch copy: **5 rows + the assertion floor go red** (107 passed / 0 failed before;
   102 / 5 after). That file sits under `apps/web-platform/infra/**`, so merging an edit to it fires the production push apply (plus the web
   release, `infra-validation`, `validate-vector-config`). Default: hold it back to S4 with operator notice (D3); two alternatives are recorded for the lead.
3. With that one site held back, **S3 touches no production deploy or apply path**: no path under `apps/web-platform/**`, none of the apply
   workflows, none of the `paths:` lists of the push-triggered deploy/apply workflows (every push `paths:` filter evaluated against the S3 file set,
   negations included). **One push-triggered workflow does fire: the plugin release (`version-bump-and-release.yml`)**, because one test file under
   `plugins/soleur/test/` is edited (see "MERGE EFFECTS"). It is not a web deploy, but it is a push-triggered release and the lead should know.
4. Further couplings found by running the owning suites against a scratch conversion (D2/D7, "Stub holders"): the `notify-ops-email` send step is
   **executed standalone** by `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh` (4 rows go red unless the suite supplies
   `GITHUB_WORKSPACE`); `scripts/prod-version-drift-check.test.sh` row B15c pins the **position** of `set +e` in the drift email steps (the `source`
   line must follow it); `apps/web-platform/test/resend-sender-domain.test.ts` pins the **set** of Resend send surfaces by the
   `api.resend.com/emails` literal and the sender string (both stay verbatim). Nine further infra suites were run and stayed green.

### MERGE EFFECTS (read first)

| Trigger | Fires on merge? | Why | Plan response |
|---|---|---|---|
| `apps/web-platform/infra/**` (push apply: `apply-web-platform-infra.yml`; also `infra-validation`, `validate-vector-config`, `mint-inngest-bootstrap-tag` on subsets) | **No edit planned** | Evaluated: no S3 file, and no S3 test fix, is under the prefix. The one S3 site that needs an infra-suite edit is held back (D3). | Acceptance row: the diff contains no path under `apps/web-platform/` (script-checked). If implementation finds an infra or web-platform edit unavoidable, STOP and escalate to the lead for operator notice. |
| `apps/web-platform/**` (web release: `web-platform-release.yml`) | **No edit planned** | `apps/web-platform/test/resend-sender-domain.test.ts` and `apps/web-platform/scripts/sentry-monitors-audit.test.sh` read touched files but stay green (the Resend literal and sender stay verbatim; the sentry suite tests the script, not the workflow step). | Run both read-only in Phase 0; any red row stops the slice. |
| `plugins/soleur/**` (`version-bump-and-release.yml` includes the whole tree; `web-platform-release.yml` excludes `docs/` and `test/`) | **Yes: the plugin release run** | The one edit under it is `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh`. `version-bump-and-release.yml` calls `reusable-release.yml` (inherited secrets, write permissions), and that workflow calls the converted `notify-ops-email` on failure paths. Not a web deploy. | First line of the PR body names it; merge when no other release is in flight; post-merge check on that run's conclusion. |
| `.github/workflows/<converted>.yml`, `.github/actions/**`, `scripts/**`, `tests/**`, `knowledge-base/**` | Fires no deploy | None of the converted workflows lists itself, the composites or `scripts/lib/` in a **push** `paths:` filter. `infra-validation.yml` runs on `pull_request` for five converted workflows and `sentry-audit-gate.yml` on a PR touching itself; those are CI gates. | PR CI is part of the pre-merge proof. |
| Unfiltered push workflows (`ci`, `secret-scan`, `codeql-main-alert-gate`, `skill-security-scan-*`, `tenant-integration`, `vendor-pin-verify`) | Yes, by design, on every merge | They carry no `paths:` filter; all are CI gates and none deploys. | None. |
| Runtime reach of the composites | **Not triggered, but the next run uses them** | `notify-ops-email` has 23 call steps and `anthropic-preflight` 3 (26 steps in 16 workflow files; the fix round re-counted, the first count said 24 steps / 14 files; measured by parsing every job), including `apply-web-platform-infra.yml` and `reusable-release.yml`, which are alert paths. Merging changes what those alert steps run the next time they fire. | Composite step executed end to end under the shim (Phase 2); library-absent row; a lint closure over all 24 callers (Phase 6); post-merge first-run table. |
| Live self-exercise on the PR | Yes, on its own branch | `board-status-sync.yml` runs on PR events with the real App-token mint; `sentry-audit-gate.yml` runs on PRs touching its own file. | These are the live pre-merge proofs for two sites (Phase 9). |

## Decisions

**D1. One helper, `scripts/lib/bearer-curl.sh`, three functions, one send chokepoint.**
A sourced library (functions only; `return`, never `exit`; `scripts/lib/*.sh` is outside the xtrace-prologue rules for exactly that reason, so each
credential-binding function carries its own `case "$-"` refusal returning 78). Public surface:

- `bc_ok VALUE`: 0 for a non-empty value in `[A-Za-z0-9._~+/=-]` under `LC_ALL=C` (the class the 68 existing `_bearer_ok` copies use).
- `bc_curl SCRIPT SPEC... -- [curl args]`: one function for every header shape. A `SPEC` is `NAME:PREFIX:VAR` (name `^[A-Za-z0-9-]+$`, prefix `^[A-Za-z0-9=_ .-]*$`
  with no `:`, `VAR` a variable name read by indirect expansion only inside the library). Bearer: `'Authorization:Bearer :TOKEN'`; the API key:
  `'x-api-key::ANTHROPIC_API_KEY'`; the deploy-webhook triple is three specs (`'X-Signature-256:sha256=:SIG'`, `'CF-Access-Client-Id::CF_ACCESS_CLIENT_ID'`,
  `'CF-Access-Client-Secret::CF_ACCESS_CLIENT_SECRET'`). Every value is judged before the first byte is sent. (Review: one N-header function, not three wrappers.)
- `bc_hmac_sha256_hex KEYVAR`: message on stdin, prints 64 lowercase hex or returns 1; the key reaches a `python3 -I` child by per-command environment prefix only
  (the S2 canonical snippet, byte-pinned by the suite); an empty key returns 1, it must never sign with `b""`.

`bc_curl` funnels through ONE internal `_bc_send`, which validates every value and only then runs
`curl --disable --noproxy '*' "$@" --config - < <(printf 'header = "%s: %s%s"\n' ...)`: process substitution, never a pipe (`pipefail` returns 141 when the consumer exits
first). `--disable` is the first operand (it aborts `.curlrc` parsing). **No default timeout is added** (review: byte-neutral per site is the tracker's acceptance; every converted
step has its own `timeout-minutes` and sites that carry `--max-time` keep it). Refusal: return **2**, stderr gets one line naming only the variable and the marker
`SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char>` (value-free; `MARKER_RE` already matches, no registration change). `script=` is the caller-supplied short
name (`$0` is a temp file in a runner step). A census row asserts the token `curl` appears in the library only inside `_bc_send`.

**D2. Refusal contract: a refused credential must land in the same verdict class the old failure did.** (Binding lesson from the 2026-10-06 refuse-before-send learning and S2's D4.)
Default rule: **a helper return of 2 is a curl failure.** At a site whose old failure was already a red step, the refusal is a red step with the marker visible on stderr (no `2>/dev/null`
anywhere on a converted call), and no pre-guard is written. An explicit pre-guard (`bc_ok` before the call, then the site's own verdict) is written **only where a bare rc 2 would fold
into a different verdict arm** — those are the load-bearing rows:

- `anthropic-preflight`: the old bad-key path was HTTP 401 -> `::error::Unexpected Anthropic preflight response` -> **exit 1 (red)**. A bare rc 2 inside `$(... || echo "000")` would land in the
  `5xx|000` **soft-skip** arm: a malformed key would silently skip every Claude step. Pre-guard outside the substitution, exit 1.
- `scheduled-inngest-health.yml` probe: the call ends in `|| echo "000"`; `CODE=000` grades as non-200 and an `inngest_down` verdict **restarts the server**. A credential fault must never map
  there. Pre-guard (HMAC shape and both Cloudflare Access values) **before** the `for attempt` loop; a refusal records `secret_unset`, which routes to the `liveness-probe` issue class with no restart.
- `notify-ops-email`: old non-2xx -> `::warning::` + `sent=false` + exit 0, and the missing-key `exit 1` is pinned by `terraform-target-parity.test.ts` AC2d. Refusal -> `sent=false`, an
  `::error::` annotation naming the refusal (visible on the run summary), exit 0. The two AC2d regex windows are re-checked.
- Existing quirks the oracle must not "fix" by accident: real curl prints `000` via `-w` on a transport failure and `|| echo "000"` appends another, so `$HTTP_CODE` is `000000`, and
  `anthropic-preflight`'s `^(5[0-9]{2}|000)$` soft-skip arm never matches a real network failure (the job goes red). Transport-failure rows run through the real-curl oracle against a closed
  port, not a stub that prints a clean `000`.
- rc 2 collides with curl's own exit 2 (init failure): no converted site may branch on `rc == 2`; the marker is the discriminator. `rule-audit.yml` branches on `PROBE_RC`, so it gets a row.

**D3. Partition: convert 12 files / 19 sites; hold back `workspaces-luks-cutover.yml` (1 site) by default.** Evidence: the stub reddens 5 rows and the 107-assertion floor the moment the
curl gains `--disable --noproxy '*'`. The residual is one Hetzner token (`HCLOUD_TOKEN_READONLY` first, falling back to the read/write name until ADR-241 O10, so it is **not**
purely read-only today) on a runner's argv for the life of one curl, on a manual dispatch behind an environment reviewer. Alternatives, recorded for the lead in the decision file and not
implemented: **B** convert it and edit the stub (an `apps/web-platform/infra/**` edit: the push apply, web release and `infra-validation` fire; needs operator notice and a post-merge
outcome check; the last test-only infra edit, in S2, ran green with no resource changes); **C** convert it inline without the two confinement flags (`--config -` alone is
stub-compatible, so zero infra edit), at the price of a weaker form for that one call and a non-library copy of the guard. The hold-back is filed as an issue with an owner and a
deadline (S4) and recorded on the tracker.

**D4. The two HMAC keys that sit on the same curl calls move too (`inferred`; see Scope Check).** `canary-status.yml` and the `probe` step of `scheduled-inngest-health.yml` compute
`openssl dgst -sha256 -hmac "$WEBHOOK_*"` and send the result in `X-Signature-256` on the very curl being converted. Converting the header and leaving the key on `openssl`'s argv
would be a half-fix on the same call; both go to `bc_hmac_sha256_hex` + `bc_curl` (`|| SIG=""`, then a 64-hex check before any send, so an empty key refuses with the marker and does not abort
mute). The other `-hmac` sites in `.github/` (`apply-deploy-pipeline-fix`, `deploy-inngest-image`, `restart-inngest-server`, `web-platform-release`, `dispatch-web-redeploy/track.sh`) are S4.

**D5. Better Stack reader stderr is surfaced as `::warning::` (the #9757 item) in both callers, as a best-effort diagnostic that never changes a verdict.**
`scheduled-inngest-health.yml` (dedicated-host arm: `ROWS="$(bash ... 2>/dev/null)" || rc=$?`) and `git-data-cutover.yml` (per-host assertion: `... 2>/dev/null || true`). Each captures
stderr to a runner-temp file, and on a non-zero read prints one `::warning::` carrying `bs_read_classify <rc> <file>` and `bs_read_scrub_err1 <file>` (existing helpers in
`scripts/lib/betterstack-read-classify.sh`; the classifier already names the credential-refusal class `reader-refusal` for rc 2/64/78). The library is sourced behind a `declare -F`
guard: that guard is load-bearing, not decoration, because the infra suites that execute these steps build fake workspaces that may not carry the library (Phase 0 verifies), and a hard
failure there would force an `apps/web-platform/infra/**` edit. The verdict path (`__UNREADABLE__`; `rows=""` retry) is byte-unchanged. The infra suite that executes the dedicated-host arm
(`inngest-dedicated-host-classify.test.sh`, 134 passed / 0 failed) stayed green with stderr capture in the scratch conversion because its stub reader writes nothing to stderr.

**D6. `canary-status.yml` is the one checkout-free job; it gains a plain checkout.** `permissions: {}` and no checkout today. It adds `actions/checkout` (the repo's pinned SHA) with
`persist-credentials: false` and `permissions: contents: read`, so there is one tested implementation rather than a pasted copy (review: no sparse inputs for a negligible saving).
Alternative recorded for the lead: hold this dispatch-only file back to S4 with the other one. Reversible: the inline form is the S2 pattern (`scripts/check-deploy-script-parity.sh`).

**D7. Composite actions source the helper from the job's own checkout.** `source "${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh"`, placed **after** the missing-key block (so the AC2d window
`RESEND_API_KEY[\s\S]{0,200}?exit 1` keeps matching its real target) and with a failure arm that writes `sent=false` (notify) or a plain `::error::` and `exit 1` (preflight)
before exiting 1. Never a fallback to the argv form. Why the source path is safe: every one of the 24 call steps sits in a job with a prior `actions/checkout`, none uses `path:` or
`sparse-checkout` (measured), and `scripts/lint-workflow-local-action-checkout.py` already requires a usable checkout for any `uses: ./`; the action file and the library come from the same
workspace, so ref skew cannot exist. No `pull_request_target` workflow calls either composite today (measured: apply-sentry-infra, cla, cla-evidence, dev-ledger-reconcile,
merge-queue-cla-synthetics, secret-scan are the `pull_request_target` set); that is true by accident, so Phase 6 extends the existing lint to make it a checked property. The one PR-head checkout
(`fix-constraints-stage-a.yml`) resolves the action and the library from the same head tree and holds no new privilege (a same-repo author could already edit the action; fork PRs get no secrets).
The standalone executor in `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh` is given `GITHUB_WORKSPACE="$REPO_ROOT"` in its run environment.

**D8. Baseline E: shrink by deletion only; per-site fingerprint keying is decided "not adopted".** The tracker asks S3 to decide fingerprint keying because a count cannot see a net-equal
edit inside one file. Every file S3 converts leaves baseline E **entirely**, so a re-added argv site there is an unlisted offender and fails the equality check; the 16 rows that remain belong
to S4, S5, the two cla-evidence files (#9756) and the held-back file. A keying mechanism would be built for a population that S4 and S5 delete. Residual stated: until S4/S5, a PR that converts
one site and adds another in a still-listed file is count-neutral (reviewer gate, as before). Ratchet: **28 files / 61 sites -> 16 / 42** (derived: minus the converted rows).

**D9. Other checklist items: worked only where they touch the same file.** #9757 "Better Stack reader stderr" is S3 (D5). Left for their slices: the held-back cutover HMAC pair and heartbeat URLs
(#9757 S4), the `op=backup` environment gate (#9755: `cutover-inngest.yml` + an infra suite), the two cla-evidence `--user` sites (#9756), `linkedin-setup.sh` `write-env` validation, the review leads
(a) to (h) of #9757 (none touches an S3 file), and Markdown that agents execute. **Cut:** rewriting the argv-form `curl` text that `scheduled-terraform-drift.yml` prints into an issue body (inferred,
outside the brief; the review panel cut it; recorded in the Cut List).

**D10. Anonymous registry tokens (`rule-audit.yml`, two sites) are converted for ratchet consistency.** The `T`/`UB_T` values are anonymous pull tokens, not secrets, but Rule E counts the shape and
the file would otherwise stay in the baseline for no property gain. The two Docker Hub / GHCR token-fetch curls carry `2>/dev/null`; the converted `UB_HDR` call drops it so the marker is visible.
The refusal sink is the existing `PROBLEMS` accumulator (via the `PROBE_RC`/`CODE` arms). No dedicated slice-driven battery row beyond the class representative.

**D11. Commits are separable by blast radius:** (1) library + its suite + CODEOWNERS + the ADR; (2) composites + the plugin-test env fix; (3) read-only/alert workflows (board sync, sentry gate,
drift emails, rule-audit, kb-drift, terraform-drift sweep); (4) rehearsal workflow; (5) cutover workflow + canary + inngest-health (HMAC + stderr); (6) battery stage + the lint extension; (7) docs/trackers;
(8) baseline-only commit last (after the merge-from-main commit exists). The composites stay in their own revertable commit.

**D12. An ADR records the contract (a plan deliverable, not a follow-up).** The library is a cross-cutting invariant five slices and 24 alert-path steps depend on: credentials reach curl on its
stdin config through `scripts/lib/bearer-curl.sh`; a refusal must land in the same verdict class as the old failure; a missing library is a hard failure, never an argv fallback. Status `adopting`;
ordinal provisional (the highest ordinal on `origin/main` is 277; open PRs 9529 and 9787 already claim 278 and 279, so 280 is the next free; re-verify against `origin/*` and every open PR's files, and again at ship).

## Precedent diff (pattern-bound behaviors)

The library generalizes two precedents already on `main`; the differences are deliberate and named.

| Behavior | `scripts/cutover-inngest.sh` (`_bearer_curl`, `_sig_curl`) | `scripts/check-deploy-script-parity.sh` (S2 HMAC block) | `scripts/lib/bearer-curl.sh` (this plan) |
|---|---|---|---|
| Shape guard | `_bearer_ok` per value, inline copy | `_bearer_ok` inline copy, `_refuse` exits 2 | `bc_ok`, one copy, called from `_bc_send` for every spec |
| Refusal | `return 2`, marker `script=cutover-inngest` | `exit 2`, marker `script=check-deploy-script-parity` | `return 2` (a sourced library never `exit`s), caller-supplied `script=` name |
| Transport flags | `--disable --noproxy '*' --max-time 60` | `--disable --noproxy '*' --proto '=https'` | `--disable --noproxy '*'`, **no default timeout** (byte-neutral), caller adds `--max-time` and `--proto` |
| Header feed | `--config - < <(printf ...)` | `--config - < <(printf ...)` | the same process substitution |
| HMAC | not in the wrappers (inline python snippet per site) | inline python snippet, `|| HMAC=""`, 64-hex check | `bc_hmac_sha256_hex` (one copy of the same snippet, byte-pinned by the suite) |
| xtrace | script-level refusal | script-level refusal | per-function refusal (a sourced library cannot rely on the caller's prologue) |

No precedent exists for a **sourced workflow-side credential library**; that part is novel, which is why the plan adds the closure lint (usable checkout, no `pull_request_target`), the library-absent rows and ADR-280.

## Research Reconciliation: brief and tracker text vs. codebase

| Brief / tracker claim | Reality (`02986587cd`, measured 2026-10-09) | Plan response |
|---|---|---|
| "S3 = workflow YAML that cannot fire production on merge plus two composites" (count not given) | `python3 scripts/lint-shell-trace-credential-refusal.py --census` rule E: 28 files / 61 sites. By trigger (PyYAML over each `on:`): 11 workflows with no `push` trigger + 2 composites = **13 files / 20 sites**. The other 15 rows are 7 push-triggered workflows (6 for S4, `apply-web-platform-infra.yml` for S5), 2 push-path files under `.github` (`mint-infra-app-token`, `dispatch-web-redeploy/track.sh`), `cloud-init-registry.yml`, 3 infra scripts and the 2 cla-evidence files. | Census table below. |
| Tracker: "35 argv sites in 16 files" for Tier 3 YAML | Stale: S1's census moved it. 22 rows under `.github/` (21 YAML files + `track.sh`): 13 S3 + 8 S4 + 1 S5. | S3 list re-derived; counts above. |
| "Convert `scheduled-inngest-health.yml` and `git-data-cutover.yml` Better Stack stderr" | Both verified: dedicated-host arm line `... --limit "$PROBE_LIMIT" 2>/dev/null)" || rc=$?`; assertion step `... FORMAT JSONEachRow" 2>/dev/null || true)`. In `git-data-cutover.yml` the **flip-precondition curl** also carries `2>/dev/null || echo 000`, which would hide the new marker. | D5 and D2. |
| Lead: "open PR 9785 edits `anthropic-preflight/action.yml`" | Confirmed: it rewrites the single `PAYLOAD=...model:"claude-haiku-4-5-20251001"` line directly above the curl, and adds a vitest regex over that action's `model:"(claude-haiku-...)"` literal. | Keep the PAYLOAD line byte-identical; read `gh pr diff 9785` and merge main before editing the file; expect an adjacent-hunk conflict if 9785 lands first. |
| Lead: "draft PR 9794 edits `git-data-cutover-access.test.sh`" | Confirmed. S3 plans no edit to that file; the suite stayed green under the scratch conversion (548 passed / 1 failed in both the converted and the unmodified scratch copy; the 1 is a missing-file artifact of the trimmed scratch tree). | None. |
| (Additional, found) other open PRs touching S3 files | 9787 (`scheduled-terraform-drift.yml`, appended at EOF), 9529 (`rule-audit.yml` @368), 7999 (`git-data-rung2-rehearsal.yml` @470), 9784 (`terraform-target-parity.test.ts`), 9801 (`tests/scripts/test-kb-drift-walker.sh`). None overlaps a site hunk. | `git fetch && git merge origin/main` before the baseline commit and again just before merge. |
| "Sourced only from the job's own checkout" is satisfiable everywhere | One S3 job has no checkout: `canary-status.yml` (`permissions: {}`). All 26 composite call steps have a prior checkout. | D6, D7. |
| Lessons: "grep the whole repo for transport stubs of the changed credential path" | Done for S3's vocabulary; holders in "Stub holders" below. One infra-path holder found (the workspaces-luks stub). | D3. |
| Tracker acceptance: "a guard-before-curl battery row per converted site (the lint cannot decide ordering statically)" | With a single `_bc_send` chokepoint the ordering is structural for the library (proved once, in the library suite). The per-site battery rows prove the **verdict class** at the sites where a bare refusal could land in a different arm, plus one representative per class; every site is also covered structurally (calls the library, no credential on argv, argv-neutrality golden). | Phase 6, Guard 2. |
| `scripts/lib/bearer-curl.sh` "exists" (implied by the tracker's wording) | Does not exist (`ls scripts/lib`); 68 inline `_bearer_ok` copies exist. | New file (Files to Create). |
| Hold-back: "nothing else needs an infra-path edit" | Held on the 14 suites run so far; the review panel found five more suites naming converted files (run: all green) and the `cutover-inngest-workflow.test.sh` remedy-text greps (to run in Phase 0). | Phase 0 derives the suite list with `git grep -l` and runs it all. |

## Stub holders (the whole-repo transport grep for S3's vocabulary)

Method: `git grep` over tests, scripts and fixtures for the converted files' names and for the credential vocabulary (`-u)`, `--user`, `Authorization`, `x-api-key`, `X-Signature-256`,
`CF-Access-Client`), each hit classified as *executes the step*, *greps the step text* or *comment only*, and the owning suites **run against a scratch conversion** (a copy of the tracked tree outside
the worktree; the real files are untouched; the scratch conversion approximated each site with the intended call shape and a minimal library). Phase 0 repeats this on the real tree and derives the
list rather than trusting this table.

| Holder | What it does with the S3 surface | Measured under the scratch conversion | Fix |
|---|---|---|---|
| `apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh` | Executes the cutover step's body under a curl stub that exits 64 on an unmodelled flag; mutation battery plants `Authorization: Bearer` as a write | **RED: 5 rows + floor (107 -> 102)** | Hold the site back (D3); infra path. |
| `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh` | Extracts and executes the `notify-ops-email` `send` step with a curl stub that prints the code (ignores args and stdin) | **RED: A1 to A4** (no `GITHUB_WORKSPACE`) | Export `GITHUB_WORKSPACE="$REPO_ROOT"` in its run environment; plugin test dir. |
| `scripts/prod-version-drift-check.test.sh` | Pins `set +e` as the first statement (B15c) and counts `api.resend.com` bodies | **RED: B15c, C0** (a `source` line before `set +e`) | Place `source` **after** `set +e`; keep the URL literal. |
| `plugins/soleur/test/terraform-target-parity.test.ts` (AC2d) | Regex windows over the composite: `RESEND_API_KEY[\s\S]{0,200}?exit 1`, `HTTP_CODE[\s\S]{0,400}?::warning::` | Both match a converted composite (regex-checked) | Keep the missing-key block and the final warning arm within those windows. |
| `apps/web-platform/test/resend-sender-domain.test.ts` | Pins the set of Resend send surfaces by `api.resend.com/emails` and the sender string | Static: both literals preserved (not run in the scratch tree: needs node deps) | Preserve both verbatim; run in Phase 0. |
| `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` | Greps the reset step's text and the sweep job's `api.hetzner.cloud/v1/${_kind}`; executes the **seed** poll step (not converted) | **GREEN 129/0** | Preserve the URL literals and the line order of the POST. |
| `apps/web-platform/infra/inngest-dedicated-host-classify.test.sh` | Executes the dedicated-host arm of `scheduled-inngest-health.yml` with a stub reader | **GREEN 134/0** with stderr capture | Keep the `ROWS="$(...)" || rc=$?` shape and the library-source whole-line match. |
| `git-data-cutover-access`, `git-data-flag-precheck`, `inngest-host-state-workflow-guard`, `rule-audit-inngest-pin-workflow-guard` (all `apps/web-platform/infra/*.test.sh`) | Structure checks (step ids, order, secrets set, flip-precondition inputs) | **GREEN / identical fail set to the unmodified scratch copy** | None. |
| `web-hosts-fanout-parity`, `git-data-root-key` (G8 pins the notify step shape), `inngest-cli-staleness`, `zot-image-staleness` (all `apps/web-platform/infra/*.test.sh`) | Named by the review panel as readers of converted files | **GREEN: 14/0, 153/0, 19/0, 15/0** | None. |
| `scripts/lint-workflow-errexit-capture.test.sh`, `scripts/lint-workflow-local-action-checkout.test.sh`, `tests/scripts/test-infra-privileged-tier-census.sh`, `scripts/alarm-issue-filing-guard.test.sh`, `tests/scripts/test-kb-drift-walker.sh` | Workflow-wide lints and censuses | **GREEN / identical to base** | None. |
| `apps/web-platform/infra/cutover-inngest-workflow.test.sh` | Greps `scheduled-inngest-health` remedy text | Not yet run (long suite) | Run in Phase 0. |
| `.claude/hooks/security_reminder_hook.test.sh`, `scripts/lint-shell-trace-credential-refusal.test.sh` | Path string only / fixtures | Not coupled | None. |

## Research Insights

**Premise Validation (Phase 0.6).** Cited by reference: #9597 (open; restated checklist and the S2 comment read in full), #7797 (open), #9755, #9756, #9757 (all open), S1 = #9674 and S2 = #9753
(merged; the S2 comment confirms the held-back items and the follow-ups), ADR-241 (proposed; D4's Tier-A read-only Hetzner token and the O10 token removal are why the held-back file reads
`HCLOUD_TOKEN_READONLY` first). Cited paths verified on `origin/main`: all 13 S3 files exist; `scripts/lib/bearer-curl.sh` does not. Proposed mechanism versus the ADR corpus: no ADR rejects stdin
config or a shared sourced library, and none records the credential-transport contract (hence D12); ADR-241 only constrains which jobs may name Tier-B secrets, and S3 adds no `secrets.*` reference
(the suites that pin the secret set stay green). What held: the conversion pattern, Rule E structure, the S1/S2 learnings. What was stale: the tracker's site counts, the implied existence of the
helper, and the assumption that every S3 file converts without an infra-suite edit.

**Property List (Phase 0.6b).**

1. After S3, no S3 file places a credential (header value, API key, deploy-webhook signature, the HMAC key that produces it) on any process's argument list.
2. A malformed, empty or unset credential produces zero outbound requests and one value-free marker line, and the site's own verdict class (red step, soft verdict or warning) is the one the old
   failure produced: nothing newly silent, nothing newly red, and no credential fault ever maps to a production action (a restart).
3. A Better Stack reader refusal (exit 2, marker on stderr) is visible in the two callers that discarded it, without changing their verdicts.
4. The converted requests keep the same method, URL, non-credential headers, body and timeouts. The transport itself is NOT byte-neutral: it runs `--disable --noproxy '*'` first and with the TLS/proxy/loader-redirecting environment unset (ADR-280 decision 6).
5. The library, the composites and the converted workflows are exercised under the runner's toolchain (bash 5.2.21, curl 8.5.0), not only the dev host's.

**Cut List (Phase 0.6b).** (i) Per-site fingerprint keying for baseline E (buys property 1 for files that S4/S5 delete; D8). (ii) Converting the existing `printf | curl -K -` / `-H @-` pipe-form sites
in these files (already off argv, so no property gain; the rung-2 seed poll, the Supabase read in inngest-health). (iii) A fallback to the argv form when the library is missing (defeats the property).
(iv) A new marker class or reason (`xtrace` stays a plain `::error::` + return 78). (v) Three wrapper functions (`bc_curl`, `bc_curl_hdr`, `bc_curl_webhook`): folded into one N-spec function (review).
(vi) A default `--max-time` in the library (breaks byte-neutrality; review). (vii) Rewriting the argv-form `curl` text printed into the terraform-drift orphan issue body (inferred, outside the brief; review).
(viii) Guard 2 of the first draft (a restatement of Rule E's baseline equality; review). (ix) A hand-kept hermetic/slice taxonomy in the battery (reuse the existing `CLASSIFIED` mechanism; review).
(x) A runner-side `curl` wrapper in `$PATH` (ambient, not testable per site).

**Learnings applied (read, not recalled):**
`2026-10-06-an-argv-bearer-sweep-needed-a-ratchet-a-token-shape-guard-and-a-process-substitution-not-a-pipe` (process substitution, guard before every call);
`2026-10-06-a-refuse-before-send-guard-turned-a-paging-401-into-a-silent-skip` (D2: name the old failure's sink and the new refusal's sink per site; the anthropic-preflight and inngest-health cases are the same class);
`2026-10-08-a-pipe-tail-swapped-for-a-command-substitution-aborts-mute-and-the-green-suite-ran-on-a-newer-toolchain-than-ci` (`|| VAR=""`, assert failure behaviour at the call site, verify on the runner userland, run the
repo-global ratchets by hand, helpers go below any xtrace refusal);
`2026-10-07-a-guard-pr-added-an-unregistered-marker-and-resumed-fix-agents-stalled-on-a-status-line` (marker drift guard; brief fix agents that waiting on a monitor is not a report).

## Census and per-site contract

Measured with the lint (`python3 scripts/lint-shell-trace-credential-refusal.py <paths>`), PyYAML trigger evaluation and `git grep`; line numbers are a snapshot at `02986587cd`, implementation locates
every site by the **anchor**, never by line number. `bc_curl <name> <spec>` below abbreviates the D1 call.

| # | File (trigger) | Step / anchor | Sites | Credential and shape | Call | Old failure sink | New refusal sink | Proof |
|---|---|---|---|---|---|---|---|---|
| 1 | `.github/actions/anthropic-preflight/action.yml` (composite) | step `check`, `-H "x-api-key: $ANTHROPIC_API_KEY"` | 1 | Anthropic key (`sk-ant-...`: alnum, `-`, `_`) | `bc_curl anthropic-preflight 'x-api-key::ANTHROPIC_API_KEY'` after an explicit `bc_ok` pre-guard | 401 -> `::error::Unexpected ... response` exit 1 (red) | pre-guard `::error::` + marker, **exit 1** (red); never the `000` soft-skip arm | composite row; PR 9785 coordination |
| 2 | `.github/actions/notify-ops-email/action.yml` (composite) | step `send`, `-H "Authorization: Bearer ${RESEND_API_KEY}"` | 1 | Resend key (`re_...`) | `bc_curl notify-ops-email 'Authorization:Bearer :RESEND_API_KEY'` after a `bc_ok` pre-guard | non-2xx -> `::warning::` + `sent=false`, exit 0 | `::error::` annotation + `sent=false`, exit 0 (visible, caller contract kept) | heartbeat suite A1-A4 (with env fix), AC2d, composite rows |
| 3 | `board-status-sync.yml` (issues, pull_request) | step "Mint App token and sync board Status", `INSTALL_TOKEN=$(curl ... "Authorization: Bearer $JWT")` | 1 | locally minted JWT (base64url + `.`); `::add-mask::` of the JWT and the installation token already precede first use (keep) | `bc_curl board-status-sync 'Authorization:Bearer :JWT'` inside the existing `| jq` pipeline | empty token -> `::error::Installation-token exchange ...` exit 1 | red step (rc 2 through the pipeline), marker visible | live PR-event run |
| 4 | `canary-status.yml` (workflow_dispatch) | step "Read /hooks/deploy-status .sandbox_canary" (HMAC + 3 headers) | 1 (+1 HMAC) | deploy-webhook key (HMAC input), CF Access pair | `bc_hmac_sha256_hex` + `bc_curl canary-status` with the triple of specs; adds a plain checkout (D6) | non-200 -> `::error::deploy-status returned HTTP $CODE` exit 1 | red step, marker visible (empty `SIG` refuses before the call) | HMAC-site row (the one HMAC representative) |
| 5 | `git-data-cutover.yml` (workflow_dispatch) | step "Flip preconditions", `curl ... "Authorization: Bearer ${SENTRY_ACTIONS_RO_TOKEN}"`; step "Per-host git_data_store= assertion" (reader) | 1 (+ stderr) | Sentry read token (`sntrys_...`) | `bc_curl git-data-cutover 'Authorization:Bearer :SENTRY_ACTIONS_RO_TOKEN'`; drop the `2>/dev/null`; reader stderr -> `::warning::` | `code=000` -> `fail pin_fault_paging_absent` (fail-closed) | same `fail` verdict (rc 2 lands in the `|| echo 000` arm), marker now visible | cutover-access + flag-precheck (green), verdict row |
| 6 | `git-data-rung2-rehearsal.yml` (workflow_dispatch) | step "Hard-reset the rehearsal host (Hetzner API)" x3 curls; step "Assert no rehearsal host survives (Hetzner API)" x1 | 4 | Hetzner token (alnum) | `bc_curl rung2-rehearsal 'Authorization:Bearer :TOKEN'` (the `-X POST` keeps its `Content-Type` argv header) | `-f` fail -> `::error::could not resolve ... Failing closed` exit 1 | the same arms fire (rc 2 is a curl failure); marker visible | `git-data-rung2-rehearsal.test.sh` (green), class representative |
| 7 | `kb-drift-walker.yml` (schedule 03:00 UTC, dispatch) | step "Run walker and POST to ingest", `-H "X-Soleur-Kb-Drift-Signature: $SIG"` | 1 | HMAC signature `sha256=<hex>` (key already env-only via python3) | `bc_curl kb-drift-walker 'X-Soleur-Kb-Drift-Signature::SIG'` | ingest 4xx -> `test` fails -> red | red, marker visible | `tests/scripts/test-kb-drift-walker.sh` (PR 9801 edits it) |
| 8 | `rule-audit.yml` (schedule 1st/15th, dispatch) | step "Detect zot pin staleness" x2 (`T`, `UB_T`; `2>/dev/null` dropped on the `UB_HDR` call) | 2 | anonymous pull tokens (JWT shape; `jq -r .token` can yield the literal `null`, which passes the shape class and keeps the old 401 path) | `bc_curl rule-audit 'Authorization:Bearer :T'` / `UB_T` | 401 -> "unexpected HTTP"/"could not verify" appended to `PROBLEMS` | rc 2 -> "could not verify ... (network/probe failure)" appended to `PROBLEMS` | `rule-audit-inngest-pin-workflow-guard` (green); a curl-init-failure row |
| 9 | `scheduled-inngest-health.yml` (schedule */15, dispatch) | step `probe` (HMAC + 3 headers); step "Census tunnel connectors" x2 | 3 (+1 HMAC) (+ stderr) | webhook key + CF Access pair; Cloudflare API token | pre-guard, then `bc_hmac_sha256_hex` + `bc_curl inngest-health` (triple); census `bc_curl inngest-health 'Authorization:Bearer :CF_API_TOKEN'` x2; reader stderr -> `::warning::` | probe non-200 -> `record_failure`; census empty -> `census_unavailable` (soft, exit 0) | refusal -> `record_failure "secret_unset"` (`liveness-probe` issue class, **no restart**; never `inngest_down`); census refusal -> `census_unavailable` + visible marker | `inngest-dedicated-host-classify`, `inngest-host-state-workflow-guard` (green); verdict row |
| 10 | `scheduled-prod-version-drift.yml` (schedule hourly, dispatch) | steps "Email ops on first detection" and "Email ops when the check cannot evaluate" (inline Resend) | 2 | Resend key | `bc_curl scheduled-prod-version-drift 'Authorization:Bearer :RESEND_API_KEY'`; `source` placed **after** `set +e` | non-2xx -> `::error::... FAILED` + `delivered=0` | refusal -> `HTTP_CODE=000` -> same `::error::` + `delivered=0` | `prod-version-drift-check.test.sh` (B15c), class representative |
| 11 | `scheduled-terraform-drift.yml` (workflow_dispatch; the Inngest cron dispatches it) | job `rung2-rehearsal-orphan-sweep`, step "Sweep for orphaned rung-2 rehearsal hosts" (loop over 4 kinds) | 1 | Hetzner token | `bc_curl terraform-drift 'Authorization:Bearer :TOKEN'` | `-f` fail -> `::error::could not list ... fail-closed` exit 1 | same arm | `git-data-rung2-rehearsal.test.sh` (greps the `${_kind}` URL) |
| 12 | `sentry-audit-gate.yml` (pull_request, runs on edits to itself) | step "Verify token scope against org endpoint (fail-loud)" (already `--disable --noproxy --proto '=https' -g`) | 1 | Sentry auth token | `bc_curl sentry-audit-gate 'Authorization:Bearer :SENTRY_AUTH_TOKEN' -- --proto '=https' -g ...` | non-200 -> `::error::scope check failed` exit 1 | red step, marker visible | live PR run |
| 13 | `workspaces-luks-cutover.yml` (workflow_dispatch) | step "Run workspaces-luks cutover", `VOL_JSON="$(curl -fsS ... "Authorization: Bearer $HCLOUD_TOKEN")"` | 1 | Hetzner token | **HELD BACK (D3)** | not converted | not converted | the infra suite (red under conversion) |

Totals: **13 files, 20 sites; converted 12 files / 19 sites; held back 1 file / 1 site**, plus the two HMAC keys of D4 (not Rule E sites).

Reproduce before implementing; record counts only (no values) in the PR body: `python3 scripts/lint-shell-trace-credential-refusal.py --census | sed -n '/rule E/,$p' | grep -c '^\.github'` (22), the
13-path explicit run (20 violations), `grep -v '^#' scripts/lint-shell-trace-credential-refusal-e.baseline.txt | awk -F'\t' '{n++; s+=$2} END{print n, s}'` (28 61), and
`git grep -n -E -- '-hmac' -- .github` (S3 set: `canary-status.yml`, `scheduled-inngest-health.yml`; the rest stay).

## User-Brand Impact

**If this lands broken, the user experiences:** an alert email that never arrives (the converted `notify-ops-email` runs on the failure paths of the release and apply workflows and on the hourly
stale-production check, so a broken helper source, a mis-routed refusal or a vendor key format outside the shape class means a stale or failed production deploy goes unreported), a pre-flight that
silently skips every Claude-driven workflow (the soft-skip trap in D2), a cutover precondition or a rehearsal teardown assertion reading "cannot verify" when the system is fine (a stopped dispatch, never a
silent pass: both are fail-closed), the inngest health watchdog failing to file a real alarm or filing a false one (and, if a credential fault were mapped to `inngest_down`, restarting the server), or the board
automation going quiet. All are loud or recoverable by revert except the first, which is why it carries an end-to-end composite row, an `::error::` annotation on refusal and a bounded post-merge check.

**If this leaks, the user's data is exposed via:** the failure the sweep removes: a token readable in `/proc/<pid>/cmdline` for the life of a curl by any other process in the same job — on hosted
runners (no self-hosted runner is used anywhere in `.github`, measured) that means a compromised third-party action or dependency step; plus the ways this change could add one: a credential echoed
by a new diagnostic (the Better Stack `::warning::` prints only a classification token and a scrubbed first stderr line, never a value), a key written to a temp file, or tracing left on while the library binds a
credential (each function refuses under xtrace). The exposed classes are the Hetzner token, the deploy-webhook key plus Cloudflare Access pair (can rewrite the production host and read its credential
file, ADR-241 D1 amendment) and the Resend key. Residual after S3: the held-back file's Hetzner token on argv for one curl on a manual dispatch; the HMAC key and the credentials live in a child's
environment (same-uid and root can read `/proc/<pid>/environ`), a reduction from world-readable `cmdline`, not elimination. **This PR does not remediate past exposure**: rotation of these classes stays
with ADR-241 O13 and #9294 and nothing here closes them. A vendor changing its key alphabet would turn alerts into a visible refusal annotation instead of a vendor 401, with a new cause; the marker lives
in run logs and is not paged (stated, accepted).

- **Brand-survival threshold:** single-user incident

CPO assessment: **sign-off yes-with-conditions** (headless panel, 2026-10-09), all conditions applied: (1) a negative canary over stdout, stderr, step summary and annotations on every refusal, error and
diagnostic path including curl's own config-parse errors (Test Scenario 2); (2) mask-before-use for the runtime-minted tokens (already present in `board-status-sync.yml`, kept); (3) a checked assertion that no
caller runs under `pull_request_target` or an untrusted ref (Phase 6 lint extension); (4) a bounded positive control for the alert path (post-merge table, owner and deadline) with an optional active control
needing the lead's go; (5) separable commits (D11); (6) rotation not claimed (above); (7) named first runs (post-merge table). `soleur:engineering:review:user-impact-reviewer` is invoked at review time.

## Architecture Decision (ADR/C4)

### ADR

Create **ADR-280** (provisional ordinal; re-verify the next free number against every `origin/*` ref and again at ship) via `soleur:architecture`, status `adopting`, in Phase 7 as a plan task (D12): credentials
reach curl on stdin config through `scripts/lib/bearer-curl.sh`; the refusal contract (same verdict class as the old failure, marker value-free, rc 2, no site branches on rc 2); library absence is a hard failure; the
alternatives considered are the 68 inline copies, a `$PATH` curl wrapper, and the argv-with-masking status quo. ADR-241 is not amended: S3 names no new `secrets.*` in any job, adds no Tier-B read and changes no tier
classification.

### C4 views

No C4 impact. All three model files were read (`model.c4`, `views.c4`, `spec.c4`): the external systems the converted calls touch are GitHub Actions runners, Hetzner API, Resend, Anthropic, Sentry, Cloudflare (API
and Access), the deploy webhook host and Better Stack, all already modeled with their edges; the Docker Hub and GHCR anonymous registry reads are not modeled and stay unmodeled (a pre-existing gap this slice does
not widen: the edge exists, only its argv encoding changes). No actor, container, data store or access relationship changes. `plugins/soleur/test/c4-count-parity.test.sh` runs in Phase 9 (S3 adds no workflow and no
monitor, so no embedded count moves).

### Sequencing

None. The ADR describes the state this PR ships.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Continue the argv-bearer sweep (tracker #9597, Ref #7797). Slices S1 and S2 are already merged. Do ONE slice per PR, in order — this PR is S3 only." [brief] | whole plan; MERGE EFFECTS | mapped |
| 2 | "re-derive every count, they were wrong twice" [brief] | Census, Research Reconciliation, "Reproduce before implementing" | mapped |
| 3 | "Also read #9755, #9756, #9757 and ADR-241" [brief] | Research Insights (Premise Validation), D9 | mapped |
| 4 | "run the repo-wide transport-stub grep (`-u)`, `--user`, `Authorization`, `x-api-key`) over the WHOLE repo for S3's credential vocabulary BEFORE planning (to know apply exposure of stub fixes under infra paths)" [brief] | Stub holders; MERGE EFFECTS; D3 | mapped |
| 5 | "workflow YAML that cannot fire production on merge (workflow_dispatch / schedule / pull_request triggers only) plus the composite actions notify-ops-email and anthropic-preflight, converted through a tested shared helper scripts/lib/bearer-curl.sh" [brief] | D1, D2, D6, D7, Phases 1 to 5, Census | mapped |
| 6 | "the two Better Stack reader callers that discard stderr: scheduled-inngest-health.yml (2>/dev/null, so exit 2 reads as __UNREADABLE__) and git-data-cutover.yml (2>/dev/null \|\| true)" [brief] | D5, Phase 5 | mapped |
| 7 | "Work other #9757 / #9755 / #9756 checklist items into S3 only where they touch the same file; otherwise leave them for their slice" [brief] | D9 | mapped |
| 8 | "Do not plan S4/S5." [brief] | Overview; D3 (hold-back destination named, not planned) | mapped |
| 9 | "Do not print or echo any token value, and compare secrets without printing them. Never use git stash or a pattern-matching process kill." [brief] | Phase intro; Risks | mapped |
| 10 | "PR carries `Ref #9597` and `Ref #7797` (NOT Closes; only S5 closes #9597). Poll with Monitor, never Bash run_in_background. Production-apply dispatch needs explicit operator approval each time; flag in the plan if S3 turns out to touch any push-triggered production path" [brief] | Phase 10; MERGE EFFECTS (plugin release flagged); Phase 9 dispatch rule | mapped |
| 11 | "open PR 9785 ... plan for a rebase/merge conflict there and read its diff" / "Open draft PR 9794 edits ..." / "do not touch its files" (ci-deploy.sh) [brief] | Research Reconciliation, Phase 0, Phase 2, Files "Not edited" | mapped |
| 12 | "BINDING LESSONS FROM S2 (encode in the plan's tasks/acceptance criteria)" 1 to 11 [brief] | lesson 1 Stub holders; 2 Phase 1; 3 Phase 6; 4 Phase 8; 5 D2/D4; 6 D1; 7 Phase 6; 8 Phase 10; 9 Phase 9; 10 Phase 9 gate list; 11 Phase intro | mapped |
| 13 | "a guard-before-curl battery row per converted site ... decide per-site fingerprint keying for baseline E ... CODEOWNERS row" [issue #9597] | Guard 2, Phase 6, D8, Phase 1 | mapped (battery rows scoped by class, see Plan Review Revisions) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/lib/bearer-curl.sh` + `scripts/lib/bearer-curl.test.sh` | "converted through a tested shared helper scripts/lib/bearer-curl.sh" | asked |
| 12 converted workflow/composite files | "workflow YAML that cannot fire production on merge ... plus the composite actions notify-ops-email and anthropic-preflight" | asked |
| Better Stack stderr surfacing (D5) | "the two Better Stack reader callers that discard stderr" | asked |
| `.github/CODEOWNERS` rows | "CODEOWNERS row" [issue #9597] | asked |
| `bc_hmac_sha256_hex` and the two HMAC moves (D4) | — | inferred — justification: the HMAC key is on `openssl`'s argv on the very curl whose signature header is converted; converting only the header leaves the same call half-fixed |
| `canary-status.yml` plain checkout (D6) | — | inferred — dependency: "sourced only from the job's own checkout" requires a checkout in the one checkout-free job |
| `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh` env edit | — | inferred — dependency: the suite executes the composite's send step standalone and goes red (A1 to A4) without `GITHUB_WORKSPACE` |
| `lint-workflow-local-action-checkout.py` extension (Phase 6) | — | inferred — enforcement contract: the library-source closure and the no-`pull_request_target` property are otherwise true by accident (CPO condition 3, architecture review) |
| ADR-280 (D12) | — | inferred — enforcement contract: `wg-architecture-decision-is-a-plan-deliverable`; a cross-cutting contract five slices and 24 alert-path steps depend on |
| `rule-audit.yml` anonymous-token conversion (D10) | "workflow YAML that cannot fire production on merge (workflow_dispatch / schedule ..." | asked (file is in the baseline and the trigger class) |
| Battery stage S3 (`tests/scripts/test-argv-bearer-sweep.sh`) and baseline/ceiling edits | "a guard-before-curl battery row per converted site" [issue #9597] | asked |
| `lint-shell-trace-credential-refusal.py` docstring edit | — | inferred — enforcement contract: the lint docstring records the converted file classes and the keying decision (D8) or it rots |

### Split Assessment

- Subsystems touched: 5 — `.github`, `scripts`, `tests`, `plugins/soleur`, `knowledge-base`
- Planned files: 27 | Estimated changed lines: about 1800 (library 150, library suite 550, battery 450, workflows and composites 300, lint extension 100, docs and ADR 250)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the brief fixes one slice per PR for S3, and the library is only meaningfully testable against its consumers. Pre-agreed seam if CI shows two red cycles from the battery rows: split the battery stage (Phase 6) into a follow-up commit series on the same PR, never a second slice.

## Guard Contract

### Guard 1 — The library's shape guard runs before any outbound request

**Property.** No value that is empty, holds a character outside `[A-Za-z0-9._~+/=-]`, or could break a `header = "..."` config line reaches curl's stdin config or argument list, and a refused call sends zero requests and prints one value-free marker.
**Assembly.** Every code path in `scripts/lib/bearer-curl.sh` that can run `curl`: `bc_curl` and the one internal `_bc_send` it funnels through (the chokepoint; a census row asserts the token `curl` occurs in the library only inside `_bc_send`); the values judged are every `SPEC` variable of the call, not only the first (the webhook triple has three); the header-name and prefix grammar of the specs; and `bc_hmac_sha256_hex`. The call-site population is derived from the workflow and composite step texts (any step sourcing the library), never a hand-kept list.
**Mutation matrix.**

| # | Mutation (edit the library or a call site) | Must go RED |
|---|---|---|
| 1 | delete the value check inside `_bc_send` | hostile-token rows: the quote/newline token reaches the shim's stdin as an `INJECTED` config line; the zero-call assertion fails |
| 2 | widen the class (add `"` or a space) | the byte-sweep superset row (bytes 0x01-0x7f through real curl) |
| 3 | move the check after the `curl` line | the ordering row (a refused call must show 0 recorded calls) |
| 4 | validate only the first `SPEC` and skip the rest (the second-member case: webhook triple with a hostile Cloudflare Access secret) | the hostile-second-spec row |
| 5 | add a second function that calls `curl` directly | the chokepoint census row |
| 6 | empty the derived call-site population (the guard's own dispatch) | the population floor (`-lt` literal, lower-case "anti-vacuity floor" text) |
| 7 | `bc_hmac_sha256_hex` signs an empty key (drop the `k or sys.exit(1)`) | the empty-key and python3-absent rows |

**Harness rows.** (a) the curl shim ignores `--config -` (stops reading stdin): the credential-on-stdin row must go RED; (b) the shim is calibrated against real curl by `--libcurl` (exactly one header append for the compliant form, a second `CURLOPT_URL` for a hostile value); (c) must-PASS inputs that are not the canonical: realistic shapes (an Anthropic-style key with `-` and `_`, a Resend `re_` key, a Sentry `sntrys_`-style token, a JWT with dots, a CF Access id ending `.access`) must be accepted, so a guard that rejects everything cannot pass; (d) a **negative canary**: a distinctive fake credential is planted and every captured stdout, stderr, step-summary and annotation line on every refusal, error and diagnostic path (including curl's own config-parse errors) is searched for it; (e) the suites run once in `ubuntu:24.04` (bash 5.2.21, curl 8.5.0) with identical row counts.
**Anchor.** The guard compares no stored value; its anchor is the derived call-site population plus baseline E equality (Rule E, existing), and a weakening of the class edits the library and its suite in one diff, so the merge-base diff and the CODEOWNERS rows on the library and its test are the independent review (reviewer gate, stated).

### Guard 2 — A refusal reaches the same verdict class as the old failure

**Property.** At every converted site, a refused credential produces the site's old verdict class (red step, soft verdict or warning) with the marker visible, never a silent skip, never a newly red job where the old failure was soft, and never a production action.
**Assembly.** The 19 converted sites, each covered structurally (calls the library, no credential on argv, argv-neutrality golden table for the non-credential arguments) and, where a bare refusal could land in a different verdict arm or the site is a class representative, run at its call site (the real `run:` body or a recorded slice whose drift from the live step text is pinned by a row) with the credential empty, unset and hostile, and for the HMAC representative with `python3` absent: `anthropic-preflight`, `notify-ops-email`, the inngest-health probe, the cutover flip precondition, one HMAC site, and one representative each of the red class (rung-2 or the sentry gate), the soft class (the census step) and the warning class (a drift email).
**Mutation matrix.**

| # | Mutation | Must go RED |
|---|---|---|
| 1 | route the `anthropic-preflight` refusal into the `000` soft-skip arm (drop the pre-guard) | the composite row: expects exit 1, got `ok=false` exit 0 |
| 2 | make `notify-ops-email` exit 1 on refusal, or swallow it without the annotation | the composite row and the AC2d window |
| 3 | remove the inngest-health pre-guard (let `CODE=000` reach the classifier) | the probe row: expects `secret_unset` and no restart verdict |
| 4 | restore `2>/dev/null` on the flip-precondition curl | the marker-visible row |
| 5 | a swapped `$(...)` tail without `|| VAR=""` at an HMAC site | the empty-key row: expects the marker and the arm's own verdict, got a mute abort |
| 6 | place `source` before `set +e` in a drift email step | `prod-version-drift-check.test.sh` B15c |
| 7 | a site branches on `rc == 2` | the `rule-audit` curl-init-failure row |

**Harness rows.** the shim's verdict capture reads the step's own `::error::`/`::warning::` lines (a harness that only checks the exit code cannot tell a mute abort from a refusal); a must-PASS well-formed run per representative proves the arm still succeeds; transport-failure rows use the real-curl oracle against a closed port (the `000000` quirk); at least one representative per class runs on the runner userland.
**Anchor.** the sink table in this plan is the review anchor (each row names the old and the new sink); the executed rows pin it mechanically.

## Implementation Phases

Order is guard-first, then conversions by blast radius, then the battery, then docs, then the baseline-only commit. Write each phase's failing rows BEFORE its change (`cq-write-failing-tests-before`).
Every command below prints counts or exit codes only: no credential value is printed, echoed or compared in the clear (compare with `[[ "$a" == "$b" ]]` or `cmp` and print the verdict only). Never type
`git stash`, and never match processes by pattern. Poll with Monitor, never `run_in_background`. The repo-wide Rule E run is **expected red from commit 2 until commit 8** (the baseline is stale until then);
the per-phase gate is the explicit-path run, and the baseline must not be regenerated early (open PRs 9529 and 9801 move neighbouring rows).

### Phase 0: Gates, measure, then RED

0. Gates before any edit: record the CPO sign-off (this plan's CPO assessment) in the PR description draft; record the lead's choice on the D3 alternatives in the decision file (default A); confirm the plan's counts still hold.
1. `git fetch origin main`; read `gh pr diff 9785` (anthropic-preflight) and `gh pr view 9794 --json files`; if either merged, `git merge origin/main` now. Re-run the census commands; record counts.
2. **Derive** the coupled-suite list on the real tree: `git grep -l` every converted file name and `notify-ops-email` / `anthropic-preflight` across `apps/web-platform/{infra,test,scripts}`, `plugins/soleur/test`, `scripts`, `tests`;
   run every hit (or `apps/web-platform/infra/run-registered-suites.sh`) read-only against a scratch conversion (a copy of the tracked tree outside the worktree), including `cutover-inngest-workflow.test.sh`,
   `terraform-target-parity.test.ts` (AC2d), `resend-sender-domain.test.ts` (from a tree with deps), `prod-version-drift-check.test.sh`, `tests/scripts/test-git-data-rung2-evidence-capture.sh`,
   `plugins/soleur/test/c4-count-parity.test.sh`. Record every red row. Any red row that needs an edit under `apps/web-platform/**` moves that site into the held-back set and is reported to the lead before continuing
   (counts are then re-derived; the plan is amended).
3. Credential-shape measurement, count only: classes held in Doppler (Hetzner, Cloudflare API, Sentry read, CF Access, deploy-webhook): read into a variable and test with a `case` glob, print the verdict only. Classes held **only** as
   GitHub secrets (`RESEND_API_KEY`, `ANTHROPIC_API_KEY`, `SENTRY_AUTH_TOKEN`, possibly the CF Access pair): Doppler cannot measure them. Default: the vendors' published key formats (`re_...`, `sk-ant-...`, `sntrys_...`) sit inside the
   class, the PR's own live `sentry-audit-gate` run measures `SENTRY_AUTH_TOKEN`, and the `notify-ops-email` refusal is an `::error::` annotation (D2). Optional, needs the lead's go (decision file): a temporary `pull_request` verdict job that
   prints `bc_ok` pass/fail per secret, added in a throwaway commit and dropped before the PR is marked ready. A failed measurement stops that conversion until the class is widened with evidence.
4. Toolchain: `docker run --rm ubuntu:24.04 bash -c 'bash --version | head -1; command -v python3 curl jq openssl'` and record versions (bash 5.2.21 / curl 8.5.0 expected); python3 must be present for D4.
5. Verify the inngest-health `secret_unset` routing: the `liveness-probe` issue class, its dedupe (one open issue per class) and the re-open behaviour, so a sustained refusal cannot file an issue every 15 minutes. Revert trigger recorded in the PR body:
   the first scheduled tick that turns red because of a refusal marker reverts the PR.
6. Next free ADR ordinal against `origin/main`, every `origin/*` ref and every open PR's files (`gh pr list --state open --json number,files`; PRs 9529 and 9787 hold 278 and 279 today); draft the RED rows (library suite, battery, plugin-test env row, lint extension) and record RED counts.

### Phase 1: the library, its suite, the ADR and CODEOWNERS (commit 1)

`scripts/lib/bearer-curl.sh` and `scripts/lib/bearer-curl.test.sh` (picked up by the `scripts/lib/*.test.sh` glob; verify with `scripts/lint-orphan-test-suites.sh`). Library rules: functions only, no top-level command beyond
definitions; each credential-binding function begins with `case "$-" in *x*) ... return 78 ;; esac`; `local LC_ALL=C`; no here-string or heredoc on key-derived data; allexport saved and restored where a key is handled; the
python snippet byte-equal to the S2 canonical string; no default timeout. Suite rows: shim-based contract (`--config -` models, auth-gated, INJECTED detection, calibrated against `curl --libcurl`); loopback real-curl end to end through
a one-shot Python `http.server` (request line, headers, body; byte-neutrality of the credential header versus the old `-H` form); hostile, empty and unset values for every spec position; the 0x01-0x7f byte sweep through real curl;
`--disable` is the first operand; xtrace refusal; chokepoint census; HMAC oracle against `openssl dgst -hmac` for an empty body and a JSON body plus RFC 4231 vectors and the empty-key / python3-absent behaviour; the negative canary;
floors in the form `if [[ $((PASS + FAIL)) -lt N ]]; printf 'anti-vacuity floor: ...'`. Run the suite with `trap '' PIPE`, with the config writer's stderr silenced **inside** the process substitution (`< <(printf ... 2>/dev/null)`).
Add `/scripts/lib/bearer-curl.sh` and `/scripts/lib/bearer-curl.test.sh` to `.github/CODEOWNERS` (`@deruelle`). Create ADR-280 via `soleur:architecture` (D12).

### Phase 2: composites and the plugin-test fix (commit 2)

`notify-ops-email` and `anthropic-preflight` per D2/D7. Read `gh pr diff 9785` again immediately before editing `anthropic-preflight`; leave the `PAYLOAD=` line byte-identical (a vitest in that PR extracts its model literal). Keep
`https://api.resend.com/emails` and the `--arg from "Soleur Ops <noreply@soleur.ai>"` line verbatim in `notify-ops-email`. Edit `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh` to supply `GITHUB_WORKSPACE="$REPO_ROOT"` in the
executor environment and extend its curl stub to read and record stdin and `$*`, so a row asserts the credential is on stdin and absent from argv. Rows: the composite executed end to end under the shim (2xx, non-2xx, transport failure through the
real-curl oracle, missing key, malformed key, **library absent**: `sent=false` and exit 1), AC2d regex windows re-checked.

### Phase 3: read-only and alert workflows (commit 3)

Rows 3, 7, 8, 10, 11, 12 of the census table. `scheduled-prod-version-drift.yml`: `source` after `set +e`. `kb-drift-walker.yml`: `FINDINGS_JSON` stays an argv `--data-raw` (findings, not a credential). `rule-audit.yml`: the `set +e` region keeps its
structure; `-I`, `-o /dev/null`, `-w`, `-D -` and `Accept` arguments stay; `2>/dev/null` dropped on the `UB_HDR` call. `scheduled-terraform-drift.yml`: the sweep step only.

### Phase 4: rehearsal workflow (commit 4)

Row 6, four sites, preserving the literals the rung-2 suite greps. Run `git-data-rung2-rehearsal.test.sh` after each edit.

### Phase 5: cutover, canary and inngest-health (commit 5)

Rows 4, 5, 9. HMAC via `bc_hmac_sha256_hex`; `canary-status.yml` gains the plain checkout and `contents: read` (D6); D5's stderr surfacing in both callers behind the `declare -F` guard; the `git-data-cutover.yml` flip-precondition curl drops
its `2>/dev/null`; the inngest-health probe pre-guard sits before the `for attempt` loop and the `|| echo "000"` tail is unreachable by a refusal. Run `git-data-cutover-access.test.sh` (about 3 minutes; give the tool an explicit long timeout),
`git-data-flag-precheck.test.sh`, `inngest-dedicated-host-classify.test.sh`, `inngest-host-state-workflow-guard.test.sh`.

### Phase 6: battery stage and the lint extension (commit 6)

Add stage `S3` to `tests/scripts/test-argv-bearer-sweep.sh`, **reusing** its curl shim, real-curl oracle and `CLASSIFIED` population mechanism (static-only members carry a justification and a row that goes RED when they become hermetically
reachable): a derived population of workflow and composite steps that source the library; per member the structural rows (calls the library, no credential on argv or in a child's environment except the HMAC key by design, argv-neutrality golden);
the Guard 2 verdict rows for the representative set; a row that fails when a recorded slice no longer matches the live step text; a source-path row (`"${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh"` only); the marker drift guard
(`bunx vitest run apps/web-platform/test/git-lock-marker-telemetry.test.ts`). Bump `EXPECTED_TESTS=410` in the same commit. **Extend `scripts/lint-workflow-local-action-checkout.py` and its suite** by one check: a job that uses either
composite or sources the library must have a usable checkout that includes `scripts/lib/` (no `path:`, no sparse cone excluding it), and the workflow must not be triggered by `pull_request_target`. Fixtures: any new suite that creates git fixtures uses
`plugins/soleur/test/lib/git-fixture-env.sh` (`git_fixture_env "$dir"`); every fixture write is guarded by the canonical `assert_fixture_dir` placed **below** the xtrace refusal; no pathological YAML is committed as a fixture (synthesize it in
the scratch dir at run time). If the battery now reads any `knowledge-base/` file, run `scripts/test-affected-kb-consumers.test.sh` and add covering edges to `AFFECTED_TESTS_SCRIPTS_ARGV_BEARER_SWEEP_PATHS` in
`scripts/lib/test-affected-paths.sh` (the converted workflow paths, `.github/actions/notify-ops-email/`, `.github/actions/anthropic-preflight/`, `scripts/lib/bearer-curl.sh`) instead of baselining.

### Phase 7: docs and tracking inputs (commit 7)

Update the Rule E docstring's S3 paragraph (converted file classes, the helper, the held-back file, the keying decision D8). Write ADR-280 final text (if not completed in Phase 1). Draft the tracker comments and the filed issues (Phase 10).
Add a one-line runbook note for the new `::warning::` in `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` only if the suite already pins its sentences; otherwise leave the runbook alone.

### Phase 8: verification on the runner userland

For every new or changed shell suite (`scripts/lib/bearer-curl.test.sh`, the battery, `heartbeat-reconcile-issue-step.test.sh`, `prod-version-drift-check.test.sh`, the lint suite): run once on the dev host and once in `ubuntu:24.04` (bash 5.2.21, curl 8.5.0) with
identical row counts. Never write a floor that is a count of one tool build (state floors as invariants over named character sets, and assign `${v//pat/repl}` replacements to a variable first). Run the repo-global ratchets by hand (no
consumer-grep selects them): `fixture-relative-assert`, `fixture-dir-operand-assert`, `lint-shell-capture-exit`, `lint-window-closure-assertion`, `lint-trap-tempfile-ownership`.

### Phase 9: pre-push gates, then the baseline-only commit (commit 8)

Ordering: (1) commits 1 to 7 on the branch, tree clean. (2) `git fetch origin main && git merge origin/main`; if another PR moved baseline E take `origin/main`'s copy of **both** the baseline and the ceiling table and regenerate. **This is the "merge commit
exists" step.** (3) `python3 scripts/lint-shell-trace-credential-refusal.py --write-baseline-e`. (4) In the same change delete the 12 converted files' rows from `scripts/fixtures/shell-trace-refusal/rule-e-census-ceiling.tsv`. (5) Commit steps 3 to 4 as the
baseline-only commit; `git status --short` shows nothing afterwards. (6) Run every gate below on the **committed** tree (new files tracked): the lints that enumerate with `git grep` pass on untracked files and fail in CI. (7) Push once. Any later merge
of `main` (a moved baseline row, PR 9785 landing during review) re-runs steps 2 to 7 including the ceiling table, and a last `git merge origin/main` plus the equality re-check runs immediately before `gh pr merge`.

Pre-push gates (owning suites directly; **do not run `scripts/test-all.sh` locally**):
- Rule E, explicit-path run over the 12 converted files and the library: `python3 scripts/lint-shell-trace-credential-refusal.py <paths>` (every rule, no baseline), then the repo-wide run (`python3 scripts/lint-shell-trace-credential-refusal.py`).
- `bash tests/scripts/test-argv-bearer-sweep.sh`; `bash scripts/lib/bearer-curl.test.sh`; `bash scripts/lint-shell-trace-credential-refusal.test.sh`.
- the grep-q pipe guard test; `bash scripts/lint-supabase-deprecated-endpoints.sh`; `bash scripts/lint-orphan-test-suites.sh`; `bash scripts/guard-vacuity-floor.test.sh`; `bash plugins/soleur/test/fixture-env-adoption.test.sh`; the fixture-relative and fixture-dir-operand ratchets.
- the workflow lints: `scripts/lint-workflow-errexit-capture.py`, `scripts/lint-workflow-run-body-syntax.py`, `scripts/lint-workflow-step-env-refs.py`, `scripts/lint-workflow-local-action-checkout.py` (and its suite).
- `python3 scripts/lint-skill-body-budget.py` and `python3 scripts/lint-rule-bodies.py --check` with `--base` the merge-base; `python3 scripts/lint-guard-contract.py` on this plan.
- `tsc --noEmit` for any changed `.ts` (none planned), `bunx vitest run apps/web-platform/test/git-lock-marker-telemetry.test.ts`.
- the infra and plugin suites derived in Phase 0, read-only; `bash plugins/soleur/test/c4-count-parity.test.sh`; `bash scripts/test-affected-kb-consumers.test.sh` when a `knowledge-base/` read was added.
- `gitleaks` over `origin/main..HEAD` (every fixture token synthesized; none resembles a real prefix).
- the apply-exposure check (script-checked): `git diff --name-only origin/main...HEAD` contains no path under `apps/web-platform/`, none of `.github/workflows/apply-*.yml`, `deploy-inngest-image.yml`, `restart-inngest-server.yml`, `web-platform-release.yml`, and not the held-back file.
- live pre-merge proof: the PR's own `sentry-audit-gate` run and the `board-status-sync` run on marking ready. A read-only `workflow_dispatch` smoke of `canary-status.yml` on the branch touches the production deploy host (a read) and needs the lead's explicit go first;
  the other dispatchable S3 workflows write (issues, emails, restarts, ingest) and are **not** dispatched.

### Phase 10: PR and tracking

PR title `fix(security): argv-credential sweep S3, workflow YAML and composite actions off the command line`; `Ref #9597`, `Ref #7797` (not `Closes`). The first body line states which pushes the merge fires (the plugin release run, via one test-file edit),
that no `apps/web-platform/**` file is in the diff, and that the merge changes what the alert steps of the release and apply workflows run next time (the operator-visible line). No plan or spec file paths in the body and no script named like `*-soak-*` (say "the
fourth converted probe" if that script must be named); avoid the words soak, outage, "Pro" and "subscription" in the body; the baseline arithmetic (28/61 -> 17/43, deletions only). Declare `Filed: #N ...` for every issue this PR files and, because it files issues,
the net-issue-flow override with **one justification per issue**. Issues to file: (1) the held-back `workspaces-luks-cutover.yml` conversion (blocked by its infra suite's curl stub; rides S4 with operator notice; **owner and deadline named**; worded "reads
`HCLOUD_TOKEN_READONLY` first and falls back to the read/write name until ADR-241 O10", never "read-only"), with `gh issue edit --add-blocked-by` where a blocker is known; (2) one post-merge first-run follow-through issue carrying the table below (owner, deadline merge + 3 days, and the
staged positive-control path if no alert fires). Comments: on #9597 (S3 done, corrected counts and the partition, new baseline, the fingerprint-keying decision, the apply-exposure finding, the plugin-release finding), and on #9757 (the Better Stack stderr item
done; the owner ticks the checkbox, the issue stays open).

## Baseline and ceiling rows

Rows leaving baseline E (files fully converted): `.github/actions/anthropic-preflight/action.yml 1`, `.github/actions/notify-ops-email/action.yml 1`, `.github/workflows/board-status-sync.yml 1`, `canary-status.yml 1`, `git-data-cutover.yml 1`,
`git-data-rung2-rehearsal.yml 4`, `kb-drift-walker.yml 1`, `rule-audit.yml 2`, `scheduled-prod-version-drift.yml 2`, `scheduled-terraform-drift.yml 1`, `sentry-audit-gate.yml 1` (11 rows leave, 16 sites); `scheduled-inngest-health.yml` goes 3 -> 1 (the held-back probe step keeps one; 2 sites removed). Rows staying:
`workspaces-luks-cutover.yml 1` and `scheduled-inngest-health.yml 1`. Net: 18 sites removed. Result: **17 files / 43 sites** (derived at ship; the earlier 16/42 figure predated holding the inngest-health probe step back). The ceiling table loses the same 11 rows and lowers `scheduled-inngest-health.yml` to 1 in the same change. No row enters. Neither file is edited before the merge-from-main commit exists.

## Test Scenarios

1. A well-formed credential reaches the shim on stdin only, in every converted site; the recorded argv never contains it, and no child's environment holds it except the HMAC key by design (a per-command prefix on the `python3 -I` child).
2. **Negative canary.** A credential holding `"`, a backslash, CR, LF, a tab, a space, an empty value or an unset variable: zero calls, one marker, the site's old verdict class; the planted fake value appears in no stdout, stderr, step summary or annotation on any refusal, error or diagnostic path (including curl's own config-parse errors and the Better Stack warning).
3. A hostile value that tries to inject a second config line (`x" \n url = "http://evil`): refused, never a second `CURLOPT_URL` (real-curl oracle).
4. The deploy-webhook triple with the signature valid and each Cloudflare Access value hostile in turn.
5. `bc_hmac_sha256_hex` with the key empty, unset, and `python3` absent at `canary-status` and the inngest-health probe: marker and the arm's own verdict, never a mute abort; and the inngest-health refusal never reaches the `inngest_down` arm.
6. `notify-ops-email` end to end: 2xx -> `sent=true`; non-2xx -> warning, `sent=false`, exit 0; transport failure (real curl, closed port) -> same; missing key -> exit 1; malformed key -> `::error::` annotation + marker, `sent=false`, exit 0; library absent -> `sent=false`, exit 1.
7. `anthropic-preflight` end to end: 200 -> `ok=true`; billing 400 -> `ok=false`; 5xx -> `ok=false`; real transport failure -> the existing behaviour (documented `000000` quirk, red); malformed key -> exit 1 (not `ok=false`).
8. Better Stack reader exit 2 with the marker on stderr: the dedicated-host arm still grades `__UNREADABLE__`/probe-unavailable and prints one `::warning::` carrying `reader-refusal`; the cutover assertion retries as before and prints the warning once per failed read; with the library absent from a fake workspace both steps behave exactly as before.
9. Source-path closure: all 26 composite call steps resolve the library (lint); no caller or converted workflow is `pull_request_target`; the one `ref:` checkout (`fix-constraints-stage-a.yml`, PR head) resolves it from the same tree as the composite.
10. Runner parity: every new or changed suite green in `ubuntu:24.04` with the same row counts.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `python3 scripts/lint-shell-trace-credential-refusal.py` repo-wide exits 0 with baseline E equal to the pre-slice baseline minus the converted rows (derived: **17 files / 43 sites** with the final partition) and the ceiling table equal; the explicit-path run over the converted files and the library reports 0 findings (all rules A to E).
- [ ] `scripts/lib/bearer-curl.sh` exists with `bc_ok`, `bc_curl`, `bc_hmac_sha256_hex`, one `_bc_send` chokepoint, an xtrace refusal in each credential-binding function, no `exit`, and no default timeout; its suite is green on the dev host and in `ubuntu:24.04` with identical row counts.
- [ ] No S3 file keeps `-hmac` in a credential operand or `2>/dev/null` on a converted curl; the converted files contain no `Authorization: Bearer`, `x-api-key`, `X-Signature-256`, `CF-Access-Client-*` or `X-Soleur-Kb-Drift-Signature` inside any curl argument list.
- [ ] Every converted site is covered structurally (derived population: calls the library, no credential on argv, argv-neutrality golden), and the Guard 2 representative set runs at the call site (real step body, or a recorded slice with a row that fails when the slice no longer matches the live text) with the credential empty, unset and hostile, asserting zero calls, the marker once and the site's verdict class; the HMAC representative also with `python3` absent.
- [ ] `anthropic-preflight` with a malformed key exits 1 (red), never `ok=false`; `notify-ops-email` with a malformed key exits 0 with `sent=false` and an `::error::` annotation; its missing-key exit 1 and both AC2d regex windows still hold; the library-absent row passes for both composites.
- [ ] The inngest-health probe with a malformed signature or Cloudflare Access value records `secret_unset` and never reaches `inngest_down`.
- [ ] `git diff --name-only origin/main...HEAD` shows no path under `apps/web-platform/`, none of the apply/release/inngest push workflows, and the held-back file is not in the diff; the PR body names the plugin release run.
- [ ] `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh`, `scripts/prod-version-drift-check.test.sh`, the derived infra and plugin suites (read-only, unedited), `terraform-target-parity.test.ts` and `resend-sender-domain.test.ts` are green.
- [ ] `lint-workflow-local-action-checkout.py` (extended) is green and its suite covers the new check (usable checkout including `scripts/lib/`; no `pull_request_target`).
- [ ] The `anthropic-preflight` `PAYLOAD=` line is byte-identical to `origin/main`'s at the time of the last merge; if PR 9785 merged first, the merge resolved by keeping its model literal.
- [ ] The marker drift guard and `c4-count-parity` pass; `EXPECTED_TESTS` in the battery was raised with the new rows and the new floors are in the harness form (`-lt N` literal, lower-case "anti-vacuity floor").
- [ ] CODEOWNERS has rows for the library and its suite; `scripts/lint-orphan-test-suites.sh` is green; ADR-280 exists with status `adopting` and an ordinal re-verified at ship.
- [ ] The two Better Stack callers print a `::warning::` on a refused read and their verdict output is byte-identical to before on a successful read (executed rows).
- [ ] `Ref #9597` and `Ref #7797` present, no `Closes`; every issue the PR files is declared with `Filed: #N ...` and the net-issue-flow override carries one justification per issue; no plan or spec path and no `*-soak-*` name in the body.
- [ ] CPO sign-off recorded; `soleur:engineering:review:user-impact-reviewer` ran at review time.

### Post-merge (verification, no SSH)

First-run proof table (owner: the lead's session or the operator; deadline: merge + 3 days; read run logs with `gh run list` / `gh run view --log` filtered to markers and conclusions only; **no Better Stack row is claimed as evidence**, the marker is not shipped there):

| Surface | Trigger and first proof | Unproven until |
|---|---|---|
| `scheduled-inngest-health` | next */15 tick: green, no `SOLEUR_CREDENTIAL_REFUSED`, no new `liveness-probe` issue | the first tick |
| `scheduled-prod-version-drift` | next hourly tick green; a clean tick sends no email | the first tick (email path: below) |
| `kb-drift-walker` | 03:00 UTC run green (ingest 2xx) | the next 03:00 |
| `rule-audit` | next 1st/15th run, or a manual dispatch with the lead's approval (it files issues) | the next scheduled run |
| `board-status-sync`, `sentry-audit-gate` | exercised live on this PR (pre-merge) | pre-merge |
| `scheduled-terraform-drift` sweep job | the next Inngest-cron dispatch | the next dispatch |
| `canary-status`, `git-data-cutover` precondition, `git-data-rung2-rehearsal` | dispatch-only: **unproven until next use**; optional read-only `canary-status` dispatch with the lead's go | next use |
| `anthropic-preflight` (3 callers) | first run of `claude-code-review`, `fix-constraints-stage-a` or `test-pretooluse-hooks` after merge: `ok=true`, no refusal | the first caller run |
| `notify-ops-email` (24-step alert paths) | the plugin release run caused by this merge, then the log line `Email notification sent to ops@jikigai.com (HTTP 2xx)` from the first real alert. The default is a one-off positive-control dispatch to the operator's own address with the operator's approval (a real alert may not fire within the deadline); the fallback is to revert the composite commit (D11, commit 2) | the first delivered email |

- [ ] The plugin release run caused by this merge concludes green.
- [ ] The table above is filled in on the follow-through issue; the held-back-file issue is open with an owner, a deadline and the S4 dependency.
- [ ] Tracker comments posted (Phase 10).

## Observability

```yaml
liveness_signal:
  what: the converted scheduled workflows keep running green (scheduled-inngest-health every 15 minutes, scheduled-prod-version-drift hourly) and print no SOLEUR_CREDENTIAL_REFUSED line
  cadence: every 15 minutes (inngest-health), hourly (version drift), daily (kb-drift-walker)
  alert_target: the existing paths, unchanged (the inngest-health issue loop and Sentry cron monitor, the drift workflow's issue and email, the Actions failure notification)
  configured_in: .github/workflows/scheduled-inngest-health.yml, .github/workflows/scheduled-prod-version-drift.yml, .github/workflows/kb-drift-walker.yml
error_reporting:
  destination: the GitHub Actions run log (value-free marker SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<token_shape|control_char>) plus the site's own verdict (red step, soft verdict, warning or error annotation)
  fail_loud: yes for the red-class sites (anthropic-preflight, cutover precondition, rehearsal arms, sentry gate, board sync, canary read); notify-ops-email prints an error annotation and sets sent=false while keeping its exit 0 contract
failure_modes:
  - mode: a credential fails the shape guard (rotation produced a new alphabet, or a hostile value)
    detection: marker line in the run log; the executed rows pin the verdict class per representative site
    alert_route: the site's existing alert (red job, issue, delivered=0 error, sent=false annotation)
  - mode: the library cannot be sourced from the job checkout
    detection: hard ::error:: and exit 1 in the composites and steps; the lint closure over all 26 composite call steps
    alert_route: red job
  - mode: the Better Stack reader refuses a credential (exit 2) in inngest-health or git-data-cutover
    detection: ::warning:: with the reader-refusal class and the scrubbed first stderr line
    alert_route: existing __UNREADABLE__ / retry-exhaustion verdicts, now with a cause in the log
logs:
  where: GitHub Actions run logs
  retention: the repository's Actions log retention
discoverability_test:
  command: python3 scripts/lint-shell-trace-credential-refusal.py .github/actions/notify-ops-email/action.yml .github/actions/anthropic-preflight/action.yml .github/workflows/canary-status.yml
  expected_output: OK:
```

Layer citation (`hr-observability-layer-citation`): layer 6 (the workflow run log and the Actions annotations). The marker is mirrored only by the agent PostToolUse extractor, not paged and not shipped to Better Stack; the plan does not claim otherwise.

## Domain Review

**Domains relevant:** engineering (security hardening of CI), operations (alert-path reliability)

### Engineering (CTO)

**Status:** reviewed (carried from the S1/S2 assessments and re-applied; the headless architecture review of 2026-10-09 added the composite trust-boundary check, the plugin-release finding, the stub-holder derivation and the ADR)
**Assessment:** the shared sourced library is the right shape for workflow-side conversions because every workflow job has a checkout and the composites resolve against the same workspace; the single `_bc_send` chokepoint makes the ordering structural. The infra-suite coupling is the one real constraint on the slice; holding the one affected file back keeps the apply exposure at zero. The 24-caller composite blast radius is the main residual and is covered by an end-to-end composite row, a lint closure and the post-merge first-run table.

### Operations (COO)

**Status:** reviewed
**Assessment:** the composites sit on alert paths; a refusal that silently drops an alert is the failure to prevent (D2). No change to credential rotation (ADR-241 O13 and #9294 cover the classes). The first real alert email after merge is the live proof, with a bounded fallback.

### Product (CPO)

**Status:** reviewed. **Sign-off: yes-with-conditions**, conditions applied (see User-Brand Impact). No Product/UX surface: no user-facing page, flow or copy changes.

## Plan Review Revisions (headless panel, 2026-10-09)

Panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CPO (the 5-agent baseline plus CPO for the single-user threshold; CMO, UX and CTO lenses not relevant: no market, design or developer-surface change).
Classification per ADR-084: engineering-panel findings with one right answer were applied (Mechanical); scope-shaped or reversible-judgment findings are persisted to the decision file (Taste / User-Challenge).

- **Applied (mechanical):** the post-merge Better Stack criterion could not fail (replaced by run-log greps); the plugin release run is fired by one test-file edit (MERGE EFFECTS row, PR body line); `source` after the missing-key block and a `sent=false` failure arm in the notify composite; Phase 0 derives the stub-holder list (five more suites run green); `|| echo "000"` in the inngest-health probe would map a refusal to `inngest_down` (pre-guard before the loop); the `000000` curl quirk (real-curl rows); refusal on `notify-ops-email` as an `::error::` annotation; ordering of the baseline commit and later merges of main; counts stated as derived; first-run proof table with owner and deadline; Phase 0 gate step for CPO sign-off and the D3 choice; the `pull_request_target` assertion and library-source closure as a lint extension; GitHub-only secret shape measurement path; rc-2 collision with curl's init failure documented; ADR-280 as a plan deliverable; dropped the default `--max-time` (byte-neutral); one N-spec `bc_curl` instead of three wrappers; pre-guards only where a bare rc lands in a different arm; Guard 2 of the first draft (a restatement of Rule E) dropped; per-site rows scoped by class; reuse of the existing `CLASSIFIED` mechanism; remedy-text rewrite cut; plain checkout for `canary-status.yml`.
- **Persisted to the decision file (Taste / User-Challenge):** D3 hold-back versus alternatives B and C (User-Challenge: drops lead-listed scope by default); `canary-status.yml` held back to S4 as the review proposed (User-Challenge: drops lead-listed scope); HMAC moves kept as `inferred` (Taste); the optional temporary verdict job for GitHub-only secrets and the optional active alert-path positive control (Taste: each needs the lead's go); the `rule-audit` anonymous-token conversion kept (Taste, review split two ways).

## Open Code-Review Overlap

3 open code-review issues name files in this plan: #8593 (`scheduled-inngest-health.yml`, probe-gate window narrower than the truncation property it names): **acknowledge**, a different concern (the 500-row window), the D5 edit does not touch it. #8800 (`scripts/lib/test-affected-paths.sh`, census sandbox shares inodes with the live repo): **acknowledge**, this plan only adds edge rows to an existing array. #3321 (`.github/CODEOWNERS`, learnings subtree coverage): **acknowledge**, this plan adds two unrelated rows.

## Files to Edit

- `.github/actions/anthropic-preflight/action.yml` (PR 9785 collision)
- `.github/actions/notify-ops-email/action.yml`
- `.github/workflows/board-status-sync.yml`
- `.github/workflows/canary-status.yml` (also: checkout, permissions)
- `.github/workflows/git-data-cutover.yml`
- `.github/workflows/git-data-rung2-rehearsal.yml`
- `.github/workflows/kb-drift-walker.yml`
- `.github/workflows/rule-audit.yml`
- `.github/workflows/scheduled-inngest-health.yml`
- `.github/workflows/scheduled-prod-version-drift.yml`
- `.github/workflows/scheduled-terraform-drift.yml`
- `.github/workflows/sentry-audit-gate.yml`
- `.github/CODEOWNERS`
- `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh`
- `tests/scripts/test-argv-bearer-sweep.sh`
- `scripts/lint-workflow-local-action-checkout.py` and `scripts/lint-workflow-local-action-checkout.test.sh`
- `scripts/lint-shell-trace-credential-refusal.py` (docstring only)
- `scripts/lint-shell-trace-credential-refusal-e.baseline.txt` (regenerated last)
- `scripts/fixtures/shell-trace-refusal/rule-e-census-ceiling.tsv` (12 rows removed)
- `scripts/lib/test-affected-paths.sh` (edges, only if the battery gains a `knowledge-base/` read or new tracked inputs)

**Not edited, deliberately:** `.github/workflows/workspaces-luks-cutover.yml` and `apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh` (D3); `apps/web-platform/infra/git-data-cutover-access.test.sh` (PR 9794);
anything under `apps/web-platform/**`; `scripts/cutover-inngest.sh` and `ci-deploy.sh` (adjacent worktrees).

## Files to Create

- `scripts/lib/bearer-curl.sh`
- `scripts/lib/bearer-curl.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md` (ordinal provisional)

## Risks and Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only filler text, or omits the threshold fails `deepen-plan` Phase 4.6; this plan's section is complete and the threshold is `single-user incident`.
- `set -euo pipefail` plus a swapped substitution tail aborts mute: the default rule (rc 2 is a curl failure, red with the marker visible) is acceptable only where the old failure was red; every other site carries a pre-guard (Guard 2 rows 3 and 5).
- The `source` line placement is constrained by `prod-version-drift-check.test.sh` B15c (after `set +e`), by AC2d (after the missing-key block in the notify composite) and, in `canary-status.yml`, by the checkout step ordering; a helper inserted above a
  script's xtrace refusal fails Rule A.
- A converted `$(...)` that swaps a pipe tail for the helper changes the exit status of the pipeline under `pipefail` (rc 2 versus the old tail's 0); re-read each site's old and new status.
- PR 9785 and the adjacent worktree's HMAC work: do not touch `ci-deploy.sh` or the cutover script; merge main before the baseline commit and again before merge.
- The `heartbeat-reconcile-issue-step.test.sh` edit fires the plugin release run on merge; merge when no other release is in flight.
- Everything printed in this slice is counts, exit codes, marker names and class tokens; a comparison of a secret with an expected value goes through `[[ ... == ... ]]` or `cmp`, never through output.

## Work-Phase Addendum (2026-10-09)

Appended, not edited in place. Deviations found while implementing, each measured:

- **The `scheduled-inngest-health.yml` `probe` step is held back to S4 (second held-back site).** Converting it (HMAC key and header onto the library) reddens 12 rows of
  `inngest-dedicated-host-classify.test.sh`, which executes the real step in a fake workspace with no library and stubbed `openssl` and `curl`. Fixing that suite is an
  `apps/web-platform/infra/**` edit, so it fires the production push apply. The census calls and the dedicated-host reader's stderr surfacing (the #9757 item) DO convert.
  Result: 11 files fully converted, 1 partially (that file keeps 1 site), 1 held back whole. Baseline E ends at **17 files / 43 sites** (not 16 / 42).
- **`bc_refuse SCRIPT VAR` added to the library** so a site's own pre-guard prints the identical value-free line and marker as the chokepoint.
- **Battery stage S3 does not reuse the shim or the `CLASSIFIED` mechanism**: it carries its own small recording shim (calibrated against `curl --libcurl` in the library suite) and a derived
  manifest, because the existing shim's auth profiles do not model `x-api-key` or the Cloudflare Access pair and its `CLASSIFIED` keys off the followthrough population.
- **Population floor for the library surface lives in the lint suite's live row** (>= 20 library-consuming steps; 36 today), not in the lint (a fixture tree legitimately has few).
- Known environmental reds on the unmodified base, unrelated to this slice: `git-data-runcmd-rehearsal.test.sh` (4 container-fixture rows).

## Fix-Round Addendum (2026-10-09, review round 1)

A fix-round review (security, test-design, architecture, pattern, code-quality, performance) reported no P1 in the code and two vacuous library
test rows; all findings were fixed inline. What changed against this plan, so the earlier text is read as superseded where it disagrees:
- The composite call-step count is 26 (23 + 3) in 16 workflow files, and the union of workflows that source the library directly or call a
  library composite is 22 (the earlier 24 / 14 / 12 figures counted differently). The blast-radius statement in ADR-280 uses the union.
- The transport is not "byte-neutral" (see Acceptance criterion 4 above); the library's `_bc_tail_ok` now parses short clusters and attached
  values, and its env scrub is the union of two existing precedents. It remains a guard against a caller's mistake, not a boundary.
- The probe pre-guard (restart mapping) and the probe HMAC belong to the held-back probe step and are S4 obligations; mutant row 3 and the
  pre-guard rows above that describe them as built in S3 are superseded. The S4 issue must carry them.
- The lint's untrusted-ref rule is a fail-closed allowlist of the default ref (not a head-ref pattern list), the sparse-cone check is by
  path segment with negation refused, and the composite set is derived by the basename of the library, including nested directories.
- Pre-existing intermittent observed once in four runs of the sweep battery (an older stage's evaluator row reported an extra `bash-error`);
  it did not reproduce on the next three runs and is not touched by this slice.
