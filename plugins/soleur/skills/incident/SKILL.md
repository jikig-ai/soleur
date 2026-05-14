---
name: incident
description: "This skill should be used when classifying a live or recent production incident and scaffolding a redaction-gated internal post-incident report (PIR)."
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

**Purpose:** classify an incident's `brand_survival_threshold` in <60s, gate PIR drafting behind a GDPR Art. 33/34 notification-trigger evaluation, and scaffold a redaction-gated internal PIR matching the shape of `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md`.

**Operator-invoked only.** No Sentry/cron auto-fire substrate. Pre-write redaction sentinel (`scripts/redact-sentinel.sh`) is load-bearing — it runs BEFORE the draft is emitted inline to the conversation transcript AND before any file is written to disk. Transcripts ARE write boundaries; sentinel must precede inline-emit, not just file-commit.

All prod-touching steps are advisory + ack-gated per `hr-menu-option-ack-not-prod-write-auth`. The commit gate accepts a single literal token (`COMMIT-PIR`); LLM fuzzy-interpretation of "ok looks good" must never write a PIR.

## Headless / Dry-run modes

- `--headless`: suppress interactive prompts. On any blocking ack, exit non-zero with a structured error message instead of waiting. Phase 8 still requires `status: resolved`.
- `--dry-run <fixture.json>`: read fields from a synthetic JSON fixture instead of operator prompts. Used by `scripts/dry-run.sh` to drive AC8-AC13 against `test/fixtures/dry-run-*.json`. Dry-run never writes to `runbooks/` and never invokes `compound-capture`; it emits the would-be PIR to stdout.

## Phase 0 — Capture facts

Collect from the operator (or from the dry-run fixture):

1. `title` — short prose, e.g. `"dashboard error boundary outage 2026-05-14"`.
2. `detected_at` — ISO-8601 UTC. The skill validates the regex `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$` before substitution (FR7 LLM-trust boundary).
3. `symptom` — operator prose, free-form.
4. `suspected_change` — `PR #N` or commit SHA. Skill validates `incident_pr` is numeric.
5. `affected_user_count` — integer estimate; 0 is valid.
6. `data_categories_breached` — array of GDPR Art. 4(1) categories (email, userId, IP, billing, content). Empty array = no personal-data breach.
7. `risk_to_subjects` — enum `none | low | medium | high`. Phase 2 reads this for Art. 34 trigger evaluation.

Compute locally (FR7 LLM-trust boundary — never accept these from an LLM-emitted blob):

- `slug` — `awk` kebab-case of title, dropping non-`[a-z0-9-]`.
- File path — derived from slug: `knowledge-base/engineering/ops/runbooks/${slug}-postmortem.md`.

## Phase 1 — Classification

Render the `brand_survival_threshold` decision criteria INLINE before asking for confirmation. Criteria text (3 tiers, paraphrased from `hr-weigh-every-decision-against-target-user-impact`):

- **none** — no user-facing artifact, no credential surface, no billing path; internal tooling / docs / CI.
- **single-user incident** — at least one real user impacted (data loss, trust breach, credential exposure, billing surprise) OR any sensitive-data surface is at risk.
- **aggregate pattern** — repeated or systemic impact across multiple users or tenants; brand-survival-level severity.

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

`awk`-scan every `*.md` under `knowledge-base/engineering/ops/runbooks/` for a `triggers:` frontmatter block. Build a `{slug: [trigger, ...]}` map. Compute a literal-substring similarity score between operator `symptom` tokens and each runbook's `triggers[]`. Surface the top-3 matches with score and prompt:

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
| `{{INCIDENT_WINDOW}}` | `${detected_at} → TBD` (operator fills recovery time in Phase 7 review) |
| `{{SUSPECTED_CHANGE}}` | Phase 0 `suspected_change` prose |
| `{{BRAND_SURVIVAL_THRESHOLD}}` | Phase 1 confirmed value |
| `{{STATUS}}` | Literal `open` (terminal value is `resolved` — set by operator in Phase 7 review before Phase 8) |
| `{{TRIGGERS_LIST}}` | Phase 3 selected runbook slugs as YAML list items |
| `{{ART_33_TRIGGERED}}` | Phase 2 |
| `{{ART_34_TRIGGERED}}` | Phase 2 |
| `{{ART_33_DEADLINE}}` | Phase 2 |
| `{{CLASSIFICATION_OVERRIDE_BLOCK}}` | Phase 1 (empty if no override) |
| `{{SECRET_LEAK_PREAMBLE}}` | See below |
| `{{SYMPTOM}}` | Phase 0 `symptom` |
| `{{ROOT_CAUSE_HYPOTHESIS}}` | TBD (operator fills in Phase 7 review) |
| `{{DETECTED_AT}}` | Phase 0 `detected_at` |

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

Run `bash scripts/redact-sentinel.sh <draft-tmpfile>` against the unwritten draft. The draft lives in `mktemp` only — it has NOT been emitted inline yet AND has not been written to `runbooks/`.

- Exit 0 → emit `sentinel: pass` and proceed to Phase 7.
- Exit 1 → print each offset/pattern line from sentinel stdout. Prompt operator to redact. Operator iterates until sentinel exits 0. No max-iteration cap — `Ctrl-C` is the universal abort path.
- Exit 2 → halt with the sentinel's error message; this is a skill bug.

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

Parse the operator response with a case-sensitive literal-string equality check:

```bash
if [[ "${response}" == "COMMIT-PIR" ]]; then
  # write the PIR
else
  echo "Rejected. Type exactly: COMMIT-PIR" >&2
  exit 1
fi
```

On `COMMIT-PIR`: write `<slug>-postmortem.md` to `knowledge-base/engineering/ops/runbooks/`. Do not git-add — operator commits manually per their convention.

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

This skill must not collide with the rule-telemetry surface defined at `.claude/hooks/lib/incidents.sh`. Specifically the skill must not:

- Define a shell function with the same name as that file's telemetry-emit helper.
- Write to that file's jsonl output path under `.claude/`.
- Emit a PIR frontmatter field whose name matches the telemetry enum field used by the hook library.

Plan AC6 enforces all three via a `grep -lE` block in `plan #2725`; the grep is the source of truth for the literal tokens.

## LLM-trust boundary (FR7 / TR8)

Skill computes identifiers locally and validates format-sensitive LLM-emitted fields before substitution:

- `slug` — local `awk`, never LLM-emitted.
- `incident_pr` — numeric regex match (`^[0-9]+$`) before substituting into frontmatter.
- `detected_at` — ISO-8601 regex match before passing to `date -u -d`.

Validation failure halts the skill with an explicit operator-fix prompt; the substitution never happens with malformed input.
