---
title: "Doppler CLI token auto-attached into session transcripts via resolvable credential path in preflight prose"
date: 2026-07-23
incident_pr: 6864
incident_window: "unknown start (path present since preflight Check 10 authored) — 2026-07-23 detection"
recovery_at: "2026-07-23 (token rotated by operator + prose neutralized in #6864)"
suspected_change: "preflight/SKILL.md Check 10 credentialed-CLI reject prose writing a literal home-relative Doppler config path"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - security
  - credential-exposure
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option.
- `human` — Operator did this directly.

# Incident Overview

`plugins/soleur/skills/preflight/SKILL.md` Check 10 (the credentialed-CLI *reject* prose) wrote the literal, home-relative filesystem path to the operator's live Doppler CLI config at four sites. Because the preflight skill loads on **every ship**, Claude Code's harness file-path auto-attachment resolved that path to the real on-disk file and read the operator's live `dp.ct.*` Doppler CLI token into the model context as a `type: file` attachment (rendered as a "Read tool result"). The token was thereby captured into **9 separate session transcripts**.

This is a self-inflicted exposure via a harness feature, NOT an external attacker, rogue hook, or compromised MCP. The irony: security prose *warning* that commands must not read credential files is exactly what caused the credential file to be read.

## Status

resolved — the operator rotated the Doppler CLI token, and #6864 neutralizes the resolvable path literals + adds a CI guard preventing recurrence.

## Symptom

A `type: file` attachment whose `filename` was the operator's Doppler config path appeared in session transcripts, exposing a live `dp.ct.*` token. First surfaced when the operator noticed a token value in a block during a ship flow and asked for a security analysis.

## Incident Timeline

- **Start time (detected):** 2026-07-23 (exact first-exposure time unknown — the trigger path has existed since Check 10 was authored)
- **End time (recovered):** 2026-07-23
- **Duration (MTTR):** same-session remediation (token rotated + prose neutralized + guard added)

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-07-23 | Operator noticed a Doppler token value in a ship-time block; requested a prompt-injection/security analysis. |
| agent | 2026-07-23 | Forensics on the session transcript identified a `type='attachment'`/`type='file'` entry whose `filename` was the Doppler config path — confirming the harness auto-attach mechanism (not an attacker). Token found across 9 transcripts. |
| agent | 2026-07-23 | Verified containment: token absent from repo/history/origin-main; transcripts outside the repo; only the Doppler file attached (not ssh/aws/etc. despite their paths being named); MCP = playwright only; hooks all legitimate. |
| human | 2026-07-23 | Rotated the Doppler CLI token. |
| agent | 2026-07-23 | Shipped the root-cause fix (#6864): neutralized the four resolvable path literals + parser mirror + comments; added `scripts/lint-credential-path-literals.py` CI guard. |

## Participants and Systems Involved

- Claude Code harness (file-path auto-attachment feature).
- `plugins/soleur/skills/preflight/SKILL.md` (the loaded doc carrying the literal path).
- Doppler CLI (`~/.doppler/` config holding the `dp.ct.*` token).
- Session transcript store (local, under the operator's home).

## Detection (+ MTTD)

- **How detected:** external/manual — the operator visually spotted a token value during a ship flow. NOT caught by any monitor (the exposure is harness behavior into local transcripts, outside any alerting surface).
- **MTTD:** unknown (the path predates detection; the exposure was silent until visually noticed).

## Triggered by

system — the harness auto-attach feature acting on a resolvable path literal in loaded doc prose.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| External prompt injection | initial framing ("prompt injection attempt") | token sits in a `type: file` attachment keyed to a local path; no external input vector; only the operator's own file | REJECTED |
| Rogue hook / MCP reading the file | credential appeared "as if read" | hook inventory all legitimate; MCP = playwright only; no read-tool call in the trace | REJECTED |
| Harness auto-attach of a resolvable path in loaded prose | attachment `filename` == the literal path written in preflight Check 10; only files whose paths appear in prose were attached | none | CONFIRMED |

## Resolution

Two-part remediation in #6864:
1. **Neutralize the trigger** — replaced every resolvable home-relative credential path literal in `preflight/SKILL.md` Check 10 (and the byte-identical parser mirror + two comments) with non-resolvable forms (directory-only `~/.doppler/`, descriptive names, `<placeholder>` segments), preserving the security prose's meaning. The runtime denylist (`CRED_REJECT_RE` verb regex, `CMD_DEQ`, SSH/`SUBST` rejects) was left byte-identical.
2. **Durable guard** — `scripts/lint-credential-path-literals.py` (CI-wired, changed-files grandfathering) fails any tracked `*.md` under `plugins/**`/`knowledge-base/**` that reintroduces a resolvable credential path. Non-vacuous test (20 assertions, mutation-verified). The operator rotated the exposed token.

## Recovery verification

- Token rotated by the operator (old `dp.ct.*` value dead).
- `python3 scripts/lint-credential-path-literals.py --changed --base origin/main` exits 0 over the neutralized files; the guard fails the pre-fix form (proven by the 20-assertion test, including a dogfood catch of 3 resolvable paths in this incident's own compound-learning draft).
- Real-world confirmation (absence of the `type: file` credential attachment in future sessions) is a harness behavior CI cannot exercise — the mechanical CI invariant ("no tracked doc contains a resolvable credential-file path") is the enforceable proxy.

## GDPR assessment (Art. 33/34)

`art_33_triggered: false`, `art_34_triggered: false`. Rationale: the exposed artifact is an **infrastructure credential** (a Doppler CLI access token), not personal data of any data subject. No GDPR personal-data breach occurred; there are no affected data subjects and no supervisory-authority notification obligation. The exposure was confined to the operator's own local session transcripts. Recorded because the `single-user incident` threshold requires the Art. 33/34 evaluation, not because a breach occurred.

## 5-Whys (final root cause)

1. Why was a live token in the transcript? The harness auto-attached the Doppler config file.
2. Why did it auto-attach? A locally-resolvable path to that file appeared in loaded doc prose.
3. Why was the path in the prose? Check 10's reject message documented, verbatim, the credential files an un-scrubbed `$HOME` leaves readable — to explain the risk.
4. Why did that leak? The documentation used literal resolvable paths where descriptive names would have conveyed the same meaning.
5. Why wasn't it caught earlier? No guard existed for "resolvable credential path in a tracked doc," and the exposure is silent (into local transcripts, no alerting surface). #6864 adds that guard.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #6868 | Drain the ~12 grandfathered historical docs that still carry resolvable credential paths; decide whether to promote the `lint-bot-statuses` CI job to a required check so the guard is blocking rather than advisory. | agent |
