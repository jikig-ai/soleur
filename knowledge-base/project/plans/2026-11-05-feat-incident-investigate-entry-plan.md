---
title: "feat: pull logs into the incident skill"
type: feat
date: 2026-11-05
slug: feat-incident-investigate-entry
branch: feat-incident-investigate-entry
priority: medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
pr: 12143
issue: 12162
closes: 12162
---

# feat: pull logs into the incident skill

## Overview

The incident skill already names the three production log readers, then collects nineteen facts from the founder. This plan adds one pull-first phase inside that skill. The phase runs the existing readers, passes the hypothesis card through the existing redaction sentinel, and shows the cleared card before the founder confirms facts. The run stays founder-started. Scheduled repair, a new agent, and edits to the legal documents stay out of this change.

"Incident" means a production outage the founder is responding to, the sense of `plugins/soleur/skills/incident/SKILL.md`. It does not mean the rule-telemetry counter in `.claude/hooks/lib/incidents.sh`. The glossary has no entry for the word.

Tracking issue: #12162. Draft PR #12143.

## Problem Statement / Motivation

Phase 0 of the incident skill tells the agent to pull Better Stack, Sentry, and Supabase, then asks the founder for nineteen facts. Nothing in the skill executes those readers. The founder restates logs the repo can already read, and a story typed from memory becomes the post-mortem's cause.

## Proposed Solution

Insert the pull as the first part of `## Phase 0 — Capture facts`, before the nineteen-field list. On `--dry-run` and `--headless`, print three `SOLEUR_INCIDENT_PULL` lines with `verdict=never-ran` and do not call Doppler or the readers. On a live run, one shell from the worktree root runs the three existing scripts with stdout redirected to a temp file outside the repo and stderr discarded. A printer script reads that temp and prints one coverage line per source. The skill forbids `Read` or `cat` of the temp. The existing sentinel runs on those lines. The card is shown only when the sentinel exits 0.

The card is a coverage record. It records the window, the table or project ref, the exit, and the coverage line for each source. It does not rank causes, name a service, an error, or a user count, or say the complaint is false. A hypothesis is one sentence built only from those coverage fields, or the card says `hypotheses=none`. It does not print a pull time and does not offer a value for `monitoring_detected_at`. The founder still confirms `affected_user_count`, `data_categories_breached`, `risk_to_subjects`, `revenue_impact`, and `detected_at`. When the founder confirms the card, its one coverage sentence is copied into the root-cause field. `hypotheses=none` copies nothing. Confirming the card is not `ACK-ART33`, not `ACK-ART34`, and not `COMMIT-PIR`.

## Technical Considerations

- The pull is outside the under-60-second classification budget. It does not block the Art. 33/34 prompts once the founder has confirmed the fields those prompts read.
- The deadline formula stays `detected_at` plus 72 hours after the founder confirms `detected_at`. A log timestamp does not start that figure.
- Do not add a second copy of the deployed-root sentinel anchor. `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` Test 18a requires the literal `${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh` exactly once in the incident skill. The new phase points at the sentinel Phase 6 already resolves.
- Leave the skill `description:` frontmatter as it is. The pull is an internal phase. The description still matches when the skill is invoked.
- Do not pass the founder's complaint sentence to `--grep`. A complaint is a claim. A Better Stack filter that names one producer matches journald `SYSLOG_IDENTIFIER` in both the unescaped and the backslash-escaped form. This slice does not add that filter.
- The reader command itself redirects stdout to the temp and discards stderr (`2>/dev/null`). A later `doppler run` whose stdout is the log stream is the transcript, and the sentinel never sees that tool result. The printer is the only reader of the temp. It prints coverage fields and does not print the path.
- Do not decode Better Stack `.raw`. Do not walk JSON keys. Do not drop credential-noun values. The card never contains those values, so there is nothing to drop. Supabase `rows=` stays in the stderr evidence block, which this phase discards. The block says the count must not be quoted apart from that block.
- A zero-byte card is a failure. The sentinel exits 0 on a zero-byte file, so emptiness is not a pass. Emit `SOLEUR_INCIDENT_PULL` with `reason=card-empty`, show nothing, do not print `SOLEUR_INCIDENT_HALT`, and start the nineteen-field interview. Three source lines and `hypotheses=none` are a real card and are shown.
- Sentinel exit 1 on the pull card emits `SOLEUR_INCIDENT_PULL` with `reason=card-redaction-failed`, shows nothing, and prints no offset line and no temp path. Do not enter Phase 6's iterate-until-clean loop, and do not print `SOLEUR_INCIDENT_HALT`. The nineteen-field interview still starts. Phase 6's iterate-until-clean path is unchanged. Exit 2 keeps the existing halt marker.
- Phase 0 does not contain the literal `${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh`. That literal stays once, in the Phase 6 fence. The pull tells the agent to run the sentinel named by that one assignment.

### Attack Surface Enumeration

Paths that can put a production log into the transcript:

