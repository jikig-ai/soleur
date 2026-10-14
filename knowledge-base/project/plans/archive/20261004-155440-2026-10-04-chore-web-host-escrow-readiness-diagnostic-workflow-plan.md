---
title: "infra: unattended read-only web-host escrow readiness diagnostic workflow"
date: 2026-10-04
slug: chore-web-host-escrow-readiness-diagnostic-workflow
branch: feat-one-shot-escrow-config-check-workflow
issue: 9377
type: chore
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: []
refs: [9377, 9461, 9448]
lane: cross-domain
---

# infra: unattended read-only web-host escrow readiness diagnostic workflow

## Enhancement Summary

**Deepened on:** 2026-10-04
**Agents used:** learnings-researcher, functional-discovery, CTO, CPO (domain), then plan-review (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow), then deepen passes by security-sentinel, observability-coverage-reviewer, user-impact-reviewer, best-practices-researcher and a baseline-suite runner.

### Key improvements

1. **Shape test moved to a required check.** `infra-validation.yml`'s infra suites are not in the CI Required ruleset; the suite now lives in `plugins/soleur/test/` (required `test` shard), with no shard-manifest or path-filter edits.
2. **Observability probe fixed.** The first draft's command used a pipe and `&`, which preflight Check 10 refuses; it is now a single `curl` printing `total_count` or `Not Found` (measured live), and every failure mode cites the workflow run log layer.
3. **Residual stated at true strength.** No ruleset requires review, the main-only policy is nominal until R1, the token can write, any repo writer can dispatch, and `add-mask` does not reach the job summary; CODEOWNERS rows, the C4 edge edit and the #8209 inventory row were cut as decorative.
4. **Summary hardened.** Redaction applied once before log and summary, `unreadable` lines cut to the config name, ref name character-allowlisted, UTC time and SHA printed, stale-green rules in the runbook, NO TOKEN is a single cause (the loader runs Tier-B only), `exec` and `$(compgen)` forms removed.
5. **User-challenge recorded.** The security review's narrower direct read of `DOPPLER_TOKEN_TF` conflicts with the brief's loader direction; kept the loader, filed the alternative.

### New considerations discovered

- The preflight's `prd_terraform` fallback is dead after O10; the loader export is the only working route.
- The allowlist is hygiene against accidental inheritance, not a boundary (`/proc/$PPID/environ`).
- First dispatch is the real test of the allowlist against the real Doppler CLI and of the Tier-B project's token entry.

## Overview

