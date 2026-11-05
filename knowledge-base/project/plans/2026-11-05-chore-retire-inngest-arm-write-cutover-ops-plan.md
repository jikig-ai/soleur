---
title: "chore: retire the Inngest cutover write ops that need the arm-write token (epic #9927 item 8, prerequisite)"
date: 2026-11-05
slug: retire-inngest-arm-write-cutover-ops
branch: feat-one-shot-9927-retire-inngest-arm-write-ops
issue: 9927
type: chore
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# chore: retire the Inngest cutover write ops that need the arm-write token (Ref #9927 item 8)

## Enhancement Summary

**Deepened on:** 2026-11-05
**Agents used:** repo-research-analyst, learnings-researcher, CTO (six rulings, two amending the brief), DHH-style, Kieran-style and simplicity plan reviewers, a sharp-edges catalogue pass, security-sentinel, architecture-strategist, terraform-architect. Halt gates 4.6-4.13 were run by hand (see below).

### Key improvements folded in

1. Scope corrected by the CTO: three ops retired, `rollback` and `resume` kept (the arm token stays consumed by exactly those two).
2. Preflight semantics made precise: blind-instrument detection (`jq` shape check, missing `doppler`/`jq`, invalid JSON), xtrace refusal, step-block-scoped mutation checks, stub argv and token assertions, hardened extraction harness.
3. Guard 3 closed the realistic swap (the published secret carrying the arm token's key) and the by-reference project/config pin; Guard 2 gained the positive label set and a separate `if:` extraction.
4. The 282-byte headroom on `apply-web-platform-infra.yml` is a first-class constraint with a dry-run step.
5. Merge-time production effect stated plainly (the push apply mints a token and a repo secret).

### New considerations discovered

- The deletions make `lint-shell-capture-exit` and `fixture-relative-assert` baselines stale; `model.likec4.json` is generated from `model.c4`.
- A repo-scoped secret resolves in any workflow on any pushed branch; after the eventual arm revoke the new token is the only repo-wide read path to the LUKS passphrase (standing exposure with a named rotation owner).
- Both Terraform parents carry `prevent_destroy`, so the by-reference edge fails safe on a teardown.

### Halt gates (deepen-plan Phase 4)

4.6 User-Brand Impact present, `aggregate pattern`; 4.7 Observability present, probe replaced with a sub-second `grep -cF` (the suite cannot fit the 15 s cap); 4.8 no PAT-shaped variable; 4.9 not a UI plan; 4.10 Encryption Posture present with `does_not_defend` populated; 4.11 `lint-guard-contract.py` green, three entries, assemblies structural; 4.12 one unfenced Scope Check, all rows justified; 4.13 no new autonomous-task surface (a test suite and a step edit); 4.55 not triggered (additive resources, no reboot or lock). Cited issue and PR numbers were checked live; the `#7228` label is the repo's own name for the inherited-done guard as used in the workflow text (the GitHub issue of that number has an unrelated title), and is cited as the workflow cites it.

`Ref #9927` only. Spec lacks a valid `lane:` - defaulted to cross-domain (fail-closed). The epic stays open; nothing here closes it (`wg-use-closes-n-in-pr-body-not-title-to` does not apply: no `Closes`).

## Overview

`doppler_service_token.inngest_arm_write` (read/write on `soleur-inngest/prd`, published as the repo
secret `DOPPLER_TOKEN_INNGEST_ARM`) is the last wide CI credential into the isolated Inngest Doppler
project. Epic #9927 item 8 wants it revoked by its owner. That revoke is **not** part of this PR and
is not authorized by it. This PR is the CI-and-code prerequisite: it removes every consumer of the
token that can be removed safely today, moves the one read-only consumer to a new read-only token,
and records precisely which two consumers remain and why.

**Read this first (also the first lines of the PR body).** (1) Merging this PR alone mutates production in one narrow way: the push-triggered per-merge apply creates the new read-only Doppler token and its repo secret; the merge click is the per-command authorization for that (`hr-menu-option-ack-not-prod-write-auth`). Nothing else is applied or dispatched. (2) This PR departs from the brief on two points, on a technical ground ruled by the CTO: it keeps `op=rollback` and `op=resume`, so the arm-token revoke is still blocked on them. (3) The new read token buys nothing until the arm token is eventually revoked; until then it is one more read path into the config.

Four changes, in the order the CTO ruled:

1. **Mint a read-only CI token** for `soleur-inngest/prd` (Terraform file only, no dispatch, no
   manual apply) and move the host-replace inherited-done preflight read onto it. The preflight
   **fails closed** when the token is empty or the instrument cannot read.
2. **Retire `op=arm`, `op=reflush`, `op=luks-cutover`** from `cutover-inngest.yml` and
   `scripts/cutover-inngest.sh` (by deletion, not stubs). Their flags are terminal.
3. **Keep `op=rollback` and `op=resume`** (CTO amendment of the same day, see Research
   Reconciliation): they are the live break-glass verbs once the flip is `done`, so the arm token
   stays consumed by exactly those two until a replacement write-credential design exists.
4. **Update the tests, runbooks, ADR-282 and the C4 edge text** so nothing asserts or documents
   the retired verbs or the old preflight wiring.

### Phase 0 record: the flip state (read-only, taken at plan time)

Read with the maintainer's own Doppler CLI session, `--plain` get of one non-secret enum each, no
write of any kind, 2026-11-05T09:51Z:

| Key (`soleur-inngest/prd`) | Value | Meaning |
|---|---|---|
| `INNGEST_CUTOVER_FLIP` | `done` | terminal: the cutover completed |
| `INNGEST_LUKS_CUTOVER` | `done` | terminal: the LUKS cutover completed |

Live token roster on that config (`doppler configs tokens -p soleur-inngest -c prd --json`, name and
access only, no key material): `inngest-boot` read/write, `inngest-cutover-arm` read/write. There is
no read-only token. The new `inngest-ci-flip-read` does not exist yet.

The work phase re-reads both values first (Phase 0, step 1) and stops if either is no longer
terminal.

## Research Reconciliation - Brief vs. Codebase

| Brief / ruling claim | Reality (measured) | Plan response |
|---|---|---|
| Retire `arm`, `rollback`, `reflush`, `luks-cutover`; keep `resume` only if flip is not `done` | `op=resume` G1 accepts `done` only (`scripts/cutover-inngest.sh` `resume)` arm), so `flip=done` is exactly when it is needed; the runbook makes it step two of every `inngest-host-replace`. `op=rollback` is two halves: (A) a flag write and FSM confirm that stops the dedicated scheduler, (B) the web-scheduler re-enable over the deploy webhook; it is the only documented remedy named by `scheduled-inngest-health.yml`, `restart-inngest-server.yml`, `deploy-inngest-image.yml` and the host `ci-deploy.sh` refusals | CTO amendment (decision-challenges F1, F2): retire three ops, keep two. The arm token stays consumed by `rollback` and `resume`. The brief's direction is **not** followed to the letter on this point, on a technical ground the CTO ruled; the owner-reserved revoke is unchanged and now additionally blocked on those two |
| Preflight "only warns+skips when the token is empty" | Confirmed (`apply-web-platform-infra.yml`, step `Preflight - warn if this replace will strand the scheduler (#7228)`): `continue-on-error: true`, every failure path `exit 0` | Rewrite per F3: fail closed on an unreadable instrument |
| "token-drift-read-tokens.tf has a read token for project soleur only" | Confirmed: `for_each` over `doppler-config-inventory.txt`, `project = "soleur"` | New file `inngest-flip-read-token.tf` (F4); the token never joins the drift map |
| Reserved name `DOPPLER_TOKEN_INNGEST_FLIP_READ` | Already reserved in the `CONSUMERS` comment of `inngest-arm-write-token.tf` (consumer 3), which also says the read token is "STILL UNBUILT AND UNTRACKED" | Use that name; the comment is updated, no resource edit |
| Open PRs #12100 and #12064 touch the same files | #12100: `token-drift-read-tokens.tf`, `doppler-config-inventory.txt`, `terraform-target-parity.test.ts` (its drift-inventory floor 13 to 16, a different number from the shape-gate parity floor of 16 below). #12064 (WIP): `apply-web-platform-infra.yml` (+3 target lines), `cutover-inngest-workflow.test.sh` (+8/-8), `terraform-target-parity.test.ts` (+169/-1). Neither is merged | F6: ship independently; whichever merges second rebases; recompute counts, never hand-add |
| `cla-signed-author-gate.test.sh` T15 (#12120) may block CI | #12120 is an **issue** (no PR yet). Main CI is green at `625e605d31` | Conditional Phase 0 step 3: only if this PR's CI turns red on it, fix first as its own one-file PR |
| `apply-web-platform-infra.yml` room for the edit | The file is **489,718 bytes against a 490,000-byte gate** (`plugins/soleur/test/workflow-file-size.test.ts`); 282 bytes of headroom | The preflight rewrite must be net-shrinking; move rationale prose into the runbook (precedent named by that test) |
| Item-8 text says "scope or revoke" the token | Scoping is impossible: Doppler tokens are per-config, there is no per-secret narrower write token | Retire consumers; do not re-point writes |

## Research Insights

### Premise validation (Phase 0.6)

Cited artifacts checked on this branch (`git show`/`grep`/`gh`): #9927 OPEN; #12100 OPEN (not merged);
#12064 OPEN WIP; #12120 is an open issue, not a PR; collision pre-check hit only this branch's own
draft PR #12133 plus another worktree's long-running `test-all.sh`. The two Doppler values were read
live (table above). Held: the token, the preflight, the workflow ternaries and all line anchors.
Stale: the brief's "retire resume if `done`" and "retire rollback" (reversed by the CTO after
reading the code, F1/F2). ADR corpus: ADR-282 addenda (2026-10-30, 2026-11-01, 2026-11-04) already
record that the flip-token split is built, undelivered until the next owner-gated replace, and that
"design nothing on the CI side" for where CI flag writes move; this plan designs no new write path.

### Property list (Phase 0.6b)

P1. After the owner eventually revokes the arm token, the host-replace preflight still reads the flip
    state and fails loudly, never silently skips, if it cannot.
P2. Fewer dispatch verbs can write `soleur-inngest/prd` flags with a read/write CI credential.
P3. The CI read credential into `soleur-inngest/prd` cannot write.
P4. No live text sends an operator or alert to a verb that no longer exists.
P5. No test keeps asserting a deleted verb, and no guard goes vacuous when its subject is deleted.
P6. The recovery for an inherited-`done` host replace and for a quiesced web scheduler keeps working.

### Cut list (mechanisms considered and cut)

| Mechanism | Property it would buy | What already covers it / why cut |
|---|---|---|
| Stubs that exit 1 for retired ops | P4 | F5: deletion plus an absence assertion covers it with less dead code |
| Re-point `rollback`/`resume` to a narrower write token | P2 | Does not exist: Doppler tokens are per-config (brief, confirmed) |
| Put the new token in `token-drift-read-tokens.tf` / the drift map | P3 | The map is a `for_each` over `soleur` configs; a different project cannot join it (F4) |
| Retire `rollback`/`resume` now with a Doppler-console write as the recovery | P2 | Skips resume's G3/G4 gates; the code names an early `flushed` write a dead end (F2) |
| Edit host-side `ci-deploy.sh`, sudoers, `cloud-init.yml` text that says `op=rollback` | P4 | `rollback` is kept; and `ci-deploy.sh` is a config-bundle member compared by sha256 (F1) |
| New workflow or dispatch route for rotating the new token | P1 | Existing family-wide gap tracked at #7263; `-replace` recipe goes in the new file's comment |
| `scripts/lib/inngest-probe-row.test.sh` `LUKS_TAG` literal cleanup (unlocked by retiring `luks-cutover`) | P5 | Not asked; touches a probe-row contract; left as is |

### Institutional learnings applied

- `2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`: a gate that SKIPs on missing data is fail-open; fix the preflight to FAIL and test the failure path.
- `2026-05-20-doppler-write-token-bootstrap-cycle-and-access-enum.md`: `access` enum is `"read"` / `"read/write"`, ForceNew; a repo secret minted mid-run is empty for that same run (hence the merge-to-first-use window below); `key` is unreadable after create.
- `security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`: a read token over a Doppler config reads the whole config. `soleur-inngest/prd` holds `INNGEST_REDIS_LUKS_KEY`, `INNGEST_TLS_KEY`, `INNGEST_SIGNING_KEY` and `INNGEST_EVENT_KEY` (names verified live). The new token is **not** a least-privilege boundary for reads, only for writes; the plan and the `.tf` comment say so.
- `2026-03-29-doppler-service-token-config-scope-mismatch.md` (with its 2026-08-04 correction): keep `-p`/`-c` on every read; a wrong `-c` errors loudly and that error is the binding control.
- `workflow-issues/2026-10-29-retiring-a-gate-arm-the-interlock-parser-and-the-ci-ratchets-it-trips.md`: `wc -c` on `apply-web-platform-infra.yml` before and after; run `lint-infra-no-human-steps.py --changed` before the first push; run the whole-tree ratchets, not only touched-file suites.
- `2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried.md`: expected sets derived from the artifact under test are tautologies; deleting a payload shrinks both sides. Derive expected op sets independently (a literal list in the test).
- `2026-06-17-terraform-target-parity-test-guards-only-terraform-data-subset.md`: a misspelled `-target=` for a `doppler_*` resource can no-op silently; check both new addresses by hand and via the #5566 publish rule.
- Post-mortem `inngest-inherited-done-host-replace-strand-postmortem.md`: the preflight must be pinned to the host it guards; its recovery text names `op=resume` and stays correct because `resume` is kept.

### Verified facts the plan leans on

- Script structure: `case "$OP"` at the dispatcher; arms `arm)` (lines 2471-3198, about 728), `reflush)` (about 105), `luks-cutover)` (about 90, to end), kept: `rollback)`, `resume)`, `enumerate`, `registry-probe`, `doublefire-probe`, `rearm`, `capture`, `verify-wiped-volume`, `backup`, `inventory`, `execute`, `quiesce-web`, `verify`. The only `$OP` validation is the `*)` unknown-op arm; there is no usage string.
- Helper call graph (grep over the script, to be re-run at work time with `git grep -n`):
  deleted with the three arms (callers only in `arm`/`reflush`/`luks-cutover`): `diag_boot_decide`, `flush_latch_decide`, `g3_action`, `g3_decide`, `_flush_latch_count`, `confirm_luks_state`, `_luks_pointer_state`, `_luks_liveness_count`, plus the globals `FLUSH_LATCH_SINCE` and `LUKS_LIVENESS_SINCE`.
  **kept**: `confirm_flip_state` (rollback), `_flip_liveness_count`, `resume_liveness_decide`, `resume_bootstrap_decide`, `FLIP_LIVENESS_SINCE` (resume), and the generation-scope chain `_inngest_server_created_epoch`, `_hcloud_created_epoch`, `_generation_scoped_count`, `_current_instance_row_counts` (still reachable through `_flip_liveness_count`), `_fsm_own_rows`, `_flip_transition_dt`, `doublefire_from`.
  The research agent's first pass listed resume/rollback helpers as deletable; that was under the superseded retire-five scope and is corrected here.
- Workflow: the `Export Inngest arm token (gated ops only)` step stays but its `if:` and `env:` ternary narrow to `rollback || resume`; the `environment: inngest-cutover` ternary becomes `rollback || resume || backup`; `FLUSH_LATCH_SINCE` env mapping and its comment block go; header comments and `inputs.op.options` lose the three verbs.
- `tests/scripts/test-argv-bearer-sweep.sh` asserts an exact HMAC-copy count and has an arm mask battery (`ar_run`); both change only to the degree the arm arm contained copies (recompute, do not assume).

## Problem Statement

Today the repo secret `DOPPLER_TOKEN_INNGEST_ARM` has two consumer families. (a) Five `cutover-inngest.yml` verbs write flags with it, three of them for cutovers that finished (`arm`, `reflush`, `luks-cutover`; `INNGEST_CUTOVER_FLIP` and `INNGEST_LUKS_CUTOVER` are `done`). (b) The `inngest_host_replace` preflight reads `INNGEST_CUTOVER_FLIP` with it, and silently skips when the secret is empty, so a revoke would turn that guard into a permanent no-op that still prints "SKIPPED" as a warning nobody acts on. A wide, standing, read/write credential for a finished operation is a liability whose removal is blocked by (b).

## Proposed Solution

See Overview. Design decisions are rulings F1-F6 in `knowledge-base/project/specs/feat-one-shot-9927-retire-inngest-arm-write-ops/decision-challenges.md`.

### Preflight semantics (F3, binding)

1. `DOPPLER_TOKEN_INNGEST_FLIP_READ` empty: print an error naming the missing secret and the per-merge apply that mints it, `exit 1`. `continue-on-error: true` is removed from the step (otherwise the `exit 1` is a no-op, and `continue-on-error` forces `conclusion: success`).
2. Names list: `doppler secrets --only-names --json -p soleur-inngest -c prd` with that token as `DOPPLER_TOKEN`. The instrument is blind (`exit 1`) unless ALL of: `doppler` and `jq` exist, `doppler` exits 0, the output is non-empty, and `jq -e 'type=="object" and length>0'` succeeds. Only then is `jq -e 'has("INNGEST_CUTOVER_FLIP")'` consulted, and there exit 1 means "absent" while exit 2, 127 or any other code means blind. (The existing `_luks_pointer_state` idiom conflates jq exit 1, unparseable output and a missing `jq` as "absent", which is fail-open; it is not copied verbatim. The stub fixtures come from a real read-only capture in Phase 0 step 5.)
3. `INNGEST_CUTOVER_FLIP` absent from the names: warn "unset", `exit 0` (the normal pre-cutover state; unchanged text).
4. Present: `doppler secrets get INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd --plain`; non-zero exit: `exit 1`.
5. Read succeeded and value (whitespace-stripped with `tr -d '[:space:]'`, matching the on-host readers) is empty: keep the existing warn-and-proceed text.
6. `armed`/`flipping`/`flushed`/`done`/other-value branches and the `$GITHUB_STEP_SUMMARY` block are unchanged, except the RECOVER text gains one clause: `op=resume` accepts `done` only.

Scope of "fails closed": it covers an unreadable or blind instrument only. A successful read of `done`, `armed`, `flipping`, `flushed` or any other value stays exit 0 with its existing warning and summary, by design (the replace is often what the owner wants).

Rationale for 2/4 versus a bare `rc != 0`: an absent secret is the normal pre-cutover state, so rc alone cannot tell "absent" from "blind". The names-list idiom is already used by `_luks_pointer_state`.

## Implementation Phases

Order is test-first (`cq-write-failing-tests-before`): Phase 1 produces RED, Phases 2-5 turn it GREEN.

### Phase 0 - Preconditions (read-only, no edits)

1. Re-read both flags (`doppler secrets get INNGEST_CUTOVER_FLIP -p soleur-inngest -c prd --plain`, and `INNGEST_LUKS_CUTOVER`) and record value plus UTC time in the PR body. If either is not `done`, STOP: the premise of retiring `arm`/`reflush`/`luks-cutover` changes; re-open F1/F5 with the CTO.
2. `git fetch origin main`; note whether #12100 and #12064 have merged. If merged, rebase now and recompute the two counts (F6) before editing.
3. Only if CI on this PR turns red on `.claude/hooks/cla-signed-author-gate.test.sh` T15: stop, fix first as its own ~4-line one-file PR giving `push_cla_yml` and `push_cla_signatures` a test-local git identity (the `git -C "$work" config user.email/user.name` pattern), merge it, rebase this PR. Reproduce locally with `HOME=$(mktemp -d) GIT_CONFIG_GLOBAL=/dev/null bash .claude/hooks/cla-signed-author-gate.test.sh`.
4. `wc -c .github/workflows/apply-web-platform-infra.yml` (baseline 489,718).
5. Capture, read-only and names only, the real CLI shapes the stub must reproduce: `doppler secrets --only-names --json -p soleur-inngest -c prd` (a JSON object keyed by name) and `doppler secrets get <absent-key> -p soleur-inngest -c prd --plain` (its exit code and stderr). Store them as synthesized fixtures in the new suite (`cq-test-fixtures-synthesized-only`: names only, no values).

### Phase 1 - Failing tests first

1. New suite `apps/web-platform/infra/inngest-host-replace-preflight.test.sh` (Guard 1): extracts the preflight step's `run:` body from `apply-web-platform-infra.yml` by step name (non-vacuity: at least 40 non-comment lines, the step name found exactly once) and executes it under a `doppler` stub, covering every row of the Guard 1 harness table, and asserting the stub's argv (`-p soleur-inngest -c prd`) and that the `$DOPPLER_TOKEN` the stub sees equals the flip-read value (dropping the inline `DOPPLER_TOKEN=` override would otherwise read with the ambient Tier-A token and go unnoticed). RED now (the step still reads the arm secret and exits 0 everywhere). Harness hardening: match the step name with a fixed-string comparison (it contains `(#7228, #9927)`); write the extracted body to a temp file and run `bash <file>`, never `eval`; run under `env -i` with a temp `HOME`, `GITHUB_STEP_SUMMARY` and `GITHUB_ENV` and a PATH built from a symlink farm holding only the stub, `tr` and `printf` plus `jq` toggled per row (a runner's real `doppler` or an ambient `DOPPLER_TOKEN` must not be able to satisfy the stub-sees-flip-read assertion); read the env-var name from the step's own `env:` block; use fake token strings that do not resemble `dp.st.` secrets (keeps secret scanners quiet).
2. In `apps/web-platform/infra/cutover-inngest-workflow.test.sh` add the Guard 2 absence block (retired verbs absent from options, case labels, ternaries; token-op set literal `rollback resume`; environment-op set literal `backup resume rollback`). RED now.
3. Static pins for the new token (Guard 3) in the same preflight suite: `access = "read"`, by-reference project/config, not in `token-drift-read-tokens.tf` or `doppler-config-inventory.txt`, both addresses present in the default per-merge `-target` list. RED now (file absent).
4. Register the new suite wherever `scripts/lint-orphan-test-suites.sh` requires (run it; `apps/web-platform/infra/*.test.sh` is normally picked up by the infra runner glob in `infra-validation.yml`, but the orphan lint and `scripts/lib/test-affected-paths.sh` decide).

### Phase 2 - Terraform (file only; applied by the standard per-merge pipeline, never dispatched)

1. Create `apps/web-platform/infra/inngest-flip-read-token.tf` (F4, details in `## Infrastructure (IaC)`).
2. `apply-web-platform-infra.yml`, the default allow-list step: add `-target=doppler_service_token.inngest_flip_read` and `-target=github_actions_secret.doppler_token_inngest_flip_read` each beside its arm sibling (the token target next to `doppler_service_token.inngest_arm_write`, the secret target next to `github_actions_secret.doppler_token_inngest_arm`; this keeps the #12064 conflict surface small), and never between `doppler_secret.inngest_redis_luks_key` and `supabase_project.prd` (the parity test pins the TLS targets directly after the former and `supabase_project.prd` after them). **Not** the `inngest_host` job (its shape-gate parity floor, `targets.length` equal to 16 in `terraform-target-parity.test.ts`, stays untouched and is unrelated to #12100's drift-inventory floor).
3. `inngest-arm-write-token.tf`: comment-only edits. The `CONSUMERS` block (consumer 1 is now `rollback`/`resume` only; consumer 3 reads `DOPPLER_TOKEN_INNGEST_FLIP_READ`; strike "STILL UNBUILT AND UNTRACKED"), and the other comments that name `op=arm`/`op=reflush`/`op=luks-cutover` as consumers or as the reviewer-gated jobs (the file header, the "Human ack" paragraph, the environment-secret comment), so property P4 holds for this file too. No resource block is edited, nothing deleted; the file stays (hard limit).
4. If `terraform-target-parity.test.ts` needs a new `test(` block (only if one is added), recompute `TEST_FLOOR` with `grep -cE '^\s*test\(' plugins/soleur/test/terraform-target-parity.test.ts`, set exactly that, and add a `prev -> new` comment line citing this PR (F6). Do not hand-add.

### Phase 3 - Preflight rewrite (size-neutral or smaller)

1. Replace the step per `### Preflight semantics`. Rename the step to `Preflight - inherited-done check, fails closed (#7228, #9927)`; remove `continue-on-error`; env `DOPPLER_TOKEN_INNGEST_FLIP_READ: ${{ secrets.DOPPLER_TOKEN_INNGEST_FLIP_READ }}`. The step's first line is the xtrace refusal this workflow already uses elsewhere (`case "$-" in *x*) ... exit 78`, see the existing instances in the same file): under a `BASH_ENV`/`SHELLOPTS` trace the inline `DOPPLER_TOKEN=... doppler` assignment would otherwise print the token. Both `doppler` calls discard stderr and the error branches print only an exit code, never the names JSON. The empty-token and blind-instrument `::error::` text names the secret, says the per-merge apply mints it, and says to re-run the failed `apply-web-platform-infra` push run if the apply was partial (never `-replace` the token on a partial apply: that orphans a live key).
2. Move the long rationale comment blocks (the 2026-09-17 incident narrative, the `rc` CAPTURED paragraph, the `done is not the only stranding value` paragraph) into `knowledge-base/engineering/operations/runbooks/inngest-server.md` under the existing inherited-`done` section; leave a two-line pointer in the workflow. The runbook sentence "degrades open on an unreadable flag" becomes "fails closed".
3. Dry-run first: write the new step into a scratch copy and `wc -c` the whole file BEFORE committing to the shape; the new branches add bytes that the moved prose must more than repay. If it does not fit, move more prose to the runbook, not code. `wc -c` after: must be at or below baseline, and `bun test plugins/soleur/test/workflow-file-size.test.ts` green. Run `python3 scripts/lint-infra-no-human-steps.py --changed`.
4. Grep proves zero remaining `DOPPLER_TOKEN_INNGEST_ARM` references in `apply-web-platform-infra.yml`, comments included: the new pointer comment names the runbook and the new secret, never the old one.

### Phase 4 - Retire arm, reflush, luks-cutover (deletion)

1. `.github/workflows/cutover-inngest.yml`: remove the three options and their comments; narrow the three ternaries/`if:` as in Research Insights; delete `FLUSH_LATCH_SINCE` env mapping and its G3.7 comment block; rewrite header and job comments that name the retired verbs.
2. `scripts/cutover-inngest.sh`: delete the `arm)`, `reflush)`, `luks-cutover)` arms; delete a helper or global only after `git grep -n '<name>' scripts apps tests plugins .github` shows no remaining caller **and** no remaining test that sources it (re-derive per helper, do not trust the list above). Keep `confirm_flip_state` and the resume/rollback helpers.
3. Rewrite live operator text inside kept code: the `execute)` arm's `GATE_REMEDY` and SEAM text that say "Dispatch the no-SSH op=arm verb"; the `rollback)` text that says "re-dispatch op=arm" (new text: a re-cutover needs a reviewed re-introduction of `arm`, i.e. a revert of this PR). Also in the kept `resume)` arm: the operator text that says "Use op=arm for a fresh cutover" and "op=arm is separately refused by G3.7" (grep the arm for `op=arm`). The `resume)` and `rollback)` arms are otherwise unchanged. Phases 4 and 5 and the floor recompute land as ONE commit (per-phase commits would leave red tests or a floor that disagrees with the live count at an intermediate commit); confirm against the lefthook ratchets.
4. Do **not** touch host-side files (`ci-deploy.sh`, `deploy-inngest-bootstrap.sudoers`, `cloud-init.yml`, `inngest-inventory.sh`, `inngest-rearm-reminders.sh`, `inngest-cutover-flip.sh`): `rollback` and `resume` are kept, and the config bundle is sha256-compared.

### Phase 5 - Prune and re-derive the tests

1. `apps/web-platform/infra/cutover-inngest-workflow.test.sh`: delete every block that exists only for the three retired verbs (arm assembly, G3.5/G3.6/G3.7, g3/diag/flush-latch harnesses, luks-cutover, reflush); keep resume and rollback blocks and the shared reader blocks. Fix the arm-token wiring asserts the brief names (the lines anchored on `G3.5 reads the HOST key ... via the arm token`, `job gates op=arm/op=rollback on the inngest-cutover environment`, `DOPPLER_TOKEN_INNGEST_ARM injected conditionally`, and the `ENV_OPS == CRED_OPS` parity row with its `TOK_EXPR` extraction), turning the parity row into the literal-set form of Guard 2. Non-vacuity asserts on emptied extractions (`ARM_FILE`, `LUKS_FILE`, `RFL_FILE`) are deleted with their subject, never left to pass on an empty file. The "shared reader has exactly N call sites" assert is re-counted from the file.
2. `_EXACT_FLOOR` (and its two-direction FATAL) is a runtime PASS+FAIL count of the suite, not a grep: run the suite and read the `STALE FLOOR` FATAL line for the number; set exactly that; comment `prev -> new (this PR)`. Only `TEST_FLOOR` in `terraform-target-parity.test.ts` uses the `grep -cE '^\s*test\('` count.
3. `tests/scripts/test-argv-bearer-sweep.sh`: remove the arm mask battery and its `$CUT` extraction; recompute the exact HMAC-copy count only if the deleted arms contained copies; keep rollback's.
4. `tests/scripts/test-infra-privileged-tier-census.sh`: unchanged for the arm token (row 2j stays valid, the secret remains); run it with `secrets.DOPPLER_TOKEN_INNGEST_FLIP_READ` newly referenced in `inngest_host_replace` and add a row only if the census flags it.
5a. Baselines that carry rows keyed to the deleted arm blocks: `scripts/lint-shell-capture-exit.baseline.txt` (may only SHRINK) and `plugins/soleur/test/fixture-relative-assert.baseline.txt` (row-equality): drop or re-key the `ARM_FILE`-based rows (for example `FLIP_SET_LN`, `G4_WRITE_LN`, `PARITY_LN`) in the same commit; the new preflight suite must be clean against `lint-shell-capture-exit`. In the pruned test file: delete the assertion that puts `luks-cutover` in `ENV_OPS` and keep the one that pins `luks-rollback` absent.
5. `scripts/ci-pr-affected-audit.accept.tsv`: re-derive any row whose anchored boundary line changed (the anchor is a sha256 of the line); `scripts/lint-hcloud-token-readonly-no-fallback.sh` cites a `cutover-inngest.sh` line number: convert to a content anchor (`cq-cite-content-anchor-not-line-number`).
6. Run the whole-tree ratchets, not only touched suites: `bash scripts/test-all.sh` for the infra and scripts legs, `bun test plugins/soleur/test/terraform-target-parity.test.ts`, `bun test plugins/soleur/test/workflow-file-size.test.ts`, `bash plugins/soleur/test/c4-count-parity.test.sh`.

### Phase 6 - Docs and records

1. Runbook `inngest-server.md`: remove or mark retired the `arm`, `reflush`, `luks-cutover` rows and sections; the quick-reference rows that name them; add one note that a re-cutover or a second FLUSHALL now needs a reviewed re-introduction of the verb (revert of this PR) and, for the on-host reflush arm, a Doppler-console write of `INNGEST_CUTOVER_FLIP` on `soleur-inngest/prd` preceded by a live read of its current value (acceptable for a catastrophic event, CTO; the bound is the key name, the config and the read-first rule, not a printed recipe). Also update `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`, whose rows list `op=arm`, `op=reflush` and `op=luks-*` among the generation-anchor consumers. Keep the `op=resume` and `op=rollback` procedures. Add a repair line for a dead or missing `DOPPLER_TOKEN_INNGEST_FLIP_READ` (operator-local `-replace` of both targets per the `.tf` header recipe, and re-running a partial per-merge apply). Update the inherited-done text per Phase 3. Runbook `inngest-luks-cutover-6894.md`: add a retirement note modeled on its existing section 5a (`luks-rollback` retired).
2. ADR-282: append an addendum (`soleur:architecture`, no new ordinal): "arm, reflush and luks-cutover retired; rollback and resume remain pending a write-credential design; the preflight reads `DOPPLER_TOKEN_INNGEST_FLIP_READ` and fails closed". The addendum restates the ledger of who reads or writes `INNGEST_CUTOVER_FLIP` by token (arm and reflush rows retired, preflight row now flip-read), cross-references ADR-100 D6b (CI can write `soleur-inngest/prd`) and ADR-241 D2 (the repo-scoped secret is an advisory deviation from the main-only direction, forced by the Terraform App being unable to write environment secrets), and uses the precedent wording "conditional on the PR merging". Append-only: no existing text edited. Other ADRs (100, 117, 142, 225, 257, 307) and the post-mortems are append-only records and are not edited.
3. C4: `model.c4` `github -> hetzner` edge description names "op=arm G3.7 H and op=luks-* G3": rewrite to the surviving verbs; add ONE `github -> doppler` edge whose description covers both CI credentials into `soleur-inngest/prd` (the read/write arm token, now consumed only by `rollback`/`resume`, and the read-only flip-read token), so the model does not carry an edge for only the weaker token (see `## Architecture Decision`). Regenerate the tracked `knowledge-base/engineering/architecture/diagrams/model.likec4.json` with `scripts/regenerate-c4-model.sh` (it carries the same edge text). Run the C4 validation tests and `c4-count-parity`.
4. At ship time (not production-mutating): file the tracking issue "design a replacement write credential for op=rollback and op=resume so doppler_service_token.inngest_arm_write can be revoked" (`wg-when-deferring-a-capability-create-a`, milestone from `knowledge-base/product/roadmap.md`, `Ref #9927`). The issue body carries the F2 precondition (delivery replace plus `op=resume` first, then retire resume and rollback in the same owner-run sequence as the revoke) and `Ref #9927`, which cross-references the epic; no separate epic comment and no `Closes`.

### Phase 7 - Post-merge verification (read-only, agent-run)

1. The per-merge `apply-web-platform-infra` run for the merge commit: log shows the two new resources created, no other change (`git fetch origin main`, take the sha from `git rev-parse origin/main`, then `gh run list -w apply-web-platform-infra.yml --event push --commit <merge-sha> -L 3`; an empty result means "not yet", poll again; require `conclusion=success`, then `gh run view <id> --log | grep -E 'Plan:|Apply complete'`). It is a push-triggered run, not a dispatch, so no dispatch watch is armed, but its conclusion is read.
2. `gh secret list --repo jikig-ai/soleur | grep DOPPLER_TOKEN_INNGEST_FLIP_READ` present; `doppler configs tokens -p soleur-inngest -c prd --json | jq -r '.[]|"\(.name)\t\(.access)"'` shows a row named `inngest-ci-flip-read` with access `read` (metadata only).
3. The first real use of the new secret is the owner-gated replace (Operator Holds). Until then the fail-closed preflight can only be exercised by the test suite; that residual is recorded in the PR body.

## Files to Edit

- `.github/workflows/cutover-inngest.yml` - three options, ternaries, export step, `FLUSH_LATCH_SINCE`, comments
- `scripts/cutover-inngest.sh` - delete three arms and their dead helpers; reword live pointers
- `.github/workflows/apply-web-platform-infra.yml` - preflight step; two `-target` lines; net byte-shrink
- `apps/web-platform/infra/inngest-arm-write-token.tf` - `CONSUMERS` comment only
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` - prune, rewire, Guard 2, floor
- `plugins/soleur/test/terraform-target-parity.test.ts` - only if a `test(` is added: `TEST_FLOOR`
- `tests/scripts/test-argv-bearer-sweep.sh` - arm battery, copy count
- `tests/scripts/test-infra-privileged-tier-census.sh` - only if the census flags the new reference
- `scripts/ci-pr-affected-audit.accept.tsv` - re-derived anchors, if the gate trips
- `scripts/lint-hcloud-token-readonly-no-fallback.sh` - line-number citation to content anchor
- `knowledge-base/engineering/operations/runbooks/inngest-server.md`
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md`
- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` - append addendum
- `knowledge-base/engineering/architecture/diagrams/model.c4` - one edge description rewritten (`github -> hetzner`), one edge added (`github -> doppler`); plus the regenerated `model.likec4.json`
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` - generation-anchor consumer rows
- `scripts/lint-shell-capture-exit.baseline.txt`, `plugins/soleur/test/fixture-relative-assert.baseline.txt` - rows keyed to the deleted arm blocks

## Files to Create

- `apps/web-platform/infra/inngest-flip-read-token.tf`
- `apps/web-platform/infra/inngest-host-replace-preflight.test.sh` (Guards 1 and 3)
- `knowledge-base/project/specs/feat-one-shot-9927-retire-inngest-arm-write-ops/tasks.md`, `decision-challenges.md` (exists)

## Open Code-Review Overlap

None. Queried the open `code-review` issues for every path under Files to Edit (the nine source paths that exist today): no body names any of them.

## Architecture Decision (ADR/C4)

### ADR

Append an addendum to ADR-282 (decision: the CI credential topology into `soleur-inngest/prd` changes; three verbs retired, two kept; a read-only CI token added; the preflight fails closed). This is a topology change a future engineer would be surprised to find undocumented, so it is a deliverable of this PR, not a follow-up. No new ordinal; no existing ADR text edited.

### C4 views

All three model files were read in full for this section (`model.c4`, `views.c4`, `spec.c4`). Enumerated against the feature:
(a) external human actor: the repository owner as approver of the `inngest-cutover` environment - already modeled (the `founder -> github` approval edge, `founder -> doppler`); unchanged.
(b) external systems: Doppler (`doppler`) and GitHub (`github`) - both modeled; the Hetzner edge is touched below.
(c) data stores/containers: the Inngest Redis store (`inngest` durable queue) - modeled, unchanged; the `soleur-inngest/prd` Doppler project is described inside the `doppler` system and the existing `github -> doppler` Tier-B edge names the `inngest-cutover` environment.
(d) actor-to-surface access relationship that changes: CI's read credential into `soleur-inngest/prd` is new and has no edge, and the `github -> hetzner` edge text (the line that says "op=resume G3, op=arm G3.7 H and op=luks-* G3") is falsified by the retirement.
In-scope `.c4` edits: reword that `github -> hetzner` description to the surviving verbs; add one `github -> doppler` edge for the read-only flip-read token (no new element, so no `view include` line is needed - both endpoints are already in every view that includes them). Run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (a derived cardinality in edge prose, e.g. an "N workflows" count, is gated there).

### Sequencing

Decision is true on merge for CI behaviour; the host-side delivery (flip-token split) is unchanged and still rides the next owner-gated replace. No `status: adopting` language needed.

## Infrastructure (IaC)

### Terraform changes

New `apps/web-platform/infra/inngest-flip-read-token.tf` (providers already pinned in the root):

- `doppler_service_token.inngest_flip_read`: `project = doppler_project.inngest.name`, `config = doppler_environment.inngest_prd.slug` (by-reference, as `inngest_arm_write`, F4), `name = "inngest-ci-flip-read"`, `access = "read"`. No `expires_at`, no `lifecycle` block.
- `github_actions_secret.doppler_token_inngest_flip_read`: `repository = "soleur"`, `secret_name = "DOPPLER_TOKEN_INNGEST_FLIP_READ"`, `plaintext_value = doppler_service_token.inngest_flip_read.key`. No `ignore_changes` (a `-replace` rotation must propagate in the same apply).
- Header comment: purpose (the one consumer, the preflight), that it is **not** `doppler_service_token.inngest_flip` (the on-host read/write flip credential, never published), that read access reaches the whole config (names verified: `INNGEST_REDIS_LUKS_KEY`, `INNGEST_TLS_KEY`, `INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY`) so it bounds writes, not reads, the `autonomy-considered: provider-mint-applied` line, the rotation recipe with BOTH `-target`s (token and secret; `-target` selects dependencies never dependents), the by-reference transitive-edge caveat (both `doppler_project.inngest` and `doppler_environment.inngest_prd` carry `prevent_destroy = true`, so a teardown first needs a reviewed lift; do not copy the arm file's "recreates the isolated project unattended" wording verbatim), the teardown ordering (once the arm token is gone this token is the only per-merge path onto those two parents, so a teardown removes both `-target` lines first), the standing-exposure note (a repo secret resolves in any workflow on any pushed branch with no reviewer gate; after the arm revoke this is the only repo-wide read path to `INNGEST_REDIS_LUKS_KEY` and `INNGEST_TLS_KEY`; rotation owner is the repository owner via the recipe above; fetching the token inside the main-only `infra-privileged` job from a Tier-B secret was considered and not chosen, F4), and the repo-scoped (not environment) secret reason (the Terraform GitHub App cannot write environment secrets).
- Sensitive variables: none new. The token is minted by the existing `DOPPLER_TOKEN_TF` provider auth.

### Apply path

(a) The standard push-triggered per-merge `apply-web-platform-infra` run applies the two additive resources through the default allow-list (no dispatch, no `-replace`, no host touched). **Merging this PR alone therefore mutates production**: it mints a Doppler service token and a repo secret; the merge click is the per-command authorization, and the PR body says so in its first line. Expected blast radius: two creates, zero destroys, zero changes to existing resources. No downtime. Other push-triggered workflows with `apps/web-platform/infra` path filters were enumerated (`apply-deploy-pipeline-fix.yml`, `apply-inngest-rls.yml`, `apply-sentry-infra.yml`): none carries these addresses in its `-target` set, and `scheduled-terraform-drift.yml` is plan-only (it may show the two creates as drift for the minutes before the merge apply lands). Nothing is dispatched by this PR's author. The hard limits stand: no `apply_target=inngest-host-replace`, no manual apply.

### Host fan-out

None. No `terraform_data` SSH provisioner is added or edited; no host is touched (the replace gate and `inngest_host` job `-target` set are unchanged).

### Distinctness / drift safeguards

The token name `inngest-ci-flip-read` is distinct from `inngest-boot`, `inngest-cutover-arm` and the on-host `inngest-flip`. `access = "read"` is pinned by the Guard 3 static test. The drift scan (`scheduled-terraform-drift.yml`) is unaffected: this token is outside the `soleur` project and outside `doppler-config-inventory.txt`. State holds the new key in `terraform.tfstate` on the R2 backend, same posture as the sibling tokens; state-loss recovery is `-replace` (mints a new token, orphans the old; revoke by slug).

### Vendor-tier reality check

Doppler service tokens of `access = "read"` are already minted in this root (`token-drift-read-tokens.tf`); no tier gate. GitHub repo-level Actions secrets are the established publish channel here.

## Observability

```yaml
liveness_signal:
  what: the inherited-done preflight step conclusion on every inngest-host-replace dispatch (it now fails the job instead of warning); plus the per-merge apply run that creates the token and secret
  cadence: per host-replace dispatch (owner-gated, rare) and per merge to main
  alert_target: the GitHub Actions run conclusion on the dispatching job; the existing apply-failure channel (main-health-monitor / apply failure issue) for the merge apply
  configured_in: .github/workflows/apply-web-platform-infra.yml (the preflight step)
error_reporting:
  destination: the Actions run log and job summary (the step prints ::error:: lines naming the missing secret, or the failed Doppler read, never a value)
  fail_loud: exit 1 with an ::error:: annotation; continue-on-error removed
failure_modes:
  - mode: DOPPLER_TOKEN_INNGEST_FLIP_READ not yet published (dispatch between merge and the per-merge apply, or after a bad rotation)
    detection: preflight empty-token arm exits 1 naming the secret
    alert_route: failed run on the dispatching actor's terminal and the Actions UI
  - mode: read token revoked or wrong config (names-list errors)
    detection: names-list arm exits 1 ("instrument blind"), distinct from "flag unset"
    alert_route: same
  - mode: INNGEST_CUTOVER_FLIP is done and a replace is dispatched
    detection: existing step-summary block and ::warning:: with the op=resume recovery
    alert_route: job summary
  - mode: a retired verb is dispatched from a stale ref or a stale doc
    detection: the dispatch input no longer lists it (rejected by GitHub); the script's unknown-op arm exits non-zero
    alert_route: failed dispatch
logs:
  where: GitHub Actions run logs for apply-web-platform-infra.yml and cutover-inngest.yml
  retention: the repository's configured Actions log retention
discoverability_test:
  command: grep -cF 'secrets.DOPPLER_TOKEN_INNGEST_FLIP_READ' .github/workflows/apply-web-platform-infra.yml
  expected_output: "1"
```

The probe is the smallest command that prints the wiring signal named in `liveness_signal.what` (the preflight reads the new secret exactly once); it finishes in milliseconds and needs no credentials. The behavioural proof is the new suite `inngest-host-replace-preflight.test.sh`, run by CI, not declared here because a suite cannot finish inside the 15-second probe cap.

## Encryption Posture

```yaml
at_rest:
  - store: doppler_service_token.inngest_flip_read key, held in terraform.tfstate on cloudflare_r2_bucket soleur-terraform-state and in github_actions_secret.doppler_token_inngest_flip_read
    mechanism: provider-managed:Cloudflare R2 server-side encryption for the state object; GitHub Actions secrets are encrypted with a repository libsodium sealed-box public key before upload
    evidence: apps/web-platform/infra/main.tf backend "s3" block (R2, TLS-only) for the state; github_actions_secret resource in inngest-flip-read-token.tf for the secret; same posture as every sibling doppler_service_token key in this root (see the arm file's State storage paragraph)
    defends_against: a leaked R2 object copy at rest without the R2 credential; a read of the repo secret listing (values are write-only to the API)
    does_not_defend: any workflow on any pushed branch in this repository that can resolve repo secrets (the secret is repo-scoped, not environment-scoped, so CODEOWNERS and the main-only environments do not gate it; after the arm revoke this is the only repo-wide read path to the LUKS passphrase); a holder of Terraform state access or R2 credentials, who obtains the key in cleartext; read of the WHOLE soleur-inngest/prd config, including INNGEST_REDIS_LUKS_KEY, by whoever holds the token
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:the token key is unreadable after create and the repo secret is write-only; only token metadata (name, access) is readable, which Phase 7 reads
in_transit:
  - connection: GitHub Actions runner -> Doppler API (api.doppler.com) from the preflight step
    enforced_at: .github/workflows/apply-web-platform-infra.yml (the preflight step, doppler CLI over HTTPS)
    tls: HTTPS, the Doppler CLI default (TLS 1.2 or higher)
    cert_verification: on
    does_not_defend: a compromised runner or a malicious workflow ref that echoes the token; no IP allow-list on the Doppler token
    disclosed_as: not-publicly-claimed
```

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The failure surface is the maintainer's own host-replace dispatch (it would fail loudly at the preflight, which is the intended direction) or, if a kept verb were broken by the deletions, a slower recovery of the web scheduler or the dedicated scheduler (a window of delayed reminders/crons for end users, bounded by the operator-run recovery).
- **If this leaks, the user's workflow data is exposed via:** the new read token. It can read every key in `soleur-inngest/prd` (including the Redis LUKS passphrase of the sole-copy scheduler volume and the TLS key) through any workflow that resolves repo secrets. This is the same exposure class as the existing arm token, strictly weaker (no write) and temporary in the sense that the arm token is the larger credential that this work is a step toward retiring; until that revoke it is one more copy of a read path.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** not `single-user incident`: the new credential adds no capability the standing arm token does not already hold, and the diff removes write-capable verbs rather than adding them; a leak of either token is the same event class, handled by the existing revoke and rotation path.

## Guard Contract

### Guard 1 - Host-replace preflight fails closed

**Property.** The inherited-done preflight can only let a host-replace proceed after it has either read `INNGEST_CUTOVER_FLIP` with a non-empty read token or positively listed the config's key names without that key; an empty token, an erroring names list, or a failing `get` of a present key always fails the job.

**Assembly.** The single step in `.github/workflows/apply-web-platform-infra.yml` (job `inngest_host_replace`), all of its exit paths (empty token; names-list error; names-list ok and key absent; key present and `get` error; `get` returns empty; `armed`/`flipping`; `flushed`; `done`; other value), its `continue-on-error` key, its `env:` secret name, and every other occurrence of `DOPPLER_TOKEN_INNGEST_ARM` or the new secret name anywhere in that workflow file (the chokepoint is the step body extracted by name; there is exactly one such step; any second `Preflight` step or any residual `ARM` reference is itself a RED condition).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `continue-on-error: true` to the step | RED |
| 2 | Change the empty-token arm from `exit 1` to `exit 0` | RED |
| 3 | Rename the step so the by-name extraction returns nothing (the guard's own dispatch: "0 lines checked") | RED (non-vacuity assert on step found once and body length) |
| 4 | Keep the empty-token and names-list arms fail-closed but make the key-present `get` failure `exit 0` (a second member after compliant first ones) | RED |
| 5 | Point the step `env:` back at `secrets.DOPPLER_TOKEN_INNGEST_ARM` | RED |
| 6 | Treat a names-list error as "key absent" | RED |
| 7 | Add a second step elsewhere in the file that reads the arm secret | RED |
| 8 | Names list returns invalid JSON with rc 0 and the step treats `jq`'s non-zero as "absent" | RED |
| 9 | Keep the env key `DOPPLER_TOKEN_INNGEST_FLIP_READ` but give it the value `${{ secrets.DOPPLER_TOKEN_INNGEST_ARM }}`, or any other `secrets.` / `secrets[` / `toJSON(` reference in the step body (the step's `env:` value must equal the literal flip-read expression and the body must contain no other secrets access) | RED |
| 10 | Remove the leading xtrace refusal; run the step with `SHELLOPTS=xtrace` | RED (the step must exit 78) |

Mutation 1 is checked against the step block extracted by name, not the whole file, so a retained comment that merely contains the text `continue-on-error` neither masks nor fakes it.

**Harness rows:** (a) suite edit: make the step treat an empty or `{}` names-list output as "key absent" (the realistic fail-open edit), then the rows "doppler exits 0 with empty output" and "doppler exits 0 with `{}`" MUST turn RED (a harness whose blind-instrument rows pass either way is vacuous); extra must-FAIL rows: names list is invalid JSON with rc 0; `doppler` absent from PATH (rc 127); `jq` absent from PATH; (b) must-PASS inputs that differ from the canonical flow in a permitted way: names-list ok with the key absent (exit 0, warning "unset"); a value of `flushed` with trailing whitespace and CRLF (exit 0, no hazard text); `done` (exit 0, summary block written to a temp `GITHUB_STEP_SUMMARY`); a different but valid token string.

**Anchor.** The test and the step land in one diff, so this proves consistency, not integrity. Independent anchors that are not in this diff: the replace gate and workflow-file-size test (unchanged) and the owner-gated nature of the dispatch. No outside registry is introduced; the residual is accepted and recorded.

### Guard 2 - Retired verbs stay retired, credentialed op sets agree

**Property.** `arm`, `reflush` and `luks-cutover` appear in no `workflow_dispatch` option, no `case "$OP"` label and no ternary of `cutover-inngest.yml`/`cutover-inngest.sh`, and the op set that receives the arm token equals exactly `{rollback, resume}` while the reviewer-gated set equals exactly `{backup, resume, rollback}`.

**Assembly.** Four places in `cutover-inngest.yml` (options list, `environment:` ternary, token env ternary and the export step's `if:`), the Tier-B loader's `doppler-token-infra-privileged:` ternary, and the case labels in `scripts/cutover-inngest.sh`. The expected sets are **literals in the test**, not derived from the workflow (a derived expected set shrinks with the deleted payload and still passes).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `arm` to `inputs.op.options` | RED |
| 2 | Re-add `luks-cutover` to the `environment:` ternary only | RED |
| 3 | Re-add a `reflush)` case label to the script | RED |
| 4 | Make the token-ternary extraction return empty (rename the `DOPPLER_TOKEN_INNGEST_ARM:` env key) | RED (anti-vacuity: extraction found and non-empty) |
| 5 | Add `reflush` as the second op in the token ternary after a compliant `rollback` | RED |
| 6 | Add `backup` to the token ternary (credentialed-but-wrong) | RED |
| 7 | Add a new reviewer-gated op to `environment:` with no credential delivery | RED |
| 8 | Add `reflush` only to the export step's `if:` (extracted separately from the env ternary) | RED |
| 9 | Combined case label `arm\|rollback)` or quoted `"arm")` in the script | RED |
| 10 | A `contains(...)` form of the op test in a ternary naming a retired verb | RED |

The case-label check is a literal POSITIVE set of surviving labels (enumerate, registry-probe, doublefire-probe, rearm, capture, verify-wiped-volume, backup, inventory, execute, quiesce-web, verify, rollback, resume), extracted so combined and quoted spellings are split, in addition to the per-verb absence check. The derived check that every credentialed op is also reviewer-gated (environment set is a superset of the token set) is kept alongside the literals, so a credentialed op with no reviewer gate still fails. Assembly extraction takes BOTH the token env ternary line and the export step's `if:` line.

**Harness rows:** suite edit: replace the literal expected token-op set with the workflow-derived one and confirm mutation 5 then fails to turn RED in that variant (proving the literal form is the load-bearing one; not shipped, run once and recorded); must-PASS non-canonical: reorder the ternary's ops and rewrap its whitespace (set compare is order-insensitive, so it must stay GREEN).

**Anchor.** Same-diff weakening is possible (one commit can edit the workflow and the literals). Outside anchor: the CODEOWNERS pin on `.github/workflows/` (owner reviews the diff) and the existing `inngest-cutover` reviewer-gated environment. Recorded as consistency-plus-review, not integrity.

### Guard 3 - The CI flip credential cannot write

**Property.** The only CI-published credential into `soleur-inngest/prd` that this PR adds has `access = "read"`, is declared outside the token-drift map and inventory, is published under the secret name the preflight reads with `plaintext_value` equal to its own token's `.key`, and references the isolated project and config by-reference. (Presence of both addresses in the per-merge allow-list is enforced by the parity test's #5566 rule and is deliberately not re-asserted here.)

**Assembly.** `inngest-flip-read-token.tf` (two resources), `token-drift-read-tokens.tf` and `doppler-config-inventory.txt` (must not mention it), the `github_actions_secret` `plaintext_value` expression, the token's `project`/`config` expressions, the preflight's `env:` secret name, and (by reference, not re-asserted) the parity test's #5566 publish rule. Pins run on comment-stripped, whitespace-normalized `.tf` text.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change `access = "read"` to `"read/write"` | RED |
| 2 | Remove the token's `-target=` line | RED (by the parity test's #5566 rule; this suite does not duplicate it) |
| 3 | Rename the secret so the preflight's `env:` name no longer matches | RED |
| 4 | Make `doppler_service_token.inngest_flip_read` join the `for_each` in `token-drift-read-tokens.tf` (or add it to the inventory file) | RED |
| 5 | Make the static pin's `.tf` read return empty (path typo) | RED (non-vacuity) |
| 6 | Add a second resource in the file with `access = "read/write"` after the compliant first | RED |
| 7 | Set the published secret's `plaintext_value` to `doppler_service_token.inngest_arm_write.key` (the realistic swap: the secret named read-only would carry the read/write token) | RED |
| 8 | Change `project` or `config` to a string literal or another project's reference | RED |

**Harness rows:** suite edit: point the pin at a copy where `access` is split across lines or quoted differently (a permitted spelling) - must stay GREEN; and a copy with a trailing comment containing the text `read/write` - must stay GREEN (comment-stripped match).

**Anchor.** Value and pin share a diff. Independent check after the fact: Phase 7 reads the live token's access from `doppler configs tokens` (metadata). That is a one-time read, not a standing control; a standing control would be extending the replace gate's access pin (`tests/scripts/test-inngest-host-replace-gate.sh`, CTO's 2026-11-02 pattern) to this token, which only applies to plans that touch it and is noted as a possible follow-up, not built here.

## Scope Check

### Ask Mapping

<!-- lint-infra-ignore start: verbatim quotes of the brief's prohibitions (do-not-apply, do-not-revoke); they forbid infra steps, they prescribe none -->
| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Plan and implement the prerequisite retirement PR for doppler_service_token.inngest_arm_write (item 8), CI and code only, no production change." [brief] | Whole plan; Phases 0-7 | mapped |
| 2 | "mint a read-only service token for soleur-inngest/prd (terraform file only, no apply) and move the preflight read to it; make the preflight fail closed when empty" [brief, CTO ruling step 1] | Phase 2 (token), Phase 3 (preflight); Guards 1 and 3; `inngest-flip-read-token.tf` | mapped |
| 3 | "Retire arm/rollback/reflush/luks-cutover once the flip state is terminal (`done`); the plan's first step must READ the flip state from Doppler (read-only) and record it." [brief, step 2] | Phase 0 step 1 and the Phase 0 record; Phase 4 retires `arm`, `reflush`, `luks-cutover`; `rollback` retained by CTO amendment F1 | mapped (rollback descoped - justification: CTO ruling F1, `rollback` Half B is the only web-scheduler re-enable and Half A gates it against two live schedulers) |
| 4 | "Keep op=resume on the write token only if flip is not `done`, else retire it too." [brief, step 3] | Retained by CTO amendment F2 | mapped (descoped - justification: resume G1 accepts `done` only, so the premise of the conditional was inverted; recovery for every host replace depends on it) |
| 5 | "Update cutover-inngest-workflow.test.sh (arm-token wiring asserts ~lines 1821, 1846, 2088)." [brief, step 4] | Phase 5 step 1; Guard 2 | mapped |
| 6 | "Sequence/rebase against the open PR that adds read tokens for three more Doppler configs ... open PR #12100. Also note open PR #12064 ... sequence against it." [brief] | Phase 0 step 2; F6 | mapped |
| 7 | "If .claude/hooks/cla-signed-author-gate.test.sh T15 (#12120, open) blocks this PR's CI, fix it first as its own ~4-line one-file PR (test-local git identity)." [brief] | Phase 0 step 3 | mapped |
| 8 | "do NOT revoke, scope down or delete the arm-write token or remove inngest-arm-write-token.tf" [brief hard limit] | Phase 2 step 3 (comment-only edit); `## Operator Holds` | mapped |
| 9 | "do NOT remove the G2e pin ... do NOT dispatch apply_target=inngest-host-replace or any terraform apply; do NOT close #9927; do NOT sign A6 or decide the ciphertext copy." [brief hard limits] | No file touches the G2e pin; `Ref #9927` only; Phase 2 apply path; Operator Holds | mapped |
| 10 | "The plan's `## Operator Holds` section must list the arm-token revoke as a separate, undelegated, production-mutating step (Operator-reserved). No invented operator-go gates." [brief] | `## Operator Holds` | mapped |
| 11 | "Persist every decision as a row of the `| Item | Class | Ruling |` table in knowledge-base/project/specs/<branch>/decision-challenges.md" [brief] | `decision-challenges.md` (F1-F6 plus three rows) | mapped |
<!-- lint-infra-ignore end -->

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `inngest-flip-read-token.tf` and two `-target` lines | "mint a read-only service token for soleur-inngest/prd (terraform file only, no apply)" | asked |
| Preflight rewrite and its test suite | "make the preflight fail closed when empty" | asked |
| Delete `arm`/`reflush`/`luks-cutover` arms, options, ternaries | "Retire arm/rollback/reflush/luks-cutover once the flip state is terminal" | asked |
| Keep `rollback` and `resume` | asks 3-4 (CTO amendment) | inferred - justification: deleting them removes the only web-scheduler re-enable and the inherited-done recovery, a regression the CTO ruled against in F1/F2 |
| Dead-helper deletions in `cutover-inngest.sh` | asks 3 | inferred - justification: a helper with no caller after the arm deletion is dead code that tests would keep asserting; F5 rules delete-if-no-caller |
| Guard 2 absence assertion and literal op sets | ask 5 | inferred - justification: without it, the deleted verbs can silently return in one edit and the parity row stays green on a shrunken derived set |
| Guard 3 static pin | ask 2 | inferred - justification: "read-only" is only true while `access = "read"` holds, and nothing else pins it |
| Runbook, ADR-282 addendum, C4 edits | ask 1 ("CI and code only") | inferred - justification: `wg-architecture-decision-is-a-plan-deliverable` and the live-text rule P4; runbooks/ADR/C4 are the docs that name the retired verbs |
| `inngest-arm-write-token.tf` CONSUMERS comment | "do NOT revoke, scope down or delete the arm-write token or remove inngest-arm-write-token.tf" | asked (comment-only, no resource change) |
| Tracking issue for the replacement write credential, #9927 comment | ask 1 | inferred - justification: `wg-when-deferring-a-capability-create-a`; the CTO ruled it a deliverable (F1) |
| `workflow-file-size` net-shrink and rationale move to the runbook | ask 2 | inferred - justification: the workflow has 282 bytes of headroom against a required gate |

### Split Assessment

- Subsystems touched: 4 - `.github/workflows`, `scripts` + `tests/scripts`, `apps/web-platform/infra`, `plugins/soleur/test` (+ `knowledge-base`, docs only)
- Planned files: about 17 | Estimated changed lines: about 2,400 (mostly deletions; the test file prune dominates)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the retirement, the new read token and the preflight move must land together or the arm-token consumer story is inconsistent at every intermediate commit. The size is deletion-dominated and each deletion is covered by a guard. (Over the line threshold; considered a split into "token + preflight" and "retire three ops". Rejected: the first alone leaves the retired-op tests and runbooks in place, the second alone leaves the preflight on the wide token; both are small to review as deletions-plus-one-file.)

## Acceptance Criteria

### Functional

- [ ] AC1. Phase 0 record in the PR body: both flags `done` with UTC time, and the live token roster before/after.
- [ ] AC2. `inngest-flip-read-token.tf` defines `doppler_service_token.inngest_flip_read` (`access = "read"`, by-reference project/config, name `inngest-ci-flip-read`) and `github_actions_secret.doppler_token_inngest_flip_read` (`DOPPLER_TOKEN_INNGEST_FLIP_READ`); neither appears in `token-drift-read-tokens.tf` or `doppler-config-inventory.txt`. Pin: `inngest-flip-read-token.tf` + Guard 3.
- [ ] AC3. Both addresses are in the default per-merge `-target` list and in neither exclusion set; `bun test plugins/soleur/test/terraform-target-parity.test.ts` green. Pin: `apply-web-platform-infra.yml` allow-list step.
- [ ] AC4. The preflight step has no `continue-on-error`, reads only `secrets.DOPPLER_TOKEN_INNGEST_FLIP_READ`, and implements all six semantics rules; `grep -c DOPPLER_TOKEN_INNGEST_ARM .github/workflows/apply-web-platform-infra.yml` prints `0`. Pin: `apply-web-platform-infra.yml:` preflight step; Guard 1.
- [ ] AC5. `apps/web-platform/infra/inngest-host-replace-preflight.test.sh` prints `0 failed` and every Guard 1 and Guard 3 mutation row is RED on a mutated copy.
- [ ] AC6. `cutover-inngest.yml` offers neither `arm`, `reflush` nor `luks-cutover`; token ternary and export `if:` are exactly `rollback || resume`; the `environment:` ternary is exactly `rollback || resume || backup`; `scripts/cutover-inngest.sh` has no `arm)`, `reflush)`, `luks-cutover)` labels. Pin: `cutover-inngest.yml:` options and ternaries; `cutover-inngest.sh:` dispatcher; Guard 2.
- [ ] AC7. `rollback` and `resume` arms are byte-identical to `origin/main` except text pointing at `op=arm`; `git diff origin/main...HEAD -- scripts/cutover-inngest.sh` shows no other hunk inside them (the `op=arm` text hunks include those in `resume)`). Pin: diff review of both arms.
- [ ] AC8. No deleted helper has a remaining caller or test that sources it (`git grep -n '<name>' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'` returns nothing for each deleted name).
- [ ] AC9. `cutover-inngest-workflow.test.sh` has no assertion naming the three retired verbs except the Guard 2 absence block; `_EXACT_FLOOR` equals the recomputed assertion count; the non-vacuity asserts for emptied extractions are deleted, not left passing on empty files.
- [ ] AC10. `workflow-file-size.test.ts` green; `wc -c` of `apply-web-platform-infra.yml` at or below 489,718; the new pointer comment does not contain the old secret name (AC4's grep stays at 0).
- [ ] AC11. Runbooks, ADR-282 addendum and C4 edits done; the C4 validation tests, `c4-count-parity` and `lint-infra-no-human-steps.py --changed` pass; no existing ADR/post-mortem text edited (`git diff` shows additions only in ADR-282).
- [ ] AC12. `git diff origin/main...HEAD --stat` shows no change under `apps/web-platform/infra/ci-deploy*`, `deploy-inngest-bootstrap.sudoers`, `cloud-init.yml`, `inngest-cutover-flip.sh`, nor to `inngest-arm-write-token.tf` outside comments (`git diff` filtered to non-comment lines is empty), nor to the G2e pin region of `terraform-target-parity.test.ts`.
- [ ] AC13. The PR body uses `Ref #9927`, never `Closes`, and its first lines state: merging mutates production (the token and secret are minted by the push-triggered apply); the two departures from the brief and why; the new token buys nothing until the arm-token revoke.
- [ ] AC15. `git grep -nE 'op=(arm|reflush|luks-cutover)' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!knowledge-base/engineering/architecture/decisions' ':!knowledge-base/engineering/operations/post-mortems'` has every remaining hit classified in the PR body as historical record, or a host-side comment/marker in a sha256-compared config-bundle file (accepted residual: `inngest-cutover-flip.sh`, `inngest-server-flip-guard.sh`, `ci-deploy.sh` and siblings cannot change without a host replace). Property P4 therefore holds for CI, scripts and runbooks, and is explicitly NOT claimed for host-side text.

### Post-merge (agent-run, read-only; Phase 7)

- [ ] AC14. The merge-commit per-merge apply shows two creates and no other change; the repo secret and the `inngest-ci-flip-read` token (access `read`) exist.

## Domain Review

**Domains relevant:** engineering

### Engineering

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-11-05: six rulings F1-F6 (decision-challenges.md) plus the earlier same-day ruling in the brief. The CTO amended the brief on two points after reading the code (keep `rollback` and `resume`). No product, marketing, legal, finance, sales or support surface: no user-facing page or copy, no personal data processing change, no spend. No GDPR-gate trigger: no schema, auth flow, API route or `.sql`, and no LLM/external-API processing of operator-derived data.

## Test Scenarios

- Preflight (executable, stubbed `doppler`, temp `GITHUB_STEP_SUMMARY`): empty token -> exit 1 with the secret name in the message; names-list non-zero -> exit 1; names list without the key -> exit 0 and the "unset" warning; key present and `get` non-zero -> exit 1; `get` empty -> exit 0; `armed`/`flipping` -> exit 0 with the strand warning; `flushed` -> exit 0; `done` -> exit 0 plus summary with `op=resume` and the `accepts done only` clause; trailing whitespace/CRLF on the value; unknown value; `doppler` or `jq` absent from PATH (exit 1); names list invalid JSON with rc 0 (exit 1); stub-observed argv is `-p soleur-inngest -c prd` and the stub-observed `DOPPLER_TOKEN` equals the flip-read value.
- Absence/parity (static, literal expected sets): the Guard 2 matrix.
- Token pin (static): the Guard 3 matrix.
- Regression: the entire remaining `cutover-inngest-workflow.test.sh` (resume, rollback, backup, probes, doublefire, missed-tick) green at the new floor; `test-argv-bearer-sweep.sh`, `test-infra-privileged-tier-census.sh`, `test-inngest-host-replace-gate.sh` green; the C4 and parity suites green.
- Integration verification: none beyond Phase 7; a live exercise of the new token requires the owner-gated replace and is deliberately not run here.

## Risks and Sequencing

- **Merge-to-apply window.** Between merge and the per-merge apply, `secrets.DOPPLER_TOKEN_INNGEST_FLIP_READ` is empty; a host-replace dispatched in that window fails at the preflight naming the secret. Fail-closed is the safe direction and no replace is scheduled (it needs the owner's in-session go).
- **Recovery replace blocked by a Doppler outage.** The job is also the sole-scheduler recovery route. The step now fails on a blind read where it used to degrade open. CTO F3: acceptable, because the later "Extract backend credentials" and terraform steps need Doppler anyway.
- **A never-used credential gates a recovery route.** Fail-closed makes the sole-scheduler recovery replace depend on a credential that has not been exercised live and has no CI rotation path (#7263). If it is dead at that moment the dispatch fails at the preflight. Mitigation: the runbook gets a repair line (operator-local `-replace` of both targets per the `.tf` header recipe), and Phase 7 confirms the apply conclusion is `success` before anyone relies on it. A partial per-merge apply (token created, secret not) is idempotent on retry: re-run the failed push run; never `-replace` the token.
- **The arm token is NOT revocable after this PR.** `rollback` and `resume` still consume it. The PR body, the ADR-282 addendum and the tracking issue say so explicitly; the revoke precondition is in `## Operator Holds`.
- **Concurrent PRs.** F6: ship independently. If #12100 merges first, it edits `terraform-target-parity.test.ts` and the inventory: rebase and recompute `TEST_FLOOR`. If #12064 merges first, it edits the allow-list region and `cutover-inngest-workflow.test.sh` (+8/-8, a probe-schema rename): rebase, resolve, recompute `_EXACT_FLOOR`. Never hand-add to a count; the Phase 5 command is authoritative.
- **Large mechanical deletion.** Mitigation: Guard 2 absence block, per-helper `git grep`, AC7 byte-identity of the kept arms, and the whole-tree ratchets.

<!-- lint-infra-ignore start: this section states the operator-reserved hold the brief mandates; it prescribes no step to an agent and no step is executed by this PR -->
## Operator Holds

Nothing here is delegable and nothing here is discharged by this plan or this PR. No delegation exists on the epic. These are held acts, not gates this PR invents: this PR does not wait on any of them and does not perform any of them.

- **Revoke of `doppler_service_token.inngest_arm_write` (secret `DOPPLER_TOKEN_INNGEST_ARM`), and any scoping down or deletion of it, and removal of `inngest-arm-write-token.tf`.** Separate step, undelegated, production-mutating. Class: operator (production-mutating). Operator-reserved. **Currently blocked** (technical, not a gate): `op=rollback` and `op=resume` still consume the token (F1, F2). The recorded precondition for the revoke sequence is: the delivery `inngest-host-replace` plus `op=resume` first, then retire `resume` and `rollback` in the same owner-run sequence as the revoke, after a replacement write-credential design exists (tracking issue filed by this PR).
- **Authorizing `apply_target=inngest-host-replace`.** Operator-reserved, in-session per-command go, withheld from delegation (runbook `inngest-server.md`, host-replace row). This PR does not dispatch it. Class: operator (production-mutating).
- **Closing #9927.** Operator-reserved. Class: operator (scope).
- **Signing the A6 "no known access" record and deciding the off-project ciphertext copy.** Not touched here. Class: operator (third-party system) and operator (money), as recorded on #9927.
- **Removing the G2e pin.** Not before 2026-11-17 with the new Guard 1 leg green on main, or at the next host replace; not touched here.
<!-- lint-infra-ignore end -->

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or lacks the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern` with a challengeable sentence.
- `apply-web-platform-infra.yml` has 282 bytes of headroom; any prose added to the workflow without a matching removal turns `workflow-file-size.test.ts` red.
- `continue-on-error: true` forces the step `conclusion` to `success`; the removal is the load-bearing edit of the fail-closed change, not the `exit 1`.
- A set-equality guard whose expected set is read from the artifact under test passes after deleting the payload; Guard 2's expected sets are literals.
- `-target` selects dependencies, never dependents: any future rotation of the new token needs both `-target`s (token and secret).
- The research pass listed `confirm_flip_state`, `_flip_liveness_count` and the resume helpers as deletable under the superseded retire-five scope; they are kept. Re-derive deletable helpers with `git grep` at work time.
