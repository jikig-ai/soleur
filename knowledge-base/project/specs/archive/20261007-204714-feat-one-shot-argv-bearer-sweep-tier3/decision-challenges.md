# Decision challenges: feat-one-shot-argv-bearer-sweep-tier3

Persisted for `ship` to render and file (ADR-084). Nothing here changes the operator's stated direction;
these are taste calls the plan made that review should confirm.

## 2026-10-07 plan phase

1. **Review skill extraction takes only the migration/RLS cluster (taste).** The first draft moved the
   whole 250,787-byte Defect Classes section behind an unconditional read; the simplicity review
   reversed that (it adds about 60k tokens to every review to fix a 1 KB problem). The plan now moves three
   conditional bullets (4,402 bytes) to `references/defect-classes-migrations.md`, giving about 3 KB of
   headroom. Alternative if review objects: the whole-section move, accepting the read cost.
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
