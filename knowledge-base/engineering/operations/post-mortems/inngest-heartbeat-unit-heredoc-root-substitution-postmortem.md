---
title: "An unquoted heredoc ran two doppler commands as root and wrote their stdout into a world-readable unit file"
date: 2026-09-08
incident_pr: 7887
incident_issue: 7674
incident_window: "2026-07-16 (`e3a5bab21`, #6567 — the first backtick spans naming real commands land in the heredoc body) → open; the repair reaches the host only at the host replace. The unquoted delimiter itself predates this, arriving 2026-05-18 in `e7ad93e31` (#3960/#3973), but nothing in the body substituted until #6567."
recovery_at: "not yet — the fix is committed and baked into vinngest-v1.1.26, but the running host still boots v1.1.25"
suspected_change: "`e3a5bab21` (2026-07-16, #6567) added three backtick spans naming real commands to a heredoc body whose delimiter had been unquoted since `e7ad93e31` (2026-05-18). Neither commit is wrong on its own; the defect is their composition."
brand_survival_threshold: single-user incident
status: ongoing
triggers:
  - "`cat > \"$HEARTBEAT_UNIT\" <<HEARTBEATEOF` — an UNQUOTED delimiter, so bash performs command substitution on the body"
  - "five backtick spans accumulated inside the heredoc's explanatory comments, two of which name real commands (`doppler secrets`, `doppler run`)"
  - "inngest-bootstrap.sh runs as root under cloud-init, and asserts at line 344 that the doppler CLI is already on PATH before the heredoc at line 348"
  - "the unit file is written with the ambient umask — no `( umask … && … )` wrapper, unlike the sibling credential write at line 838"
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data breach. The values at risk are service credentials in soleur-inngest/prd (Redis password, LUKS key, service tokens), not personal data, and the file is readable only by local accounts on a single-tenant host whose only principals are root and `deploy`. This was an exposure PATH, not an established access event. Re-evaluate if the Doppler activity log shows a read by an unrecognised principal inside the window above, or if the host is ever given a third local account."
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

`inngest-bootstrap.sh` renders `/etc/systemd/system/inngest-heartbeat.service` from a heredoc.
The delimiter was **unquoted**, so bash performed command substitution on the body — and the body
had accumulated five backtick spans inside its explanatory comments. Two of those spans name real
commands. On every boot of the dedicated Inngest host, cloud-init therefore executed
`doppler secrets` and `doppler run` **as root**, and interpolated their stdout into a systemd unit
file written with the ambient umask.

The defect was found while re-pinning the host's image for #7695 — not by a monitor, and not by
anything looking for it.

## Status

`ongoing` — the repair is committed and baked into `vinngest-v1.1.26`, but the live host still
boots `v1.1.25` and still carries the unquoted delimiter. The window closes at the host replace.

## Symptom

None observable. There is no alert, no log line, and no failed unit: the substitution happens at
*render* time and its only trace is the content of the rendered file. The heartbeat service itself
started and ran normally, because the interpolated text landed inside comment lines.

That is the whole problem — a defect whose symptom is the absence of one.

