---
title: "My counsel question described a narrower record than my own data-flow table"
date: 2026-11-18
category: compliance
module: legal-audits
tags: [dpia, legal-prose-drift, counsel-question, log-persistence, journald]
related_pr: 12900
related_issues: [9853, 11637]
---

# Learning: a legal record's summary sentences drift from its own detailed tables

## Problem

The DPIA re-screen memo for the #11637 egress credential injector (PR #12900) was written as dictated text.
Its section 2 data-flow table was close to the spike code. Four of its summary sentences were not:

- **Q-1, the question for outside counsel**, said "Only a structured approval record is kept, for write
  requests (repository, ref or path, and a body hash)". The code also keeps a hook marker for every
  request, reads included (`approval-hook.mjs`). It keeps a `SOLEUR_EGRESS_ROUTE` line for every
  CONNECT, open web included (`connect-router.mjs`). And `canonicalFor` / the GraphQL classifier in
  `policy.mjs` store the raw query, push options, SHAs and GraphQL hashes. Counsel would have answered a
  question about a smaller system than the one being built.
- **Re-open trigger r3** ("any path, query ... is persisted, or responses are sent to the hook") fired on
  the design it screened. The approval row stores path and query by design, and iron-proxy calls
  `TransformResponse` on every response.
- **Gate B-3** allowed a request path to be dropped "at source or in Vector". The container logs to
  journald with `Storage=persistent` (`infra/journald-soleur.conf`), so dropping the path in Vector
  leaves every path on the host disk.
- **The trigger list** said t5 and t6 "do not fire". Both had already fired: t5 on 2026-11-09 (PR #12465)
  and t6's viewer limb on 2026-10-26 (PR #11115).

## Solution

A six-seat review panel compared each summary sentence with the cited code and ADRs. Those sentences
were rewritten from the section 2 table, not the other way round. B-3 now lists every persisted
artifact, journald first. r3 now excludes the fields the approval row is allowed to hold. B-4 holds the
only list of marker fields, and section 1 points to it. The section 5 and section 6 outcomes did not
change.

## Key Insight

The detailed table in a legal record is usually the part that was checked against code. The prose that
summarises it (the counsel question, the trigger, the gate, the public wording) is checked against
nothing. When a record has both, derive every summary sentence from the table and grep the table for
each noun the summary uses. Any "dropped in the log pipeline" claim must say where the line is first
persisted. On this host that is journald, not Vector.

## Session Errors

1. **Dictated memo text carried factual errors** against the code (Q-1, r3, B-3, t5/t6, the "PA-36 holds"
   claim, DPA item 1, the toggle-copy quote). Recovery: the review panel found them and they were fixed
   inline. **Prevention:** the CLO agent's existing sharp edge ("verify every implementation-detail claim
   against the actual migration/RPC/TS body") covers this. Apply it to the summary sentences as well as
   the tables.
2. **During the fix, a new citation named the wrong source.** "Tracer items 2 and 2b" were cited to
   ADR-325, which does not contain them. Recovery: a grep found them in `connect-router.mjs` and
   `iron-proxy.config.tmpl.yaml`, and the citation was repointed. **Prevention:** grep the cited file for
   the cited token before writing the citation (same sharp edge).
3. **A `sed -n "${L},+6p"` call failed** with "unknown command: ','" because `$L` was empty. This was a
   one-off. Recovery: the line was read another way. **Prevention:** guard the derived line number
   (`[ -n "$L" ]`) before interpolating it.
4. **The session's primary working directory was another session's worktree.** Recovery: every command
   used absolute paths into this worktree, and the other worktree was left untouched. **Prevention:** a
   one-off. Absolute paths are already the rule for agent threads.

## Tags

category: compliance
module: legal-audits
