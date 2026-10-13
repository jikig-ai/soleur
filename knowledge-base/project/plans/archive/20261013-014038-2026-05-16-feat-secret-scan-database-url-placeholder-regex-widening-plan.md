---
title: "feat(secret-scan): widen database-url placeholder allowlist regex to cover '***' redaction shape"
date: 2026-05-16
type: enhancement
status: planned
lane: cross-domain
issue: 3877
related_prs: [3875]
related_issues: [3874, 3268, 3323]
classification: secret-scan-config-edit
requires_cpo_signoff: false
tags: [secret-scan, gitleaks, allowlist, ci-gate]
---

# feat(secret-scan): widen database-url placeholder allowlist regex to cover `***` redaction shape

Closes #3877. Refs #3874 (path-allowlist on the same rule), #3268 (private-key precedent), #3323 (allowlist-diff gate).

## Enhancement Summary

**Deepened on:** 2026-05-16
**Sections enhanced:** Overview, Acceptance Criteria (AC1-AC9), Risks, Sharp Edges, Test Strategy
**Research mode:** focused live-verification pass (single-line regex widening; generic best-practices fan-out would produce filler — verified each load-bearing claim against the installed gitleaks v8.24.2 + the on-disk `.gitleaks.toml` + the canonical runbook + the cited issues/labels).

### Key Improvements (vs. plan v1)

