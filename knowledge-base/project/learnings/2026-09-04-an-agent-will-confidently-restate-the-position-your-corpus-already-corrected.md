---
title: "An agent will confidently restate the position your corpus already corrected"
date: 2026-09-04
category: workflow-patterns
module: brainstorm, subagents, legal-corpus
tags: [subagent-verification, corpus-correction, citation-integrity, autofix, deferral-triggers]
issues: [3210, 7624, 7832]
pr: 7828
---

# An agent will confidently restate the position your corpus already corrected

## Problem

During the 2026-09-04 Corporate CLA brainstorm, a `learnings-researcher` subagent reported, as a finding:

> "Cloudflare R2 + FreeTSA transfers: R2 buckets are hosted in EU (WEUR) — **no outbound transfer**. The CLA evidence archive does not leave the EU."

This is fluent, plausible, and matches the intuitive model of data residency. It is also **the exact position this repo raised issue #7624 to correct**, and the correction had already landed. `knowledge-base/legal/article-30-register.md` PA-7 §(e) says, in terms:

> "`cloudflare_r2_bucket.cla_evidence` sets `location = "WEUR"`, which is a **placement hint, not a jurisdiction** — the bucket sits on Cloudflare's `default` (standard, non-EU-tier) jurisdiction … **The transfer arises from the identity of the importer, not from the location of the bytes**."

The same agent, in the same report, asserted that a signatory's name + title + corporate email are **Art. 9 special-category data**. Art. 9's categories are closed (racial/ethnic origin, political opinions, religious belief, trade-union membership, genetic, biometric, health, sex life/orientation). A job title is not among them.

Both claims would have propagated into a legal spec. Neither was flagged by anything.

## Root cause

A subagent reasons from general knowledge plus whatever it read. Where a repo has *corrected* a widely-held position, general knowledge holds the **pre-correction** view — and the correction exists precisely because the pre-correction view is the intuitive one.

That makes a reversed correction more dangerous than a novel hallucination:

- A novel error looks unfamiliar and invites checking.
- A reversed correction looks like **corroboration of the answer you would have guessed**, so it lowers scrutiny at exactly the moment scrutiny is needed.

The repo's own artifact history is the tell: if someone bothered to file an issue and amend six documents to establish X, then "not X" is the position the world defaults to, and every fresh agent will arrive carrying it.

## Solution

**When a subagent makes a claim in a domain where this repo maintains a governing register or corpus, grep that register for the governing cell before accepting the claim.**

Registers that govern in this repo:

| Domain | Governing artifact |
|---|---|
| Data protection / transfers / lawful basis | `knowledge-base/legal/article-30-register.md` (per-PA cells) |
| Architecture decisions | `knowledge-base/engineering/architecture/decisions/` |
| Executed counterparty agreements | `knowledge-base/legal/*-register.md` |
| Encryption posture exceptions | `scripts/encryption-posture-ledger.json` |

Concretely, the check that caught it:

```bash
grep -n 'Third-country transfers' knowledge-base/legal/article-30-register.md
```

The cell's own text — "placement hint, not a jurisdiction" — settles it in one read, and it also carries the `[2026-08-20 DIVERGENCE DISCHARGED (#7624)]` audit block that names the error class explicitly.

### Corollary — a verbatim-looking quote is a claim to grep, not a citation to trust

The `repo-research-analyst` in the same session presented this as PA-7 §(c):

> "Corporate CLA additionally captures authorised signatory name and corporate email address"

Grepping the string returned **zero hits**. The actual text is "For Corporate CLA: signatory name + corporate email + corporate identity." The substance survived; the wording was reconstructed and presented in a table styled as extraction.

Detection is one command — grep the quoted string itself:

```bash
grep -n 'authorised signatory' knowledge-base/legal/article-30-register.md   # 0 hits
```

A second tell from the same report: it gave **two different paths for the same file** (`apps/web-platform/scripts/cla-evidence/build-bypass.ts` and a non-existent `cla-backfill-evidence/build-bypass.ts`). Internal inconsistency within a single agent report is a reliable signal that at least one branch was inferred rather than read.