- The new pull phase, if it prints reader stdout or stderr. Checked: stdout is redirected on the reader command, stderr is discarded, and the printer is the only program that reads the temp. The skill forbids `Read` or `cat` of that path.
- The existing Phase 0 blockquote, if it remains an improvised second pull with `--grep`. Checked: retarget that sentence at the new phase so there is one procedure.
- Phase 6, which already scans the post-mortem draft. Unchanged. The pull is an earlier pass on the card, not a replacement.
- `--dry-run` and `--headless`. Checked: they print `verdict=never-ran` and do not call the readers.
- Vendor `--redact` on `scripts/sentry-issue.sh`. Not used. It masks emails and bearer values only.

## Research Insights

### Premise Validation

Checked #7529 with `gh issue view`: still OPEN, title records the Better Stack vendor DPA as unexecuted. The plan does not claim an Article 28 instrument and does not edit the privacy policy. Checked #4886 with `gh issue view`: state MERGED, title is the cron workspace-gc fix. The incident skill cites it as the report that blamed ENOSPC when a Sentry read showed a dirty clone. The plan uses that sentence. It does not treat #4886's title as "fluent wrong cause." The three reader scripts and `redact-sentinel.sh` exist on this branch. `plugins/soleur/skills/incident/SKILL.md` names them in the Phase 0 blockquote and does not execute them. No plan file for this branch existed before the skeleton. Community discovery: no uncovered stack. Functional overlap: registries returned skills for Sentry, Better Stack setup, and generic incident response. None calls these three readers and this sentinel. Skip-install.

### Property List

1. When the founder starts the incident skill, the skill runs the existing readers and shows a redacted hypothesis card before the nineteen-field interview.
2. `--dry-run` and `--headless` do not perform a live pull, and the transcript says so.
3. The card does not fill the breach fields or `detected_at` from telemetry.
4. Raw reader output does not enter the transcript.
5. A zero, an exit 0, and a query that never ran stay distinct on the card.

### Cut List

- New skill or new agent. Property 1 is already owned by `plugins/soleur/skills/incident/SKILL.md`.
- Scheduled auto-fix, cron or webhook auto-PIR, paging, the Better Stack Claude plugin. The founder selected the investigate entry. The May 2026 incident skill already forbids auto-fire.
- Sentry list mode and `--host-events`. The issue and latest-event modes require an id. No property needs a list.
- Editing `scripts/betterstack-query.sh`, `scripts/sentry-issue.sh`, or `scripts/supabase-logs-query.sh`. They already implement the reads.
- A new ack token. `ACK-ART33`, `ACK-ART34`, and `COMMIT-PIR` already exist.
- Legal-document edits. Counsel owns that text. Issue #7529 stays the DPA tracker.

### Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| A zero-row result carries the script's coverage verdict | Better Stack mode 2 prints JSONEachRow and returns the HTTP status. An empty body exits 0 and has no `verdict=` token. Supabase always emits `verdict=` and `reason=` | Better Stack exit 0 with an empty body is `exit=0` and `stdout-empty`. It does not say the table or the archive had no rows. Supabase copies the stdout `verdict=` and `reason=` pair. `rows=` is not copied |
| Better Stack exit 3 and "Doppler unavailable" are one condition | Better Stack exit 3 is unset `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}`: the query never ran. Supabase missing creds is exit 2. Supabase exit 3 is an inconclusive data verdict after a query | Map Better Stack 3 to `never-ran`. Map Supabase 2 to unverified. Map Supabase 3 to queried, and keep the script's `verdict=` and `reason=` |
| Sentry without an id can still be queried | Issue and latest-event modes exit 64 without an id. 401 exits 77 and 403 exits 78, both terminal. Exit 78 is also the `set -x` guard before any HTTP | No id: do not exec, print `sentry: not-queried reason=no-issue-id`. Exit 77 is `unverified` with `reason=401`. Exit 78 is `unverified` with `reason=credential-refused`. Neither is retried, neither shows a body, and neither halts the skill |
| The sentinel's existing halt covers a dirty card | Exit 1 means redaction needed and prints offset lines. Exit 2 is the halt | Exit 1 shows nothing, including those offset lines. Exit 2 keeps `SOLEUR_INCIDENT_HALT` |

### Learnings the implementation obeys

- `knowledge-base/project/learnings/workflow-patterns/2026-07-08-self-pull-observability-in-diagnostic-loops-never-ask-operator-to-fetch.md` — the skill runs the readers. It does not ask the founder to paste logs.
- `knowledge-base/project/learnings/workflow-patterns/2026-07-15-infra-incident-diagnose-before-mutate-and-no-out-of-band-applies.md` — the phase stops at the card. It does not apply, rescue, or reboot.
- `knowledge-base/project/learnings/2026-07-18-betterstack-followthrough-probe-must-field-isolate-syslog-identifier.md` — do not `--grep` the complaint.
- `knowledge-base/project/learnings/2026-09-18-the-loop-was-not-failing-it-was-succeeding-at-nothing-and-said-ok.md` — exit 0 and an empty body are not "nothing happened."
- `knowledge-base/project/learnings/2026-05-14-incident-skill-impl-review-vs-plan-review-and-push-protection-defang.md` — fixtures are defanged. No contiguous token shape in the skill or the plan.
- `knowledge-base/project/learnings/2026-06-08-debug-mode-stream-redaction-and-pushprotection.md` — drop credential-noun values before the shape scan.
- `knowledge-base/project/learnings/workflow-patterns/2026-07-14-watchdog-issue-body-root-cause-is-a-claim-verify-via-observability.md` — the complaint stays a claim.
- `knowledge-base/project/learnings/2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md` — run `soleur:gdpr-gate` even though the diff matches no migration regex.

