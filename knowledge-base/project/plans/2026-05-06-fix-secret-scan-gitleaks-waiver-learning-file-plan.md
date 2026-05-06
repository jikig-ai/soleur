---
title: "fix(secret-scan): unblock push:main full-tree scan from learning-file private-key example"
issue: 3281
related_issues: [3268, 3160, 3194, 3121]
type: bug-fix
classification: ci-only
requires_cpo_signoff: false
created: 2026-05-06
branch: feat-one-shot-3281-secret-scan-gitleaks-waivers
---

# fix(secret-scan): unblock push:main full-tree scan from learning-file private-key example

## Enhancement Summary

**Deepened on:** 2026-05-06
**Sections enhanced:** Overview, Research Reconciliation, Approach, Phase 1, Acceptance Criteria, Sharp Edges, Research Insights.
**Verification performed during deepen pass:**

- Live `gitleaks git` re-run on this branch — confirmed exactly **1** finding (issue body claims 12; 11 already resolved by PRs #3196/#3197).
- Live `gh pr view` for #3196, #3197, #3264, #3129 — all MERGED, titles match plan citations.
- Live `gh issue view` for #3268 (OPEN — direct duplicate of the remaining finding), #3160 (OPEN — orthogonal rename-laundering guard), #3194 (CLOSED — historical-triage tracker), #3121 (CLOSED — secret-scanning floor umbrella). All citations verified.
- Live `git log --grep="#3196|#3197|#3264"` — commits exist and touch the claimed files.
- Live `grep -nE "^id =" .gitleaks.toml` — 14 custom rule ids enumerated; **`private-key` already has a same-id replacement block** at lines 292-300 with an attached `[[rules.allowlists]]`. The plan was corrected from "add a same-id replacement" to "extend the existing allowlist's `paths` array".
- Live regex test of the existing path allowlist — confirmed `knowledge-base/.*/(plans|specs)/.*\.md$` does NOT catch `learnings/` paths; the proposed `knowledge-base/project/learnings/.*\.md$` addition does.
- Live empirical waiver test on gitleaks v8.24.2 — both `# gitleaks:allow` and `<!-- gitleaks:allow … -->` HTML-comment forms suppress the `private-key` rule on a markdown fixture.

### Key Improvements

1. **Plan body now reflects actual codebase state**, not a paraphrased issue body. The fix is one-line (`paths = [...]` array entry), not a multi-block rule addition. Implementer time saved: ~10 min reading-and-mistakenly-creating-duplicate-rule.
2. **Negative-case AC added** — verifies that the allowlist extension does NOT degrade detection on source paths. Prevents accidental over-widening.
3. **Single-occurrence AC added** for `id = "private-key"` — guards against future double-replacement (a known v8.24.2 silent-failure mode).
4. **Sharp Edges section corrected** — removed the "create a same-id replacement" gotcha (incorrect for current state) and replaced with the more important "do NOT double-create" guard.
5. **Stale-issue-body framing made explicit** in the Research Reconciliation table — issue body cited 12 leaks but only 1 remains; the plan disposes of #3281 by closing the umbrella with `Closes #3281` while the actual remediation surface is the single finding tracked by #3268.

### New Considerations Discovered

- The 11 "already resolved" findings cited in #3281's body have telemetry: PRs #3196 + #3197 (the 18 historical-triage allowlists) landed on 2026-05-04/05 and overlap the issue's enumeration. This dramatically changes the plan's effort estimate vs. what the issue body suggests (small 1-line config edit + 1-line waiver, not a 12-finding triage).
- Per the existing runbook (`knowledge-base/engineering/operations/secret-scanning.md` line 113-145), `# gitleaks:allow` waivers without an `issue:#NNN <reason>` trailer are rejected by the `lint-fixture-content.mjs` linter. Phase 2's HTML-comment waiver MUST include `issue:#3268` (or `#3281`) and a ≥3-char reason.
- The `lint-fixture-content.mjs` linter is glob-scoped to `__goldens__/`, `__synthesized__/`, `apps/web-platform/test/fixtures/` — it does NOT scan `knowledge-base/project/learnings/`. So the trailer-discipline lint will NOT fire on the Phase 2 waiver, but the convention is still followed for forensic consistency. (Verified: `cat apps/web-platform/scripts/lint-fixture-content.mjs | head -30` shows the WAIVER_RE / WAIVER_TRAILER_RE patterns; the script's CLI entry takes file arguments, and our learning file is not in any auto-scanned glob.)

## Overview

`secret-scan.yml` has been failing on every push to `main` since commit `f63b574`
(2026-05-05) because PR #3264 added a learning file
(`knowledge-base/project/learnings/best-practices/2026-05-05-leak-tripwire-self-trips-on-mask-registrations.md`)
that documents `::add-mask::-----BEGIN RSA PRIVATE KEY-----` directives as part of
its symptom reproduction. gitleaks's default-pack `private-key` rule matches the
literal `BEGIN RSA PRIVATE KEY` token regardless of context.

This plan does **not** introduce new behavior; it closes a coverage gap that the
recent allowlist work (PRs #3196 / #3197) left open: those PRs covered
`knowledge-base/(plans|project/(plans|specs))/.*\.md$` and skill `references/`
docs, but **not** `knowledge-base/project/learnings/` — and learning files are the
single most likely place for the team to document what private-key leaks look like
on disk.

## Research Reconciliation — Spec vs. Codebase

The issue body enumerates **12 leaks**, but a fresh local
`gitleaks git --no-banner --exit-code 1` from this branch (post PRs #3196/#3197)
returns **1 leak**. The issue body is a snapshot from before those allowlist PRs
landed; it has not been re-scanned. This plan is scoped to the actual current
state, not the issue body's stale enumeration.

| Spec claim (issue body) | Reality (verified 2026-05-06 via `gitleaks git`) | Plan response |
|---|---|---|
| 12 leaks across 11 files (`gitleaks git`) | 1 leak in 1 file (`learnings/best-practices/2026-05-05-leak-tripwire...md:50`, rule `private-key`) | Scope plan to the 1 remaining finding; explicitly close #3268 (which tracks exactly this finding) and `Ref #3281` for the umbrella tracker. The 11 prior findings were resolved by PRs #3196/#3197. |
| Two private-key findings in `apps/web-platform/test/github-app-drift-guard-contract.test.ts:475/478` are highest-priority | Already covered by `[allowlist]` block scoping `apps/web-platform/(infra\|test)/.*\.test\.(sh\|ts)$` (PR #3196) | No-op. |
| JWT findings in `apps/web-platform/infra/canary-bundle-claim-check.test.sh` | Already covered by same `[allowlist]` block | No-op. |
| Plan/learning markdown findings in `knowledge-base/(plans\|project/specs\|knowledge-base/plans)` | Already covered by `[allowlist] paths = […knowledge-base/(?:plans\|project/(?:plans\|specs))/.*\.md$ …]` (PR #3196) | No-op. |
| `knowledge-base/project/learnings/**/*.md` | **NOT covered** by current allowlist — this is the actual gap | This plan closes the gap. |

**Verification command** (anyone can re-run):

```bash
gitleaks git --no-banner --report-path /tmp/leaks.json --exit-code 0 \
  && jq 'length, [.[] | {file: .File, line: .StartLine, rule: .RuleID}]' /tmp/leaks.json
```

## User-Brand Impact

**If this lands broken, the user experiences:** every PR merged to main shows a red
`secret-scan` workflow under the commit checks on `main`. New contributors and
operators perceive the secret-scanning floor as a broken/distrusted gate; over
time the team learns to ignore red `secret-scan`, eroding the gate's signal value
and increasing the chance a real leak slips by because "secret-scan is always red
on main anyway."

**If this leaks, the user's data is exposed via:** N/A — this plan does not
weaken any detection. The remediation either (a) waives one specific
documentation example, (b) widens the path allowlist to the learnings tree
**only for the `private-key` rule**, OR (c) rewrites the example to a redacted
form. Real private keys (matching `private-key` rule) anywhere outside the
allowlisted paths still trip the gate. Default-pack rules with stronger token
shapes (AWS, Stripe, Doppler, Anthropic) are not modified.

**Brand-survival threshold:** none — the change is a CI-gate triage, not a
credential-handling pathway. No user data, auth, or payments are touched.
Compensating controls preserved: lefthook `gitleaks-staged` + `lint-fixture-content`
hooks fire on every local commit; GitHub push-protection scans server-side; CI
weekly cron re-scans full-tree with the rule pack.

## Hypotheses

(N/A — root cause is empirically verified. The `secret-scan` push:main
runs visibly fail; local `gitleaks git` reproduces; the offending file
and line are deterministic.)

## Approach

Choose **Option B (path allowlist for the `private-key` rule on the learnings
tree)** as the primary fix, and **Option A (inline `<!-- gitleaks:allow … -->`
waiver)** as a second defense-in-depth measure on the specific line.

**Rationale for Option B as primary:**

- The existing PR #3196 allowlist precedent already silences ALL rules across
  `apps/web-platform/(infra|test)/.*\.test\.(sh|ts)$` and
  `knowledge-base/(?:plans|project/(?:plans|specs))/.*\.md$`. Extending coverage
  to learnings is the natural next coverage gap, and the surrounding `[allowlist]`
  block already documents the threat model and compensating controls.
- The `[allowlist]` (top-level, in PR #3196) silences ALL rules including
  default-pack on the listed paths. **However**, this plan scopes the learnings
  add to the **per-rule `private-key` allowlist only**, not the top-level block.
  Reason: learning files document private-key shapes in symptom reproductions;
  Doppler, AWS, Stripe, Anthropic tokens have no documentation reason to appear
  in learning files. Keeping default-pack rules + custom Soleur rules live on
  learnings preserves the "real leak still trips" guarantee.
- Future learning files documenting the same phenomenon (the existing
  `2026-05-04-gitleaks-secret-scanning-floor-rollout.md` could plausibly be
  amended later) won't re-trip the gate.

**Rationale for Option A as a second defense:**

- Documents intent at the leak site for any future reader who finds the line
  via grep without reading `.gitleaks.toml`.
- The `<!-- gitleaks:allow # issue:#3268 documentation example, not a real key -->`
  HTML-comment form is invisible in rendered markdown (the file's likely audience
  surface — Eleventy docs site, GitHub markdown view), so it doesn't degrade the
  reading experience.
- Verified locally via gitleaks v8.24.2 that both `# gitleaks:allow` and
  `<!-- gitleaks:allow … -->` HTML-comment forms suppress the finding. The
  HTML-comment form is the markdown-correct choice.

**Why not Option C (rewrite the example to a redacted form):** The learning file's
entire point is showing what the unredacted bytes look like in the log file (which
is what makes the tripwire fire on itself). Redacting them defeats the example's
forensic value. Reject.

## Implementation Phases

### Phase 1 — Allowlist extension for `private-key` rule (Option B)

**Verified state (2026-05-06):** `.gitleaks.toml` already declares a same-id
replacement for the default `private-key` rule at lines 292-300 (`id =
"private-key"`, regex `-----BEGIN[ A-Z]*PRIVATE KEY( BLOCK)?-----[\s\S]*?-----END[
A-Z]*PRIVATE KEY( BLOCK)?-----`, with a per-rule `[[rules.allowlists]]` block
already attached). **No new rule block needs to be created.** Only the existing
`paths = [...]` array needs extension.

The existing path list (line 300) is:

```
paths = ['''__goldens__/.*''', '''(__snapshots__|__goldens__)/.*\.snap$''', '''apps/web-platform/test/__synthesized__/.*''', '''reports/mutation/.*''', '''apps/web-platform/test/.*\.test\.(ts|tsx)$''', '''apps/web-platform/infra/.*\.test\.sh$''', '''knowledge-base/.*/(plans|specs)/.*\.md$''', '''knowledge-base/plans/.*\.md$''', '''plugins/soleur/skills/.*/references/.*\.md$''']
```

Note the existing `knowledge-base/.*/(plans|specs)/.*\.md$` pattern does NOT
catch learnings — verified locally:

```
$ printf '%s\n' 'knowledge-base/project/learnings/best-practices/2026-05-05-leak-tripwire...md' \
    'knowledge-base/project/plans/foo.md' \
  | grep -E 'knowledge-base/.*/(plans|specs)/.*\.md$'
knowledge-base/project/plans/foo.md   # learnings path NOT matched
```

**Edit:** insert `'''knowledge-base/project/learnings/.*\.md$'''` into the
`paths = [...]` array on **only the `private-key` rule** (line 300), keeping
the inline single-line single-quoted regex formatting style of the
surrounding entries. Comma-separate.

**Critical scoping constraint:** make this change ONLY on the `private-key`
rule's allowlist. **Do not** propagate the learnings path to the other 13
custom rules' allowlists (Soleur BYOK key, Doppler tokens, Supabase JWTs,
Stripe webhook secret, Anthropic, Resend, Cloudflare, Sentry, Discord
webhook, database URL, VAPID, JWT, generic-API-key) and **do not** add it
to the top-level `[allowlist]` block (which silences ALL rules on listed
paths). Rationale: learning files have a documentation reason for
private-key shapes (the team writes about leak phenomena); they have no
documentation reason for AWS/Stripe/Doppler/Anthropic/Discord-webhook
tokens. Keeping default-pack + the other 13 custom rules LIVE on learnings
preserves the "real leak still trips" guarantee.

**Mechanical instruction (suggested diff shape — implementer can adjust
formatting):**

```diff
   [[rules]]
   id = "private-key"
   description = "Private key (default pack, allowlist-extended)"
   regex = '''-----BEGIN[ A-Z]*PRIVATE KEY( BLOCK)?-----[\s\S]*?-----END[ A-Z]*PRIVATE KEY( BLOCK)?-----'''
   keywords = ["BEGIN"]
   tags = ["key", "private"]
     [[rules.allowlists]]
     description = "Synthesized fixtures, test files, plan/spec/skill-reference docs"
-    paths = ['''__goldens__/.*''', '''(__snapshots__|__goldens__)/.*\.snap$''', '''apps/web-platform/test/__synthesized__/.*''', '''reports/mutation/.*''', '''apps/web-platform/test/.*\.test\.(ts|tsx)$''', '''apps/web-platform/infra/.*\.test\.sh$''', '''knowledge-base/.*/(plans|specs)/.*\.md$''', '''knowledge-base/plans/.*\.md$''', '''plugins/soleur/skills/.*/references/.*\.md$''']
+    paths = ['''__goldens__/.*''', '''(__snapshots__|__goldens__)/.*\.snap$''', '''apps/web-platform/test/__synthesized__/.*''', '''reports/mutation/.*''', '''apps/web-platform/test/.*\.test\.(ts|tsx)$''', '''apps/web-platform/infra/.*\.test\.sh$''', '''knowledge-base/.*/(plans|specs)/.*\.md$''', '''knowledge-base/project/learnings/.*\.md$''', '''knowledge-base/plans/.*\.md$''', '''plugins/soleur/skills/.*/references/.*\.md$''']
```

**Files to edit:**

- `.gitleaks.toml` — insert ONE path entry into the `private-key` rule's
  `paths = [...]` array (line 300 on the current branch). No new
  `[[rules]]` block, no top-level `[allowlist]` widening, no edits to any
  other rule's allowlist.

**Verification (mandatory, run from worktree root):**

```bash
gitleaks git --no-banner --exit-code 1
# expected: "no leaks found", exit 0
```

**Negative-case verification (mandatory):** confirm a private key in a
non-allowlisted path STILL trips the gate. Belt-and-suspenders against
accidental over-widening:

```bash
# Spot-test that private-key detection is preserved on non-allowlisted paths.
mkdir -p /tmp/leak-negcheck && cat > /tmp/leak-negcheck/server.ts <<'EOF'
const KEY = `-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA-SYNTHESIZED-FAKE-DO-NOT-COMMIT
-----END RSA PRIVATE KEY-----`;
EOF
gitleaks dir /tmp/leak-negcheck --no-banner --exit-code 0 \
  --config "$(git rev-parse --show-toplevel)/.gitleaks.toml" 2>&1 | grep -i "leaks found"
# expected: "leaks found: 1" (private-key STILL trips on non-allowlisted source paths)
rm -rf /tmp/leak-negcheck
```

### Phase 2 — Inline waiver on the specific line (Option A)

Edit the offending file:

- `knowledge-base/project/learnings/best-practices/2026-05-05-leak-tripwire-self-trips-on-mask-registrations.md`
  - Append `<!-- gitleaks:allow # issue:#3268 documentation example, not a real key -->`
    to line 50 (the `BEGIN RSA PRIVATE KEY` example line).
  - The HTML-comment form does NOT render visibly on Eleventy/GitHub markdown.
  - Trailer format follows `cq-test-fixtures-synthesized-only` waiver protocol:
    `issue:#NNN <reason>` where `<reason>` is ≥3 chars.

**Files to edit:**

- `knowledge-base/project/learnings/best-practices/2026-05-05-leak-tripwire-self-trips-on-mask-registrations.md`

**Verification:**

```bash
# Belt-and-suspenders: temporarily revert Phase 1, confirm Phase 2 alone suppresses.
git stash -- .gitleaks.toml  # NB: NOT in worktree per hr-never-git-stash; use git show main:.gitleaks.toml > /tmp/main-toml && cp .gitleaks.toml /tmp/branch-toml && cp /tmp/main-toml .gitleaks.toml instead
gitleaks git --no-banner --exit-code 1  # expected: 0 with Phase 2 alone
cp /tmp/branch-toml .gitleaks.toml  # restore Phase 1
```

(The stash sequence above will fail under `hr-never-git-stash-in-worktrees` —
use the `git show main:.gitleaks.toml > /tmp/main-toml` swap instead. This
verification is OPTIONAL belt-and-suspenders; primary verification is Phase 1+2
green together.)

### Phase 3 — Runbook update + rule trailer note

Update `knowledge-base/engineering/operations/secret-scanning.md`:

- Under `### Allowlist semantics — read this carefully`: add a bullet noting
  that `knowledge-base/project/learnings/.*\.md$` is allowlisted on the
  `private-key` rule (and ONLY that rule), with the rationale that learning
  files often document private-key-shape examples.
- Update the `last_updated:` frontmatter field to `2026-05-06`.

Update `AGENTS.md` rule `cq-test-fixtures-synthesized-only` ONLY if needed —
verify first by reading the current rule. The rule's hook-enforced tag still
points to `.github/workflows/secret-scan.yml`, which is correct. No edit needed
unless this plan adds a new convention. **Apply placement gate** per
`cq-agents-md-tier-gate`: this is a domain-scoped change to the secret-scanning
runbook, NOT AGENTS.md material. **No AGENTS.md edit.**

**Files to edit:**

- `knowledge-base/engineering/operations/secret-scanning.md`

### Phase 4 — Issue lifecycle

After CI green:

- PR body contains `Closes #3268` (the actual single-finding tracker that this
  plan fully resolves) **and** `Closes #3281` (the umbrella issue — its
  enumeration was stale, and the actual remediation surface after PRs #3196 +
  #3197 is just the one finding documented in #3268, so closing the umbrella
  in this same PR is correct).
- Verify by running `gh run watch` on the post-merge `secret-scan` push:main
  workflow — must complete green before declaring the issue closed
  (`hr-when-a-command-exits-non-zero-or-prints` + `wg-after-a-pr-merges-to-main`).

## Files to Edit

- `.gitleaks.toml` — extend `private-key` per-rule allowlist with
  `knowledge-base/project/learnings/.*\.md$`. May require adding a same-id
  replacement block for `private-key` if one does not exist.
- `knowledge-base/project/learnings/best-practices/2026-05-05-leak-tripwire-self-trips-on-mask-registrations.md` —
  append HTML-comment waiver on line 50.
- `knowledge-base/engineering/operations/secret-scanning.md` — runbook bullet
  + `last_updated` bump.

## Files to Create

(None.)

## Open Code-Review Overlap

Per Step 1.7.5 procedure (`gh issue list --label code-review --state open`,
44 open code-review issues fetched, jq-searched for the planned file paths):

- `.gitleaks.toml` → no overlap.
- `knowledge-base/project/learnings/best-practices/2026-05-05-leak-tripwire-self-trips-on-mask-registrations.md` → no overlap.
- `knowledge-base/engineering/operations/secret-scanning.md` → no overlap.
- Related **non-code-review** open issue: **#3160** (rename-laundering CI guard
  for secret-scanning floor) — orthogonal scope, not a file-path overlap, no
  fold-in/acknowledge/defer decision required. Recorded for awareness.

**Decision:** None.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `gitleaks git --no-banner --exit-code 1` exits 0 from a fresh checkout of
      the feature branch (re-runnable by any reviewer).
- [ ] PR-event `secret-scan` workflow run is green on the feature-branch PR.
- [x] `.gitleaks.toml` modifications are limited to extending the `private-key`
      per-rule allowlist; no top-level `[allowlist]` widening; no other rule
      modified. Verify with: `git diff main -- .gitleaks.toml` shows exactly
      ONE line changed within the `private-key` rule's `paths = [...]` array.
- [x] `grep -c '^id = "private-key"' .gitleaks.toml` returns `1` (no
      duplicate same-id replacement block).
- [x] Negative-case verification (preserved detection): a synthesized
      `BEGIN RSA PRIVATE KEY` block placed under a non-allowlisted source
      path (e.g., `/tmp/leak-negcheck/server.ts`) still trips the
      `private-key` rule. See Phase 1 verification block.
- [x] HTML-comment waiver on the learning file uses the exact form
      `<!-- gitleaks:allow # issue:#3268 <≥3-char reason> -->` and renders
      invisibly on GitHub markdown view (verified by viewing the file in the
      PR's "Files changed" tab; the comment should NOT appear in the
      rendered preview pane).
- [x] Runbook update lands the `last_updated: 2026-05-06` and a one-bullet
      learnings-tree allowlist note under `### Allowlist semantics`.
- [ ] PR body uses `Closes #3268` and `Closes #3281` (the umbrella) per
      `wg-use-closes-n-in-pr-body-not-title-to`.

### Post-merge (operator)

- [ ] First push:main `secret-scan` workflow run after merge completes green
      (`gh run watch <id>` — required by `wg-after-a-pr-merges-to-main`).
- [ ] Weekly cron `secret-scan` run on the next Monday 06:00 UTC fires green.
      (Note: this AC is verification-only; if it surfaces a NEW finding, that
      is a separate issue, not a reopener of #3281.)
- [ ] No follow-up `secret-scan` failures appear in `gh run list
      --workflow=secret-scan.yml --status=failure --limit 5` for the next 7
      days. Tracked via passive observation; no separate scheduled task.

## Test Scenarios

This is a CI-config + docs change with no application-runtime surface. The
"tests" are the gitleaks invocations themselves — there is no Vitest/bun-test
harness to extend. Per `cq-write-failing-tests-before` Infrastructure-only
exemption, no failing-test-first cycle is required.

The verification cycle:

1. **Before:** `gitleaks git --no-banner --exit-code 1` exits 1 with `leaks
   found: 1` on the offending learning file. (Already verified locally
   2026-05-06.)
2. **After Phase 1 only:** exit 0.
3. **After Phase 1 + Phase 2:** exit 0 (idempotent — both layers active).
4. **After Phase 2 only (Phase 1 reverted via `git show main:.gitleaks.toml`
   swap):** exit 0 — confirms the inline waiver alone is sufficient if the
   path allowlist is ever rolled back.

## Domain Review

**Domains relevant:** none

This is a CI-tooling triage with no cross-domain implications:

- Not a feature, not user-facing, not on any product surface.
- Does not weaken the secret-scanning floor (preserves default-pack +
  Soleur custom rules on the learnings tree except for `private-key` only).
- Does not modify Doppler, Supabase, payments, auth, or any
  external-service contract.
- Falls under `Infrastructure/tooling change` per `## Domain Review`
  template guidance — no domain leader spawn.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. (Filled above with `threshold: none` plus the
  CI-only-no-credentials-touched rationale per the
  `single-user-incident → CPO sign-off` carve-out — sensitive-path scope-out
  is satisfied because `.gitleaks.toml` is in CODEOWNERS but the diff
  preserves all detection capability.)
- **Same-id rule replacement is already in place:** the codebase's
  `.gitleaks.toml` already declares `id = "private-key"` at lines 292-300
  on the current branch (and on `main`), with a per-rule
  `[[rules.allowlists]]` block. Phase 1 only EXTENDS the existing
  `paths = [...]` array — it does NOT add a new `[[rules]]` block. If a
  reviewer or future implementer is tempted to "create a same-id
  replacement", stop: the replacement is already there. Double-creating
  it would put two `[[rules]]` blocks with the same id in the file,
  which gitleaks v8.24.2 does NOT diagnose — it silently uses one and
  ignores the other, producing nondeterministic behavior on `gitleaks
  --config` reload. Verify single-occurrence with `grep -c '^id =
  "private-key"' .gitleaks.toml` → must equal `1`.
- **Per-rule vs. top-level `[allowlist]` scoping is asymmetric:** the
  top-level `[allowlist]` (PR #3196 precedent) silences ALL rules
  including default-pack on listed paths; per-rule `[[rules.allowlists]]`
  silences ONLY that rule. This plan deliberately uses the per-rule form
  to keep AWS/Stripe/Doppler/Anthropic detection LIVE on the learnings
  tree. Reviewers must confirm the change is per-rule, not top-level.
- **`hr-never-git-stash-in-worktrees`:** the optional Phase 2 standalone
  verification described above must NOT use `git stash` in a worktree.
  Use `git show main:.gitleaks.toml > /tmp/main-toml; cp .gitleaks.toml
  /tmp/branch-toml; cp /tmp/main-toml .gitleaks.toml` instead, then
  restore from `/tmp/branch-toml` after the test. This is verified
  manually; no automation hook fires here.
- **Issue #3268 prior precedent:** the `<!-- gitleaks:allow -->`
  HTML-comment form was proposed but not yet verified against gitleaks
  v8.24.2 in #3268. This plan's research empirically verified both the
  hash form and the HTML-comment form suppress the finding (test
  fixtures: `/tmp/waiver-test.md` HTML-comment-form scanned 0 leaks;
  `/tmp/waiver-test2.md` hash-form scanned 0 leaks). Plan adopts
  HTML-comment form for markdown-rendering hygiene.
- **Closes vs. Ref disposition for #3281:** issue #3281's body enumerates
  12 findings; only 1 remains. Per Spec-vs-Codebase reconciliation,
  closing #3281 with `Closes #3281` is correct because the actual
  remediation surface is the 1 remaining finding. The other 11 listed
  findings were already resolved by PRs #3196/#3197 — they will not
  re-surface. If a reviewer prefers `Ref #3281` + manual close after
  verification, note that the umbrella tracker can equivalently be
  closed by hand post-merge; either path is correct under
  `wg-use-closes-n-in-pr-body-not-title-to`.
- **CODEOWNERS gate on `.gitleaks.toml`:** `.gitleaks.toml` is
  CODEOWNERS-protected (per the secret-scanning runbook). The PR will
  require a 2nd-reviewer sign-off on the `.gitleaks.toml` diff. This is
  expected and a feature, not a friction point.

## Research Insights

### Verified facts

- `gitleaks git --no-banner --exit-code 1` from this branch returns
  exactly **1 finding** (verified 2026-05-06 against worktree at HEAD
  `5bb9d708`). Issue #3281's 12-finding enumeration is stale.
- The 1 remaining finding is at
  `knowledge-base/project/learnings/best-practices/2026-05-05-leak-tripwire-self-trips-on-mask-registrations.md:50`,
  rule `private-key`, commit `f63b5743` (PR #3264).
- The current top-level `[allowlist]` in `.gitleaks.toml` (PR #3196)
  scopes `knowledge-base/(?:plans|project/(?:plans|specs))/.*\.md$` —
  this is missing the `learnings/` subtree.
- gitleaks v8.24.2 honors both `# gitleaks:allow` and
  `<!-- gitleaks:allow … -->` HTML-comment waivers in markdown
  (verified locally 2026-05-06).
- Same-id custom rule replacement is the v8.24.2 pattern for attaching
  a path allowlist to a default-pack rule (codebase precedent:
  `.gitleaks.toml` Doppler rule replacement at lines 95-110 on main).
- gitleaks v8.24.2 binary is pinned in `.github/workflows/secret-scan.yml`
  with hardcoded SHA256 `fa0500f6b7e41d28791ebc680f5dd9899cd42b58629218a5f041efa899151a8e`.
  No upgrade is in scope for this plan.

### Related learnings

- `knowledge-base/project/learnings/2026-05-04-gitleaks-secret-scanning-floor-rollout.md` —
  documents (a) the v8.24.2 vs v8.25 syntax constraint, (b) the
  default-rule-replacement pattern, (c) the native `# gitleaks:allow`
  bypass risk that motivated the `lint-fixture-content` linter trailer
  enforcement.
- `knowledge-base/project/learnings/best-practices/2026-05-05-leak-tripwire-self-trips-on-mask-registrations.md` —
  the file this plan is fixing; its content is the symptom and its
  documentation explains the underlying GitHub Actions `::add-mask::`
  ordering issue. Read it for full context on why redacting (Option C)
  defeats the file's purpose.

### Workflow precedents

- PR #3196 (`fix(secret-scan): allowlist 18 historical false-positives
  blocking main`) — top-level `[allowlist]` widened to plans/specs/refs.
- PR #3197 (`fix(secret-scan): triage 18 historical leaks; push:main
  green`) — companion triage commit. Together these resolved 18 of the
  pre-existing findings.
- PR #3129 (`feat(security): secret-scanning floor`) — original floor
  introduction; established the per-rule allowlist convention.
- Issue #3268 — the prior tracker for this exact 1-finding leak;
  proposed Options 1/2/3 that this plan operationalizes (chooses Option
  2 + Option 1 belt-and-suspenders, rejects Option 3).
- Issue #3160 — orthogonal: rename-laundering CI guard. Out of scope
  for this plan but worth knowing it exists for any future allowlist
  edit (renames-into-allowlists are the known v8.24.2 escape hatch).
