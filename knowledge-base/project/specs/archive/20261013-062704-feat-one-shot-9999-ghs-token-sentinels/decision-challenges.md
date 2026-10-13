# Decision Challenges — feat-one-shot-9999-ghs-token-sentinels

Headless pipeline artifacts persisted per plan SKILL.md Step 4.5 / Plan Review headless arm (ADR-084 channel). Reviewer-visible; `soleur:ship` renders into the PR body + files as an `action-required` issue.

## 2026-10-11 — Planning session (soleur:plan, headless)

### CPO sign-off flag (requires_cpo_signoff: true)

Plan declares `brand_survival_threshold: single-user incident` — the run-scan/redaction-allowlist defect is a partial-credential-disclosure class (a ~390-char `ghs_` token's punctuation tail survives the mask inside scan output). `requires_cpo_signoff: true` is set in plan frontmatter per plan Phase 2.6. No CPO consult ran (this harness exposes no Task/subagent spawn); `soleur:engineering:review:user-impact-reviewer` is the review-time seat that must concur or challenge the threshold.

### Taste — folded scope beyond the issue's six sites

Two inferred scope folds, each flagged in `## Scope Check` provenance with justification — reviewers may descope without breaking the issue's acceptance:

1. **`redaction-allowlist.ts:71`** — a seventh same-class site the issue missed (TS redaction family regex; same truncation→leak shape as run-scan.sh, mandated by `hr-write-boundary-sentinel-sweep-all-write-sites`).
2. **GitHub-family widen** — `ghp_`/`gho_`/`ghr_` lines in `run-scan.sh` and `ghp_`/`gho_`/`github_pat_` in `SENSITIVE_QUERY_REGEX` also move to the canonical class. Rationale: under-match in a mask or a refusal guard is the same disclosure class; canonical is the fail-safe superset and vendor rotation of the siblings is the identical risk the issue fixes for `ghs_`. Descoping to `ghs_`-only edits is a legitimate reviewer call.

### Harness constraint (informational)

No Task/subagent spawn exists in this pipeline harness, so plan Phase 1/1.5b research, Phase 2.5 domain leaders, Phase 4.5 scoped advisor, and the Plan Review panel ran inline in the planning orchestrator rather than as separate agents. Sequential-fallback disclosure applies: no independent review ran at plan time.
