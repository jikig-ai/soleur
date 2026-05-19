---
name: brainstorm-probe-first-before-leader-spawn
description: When an issue body names a mechanical disambiguator (live API probe, DSN cluster substring, config lookup), run it BEFORE Phase 0.5 leader spawn — the answer often collapses speculative remediation tracks and softens brand-survival framing
date: 2026-05-15
category: best-practices
tags: [brainstorm, leader-spawn, probe, premise-validation, sentry, gdpr]
related_issue: "#3861"
related_pr: "#3863"
related_learnings:
  - 2026-05-04-sentry-org-token-region-probe-and-dashboards-scope-guard.md
  - 2026-05-12-anticipatory-hook-bypass-and-leader-substrate-cross-check.md
  - 2026-05-11-brainstorm-grep-approach-hook-before-spawning-leaders.md
---

# Learning: probe-driven reframing before leader spawn

## Problem

GitHub issue #3861 framed three speculative remediation tracks for a Sentry residency contradiction (US canonical / DE canonical with cluster surgery / dual-region). The brainstorm skill's default flow spawns Phase 0.5 leaders (CPO + CLO + CTO in user-brand-critical mode) before Phase 1.0 verification. Running the triad against three speculative tracks would have produced internally-coherent recommendations for two scenarios that are physically impossible (track 1 and track 3 cannot both be true given the runtime DSN binding).

The issue's own step 1 was a mechanical API probe ("Authoritatively determine which cluster(s) the Sentry org lives in") that the issue author had already enumerated. Following the brainstorm's Phase ordering literally would have run the probe AFTER the triad — wasting ~70k tokens of leader compute on possibility space that the probe collapses.

## Solution

Pull the mechanical disambiguator forward to Phase 1.0, BEFORE Phase 0.5 leader spawn. In the #3861 case:

- A 5-second DSN cluster-substring check on Doppler `prd` `SENTRY_DSN` (`o4511123328466944.ingest.de.sentry.io`) was decisive for residency.
- A 60-second multi-endpoint probe (`/organizations/jikigai/`, `/projects/.../`, customers billing) added belt-and-braces.

With the probe result in hand, the triad prompts could be sharpened to a single track (track 2 — DE canonical, US shadow org) and the brand-survival framing softened from "Article 33 statutory clock" to "misleading §5(2) accountability evidence" (the latter wholly outside Chapter V). The triad returned tightly converged 350–500-word assessments instead of three-track speculation.

## Key Insight

The brainstorm skill's Phase 1.1 already names sharp-edges for "Verifying issue-body architectural constraints," "Verifying referenced PR/issue state," and "Verifying 'this is a regression of #N' claims." Add a fourth: **Verifying issue-body mechanical disambiguators**. When the issue body itself enumerates a probe / curl / config lookup whose result narrows the decision space, run it at Phase 1.0 (between worktree creation and leader spawn). Cost: seconds. Benefit: leader prompts become single-track + correctly-thresholded.

This is distinct from the existing approach-hook check (named architectural approaches grepped against `main`) and the cited-flag check (capitalized symbols grepped against `main`). Those check **whether the named work is still relevant**. The disambiguator check answers **which of N speculative branches is real** when the issue body explicitly names how to find out.

## Recommended brainstorm-skill edit

Add to `plugins/soleur/skills/brainstorm/SKILL.md` Phase 1.1, as a peer of the existing "Verifying issue-body..." sharp edges:

> **Verifying issue-body mechanical disambiguators against runtime state.** When the issue body enumerates a probe (`curl`, `gh api`, DSN substring, config read) whose result narrows multiple speculative remediation tracks to one, run it BEFORE Phase 0.5 leader spawn. The probe usually costs seconds; running the triad against three tracks of which two are impossible costs ~70k tokens of leader compute. Sharpened leader prompts (single track + correctly-thresholded framing) return tighter assessments. Distinct from the approach-hook check (whether named work is still relevant) and the cited-flag check (whether named gates still exist) — this answers *which of N speculative branches is real*.

## Session Errors

1. **`gh issue create --label "type/infrastructure"` rejected** — the label doesn't exist in the repo. Caught at Phase 3.6 while filing the deferred follow-up issues. **Recovery:** retried without `--label`. **Prevention:** before passing `--label X` to `gh issue create`, verify the label exists via `gh label list --limit 100 --json name -q '.[].name' | grep -i <name>`. Cheap pre-flight; gh's error is clear (`could not add label: 'X' not found`) but only fires after the issue body is composed. Worth a one-liner in any `*-create-issue.sh` helper script that wraps `gh issue create`.

## Tags

category: best-practices
module: brainstorm
component: plugins/soleur/skills/brainstorm
