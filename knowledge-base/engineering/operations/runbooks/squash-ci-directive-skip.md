---
title: A CI-skip directive reached the squash commit
audience: operator
on_page_for: scripts/lint-squash-ci-directives.sh
issues: [8405]
brand_survival_threshold: none
last_updated: 2026-09-21
---

# A CI-skip directive reached the squash commit

## Trigger

Read this runbook when:

- The `Block CI-skip directives reaching the squash commit (#8405)` step is RED on a PR (it is a
  step inside the `auto-commit-message-density` job of
  [`.github/workflows/pr-quality-guards.yml`](../../../../.github/workflows/pr-quality-guards.yml),
  not a standalone workflow).
- A merge to `main` produced **no** post-merge `ci.yml` run, **no** GitHub Release, and **no**
  deploy — and the runs are *absent* rather than queued or failed.
- You are about to write about a CI-skip directive in a commit message, a learning, or a
  post-mortem.

## The signature, because it does not look like a failure

A CI-skip directive suppresses `push` and `pull_request` events only. So after the merge:

| observation | reading |
|---|---|
| `ci.yml`, `version-bump-and-release.yml`, `web-platform-release.yml` **absent** from the merge SHA | the directive fired |
| `dynamic`-event runs (`Push on main`, `Code Quality: Push on main`) present and green | not an Actions outage — those events are unaffected |
| sibling merges minutes earlier got both CI and a release | not a repo-wide or workflow-file problem |
| runs **queued** for a long time instead of absent | capacity, NOT this — do not apply this runbook |

The distinction that matters: **absent ≠ queued**. Absent means no run was ever created.

One command answers it:

```bash
git log -1 --format=%B <merge-sha> \
  | grep -nE '\[(skip ci|ci skip|no ci|skip actions|actions skip)\]|\*\*\*NO_CI\*\*\*'
```

## Why a clean-looking PR does it anyway

On a squash merge the squash commit's message is assembled from the PR title, the PR body **and
every branch commit message**. GitHub honours the directive anywhere in that assembled text. The
failure is therefore a property of the *concatenation*: each individual commit message can be
harmless while the squash message is not, which is why no per-commit check can see it.

Measured on #8405: 30 commits, a 67,884-byte squash message, the token at line 658 — inside prose
that was *ruling out* skip-ci as the cause of an earlier CI outage. Post-merge CI, the version bump
and GitHub Release, and the build/publish + deploy chain were all skipped. The deploy arm triggers
on CI *completing*, so it could never fire either.

This is the same surface as the auto-close-keyword scanner (`ship/SKILL.md` Phase 6), which already
documents that GitHub's parser reads branch commit messages on a squash merge — that gap closed
#5463 twice. The mechanism was known; nobody had generalised it from issue keywords to CI
directives.

## Fix (pre-merge)

Do not delete the sentence — writing about a directive is legitimate, and this runbook does it.
Render the token so it cannot match:

| instead of the literal | write |
|---|---|
| the bracketed skip-ci token | `` `skip-ci` `` (hyphenated) |
| an instance | "the CI-skip directives" (name the class) |
| an unavoidable quotation | break it with a zero-width space |

Then reword the offending commit (`git rebase -i`, or `git commit --amend` if it is HEAD and
unpushed) or edit the PR title/body, and re-run:

```bash
bash scripts/lint-squash-ci-directives.sh --base origin/main
```

The lint reports each hit with its surface (`pr#N body`, `commit <sha>`) and 40 characters of
context either side, because finding a token by eye in a 60,000-byte message is not realistic.

## Recovery (already merged)

```bash
gh workflow run ci.yml --ref main
```

Its completion cascades into `web-platform-release.yml`'s `workflow_run` deploy arm, reproducing
what the merge should have done. Two consequences to expect:

1. The arm builds `main`'s **tip**, not your merge commit. The correct health assertion becomes
   "the live `build_sha` is a *descendant* of my merge", not equality with it — so
   `postmerge` Phase 3 already judges it that way (`deploy-arm.sh served` → `CONTAINS` for a descendant).
2. No GitHub Release is retroactively attributed to the skipped merge. The next release tag covers
   the change; the version number simply skips it.

Doing nothing is also defensible on a busy `main`: the next merge runs CI and the release workflow
from a tip that already contains the change. That trades a missing release tag for zero action.

## Exit codes

| rc | meaning |
|---|---|
| 0 | scanned at least one surface, no directive found |
| 1 | a directive was found (each hit printed with its surface), **or** the anti-vacuity floor fired because zero surfaces were examined |
| 2 | cannot evaluate — unreadable `--text-file`, unknown flag, or a `--base` ref that does not exist (the commit surface was NOT scanned; a partial scan is never a pass) |

rc=1 with `ANTI-VACUITY` is not a clean result: it means there was no PR and no commits since the
base, so there was nothing to look at. "Nothing to look at" and "looked and it was clean" are
different claims, and the floor exists so a caller cannot confuse them.

## Related

- [`scripts/lint-bot-synthetic-statuses.sh`](../../../../scripts/lint-bot-synthetic-statuses.sh) —
  the same token set, a different surface: a bot workflow putting the directive inside a
  `gh pr create` call. Runbook: [lint-bot-statuses.md](./lint-bot-statuses.md). The two lints carry
  a byte-identical regex and
  [`plugins/soleur/test/lint-squash-ci-directives.test.sh`](../../../../plugins/soleur/test/lint-squash-ci-directives.test.sh)
  asserts that equality rather than trusting a comment, so GitHub's honoured set cannot drift
  between them.
- `ship/SKILL.md` Phase 6 §"Auto-Close Keyword Pre-Creation Scan" — the sibling scanner on the same
  assembled-message surface.
