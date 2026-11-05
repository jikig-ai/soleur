---
name: incident
description: "This skill should be used when scaffolding a redaction-gated post-incident report (PIR) after a production incident."
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
  - Grep
  - Glob
preconditions:
  - The operator (or an upstream skill) has observed a live or recently-resolved production incident.
  - Worktree is on a feature branch — never run on main/master.
---

<!-- soleur-cloud-mode:start -->
**Cloud Mode (Devin):** before pipeline work run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"`. If `CLAUDE_PLUGIN_ROOT` is unset (cloud exec shells do not export it), resolve the root by IDENTITY, never by script basename: for `d` in `"$HOME/.local/share/devin/cli/plugins/cache"` and `/opt/.devin/plugins`, skip unless `[ -d "$d" ]`, then `MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"`, `ROOT="${MANIFEST%/.claude-plugin/plugin.json}"` — one resolution, two consumers: `$ROOT/scripts/cloud-detect.sh` and `$ROOT/scripts/precommit-guard.sh`. (Shape check, not authentication: a planted `{"name":"soleur"}` dir passes — ADR-179 A11.) `local` or `not-local:no-devin-env` proceeds normally; any other `not-local:<reason>` applies `<plugin-root>/devin/INSTRUCTIONS.md` §Cloud Mode: emit the `--banner`, fan out sequentially with `Reviewed-Coverage: sequential-fallback` disclosure (never claim an independent review ran), `message_user` ack before any secrets read or production mutation, and run `precommit-guard.sh` before any `git commit` — hooks do not fire in cloud.
<!-- soleur-cloud-mode:end -->

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# incident Skill

**Inspiration:** see `NOTICE` (MIT — alirezarezvani/claude-skills, clean-room).

**Purpose:** classify an incident's `brand_survival_threshold` in <60s, gate PIR drafting behind a GDPR Art. 33/34 notification-trigger evaluation, and scaffold a redaction-gated internal PIR matching the shape of `knowledge-base/engineering/operations/post-mortems/dashboard-error-postmortem.md`.

**Directory convention:** PIRs (incident records) live under `knowledge-base/engineering/operations/post-mortems/`. Procedural runbooks (recovery procedures, rotation playbooks, audit checklists) live under `knowledge-base/engineering/operations/runbooks/`. The split is semantic: runbooks have `triggers:` frontmatter and are scanned by Phase 3 for routing; PIRs do not and are not scanned.

**Operator-invoked only.** No Sentry/cron auto-fire substrate. Pre-write redaction sentinel ([scripts/redact-sentinel.sh](./scripts/redact-sentinel.sh)) is load-bearing — it runs BEFORE the draft is emitted inline to the conversation transcript AND before any file is written to disk. Transcripts ARE write boundaries; sentinel must precede inline-emit, not just file-commit.

All prod-touching steps are advisory + ack-gated per `hr-menu-option-ack-not-prod-write-auth`. The commit gate accepts a single literal token (`COMMIT-PIR`); LLM fuzzy-interpretation of "ok looks good" must never write a PIR.

<!-- operator-typed-render:start -->
**Any message this skill PRINTS that tells the operator to run a skill or command renders at emit time.** The doc names it canonically (`soleur:<name>`, ADR-226); before printing, render it as the active harness's **operator-typed form** per `formatSkillInvocation` (`plugins/soleur/lib/harness.ts`), which owns the per-harness slash and sigil forms — the operator types that string into a fresh session where no routing contract is in context, so a bare canonical name is model-discretion there rather than a dispatch. This covers abort messages, `AskUserQuestion` prompts and options, `Display`/`echo` lines and resume prompts alike; an agent-read instruction stays canonical.
<!-- operator-typed-render:end -->

## Headless / Dry-run modes

- `--headless`: do not perform a live pull. Print three `SOLEUR_INCIDENT_PULL` lines with `verdict=never-ran` and no log body, then suppress interactive prompts. On any blocking ack, exit non-zero with a structured error message instead of waiting. Write no post-mortem. Phase 8 still requires `status: resolved`.
- `--dry-run <fixture.json>`: do not perform a live pull. [scripts/dry-run.sh](./scripts/dry-run.sh) prints three `SOLEUR_INCIDENT_PULL` lines with `verdict=never-ran` and fills fields only from the fixture. It does not implement `--headless`. Dry-run never writes to `post-mortems/` and never invokes `compound-capture`; it emits the would-be PIR to stdout.

## Phase 0 — Capture facts

Skip the fence below on `--dry-run` and `--headless`. Those modes print three `SOLEUR_INCIDENT_PULL` lines with `verdict=never-ran` and no log body, and they do not call Doppler or the readers. `--dry-run` fills the nineteen fields only from the fixture.

On a live run, the founder may supply an optional window, an optional Sentry issue id, and an optional complaint sentence. The complaint is a claim. It is never passed as `--grep`. Scan it with the sentinel the Phase 6 fence assigns to `SENTINEL` before it is printed or copied onto the card. Copy that one assignment into this shell. Do not add a second copy of the path to this file. If the complaint matches, omit that sentence, print no offset line, still show the rest of the card, and start the nineteen-field interview. A match is not Phase 6's iterate-until-clean loop.

Skill-side window allowlist. A supplied window is one quoted word and the only `--since` for Better Stack and Supabase. Better Stack accepts `^[0-9]+[hmd]$`, `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`, or `^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$` (the space form only as that one quoted word). Supabase accepts `^[0-9]+[mhd]$` or `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`. A refused window does not exec: that source is `verdict=never-ran` `reason=usage`. When the window is omitted, Better Stack runs `doppler run -p soleur -c prd_terraform -- env -u BS_TABLE -u BS_TABLE_S3 scripts/betterstack-query.sh --table t520508_soleur_inngest_vector_prd_3_logs --since 1h`. The fence passes that same `--table` literal and unsets `BS_TABLE` and `BS_TABLE_S3`, so an inherited table cannot change the query while the card still names this one. Supabase runs `doppler run -p soleur -c prd -- scripts/supabase-logs-query.sh --ref ifsccnjhymdmidffkzhl --since 24h`. Sentry has no `--since`. Its card line says `window=n/a`.

An issue id must match `^[A-Za-z0-9_-]+$`. An id outside that grammar, or an id that starts with `-`, is not executed (`verdict=never-ran` `reason=usage`). The refused id is not printed. With no issue id, the card contains `sentry: not-queried reason=no-issue-id` and `doppler run -p soleur -c prd -- scripts/sentry-issue.sh` is not executed. Do not pass `--redact`, `--host-events`, or `--liveness`.

The `prd_terraform` Doppler config is the wrong config for Sentry and for Supabase.

The application ref `ifsccnjhymdmidffkzhl` is always the Supabase command. A second Supabase command, with the same `--since` and `-c prd`, runs only when the founder gives the project name `soleur-inngest-prd` or the ref `pigsfuxruiopinouvjwy`: `doppler run -p soleur -c prd -- scripts/supabase-logs-query.sh --ref pigsfuxruiopinouvjwy --since <the same window>`. The word inngest alone does not add this second command. Do not replace the application query. The application card line that ran carries `ref=ifsccnjhymdmidffkzhl`. A `reason=usage` line and a Doppler `reason=wrapper` line do not carry `ref=`. When the second command runs, its result is a separate card line carrying `ref=pigsfuxruiopinouvjwy`, and the marker stays the application exit. Otherwise the application line says the other ref was not queried.

Better Stack names table `t520508_soleur_inngest_vector_prd_3_logs` and `limit=100`. Do not decode `.raw`. Do not pass `--no-archive`. Exit 3 is `verdict=never-ran`. Exit 2 and exit 78 are `verdict=unverified` `reason=credential-refused`. Do not print stderr. Exit 0 with an empty body is `exit=0` and `stdout-empty`. That does not say the table or the archive had no rows. It is not health and it is not disproof of the complaint. Exit 0 with a body counts lines containing `"raw"`, and `truncated=true` only when that count is 100. Any other Better Stack exit is `verdict=unverified` `reason=reader-exit-N`, and the body is not rows.

Supabase copies the stdout `verdict=` and `reason=` pair and does not copy `rows=`. Do not count stdout log lines. Exit 0 is marker `verdict=queried` together with that reason. Exit 1 is marker `verdict=unverified`, the script's pair is copied once, and this skill does not run the command again. Exit 2 is `verdict=unverified` with the script's `reason=`. Exit 3 keeps the script's data verdict on the card and the marker `verdict=queried`. `reason=ZERO_SOURCE_COVERAGE_UNESTABLISHED` is not disproof of the complaint.

Sentry exit 77 is `verdict=unverified` `reason=401`. Exit 78 is `verdict=unverified` `reason=credential-refused`. Exit 1 is `verdict=unverified` `reason=reader-exit-1`. No retry, the body is not shown, and the skill does not halt. Any reader exit this section does not name is `verdict=unverified` `reason=reader-exit-N`.

Each source gets a line. One failure does not skip the others or the nineteen-field interview. If the `doppler` binary is missing, Better Stack and Supabase are `verdict=never-ran` `reason=wrapper`. Sentry is `reason=wrapper` only when an issue id was going to be executed. With no issue id, Sentry stays `not-queried` `reason=no-issue-id`. An id outside the grammar stays `reason=usage`. If `prd` cannot be read and `prd_terraform` can, Better Stack still runs and Sentry and Supabase are `verdict=never-ran` `reason=wrapper`. Do not parse wrapper stdout as rows. Do not start `doppler login`. Do not run `scripts/ensure-doppler.sh`. Do not re-exec. A Better Stack or Supabase line that ran, or that the Doppler wrapper skipped, appends `window=` of the allowlisted value or the default. A `reason=usage` line does not print the refused window.

Print one stdout marker per source, with no log body: `SOLEUR_INCIDENT_PULL source=<betterstack|sentry|supabase> verdict=<queried|not-queried|unverified|never-ran>`. A `reason=` suffix is allowed. The verdict set does not grow.

The card is those coverage lines plus at most one hypothesis sentence assembled only from coverage fields (source, window, table or ref, exit, the Better Stack line count, truncated, and the Supabase `verdict=` and `reason=`). It does not rank causes, name a service, an error, or a user count, or say the complaint is false, or say what would disprove the complaint. If nothing can be said that way, the card says `hypotheses=none`. Three source lines and `hypotheses=none` are shown. The card does not assign `affected_user_count`, `data_categories_breached`, `risk_to_subjects`, `revenue_impact`, `detected_at`, `detection_method`, or `monitoring_detected_at`. Do not infer a user count from a line count, and do not print a pull time or offer one for `monitoring_detected_at`. The pull does not feed the `mttd-transposed` halt.

The card is not written under `post-mortems/`. When the founder confirms the card, copy its one coverage sentence into the root-cause field. `hypotheses=none` copies nothing. Do not copy into the 5-whys, the breach fields, or the Art. 33 tokens. Confirming the card is not `ACK-ART33`, not `ACK-ART34`, and not `COMMIT-PIR`.

Run this fence from the worktree root that contains `scripts/`, as one shell. Create each stdout temp with `mktemp -p /tmp` outside the repository, mode `0600`. The `EXIT` trap removes the temps and does not exit. `INT`, `TERM`, and `HUP` remove the temps and exit 130, 143, and 129, so a stopped pull does not start the remaining readers. `EXIT INT TERM HUP` is the set that deletes the temps. If a temp path is inside the worktree, halt with `SOLEUR_INCIDENT_HALT reason=temp-inside-worktree` and do not start a reader. Redirect stdout on the reader command and discard stderr. Do not print the temp path on the pass path or the fail path. Do not `Read` or `cat` the temp. `pull-card.sh` is the only reader of that temp. Show the card only when the sentinel exits 0. A zero-byte card emits `SOLEUR_INCIDENT_PULL` with `reason=card-empty`, shows nothing, does not print `SOLEUR_INCIDENT_HALT`, and starts the nineteen-field interview. Sentinel exit 1 on the card emits `SOLEUR_INCIDENT_PULL` with `reason=card-redaction-failed`, prints no offset line, does not print the temp path, does not print `SOLEUR_INCIDENT_HALT`, does not enter Phase 6's iterate-until-clean loop, and still starts the interview. Phase 6's loop is unchanged. Exit 2 prints `SOLEUR_INCIDENT_HALT` and shows nothing.

```bash
# Paste the Phase 6 SENTINEL assignment above the readability check before running this fence.
# Each fence is its own shell, so the later assignment does not survive. Do not add a second copy of the sentinel path to this file.
set +e
set -u
if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  echo "SOLEUR_INCIDENT_HALT reason=plugin-root-unverified"
  exit 2
