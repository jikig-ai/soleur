---
title: "feat: offline local-state rehearsal of terraform import for random_password.inngest_redis_luks"
date: 2026-10-19
slug: inngest-redis-luks-import-rehearsal
branch: feat-one-shot-inngest-redis-luks-import-rehearsal
issue: 9927
type: feat
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Item 5 of the Inngest LUKS arc (#9927). ADR-282 records the loss mode "Terraform state entry lost" and
says "State-loss recovery remains UNVERIFIED"; the runbook row says the candidate recipe (`special = false`
edited into the imported state) "was NOT rehearsed". This PR replaces that sentence with a measured result.

The deliverable is a hermetic suite that, in a scratch directory with local state and a synthetic passphrase,
extracts the REAL `random_password` block for the Inngest Redis LUKS passphrase from
`apps/web-platform/infra/inngest-redis-luks.tf`, simulates state loss, imports the value, and proves what
the owner would actually see: the plan after a plain import is a replacement that `prevent_destroy` turns
into a hard error (the key survives), and the candidate state edit then yields "No changes" with the value
byte-identical. It also records, as measured fact, that the `import {}` block route in ADR-282 and the
runbook does NOT plan as a no-op (it plans the same replacement and prints the value). The result lands in a
dated ADR-282 addendum plus the two sentences it falsifies.

Nothing here mutates production, reads Doppler, Hetzner or R2, or touches web-1's LUKS volume 106443278.
The rehearsal volume is not deleted (that is #10112, which lands after this PR). Refs: #9927, #10112 (never
a closing keyword). Draft PR: 10524.

Ruled by CTO agent, 2026-10-19 (five binding rulings, recorded in `decision-challenges.md` and folded into
this plan): new sibling suite instead of editing the rehearsal root's `.tf` files; fixture extracted from the
real block; parent-root lock pin; offline-first provider with a CI-only registry fallback; verified-claim
boundary with the `import {}` correction written in this PR.

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (measured / grepped) | Plan response |
|---|---|---|
| "Edit the `inngest-provision-rehearsal` root (`rehearsal.tf` and `inngest-provision-rehearsal.test.sh`)" | The root is applied by a dispatch workflow against real R2 state, Hetzner and Doppler. `inngest-provision-rehearsal.test.sh` section 0 pins its file inventory to exactly `{main,variables,rehearsal}.tf` + lockfile; section 2 requires every `random/hcloud/doppler/tls` resource address to match `rehearsal(_x)?`; `terraform fmt -check -recursive` and `lint-encryption-posture.py` (`rglob("*.tf")`) both reach the directory. The suite is pure grep/awk and has never run terraform. | CTO R1: the proof lives in a NEW sibling suite `inngest-redis-luks-import-rehearsal.test.sh`; `rehearsal.tf` is NOT edited (no resource, no comment); `inngest-provision-rehearsal.test.sh` gains one additive pointer assertion. The operator's goal (a rehearsal that proves the recovery) is met; the literal `rehearsal.tf` edit is dropped with the reason recorded. |
| "candidate recipe: `special=false` after the import" | Reproduced offline (terraform 1.9.8, random 3.9.0/3.9.1, local state): import gives `special = true`; plan = replace (`special true -> false # forces replacement`) + `prevent_destroy` error rc=1; `state pull` -> `special=false`, serial+1 -> `state push` -> plan "No changes" rc=0, value sha256 unchanged. | Verified; the suite pins it. |
| ADR-282 line 141 and runbook line 446: an `import {}` block "plans as a no-op and passes the HALT" | FALSE for this resource. With `id = var.recovery_passphrase` (sensitive, `TF_VAR_` env) the plan is "1 to import, 1 to add, 0 to change, 1 to destroy" plus the same `prevent_destroy` error, and the plan text prints the passphrase twice (`Preparing import... [id=<value>]`, `(imported from "<value>")`) despite the sensitive variable. | The suite pins both facts; ADR-282 and the runbook row are corrected in this PR (CTO R4). |
| "Pass the passphrase via an environment variable, never argv" | `terraform import` takes the id positionally. `TF_CLI_ARGS_import="-input=false <addr> <value>"` works (flags must be inside the variable too, else "expects two arguments"); a PATH shim logging `"$@"` saw only `import`. Terraform echoes the id on stdout (`Importing from ID "<value>"...`). | Use the env route; all terraform output goes to files in a 0700 scratch dir that are never printed (CTO R5). |
| "it needs NO network" | `terraform init -backend=false -plugin-dir=<cache>` with the lock pin installs from the local plugin cache with `HTTPS_PROXY` pointed at a dead port. The CI job has no provider cache but has network. | CTO R3: offline-first; registry `init` only when `CI` is set. |
| Lock pin to use | Parent root `.terraform.lock.hcl:94` pins random 3.9.0; the rehearsal root's lock pins 3.9.1. The resource is applied by the PARENT root. | CTO R2: use the parent root's lock entry (3.9.0) only. |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: #9927 OPEN (item 5 is this work; the issue stays open for the
other items); #10112 OPEN (its item 2 deletes `hcloud_volume.rehearsal_inngest` and edits `rehearsal.tf`, the
plan-shape fixtures and two ledger rows: disjoint from this plan); PR 10405 OPEN (one hunk in
`inngest-provision-rehearsal.test.sh` at section 8, lines ~243-248, plus the rehearsal workflow); PR 10501
OPEN/WIP (touches `inngest-redis-luks.test.sh`, `apply-web-platform-infra.yml`, `infra-validation.yml:157`,
`inngest-host.test.sh`, `variables.tf`; not the rehearsal test or the new suite). Cited files confirmed on
`origin/main`: `inngest-redis-luks.tf:52` (resource, `length = 40`, `special = false`, `prevent_destroy`),
ADR-282 line 141 (loss-mode row) and line 186 (`unverified`), runbook `inngest-luks-cutover-6894.md:446`.
ADR corpus check (mechanism nouns `import`, `random_password`, `state`, `rehearsal`): ADR-006 (caveat of
2026-10-06, tracked on #9572, for the web-class passphrases), ADR-263 (web-class first-create vs state loss),
ADR-142 line 713 (history), and `apply-web-platform-infra-job-rationale.md:~405` (web-class "not a supported
route") all concern OTHER resources or are history; none rejects an offline import rehearsal. Stale: nothing.

**Property List (Phase 0.6b).**
P1. After state loss, importing the passphrase value and applying the documented repair leaves a plan with no
changes and the stored value byte-identical to the pre-loss value.
P2. Until that repair is applied, no plan or apply can replace the passphrase (a wrong move cannot mint a new key).
P3. The passphrase never appears on terraform's argv, in the suite's stdout/stderr, or in any file that
survives the run.
P4. The claim the ADR makes is tied to the evidence that backs it, and the evidence runs where CI runs.

**Cut List (Phase 0.6b).** (a) A `random_password.rehearsal_*` resource in `rehearsal.tf` -> buys no P1-P4
property the scratch fixture does not, and drags the real-R2/Hetzner/Doppler root into a local test (CTO R1
rejected C). (b) Editing `rehearsal.tf` with a comment -> no property; #10112 edits the same file (R1). (c) A
workflow step pre-staging the provider -> an edit to a workflow PR 10405 also edits; the registry fallback
under `CI` covers P4 (R3 rejected B). (d) A new ADR -> the decision is an extension of ADR-282; a dated
addendum is the repo convention (R4). (e) Running the rehearsal against R2-backed state -> production-adjacent,
out of scope; recorded as UNVERIFIED. (f) Generalizing to the web-class passphrases -> different resources,
tracked by ADR-006's existing caveat on #9572.

**Relevant institutional learnings** (read by the learnings pass; paths under `knowledge-base/project/learnings/`):
`2026-10-06-narrowing-a-guard-leaves-every-sentence-about-its-old-scope.md` (paraphrase sweep after the claim
changes), `test-failures/2026-07-17-a-drift-guard-scoped-by-resource-name-is-addition-blind.md` and
`2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md` (assert attributes inside the one
extracted block, with a decoy sibling), `test-failures/2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards.md`
(no `producer | grep -q` under pipefail), `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md`
(green-control row), `2026-09-03-my-guard-blocked-the-recovery-and-missed-the-hazard.md` (an "imported, not
edited" RED state; oracle from `terraform plan`, not the edit tool's exit code),
`2026-06-18-inngest-secrets-env-not-argv-and-detection-sentinel-swap.md` (`/proc/<pid>/cmdline` is world-readable,
`environ` is not), `2026-10-07-a-comment-that-reproduced-the-call-shape-became-phantom-data.md` (the suite's
comments must not reproduce the resource block literal: sibling extractors read the infra directory),
`2026-06-30-merge-queue-iac-provider-schema-probe-and-positional-rule-readers.md` (an empty dump is not a pass),
`2026-03-21-terraform-state-r2-migration.md` (`rm -rf .terraform` between inits; scratch dir only).

**Measurements (this planning session, 2026-10-19, scratch dir, synthetic value; terraform 1.9.8; random 3.9.0 via
`-plugin-dir=~/.terraform.d/plugin-cache`; init+apply take ~1.2 s):**

| Step | Result |
|---|---|
| mint -> `rm terraform.tfstate*` -> `TF_CLI_ARGS_import` import | rc 0; state: `id="none"`, `length=40`, `special=true`, `min_*=0` |
| plan (imported, not edited) | replace, `special true -> false # forces replacement`, `Error: Instance cannot be destroyed`, rc 1 |
| apply (imported, not edited) | rc 1; value sha256 unchanged |
| same config minus `prevent_destroy`, apply | rc 0; value CHANGED (new key minted) |
| `state pull` -> `special=false`, serial+1 -> `state push` -> plan | "No changes", rc 0; `result` unchanged |
| `import {}` block + `TF_VAR_` sensitive id, plan | 1 import / 1 add / 1 destroy + the `prevent_destroy` error; value printed twice in plan text; also printed by `terraform show` of the saved plan |
| `terraform import` CLI output | echoes `Importing from ID "<value>"`; capture to a file only |
| PATH shim logging `"$@"` around the env-route import | argv = `import` only |

**Mutation trap found while measuring:** a `sed` that deleted the `lifecycle` block produced malformed HCL
("Unclosed configuration block") and a harness reading its output would have scored a RED for the wrong reason.
Every mutated fixture must be proven well-formed (`terraform validate` rc 0) before it counts as a mutation.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Add a local-state rehearsal that proves `terraform import` of `random_password.inngest_redis_luks` recovers state after state loss" | Phase 2-3 (new suite, dynamic section) | mapped |
| 2 | "closing the claim ADR-282 still marks UNVERIFIED (ADR-282 line ~141; candidate recipe: `special=false` after the import)" | Phase 3 (recipe rows) + Phase 4 (ADR) | mapped |
| 3 | "Edit the `inngest-provision-rehearsal` root (apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf and apps/web-platform/infra/inngest-provision-rehearsal.test.sh)" | Phase 2 (pointer assertion in `inngest-provision-rehearsal.test.sh`); `rehearsal.tf` not edited | mapped (partial) - `rehearsal.tf` edit descoped by CTO ruling R1 (closed-inventory pin, real-R2 root, #10112 conflict); surfaced in the Session Summary |
| 4 | "Write the failing local-state import test first" | Phase 1 (RED milestones) | mapped |
| 5 | "it needs NO network, Doppler, Hetzner or production access" | Phase 2 (`env -i`, offline-first provider, dead-port proxy) | mapped |
| 6 | "Pass the passphrase via an environment variable, never argv or CI logs, and never print it" | Phase 2-3 (env route, argv shim, self-scan) | mapped |
| 7 | "Update the ADR-282 addendum with the verified result" | Phase 4 | mapped |
| 8 | "Use \"Ref #9927\" and \"Ref #10112\" only, never closing keywords; after any PR body edit assert closingIssuesReferences is []" | Phase 5 (ship notes) | mapped |
| 9 | "Land this before the rehearsal-volume deletion work in #10112 ... do NOT delete the rehearsal volume here" | Non-goals; no edit to `rehearsal.tf` | mapped |
| 10 | "never touch web-1's LUKS volume 106443278; no SSH; no host reboot or replace; run only targeted tests locally" | Hard constraints section | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| New suite `inngest-redis-luks-import-rehearsal.test.sh` | "Add a local-state rehearsal" | asked |
| Pointer assertion in `inngest-provision-rehearsal.test.sh` | "apps/web-platform/infra/inngest-provision-rehearsal.test.sh" | asked |
| Runbook row edit (`inngest-luks-cutover-6894.md:446`) | — | inferred - the row repeats the falsified `import {}` claim and "NOT rehearsed"; leaving it would contradict the ADR addendum (learning 2026-10-06) |
| `suite-shard-legs.tsv` + `suite-durations.tsv` rows for the new suite | — | inferred - the repo's registration mechanism (ADR-240/252) assigns a leg; the registration test requires the two label sets equal |
| One `grep -q` per document (ADR row and runbook row cite the suite) | — | inferred - a closed claim that does not name its evidence reopens silently |

### Split Assessment

- Subsystems touched: 3 - `apps/web-platform/infra/` (tests), `knowledge-base/engineering/architecture/decisions/` (ADR-282), `knowledge-base/engineering/operations/runbooks/`.
- Planned files: 6 | Estimated changed lines: ~420 (suite ~300, ADR ~35, runbook ~6, pointer ~5, tsv 1, plan artifacts excluded).
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Overview of the approach (Technical Approach)

### Architecture

One new bash suite, `apps/web-platform/infra/inngest-redis-luks-import-rehearsal.test.sh`, registered by
presence (ADR-252) and run by `run-registered-suites.sh` on a `deploy-script-tests` leg, where
`hashicorp/setup-terraform` pins `TERRAFORM_VERSION` (`infra-validation.yml:277`, 1.10.5).

Two sections:

1. **Static section (no terraform needed; always runs).** Source the repo's shared HCL lexer
   `tests/scripts/lib/hcl-effective-text.sh` (resolved from the repo root, as `inngest-luks-sole-copy.test.sh`
   does) and extract the block with `block_of inngest-redis-luks.tf random_password inngest_redis_luks` (brace
   depth, comments and heredocs handled; no second extractor to maintain). Fail on zero blocks. Assert, INSIDE
   that block only, `length = 40`, `special = false`, `prevent_destroy = true` (the premise the repair depends
   on; the decoy-sibling and `ignore_changes` pins already belong to `inngest-luks-sole-copy.test.sh` and are
   NOT duplicated). Assert the parent-root lock carries a `hashicorp/random` entry and `main.tf` requires
   `random` `~> 3.0`. One `grep -q` per document: the ADR-282 loss-mode row and the runbook row each name this
   suite's filename (the claim names its evidence).
2. **Dynamic section (needs terraform + provider; CI-fatal / local-skip).** Build the scratch root from the
   extracted block, the copied parent-root lock entry and a `required_providers` stanza; run terraform under
   `env -i` with only `PATH`, `HOME` (scratch), `TMPDIR`, `TF_IN_AUTOMATION`, `CHECKPOINT_DISABLE`, `TF_LOG=` and
   the `TF_*` it needs. Sequence: mint a synthetic value (local apply), record `sha256(result)[:12]`, delete
   the state files (loss), import via `TF_CLI_ARGS_import`, assert the replacement + hard error, assert apply
   fails and the digest is unchanged, apply the pull/edit/push repair, assert plan rc 0 ("No changes"), assert
   the digest equals the pre-loss digest. Negative control: the same
   fixture minus `prevent_destroy` mints a different digest on apply (proves `prevent_destroy` is the
   load-bearing backstop and that the digest oracle can move). Characterization row: the `import {}` block
   route plans a replacement and errors, and its plan text contains the value (positive control for the
   leak scan), then that file is deleted immediately.

Secret hygiene (CTO R5, with the review corrections): the synthetic value lives in a 0600 file and in
terraform state inside a 0700 scratch dir removed by a trap on `EXIT INT TERM`; terraform runs as
`env -i PATH=... HOME=... bash -c 'TF_CLI_ARGS_import="-input=false <addr> $(<valuefile)" exec "$TF_BIN" import'`
so the value is never an argument of `env(1)` or of terraform (a `env VAR=value cmd` form puts it on `env`'s
world-readable cmdline); terraform output goes to files that are never printed or `cat`ed; every emission of
the suite goes through ONE `say()`/`fail()` funnel that refuses to print a message containing the value (a
race-free pre-print check; an `exec > >(tee ...)` post-hoc scan can run before the tee flushes) and terraform's
files are scanned with `grep -F -f <patternfile>` (the value is never on grep's argv); the suite defines
`terraform()` as a failing stub and calls the real binary only by absolute path from `tf()`, so any stray
invocation fails loudly and an argv shim in `tf()` (logs `"$@"` to the scratch dir) proves the value never
reaches terraform's argv; `set -x` is asserted off; the state repair uses `jq` (already in the tool gate), and
any jq comparison reads the value through `env`/`--rawfile`, never `--arg`. The leak scanner's positive
control is a canary the suite writes itself through the same scan path (independent of terraform version);
the `import {}` plan's printing of the value is a CHARACTERIZATION that reports the observed version-scoped
fact (`note import_block_plan_prints_value=yes|no`) rather than gating, because it was measured only on 1.9.8.

Provider acquisition (CTO R3): prefer `terraform init -backend=false -input=false -lockfile=readonly
-plugin-dir=<dir>` where `<dir>` is `$SOLEUR_TF_PLUGIN_DIR`, `$TF_PLUGIN_CACHE_DIR` or
`~/.terraform.d/plugin-cache` AND `registry.terraform.io/hashicorp/random/<locked version>/<os>_<arch>`
exists there, with `HTTPS_PROXY=http://127.0.0.1:9` to prove no network. Otherwise a plain registry
`terraform init -lockfile=readonly` ONLY when `CI` is set (lock hashes protect the download). With neither
terraform nor the provider available: local = loud SKIP of the dynamic section with a counted
`SKIPPED <n> assertions` marker and exit 0 for that section (static assertions still ran); `CI` set = FATAL
exit 1. A CI terraform version other than the pin is FATAL; a local mismatch is a printed note. The scratch
`required_providers` constraint is read from the parent `main.tf` (not hardcoded); every terraform call gets
`-no-color` (`TF_CLI_ARGS`) so phrase anchors cannot be split by escape codes; the CI registry `init` is retried
once; a local `-plugin-dir` package whose `h1:` hash is absent from the lock for this platform is a distinct
local note (checksum mismatch), not a silent pass.

Mutation driver (the matrices below are tests, not prose): the suite exposes two seams, `SOLEUR_IMPORT_REHEARSAL_SRC_TF`
(alternate source for the resource block; default the real file) and `SOLEUR_TF_PLUGIN_DIR`, plus
`SOLEUR_IMPORT_REHEARSAL_NO_MUT=1` (set in the child, prevents recursion). An in-suite battery builds each
mutated `.tf` in the scratch dir (each proven well-formed with `terraform validate` first, so a RED is never an
HCL syntax error), re-invokes the suite through the seams as a child process, and asserts the expected
non-zero exit and the expected failing assertion NAME. Suite-source mutations (the harness rows) run on a copy
of the suite whose root-relative reads are redirected by the same seams. Cost: ~4 child runs of ~3-5 s each,
inside the 360 s per-suite bound.

### Implementation Phases

**Phase 1 - RED first (`cq-write-failing-tests-before`).** Commit the suite with the dynamic oracle written
against the INTENDED behavior before the repair step exists: the first RED milestone is "plan after import
reports no changes" (it reports a replacement, rc 1, proven by running it); the second is the doc-pin rows
(the ADR/runbook rows do not yet name the suite). Run locally: `bash apps/web-platform/infra/inngest-redis-luks-import-rehearsal.test.sh`.
Both fail for the stated reason; record the failing output excerpt (counts only, never the value) in the PR.

**Phase 2 - Static section, scaffolding, hygiene.** Header comment (property list, what the suite does NOT
claim); tool gate (`terraform`, `jq`); pinned-version read from `infra-validation.yml`; scratch dir
with trap; the `tf()` wrapper (`env -i`, per-dir `TF_DATA_DIR`, output to files); block extraction; anti-vacuity
floor (`MIN`) counted on non-skipped runs; the additive pointer assertion in
`inngest-provision-rehearsal.test.sh` (suite exists and is executable), placed beside the existing
cross-checks, far from PR 10405's section-8 hunk.

**Phase 3 - Dynamic section.** Provider acquisition; mint; loss; env-route import; replacement + hard-error
assertions (anchored on the plan text `forces replacement` and `Instance cannot be destroyed`, not on exit
code alone); imported-not-edited apply refusal; repair (`state pull` | `jq '.serial += 1 | (the random_password instance).attributes.special = false'` | `state push -`); "No changes"
with `-detailed-exitcode` rc 0; digest equality; negative control; `import {}` block
characterization; leak positive control then scan; argv-shim assertion. Mutation fixtures validated with
`terraform validate` before use.

**Phase 4 - Records (CTO R4).** (a) ADR-282: a dated addendum "2026-10-19 (#9927 item 5, import rehearsal)" that states the convention exception explicitly ("Appended; the only change above is the loss-mode row ...")
stating exactly what is VERIFIED (offline, local state, terraform version(s) run, random provider 3.9.0,
synthetic value, extracted block) and what stays UNVERIFIED (R2-backed state, the per-merge jq HALT's behavior
after the state edit, every other `random_password` including `workspaces_luks_web`, the Doppler-copy
relation, other terraform versions), plus the `import {}` correction; AND one in-place edit of the line-141 row
replacing only the false `import {}` parenthetical and the "State-loss recovery remains UNVERIFIED" sentence
with a pointer to the addendum and the suite. The row's `DEFERRED (#9927)` clause for the import rehearsal is
updated to done. (b) Runbook `inngest-luks-cutover-6894.md` row "Terraform state entry lost": same
correction, naming the owner-local env route (`TF_CLI_ARGS_import`, output to a file, never to CI) and the
pull/edit/push repair as the verified-on-local-state recipe, still owner-decided and never applied by an agent.
(c) Paraphrase sweep (`2026-10-06-narrowing-a-guard...` learning): re-run `grep -rn -i -E "import ?\{\}|plans as a no-op|candidate recipe|NOT rehearsed|state-loss recovery"` over `knowledge-base/engineering` and `apps/web-platform/infra`; read every hit; the known others (ADR-142 line 713 history, `inngest-arm-write-token.tf:47` a different resource, ADR-006/rationale web-class text) are left unchanged by design and listed in the PR.

**Phase 5 - Registration, local verification, ship notes.** `git add -N` the new suite first (the generator, `--list` and the orphan lint read tracked files). Add the `suite-shard-legs.tsv` row via
`python3 scripts/regenerate-shard-manifest.py --group infra --incremental --write` (the same `--write` emits
`suite-durations.tsv`; the registration test requires the two label sets to be equal, so both files are committed); run only targeted tests
locally: the new suite, `inngest-provision-rehearsal.test.sh`, `.github/scripts/test/test-infra-suite-registration.sh`,
`python3 scripts/lint-trap-tempfile-ownership.py` over the new suite (the trap/mktemp ownership rule) and
`bash scripts/lint-orphan-test-suites.sh` once the file is tracked (the suite really is registered). `terraform fmt -check`
is not applicable (no `.tf` changes). CI is the authority for leg results. PR body: `Ref #9927` and
`Ref #10112` only; after any body edit assert `gh pr view 10524 --json closingIssuesReferences` is `[]`. Commit
trailer and PR footer as given. Merge `main` with a merge commit, never rebase; no stash.

### Files to Edit

- `apps/web-platform/infra/inngest-provision-rehearsal.test.sh` - ONE additive assertion (suite exists, is executable, bash-syntax-clean) near the "Cross-checks on the sibling artifacts" block; no other line moves. Overlap: PR 10405 edits section 8 (~lines 243-248) of this file; the insertion point is ~25 lines away, so the hunks do not touch.
- `knowledge-base/engineering/architecture/decisions/ADR-282-sole-copy-luks-volume-protection-set.md` - new dated addendum; in-place edit of the loss-mode row (line ~141) limited to the `import {}` parenthetical, the UNVERIFIED sentence and the DEFERRED clause.
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` - the "Terraform state entry lost" row (line ~446) only.
- `apps/web-platform/infra/suite-shard-legs.tsv` and `apps/web-platform/infra/suite-durations.tsv` - one row each for the new suite (generated by `scripts/regenerate-shard-manifest.py --group infra --incremental --write`; the registration test requires equal label sets).

### Files to Create

- `apps/web-platform/infra/inngest-redis-luks-import-rehearsal.test.sh` (executable).
- `knowledge-base/project/specs/feat-one-shot-inngest-redis-luks-import-rehearsal/tasks.md` and `decision-challenges.md` (planning artifacts).

Not edited (verified present, deliberately untouched): `apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf`, `main.tf`, `variables.tf` (closed inventory; #10112 owns the next edit), `inngest-redis-luks.tf`, `.github/workflows/*` (PR 10405 / 10501 overlap), `inngest-redis-luks.test.sh` (PR 10501 overlap).

## Open Code-Review Overlap

None. Checked all five planned/touched paths (`inngest-provision-rehearsal.test.sh`, `rehearsal.tf`, `inngest-redis-luks.tf`, ADR-282, the runbook) against open `code-review` issues: zero matches.

## Domain Review

**Domains relevant:** Engineering, Product (advisory only; no UI surface)

### Product (CPO)

**Status:** reviewed
**Assessment:** CPO sign-off 2026-10-19: approved with conditions - (1) threshold re-declared `single-user incident` with `requires_cpo_signoff: true` and the user-impact reviewer at review (done in this plan); (2) the VERIFIED wording is scoped to local state and the exact terraform versions CI ran, and the planning-time 1.9.8 measurements do not count as CI evidence until the pinned-version leg is green; (3) the runbook row warns that `terraform import` and an `import {}` plan echo the real passphrase (output to a file, never CI, scrollback or a ticket) and states the recipe has not been run against R2-backed state; (4) the CI-green-at-1.10.5 ready-gate stays; (5) `Ref` only, no closing keyword, #9927 stays open for its other items. Risk table: wrong recovery claim = high (outage prolonged or passphrase printed), test leak = low (synthetic value), scope = right. Conditions 2-3 are acceptance criteria below.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Five binding rulings (R1-R5) obtained 2026-10-19 via `soleur:engineering:cto`; recorded in
`decision-challenges.md`. Product, Marketing, Legal, Finance, Operations, Sales and Support are not relevant:
no user-facing surface, no personal-data processing activity (a synthetic value only), no spend, no new
vendor. No Product/UX Gate (no UI-surface path in the Files lists).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly (a test and records); a falsely "verified" recovery claim would mislead the repository owner during a state-loss incident and prolong an Inngest scheduler outage that delays or drops every user's armed reminders.
- **If this leaks, the user's data is exposed via:** no real credential is touched; the only secret in play is a synthetic passphrase minted inside the test. The exposure vector this plan defends against is a future edit that prints a REAL recovered passphrase through the same recipe: terraform echoes the import id on stdout and an `import {}` plan prints it, so the documented recipe sends output to a file and never to CI.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** adopted from the governing ADR (ADR-282 frontmatter `brand_survival_threshold: single-user incident`): this PR rewrites that ADR's sole-copy recovery claim, so it carries the ADR's tier rather than a lower one. Consequences: `requires_cpo_signoff: true` (advisory obtained at plan time, recorded in `## Domain Review`) and `soleur:engineering:review:user-impact-reviewer` at review time. The test itself touches no real credential.

## Infrastructure (IaC)

**Not applicable - no infrastructure is introduced.** No server, volume, secret, vendor account or workflow
is created or changed; no `.tf` file is edited. `terraform import` appears only inside a hermetic local
rehearsal against a scratch directory and local state. The recovery recipe the ADR documents stays an
owner-decided state repair that no agent applies (existing posture, unchanged).

### Terraform changes

None. The parent root's `random` pin (`~> 3.0`, lock 3.9.0) is read, not changed.

### Apply path

None (no apply of any root; the only `terraform apply` runs against local state in a temp dir).

### Host fan-out

None (no `terraform_data` SSH provisioner touched).

### Distinctness / drift safeguards

The suite extracts the live block, so a later change to `length`, `special` or `prevent_destroy` reddens it
(forcing a re-review of the recovery claim). State storage note: the scratch state holds a synthetic value in
plaintext inside a 0700 directory removed by trap.

### Vendor-tier reality check

None (no vendor resource).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-282 (not a new ordinal): dated addendum + the in-place row correction listed in Phase 4. No ADR
ordinal is claimed, so no ordinal collision is possible. No reversal of the Decision: the pin set, the
create-halt and the key-loss posture stand; only a recovery claim changes from UNVERIFIED to
"verified on local state, scoped".

### C4 views

No C4 impact. All three model files were read for this conclusion (`spec.c4` in full, `views.c4` in full,
`model.c4` at `inngestRedis` lines 337-341 and the actor/system block lines 395-412 plus a keyword sweep for
terraform/state/R2/doppler/luks/inngest). Enumerated and found already modeled or unaffected: (a) external
human actor: only the founder/owner, already `founder`; (b) external systems: Doppler (`doppler`) and
Cloudflare R2 (`cloudflare`) are NOT touched by the test; the provider registry fetch under `CI` is a
build-time tool fetch of the same kind `setup-terraform` already performs and is not modeled for any existing
CI job; (c) containers/data stores: `inngestRedis` description already states the key's two copies and
carries no state-loss recovery claim (grep for `import`, `unverified`, `state-loss`: no hit); (d) actor-surface
access relationships: unchanged. `plugins/soleur/test/c4-count-parity.test.sh`: run, ALL TESTS PASSED
(derived cardinalities unchanged).

### Sequencing

Authored now; nothing is deferred to a follow-up issue.

## Observability

```yaml
liveness_signal:
  what: deploy-script-tests leg result line "PASS apps/web-platform/infra/inngest-redis-luks-import-rehearsal.test.sh" (RED line on failure) from run-registered-suites.sh
  cadence: per CI run touching apps/web-platform/infra/ (every PR and every main push through the leg that owns the suite)
  alert_target: required-check surface of the PR; main-health-monitor files an issue on a red main run
  configured_in: .github/workflows/infra-validation.yml (deploy-script-tests job) via run-registered-suites.sh glob registration; apps/web-platform/infra/suite-shard-legs.tsv
error_reporting:
  destination: CI job log of the owning leg, per-suite log dir retained on RED by run-registered-suites.sh (no Sentry: a test has no runtime)
  fail_loud: "RED <path>" line plus ::error annotation; the suite prints "[FATAL]" lines for a missing tool or version mismatch under CI and never prints the synthetic value
failure_modes:
  - mode: terraform or the random provider absent on a CI leg
    detection: "[FATAL] ... CI is set: refusing to skip silently" and exit 1
    alert_route: RED line on the leg; main-health-monitor on main
  - mode: the dynamic section skipped locally (no provider cache)
    detection: counted "SKIPPED <n> assertions" marker in the suite output
    alert_route: visible in local output; CI never skips (FATAL instead)
  - mode: production block drifts (length, special, prevent_destroy changed)
    detection: static-section assertions inside the extracted block go RED
    alert_route: RED line on the leg of the PR that changes inngest-redis-luks.tf
  - mode: a change prints or argv-leaks the synthetic value
    detection: self-scan of the suite's own output and the argv-shim assertion go RED
    alert_route: RED line on the leg
logs:
  where: GitHub Actions job log of the deploy-script-tests leg that owns the suite
  retention: GitHub Actions default log retention
discoverability_test:
  command: bash apps/web-platform/infra/run-registered-suites.sh --list
  expected_output: inngest-redis-luks-import-rehearsal.test.sh
```

## Encryption Posture

Not applicable - the plan introduces no persistent data store and no cross-component connection (a hermetic
local test plus documentation; no `.tf`, `supabase/migrations/*.sql`, `cloud-init*.yaml` or
`docker-compose*.yaml` path in the Files lists). The subject store (`hcloud_volume.inngest_redis_luks`) and its
posture are unchanged and already recorded in the encryption-posture ledger.

## Guard Contract

### Guard 1 - Import-rehearsal oracle (the suite's dispatch and verdicts)

**Property.** The suite goes RED unless, after state loss and an env-route import of the extracted production
block, the unrepaired state cannot replace the key AND the documented repair yields no changes with the value
digest identical to the pre-loss digest.

**Assembly.** Quantifies over: the extraction of the block from `inngest-redis-luks.tf` (the chokepoint every
fixture flows through, including every mutated fixture); the three terraform verdicts (plan after import,
apply after import, plan after repair); the digest comparisons (pre-loss, after refused apply, after repair,
and the negative-control mint); the dispatch gate (the dynamic section executed vs skipped, and the count
floor). Extraction goes through the shared lexer's `block_of` (decoy-sibling and `ignore_changes` coverage of
that block stays with `inngest-luks-sole-copy.test.sh`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Source fixture drops `prevent_destroy` from the real block (validated well-formed first) | RED (static assertion and the imported-not-edited apply mints a new digest) |
| 2 | Dispatch: dynamic section reports "0 checked" (provider acquisition forced to a no-op under `CI=1`) | RED (FATAL under CI; the floor counts only non-skipped runs) |
| 3 | Real block `special = true` (premise drift: the repair would be unnecessary) | RED (the suite pins the replacement premise and demands a re-review) |
| 4 | Reorder: skip the repair, assert "No changes" straight after import | RED (the imported-not-edited state is a first-class RED row) |
| 5 | Repair edits `special` but not the serial (push without serial+1) | RED (the push is refused; the row asserts the post-push plan, not the edit's exit code) |

**Harness rows.** (H1, edit to the SUITE) a suite copy with the argv shim removed from `PATH` -> RED (the shim
row asserts the log exists and is non-empty, so a missing shim cannot pass by recording nothing); the
negative-control row (row 1) also covers a vacuous digest oracle. (H2, must-PASS non-canonical) the same real block with attributes reordered (`lifecycle` first, `special`
before `length`), extra whole-line comments and different indentation -> GREEN: the guard does not depend on the
canonical text.

**Anchor.** The oracle compares digests it computes itself in the same run (pre-loss vs post-repair), so a
one-diff edit cannot move both sides: the pre-loss value is minted at run time. What a single diff CAN weaken
is the suite itself; the outside anchors are the CI leg (required to be green on the PR) and the doc-pin rows
that make the ADR/runbook rows name this suite.

### Guard 2 - Secret hygiene (argv, output, residue)

**Property.** The synthetic passphrase appears nowhere on terraform's argv, in the suite's stdout/stderr, or in
any file that outlives the run.

**Assembly.** Every terraform invocation flows through the single `tf()` wrapper and the argv shim; every
output file flows through the scratch dir; every message goes through `pass()`/`fail()`/`printf` of the suite
itself (captured for the self-scan). Members: the import call, the `import {}` characterization plan (which
prints the value on terraform 1.9.8; reported, not gated), the repair's `jq` process (value never on
argv), the trap cleanup (covered by `lint-trap-tempfile-ownership.py`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | A `fail()` message echoes the capture file or the variable | RED (the `say()`/`fail()` funnel refuses to print it and records the violation) |
| 2 | The import call passes the value positionally instead of via `TF_CLI_ARGS_import` | RED (argv-shim log contains the value) |
| 3 | The scanner's canary (a value the suite itself writes into a scanned file) is not produced | RED (a scan that cannot find a known canary is vacuous, so the scan row fails) |
| 4 | `set -x` enabled at the top of the suite | RED (the suite asserts xtrace is off before minting) |

**Harness rows.** (H1) a copy of the suite that prints the value after the scan -> the scan wrapper is outside
the printing code, so the copy must still go RED. (H2, must-PASS) the unmodified suite with a stray `terraform`
mention in a comment and a differently shaped scratch path (spaces-free, different length) -> GREEN: the
argv-shim and stub checks key on invocations, not on text.

**Anchor.** The scan is validated by a canary written through the same file path terraform's output takes; the
`import {}` plan text (a terraform-produced leak) is reported as an observation on the running version, so a
version that redacts it cannot turn the suite red for the wrong reason.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `bash apps/web-platform/infra/inngest-redis-luks-import-rehearsal.test.sh` exits 0 locally with the dynamic section run (provider from the local cache) and prints a pass/fail count line; with the provider cache hidden and `CI` unset it exits 0 printing the counted `SKIPPED` marker; with `CI=1` and no provider reachable it exits 1.
- [ ] The failing run (Phase 1) was observed before the repair and doc-pin code existed, and the PR records the failing assertion names only.
- [ ] The static section extracts the block with the shared lexer's `block_of` (zero blocks = failure) and asserts `length = 40`, `special = false`, `prevent_destroy = true` INSIDE it.
- [ ] The dynamic section asserts, by terraform's own verdicts: replace + `Instance cannot be destroyed` rc 1 after import; apply refused with digest unchanged; plan rc 0 after the pull/edit/push repair; digest equal to the pre-loss digest; negative control (no `prevent_destroy`) changes the digest; `import {}` route plans replace + error and its plan text contains the value.
- [ ] Argv shim log exists, is non-empty, never contains the value; the suite's captured stdout/stderr never contains the value; the scratch dir is gone after the run.
- [ ] `inngest-provision-rehearsal.test.sh` gains only the pointer assertion; `git diff --stat origin/main -- apps/web-platform/infra/inngest-provision-rehearsal/ .github/workflows/` is empty.
- [ ] Anchored on the row start `| Terraform state entry lost |` (content anchor, never a line number), in both the ADR-282 loss-mode table and the runbook table: the row names `inngest-redis-luks-import-rehearsal.test.sh`, and none of `State-loss recovery (is|remains) UNVERIFIED`, `CANDIDATE recipe`, `NOT rehearsed`, `passes the HALT` appears inside it (the runbook says "is UNVERIFIED", the ADR "remains UNVERIFIED": both alternatives are checked).
- [ ] ADR-282 addendum states the VERIFIED and UNVERIFIED lists exactly as ruled (R4), UNVERIFIED first, scoped "local state only" with the terraform versions the suite actually ran (1.10.5 on the CI leg; 1.9.8 locally) - the wording is finalized AFTER the first green CI leg is read, and the `note import_block_plan_prints_value=` observation from that log is quoted as the version-scoped fact; ADR frontmatter `status: accepted` unchanged.
- [ ] The runbook row warns that `terraform import` and an `import {}` plan echo the real passphrase (output to a file, never CI, scrollback or a ticket), names the shell-prefix-assignment form (never `env VAR=value terraform`, which puts the value on `env`'s cmdline), and states the recipe has not been run against R2-backed state.
- [ ] `scripts/test-affected-kb-consumers.test.sh` (the KB consumer ratchet mapped to ADR-282 and the runbook by `scripts/lib/test-affected-paths.sh`) is run once locally after the doc edits; paraphrase sweep run and every hit read; the left-unchanged hits are listed in the PR body.
- [ ] `suite-shard-legs.tsv` and `suite-durations.tsv` each have a row for the new suite; `.github/scripts/test/test-infra-suite-registration.sh` passes; `bash scripts/lint-orphan-test-suites.sh` does not list the new suite; `python3 scripts/lint-trap-tempfile-ownership.py` reports no new finding for it.
- [ ] PR body contains `Ref #9927` and `Ref #10112` and no closing keyword; `gh pr view 10524 --json closingIssuesReferences --jq '.closingIssuesReferences | length'` prints `0` after every body edit.
- [ ] The `deploy-script-tests` leg that owns the suite is green on CI at the pinned terraform 1.10.5 BEFORE the PR is marked ready (the only unrelated red allowed is the push-arm "Tenant integration (dev-Supabase)" on `test/server/action-sends-worm.test.ts`, which is not touched).

### Post-merge

- [ ] None required. The suite is registered by presence; no deploy, apply or dispatch follows.

## Test Scenarios

- Given a scratch root built from the real block and a minted synthetic value, when state is deleted and the value is imported via `TF_CLI_ARGS_import`, then the plan is a replacement that errors on `prevent_destroy` and the apply is refused with the digest unchanged (integration).
- Given the imported-not-edited state, when `state pull` -> `special=false` + serial+1 -> `state push` runs, then `terraform plan -detailed-exitcode` exits 0 and the digest equals the pre-loss digest (integration).
- Given the same fixture without `prevent_destroy`, when apply runs on the imported state, then a different digest results (negative control; integration).
- Given an `import {}` block with a sensitive variable id, when plan runs, then it plans 1 import / 1 add / 1 destroy, errors, and its plan text contains the value (characterization; integration).
- Given `CI=1` and no terraform or no reachable provider, when the suite starts, then it exits 1 with a FATAL line (unit). Given no `CI` and no provider cache, then the dynamic section is skipped with a counted marker and the static section still runs (unit).
- Given the suite's own output, when scanned for the synthetic value, then zero matches; given a deliberately leaking mutation, then RED (unit).

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Resource `random_password.rehearsal_*` in `rehearsal.tf` | Rejected (CTO R1): breaks the closed-inventory and `.rehearsal` contracts, enters `lint-encryption-posture.py` scope, applied against real R2. |
| Hand-written copy of the block | Rejected (CTO R2): drifts from production. |
| Pre-stage the provider in a workflow step | Rejected (CTO R3): edits a workflow PR 10405 also edits; the lock hashes already protect the CI registry fetch. |
| `terraform test` with mock provider | Rejected: an `import` under mock providers errors; the real provider is the point (learning 2026-09-27). |
| Run against R2-backed state | Out of scope and production-adjacent; stays UNVERIFIED. |

## Non-Goals

- No edit to `rehearsal.tf`, `main.tf`, `variables.tf`; no deletion of `hcloud_volume.rehearsal_inngest` (#10112 lands after this).
- No change to the per-merge jq create-halt, to `prevent_destroy`, or to the key-loss posture; no automated repair dispatch (#9927 item 3).
- No generalization to `random_password.workspaces_luks_web` or other passphrases (ADR-006's caveat stays tracked on #9572).
- No real passphrase is ever read, imported or printed; no Doppler, Hetzner or R2 call.

## Risks and Sharp Edges

- A terraform version change can alter import defaults or plan wording; the suite pins the CI version (FATAL on mismatch under `CI`) and anchors on stable plan phrases (`forces replacement`, `Instance cannot be destroyed`) plus rc and digests, not on full text.
- `TF_CLI_ARGS_import` requires the flags inside the variable; a refactor that moves `-input=false` out re-breaks the import ("expects two arguments"). A row covers it.
- GitHub masks only registered secrets, so a synthetic value would show in logs if ever echoed; the self-scan is the control.
- The local plugin cache path is a convenience; CI never has it, so the registry path must stay exercised on CI (the leg that owns the suite is the proof, hence the ready-gate AC).
- **Model limits, stated (a scratch fixture is a MODEL of the production resource and is blind to every input it stubs):** the backend (local state, not the R2 backend), the provider set (only `random`; production plans also carry `doppler`, `hcloud`), sibling resources and dependency edges in the same plan (`doppler_secret.inngest_redis_luks_key`), the per-merge `-target` set and its jq create-halt, the terraform version (CI pins 1.10.5; the planning measurements ran on 1.9.8), and the random provider version in the rehearsal root (3.9.1) versus the parent root (3.9.0). Each is listed as UNVERIFIED in the ADR addendum; none is compared by the suite except the provider pin (lock entry) and the terraform version (FATAL under CI).
- Do not copy the resource block literal into the suite's comments or a fixture heredoc checked into the infra directory: sibling extractors read that directory (learning 2026-10-07).
- A plan whose `## User-Brand Impact` section is empty, is empty of content, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `single-user incident` (the governing ADR's tier) with a challengeable decision.
- Overlap, stated: PR 10405 (`inngest-provision-rehearsal.test.sh` section 8, rehearsal workflow) - insertion point is far from its hunk; PR 10501 (`inngest-redis-luks.test.sh`, apply workflow, `infra-validation.yml:157`) - disjoint files; #10112 (`rehearsal.tf`, plan-shape fixtures, ledger rows) - disjoint because `rehearsal.tf` is untouched here. The other PRs are not edited or commented on.
- Hard constraints carried to the work phase: never touch volume 106443278; no SSH; no reboot or replace; targeted local runs only; merge `main` with a merge commit, never rebase; no `git stash`.
