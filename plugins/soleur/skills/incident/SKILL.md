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

# incident Skill

**Inspiration:** see `NOTICE` (MIT — alirezarezvani/claude-skills, clean-room).

**Purpose:** classify an incident's `brand_survival_threshold` in <60s, gate PIR drafting behind a GDPR Art. 33/34 notification-trigger evaluation, and scaffold a redaction-gated internal PIR matching the shape of `knowledge-base/engineering/operations/post-mortems/dashboard-error-postmortem.md`.

**Directory convention:** PIRs (incident records) live under `knowledge-base/engineering/operations/post-mortems/`. Procedural runbooks (recovery procedures, rotation playbooks, audit checklists) live under `knowledge-base/engineering/operations/runbooks/`. The split is semantic: runbooks have `triggers:` frontmatter and are scanned by Phase 3 for routing; PIRs do not and are not scanned.

**Operator-invoked only.** No Sentry/cron auto-fire substrate. Pre-write redaction sentinel ([scripts/redact-sentinel.sh](./scripts/redact-sentinel.sh)) is load-bearing — it runs BEFORE the draft is emitted inline to the conversation transcript AND before any file is written to disk. Transcripts ARE write boundaries; sentinel must precede inline-emit, not just file-commit.

All prod-touching steps are advisory + ack-gated per `hr-menu-option-ack-not-prod-write-auth`. The commit gate accepts a single literal token (`COMMIT-PIR`); LLM fuzzy-interpretation of "ok looks good" must never write a PIR.

## Headless / Dry-run modes

- `--headless`: suppress interactive prompts. On any blocking ack, exit non-zero with a structured error message instead of waiting. Phase 8 still requires `status: resolved`.
- `--dry-run <fixture.json>`: read fields from a synthetic JSON fixture instead of operator prompts. Used by [scripts/dry-run.sh](./scripts/dry-run.sh) to drive AC8-AC13 against fixtures under `test/fixtures/`. Dry-run never writes to `post-mortems/` and never invokes `compound-capture`; it emits the would-be PIR to stdout.

## Phase 0 — Capture facts

> **No-SSH fact-pulling (Soleur vision — `hr-no-dashboard-eyeball-pull-data-yourself`).** The operator is non-technical: NEVER ask them to SSH, run `df -h`, or read a dashboard, and do NOT trust the report's stated *mechanism* — pull the actual prod error/state yourself. Toolchain: Doppler `DATABASE_URL_POOLER` (prod DB read), **Sentry issues via `doppler run -p soleur -c prd -- scripts/sentry-issue.sh <id>` / `--latest-event` (prefer the least-privilege `SENTRY_ISSUE_RO_TOKEN`; falls back to `SENTRY_ISSUE_RW_TOKEN`; `SENTRY_AUTH_TOKEN` 403s on issues — the producer's real stderr is in `exception.values[].value`; runbook `sentry-issue-read.md`)**, `/soleur:trigger-cron`, prod HTTP/`gh run`. If a needed signal has no no-SSH read path, **BUILD one** (emit to a GitHub issue/DB/endpoint) rather than deferring. **Why:** #4886 — the incident report blamed ENOSPC; the real cause (a dirty-clone `.claude/settings.json` blocking `git pull`) was one Sentry-issue read away. See [[2026-06-03-no-ssh-prod-signal-toolchain-never-hand-the-operator-an-ssh-task]].

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
  iso_to_epoch() {  # halt on a regex-valid-but-calendar-invalid date
    local epoch
    date -u -d "$1" +%s 2>/dev/null || { echo "incident: not a valid calendar date: $1" >&2; exit 2; }
  }
  if [[ -n "${recovery_at}" ]]; then
    mttr_secs=$(( $(iso_to_epoch "${recovery_at}") - $(iso_to_epoch "${detected_at}") ))
    (( mttr_secs < 0 )) && { echo "incident: recovery_at precedes detected_at (transposed)" >&2; exit 2; }
    MTTR=$(printf '%dh%dm' $(( mttr_secs / 3600 )) $(( (mttr_secs % 3600) / 60 )))
  else
    MTTR="TBD (status not resolved)"
  fi
  if [[ "${detection_method}" == "monitoring" && -n "${monitoring_detected_at}" ]]; then
    mttd_secs=$(( $(iso_to_epoch "${monitoring_detected_at}") - $(iso_to_epoch "${detected_at}") ))
    (( mttd_secs < 0 )) && { echo "incident: monitoring_detected_at precedes detected_at (transposed)" >&2; exit 2; }
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
| `{{ROOT_CAUSE_HYPOTHESIS}}` | TBD (operator fills in Phase 7 review) |
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
| `{{ACTION_ITEM_ISSUE}}` / `{{ACTION_ITEM_DESC}}` | Phase 7 review — the merged **Action Items & Follow-ups** table. **Every row REQUIRES a filed GitHub issue number:** run `gh issue create` (cross-referencing the source PR in the body) FIRST, then fill `#<n>` + description. No bare bullets, no `TBD`. If there are genuinely zero follow-ups, replace the table with the single permitted sentence `_No action items — incident fully resolved in the source PR with no residual work._`. The `/ship` Incident-PIR gate blocks merge on any item lacking a `#NNNN`. |

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

Run `bash scripts/redact-sentinel.sh <draft-tmpfile>` against the unwritten draft. The draft lives in `mktemp` only — it has NOT been emitted inline yet AND has not been written to `post-mortems/`.

`redact-sentinel.sh` is a thin shim over the hardened `redact-engine.py` (#5987): the engine NFKC-normalizes and strips zero-width/bidi/invalid-byte characters BEFORE matching (defeating compatibility-char / zero-width / soft-hyphen / prefix-homoglyph evasion), and fail-closes with a synthetic-HIGH finding on oversize input (raw or NFKC-expanded). The CLI contract — argv, exit codes, and output shape — is unchanged; the shim fails closed (exit 2) if `python3` is absent. See [ADR-095](../../../../knowledge-base/engineering/architecture/decisions/ADR-095-fail-closed-redaction-engine-contract.md) for the scope boundary (named non-goals: full TR39 homoglyph space, whitespace token-splitting, reversibly-encoded secrets).

- Exit 0 → emit `sentinel: pass` and proceed to Phase 7.
- Exit 1 → print each offset/pattern line from sentinel stdout. Prompt operator to redact. Operator iterates until sentinel exits 0. No max-iteration cap — `Ctrl-C` is the universal abort path.
- Exit 2 → halt with the sentinel's error message; this is a skill bug OR an unmet runtime prerequisite (e.g. `python3` absent — the shim fails closed to exit 2 rather than a false "clean"/"secrets found" result).

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
Update the PIR's `status:` frontmatter after recovery is verified, then re-invoke /soleur:incident --phase-8 <slug>.
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
