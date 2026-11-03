# Tasks — feat-one-shot-12027-commit-author-identity-gate

Plan: `knowledge-base/project/plans/2026-11-03-ci-commit-author-identity-gate-plan.md`
Issues: Closes #12027, Closes #7218

## Phase 1 — Hook extension

- [ ] 1.1 Extend `.claude/hooks/cla-signed-author-gate.sh` with a sanctioned-set builder:
  - `git -C "$WORK_DIR" config --get user.email` (independently optional)
  - `SANCTIONED_EMAILS` constant pinning `jean.deruelle@jikigai.com` (provenance comment → `devin/INSTRUCTIONS.md` §Devin-specific considerations)
  - noreply-login resolver: email `^[0-9]+\+<login>@users\.noreply\.github\.com$` where `<login>` ∈ (`git show origin/main:.github/workflows/cla.yml` `allowlist:` ∪ `git show origin/cla-signatures:signatures/cla.json` `signedContributors[].name`)
- [ ] 1.2 `allowlist:` parse anchored `^[[:space:]]+allowlist:[[:space:]]*"`, first match only (comment block mentions the word)
- [ ] 1.3 Every `git show`/`git config`/jq read guarded (`|| true`-class) so `set -eo pipefail` never aborts before the deny JSON; all-sources-empty → `exit 0`
- [ ] 1.4 Subset-check stage AFTER the existing `noreply@anthropic.com` deny: unique `%ae` ∪ `%ce` on `origin/main..HEAD`; offenders → `emit_incident` + `jq -n` deny payload naming each offender email + generalized `filter-branch --env-filter` fix; `exit 0` always
- [ ] 1.5 Header comment updated to describe the subset semantics (fail-open edges unchanged)

## Phase 2 — Fixture suite (`.claude/hooks/cla-signed-author-gate.test.sh`)

- [ ] 2.1 Fixture helpers: plant `.github/workflows/cla.yml` (with `allowlist:` carrying `soleur-ai[bot]` etc.) on the fixture's origin `main`; push a `cla-signatures` branch carrying `signatures/cla.json` (with `Elvalio`) to the bare origin
- [ ] 2.2 RED arms (must deny): `jean@jikig.ai` wrong-identity; `ops@jikigai.com`; `158243242+devin-ai-integration[bot]@users.noreply.github.com`; `999999999+madeup[bot]@users.noreply.github.com`; unsanctioned COMMITTER with clean author; mixed authors (compliant first + unsanctioned second — assert the SECOND email is named)
- [ ] 2.3 PASS arms (must pass): `273333864+soleur-ai[bot]@users.noreply.github.com`; `92384917+Elvalio@users.noreply.github.com`; config-equal authors; unset-config + `jean.deruelle@jikigai.com` pinned email; all-sources-absent fail-open
- [ ] 2.4 Harness self-test: assert `assert_deny` actually parses the JSON deny payload (counter floor / instrument check)
- [ ] 2.5 Existing T1–T6 stay green (noreply deny preserved)

## Phase 3 — Guidance convergence

- [ ] 3.1 `AGENTS.rules.md` — widen `wg-cla-signed-author-before-merge` (stay < 600 bytes/line; re-run `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md`)
- [ ] 3.2 `plugins/soleur/skills/git-worktree/SKILL.md` ~line 461 — widen `hr-never-fake-git-author` to cover real-but-wrong `-c user.*` overrides
- [ ] 3.3 `plugins/soleur/devin/INSTRUCTIONS.md` §Devin-specific considerations — "prefer configured identity; `-c` only when unset and only an allowlisted email"
- [ ] 3.4 `plugins/soleur/skills/work/SKILL.md` — one line at incremental-commit guidance
- [ ] 3.5 `plugins/soleur/skills/ship/SKILL.md` — one line in the `gh pr ready`-boundary gate cluster (after recurring-vendor-expense block)

## Phase 4 — Verify

- [ ] 4.1 `bash .claude/hooks/cla-signed-author-gate.test.sh` → `<n>/<n> passed`, exit 0
- [ ] 4.2 Run the suites covering the touched files (`affected-tests.sh` or shard grep) + shellcheck if wired
- [ ] 4.3 PR body carries `Closes #12027` AND `Closes #7218`; `semver:patch` label (plugins/soleur touched)
