# GitHub Issue Creation for Review Findings

## Label Prerequisite

Before creating the first issue, verify the `code-review` label exists:

```bash
gh label list --search "code-review" --json name --jq '.[0].name // empty'
```

If empty, create it:

```bash
gh label create code-review --description "Finding from code review" --color 0E8A16
```

## Issue Body Template

The body is written to a temporary file and passed via `--body-file` to avoid `$()` command substitution permission prompts and handle arbitrary markdown safely.

**Template content (write to `/tmp/review-finding-NNN.md`):**

```markdown
**Source:** PR #<pr_number> review | **Effort:** <Small|Medium|Large> | **Provenance:** <pr-introduced|pre-existing> | **Re-eval by:** <concrete trigger — see Field rules>

## Problem

<description>

**Location:** `<file_path>:<line_number>`

## Proposed Fix

<recommended fix>

## Acceptance Criteria

- [ ] <criterion_1>
- [ ] <criterion_2>
```

**Field rules:**

- `Provenance:` is required on every filed issue.
  - `pr-introduced` findings MUST be fixed inline — they should not reach the issue-creation step. If one does reach it, abort the filing and fix inline instead.
  - `pre-existing` findings MUST carry the `pre-existing-unrelated` scope-out criterion in the `## Scope-Out Justification` section.