fi
bs_out="$(mktemp -p /tmp)"
sb_out="$(mktemp -p /tmp)"
sb2_out="$(mktemp -p /tmp)"
sy_out="$(mktemp -p /tmp)"
card="$(mktemp -p /tmp)"
complaint_out="$(mktemp -p /tmp)"
chmod 0600 "$bs_out" "$sb_out" "$sb2_out" "$sy_out" "$card" "$complaint_out"
repo_phys="$(pwd -P)"
for tmp in "$bs_out" "$sb_out" "$sb2_out" "$sy_out" "$card" "$complaint_out"; do
  case "$tmp" in
    "$repo_phys"|"$repo_phys"/*)
      echo "SOLEUR_INCIDENT_HALT reason=temp-inside-worktree"
      exit 2
      ;;
  esac
done
trap 'rm -f "$bs_out" "$sb_out" "$sb2_out" "$sy_out" "$card" "$complaint_out"' EXIT
trap 'rm -f "$bs_out" "$sb_out" "$sb2_out" "$sy_out" "$card" "$complaint_out"; exit 130' INT
trap 'rm -f "$bs_out" "$sb_out" "$sb2_out" "$sy_out" "$card" "$complaint_out"; exit 143' TERM
trap 'rm -f "$bs_out" "$sb_out" "$sb2_out" "$sy_out" "$card" "$complaint_out"; exit 129' HUP
if [[ -z "${SENTINEL:-}" || ! -r "${SENTINEL}" ]]; then
  echo "SOLEUR_INCIDENT_HALT reason=sentinel-unreadable"
  exit 2
fi
window="${INCIDENT_WINDOW:-}"
issue_id="${INCIDENT_SENTRY_ISSUE_ID:-}"
sb_project="${INCIDENT_SUPABASE_PROJECT:-}"
bs_since="1h"
sb_since="24h"
bs_skip=""
sb_skip=""
if [[ -n "$window" ]]; then
  if [[ "$window" =~ ^[0-9]+[hmd]$ || "$window" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ || "$window" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    bs_since="$window"
  else
    bs_skip="usage"
  fi
  if [[ "$window" =~ ^[0-9]+[mhd]$ || "$window" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    sb_since="$window"
  else
    sb_skip="usage"
  fi
fi
tf_ok=0
prd_ok=0
if ! command -v doppler >/dev/null 2>&1; then
  tf_ok=0
  prd_ok=0
else
  doppler run -p soleur -c prd_terraform -- true >/dev/null 2>&1
  tf_rc=$?
  doppler run -p soleur -c prd -- true >/dev/null 2>&1
  prd_rc=$?
  if [[ "$tf_rc" -eq 0 ]]; then tf_ok=1; fi
  if [[ "$prd_rc" -eq 0 ]]; then prd_ok=1; fi
fi
bs_line=""
sb_line=""
sy_line=""
if [[ -n "$bs_skip" ]]; then
  echo "SOLEUR_INCIDENT_PULL source=betterstack verdict=never-ran reason=usage"
  bs_line="betterstack verdict=never-ran reason=usage"
elif [[ "$tf_ok" -ne 1 ]]; then
  echo "SOLEUR_INCIDENT_PULL source=betterstack verdict=never-ran reason=wrapper"
  bs_line="betterstack verdict=never-ran reason=wrapper window=${bs_since}"
else
  doppler run -p soleur -c prd_terraform -- env -u BS_TABLE -u BS_TABLE_S3 scripts/betterstack-query.sh --table t520508_soleur_inngest_vector_prd_3_logs --since "$bs_since" >"$bs_out" 2>/dev/null
  bs_rc=$?
  bs_line="$(bash "${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/pull-card.sh" betterstack "$bs_rc" "$bs_out")"
  bs_line="${bs_line} window=${bs_since}"
  if [[ "$bs_rc" -eq 0 ]]; then
    echo "SOLEUR_INCIDENT_PULL source=betterstack verdict=queried"
  elif [[ "$bs_rc" -eq 3 ]]; then
    echo "SOLEUR_INCIDENT_PULL source=betterstack verdict=never-ran"
  elif [[ "$bs_rc" -eq 2 || "$bs_rc" -eq 78 ]]; then
    echo "SOLEUR_INCIDENT_PULL source=betterstack verdict=unverified reason=credential-refused"
  else
    echo "SOLEUR_INCIDENT_PULL source=betterstack verdict=unverified reason=reader-exit-${bs_rc}"
  fi
fi
if [[ -n "$sb_skip" ]]; then
  echo "SOLEUR_INCIDENT_PULL source=supabase verdict=never-ran reason=usage"
  sb_line="supabase verdict=never-ran reason=usage"
elif [[ "$prd_ok" -ne 1 ]]; then
  echo "SOLEUR_INCIDENT_PULL source=supabase verdict=never-ran reason=wrapper"
  sb_line="supabase verdict=never-ran reason=wrapper window=${sb_since}"
else
  doppler run -p soleur -c prd -- scripts/supabase-logs-query.sh --ref ifsccnjhymdmidffkzhl --since "$sb_since" >"$sb_out" 2>/dev/null
  sb_rc=$?
  sb_line="$(bash "${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/pull-card.sh" supabase "$sb_rc" "$sb_out")"
  sb_reason=""
  case "$sb_line" in
    *reason=*) sb_reason="${sb_line##*reason=}" ;;
  esac
  if [[ -z "$sb_reason" ]]; then
    echo "SOLEUR_INCIDENT_PULL source=supabase verdict=unverified reason=reader-exit-${sb_rc}"
  elif [[ "$sb_rc" -eq 0 || "$sb_rc" -eq 3 ]]; then
    echo "SOLEUR_INCIDENT_PULL source=supabase verdict=queried reason=${sb_reason}"
  elif [[ "$sb_rc" -eq 1 || "$sb_rc" -eq 2 ]]; then
    echo "SOLEUR_INCIDENT_PULL source=supabase verdict=unverified reason=${sb_reason}"
  else
    echo "SOLEUR_INCIDENT_PULL source=supabase verdict=unverified reason=reader-exit-${sb_rc}"
  fi
  sb_line="${sb_line} ref=ifsccnjhymdmidffkzhl window=${sb_since}"
  if [[ "$sb_project" == "soleur-inngest-prd" || "$sb_project" == "pigsfuxruiopinouvjwy" ]]; then
    doppler run -p soleur -c prd -- scripts/supabase-logs-query.sh --ref pigsfuxruiopinouvjwy --since "$sb_since" >"$sb2_out" 2>/dev/null
    sb2_rc=$?
    sb2_line="$(bash "${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/pull-card.sh" supabase "$sb2_rc" "$sb2_out")"
    sb2_line="${sb2_line} ref=pigsfuxruiopinouvjwy window=${sb_since}"
    sb_line="${sb_line}"$'\n'"${sb2_line}"
  else
    sb_line="${sb_line} other-ref=not-queried"
  fi
fi
if [[ -z "$issue_id" ]]; then
  echo "SOLEUR_INCIDENT_PULL source=sentry verdict=not-queried reason=no-issue-id"
  sy_line="sentry: not-queried reason=no-issue-id window=n/a"
elif [[ "$issue_id" == -* || ! "$issue_id" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo "SOLEUR_INCIDENT_PULL source=sentry verdict=never-ran reason=usage"
  sy_line="sentry verdict=never-ran reason=usage window=n/a"
elif [[ "$prd_ok" -ne 1 ]]; then
  echo "SOLEUR_INCIDENT_PULL source=sentry verdict=never-ran reason=wrapper"
  sy_line="sentry verdict=never-ran reason=wrapper window=n/a"
else
  doppler run -p soleur -c prd -- scripts/sentry-issue.sh "$issue_id" >"$sy_out" 2>/dev/null
  sy_rc=$?
  sy_line="$(bash "${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/pull-card.sh" sentry "$sy_rc" "$sy_out")"
  if [[ "$sy_rc" -eq 0 ]]; then
    echo "SOLEUR_INCIDENT_PULL source=sentry verdict=queried"
    sy_line="sentry verdict=queried window=n/a"
  elif [[ "$sy_rc" -eq 77 ]]; then
    echo "SOLEUR_INCIDENT_PULL source=sentry verdict=unverified reason=401"
    sy_line="sentry verdict=unverified reason=401 window=n/a"
  elif [[ "$sy_rc" -eq 78 ]]; then
    echo "SOLEUR_INCIDENT_PULL source=sentry verdict=unverified reason=credential-refused"
    sy_line="sentry verdict=unverified reason=credential-refused window=n/a"
  else
    echo "SOLEUR_INCIDENT_PULL source=sentry verdict=unverified reason=reader-exit-${sy_rc}"
    sy_line="sentry verdict=unverified reason=reader-exit-${sy_rc} window=n/a"
  fi
fi
# An inherited xtrace would print the complaint before the sentinel scans it.
# The assignment stays below set +x. Nothing above this line expands the complaint.
set +x
complaint="${INCIDENT_COMPLAINT:-}"
complaint_keep=""
if [[ -n "$complaint" ]]; then
  printf '%s\n' "$complaint" > "$complaint_out"
  bash "$SENTINEL" "$complaint_out" >/dev/null 2>&1
  complaint_rc=$?
  if [[ "$complaint_rc" -eq 0 ]]; then
    complaint_keep="$complaint"
  elif [[ "$complaint_rc" -ne 1 ]]; then
    echo "SOLEUR_INCIDENT_HALT reason=sentinel-exit-2"
    exit 2
  fi
fi
{
  printf '%s\n' "$bs_line"
  printf '%s\n' "$sb_line"
  printf '%s\n' "$sy_line"
  if [[ -n "$complaint_keep" ]]; then
    printf 'complaint: %s\n' "$complaint_keep"
  fi
  # Before the card sentinel, replace this single hypotheses=none line only when one sentence can be built from the coverage fields above. Leave hypotheses=none otherwise.
  printf '%s\n' "hypotheses=none"
} > "$card"
if [[ ! -s "$card" ]]; then
  echo "SOLEUR_INCIDENT_PULL source=betterstack verdict=unverified reason=card-empty"
  echo "SOLEUR_INCIDENT_PULL source=sentry verdict=unverified reason=card-empty"
  echo "SOLEUR_INCIDENT_PULL source=supabase verdict=unverified reason=card-empty"
else
  bash "$SENTINEL" "$card" >/dev/null 2>&1
  sent_rc=$?
  if [[ "$sent_rc" -eq 0 ]]; then
    cat "$card"
  elif [[ "$sent_rc" -eq 1 ]]; then
    echo "SOLEUR_INCIDENT_PULL source=betterstack verdict=unverified reason=card-redaction-failed"
    echo "SOLEUR_INCIDENT_PULL source=sentry verdict=unverified reason=card-redaction-failed"
    echo "SOLEUR_INCIDENT_PULL source=supabase verdict=unverified reason=card-redaction-failed"
  else
    echo "SOLEUR_INCIDENT_HALT reason=sentinel-exit-2"
    exit 2
  fi
fi
```

> **No-SSH fact-pulling (Soleur vision — `hr-no-dashboard-eyeball-pull-data-yourself`).** The operator is non-technical: NEVER ask them to SSH, run `df -h`, or read a dashboard, and do NOT trust the report's stated *mechanism*. The pull at the start of this phase is the only live read. Do not run a second pull from this note. This includes NEVER asking the operator to paste verbatim error output, run `grep`/`stat`/`git config` probes, or eyeball logs — the operator decides, they do not retrieve. If a needed signal has no no-SSH read path, **BUILD one** — add a monitored stdout `SOLEUR_*` marker in the emitting code (or emit to a GitHub issue/DB/endpoint) so the next occurrence self-reports, rather than deferring to the operator. **Why:** #4886 — the incident report blamed ENOSPC; the real cause (a dirty-clone `.claude/settings.json` blocking `git pull`) was one Sentry-issue read away. #5934 — the worktree-wedge diagnosis twice asked the operator to paste `grep`/`stat` output that the observability layer held once instrumented (`SOLEUR_GIT_CONFIG_TARGET_MASKED`, `SOLEUR_GIT_WORKTREE_VERIFY_FAILED`). See [[2026-06-03-no-ssh-prod-signal-toolchain-never-hand-the-operator-an-ssh-task]] and [[2026-07-08-self-pull-observability-in-diagnostic-loops-never-ask-operator-to-fetch]].

<!-- -->
> **Unreachable host with no log-shipping — READ before you MUTATE (`hr-no-dashboard-eyeball-pull-data-yourself` extended to diagnosis).** When the failing surface is a host that answers nothing (no SSH, no Vector/journald shipping, no Sentry emit), the self-serve read path is the **provider API + rescue mode** — it is NOT an operator-console task. Ladder, in order: (1) **Provider API reads** — `GET /servers/{id}` (status, `private_net`), `/metrics?type=cpu,disk,network`, `/actions`. Query the **BOOT window**, not the current window: an unreachable-but-idle host reads `net=0/disk=0` and looks "dead" when it merely has no clients. (2) **Rescue-mode disk read** (Hetzner: `enable_rescue` with `{"type":"linux64","ssh_keys":[<id>]}` to inject a registered key whose private half is in your agent → key auth, no `sshpass`; scope SSH in by `set_rules` allowing ONLY your egress IP on `:22` and restore `{"rules":[]}` immediately after; `reboot` → SSH → `lsblk` (the OS disk is NOT necessarily `sda` — an attached volume can take it) → mount the boot partition → read `/var/log/cloud-init-output.log`, `grep -iE 'error|fail' /var/log/cloud-init.log`, `/var/lib/cloud/data/status.json`). (3) **Only then mutate**, and only via the sanctioned destroy-guarded dispatch (`apply-web-platform-infra.yml apply_target=…`) — **never a hand-rolled `terraform apply`**: an out-of-band apply on an unverified hypothesis diverges prod from `main` and makes the guarded recovery abort `out_of_scope=1`, blocking the real fix. Guard aborts are information — read their counters (`out_of_scope=`, `server_replaced=`, `volume_created=`) to learn which recovery path actually fits. And `Apply complete` is not proof: `GET` the resource to confirm the provider's reality. **Why:** #6400 — four hypotheses (credential → firewall → store OOM → boot) were mutated-then-tested over hours; a rescue read of `cloud-init.log` named the real cause (a transient IMDS failure left the host with no private NIC) in one shot, and a hypothesis-driven firewall apply blocked the sanctioned recreate three times. See [[2026-07-15-infra-incident-diagnose-before-mutate-and-no-out-of-band-applies]].

Collect from the operator (or from the dry-run fixture):

1. `title` — short prose, e.g. `"dashboard error boundary outage 2026-05-14"`.
2. `detected_at` — ISO-8601 UTC. The skill validates the regex `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$` before substitution (FR7 LLM-trust boundary). This is the incident START time.
3. `symptom` — operator prose, free-form.
4. `suspected_change` — `PR #N` or commit SHA. Skill validates `incident_pr` is numeric.
5. `affected_user_count` — integer estimate; 0 is valid.
6. `data_categories_breached` — array of GDPR Art. 4(1) categories (email, userId, IP, billing, content). Empty array = no personal-data breach.
7. `risk_to_subjects` — enum `none | low | medium | high`. Phase 2 reads this for Art. 34 trigger evaluation.
8. `incident_overview` — operator prose, 1-2 sentence executive summary (distinct from `symptom`, which is the full operator prose). Default `TBD`.
9. `recovery_at` — ISO-8601 UTC, OPTIONAL. The incident END time. Validated against the SAME regex as `detected_at` before substitution. Empty → status not yet resolved → MTTR rendered `TBD`.
10. `monitoring_detected_at` — ISO-8601 UTC, OPTIONAL. The moment a monitoring system first flagged the incident (used only when `detection_method == monitoring`). Same regex validation.
11. `detection_method` — enum `monitoring | external | manual`. Feeds the Detection section and the MTTD computation.
12. `triggered_by` — enum `user | system | market | provider`.
13. `participants` — operator prose (people + systems involved). Default `Operator (single founder)`.
14. `resolution` — operator prose: which actions brought resolution. Default `TBD`.
15. `version_triggered` — repo + version / PR / commit SHA that triggered the outage. Default `TBD`.
16. `version_restored` — repo + version / PR / commit SHA that restored the service. Default `N/A — not yet restored`.
17. `services_impacted` — operator prose. Default `TBD`.
18. `revenue_impact` — operator prose. Default `Unknown / N/A` (never fabricate a number).
19. `team_impact` — operator prose. Default `Unknown / N/A`.

The post-resolution review fields (`{{ROOT_CAUSE_5WHYS}}`, `{{LUCKY}}`, `{{WENT_WELL}}`, `{{WENT_WRONG}}`, `{{ACTION_ITEM_ISSUE}}`/`{{ACTION_ITEM_DESC}}`) are NOT captured at Phase 0 — they do not exist yet at incident-open time. They scaffold with a static `TBD` default and the operator fills them during the Phase 7 review. This keeps Phase 0 inside the <60s classification budget (only operator-answerable-at-open fields are prompted).

Compute locally (FR7 LLM-trust boundary — never accept these from an LLM-emitted blob):

- `slug` — `awk` kebab-case of title, dropping non-`[a-z0-9-]`.
- File path — derived from slug: `knowledge-base/engineering/operations/post-mortems/${slug}-postmortem.md`.
- `MTTR` (mean time to recovery) / `MTTD` (mean time to detect) — computed from validated timestamps, NEVER an LLM-emitted duration. The ISO regex gates FORMAT but not calendar validity (it accepts month 13 / day 40 / hour 25), so `date -u -d` can still reject a regex-passing value — capture the epoch with explicit failure handling and HALT on a bad date or a transposed (negative) pair rather than emitting a garbage/empty duration:

  ```bash
  # Returns the epoch on stdout and FAILS on a regex-valid-but-calendar-invalid date.
  # It must not print a marker and must not `exit`: every call site below is a COMMAND
  # SUBSTITUTION, so stdout is captured into an arithmetic operand and `exit` leaves only
  # the subshell. Both were measured. An earlier revision added the marker echo here and
  # thereby DESTROYED this guard: the marker text landed inside `$(( … ))`, and the run
  # either died on `SOLEUR_INCIDENT_HALT: unbound variable` (under `set -u`) or continued
  # past the check and rendered a fabricated `MTTR=0h0m` into a published post-mortem.
  # The pre-marker shape reached the transposed-date halt correctly at rc 2.
  # The halt therefore dispatches in the CALLER frame, where `exit` exits the script.
  iso_to_epoch() {
    date -u -d "$1" +%s 2>/dev/null || return 1
  }
  halt_bad_date() {
    echo "SOLEUR_INCIDENT_HALT reason=invalid-calendar-date value=[$1]"
    echo "incident: not a valid calendar date: $1" >&2
    echo "  Dates must be ISO-8601 UTC and must exist on the calendar (e.g. 2026-02-30 does not)." >&2
    echo "  Re-run soleur:incident and supply a real date; nothing has been written." >&2
    exit 2
  }
  if [[ -n "${recovery_at}" ]]; then
    r_epoch=$(iso_to_epoch "${recovery_at}") || halt_bad_date "${recovery_at}"
    d_epoch=$(iso_to_epoch "${detected_at}") || halt_bad_date "${detected_at}"
    mttr_secs=$(( r_epoch - d_epoch ))
    (( mttr_secs < 0 )) && { echo "SOLEUR_INCIDENT_HALT reason=mttr-transposed"; echo "incident: recovery_at precedes detected_at (transposed)" >&2; exit 2; }
    MTTR=$(printf '%dh%dm' $(( mttr_secs / 3600 )) $(( (mttr_secs % 3600) / 60 )))
  else
    MTTR="TBD (status not resolved)"
  fi
  if [[ "${detection_method}" == "monitoring" && -n "${monitoring_detected_at}" ]]; then
    m_epoch=$(iso_to_epoch "${monitoring_detected_at}") || halt_bad_date "${monitoring_detected_at}"
    d_epoch=$(iso_to_epoch "${detected_at}") || halt_bad_date "${detected_at}"
    mttd_secs=$(( m_epoch - d_epoch ))
    (( mttd_secs < 0 )) && { echo "SOLEUR_INCIDENT_HALT reason=mttd-transposed"; echo "incident: monitoring_detected_at precedes detected_at (transposed)" >&2; exit 2; }
    MTTD=$(printf '%dh%dm' $(( mttd_secs / 3600 )) $(( (mttd_secs % 3600) / 60 )))
  else
    MTTD="Unknown (external/manual report)"
  fi
  ```

## Phase 1 — Classification

Render the `brand_survival_threshold` decision criteria INLINE before asking for confirmation.
Criteria text (3 tiers, paraphrased from `hr-weigh-every-decision-against-target-user-impact`):

<!-- eval-gate:block:incident-threshold:start -->
- **none** — no user-facing artifact, no credential surface, no billing path; internal tooling / docs / CI.
- **single-user incident** — at least one real user impacted (data loss, trust breach, credential exposure, billing surprise) OR any sensitive-data surface is at risk.
- **aggregate pattern** — repeated or systemic impact across multiple users or tenants; brand-survival-level severity.
<!-- eval-gate:block:incident-threshold:end -->

Compute an advisory recommendation from `affected_user_count` + `risk_to_subjects` + `data_categories_breached`. Print:

```
brand_survival_threshold (advisory): single-user incident
  reason: affected_user_count=1, risk_to_subjects=high, data_categories_breached=[email, userId]
```

Then prompt: `Confirm advisory, or type override value: [none | single-user incident | aggregate pattern]`. If the operator overrides, write `classification_override: {advisory: <X>, chosen: <Y>, reason: <text>}` into PIR frontmatter (becomes `{{CLASSIFICATION_OVERRIDE_BLOCK}}`).

## Phase 2 — GDPR Art. 33 / 34 gate (BLOCKING)

Compute three values:

- `art_33_triggered` — true if `data_categories_breached` is non-empty AND `risk_to_subjects != none`. (Art. 33 covers any personal-data breach.)
- `art_34_triggered` — true if `risk_to_subjects == high`. (Art. 34 covers high-risk breaches requiring direct subject notification.)
- `art_33_deadline` — `date -u -d "${detected_at} +72 hours" +%Y-%m-%dT%H:%M:%SZ`. CNIL hard 72h deadline.

**Where an Art. 33 determination is RECORDED (ADR-200).** When `art_33_triggered` is true, the
PIR is the per-incident documentation Art. 33(5) requires, and it also needs a row in the
**Art. 33(5) breach register** at `knowledge-base/legal/breach-register.md` — an index with
stable canonical pointers, not a transcription, so add a summary row pointing at the PIR and copy
nothing out of it. Columns and the inclusion predicate are fixed by
[ADR-200](../../../../knowledge-base/engineering/architecture/decisions/ADR-200-art-33-5-documentation-is-a-distinct-register-discharged-by-an-index.md);
record Art. 33 and Art. 34 as **separate** columns, and where this PIR makes a finding on one and
is silent on the other, record the silence rather than inferring it.

**Do NOT add a row when `art_33_triggered` is false.** That is a *screening output*, not a
determination, and the register's predicate excludes it expressly: 104 post-mortems generated
from `templates/pir.md` carry the field, and indexing them would bury the determinations under
routine negatives. The row belongs to the CLO, who adds it in the same PR that lands the PIR;
[lint-legal-registers.sh](../../../../scripts/lint-legal-registers.sh) asserts nothing determination-shaped is dropped silently.

**Block Phase 3+ if EITHER trigger fires.** If only Art. 33 fires, prompt one ack:

```
Art. 33 triggered. CNIL notification deadline: <art_33_deadline>.
Confirm notification path acknowledged (type ACK-ART33 to proceed).
```

If Art. 34 ALSO fires, prompt a SECOND ack on a separate line:

```
Art. 34 triggered (risk_to_subjects=high). Direct subject notification "without undue delay" — no fixed numeric deadline.
Confirm subject-notification path acknowledged (type ACK-ART34 to proceed).
```

Operator must type each token exactly. Free-form yes is rejected. Both acks required when both fire (parity per SpecFlow Important #4 — Art. 34 is higher severity than Art. 33).

## Phase 3 — Runbook routing

`awk`-scan every `*.md` under `knowledge-base/engineering/operations/runbooks/` for a `triggers:` frontmatter block. Build a `{slug: [trigger, ...]}` map. Compute a literal-substring similarity score between operator `symptom` tokens and each runbook's `triggers[]`. Surface the top-3 matches with score and prompt:

```
Runbook matches:
  1. <slug-a>  score=4  (matched: "module-load throw", "dashboard error boundary")
  2. <slug-b>  score=2  (matched: "supabase claim")
  3. <slug-c>  score=1  (matched: "canary swap")
Select 0-N (comma-separated indices, or 'none' to proceed ad-hoc):
```

If 0 runbooks have a `triggers:` frontmatter block, surface `no runbook matches — proceed to ad-hoc response` and fall through to Phase 4 with `triggers[]` empty.

Selected runbook slugs auto-populate Phase 4 `triggers[]` verbatim (SpecFlow Important #5 — no re-typing).

## Phase 4 — Internal PIR scaffold (template substitution)

`sed`-substitute against `templates/pir.md`. Substitutions:

| Token | Source |
|---|---|
| `{{TITLE}}` | Phase 0 `title` |
| `{{DATE}}` | `date -u +%Y-%m-%d` |
| `{{INCIDENT_PR}}` | Phase 0 `suspected_change` (numeric-validated) |
| `{{INCIDENT_WINDOW}}` | `${detected_at} → ${recovery_at:-TBD}` (operator fills recovery time in Phase 7 review when empty) |
| `{{RECOVERY_AT}}` | Phase 0 `recovery_at` (ISO-8601 validated; default `TBD`) |
| `{{SUSPECTED_CHANGE}}` | Phase 0 `suspected_change` prose |
| `{{BRAND_SURVIVAL_THRESHOLD}}` | Phase 1 confirmed value |
| `{{STATUS}}` | Literal `open` (terminal value is `resolved` — set by operator in Phase 7 review before Phase 8). The Status prose section reads the same value — single source of truth. |
| `{{TRIGGERS_LIST}}` | Phase 3 selected runbook slugs as YAML list items |
| `{{ART_33_TRIGGERED}}` | Phase 2 |
| `{{ART_34_TRIGGERED}}` | Phase 2 |
| `{{ART_33_DEADLINE}}` | Phase 2 |
| `{{CLASSIFICATION_OVERRIDE_BLOCK}}` | Phase 1 (empty if no override) |
| `{{SECRET_LEAK_PREAMBLE}}` | See below |
| `{{INCIDENT_OVERVIEW}}` | Phase 0 `incident_overview` (operator prose; sentinel-scanned + sed-escaped) |
| `{{SYMPTOM}}` | Phase 0 `symptom` |
| `{{DETECTED_AT}}` | Phase 0 `detected_at` (incident start) |
| `{{MTTR}}` | Computed locally from `recovery_at − detected_at` (Phase 0 compute block); `TBD (status not resolved)` when `recovery_at` empty |
| `{{PARTICIPANTS}}` | Phase 0 `participants` (default `Operator (single founder)`) |
| `{{DETECTION_METHOD}}` | Phase 0 `detection_method` enum: `monitoring \| external \| manual` |
| `{{MTTD}}` | Computed locally; `Unknown (external/manual report)` when not monitoring-detected |
| `{{TRIGGERED_BY}}` | Phase 0 `triggered_by` enum: `user \| system \| market \| provider` |
| `{{ROOT_CAUSE_HYPOTHESIS}}` | The one coverage sentence copied when the founder confirms the pull card. `hypotheses=none` leaves `TBD` for the Phase 7 review. The 5-whys stay founder-written. |
| `{{RESOLUTION}}` | Phase 0 `resolution` (operator prose; default `TBD`) |
| `{{ROOT_CAUSE_5WHYS}}` | Phase 7 review (operator fills; default `TBD`) |
| `{{VERSION_TRIGGERED}}` | Phase 0 `version_triggered` (repo + version/PR/SHA; default `TBD`) |
| `{{VERSION_RESTORED}}` | Phase 0 `version_restored` (default `N/A — not yet restored`) |
| `{{SERVICES_IMPACTED}}` | Phase 0 `services_impacted` (default `TBD`) |
| `{{REVENUE_IMPACT}}` | Phase 0 `revenue_impact` (default `Unknown / N/A`) |
| `{{TEAM_IMPACT}}` | Phase 0 `team_impact` (default `Unknown / N/A`) |
| `{{LUCKY}}` | Phase 7 review (default `TBD`) |
| `{{WENT_WELL}}` | Phase 7 review (default `TBD`) |
| `{{WENT_WRONG}}` | Phase 7 review (default `TBD`) |
| `{{ACTION_ITEM_ISSUE}}` / `{{ACTION_ITEM_DESC}}` | Phase 7 review — the merged **Action Items & Follow-ups** table. **Every row REQUIRES a filed GitHub issue number:** run `gh issue create` (cross-referencing the source PR in the body) FIRST, then fill `#<n>` + description. No bare bullets, no `TBD`. If there are genuinely zero follow-ups, replace the table with the single permitted sentence `No action items — incident fully resolved in the source PR with no residual work.`. The `soleur:ship` Incident-PIR gate blocks merge on any item lacking a `#NNNN`; self-check before ship with `bash "${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/ship-pir-action-items-gate.sh" <pir-path>` (exit 0 = shape accepted). |

**Secret-leak preamble** (TR2): if `triggers[]` contains any of `api_key_leaked`, `credentials_exposed`, `token_exposed`, `secret_in_logs`, replace `{{SECRET_LEAK_PREAMBLE}}` with:

```
## Step 0: REVOKE FIRST

Before any forensic work, revoke the leaked credential at the issuer:
- Stripe: dashboard → API keys → roll
- Supabase: dashboard → API → reset
- Doppler: rotate via `doppler secrets rotate`
- GitHub: Settings → Tokens → revoke
- Anthropic / OpenAI / Vercel / Cloudflare: equivalent dashboard rotation

Per learning `2026-02-10-api-key-leaked-in-git-history-cleanup.md` — git history rewrite is NOT enough; the credential must be invalidated upstream.
```

Otherwise replace with empty string.

## Phase 5 — Public summary (deferred)

Emit one inline note and continue:

```
Public-safe PIR summary deferred to #3732 (opens after first real customer-impact incident).
```

No public artifact is generated in MVP. Re-evaluation criteria are tracked in #3732.

## Phase 6 — Redaction sentinel (BLOCKING, pre-inline-emit)

Resolve the gate from the **deployed plugin root** (`${CLAUDE_PLUGIN_ROOT}`, the platform-trusted copy — ADR-179's canonical bare anchor, with no fallback arm), verify the root is really a Soleur install, fail closed if either check fails, then run it against the unwritten draft. On the Concierge server the deployed-root anchor is load-bearing: a bare CWD-relative path would resolve the connected repo's **untrusted** copy of the sentinel (ADR-093). The default arm was **removed, not re-pointed**: `review/SKILL.md` instructs `gh pr checkout`, after which the git worktree is the *reviewed party's* tree, so that arm resolved this gate's own scanner from a file a hostile PR controls (#7450). The draft lives in `mktemp` only — it has NOT been emitted inline yet AND has not been written to `post-mortems/`.

**Allocate the draft, register the trap, run the gate — all in ONE fence.** That is not
formatting: each fenced block is a SEPARATE Bash call, so a trap registered in its own block
fires when *that* block exits, deleting the draft immediately and leaving `$DRAFT` empty for
every block after it. Splitting them is what review-finding C14 asked for and it does not
work — the first attempt shipped exactly that shape, and all three of its stated guarantees
were false: the trap did not cover the halts below, `$DRAFT` was empty by the time the gate
ran, and the gate scanned a literal `<draft-tmpfile>` placeholder rather than the draft.

This matters because the abandoned file is the UN-REDACTED text, which is precisely what this
gate exists to stop escaping — a leak with a longer lifetime than the session.

The two checks below have **different** jobs, and conflating them overstates the second.

The **bare anchor is the load-bearing control.** The loader substitutes `${CLAUDE_PLUGIN_ROOT}` with the installed root at delivery, *before* this text reaches bash — so at this site there is no shell variable for an ambient `direnv` / `.bashrc` / `postinstall` value to poison. Measured directly, with a decoy value simultaneously live in the executing subprocess and ignored: [`phase-1-measurement.md`](../../../../knowledge-base/project/specs/archive/20261013-051752-feat-one-shot-7450-git-root-anchor-untrusted/phase-1-measurement.md) Arm 4.

The **identity preflight is defence-in-depth** — for surfaces where substitution does *not* govern and the environment does. It is a *shape* check: it cannot distinguish an installed plugin from a checkout carrying the same manifest, and ADR-179 §(a) measured a shape check passing while an attacker-chosen payload executed. It is retained because it is the only control on an unsubstituted surface; it is not what makes the bare anchor safe. The stronger "assert the root is outside the working tree" form was evaluated and **rejected** — it guards an operand the adversary cannot reach here, breaks dogfooding on any plain clone, and reintroduces `git rev-parse` into the very gate this PR de-git-roots: [`b1-disposition.md`](../../../../knowledge-base/project/specs/archive/20261013-051752-feat-one-shot-7450-git-root-anchor-untrusted/b1-disposition.md).

Each halt emits a `SOLEUR_*` marker on stdout so a refusal is visible in telemetry rather than only to whoever was watching the terminal (`hr-observability-as-plan-quality-gate`; same pattern as `go.md`'s `SOLEUR_GIT_REPO_DIAG`). The operator guidance is **state-discriminating**: an empty root and a wrong root need different actions, and "re-run this skill" is not an action for either.

```bash
DRAFT="$(mktemp -p "$(mktemp -d -t soleur-run.$$.XXXXXXXX)")" || { echo "SOLEUR_INCIDENT_HALT reason=draft-alloc-failed"
                       echo "incident: cannot allocate a draft file — stopping before any post-mortem text exists." >&2
                       exit 2; }
trap 'rm -f "$DRAFT"; rmdir "$(dirname "$DRAFT")" 2>/dev/null' EXIT INT TERM HUP

# Write the drafted post-mortem into "$DRAFT" here — in THIS fence, before the gate below.
# Use a QUOTED heredoc delimiter (`<<'PIR_EOF'`), which is load-bearing twice over: production
# log excerpts routinely contain `$(…)`, backticks and `$VAR`, and an unquoted delimiter would
# (a) EXECUTE the command substitutions on the operator's machine, and (b) expand `$VAR`
# fragments to empty — mutating the very text the sentinel is about to scan, so a secret whose
# shape the redactor matches can be destroyed by the shell instead of by the redactor.
#   cat > "$DRAFT" <<'PIR_EOF'
#   <the drafted post-mortem, verbatim>
#   PIR_EOF

[ -f "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" ] \
  && grep -q '"name"[[:space:]]*:[[:space:]]*"soleur"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" \
  || { echo "SOLEUR_INCIDENT_HALT reason=plugin-root-unverified root=[${CLAUDE_PLUGIN_ROOT}]"
       echo "incident: cannot verify the Soleur plugin installation — stopping before any post-mortem is written." >&2
       echo "  Resolved plugin root: [${CLAUDE_PLUGIN_ROOT}]" >&2
       echo "  If that is EMPTY: no Soleur plugin is loaded in this session. Install it and start a NEW session — re-running here resolves the same empty root." >&2
       echo "  If it names a path: that path is not a Soleur install (a repo checkout is not an install). Run 'claude plugin update soleur@soleur-marketplace' (or the id 'claude plugin list' prints, if you added the repository directly), then RESTART Claude Code — plugin changes apply only on restart. If you installed with --scope project or --scope local, pass the same scope. Reinstall only if that does not clear it." >&2
       echo "  Do NOT write this post-mortem by hand — the redaction scanner is what makes it safe to publish." >&2
       exit 2; }
SENTINEL="${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-sentinel.sh"
[[ -r "$SENTINEL" ]] || { echo "SOLEUR_INCIDENT_HALT reason=sentinel-unreadable sentinel=[$SENTINEL]"
       echo "incident: the redaction sentinel is missing from an otherwise valid Soleur install — stopping." >&2
       echo "  Expected at: [$SENTINEL]" >&2
       echo "  The install is partial or out of date. Run 'claude plugin update soleur@soleur-marketplace' (or the id 'claude plugin list' prints, if you added the repository directly), then RESTART Claude Code — plugin changes apply only on restart. If you installed with --scope project or --scope local, pass the same scope. Reinstall only if that does not clear it." >&2
       echo "  Do NOT write this post-mortem by hand — the redaction scanner is what makes it safe to publish." >&2
       exit 2; }
# EMPTINESS IS A FAILURE, NOT A CLEAN SCAN. The sentinel exits 0 on a zero-byte file, so if the
# draft was never written into "$DRAFT" (composed in the conversation and written by a LATER tool
# call, which is the natural agent behaviour) the gate passes vacuously and Phase 7 emits the
# un-redacted text inline. That is a fail-OPEN, and strictly worse than the loudly-broken
# `<draft-tmpfile>` placeholder it replaced. `linear-fetch` already pins the identical
# precondition on its own artifact (`[ -n "$PERSIST_SAFE" ]`); this is that guard's sibling.
[ -s "$DRAFT" ] || { echo "SOLEUR_INCIDENT_HALT reason=draft-empty draft=[$DRAFT]"
       echo "incident: the draft file is empty — nothing was scanned, so nothing is safe to publish." >&2
       echo "  Write the post-mortem into \"\$DRAFT\" in the SAME fence as this gate, then re-run." >&2
       echo "  An empty file is a failure, not a clean scan: the sentinel exits 0 on zero bytes." >&2
       exit 2; }
bash "$SENTINEL" "$DRAFT"
```

Every halt above sits inside this same shell, so the `EXIT` trap removes the un-redacted draft
whether the gate passes, refuses, or the shell dies.

`redact-sentinel.sh` is a thin shim over the hardened `redact-engine.py` (#5987): the engine NFKC-normalizes and strips zero-width/bidi/invalid-byte characters BEFORE matching (defeating compatibility-char / zero-width / soft-hyphen / prefix-homoglyph evasion), and fail-closes with a synthetic-HIGH finding on oversize input (raw or NFKC-expanded). The CLI contract — argv, exit codes, and output shape — is unchanged; the shim fails closed (exit 2) if `python3` is absent. See [ADR-095](../../../../knowledge-base/engineering/architecture/decisions/ADR-095-fail-closed-redaction-engine-contract.md) for the scope boundary (named non-goals: full TR39 homoglyph space, whitespace token-splitting, reversibly-encoded secrets).

- Exit 0 → emit `sentinel: pass` and proceed to Phase 7.
- Exit 1 → print each offset/pattern line from sentinel stdout. Prompt operator to redact. Operator iterates until sentinel exits 0. No max-iteration cap — `Ctrl-C` is the universal abort path.
- Exit 2 → halt with the error message; this is a skill bug OR an unmet runtime prerequisite (e.g. `python3` absent — the shim fails closed to exit 2 rather than a false "clean"/"secrets found" result; the pre-run `[[ -r "$SENTINEL" ]]` guard also exits 2 here, with its own "sentinel not found — halt" message, before the sentinel runs).

**Why pre-inline-emit (SpecFlow Critical #2):** transcripts ARE write boundaries. If the draft is emitted inline and only then scanned, the un-redacted secret has already crossed the operator transcript surface — and the conversation may be screenshot, exported, or replayed in plan-review tools. The sentinel must run before the draft is visible anywhere.

## Phase 7 — Operator review + commit (literal token gate)

Emit the cleared draft INLINE for operator review. (The sentinel cleared it in Phase 6; this emit is safe.) Print:

```
<draft begins>
<full PIR content>
<draft ends>

Review the draft. To commit, type exactly: COMMIT-PIR

Anything else (yes, y, ok, approved, looks good, etc.) is REJECTED. To abort, press Ctrl-C.
```

Parse the operator response with a case-sensitive literal-string equality check. Strip trailing `\r` and surrounding whitespace first so a `printf "COMMIT-PIR\r\n"` from a Windows-origin caller or an autonomous-orchestrator stdin pipe is not silently rejected (agent-user parity per `hr-weigh-every-decision-against-target-user-impact`): `response="${response%$'\r'}"; response="${response//[[:space:]]/}"`, then `[[ "${response}" == "COMMIT-PIR" ]]`.

On `COMMIT-PIR`: write `<slug>-postmortem.md` to `knowledge-base/engineering/operations/post-mortems/`. Do not git-add — operator commits manually per their convention.

There is NO literal `ABORT` token. `Ctrl-C` is universal.

## Phase 8 — Compound-capture handoff (status: resolved gate)

Grep the just-written PIR file for `^status:\s*resolved$`. If the file still shows `status: open`, exit non-zero with:

```
Phase 8 requires PIR status: resolved. Current: <value>.
Update the PIR's `status:` frontmatter after recovery is verified, then re-invoke soleur:incident --phase-8 <slug>.
```

When the file shows `status: resolved`:

1. Emit the closed PIR body (frontmatter + sections) INLINE to the conversation transcript so `compound-capture`'s Step 2 transcript-scrape can see it.
2. Invoke `skill: soleur:compound-capture --headless` (the ONLY supported argument per `plugins/soleur/skills/compound-capture/SKILL.md`).

`compound-capture` does its own transcript-scrape — this skill does not pass structured positional args.

## Naming-collision avoidance (FR6)

This skill must not collide with the rule-telemetry surface at `.claude/hooks/lib/incidents.sh`. See plan #2725 AC6 for the literal collision-token grep that enforces the three forbidden surfaces.

## LLM-trust boundary (FR7 / TR8)

Skill computes identifiers locally and validates format-sensitive LLM-emitted fields before substitution:

- `slug` — local `awk`, never LLM-emitted.
- `incident_pr` — prefer the first `#NNNN` token in `suspected_change` (regex `#[0-9]+`); fall back to leading numeric run only when no `#NNNN` exists. Prevents `"see #3721 (replaces #2725)"` from resolving to `3721` against an unrelated prose-leading numeric.
- `detected_at` / `recovery_at` / `monitoring_detected_at` — ISO-8601 regex match before passing to `date -u -d`. `recovery_at` and `monitoring_detected_at` are optional; when present they MUST match the same regex as `detected_at` before any duration arithmetic. MTTR/MTTD are computed locally from these validated timestamps (Phase 0 compute block) — NEVER accepted as an LLM-emitted duration string.
- `title`, `symptom`, and the new operator-prose fields (`incident_overview`, `participants`, `resolution`, `services_impacted`, `revenue_impact`, `team_impact`, `version_triggered`, `version_restored`) — these are operator-supplied free-form prose that flows into `sed`-substitution against `templates/pir.md`. Run EACH through `sed`-metacharacter escaping (`s|[\\/&]|\\&|g` plus newline strip) before substituting, OR perform substitution with `awk` literal-replace semantics. An LLM-emitted value containing `&` or `/` will otherwise corrupt the template. The enum fields (`detection_method`, `triggered_by`) are validated against their fixed value lists before substitution and need no escaping.
- Phase 0 / dry-run mode: run the redaction sentinel against EVERY operator-supplied string the moment it is captured, BEFORE any echo to the conversation transcript — `symptom` / `suspected_change` / `title` / `incident_overview` / `participants` / `resolution` / `services_impacted` / `revenue_impact` / `team_impact` / `version_triggered` / `version_restored`, AND the `triggers[]` entries (echoed during Phase 3 routing). Any field that is echoed to the transcript OR substituted into the draft must be in this first pass; Phase 6's sentinel-on-draft is the second pass, not a substitute for the first.

Validation failure halts the skill with an explicit operator-fix prompt; the substitution never happens with malformed input.
