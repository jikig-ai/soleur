---
title: "fix(ci): version-bump tag-filter must match strict semver, not bare prefix glob"
type: fix
date: 2026-05-19
issue: 4082
branch: feat-one-shot-version-bump-tag-filter-4082
lane: single-domain
---

## Enhancement Summary

**Deepened on:** 2026-05-19
**Sections enhanced:** Files to Edit, Acceptance Criteria, Sharp Edges, Risks, Research Insights
**Research agents used:** inline planner deepen-pass (single-line CI fix; per `cm-delegate-verbose-exploration-3-file`, the plan touches 1 production file + 1 test file — sub-agent fan-out adds cost without coverage gain)

### Key Improvements

1. **`-eo pipefail` trap caught at deepen time, not at /work-time GREEN.** GitHub Actions' default shell is `bash --noprofile --norc -eo pipefail`. The naive `LATEST_TAG=$(... | grep ... | head -1)` form aborts the step with rc=1 when grep finds no match (empty-namespace bootstrap case) — BEFORE the existing `if [ -z "$LATEST_TAG" ]` fallback can fire. Two mitigations evaluated; **`grep -m1 ... || true`** is the chosen shape (eliminates SIGPIPE risk too).
2. **SIGPIPE-on-large-corpus risk surfaced.** Current corpus is ~11KB (safe), but `head -1` closing early on a >64KB pipe buffer would SIGPIPE grep (exit 141) and pipefail would propagate. `grep -m1` exits successfully after first match; no SIGPIPE possible. Forward-proof against tag corpus growth.
3. **Live citations verified.** PRs #4062, #3940, #4081 are MERGED; commit `1cb5c4312` for #4062 is on main; `vinngest-v1.0.0` tag dated 2026-05-19 attached to that commit. `hr-tagged-build-workflow-needs-initial-tag-push` confirmed ACTIVE in worktree `AGENTS.md`.
4. **GitHub Actions default-shell citation added.** Doc URL pinned so future maintainers don't second-guess the `pipefail` reasoning.

### New Considerations Discovered

