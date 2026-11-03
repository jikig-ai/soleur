---
module: Soleur hooks / CLA enforcement
date: 2026-11-03
problem_type: best_practice
component: tooling
symptoms:
  - "local cla-signed-author-gate denied only the literal noreply@anthropic.com; real-but-wrong -c user.email authors (jean@jikig.ai, ops@jikigai.com) sailed past it to a red cla-check"
  - "issue #12027's premise — 'devin-ai-integration[bot] is a sanctioned override per git-rules' — was measured FALSE (in neither cla.yml allowlist nor cla.json roster; cannot sign)"
  - "a naive allowlist admit would have admitted the bot whenever the session's own git config user.email equaled it"
root_cause: missing_validation
resolution_type: code_fix
severity: high
rule_id: wg-cla-signed-author-before-merge
issue: 12027
status: closed
tags: [cla-check, sanctioned-set, deny-overrides-admit, author-vs-committer, premise-validation, gate-design, pull-request-target]
---

# Learning: designing a CLA sanctioned-set gate — deny overrides admit, slots are separate, and one deny covers every class the same rewrite fixes

## Problem

Issue #12027: the local `cla-signed-author-gate.sh` denied only the literal
`noreply@anthropic.com`, so real-but-wrong `-c user.email` authors
(`jean@jikig.ai`, `ops@jikigai.com`) passed local review and failed the required
`cla-check` at merge time — a wasted CI cycle each time. Widening the gate to a
sanctioned-set subset check surfaced four design findings worth keeping.

## Solution

**1. Deny overrides admit — evaluate explicit exclusions BEFORE every admission source.**

The issue brief claimed `devin-ai-integration[bot]` was "a sanctioned Devin-bot
override per git-rules". Measured false: the bot is in neither
`origin/main:.github/workflows/cla.yml` `allowlist:` nor
`origin/cla-signatures:signatures/cla.json` `signedContributors[]`, and cannot
sign (the signature requires a comment from that account — PR #11690's cla-check
ran permanently red, learning 2026-10-30). No "git-rules" doc sanctions it.

The ordering consequence matters: session `git config user.email` is an admit
source, and a Devin session could in principle be configured with the bot
noreply — so `DENIED_EMAILS` is checked before all admit clauses. A bot email
denies even when it equals the session's configured identity.

**2. Author and committer slots are different properties — evaluate them separately.**

`cla-check` resolves `commit.author.user.login` only. `noreply@github.com` is
GitHub's **web-merge COMMITTER** identity: measured 25/25 `origin/main` commits
carry `%ce=noreply@github.com` (uniform squash-merge web flow), so a
committer-slot carve-out for it is parity with the CI check — while an
**author**-slot `noreply@github.com` resolves to the unsigned web-flow login and
must still deny (fail-closed). Carve-outs are per-slot, never per-email.

**3. Sanction rosters are read at base refs, not the PR head.**

`pull_request_target` executes `cla.yml` from `main`, so the allowlist is read
at `origin/main` and signatures at `origin/cla-signatures` — a branch cannot
widen the roster that sanctions its own commits. Rosters are remote-tracking
refs (last fetch); the deny message tells the operator to `git fetch origin` on
a fresh-roster edge. GitHub logins compare case-insensitively — fold BOTH the
roster and the extracted login (roster spells `Elvalio`; a noreply can spell
`elvalio`). Both noreply forms are valid: canonical `<id>+<login>` and the
pre-2017 bare `login@users.noreply.github.com`.

**4. Fold every failing class into ONE deny when they share the remedy.**

Stage 1 (specialized `noreply@anthropic.com` message naming the modal
subagent-commit class) emits first — order is the property, its remedy would be
buried under a generic stage-2 deny. But stage-2 offenders are computed BEFORE
the stage-1 emit and ride along in the same deny/remedy, because the fix for
both classes is the same expensive `filter-branch` rewrite + force-push. Two
sequential denies = two rewrite rounds; one combined deny = one round. Also:
drop the stage-1 email from the stage-2 offender set to avoid a redundant
`for e in` arg.

Fail-open posture preserved: every dynamic read is `|| true`-guarded under
`set -eo pipefail` (a bare failing `$()` would abort before the deny JSON
emits), and all-sources-empty → `exit 0` — an unevaluable run is not a deny.
The pinned human email deliberately does NOT count toward evaluability (a
stripped clone would otherwise deny every branch not authored by that human).

## Key Insight

When a gate's admission set has multiple independent sources and any source is
session-configurable, explicit exclusions must be evaluated **before** the
admissions — "is X allowed?" is not the negation of "is X admitted?" once admit
sources overlap. And when a gate's remedy is an expensive history rewrite, the
deny should enumerate every failing class a single rewrite can fix; sequencing
denies by stage costs the operator one rewrite+force-push round per stage.

## Session Errors

**`git branch --show-current` ran in a fresh shell at the bare repo root and reported `main` (plan phase, forwarded in session-state.md).**

- **Recovery:** re-ran with explicit `workdir` — the worktree was correctly on the feature branch; all later commands used explicit `-C`/`workdir`.
- **Prevention:** in a worktree session never trust a bare `git branch --show-current` in a fresh shell — pin `-C <worktree>` (already covered by `hr-when-in-a-worktree-never-read-from-bare`).

**`markdownlint` prints usage text when pointed at plan files (plan phase, forwarded).**

- **Recovery:** confirmed `knowledge-base/project/` is exempt by `.markdownlintignore` (#7927 design) — no lint applies there; continued.
- **Prevention:** check `.markdownlintignore` before treating a linter's usage output as a finding on KB paths.

**Pipeline brief's premise — "`devin-ai-integration[bot]` is a sanctioned override per git-rules" — was measured FALSE (plan phase, forwarded).**

- **Recovery:** recorded as `pending - assumed` rows in `decision-challenges.md`; the CTO consult ruled EXCLUDE after measuring `origin/main:.github/workflows/cla.yml` allowlist, `origin/cla-signatures:signatures/cla.json`, and PR #11690's red cla-check.
- **Prevention:** an issue/brief premise that reads as established ("sanctioned carve-out") still needs a measured falsification command — `git show origin/main:.github/workflows/cla.yml | grep <bot>` refuted this one in seconds.

**deepen-plan Phase 4.7 authored a `discoverability_test.command` shaped like the whole suite (`.test.sh`) (plan phase, forwarded).**

- **Recovery:** corrected to `grep SANCTIONED .claude/hooks/cla-signed-author-gate.sh` — a probe of the new marker, not the suite.
- **Prevention:** author discoverability probes as a grep of the diff's new constant/marker; a suite-shaped probe re-runs everything and halts on cost.

**Compound session: scratch-repo verification `git commit` denied twice by hooks (variable path, then not-yet-existing path in the same command).**

- **Recovery:** created `/tmp/ident-test-12027` as its own call, then ran `git -c user.email=… commit` against the literal path — hook working as intended.
- **Prevention:** the commit-scanning hook resolves only literal absolute paths that already exist — create the dir first, then commit with the literal path.

## Related Issues

- See also: `../security-issues/2026-11-03-gate-printed-remedy-git-ident-injection.md` (the injection surface in this gate's printed remedy)
- See also: `../integration-issues/2026-10-30-npm-e404-is-authz-masking-and-devin-commits-break-cla-check.md` (the measurement that falsified the bot-override premise)
- See also: `../workflow-patterns/2026-06-04-subagent-commits-fail-cla-check.md` (original gate provenance, PR #4948)
- Issues: #12027, #7218; evidence: PR #11690
