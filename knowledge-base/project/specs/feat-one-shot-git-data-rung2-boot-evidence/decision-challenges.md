# Decision Challenges — feat-one-shot-git-data-rung2-boot-evidence

Recorded headless per ADR-084. These are points where the plan-review panel and the planning
session agree that the **stated direction** should change. The stated direction is the default
and was kept; these are surfaced for a decision rather than applied.

## DC-1 — `--window '7 DAY'` versus the script's own `30 DAY` default

**Stated direction.** The brief prescribes the capture invocation verbatim, including
`--window '7 DAY'`.

**The challenge.** Three of five reviewers independently flagged this. The rehearsal ran
2026-09-04; the capture runs 2026-09-09. `7 DAY` clears it by roughly two days. The capture's
own default is `30 DAY` (`WINDOW="30 DAY"` in
`scripts/followthroughs/git-data-rung2-evidence-capture.sh`). Because re-dispatch is forbidden
and widening is free, starting at `30 DAY` would remove the margin, and with it the TRANSIENT
row, the Research Reconciliation row and the Risks bullet the plan currently spends on managing
a two-day gap it created. DHH's framing: "You manufactured a problem and then wrote three
mitigations for it."

**Kept as briefed.** The brief is explicit that the plan must specify this command, and it
already names widening as the remedy. The plan therefore uses `7 DAY` on the first attempt and
documents the ladder (`30 DAY`, then `2 MONTH`) with a floor.

**Decision wanted.** Change the first attempt to `--window '30 DAY'`? It is one token and would
delete three paragraphs of contingency. Nothing else in the plan depends on the value.

## DC-2 — `--out` is strictly worse than omitting it

**Stated direction.** The brief prescribes
`--out apps/web-platform/infra/git-data-rung2-boot-evidence.env`.

**The challenge.** Kieran's finding, verified: the capture defaults `OUT` to
`$(dirname "$CLOUD_INIT")/git-data-rung2-boot-evidence.env`, and `CLOUD_INIT` defaults to
`$REPO_ROOT/apps/web-platform/infra/cloud-init-git-data.yml` where `REPO_ROOT` is derived from
`BASH_SOURCE` — an **absolute** path that resolves correctly from any working directory. The
explicit relative `--out` is the only reason the plan needs a working-directory precondition at
all. Omitting the flag removes a whole class of silent failure (a run from the wrong directory
writes the file somewhere the gate will not look, and the gate then reports HOLD for a reason
unrelated to the evidence).

**Kept as briefed.** The plan keeps `--out` and hardens the precondition into a mechanical
`git rev-parse --show-toplevel` check instead.

**Decision wanted.** Drop `--out` entirely? The default resolves to the identical path.

## Not challenges — applied directly

For the record, the following plan-review findings were mechanical and were applied without
asking: the one-argument gate invocation (mirroring CI), the full exit-path routing table
(rc=2 splits into TRANSIENT and DERIVATION FAULT; rc=78 and the no-sentinel-line case added),
the `CLEAN`-only cross-check rule, `git fetch origin main` before AC2/AC4, the widened AC4
filter, the `if !` form in AC2, `gitleaks` named explicitly in AC5, AC6 encoded as a command,
the divergence set re-derived from `rehearsal.tf` rather than from the gate's allowlist, the
push/CI/post-merge phases, the CPO sign-off step, and the disclosure that this plan does not
follow the runbook's `## After a PASS` artifact-download sequence.
