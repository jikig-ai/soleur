---
title: Graphify evaluation — KB decline, code-axis probe
date: 2026-08-03
lane: cross-domain
brand_survival_threshold: single-user incident
status: decided — decline for KB (#4206); narrow code-axis probe on #5708
brainstorm: knowledge-base/project/brainstorms/2026-08-03-graphify-eval-brainstorm.md
external_tool: https://github.com/Graphify-Labs/graphify
branch: feat-graphify-eval
pr: 7205
issues: [4206, 5708]
---

# Spec: Graphify evaluation outcome

## Problem Statement

Soleur's `kb-search` Stage 3 (#4206) has been an open, unbuilt ADR-trigger since
2026-05-20. Heavy-paraphrase recall over the learnings corpus sits at R@5 ≈ 0.27
(kb-search) / 0.30 (grep) against a pre-committed close gate of ≥ 0.40, and the
2026-05-20 diagnostic established the gap is a **ceiling of keyword methods**, not a
corpus artifact. Graphify was proposed as a candidate implementation, and separately as
a possible improvement to code-base understanding and token efficiency.

## Goals

- **G1.** Settle whether Graphify can serve as the #4206 Stage-3 retriever, on evidence.
- **G2.** Record the reason durably enough that it survives the next candidate tool.
- **G3.** Determine whether the code base — Graphify's actual competency — warrants a
  time-boxed probe under the existing #5708 track.

## Non-Goals

- **NG1.** Adopting Graphify for Soleur Users' knowledge bases or repos (Axis B stays
  deferred on #5708 with all prior gates intact).
- **NG2.** Building the Stage-3 embeddings implementation. #4206's original ADR framing
  (OpenAI vs Voyage vs local bge/nomic) is untouched by this work.
- **NG3.** Vendoring or redistributing any Graphify source into `plugins/soleur/`.
- **NG4.** Running the ~50-minute retrieval bench for the KB question — the mechanism
  settles it without a measurement.

## Findings (evaluation outcome)

- **FR1 — KB verdict: DECLINE.** `graphify/extractors/markdown.py` (194 lines) emits a
  file node, heading nodes, `contains` edges and `references` edges for explicit links
  only; it returns `input_tokens: 0` and never reads paragraph text.
- **FR2 — Corpus evidence.** 2,085 learnings, **~92% prose** (177,530 lines total, 11,020
  inside code blocks); 354 cross-doc `.md` links across 152 files, 753 wikilinks, for
  502 of 2,085 files (24%) carrying any extractor-capturable link; heading population
  dominated by ~5 template strings, `## Problem` alone in ~90% of files.
- **FR3 — Mechanism is disqualifying.** The deterministic path searches a strict subset
  of what the grep arm already searches (full text) at R@5(heavy) 0.2966. It cannot beat
  a superset of its own signal.
- **FR4 — The semantic path is LLM extraction, and it repeats a failed experiment.** Per
  the vendor's `skill.md`, the no-LLM guarantee covers **code only**; docs, papers and
  images go through semantic extraction using **Gemini** when `GEMINI_API_KEY`/
  `GOOGLE_API_KEY` is set, "otherwise the host agent itself is the LLM." Stage 2's LLM
  pre-pass regressed heavy recall by −0.0238 per the canonical diagnostic (#4206's table
  says −0.0381 on a 1,169-file corpus; see the re-baseline requirement in AC1).
- **FR5 — Code axis is open.** ~3,200 tracked code files (1,599 `.ts`, 736 `.sh`,
  480 `.tsx`, 283 `.sql`, 69 `.tf`) match Graphify's real extractors.

## Technical Requirements (code-axis probe only, if run)

- **TR1 — Egress proof (hard gate).** Deny-all-egress netns run with host packet
  capture. PASS = zero non-loopback packets **and** a successful run; a fail-closed run
  proves nothing.
- **TR2 — Supply-chain pinning (hard gate).** Hash-pinned `graphifyy==0.9.32` with a
  pinned `--index-url` and no extra-index. CI assertion positive on both sides:
  `graphifyy` present at the pinned version **and** `graphify` (single-y) absent from
  the resolved set.
- **TR3 — Time-box.** Probe is scoped to the operator's machine and this repo only. Any
  result that requires new always-on infrastructure ends the probe rather than expanding it.
- **TR4 — Worktree maintenance is in scope.** `watch.py` is single-working-tree; the
  probe must state the per-tree regeneration cost across the current 20 worktrees, or
  explicitly scope to one tree.
- **TR5 — No `.mcp.json` entry during the probe.** The bench harness calls retrievers as
  shell functions; an MCP stdio server is not callable from it and is not needed to
  measure token deltas via the tool's own `benchmark.py`.

## Acceptance Criteria

- **AC1.** #4206 records Graphify as eliminated, with the mechanism reason and the
  measured corpus evidence, and proceeds to (or closes in favour of) its original
  embeddings ADR. It also records that the bench baseline is stale (1,163-file corpus vs
  2,085 live) and that three Stage-2 R@5 number sets are in circulation, so **any future
  Stage-3 evaluation re-baselines first** and cites the auto-emitted diagnostic rather
  than an issue body's transcription of it.
- **AC2.** #5708 records the code-axis finding so the Axis-A probe, if picked up,
  inherits TR1–TR5 rather than re-deriving them.
- **AC3.** No fourth KB-retrieval candidate is evaluated absent a user-side signal
  (a validation interview naming retrieval, or a logged operator incident).
