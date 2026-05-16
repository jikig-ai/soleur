---
category: best-practices
tags: [legal, runbooks, plan-time-discovery, cross-artifact-drift, gdpr]
date: 2026-05-16
issue: 3924
pr: 3920
---

# Legal-Prose Vocabulary Refactors Implicate Operational Runbooks

## Context

PR #3920 migrated the cla-evidence bucket from S3 Object Lock (which R2 does not implement) to CF native R2 Lock Rules. The PR's public surface was:

- `apps/cla-evidence/infra/object_lock.tf` — null_resource provisioner shape
- `apps/cla-evidence/infra/bootstrap.sh` — HMAC credential derivation
- `apps/cla-evidence/scripts/sentinel-pr.sh` — automation for Phase 8 sentinels
- `docs/legal/gdpr-policy.md` + `plugins/soleur/docs/pages/legal/gdpr-policy.md` — §2.2 + §3.4 vocabulary reword
- `knowledge-base/project/learnings/2026-05-04-cla-evidence-sidecar-pattern.md` — Section 12 explaining the API surface change

The plan correctly enumerated all five files. The multi-agent review (10 agents, parallel) added one finding the plan missed: **the operational runbook at `knowledge-base/engineering/ops/runbooks/cla-signature-evidence-retrieval.md` §7 was now stale**. §7.1 still told the operator to mint a CF token with "Bypass Governance Retention" permission (an S3 Object Lock concept R2 doesn't implement); §7.3 still described `aws s3api delete-object --bypass-governance-retention` (the exact S3 surface verified empirically as NotImplemented by R2).

The legal docs were updated to describe the NEW procedure ("temporarily edit the bucket lock-rule list to exclude the offending object, delete, restore") — but no PR file updated the runbook to match. An operator following §7 verbatim during a real GDPR Art. 17 request would have every step fail.

## The Drift Class

A PR that **rewords vocabulary in load-bearing legal documents** (privacy policy, GDPR policy, DPA, terms of service) creates an asymmetric drift surface: the public-facing prose advertises a procedure, while operational runbooks (private to the team) continue to describe the deprecated mechanism. The drift is invisible to:

- **Pattern-recognition / code-quality reviewers** — they read the diff, not the runbook
- **Architecture / data-integrity reviewers** — they verify the new design works, not that older docs follow
- **Author** — the PR author updates the files they're explicitly editing; nobody reminds them to grep for operational consumers of the vocabulary they changed

The only reviewer that surfaced this was **git-history-analyzer**, because it cross-checks documented procedures against the actual code paths and detects when the runbook references commands/permissions the codebase no longer supports.

## Detection at Plan Time (recommended cheap gate)

When a plan touches `docs/legal/*.md` or `plugins/soleur/docs/pages/legal/*.md` with vocabulary changes (mode names, permission names, API surfaces, command flags), add a Risk entry that names operational runbooks consuming the old vocabulary:

```bash
# Example gate during plan time, replacing <old-vocab> with the literal string
# being deprecated (e.g., "Object Lock Governance", "--bypass-governance-retention",
# "X-Vault-Token", "S3 Object Lock").
git grep -nl '<old-vocab>' knowledge-base/engineering/ops/runbooks/ docs/ apps/ plugins/ \
  | grep -v knowledge-base/project/learnings/ \
  | grep -v knowledge-base/project/plans/
```

Every file returned is a candidate for vocabulary alignment in the same PR. If the file is a runbook with embedded command sequences (not just prose), the alignment is operationally load-bearing — either update the runbook in the same PR OR add an explicit `Risk` entry citing it and a `Future-Work Tracking` issue.

## Why It's Easy to Miss

The legal-doc reword PR feels self-contained: the prose change is small, the legal claim is preserved, the unit test (`legal-doc-consistency.test.ts`) passes, the file-list grep returns the docs themselves. The runbook is a sibling artifact in a different directory, owned by ops (not legal, not infra), so it's not in the obvious "things this PR touches" scope.

The plan-time grep above catches it cheaply; the multi-agent review (specifically git-history-analyzer's "what does this PR claim, and what does the operational reality actually support?") also catches it. Both gates run; defense in depth.

## Inline Mitigation Pattern (when the runbook can't be fully rewritten in the same PR)

When the runbook update requires designing + testing a new operational procedure (e.g., here: validating the Lock-Rule-edit-delete-restore sequence against a real bucket), the safe inline mitigation is:

1. Add a stale-warning banner at the runbook header citing the PR + tracking issue.
2. Add `<details>` blocks around the deprecated command sequences with "STALE — see banner" markers.
3. Provide an interim high-level outline of the corrected procedure inline.
4. File a tracked follow-up issue for the full rewrite + tested driver script.

This keeps an unsuspecting operator from following the broken procedure verbatim while deferring the design work that genuinely needs separate consideration.

PR #3920 → #3924 (full §7 admin-override rewrite) is the canonical example.

## Session Errors

- **terraform fmt auto-reformat surprise on first apply.** Recovery: ran `terraform fmt`. **Prevention:** chain `terraform fmt && terraform fmt -check` post-Write to surface formatter diffs immediately.
- **AC1 grep false-positive on documentation-only comment.** The plan's AC for "no `aws s3api .* object-lock` literals" matched my own deprecation-explaining comment. Recovery: reworded the comment. **Prevention:** plan-time AC greps should anchor on actual code paths (file ranges, function names) rather than generic literals; OR explicitly document that even comments must avoid the deprecated vocabulary.
- **Static-lint grep drift after single-source refactor.** Refactoring `object_lock.tf` to `local.lock_rule_json` removed the literal JSON the `main.test.sh` static lint anchored on. Recovery: re-anchored on canonical HCL (`type = "Age"`, `maxAgeSeconds = 315360000`). **Prevention:** test-design M1 — static-lint regex MUST anchor on canonical source, not derived/mirrored strings. This session validates the pattern at scale.
- **Bash CWD non-persistence trap.** Multiple `cd` invocations across Bash tool calls failed silently when CWD reset between calls. **Prevention:** documented in AGENTS.md; use absolute paths or chain in single `&&`-joined invocation.
- **test-all.sh timeout-flake under concurrent load.** Three suites (`skill-security-scan`, `marketing-content-drift`, `jsonld-escaping`) all failed at the 5000ms vitest default when run concurrently; `skill-security-scan` passed in 74s isolated. **Prevention:** test-all.sh runs many suites in parallel; suites with heavy `spawnSync`/network setup need either a higher default timeout or `test-all.sh` retry-then-isolate-on-fail logic to distinguish flake from real regression.
- **gdpr-gate skill mis-scoped against legal-doc-only diff.** Canonical regex covers code paths (migrations + auth + .sql), not `docs/legal/*.md`. Gate correctly emitted no-trigger output. **Prevention:** verify regex match BEFORE invoking gdpr-gate; trust `hr-gdpr-gate-on-regulated-data-surfaces` to gate the invocation.
- **ScheduleWakeup outside /loop dynamic mode.** Wakeups scheduled outside `/loop` are a no-op friction; harness already notifies on background task completion. **Prevention:** never set ScheduleWakeup as a substitute for harness task-notification.
- **Cross-artifact drift not detected at plan time.** git-history-analyzer found `cla-signature-evidence-retrieval.md` §7 was stale after legal-doc reword; not surfaced in the plan's Risk section. **Prevention:** at plan time, when the diff touches `docs/legal/*.md` vocabulary, run the runbook grep gate documented above and add a Risk entry naming every consumer of the old vocabulary.

## See also

- `2026-05-04-cla-evidence-sidecar-pattern.md` §12 — CF R2 has no S3 Object Lock; HMAC derivation contract; cert-expiry guard; §3.4 vocabulary update; Phase 8 sentinel-PR automation.
- `2026-05-11-multi-agent-review-catches-cross-artifact-contract-drift.md` — adjacent pattern (compliance-posture vendor-row vs public legal-doc disclosure mismatch); same class as this learning but applied to compliance-posture.md.
- `2026-04-22-markdown-table-parser-papercuts-and-review-diff-direction.md` — three-dot vs two-dot diff direction (relevant to git-history-analyzer's findings).
