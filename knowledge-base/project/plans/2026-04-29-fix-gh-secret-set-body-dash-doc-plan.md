---
issue: 2993
type: docs-fix
classification: docs-only
requires_cpo_signoff: false
---

# Fix `gh secret set --body -` mis-prescription in OAuth-supabase-url learning (#2993)

## Enhancement Summary

**Deepened on:** 2026-04-29
**Sections enhanced:** Files to Edit (corrected fix prescription), Acceptance Criteria, Risks, Test Plan, Research Insights
**Verification artifacts:** `gh secret set --help` (gh 2.92.0, captured 2026-04-29)

### Key Improvements

1. **Caught a fabricated CLI flag in the initial plan.** The first draft prescribed
   `--body-file -` as the corrected stdin sentinel. Live `gh secret set --help`
   verification (gh 2.92.0) shows no `--body-file` flag exists; the documented
   stdin form is to omit `--body` entirely. Plan now prescribes the correct
   form: drop `--body -` from the pipe.
2. **Differentiated the URL fix (already shipped, public value, inline `--body`)
   from the anon-key fix (still pending, secret JWT, must use stdin to keep
   the value off the cmdline).** Single PR closes both surfaces of the issue.
3. **Embedded `<!-- verified: ... source: ... -->` annotations on the corrected
   CLI snippet** per `cq-docs-cli-verification` (#2566). This is the rule's
   retroactive remediation case applied to itself.

### New Considerations Discovered

- The `cq-docs-cli-verification` Sharp Edge in the planning skill is now
  doubly-precedented: the original incident (#1810/#2550 fabricated `ollama`
  invocation) AND a fresh case during this plan's first draft (fabricated
  `gh secret set --body-file` flag). The catch-rate of live `--help` verification
  is materially higher than reasoning-from-memory.
- Issue #2993's OPEN status despite PR #3018's merge is a soft signal that the
  issue body's "Optionally cross-check" follow-ups are not picked up by bot-fix
  flows. Worth a follow-up note in the closing PR comment.

## Overview

Issue #2993 reports that an operator-run remediation step in
`knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md`
prescribed the wrong `gh secret set` invocation:

```text
printf '%s' 'https://api.soleur.ai' | gh secret set NEXT_PUBLIC_SUPABASE_URL --body -
```

`gh secret set --body -` treats `-` as the **literal value**, not as a stdin sentinel
(verified via `gh secret set --help`: `-b, --body string  The value for the secret
(reads from standard input if not specified)`). The pipe is therefore ignored and
the secret is set to the single character `-`. This was caught at runtime during
operator remediation 2026-04-28T12:14 — the new Validate step in `reusable-release.yml`
rejected the malformed value, and the operator re-ran with the correct form.

The corrected form prescribed by the issue is:

```text
gh secret set NEXT_PUBLIC_SUPABASE_URL --body 'https://api.soleur.ai'
```

(value passed inline via `--body 'value'`, no shell pipe).

## Research Reconciliation — Spec vs. Codebase

| Issue claim                                                                                      | Reality                                                                                                                                                                                                                                                                                          | Plan response                                                                                                                                                                                          |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Target file contains the broken `printf … \| gh secret set --body -` line.                       | `knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md:47` already contains the corrected inline form (`gh secret set NEXT_PUBLIC_SUPABASE_URL --body 'https://api.soleur.ai'`). Fixed in commit `62581167` via PR #3018 (merged).     | Issue #2993 is materially fixed for the named file. Confirm and post a closing comment. Do NOT re-author the same edit (no-op).                                                                        |
| "Optionally cross-check `gh secret set.*--body -` repo-wide — should return zero hits."          | `grep -rn "gh secret set.*--body -" --include='*.md'` returns ONE remaining hit (excluding plan files describing the bug itself): `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md:92`, inside a Doppler→stdin pipe block.                  | Fix this second occurrence in the same PR — same root cause, identical reader risk (next operator remediation copy-pastes a broken command).                                                           |
| Issue is a P3 docs-only fix.                                                                     | Plan files (`2026-04-28-fix-oauth-supabase-url-prod-plan.md`, `2026-04-28-fix-supabase-anon-key-guardrails-plan.md`) also contain the broken pattern, but those are historical planning artifacts describing the bug — rewriting them would falsify the historical record.                       | Leave plan files untouched. Scope the fix to the two **learnings** files (operator-facing runbook surface) and call this out explicitly under Non-Goals.                                                |

