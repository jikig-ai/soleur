---
title: "fix(infra): bring doppler_project.infra_privileged's description under Doppler's 255-character cap, and add a PR-time guard"
type: fix
date: 2026-09-23
slug: fix-infra-privileged-doppler-description-cap
branch: feat-one-shot-infra-privileged-doppler-description
issue: 8209
closes: none
priority: p1
domain: engineering
brand_survival_threshold: none
pr: 8667
lane: cross-domain
---

# fix(infra): bring doppler_project.infra_privileged's description under Doppler's 255-character cap

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

Since the credential-tiering merge (2d974f8eef, PR #8563 for #8209), every push-triggered run of
`apply-web-platform-infra.yml` goes red at its `Terraform apply` step. The Doppler API rejects the
create of `doppler_project.infra_privileged` because its `description` is 273 characters and the API
caps the field at 255. The comment directly above the string already says so. As a result the Doppler
project `soleur-infra-privileged` does not exist, and ADR-241's O0 step is incomplete.

This plan does three things:

1. Shortens the description to 230 characters. The rationale stays in the header comment.
2. Adds a PR-time lint over every `description` on a `doppler_*` resource in every tracked `.tf`
   file. It runs under the required `test` context. No such guard exists today; the section below
   explains why nothing caught this one.
3. Says exactly how post-merge verification decides which ADR-241 O0 resources now exist.

The PR references #8209 and does not close it. #8209 still has operator steps O1 to O13 ahead of it.

## Deepen-Plan Findings (2026-09-24)

**Halt gates:** all passed, all run mechanically.

- 4.6 User-Brand Impact: present; `none` with a scope-out for the sensitive `apps/*/infra/` path.
- 4.7 Observability: 5 fields; `probe-verb-gate.sh 'python3 scripts/lint-doppler-description-length.py'` rc 0; `expected_output` is a literal.
- 4.8 PAT sweep: no hits.
- 4.10 Encryption Posture: all fields; `in_transit: []`.
- 4.11 `lint-guard-contract.py`: green.
- Not triggered:
  - 4.5 network: the only SSH token is the phrase "no SSH", and the plan does not change provisioner resources.
  - 4.55 downtime: no reboot, replace or lock.
  - 4.9 UI: no UI surface.

**Fan-out:** proportionate, not exhaustive. The plan is a one-string fix plus a roughly 60-line
lint. The panel was test-design-reviewer, security-sentinel, a prototype probe, and a
verify-the-negative sweep.

**Findings:**

1. **The design was prototyped against the real tree before any code.** A scratchpad copy of the
   Phase 2 lint (current-header attribution, blank-line skip, orphan fail-closed, raw bytes,
   unescaped-template regex, vacuity) was run over all 81 tracked `.tf` files.
   - It reported exactly one finding,
     `infra-privileged-environment.tf:73: doppler_project.infra_privileged description is 273 bytes`,
     and zero orphan or unmeasurable false positives.
   - With the replacement string substituted, it printed
     `OK: … 1 description(s) measured, max 230/255 bytes`.
   - The full-tree run took 0.04 s.
   - So the lint will not block unrelated PRs through the required `test` context.
2. **Joi's counting rule is now cited, not inferred.** Joi documents `string.max(limit, [encoding])`
   as "the maximum number of string characters", with byte-length counting only when an encoding
   is passed (<https://joi.dev/api/18.x.x#stringmaxlimit-encoding>, via Context7 `/websites/joi_dev`).
   Doppler's choice of encoding stays unknown. The raw-byte rule bounds both, as the plan already
   argues.
3. **A negative claim was verified.** "`terraform validate` rejects a duplicate attribute" was
   checked against the pinned `dopplerhq/doppler` 1.21.2 in a scratch root: `Error: Attribute
   redefined … "description" was already set`. Cutting the duplicate arm is safe.
4. **A negative claim was corrected.** "Terraform is the only writer of `description` in this repo"
   is true for tracked `.tf`. But `plugins/soleur/skills/provision-doppler/scripts/provision-doppler.sh`
   renders a `doppler_project` with `description = "Tenant project for ${SLUG}"` into **user** repos,
   and this lint cannot see it. It is out of scope (a user-repo artifact, and short by
   construction); recorded as a known limit under §Dependencies & Risks.
5. **Security-sentinel.** No P0 or P1 findings.
   - P2, applied: the description's "Read only via" overstated the control, because the
     workplace-scoped `DOPPLER_TOKEN_TF` can read the project until O10/O13. The new wording is "CI
     reads it via", 230 bytes.
   - P3, applied: control characters are stripped from printed paths and names, closing the
     `::`-command injection path.
   - Confirmed: the merge widens nothing (both Doppler addresses were already in `-target=`, and
     credentials are unchanged), and no post-merge read prints a secret value.
6. **Test-design-reviewer: 7.6/10 (B).**
   - Row 11 had the wrong verdict.
   - Two silent-skip holes were closed by new fail-closed arms: a one-line doppler block, and a
     column-0 `description`.
   - Six surviving mutants got rows: `%{`, mid-string `${`, the end anchor, trailing `//`, the
     no-argument scan set, and stop-at-first.
   - Rows 10 and 12 now assert the specific message, with compliant twins.
   - H4 asserts bounds rather than today's exact numbers.
   - All of it is recorded in §Plan Review Revisions.

## Research Reconciliation — Brief vs. Codebase

| Claim in the brief | Reality (measured) | Plan response |
|---|---|---|
| The description is 273 characters | `python3` over the literal: 273 characters, 273 UTF-8 bytes, 273 UTF-16 units (pure ASCII) | Replace it with a 230-character string (25 below the cap) |
| "Check whether a guard already exists" | None exists. `git grep` finds no suite or lint that measures a `.tf` `description`. `tests/scripts/test-infra-privileged-tier-census.sh` (#8209's own guard) has no length row, and nothing in `infra-validation.yml` has one either | Build one (Guard 1) |
| "Why did it miss this one" | The `dopplerhq/doppler` provider v1.21.2 (`resource_project.go`) declares `description` as a plain `Optional` `TypeString` with no `ValidateFunc`. `terraform validate` and the PR-time `terraform plan` both pass. Planning a *create* never calls the Doppler API; the 255 limit exists only in the API's own check (Joi-style message), which runs at `POST /v3/projects` during apply. The only control was a comment | The guard runs a static check before merge. The comment now points to the guard instead of standing in for one |
| "The ADR-241 O0 apply is incomplete" | Confirmed from the two failed apply logs (see §Post-merge verification). Run 35912754656 **did** create 5 resources and forget 4. It failed only on `doppler_project.infra_privileged`, and `doppler_environment.infra_privileged_prd` was skipped because it depends on the project. Run 35921899265 re-planned exactly the project, the environment and the #8202 perpetual pair | Post-merge verification checks each O0 resource separately, not just "apply is green" |
| Only `doppler_project` is at risk | Only two `doppler_*` resource types in the provider schema have a `description` attribute: `doppler_project` and `doppler_change_request_policy` (`terraform providers schema -json`). The repo uses only `doppler_project` (4 instances: 174, 220, 245, 273 characters) | The guard covers the whole `doppler_*` type family, so a future `doppler_change_request_policy` is covered without an edit |

## Research Insights

**Premise validation.** #8209 is OPEN (the eviction umbrella; this PR is Ref, not Closes). PR #8563
MERGED 2026-09-23T19:57:32Z as 2d974f8eef. #8610 is OPEN and adjacent (Terraform-managing the Tier-B
environment secrets); it is not this defect. #8590 is OPEN (web-platform drift) and #8202 is OPEN
("every web-platform apply re-applies the same 2 changes"). Both already cover the perpetual
`github_repository_environment_deployment_policy.web_platform_infra_apply_main` create
(`id=soleur:web-platform-infra-apply:0`) and the `cloudflare_bot_management.soleur_ai` in-place update
that appear in both failed plans. `doppler projects get soleur-infra-privileged --json` returns
`Could not find requested project 'soleur-infra-privileged'` (measured). The GitHub environment
`infra-privileged` exists with `custom_branch_policies=true` and one policy, `main` (id 60846728), and
has zero environment secrets (`gh api .../environments/infra-privileged/secrets` is empty).

**Property List (Phase 0.6b).**

- P1: the push apply on `main` no longer fails on the `doppler_project.infra_privileged` create.
- P2: a `description` over the Doppler cap on any `doppler_*` resource fails a required check before
  merge rather than at apply time on `main`.
- P3: the rationale the long string carried stays in the file.
- P4: after merge, it is known from evidence which O0 resources exist, not assumed.

**Cut List.**

- A tflint plugin or a community Terraform linter → P2 → no registry artifact checks vendor string
  limits (functional-discovery: none relevant). A roughly 150-line repo lint is cheaper than
  installing and pinning a new tool.
- A new required status context for the lint → P2 → the existing required `test` context (the
  `test-scripts` shard running `scripts/test-all.sh scripts`) already runs a registered `-live` lint on
  every PR and merge_group. Adding a ruleset context is out of scope.
- Extending `tests/scripts/test-infra-privileged-tier-census.sh` → P2 → that suite's property is Tier-B
  reachability. A length rule there would be scoped to one file, when the property covers every root.
- Registering the lint in `infra-validation.yml` → P2 → that workflow is not a required context; the
  required `test` job is the chokepoint. (Infra PRs also run `infra-validation`, but that is not
  load-bearing.)
- A full HCL tokenizer and an escape decoder → P2 → a line scan that attributes each `description` to
  the current column-0 header, measuring raw source bytes, covers the same members. It has far less
  parse surface that could misfire and block every PR through a required context (Phase 4.5 consult,
  plan review).
- `.tf.json` refusal, heredoc refusal, unclosed-block exit 2, duplicate-description check → P2 → zero
  `.tf.json` files are tracked; a heredoc description already fails as unmeasurable, and a heredoc in a
  `doppler_secret` value is legitimate; `terraform validate` rejects a duplicate attribute (plan
  review).

**Consult (Phase 4.5, strong-model, curated payload).** Two recommendations. (1) Drop the hand-written
tokenizer for a line-based scan. **Applied**, and the plan review simplified it further (see §Plan
Review Revisions). (2) Add headroom by
capping at 250, because Doppler's counting rule is unconfirmed. **Applied in a different form**: the
lint measures UTF-8 bytes, an upper bound on UTF-16 units, rather than an arbitrary margin. That
resolves the ambiguity the margin was hedging, and it still passes all four current strings (max 245
bytes).

**Relevant files.**

- `apps/web-platform/infra/infra-privileged-environment.tf`, anchored on
  `resource "doppler_project" "infra_privileged"`: the offending string and its comment.
- `apps/web-platform/infra/inngest-host.tf` (`resource "doppler_project" "inngest"`, 245 characters),
  `zot-registry.tf` (`doppler_project.registry`, 220), and `git-data-root-key/access.tf`
  (`doppler_project.git_data_root`, 174): the other three members. `inngest` sits 10 characters from
  the cap.
- `.github/workflows/apply-web-platform-infra.yml`: the `apply:` job (`environment: infra-privileged`),
  its `-target=doppler_project.infra_privileged` / `-target=doppler_environment.infra_privileged_prd`
  lines, `notify-apply-failure` (ops email via `.github/actions/notify-ops-email`), and
  `workflow_dispatch` with `apply_target: manual-rerun`.
- `scripts/test-all.sh`: the `run_suite "scripts/lint-infra-no-human-steps"` neighbourhood, and the
  `-live`/`-unit` pairing precedent (`scripts/lint-migrated-rule-ids-live` / `-unit`).
- `scripts/guard-vacuity-floor.test.sh`: `COVERED_DIRS='^(scripts/|…)'`. A new
  `scripts/*.test.sh` with a floor is mutation-tested automatically and needs **no** `PROMOTED_FILES`
  entry. The `PROMOTED_FILES` union instruction in the brief applies only if a rebase conflict
  touches that line anyway.
- `scripts/suite-shard-legs.tsv`: an unlisted label falls back to a `cksum`-hash leg
  (`_shard_selects`), so no manifest edit is needed.
- `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md` (row O0) and
  `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`
  (§Host-key pinning post-merge sequence, step 1 then step 3).

**Institutional learnings applied.**

- `2026-09-23-every-fix-i-shipped-to-close-a-defect-carried-the-same-defect.md`: "Comment-strip and
  brace-match every haystack." A commented-out `# description = "…"` inside a doppler block is not
  measured (the attribute regex requires `description` as the line's first token). Attribution comes
  from the current column-0 header rather than a fixed line window, and a `description` seen with no
  header fails closed. This defect is the class that learning names: a comment claimed a control
  that did not exist.
- `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`: `validate`/`plan` check the provider
  schema only, never vendor-side constraints.
- `2026-03-21-terraform-drift-dead-code-and-missing-secrets.md`: a failed apply is partial.
  Establish what was created from the apply log and the next plan, not from the exit code.
- `2026-04-03-cloudflare-dns-at-symbol-causes-terraform-drift.md` recommends "the next plan shows zero
  changes". Here that is **not** the bar, because of #8202's known perpetual pair. The bar is "no
  create for the two O0 Doppler addresses, and nothing outside the known pair".

**CLI verification (Phase 6 gate).** `gh run list` supports `-w/--workflow`, `-e/--event`,
`-c/--commit` (checked with `gh run list --help`, 2026-09-23). `doppler configs -p <project> --json` and
`doppler projects get <name> --json` were checked with `--help` and a live read against
`soleur-inngest` (prints `prd`).

**Skill description budget (Phase 1.8).** Not applicable: no `SKILL.md` `description:` edit.

## Problem Statement / Motivation

The push apply is how this root reaches production. While it is red, every merge touching
`apps/web-platform/infra/**` fails its apply, and the failure-email channel fires on each merge.
ADR-241 O0 cannot finish, so O2/O3 (populate the project, mint the read token) are blocked, and the
four privileged credentials stay branch-reachable in `prd_terraform`: the exposure #8209 exists to
remove. ADR-237's post-merge step 3 (the pin-publishing `git-data-host-replace` in
`git-data-luks-cutover-5274.md`) is gated on step 1: "every merge-triggered apply is `success`".

## Proposed Solution

### Phase 1: The string (one `.tf` edit)

In `apps/web-platform/infra/infra-privileged-environment.tf`, `resource "doppler_project" "infra_privileged"`:

```hcl
  # Doppler's API caps `description` at 255 (unchecked by the provider and by plan); enforced at PR
  # time by scripts/lint-doppler-description-length.py. Full rationale: the header comment above.
  description = "Tier B (#8209, ADR-241): credentials that write infra, read another tier's secrets, or reach third-party installations. CI reads it via DOPPLER_TOKEN_INFRA_PRIVILEGED on main-only environments. Operator-supplied; never in tfstate."
```

Measured: 230 characters, 230 UTF-8 bytes (pure ASCII). The wording is "CI reads it via", not
"Read only via" (security-sentinel, deepen pass). Until runbook steps O10/O13 evict and rotate the
workplace-scoped `DOPPLER_TOKEN_TF` that Terraform itself authenticates with, a token reachable
from any branch can also read this project, so "only" would overstate the control. The
`--- The Tier-B Doppler project ---` comment block gains one sentence naming that O2→O13 window. The dropped clause ("an environment secret on main-only
environments") moves into the `--- The Tier-B Doppler project ---` comment block as one sentence
naming `DOPPLER_TOKEN_INFRA_PRIVILEGED` as the only read path and where it is stored (a GitHub
**environment** secret on the four main-only environments). This is P3.

This is a **create**, not an update: the project does not exist, so no in-place description change is
planned against a live object.

Also correct the parenthetical `(see doppler_project.inngest)` in the existing comment. The inngest
resource carries a comment, not a mechanism, and pointing at it is how the cap stayed prose-only.

### Phase 2: The guard (RED first)

Write the unit suite first, from Guard 1's mutation matrix below, and watch it fail against a lint
that does not exist yet. Then write the lint.

**`scripts/lint-doppler-description-length.py`** (new, stdlib only, Python 3, about 60 lines). It
is **line-based, with no tokenizer and no escape decoder**. This was decided in the Phase 4.5 consult
and the plan review; see §Plan Review Revisions at the end of this plan.

- **Scan set.** With no arguments: `git ls-files -z -- '*.tf'` from `git rev-parse --show-toplevel`,
  which covers every Terraform root, not only `apps/web-platform/infra`. A failing `git` call exits
  non-zero on its own. With positional file arguments, it scans exactly those files (fixture mode).
- **Attribution by current header.** Walk each file line by line and track the current top-level
  header:
  - Any **non-blank** column-0 line that is not `}` and not a comment (`#`, `//`, `/*`) sets the
    header. Blank lines are skipped and never change it.
  - A column-0 `}` clears it.
  - A `description =` line (regex `^\s+description\s*=`) is measured only while the header matches
    `^resource "(doppler_[a-z0-9_]+)" "([^"]+)"`.
  - An indented `description =` line seen while **no** header is set fails closed:
    `FAIL: <path>:<line>: description outside any top-level block; run terraform fmt`. An
    unformatted nested `}` at column 0 would otherwise clear the header and silently hide the
    `description` after it.
  - Two more unformatted shapes fail closed rather than being skipped (test-design review, deepen
    pass):
    - A column-0 attribute line (`^[A-Za-z_][A-Za-z0-9_-]*\s*=`) is not a header; it fails with
      `attribute at column 0; run terraform fmt`.
    - A doppler header line with content after its `{` (a one-line block such as
      `resource "doppler_project" "x" { description = "…" }`, which `terraform fmt` allows) fails
      with `one-line doppler block; put description on its own line`.
    - Measured on the real tree: zero column-0 attribute lines and zero one-line doppler blocks, so
      neither arm can block an unrelated PR. `terraform fmt` is not a merge gate (`infra-validation` is not a required
    context and only runs on changed dirs), so the lint cannot rely on it.

  Nested blocks close at column 2 or deeper under `terraform fmt`, which `infra-validation.yml`'s
  `validate` job enforces with `terraform fmt -check -recursive`, so they do not change the header.
  A `#` / `//` comment line cannot match, because `description` must be the line's first token.
  `data` and `module` blocks are out of scope: the API field is only sent by a resource create or
  update. The file carries a one-line comment stating the `terraform fmt` column-0 assumption.
- **Measure.**
  - If the value is exactly one double-quoted literal (`"((?:[^"\\]|\\.)*)"`, optionally followed
    by whitespace and a `#` / `//` comment) containing no **unescaped** template sequence (regex
    `(?<!\$)\$\{` or `(?<!%)%\{`; the escaped forms `$${` and `%%{` are literal text), measure the
    **raw UTF-8 bytes
    of the source text between the quotes**. Every HCL escape is at least as long in source as its
    decoded form (`\"` is 2 bytes for 1, `\uXXXX` is 6 for at most 3, `$${` is 3 for 2). Raw source
    bytes are therefore an upper bound on the decoded UTF-8 bytes, which in turn bound UTF-16 units.
    A string that passes the lint passes whichever counting rule Doppler's Joi check uses. Joi counts
    `value.length` by default and bytes only when an encoding is set, and Doppler's choice is
    unconfirmed; both failed strings were pure ASCII, so the rejection does not settle it.
  - Anything else (a reference, a function call, interpolation, concatenation, a heredoc, a string
    continued over several lines) is **unmeasurable** and fails closed.
- **Verdicts and remediation text.** Exit 1 on any finding. Each finding prints one line plus a fix:
  - `FAIL: <path>:<line>: <type>.<name> description is <N> bytes (Doppler API cap 255). Shorten by <N-255> bytes; a non-ASCII character counts 2-4 bytes (an em dash is 3); put the rationale in a # comment above the attribute.`
  - `FAIL: <path>:<line>: <type>.<name> description is not a single-line string literal; cannot measure. Use one literal; var., interpolation and heredoc are unsupported by design.`
- **Log safety.** Paths and resource names are printed with C0/C1 control characters, `\x7f`, U+2028
  and U+2029 stripped. A tracked path containing a newline would otherwise start a CI log line with
  attacker text (`::add-mask::`, `::stop-commands::`). The description value itself is never printed,
  only its length (security-sentinel P3).
- **Vacuity.** Exit 1 when the scan found zero `doppler_*` resource headers
  (`FAIL: vacuous scan: no doppler_* resource found`), **or** headers but zero measured descriptions
  (`FAIL: vacuous scan: no description measured`). The two messages differ so each clause has its own
  row. A description regex that stops matching must not pass.
- **All findings, not the first.** Every finding in the scan is printed before exiting; the scan never
  stops at the first.
- **Success line.** Exit 0 prints
  `OK: <R> doppler_* resource(s) in <F> file(s); <D> description(s) measured, max <M>/255 bytes`.
- **One constant.** `DOPPLER_DESCRIPTION_MAX_BYTES = 255`, defined once, with a comment citing the
  API error text and runs 35912754656 / 35921899265.
- **Known limit, accepted.** `*.tf.json` is not scanned. None are tracked, and a JSON-syntax Doppler
  resource would bypass the lint.
- **Portability.** The lint needs only `python3` and `git`. The `.test.sh` uses only `bash`, `mktemp`,
  `printf` and `python3` (no `timeout`, `bc`, `sed -i` or `date -d`), so it runs on macOS as well.

**`scripts/lint-doppler-description-length.test.sh`** (new) is the mutation matrix below, as fixtures
in `mktemp -d` trees. It is driven by one data-driven helper, `row <name> <expected-exit>
<expected-substring> <fixture-file>...`, so adding an edge case means adding a line, not editing
shell. It does **not** source `plugins/soleur/test/test-helpers.sh` and installs its own
single `trap … EXIT` (the #8659 composed-trap hazard does not arise).

The floor follows the covered-bar shape `guard-vacuity-floor.test.sh` mutation-tests:

- **Counter.** A `cases` counter is incremented at each row's **call site**, never inside
  `pass()`/`fail()`. It is written literally as `cases=$((cases + 1))`, because
  `guard-vacuity-floor.test.sh`'s `counters_of` recognises only `X=$((X + 1))` and `((X++))`. A
  `((cases += 1))` would drop the suite from that guard's population silently: not FIRES, not
  UNCLASSIFIED, just absent.
- **Self-test.** Before any row, a helper self-test drives `pass` and `fail` once with output
  suppressed and exits 2 if either counter did not move. It then **resets `PASS` and `FAIL` to 0**, so
  the later `PASS + FAIL == cases` check is not broken by the self-test's own two calls.
- **Conservation, then floor.** After the rows, the conservation check `PASS + FAIL == cases` runs,
  then the floor. The bound is a literal on the line directly above a **multi-line**
  `if (( cases < MIN_CASES )); then` block, which emits
  `printf '[FATAL] assertion floor: only %d assertions ran (floor %d)\n'` then `exit 1`, never through
  a verdict helper (ADR-193).

**Registration** in `scripts/test-all.sh`, next to `run_suite "scripts/lint-infra-no-human-steps"`:

```bash
  # Doppler API caps doppler_* `description` at 255 characters; the provider schema does not, and
  # `terraform plan` cannot see it — a 273-char doppler_project.infra_privileged reddened every push
  # apply after #8563. -live asserts the real tree; -unit is the mutation matrix.
  run_suite "scripts/lint-doppler-description-length-live" python3 scripts/lint-doppler-description-length.py
  run_suite "scripts/lint-doppler-description-length-unit" bash scripts/lint-doppler-description-length.test.sh
```

Both labels land in the `scripts` group, so the required `test` aggregate carries them on every
`pull_request` and `merge_group`.

### Phase 3: Local verification before push

- `bash scripts/lint-doppler-description-length.test.sh` passes, with every RED row observed RED
  before the lint existed.
- `python3 scripts/lint-doppler-description-length.py` prints
  `OK: 79 doppler_* resource(s) in 30 file(s); 4 description(s) measured, max 245/255 bytes`. The counts are
  from 2026-09-23 (`git ls-files '*.tf' | xargs grep -hE '^\s*resource "doppler_' | wc -l` gives 79, in 30
  files); re-derive them rather than trusting these. The pre-fix tree prints a FAIL naming
  `infra-privileged-environment.tf` and `273`.
- `bash scripts/guard-vacuity-floor.test.sh` passes. The new suite is floor-bearing under
  `COVERED_DIRS` and must score `FIRES`; do not add it to `PROMOTED_FILES`.
- `terraform -chdir=apps/web-platform/infra fmt -check infra-privileged-environment.tf`, and the
  `infra-validation` `validate` job on the PR.
- `python3 scripts/lint-guard-contract.py <this plan>` passes.
- No `.ts` file is in scope. If one becomes necessary, `scripts/test-all.sh --capacity` runs before
  it is staged.

### Phase 4: Merge gate

Admit the merge only when every context in
`scripts/ci-required-ruleset-canonical-required-status-checks.json` (**24** contexts, counted
2026-09-23) is present **and** `success` on the exact PR head SHA. Enumerate them by name and compare
the count. Absence of red is not the test:

```bash
D="$(mktemp -d)"
jq -r '.[].context' scripts/ci-required-ruleset-canonical-required-status-checks.json | sort -u > "$D/req.txt"
wc -l < "$D/req.txt"                     # 24 at plan time; the gate derives it, never hard-codes it
gh api "repos/jikig-ai/soleur/commits/$HEAD_SHA/check-runs?per_page=100" --paginate \
  --jq '.check_runs[] | {name, conclusion, completed_at}' \
  | jq -rs 'group_by(.name) | map(max_by(.completed_at // "")) | .[] | select(.conclusion=="success") | .name' \
  | sort -u > "$D/green.txt"   # LATEST run per name: an older success must not mask a failed re-run
comm -23 "$D/req.txt" "$D/green.txt"     # must print nothing
[ "$(comm -12 "$D/req.txt" "$D/green.txt" | wc -l)" -eq "$(wc -l < "$D/req.txt")" ]   # positive count, derived, not a literal
```

All 24 contexts carry an `integration_id` (15368 = GitHub Actions, 57789 = CodeQL), so all 24 report
as check runs. If `comm` names a context, it is missing or not green, and the merge waits.

### Phase 5: Post-merge verification

See §Post-merge verification below. It runs after merge, read-only, from the pipeline.

## Post-merge verification (what the failed applies left un-created)

**What the two failed runs already did.** Both were read from `gh run view <id> --log --job <apply>`.

| O0 resource (runbook row O0) | Run 35912754656 (2d974f8eef) | Run 35921899265 (79e84ea1a0) | State now |
|---|---|---|---|
| `github_repository_environment.infra_privileged` | Creation complete `[id=soleur:infra-privileged]` | not in plan | **exists**: live read `custom=true`, policies `["main"]` |
| `github_repository_environment_deployment_policy.infra_privileged_main` | Creation complete `[id=soleur:infra-privileged:60846728]` | not in plan | **exists** (policy id 60846728, `main`) |
| `github_repository_environment.workspaces_luks_cutover` (update) + `…workspaces_luks_cutover_main` | Modifications complete; policy `[id=…:60846726]` | not in plan | **exists** |
| `cloudflare_r2_bucket.terraform_state_privileged` | Creation complete `[id=soleur-terraform-state-privileged]` | not in plan (refreshed from state, no create planned) | **exists** |
| forgets: `doppler_secret.github_app_id`, `doppler_secret.github_app_private_key`, `doppler_service_token.write`, `github_actions_secret.doppler_token_write` | planned as "will no longer be managed" | zero "no longer be managed" lines | **done** (forgotten, not destroyed) |
| `doppler_project.infra_privileged` | **Error**: `"description" length must be less than or equal to 255 characters long` | same error | **absent** (live `doppler projects get` 404) |
| `doppler_environment.infra_privileged_prd` | not attempted (depends on the project) | not attempted | **absent** |
| `github_repository_environment_deployment_policy.web_platform_infra_apply_main` | "Creation complete" with `id=…:0` | re-planned, "Creation complete" again with `:0` | perpetual create, **#8202 / #8590**, not this defect |

**Expected plan on the fix-merge push apply:** `Plan: 3 to add, 1 to change, 0 to destroy.` The 3 adds
are `doppler_project.infra_privileged`, `doppler_environment.infra_privileged_prd`, and the #8202
`web_platform_infra_apply_main` recreate. The change is #8202's `cloudflare_bot_management.soleur_ai`.
If another infra PR merges first, its own resources add to this count. Compare against the address
list, not the number.

**Reads, all read-only, no SSH, all agent-executable:**

1. **The `apply` job (not just the run) for the merge commit concluded `success`:**
   - `gh run list -w apply-web-platform-infra.yml -e push -c <merge-sha> --json databaseId --jq '.[0].databaseId'`
     gives the run id.
   - `gh run view <run-id> --json jobs --jq '.jobs[] | select(.name=="apply") | "\(.conclusion) \(.databaseId)"'`
     must print `success <job-id>`.
   - The run conclusion alone is a proxy. When preflight's kill switch (`[skip-web-platform-apply]`,
     `skip=true`) fires, `apply` is **skipped** and the run is still `success`.
   - The job id feeds read 2.
   - While the job is `in_progress`, wait with a Monitor until-loop
     (`hr-monitor-not-run-in-background-for-polling`), not background sleeps.
   - This is also `git-data-luks-cutover-5274.md` step 1's read. Every push apply created **after**
     the fix merge must be `success`. Runs 35912754656 and 35921899265 stay in that runbook's
     `-L 5` window until three more push applies land. They predate the fix and are the defect
     itself, not a regression.
2. **Its plan section contains exactly the expected addresses, with no destroy or replace:**
   `gh run view <run-id> --log --job <job-id> | grep -E '# .* (will be|must be)|Plan: '`.
   - The creates are `doppler_project.infra_privileged` and `doppler_environment.infra_privileged_prd`,
     plus the #8202 pair and any concurrently merged PR's own addresses.
   - No line names `doppler_secret.github_app_(id|private_key)`. They were forgotten in run
     35912754656, so their absence also re-reads runbook row O0's U1(b) gate.
3. **The project and its config exist:**
   `doppler projects get soleur-infra-privileged --json | jq -r .name` prints
   `soleur-infra-privileged` (the brief's own check; before the fix it errors with
   `Could not find requested project`), and
   `doppler configs -p soleur-infra-privileged --json | jq -r '.[].name'` prints `prd`, which proves
   `doppler_environment.infra_privileged_prd` was created too.
4. **The GitHub O0 resources the first run created are still in place** (the brief asks to re-read
   them). This is one command over the four Tier-B environments:
   `for e in infra-privileged web-platform-infra-apply inngest-cutover workspaces-luks-cutover; do gh api repos/jikig-ai/soleur/environments/$e --jq '"\(.name) custom=\(.deployment_branch_policy.custom_branch_policies)"'; gh api repos/jikig-ai/soleur/environments/$e/deployment-branch-policies --jq '[.branch_policies[].name]'; done`.
   Each must print `custom=true` and `["main"]`. All four did pre-merge (read 2026-09-24).

Idempotence (no second create for either Doppler address) is **not** a separate read. It is shown by
the next push apply's plan whenever one lands. A `manual-rerun` dispatch just to prove it would be a
separate production-credentialed apply that the merge click did not authorize, so the plan does not
prescribe one.

`DOPPLER_TOKEN_INFRA_PRIVILEGED` staying unset on `infra-privileged` is **expected**. It is O3's
output, after O2 fills the project this PR finally creates. It is not a post-merge failure here.

## Technical Considerations

- **Does merging this alone mutate production? Yes.** `apply-web-platform-infra.yml` fires on push to
  `main` for `apps/web-platform/infra/**`. `doppler_project.infra_privileged` and
  `doppler_environment.infra_privileged_prd` are in its `apply` job's `-target=` allowlist, so the
  merge click creates the `soleur-infra-privileged` project and its `prd` environment in the Doppler
  workplace. The merge is the per-command authorization for that create
  (`hr-menu-option-ack-not-prod-write-auth`). It is the O0 create ADR-241 already authorized in
  #8563, and it writes no secret. The PR body's first line states this.
- **No new infrastructure.** The four O0 resources are already declared and targeted. This PR changes
  one string literal, and no resource address or `-target=` line. `terraform-target-parity.test.ts`
  and the tier census are unaffected.
- **Security.** The description is free text and not a secret. The lint reads only tracked `.tf`
  files, and execution is argv-only (`git ls-files -z`), with no shell interpolation of paths.
- **Performance.** The lint reads 81 tracked `.tf` files line by line (30 of them contain `doppler_*` resources); target under 1s. The `-unit` suite runs
  about 20 small fixture invocations.
- **NFR register.** No NFR row changes. CI reliability improves by one guard.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly: no app, API or data path changes.
  The indirect cost is that the Tier-B cutover stays blocked. The GitHub App private key that every
  connected user's repo access depends on stays reachable from branch workflows via `prd_terraform`
  longer. That is the status quo #8209 exists to end, not an exposure this PR creates.
- **If this leaks, the user's data is exposed via:** no new vector. The only artifact is a public-safe
  project description; no credential, token or state value is added (the file's own
  `WHY THIS FILE HOLDS NO SECRET` contract is preserved).
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the diff edits one free-text Doppler project description and adds a static lint; it touches no user data, auth, runtime or credential path, and creates no secret.`

## Observability

```yaml
liveness_signal:
  what: conclusion of the push-triggered apply-web-platform-infra.yml `apply` job, plus the notify-apply-failure ops email on any non-green run
  cadence: per push to main touching apps/web-platform/infra/**
  alert_target: ops email via .github/actions/notify-ops-email
  configured_in: .github/workflows/apply-web-platform-infra.yml (jobs apply, notify-apply-failure)

error_reporting:
  destination: required `test` check (PR time) and the ops email from notify-apply-failure (post-merge)
  fail_loud: "FAIL: <path>:<line>: doppler_<type>.<name> description is <N> bytes (Doppler API cap 255)" in the test-scripts shard log, exit 1

failure_modes:
  - mode: a doppler_* description over 255 bytes is committed
    detection: scripts/lint-doppler-description-length-live reds the required `test` aggregate on the PR
    alert_route: PR author and reviewer, via the blocked merge
  - mode: a description written as an expression the lint cannot measure (reference, interpolation, heredoc)
    detection: the lint fails closed with "cannot measure" at PR time
    alert_route: PR author via the required `test` check
  - mode: the lint silently scans nothing (glob, git or member-regex regression)
    detection: exit 1 on zero doppler_* resources found; the -unit floor and guard-vacuity-floor FIRES scoring
    alert_route: required `test` check
  - mode: the Doppler API rejects the create for another reason at apply time
    detection: push apply goes red; notify-apply-failure resolves the failing step
    alert_route: ops email

logs:
  where: GitHub Actions run logs (ci.yml test-scripts shards; apply-web-platform-infra.yml apply job)
  retention: 90 days (repo artifact-and-log-retention setting, read 2026-09-23)

discoverability_test:
  command: python3 scripts/lint-doppler-description-length.py
  expected_output: "OK"
```

## Encryption Posture

```yaml
# No NEW store and no NEW connection. The plan edits an existing, already-declared store's free-text
# label. The store class is the ledger's existing doppler.secrets row; restated here because the
# .tf edit trips the Phase 2.11 detector.
at_rest:
  - store: doppler_project.infra_privileged (soleur-infra-privileged/prd), within ledger row doppler.secrets
    mechanism: provider-managed:doppler-aes256-gcm
    evidence: scripts/encryption-posture-ledger.json row "store": "doppler.secrets" (Doppler security documentation, https://www.doppler.com/security, retrieved_on 2026-07-24)
    defends_against: physical-media compromise of Doppler's secret storage
    does_not_defend: a leaked DOPPLER_TOKEN_INFRA_PRIVILEGED or a workplace token that can read the project; the description itself is plaintext metadata by design and must never hold a secret
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:named SOC 2 attestation formalization pending; tracked #6911"
in_transit: []   # no new connection; the existing Terraform doppler provider -> Doppler API path is unchanged
```

## Guard Contract

### Guard 1 — Doppler description length lint

**Property.** No tracked Terraform `resource` block of any `doppler_*` type carries a `description`
whose literal's **raw source** exceeds 255 UTF-8 bytes, or one the lint cannot measure statically.
Raw source bytes bound the decoded UTF-8 bytes, which bound UTF-16 units, so the property implies
the API cap under either counting rule Doppler's Joi check might use.

**Assembly.** The chokepoint is the set of tracked Terraform files, `git ls-files -- '*.tf'` from the
repo top level. That covers every root: `apps/web-platform/infra/`, its sub-roots
(`git-data-root-key/`, `rung2-rehearsal/`), `infra/github/` and any future `apps/*/infra/`. Within a
file, a `description` line is a member when the current column-0 header is a
`resource "doppler_<t>" "<n>"` line; a column-0 `}` clears the header (the `terraform fmt` shape).
There is one enforcement call site, the `-live` registration in `scripts/test-all.sh` (scripts group,
then the required `test` context). The `-unit` suite is its harness. No other path sends a Doppler
description: `data`/`module` blocks and the CLI are out of scope, and Terraform is the only writer of
`description` in this repo. `*.tf.json` is an accepted blind spot (zero tracked).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Regression: a fixture `doppler_project` whose description is the original 273-character string | RED (exit 1, message names 273) |
| 2 | Boundary: the same resource at exactly 256 bytes | RED |
| 3 | Boundary pair: exactly 255 bytes, followed by a trailing `# comment` after the closing quote | PASS |
| 4 | Second member: a file with a compliant `doppler_project` first, then a 256-byte second `doppler_project` | RED, naming the second |
| 5 | Second file: a compliant file plus an over-cap file in the same scan | RED, naming the second file |
| 6 | Type family: an over-cap `doppler_change_request_policy` (kills a regex narrowed to `doppler_project`) | RED |
| 7 | Unmeasurable: (a) `description = var.d`; (b) `description = "${var.a} x"`; (c) `description = "x ${var.a}"` (mid-string, kills a `startswith` check); (d) `description = "%{ for i in range(50) }xxxxxxxx%{ endfor }"` (kills dropping the `%{` alternative); (e) `description = "a" != "" ? var.long : "b"` (kills dropping the literal's end anchor) | RED ×5 ("cannot measure") |
| 8 | Multibyte: 254 ASCII characters plus one em dash (255 characters, 257 bytes) | RED (the byte rule, not a character count) |
| 9 | Own dispatch: (a) a scan with zero `doppler_*` headers (only `variable`/`github_*` blocks); (b) doppler headers but zero `description` lines | RED ×2, each asserting its own message (`no doppler_* resource found` / `no description measured`) |
| 10 | Reorder: an over-cap `description` placed **after** a nested `lifecycle { … }` block whose `}` sits at column 2; plus its compliant twin | RED asserting `<type>.<name> description is 256 bytes` (not the orphan or vacuity message); twin PASS with `1 description(s) measured` |
| 11 | Escapes counted raw: 255 decoded bytes containing one `\"` (256 raw bytes); twin: 254 decoded bytes with one `\"` (255 raw) | RED (kills a lint that counts decoded bytes); twin PASS |
| 12 | Blank line: an over-cap `description` preceded by `name = …` and a blank line inside the doppler block; plus its compliant twin | RED asserting the `256 bytes` message; twin PASS with `1 description(s) measured` |
| 13 | Unformatted shapes beside a compliant resource: (a) a column-0 nested `}` inside a doppler block, then an over-cap `description`; (b) an over-cap `description =` at **column 0** inside a doppler block; (c) a one-line `resource "doppler_project" "x" { description = "<300 B>" }` | RED ×3, with `outside any top-level block` / `attribute at column 0` / `one-line doppler block` respectively, never a silent skip |
| 14 | Escaped template and trailing `//`: (a) `description = "a $${literal} b"` under the cap; (b) a 255-byte literal followed by `// c` | PASS ×2 (measured, not rejected) |
| 15 | Scan set, no-argument mode: in a `git init` temp repo, an over-cap doppler resource at `infra/github/x.tf`, lint run with **no arguments** from a subdirectory | RED naming `infra/github/x.tf` (kills narrowing `git ls-files` to one root or dropping `--show-toplevel`) |
| 16 | Two findings in one scan: two over-cap resources in two files | RED, output contains **both** FAIL lines (kills stop-at-first) |

**Harness rows:**

| # | Row | Expected |
|---|---|---|
| H1 | Must-PASS, not canonical: a 600-byte `variable "x" { description = … }` and a 400-byte `github_repository_environment`-shaped description beside a compliant `doppler_project` | PASS (non-doppler headers are ignored), and `1 description(s) measured` |
| H2 | Must-PASS: a commented-out `# description = "<300 bytes>"` inside a doppler block whose real description is compliant | PASS |
| H3 | Suite edits (delete a row's call; neuter `pass()`/`fail()`) | the floor FIRES. This is **not** a suite row: `scripts/guard-vacuity-floor.test.sh` applies these mutants to every floor-bearing `scripts/*.test.sh` and must score this suite FIRES |
| H4 | Live: the `-live` registration over the real tree | PASS after Phase 1, asserting bounds rather than exact numbers (D ≥ 4 descriptions, M ≤ 255), so a legitimate description edit does not break it; RED on the pre-fix tree naming `infra-privileged-environment.tf` |

**Anchor.** The cap constant (255) and the lint live in the same reviewable diff, so one PR could raise
both. The external anchor is Doppler's API: a weakened constant does not make an over-cap string
apply. It moves the failure back to the push apply, where `notify-apply-failure` emails ops, which is
the state this PR leaves. Row 3 plus row 2 pin the boundary, and the PR diff to
`DOPPLER_DESCRIPTION_MAX_BYTES` is the review surface.

## Acceptance Criteria

### Pre-merge

- [ ] AC1: `python3 scripts/lint-doppler-description-length.py` exits 0 on the branch tree and prints
      `4 description(s) measured, max 245/255 bytes`. On the pre-fix tree (`git stash`-free: run it
      against `git show origin/main:apps/web-platform/infra/infra-privileged-environment.tf` saved to
      a temp file, in fixture mode) it exits 1 naming `273`.
- [ ] AC2: in `apps/web-platform/infra/infra-privileged-environment.tf`, the comment above
      `description` names `scripts/lint-doppler-description-length.py` and no longer says
      `see doppler_project.inngest`. The `--- The Tier-B Doppler project ---` comment block names
      `DOPPLER_TOKEN_INFRA_PRIVILEGED` as the only read path and says it is a GitHub **environment**
      secret on main-only environments, plus one sentence naming the O2→O13 window in which the
      branch-reachable `DOPPLER_TOKEN_TF` can still read the project.
- [ ] AC3: every Guard 1 row (1–16, H1, H2, H4) is a `row` call in
      `scripts/lint-doppler-description-length.test.sh`, and the suite exits 0. RED rows were observed
      RED before the lint file existed (recorded in the work log).
- [ ] AC4: `scripts/test-all.sh` contains exactly one `run_suite
      "scripts/lint-doppler-description-length-live"` and one `…-unit` line, and CI's `test-scripts`
      shard logs show both labels PASS on the PR head.
- [ ] AC5: `bash scripts/guard-vacuity-floor.test.sh` exits 0, **and** its `=== derived population ===`
      block shows `covered (mutation-arm)` and `floor fires` each exactly **one higher** than the same
      run on `origin/main`, with `floor does NOT fire` and `mutant not constructible` unchanged (H3).
      The guard prints counts, not names, so the delta is the check. An exit 0 alone would also hold
      if the suite had dropped out of the population (for example through a counter form
      `counters_of` does not recognise).
      `PROMOTED_FILES` is unchanged by this PR, or, if a rebase conflict touches it, resolved as the
      union of both sides.
- [ ] AC6: `python3 scripts/lint-guard-contract.py` on this plan and markdownlint on the plan and
      `tasks.md` both exit 0.
- [ ] AC7: the infra-validation `validate` job (it runs `terraform fmt -check -recursive`) is green on
      the PR head.
- [ ] AC8: the PR body's first line states that merging creates the `soleur-infra-privileged`
      Doppler project and its `prd` environment through the push apply, and the body says
      `Ref #8209`, not `Closes`.
- [ ] AC9: every context in `scripts/ci-required-ruleset-canonical-required-status-checks.json` is a
      `success` check run **by name** on the exact head SHA. The Phase 4 block's `comm -23` prints
      nothing, and its derived positive-count comparison holds.

### Post-merge (read-only; the pipeline performs them)

- [ ] AC10: read 1 prints `success <job-id>` for the `apply` job of the push run on the merge SHA.
- [ ] AC11: read 2's address list is exactly the expected set, with no destroy or replace and no
      `doppler_secret.github_app_*` line.
- [ ] AC12: read 3 prints `soleur-infra-privileged` and `prd`.
- [ ] AC13: read 4 prints `custom=true` and `["main"]` for all four environments.
- [ ] AC14: a comment on #8209 links the green run, lists the O0 state in one line per resource, and
      says O2 (populate) is unblocked and ADR-237 step 1 holds for every post-fix push apply.

## Test Scenarios

- Given the pre-fix `infra-privileged-environment.tf`, when the lint runs on it, then it exits 1 and
  names `273` (AC1, row 1).
- Given the post-fix tree, when the `-live` registration runs, then it exits 0 with 4 descriptions
  measured (H4).
- Given each Guard 1 row, when the `-unit` suite runs, then each row's verdict holds and the suite ends
  with `PASS + FAIL == cases` and `cases >= MIN_CASES`.
- Given the merged fix, when the push apply runs, then it concludes `success` and the Doppler project
  and its `prd` config exist.
- Regression: given a future PR that pastes a 256-byte description on any `doppler_*` resource in any
  root, when CI runs, then the required `test` context is red before merge.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. (Product/UX: no UI-surface
file in Files to Edit/Create; no mechanical override. Legal: no new processing, and ADR-241's
compliance entries already landed with #8563.)

## Files to Edit

- `apps/web-platform/infra/infra-privileged-environment.tf`: the description string and the two
  comment edits (Phase 1).
- `scripts/test-all.sh`: two `run_suite` registrations (Phase 2).

## Files to Create

- `scripts/lint-doppler-description-length.py`
- `scripts/lint-doppler-description-length.test.sh`

## Open Code-Review Overlap

Two open scope-outs mention `scripts/test-all.sh`:

- #8659 (33 suites replace test-helpers' composed EXIT trap): **Acknowledge.** The new suite does not
  source `test-helpers.sh`, so it cannot join that population. The fix belongs to #8659's own
  follow-through.
- #7942 (two `*.mutation.sh` batteries run in no gate): **Acknowledge.** It is a different file set.
  This PR registers its own suite explicitly, which is the remedy #7942 asks for, for its own files.

No open scope-out names `infra-privileged-environment.tf`.

## Dependencies & Risks

- **Merge-order.** Every infra merge before this one also reds its apply on the same resource. That
  is harmless and expected, but read 2's address list may include those PRs' resources.
- **A second hidden vendor limit.** The project name `soleur-infra-privileged` or the environment
  `slug`/`name` could hit another server-side check on first create. They mirror the
  `soleur-inngest` / `doppler_environment.inngest_prd` precedent, which applied cleanly. If the fix
  apply reds on a different Doppler error, that is a new finding for a follow-up PR, not a retry.
- **Known limit: user-repo Doppler projects.** `provision-doppler.sh` renders
  `description = "Tenant project for ${SLUG}"` into a user's repo. That text is outside this repo's
  `git ls-files`, so the lint does not cover it. Its length is 19 bytes plus the slug, well under the
  cap for any plausible slug; no action.
- **#8202 noise.** The perpetual pair makes "zero-diff after apply" an unusable bar. AC11 names
  addresses instead.
- **Rollback.** A revert restores the 273-character string and the red apply; nothing is destroyed,
  because the project does not exist yet. After the project exists, `prevent_destroy` and runbook row
  O0's rollback note govern it.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| A `lifecycle { precondition { condition = length(local.desc) <= 255 } }` per resource | It would fail at plan time, before any partial apply, which is better than today. But it is per member: each of the four resources needs its own local and precondition, and a fifth resource without one is uncovered. It also fires only in `terraform plan`, and the PR-time plan job (`infra-validation.yml` `plan`) is not a required context. The static lint covers the type family in every root under a required context |
| `check {}` block / tflint custom rule | tflint is not in CI; adding and pinning a new tool is out of scope for a P1 unblock (Cut List) |
| Trimming only, no guard | The comment was already present and did not work. Without a guard the next near-cap string (`inngest` is at 245) repeats this |

## Plan Review Revisions

The panel was DHH, Kieran and code-simplicity, plus the relevance-gated CTO (devex lens). The
threshold is `none`, so the 3-agent baseline applied. Every applied change is Mechanical. None drops
scope the brief asked for.

| Source | Finding | Disposition |
|---|---|---|
| DHH P1, Simplicity | Drop the HCL escape decoder: raw source bytes bound the decoded bytes | Applied (Phase 2 *Measure*, Guard 1 row 11) |
| DHH P1, Simplicity | Replace block-end tracking with a current-header variable; cut `.tf.json` / heredoc / unclosed-block / duplicate arms | Applied (Phase 2, Cut List) |
| DHH P1, Simplicity | Cut the matrix from about 20 rows | Applied, to 14 + H1/H2/H4. Kept: row 4 (second member after a compliant first, required by Phase 2.12), row 6 (kills a regex narrowed to `doppler_project`), row 10 (reorder) |
| Simplicity | The vacuity floor must also cover zero *measured descriptions* | Applied (Phase 2 *Vacuity*, row 9b) |
| Kieran P0 | Guard Contract contradicted the revised Phase 2 (exit-2 rows, H1, "decoded", constant name, dangling section reference) | Applied: Property, Assembly, matrix, Anchor rewritten; this section added |
| Kieran P1 | Blank lines inside a block would clear the header | Applied (blank lines skipped; row 12) |
| Kieran P1 | With `fmt` not a merge gate, a column-0 nested `}` hides the next `description` | Applied (orphan-`description` fail-closed; row 13) |
| Kieran P1 | The self-test broke `PASS + FAIL == cases` | Applied (counters reset after the self-test) |
| Kieran P1 | `counters_of` only sees `X=$((X + 1))` / `((X++))` | Applied (counter form pinned; AC5 checks the FIRES delta, not exit 0) |
| Kieran P2 | `$${` contradicted "no `${`" | Applied (unescaped-sequence regex; row 14) |
| Kieran P1 | Read 1 read the run conclusion, a proxy that is `success` when `apply` is skipped | Applied (job-level read) |
| Kieran P2 | Merge gate could pass on an older success masking a failed re-run | Applied (latest run per name) |
| CTO P2 | FAIL messages must say how to fix | Applied (remediation text in both FAIL lines) |
| CTO P2 | The idempotence read needed an unauthorized prod dispatch | Applied (dropped as a separate read) |
| CTO P3 | Data-driven fixture helper | Applied (`row` helper) |
| DHH P1 | Commit the string fix separately, first, so it can ship alone if the guard stalls | Applied (tasks Phase 2 is the string commit; the guard follows) |
| DHH P2, Simplicity | Delete the Phase 4 merge-gate script ("the ruleset already does this") | **Kept.** The brief explicitly requires counting required contexts by name on the exact head SHA. The count is now derived, not a literal |
| DHH P2, Simplicity | Cut the Encryption Posture section | **Kept, minimal.** deepen-plan Phase 4.10 halts mechanically on a `.tf` edit without it |
| DHH P2, Simplicity | Cut reads 6 and 8 and the O0 table | **Kept, merged.** The brief asks to re-read which O0 resources remain. Reads are now 4, and the table is the answer |
| Deepen: security-sentinel P2 | "Read only via DOPPLER_TOKEN_INFRA_PRIVILEGED" overstates the control while the workplace-scoped `DOPPLER_TOKEN_TF` can still read the project (until O10/O13) | Applied: "CI reads it via …" (230 bytes) plus a header-comment sentence on the O2→O13 window |
| Deepen: security-sentinel P3 | Tracked paths with newlines could inject `::` workflow commands | Applied (control characters stripped from printed paths and names) |
| Deepen: test-design-reviewer | Row 11's verdict was wrong; one-line blocks and column-0 `description` were silent skips; rows 10/12 could pass through the wrong fail path; `%{`, mid-string `${`, end-anchor, `//`, scan-set and stop-at-first mutants survived; H4 pinned exact numbers | Applied (rows 7, 9–16 and H4 rewritten; two new fail-closed arms, both measured at zero hits on the real tree) |
| CTO P3 | Settle Doppler's counting rule with a throwaway 255-multibyte project | **Not taken.** It is a Doppler workplace write outside this fix; the byte rule makes the answer unnecessary |

## Addendum — 2026-09-24 (review and sibling PR)

- **The string fix shipped in a sibling PR.** #8668 (another session) merged the same one-line fix
  (231 characters) at 04:13Z. Its own push apply was cancelled by concurrency, and push apply
  35963237090 (on `ca83c8edf0`) created `doppler_project.infra_privileged` and
  `doppler_environment.infra_privileged_prd`: plan `3 to add, 1 to change, 0 to destroy`, SSH apply
  `0 added, 0 changed, 0 destroyed`, every step `success`. §Post-merge verification's reads 1-4
  are therefore discharged by that run, not by this PR's merge. This PR's own merge apply is an
  in-place `~ update` of the description (230-byte "CI reads it via" wording), never a replace.
- **Four failed push applies, not two:** 35912754656, 35921899265, 35927849285, 35951193547.
- **The lint was rewritten during review.** A panel showed five `terraform fmt`-clean layouts
  (and three fmt-fixable ones) defeating the line-based design this plan specifies. The lint is
  now a bracket-depth tokenizer; §Proposed Solution Phase 2's "line-based, no tokenizer" and its
  column-0 fail-closed arms are superseded. Measurement is max(raw bytes, UTF-8 bytes of the
  NFC-normalised decoded value), the lint's own failures exit 2, and `*.tf.json` fails closed.
  The suite has 61 rows; the live check lives only in the `-live` registration (H4 left the unit
  suite).
