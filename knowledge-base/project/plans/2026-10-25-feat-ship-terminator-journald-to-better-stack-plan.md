---
title: "feat: ship the Inngest TLS terminator's journald to Better Stack"
date: 2026-10-25
slug: ship-terminator-journald-to-better-stack
branch: feat-one-shot-terminator-journald-shipping
issue: 10136
---

## Overview

The Inngest link self-gate failed a third time on 2026-10-24 with `phase=request` (TLS completed and verified, no HTTP response). The
stunnel terminator runs as `soleur-inngest-tls.service` on the Inngest host and its own journal is not shipped to Better Stack, so the
terminator's side of that stage cannot be read without SSH. This plan ships that unit's journal through the Vector agent, which is the
exit the runbook names for the `request` stop rule.
