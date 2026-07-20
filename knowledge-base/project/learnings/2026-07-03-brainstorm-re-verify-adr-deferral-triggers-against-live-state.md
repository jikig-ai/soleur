# Learning: An ADR's "deferred/blocked" label goes stale — re-verify each deferral trigger against live state

## Problem

`/soleur:go #5933` routed to brainstorm for a 4-item infra tracker. A same-day governing ADR (ADR-082, "Adopting", 2026-07-03) already recorded the full design for all four items and labeled three of them **deferred/blocked**. Trusting those labels would have produced one of two wrong outcomes: re-deriving an already-decided design, or re-confirming a "blocked" status that had silently cleared.

Three concrete drifts, all invisible if you read the ADR/issue prose without re-checking live state:

1. **Item 3 had already shipped** via PR #5945 — merged with "**Ref** #5933" (not "Closes"), so the issue stayed OPEN and its checkbox still read unchecked. The issue body listed it as a gap.
2. **The cited blocker was the wrong issue.** Both the issue body and ADR-082 said the work "blocks #5887" and called #5887 "the operator cutover." #5887 was actually a **CLOSED** Terraform `moved`-block CI fix. The real web-2 provisioning cutover is **#5274 Phase 3.D** (OPEN) — discoverable only by reading `dns.tf:4`, which names it.
3. **A deferral trigger had cleared.** ADR-082 deferred Item 1 *solely* because `apply-web-platform-infra.yml` was RED (the #5887 `moved`-block breakage) — a new `cloudflare_record` couldn't auto-apply. #5887 was since fixed and the pipeline's last two `main` runs were green. The ADR still said "deferred, blocked on #5887." Item 1 (web-1 portion) was in fact shippable now.

## Solution

Before accepting any "deferred/blocked/after #N" framing from a governing ADR or issue body, read the **deferral rationale** (not just the label) and re-verify each cited trigger against **live** state:

- `gh pr list --state all --search "<N> in:body,title"` — did a sibling PR already ship an item? (Watch for "Ref #N" merges that leave the issue open.)
- `gh issue view <N> --json state,title` — is the cited blocker actually the thing the prose claims, and is it still open?
- `gh run list --workflow=<apply>.yml --limit 6` — if the deferral reason is "pipeline RED / CI failing", is it still red *now*?
- Grep the IaC/source for the real cross-reference (`dns.tf:4` named #5274, correcting the issue's #5887 mis-citation).

When a same-day ADR already contains the accepted design, the brainstorm's job is **certify-and-scope**, not **explore-and-derive**: certify which deferral triggers have cleared, surface the ADR extension the operator wants (here: dual-path cosign verify), and hand a certification-flavored spec to `soleur:plan`.

## Key Insight

An ADR records what was true *when written*. Its "deferred because X" clauses are the most perishable part — X (a red pipeline, an open blocker, an unshipped sibling) routinely flips within hours on a fast repo. Read the **reason** behind every deferral label and re-run the exact check that reason implies against live CI/issue/PR state. A "deferred" label re-verified is worth more than a design re-derived.

## Session Errors

1. **`git grep` from the bare-repo root without a tree-ish** — `fatal: this operation must be run in a work tree`. Recovery: added the `main` ref (`git grep <pat> main -- <path>`). Prevention: already covered by `hr-when-in-a-worktree-never-read-from-bare`; when premise-grepping before a worktree exists, always pass an explicit ref. One-off (self-corrected, rule-covered).

## Tags
category: workflow-patterns
module: brainstorm
related: ADR-082, #5933, #5274, #5945, 2026-05-21-brainstorm-premise-verification-call-site-granularity-and-adr-mutability.md, 2026-05-29-brainstorm-read-adr-alternatives-considered-before-proposing-reversal.md
