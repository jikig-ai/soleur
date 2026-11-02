---
title: launch-check — a read-only skill whose Soleur baseline is derived from the guard manifest
status: adopting
date: 2026-11-02
supersedes: none
issue: 11910
related: [7442, 7452, 11867]
related_adrs: [ADR-178, ADR-193, ADR-236, ADR-295]
tags: [plugin, customer-repo, redaction, baseline]
---

# ADR-314: launch-check — a read-only skill whose Soleur baseline is derived from the guard manifest

## Context

Customers who arrive with an existing repository and an MVP (the first is alpha tester #1) have no way to learn what stands between that repo and real users, nor which Soleur engineering practices it lacks. `/soleur:sync` bootstraps a knowledge base but is a write path that the web platform runs headless on every clone (`apps/web-platform/server/auto-sync-trigger.ts`), and its customer-repo path had defects (#7442, fixed; #7452, post-MVP follow-ups still open). `soleur:verification-scaffold` installs four guards but cannot say which are missing.

## Decision

1. **A new skill, `launch-check`, not a `/soleur:sync` area and not a `verification-scaffold` mode.** It is model-invocable (its 18-word description is counted in the skill-description budget, which has only a few words of headroom left) because a customer asking whether their repository is ready should reach it; its analysis writes exactly one file, `knowledge-base/engineering/readiness/launch-check.md`.
2. **The Soleur-baseline guard checks are derived at run time from `verification-scaffold/references/guards.tsv`** (`tier=v1` rows, columns resolved by header name). They are never listed in the skill (ADR-193, "the population is derived, never listed"). An empty or unreadable manifest aborts with `reason=baseline-source-empty`; it never reads as "zero baseline checks". Non-guard conventions (agent-conventions file, architecture notes, the Next.js import-boundary gate) are rows in `references/checks.tsv`.
3. **Findings carry the check id as their identity.** Re-runs diff against the previous report's fenced state block (`schema_version`, `catalog_hash`, one `finding <id> open|accepted [date reason]` line per finding), listing closed, new, accepted and retired ids. A customer accepts a finding by editing its state line. No issue numbers live in the state block.
4. **Packaging constraint.** Everything the skill reads at run time ships inside `plugins/soleur/`. The plugin root is resolved by identity (the manifest names `soleur`), and a missing `guards.tsv` or `redact-sentinel.sh` aborts with `reason=plugin-root-unresolved` (#7442).
5. **Redaction trust boundary.** One chokepoint, `lc_emit_checked`, scans the exact report bytes with `redact-sentinel.sh` and `gitleaks` and writes nothing on a hit or on a scanner that did not run. Secret-class findings (`SEC-01`, `SEC-02`) are counts only; their locations never reach any file. The AI-assisted review items use a closed schema (status, severity enum, evidence ids), so free text from that step cannot pass the scanner; titles and remedies come from the catalog. The facts file is not trusted either: `render` validates it against the catalog (every non-judged id exactly once, known statuses) and passes evidence only if it is a fixed detector phrase, a bare path or `path:line` (count-only ids keep fixed phrases), and it parses the previous report with the state-line grammar, refusing a report that has no state block. A check that did not run (`na`, `unsupported-stack`, an unreviewed AI-assisted item) is carried or listed under *Not assessed*, never closed. All report prose originates in static files under `references/`, linted for assurance wording by a test.
6. **Local CLI, no telemetry.** The skill runs on the customer's machine and key and has no network call and no share-back path. A hosted variant is out of scope until an Art. 28(3) instrument exists. The skill is model-invocable and ships inside the plugin, so nothing in the plugin stops a hosted agent from loading it: the platform must not enable it until that instrument exists. Unattended runs (`CI`, or `LAUNCH_CHECK_HEADLESS=1`) are refused a report write by the script. The scanner, sentinel and manifest overrides (`LAUNCH_CHECK_GITLEAKS`, `LAUNCH_CHECK_REDACT_SENTINEL`, `LAUNCH_CHECK_GUARDS_TSV`) are honoured only under `LAUNCH_CHECK_TEST=1`, so an inherited environment variable cannot weaken the redaction gate. `scan --show-secrets` needs a real terminal.
   SEC-01 scans every file of the last commit through a throwaway index (not `git archive`, which honours `export-ignore`), including the never-read classes, ignoring the repository's own gitleaks configuration; a snapshot that cannot be read aborts instead of reading as clean.
7. **Issue-epic creation is a separate change (planned).** When built, every `gh` write goes through one function that executes only a saved preview plan, refuses under `--dry-run` and headless, and treats an existing marked issue (open or closed) as present. Consent is skill-enforced (the customer is asked before `--create`) plus the harness permission prompt; the script cannot prove human approval.

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| A `/soleur:sync` area | `sync` is a write path run headless on every clone; an unattended analysis plus issue creation there would act on every connected repo with no approval step, and its customer-repo path is already broken in places. |
| `verification-scaffold --audit` | The manifest has four v1 guards; it cannot express production readiness (observability, scale, architecture). The baseline reuses the manifest instead. |
| A hand-listed baseline inventory | Goes stale on the next manifest edit; contradicts ADR-193. |
| A readiness score | Reads as an attestation (CLO, CMO); the report is a findings list with a standing banner. |
| Fingerprint- or path-keyed finding ids | Would put a secret's location or a renamed path into committed state; check ids are stable and carry no location. |

## Consequences

- Adding a v1 guard to `guards.tsv` adds a baseline check with no code change; the `baseline.test.sh` suite pins that by name identity.
- The baseline is small (four guards plus three conventions); a repository that has the original form of a guard (the source repo itself) is recognised through the manifest's `source_files` column.
- Detectors are heuristics. A negative reads "not identified in the files read", and the banner states that absence of findings is not assurance.
- Scan time scales with repository size (about 27 s on this 20k-file monorepo, dominated by gitleaks).
