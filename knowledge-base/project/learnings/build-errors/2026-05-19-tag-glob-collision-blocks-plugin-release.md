---
title: 'vinngest-v* bootstrap tag silently blocks every plugin release'
date: 2026-05-19
category: ci-cd
tags: [ci, github-actions, semver, tag-filter, regex, release-pipeline, namespace-collision]
symptoms: [Every plugin release silently blocked; no `vX.Y.Z+1` tag minted on merge to main, CI log: `Latest tag: vinngest-v1.0.0 (version: inngest-v1.0.0)` followed by `##[error]Invalid version components: MAJOR=inngest-v1 MINOR=0 PATCH=0 (from inngest-v1.0.0)`, `git tag --list 'v*' --sort=-version:refname | head -1` returns `vinngest-v1.0.0` instead of the plugin's `v3.101.5`]
module: Release Workflow
component: tooling
problem_type: build_error
resolution_type: workflow_improvement
root_cause: config_error
severity: high
---

# vinngest-v* bootstrap tag silently blocks every plugin release

## Problem

`.github/workflows/reusable-release.yml` computes the next plugin version by piping `git tag --list "${TAG_PREFIX}*" --sort=-version:refname` through `head -1`. The plugin caller passes the bare `v` prefix, which has been safe historically because the plugin was the only `v*` namespace. PR #4062 (TR9 PR-2 — migrate scheduled-follow-through to Inngest cron) introduced the `vinngest-v1.0.0` bootstrap tag to satisfy `hr-tagged-build-workflow-needs-initial-tag-push`. `--sort=-version:refname` ranked it above `v3.101.5`, the prefix-strip step produced `inngest-v1.0.0`, the integer regex tripped, and every plugin release after PR #4081 was silently halted.

The fnmatch `git tag --list "v*"` glob and the bare-`v` prefix are both correct in isolation; the bug surfaces only when a sibling track's tag enters the namespace.

## Solution

Add an anchored-regex post-filter to the pipeline, escape the caller's prefix against regex metacharacters, and replace `head -1` + `|| true` with `grep -m1` + `|| [ $? -eq 1 ]` so the pipefail guard only swallows "no match" (grep exit 1), not real grep errors.

`.github/workflows/reusable-release.yml`:

```yaml
# Escape regex metacharacters in the caller-supplied prefix so the
# anchored post-filter below stays correct if a future caller passes
# a prefix containing `.`, `+`, `*`, `(`, etc. Today's callers pass
# `v`, `web-v`, `telegram-v` (metachar-free); the escape is defense
# in depth.
TAG_PREFIX_RE=$(printf '%s' "$TAG_PREFIX" | sed 's/[][\\.^$*+?(){}|/]/\\&/g')

# Glob is fnmatch-style (cheap pre-filter); anchored regex enforces
# strict ${TAG_PREFIX}X.Y.Z shape. `grep -m1` over `head -1` avoids
# SIGPIPE on large corpora. `|| [ $? -eq 1 ]` lets the empty-fallback
# fire on no-match WITHOUT masking grep exit 2 (regex syntax error).
LATEST_TAG=$(git tag --list "${TAG_PREFIX}*" --sort=-version:refname \
  | { grep -m1 -E "^${TAG_PREFIX_RE}[0-9]+\.[0-9]+\.[0-9]+$" || [ $? -eq 1 ]; })
```

Self-contained shell fixture at `.github/scripts/test/test-tag-filter.sh` (`bash .github/scripts/test/run-all.sh`):

- 4 YAML structural-token assertions (`grep -F` against distinctive substrings, not the full literal line — survives cosmetic edits like indentation changes).
- 3 per-caller behavior cases (`v`, `web-v`, `telegram-v`) against a synthetic corpus.
- 2 empty-corpus assertions, including a subshell run under `bash --noprofile --norc -eo pipefail` to prove the pipefail guard.
- 2 regex-metachar cases proving the `TAG_PREFIX_RE` escape rejects an attacker tag (`aXb-1.0.0` under prefix `a.b-`) that the unescaped form would accept.

`LC_ALL=C` pinned at fixture top so `sort -V -r` collation is deterministic across runners.

## Key Insight

A fnmatch glob like `git tag --list "${TAG_PREFIX}*"` is a substring filter, not a delimiter-aware one. Once a sibling track adds a tag in the same lexical namespace as your prefix, `--sort=-version:refname` will mis-rank it as "latest" without any visible warning — the strip-and-parse step downstream fails with a misleading error.

Rule of thumb: anything that calls itself "latest tag for prefix X" must (a) glob-filter for cheap pre-narrowing, (b) anchor-regex-filter for shape correctness, and (c) escape any caller-supplied input that flows into the regex. `gh release list` is **not** a substitute — it sorts by creation date, not semver, and a manual hotfix would silently win over the actual latest.

Generalizes to any "fnmatch + sort + head" pattern across CI/release pipelines: when a new track joins the namespace, the older consumer breaks silently. The narrow-type-filter-trap-when-corpus-expands learning applies — re-grep for sibling consumers when widening a namespace, even when the widening is technically backward-compatible.

## Session Errors

- **PreToolUse `security_reminder_hook` blocked the first workflow Edit** with an advisory about `${{ github.event.* }}` command injection. The edit only touched `${TAG_PREFIX}` (a structured `workflow_call` input from sibling release workflows), which is not the targeted threat class. **Recovery:** retried the same edit; the hook is advisory and the second attempt landed. **Prevention:** the hook should differentiate between `github.event.*` interpolation (the actual command-injection vector) and structured `inputs.*` references which carry the existing workflow's trust boundary. Separate task — out of scope for this PR.
- **Test fixture quote-escape hell** — first version of `check_yaml_token "yaml-shape:prefix-escape"` mixed `$'...'` and `"..."` to embed a single quote inside a double-quoted bash string for matching the YAML sed expression. The bash parser surfaced the error at the `(` in a much later `echo` line because that was the next syntactically-significant token, not the actual error location. **Recovery:** rewrote with single-quoted bash strings + `grep -F`, matching distinctive substrings (e.g., `TAG_PREFIX_RE=$(printf`, `'[ $? -eq 1 ]'`) instead of the literal sed expression. **Prevention:** when a test fixture needs to grep a workflow YAML for a literal regex/sed line, use `grep -F` (fixed-string) with single-quoted bash strings — never construct complex quoting at the bash level.
- **Sanity-check assertion drift on `ac-metachar-unescaped-would-overmatch`** — initially asserted that the unescaped regex would return `aXb-1.0.0` from a multi-tag corpus, but `sort -V -r` placed the legitimate `a.b-1.0.0` ahead in version order, so the unescaped regex matched the *legitimate* tag first. **Recovery:** pinned the unescaped-overmatch corpus to the attacker tag alone, added a symmetric escape-rejects-attacker check via `run_pipeline`. **Prevention:** when a test asserts that an "unsafe form would produce wrong output X", isolate the input — multi-candidate fixtures introduce a sort-order variable that obscures whether the regex itself was correct.
- **Chained `bash -n && bash --noprofile --norc -eo pipefail` masked syntax-error origin** — both commands errored, but the second's verbose runtime output overshadowed the first's exit code. **Recovery:** ran `bash -n` in isolation to confirm syntax status. **Prevention:** in a verification sequence where you need a clean signal from each step, run them in separate Bash calls (and avoid `&&`-chaining) so each step's exit code is independently inspectable.

## Related Learnings

- `2026-04-15-narrow-type-filter-trap-when-corpus-expands.md` — direct parent class. When a namespace widens, every filter that encodes the old assumption needs to narrow correspondingly.
- `2026-03-19-git-tag-sort-shallow-clone-semver.md` — establishes that `gh release list` sorts by creation date, not semver; rejected as alternative path.
- `2026-03-19-reusable-workflow-monorepo-releases.md` — documents the 3-caller architecture (`v`, `web-v`, `telegram-v`); confirms the symmetric-fix approach is safe.

## References

- Issue: #4082
- PR: #4087
- Tag that triggered the collision: `vinngest-v1.0.0` (commit `1cb5c4312`, PR #4062)
- File fixed: `.github/workflows/reusable-release.yml:196`
- Test fixture: `.github/scripts/test/test-tag-filter.sh`
