# CLO copy review — statutory reminder framing (#6798)

**Reviewing agent:** `soleur:legal:clo` (Task subagent).
**Date:** 2026-07-22.
**Gate:** blocking, required by #6798 acceptance bullet 3 ("CLO reviews the wording before it ships
— this is a reliance question, not a copy-polish question"). Run at `/work` Phase 1.4.
**Disposition:** **APPROVE-WITH-CHANGES → change applied → DISCHARGED.**

The CLO read the shipped constant, the email render path (`notifications.ts` §`sendEmailTriageEmailNotification`),
the push path (`sendPushNotifications`), and the cron title (`cron-email-ingress-probe.ts`).

## Verdict (verbatim)

**Q1 — Reliance: APPROVE.** The date never appears un-qualified. Every dated surface carries
"(computed)" inline, and the email body states "not legal advice… best-effort backstop — you remain
responsible for confirming the real deadline." That trio breaks the "this is THE deadline" reading
for a non-technical founder. Discharged.

**Q2 — Art. 33 awareness-vs-receipt asymmetry: APPROVE-WITH-CHANGES.** The copy discloses that a
breach clock "run[s] from a different starting point" but omits the *direction*, which is the
load-bearing fact. The hazard #6798 names is specifically that the computed date can be **later**
than the true deadline — i.e. relying on the shown date makes you late. "Different starting point"
is directionally neutral; a non-technical reader can't infer "and therefore the real deadline may
already have passed." For a 72h regulatory clock, the direction is not a nuance, it is the warning.
Required replacement for the final sentence of `NOT_LEGAL_ADVICE_NOTICE`:

> "Some clocks start earlier than the date used here — a data breach deadline, for example, runs
> from when you first became aware of it, so the real deadline may be sooner than shown and may
> already have passed."

(Everything before that sentence stays verbatim.)

**Q3 — Push with no disclaimer: APPROVE.** Acceptable. The push *body* makes no standalone deadline
claim; it is a non-authoritative imperative pointer. The push *title* carries the date with the
"(computed)" qualifier attached. Guardrail for the record: if the push title/body is ever
restructured to drop "(computed)" from the dated string, a minimal caveat must be re-added — the
approval rests on that token surviving.

**Q4 — Over-claim / under-warn: one required fix (Q2), no over-claim.** The notice never implies
legal completeness; "you remain responsible for confirming the real deadline" correctly places the
duty on the operator. The per-rule `catalogExcerpt` for service-of-process and regulator-contact
correctly frames the computed month as a "safety net / outer default". The sole defect is the
under-warning in Q2.

**Disposition: BLOCKED pending the Q2 wording change.** Once the edit lands, DISCHARGED — no
re-review of the other three surfaces needed. External counsel re-review remains reserved for the
audit frontmatter triggers (first arms-length user, EEA-out, regulated industry), not this change.

## Change applied

The Q2 replacement sentence was applied verbatim to `NOT_LEGAL_ADVICE_NOTICE` in
`apps/web-platform/lib/email-triage/statutory-rules.ts`. The Phase 1 tests (which assert the email
carries "not legal advice" + the rule's clock-origin excerpt) were re-run GREEN after the edit.
**Every CLO-required change is applied.** No other surface required a change.

## GDPR gate (task 1.4.2)

`/soleur:gdpr-gate` assessment of the cumulative diff: **no new processing activity, no new personal
data category, no new recipient/processor.** The change routes an existing notification (same
recipient `auth.users.email`) with server-authored, code-static disclaimer text; Web Push services
already receive the encrypted payload today. Transparency (Art. 12(1)) improves. No Critical
finding → no `compliance-posture.md` Active Items write, no `compliance/critical` issue. The
canonical `hr-gdpr-gate-on-regulated-data-surfaces` regex does not fire (no schema, migration, auth
flow, `.sql`, or new API route); expansion trigger (b) `single-user incident` fires and is assessed
inline here and in the plan §Domain Review → Legal.