- The original plan's R1 ("empty filter result falls through to `CURRENT=0.0.0`") was **wrong**: under `-eo pipefail`, the step aborts BEFORE the fallback runs. The fix shape must include `|| true` (or use `grep -m1` semantics) to preserve the existing empty-fallback path.
- `wg-never-bump-version-files-in-feature` rule body confirms version comes from git tags; the workflow IS the version-of-record producer. A regression here silently halts the release pipeline (already proven by issue #4082 itself).

---

# fix(ci): version-bump tag-filter must match strict semver, not bare prefix glob

The reusable-release workflow's `git tag --list "${TAG_PREFIX}*"` glob is `fnmatch`-style, so the plugin's bare `v` prefix matches every tag starting with `v` — including the new `vinngest-v1.0.0` bootstrap tag from PR #4062. `--sort=-version:refname` returns `vinngest-v1.0.0` as "latest plugin tag", the strip-and-parse step splits `inngest-v1.0.0` into `MAJOR=inngest-v1 MINOR=0 PATCH=0`, the regex gate trips, and every plugin release is silently blocked.

The fix is a one-line post-filter that anchors to strict `^<prefix>[0-9]+\.[0-9]+\.[0-9]+$` after the glob pre-filter. The glob stays as a cheap O(N→N') reducer; the anchored regex is the canonical-shape gate. The change lives entirely in `.github/workflows/reusable-release.yml`; no caller change, no tag rename.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — plugin releases stay blocked, no `vX.Y.Z+1` tag is minted, but no end-user data path is touched. The harm is internal: marketplace-fetched plugin updates stall, and any post-merge skill/agent edits fail to reach users.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A — this is CI build-pipeline plumbing, no PII/auth/payment surface.
- **Brand-survival threshold:** `none`
- *Scope-out override:* `threshold: none, reason: CI tag-glob filter in .github/workflows/reusable-release.yml; no user-facing data path, no auth/PII surface — preflight Check 6 sensitive-path regex does not match this file.`

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 — `git tag --list "v*" --sort=-version:refname | grep -m1 -E "^v[0-9]+\.[0-9]+\.[0-9]+$"` against the live tag corpus returns `v3.101.5` (the current plugin latest), NOT `vinngest-v1.0.0`. Output captured in PR body. **Verified 2026-05-19: returned `v3.101.5`.**
- [x] AC2 — Same pipeline applied to `TAG_PREFIX=web-v` returns `web-v0.94.8` (post-plan release minted `web-v0.94.8`; preserved-behavior assertion satisfied — pipeline returns the latest stable per-prefix without inngest collision).
- [x] AC3 — Same pipeline applied to `TAG_PREFIX=telegram-v` returns `telegram-v0.1.28` (unchanged behavior — preserved).
- [x] AC4 — `.github/workflows/reusable-release.yml` line ~196 contains exactly one canonical-shape line; fixture `[yaml-shape]` check passes.
- [x] AC5 — Test fixture lives at `.github/scripts/test/test-tag-filter.sh` (existing repo convention; `.github/workflows/test/` does not exist — fell through to `.github/scripts/test/` where sibling fixtures `test-check-settings-integrity.sh` etc. already live and are exercised by `run-all.sh`). Synthesizes the tag list and asserts the canonical pipeline returns the correct winner per prefix plus the empty-corpus case.
- [x] AC6 — `bash -n .github/scripts/test/test-tag-filter.sh` exits 0.
- [x] AC7 — `bash --noprofile --norc -eo pipefail .github/scripts/test/test-tag-filter.sh` exits 0 (6 passed, 0 failed).
- [ ] AC8 — Spec at `knowledge-base/project/specs/feat-one-shot-version-bump-tag-filter-4082/spec.md` exists (deferred — the one-shot pipeline produced `session-state.md` and `tasks.md` in this directory but no `spec.md`; this plan IS the spec).

### Post-merge (operator/CI)

- [ ] AC9 — `version-bump-and-release.yml`'s path filter is `'plugins/soleur/**'` + `'plugin.json'` (verified at plan-write time in `.github/workflows/version-bump-and-release.yml:5-6`). This PR edits `.github/workflows/reusable-release.yml` + `.github/workflows/test/test-tag-filter.sh` + `knowledge-base/...` — **none of those match the path filter**. The plugin-release workflow will NOT re-fire on merge. Therefore: dispatch via `gh workflow run version-bump-and-release.yml --ref main` in `/soleur:ship`'s post-merge phase (`workflow_dispatch` requires `bump_type` input — pass `patch`). Confirm a `v3.101.6` tag + GitHub Release is minted. Per `wg-plan-prescribed-skills-must-run-inline`, `/soleur:ship` performs this dispatch — not the operator.
- [ ] AC10 — `gh run view <run_id> --log` for the post-merge run shows `Latest tag: v3.101.5 (version: 3.101.5)` followed by `Bumping 3.101.5 -> 3.101.6 (patch), tag: v3.101.6`. The `Invalid version components: MAJOR=inngest-v1` line MUST be absent.
- [ ] AC11 — `gh release view v3.101.6 --json tagName,name` returns the minted release; `Closes #4082` in PR body auto-closes the issue on merge (this is a code-shipping fix, not an ops-remediation, so `Closes` is correct per `wg-use-closes-n-in-pr-body-not-title-to`).

## Test Scenarios

- **Given** a tag corpus containing `vinngest-v1.0.0` AND `v3.101.5`, **when** `LATEST_TAG=$(git tag --list "v*" --sort=-version:refname | grep -m1 -E "^v[0-9]+\.[0-9]+\.[0-9]+$" || true)` runs under `bash -eo pipefail`, **then** `LATEST_TAG=v3.101.5` and rc=0.
- **Given** the corpus also contains `web-v0.94.7` and `telegram-v0.1.28`, **when** the same pipeline runs with `TAG_PREFIX=web-v`, **then** `LATEST_TAG=web-v0.94.7` (verifying no regression on the track-prefixed tracks).
- **Given** a hypothetical future `v3.101.6-rc1` pre-release tag, **when** the filter runs, **then** the rc tag is excluded by the `$` end-anchor and the last stable `v3.101.5` is returned. (Defensive — plugin does not currently use rc suffixes; documents intent. If pre-releases are adopted later, the regex is widened to `^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$` per Risk R2.)
- **Given** the post-filter returns nothing (empty corpus, all tags filtered out — e.g., bootstrap of a new component prefix), **when** the pipeline runs under `-eo pipefail`, **then** `LATEST_TAG=""` (NOT a step abort) and the existing `if [ -z "$LATEST_TAG" ]` branch fires `CURRENT=0.0.0`. The `|| true` is load-bearing for this scenario; without it, the step aborts with rc=1 before reaching the empty-fallback.
- **Given** a synthesized large corpus (>64KB through the pipe, simulating future tag-corpus growth), **when** the pipeline runs, **then** `grep -m1` exits 0 after the first match (no SIGPIPE to upstream); the step succeeds. (Deepen-pass empirically verified: `seq 1 10000 | sed 's/^/v3.101./;s/$/.0/' | grep -m1 -E ...` returns rc=0 even though `head -1` on the same input returns rc=141 from SIGPIPE.)

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Codebase reality | Plan response |
|---|---|---|
| "Workflow likely uses a permissive `v`-prefix strip rather than `^v[0-9]+\.[0-9]+\.[0-9]+$`" | Confirmed — `reusable-release.yml:188` uses `git tag --list "${TAG_PREFIX}*"` glob with no regex post-filter; the strip is `"${LATEST_TAG#"$TAG_PREFIX"}"` (literal prefix strip). | Add anchored regex post-filter as the new pipe tail (`grep -m1 ... || true` replaces `head -1` — see Files to Edit for `-eo pipefail` rationale). |
| "Inngest tag pushed by an earlier PR (likely #4062)" | Verified — `git show vinngest-v1.0.0` is dated 2026-05-19, attached to commit 1cb5c4312 from PR #4062. | Confirmed root cause; no tag rename — fix-A is sufficient. |
| "Switch to `gh release list`" (option c) | Rejected by prior learning `2026-03-19-git-tag-sort-shallow-clone-semver.md` — `gh release list` sorts by creation date, not semver; a manual hotfix would be returned as "latest" out of order. Also `gh release view` (no args) returns the single latest across ALL tag namespaces. | Do NOT adopt option c. Stay on `git tag --sort=-version:refname` + anchored post-filter. |
| "Rename `vinngest-v1.0.0` to `inngest-v1.0.0`" (option b) | Workflow `.github/workflows/build-inngest-bootstrap-image.yml` is gated on `vinngest-v*.*.*`; rename would require updating that gate + any consuming `ci-deploy.sh` references. The tag is intentional and documented in the tag message. | Defer — file follow-up if rename ever desired. Fix-A makes rename optional. |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --json number,title,body --limit 200` returns no issue body containing `.github/workflows/reusable-release.yml`. (Verified at plan time.)

## Domain Review

**Domains relevant:** Engineering/Infrastructure (CTO)

### Engineering/Infrastructure (CTO)

**Status:** reviewed (inline by planner — single-line YAML edit in CI substrate, blast radius bounded to `reusable-release.yml`'s 3 callers, no infra resources touched)
**Assessment:** The fix is a defensive narrowing of an existing glob — no new dependency, no new YAML stanza, no caller signature change. The single risk is the post-filter regex being wrong; the test fixture in AC5 mitigates by exercising all 3 callers' prefixes against a synthetic corpus. No CTO Task spawn warranted for a one-line fix on a well-understood substrate; planner-inline review per `cm-delegate-verbose-exploration-3-file` (this is a 1-file change).

Product, Marketing, Sales, Operations, Legal, Finance, Security: not relevant — pure CI plumbing change with no user-facing surface, no PII path, no payment flow, no auth boundary, no compliance trigger.

## Files to Edit

- `.github/workflows/reusable-release.yml` — line ~188 in the `Compute next version` step:
  ```yaml
  # BEFORE
  LATEST_TAG=$(git tag --list "${TAG_PREFIX}*" --sort=-version:refname | head -1)
  # AFTER (deepen-pass corrected — uses grep -m1 + || true for -eo pipefail safety)
  LATEST_TAG=$(git tag --list "${TAG_PREFIX}*" --sort=-version:refname \
    | grep -m1 -E "^${TAG_PREFIX}[0-9]+\.[0-9]+\.[0-9]+$" || true)
  ```
  Rationale:
  - Glob `--list "${TAG_PREFIX}*"` stays as cheap pre-filter (760-entry corpus → namespace-scoped subset).
  - `--sort=-version:refname` preserves semver ordering (handles `v3.101.5 > v3.99.0`).
  - `grep -m1 -E "^<prefix>[0-9]+\.[0-9]+\.[0-9]+$"` enforces strict `<prefix><X>.<Y>.<Z>` shape AND stops after first match (replaces `head -1`).
  - **`|| true` is load-bearing** — GitHub Actions runs `run:` blocks with `bash --noprofile --norc -eo pipefail {0}` by default ([docs ref](https://docs.github.com/en/actions/using-jobs/setting-default-values-for-jobs#about-default-shells)). When grep finds no match it exits 1; without `|| true`, command-substitution propagates rc=1 to the assignment AND `-e` aborts the step BEFORE the existing `if [ -z "$LATEST_TAG" ]` empty-fallback fires. `|| true` preserves the fallback path (empty `LATEST_TAG` → `CURRENT=0.0.0`).
  - **`grep -m1` over `head -1` choice:** `grep -m1` exits 0 after the first matching line is written to stdout, never receives SIGPIPE. `head -1` would close stdin after one line; on a corpus larger than the kernel pipe buffer (~64KB), upstream grep would SIGPIPE (exit 141) and `pipefail` would propagate. Current corpus is ~11KB (safe today), but `grep -m1` is forward-proof.
  - Why **not** `gh release list`: per learning `2026-03-19-git-tag-sort-shallow-clone-semver.md`, `gh release list` sorts by creation date, not semver — a manual hotfix release would be returned as "latest" out of order; multi-namespace collision returns the wrong component.

## Files to Create

- `.github/workflows/test/test-tag-filter.sh` (or wherever the test-suite convention places shell-test fixtures — verified at /work time via `ls .github/workflows/test 2>/dev/null` and falling back to `plugins/soleur/test/` if `.github/workflows/test/` does not exist).
  Contents: a self-contained shell script that synthesizes a tag list (heredoc or array), pipes it through the same `--sort=-version:refname | grep -E ...` pipeline (using `printf '%s\n' "${tags[@]}" | sort -V -r` as the `git tag --sort` substitute since the test does not have a real git repo), and asserts the expected winner per prefix. Exits 0 on success, non-zero on failure. `bash -n` clean.
- `knowledge-base/project/specs/feat-one-shot-version-bump-tag-filter-4082/spec.md` — created by the one-shot pipeline if absent.
- `knowledge-base/project/specs/feat-one-shot-version-bump-tag-filter-4082/tasks.md` — derived from this plan at the `Save Tasks` step.

## Research Insights

- **Tag corpus snapshot (2026-05-19):** 760 tags total. `v[0-9]*` namespace has ~700 entries (plugin track, `v0.0.x`–`v3.101.5`). `web-v*` has the web-platform track. `telegram-v*` has the telegram-bridge track. `vinngest-v1.0.0` is the sole offender in the bare-`v` glob; no other `v<word>-*` collisions exist today.
- **Why the bare-`v` plugin prefix is grandfathered:** the plugin was the only `v*` namespace until 2026-05-19. The Inngest bootstrap-image workflow (PR-F #3940) chose `vinngest-v` to satisfy `hr-tagged-build-workflow-needs-initial-tag-push` — that hard rule is satisfied; it does not specify "must not collide with other prefixes."
- **Single consumer:** `grep -rn 'git tag.*sort.*v:refname' .github/ apps/ plugins/ scripts/` returns exactly one match — `reusable-release.yml:188`. No other "latest tag" computation exists in the repo. The narrow-type-filter-trap class (one place expanded, another didn't) does NOT apply because there is no sibling reader.
- **CLI verification:** `git tag --list "<glob>" --sort=-version:refname` — verified per `man git-tag`; `--sort=-version:refname` is semver-aware (v3.101.5 > v3.99.0). Anchored regex `^v[0-9]+\.[0-9]+\.[0-9]+$` syntax verified locally.
- **Reusable-release blast radius:** 3 callers (`version-bump-and-release.yml` → `tag_prefix: v`; `web-platform-release.yml` → `tag_prefix: web-v`; `telegram-bridge-release.yml` → `tag_prefix: telegram-v`). The proposed post-filter is symmetric across all three because the regex interpolates `${TAG_PREFIX}` — no caller change needed.

## Related Learnings

- `knowledge-base/project/learnings/2026-04-15-narrow-type-filter-trap-when-corpus-expands.md` — direct parent class. The lesson "when you widen an allowlist in one place, grep for every filter that encodes the same concept" applies here in reverse: the tag NAMESPACE widened (Inngest joined `v*`-prefixed tags) without the LATEST-TAG filter narrowing. Single consumer means no companion-file fix needed.
- `knowledge-base/project/learnings/2026-03-19-git-tag-sort-shallow-clone-semver.md` — establishes that `gh release list` is unfit (sorts by creation date, not semver). Codifies the `git fetch --tags` + `--sort=-version:refname` pattern this plan defends. The proposed post-filter is additive to that pattern.
- `knowledge-base/project/learnings/2026-03-19-reusable-workflow-monorepo-releases.md` — documents the 3-caller architecture. Confirms the symmetric-fix approach is safe.

## Risks

- **R1 — `-eo pipefail` step abort on empty filter result.** Original draft assumed `if [ -z "$LATEST_TAG" ]` would fire if the regex matched nothing. **Deepen-pass empirically disproved this**: under GitHub Actions' default `bash -eo pipefail`, the command-substitution `LATEST_TAG=$(... | grep ... | head -1)` returns rc=1 when grep fails to match, and `-e` aborts the step BEFORE the empty-fallback can fire. **Mitigation:** `grep -m1 ... || true` form (Files to Edit). This Risk is fully closed by the corrected fix shape; documented here for historical record so a future maintainer doesn't naively strip `|| true` thinking it's redundant.
- **R2 — Pre-release suffix exclusion.** The proposed regex `^v[0-9]+\.[0-9]+\.[0-9]+$` excludes `v3.101.5-rc1`-style pre-releases. The plugin does not currently use pre-release tags. If pre-releases are ever adopted, widen to `^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.]+)?$`. **Mitigation:** an inline YAML comment in the workflow documents the exclusion; defer rc support to a follow-up issue if/when adopted.
- **R3 — Future track collision in the same namespace.** If a future PR introduces e.g. `vfoo-v1.0.0` (another nested-prefix tag), the regex still rejects it. Defense-in-depth. No mitigation needed.
- **R4 — SIGPIPE on large corpus.** `head -1` closes stdin after one line, which would SIGPIPE (exit 141) an upstream grep if the corpus exceeds the kernel pipe buffer (~64KB). Current corpus is ~11KB; the danger is forward-looking. **Mitigation:** `grep -m1` (no `head -1`) eliminates the SIGPIPE path entirely.
- **R5 — Per `cq-test-fixtures-synthesized-only`:** the AC5 fixture uses a synthesized tag list, NOT real git tags from the working copy. Compliant.
- **R6 — Regex-metachar in future prefixes.** Today's prefixes (`v`, `web-v`, `telegram-v`) have no regex metacharacters in their inputs to the regex interpolation. If a future prefix contains `.` or `+`, it must be escaped (e.g., `cli-v1.0.0` prefix `cli-v` is safe). **Mitigation:** Sharp Edges comment in the workflow YAML; deepen-plan flagged but no current violation.

## Sharp Edges

- **`git tag --list` glob is fnmatch, NOT regex.** `v[0-9]*` is a valid shell glob (works), but `v\d+` is not. The post-filter must be `grep -E` regex, not a glob.
- **End-anchor (`$`) is load-bearing.** Without it, `^v[0-9]+\.[0-9]+\.[0-9]+` matches `v3.101.5-rc1`, `v3.101.5.broken`, etc. The plan prescribes `$` explicitly.
- **`${TAG_PREFIX}` interpolation requires escaping regex metacharacters.** The current prefixes are `v`, `web-v`, `telegram-v` — `-` is regex-safe outside character classes. `v` and `web-v` and `telegram-v` have NO regex metachars. If a future prefix contains `.` or `+` it must be escaped. **Mitigation:** add a Sharp Edges comment in the workflow YAML noting this constraint.
- **`grep -E` exit code under `-eo pipefail`** (deepen-pass-corrected). `grep` returns exit 1 when no lines match. GitHub Actions' default shell for `run:` blocks is `bash --noprofile --norc -eo pipefail {0}` ([docs](https://docs.github.com/en/actions/using-jobs/setting-default-values-for-jobs#about-default-shells)) — `pipefail` IS enabled. Inside the command substitution `LATEST_TAG=$(... | grep ... | head -1)`, `pipefail` propagates grep's rc=1 to the entire pipeline, the substitution returns rc=1, `-e` triggers, and the step aborts BEFORE the existing `if [ -z "$LATEST_TAG" ]` empty-fallback can fire. **The plan's fix MUST include `|| true`** (or use a form that exits 0 on no-match). The chosen form is `grep -m1 ... || true`. Empirically verified at deepen-time:
  ```bash
  $ bash --noprofile --norc -eo pipefail -c 'LATEST_TAG=$(printf "vinngest-v1.0.0\n" | grep -E "^v[0-9]+\.[0-9]+\.[0-9]+$" | head -1); echo done'
  # (no "done" printed) ; rc=1   ← STEP ABORTED
  $ bash --noprofile --norc -eo pipefail -c 'LATEST_TAG=$(printf "vinngest-v1.0.0\n" | grep -m1 -E "^v[0-9]+\.[0-9]+\.[0-9]+$" || true); echo "LATEST_TAG=[$LATEST_TAG] done"'
  LATEST_TAG=[] done                ← STEP CONTINUES, FALLBACK FIRES
  ```
- **`grep -m1` over `head -1`** (deepen-pass-introduced). `head -1` closes stdin after reading one line; on a corpus larger than the kernel pipe buffer (~64KB Linux default), upstream `grep` receives SIGPIPE and exits 141, which `pipefail` propagates. `grep -m1` exits 0 cleanly after the first match without closing its stdout. Current corpus (~11KB) is safe today, but `grep -m1` is forward-proof against tag growth. Sibling rationale: removes an unnecessary process from the pipeline.
- **CLI sentinel for AC1:** the assertion command in AC1 (`grep -m1 -E "^v[0-9]+\.[0-9]+\.[0-9]+$"`) must be paren/punctuation-free in any prose mirror — no embedded `(X)` form. Confirmed; the command is plain shell.
- **Per `hr-tagged-build-workflow-needs-initial-tag-push`:** this PR does NOT add a tag-triggered workflow; it fixes a consumer of existing tags. The rule does not apply. No initial-tag-push step required.
- **Per `wg-never-bump-version-files-in-feature`:** this PR MUST NOT edit `plugin.json` version, `marketplace.json` version, or any version file. The fix is to the workflow, not to a version constant. Verified — no version-file edit in the file list.
- **Per `wg-use-closes-n-in-pr-body-not-title-to`:** PR body uses `Closes #4082`. Bug fixes are pre-merge resolved (the tag-filter ships in the merge), so `Closes` is correct here — not `Ref`.
- **Per `hr-no-dashboard-eyeball-pull-data-yourself`:** post-merge verification (AC8/AC9/AC10) uses `gh run view` and `gh release view` deterministically, not dashboard inspection.

## References

- Issue: #4082
- Tag that triggered the bug: `vinngest-v1.0.0` (commit `1cb5c4312`, PR #4062, 2026-05-19)
- File: `.github/workflows/reusable-release.yml:188`
- Sibling callers: `.github/workflows/version-bump-and-release.yml`, `.github/workflows/web-platform-release.yml`, `.github/workflows/telegram-bridge-release.yml`
- Hard rule satisfied: none required to add; defensive narrowing of existing logic.
- Related rule that should NOT be relaxed: `hr-tagged-build-workflow-needs-initial-tag-push` (it's why the offending tag exists; it's correct and stays).
- GitHub Actions default shell: <https://docs.github.com/en/actions/using-jobs/setting-default-values-for-jobs#about-default-shells> — `bash --noprofile --norc -eo pipefail {0}`.

### Live citation verification (deepen-pass, 2026-05-19)

```text
$ gh pr view 4062 --json state,title  → state=MERGED title="feat(runtime): TR9 PR-2 — migrate scheduled-follow-through to Inngest cron"
$ gh pr view 3940 --json state,title  → state=MERGED title="feat(runtime): PR-F Inngest trigger layer + CFO autonomous-draft (#3244 §F)"
$ gh pr view 4081 --json state,title  → state=MERGED title="legal: #4051 LIA + Privacy Policy + DPD updates for LinkedIn Company Page publication"
$ git show vinngest-v1.0.0 --no-patch | head -3
  tag vinngest-v1.0.0  Tagger: Jean Deruelle  Date: Tue May 19 17:57:40 2026 +0200
$ git log --oneline -1 1cb5c4312
  1cb5c4312 feat(runtime): TR9 PR-2 — migrate scheduled-follow-through to Inngest cron (#4062)
$ grep -E "\[id: hr-tagged-build-workflow-needs-initial-tag-push\]" /home/jean/.../feat-.../AGENTS.md
  - [id: hr-tagged-build-workflow-needs-initial-tag-push] → core   ← ACTIVE
```
