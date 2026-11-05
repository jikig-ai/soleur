# Tasks: founder pull into the incident skill

Plan: `knowledge-base/project/plans/2026-11-05-feat-incident-investigate-entry-plan.md`
Lane: cross-domain

"Incident" means a production outage the founder is responding to, the sense of `plugins/soleur/skills/incident/SKILL.md`. It does not mean `.claude/hooks/lib/incidents.sh`.

Do not edit the three reader scripts, `redact-engine.py`, `templates/pir.md`, the skill `description:`, or the privacy, GDPR, or data-protection documents. Do not file a tracking issue from the plan's line estimate.

## Phase 1: Setup

- [x] 1.1 Add `SOLEUR_INCIDENT_PULL\b` to `MARKER_RE` in `apps/web-platform/server/git-lock-marker-telemetry.ts`, and nothing narrower. The drift-guard sample is `SOLEUR_INCIDENT_PULL file=.git/config.lock type=chardevice rdev=1:3`. Comment it `MIRRORED-NOT-PAGED`: the extractor is the agent `PostToolUse(Bash)` hook. Do not add the marker to `WEDGE_RE`.

## Phase 2: Core Implementation

- [x] 2.1 Write the pull at the start of `## Phase 0 — Capture facts` in `plugins/soleur/skills/incident/SKILL.md`, before the nineteen-field list. Retarget the first blockquote so it is not a second pull. Leave the deployed-root sentinel anchor in the Phase 6 fence only.
  - [x] 2.1.1 Optional window: omitted means Better Stack `--since 1h` and Supabase `--since 24h`. A supplied window is one quoted word on the skill-side allowlist, or that source is `verdict=never-ran` `reason=usage` and is not executed. Sentry has no window. An issue id outside `^[A-Za-z0-9_-]+$` is not executed.
  - [x] 2.1.2 One shell from the worktree root. Redirect each reader's stdout to a `0600` temp outside the repo, discard stderr, and remove the temp on EXIT, INT, TERM, and HUP. Do not print the temp path.
  - [x] 2.1.3 Better Stack uses Doppler `prd_terraform` and names `t520508_soleur_inngest_vector_prd_3_logs`. Supabase uses Doppler `prd` and ref `ifsccnjhymdmidffkzhl`. A second Supabase line runs only when the founder gives `soleur-inngest-prd` or `pigsfuxruiopinouvjwy`. Sentry uses Doppler `prd` and runs only with a valid issue id.
  - [x] 2.1.4 Map the exits in the plan: Better Stack 3 is `never-ran`; 2 and 78 are `unverified` `reason=credential-refused`; exit 0 with an empty body is `stdout-empty`. Supabase copies the stdout `verdict=` and `reason=` pair and does not copy `rows=`. Sentry 77 is `unverified` `reason=401`. Any unnamed exit is `unverified` `reason=reader-exit-N`. A wrapper failure is `never-ran` `reason=wrapper`.
  - [x] 2.1.5 Print `SOLEUR_INCIDENT_PULL` with `source=`, `verdict=`, and an optional `reason=`. The verdict set stays `queried`, `not-queried`, `unverified`, and `never-ran`.
  - [x] 2.1.6 If the complaint matches the sentinel, omit that sentence, print no offset line, and still show the rest of the card. Never pass it as `--grep`.
- [x] 2.2 Add `plugins/soleur/skills/incident/scripts/pull-card.sh`. It takes a source name, an exit code, and a stdout path, and it prints one coverage line. It does not print the path, a log line, `rows=`, or a decoded body, and it does not echo `SOLEUR_INCIDENT_PULL`.
- [x] 2.3 Run the existing sentinel on the printer's lines, by the single Phase 6 assignment. Show the card only on exit 0. Exit 1 emits `reason=card-redaction-failed` and starts the interview. A zero-byte card emits `reason=card-empty` and starts the interview. Exit 2 keeps `SOLEUR_INCIDENT_HALT`.
- [x] 2.4 On confirm, copy the one coverage sentence into the root-cause field. `hypotheses=none` copies nothing. Do not copy into the 5-whys, the breach fields, or the Art. 33 tokens. Confirming is not `ACK-ART33`, `ACK-ART34`, or `COMMIT-PIR`, and it does not set `detected_at`.
- [x] 2.5 In `plugins/soleur/skills/incident/scripts/dry-run.sh`, print three `verdict=never-ran` lines with `echo "SOLEUR_INCIDENT_PULL` or `printf 'SOLEUR_INCIDENT_PULL` and no leading indent, before the Phase 0 facts marker. Do not call Doppler or the readers. Keep the single fixture argument.

## Phase 3: Testing

- [x] 3.1 Add `plugins/soleur/skills/incident/test/fixtures/pull-card-synthetic.json` with a UUID, an IPv4 address, and an email inside `event_message` and `message`. No live capture.
- [x] 3.2 Add `plugins/soleur/skills/incident/test/pull-card.test.sh`. It asserts the `SKILL.md` command order, the dry-run markers, the printer's silence on secrets and `rows=`, the Doppler config split, the allowlist refusal, and `reason=card-empty`. No test calls Doppler. Headless stays skill prose.
- [x] 3.3 Run `apps/web-platform/test/git-lock-marker-telemetry.test.ts` and `plugins/soleur/skills/incident/test/pull-card.test.sh`.