### External practice

Opened for this plan, and applied only as constraints on the card:

- Show post-sentinel text only. OWASP Logging Cheat Sheet, https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html
- A log line that lines up with a failure is a hypothesis. https://www.pagerduty.com/eng/lessons-from-pd-labs-from-experimentation-to-a-production-ready-sre-agent/
- Do not turn a row count into a user count. https://www.elastic.co/docs/reference/aggregations/search-aggregations-metrics-valuecount-aggregation
- The founder starts the pull. https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/artificial-intelligence/the-ico-s-call-for-evidence-on-agentic-ai/about-agentic-ai/
- Do not write that an Article 28 contract is in force. https://www.legislation.gov.uk/eur/2016/679/article/28/data.html — Soleur's own record is issue #7529, still open. This slice does not edit the privacy policy.

Framework-docs research was skipped. The change adds no library. The readers and the sentinel are already in the repo.

### Spec-flow dispositions

`soleur:product:spec-flow-analyzer` returned after the first draft. These points are now acceptance criteria. The verdict vocabulary on `SOLEUR_INCIDENT_PULL` stays `queried`, `not-queried`, `unverified`, and `never-ran`. A `reason=` suffix carries the script's distinction. No fifth verdict is added.

- An omitted window records the script defaults (`--since 1h`, `--since 24h`). A supplied window is the only `--since`, and it is one quoted word on the skill-side allowlist or that reader is not executed. Sentry takes no window.
- Better Stack exit 2 is the script's refuse-to-send class (host pin or credential shape), mapped to `verdict=unverified` and `reason=credential-refused`. It is not exit 3 and it is not Sentry's 403. Stderr from that refusal is not shown. Supabase exit 1 is recorded once and not retried. A Doppler wrapper failure is `never-ran` with `reason=wrapper`. The skill does not start `doppler login`. One source failing does not skip the others or the interview.
- The card quotes no raw log line. Production rows contain values the sentinel fails closed on (UUID, IPv4, email). A card that pastes those rows can never be shown. Counts, exits, windows, the table or ref, and the complaint as a claim are the card. The Better Stack line names the table, `limit=100` (the script default at `SINCE="1h"; … LIMIT=100`), and `truncated=true` when 100 rows return. Empty stdout is not disproof of the complaint.
- The complaint is added to the Phase 0 pre-echo sentinel set. It is still never passed as `--grep`.
- The card does not print a pull time and does not offer a value for `monitoring_detected_at`. The existing `mttd-transposed` halt still applies to a pair the founder confirms. The pull does not feed that halt.
- One stdout temp is `mktemp` outside the repo, mode `0600`, removed on EXIT, INT, TERM, and HUP. Stderr is discarded. The printer is the only reader of the temp.

Not adopted: a `RETRY-PULL` token. The cut list refuses a new acknowledgement token. The founder starts the skill again when the window missed the incident.

### Advisor consult

A general subagent stood in for the advisor tier. This harness has no separate advisor SKU. Applied before plan review, as a technical correction. The founder's drafted cause stays. It is assembled only from coverage lines.

- Better Stack stdout is JSONEachRow, and `raw` is double-encoded JSON. Supabase human mode is log lines, then one `verdict=` line. Sentry issue mode is one JSON object and has no `raw` column. One decode path would drop the Supabase verdict or leave message bodies on the card.
- Drop credential-noun keys, and also omit `event_message`, `message`, and event-body fields before the sentinel. Key-dropping does not remove a UUID, an email, or an IPv4 address inside those strings.
- A hypothesis may use only the coverage fields: source, window, table or ref, exit, row count, truncated, and the Supabase verdict. Otherwise the card says `hypotheses=none`.
- `scripts/dry-run.sh` takes one fixture argument (`$# -ne 1`). The Sentry issue id is not a second positional and is not a new dry-run prompt.

Plan review superseded the decode and the credential-noun drop. The printer never emits JSON values, so those steps are not a second redaction pass. The coverage-field limit and the single dry-run argument stay.

## Hypotheses

The network-outage checklist matched the letters SSH inside the spec sentence that the discoverability command runs from a checkout and does not use SSH. This plan does not open a host, change a firewall, or diagnose an unreachable machine. Files to Edit are the incident skill, its dry-run script, and the telemetry marker. Files to Create are the printer, one test, and one fixture.

1. **L3 firewall.** Opt-out: no firewall resource is in Files to Edit or Files to Create. Verified by reading that list. No `hcloud` call is part of this change.
2. **L3 DNS.** Opt-out: the plan introduces no hostname.
3. **L7 TLS.** Opt-out: no new HTTPS client. The pull calls the three existing scripts.
4. **L7 service.** Opt-out: no sshd change and no host journal read. The pull reads the existing log scripts.

## Files to Edit

