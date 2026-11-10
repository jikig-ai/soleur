# bot-pr-with-synthetic-checks — changelog

Composite-action behavior log. No test runner exists for composites in this
repo, so backward-compat is asserted by reading existing callers and verifying
their input set is unchanged. See `action.yml` for the live contract.

## v4 (2026-10-11)

Issue: #9454 (item 4). Decision: ADR-285.

**Contract change: `pr-token` is a new REQUIRED input.** The PR is authored, pushed and armed for
auto-merge under `pr-token`, a `soleur-infra` App installation token the caller mints in its own
job with `./.github/actions/mint-infra-app-token`. `gh-token` keeps one job: it posts the
synthetic check-runs, because the rulesets match `integration_id 15368` (the workflow token).
A PR authored and armed as the workflow token had its own runs held for approval and its merge
queue entry received no `merge_group` runs (PR 10013, 2026-10-11).

- The step now refuses, before the no-change exit, an empty or non-bearer `pr-token`, one equal to
  `gh-token`, and a non-main ref. It copies both tokens into unexported variables and unsets them
  (and `GH_TOKEN`), so the gitleaks download and the repo lint scripts never inherit a credential.
  There is no step-level `GH_TOKEN`: PR writes go through `gh_app`, check-runs through `gh_gate`,
  and a bare `gh` call fails.
- `git push` carries the App token as a per-command `http.https://github.com/.extraheader`
  (the `actions/checkout` form), never on an argument list. The caller's checkout must therefore use
  `persist-credentials: false`, or git sends two Authorization headers.
- The `cla-check` synthetic summary is author-neutral.
- The commit identity is the App's too (`soleur-infra[bot]`, the pair the pin-bump script pins), so the
  commit author, the pusher and the PR author are one identity; `cla.yml` allowlists it. Before this
  version the commit author was `github-actions[bot]`.
- The step refuses a non-regular-file path before staging, and refuses a push when the date-suffixed
  branch already exists on origin (a same-day re-run), naming the delete command in the error.
- The single in-repo caller (`weakness-miner.yml`) moves in the same change; the static guard in
  `tests/scripts/test-weakness-miner.sh` evaluates every caller and hash-pins this composite's
  run body, env, shell, inputs and defaults: an edit to any of them re-pins `WM_COMPOSITE_PIN` there in the same
  PR. The earned-green blocks, the allowlist and the off-main refusal are unchanged.

## 2026-11-10 — lint-cve-safe-status earned green (#12348)

