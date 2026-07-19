# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-19-fix-secret-scan-gitleaks-ref-scope-and-dsn-placeholder-plan.md
- Status: complete

### Errors
- Self-inflicted, caught and corrected in-session: (1) a verification harness using `grep -cE 'leaks found'`, which also matches `no leaks found` — produced a wrong safety matrix until switched to exit codes; (2) a fabricated issue reference written into the reconciliation table, removed; (3) an initial `## User-Brand Impact` section that failed deepen-plan gate 4.6 (sensitive path + `none` threshold with no `threshold: none, reason:` bullet).
- One research agent asserted `database-url-with-password` is a default-pack rule with same-ID shadowing risk. Verified false — it is a custom rule at `.gitleaks.toml:281`; the default pack is clean on a real DSN.

### Decisions
- **Layer 1: widen the `regexes` placeholder alternation** (`passwd|pass|pw`) on the existing custom rule — content-anchored, so SHA-independent and merge-strategy-proof. Rejected the path-scoped allowlist because it would blind the rule for `apps/web-platform/infra/`, exactly where a real DSN would land.
- **Layer 2: `--log-opts="--no-merges HEAD"` on `push:main`** — reproduced end-to-end (3228 commits/1 leak → 3094/clean with an unmerged branch ref present).
- **Cut the branch-attribution machinery for `-v`** — largest failure surface in the plan serving its smallest consumer; a failing `jq` under `pipefail` would turn a clean run red.
- **Detection coverage proven preserved** via a 20-fixture adversarial matrix (case variants, URL-encoding, Cyrillic homoglyph, colon-embedded secrets). The `@` anchor means only exact placeholder tokens go quiet.
- **Premises overturned by direct measurement:** the flagged line is the comment, not the scrubber; the current tree is already clean (finding is purely historical); `.gitleaksignore` fingerprints are merge-strategy-dependent and cannot satisfy "must survive the branch merging"; the repo does not exclusively squash-merge (35 merge commits on `main`).

### Components Invoked
`soleur:plan`, `soleur:deepen-plan` (gates 4.6–4.9), `repo-research-analyst`, `learnings-researcher`, `security-sentinel` (adversarial), `architecture-strategist`, plus direct measurement with pinned gitleaks v8.24.2, `gh`, and git.