## Key Insight

**Verify a subagent's claim against the artifact that governs it, not against your sense of whether it sounds right — and treat a claim that confirms the intuitive answer as needing *more* checking, not less, in any domain where the repo has published a correction.**

A quoted string is the cheapest possible verification target: grep it. If it does not appear verbatim, the agent reconstructed it, and everything else in that table is now suspect.

## Prevention

- Before accepting a domain claim, identify the governing register and read its cell. Registers carry dated `DIVERGENCE`/`CORRECTED` audit blocks naming exactly this error class — they are written for this reader.
- Grep every quoted string an agent presents as verbatim. Zero hits = reconstruction.
- Treat internal inconsistency inside one agent report (two paths for one file, two numbers for one count) as grounds to re-derive every fact in it.
- Where an agent's claim would *remove* scope or *relax* a constraint, verify before acting — a relaxation leaves no artifact behind to review later.

## Session Errors

1. **learnings-researcher reversed a landed corpus correction** ("WEUR ⇒ no outbound transfer"). Recovery: read PA-7 §(e) directly; claim not propagated. Prevention: the governing-register check above.
2. **learnings-researcher asserted Art. 9 covers signatory name/title/email.** Recovery: Art. 9's category list is closed; the CLO independently assessed every field under Art. 6(1)(f). Prevention: same class as #1 — check the closed list, not the plausibility.
3. **repo-research-analyst presented a reconstructed quote as verbatim PA-7 §(c) text.** Recovery: grepped the quoted string, got zero hits, pulled the real cell. Prevention: grep quoted strings.
4. **repo-research-analyst gave two mutually inconsistent paths for one parser.** Recovery: `git ls-files | grep build-bypass` resolved it. Prevention: internal inconsistency ⇒ re-derive.
5. **`knowledge-base/product/roadmap.md` fails `markdown-lint` on `main`,** so the pre-commit hook blocks *any* commit staging it — the CPO's recommended roadmap row could not land. Recovery: reverted the roadmap change, filed **#7832**, carried the row text in the spec's Sequencing section so it is not lost. Prevention: #7832; note the file is written by a scheduled cron (`roadmap-reconcile.sh`, CPO weekly review), so a lint failure there is a latent wedge that will either block the cron path or push it to `--no-verify`.
6. **`markdownlint-cli2 --fix` damaged real prose.** It cleared an MD037 false positive on `roadmap.md` line 74 by deleting a legitimate space, rendering `All-in burn**$643.24/mo**`. The markers were balanced and correctly paired (6 markers, 3 pairs). Recovery: restored the space, reverted the file. Prevention: read an autofixer's **character-level** diff before committing it — `git diff -U0 <file>` piped through a `difflib` opcode dump makes single-character deletions visible where a normal diff does not.
7. **`git stash list` tripped the never-stash-in-worktrees hook** (one-off). The hook matched on `git stash` regardless of the read-only `list` subcommand. Recovery: used `git show main:<path>` instead. Not worth a rule change — the hook is correct to be conservative and the alternative was one command away.
8. **My own new files failed MD034 (bare URLs) on the first commit attempt** (one-off). Recovery: wrapped emails/URLs in backticks or angle brackets. Prevention: none warranted; the gate caught it immediately and cheaply.
9. **`git checkout -- <path>` restored from the index, not HEAD** (one-off), leaving the staged change in place. Recovery: `git checkout HEAD -- <path>`.
10. **awk byte-offsets do not match markdownlint character-columns** on lines containing multi-byte characters (one-off), sending me to the wrong part of the line twice. Recovery: indexed with Python on a decoded string.

## Related

- `knowledge-base/project/brainstorms/2026-09-04-ccla-signing-mechanism-brainstorm.md` — the session
- `knowledge-base/legal/article-30-register.md` PA-7 §(e) — the governing cell
- #7624 — the correction the agent reversed; #7670 — the still-open importer-identity vs byte-location divergence
- #7832 — the roadmap lint blocker