`bash scripts/check-web-host-escrow-config.sh --live` (C8 of #9377) lists secret NAMES in the Doppler configs `prd` and
`prd_workspaces_luks_web`. It needs a workplace-scope Doppler token and refuses an ambient login. Today it runs in CI only
as a step of `web_host_create` and `web_host_replace` in `apply-web-platform-infra.yml` (via
`scripts/web-host-escrow-preflight.sh`), behind a reviewer approval and in front of Terraform. An agent therefore cannot ask
"is escrow ready?" before it starts a birth, and the runbooks' step 0 sends a person to run the command with a token read
from a config that no longer holds it (see Credential Resolution).

This change adds ONE dispatch-only workflow, `.github/workflows/web-host-escrow-diagnose.yml`, that loads credentials
through `.github/actions/infra-credentials` on the `infra-privileged` environment, runs
`bash scripts/web-host-escrow-preflight.sh` and nothing else, and writes the verdict plus the missing-name causes to the job
summary. It has no Terraform, no write of any kind, `permissions: contents: read`, no schedule. It also updates step 0 of
the two runbooks, adds an ADR-241 dated note, and adds a shape test. It does NOT dispatch the workflow: the first
dispatch is the post-merge next step (a `workflow_dispatch` file must be on `main` first, and ADR-241 R3 refuses a branch-ref
dispatch of a Tier-B environment).

`Ref #9377 and #9461`, never `Closes`: the live R2 mint and the reviewed push-apply stay open on #9377, and #9461 keeps its
scope for the birth/replace jobs (see Risks).

## Research Insights

### Premise Validation

Checked before research. Held: #9377 and #9461 are OPEN; PR #9448 is on `origin/main` (`scripts/web-host-escrow-preflight.sh`
and `scripts/check-web-host-escrow-config.sh` exist with the behaviour the brief states: env token wins, dp.pt shape check on
the fallback only, `add-mask`, xtrace refusal, `ESCROW_ADVISORY=count`, exit 0/1/2/3). The `infra-privileged` environment
exists with a custom branch policy and no reviewers (`gh api .../environments/infra-privileged`: `custom_branch_policies:true`,
protection rules `branch_policy` only) and holds exactly the secrets `DOPPLER_TOKEN_INFRA_APP`, `DOPPLER_TOKEN_INFRA_PRIVILEGED`,
`DOPPLER_TOKEN_WRITE` (names only). Stale or corrected: the brief's mechanism "a scheduled run if the drift pattern makes it
natural" does not hold: `scheduled-terraform-drift.yml` has NO `schedule:` trigger (header: Inngest-dispatched via
`apps/web-platform/server/inngest/functions/cron-terraform-drift.ts`, ADR-033), so a scheduled escrow run would need a TS Inngest
function, a trigger-cron allowlist entry and a monitor. Declined (Cut List). ADR corpus: ADR-241 D2 already defines
`infra-privileged` as the unattended Tier-B environment and records each added consumer as a dated note (#6604 step 7, #9262);
nothing in its rejected alternatives covers a read-only diagnostic consumer.

### Property List (what the ask buys)

1. P1. An agent can obtain the escrow-config verdict in one dispatch with no human approval step and no Terraform.
2. P2. None of this workflow's steps changes anything: no Terraform, no Doppler write or mint, no GitHub write, `contents: read` (the token itself could write; read-only is a property of the steps).
3. P3. The workplace-scope token reaches only the checker's process: never argv, a file, `GITHUB_ENV` written by this workflow's own steps, or a log/summary line.
4. P4. The verdict and the missing-name causes are readable from the run page (job summary) without opening the raw log, on a public repo, names and fixed sentences only.
5. P5. Any non-zero checker result fails the run; an unreadable, empty or unknown result is never read as ready.
6. P6. The runbooks tell the next reader to dispatch this workflow rather than reproduce the check by hand.

### Cut List

| Mechanism | Property it buys | What already covers it / why cut |
|---|---|---|
| Scheduled run (Inngest-dispatched, like the drift check) | early warning of config drift between births | Escrow readiness only matters at birth/replace time; a dispatch gives a fresh answer then (CPO assessment). Needs a TS function, allowlist entry and monitor: out of proportion. Re-evaluation trigger recorded under Deferred. |
| A new narrow Doppler project / read token for the check | smaller token reach (#9461) | Excluded by the brief (no mint). #9461 stays open for the birth/replace jobs. |
| A direct single-name read of `DOPPLER_TOKEN_TF` with `DOPPLER_TOKEN_INFRA_PRIVILEGED` | avoids exporting the whole project to `$GITHUB_ENV` | A new Tier-B read site outside the loader: invites census edits in a 3,500-line suite. Against a malicious `main` merger the reach is identical (the job holds the same service token); against an accidental leak or a compromised CLI it is smaller (one token instead of the whole project), which the security review of this plan stressed. Loader reused because the brief directs it; the alternative is recorded as a user-challenge in `decision-challenges.md`. |
| A new checker mode or a new wrapper script | a summary-friendly output | `scripts/web-host-escrow-preflight.sh` already prints the verdict, the CAUSE/NOTE/FAIL lines and annotations; the workflow step post-processes its stdout. |
| `workflow_dispatch` inputs (host filter, advisory level) | flexibility | Every input is injection surface on a token-holding job; none is needed. |
| `ESCROW_MODE=read-only` guard env (suggested by the learnings sweep) | defence in depth | The shape test pins the structural read-only posture (no terraform, no writes, `contents: read`); an env flag that nothing consumes is a second progress signal that can disagree with the file. |

Cut at plan review (5-agent panel: DHH, Kieran, code-simplicity, architecture, spec-flow; CTO and CPO consulted earlier):

| Mechanism cut | Why |
|---|---|
| `.github/CODEOWNERS` rows | The default `*` rule already names the same owner and no ruleset requires code-owner review (verified with `gh api repos/jikig-ai/soleur/rulesets`), so the rows add no reviewer and the "two-reviewer edit" claim was false. |
| `model.c4` clause + regenerated `model.likec4.json` | The edge describes no element or count this changes; the ADR note and runbook step 0 carry the fact. (Taste item: the CTO suggested the clause.) |
| `infra-credential-tiers-8209.md` inventory row | That table's scope is jobs referencing `DOPPLER_TOKEN`, `DOPPLER_TOKEN_PRD`, `DOPPLER_TOKEN_WRITE` or `DOPPLER_TOKEN_GIT_DATA_ROOT`; this job references none of them. |
| `concurrency:` block and per-step `timeout-minutes` | Serialises nothing; the job-level timeout bounds the run. |
| Second deferral issue (narrow credential) | Already tracked by #9461. |
| Mutation rows for the cap, case-count over-pinning and the rc 78 / unlisted-code duplicate | Trimmed to rows that map to P2, P3, P5 (rc 78 kept as the one `SHELLOPTS` row). |

### Credential Resolution (the open question, settled from repo text and names only)

The check needs a token that lists names in BOTH `prd` and `prd_workspaces_luks_web` (a config-scoped or project-scoped
service token exits 3). Evidence, by candidate:

| Candidate | What it reads (source) | Reaches both configs? |
|---|---|---|
| env secret `DOPPLER_TOKEN_INFRA_PRIVILEGED` | A read service token bound to Doppler project `soleur-infra-privileged`, config `prd` (loader `action.yml`: `doppler secrets download -p soleur-infra-privileged -c prd`; ADR-241 D3 "Its read service token is the environment secret DOPPLER_TOKEN_INFRA_PRIVILEGED") | No. It reads only the carrier project. |
| env secret `DOPPLER_TOKEN_INFRA_APP` | Project `soleur-infra-app/prd`, the two App values only (ADR-241 D11, model.c4 edge) | No. |
| env secret `DOPPLER_TOKEN_WRITE` | Repo secret, read/write on `soleur/prd_terraform` (Tier A, branch-reachable; census `ENV_SECRETS`) | No, and it must not be used: it is write-capable and branch-planted-value reachable. |
| **loader output `DOPPLER_TOKEN_TF` / `TF_VAR_doppler_token_tf`** | The loader (Tier-B arm) downloads the whole `soleur-infra-privileged/prd` project, which ADR-241 D3 lists as holding `DOPPLER_TOKEN_TF` ("a workplace **personal** token that reads every Doppler project", ADR-241 Context), and exports every name plus its `TF_VAR_` lowercase twin through `$GITHUB_ENV`, masked per line. `DOPPLER_TOKEN_TF` is expressly NOT filtered as metadata (loader test row 4). | **Yes.** This is the token `scripts/web-host-escrow-preflight.sh` already prefers (`TF_VAR_doppler_token_tf`, "the environment token wins"). |
| preflight legacy arm (read of `DOPPLER_TOKEN_TF` from `soleur/prd_terraform`) | The runbook O10 loop deletes `DOPPLER_TOKEN_TF` from `prd_terraform`; ADR-241 records O10 as executed (2026-10-01 amendment: "O10 replaced `GITHUB_APP_PRIVATE_KEY` in `soleur/prd_terraform`..."). | Dead. After O10 this arm cannot yield a `dp.pt.*` value, so the loader's Tier-B export is the ONLY working route. |

Answer: no environment secret on `infra-privileged` reads both configs by itself. What supplies the token is the existing
loader's Tier-B export of `DOPPLER_TOKEN_TF`, delivered through the project that `DOPPLER_TOKEN_INFRA_PRIVILEGED` reads. No
credential is minted; nothing outside the repo's own mechanism is invented. Two things are NOT verified from names alone and
the first dispatch (post-merge) settles them: (a) that the seeding step O2 put `DOPPLER_TOKEN_TF` into
`soleur-infra-privileged/prd` (the ADR requires it; if absent the preflight exits 2 and the summary says NO TOKEN), and (b) that the O13 rotation of that personal token (if done) left a valid value there (an invalid one reads
as exit 3 `unreadable`).

Consequence stated honestly: the loader exports the WHOLE Tier-B project (read/write Hetzner token, R2 key, App key, state keys)
into the job's `$GITHUB_ENV`, masked. This workflow's own steps write nothing to `$GITHUB_ENV` or any file; the loader's
existing, ADR-241-sanctioned export is the only carrier of the token, and the checking step reduces its environment to an
allowlist before the preflight starts (below).

### Repo and learnings findings carried into the design

- Loader pair-handling: every existing caller passes `doppler-token-legacy`; this workflow passes ONLY `doppler-token-infra-privileged`, so the loader's legacy arm cannot be taken: a missing Tier-B secret fails loudly with `verdict=no_credential_source` instead of continuing on a Tier-A token.
- Pattern copied from `scheduled-terraform-drift.yml` (`environment: infra-privileged`, SHA-pinned `actions/checkout` v4.3.1 `34e114876b0b11c390a56381ad16ebd13914f8d5`, the loader `uses:` step) and from `git-data-rung2-rehearsal.yml` (`permissions: contents: read`, per-step `timeout-minutes`).
- Learning `2026-07-17-inert-until-dispatched-verify-steps-are-false-green-vectors-only-review-catches.md`: a workflow with zero in-PR executions needs a behavioural test that EXECUTES the step body, and every `|| true` on a verdict path is guilty until proven benign. The step captures the preflight rc with `|| rc=$?` and ends in `exit "$rc"`; the two `|| true` guard the unset loop and the presentation pipeline's no-match grep (S14 pins at most two).
- Learning `2026-09-21-my-escrow-suite-stubbed-the-one-tool-that-would-have-refused-it.md`: the behavioural test runs the REAL preflight and REAL checker behind a Doppler stub that refuses anything the wrapper must not call (the existing `scripts/web-host-escrow-preflight.test.sh` pattern), not a stub of the preflight.
- Learning `2026-03-20-process-env-spread-leaks-secrets-to-subprocess-cwe-526.md`: deny-by-default environment for the child, which is the allowlist step below. The learnings sweep also suggested `actions: write` and an `ESCROW_MODE` flag; both are rejected (no workflow is dispatched or read by this one, and see the Cut List).
- Open code-review overlap: see that section (none relevant).

### Census, size and lint gates (what each needs for a new workflow file)

Read from the tests themselves, not from names. "Verify" items are run in the work phase (they cannot run before the file exists).

| Gate | How it enumerates | What the new file needs |
|---|---|---|
| `tests/scripts/test-infra-privileged-tier-census.sh` (Guards 1,2,4,5,6,7) | Derives the Tier-B job set from what jobs REFERENCE (`secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED`, the loader); never a hand-kept job list (header: "keyed on what a job REFERENCES"). | G1b/G1c/G1d: job declares `environment: infra-privileged` (in `TIER_B_ENVIRONMENTS`, with a Terraform-declared main policy). G1e: no `toJSON(secrets)`/`secrets[...]`. G1g: no `-c prd_terraform` read of a Tier-B name in the workflow (none; the preflight script's legacy read is a script, which the row does not see, and the web-host jobs already carry it). G2 vacuous (no `doppler run`). G6: no `github-app-runtime-token` opt-in (default `false`). No census edit expected; **Verify**: run the suite, expect no new FAIL and no changed exact-count pin. |
| `plugins/soleur/test/workflow-file-size.test.ts` | Every top-level `*.yml` under `.github/workflows`, gate 490,000 bytes, floor `LIVE_MIN_FILES = 20`. | Nothing: the new file is about 5 KB. |
| `plugins/soleur/test/terraform-target-parity.test.ts` | Discovers workflows by content (a Terraform plan or apply command, a target flag, a state-remove command); the "NO other workflow FILE -targets..." row scans every sibling after comment stripping. | Nothing, provided the file contains no `terraform` command line and no passphrase-pair address; comments are stripped but keep prose free of those tokens anyway. **Verify.** |
| `tests/scripts/test-destroy-guard-regex-parity.sh` | Fixed list of three apply workflows. | Not applicable (no Terraform, no destroy path). |
| `plugins/soleur/test/required-checks-canonical-parity.test.sh` + `scripts/required-checks.txt` | Fixed files (`ci.yml`, `secret-scan.yml`, `main-health-monitor.yml`). | Not applicable: no `pull_request` trigger, no required check added. |
| `plugins/soleur/test/web-host-escrow-preflight-census.test.ts` | Host-creating predicate = a `terraform apply` with a `-target/-replace` of `hcloud_server.web[...]`. | The new job is not host-creating, so it is neither required nor forbidden to run the preflight. **Verify** the suite stays green and its exact `TEST_FLOOR` is untouched (this change adds no row to it). |
| `plugins/soleur/test/c4-count-parity.test.sh` | Counts `actions/sentry-heartbeat` users, `schedule:`-fired vs dispatch-only heartbeat workflows, monitor slugs, Resend emitters. | Not moved: the new workflow uses no heartbeat composite and no Resend, and `model.c4` is not edited. **Verify** it stays green. |
| `scripts/lint-workflow-local-action-checkout.py` | Every `uses: ./...` step must follow a usable `actions/checkout` in the same job. | The checkout precedes the loader and has no `if`, `path`, `repository` or `continue-on-error`. |
| `scripts/lint-workflow-step-env-refs.py`, `scripts/lint-workflow-run-body-syntax.py`, `scripts/lint-workflow-errexit-capture.py` | Every `run:` body. | Every referenced ALL_CAPS variable is runner-provided or step-assigned; the body parses as bash; the rc is read only through `|| rc=$?`. |
| `scripts/lint-workflows.sh` (actionlint) | Whole directory; exits 0 on findings except a hang. | Run it; fix any finding in the new file (the file is small, so findings are attributable). |
| `.github/actions/infra-credentials/infra-credentials.test.sh` | Drives the loader against a Doppler stub. | Not edited. Run it unchanged as a regression check; the loader is not touched. |
| `plugins/soleur/test/*.test.sh` auto-glob (`scripts/test-all.sh` scripts group, `test-scripts` CI shard, rolls up into the REQUIRED `test` check) + `scripts/lint-orphan-test-suites.sh` + the affected-set declarations in `scripts/lib/test-affected-paths.sh` | Filesystem glob; presence is registration. The infra alternative (`apps/web-platform/infra/*.test.sh`, `suite-shard-legs.tsv`, `suite-durations.tsv`, ADR-240/252) runs only in `infra-validation.yml`'s `deploy-script-tests` job, which is NOT in `scripts/required-checks.txt` or the CI Required ruleset (verified with `gh api repos/jikig-ai/soleur/rulesets`), so a guard there is advisory. | The shape test goes here, not in the infra directory, so it is a required check; no shard-manifest rows and no `infra-validation.yml` path edit are needed. **Verify** `bash scripts/lint-orphan-test-suites.sh` and the affected-set census stay green (classify the suite only if the census asks). |
| `.github/CODEOWNERS` | Default `*` already assigns `@deruelle`; the file's header says the branch-protection requirement for CODEOWNERS review is a separate admin follow-up. | No edit: explicit rows naming the same owner add no reviewer (plan-review cut). |

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality | Plan response |
|---|---|---|
| "a scheduled run only if the existing drift-check pattern makes that natural" | The drift check has no `schedule:`; it is dispatched by an Inngest function. | Single `workflow_dispatch`; scheduled run declined with a re-evaluation trigger. |
| "loads credentials through the existing tiered loader" and "the token must never reach ... GITHUB_ENV" | The loader itself writes every Tier-B value (including `DOPPLER_TOKEN_TF`) to `$GITHUB_ENV`, masked, heredoc-delimited. That is how `TF_VAR_doppler_token_tf` reaches the preflight in the birth jobs too. | This workflow's own steps write nothing to `$GITHUB_ENV`/files/argv; the loader's export is the pre-existing carrier and is named as a residual (ADR-241 note). The checking step strips the environment to an allowlist so the checker child inherits only the one token it needs. |
| "reuse the preflight's masking" | The env-token arm of the preflight adds no mask (the loader masked the value per line); the `add-mask` is the fallback arm only. | Nothing to add; the shape test pins that the step never prints the token and that summary lines are scrubbed of `dp.<kind>.<body>` shapes. |
| Runbook step 0: "run it yourself" snippet reads `DOPPLER_TOKEN_TF` from `soleur/prd_terraform` | O10 evicted that name from `prd_terraform`; the snippet cannot work. | Runbooks switch to "dispatch this workflow"; the break-glass snippet in `web-host-birth.md` is repointed at `soleur-infra-privileged/prd` (workplace login, value read by the person, never echoed). |

## Implementation Phases

### Phase 1 - Write the failing shape test first (cq-write-failing-tests-before)

Create `plugins/soleur/test/web-host-escrow-diagnose-workflow.test.sh` (location chosen for required-ness, see the gate table; pattern: `apps/web-platform/infra/workspaces-plaintext-forget-workflow.test.sh`: instrument self-test, YAML-parsed structural rows, behavioural rows that EXECUTE the extracted step body). It fails until Phase 2 because the workflow does not exist. Rows are listed under Guard Contract and Test Scenarios.

### Phase 2 - The workflow

Create `.github/workflows/web-host-escrow-diagnose.yml`. Design (the file is the source of truth; this is its pinned shape):

```yaml
name: Web-host escrow readiness (read-only diagnostic)
on:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  escrow-check:
    environment: infra-privileged
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
        with:
          persist-credentials: false
      - name: Load infra credentials (tiered)
        uses: ./.github/actions/infra-credentials
        with:
          doppler-token-infra-privileged: ${{ secrets.DOPPLER_TOKEN_INFRA_PRIVILEGED }}
      - name: Escrow readiness check (read-only)
        run: |
          set -uo pipefail
          rc=0
          # Deny-by-default child environment (hygiene against ACCIDENTAL inheritance, not a boundary: the parent
          # step shell keeps the full environment at /proc/$PPID/environ, readable by same-UID processes): unset
          # every exported name but the allowlist, in a subshell, so the loader's other Tier-B exports are not
          # inherited by the checker, the doppler CLI or curl. No `env -i VAR=...`:
          # that would put the token in an argv.
          out="$(
            while IFS= read -r v; do
              case "$v" in PATH|HOME|TMPDIR|LANG|TF_VAR_doppler_token_tf) ;; *) unset "$v" 2>/dev/null || true ;; esac
            done < <(compgen -e)
            bash scripts/web-host-escrow-preflight.sh 2>&1
          )" || rc=$?
          # One redaction for log and summary alike (the loader's per-line mask is the first control, this is the second).
          out="$(printf '%s\n' "$out" | sed -E 's/dp\.[A-Za-z]+\.[A-Za-z0-9._-]+/dp.REDACTED/g')"
          [[ -z "$out" ]] || printf '%s\n' "$out"      # keeps the preflight's ::error:: annotations
          case "$rc" in
            0) if grep -qx 'escrow-split-contract:live-ok' <<<"$out"; then
                 verdict="PASS (names only, necessary not sufficient): escrow-split-contract:live-ok"
               else
                 verdict="NOT READY: exit 0 without the live-ok line"; rc=1
               fi ;;
            1) verdict="FAIL: the escrow-split contract is violated; read the CAUSE and FAIL lines below" ;;
            2) verdict="NO TOKEN: the loader succeeded but no Doppler provider token reached the check, so the Tier-B project has no usable workplace-token entry" ;;
            3) verdict="UNREADABLE: an unreadable config line naming prd suggests a bad or rotated token; one naming prd_workspaces_luks_web suggests the config is absent. Never read as ready" ;;
            *) verdict="UNEXPECTED exit ${rc}: not ready" ;;
          esac
          {
            printf '## Web-host escrow readiness (read-only)\n\n**%s**\n\n' "$verdict"
            printf 'Dispatched at %s UTC, SHA %s (ref %s). Valid at run time only; the birth and replace jobs re-run this check themselves. Names only: it does not prove the R2 pair is bucket-scoped, that web-1 is unreachable with it, or that a header backup restores.\n\n```text\n' "$(date -u '+%F %T')" "$GITHUB_SHA" "${GITHUB_REF_NAME//[^A-Za-z0-9._\/-]/_}"
            printf '%s\n' "$out" | LC_ALL=C tr -c '\n\040-\176' ' ' | tr -d '`' \
              | sed -E 's/^(escrow-split-contract:unreadable: config [A-Za-z0-9_]+).*/\1 (vendor detail withheld, see the run log)/' \
              | { grep -E '^(escrow-split-contract:|advisory: [0-9]+ )' || true; } | cut -c1-600 | sed -n '1,40p'
            printf '```\n'
          } >> "$GITHUB_STEP_SUMMARY"
          exit "$rc"
```

Decisions inside the step: (1) one step, so the rc, the output and the summary never cross a step boundary; (2) the allowlist keeps
`TF_VAR_doppler_token_tf` only, so the preflight takes its "environment token wins" arm; the loader's Tier-B arm filters
`DOPPLER_TOKEN` out of its exports and the workflow passes no legacy token, so the preflight's legacy arm is unreachable and an absent
token ends at the preflight's exit 2, never at a Tier-A read. Because the loader step only succeeds on its Tier-B arm here (no legacy
token is passed), rc 2 has exactly one cause and the NO TOKEN text can say so; (3) the summary lines are filtered to the checker's own
prefixes (`escrow-split-contract:` covers its CAUSE, NOTE, FAIL and unreadable lines; `advisory:` is the count-only line),
flattened to printable ASCII, stripped of backticks (so the fenced block cannot be closed from inside), token-shape redacted, `unreadable` lines cut to their config name (the checker embeds up to 300 characters of Doppler CLI stderr there, which can carry account detail the token-shape redaction does not cover; the detail stays in the run log) and
capped at 40 lines of 600 characters (`sed -n` rather than `head`, which would SIGPIPE the upstream stage under `pipefail`);
(4) the only guard on the presentation pipeline is the `grep ... || true` for a no-match; the verdict is the captured `rc` and
the step ends in `exit "$rc"`; (5) no `if: always()` step, no artifact upload, no `GITHUB_OUTPUT` write, no `concurrency:`
group (nothing shared is serialised: no state, no Terraform; back-to-back dispatches are harmless and run independently) and no per-step
timeouts (the job-level `timeout-minutes` bounds the run; AS BUILT, the review round added `timeout -k 10 240` around the preflight only, so a stalled Doppler call still yields a verdict); (6) the PASS text is printed only when rc is 0 AND the captured output contains
the exact `escrow-split-contract:live-ok` line, otherwise the verdict is NOT READY and the step exits non-zero (an empty capture is never
a pass); (7) the summary prints the UTC time, dispatched SHA and ref (the ref name is user-selected at dispatch and a branch or tag name may carry shell or markdown metacharacters, so it is character-allowlisted before printing; it is read from the runner's environment, never interpolated into the script text) so a green run is tied to the workflow bytes that produced it; (8) `::add-mask::` values are NOT masked inside `$GITHUB_STEP_SUMMARY` (GitHub docs: masking applies to logs) and job summaries on a public repository are readable anonymously, so the explicit `dp.<kind>.<body>` redaction and the prefix filter are the only controls on the summary, not a belt-and-braces duplicate of the loader's mask.

**As-built deltas (work and review rounds; the YAML block above is the plan's pin, not the shipped file).** The shipped step
adds: a 40+ character key-like redaction pass after the `dp.<kind>` pass; a `Verdict:` and a `Run-context:` line (commit,
dispatcher, UTC time) in the run log, because the gh CLI exposes no job-summary field; `timeout 240` around the preflight
with a `124` verdict arm, so a stalled Doppler call still produces a verdict and the summary; a second loop that unsets
exported shell functions; hedged NO TOKEN and UNREADABLE verdict text (the checker reads `prd_workspaces_luks_web` first, so a
bad token names it); and a workflow `name:` that says "necessary, not sufficient". The suite adds a positive command-capability
check (the step runs on a PATH of vetted tools, and a command outside it is refused), a runbook-log-grep row over a log shaped like
GitHub's (the log echoes the step's script, which contains `live-ok` and `PASS`), and an exact pin of the case list. Task 5.2
(a deferral issue) is not taken; see decision-challenges.md. AS BUILT, wherever the plan below says the agent reads the "job summary", it reads the run LOG (the gh CLI exposes no summary field); the NO TOKEN and loader repairs are O2/O3 and never O13 from the table (O13 is gated on O12b); and the summary heading is "Web-host escrow config names check" (the YAML snapshot above keeps the plan's original heading).

### Phase 3 - Wire the gates

- Confirm the suite is picked up by the `plugins/soleur/test/*.test.sh` glob in `scripts/test-all.sh` and that `bash scripts/lint-orphan-test-suites.sh` is green; no shard-manifest or `infra-validation.yml` edit.
- Run the census/lint/size gates in the table above; fix findings in the NEW file only. No CODEOWNERS, `model.c4` or tiers-runbook edit (plan-review cuts: no ruleset requires code-owner review, so rows naming the same owner add no reviewer; the C4 edge and the #8209 inventory describe no element, count or sweep this job changes).

### Phase 4 - Docs and ADR

- `web-host-birth.md` and `web-host-replace.md`, Step 0: rewrite the whole step, not just the snippet. Remove "There is nothing to run beforehand" and the "To re-run the identical check ... from a checkout" paragraph with its command block, and the "That token is write-capable; a read-only preflight token is tracked in #9461" line. The new step 0 says, in this order:
  1. Dispatch `gh workflow run web-host-escrow-diagnose.yml --ref main`, arm `gh run watch` on the run it started, read the job summary. A branch ref is stopped by the environment's main-only policy: the run is created and its job is blocked before any step runs (community-reported behaviour, wording not in the official docs, so the runbook says "blocked before any step" and does not quote a message); that is expected, never retry it with a token workaround.
  2. How to read it (decode table, one row per outcome): the loader step red with no summary (read its annotation: `verdict=no_credential_source`, `privileged_read_failed`, `privileged_empty`); summary PASS; NO TOKEN (the Tier-B project lacks the workplace-token entry: follow the seeding step O2 and the rotation step O13 of `infra-credential-tiers-8209.md`, which needs a workplace-scoped Doppler login, then dispatch again); FAIL (read the CAUSE lines: push-apply not done vs live R2 mint not done, then act on that family); UNREADABLE (the `unreadable` line names the config: `prd` suggests a bad or rotated token, `prd_workspaces_luks_web` suggests the config is absent and carries the NOTE); UNEXPECTED, including exit 78 (open the step log, check for xtrace or `SHELLOPTS`, fix by PR, dispatch again).
  3. Green is necessary, not sufficient, and valid only at its run time and SHA (the summary prints both, in UTC): cite a green run only if it was created in the current birth session and its SHA equals the current `main` head; otherwise dispatch again. The birth and replace jobs re-run the same preflight and still abort on any non-zero result with nothing changed, and the break-glass local path never re-runs this check. Concurrent or back-to-back dispatches are harmless. A red or UNEXPECTED run blocks nothing automated: read the decode table, repair the named cause, dispatch again.
  4. The token this job uses is the workplace personal token; read-only is a property of the workflow steps, not of the token.
  Keep the NOTE-vs-CAUSE and `escrow=missing` paragraphs. `web-host-birth.md` break-glass step 0 (the Actions-unavailable path, which is exactly when dispatch is impossible) keeps a local command but repoints the source to `soleur-infra-privileged/prd`, states the precondition (a workplace-scoped Doppler login), and says why `prd_terraform` no longer works. `web-host-replace.md` points to the birth runbook's break-glass for that case.
- ADR-241: dated note on D2. It states the residual in its true strength: (a) the job holds the workplace personal token and the whole Tier-B set, and the token can read and write every Doppler project, so read-only is a property of the steps only; (b) any actor who can merge to `main` can change what this no-reviewer job does, and no ruleset on this repository requires a pull-request review or code-owner approval today, so the bound is the main-only branch policy, which ADR-241 itself calls nominal until residual R1 closes; (c) it reconciles with D11's rejected alternative ("a `main`-dispatched workflow ... would need `DOPPLER_TOKEN_TF`-class authority in a job any `main` writer can trigger"): D11 removed that reach from the release jobs, whereas `infra-privileged` already hosts jobs that hold it (apply-on-merge, the drift check, the dispatched forget and teardown); this job adds one more consumer of the same class, accepted because the alternative is a human reading a stale runbook command, and it adds no new reach; (d) the narrower credential (a D11-style project holding only a names-read token) is deferred with a trigger. No status change, no new ADR.

### Phase 5 - Tracking and hand-off (no dispatch)

- Comment on #9461: this workflow removes the need for a separate minted read-only credential for the DIAGNOSTIC path (the dispatch uses the existing loader export); the birth/replace jobs still use the workplace token until #9461 is done, so #9461 stays open with that narrowed scope; link the ADR note.
- Comment on #9377: the dispatch is the pre-birth check, and where it is recorded (runbooks step 0).
- (NOT TAKEN, see decision-challenges.md; no issue is filed) File one deferral issue (scheduled / Inngest-dispatched check; labels verified to exist: `deferred-automation`, `domain/engineering`, `priority/p3-low`), with the re-evaluation trigger from the Deferred table, milestone from `knowledge-base/product/roadmap.md`. The narrower-credential direction is tracked by #9461 (no second issue).
- PR body: `Ref #9377`, `Ref #9461`; the "necessary, not sufficient" sentence (CPO condition 1); a statement that the workflow was NOT dispatched.
- The work phase and ship MUST NOT dispatch the workflow.

## Files to Edit

- `knowledge-base/engineering/operations/runbooks/web-host-birth.md`
- `knowledge-base/engineering/operations/runbooks/web-host-replace.md`
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md`

Untouched by design: `tests/scripts/lib/web-host-replace-gate.sh` (the by-name web-1 refusal), `scripts/web-host-escrow-preflight.sh`
(`scripts/check-web-host-escrow-config.sh` changes by three header COMMENT lines only, after review), `.github/actions/infra-credentials/action.yml`, `apply-web-platform-infra.yml`, `.github/CODEOWNERS`,
`model.c4`.

## Files to Create

- `.github/workflows/web-host-escrow-diagnose.yml`
- `plugins/soleur/test/web-host-escrow-diagnose-workflow.test.sh`

## Open Code-Review Overlap

Queried open `code-review` issues against every planned path (the workflow, the new suite, the two runbooks, ADR-241). The one earlier match (#8735 and #7942 on `.github/workflows/infra-validation.yml`; #3321 on `.github/CODEOWNERS`) came from files this plan no longer edits. Result: **None** for the final file list.

## User-Brand Impact

- **If this lands broken, the user experiences:** a web-host birth or replace that proceeds, or is blocked, on a wrong readiness answer. False green: the check reads names only, so a `prd_workspaces_luks_web` holding web-1's R2 pair pasted under the new names passes, a host is born whose LUKS header escrow (the `WORKSPACES_HEADER_R2_*` pair and `WORKSPACES_LUKS_KEY`) is unusable, and a lost volume key means a connected user's repositories cannot be recovered (control: the signed `HEAD` of web-1's bucket returning 403 on #9377's mint step, which this workflow does not replace; see Known Limits). False red: the first dispatch fails (the allowlist starves the real Doppler CLI, or a Doppler outage reads as rc 3) and a legitimate birth is delayed, which costs capacity, not data; nothing automated gates on this workflow, so a red run blocks no pipeline.
- **If this leaks, the user's data is exposed via:** the workplace-scope Doppler token (`DOPPLER_TOKEN_TF` reads every Doppler project, including the isolated `soleur-git-data-root` project that decrypts every connected user's stored repositories) or the whole Tier-B set loaded beside it (read/write Hetzner token, R2 key, App key): through argv, a file, `$GITHUB_ENV`, a log or a public job summary, or through a main-merged edit that adds a step to this no-reviewer job.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the job holds a token with reach over the key store behind every user's source code in an environment with no reviewer, so one mishandled token is a single-user-class breach, not an aggregate pattern; the CPO assessment concurred ("yes with conditions", threshold agreed).

CPO conditions carried into this plan: describe the check as necessary-not-sufficient everywhere (workflow summary text, runbooks, PR
body); least-privilege permissions, existing loader, no mint, no step that echoes the environment or takes PR input; names-only fixed
sentences in the public summary; fail closed on any unknown; `soleur:engineering:review:user-impact-reviewer` runs at
review time; the code-owner condition is NOT met by a CODEOWNERS edit (see Known Limits: no ruleset enforces review) and is recorded as a residual; the workflow is recorded where the pre-birth check is expected (runbooks, #9377 comment).

## Observability

```yaml
liveness_signal:
  what: the run conclusion of web-host-escrow-diagnose.yml and the first line of its job summary (PASS escrow-split-contract:live-ok or FAIL/NO TOKEN/UNREADABLE)
  cadence: on dispatch only (no schedule, by decision); the dispatching agent arms gh run watch on every dispatch
  alert_target: the dispatching agent session via gh run watch / gh run view; a red run is visible on the Actions tab (no standing alert, because nothing runs unattended)
  configured_in: .github/workflows/web-host-escrow-diagnose.yml (job escrow-check, final step exits with the preflight rc)
error_reporting:
  destination: GitHub Actions run annotations (::error:: lines re-emitted by scripts/web-host-escrow-preflight.sh) plus the job summary; no Sentry path (a CI step, not product code)
  fail_loud: the step exits with the preflight's own code (1 contract violated, 2 usage/no token, 3 unreadable); every non-zero fails the run; an unknown code prints UNEXPECTED and fails
failure_modes:
  - mode: no provider token reached the step (the Tier-B project has no usable workplace-token entry, or the Tier-B secret is missing)
    detection: workflow run log - the loader step's ::error:: annotation (verdict=no_credential_source) or the check step's job summary NO TOKEN with exit 2
    alert_route: workflow run log red run, read by the dispatching agent through gh run watch and gh run view
  - mode: escrow config incomplete (a name missing in prd_workspaces_luks_web, or a forbidden name present in the prd root)
    detection: workflow run log - ::error:: annotations and job summary FAIL with escrow-split-contract:FAIL and CAUSE lines (exit 1)
    alert_route: workflow run log red run; the cause family names the next action (push-apply not done vs live R2 mint not done)
  - mode: config unreadable or absent (token invalid after rotation, prd_workspaces_luks_web not created yet)
    detection: workflow run log - ::error:: annotation and job summary UNREADABLE with escrow-split-contract:unreadable or NOTE lines (exit 3)
    alert_route: workflow run log red run; a NOTE is explicitly "consistent with", not a diagnosis
  - mode: summary or log leaks a token or credential name inventory
    detection: workflow run log - pre-merge, the shape test canary rows (token and Doppler-stderr credential shapes never in stdout or summary; only allow-listed prefixes pass); ESCROW_ADVISORY=count withholds prd-root names
    alert_route: CI failure of web-host-escrow-diagnose-workflow.test.sh before merge
  - mode: false green (names present but the R2 pair is web-1's pair pasted under new names)
    detection: accepted gap, not detectable by this check; the workflow run log shows PASS labelled "necessary, not sufficient"; the control is the signed HEAD of web-1's bucket returning 403 on #9377's mint step
    alert_route: workflow run log PASS wording plus the #9377 mint-step control; no alert from this workflow
logs:
  where: the run's step log and job summary on GitHub Actions
  retention: GitHub's default run-log retention (90 days); no artifact is uploaded
discoverability_test:
  command: curl -sS --max-time 10 https://api.github.com/repos/jikig-ai/soleur/actions/workflows/web-host-escrow-diagnose.yml/runs
  expected_output: total_count or Not Found
```

`Not Found` is the pre-merge answer (the file is not on the default branch yet; measured live: the endpoint returns a 404 JSON body with `"message": "Not Found"`); `total_count` is in the JSON body once the workflow exists, before and after the first dispatch (the conclusion of the latest run is in that same body). The command is a single statement with no pipe and no `&`, because preflight Check 10 refuses any shell-active token even inside quotes; it is unauthenticated (public repository), has no ssh, and finishes inside the 15-second cap. If the unauthenticated rate limit is hit it prints the limit message, which is a probe failure, not a pass.

## Guard Contract

### Guard 1 - the diagnostic workflow stays read-only and token-clean

**Property.** `web-host-escrow-diagnose.yml` can never run Terraform, write to Doppler, GitHub or any store, widen its token beyond the loader's export, or hand the provider token to anything but the preflight's environment.

**Assembly.** Quantified over every structural channel, derived by parsing the YAML rather than listing today's steps: (a) the `permissions` map at workflow AND job level; (b) the `on:` trigger set; (c) every job in the file (not "the" job); (d) every step's `uses:` and every `run:` body (comments stripped); (e) the loader's `with:` inputs; (f) every sink that persists a value (`$GITHUB_ENV`, `$GITHUB_OUTPUT`, `upload-artifact`, any `>` redirect to a path other than `$GITHUB_STEP_SUMMARY`); (g) argv positions of the token variable. The chokepoint is the one `run:` step that invokes the preflight; the assembly of "who may read `TF_VAR_doppler_token_tf`" is that step's allowlist `case` and nothing else (no expansion of it exists in the file).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `issues: write` (or any `write`) to the workflow-level or job-level `permissions` | RED (the effective permissions must equal exactly `{contents: read}`; an absent job-level block passes, a present one must not widen it) |
| 2 | Add a second job after the compliant first (a copy of the job with a Terraform plan line in a `run:`) | RED (exactly one job; the scan quantifies over all jobs) |
| 3 | Add `schedule:` or `pull_request:` beside `workflow_dispatch` | RED (trigger set must equal `{workflow_dispatch}`) |
| 4 | Pass `doppler-token-legacy` to the loader, or `github-app-runtime-token: true` | RED (loader `with:` keys must equal `{doppler-token-infra-privileged}`) |
| 5 | Add a Terraform command, a Doppler secret-write or token-mint subcommand, a `doppler run`, a `gh api` POST/PUT/PATCH/DELETE or a `curl -X POST` line to any `run:` | RED (denylist of write verbs over all steps) |
| 6 | Add a line that appends the token to `$GITHUB_ENV`, or an `actions/upload-artifact` step, or a `GITHUB_OUTPUT` write | RED (persisting sinks other than `$GITHUB_STEP_SUMMARY` are refused) |
| 7 | Reference the token variable by expansion (`$TF_VAR_doppler_token_tf`, `${TF_VAR_doppler_token_tf...}`, `$DOPPLER_TOKEN_TF`) anywhere in a `run:`; the bare name inside the allowlist `case` pattern and inside verdict prose is allowed | RED on any expansion (an expansion is how a value reaches an argv or a file) |
| 8 | Remove the allowlist loop, or add `HCLOUD_TOKEN` to its keep-list | RED (behavioural: a canary `HCLOUD_TOKEN`/`SENTRY_AUTH_TOKEN` exported to the step is visible to the child) |
| 9 | Remove `persist-credentials: false` from the checkout | RED |
| H1 | Harness: delete one behavioural case (e.g. the rc=3 case) from the suite | RED (the suite's declared case count is an exact pin) |
| H2 | Must-PASS, non-canonical: the same workflow with the comment block reworded, step names changed, an added comment mentioning a Terraform plan, and the checkout moved before a no-op `run: true` step | GREEN (comments and names are not behaviour) |
| H3 | Dispatch row: run the suite against a tree with ZERO workflow files and against the real tree with the workflow renamed | RED each, as `workflow-missing`, never "0 checked, pass" |

**Anchor.** The suite compares structure to constants inside the same PR, so one diff can weaken both, and no repository ruleset requires a reviewer today, so there is no review control outside the commit to name. What does sit outside the suite: the census (`test-infra-privileged-tier-census.sh`), a separate suite that independently derives every Tier-B job from references and checks tier membership (not read-only posture). The honest statement is that this guard proves consistency, not integrity; the residual is recorded in Known Limits and the ADR note.

### Guard 2 - the job summary carries only scrubbed checker lines and an rc-derived verdict

**Property.** No byte of the step's `$GITHUB_STEP_SUMMARY` output is a token, a markdown/HTML injection, or a line the checker did not print, and the verdict text is a pure function of the preflight's exit code plus the presence of the exact `live-ok` line.

**Assembly.** The log/summary path (the token-shape `sed` on the captured output, then `tr` flatten, backtick strip, prefix `grep`, `cut`, `sed -n` cap) and the `case "$rc"` verdict table; both are exercised through the real preflight and checker behind a Doppler stub, over every exit code the preflight can return (0, 1, 2, 3, the xtrace refusal 78, an unlisted code).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Stub the checker to print a synthetic `dp.pt.SYNTH...` token inside an `escrow-split-contract:FAIL` line | RED if the token appears in the log or the summary; GREEN only with `dp.REDACTED` in both |
| 2 | Drop the prefix `grep` (or widen it to `.*`) | RED (a non-prefixed line containing an HTML tag or a `::set-output` directive reaches the summary) |
| 3 | Make the checker print 200 lines, one of them 2,000 characters | RED unless the summary holds at most 40 lines of at most 600 characters |
| 4 | Swap the verdict for rc=3 to the PASS text, or make the `*)` arm read "ready" | RED (each rc maps to its own exact first line; the unlisted code maps to UNEXPECTED and exits non-zero) |
| 5 | Replace `exit "$rc"` with `exit 0` | RED (the step's exit status must equal the stub's rc for all five codes) |
| 6 | Add a second member after a compliant first: a line containing a backtick fence closer followed by markup | RED (backticks stripped, the fenced block cannot be closed from inside) |
| 7 | Produce rc 78 the only way the real preflight does (inject `SHELLOPTS=xtrace` into the step environment; it is exported readonly, so the allowlist cannot unset it and the child inherits it, which still fails closed) | RED unless the step exits 78, prints the UNEXPECTED verdict and still writes the summary |
| H1 | Harness: the stub returns rc=0 with an EMPTY output | RED: an empty capture with rc 0 must not print PASS text unless `live-ok` is present, pinned as a case |
| H2 | Must-PASS, non-canonical: the checker prints the same lines in a different order with an extra benign `advisory:` count line | GREEN (summary shows both, verdict unchanged) |

**Anchor.** The verdict mapping lives in the workflow and the fixtures live in the suite, in one PR. The independent anchor is the real checker's own exit-code contract, pinned in `scripts/check-web-host-escrow-config.test.sh` (a separate suite already on main): the diagnose suite runs the real checker, so redefining a code in the checker reds that suite first.

## Architecture Decision (ADR/C4)

Detection: a new consumer of the `infra-privileged` Tier-B environment is an extension of ADR-241 D2 (its dated-note convention records each added consumer), not a new decision; it accepts a stated residual (the diagnostic holds the whole Tier-B set for its duration).

### ADR

Amend ADR-241 D2 with a dated note via `soleur:architecture`: the environment also serves `web-host-escrow-diagnose.yml`, a dispatched read-only diagnostic; the token it needs is the loader's Tier-B export of `DOPPLER_TOKEN_TF`; no credential minted; residual stated in its true strength (see Phase 4), including the reconciliation with D11's rejected main-dispatched alternative; narrower-project follow-up tracked by #9461. No status flip. This is a task of this plan (Phase 4), not a follow-up issue.

### C4 views

No C4 change, with the enumeration that supports it. Read for this feature: the `github -> doppler` edge in `model.c4` (the one place infra-privileged consumers are described) and the two other model files (`views.c4`: `github` and `doppler` are already in the two views that include them, no per-workflow element; `spec.c4`: no hit for infra-privileged, the token or escrow). External human actor: the dispatching operator or agent, already implicit in every `github` edge, no new actor. External systems: GitHub Actions (`github`) and Doppler (`doppler`), both modelled; the Doppler configs `prd` and `prd_workspaces_luks_web` are described on the `doppler -> hetzner` edge. Container/data store: none new. Access relationship: the existing `github -> doppler` edge already states that a Tier-B job loads the whole carrier project through the loader on a main-only environment; its prose names consumers by class (apply-on-merge and drift, then the #9262 pair), and the dispatched forget and teardown consumers were never added to it, so omitting a read-only dispatch keeps it as accurate as it was. Derived counts: the edge carries no workflow count this change moves; `plugins/soleur/test/c4-count-parity.test.sh` is run and must stay green. Plan-review (code-simplicity and the structural reviewer) cut a prose-only edge plus the regenerated `model.likec4.json` and three C4 suites; the CTO suggested the clause. Recorded as a taste item in `decision-challenges.md`.

### Sequencing

The ADR note is accurate as soon as the workflow merges; the claim that the first dispatch works (O2 seeded, token valid) is stated as unverified until that dispatch runs.

## Infrastructure (IaC)

No new infrastructure: no server, secret, vendor account, DNS record or Terraform resource. The workflow file is the deliverable; the environment, its main-only policy and its secrets already exist (`apps/web-platform/infra/infra-privileged-environment.tf`; no change). Terraform changes: none. Apply path: merge, then dispatch from `main`. Distinctness/drift safeguards: unchanged `infra-privileged` policy, pinned by census G1d. Vendor-tier reality check: not applicable (no vendor feature used beyond what the loader already uses).

## Domain Review

**Domains relevant:** engineering, product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Sound and small; risk is medium and driven entirely by the credential residual (whole Tier-B project into a no-reviewer dispatch job). Acceptable if stated plainly in the plan and an ADR-241 dated note, with the narrower credential recorded as a deferred follow-up. Recommended pinning: `permissions` exactly `contents: read`, dispatch-only trigger, one job on `infra-privileged`, loader gets only the privileged token, no terraform/write verbs, no artifact upload or `GITHUB_OUTPUT` write, `persist-credentials: false`, summary content limited to scrubbed checker lines. Recommended a deny-by-default child environment; the `env -i VAR="$TOK"` spelling was adjusted here to an unset-everything-but-the-allowlist loop because the `env -i` form would put the token in `env`'s argv (the brief forbids argv), and the allowlist form is equally fail-closed. `infra-validation.yml` takes the workflow path in the `pull_request` list only. ADR-241 dated note, not a new ADR.

### Product (CPO)

**Status:** reviewed
**Assessment:** Sign-off: yes with conditions (threshold `single-user incident` agreed). Conditions are carried under User-Brand Impact. Scheduled run: declining it loses little (readiness only matters at birth/replace); revisit when the Inngest-dispatch substrate is used for it or births become frequent. No capability gaps. A restore rehearsal stays on the L27 path: this check must not be the only gate.

### Product/UX Gate

**Tier:** none (no user-facing surface: a CI workflow, runbook text and tests; no `components/`, `app/` or page file in the Files lists).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add a read-only, unattended diagnostic workflow so the web-host escrow check ... runs in CI with no human step" [brief] | Phase 2, Files to Create (workflow) | mapped |
| 2 | "Build one workflow_dispatch workflow (plus a scheduled run only if the existing drift-check pattern makes that natural)" [brief] | Phase 2; schedule declined in Cut List and Research Reconciliation | mapped |
| 3 | "loads credentials through the existing tiered loader (.github/actions/infra-credentials) on `infra-privileged`" [brief] | Phase 2 (loader step, environment); Credential Resolution | mapped |
| 4 | "runs scripts/web-host-escrow-preflight.sh (or the checker --live with ESCROW_ADVISORY=count) and NOTHING else, has no Terraform and no write of any kind" [brief] | Phase 2 checking step; Guard 1 | mapped |
| 5 | "prints the checker verdict plus the missing-name causes into the job summary, and fails on a non-zero rc" [brief] | Phase 2 summary block and `exit "$rc"`; Guard 2 | mapped |
| 6 | "the by-name web-1 refusal in tests/scripts/lib/web-host-replace-gate.sh stays untouched" [brief] | Files to Edit "Untouched by design"; AC | mapped |
| 7 | "no Doppler write or token mint; no production write of any kind; permissions: contents read only" [brief] | Guard 1 rows 1,2,5; AC | mapped |
| 8 | "the token must never reach argv, a file, GITHUB_ENV or logs (reuse the preflight's masking)" [brief] | Phase 2 allowlist and scrub; Guard 1 rows 6-8, Guard 2 row 1; Reconciliation row 2 | mapped |
| 9 | "follow the workflow census/size/lint gates already in the repo (workflow-file-size, terraform-target-parity, destroy-guard, required-checks lists, shard manifests)" [brief] | Census, size and lint gates table; Phase 3 | mapped |
| 10 | "Update the web-host-birth and web-host-replace runbooks' step 0 to say 'dispatch this workflow' instead of 'run it yourself'" [brief] | Phase 4 | mapped |
| 11 | "Ref #9377 and #9461 (this removes the need for a separate minted read-only credential for the diagnostic path; say so on #9461)" [brief] | Phase 5 comments; frontmatter `refs` | mapped |
| 12 | "Do NOT dispatch the workflow in this PR's work" [brief] | Phase 5; AC | mapped |
| 13 | "Open question the plan MUST settle by reading the repo ... which of those environment secrets (or which loader output) actually yields a token that can read BOTH Doppler configs" [brief] | Credential Resolution | mapped |
| 14 | "how the scheduled drift-check workflow is wired on infra-privileged (the pattern to copy)" [brief] | Premise Validation; Repo findings | mapped |
| 15 | "the brand-survival threshold", "the Observability block with a discoverability_test.command that runs WITHOUT ssh, and Known limits" [brief] | User-Brand Impact; Observability; Known Limits | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `.github/workflows/web-host-escrow-diagnose.yml` | "Build one workflow_dispatch workflow" | asked |
| Allowlist (deny-by-default child env) in the checking step | "the token must never reach argv, a file, GITHUB_ENV or logs" | inferred — justification: the loader exports the whole Tier-B set into the job environment (a precedent finding: a mirrored line is a claim about the whole job), so the child process would otherwise inherit credentials the token ask does not need; plan-review split 3:2 on keeping it (kept, taste item in `decision-challenges.md`) |
| Summary scrub + prefix filter | "prints the checker verdict plus the missing-name causes into the job summary" and "the token must never reach ... logs" | asked |
| `plugins/soleur/test/web-host-escrow-diagnose-workflow.test.sh` | "follow the workflow census/size/lint gates already in the repo" | asked |
| Runbook step 0 edits (birth, replace) | "Update the web-host-birth and web-host-replace runbooks' step 0" | asked |
| Break-glass snippet repoint in `web-host-birth.md` | — | inferred — justification: the snippet reads a name O10 evicted, so leaving it makes the same runbook contradict its new step 0 (the stale-source finding in Credential Resolution) |
| ADR-241 D2 dated note | "ADR-241 defines the `infra-privileged` environment ... for unattended Tier-B jobs" | inferred — justification: plan Phase 2.10 requires the record of a decision that adds a consumer and states its residual; precedent notes #6604, #9262 |
| Deferral issue (scheduled run) | "plus a scheduled run only if the existing drift-check pattern makes that natural" | inferred — justification: wg-when-deferring-a-capability-create-a requires a tracking issue for a declined capability; the narrower credential is already tracked by #9461 |

### Split Assessment

- Subsystems touched: 3 - roots: `.github`, `plugins/soleur`, `knowledge-base`
- Planned files: 5 | Estimated changed lines: about 300
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR (3 roots by the two-segment rule; one workflow, its test and its documentation)

## Acceptance Criteria

### Pre-merge (PR)

- [x] `.github/workflows/web-host-escrow-diagnose.yml` exists; parsed triggers are exactly `{workflow_dispatch}` with no inputs; the effective permissions are exactly `{contents: read}` (an absent job-level block passes); exactly one job with `environment: infra-privileged`.
- [x] The loader step passes only `doppler-token-infra-privileged`; the checkout has `persist-credentials: false`; every `uses:` is SHA-pinned (checkout) or local (loader).
- [x] No Terraform command, Doppler secret-write or token-mint subcommand, `doppler run`, `gh api` write verb, `upload-artifact`, `GITHUB_OUTPUT` or `GITHUB_ENV` write appears in the file's non-comment text (shape test rows, workflow file).
- [x] The token variable is never expanded in the file (it appears only as the bare name in the allowlist `case` pattern and in verdict prose); the behavioural row exports a canary `HCLOUD_TOKEN` and `SENTRY_AUTH_TOKEN` to the step and the child does not see them.
- [x] Behavioural rows run the step body with the REAL preflight and checker behind a Doppler stub for rc 0, 1, 2, 3, 78 and an unlisted code: the step exits with that rc, the summary's first verdict line matches the exact table text, and a synthetic `dp.pt.SYNTH...` token never appears in stdout or the summary file.
- [x] `bash plugins/soleur/test/web-host-escrow-diagnose-workflow.test.sh` passes (and runs in the required `test` check via the scripts-group glob); it fails on the tree before Phase 2 (the workflow-missing row).
- [x] `bash tests/scripts/test-infra-privileged-tier-census.sh`, `plugins/soleur/test/terraform-target-parity.test.ts`, `plugins/soleur/test/workflow-file-size.test.ts`, `plugins/soleur/test/web-host-escrow-preflight-census.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh`, `.github/actions/infra-credentials/infra-credentials.test.sh`, `scripts/web-host-escrow-preflight.test.sh` and `scripts/check-web-host-escrow-config.test.sh` all pass with no edit to their assertions.
- [x] `bash scripts/lint-workflows.sh` reports no finding attributable to the new file; the four `lint-workflow-*.py` gates pass.
- [x] `git diff origin/main -- tests/scripts/lib/web-host-replace-gate.sh scripts/web-host-escrow-preflight.sh .github/actions/infra-credentials/action.yml` is empty, and the diff of `scripts/check-web-host-escrow-config.sh` is header comment lines only.
- [x] `bash scripts/lint-orphan-test-suites.sh` is green with the new suite present; `infra-validation.yml` is not changed; AS BUILT the shard manifest gained one row in each of `suite-shard-legs.tsv` and `suite-durations.tsv` (regenerated incrementally), and `scripts/lib/test-affected-paths.sh` gained an `AFFECTED_` array for the suite (`test-affected-kb-consumers` was red without it).
- [x] Both runbooks' step 0 tell the reader to dispatch `web-host-escrow-diagnose.yml`, keep "necessary, not sufficient", and no longer contain the `prd_terraform` read of `DOPPLER_TOKEN_TF`; the break-glass line reads from `soleur-infra-privileged/prd`.
- [x] ADR-241 carries the dated D2 note stating the residual in its true strength (token can write; the main-only policy is nominal until R1; no ruleset requires review; reconciled with D11's rejected alternative); `model.c4`, `model.likec4.json` and `.github/CODEOWNERS` are unchanged.
- [x] `python3 scripts/lint-guard-contract.py` passes on this plan.
- [ ] PR body: `Ref #9377`, `Ref #9461`, the necessary-not-sufficient sentence, the residual, and a statement that the workflow was NOT dispatched.

### Post-merge (next step, read-only; not part of this PR's work)

- [ ] Automated (an agent, no human step): `gh workflow run web-host-escrow-diagnose.yml --ref main`, then `gh run watch <run-id>` armed on the run it started (`hr-dispatch-async-must-arm-watch`) (the job's 10-minute timeout bounds the watch; an agent that exits first re-reads the run with `gh run view`). The dispatching session records the verdict line and the summary on #9377 before it ends. Expected: the loader notice `source=tier_b` and a summary first line of PASS or a named FAIL, NO TOKEN, UNREADABLE or UNEXPECTED. Per outcome: a loader failure with no summary or NO TOKEN means the Tier-B project lacks a usable workplace-token entry (the question this plan could not settle from names; the seeding or rotation step is an existing runbook item, not a new step here); FAIL follows the CAUSE family (push-apply or live R2 mint); UNREADABLE follows the config the `unreadable` line names; none of these is fixed by editing this workflow, and a workflow defect is fixed by a normal PR and a fresh dispatch.

## Test Scenarios

1. Structural (YAML-parsed): triggers, permissions, single job, environment, loader inputs, checkout flags, step order (checkout, loader, check), no persisting sink.
2. Behavioural, rc matrix: rc 0 (`live-ok`), 1 (missing name plus CAUSE), 2 (no token in env: the preflight's usage exit), 3 (NOTE on absent config), 78 (xtrace refusal), unlisted (7): exit code, verdict line, summary content.
3. Token containment: synthetic token in the stub's checker output; absent from stdout, summary and the child's environment other than the one allowed name; canary Tier-B names absent from the child.
4. Injection: checker lines carrying backticks, HTML, `::error::`, 600+ character and 40+ line bursts; the summary is capped and cannot close its fence.
5. Doppler-stderr containment: run the REAL checker once behind a Doppler stub that fails with stderr text carrying a synthetic credential shape (a `dp.st.`/`dp.pt.` shape and a long base64-like string); assert the log and the summary carry no credential shape (the `unreadable` line embeds up to 300 characters of CLI stderr, and only `dp.<kind>.<body>` shapes are redacted, so the row also pins that the summary prefix filter plus redaction is the whole control and records any shape the redaction misses).
6. Dispatch/anti-vacuity: empty workflow directory, renamed file, suite case-count pin.
7. Wording pins (doc-grep rows in the shape test): both runbooks' step 0 and the workflow's PASS text say "not sufficient"; both runbooks say the birth and replace jobs re-run the check and that a cited green run must match the current `main` head; neither runbook retains the "nothing to run beforehand" sentence or the `prd_terraform` read of the workplace token.
8. Regression of the neighbouring suites listed in the acceptance criteria.

## Known Limits

- A names-only check proves necessary, not sufficient. It cannot tell a bucket-scoped R2 pair from web-1's pair pasted under the new names (the signed `HEAD` of web-1's bucket returning 403 on #9377's mint step is the control), cannot prove a header backup restores, and cannot see a value rotated to a wrong-but-present one.
- An unreadable or absent config is `unreadable` (rc 3), never "missing"; a NOTE says what the failed read is consistent with and is not a diagnosis.
- The job holds the workplace personal token (it reads and writes every Doppler project) and the whole Tier-B set for its duration; no narrower credential exists without a mint. Read-only is a property of this workflow's steps, not of the token. Anyone who can merge to `main` can change what this no-reviewer job does: `gh api repos/jikig-ai/soleur/rulesets` lists CI Required, CLA Required, Copilot review and Force Push Prevention and none carries a pull-request-review rule, so neither a CODEOWNERS row nor a second reviewer is an enforced control today (the CODEOWNERS header calls enforcement an admin follow-up). The main-only branch policy is the boundary, and ADR-241 calls it nominal until residual R1 closes (a holder of the soleur-ai runtime key can rewrite it). The allowlist is hygiene against accidental inheritance (the parent step shell keeps the full environment readable at `/proc/$PPID/environ` by same-UID processes), not a boundary; the shape test narrows a casual edit and, because it lives in the required `test` check, makes a deliberate edit visible in review, but one pull request can change both the workflow and the test. Anyone with repository write access can also DISPATCH this job on demand (they cannot change what it runs), a trigger surface apply-on-merge does not have. On a public repository logs and summaries are world-readable and masking is bypassable by encoding, so a malicious merge needs no external endpoint to exfiltrate.
- The preflight's `prd_terraform` fallback arm is dead after O10; it is left in place (the host-create jobs' tests pin it) and is unreachable here because the loader's Tier-B arm filters `DOPPLER_TOKEN` out of its exports, the workflow passes no legacy token, and the allowlist drops it anyway.
- Not verifiable before merge: the Tier-B project actually holds a valid `DOPPLER_TOKEN_TF` (first dispatch settles it); the step has zero in-PR executions against the live loader (the behavioural rows use the real preflight and checker with a Doppler stub; the learnings' sequential bring-up walls apply, so the first dispatch is a verification step, not a formality).
- The allowlist (PATH, HOME, TMPDIR, LANG and the one token) is proven only against a Doppler stub; the real CLI may need another variable (a failure reads as rc 3 `unreadable`, never as a leak), so the first dispatch is its real test. `SHELLOPTS` is exported readonly, so the unset cannot clear it; that fails closed for `xtrace` (the preflight refuses it with rc 78) but NOT for `noexec`: `SHELLOPTS=noexec` makes the step a green no-op with no `Verdict:` line, which the runbook decode table names as 'green without a Verdict line is NOT a pass'. Both are known gaps in the deny-by-default claim.
- The public job summary carries missing-secret NAMES and fixed sentences, the same exposure the birth jobs' annotations already have; prd-root advisory names stay a count.

## Deferred, gated follow-ups (recorded here and in the ADR-241 note; no issue is filed, see decision-challenges.md)

| Item | Why deferred | Re-evaluation trigger |
|---|---|---|
| Scheduled / Inngest-dispatched escrow check | Needs a TS Inngest function, trigger-cron allowlist entry and a monitor; value is early drift warning between births only | Births become frequent, or escrow config drift is observed between two births |
| Narrow credential for the diagnostic (a D11-style narrow project holding only a names-read token) | Needs a minted project and token (excluded by the brief). Already tracked by #9461 (no second issue); the ADR note links D11's pattern | The workplace token is next rotated, or #9461 is picked up (then also revisit this workflow's loader use) |

## Risks

- **Whole-Tier-B exposure in a no-reviewer job (highest).** Mitigations above; stated in the ADR note. A reviewer-gated environment is not an alternative: it would defeat the unattended purpose and ADR-241 states a reviewer gate is not the boundary.
- **#9461 overclaim.** This removes the need for a separate minted credential on the DIAGNOSTIC path only. The birth/replace jobs keep using the workplace token via the same loader export until #9461 lands; the comment on #9461 says exactly that.
- **First dispatch fails on a never-run workflow.** Budgeted: sequential walls are expected (learning 2026-07-18); the step is one place, and the runbook decode table maps each outcome to its next action. A failed first dispatch is fixed by a normal PR and re-dispatched; there is nothing to roll back because nothing was written.
- **False green from an empty capture.** Guard 2 H1: PASS only when rc is 0 AND the exact `live-ok` line is present.
- **`unset` of a readonly variable** can fail; the loop guards each `unset` with `2>/dev/null || true` (non-verdict path), and the loop reads `compgen -e` with `while read` (not `for v in $(...)`, which actionlint flags and `lint-workflows.sh` would let through).
- **Claim hygiene.** P2 is worded as "this workflow's steps change nothing", never "the dispatch cannot change anything": the token can.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one carries all four lines and `requires_cpo_signoff: true`.
- Do not "simplify" the allowlist into `env -i TF_VAR_doppler_token_tf="$TF_VAR_doppler_token_tf" ...`: that puts the token in `env`'s argv.
- Do not add `actions: write`, `issues: write` or any scope "to be able to report"; the summary and the run conclusion are the report.
- Do not dispatch the workflow from the work or ship phases; the dispatch is the post-merge step.
- Keep prose in the workflow comments free of Terraform plan/apply command text and passphrase-pair addresses (the target-parity scans strip comments, but a comment-stripper bug should not be able to red an unrelated suite).
- Task subagents see prompt text only: when spawning review agents at work/review time, quote the Guard Contract tables and the rc matrix into the prompt.
