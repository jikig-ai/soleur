---
title: The review SAST scan's evidence is the orchestrator's stdout receipt
status: accepted
date: 2026-11-10
issue: 12530
related_adrs: []
---

# ADR-324: The review SAST scan's evidence is the orchestrator's stdout receipt

Refs: #12530. Plan: `knowledge-base/project/plans/2026-11-10-feat-orchestrator-security-scan-gate-plan.md`.

## Status

Accepted 2026-11-10. In force when the review skill runs `plugins/soleur/skills/review/scripts/review-scan-gate.sh` before any review seat and continues only on that script's own `ok` or `skip` receipt.

## Context

`soleur:engineering:review:security-sentinel` could report a clean diff without a deterministic scan having run. `soleur:engineering:review:semgrep-sast` ran later, only when the diff looked like source, and its own report was the evidence the scan had happened. A seat can print a clean line when the scanner never ran, when the scanner exited without a rule summary, or when the output was not read. The pre-push secret scan is a different gate and does not close this hole.

## Decision

The review orchestrator's stdout receipt is the only evidence the review SAST scan ran. The script prints one status line, `SOLEUR_REVIEW_SCAN_GATE`, and the phase continues only when that line's status token is `ok` or `skip`. `probe` exits 0 and is not a scan. `refuse`, any other token, a non-zero exit, or a missing line stops the phase before any seat, including the design-validity pass and a fix-round.

A zero-finding SAST claim requires `ok` with `findings=0` and `files` equal to the classified source-and-shell target count. For semgrep or mixed, the rule count must be greater than zero, taken from semgrep's own `Ran N rules on M files` summary, singular or plural, and `paths.scanned` must map back to every source target. Shellcheck `ok` requires the binary to have run with every shell target on its argv. `skip` (`engine=none`) does not authorize a SAST-clean claim. Findings stay on stdout as `file:line rule-id` and do not stop the phase.

`plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh` remains a separate deterministic scan. It is not this receipt, and this decision does not change its exit codes.

A non-zero rule count can still miss the language under scan. That residual is accepted here. The receipt proves the scan ran and was read. It does not prove the rule pack models every bug class.

## Consequences

- Review seats, including `semgrep-sast` and the shellcheck seat, quote the receipt. They do not invoke semgrep or shellcheck.
- A clean security verdict without an `ok` receipt with `findings=0` is not evidence.
- The secret-scan pre-push gate stays on its own contract. A review that skips because nothing is scannable still runs the sentinel.
- The opt-in review workflow prototype is not this gate. The skill is the authority.
