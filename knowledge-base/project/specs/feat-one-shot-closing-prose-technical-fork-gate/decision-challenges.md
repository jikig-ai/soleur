# Decision challenges: feat-one-shot-closing-prose-technical-fork-gate

Persisted by the headless plan phase (ADR-084 channel). `ship` Phase 6 renders this into the PR body and files an
`action-required` issue for operator-class rows only. Technical rows were ruled by the CTO agent and are not for the operator.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| T1 where the closing-prose gate lives: repo-local `.claude/hooks` Stop entry versus the shipped plugin | technical | Ruled by CTO agent, 2026-10-12: repo-local; graduate to the plugin only together with the pre-ask gate under #10056 after 30 days in service, 10 recorded firings, zero founder-reported wrongful blocks and a clean sample re-run - the plugin route needs a web opt-out and the web-parity test, and third-party vocabularies raise the false-positive risk |
| T2 shared cue lib structure, new cues and veto split | technical | Ruled by CTO agent, 2026-10-12: one lib with SHARED (byte-identical) and CLOSING groups as a function argument; BUSINESS/ACTION veto split with CLOSING cues vetoed by BUSINESS only; strong cues CL1 sufficiency, CL2 design, CL3 ordering; one verdict function owns extraction, vetoes and the permission exemption - the pre-ask hook is not widened |
| T3 closing window and sentence scoping | technical | Ruled by CTO agent, 2026-10-12: last 1500 bytes of fence-stripped prose, judge only `?`-terminated sentences each alone, lists with no `?` are not judged - the stricter option that blocks less |
| T4 escape vocabulary and block-reason wording | technical | Ruled by CTO agent, 2026-10-12: honour `<stop>` markup, a plain `Operator-only (category):` sentence and a final-sentence `Paused:`/`Blocked:` label; reason has no angle-bracket text - the model echoes markup it is taught |
| T5 false-positive budget and measurement method | technical | Ruled by CTO agent, 2026-10-12: newest 300 closings with a `?`, counts only, zero operator-class or ambiguous hits, over 15% blocked is too broad, two failed narrowing rounds drop the cue - a wrongly blocked closing is the worse failure |
| T6 skill pointer lines | technical | Ruled by CTO agent, 2026-10-12: pointers in `one-shot` and `go` only, naming the closing message as the carrier; none in `plan` or `work`; no trimming of `work/SKILL.md` line 286 - the rule prose and link already exist in all four skills |
| S1 pointer lines in `plan` and `work` (the brief names all four skills) | taste | |
| S2 escape scope of `Operator-only (category):` (own sentence plus the next unit) versus the CTO's whole-window wording | taste | |
| T7 reconciliation with R3, #10057 and #10056 | technical | Ruled by CTO agent, 2026-10-12: R3 stands for the exact-label arm; close #10057 as superseded, file ONE follow-up for the rule's `[hook-enforced:]` tag, leave #10056 open with the graduation criterion - no `AGENTS.rules.md` edit under ADR-092 |
| T8 most likely failure and the cheapest cut | technical | Ruled by CTO agent, 2026-10-12: recall decay; do not broaden preemptively, use the miss, cue, fixture loop; keep the CLOSING group separate so pre-ask is not widened |

## S1 — Model dissent (class `taste`): the operator's stated direction was followed against the CTO's two-skill form

No operator question is asked: the operator's own brief is the direction, so following it is not an override and files no issue; the row renders under Model Dissents in the PR body.

1. **Operator direction:** "a short POINTER LINE, not prose, in one-shot (before the Step 8 closing), go, work and plan".
2. **Model/CTO view:** the CTO would cut `plan` and `work`: rule prose and a link to the reference already exist in all four skills and the 2026-10-12 failure
   happened anyway, so the hook carries the property; the `work` pointer also needs a byte-neutral relocation because that skill has 0 bytes of headroom.
3. **Default taken:** the operator's direction (four pointer lines), because dropping a stated scope item is a NEVER-Mechanical class.
4. **Cost of the default:** about 600 bytes across `one-shot` (1640 headroom), `plan` (1087 headroom) and `go.md` (no ceiling), plus one relocation in `work`.
5. **Reversal:** delete the `plan` and `work` lines; nothing else depends on them.

## S2 — Model dissent (class `taste`): escape scope

The CTO ruled the three escapes honoured "anywhere in the closing window" (the first two) or as the final sentence. Deepen-plan's spec-flow pass showed that a whole-window `Operator-only (category): ...`
lets one appended sentence pass unrelated technical questions (the silent self-label path). Default taken: `<stop>` forms and a final-sentence `Paused:`/`Blocked:` stay whole-window (the brief's fixture and
the plugin hook's own escape require it); `Operator-only (category):` governs only its own sentence and the next `?` unit. This blocks MORE than the CTO's wording for that one form. Reversal: widen the scope
in the hook's escape arm and drop row E4 and mutant G1-10; nothing else depends on it. Not an operator question: it is technical.

## Note on scope not taken

`brainstorm` carries no link to the delegation reference and is where "which approach?" prose is likeliest, but the brief names one-shot, go, work and plan only; recorded as an omission, not added.