## Files to Edit

- `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md`
  — line 92 currently reads:

  ```text
  doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain \
    | tr -d '\r\n' \
    | gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY --body -
  ```

  Drop `--body -` entirely (`gh secret set` reads stdin when `--body` is omitted):

  ```text
  doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain \
    | tr -d '\r\n' \
    | gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY
  ```

  Why drop the flag instead of replacing it: `gh secret set --help` (verified live,
  gh 2.92.0, 2026-04-28) documents `-b, --body string  The value for the secret
  (reads from standard input if not specified)`. The flag set has NO `--body-file`
  option for single-secret sets — the documented stdin form is `gh secret set
  MYSECRET < myfile.txt` (or `... | gh secret set MYSECRET`), with the flag
  omitted. `--body -` sets the secret to the literal `-`; `--body-file -` would
  fail with `unknown flag`. (`-f/--env-file` exists for the dotenv-multi-secret
  form, e.g., `gh secret set -f - < myfile.txt`, but that path expects
  `KEY=value` lines, not a single value, and is not what this block needs.)

  Why drop the flag rather than switch to `--body "$(doppler …)"`: command
  substitution exposes the JWT on the process command line (`ps`, `/proc/<pid>/cmdline`,
  audit logs). The piped-stdin form keeps the secret off the cmdline.

  <!-- verified: 2026-04-29 source: gh secret set --help (gh 2.92.0) -->
  <!-- verified: 2026-04-29 source: https://cli.github.com/manual/gh_secret_set -->

## Files to Create

None.

## Open Code-Review Overlap

Query: `gh issue list --label code-review --state open --json number,title,body --limit 200`
returned no open issues whose body references either file path.
**None.**

## User-Brand Impact

**If this lands broken, the user experiences:** an operator running the OAuth-URL
or anon-key remediation runbook copy-pastes the broken command, sets the GitHub
repo secret to the literal string `-` (anon-key) or `-` (URL), the Validate step
in `reusable-release.yml` rejects the build, the operator burns one workflow-run
cycle (~2-3 min) re-running with the corrected form. No user data exposed.

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this is
a documentation-only correction. The piped-stdin form (`--body` omitted)
explicitly avoids exposing the secret on the process command line, which is a
*strengthening* of the operator runbook against the inline-substitution
alternative.

