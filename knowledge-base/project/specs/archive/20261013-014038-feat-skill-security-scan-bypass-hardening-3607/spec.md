---
title: skill-security-scan — widen download-tool allowlist (aria2c, axel, httpie)
issue: 3607
branch: feat-skill-security-scan-bypass-hardening-3607
status: ready-for-plan
brand_survival_threshold: single-user incident
---

# Spec: skill-security-scan tool-allowlist widening

## Problem Statement

The three `fetch-*` rules in `plugins/soleur/skills/skill-security-scan/references/rules/code-exec.yaml` (`fetch-pipe-shell`, `fetch-process-sub-shell`, `fetch-cmdsub-exec`) hardcode `(curl|wget|fetch)` in their tool-name capture group. A malicious SKILL.md that uses `aria2c`, `axel`, or `httpie` for the download half of a curl-pipe-bash attack bypasses the scanner and produces a `LOW-RISK` verdict, undermining the operator-facing trust signal.

## Goals

1. Widen the tool-name capture group in all 3 affected rules to `(curl|wget|fetch|aria2c|axel|httpie)`.
2. Keep regex shape, ReDoS bound (`{0,200}`), rule IDs, and severity tier unchanged.
3. Recompute and commit the rule-pack manifest SHA.
4. Extend the scanner self-test fixture and the corpus calibration fixture with 6 new positive cases (3 tools × 3 rules) and verify each fires HIGH-RISK.
5. File a fresh follow-up issue capturing the class-(a) split-line / indirect-invocation work.
6. Close #3607 with a comment linking the new (b) PR and the new (a) issue.

## Non-Goals

- **Class (a) split-line / indirect-invocation detection** — deferred to a separate focused cycle. The three valid approaches (stateful two-pass, YARA sequential, AST fenced-block) need their own brainstorm.
- **Adding `http` or `lwp-request` to the alternation** — `http` is a 4-char substring with prose-collision risk; `lwp-request` is ecosystem-vanishing.
- **New rule IDs** — extending existing rules preserves rule-ID immutability.
- **Severity changes** — rules stay HIGH-RISK.

## Functional Requirements

- **FR1** Each of `aria2c URL | bash`, `axel -o - URL | bash`, `httpie URL | bash` (and the `wget`-shape variants for each) is detected as HIGH-RISK by `fetch-pipe-shell`.
- **FR2** Each of `bash <(aria2c URL)`, `bash <(axel URL)`, `bash <(httpie URL)` is detected as HIGH-RISK by `fetch-process-sub-shell`.
- **FR3** Each of `eval "$(aria2c URL)"`, `eval "$(axel URL)"`, `eval "$(httpie URL)"` (and POSIX-backtick variants) is detected as HIGH-RISK by `fetch-cmdsub-exec`.
- **FR4** A SKILL.md with NO bypass pattern continues to scan as `LOW-RISK` (no false-positive regression).
- **FR5** The scanner's existing calibration corpus continues to produce the same verdict-count distribution post-widening (no calibration drift on legitimate skills).

## Technical Requirements

- **TR1** Edit `plugins/soleur/skills/skill-security-scan/references/rules/code-exec.yaml` only — three regex lines.
- **TR2** Recompute `manifest.yaml`'s `code-exec.yaml` SHA and commit it in the same diff (per the scanner's `Self-defense: rule-pack SHA validation` block in `run-scan.sh`).
- **TR3** Extend `plugins/soleur/skills/skill-security-scan/scripts/run-self-test.sh` (or the equivalent fixture file) with one positive case per (tool × rule) combination — 9 new cases total.
- **TR4** Extend `plugins/soleur/test/skill-security-scan.test.ts` to assert the 9 new cases each fire HIGH-RISK.
- **TR5** Calibration corpus: re-grep the project's own SKILL.md universe (`find plugins/soleur/skills -name SKILL.md`) and verify no legitimate SKILL.md produces a NEW HIGH-RISK finding under the widened alternation.

## Acceptance Criteria

- **AC1** `bun test plugins/soleur/test/skill-security-scan.test.ts` passes including the 9 new positive cases.
- **AC2** `bash plugins/soleur/skills/skill-security-scan/scripts/run-self-test.sh` exits 0.
- **AC3** Manifest SHA in `manifest.yaml` matches `sha256sum code-exec.yaml` byte-for-byte (the scanner will short-circuit to REVIEW if the SHAs disagree).
- **AC4** Calibration re-grep over `plugins/soleur/skills/**/SKILL.md` produces zero NEW HIGH-RISK findings vs the pre-widening baseline.
- **AC5** `bash scripts/test-all.sh` is green (35+ suites pass; bot-fixture skipped per env policy).
- **AC6** A fresh GitHub issue is filed: `feat: skill-security-scan — detect split-line / indirect-invocation curl-pipe-bash obfuscation` with `priority/p3-low`, the 3-approach enumeration copied verbatim from #3607, and a re-evaluation criterion ("when calibration corpus shows ≥5 SKILL.md files using one of these patterns OR a production false-negative is filed").
- **AC7** Issue #3607 is closed with a comment linking the new (b) PR and the new (a) follow-up issue.

## Risks

- **R1** ReDoS regression. Mitigation: regex shape unchanged; the `{0,200}` bound applies to the same character class as before. The widening only adds 3 alternations inside the capture group; the alternation operator is constant-time on regex engines.
- **R2** Calibration drift. Mitigation: AC4 explicitly asserts zero new HIGH-RISK findings against the project's own SKILL.md universe (which contains no legitimate `aria2c|axel|httpie` install patterns).
- **R3** Test-fixture coverage gap. Mitigation: TR3 requires 9 cases (3 tools × 3 rules); each combination is one fixture line.

## Sharp Edges

- **`httpie` vs `http`.** HTTPie's installed binary is `http` (short form) AND `httpie` (long form). This spec adds only `httpie` (unambiguous). The short form `http` is deliberately excluded — its substring collision risk against URL prose (`http://...`) is real and the boundary-anchored regex needed to add it safely is out of scope for this mechanical widening. If a future calibration sample shows malicious skills using the short form, a follow-up can add it with explicit `[[:space:]]http[[:space:]]` boundary anchors.
- **Manifest SHA recomputation.** `run-scan.sh:34-55` validates per-file SHAs from `manifest.yaml`. Forgetting to recompute the SHA after editing `code-exec.yaml` causes every future scan to short-circuit to REVIEW (a noisy false-positive on every skill). The PR MUST include the recomputed SHA in the same commit.
- **Class (a) deferral remains valid.** Filing the fresh class-(a) issue (AC6) is part of THIS PR's ship checklist, not a separate cycle. Without it, the scope-out trail ends with this PR and the contested-design work has no tracking artifact.

## Open Code-Review Overlap

None. The three rules touched live exclusively in `code-exec.yaml` and the test file. No open `code-review`-labeled issue references either file.
