---
title: "fix: zot pull token off terraform's argv in the inngest rehearsal workflow (argv-bearer follow-up, item 2 of #9757)"
type: fix
date: 2026-10-20
slug: zot-pull-token-off-terraform-argv
branch: feat-one-shot-9757-zot-pull-token-tf-var-env
issue: 9757
priority: p3-low
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: cross-domain
---

# fix: zot pull token off terraform's argv in the inngest rehearsal workflow

Spec lacks valid lane: no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (fail-closed). `issue: 9757` is a reference only: #9757 is a tracking umbrella that stays open, there is no `closes:` key, and the PR body says `Ref #9757`, never a closing keyword.

## Overview

The inngest provision rehearsal workflow (`.github/workflows/inngest-provision-rehearsal.yml`) hands the zot pull token to terraform as a `-var "zot_pull_token=${ZOT_PULL}"` option on four terraform invocations. Each of those commands runs under `doppler run ... --`, so the token sits in the argument list of both the `doppler` and the `terraform` processes for the life of the command. Each step reads the token from Doppler and masks it first, but `::add-mask::` hides log text and does nothing for `/proc/<pid>/cmdline`. This is the same exposure class the argv-bearer sweep (#9597, ADR-280) closed for curl bearers, `htpasswd` passwords and registry-login passwords; it is the last unchecked "token on argv" lead on the #9757 umbrella.

Two deliverables, in the same change so the gate arrives green:

1. **Remedy.** In each of the four steps, export `TF_VAR_zot_pull_token` from the already-read, already-masked `ZOT_PULL` and delete the `-var "zot_pull_token=..."` line. A shell `export` is a builtin and puts nothing on any argv; terraform reads `TF_VAR_<name>` natively and `doppler run --preserve-env` leaves an existing environment value in place (ADR-241, measured).
2. **Guard.** A new stage **S9** appended to `tests/scripts/test-argv-bearer-sweep.sh` (immediately before the `# VERDICT` block): a derived static scan that no tracked non-test file carries a credential-named variable on a `-var` option; a static pin that each of the four converted steps exports `TF_VAR_zot_pull_token` before its `doppler run`; and executed rows that run the two converted `terraform destroy` step bodies (the arms whose failure leaks a paid host) under PATH stubs. S9 also forces one doc line (`plugins/soleur/skills/deploy/references/hetzner-setup.md`, which teaches `-var="hcloud_token=<your-token>"`) to the env form.

Plan-review panel outcome (DHH + simplicity + Kieran, then a CTO re-ruling on the findings that touched earlier rulings): the stage was shrunk from about 580 to a target of about 300 lines. Executed rows narrowed from four steps to the two destroy steps; the value-side taint arm, the mask-order assertions, the per-site mutation multiplication, the file floor and most fabricated per-clause controls were cut. The verb-free regex and the plugin-markdown corpus (with the doc fix) were kept by CTO ruling.

## Research Reconciliation — Spec vs. Codebase

| Brief / umbrella claim | Reality (measured on `origin/main` 91594324ef, 2026-10-20) | Plan response |
|---|---|---|
| The four sites are at lines 224, 250, 376, 646 of the rehearsal workflow | Confirmed exactly: teardown-only step (224), plan phase A (250), plan phase B (376), the teardown job's destroy (646). Each is preceded by `ZOT_PULL="$(DOPPLER_TOKEN="$DOPPLER_TOKEN_PRD" doppler secrets get ZOT_PULL_TOKEN -p soleur -c prd --plain)"` and `printf '::add-mask::%s\n' "$ZOT_PULL"`. No other `terraform apply` in the file carries a `-var` (apply consumes saved plans) | Phase 1 converts all four; Phase 0 re-greps before editing |
| "other workflows pass `-var "...token..."` the same way?" | No. Every `-var` name in tracked non-test code was enumerated: `ssh_key_path` (21, a pubkey path), `rehearsal_run_id` (9), `rehearsal_phase` (5), `zot_pull_token` (4, this item), `nic_attached` (4), `image_name` (4), `name`, `key_name`, `admin_ips`, and `hcloud_token` (1, in `hetzner-setup.md`, a placeholder). Arrays (`VAR_ARGS+=(-var=...)`) carry only `ssh_key_path`. So the workflow sites are the only real credential hits; the one other hit is agent-run markdown | S9 covers workflows, scripts and plugin markdown; the doc line is fixed in this change (CTO-ruled) |
| "move it to `TF_VAR_zot_pull_token` in the step environment" | Sound. Terraform contract measured locally (v1.9.8): with `TF_VAR_zot_pull_token` set, `plan` and `destroy` consume the variable; unset, both stop with `No value for required variable` (destroy validates it too, which is why the workflow reads it on teardown). ADR-241 measured that bare `--preserve-env` keeps the environment value over Doppler's | Phase 1 |
| (not in the brief) the workflow header explains why the token is read from Doppler `prd` and passed explicitly ("not reachable across roots" = terraform roots, accurate; plus a measured 403 on `soleur/prd` for the `prd_terraform`-scoped CI token) | New finding, measured with the operator's Doppler login (names and hashes only, no value printed): `prd_terraform` is a branch config of `prd`; `ZOT_PULL_TOKEN`, `ZOT_PULL_USER`, `ZOT_PUSH_TOKEN` are all listed in it, and the sha256 of `ZOT_PULL_TOKEN` read from `prd_terraform` equals the one read from `prd` (non-empty). So `doppler run -c prd_terraform --name-transformer tf-var` plausibly already exports `TF_VAR_zot_pull_token` with the identical value; the comment's 403 was measured on reading `soleur/prd` directly, not on the name in `prd_terraform` | Keep the explicit read (the CI service token's read of that name is unmeasured). Adjust only the Doppler-scope sentence of the header comment, and leave the accurate "not reachable across roots" text. Track dropping the explicit reads as option B (Phase 7; it needs an edit of the infra suite, which fires a production apply) |
| "scanner stages up to S8; floor currently 12 registry-login sites in 7 files" | Confirmed (S8 starts at line 7609 of the 8057-line file; `S8_SITE_FLOOR=12; S8_FILE_FLOOR=7`; `EXPECTED_TESTS=840` at the tail). S8's scan is keyed on login verbs and never sees a `terraform` line, so the zot `-var` is invisible to it | New stage S9, not a widening of S8 (CTO-ruled) |
| "editing `apply-web-platform-infra.yml` fires the production apply" | True, and the same holds for any path under `apps/web-platform/infra/**`: the push trigger excludes only `inngest-provision-rehearsal/**`, `rung2-rehearsal/**` and `git-data-root-key/**` as subdirectories. The infra suite `apps/web-platform/infra/inngest-provision-rehearsal.test.sh` (which pins the four `ZOT_PULL_TOKEN` reads, `>= 4`, and the absence of `-p soleur-registry`) sits in the triggering set; the rehearsal workflow itself does not (it triggers `infra-validation.yml`, which runs that suite) | No edit under `apps/web-platform/infra/**`; the new assertions live in the sweep suite. The infra suite is run read-only as a regression gate on the workflow edit |
| PRs 10566 and 10546 also edit the sweep script | Confirmed OPEN. Their hunks are manifest rows near lines 917-930 and one list near 4492; neither touches the tail | S9 is a tail append; the only existing lines edited are `EXPECTED_TESTS` and its ledger comment |
| "recompute the grep-q-pipe-guard `PJ_TRIPLES` pin if the change touches it" | The pin is 288 and counts (test file, verb, producer file) triples. The sweep suite already stubs `doppler` and names `inngest-provision-rehearsal`-adjacent producers only through its own text; the rehearsal workflow holds no `doppler|terraform ... | grep -q` pipe (its only grep pipes read `ls`/`grep` output) | Phase 6 runs the recompute recipe after S9 lands; the pin changes only if the count moves |

## Research Insights

### Premise Validation (Phase 0.6)

Checked: umbrella #9757 is OPEN and item 2 (`the zot pull token on terraform's argv`) is the unchecked bullet (together with the apply-workflow annotation bullet, so ticking this one cannot close the umbrella); PRs 10566 and 10546 are OPEN and edit only manifest regions of the sweep script; the four site lines match on `origin/main` byte for byte; deferred leads #10531, #10529, #10532, #10530 are all OPEN and out of scope; the ADR corpus (ADR-280 stdin-config contract, ADR-241 `--preserve-env`, ADR-279 rehearsal) has no rejected-alternatives entry for an env-var form of a terraform credential (ADR-241 prescribes it). Nothing cited was stale. One new fact surfaced: the workflow header's "not reachable across roots" is about terraform roots (the token is a parent-root `random_password`) and stays accurate; only its Doppler-scope sentence (the 403 on `soleur/prd`) was never measured against `prd_terraform`, which lists the same value (see reconciliation row 4).

### Property List (Phase 0.6b)

- **P1** After the change, no argv of `doppler run` or `terraform` in the rehearsal workflow's four steps contains the pull token.
- **P2** Terraform still receives the token in every one of the four steps (plan A, plan B, the destroy in the teardown-only arm, and the destroy in the teardown job), so none fails with `No value for required variable`; a destroy that fails there skips the orphan assertion and leaks the paid stack (the workflow's own comment).
- **P3** A future change that puts a credential on a `-var` option anywhere in tracked non-test code fails CI with `file:line` and the remedy.
- **P4** The new guard is green on arrival and cannot pass vacuously (its population is derived, floored, set-identity-checked and mutation-tested).
- **P5** The change fires no production apply and conflicts with PRs 10566/10546 at no more than the `EXPECTED_TESTS` line.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | What already covers it / why cut |
|---|---|---|
| Stdin-fed tfvars file (`-var-file=/dev/stdin` or a mode-600 file) | P1 | Env var buys P1 with zero file lifecycle; `/dev/stdin` also fights `doppler run`'s stdin (CTO, option C rejected) |
| Drop the explicit Doppler read and rely on `prd_terraform` inheritance (option B) | P1, smaller secret surface | Needs an edit of the infra suite (fires a production apply) and is unmeasured with the CI service token. Deferred to a tracked issue (Phase 7) |
| Widen S8's `scan.py` to a second verb | P3 | Rewrites S8's 12/7 floor and identity rows (the lines most likely to conflict with 10566/10546). S9 is additive (CTO) |
| Edit `apps/web-platform/infra/inngest-provision-rehearsal.test.sh` to pin the `export` | P2 | Fires the production apply. The sweep's executed rows plus one static `export` pin row cover P2 |
| A new standalone suite plus a `scripts/test-all.sh` registration | P4 | The sweep is already registered (`run_suite "tests/scripts/argv-bearer-sweep"`); a new stage rides it |
| A new ADR | decision record | ADR-280 already owns "credentials never ride argv"; one addendum paragraph records the new population (each prior slice did the same) |
| Token rotation | remediate past exposure | Out of scope by ADR-280 ("past exposure is not remediated here; rotation stays with ADR-241 O13"); the workflow ships unfired and the exposure window is a reviewer-gated, dispatch-only runner |

### Institutional learnings applied

- ADR-241 (§ every Tier-B `doppler run` carries `--preserve-env`): bare `--preserve-env` and the list form both keep the environment value; the source (pre-transform) name does not. The four invocations already carry bare `--preserve-env`, so an exported `TF_VAR_zot_pull_token` wins by construction, and the value is identical either way.
- `2026-03-21-doppler-tf-var-naming-alignment.md`: `tf-var` yields `TF_VAR_<lowercase key>`; `--only-secrets` combined with `--name-transformer tf-var` fails. The change must not add `--only-secrets`, and the variable name equals the lowercased Doppler key (`zot_pull_token`).
- `2026-04-05-terraform-doppler-dual-credential-pattern.md`: `tf-var` prefixes every secret, so the change is additive: one `TF_VAR_` entry, raw `AWS_*` backend vars untouched.
- `2026-10-14-my-stubs-checked-the-shape-of-argv-and-never-the-value...`, `2026-10-09-my-gate-pins-were-green-and-left-position-wiring...`, `2026-10-15-a-census-that-stubs-the-host-verb-cannot-see-the-env-the-step-forgot-to-pass.md`: text pins compare strings, not wiring. S9 executes the real `run:` body, asserts VALUES (the canary, `rehearsal_run_id=<id>`, `nic_attached=<bool>`) and derives the required environment from the consumer.
- `2026-10-01-a-grep-q-in-a-pipefail-chain...`: `producer | grep -q` returns 141 on a real match under pipefail; S9 greps files and here-strings, never a pipe into `grep -q`.
- `2026-10-09-docs-only-path-filter-claims-need-verification.md`: verify the literal `on.push.paths` before claiming a change skips a deploy. Done for the apply trigger; `plugins/soleur/**` (the doc fix) triggers `version-bump-and-release.yml`, an expected plugin release, not an infra apply.
- ADR-280 / sweep ledger: floors are re-measured, never lowered; `EXPECTED_TESTS` is the measured green total; every fixture dir goes through `assert_fixture_dir` first (the `fixture-relative-assert` P1b baseline is row-by-row equality).

## Open Code-Review Overlap

One open `code-review` issue names a planned file: **#8800** (census sandbox shares inodes/symlinks with the live repo) names `scripts/lib/test-affected-paths.sh`. **Acknowledge:** a different concern (fixture write-through hazard in a census), the plan adds one array entry and does not touch the census. No open code-review issue names the workflow, the sweep suite, the doc, or the guard test. The deferred argv-bearer leads #10531, #10529, #10532, #10530 are named out of scope by the brief and stay open.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Implement item 2 of umbrella #9757 (argv-bearer follow-ups)." | the whole plan (Phases 1-2) | mapped |
| 2 | "#9757 is a tracking umbrella: it MUST STAY OPEN; the PR body uses \"Ref #9757\", never a closing keyword (no Closes/Fixes/Resolves)." | frontmatter has no `closes:`; AC-12; Phase 7 | mapped |
| 3 | "move it to `TF_VAR_zot_pull_token` in the step environment (or a stdin-fed file)" | Phase 1 (env chosen; stdin file cut, CTO) | mapped |
| 4 | "add the verb to a scanner stage in the same change (tests/scripts/test-argv-bearer-sweep.sh, which has stages up to S8" | Phase 2 (stage S9) | mapped |
| 5 | "widen the corpus or add a stage so the gate arrives green" | Phase 2 (S9 added; real-tree row green after Phase 1) | mapped |
| 6 | "confirm the four sites still match on current main before editing" | Phase 0 and AC-1 | mapped |
| 7 | "also check whether other workflows pass `-var \"...token...\"` the same way and whether the scanner should cover them" | Reconciliation row 2; S9 corpus (workflows, scripts, plugin markdown); Phase 4 | mapped |
| 8 | "Out of scope (do not touch): .github/workflows/apply-web-platform-infra.yml ..., the deferred review leads #10531, #10529, #10532, #10530, and the pending D10 rehearsal-log verification (never force a registry-luks-recut)" | Non-Goals; AC-9 (diff-scope) | mapped |
| 9 | "keep the sweep-script edit minimal and additive" | S9 is a tail append; AC-8 bounds the diff of existing lines | mapped |
| 10 | "recompute the grep-q-pipe-guard PJ_TRIPLES pin per the recipe in .claude/hooks/grep-q-pipe-guard.test.sh if the change touches it" | Phase 6 (conditional) | mapped |
| 11 | "Constraints: never print secrets; no -auto-approve for Terraform; no git stash; no git add -A / git add . (pathspec commits only)" | Sharp Edges; AC-10 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Edit `.github/workflows/inngest-provision-rehearsal.yml` (four sites + header comment) | "move it to `TF_VAR_zot_pull_token` in the step environment" (asks 3) | asked |
| Edit `tests/scripts/test-argv-bearer-sweep.sh` (stage S9, `EXPECTED_TESTS`) | "add the verb to a scanner stage in the same change" (asks 4, 5) | asked |
| S9 executed rows for the two destroy bodies (run the real step bodies under stubs) | "so the gate arrives green" (ask 5) | inferred — justification: a text scan cannot prove that a destroy step (the arm whose failure leaks a paid host) hands terraform the token by environment; the S3/S4 stages set the precedent; CTO-ruled, then narrowed from four steps to the two destroy bodies at plan review |
| Edit `plugins/soleur/skills/deploy/references/hetzner-setup.md` (one line) | "whether the scanner should cover them" (ask 7) | inferred — justification: S9 covering plugin markdown (CTO-ruled) would otherwise carry a permanent exception that defeats the rule |
| Edit `scripts/lib/test-affected-paths.sh` (one array entry) | "so the gate arrives green" (ask 5) | inferred — justification: S9 executes the workflow's step bodies, so a workflow edit must select the suite in the pre-push affected gate (S3/S4 convention; CTO-ruled) or the break surfaces only in CI's full run |
| Append an addendum to ADR-280 | "add the verb to a scanner stage" (ask 4) | inferred — justification: every prior sweep slice recorded its guard class and stated blind spots in the ADR addendum chain; the suite pins the ADR's sentences and a silent guard-class change rots the record |
| Conditional `PJ_TRIPLES` recompute | "recompute the grep-q-pipe-guard PJ_TRIPLES pin per the recipe" (ask 10) | asked |
| File a tracked follow-up for option B | "the deferred review leads ..." (ask 8: out-of-scope items are tracked, not dropped) | inferred — justification: a deferral without a tracking issue is invisible (the plan skill's deferral-tracking check) |

### Split Assessment

- Subsystems touched: 5 — `.github`, `tests`, `scripts`, `plugins/soleur`, `knowledge-base` (ADR addendum plus plan/spec artifacts)
- Planned files: 6 edited code/doc files plus 3 artifacts | Estimated changed lines: about 650 (about 580 in the sweep suite, mostly the new stage; the other four files change by 25 lines in total)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — over the threshold on subsystem roots only. The roots beyond `.github` + `tests` are one array entry, one doc line and one ADR paragraph. A split would leave S9 either red (the doc line, or the rehearsal sites, would trip it) or carrying a temporary allowlist, and it would put a second edit on the sweep script's tail while 10566/10546 are in flight. No file moves in a split that this PR can avoid.

## Implementation Phases

Order is test-first (`cq-write-failing-tests-before`): S9's real-tree row is added first and is RED while the four sites exist; Phase 1 turns it GREEN.

### Phase 0 — Re-verify the premise (no edit)

- `git fetch origin main`; re-run `git grep -n 'zot_pull_token=\${ZOT_PULL}' origin/main -- .github/workflows/inngest-provision-rehearsal.yml` (expect exactly 4 lines, 224/250/376/646 or their successors) and the `-var` name census (the reconciliation table's list). If main moved the lines, use the new lines; if a fifth site or another credential-named `-var` appeared, stop and re-plan.
- `gh pr view 10566` / `gh pr view 10546`: if either merged, rebase onto main first and re-diff the `EXPECTED_TESTS` region.

### Phase 1 (RED) — Add stage S9 to `tests/scripts/test-argv-bearer-sweep.sh`

Insert after the S8 `echo "=== stage S8 ... done ==="` line and before the `# VERDICT` block. Reuse the helpers already defined earlier in the file (`assert_fixture_dir`, `row`, `fatal`, `s3_body`, `s6_edit`, `git-fixture-env.sh`); define `s9_*` helpers locally. Components:

1. **Scanner `scan.py`** (heredoc, `python3 -I`, a function of a root so mutation rows run the same text on a scratch repository). Corpus = `git ls-files --cached --others --exclude-standard`, minus the S8 exclusion predicate (copy it byte-for-byte: `*.test.sh`, `.test.` in the basename, any `test`/`tests`/`fixtures` directory component, `knowledge-base/`); extensions `.yml .yaml .sh .bash`, plus `.md` only under `plugins/`; a fast bytes filter on `-var`. Logical lines join backslash continuations (a comment line is never continued); full-line comments are skipped in non-markdown files. The option regex is anchored on BOTH sides: `(?<![\w-])-var(?:=|\s+)["']?(?P<name>[A-Za-z_][A-Za-z0-9_]*)=`, so it needs a left boundary and the `NAME=` shape. Without them it matches `--name-transformer tf-var -- \` (dozens of tracked lines: the apply workflows, `admin-ip-refresh` and plugin markdown) and `-var-file`. It accepts `-var NAME=v`, `-var=NAME=v`, `-var "NAME=v"`, `-var="NAME=v"`, `-var 'NAME=v'`. No terraform-verb requirement (CTO, item 3): `VAR_ARGS+=(-var=...)` array building has no verb on its line and is the same exposure; the S9 header comment states why this differs from S8, which keys on verbs. One TSV record per option: file, line, name, verdict, logical line.
2. **Verdict (CTO-ruled; the value-side arm was cut at plan review).** BAD when the NAME matches `(token|secret|passw(or)?d|credential|api_?key|private_?key|bearer)|(^|_)key$` case-insensitively (so `ssh_key_path`, `image_name`, `rehearsal_run_id`, `rehearsal_phase`, `nic_attached`, `key_name`, `admin_ips` stay clean). A credential reaching a non-matching name (for example `-var "zp=${ZOT_PULL}"`) is a STATED blind spot recorded in the ADR addendum; the one known file is closed by identity row I1.
3. **Floor and identity (anchor).** `S9_VAR_FLOOR` is the count of `-var` options on the real tree (re-measure: about 50, and the census of `ssh_key_path` sites reads 21 or 22 depending on the counting rule, so never copy a number from this plan). During the RED phase set it to the count on the unchanged tree minus the 4 `zot_pull_token` options, and confirm it in Phase 2; a scan below the floor is RED, never a clean bill. There is no file floor (I1 pins the rehearsal file's names). A floor survives any substitution that keeps the count, so it is paired with set identity: **I1** the rehearsal workflow's records are exactly `rehearsal_run_id` x4 and `nic_attached` x4, no other name (its failure message names the edit procedure: a new benign `-var` there is a deliberate edit of the row); **I2** a static pin over ALL four step bodies: exactly one `export TF_VAR_zot_pull_token=` line whose value is the read variable, positioned BEFORE the step's `doppler run` line (position, not only presence), and the `doppler run` line keeps bare `--preserve-env` (ADR-241). I2 pins the real workflow's spelling; the executed judge below accepts the contract's other spellings (braces, export before or after the mask line), so a braces variant is a must-pass for the judge, not a competitor of I2.
4. **Executed rows for the two destroy bodies (CTO re-ruling, option b).** The destroy steps are the arms whose failure leaks a paid host (a destroy that dies on `No value for required variable` skips the orphan assertion); a forgotten export in a PLAN step fails loudly before any host exists and is covered by I2. Selectors via `s3_body`: `Teardown only (recovery arm)` and `Terraform destroy (everything` (use these exact prefixes in code and rows). Run the real `run:` body under `env -i` with a PATH of stubs plus a symlink dir of real tools (`bash date printf cat grep mkdir rm env`): `GITHUB_RUN_ID`, `DOPPLER_TOKEN` and a DIFFERENT synthetic `DOPPLER_TOKEN_PRD` (no phase-B scratch setup is needed). **Stub `doppler`:** `secrets get ZOT_PULL_TOKEN -p soleur -c prd --plain` prints a synthetic canary only when `DOPPLER_TOKEN` equals the PRD synthetic (else exit 1, modelling the 403); `run ... -- <cmd>` records its own argv (NUL-delimited) and execs `<cmd>` WITHOUT injecting any `TF_VAR_*` (production would inherit the identical value from `prd_terraform`, but the stub models the unmeasured case so the drop-export mutation cannot pass by inheritance; say so in a row comment). **Stub `terraform`:** records argv (NUL-delimited) and the value of `TF_VAR_zot_pull_token` (or the literal `<unset>`), prints a marker line, exits 0. Assertions (a verdict helper `s9_judge_run` naming the failing clause): exit 0; exactly one terraform call; the canary is in NO recorded argv (doppler secrets-get, doppler run, terraform); `TF_VAR_zot_pull_token` equals the canary in terraform's environment; terraform's argv carries `rehearsal_run_id=<GITHUB_RUN_ID>` by value. Mask-order and printed-once assertions are deliberately NOT included (log masking is not P1 or P2).
5. **Mutation, harness and must-pass rows** (see `## Guard Contract`): one site per mutation type (not one per site), the undoctored-GREEN control for `s9_judge_run`, and fabricated per-clause controls only for clauses no real mutation reaches (terraform call count, argv value).
6. **Ledger, at the end of Phase 2.** Bump `EXPECTED_TESTS` (line `EXPECTED_TESTS=840`) to the measured green total (`840 + the S9 row count`, only measurable once the whole suite is green) and add one ledger comment line in the existing `# a -> b at ...` style. Both operands stay literals directly above the `if`. No other existing line is edited.

Style constraints (they keep the repo ratchets quiet): call `assert_fixture_dir` on every fixture dir before writing into it; no `producer | grep -q` pipes (grep a file or a here-string); no new stub verb beyond `doppler` and `terraform`; derive the python in `python3 -I` heredocs, as S8 does. Target size: about 300 lines for the whole stage.

At the end of Phase 1 the S9 real-tree rows (not the suite total, which fails for unrelated reasons while `EXPECTED_TESTS` is stale) must be RED naming the four workflow lines (it is the proof the scanner sees the verb) — record those rows' output in the work log.

### Phase 2 (GREEN) — Convert the four sites in the rehearsal workflow

For each of the four steps, keep the existing read and mask lines exactly (the infra suite pins them), add one export line directly after the `printf '::add-mask::...'` line, and delete the `-var "zot_pull_token=${ZOT_PULL}"` line together with the now-dangling `\` at the end of the previous line:

```bash
ZOT_PULL="$(DOPPLER_TOKEN="$DOPPLER_TOKEN_PRD" doppler secrets get ZOT_PULL_TOKEN -p soleur -c prd --plain)"
printf '::add-mask::%s\n' "$ZOT_PULL"
export TF_VAR_zot_pull_token="$ZOT_PULL"
doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan -no-color -input=false -out=tfplan-a \
    -var "rehearsal_run_id=${GITHUB_RUN_ID}" -var nic_attached=false
```

Rules (all four steps): the invocations keep bare `--preserve-env` (ADR-241) and do not gain `--only-secrets`; the read keeps its `DOPPLER_TOKEN_PRD` override and `-p soleur -c prd` (the infra suite pins `>= 4` such reads and the absence of `-p soleur-registry`); comments added to the YAML must not contain the substring `ssh ` or `ssh-key` (the same suite asserts the workflow has none) or the literal `get ZOT_PULL_TOKEN -p soleur-registry`. Header comment above the phase-A plan step: leave "not reachable across roots" (accurate: terraform roots) and change only the Doppler-scope sentence to one measured sentence — the 403 was on reading `soleur/prd`; `prd_terraform` lists `ZOT_PULL_TOKEN` with an equal value; the explicit read stays pending the option-B issue (Phase 7). Run the infra suite read-only afterwards (`bash apps/web-platform/infra/inngest-provision-rehearsal.test.sh`) and confirm it is unchanged-green.

### Phase 3 — Affected-test edge

Add `.github/workflows/inngest-provision-rehearsal.yml` to `AFFECTED_TESTS_SCRIPTS_ARGV_BEARER_SWEEP_PATHS` in `scripts/lib/test-affected-paths.sh` (array at line 962 on main), in a new `# S9 (#9757 item 2): ...` comment block beside the S3 workflow paths. Measure with `bash scripts/test-all.sh --print-selection --paths=<path>` (note: the pre-pass is slow; run it detached): before the edit the workflow path does not select `tests/scripts/argv-bearer-sweep`, after it does; and `--paths=scripts/lib/test-affected-paths.sh` selects the same set before and after (the array already lists that file, so the edit selects the suite and nothing broader). S8 stays full-run only (its population is the whole tree); the ADR addendum states why S9 differs.

### Phase 4 — Fix the one doc hit

`plugins/soleur/skills/deploy/references/hetzner-setup.md` line 17: replace `-var="hcloud_token=<your-token>"` with the env form: `read -rs TF_VAR_hcloud_token; export TF_VAR_hcloud_token` before `terraform apply -var='admin_ips=["<your-ip>/32"]'` (CTO: `read -rs`, not an inline literal, so the value never lands in shell history). One line plus one line; no behavior change. This path matches `version-bump-and-release.yml` (`plugins/soleur/**`), so the merge cuts an automatic plugin release; that is expected and not an infra apply.

### Phase 5 — Architecture record

Append a `### 2026-10-20 follow-ups: terraform -var credentials (#9757 item 2)` subsection to ADR-280 (after the `2026-10-19 follow-ups: registry login verbs` subsection) via `soleur:architecture`: the rule (a credential reaches terraform through `TF_VAR_*` in the step environment, never `-var`), the S9 guard, its stated blind spots and the open option B, in about five lines. No new ordinal. See `## Architecture Decision (ADR/C4)`.

### Phase 6 — Verification (run detached, logs under `/var/tmp`)

Detached form: `setsid nohup bash -c '<cmd>; echo $? > /var/tmp/<name>.rc' </dev/null > /var/tmp/<name>.log 2>&1 &`, then a `Monitor` until-loop on the rc file (no `sleep N &&`, no `pgrep -f`; `plugins/soleur/scripts/lib/proc.sh` for process lookups).

- `bash tests/scripts/test-argv-bearer-sweep.sh` (the suite is long: tens of seconds to minutes) — GREEN, `EXPECTED_TESTS` equals the measured total.
- `bash apps/web-platform/infra/inngest-provision-rehearsal.test.sh` (read-only) — GREEN.
- `bash plugins/soleur/test/c4-count-parity.test.sh` — GREEN (it was green at plan time, rc=0; the change adds no workflow, monitor or heartbeat slug).
- The `PJ_TRIPLES` recompute (recipe at `.claude/hooks/grep-q-pipe-guard.test.sh`, the `Recompute PJ_TRIPLES` line: `PJ_ALL="$(git ls-files)"; . <(sed -n '/^# PJ-DERIVE-BEGIN/,/^# PJ-DERIVE-END/p' .claude/hooks/grep-q-pipe-guard.test.sh); pj_join_pairs | LC_ALL=C sort -u | wc -l`) from a tree with no uncommitted tracked change, so commit first: expect 288 unchanged. If the count moves, add the exempt row(s) for the new pair(s) with a vocabulary word from `PJ_VOCAB` and a reason, update `PJ_TRIPLES`, and run the guard (`bash .claude/hooks/grep-q-pipe-guard.test.sh`). Touch that file only if the count moved.
- `bash plugins/soleur/test/fixture-relative-assert.test.sh` — row-by-row equality with `plugins/soleur/test/fixture-relative-assert.baseline.txt` (the sweep file has 5 rows). PR 10546 also edits that baseline, so regenerate it only if S9 truly adds a row, in the same commit.
- `bash scripts/guard-vacuity-floor.test.sh`, `python3 scripts/lint-guard-contract.py` (this plan), and the repo's workflow lints that run on a `.github/workflows/*.yml` edit (actionlint where installed, shellcheck on the extracted bodies).
- Diff-scope check (AC-9) and the secret-leak check (AC-10) below.

### Phase 7 — Tracking and hand-off

- File one GitHub issue for **option B** (title: `chore(infra): drop the explicit ZOT_PULL_TOKEN reads in inngest-provision-rehearsal.yml and rely on prd_terraform inheritance`; body: the measured evidence, the pins that must change in `inngest-provision-rehearsal.test.sh`, the flip evidence "a measured read of `ZOT_PULL_TOKEN` with the CI service token's `prd_terraform` scope", milestone from `knowledge-base/product/roadmap.md`, `Ref #9757`). It rides the next PR that already owns an apply.
- PR body: `Ref #9757` (never `Closes`), the measured findings, the `Ruled by CTO agent` lines from `decision-challenges.md`, and the note that no production apply fires.
- After merge (ship's post-merge step): tick item 2 on #9757 with a `_Landed: PR #<n> ..._` note in the style of the neighbouring items, and state the pending verification (the next rehearsal dispatch's phase-A plan succeeds without `No value for required variable`; that dispatch is the already-pending D10 evidence run, so this adds no new operator step). The umbrella stays open: the apply-workflow annotation bullet is still unchecked.

## Files to Edit

- `.github/workflows/inngest-provision-rehearsal.yml` — four sites, header comment (Phases 1-2)
- `tests/scripts/test-argv-bearer-sweep.sh` — stage S9 appended before `# VERDICT`; `EXPECTED_TESTS` and its ledger line (Phase 1)
- `scripts/lib/test-affected-paths.sh` — one array entry plus a comment block (Phase 3)
- `plugins/soleur/skills/deploy/references/hetzner-setup.md` — one doc line (Phase 4)
- `knowledge-base/engineering/architecture/decisions/ADR-280-credentials-reach-curl-on-stdin-config-through-one-shared-library.md` — addendum subsection (Phase 5)
- `.claude/hooks/grep-q-pipe-guard.test.sh` — ONLY if the `PJ_TRIPLES` recompute moves (Phase 6)
- `plugins/soleur/test/fixture-relative-assert.baseline.txt` — ONLY if S9 adds a P1b row (Phase 6)

Glob check (`hr-when-a-plan-specifies-relative-paths-e-g`): every path above was confirmed with `git ls-files`; the S9 corpus globs (`.github`, `scripts`, `apps`, `plugins`) each match real files (the census found `-var` records in `.github/workflows/*.yml` and `plugins/soleur/skills/deploy/references/hetzner-setup.md`).

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9757-zot-pull-token-tf-var-env/tasks.md` and `decision-challenges.md` (plan artifacts). No new source, test or workflow file.

## Non-Goals / Out of Scope

- `.github/workflows/apply-web-platform-infra.yml`, and anything under `apps/web-platform/infra/**` outside the three excluded subdirectories (editing either fires the production apply), including the infra suite `inngest-provision-rehearsal.test.sh`.
- The deferred review leads #10531, #10529, #10532, #10530 (named by the brief; each stays open).
- The pending D10 rehearsal-log verification; never dispatch or force a `registry-luks-recut`.
- The apply-workflow restore-step annotations (a separate unchecked umbrella bullet that rides the next apply-owning PR).
- Rotating the pull token (ADR-280: past exposure is not remediated here; rotation stays with ADR-241 O13).
- Option B (dropping the explicit reads): tracked in Phase 7, not built.
- `env "TF_VAR_inngest_link_tls=..." terraform` at `apply-web-platform-infra.yml:6575` (a non-secret flag value on `env`'s argv, in the out-of-scope file).

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The rehearsal workflow is dispatch-only and reviewer-gated; a broken export fails the phase-A plan with `No value for required variable` in the Actions log, before any host is created. The worse case is the teardown arm: if the destroy step fails the same way, a real run leaks a paid throwaway host until the drift sweep flags it. S9's executed rows run all four step bodies, including both destroys, to prevent exactly that.
- **If this leaks, the user's workflow is exposed via:** the zot pull credential (read access to the self-hosted registry that serves the app images) appearing in the process list of a GitHub-hosted runner for the duration of each terraform command, readable by any other process on that runner VM; masking hides log text only. No end-user data is involved.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** `aggregate pattern`, not `single-user incident`: one ephemeral single-tenant runner, a reviewer-gated dispatch-only workflow, an infra credential and no end-user data; the stake is the class (credentials on argv across the sweep), which is why the guard is the deliverable. Ruled by CTO agent, 2026-10-20: `aggregate pattern` confirmed, no CPO sign-off.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO ruled on the forks (recorded in `decision-challenges.md`, with a second ruling after plan review): env export (option A) over dropping the read (B) or a stdin file (C); new stage S9 over widening S8; S9 covers workflows, scripts and plugin markdown with the doc line fixed here; a verb-free `-var` regex with the name arm only (the value-side taint arm was dropped at re-ruling); executed rows for the two destroy bodies, static export-position pin for all four steps, with a `doppler` stub that does not inject `TF_VAR_*`; one affected-paths entry; threshold `aggregate pattern`. Constraint carried: nothing under `apps/web-platform/infra/**` is edited. Product/UX, Marketing, Operations, Finance, Legal, Sales and Support: no implications (CI-runner credential hygiene; no UI, no vendor, no spend, no personal data, no published claim).

No GDPR/compliance gate fired: no regulated-data surface, no new processing activity, no LLM or external-API use on session data, no new artifact distribution surface (the plugin release triggered by the doc line ships an existing skill reference with one line changed).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-280 (`status: adopting`, no new ordinal): add `### 2026-10-20 follow-ups: terraform -var credentials (#9757 item 2)` as an in-scope task of Phase 5 — the decision is "a credential reaches terraform through `TF_VAR_*` in the step environment, never as a `-var` option", enforced by S9. It records S9's blind spots and the open option B, in about five lines. Not deferred to a follow-up issue.

### C4 views

No C4 impact. Checked against `spec.c4` (read in full), `views.c4` (read in full) and the element and relationship declarations of `model.c4` (90 elements; the `github`, `doppler`, `zotRegistry`, `hetzner` systems and the `github -> doppler`, `doppler -> zotRegistry`, `github -> zotRegistry` edges): (a) external human actors: none added (the founder approval edges are unchanged); (b) external systems and vendors: GitHub Actions, Doppler, the zot registry and Hetzner are all already modeled, and nothing new is called; (c) containers and data stores: none touched; (d) actor-to-surface access relationships: the runner's read of Doppler secrets for the rehearsal root is the existing `github -> doppler` family and is unchanged — the credential moves from argv to the environment inside the same runner process tree, below C4 altitude. The throwaway rehearsal host is deliberately unmodeled. Derived cardinalities: `plugins/soleur/test/c4-count-parity.test.sh` was green at plan time (rc=0) and is re-run in Phase 6; the change adds no workflow, monitor or heartbeat slug.

### Sequencing

The ADR describes the target state now; nothing is soak-gated.

## Guard Contract

### Guard 1 — S9 static scan: no credential-named variable rides a `-var` option

**Property.** No tracked, non-test, non-comment `-var` option in a workflow, script or plugin markdown names a credential variable, and each converted rehearsal step exports `TF_VAR_zot_pull_token` before its `doppler run`.

**Assembly.** The population is derived, not listed: every file from `git ls-files --cached --others --exclude-standard` (the S8 exclusion predicate: `*.test.sh`, `.test.` basenames, `test`/`tests`/`fixtures` directory components, `knowledge-base/`) with extension `.yml .yaml .sh .bash`, plus `.md` under `plugins/`; every logical line after backslash-continuation joining. The chokepoint is the one anchored option regex (left boundary `(?<![\w-])`, then `-var`, then `=` or whitespace, then `NAME=`), applied to every logical line with NO verb requirement, so array building (`VAR_ARGS+=(-var=...)`), `bash -c "..."` payloads and `ssh host "..."` strings reach the same predicate; the verdict (name regex) is quantified over every record, not the first. The static export pin (I2) quantifies over all four step bodies of the rehearsal workflow. Stated blind spots: a credential reaching a non-matching name (covered for the rehearsal file only by identity row I1), a value built by concatenation or held in an array element, a YAML folded `>` block, `.ts`/`.tf` files, and a `-var` in unrelated tooling (an over-read, not a miss).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert ONE rehearsal site (one site per mutation type, not one per site) to `-var "zot_pull_token=${ZOT_PULL}"` in a scratch copy | RED, reason `name`, naming that file:line |
| 2 | Dispatch: delete the scan roots (`.github`, `scripts`, `apps`, `plugins`) from the scratch tree (a separate row from the rename below) | RED, reason `floor` |
| 3 | Same dispatch, other cause: rename the matched option (`-var` to `-vars`) in every site | RED, reason `floor` |
| 4 | A second member after a compliant first, next line and same line: `-var "rehearsal_run_id=1" -var "api_token=$T"` in one new file; also `VAR_ARGS+=(-var="deploy_token=$T")` with no verb on the line and `bash -c "terraform plan -var db_password=$P"` as a quoted payload | RED for each file; the compliant first record is still counted |
| 5 | Add a credential-named `-var` to the rehearsal workflow under a new name (`-var "zot_pull_credential=..."`), and separately a non-credential name with a plain value (`-var "extra_flag=1"`) | the first RED (`name`); the second fails identity row I1 (the set is closed) |
| 6 | Restore `-var="hcloud_token=<your-token>"` in the scratch copy of `hetzner-setup.md` | RED (plugin markdown is in the corpus) |
| 7 | Static pin I2: move the `export` line after the `doppler run` line in one step; and separately remove bare `--preserve-env` from one `doppler run` line | RED for each (position and flag are both pinned, not only presence) |

**Harness rows.** (i) A harness-side edit that must drive the SUITE red: make `s9_scan` print nothing and assert the real-tree row reports `floor`, not green. (ii) Must-PASS inputs that are NOT the canonical tree: `-var "ssh_key_path=${CI_SSH_PUB}"`, `-var image_name="$PINNED"`, `-var-file=<(printf ...)`, `--name-transformer tf-var -- \` (the line shape that over-matches a bare `-var` regex), a commented `# -var api_token=x`, a `-var` in a `*.test.sh` and under `knowledge-base/` (all zero BAD records), and a file that reads a secret AND passes a clean `-var` value (the shape of `apply-web-platform-infra.yml`, where a taint rule would have over-fired); this is what separates a guard that rejects everything from one that judges. (iii) Control: the scratch base copy (every file the floor counts) is judged GREEN with the real tree's count, so each mutant is RED for its mutation alone.

**Anchor.** The floor and identity row I1 live in the same file as the scanner, so one diff can weaken both; the guard proves consistency, not integrity. What sits outside the commit: Guard 2 reads the real workflow, not a registry of it; `EXPECTED_TESTS` is an independent count of how many rows ran; PR review of the diff is the final anchor. A `>= N` floor survives any substitution that keeps N, which is why I1 pins the rehearsal file's exact name multiset.

### Guard 2 — S9 executed rows: the destroy steps reach terraform with the token in the environment and in no argv

**Property.** In each of the two converted `terraform destroy` step bodies (the teardown-only recovery arm and the teardown job), the pull token is in the environment of the `terraform` process and in no process argument list (doppler or terraform), so a destroy never dies on a missing required variable.

**Assembly.** The two bodies are derived by selector from the workflow YAML (`s3_body`), not copied: `Teardown only (recovery arm)` and `Terraform destroy (everything`. The chokepoint is the stub pair every destroy must flow through: stub `doppler` (secrets-get and run arms; the run arm injects nothing) and stub `terraform` (argv and `TF_VAR_zot_pull_token` recorder). The two plan steps are not executed; they are covered by Guard 1's static pin (a forgotten export there fails loudly before any host exists). A destroy-class step added to the workflow later is a member the derivation must see: a row asserts the number of steps containing `terraform destroy` equals the two exercised ones.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Revert ONE destroy step to the `-var` form and delete its export | RED: `canary-in-argv` and `env-not-set` |
| 2 | REORDER: move the `export` line after the `doppler run` line in one destroy step (the property is about order: terraform must see the variable at call time) | RED: `env-not-set` at the terraform call, although the export still exists in the body |
| 3 | Export a different value (`"x${ZOT_PULL}"`) | RED: `env-value-differs` |
| 4 | Break the Doppler pairing: read with the default token instead of `DOPPLER_TOKEN_PRD` | RED: the stub's 403 model fails the step (rc != 0) |
| 5 | Add a third step that runs `terraform destroy` | RED: the destroy-step count row |

(Dropping the export alone is subsumed by rows 1 and 2, which both produce `env-not-set`; it is not a separate row.)

**Harness rows.** (i) Controls for `s9_judge_run`: the undoctored directory must come out GREEN first, plus fabricated directories for the clauses no real mutation reaches (terraform call count, the `rehearsal_run_id` value). (ii) Must-PASS non-canonical: a compliant variant that writes the export with braces (`"${ZOT_PULL}"`), places it BEFORE the `add-mask` line (the contract permits either order) and adds an unrelated `TF_LOG=` export; it must come out GREEN (this is the judge's contract, which is wider than the static I2 spelling pin). (iii) The stub controls: the stub `terraform` fed a body that never exports records `<unset>` (so a stub that always reported the canary is caught), and the stub `doppler` returns 1 when `DOPPLER_TOKEN` is not the PRD synthetic.

**Anchor.** The synthetic canary and the PRD token are drawn from the suite's own synthesized-token convention and differ from each other; the comparison value is generated in the harness, never read from the workflow under test, so the workflow cannot move it. As in Guard 1, integrity beyond consistency rests on `EXPECTED_TESTS` and review.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC-1 (premise held at edit time): immediately before editing, `git grep -c 'zot_pull_token=\${ZOT_PULL}' -- .github/workflows/inngest-provision-rehearsal.yml` printed `4` (recorded in the work log with the line numbers).
- [ ] AC-2 (P1): `git grep -nE -- '-var[= ]+"?zot_pull_token' -- .github/workflows/inngest-provision-rehearsal.yml` is empty, and each of the four steps contains exactly one `export TF_VAR_zot_pull_token="$ZOT_PULL"` (S9 row I2).
- [ ] AC-3 (P2): the S9 executed rows for the two destroy bodies report the canary in no argv, `TF_VAR_zot_pull_token` equal to the canary in terraform's environment and `rehearsal_run_id=<id>` by value; the static pin I2 holds for all four steps (one `export` of the read variable, positioned before the `doppler run`, bare `--preserve-env` kept) (`tests/scripts/test-argv-bearer-sweep.sh`, S9 rows).
- [ ] AC-4 (P3/P4, red-then-green): before Phase 2 the S9 real-tree rows were RED naming the four workflow lines (the S9 rows' output saved; the suite total is red for unrelated reasons until `EXPECTED_TESTS` is bumped); after Phase 2 they are GREEN with the measured count, and `S9_VAR_FLOOR` equals the count measured on the converted tree.
- [ ] AC-5 (guard contract): every mutation row of both guards in `## Guard Contract` exists in S9 and is judged RED for its named reason; the reorder rows (Guard 1 row 7 and Guard 2 row 2) are RED while the export line still exists; the undoctored-GREEN control and the must-PASS rows (including `tf-var -- \` and the secret-reading file with a clean `-var`) are present.
- [ ] AC-6: `bash tests/scripts/test-argv-bearer-sweep.sh` exits 0 with `0 failed`, and `EXPECTED_TESTS` equals the measured pass count (`840 + the number of S9 rows`, derived from the run).
- [ ] AC-7: `bash apps/web-platform/infra/inngest-provision-rehearsal.test.sh` (unedited) is green; `plugins/soleur/test/c4-count-parity.test.sh` is green; `python3 scripts/lint-guard-contract.py` passes on this plan.
- [ ] AC-8 (minimal, additive): `git diff origin/main -- tests/scripts/test-argv-bearer-sweep.sh` shows added lines only except the `EXPECTED_TESTS=` line (changed) — verified with `git diff --numstat` (deleted lines in that file: 1) — and the new stage sits between the S8 `echo "=== stage S8` line and the `# VERDICT` block.
- [ ] AC-9 (diff scope, nothing fires an apply): `git diff --name-only origin/main...HEAD` contains none of: `.github/workflows/apply-web-platform-infra.yml`, `tests/scripts/lib/destroy-guard-filter-web-platform.jq`, or any `apps/web-platform/infra/**` path outside `inngest-provision-rehearsal/`, `rung2-rehearsal/`, `git-data-root-key/` (verified with `git diff --name-only origin/main...HEAD | grep -E '^apps/web-platform/infra/' | grep -vE '^apps/web-platform/infra/(inngest-provision-rehearsal|rung2-rehearsal|git-data-root-key)/' || true` printing nothing; read the output, not the exit status, which is 1 when the list is empty); the changed-file set is the Files to Edit list.
- [ ] AC-10 (no secret printed): no log, plan, ADR, issue body or PR body contains a token value; the hashes quoted in the plan are not reproduced; no `-auto-approve` was added or run, no `git stash` used, and commits are pathspec-only (`git add <paths>`).
- [ ] AC-11 (affected-gate edge): after Phase 3, `--print-selection --paths=.github/workflows/inngest-provision-rehearsal.yml` selects `tests/scripts/argv-bearer-sweep`, and `--paths=scripts/lib/test-affected-paths.sh` selects the same set as before the edit (both recorded).
- [ ] AC-12 (umbrella stays open): the PR body contains `Ref #9757` and no `Closes`/`Fixes`/`Resolves` for it (`gh pr view --json body` checked); #9757 is OPEN after the PR is marked ready.
- [ ] AC-13 (doc): `git grep -n 'hcloud_token=' -- plugins/` is empty and `hetzner-setup.md` teaches the `read -rs` plus `export` form.
- [ ] AC-14 (repo ratchets): `PJ_TRIPLES` recomputed per the recipe (unchanged at 288, or updated with its exempt rows in the same commit); `fixture-relative-assert.test.sh` row-by-row green without a baseline edit (or the baseline regenerated in the same commit when S9 truly adds a row); `scripts/guard-vacuity-floor.test.sh` green.
- [ ] AC-15 (ADR + tracking): the ADR-280 addendum (about five lines) exists and states the rule, the guard, the blind spots and option B; the option-B issue is filed with `Ref #9757` and its number is in the PR body.

### Post-merge (operator)

- [ ] The umbrella note on #9757 is updated after merge (ship's post-merge step; item 2 ticked with a `_Landed: PR #<n>_` note and the pending-verification sentence). Verification of the live behavior rides the next rehearsal dispatch (the already-pending D10 evidence run): its phase-A plan succeeds without `No value for required variable`. No new dispatch is requested by this PR.

## Test Scenarios

1. The real tree, before Phase 2: S9 RED, four BAD records at the four workflow lines. After Phase 2: GREEN, zero BAD, counts at the floors.
2. Each of the two destroy step bodies executed under the stubs: a green row each; the four steps' export statically pinned in position.
3. The two destroy arms with the PRD token missing: the stub's 403 model fails the step loudly (the property that a teardown never silently skips).
4. Mutation batteries of both guards (above), each judged by its named reason.
5. Evasion shapes for the scanner: `-var=NAME=v`, `-var 'NAME=v'`, `-var "NAME=v"`, a continuation-split `-var`, a `bash -c "... -var ..."` payload, an array append, a markdown line, a second option on the same line, and a quoted `#` earlier on the line.
6. Must-pass inputs: `ssh_key_path`, `image_name`, `rehearsal_run_id`, `-var-file=<(...)`, commented lines, excluded paths.
7. Regression: the infra suite, c4 parity, the guard-vacuity floor, the fixture-relative-assert ratchet and the pipe guard stay green.

## Risks and Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** It is filled here.
- **Precedence under `--preserve-env`.** Correctness does not depend on it: `prd_terraform` carries an equal value, and ADR-241 measured that the environment value wins. The executed rows deliberately do NOT inject `TF_VAR_*` from the Doppler stub, so a dropped export is RED even though production would partly inherit.
- **The infra suite's text pins.** It pins the four reads and `! grep -qE 'ssh |ssh-key'` over the whole workflow. A YAML comment edit that contains `ssh ` or the registry-mirror read literal reddens `infra-validation.yml`. Run the suite read-only after the edit.
- **No live proof exists before a dispatch.** The workflow ships unfired. The hermetic executed rows are the substitute; the live proof rides the next D10 dispatch (post-merge note).
- **Merge conflicts.** PRs 10566 and 10546 edit manifest regions of the sweep script (about lines 917-930 and 4492) and 10546 also edits `fixture-relative-assert.baseline.txt`; the S9 tail append and the single `EXPECTED_TESTS` line are the only overlaps possible. Re-diff after either merges.
- **Failure mode of the change (no new observability surface needed).** A broken export fails `terraform plan`/`destroy` with `Error: No value for required variable` in the Actions log of a reviewer-gated dispatch; the teardown job's `always()` orphan assertion (Hetzner API, by label) already makes a leaked host fail loudly in the run that leaked it, and the scheduled drift sweep detects survivors. The guard is the observability for the regression class.
- **Plugin release side effect.** The doc line is under `plugins/soleur/**`, which fires `version-bump-and-release.yml`; the PR needs the usual semver label handling from `soleur:ship`. Do not bump version files by hand.
- **S9 over-reads.** A verb-free `-var` regex also matches other tools' `-var` flags (packer); that is the same exposure, so it fails closed. The failure message must name `file:line` and the remedy (`TF_VAR_<name>` in the step environment).
- **Constraints carried from the brief.** Never print a secret value or a hash of one into a plan, log or issue; no `-auto-approve` for Terraform; no `git stash`; no `git add -A` / `git add .`; hooks block `pgrep -f`, `sleep N &&` and `ps | awk`, so use `plugins/soleur/scripts/lib/proc.sh` and `Monitor` until-loops; run long suites detached with logs under `/var/tmp`, never `/tmp`.
- **Stated residuals of S9** (recorded in the ADR addendum): a credential reaching a non-matching `-var` name from a non-Doppler source (only identity row I1 covers the rehearsal file); concatenated or array-held values; YAML folded blocks; `-var` in `.ts`/`.tf`; the standing secret surface of two reads per run until option B lands (CTO dissent line, accepted as low).
