---
title: "How We Let AI Agents Run Cron Jobs Without Letting Them Exfiltrate Secrets"
type: engineering-deep-dive
publish_date: ""
channels: blog, hackernews, x, linkedin-personal
status: parked
pr_reference: "#5089"
issue_reference: "#5104"
---

<!-- PARKED 2026-06-12 (operator decision): not distributing — too technical for the current audience. The blog post was UNPUBLISHED from the docs site (moved out of plugins/soleur/docs/blog/ so it no longer renders at /blog/). Draft retained for later revival. -->
<!-- To revive: move the blog draft back to plugins/soleur/docs/blog/ to republish, then set BOTH publish_date AND status: scheduled here. -->
<!-- TIMING GATE (still applies if revived): nothing publishes before PR #5089 is merged (DONE 2026-06-10) AND /soleur:postmerge is green (DONE 2026-06-12). -->
<!-- Blog draft (UNPUBLISHED, parked): knowledge-base/marketing/blog-drafts/2026-06-12-ai-agents-cron-without-exfiltrating-secrets.md (fact-checked SHIP, 2026-06-12). -->

## P1 — Primary piece (engineering deep-dive)

**"How We Let AI Agents Run Cron Jobs Without Letting Them Exfiltrate Secrets"**

- **Surface order:** Blog (canonical) → Hacker News (direct submit, Tue–Thu 14:00–16:00 UTC) → X thread → LinkedIn Personal at T+4–7d.
- **Audience:** technical builders running Claude Code / autonomous agents in production; security-conscious eng leaders.
- **Angle:** defense-in-depth — three independent layers, each assuming the others fail: (1) PreToolUse containment hook with every secret-read layer kept; (2) default-drop nftables DOCKER-USER egress allowlist; (3) least-privilege GitHub tokens (`contents:read` + `issues:write`). The honest-residuals disclosure (ADR-052 names content-blind egress, DNS-tunneling, CDN shared-IP broadening, DoH-on-443) is the trust differentiator.
- **CTA:** repo + **ADR-052** (open threat model for the firewall + residuals) and **ADR-051** (least-privilege token-derived egress).
- **Success metrics:** HN >50 points; repo referral spike; 2+ inbound defense-in-depth citations.

### Hacker News submission

- **Title:** "How we let AI agents run cron jobs without letting them exfiltrate secrets"
- **URL:** link to the published blog post.
- **First comment (author):** Short, no-marketing framing — "We run autonomous agents (Claude Code) on a schedule with shell access and live secrets. Three independent containment layers, each assuming the others fail, plus the residuals we deliberately did not close (DNS-tunnel through the pinned resolver, CDN shared-IP broadening). Threat model is public in ADR-052. Happy to answer questions about the nftables DOCKER-USER setup or the terraform `set -e` gotcha that almost shipped a guard that couldn't fail."

### X thread (P1, derived from the blog)

1/ We give autonomous agents a shell and live secrets on a schedule. That's an exfiltration surface. Here's the three-layer containment we shipped — each layer assumes the other two already failed.

2/ Layer 1: a PreToolUse hook that denies every secret-read path and only allows Task/Agent/Skill. Layer 2: a default-drop nftables allowlist in DOCKER-USER — 22 hosts, grep-enumerated from runtime code, re-resolved every minute in one atomic transaction. Layer 3: GitHub tokens scoped to `contents:read` + `issues:write`. Push and PR are denied at the token layer.

3/ The part most posts skip: what it does NOT stop. An agent can still tunnel data through the pinned DNS resolver, or ride a CDN's shared IP. We named all four residuals in a public ADR instead of pretending the box is sealed. That honesty is the point.

4/ Full write-up + open threat model (ADR-052): [blog link]

### LinkedIn Personal (P1, T+4–7d)

First-person founder voice. Lead with the tension: autonomous agents are only useful with real access, and real access is the risk. We shipped three containment layers and — the part that matters — published the residuals we chose not to close. Link the post. Pull-quote the honest-residuals framing.

---

## P2 — Secondary piece (short-form)

**"5 AI Reviewers, 4 P1s, 1 Terraform Gotcha"** — X / Bluesky thread on the terraform remote-exec inline-assertion finding. Publish T+4–7d after P1.

> A terraform remote-exec assertion is decorative. We learned it the expensive way: our new egress-firewall provisioner ran live "is enforcement actually on?" probes — then ended on an unconditional echo. An inert, non-enforcing ruleset would have applied bright green.

> 2/ The cause: terraform joins remote-exec `inline` commands into one shell script with no implicit `set -e`. The provisioner fails only on the LAST command's exit. Every probe ran, proved nothing, and the green checkmark lied. The guard couldn't fail — which is worse than no guard.

> 3/ Five independent AI reviewers concurred on this one finding (the full review was 11 agents, 38 findings, all fixed inline). Fix: `set -e` first, every probe as `if cmd; then echo FAILED; exit 1; fi`. A guard that can't fail converts "unverified" into "verified-looking."

---

## Notes

- Net-new content pillar — no prior AI-agent-security engineering content in `distribution-content/`. The 2026-06-11 `waitlist-signups-survive-firewall-re-escalation` piece is a customer-facing vendor-firewall incident story, a distinct topic.
- Maps to content-strategy.md's developer/security audience slot (cf. the planned "Credential Helper Isolation" deep-dive).
- Execution path: copywriter → fact-checker (verdict: SHIP, 2026-06-12) → this file → `/soleur:social-distribute` once the timing gate clears.
- Honest-residuals angle stays embedded in P1 (LinkedIn Personal pull-quote), not standalone.
