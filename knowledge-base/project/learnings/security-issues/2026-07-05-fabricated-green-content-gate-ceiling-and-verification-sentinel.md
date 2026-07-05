---
title: "A fabricated-green content-scan gate needs a safe-surface allowlist that rejects exactly what the scanner's OWN config allowlists — and you can't verify it with an allowlisted example secret"
date: 2026-07-05
category: security-issues
module: ci-governance
issue: 6049
pr: 6050
tags: [gitleaks, secret-scanning, bot-pr, ci-required-ruleset, synthetic-checks, verification, bash-tests]
---

# Fabricated-green content-gate ceiling: allowlist tension + verification sentinel

## Problem

`bot-pr-with-synthetic-checks` posts **synthetic** green check-runs for bot PRs
(which never trigger `pull_request` CI) to satisfy `main`'s required-check
rulesets. Completing the synthetic set (#6049) meant fabricating greens for two
**content** gates — `gitleaks scan` and `lint fixture content` — which relaxes
the accidental "a secret-bearing digest stalls at BLOCKED" protection. The
ceiling: reproduce both gates over the bot's staged diff before creating the PR.
Two non-obvious traps surfaced.

## Key Insight 1 — the safe-surface allowlist must reject exactly the paths the scanner's OWN config allowlists

The action earns a real `gitleaks scan` green by running gitleaks over the
staged artifact. But `.gitleaks.toml` **allowlists** whole subtrees
(`knowledge-base/{plans,specs,references}/**`, `learnings/**`). If the action
were allowed to add a file under one of those subtrees, the "real" gitleaks run
would find nothing **because gitleaks skips that path** — the earned-green would
be a fabrication after all. So a naive "markdown under `knowledge-base/`"
safe-surface predicate **voids the ceiling**.

The fix is an **explicit enumeration** of the exact artifacts the scanner
actually scans (`knowledge-base/project/weakness-digest.md`,
`knowledge-base/project/rule-metrics.json` — both provably OUTSIDE every
`.gitleaks.toml` allowlist regex), rejecting anything else. General rule: **when
a gate fabricates a green by re-running a scanner, its input allowlist must be
the complement of the scanner's own allowlist, not a superset of it.** Verify
each permitted path against the scanner config's allowlist regexes before
trusting the earned-green.

## Key Insight 2 — you cannot verify a secret-scan gate with an allowlisted example secret

Verifying "the ceiling fails loud on a secret" (QA Scenario 4) first used
`AKIAIOSFODNN7EXAMPLE` as the sentinel → gitleaks returned `rc=0` (clean),
which reads as "BAD — ceiling passes a secret." But that string is gitleaks'
**canonical AWS documentation example key**, which its default rules
**allowlist by design** (and the `+1` I appended broke the AKIA+16-char
length). The gate was fine; the sentinel was useless.

**A secret-scanner test fixture must be a shape the scanner actually catches
AND is not on its example/stopword allowlist.** Reliable synthetic sentinels:
an on-the-fly PEM private-key block (`-----BEGIN RSA PRIVATE KEY-----` + random
base64 — the `private-key` rule fires, and it's not allowlisted at repo root),
or a repo-custom-rule shape (`postgres://`, `dp.st.`/`dp.sa.`). Always pair the
positive (secret → `rc≠0`) with a **clean control** (no-secret artifact →
`rc=0`) so a vacuous "scanner never fires" can't masquerade as "gate works."
Run the check in an **isolated throwaway git repo** so the synthetic never
touches the real worktree/push-protection.

## Key Insight 3 (bonus) — LC_ALL=C for bash set-comparison tests

A file-vs-file set-parity test using `sort -u | comm` aborted under
`set -euo pipefail` with `comm: file 1 is not in sorted order`. Cause: locale
`sort` interleaves upper/lowercase (`Bash…` vs `allowlist…`) while `comm`
expects C-locale byte order. Fix: `export LC_ALL=C` once so `sort` and `comm`
agree on collation. Any `comm`-based set diff over mixed-case strings needs this.

## Session Errors

1. **IaC-routing hook false-positive** (forwarded from session-state.md) — the plan's "install"/"out-of-band" prose tripped the IaC-routing PreToolUse hook. **Recovery:** the `<!-- iac-routing-ack: ... -->` opt-out. **Prevention:** already covered by the ack mechanism; the only infra change routed through `infra/github/*.tf`.
2. **Push rejected (non-fast-forward)** after rebasing the branch onto `origin/main` (the draft-PR init commit diverged). **Recovery:** `git push --force-with-lease`. **Prevention:** expected when a one-shot rebases mid-flow after `draft-pr` already pushed an init commit; `--force-with-lease` is the standard, safe recovery on an owned feature branch.
3. **Parity test aborted under `set -e`** — `sort`/`comm` collation mismatch. **Recovery/Prevention:** `export LC_ALL=C` (Key Insight 3).
4. **grep-over-own-comments trap** — the parser-parity negative grep would have false-matched `${line%%#*}` in explanatory comments. **Recovery:** filter `^[[:space:]]*#` before the grep. **Prevention:** already documented in `2026-06-17-grep-assertion-over-script-body-false-matches-own-comments.md`; anchor/filter body-greps away from comments.
5. **gitleaks allowlisted-example sentinel** — false `rc=0` from `AKIAIOSFODNN7EXAMPLE`. **Recovery:** synthetic PEM + clean control. **Prevention:** Key Insight 2.
6. **Background test-all redirect gotcha** — redirected output away from the bg task file (empty task file; real output in the redirect target). **Prevention:** for `run_in_background` runners, either drop the redirect or always grep the redirect target for the runner's own summary before trusting the "exit 0" notification (known pattern).

## Related

- ADR-032 amendment (2026-07-05, #6049): the closed drift-chain contract.
- `2026-06-17-grep-assertion-over-script-body-false-matches-own-comments.md`
- `plugins/soleur/skills/qa/SKILL.md` §Sharp edges (secret-scan verification).
