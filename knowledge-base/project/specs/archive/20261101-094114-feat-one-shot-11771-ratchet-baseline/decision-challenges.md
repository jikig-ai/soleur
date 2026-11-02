# Decision Challenges — feat-one-shot-11771-ratchet-baseline

| Item | Class | Ruling |
|------|-------|--------|
| R1 home-census pair (home-census-trigger.test.sh → CLO audit md): declare edge vs accept rows — SUT reads the file at runtime (`git show` at home-census-trigger.sh:246) but the test stubs git | technical | Ruled by CTO agent, 2026-11-01: declare the edge — the pair is not a bare-naming mention: the suite executes the SUT whose exercised code path opens the path's content at runtime, and the test pins that contract; ambiguity resolves to the stricter default (declare), edge cost ~zero (1 commit/90d) |
| R2 stale accept row disposition + betterstack pair class | technical | Ruled by CTO agent, 2026-11-01: accept row confirmed (mention — zero trusted-verdict hits in suite+SUT); correct the stale row in place; sibling rows' cited lines `:311→:318`, `:347→:354` updated as cosmetic honesty |
| #8800 overlap (census-sandbox write-through) | technical | acknowledge — body only names a planned file; builder semantics are a different concern with its own issue/re-eval date |
| threshold `none` (User-Brand) | taste | threshold: none — CI-selection machinery, no user-facing surface; challengeable |
