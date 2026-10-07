# Decision challenges: feat-one-shot-argv-bearer-sweep-tier3

Persisted for `ship` to render and file (ADR-084). Nothing here changes the operator's stated direction;
these are taste calls the plan made that review should confirm.

## 2026-10-07 plan phase

1. **Whole-section extraction of the review skill's Defect Classes list (taste).** The brief said to
   extract "a block". The plan extracts the whole 250,787-byte section because bold-lead clustering found
   only small domain clusters (4.4 KB of SQL/RLS, 1.8 KB of React) and keyword clustering mixes
   examples with subjects. The cost is a behaviour change: the list moves from ambient context to a
   read directive at the Findings Synthesis step. Alternative if review objects: a smaller, hand-selected
   cluster of at least 5 KB by reading the bullets, accepting more editorial risk. The plan's recommended
   default stands.
2. **Item 4 bundled in S1 (taste).** The review extraction is independent of the argv sweep. It rides in
   S1 because the brief lists it as one task and it touches no shared file; Phase 3 is a separate commit
   group so it can become its own PR if review asks.
3. **No "guard runs before curl" lint check (taste, decided in D1).** Chosen against because ordering is
   undecidable statically (the lint's own Rule A docstring); pinned by battery mutation rows instead.
4. **`--changed` stays `*.sh`-only (taste, decided in D1).** YAML is enforced by the repo-wide equality
   run and by explicit paths, so unrelated edits to baselined workflows are not forced to remediate.
5. **Shared helper for workflow YAML (taste, S3).** `scripts/lib/bearer-curl.sh` is preferred to inline
   conversion for byte-budget and single-guard reasons; host-baked files keep the inline form.
6. **S1 sequencing against PR #9632.** If #9632 merges first, S1 rebases and regenerates baseline E; if
   S1 merges first, #9632 rebases. Either order is acceptable; the plan does not wait for it.