The staged-diff lint chain gains a `python3 -I scripts/lint-cve-safe-status.py --paths` run over the staged paths,
after `git add` and before the push and the check-run POST (`-I` stops python3 reading `PYTHON*` variables, user
site-packages and the script's own directory): an advisory id beside a listed status word (ADR-322), or a file the lint
refuses to read, fails the step before the PR is created. The lint scans every tracked `knowledge-base/` file as the
`guards-ruleset` member `cve-safe-status` and in the `test` sweep, and `weakness-digest.md` sits inside that surface,
so both synthetic greens are earned rather than argued. `--paths` takes `knowledge-base/` paths only. The run body
changed, so `WM_COMPOSITE_PIN` in `tests/scripts/test-weakness-miner.sh` moved `5f6a943e…71c1` → `8d799113…3758`
in the same PR (ADR-285). Pinned by `plugins/soleur/test/required-checks-canonical-parity.test.sh` Test 11.

## 2026-11-08 — retry the pinned gitleaks download (Ref #10479)

The gitleaks install `curl` gains `--fail --retry 5 --retry-all-errors` (the same three flags the six other pinned
gitleaks copies and the actionlint install got in the same PR; the `sha256sum -c` check is unchanged). Behaviour is otherwise identical; the retry
budget is about 31 s, which rides out a transient release-CDN 5xx and not an hour-long outage. The run body changed, so
`WM_COMPOSITE_PIN` in `tests/scripts/test-weakness-miner.sh` moved `5f736544…40fe` → `5f6a943e…71c1` in the same PR
(ADR-285). Scanner: `plugins/soleur/test/required-checks-canonical-parity.test.sh` Test 10.

## 2026-11-07 — waiver-discipline earned green (#12276)

The staged-diff lint chain gains a `waiver-discipline` reproduction: added `gitleaks:allow` lines
outside the member's own exclusions must carry an `issue:#NNN <reason>` trailer, or the step fails
loud before the PR is created. This replaces the earlier unreachability argument, which leaned on the
generator-emitted `weakness-digest.md` never containing the token — a claim about today's output
format, not a property of the diff. The synthetic green for `waiver-discipline` (a `secret-guards`
member) is now earned the same way `credential-path-guard` is below it. Re-pinned
`WM_COMPOSITE_PIN` in `tests/scripts/test-weakness-miner.sh` (run body changed; first re-pin since
v4 set the pin); recorded in ADR-285.

## 2026-09-20 — ALLOWED_PATHS drops rule-metrics.json (#8377)

`knowledge-base/project/rule-metrics.json` was removed from `ALLOWED_PATHS`. ADR-235
reclassified it as an untracked cache (it aggregates gitignored local incident data per
ADR-091, so the committed copy only ever reflected the worktree that last ran the
aggregator), and `.github/workflows/rule-metrics-aggregate.yml` — the only workflow that
staged it — was deleted in the same change. A bot PR can no longer produce that path at
all, so the array entry was unreachable machinery.

Earlier entries below reference `rule-metrics-aggregate.yml` and the two-member
`ALLOWED_PATHS`; they are left as written because they were accurate when made. Every
unreachability argument that named the two-member set still holds — removing a member can
only shrink an intersection.

## v3 (2026-07-05)

Issue: #6049. Plan:
`knowledge-base/project/plans/2026-07-05-fix-bot-synthetic-check-names-drift-plan.md`.

`CHECK_NAMES` had drifted: the action hardcoded 6 CI contexts (+ `cla-check` /
`cla-evidence`) while the live **CI Required** ruleset requires **17** contexts
(16 GitHub-Actions `integration_id 15368` + `CodeQL` GHAS 57789). Every
synthetic-check bot PR sat at `mergeState=BLOCKED` forever — zero `ci/`-prefixed
bot PRs had ever auto-merged.

**Two behavior changes:**

1. **`CHECK_NAMES` is now DERIVED from `scripts/required-checks.txt`** (the
   SSOT), not hardcoded. The action parses the file (leading-`#`-only comment
   rule, multi-word- and `#`-safe — shared with
   `scripts/lint-bot-synthetic-completeness.sh`) and posts one check-run per
   name, with `cla-check` / `cla-evidence` custom outputs preserved via a
   `case`. Fails loud if the file is absent (a non-checkout consumer) rather
   than posting an empty, deadlocking set. A composite→SSOT guard in
   `plugins/soleur/test/required-checks-canonical-parity.test.sh` catches any
   future re-hardcode. `CodeQL` stays omitted (a 15368 synthetic can't satisfy
   a GHAS gate; it concludes `neutral` for bot PRs).

2. **Content-safety ceiling (Tier 2, mandatory).** Completing the synthetic set
   fabricates greens for the `gitleaks scan` AND `lint fixture content` required
   contexts, so the action now EARNS both over its own staged diff before
   creating the PR: a pinned real `gitleaks` run (v8.24.2 + SHA256, matching
   `secret-scan.yml` + `ci.yml` test-scripts — pin-parity asserted in CI) plus
   `lint-fixture-content.mjs`. Any finding → fail loud, no branch pushed, no PR,
   no synthetics. A **safe-surface allowlist** additionally restricts `add-paths`
   to the two artifacts the two callers actually emit
   (`knowledge-base/project/weakness-digest.md`,
   `knowledge-base/project/rule-metrics.json`) and rejects the
   `.gitleaks.toml`-allowlisted `plans/`/`specs/`/`references/`/`learnings/`
   subtrees (where a real gitleaks run would be blind and the green fabricated).

**No input contract change.** Both existing callers (`weakness-miner.yml`,
`rule-metrics-aggregate.yml`) pass allowlisted `add-paths` and are unaffected.

## v2.1 (2026-05-17)

Issue: #3916 / #3923 / #3927. PR #3201 added `cla-evidence` to the "CLA
Required" ruleset via `scripts/required-checks.txt`, but synthetic-posting
sites (this action and two inline-posting bot workflows) were not updated.
Bot PRs from composite-action consumers (`scheduled-skill-freshness`,
`scheduled-weekly-analytics`, `rule-metrics-aggregate`,
`scheduled-content-vendor-drift`, `scheduled-rule-prune`) would deadlock
on the new required check at next firing.

Adds a 6th synthetic check-run after the existing `cla-check` post:

- `cla-evidence` — auto-success, fixed `"Bot-authored PR — no CLA-signed
  contributions to attest."` summary in this composite. Matches the
  `cla-check` shape; no caller input is consumed. (The two inline-posting
  workflows — `scheduled-compound-promote.yml` and
  `scheduled-content-publisher.yml` — use a `"Bot-authored content PR — …"`
  variant since they're both content-emitting; this composite serves
  generic bot PRs and keeps the unqualified phrasing.)

**No input contract change.** Existing v2 callers are forward-compatible —
the new synthetic is posted unconditionally, like `cla-check`.

## v2 (2026-05-11)

Issue: #2720. Plan: `knowledge-base/project/plans/2026-05-11-feat-compound-promotion-loop-plan.md`.

Adds 3 optional inputs needed by the compound-promotion-loop cron (which
opens draft PRs, labels them `self-healing/auto`, and skips auto-merge so a
human operator confirms before merge). All three default to behavior
identical to v1.

- `draft` (default `'false'`): when normalized-true, passes `--draft` to
  `gh pr create`.
- `skip-auto-merge` (default `'false'`): when normalized-true, omits the
  closing `gh pr merge --squash --auto` step.
- `labels` (default `''`): newline-separated label names applied via
  `gh pr edit --add-label` after PR creation. Caller is responsible for
  label existence; the action does not create labels.

**Boundary normalization.** `draft` and `skip-auto-merge` are lowercased and
hard-validated against the literal `true|false` set so callers passing
`'True'`, `'TRUE'`, `'1'`, or any other approximation fail loud, not silent.
GitHub Actions composite-input booleans-as-strings are an evergreen footgun;
the normalization step is the load-bearing defense.

**Shell flags unchanged.** Run block keeps `set -eo pipefail` (NOT `-euo`).
Several existing inputs (`add-paths`, `change-summary` default) rely on
unset-permissive semantics; upgrading to `-u` would break the v1 callers
this changelog promises not to break.

**Backward compatibility.** Existing callers (`scheduled-rule-prune.yml`,
`rule-metrics-aggregate.yml`) omit the new inputs, so defaults
`'false'`/`'false'`/`''` make the action open a non-draft PR, label nothing,
and queue auto-merge — exactly the v1 behavior.

## v1 (pre-2026-05-11)

Original surface. Opens a non-draft bot PR from `${BRANCH_PREFIX}<date>` →
`main`, posts 4 synthetic check-runs (`test`, `dependency-review`, `e2e`,
`skill-security-scan PR gate`) plus `cla-check`, queues `gh pr merge
--squash --auto`. Inputs: `add-paths`, `branch-prefix`, `commit-message`,
`pr-title-prefix`, `pr-body`, `change-summary`, `gh-token`.
