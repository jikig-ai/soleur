---
title: Sandbox incident follow-ups triage (#10455, #10548, #10549, #10604)
date: 2026-10-20
issues: [10455, 10548, 10549, 10604]
branch: feat-sandbox-followups-triage-10455
pr: 10697
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: sandbox incident follow-ups triage

## What We're Building

Four open issues are follow-ups of incident #10445 (hosted-agent Bash down 2026-10-06..16, no alert). PR #10546 (merged 2026-10-20 11:43Z) shipped the tenant-visible message, the helper-step classifier, the Slack-wake check, the non-blocking deploy-time SDK Bash smoke, and the AF_UNIX-deny seccomp variant behind the default-OFF runtime flag `agent-sandbox-unix-deny` (the flag itself is not created anywhere yet).

This brainstorm decides which of the remaining items are actionable now. One follow-up PR is scoped; everything else stays open behind its recorded trigger.

## Triage

| Issue / item | Class | Reason |
|---|---|---|
| #10548 smoke promotion, flag creation, prod enable | OPERATOR-ONLY / time-gated | Sweeper skips the tracker before 2026-10-26; needs >=5 green verdicts over >=3 days; flag create and enable are operator-typed writes (`hr-menu-option-ack-not-prod-write-auth`). |
| #10549 egress-session AF_UNIX deny | GATED | No SDK bump breaking the vendored-argv pins, no realized egress-session incident, egress population not the majority. |
| #10604 flag cohort, variant-EPERM signal, legacy observer | GATED | No tenant AF_UNIX EPERM report, flag is OFF, no unattended or default-on proposal. |
| #10455 b: runtime synthetic with dead-man heartbeat | ACTIONABLE NOW | The only item closing the between-deploys gap that let the outage run 10 days. Design already ruled (decision-challenges, 2026-10-19). Verified unbuilt: `web-bash-synthetic` exists only in archived plan/tasks. |
| #10455: alert for `op=masked-dir-precreate` | ACTIONABLE NOW (small) | Verified Sentry-only (`agent-runner-sandbox-config.ts:535`), no routing rule. |
| #10455: measure sibling-reachable persisted CLI output | ACTIONABLE NOW (read-only measurement) | CLO: only item with a possible Art. 32 angle. `HOME` is passed through to the CLI (`agent-env.ts` allowlist) and `CLAUDE_CONFIG_DIR` is not set per tenant, so `history.jsonl`/`debug`/`todos` reachability is unmeasured. Measure first; fix is a conditional follow-up. |
| #10455: deny set derived from `agentEnv` + test | ACTIONABLE, only if the diff stays small | CTO ruling. |
| #10455: test hardening P3 | ride-along only | |
| #10455: page on >=2 distinct users | GATED | No observed noisy-tenant suppression. The synthetic's own failure pages on the first miss, so this is not in conflict with the CPO. |
| #10455: legacy-runner observer | GATED | CTO. The synthetic exercises the shared sandbox config, so it catches a repeat of the original outage on both runners. CPO rated it medium; revisit when the flag goes ON. |
| #10455: SOCKS probe + `allowWebEgress`/read-only arms, peer-messaging auth, `--pids-limit`, EACCES/EINVAL classification | GATED / parked | Coverage gaps or research with no incident behind them. |
| #10455: PIR affected-user count | PROPOSED CLOSE (won't-fix) | No queryable store of Bash tool_result text; the item itself says revisit only if one appears. Needs the operator's OK. |

## Key Decisions

1. Next PR = runtime synthetic (b) + `masked-dir-precreate` alert + persisted-CLI-output measurement; `agentEnv` deny-set derivation if small. Uses `Ref #10455`, never `Closes`.
2. Keep the separate `web-bash-synthetic` unit and per-host heartbeat (period 900 s, grace 900 s; 1800 s if the tier floor forbids). Ruled by CTO agent, 2026-10-20 (reaffirming the 2026-10-19 ruling).
3. Keep the deploy smoke non-blocking; no distinct-user paging; no cohort step or legacy observer while the flag is OFF. Ruled by CTO agent, 2026-10-20.
4. CLO overrides the CTO's "gated" for persisted CLI output only as a measurement step: if reachable, it becomes a P1 Art. 32 gap with an Art. 4(12) screening, not before.
5. Productize candidate: none.

## User-Brand Impact

- **Artifact:** the hosted-agent Bash sandbox and its detection layer (runtime synthetic, Better Stack alerts, per-tenant CLI isolation).
- **Vector:** a silent multi-day sandbox outage, or a cross-tenant read of persisted CLI output, that reaches a paying user with no alert.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering
**Summary:** Classified every item (above). Runtime synthetic is the one high-value actionable item; precedent heartbeats exist (`web_nic_guard`, `web_zot_consumer` in `arm-heartbeats.sh`). Keep non-blocking smoke and global flag.

### Product
**Summary:** Synthetic is high outage-risk reduction; page the synthetic on the first miss. Egress AF_UNIX deny and the variant-EPERM signal are low value at alpha scale. Error wording, outreach, and any post-incident statement are operator brand calls.

### Legal
**Summary:** Synthetic and alert add no Art. 30 category (PA-8 already covers `userIdHash` on the Sentry/Better Stack plane). Sibling-reachable persisted CLI output is the only legal angle: measure before ranking. No Art. 33/34 clock (PIR `art_33_triggered: false`); outreach is a brand decision, not a statutory one.

## Open Questions

- Operator: close the PIR affected-user-count item as won't-fix?
- Operator (brand): any user outreach about the 10-day outage (#10477), and final plain-language wording.
- Operator (production write, after 2026-10-26 soak): create and enable `agent-sandbox-unix-deny` (tracked in #10548).
- Is `~/.claude` under a shared `HOME` actually reachable by sibling tenants? (measurement step in the next PR)

## Capability Gaps

None reported.