- `plugins/soleur/skills/incident/SKILL.md` — add the pull at the start of Phase 0, and retarget the first blockquote so it is not a second improvised pull. Do not add another copy of the deployed-root sentinel anchor. Do not change `description:`.
- `plugins/soleur/skills/incident/scripts/dry-run.sh` — before the Phase 0 facts marker, print the three `SOLEUR_INCIDENT_PULL` lines with `verdict=never-ran`. Do not call Doppler or the readers. Keep the single fixture argument.
- `apps/web-platform/server/git-lock-marker-telemetry.ts` — add `SOLEUR_INCIDENT_PULL\b` to `MARKER_RE`, and nothing narrower. The drift guard's sample is `SOLEUR_INCIDENT_PULL file=.git/config.lock type=chardevice rdev=1:3`, so a pattern that requires `source=` fails that sample. The guard collects only `echo "` and `printf '` from every `skills/*/scripts/*.sh`, with no domain filter. `dry-run.sh` emits `echo "SOLEUR_INCIDENT_PULL` or `printf 'SOLEUR_INCIDENT_PULL`, with no leading indent. A `printf "%s\n"` form is invisible to the guard. A `SKILL.md` mention is domain-filtered and does not by itself fail the guard. Comment it `MIRRORED-NOT-PAGED`: the only extractor is the agent `PostToolUse(Bash)` hook, not a hosted cron's stderr. The printed line carries `source=`, `verdict=`, and an optional `reason=`. It is not added to `WEDGE_RE`. Do not add a second `SOLEUR_*` name for the redaction failure; that case is `reason=card-redaction-failed` on this marker.

## Files to Create

- `plugins/soleur/skills/incident/scripts/pull-card.sh` — prints one coverage line from a source name, an exit code, and a stdout temp. It does not echo `SOLEUR_INCIDENT_PULL`.
- `plugins/soleur/skills/incident/test/pull-card.test.sh` — synthesized fixtures only. `scripts/test-all.sh` already runs `plugins/soleur/skills/*/test/*.test.sh`. A missing test file is not a failure of that glob.
- `plugins/soleur/skills/incident/test/fixtures/pull-card-synthetic.json` — stand-in reader output. Format-shaped, low-entropy, no live capture.

## Implementation Phases

### Phase 1: Skill text

Add the pull procedure at the start of `## Phase 0 — Capture facts`, before the nineteen-field list.

The founder may pass an optional window. When it is omitted, Better Stack uses `--since 1h` and Supabase uses `--since 24h`, and the card records those defaults. When it is supplied, that value is the only `--since` for those two scripts, and it is one quoted word. The check is a skill-side allowlist, not a claim about the script's usage exit. Better Stack's allowlist is `Nh`, `Nm`, `Nd`, or `YYYY-MM-DDTHH:MM:SSZ`. The form `YYYY-MM-DD HH:MM:SS` is accepted only as that one quoted word. Supabase's allowlist is `Nm`, `Nh`, `Nd`, or one ISO timestamp. A refused value does not exec, and that source is `verdict=never-ran` with `reason=usage`. Sentry has no `--since`. Its card line says `window=n/a`. An issue id outside `^[A-Za-z0-9_-]+$` is not executed and is `verdict=never-ran` with `reason=usage`.

Live commands, archive arm left on, no `--no-archive`, no `--grep` of the complaint. Stdout is redirected to the temp on this same command. Stderr is discarded. Do not re-exec. Do not run `doppler login` or `scripts/ensure-doppler.sh`.

- `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h` — name table `t520508_soleur_inngest_vector_prd_3_logs` on the card. The script's default is that table, and its default `LIMIT` is 100. Name `limit=100`. Exit 3 → `verdict=never-ran`. Exit 2 and exit 78 → `verdict=unverified` and `reason=credential-refused` (the script refused to send, or a traced shell held the password; this is not Sentry's 403). Do not print stderr. Exit 0 with an empty body → `exit=0` and `stdout-empty`. That does not say the table or the archive had no rows. It is not health, and it is not disproof of the complaint. Exit 0 with a body → the row count is the number of stdout lines that contain `"raw"`, and `truncated=true` only when that count is 100. Do not decode `.raw`. Any other exit → `verdict=unverified` with `reason=reader-exit-N`, and the body is not rows.
- `doppler run -p soleur -c prd -- scripts/supabase-logs-query.sh --ref ifsccnjhymdmidffkzhl --since 24h` — this application ref is always the command. A second Supabase line, with the same `--since`, runs only when the founder gives the project name `soleur-inngest-prd` or the ref `pigsfuxruiopinouvjwy`. The word inngest alone does not add it. Do not replace the application query with the Inngest ref. The card names the project that was queried and says the other ref was not queried. Copy the stdout `verdict=` and `reason=` pair unchanged. Do not put `rows=` on the card. Do not count stdout log lines. Exit 0 is marker `verdict=queried` together with that reason (`FULLY_COVERED` or `TRUNCATED_AUTONARROWED`; both print `verdict=COVERED`). Exit 1 is marker `verdict=unverified`, the script's `verdict=` and `reason=` are copied once, the script calls a retry rational, and this skill does not run the command again. Exit 2 is `unverified` with the script's `reason=`. Exit 3 stays the script's data verdict on the card, marker `verdict=queried`, and `reason=ZERO_SOURCE_COVERAGE_UNESTABLISHED` is not disproof of the complaint.
- `doppler run -p soleur -c prd -- scripts/sentry-issue.sh <issue-id>` only when the founder supplies an id that matches `^[A-Za-z0-9_-]+$`. Otherwise `sentry: not-queried reason=no-issue-id` and the script is not executed. Exit 77 → `verdict=unverified` and `reason=401`. Exit 78 → `verdict=unverified` and `reason=credential-refused`. Exit 1 → `verdict=unverified` and `reason=reader-exit-1`. No retry, body not shown, and the skill does not halt. Do not pass `--redact`, `--host-events`, or `--liveness`. `prd_terraform` is the wrong config for this command.

Each source always gets a line. One failure does not skip the other sources or the nineteen-field interview. A Doppler wrapper failure before the script, including a missing `doppler` binary and a `prd` config that cannot be read, is `verdict=never-ran` with `reason=wrapper` for each source that did not run. Better Stack still runs when only `prd_terraform` can be read. Do not parse wrapper stdout as rows. Do not start `doppler login`.

Scan the complaint with the other Phase 0 strings before it is printed or copied onto the card. If it matches, omit that sentence, print no offset line, still show the rest of the card, and start the nineteen-field interview. It is never passed as `--grep`.

Print one stdout marker per source, with no log body: `SOLEUR_INCIDENT_PULL source=<betterstack|sentry|supabase> verdict=<queried|not-queried|unverified|never-ran>`. A `reason=` suffix is allowed. The verdict set does not grow.

### Phase 2: Card and sentinel

One shell, from the worktree root that contains `scripts/`. Create the stdout temp with `mktemp` outside the repository root, mode `0600`, and remove it on EXIT, INT, TERM, and HUP. The same shell redirects the reader, runs the printer, runs the sentinel, and prints the marker and the card. The test asserts the path is outside that root and is gone after the trap. Do not print the temp path on the pass path or the fail path.

`plugins/soleur/skills/incident/scripts/pull-card.sh` is the only reader of the temp. Arguments are the source name, the exit code, and the stdout path. It prints one coverage line. It does not print the path, a log line, `rows=`, or a decoded `.raw` body. Supabase's coverage line is the stdout `verdict=` and `reason=` pair. Better Stack's line is the table, `limit=100`, `exit=`, and either `stdout-empty` or the count of lines containing `"raw"`. Sentry's line is the marker fields only. The skill forbids `Read` or `cat` of the temp.

The card quotes no raw log line. A hypothesis is one sentence assembled only from coverage fields: source, window, table or ref, exit, the Better Stack line count, truncated, and the Supabase `verdict=` and `reason=`. It does not say what would disprove the complaint, and it does not say the complaint is false. If nothing can be said that way, the card says `hypotheses=none`. Three source lines and `hypotheses=none` are shown. A zero-byte card emits `reason=card-empty`, shows nothing, does not print `SOLEUR_INCIDENT_HALT`, and still starts the interview. The card is not written under `post-mortems/`. When the founder confirms the card, the one coverage sentence is copied into the root-cause field. `hypotheses=none` copies nothing. The card is not copied into the 5-whys or the Art. 33 tokens.

Run the sentinel by the single assignment in the Phase 6 fence. Do not paste that literal into Phase 0. No log-derived text is emitted before sentinel exit 0. Show the card only on that exit.

Sentinel exit 1 on the card emits `SOLEUR_INCIDENT_PULL` with `reason=card-redaction-failed`, prints no offset line, does not print the temp path, does not print `SOLEUR_INCIDENT_HALT`, and still starts the nineteen-field interview. Phase 6's iterate-until-clean path stays as it is. Exit 2 keeps the existing halt marker and shows nothing.

The card does not print a pull time and does not offer a value for `monitoring_detected_at`, `detected_at`, or `detection_method`. Confirming the card does not set those fields or any breach field. The founder still answers every field. A pair the founder confirms that has `monitoring_detected_at` before `detected_at` still hits the existing `mttd-transposed` halt. The pull does not feed that halt.

There is no `RETRY-PULL` token.

On `--dry-run` and `--headless`, print the three `never-ran` lines and do not call Doppler or the readers. `--headless` without a fixture then follows the existing headless rule: exit non-zero on the first blocking prompt and write nothing. `--dry-run` fills fields only from the fixture.

### Phase 3: Tests

`pull-card.test.sh` drives `dry-run.sh` on the existing dry-run fixture and asserts the three `never-ran` markers precede the Phase 0 facts marker, and that `dry-run.sh` contains no `doppler` or reader-script invocation. `dry-run.sh` keeps a single fixture argument. Those three lines are `echo "SOLEUR_INCIDENT_PULL` or `printf 'SOLEUR_INCIDENT_PULL`, with no leading indent. Headless is skill prose: the test does not claim `dry-run.sh` implements `--headless`. The order check reads `SKILL.md` and does not expect `dry-run.sh` to contain the reader commands.

A second case runs `pull-card.sh` on `pull-card-synthetic.json` with a fixture exit code and asserts the printer's stdout has no raw stream, no `rows=` value, no temp path, and no breach-field assignment taken from a line count. The fixture puts a UUID, an IPv4 address, and an email inside `event_message` and `message` fields. The printer's stdout contains none of those literals, and it still prints the coverage line. A fixture that pairs `verdict=COVERED` with `rows=0` is not a valid Supabase result. `reason=ZERO_SOURCE_COVERAGE_UNESTABLISHED` is not written as disproof. A zero-byte card emits `reason=card-empty`. A window outside the skill-side allowlist does not exec.

The same test fails if the skill's Better Stack command is not the `prd_terraform` command, if either other command uses `prd_terraform`, if `BETTERSTACK_LOGS_TOKEN` appears, or if an id outside `^[A-Za-z0-9_-]+$` is executed. No test calls Doppler.

## Alternative Approaches Considered

| Approach | Why it is out |
|---|---|
| A new SRE agent | `plugins/soleur/agents` has no such file. The February 2026 brainstorm scoped Terraform only |
| A new skill | It would copy the transcript gate and the post-mortem path |
| Install a community incident skill | None of the registry hits calls these readers and this sentinel |
| Scheduled auto-fix | The founder kept this out. The incident skill forbids auto-fire |

## User-Brand Impact

- **If this lands broken, the user experiences:** a hypothesis card, or a Phase 0 field accepted from that card, that names the wrong cause.
- **If this leaks, the user's data is exposed via:** a production log line (stack, pseudonymous id, raw workspace id, or secret) shown in the transcript or written into the post-mortem before the sentinel runs.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one fluent wrong cause, or one uncleared log line, is enough. The founder is the person in the transcript during the incident.

CPO reviewed this shape in the brainstorm on 2026-11-05. `soleur:engineering:review:user-impact-reviewer` runs at review time.

Sharp edge: a plan whose `## User-Brand Impact` section is empty, or omits the threshold, fails `deepen-plan` Phase 4.6.

## Observability

```yaml
liveness_signal:
  what: "one stdout line SOLEUR_INCIDENT_PULL per source on each incident-skill run"
  cadence: per-run
  alert_target: "founder transcript; no new pager"
  configured_in: plugins/soleur/skills/incident/SKILL.md
error_reporting:
  destination: "existing stdout marker SOLEUR_INCIDENT_HALT when the sentinel cannot run"
  fail_loud: "SOLEUR_INCIDENT_HALT"
failure_modes:
  - mode: "a reader never ran"
    detection: "SOLEUR_INCIDENT_PULL verdict=never-ran"
    alert_route: "founder transcript; no pager"
  - mode: "sentinel refuses the card"
    detection: "no card is shown; exit 2 also prints SOLEUR_INCIDENT_HALT"
    alert_route: "founder transcript; no pager"
logs:
  where: "cleared card in the transcript; raw reader streams stay in the temp file the trap deletes"
  retention: "temp file removed on exit; cleared card remains in the transcript"
discoverability_test:
  command: rg -n SOLEUR_INCIDENT_PULL plugins/soleur/skills/incident/SKILL.md
  expected_output: SOLEUR_INCIDENT_PULL
  # Measured 2026-11-05, before the skill edit: this command exits 1. That is the pre-work state. After the edit it must print the marker. The command has no pipe, semicolon, or substitution, so preflight Check 10 can run it.
```

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Operations

Carried forward from `knowledge-base/project/brainstorms/2026-11-05-incident-investigate-entry-brainstorm.md`. The plan does not change those rulings. No specialist was named for a further pass.

### Product (CPO)

**Status:** reviewed
**Assessment:** Extend the incident skill. Show a sentinel-cleared card with competing hypotheses and a coverage line per source. Confirming the card does not replace the Art. 33 acknowledgement or `COMMIT-PIR`.

### Legal (CLO)

**Status:** reviewed
**Assessment:** A founder-invoked pull is a new recipient, the harness model provider. Run the sentinel before the card is shown. Run the Art. 33/34 gate before the narrative. Do not write that an Article 28(3) instrument exists. Draft internal review, not legal advice.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The pull calls the three scripts and nothing else. Empty or exit-0 results are not health. The breach fields stay founder-confirmed.

### Operations (COO)

**Status:** reviewed
**Assessment:** No new vendor and no new schedule. Better Stack uses Doppler `prd_terraform`. Sentry and Supabase use Doppler `prd`.

**Brainstorm-recommended specialists:** none

Product/UX Gate: tier NONE. Files to Edit and Files to Create are a skill, a shell harness, and a fixture. No UI-surface path.

## Open Code-Review Overlap

None. Open issues labeled `code-review` were listed (95) and none of their bodies contain the four planned paths.

## GDPR gate

Phase 2.7 ran against this plan. The canonical path regex matches no file in Files to Edit. Triggers (a) and (b) fired: log text can reach the model transcript, and the threshold is `single-user incident`.

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

No Art. 9 column. No new schema, so Art. 6, Art. 5(1)(e), and Art. 17 do not fire. No `Critical` finding, so no `compliance-posture.md` row and no `compliance/critical` issue from this gate.

Suggestion: the transcript copy is a recipient the privacy-policy log sections do not name, and #7529 is still the unsigned Better Stack DPA. This change does not edit those documents and does not state that an Article 28 instrument exists.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "would it make sense to add this capability to Soleur for the SRE agent/skills?" | Phase 1 in `plugins/soleur/skills/incident/SKILL.md` | mapped |
| 2 | "One founder command that pulls Better Stack, Sentry, and Supabase logs, then hands a drafted cause to the existing incident report. No scheduled repair, no Better Stack plugin." | Phase 1, Phase 2, Non-goals in the brainstorm | mapped |
| 3 | "auto-fix errors on a schedule" | — | descoped — justification: the founder selected the investigate entry, which keeps scheduled repair out |
| 4 | "set up Better Stack without clicking in UI" | — | descoped — justification: Better Stack setup already lives in Terraform, and the selected entry does not include it |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plugins/soleur/skills/incident/SKILL.md` pull phase | "One founder command that pulls Better Stack, Sentry, and Supabase logs, then hands a drafted cause to the existing incident report. No scheduled repair, no Better Stack plugin." | asked |
| `plugins/soleur/skills/incident/scripts/dry-run.sh` never-ran markers | "No scheduled repair, no Better Stack plugin." | inferred — justification: `--dry-run` and `--headless` must not become a live pull, and a missing marker is indistinguishable from a pull that returned nothing |
| `plugins/soleur/skills/incident/test/pull-card.test.sh` | "hands a drafted cause to the existing incident report" | inferred — justification: the card is the cause the founder sees, and a test is the only check that a fixture secret is not printed |
| `pull-card-synthetic.json` | — | inferred — justification: `cq-test-fixtures-synthesized-only` forbids a live capture in the test |
| Credential-noun drop before the sentinel | — | cut at plan review — the printer never emits JSON values |
| Stderr captured in its own temp file | — | cut at plan review — stderr is discarded; `rows=` stays in the evidence block and is not copied |
| `plugins/soleur/skills/incident/scripts/pull-card.sh` | — | inferred — justification: the agent reading the temp is the transcript, so a printer is the only check that a fixture secret is not printed |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `apps/web-platform`
- Planned files: 6 | Estimated changed lines: 560
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Guard Contract

### Guard 1 — pull card shows no raw stream and fills no breach field

**Property.** The text the incident skill shows after a pull contains no reader stdout or stderr, and it does not assign `affected_user_count`, `data_categories_breached`, `risk_to_subjects`, `revenue_impact`, or `detected_at` from telemetry.

**Assembly.** The chokepoint is `pull-card.sh` stdout after `scripts/redact-sentinel.sh` exits 0. The reader command redirects stdout to a temp outside the repo and discards stderr. The skill forbids `Read` or `cat` of that temp. The printer does not copy `rows=`, a decoded body, or the temp path. Live runs and `dry-run.sh` print `SOLEUR_INCIDENT_PULL` with `source=`, `verdict=`, and an optional `reason=` only.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | A line count is copied into `affected_user_count` on the shown card | RED |
| 2 | The printer stdout contains a fixture email, UUID, or IPv4 address | RED |
| 3 | The printer prints a Supabase stderr line or a `rows=` value | RED |
| 4 | The printer prints the temp path or a reader log line | RED |
| 5 | A card with per-source coverage lines, `hypotheses=none` or one coverage sentence, and no breach-field assignment, sentinel exit 0 | PASS |

## Acceptance Criteria

- [ ] The incident skill text places the three reader commands before the nineteen-field list. The order check reads `SKILL.md`. It does not expect `dry-run.sh` to contain those commands. The test does not call Doppler.
- [ ] `--dry-run` and `--headless` print `SOLEUR_INCIDENT_PULL` with `verdict=never-ran` for each source and do not invoke Doppler or the readers.
- [ ] With no Sentry issue id, the card contains `sentry: not-queried reason=no-issue-id` and `scripts/sentry-issue.sh` is not executed.
- [ ] Better Stack exit 3 is `verdict=never-ran`. Supabase exit 3 keeps the script's data `verdict=` and `reason=`. A Better Stack empty body with exit 0 is `exit=0` and `stdout-empty`, not a claim that the table or the archive had no rows, and not health.
- [ ] The shown card has no reader stdout, no reader stderr, no `rows=` value, and no assignment of `affected_user_count`, `data_categories_breached`, `risk_to_subjects`, `revenue_impact`, or `detected_at` from the pull. It does not print a pull time.
- [ ] Sentinel exit 1 on the pull card emits `SOLEUR_INCIDENT_PULL` with `reason=card-redaction-failed`, prints no offset line and no temp path, does not print `SOLEUR_INCIDENT_HALT`, and still starts the nineteen-field interview. Phase 6's iterate-until-clean path is unchanged. Sentinel exit 2 prints `SOLEUR_INCIDENT_HALT` and shows nothing. A zero-byte card emits `reason=card-empty`, shows nothing, does not print `SOLEUR_INCIDENT_HALT`, and still starts the interview. Three source lines and `hypotheses=none` are shown.
- [ ] `SOLEUR_INCIDENT_PULL\b` is an alternation in `MARKER_RE` and nothing narrower. `extractGitLockMarkers` matches the sample `SOLEUR_INCIDENT_PULL file=.git/config.lock type=chardevice rdev=1:3`. The marker is not in `WEDGE_RE`. The comment names the `PostToolUse(Bash)` hook as the extractor. `dry-run.sh` emits `echo "SOLEUR_INCIDENT_PULL` or `printf 'SOLEUR_INCIDENT_PULL` with no leading indent.
- [ ] Confirming the card copies its one coverage sentence into the root-cause field. `hypotheses=none` copies nothing. Confirming does not satisfy `ACK-ART33`, `ACK-ART34`, or `COMMIT-PIR`, and it does not set `detected_at`, `detection_method`, `monitoring_detected_at`, or any breach field. The card does not offer a pull time for `monitoring_detected_at`.
- [ ] An omitted window records Better Stack `--since 1h` and Supabase `--since 24h`. A supplied window is one quoted word and the only `--since` for those two scripts. A window outside the skill-side allowlist does not exec, and the marker is `verdict=never-ran` with `reason=usage`. The Sentry line says `window=n/a`. An issue id outside `^[A-Za-z0-9_-]+$` is not executed.
- [ ] Each source gets a line. One source failing does not skip the others or the nineteen-field interview. Better Stack exit 2 and exit 78 are `verdict=unverified` with `reason=credential-refused`, and stderr is not shown. Sentry exit 77 is `verdict=unverified` with `reason=401`. Supabase exit 1 is `verdict=unverified`, copies the script's `verdict=` and `reason=` once, and is not retried. Any reader exit this plan does not name is `verdict=unverified` with `reason=reader-exit-N`. A Doppler wrapper failure, including `prd` unreadable while `prd_terraform` works, is `verdict=never-ran` with `reason=wrapper` for each source that did not run. The skill does not start `doppler login`.
- [ ] The card quotes no raw log line. A hypothesis uses only coverage fields, or the card says `hypotheses=none`. A fixture that places a UUID, an IPv4 address, and an email inside `event_message` and `message` still produces printer stdout with none of those literals. The Better Stack line names the table, `limit=100`, and `truncated=true` only when the `"raw"` line count is 100. Empty Better Stack stdout is not written as disproof of the complaint. `reason=ZERO_SOURCE_COVERAGE_UNESTABLISHED` is not written as disproof. The card has no `rows=` value.
- [ ] The card is not written under `post-mortems/`. The coverage sentence is the only pull text copied into the report, and only into the root-cause field, and only after the founder confirms the card. The 5-whys and the Art. 33 tokens stay founder-written.
- [ ] Pull temps are created outside the repository root, mode `0600`, and removed on EXIT, INT, TERM, and HUP. The test asserts the path is outside that root and is gone after the trap. No log-derived text is emitted before sentinel exit 0.
- [ ] The complaint is sentinel-scanned before it is printed or copied onto the card, and it is never passed as `--grep`. A match omits that sentence, prints no offset line, still shows the rest of the card, and starts the interview.
- [ ] `--headless` without a fixture is skill prose. It prints the three `never-ran` lines and then exits non-zero on the first blocking prompt. It writes no post-mortem. The test does not claim `dry-run.sh` implements headless. `--dry-run` fills fields only from the fixture.
- [ ] `pull-card.test.sh` passes under `scripts/test-all.sh` with synthesized fixtures and without Doppler.
- [ ] The incident skill still contains the deployed-root sentinel anchor exactly once.
- [ ] This change does not edit the privacy policy, the GDPR policy, or the data-protection disclosure, and it does not state that a Better Stack Article 28 instrument exists.

## Test Scenarios

- unit: Given `dry-run.sh` and `test/fixtures/dry-run-incident.json`, when the harness runs, then three `verdict=never-ran` lines appear before the Phase 0 facts marker and the script text contains no reader invocation.
- unit: Given `pull-card-synthetic.json` with a Better Stack empty body (exit 0) and a Supabase `verdict=COVERED` line, when the card is built, then the Better Stack line names `t520508_soleur_inngest_vector_prd_3_logs` and does not say the incident is absent.
- unit: Given a synthesized secret inside a log line, when `pull-card.sh` runs, then that secret is absent from the printer stdout because the printer does not emit the line.
- unit: Given a fixture whose body matches a sentinel pattern, when the sentinel exits 1, then the harness output does not contain the card.
- unit: Given a fixture row count of 4, when the card is shown, then `affected_user_count` is not set to 4.
- unit: Given an omitted window, when the commands are assembled, then Better Stack receives `--since 1h` and Supabase receives `--since 24h`.
- unit: Given a window outside the skill-side allowlist, when the pull starts, then that reader is not executed and the marker is `verdict=never-ran` with `reason=usage`.
- unit: Given fixture stdout that contains a UUID, an IPv4 address, and an email, when the card is shown, then none of those literals appear.
- unit: Given no complaint and no rows, when the card is built, then it contains `hypotheses=none` and is shown.
- unit: Given a complaint sentence, when the pull argv is assembled, then it does not contain `--grep`.

## Success Metrics

The founder sees a coverage card before answering the nineteen fields. A test fails if the printer prints a raw stream, a `rows=` value, or a breach field taken from a line count.

## Dependencies & Risks

- Doppler `prd` and `prd_terraform` are read at incident time. Tests do not call them. A missing config is `never-ran` with `reason=wrapper`, not a cause.
- Test 18a fails if the skill gains a second copy of the deployed-root sentinel anchor.
- #7529 stays open. This plan does not close it.

## References & Research

- Brainstorm: `knowledge-base/project/brainstorms/2026-11-05-incident-investigate-entry-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-incident-investigate-entry/spec.md`
- Draft PR: #12143
- DPA tracker: #7529
- Incident skill issue that shipped the sentinel: #2725
