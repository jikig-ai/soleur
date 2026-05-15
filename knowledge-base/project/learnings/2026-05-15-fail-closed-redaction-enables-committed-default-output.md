# Learning: Fail-closed redaction enables committed-default output for security-aggregating artifacts

## Problem

The `2026-02-16-inline-only-output-for-security-agents.md` learning crystallized "the aggregation is the risk, not the individual facts" and pushed security-aggregating artifacts (PRDs, audit reports, full-codebase summaries) toward gitignored-by-default output paths. The implicit corollary was: "if it aggregates, don't commit it by default."

Applied uncritically, that rule pushes every new aggregating artifact onto a gitignored path. But some artifacts — like a code-to-prd PRD — are *meant* to be shared externally. Forcing the operator to manually move the file to a committed path before sharing makes the founder the last line of defense against secret leakage. That's exactly what the `code-to-prd` brainstorm operator pushed back on: "Soleur should automatically check for leaks; founder shouldn't have to verify manually."

## Solution

When the artifact MUST be reviewable and shareable, replace the gitignored-default heuristic with a **4-layer fail-closed redaction stack**. Committed-by-default becomes acceptable only when all four layers run:

1. **Pre-scan path exclusion** — walker uses `git ls-files -c -o --exclude-standard` (respects `.gitignore`) plus an explicit deny-list (`.env*`, `*.pem`, `*.key`, `credentials.*`, `master.key`). No file matching deny-list is ever read into memory.
2. **Input sanitization** — every file content chunk passes through the existing `redact-sentinel.sh` (14 secret classes) before being incorporated into the template. Matches replaced with `[REDACTED:type]`.
3. **Pre-write sentinel** — rendered output passes through `redact-sentinel.sh` immediately before disk write. Exit code 1 (matches found) MUST abort write; no partial output ever lands on disk.
4. **Post-write verifier** — independent re-scan (`gitleaks detect --source <path> --no-git`) deletes the written file if anything escapes layers 1–3.

Layer 3 is the load-bearing gate. Layers 1, 2, 4 are defense-in-depth. The combination flips the trust model: instead of "operator verifies before committing," the artifact verifies itself before existing on disk.

## Key Insight

The committed-by-default / gitignored-by-default choice is downstream of the redaction architecture, not upstream. **Aggregation-is-the-risk** is still true; what changes is the *mitigation*. Fail-closed redaction at the write boundary is a stronger mitigation than gitignoring, because it survives operator carelessness (gitignored files can still be `cp`'d into the share path manually).

The reusable pattern: when an artifact is meant for external sharing AND can plausibly contain secrets/PII, build the redaction stack first, then choose the output path based on what the founder needs to do with the file. Don't choose the path first and bolt redaction onto whichever path won.

## Session Errors

**Path confusion after worktree cd** — Initial `ls .worktrees/feat-code-to-prd-2726/...` returned "no such file" because the bash session retained the worktree's cwd from an earlier `cd`, double-resolving the relative path. Recovery: switched to absolute paths.  Prevention: existing learning `2026-04-17-brainstorm-verify-existing-artifacts-and-mount-sites.md` already covers this exact pattern (file-existence verification with absolute paths); no new rule needed.

## When This Applies

- A new skill or agent generates a markdown artifact derived from user code, config, or data.
- The artifact is meant to be shared externally (buyer, contractor, agent, investor).
- The artifact can plausibly contain secrets, PII, or proprietary IP.

When this does NOT apply: artifacts that stay local, artifacts the user never shares, or artifacts that contain only structural metadata (no user-content quotation).

## Tags

category: design-patterns
module: skill-design
related:
  - knowledge-base/project/learnings/2026-02-16-inline-only-output-for-security-agents.md
  - knowledge-base/project/learnings/2026-02-21-private-document-generation-pattern.md
  - knowledge-base/project/brainstorms/2026-05-15-code-to-prd-brainstorm.md
  - knowledge-base/project/specs/feat-code-to-prd-2726/spec.md
issue: 2726
