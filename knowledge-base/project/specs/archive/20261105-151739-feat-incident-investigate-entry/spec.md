---
title: founder pull into the incident skill
date: 2026-11-05
lane: cross-domain
brand_survival_threshold: single-user incident
status: specced
pr: 12143
brainstorm: knowledge-base/project/brainstorms/archive/20261105-151739-2026-11-05-incident-investigate-entry-brainstorm.md
---

# Feature: founder pull into the incident skill

"Incident" means a production outage the founder is responding to, the sense of `plugins/soleur/skills/incident/SKILL.md`. It does not mean `.claude/hooks/lib/incidents.sh`.

## Problem Statement

The incident skill tells the agent to pull Better Stack, Sentry, and Supabase, then asks the founder for 19 facts from memory. Nothing in the skill executes those readers. The founder restates logs the repo can already read, and a story typed from memory becomes the post-mortem's cause.

## Goals

- The incident skill runs the three existing readers before the founder confirms facts.
- The founder sees a redacted coverage card: one sentence built only from coverage fields, or `hypotheses=none`, and a coverage line per source.
- Confirming the card does not skip `ACK-ART33`, `ACK-ART34`, or `COMMIT-PIR`.
- A missing source, an empty result, or exit 0 on the wrong question is labeled a gap.

## Non-Goals

- A new skill, a new agent, or the Terraform SRE agent.
- Scheduled repair, cron or webhook auto-PIR, paging, or the Better Stack Claude plugin.
- Configuring Better Stack outside Terraform.
- Production writes of any kind.
- A Sentry issue list mode.
- Edits to the privacy policy, the GDPR policy, or the data-protection disclosure.
- A change to the Art. 33 formula (`detected_at` plus 72 hours, after the founder confirms `detected_at`).
- Filling Phase 7's 5-whys from the pull.

## User-Brand Impact

**Artifact:** the hypothesis card, and the Phase 0 fields the founder accepts from it.

**Vector:** a wrong cause confirmed because it was fluent, or a log line shown before `redact-sentinel.sh` passes.

**Threshold:** `single-user incident`.

## Functional Requirements

### FR1: Pull before the interview

When the founder starts the incident skill, and the run is not `--dry-run` and not `--headless`, the skill runs the pull before it asks for the 19 fields. `--dry-run` and `--headless` do not perform a live pull.

### FR2: Defaults the founder can override

Better Stack: `--since 1h` with the archive arm, under Doppler `soleur/prd_terraform`. The card names the table. The default table is the Inngest vector source.

Supabase: `--ref ifsccnjhymdmidffkzhl --since 24h` under Doppler `soleur/prd`. The Inngest project ref is used only when the founder names that project.

Sentry: `scripts/sentry-issue.sh` runs only when the founder supplies an issue id. Otherwise the card records `sentry: not-queried reason=no-issue-id`.

The founder may pass a window and an optional complaint sentence. The complaint sentence is a claim to check, not the cause.

### FR3: Partial failure

If Doppler `prd` cannot be read and `prd_terraform` can, Better Stack still runs. Sentry and Supabase are `verdict=never-ran` `reason=wrapper` when that source was going to be executed. With no issue id, Sentry stays `not-queried` `reason=no-issue-id`. If the `doppler` binary is missing, Better Stack and Supabase are `reason=wrapper` and Sentry follows that same split. Better Stack exit 3 is `verdict=never-ran`. Supabase exit 3 keeps the script's data verdict on the card and the marker `verdict=queried`.

### FR4: Hypothesis card

The card is the coverage lines plus at most one sentence built only from those fields, or `hypotheses=none`. It does not rank causes, say what would disprove the complaint, or print a pull time. A source that ran names the window and, for Better Stack and Supabase, the table or ref. A Doppler wrapper line names the window and the coverage verdict and does not name the table or ref. A `reason=usage` line does not print the refused window. It does not set `affected_user_count`, `data_categories_breached`, `risk_to_subjects`, `revenue_impact`, the Art. 33/34 booleans, `brand_survival_threshold`, or `detected_at` from telemetry.

### FR5: Sentinel before display

The card is passed through `plugins/soleur/skills/incident/scripts/redact-sentinel.sh` before it is shown and before it is written. Raw reader stdout is not copied into the transcript. A vendor `--redact` flag is not a substitute.

### FR6: Existing gates stay

The founder confirms which proposed fields to keep. That confirm is not `ACK-ART33`, not `ACK-ART34`, and not `COMMIT-PIR`. Phase 1 classification and the Art. 33/34 prompts still run. Phase 7 still collects the 5-whys from the founder after recovery.

## Technical Requirements

### TR1: Call the scripts, not a new client

The pull shells out to the three scripts with the flags in FR2. It does not add a curl client, a Sentry list mode, or a write call.

### TR2: Empty is not health

A zero-row result is reported with the script's coverage verdict. The card includes a control note when the verdict says the window or the source cannot support "nothing happened." The Better Stack pull does not pass `--no-archive`.

### TR3: No production mutation

The pull does not apply, rotate, resolve, reboot, write Doppler, or append the breach register.

### TR4: Plan-time GDPR gate

Plan Phase 2.7 runs `soleur:gdpr-gate` on this change. The gate is advisory. The implementation does not edit the three legal documents. It does not state that a Better Stack Article 28(3) instrument exists.

### TR5: Tests use synthesized fixtures

Tests drive the card and the sentinel with synthesized log lines. They do not call Doppler or the live readers.

## Observability

The pull prints one stdout marker per source, `SOLEUR_INCIDENT_PULL source=<betterstack|sentry|supabase> verdict=<queried|not-queried|unverified|never-ran>`, with no log body. A refusal of the sentinel prints the skill's existing halt marker and shows nothing.

`discoverability_test.command`: `rg -n "SOLEUR_INCIDENT_PULL" plugins/soleur/skills/incident/SKILL.md` from a checkout, no SSH.