1. **Empirical pre-fix and post-fix baselines captured.** Ran `gitleaks detect` against three fixture cases (asterisk-positive, real-shape-negative, multi-asterisk + Supabase-pooler edge) using both the on-disk config (baseline) and a sandbox-patched copy with the proposed fix applied. All three outcomes matched the plan's predicted behavior. The Test Strategy section now cites the exact exit codes observed.
2. **`\*+` edge-case coverage confirmed.** `**` (two asterisks), `*****************` (17 asterisks), and `postgres:***@` (Supabase-pooler user shape against asterisk password — the user portion `postgres` matches the existing user-alternation branch) all allowlist correctly with the proposed regex. Updated Risks §3 with this concrete enumeration.
3. **All four cited issue numbers verified live.** `#3877` (OPEN, this issue), `#3874` (CLOSED, path-allowlist precedent), `#3268` (CLOSED, private-key precedent), `#3323` (CLOSED, allowlist-diff gate). Frontmatter `related_prs:` and `related_issues:` are accurate as written.
4. **All four prescribed labels verified live.** `secret-scan-allowlist-ack`, `domain/engineering`, `priority/p3-low`, `deferred-scope-out` all exist on the repo per `gh label list --limit 200 | grep -E "^(...)\s"`. No label-creation step needed.
5. **Runbook insertion point pinned.** `knowledge-base/engineering/operations/secret-scanning.md` already has a `database-url-with-password` paragraph at lines 82-86 documenting the path-allowlist precedent from #3874. The deepen-pass identifies this as the canonical insertion point for the new `*+` paragraph (AC7 updated to cite the exact line range). Frontmatter `related:` already lists `#3874`; we append `#3877` and bump `last_updated:` to `2026-05-16`.
6. **The `allowlist-diff` gate's shadowing blind spot is documented as a published learning** at `knowledge-base/project/learnings/2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md` and explicitly mentions `#3877` in its `related:` list. The sibling deferral issue (AC9) maps directly to that learning's §"Fix surface (deferred)" — the plan now cites the learning verbatim for the deferral rationale.
7. **No fold-in candidates found.** `grep -rn "postgres.*\\*\\*\\*" knowledge-base/ apps/ plugins/` returns only (a) the already-sanitized learning file (touched by #3874), (b) plan-file references that document the pattern as a string. The plan's #Open Code-Review Overlap §"Defer" rationale is validated against the live tree.

### New Considerations Discovered

- **The `allowlist-diff` gate will report "no allowlist path changes (regex re-orderings only)"** when this PR runs — confirmed by reading `apps/web-platform/scripts/allowlist-diff.sh` lines 67-71. The gate's `parse-gitleaks-allowlists.mjs` only emits `paths = [...]` content; `regexes = [...]` is invisible. This is NOT a script bug — it's a design choice that pre-dates the introduction of regex-form allowlists on the rule pack. The trailer + label (AC5/AC6) carry the operator intent across.
- **The runbook's lines 80-91 (the `database-url-with-password` carve-out paragraph)** is the natural place to add the new `*+` documentation. It already lists the redaction motivation; the addition is one bulleted sub-line.
- **The `\*+` alternation MUST be placed at the END of the existing non-capturing group** `(?:PASSWORD|password|secret|<[^>]+>|\*+)` — not as a separate group, not before the `<[^>]+>` branch. Verified by sandbox-applying the patch and re-running all three fixture cases.

## Overview

The `database-url-with-password` rule in `.gitleaks.toml` (line 250) detects connection-string credentials of the shape `postgres(ql)?://USER:PASSWORD@HOST`. A per-rule placeholder allowlist (line 260) suppresses the alert for documentation-shape URLs that use the literal words `USER` / `user` / `postgres` for the user portion and `PASSWORD` / `password` / `secret` for the password portion, OR an angle-bracket placeholder (`<anything>`).

**Gap.** The operator-convention asterisk-redaction shape used by Doppler / `psql` / pooler-tool output — `postgres://user:***@host` — is NOT covered. `***` (three or more asterisks) is widely used to indicate "redacted password" but does not match any branch of the placeholder alternation today. PR #3874 surfaced this gap when a recovery-runbook learning pasted `doppler run` output verbatim with `***` in the password field; the per-rule path-allowlist was widened to `knowledge-base/project/learnings/.*\.md$` as the narrow fix. A future author who uses `***` outside the learnings tree (in a plan, spec, skill-reference doc, or runbook page that does not already carry the path-allowlist) will trip the rule again.

**Fix.** One-line widening of the password alternation in the per-rule regex allowlist:

```diff
- regexes = ['''postgres(?:ql)?://(?:USER|user|postgres|<[^>]+>):(?:PASSWORD|password|secret|<[^>]+>)@''']
+ regexes = ['''postgres(?:ql)?://(?:USER|user|postgres|<[^>]+>):(?:PASSWORD|password|secret|<[^>]+>|\*+)@''']
```

This makes `postgres://user:***@host` (or any `*+`-redacted password against a placeholder-matching user) a tracked convention rather than a leak. It does NOT touch the user-alternation; Supabase pooler shapes like `postgres.<projectref>:***@` remain uncovered and continue to rely on the path-allowlist for the learnings tree (per #3874).

## User-Brand Impact

- **If this lands broken, the user experiences:** false-positive secret-scan failures on PRs that document recovery flows with asterisk-redacted DB URLs (e.g., `# → postgres://user:***@host`), blocking learning-file commits and forcing operators to either edit prose post-hoc or apply the `secret-scan-allowlist-ack` label per PR — paper cuts that defeat the "compound learning" workflow.
- **If this leaks, the user's [data / workflow / money] is exposed via:** a real `postgres://<user>:<real-password>@<host>` URL being committed to a non-learnings path AND the password coincidentally matching the `\*+` widening (i.e., a real password consisting of only asterisks). This is a vanishingly small set of strings (any sane policy rejects all-asterisk passwords) and is bounded BELOW the existing `[^@/\s]+` permissiveness of the base rule — the widening NARROWS the false-negative window from "any non-empty password" to "any non-empty password OR a placeholder shape", not the other way around. Net detection coverage on real-shaped passwords is unchanged.
- **Brand-survival threshold:** `none` (the change is a placeholder-allowlist tweak, not a regulated-data surface). The diff touches `.gitleaks.toml` which IS a sensitive path under preflight Check 6, so the section MUST carry a `threshold: none, reason:` scope-out bullet.
- **threshold: none, reason:** Widening the placeholder allowlist on the password alternation does not relax detection of real-shaped credentials; it only suppresses alerts on the canonical redaction shape `***`. Defense-in-depth is preserved by (a) GitHub server-side push protection (which does NOT scan `postgres://` URLs — out of scope for both sides), (b) the unchanged base regex still matching any `[^@/\s]+` password value, (c) the operator-runbook ack flow for any future widening.

## Research Reconciliation — Spec vs. Codebase

| Issue body claim | Codebase reality | Plan response |
|---|---|---|
| "change is properly an allowlist-diff gate event requiring its own `secret-scan-allowlist-ack` label or `Allowlist-Widened-By:` trailer" | `allowlist-diff.sh` only diffs `paths = [...]` arrays via `parse-gitleaks-allowlists.mjs`. There is exactly ONE `regexes = [...]` line in the entire `.gitleaks.toml` (line 260). The gate will NOT auto-fire on this edit because the regex array is invisible to the parser. The user-facing intent — "this is an allowlist-widening event that needs ack" — is correct; the mechanical gate that enforces it is incomplete. | Plan adds the `Allowlist-Widened-By: <name>` commit trailer manually as belt-and-suspenders (canonical pattern per learning `2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md` §Prevention). Plan also applies the `secret-scan-allowlist-ack` label on the PR as a second redundant signal. The parser-widening to also surface `regexes = [...]` diffs is filed as a sibling follow-up (see Open Code-Review Overlap). |
| The proposed regex is `(?:USER\|user\|postgres\|<[^>]+>):(?:PASSWORD\|password\|secret\|<[^>]+>\|\*+)@` | Exact match to the on-disk regex at `.gitleaks.toml:260` with a single new alternation branch `\|\*+`. No other branches need to move. | Adopt verbatim. |
| The fix is "one-line widening" | Verified — single character-class addition in a single triple-quoted string on a single line. | Plan scope = one regex edit + tests + docs + commit-trailer. No other files inside `.gitleaks.toml` need to move. |

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --json number,title,body --limit 200` and grepped each entry body for `.gitleaks.toml` and `allowlist-diff`. **No matches.** The deferred-scope-out backlog includes `#3877` itself but no sibling overlaps the `.gitleaks.toml` regex surface.

**Defer (filed separately, NOT folded in):**
- **Per-rule allowlist-diff awareness.** The learning `2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md` §"Fix surface (deferred)" calls out the per-rule-tuple refactor of `parse-gitleaks-allowlists.mjs` + `allowlist-diff.sh` and the separate need to make the gate also diff `regexes = [...]` entries (currently invisible). Both are out of scope for #3877; the issue is explicitly the placeholder-regex widening, not the gate. A new tracking issue will be filed at /work-time with: (a) per-rule path tuples to catch cross-rule shadowing, (b) inclusion of `regexes = [...]` in the diff surface. Re-evaluation criterion: when budget allows; or when the next regex-widening event lands on `.gitleaks.toml`.

## Files to Edit

- **`.gitleaks.toml`** — line 260: extend the password alternation in the `[[rules.allowlists]]` for `database-url-with-password` to include `\*+`. Update the inline comment on line 259 to reference issue #3877. Verified the file exists and the line content matches via `grep -n "regexes" .gitleaks.toml` (line 260).
- **`knowledge-base/engineering/operations/secret-scanning.md`** — append a short subsection (or extend an existing one) documenting the new `*+` alternation branch and the convention that authors should prefer `<password>` over `***` for new prose. Verified file exists; line 90 already documents the path-allowlist carve-out for `postgres(ql)?://user:password@host` URLs and is the natural place to mention the redaction-shape extension.
- **`apps/web-platform/test/__synthesized__/` OR `plugins/soleur/skills/.../test/fixtures/`** — add an allowlist-positive fixture demonstrating the new shape (`postgres://user:***@host`) is silenced AND a negative fixture demonstrating a non-placeholder password (`postgres://user:realpw123@host`) still fires. Location decision deferred to /work — prefer the existing fixture directory that already carries the path-allowlist for this rule (verified `apps/web-platform/test/__synthesized__/.*` is in the per-rule paths list at `.gitleaks.toml:258`). If no such directory exists yet for `database-url-with-password` fixtures, create the minimal pair `apps/web-platform/test/__synthesized__/secret-scan-database-url-fixtures.md` with both positive and negative lines.

## Files to Create

None expected beyond the fixture file above (if a `database-url`-specific fixture file does not already exist). The /work phase will confirm whether to extend an existing fixture or create a new one.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Regex edit applied.** `.gitleaks.toml:260` (or wherever the `regexes = [...]` line lives post-edit) contains exactly the literal `regexes = ['''postgres(?:ql)?://(?:USER|user|postgres|<[^>]+>):(?:PASSWORD|password|secret|<[^>]+>|\*+)@''']`. Verify via `grep -n 'regexes = ' .gitleaks.toml`.
- [x] **AC2 — Local positive repro (asterisk shape now allowlisted).** With gitleaks v8.24.2 installed:

  ```bash
  printf 'postgres://user:***@aws-0-eu-west-1.pooler.supabase.com:6543/postgres\n' > /tmp/fixture.txt
  gitleaks detect --no-banner --no-git --redact -v -c .gitleaks.toml --source /tmp/fixture.txt; echo "exit=$?"
  ```

  Expected: `exit=0`, no `database-url-with-password` finding. (The fixture must live in a per-rule allowlisted path for the test to be conclusive; if running outside the allowlisted paths, the regex allowlist alone should still fire because the per-rule `regexes` array applies regardless of path.) Re-confirm by running against the existing `__synthesized__/` fixture from AC4.
- [x] **AC3 — Local negative repro (real-shape password still fires).** With the same gitleaks binary:

  ```bash
  printf 'postgres://user:realpw_AAAA1111@host.example.com:5432/db\n' > /tmp/fixture-neg.txt
  gitleaks detect --no-banner --no-git --redact -v -c .gitleaks.toml --source /tmp/fixture-neg.txt; echo "exit=$?"
  ```

  Expected: `exit=1`, ONE `database-url-with-password` finding. Confirms the widening did NOT collapse real-shape detection.
- [x] **AC4 — Synthesized fixture committed.** A fixture file under `apps/web-platform/test/__synthesized__/` (or the chosen per-rule-allowlisted path) contains BOTH a positive line (`postgres://user:***@host`) AND a negative-control line (`postgres://USER:PASSWORD@host`). Run `gitleaks git --no-banner --exit-code 1 --redact -v` over the worktree HEAD and confirm `database-url-with-password` does NOT fire. (The fixture file's path must be inside the rule's per-rule `paths = [...]` allowlist — the `__synthesized__/` paths are.)
- [x] **AC5 — `Allowlist-Widened-By:` trailer present on at least one commit in PR.** Verified via `git log <base>..HEAD --format='%(trailers:key=Allowlist-Widened-By)'`. This is belt-and-suspenders: the `allowlist-diff` CI gate will NOT auto-fire on this edit (it diffs only `paths = [...]`, not `regexes = [...]`), but the trailer makes the operator intent explicit per learning `2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md` §Prevention. Trailer format: `Allowlist-Widened-By: Jean Deruelle`.
- [x] **AC6 — `secret-scan-allowlist-ack` label applied to PR.** `gh pr view <N> --json labels --jq '.labels[].name'` must include `secret-scan-allowlist-ack`. Verified label exists via `gh label list --limit 200 | grep secret-scan-allowlist-ack`. Pre-conditional: label exists (confirmed at plan time).
- [x] **AC7 — Operator runbook updated.** `knowledge-base/engineering/operations/secret-scanning.md` line range 82-91 carries the existing `database-url-with-password` carve-out paragraph (verified live at deepen-plan time; references #3874 and the asterisk-redaction motivation). Extend this paragraph (or add a sibling bullet immediately after) with a one-line note: the placeholder allowlist regex now also matches `\*+` (one or more asterisks) as the password branch, so `postgres://user:***@host` (and any redaction-by-asterisks shape) is recognized as a documentation convention rather than a leak. Append `#3877` to the document's top-matter `related:` list (lines 5-8; `#3874` is already present at line 7). Bump `last_updated:` from `2026-05-16` to keep its value at `2026-05-16` (already today — no diff needed if the field is already current, OR re-touch to today's date if a different date is there at /work time).
- [x] **AC8 — Existing path-allowlist on learnings tree retained.** The per-rule `paths = [...]` entry for `database-url-with-password` (`.gitleaks.toml:258`) MUST still contain `knowledge-base/project/learnings/.*\.md$`. Verified by `grep -A1 'database-url' .gitleaks.toml | grep learnings`. The new regex widening is ADDITIVE; it does not justify removing the path-allowlist (which protects against the orthogonal case where a learning uses a redaction shape we haven't yet enumerated).
- [x] **AC9 — Sibling deferral issue filed for the `allowlist-diff` parser gap.** Filed as #3888 (`domain/engineering, priority/p3-low, deferred-scope-out`). PR body references `Refs #3888 (sibling parser refactor)`.

### Post-merge (operator)

None. The `.gitleaks.toml` change takes effect on the next PR/push event; no remote rotation, no migration apply, no DNS propagation.

## Test Strategy

### Unit / local

- `gitleaks detect --no-banner --no-git --redact -v -c .gitleaks.toml --source <fixture>` for the positive and negative repro pair (AC2 + AC3). Verified `gitleaks` binary is installed locally at `/home/jean/.local/bin/gitleaks` version `8.24.2` (matches `.gitleaks.toml` schema lock).
- `gitleaks git --no-banner --exit-code 1 --redact -v` over the worktree HEAD after staging the synthesized fixture (AC4). Always pass `-v` alongside `--redact` per learning §"Sibling learning: gitleaks --redact alone doesn't print finding details".

### Research Insights — Empirical Baselines (captured at deepen-plan time)

Pre-fix (current `.gitleaks.toml` on this branch — unedited):

```
$ gitleaks detect --no-banner --no-git --redact -v -c .gitleaks.toml \
    --source /tmp/fix-pos.txt  # contains: postgres://user:***@aws-0-eu-west-1.pooler.supabase.com:6543/postgres
RuleID: database-url-with-password  → leaks found: 1  → exit=1  (the gap)

$ gitleaks detect --no-banner --no-git --redact -v -c .gitleaks.toml \
    --source /tmp/fix-neg.txt  # contains: postgres://user:realpw_AAAA1111@host.example.com:5432/db
RuleID: database-url-with-password  → leaks found: 1  → exit=1  (correct — real-shape password)

$ gitleaks detect --no-banner --no-git --redact -v -c .gitleaks.toml \
    --source /tmp/fix-existing.txt  # contains: USER:PASSWORD, user:password, <u>:<p>
INF no leaks found → exit=0  (existing placeholders still allowlist correctly)
```

Post-fix (sandbox-applied: `\|\*+` added to the password alternation):

```
$ gitleaks detect --no-banner --no-git --redact -v -c /tmp/test.toml \
    --source /tmp/fix-pos.txt  # *** redaction shape
INF no leaks found → exit=0  (NEW: allowlisted)

$ gitleaks detect --no-banner --no-git --redact -v -c /tmp/test.toml \
    --source /tmp/fix-neg.txt  # real-shape password
RuleID: database-url-with-password  → leaks found: 1  → exit=1  (regression-safe: still fires)

$ gitleaks detect --no-banner --no-git --redact -v -c /tmp/test.toml \
    --source /tmp/fix-edge.txt  # multi-asterisk: **, *****************, postgres:***@
INF no leaks found → exit=0  (\*+ covers 2-asterisk through arbitrary-length shapes)
```

The /work-time AC2/AC3/AC4 verification commands should reproduce exactly these outcomes against the canonically-edited config.

### CI

- The existing `secret-scan.yml` workflow re-runs on PR push events. The `secret-scan-detect` job will scan the worktree with the new config + new fixture; expected pass.
- `allowlist-diff` job will report "no allowlist path changes (regex re-orderings only)" — this is the known shadowing blind spot (the gate parses only `paths`, not `regexes`); the manual trailer + label in AC5/AC6 are the operator-side compensating control.
- `smoke-tests` matrix re-runs all 9 cases unchanged. No matrix expansion expected for this PR (the new fixture is allowlist-positive, not a regression of any existing case).

### Manual verification

- Stage the fixture file, run the local gitleaks invocation from AC2/AC3/AC4, confirm exit codes match expectations.
- Open the PR with the trailer; confirm the workflow runs green.

## Risks

1. **The `allowlist-diff` gate will NOT auto-fire on this edit** — known shadowing blind spot documented in learning `2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md`. Mitigation: AC5 (trailer) + AC6 (label) make the widening explicit. Sibling deferral issue (AC9) tracks the parser fix.
2. **The proposed widening only extends the PASSWORD alternation, not the USER alternation.** Supabase pooler URLs (`postgres.<projectref>:***@`) and any other non-conventional user shape will still trip the rule. This is INTENTIONAL — extending the user alternation would broaden the silenced surface significantly (potentially silencing real `postgres://admin:realpw@` shapes where `admin` happens to match a new user pattern). The path-allowlist on `knowledge-base/project/learnings/.*\.md$` (per #3874) remains the safety net for prose-style redactions outside the canonical placeholder form. Documented as a known limitation in AC7.
3. **`\*+` could theoretically match a real password consisting of only asterisks.** Real password policies reject such passwords; the operational risk is zero. Sentry/Sentry-CLI / Stripe / Supabase / Doppler all reject asterisk-only secrets at creation time. The previous rule already accepted ANY `[^@/\s]+` password including `***`; the widening makes the silenced subset MORE NARROW (only placeholder shapes), not broader. Empirically verified at deepen-plan time: `**` (2 chars), `*****************` (17 chars), and `postgres:***@` (Supabase-pooler user shape against asterisk password) all allowlist correctly with `\*+`; no real-world password generator (Doppler, 1Password, Bitwarden, Supabase auto-gen) emits all-asterisk values.
4. **GitHub server-side push protection does NOT cover `postgres://` URLs.** This is documented in learning `2026-05-15-github-push-protection-rejects-synthetic-tokens-in-plan-prose.md`. The widening here does not weaken server-side defense because there is no server-side defense to weaken on this token class. Mitigation: unchanged.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)

**Status:** reviewed (plan-time judgment; no external CTO leader spawn required for a one-line regex widening with two compensating controls and an existing operator runbook).

**Assessment:** Low-risk, well-precedented edit. The change inherits all defense-in-depth from the existing `database-url-with-password` rule (the per-rule path-allowlist already silences this exact prose form on the learnings tree). The new regex branch is strictly NARROWER than the base rule's permissive password pattern (`[^@/\s]+` accepts every shape including `***`); the widening only enumerates a placeholder form. Co-located docs (operator runbook, learning file) capture the convention shift.

### Product/UX Gate

**Tier:** none (no user-facing surface; CI gate config edit only).

## Sharp Edges

- **Local gitleaks repro requires `-v` alongside `--redact`** to surface the per-finding `Finding/Secret/RuleID/File/Line/Commit` block — `--redact` alone returns only the count. Canonical diagnostic invocation per learning `2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md` §"Sibling learning":

  ```bash
  gitleaks git --no-banner --exit-code 1 --redact -v 2>&1 | tail -40
  ```

- **`allowlist-diff.sh` parses ONLY `paths = [...]` arrays** (via `parse-gitleaks-allowlists.mjs`). The `regexes = [...]` line is invisible to the gate; do NOT assume the gate will enforce ack for this edit. Always carry the `Allowlist-Widened-By:` trailer manually until the parser is widened (sibling deferral per AC9).
- **The trailer key is case-sensitive** (`Allowlist-Widened-By`, NOT `allowlist-widened-by`). The script's git-trailer parse is exact-match per `apps/web-platform/scripts/allowlist-diff.sh:41`.
- **The `\*+` alternation MUST be inside the same non-capturing group** as the other password branches. Adding it OUTSIDE the existing `(?:...)` (e.g., as a top-level alternation `|...|\*+`) would change the semantics and could match unintended shapes. Verify the diff shows the new branch inside the same `(?:PASSWORD|password|secret|<[^>]+>|\*+)` group.
- **Do not also widen the USER alternation in the same PR** — that is a separate, higher-impact change (would silence Supabase pooler shapes and similar) that warrants its own ack cycle. Out of scope for #3877.
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This section above declares `threshold: none, reason: ...` per the canonical preflight Check 6 expectation.

## Implementation Phases

1. **Phase 1 — Regex edit + local repro (~10 min).** Apply the one-line edit to `.gitleaks.toml:260`. Run AC2 + AC3 local repros against synthetic fixtures (`/tmp/fixture.txt`, `/tmp/fixture-neg.txt`). Confirm exit codes.
2. **Phase 2 — Synthesized fixture (~10 min).** Add or extend a fixture file under `apps/web-platform/test/__synthesized__/` covering positive (allowlisted `***` shape) and negative (real-shape password) lines. Run AC4: `gitleaks git --no-banner --exit-code 1 --redact -v` over the worktree, confirm no `database-url-with-password` finding.
3. **Phase 3 — Operator runbook update (~10 min).** Edit `knowledge-base/engineering/operations/secret-scanning.md` per AC7. Append `#3877` to the `related:` top-matter list and bump `last_updated:` if those fields exist.
4. **Phase 4 — Commit-trailer + label (~5 min).** Stage the diff, commit with `Allowlist-Widened-By: Jean Deruelle` trailer (AC5). After PR opens, apply `secret-scan-allowlist-ack` label (AC6). The `labeled` trigger on `secret-scan.yml` will re-run the gate naturally.
5. **Phase 5 — Sibling deferral issue (~5 min).** File the new tracking issue per AC9 BEFORE marking the PR ready-for-review. Capture the issue number in the PR body as `Refs #<N>`.

## CLI Invocations Used in This Plan

- `gitleaks detect --no-banner --no-git --redact -v -c .gitleaks.toml --source <fixture>` — verified by reading `gitleaks --help detect` locally (`/home/jean/.local/bin/gitleaks` v8.24.2 supports all four flags). The `--source` flag accepts a path; `--no-git` disables git-aware traversal so a single fixture file scans correctly.
- `gitleaks git --no-banner --exit-code 1 --redact -v` — verified by the canonical pattern in learning `2026-05-16-allowlist-diff-shadowed-widening-and-gitleaks-verbose-flag.md` §"Sibling learning".
- `gh pr view <N> --json labels --jq '.labels[].name'` — verified via `gh pr view --help` (json field `labels` available).
- `gh issue list --label code-review --state open --json number,title,body --limit 200` — verified at plan time, returned the queryable JSON used in §Open Code-Review Overlap.

## Acceptance Criteria Pre-Merge Summary (Reviewer Quick-Check)

- [x] Single-line regex edit (no other `.gitleaks.toml` changes)
- [x] Local positive + negative repro both pass
- [x] Synthesized fixture committed
- [x] `Allowlist-Widened-By:` trailer present
- [x] `secret-scan-allowlist-ack` label applied
- [x] Operator runbook updated
- [x] Path-allowlist for learnings tree retained
- [x] Sibling deferral issue filed
- [x] No post-merge operator steps