- `Re-eval by:` is required on every scope-out filing. The value MUST take exactly ONE of these four concrete forms (this file is the canonical enumeration; sibling SKILL.md sections reference back here): {#re-evaluation-trigger}
  1. **Date trigger** — `Re-evaluate by YYYY-MM-DD`. Calendar-anchored review. → **verification:** directive `earliest=<date>T00:00:00Z` + a trivial `exit 0` script body — the `earliest` wall-clock gate alone defers closure until the date.
  2. **Counter trigger** — `Re-evaluate when <observable counter> exceeds <threshold>`. Counter MUST be queryable via SQL, the `gh` API, or another deterministic data source. Example: `Re-evaluate when count(distinct authenticated founders in auth.users.last_sign_in_at > now() - 30 days) >= 2`. → **verification:** a `gh`/SQL/grep count check — `[[ "$count" -ge "$threshold" ]] && exit 0 || exit 2` (exit 0 when met, else transient).
  3. **Event-grep trigger** — `Re-evaluate when <grep pattern> matches in <log/issue/PR scope>`. Pattern MUST be a literal regex or substring runnable against a defined corpus (Sentry tags, GitHub issue bodies, workflow logs). Example: `Re-evaluate when Sentry tag tenant-jwt op=is_jti_denied.deny co-occurs with internal_error for same userId within ±60s window`. → **verification:** the corpus probe (`gh run list --workflow X --status success --created ">=cutoff"`, `gh issue list`, or a Sentry grep) nonempty ? `exit 0` : `exit 2`.
  4. **Dependency trigger** — `Re-evaluate when #<N> lands`, where `#<N>` is a concrete open issue or PR. **Human-gate triggers** are a sub-form of dependency triggers: file a `gh issue` assigned to the named human (lawyer / security auditor / design reviewer / exec sign-off) with the review request as the issue body, then your scope-out's dependency trigger is `Re-evaluate when #<that-issue> lands`. This keeps the trigger concrete (an `#N` ref) and assigns ownership to the gating party. → **verification:** `[[ "$(gh issue view <N> --json state --jq .state)" == CLOSED ]] && exit 0 || exit 2`.

  These `→ verification:` probes are the close gate for the follow-through sweeper: when a scope-out is filed with a `follow-through` label + a `<!-- soleur:followthrough -->` directive, the named script's exit 0 auto-closes the issue (exit 1 = FAIL-comment, other = transient-retry). Any gh-using probe (the 3 non-date shapes) MUST declare `secrets=GH_TOKEN` in its directive — the sweeper's `env -i` sandbox strips it otherwise and the probe silently never closes. Full mapping + script-scaffolding contract: [`knowledge-base/engineering/operations/runbooks/followthrough-convention.md`](../../../../../knowledge-base/engineering/operations/runbooks/followthrough-convention.md) §Trigger → verification mapping.
- **Rejected phrasings** (will be DISSENTed at the CONCUR gate and BLOCKED at /ship Phase 5.5): "when it feels right", "when ready", "when we have more users" (un-counted), "post-MVP", "later", "eventually", "when this is a problem", or a bare phase label with no linked phase-completion issue. Convert to one of the four concrete forms above. Open-ended scope-outs become the backlog this template exists to drain.
- Do not copy free-form text from PR review comments or external sources into `Re-eval by:` or any other field. Use a GitHub issue reference (`#N`), an ISO date, a queryable counter, or a literal grep pattern. This closes a phishing vector where a malicious PR review comment embeds a markdown link that is rendered on the filed issue.

Enforcement is instruction-level (this template) plus the Phase 5.5 exit gate. A pre-commit linter on issue bodies is deferred until violations are actually observed.

## Label Selection

| Review Severity    | Priority Label       | Domain Label          |
|--------------------|----------------------|-----------------------|
| P1 (CRITICAL)      | `priority/p1-high`   | `domain/engineering`  |
| P2 (IMPORTANT)     | `priority/p2-medium` | `domain/engineering`  |
| P3 (NICE-TO-HAVE)  | `priority/p3-low`    | `domain/engineering`  |

Default domain is `domain/engineering`. Override to `domain/product` for agent-native findings that are clearly product-scoped.

Every issue gets the `code-review` label in addition to priority and domain labels.

## Milestone Selection

P1 findings get the current active milestone. P2/P3 findings get `Post-MVP / Later`.

Detect the active milestone:

```bash
gh api repos/:owner/:repo/milestones --jq '[.[] | select(.state=="open") | select(.title | startswith("Phase"))] | sort_by(.due_on) | .[0].title // "Post-MVP / Later"'
```

## Duplicate Detection

Before creating an issue, check if one already exists for this finding from the same PR:

```bash
gh issue list --label code-review --state all --search "review: <description>" --json number,title --jq '.[0].number // empty'
```

`--state all` is load-bearing (#6786): `gh issue list` defaults to open-only, and under the
fix-inline default a review issue is filed and then CLOSED once resolved — which is the normal
resting state. An open-only probe therefore cannot see the duplicate it exists to find, and
re-files it on every subsequent run.

If a match exists, skip creation and reference the existing issue in the summary.

## Creation Command

```text
# 1. Write body to temp file (using Write tool, not echo/cat)
# 2. Create issue with --body-file
gh issue create \
  --title "review: <description>" \
  --body-file /tmp/review-finding-NNN.md \
  --label code-review \
  --label priority/p2-medium \
  --label domain/engineering \
  --milestone "Post-MVP / Later"
```

## Error Handling

If `gh issue create` exits non-zero for a finding, log the error and continue to the next finding. Do not block the entire review synthesis on one failed issue creation. Report failed creations in the summary.

## Batch Strategy

For reviews with 15+ findings, create issues sequentially to avoid GitHub API rate limits. For smaller batches, parallel creation via sub-agents is acceptable.

## Execution Strategy

1. Synthesize all findings into categories (P1/P2/P3)
2. Run label prerequisite check
3. Detect active milestone for P1 findings
4. For each finding:
   - Run duplicate detection
   - Write issue body to temp file
   - Create GitHub issue with appropriate labels and milestone
   - Record issue URL for summary
5. Present summary with all created issue URLs

## Severity Values

- `P1` - Critical (blocks merge, security/data issues)
- `P2` - Important (should fix, architectural/performance)
- `P3` - Nice-to-have (enhancements, cleanup)

### Bundling example

> Item A: "admin-role design cycle — current implementation hardcodes
> founder-only check; defer until admin role lands."
> Item B: "RPC signature evolution for admin role — `is_admin()` needs to
> accept role hierarchy; defer until admin role lands."
>
> Both trigger when admin role lands (same event). File ONE issue titled
> `review: admin-role landing follow-ups` with a `## Sub-Tasks` checklist:
>
> ```markdown
> - [ ] A: replace hardcoded founder-only check at <file>:<line>
> - [ ] B: extend `is_admin()` signature at <file>:<line>
> ```
>
> Single CONCUR call, single open issue, single closure when admin role lands.

## Sharp Edges

- `gh issue create --milestone <value>` resolves against milestone **title**, not number. `--milestone 6` fails with `could not add to milestone '6': '6' not found` even when milestone 6 exists. Retrieve the title via `gh api /repos/<owner>/<repo>/milestones --jq '.[] | {number, title}'` and pass the title. The `number` field is REST-API-only. **Why:** filing #2272 retried with `--milestone "Post-MVP / Later"` to succeed.