**Brand-survival threshold:** none — internal-facing operator runbook, no
end-user surface, the broken command surfaces a clear runtime error rather than
silently shipping bad data. The named gate `cq-docs-cli-verification` (#2566)
already exists to prevent fabricated CLI tokens; this is its retroactive
remediation case, not a new exposure.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** `grep -rn "gh secret set[[:space:]].*--body[[:space:]]\+-[[:space:]]*$" --include='*.md' knowledge-base/project/learnings/`
      returns ZERO hits. (The pattern matches `--body -` at end of line / followed only by whitespace, which is the broken form. Scoped to learnings/ to leave plan
      files — which describe the historical bug — untouched.)
- [x] **AC2** `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md`
      line ~92 reads exactly `| gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY` —
      no `--body` flag, no `--body-file` flag. Verify via `grep -n
      'gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY' <file>`.
- [x] **AC3** `knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md`
      line ~47 unchanged (already correct as of commit `62581167` / PR #3018).
      Verify via `grep -n "gh secret set NEXT_PUBLIC_SUPABASE_URL" <file>` →
      single hit reading `gh secret set NEXT_PUBLIC_SUPABASE_URL --body 'https://api.soleur.ai'`.
- [ ] **AC4** PR body uses `Closes #2993`. (Issue is still OPEN despite the
      target-file fix landing in #3018 — that PR's auto-close didn't fire because
      the issue body's "Optionally cross-check" follow-up was unaddressed. Closing
      the loop here.)
- [x] **AC5** Per `cq-docs-cli-verification` (#2566): the new `gh secret set
      NEXT_PUBLIC_SUPABASE_ANON_KEY` (no flag) invocation is verified against
      `gh secret set --help` output. Annotation in this plan: `<!-- verified:
      2026-04-29 source: gh secret set --help (gh 2.92.0) -->`.

### Post-merge (operator)

None. This is a documentation-only fix; no production state to mutate, no
workflow to trigger. The next OAuth/anon-key remediation will pick up the
corrected runbook organically.

## Test Scenarios

This is a docs-only fix — no test code changes. Verification is the AC1-AC3
greps. No new automated test is warranted for two reasons:

1. The static `cq-docs-cli-verification` enforcement (#2566) is the existing
   guard for this class. Adding a per-pattern grep test would duplicate it.
2. The pattern `gh secret set.*--body -` is a one-off CLI-form bug, not a
   structural invariant. A grep test pinned to this exact pattern would
   false-positive on plan files that legitimately quote the broken command.

## Non-Goals

- **Plan files are not edited.** `knowledge-base/project/plans/2026-04-28-fix-oauth-supabase-url-prod-plan.md`,
  `knowledge-base/project/plans/2026-04-28-fix-supabase-anon-key-guardrails-plan.md`,
  and any other plan/spec under `knowledge-base/project/plans/` or
  `knowledge-base/project/specs/` that contains the broken pattern is a
  **historical planning artifact** describing the bug at the time. Rewriting it
  would falsify the record. Scope is the two operator-facing **learnings** files
  only.
- **No structural lint added.** The existing `cq-docs-cli-verification`
  rule (#2566) covers the prevention dimension. A grep-based pre-commit hook
  for `gh secret set.*--body -` would have to allowlist plan files, which is
  fragile.
- **Issue #2979 (predecessor P1)** is already closed; not re-opened.

## Risks

- **R1 — Inadvertently editing a plan file.** Mitigation: AC1's grep is scoped
  to `knowledge-base/project/learnings/`. Reviewers also see a 1-file diff.
- **R2 — Bare `gh secret set NAME` looks incomplete.** A future operator may
  read the edited line and wonder where the value comes from (no `--body`, no
  `<` redirect on the same line). Mitigation: a one-line comment in the
  runbook block explaining "stdin via the upstream pipe; `--body` omitted reads
  from stdin per `gh secret set --help`" is added as part of the edit. The
  three preceding pipe stages (`doppler secrets get … --plain | tr -d '\r\n' |`)
  make the stdin source visually obvious; the comment is belt-and-suspenders.
- **R3 — `Closes #2993` may already auto-fire on push if GitHub re-processes
  the issue body.** Low risk; verify post-merge issue state.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's
  `## User-Brand Impact` is filled with `threshold: none` plus a one-sentence
  scope-out reason (the file is internal-only, the broken command surfaces a
  loud runtime error). Sensitive-path check: the diff touches `knowledge-base/project/learnings/bug-fixes/**`,
  which is NOT in the canonical sensitive-path regex (preflight Check 6 §6.1).
  No CPO sign-off required.
- Per the planning Sharp Edge on CLI-verification (#2566): the new bare
  `gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY` invocation (no flag) is
  verified against the local `gh secret set --help` output (gh 2.92.0),
  inline-cited above (AC5). Do not promote this snippet to a doc page or
  README until that verification annotation is included. Note: the initial
  draft of this plan prescribed `--body-file -` from memory; live-verification
  caught it. This is the rule's case-#2 retroactive remediation, applied at
  plan-time.
- Per the planning Sharp Edge on `gh secret set` accepting CR-terminated input
  (PR #2573 / `R10` in the anon-key guardrails plan): the existing `tr -d '\r\n'`
  filter in the affected pipe block is preserved by the edit. This plan does
  NOT remove or replace that filter.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — documentation-only correction in a
learnings file. CTO/CPO/CMO/CRO/CFO/CLO/COO all have zero surface here.

## Hypotheses

N/A — no network-outage trigger pattern in the feature description.

## Implementation Phases

### Phase 1 — Edit the anon-key learning file (5 min)

1. Open `knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md`.
2. At line ~92, change `gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY --body -`
   to `gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY` (drop the `--body -` tokens
   entirely; the upstream pipe already feeds stdin, which is `gh secret set`'s
   default value source when `--body` is omitted).
3. Optionally append a single-line comment in the runbook block explaining the
   omission ("# stdin via pipe; --body omitted reads from stdin per `gh secret
   set --help`").
4. Run AC1 grep locally; confirm zero hits under `knowledge-base/project/learnings/`.

### Phase 2 — Verify and PR (5 min)

1. `git diff knowledge-base/` — confirm one-file diff, ≤4 line change.
2. Commit with `docs: fix gh secret set --body - mis-prescription in anon-key
   learning (closes #2993)`.
3. Push and open PR with `Closes #2993` in the body.
4. Auto-merge after green CI.

## Research Insights

- **gh secret set semantics (verified live, gh 2.92.0, 2026-04-28):** flag set
  for single-secret writes is `-b/--body string`, `-e/--env`, `-o/--org`,
  `-r/--repos`, `-u/--user`, `-v/--visibility`, `-a/--app`, `--no-store`,
  `--no-repos-selected`. There is **no `--body-file` flag**. The `-f/--env-file`
  flag exists but expects a dotenv-format file (`KEY=value` lines) and is for
  the multi-secret form. Three valid value-source forms for a single secret:
  (a) `gh secret set NAME --body 'value'` (inline, exposes value on cmdline —
  fine for public values like an HTTPS URL), (b) `gh secret set NAME < file`
  (stdin via redirect), (c) `… | gh secret set NAME` (stdin via pipe). Forms
  (b) and (c) work because `--body` is documented as "reads from standard input
  if not specified." `--body -` (sets the secret to the literal `-`) is invalid;
  `--body-file -` would fail with `unknown flag`.
  <!-- verified: 2026-04-29 source: gh secret set --help (gh 2.92.0) -->
  <!-- verified: 2026-04-29 source: https://cli.github.com/manual/gh_secret_set -->

- **PR #3018 partial fix:** A bot-fix PR merged on 2026-04-29T07:58:15Z
  corrected the OAuth-URL learning file but did not address the second
  occurrence (anon-key learning). The bot's scope was the file named in the
  issue body's primary fix prescription; the issue body's "Optionally
  cross-check" follow-up was not actioned. Issue #2993 remained OPEN as a
  result.

- **Why bare `gh secret set NAME` (piped stdin) for the anon-key block, but
  `--body 'value'` for the URL block.** The URL block sets a non-secret public
  hostname (`https://api.soleur.ai`) — exposing it on the cmdline is harmless,
  inline `--body 'value'` is the most readable form. The anon-key block sets
  a JWT token sourced from Doppler — exposing it on cmdline (which `--body
  "$(doppler …)"` would do) is a leak vector (`ps`, `/proc/<pid>/cmdline`,
  audit logs). Piped stdin with `--body` omitted keeps the secret off the
  cmdline. The correction matches each block's risk profile.

## Test Plan (manual)

After the edit:

1. `grep -rn "gh secret set.*--body -" --include='*.md' knowledge-base/project/learnings/`
   → zero hits.
2. `grep -n "gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY" knowledge-base/project/learnings/bug-fixes/2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md`
   → single hit reading `| gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY` (no
   `--body` flag, no `--body-file` flag).
3. `grep -n "gh secret set NEXT_PUBLIC_SUPABASE_URL" knowledge-base/project/learnings/bug-fixes/2026-04-28-oauth-supabase-url-test-fixture-leaked-into-prod-build.md`
   → single hit reading `... --body 'https://api.soleur.ai'`.
4. PR-body grep for `Closes #2993`.

## Resume Prompt

```text
/soleur:work knowledge-base/project/plans/2026-04-29-fix-gh-secret-set-body-dash-doc-plan.md.
Branch: feat-one-shot-fix-gh-secret-set-body-dash-doc.
Worktree: .worktrees/feat-one-shot-fix-gh-secret-set-body-dash-doc/.
Issue: #2993. PR: TBD.
Plan: docs-only fix; primary file already fixed in PR #3018, this PR closes the loop on the second occurrence in the anon-key learning file.
```
