---
branch: feat-one-shot-9639-probe-residuals
created: 2026-10-26
source: one-shot pipeline, plan phase (headless; no agent-spawn surface available to the planning subagent)
---

# Decision Challenges — feat-one-shot-9639-probe-residuals

Rows follow the machine-gated contract: 3-cell rows under the canonical table header, no
literal `|` inside cells, rulings appended inside the table only. Planning ran without a
subagent-spawn surface, so technical forks are recorded `pending - assumed:` per the
pipeline brief; `technical-ruling-gate.sh` will flag them for a real CTO ruling before ship.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Refusal form in web-git-data-probe.sh: unconditional `case "$-" in *x*) exit 78` (nic-guard/inngest shape) vs conditional-on-credential-set (zot shape) | technical | pending - assumed: unconditional. The script always resolves a credential and has no `--canary-only` context where the key is legitimately unset; inngest-consumer-probe (#10363) is the identity-key precedent and its refusal is unconditional. |
| F8 mechanism: new `logtail_exploration_alert` vs rename `[nic] unpinned_url` to a `SOLEUR_*` marker and opt into `monitor_send_failed` via a needle | technical | pending - assumed: new alert. The opt-in path is documented as SOLEUR-star / PRIORITY-2-only, the `[nic]` refusal lines are the sibling-consistent telemetry shape, and the issue prescribes the alert. |
| F7 stage name and detail content: `egress_enforce_probe` + `rc=<exit>` detail file | technical | pending - assumed: as stated. Mirrors the `hostscripts_incomplete` precedent at cloud-init.yml:771 and discriminates refused(78) vs failed(1). |
| Re-scope vs delete the doppler-injection-bound mutation rows that named web-git-data-probe.service as the unfixed sibling (drop-wrapper-ack, ack-extra-name, G1.6/G1.10/G1.10b/G1.10c) | technical | pending - assumed: re-scope onto fixture-built arms where the arm is still reachable (a fixture unit that expands while its ack names a different set exercises the mismatch arm); delete only arms that are unreachable with an empty dict, with an in-file note. |
| Alert name `web_nic_guard_unpinned_url` and no `host_name` conjunct (both web hosts can refuse) | technical | pending - assumed: as stated. Matches sibling naming; a host conjunct would blind half the fleet (the #8706 trap in reverse). |
