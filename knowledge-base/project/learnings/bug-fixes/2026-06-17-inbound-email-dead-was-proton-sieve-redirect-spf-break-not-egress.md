---
title: "Dead inbound email was a Proton Sieve redirect failing SPF-on-forward — not the egress firewall the incident was framed around; fix = native Proton forward (SRS)"
date: 2026-06-17
category: bug-fixes
module: apps/web-platform/server/inngest/functions/email-on-received.ts, Proton Sieve/forwarding, Resend inbound
tags: [email, ingress, proton, sieve, spf, dmarc, forwarding, resend, live-diagnosis, playwright, red-herring]
prs: [5465]
issues: [5467, 5468]
---

# Learning: inbound email "dead since 06-12" was a Proton forward breaking SPF, not the egress firewall

## Problem

The operator-inbox email-triage chain went silent: `cron-email-ingress-probe`
RED daily, zero new `email_triage_items` rows since 2026-06-12. The incident was
framed around the recent cron **egress firewall** rollout (DOCKER-USER
default-drop #5089, LB-rotation grace-window #5413) — and the load-bearing
anomaly was "the probe still failed AFTER the grace-window egress fix."

## What it actually was

The Proton **Sieve `redirect`** (the #5103 `forward-and-keep` filter
`ops@soleur.ai → triage@inbound.soleur.ai`) was **enabled and matching**, but
its `redirect :copy` **never delivered**: forwarding breaks SPF/DMARC alignment
(the forwarded copy keeps `From: notifications@soleur.ai` while the envelope is
now Proton; soleur.ai's apex SPF authorizes only `_spf.protonmail.ch`), so
Resend's inbound MX dropped the forwarded copy. The `:copy` kept the original,
so probes **piled up unread in the ops@ inbox** while never reaching the
pipeline. The egress firewall was a complete red herring — egress-only, and
proven healthy by Supabase claim-inserts succeeding for direct-to-inbound mail.

## Lessons

1. **The loudest recent change is a hypothesis, not the cause.** The egress
   firewall was the obvious suspect; the actual break was an operator-owned
   Proton hop the firewall cannot touch. The "still broke after the egress fix"
   fact was the tell that egress was not the (whole) story — chase it, don't
   explain it away.
2. **Build a one-step differential that isolates the single varying hop.**
   Direct-to-inbound test sends (bypassing Proton) landed end-to-end; Proton-
   routed probes never produced a Resend webhook. Same pipeline, only Proton
   differs → the break is the Proton forward. This localized L3→L7 in one move.
3. **A Sieve/`redirect` forward to an external domain silently fails SPF-on-
   forward.** Prefer the provider's **native forwarding** (Proton uses SRS,
   which rewrites the envelope sender so SPF passes). Native forward also has a
   confirmation handshake; when the target is your own programmatic inbox
   (`triage@inbound.soleur.ai` via Resend), the confirmation email lands in your
   own pipeline / Resend dashboard, so the loop is completable without a human
   mailbox.
4. **"Received" ≠ "forwarded" — search the source mailbox.** The probes were in
   the ops@ **inbox** (not spam), which killed both the "disabled filter" and
   "spam-foldered" hypotheses and pointed straight at the redirect action.
5. **One discovery cascades to another.** Reading bodies for the confirmation
   link surfaced that the prod `RESEND_API_KEY` is **send-only** —
   `fetchReceivedEmail` (`resend.emails.receiving.get`) can't read inbound
   bodies, which is the real cause of the HOP F `mail_class=null` summary
   failure (#5468). Keep discovered defects as their own issues.
6. **Live remediation has true human gates — drive up to them, hand off the
   one interaction.** Creating a Proton forward requires the account password
   in a browser the operator can see; the headless Playwright MCP browser
   couldn't provide it. The workable pattern: open the exact settings page in
   the operator's own visible browser (`xdg-open`), guide the password-gated
   clicks, then resume driving the parts with no human gate (read the Resend
   confirmation email, navigate the accept link, fire + verify the probe).
7. **Extract single-use tokens via `browser_evaluate(filename:…)` + in-browser
   navigation**, never into the transcript — the Proton confirmation JWT was
   activated by setting `window.location.href` inside `evaluate`, so the token
   never entered the conversation.

## Verification

Manual-trigger probe (token `739db236…`) round-tripped to `mail_class='probe'`
in ~11s after activating the native forward. Diagnosis flow captured in
`knowledge-base/engineering/operations/runbooks/inbound-email-ingress-dead.md`.