## Incident Timeline

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-05-18 | `e7ad93e31` (#3960/#3973) writes the heartbeat unit with an unquoted `<<HEARTBEATEOF`. The body has no metacharacters, so nothing substitutes. |
| agent | 2026-07-16 | `e3a5bab21` (#6567) adds three backtick spans to the body, two naming `doppler` commands. Substitution begins on the next boot. |
| agent | 2026-07-18 | `119861998` (#6631) adds a fifth span. Five in total; each host boot renders the unit and runs two real `doppler` commands as root. |
| agent | 2026-09-08 | Found incidentally while auditing heredoc delimiters for the #7695 image re-pin. |
| agent | 2026-09-08 | Repaired: delimiter quoted, `@@SENTINEL@@` substitution added for the two values that genuinely need interpolation, plus a refusal on any unsubstituted residual. |
| agent | 2026-09-08 | Guard D added to `cloud-init-inngest-bootstrap.test.sh` so the class cannot recur silently. |

- **Start time (detected):** 2026-09-08 (substitution began 2026-07-16; the unquoted delimiter dates to 2026-05-18)
- **End time (recovered):** not yet — at the host replace
- **Duration (MTTR):** open

## Participants and Systems Involved

The dedicated Inngest host (`hetzner-162809678`), `inngest-bootstrap.sh` as baked into the
`soleur-inngest-bootstrap` OCI image, and the `soleur-inngest/prd` Doppler config.

## Detection (+ MTTD)

- **How detected:** incidental, during a manual audit of heredoc delimiters for an unrelated
  re-pin. No monitor covers this class; none could, since the defect emits no runtime signal.
- **MTTD:** ~54 days.

## Triggered by

system — an accumulation of ordinary explanatory comments inside a heredoc whose delimiter had
been unquoted since it was written.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| The unquoted delimiter caused command substitution of the comment backticks | Reproduced in a sandbox: the pre-fix block, run with a stub `doppler` on PATH, executed it twice and wrote its stdout into the rendered file at two lines | none | **Confirmed** |
| The substitutions failed harmlessly because `doppler` was absent at render time | — | Line 344 of the same script asserts the doppler CLI is on PATH and exits if it is not, four lines before the heredoc | **Rejected** |

## Resolution

The delimiter is now quoted (`<<'HEARTBEATEOF'`). The two values that genuinely need
interpolation are carried as `@@DOPPLER_BIN@@` and `@@HEARTBEAT_SCRIPT@@` sentinels, substituted
by `sed` after the write, with an explicit refusal if any `@@` residual survives. The rendered
directives are byte-identical before and after the repair.

`DOPPLEREOF` at line 838 is deliberately left unquoted: it is wrapped in `( umask 0137 && … )`,
and converting it to the sentinel form would require writing a temp file and renaming it, which
would regress CWE-732 in order to fix nothing.

## Recovery verification

Measured in both directions, in a sandbox, with a stub `doppler` that prints a synthetic
non-credential string:

- **Pre-fix block:** the stub ran twice; the synthetic string appears at two lines of the rendered
  unit; the file is written with the ambient umask (`664` under the sandbox's `0002`; `644` under
  cloud-init's root default `0022`).
- **Post-fix block:** zero occurrences. The substitution no longer happens.

Recovery on the host is **not** verified and cannot be until the replace: the host is dark, and
`hr-no-ssh-fallback-in-runbooks` bars diagnosing it by login. `scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh` is the probe that will observe the replaced host.

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did `doppler` run as root at boot?** Because bash command-substituted a backtick span in
   the heredoc body.
2. **Why was the body substituted?** Because the delimiter was unquoted.
3. **Why was it unquoted?** Because the heredoc needs two interpolated values (`$DOPPLER_BIN`,
   `$HEARTBEAT_SCRIPT`), and an unquoted delimiter is the cheapest way to get them.
4. **Why did nobody notice that this also opens the whole body to substitution?** Because when the
   delimiter was written (2026-05-18) the body had no backticks — the choice was correct for the
   body it had. The defect was created two months later, by prose, in a commit that changed no
   executable line.
5. **Why did nothing catch the prose?** Because no gate read heredoc delimiters at all. The
   sibling credential write four hundred lines below had already been hardened against a related
   class, and that hardening did not generalise into a check.

**Root cause:** a delimiter choice that is safe only as long as the body stays free of shell
metacharacters, in a body that exists to be commented.

## Versions of Components

- **Version(s) that triggered the outage:** `soleur-inngest-bootstrap` `v1.1.25` and every earlier
  tag whose tree includes `e3a5bab21` (2026-07-16). This is the image the host runs today.
- **Version(s) that restored the service:** `vinngest-v1.1.26@sha256:cba7c11fb029f80a19a4212474936e79c90205986f5d5e03dfe2219c52053385` — built, signed, and pinned, but not yet booted.

## Impact details

### Services Impacted

The dedicated Inngest host only. The heartbeat service itself was unaffected — it started and ran.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none observable. No request path touches the rendered file.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

The honest statement of risk is narrower than "credentials leaked": two commands ran as root that
should not have, and their stdout was written to a file more readable than it should be. Whether
that stdout carried secret **values** depends on whether a Doppler token was exported into root's
environment at that instant, which cannot be observed while the host is dark and SSH diagnosis is
barred. The mechanism is proven; the payload is not.

### Revenue Impact

None.

### Team Impact

The repair rides an image re-tag that was already being cut, so it cost two lines. Finding it cost
one audit that was happening anyway.

## Lessons Learned

### Where we got lucky

The five backtick spans happened to sit inside `#` comment lines, so the substituted output landed
in comments rather than in a `ExecStart=` directive. A backtick span one line lower would have
rewritten what the unit executes.

### What went well

The audit that found this was looking at delimiters as a *class*, not at this file. That is why it
found something no symptom pointed at.

### What went wrong

The hardening applied to the sibling credential write never generalised into a check, so the same
family of defect was free to reappear four hundred lines above it. A fix applied to an instance
rather than to a class is a fix with a half-life.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #7674 | Replace the host so it boots `vinngest-v1.1.26`, closing the exposure window, and confirm the rendered unit is clean via the follow-through probe rather than by host login | open |

Guard D (heredoc delimiter census + strict parse, in
`apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh`) is the recurrence check and landed
in the source PR, so it is not carried here as residual work.
