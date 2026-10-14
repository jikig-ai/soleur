---
title: Add a Cursor CLI plugin adapter
status: adopting
date: 2026-10-06
issue: 9608
related: [9611, 9610, 9609]
related_adrs: [ADR-179, ADR-223, ADR-226, ADR-245]
tags: [harness, cursor, plugin]
brand_survival_threshold: single-user incident
---

# ADR-274: Add a Cursor CLI plugin adapter

## Status

**Adopting — 2026-10-06 (#9608).** Flips to `accepted` when slice 2's committed shape note quotes the support bar below. In this record, **harness** means the `Harness` union in `plugins/soleur/lib/harness.ts`. The word is not in `knowledge-base/project/glossary.md`.

Ordinal census on 2026-10-06, after `git fetch origin --prune`, over `refs/heads` and `refs/remotes/origin`: ADR-274 was unused. `origin/main` holds `ADR-273-schema-constrained-handler-side-publication.md`. This record moved off the provisional ordinal 273 in the merge edit. The spec directory and tasks file contain no ordinal 273 citation. The colliding record's own citations stay on 273.

## Context

An operator who already runs Soleur in Codex, Devin, or Grok Build cannot run the same lifecycle in the Cursor CLI. `Harness` has no `cursor` member, so that session is `unknown`, and the unknown instructions name the Skill tool and the Task tool.

The Cursor CLI `/` menu is one list. `/plan`, `/help`, `/review`, and `/shell` are built-ins. Skill names are lowercase letters, numbers, and hyphens. Default discovery of an omitted manifest field would load `plugins/soleur/commands/`, `plugins/soleur/skills/`, and `plugins/soleur/hooks/hooks.json`.

The plugin reference types `hooks` as a path to a config file or an inline object. An omitted field loads `hooks/hooks.json`. A directory does not replace that discovery.

## Considered Options

- **CLI now, editor later.** Pros: one protocol to measure, and the names can be generated before a second surface exists. Cons: the IDE editor agent stays out until #9611. Chosen.
- **Copy the Claude or Devin `hooks.json` and call it the Cursor registry.** Pros: the file would look populated. Cons: those events are a different protocol, and a copied file is not evidence the CLI loaded it. Rejected. Slice 1 points `hooks` at `./cursor/hooks-empty.json` whose body is `{ "hooks": {} }`.
- **Submit a listing to the Cursor marketplace.** Pros: a second machine could install from the gallery. Cons: that submission is a separate contract, and nothing in this decision authorizes it. Rejected. Install is a local `--plugin-dir` from this repo, plus `agent plugin marketplace add` of this git URL.
- **Call the plugin supported when the manifest exists.** Pros: slice 1 would close #9608. Cons: a session would still be `unknown`, hooks would not fire, and the public sentence would be ahead of the measurement. Rejected.

## Decision

Cursor CLI is a host runtime with its own manifest, a generated name map, and, after a fresh-session capture, its own hook events in that empty plugin config.

`/go` and `/sync` stay bare. Every other skill and agent is `soleur-` prefixed, including `/soleur-help`, `/soleur-plan`, and `/soleur-review`. The canonical tree stays the source. Cursor names are generated. The skill tree is not hand-copied (ADR-245). Each harness keeps its own registry (ADR-223). There is no `:-` plugin-root fallback (ADR-179).

`detectHarness` does not grow a predicate until a marker is measured on the Cursor CLI and shown not to match a non-CLI process. `CURSOR_AGENT` is documented as non-empty when Cursor is running. That sentence does not say the variable is CLI-only. A predicate that also matches the IDE fails the support bar.

The plugin is supported only when slice 2's committed shape note quotes all four of these: `/go` classifies, one pipeline skill finishes its gates, one agent spawn runs or is refused in words, and each guard fires. Slice 1's pull request does not close #9608.

## Consequences

A local install and a git install can register one `/go` and one `/sync`. Slice 1 states that it does not classify the session as `cursor`, does not run hooks, and does not block a commit. Public README, getting-started, comparison, blog, and battlecard pages stay unchanged until the support bar is met. When this status flips to `accepted`, grep `knowledge-base/legal` for future-tense sentences about Cursor or the harness list and route hits to the CLO. Do not edit those pages in the flip commit without that review.

`origin/main` took 273 before this merge. This file is ADR-274. The colliding record's citations were not edited.

## Cost Impacts

None. No new Soleur subscription and no new credential. The operator's existing Cursor CLI is the host.

## NFR Impacts

None. No NFR register row changes tier. No new Sentry monitor. No soak.

## Principle Alignment

AP-004 (Agent-native parity): Aligned — the same lifecycle skills are reachable from the Cursor CLI once the support bar is met.
AP-006 (All knowledge in committed repo files): Aligned — the name map is generated into the repo.
AP-007 (Exhaust automation before manual steps): Aligned — names come from the generator, not a hand-copied tree.
AP-008 (Doppler for secrets): N/A — no new secret.
AP-011 (ADRs for architecture decisions): Aligned — this record is the decision.
AP-012 (New vendor checklist): N/A — no Soleur-paid vendor and no new vendor environment variable. Anysphere is not added as a processor.
