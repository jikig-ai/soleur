---
title: Post-replace liveness gate shipped three review-caught defect classes (errexit poll, iid-glue poisoning, templatefile ${} hazard)
date: 2026-11-13
category: workflow-patterns
tags: [github-actions, bash-errexit, adr-170, templatefile, detail-field-glue, inngest, review-findings]
module: Infrastructure
component: apply-web-platform-infra.yml / cloud-init-inngest.yml
problem_type: workflow_issue
resolution_type: prevention
root_cause: three distinct conventions each violated once in one diff
severity: high
---

# Post-replace liveness gate review defects (#12722 / #12708 / #12707)

## Problem

The first-probe liveness gate added to `inngest_host_replace` carried three defects that
review caught but the original implementation missed:

1. **`bash -e` kills the poll before its rc capture.** A bare `run:` block executes as
   `bash -e {0}`; `set -uo pipefail` adds flags but never clears `-e`. The first poll
   returning the EXPECTED rc=4 (no probe row yet — true for the first minutes of every
   healthy replace) killed the step at the read line: `last_rc=$?`, the retry loop, the
   step summary, and the `::error::` were all dead code. Same latent shape on the
   `IID="$(doppler run … | jq …)"` capture in the resolve step. ADR-170's documented
   defect class, again — the fix is `set +e` (or `|| rc=$?`) and
   `scripts/lint-workflow-errexit-capture.py` flags it (it flagged the PR's HEAD).
2. **`iid=$IID$d` glued the new `.foreign=` detail onto a field consumers parse with a
   `.`-admitting charset.** Two followthrough scripts read `iid=[A-Za-z0-9._-]+`, which
   captures `<iid>.foreign` — the provision-unit probe's stage join decoded a poisoned
   iid and the rehearsal capture read the newest-iid wrong. Rule: a detail suffix may
   glue only to a field whose consumers' parse charset stops at `.`, or sit at END.
   `attempt=` survives because its consumers parse `[0-9]+`.
3. **`${d:+$d }` inside cloud-init-inngest.yml is HCL interpolation.** The file renders
   through terraform `templatefile()`; `${…}` is not a bash expansion, it is a template
   expression that fails the render gate. Bare `$d` is safe; `${…}` needs `$$` escaping.

A fourth: removing `set -euo pipefail` from the check's inner `bash -s` heredoc let a
mid-pipe truncation (jq dying after the alphabetically-first admitted names) present
awk an all-admitted ≥6-name stream — the credential-isolation gate failing OPEN. The
failure direction of a guard's own instrument fault must be toward FATAL, not PASS.

## Solution

`set +e` before the poll + `verdict_reads` so an all-instrument-fault window reports
UNMEASURED rather than asserting the host dark; `|| IID=""` on the state capture;
`attempt=$attempt$d iid=$IID` (iid last and clean); `set -euo pipefail` restored inside
the heredoc; `--instance-id ""` exits 2 (a contract violation, never an unpinned read);
a structural guard suite extracts the step from parsed YAML and pins the call shape.

## Key Insight

Detail-field widening is a cross-consumer change even when the emitting side is
correct. Before gluing `.$k=v` onto an emitted field, grep every parser of that field
for its capture charset — a charset that admits `.` will swallow the suffix into the
preceding field's value and silently corrupt the join.

## Tags

github-actions, bash-errexit, adr-170, templatefile, detail-field-glue, iid-pin, inngest
