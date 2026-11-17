# Learning: a "measured" correction was built on a probe that had never produced a positive

## Problem

PR #12307 (issue #12196) mints a read-only bearer token with Terraform (two `random_password`, two masked `doppler_secret`) and the merge is the production apply. Eleven review seats found no P1. Three of them wrote the same sentence into their reports: Doppler's `prd_terraform` branch config inherits `prd`, so a Tier-A Doppler token can read the value without reading Terraform state. The coverage consult then pointed at three repo comments saying the opposite ("`prd_terraform` does NOT inherit a post-branch Terraform-written prd key, measured 2026-10-19").

I settled it by measuring, and measured wrong, twice in a row:

1. `doppler configs --json` showed `prd_terraform` with `inherits=[]` and `prd` with `inheritable=False`. I read that as "inherits nothing", rewrote the `.tf` header, ADR-319 and ADR-320 to say so, wrote "measured 2026-11-07" into the header, committed and pushed.
2. The supporting probe was a names-only listing grepped with an exact-line match against a table with box-drawing borders. It returned `0` for every key in both configs, including `prd` itself. I read "0 in both" as agreement and did not notice that a probe that finds nothing in the config where the key certainly lives is broken.

The `inherits` field describes explicit config inheritance. A branch config sees its environment's root through a different mechanism, so the field answered a different question. A valid probe (unanchored match, positive control) listed `EGRESS_AUDIT_INGEST_TOKEN`, `LIVE_VERIFY_USER_PASSWORD` and `INNGEST_MANUAL_TRIGGER_SECRET` in both `prd` and `prd_terraform` (154 names in `prd`, 188 in `prd_terraform`). The original claim was right. The repo's own dated comments disagree with today's read, and I did not resolve that disagreement; I reported it.

## Solution

- Re-measured with a positive control: pick keys that must be present, show the probe finds them in the config where they live, then ask about the other config.
- Restored the inheritance statement with the exact evidence next to it (a named Terraform-written key, a names-only read, the date) instead of a bare "measured".
- Kept the guard fixes the same review produced: the new test layer (`cross-layer-limits.test.ts`) fails closed on any attribute or nested block the minting resources do not need, pins the length boundary at 47/48/256/257, ties the token name to the route, the named-bearer type and the hold gate, and fails if the route gains an export other than `GET` (the ADR-320 "leaves Terraform if it gains write reach" tripwire). A 22-row mutation battery on the guard is all killed.

## Key Insight

- A probe is not evidence until it has returned a positive. "Zero hits" from a probe that has never found anything is the instrument answering, not the system. The positive control is one extra line (a key that certainly exists), and it would have caught this in seconds. This is the same rule the review skill already states for tests and greps; it applies equally to the operator's own CLI checks used to settle a disagreement.
- A field name is not the question. `inherits` answered "is this config explicitly inheriting another config", not "can a reader of this config see that key". Before reading a field as the answer, state the question in a sentence and check the field answers that sentence.
- Do not write "measured <date>" into a committed artifact unless the command and its result sit next to the claim. A bare "measured" is a trust token that the next reader will not re-check, and it made a wrong correction look authoritative.
- When review seats and the repo disagree, the disagreement is a finding in its own right. Report it with both sides; do not decide it by picking the louder source.
- A guard for a four-resource file does not need to prove the whole property. Make it fail closed on anything the resources do not need (attribute allowlist), pin the boundary values, and state its residual (modules, subdirectories, other writers) in the header so nobody reads it as integrity.

## Session Errors

1. **An unbounded repo-wide `grep -r` hung past the 120 s tool limit and was moved to the background** — Recovery: scoped the search to the plan and spec. **Prevention:** scope searches by path list or `git grep` with a pathspec; `hr-never-run-commands-with-unbounded-output` already covers it, so no new rule.
2. **A short SHA typed from memory into the `Review-Evidence` PR comment was wrong (`40e4f0d` vs the real `7c349ab701`)** — Recovery: corrected with `gh pr comment --edit-last`. **Prevention:** derive every placeholder in an evidence comment with a command in the same call that posts it (`git rev-parse --short HEAD`); the review reference now says so.
3. **A correction built on an unvalidated probe (`inherits=[]` plus an exact-match grep that returned 0 for `prd` itself) was committed and pushed as "measured"** — Recovery: re-measured with a positive control and restored the original statement. **Prevention:** run a known-positive through any probe before writing its negative into a document, and put the command beside any "measured" claim.
4. **Working directory drifted three times (`cd ..` inside compound commands) so a lint ran from `apps/` and failed with rc 2** — Recovery: re-ran from the worktree root. **Prevention:** run each repo-script command from the worktree root with no `cd ..` chain; the review skill already warns about `cd ..` in a worktree.
5. **`tsc` TS2556 on spreading a tuple constant into a helper followed by another argument** — Recovery: the helper now takes the tuple as one parameter. **Prevention:** none needed (one-off; `tsc` caught it before CI).
6. **Mutation patterns written against `length = 48` did not land after `terraform fmt` aligned the column to `length  = 48`** — Recovery: the helper's "mutation did not land" assertion caught it; patterns now use `\s*`. **Prevention:** build mutations from the parsed value or tolerant patterns; the landing guard was the control that worked.
7. **A mutant became equivalent after a simplification** (removing the `ignore_changes` text scan left the `raw` field unread, so "raw bleeds to EOF" survived) — Recovery: deleted the dead field and re-pointed the row at the body slice, which is killed. **Prevention:** rerun the battery after every simplification; a survivor is either a fixture gap or an equivalent mutant, and the second means dead code.

## Tags

category: workflow-issues
module: legal-acceptance verify token, terraform apply gates, review panel
