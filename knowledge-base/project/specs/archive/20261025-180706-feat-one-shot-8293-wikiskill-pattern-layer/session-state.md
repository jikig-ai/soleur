# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-24-feat-wikiskill-pattern-layer-proposer-index-ledger-reader-plan.md
- Status: complete
- Technical-ruling gate: pass (28 rows); cto_spawns=2

### Errors
None blocking (see plan Session Summary: transient gh TLS errors; stale weakness-digest premise).

### Decisions
- Dark launch: cron default stays corpus; manual input=patterns; ledger read on patterns path only.
- Ledger: row stays in PR; Octokit search over head:self-healing/auto- is the system of record; fail-closed-loud.
- patterns/ is the single surface; no common-solutions.md or critical-patterns.md created.
- Effect unmeasured until #10552 clears; PR must not assert the dump caused zero PRs.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan, CTO x2 spawns (this session), CLO, CPO, review panel.

## Fix-round dedup ledger (review of PR #10970)

Round 1 (panel 9edde5cb4c..d8a7c6a50b, fix 5d49a84d88): 8 seats (observability, legal, security, architecture, data-integrity, structural-enumeration, code-quality, test-design), 0 P1, 6 P2, ~35 P3 raw. Seats that reported: observability, legal, security, architecture, data-integrity, structural-enumeration, code-quality, test-design.

| canonical defect key | seats | disposition |
|---|---|---|
| gray-matter js engine open at other call sites (class gap) | security, architecture, code-quality, structural | shared `front-matter-guard.ts`, 4 callers, source pin |
| ledger query had no author bound; `head:` is a prefix match | security | `author:app/soleur-ai`, test pins |
| `error_class` is `StepError`, not `LedgerReadError` | observability, data-integrity | runbooks + harness test |
| legal prose over-claims (receives only five fields; names screened; PA-31 (f) retention) | legal, data-integrity | Art. 30 + DPIA correction rewritten before merge |
| PII scan on raw YAML, model gets decoded value | structural | decoded title/summary/tags scanned |
| symlink alias inside the learnings root | structural, security | realpath equality |

Structural-cause roll-up: a defect class closed at one instance but not at every call site; docs claiming more than the code does; fix tests pinning text rather than behaviour.

Round 2 (fix diff d8a7c6a50b..5d49a84d88): 8 seats (security, test-design, code-quality, architecture, data-integrity, observability, legal, structural-enumeration), 0 P1, 3 P2 (dirReadable default unpinned, decoded-tag PII unpinned, source pin bypassable), ~25 P3.

| canonical defect key | seats | disposition |
|---|---|---|
| decoded-field stringify ran before shape validation (alias expansion aborts the step) | structural | scan moved after shape checks; spy test |
| decoded tag PII unpinned | test-design | test row |
| `dirReadable ?? true` justified by a build that never existed | code-quality, test-design, architecture | default removed |
| source pin walked 4 dirs, static imports only | security, test-design, code-quality, architecture, structural | whole-app walk, import()/require forms, comment lines only |
| `cause` tag does not reach the pino mirror | observability | cause repeated in `extra` at 4 sites |
| literal U+FEFF in new files | code-quality, architecture | `﻿` |
| sorted-order test deleted, `.sort()` unpinned | code-quality, architecture, test-design | readdir-reversing mock test |
| head: described as word-prefix; DPIA says other authors' items can return | data-integrity, code-quality, legal, security | reworded everywhere |
| content-publisher skips tagged-opener files silently | security, observability | reportSilentFallback in the catch |
| no CI mirror for alias/size drops; decoded handle bypasses the denylist | data-integrity, legal | live-tree loads the real tree; denylist over decoded fields |
| per-page evidence count unbounded | security, structural | MAX_PAGE_EVIDENCE = 40 |
| zone-less `closed_at` accepted | test-design | regex requires a zone |
| in-repo alias rows, symlinked-parent positive control, excerpt boundary, inner separator | test-design | tests added |

Deferred (tracked in #10977): marker key allowlist from one runtime array, a distinct cause for a missing learnings root and for an oversize excerpt, an aggregate prompt-byte budget and page count cap, case-insensitive filesystem lexical filters, ISO/`compliance-posture.md` pointer, the KB content route serialising an alias-expanded frontmatter (pre-existing).
