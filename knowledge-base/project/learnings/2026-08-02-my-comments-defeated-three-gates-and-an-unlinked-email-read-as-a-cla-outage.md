---
module: prod-version-drift-check / cla-check
date: 2026-08-02
problem_type: logic_error
component: shell_script
symptoms:
  - "three mutation axes reported SURVIVED against an artifact that was actually correct"
  - "a workflow's own explanatory comments failed the ordering pin that greps its step bodies"
  - "a `--first-parent` assertion stayed green with the flag deleted from the git invocation"
  - "cla-check red on two unrelated PRs by the same allowlisted author, reading as a bot outage"
root_cause: unverified_assertion
severity: high
tags: [mutation-testing, vacuous-assertion, code-vs-prose, cla, git-identity, anchoring]
synced_to: [work, review, compound]
---

# My comments defeated three gates, and an unlinked email read as a CLA outage

Two unrelated lessons from one session (#7091, the production version-drift alerter). The
first recurred **four times in one session**, twice inside code written to prevent it.

## 1. A text gate cannot distinguish code from prose — and prose usually comes FIRST

Every static gate over a source file — a `grep` assertion, a PyYAML step-body extraction, a
`str.replace` mutation — sees comments. This is documented in-repo (`cq-assert-anchor-not-bare-token`,
the "narrowing is not anchoring" learning). What this session adds is the **ordering** corollary:

> Documentation for a token is conventionally written **above** the code that uses it. So the
> FIRST occurrence of any token in a well-commented file is usually the comment, not the code.

That single fact produced four distinct failures:

**(a) False FAIL — the ordering pin read prose as the call site.** Part B asserts every
`gh issue create` is preceded by a `gh label create` in the same step body. My comment
*explaining why the bootstrap must come first* named the create command above the bootstrap, so
`body.find()` returned the comment's index and the pin failed against a correct workflow.

**(b) Three mutation axes silently reported SURVIVED.** Each mutator did
`s.replace(token, mutant, 1)`. For `--first-parent`, `sort -n | head -1`, and `fetch-depth: 0`,
the first occurrence was the explanatory comment — so the sabotage landed in prose, the real
code was untouched, and the axis reported "the guard did not catch this."

That verdict is *about the harness*, not about the artifact. **A mutation that cannot reach the
property is not evidence about the property** — and it fails in the direction that looks like a
finding, so the natural response is to go "fix" correct code.

**(c) A genuinely vacuous assertion, revealed by fixing (b).** `grep -c -- '--first-parent'`
counts comment mentions. The checker documents that flag at length, so the assertion would have
stayed green with `--first-parent` deleted from the git invocation entirely. Re-anchored on the
command shape — `^[^#]*git (log|rev-list)[^|]*--first-parent` — which a `#`-leading line cannot
satisfy, because `[^#]*` cannot cross the `#`.

**(d) I then did it to myself while verifying an acceptance criterion.** Checking AC17 ("no live
network in the suite"), my own `grep -nE '^[^#]*(curl|wget) '` reported 4 network invocations.
All four were the word `curl` inside assertion *description strings*. The real check needs quoted
strings stripped first — it returns 0.

### The rules

- **Mutators must skip comment lines** (`if l.lstrip().startswith("#"): continue`), or a green
  axis is unfalsifiable and a red one may be fiction.
- **Anchor assertions on syntax a comment cannot produce** — a `git log …` command shape, an
  `^\s*key\s*=`, a call shape. Never a bare token, and never merely a *narrower slice* (a
  comment inside the construct defeats that too).
- **When a mutation axis reports SURVIVED, check the mutation landed in CODE before concluding
  anything about the artifact.** `diff -q` proves the file changed; it does not prove the change
  was reachable.
- Corollary for authors: a heavily-commented file is *more* likely to defeat its own gates. The
  documentation is not the problem — the unanchored gate is.

## 2. An unlinked git author email silently defeats a login-based CLA allowlist

`cla-check` was red on PR #7149 **and** #7150 — different features, same author, an author
already in the allowlist. Two red checks on unrelated branches read as one bot/CLA outage.

It was neither an outage nor two problems. `contributor-assistant/github-action`'s allowlist
matches GitHub **logins**. Commits authored as `jean.deruelle@jikigai.com` resolve to
`login: "deruelle"` and pass; commits authored as `ops@jikigai.com` resolve to **`login: ""`**,
because that address is not linked to any GitHub account. The action sees an unidentifiable
committer and cannot match it against any allowlist entry — while reporting the generic
`Committers of Pull Request number N have to sign the CLA`, which names neither the email nor
the reason.

**Diagnosis in one command** — the resolved login, not the email, is the thing to look at:

```bash
gh pr view <N> --json commits \
  --jq '.commits[].authors[] | {login, email}'
```

An empty `login` on any commit is the whole answer.

**Fix:** rewrite the branch's author/committer emails to the linked address and force-push
(`git filter-branch --env-filter` over `origin/main..HEAD`, then `--force-with-lease`). The
durable alternative is linking the address in GitHub account settings, which needs an emailed
confirmation and so cannot be done in-session.

**Why two PRs mattered:** the shared symptom was the *clue*, not the noise. Two independent
branches failing identically pointed at a shared input — the author identity — rather than at
either branch's content. Checking the second PR before touching either one is what turned a
suspected vendor outage into a one-command diagnosis.

## Session Errors

1. **Bulk-toggled 44 acceptance checkboxes in `tasks.md`** with a single `replace`, which is the
   documented anti-pattern (a checkbox is a CLAIM). Two of them were false at the time: the exit
   gate was still running, and the AC evidence walk had not been performed. Caught immediately
   and reverted, but the correct move is per-item as each is verified.
2. **Edited the bare-repo path instead of the worktree** for `model.c4`; the guardrail hook
   denied it. Harmless because the hook exists, but it is the `hr-when-in-a-worktree-never-read-from-bare`
   class and cost a round-trip.
3. **Read a background-task "exit code 0" as a suite result.** The notification reports the
   *last* command in the backgrounded body — here a trailing `echo` — so it is 0 regardless. Both
   long runs were re-read from an explicit `rc` file plus the runner's own terminal marker
   (`=== 235/235 suites passed ===`, `=== registered infra suites: 87 passed, 0 failed ===`).
   This is documented and still nearly slipped through twice.
4. **`test-all.sh` is not the exit gate for an infra diff.** Its preamble said so explicitly —
   `NOTE: your diff touches apps/web-platform/infra/, which this runner does NOT cover` — and a
   green 235/235 would otherwise have been read as covering a diff that edits
   `infra/sentry/cron-monitors.tf`. The CI-registered runner
   (`apps/web-platform/infra/run-registered-suites.sh`) was run separately: 87/87.
