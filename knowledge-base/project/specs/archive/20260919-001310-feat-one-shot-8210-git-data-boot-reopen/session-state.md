# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-18-fix-git-data-luks-mapper-reopen-at-boot-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- `iac-plan-write-guard` PreToolUse hook denied the first plan and tasks.md writes (systemctl / /etc/systemd tokens); resolved with the documented `iac-routing-ack` after terraform-architect confirmed IaC routing.
- `lint-infra-no-human-steps.py` flagged actor tokens three times; reworded, all artifacts lint green.
- Two plan-phase leader claims were false against the tree and corrected at plan-review (replace job does not call the rung-2 gate; replace route only held after this plan adds it). The rehearsal cannot be dispatched from the branch (`environment: web-platform-infra-apply` is main-only).
- playwright MCP failed to connect (not needed for planning).

### Decisions
- `cryptsetup luksOpen` runs only under cloud-init `runcmd:` (per-instance) and first-boot bootstrap §1b; `bootcmd:` holds only a Sentry beacon; fstab is `nofail`; no crypttab. crypttab/keyscript cut (no keyscript in systemd; keyfile = baked passphrase, forbidden by ADR-198).
- Mechanism: baked script + `git-data-luks-reopen.service` (git-data-gc.service shape, `doppler run --only-secrets --no-fallback`), bounded Restart, `OnFailure=` reporter emitting one routed fatal; mount delegated to PID 1 via fstab unit; never formats.
- Proof: rung-2 rehearsal gains a hard-reset arm + `--reboot-since` capture mode; stale evidence deleted in-PR and re-landed from a main run; replace job gains the rung-2 gate; PM4 guarded replace is the delivery step and a recorded #8211 prerequisite.
- Cuts at plan-review: self-wrapping script, separate env file, §1b delegation, ADR-228 (→ ADR-115 + ADR-198 amendments), birth-gate fifth key, separate probe script, Phase 0.4, paper ACs. Kept: fifth `boot_complete` boolean stays TERMINAL.
- Scope: #8101/#8010/#8094/#8211 out; `Contract for #8211` clauses (a)–(h) + follow-on issue PM5 recorded.

### Components Invoked
- Skills: soleur:plan, soleur:gdpr-gate, soleur:plan-review, soleur:deepen-plan
- Agents: repo-research-analyst, learnings-researcher, cto, cpo, terraform-architect, fable advisor; plan-review panel (dhh, kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, cto); deepen passes (verify-the-negative, framework-docs-researcher, git-history-analyzer, observability-coverage-reviewer, security-sentinel, test-design-reviewer)
