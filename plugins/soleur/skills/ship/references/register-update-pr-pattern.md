# Register / Policy Update PR Pattern

When the PR diff is bounded to `knowledge-base/legal/**` or `docs/legal/**` and
the body documents controls introduced by an ALREADY-MERGED upstream PR
(typical for follow-through register updates per `/soleur:ship` Phase 7
Step 3.5 — see PR #3882), the PR-body authoring rules differ from a normal
code-change PR.

## Cite by semantic identifier in the body

Reference upstream PR contents via SEMANTIC IDENTIFIERS, not by file path:

- ✅ Function / method / handler names — `getFreshTenantClient`,
  `runWithByokLease`, `assertWriteScope`, `refreshSubscriptionStatus.tenantFor`
- ✅ RPC names — `accept_terms`, `sum_user_mtd_cost`, `anonymise_tc_acceptances`
- ✅ Migration anchors — `001`, `018_team_names.sql`, `029` (full filename or
  bare stem; both forms are anchored by the `verify-migrations` auto-close job)
- ✅ Symbol references inside the register file itself — `PA1 row (6)`,
  `PA2 row (4)`, `counsel-review item 6`

AVOID full file paths in PROSE when those paths are not in this PR's diff:

- ❌ `apps/web-platform/server/cc-dispatcher.ts:889`
- ❌ `docs/legal/privacy-policy.md`
- ❌ `server/byok-lease.ts`

If a file-path reference is genuinely necessary for clarity, wrap it in inline
backticks — `` `server/cc-dispatcher.ts:889` `` — which the `pr-body-vs-diff`
gate exempts (see [`#3882`](https://github.com/jikig-ai/soleur/pull/3882) and
[`check-pr-body-vs-diff.sh`](../../../../.github/scripts/check-pr-body-vs-diff.sh)
inline-`code`-span strip).

## The register file itself is implementation-cited

The Article 30 register
([`knowledge-base/legal/article-30-register.md`](../../../../knowledge-base/legal/article-30-register.md))
follows the PA10/PA11 convention of citing exact file paths + line numbers
inline in the TOM cells — that's the load-bearing accountability evidence
under GDPR Art. 5(2). This guidance applies to the **PR BODY only**, not to
the register's prose.

The asymmetry is deliberate: the register's audience is a supervisory
authority probing for traceability (paths + line numbers help); the PR body's
audience is the reviewer + the `pr-body-vs-diff` CI gate (paths read as
"diff-claim hallucinations" when they're not in the diff).

## Why the gate fires on legitimate citations

`.github/scripts/check-pr-body-vs-diff.sh` (issue #2905) fails when fewer than
50% of file-path tokens in the PR body's prose appear in the PR's diff. The
gate cannot distinguish a legitimate cross-reference from a hallucinated path.
Register / policy-update PRs document controls implemented in OTHER files;
those file paths legitimately are not in the diff.

As of PR #3882's follow-up fix, inline-backtick code spans are stripped before
path extraction. Plain-prose paths are still checked — a body claim like
"I edited foo.ts to fix the bug" must still match the diff.

## Override (last resort)

If a PR body genuinely needs plain-prose file-path citations and the gate
fires, add the `confirm:claude-config-change` label. The label name is a
precedent artifact (originally for `.claude/` config changes); reusing it for
legal/register PRs is acceptable until a more semantically-fit label is
introduced.
