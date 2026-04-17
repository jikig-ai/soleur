---
title: "Your AI Team Now Works From Your Actual Codebase"
type: feature-launch
publish_date: "2026-04-17"
channels: discord, x, bluesky, linkedin-personal, linkedin-company, indiehackers, reddit, hackernews
status: published
pr_reference: "#1257"
issue_reference: "#1273"
blog_url: "/blog/your-ai-team-works-from-your-actual-codebase/"
---

## Discord

Your AI team now operates on your actual codebase.

Connect your GitHub repository during onboarding and every agent conversation starts with full project context -- your architecture, your brand guide, your legal documents, every decision from every prior session.

What this changes:

- No more briefing the AI from scratch every session
- Knowledge compounds across conversations -- brainstorms, specs, plans, and learnings persist in your repo
- Best-effort sync: pull on session start, push on session end, never blocks your work
- GitHub App authentication with short-lived tokens -- no long-lived credentials in your workspace

Three onboarding paths: connect an existing repo, create a new one, or skip for later.

Blog post with full details: <{{ site.url }}blog/your-ai-team-works-from-your-actual-codebase/>

---

## X/Twitter Thread

Your AI team now operates on your actual codebase -- not a blank workspace.

Connect your GitHub repo during onboarding. Every agent conversation starts with real project context.

2/ The problem with every AI development workflow: the agent starts from zero. It does not know your architecture, your brand voice, your legal constraints, or what you shipped last week.

You brief it from scratch. Every. Single. Session.

3/ Now: connect your GitHub repo, and 63 agents across 8 departments read your knowledge base, brand guide, specs, and learnings. Context carries forward. Knowledge compounds.

4/ How it works behind the scenes:

- Session start: workspace pulls latest from your repo
- Session end: changes push back
- Sync is best-effort -- a failed sync never blocks your session
- Auth uses GitHub App tokens that expire in 1 hour

5/ Three paths during onboarding:

- Connect an existing project
- Start fresh (we create the repo for you)
- Skip for now

Designed for founders who may not be technical. Plain language throughout.

Full details: <{{ site.url }}blog/your-ai-team-works-from-your-actual-codebase/>

<!-- markdownlint-disable-next-line MD018 -->
#solofounder #buildinpublic

---

## Bluesky

Your AI team now operates on your actual codebase. Connect your GitHub repo during Soleur onboarding -- every agent conversation starts with real project context. No blank workspaces. Knowledge compounds across every session. Best-effort sync that never blocks your work.

---

## LinkedIn Personal

Every AI development workflow has the same failure mode: the agent starts with a blank workspace.

It does not know your architecture. It does not know your brand voice. It does not know what you shipped last week. You brief it from scratch every session. The context you build evaporates when the session ends.

We shipped the fix. Soleur agents now operate on your actual codebase.

Connect your GitHub repository during onboarding, and every agent conversation -- marketing, engineering, legal, finance, all eight departments -- starts with full project context. Your knowledge base, your brand guide, your specifications, your learnings from every prior session.

The sync model is best-effort: pull on session start, push on session end. A failed sync never blocks your session. Authentication uses GitHub App installation tokens that expire after one hour -- no long-lived credentials stored in your workspace.

For founders without a repo yet: the onboarding flow creates one for you with a knowledge-base scaffolded from day one.

This is the feature that makes compound knowledge practical. Without it, institutional memory was per-session. With it, every decision persists, every session builds on the last, and the AI team gets better the longer you use it.

Full writeup on the engineering and the design decisions: <{{ site.url }}blog/your-ai-team-works-from-your-actual-codebase/>

<!-- markdownlint-disable-next-line MD018 -->
#solofounder #buildinpublic

---

## LinkedIn Company Page

Soleur agents now operate on your actual GitHub codebase.

Connect your repository during onboarding, and every agent conversation starts with full project context -- architecture, brand guide, legal documents, and accumulated institutional knowledge.

Key details:

- Best-effort sync: pull on session start, push on session end
- GitHub App authentication with short-lived tokens (no long-lived credentials)
- Three onboarding paths: connect existing, create new, or skip
- Designed for non-technical founders with plain-language UX

This is the infrastructure that makes Soleur's compound knowledge architecture practical. Every session builds on the last.

Full details: <{{ site.url }}blog/your-ai-team-works-from-your-actual-codebase/>

---

## IndieHackers

**Your AI team now works from your actual codebase**

Shipped the repo connection feature for Soleur today. This is the feature I have been building toward since day one.

The problem: every AI dev tool starts with a blank workspace. The AI does not know your project, your decisions, your constraints. You re-explain everything every session.

The fix: connect your GitHub repo during onboarding. Your AI team (63 agents across 8 departments) reads your codebase, knowledge base, brand guide, and learnings. Context carries forward. Knowledge compounds.

Technical details for the curious:

- GitHub App with installation token auth (not PAT, not OAuth)
- Best-effort sync: pull on session start, push on session end
- Shallow clone for speed, merge (not rebase) for shallow history compatibility
- Credential helper isolation pattern (separate blog post coming on the security side)

Three onboarding paths: connect existing repo, create new, or skip.

Open source. Free. Built by a solo founder for solo founders.

---

## Reddit

**Your AI team now operates on your actual codebase -- not a blank workspace**

I built an AI team platform (Soleur) that deploys 63 agents across 8 business departments. The biggest missing piece was always: these agents start from zero every session.

Shipped the fix today. Connect your GitHub repo during onboarding, and every agent conversation starts with full project context.

How the sync works:

- Session start: pulls latest from your repo
- Session end: pushes changes back
- Best-effort model -- a failed sync never blocks the session
- GitHub App tokens (expire in 1hr, per-repo scoped)
- Shallow clone + merge strategy for speed

The compound effect is the key part. Every brainstorm, plan, spec, and learning gets committed to your repo. The next session reads them. The one after builds on them. The AI team develops institutional memory.

Open source (Apache 2.0). Would appreciate feedback on the approach.

---

## Hacker News

**Show HN: Git credential helper isolation for sandboxed AI agents**

We needed to give sandboxed AI agents git push/pull access without exposing long-lived credentials. The solution: temporary credential helper scripts with randomized paths, backed by GitHub App installation tokens (1hr expiry).

The pattern: write a shell script to `/tmp/git-cred-<UUID>` that echoes x-access-token credentials, pass it to git via `-c credential.helper=!<path>`, delete in `finally`. The credential exists on disk for the duration of one git command.

Security hardening: randomized UUID paths prevent symlink attacks, userId UUID validation prevents path traversal, and the tokens auto-expire regardless.

Full technical writeup: <{{ site.url }}blog/credential-helper-isolation-sandboxed-environments/>

Context: this is part of Soleur, an open-source AI team platform. The repo connection feature lets agents operate on a founder's actual GitHub codebase with best-effort sync (pull on session start, push on session end).

Source: <https://github.com/jikig-ai/soleur>
