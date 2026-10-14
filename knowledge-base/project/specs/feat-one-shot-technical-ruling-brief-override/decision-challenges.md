# Decision challenges (plan, headless)

Technical rulings made during planning of `feat-one-shot-technical-ruling-brief-override`. Every technical item was
ruled by the CTO agent in the planning run (the Agent tool was available); none was put to the operator. The
operator's own words in this incident ("ask the CTO not me") already classify the underlying shape as technical.
Full rule: `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md`.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| H1 extend the pre-ask hook for the "who owns / run as new pipeline vs record not fixed" shape, and where the cue lives | technical | Ruled by CTO agent, 2026-10-14: add a narrow `ask` cue as a new lib group `shared+ask` (constants `TFC_ASK_*`, never in `shared`, never inline in the hook) with the operator-vocabulary and money vetoes and the permission exemption kept, keep `scope` in `AUTHORITY_RE`; residual: the bare "is the scope limited to item 1" phrasing stays allowed - the cue is lexical and a paraphrase slips through; a measured false-deny on a real operator ask flips this to skill text only |
| H2 where and how the skill text states the brief-wording trigger, and how the scope-worded disposition shape is classified | technical | Ruled by CTO agent, 2026-10-14: edit the Sharp Edge in `commands/go.md` (the authority) plus a pointer sentence in `skills/go/SKILL.md`; extend reference section 5 so a brief's "ask the operator" / "OPEN DECISION" wording is itself the CTO trigger; a scope question is the operator's only when it asks to drop, defer or add something the operator asked for, routing or ownership of an already-named gap is technical |
| H3 what the learning's Key Insight and Prevention rule are | technical | Ruled by CTO agent, 2026-10-14: the brief wording is the third carrier (after the artifact pipeline and the closing message) and the hook cannot see a brief; one Prevention rule: treat the brief's "ask the operator" wording on a technical fork as the trigger to spawn the CTO and ask the operator only the authorization |
| H1b keep or cut the ownership-only (`who owns ...`) arm of the new cue | technical | Ruled by CTO agent, 2026-10-14: cut it (three plan reviewers measured a false deny of an assignment ask, "Who should own the remaining items, Alice or Bob?"); the cue is the route-AND-record pair only; ownership-only phrasings become the stated residual covered by skill text. Dissent: a ledger sample showing PR-ownership phrasing as the dominant carrier flips this, adding only the artifact-subject alternative |
| H1c where the cue sits in the lib and whether it keeps a money conjunct | technical | Ruled by CTO agent, 2026-10-14: inside the existing weak-cue block on the last sentence of each interrogative segment, guarded by the `ask` group, before the permission exemption; the money conjunct is dropped (the operator-vocabulary veto already holds the money words that matter) |
| H4 keep the operator-only list closed and unchanged | operator (scope) | Keep the closed list `money, scope, priority, schedule, irreversible, production-mutating, legal-risk, brand` exactly as the operator's brief states; no category moves |
| H5 authorization to merge the PR | operator (production-mutating) | Authorise merging the fix PR once review evidence is recorded via `emit-review-trailer.sh --findings <n>` (split from H1 to H3) |
| H6 wording of the new deny lead | taste | |
| H7 content-pin scope in `components.test.ts` (plan-review: DHH and simplicity would delete it, the CTO review would keep a light pin) | taste | Kept a light pin: three content anchors in one test plus one token in the existing inline-copy list; the four-file Guard 2 with a block-hash re-run was dropped. Operator may cut it entirely |
| H8 committed mutants for every Guard Contract row (plan-review: DHH and simplicity would commit only the retarget and the closing-carrier mutant) | taste | Kept the three that need the closing suite's tree machinery (group ignored, dispatch dead, Stop carrier widened) plus the G2-2 retarget; the three cue-internal rows are run once by hand and recorded in the PR body |

The one-shot inline-copy clause and the ADR-084 addendum are mechanical consequences of H1 and H2 (de minimis bound: no durable contract of their own), so they carry no row.
