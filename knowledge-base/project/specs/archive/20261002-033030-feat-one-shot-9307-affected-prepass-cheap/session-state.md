# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-01-feat-cheap-affected-prepass-and-pr1-residuals-plan.md
- Status: recovered from partial-artifact (planning subagent stopped when the prior session ended; plan body incl. deepen-plan Enhancement Summary was on disk)
- Plan artifact: recovered (selector=branch)

### Decisions
- Split per the operator's "unless review says split" clause: PR-A (byte-identical speedup), PR-B (re-demotion, recorder, ratchet breadth, minting fixes), PR-C (runner leaf, REPO_ROOT idiom, heavy batteries). This run implements PR-A.
- Identity-preserving series measures 4.0x and 4.4 (3.1 at the minimum, 280 s to 89 s, because the base side was noisy)x CPU (two probes, interleaved), not 10x; the 10x route (runner as closure leaf) narrows selection and is PR-C.
- Byte-identity contract: row-set comparison with a declared added-label list.
