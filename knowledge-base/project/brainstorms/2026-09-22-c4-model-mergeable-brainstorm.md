---
date: 2026-09-22
topic: c4-model-mergeable
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Make model.likec4.json mergeable, and close out rule-metrics.json

## What We're Building

`knowledge-base/engineering/architecture/diagrams/model.likec4.json` is committed on purpose
(ADR-235 classes it as a PRODUCT: the web viewer fetches the committed blob from GitHub on the
request path). Today it is 1,133,281 bytes on one line, so any two PRs that regenerate it
conflict, and GitHub's server-side merge reports DIRTY. The regenerate-on-conflict resolver
only runs in local paths, so every affected PR needs a local resync.

We change the artifact's canonical on-disk format so git can merge it whenever the
underlying changes don't actually collide:

1. Parse likec4's export, set every `views[*].hash` to `""`, re-serialize with one JSON value
   per line and no indentation, trailing newline.
2. One dependency-free Node module does this, used by BOTH writers
   (`scripts/regenerate-c4-model.sh` and `apps/web-platform/server/c4-render.ts`), so the repo
   and the app emit byte-identical files.
3. Conflicts that remain are true overlaps and keep the existing regenerate-on-conflict path.

## Measurements (2026-09-22, origin/main 69b08a4ee)

Replay harness: `knowledge-base/project/specs/feat-c4-model-mergeable/replay/`. For each pair
(A, B) of main commits touching `.c4` sources at gaps 1-5: base = A^, side A = A, side B =
B's source diff re-applied onto A^. Each side is rendered with `likec4@1.50.0`, the artifact is
3-way merged with `git merge-file`, and a clean result is compared against a fresh render of
the merged sources.

| Format | Clean and correct | Conflict | Clean but wrong |
|---|---|---|---|
| raw (today) | 0 / 105 | 105 | 0 |
| indent 2, hash kept (sorted or not) | 4 / 105 | 101 | 0 |
| indent 2, hash blanked | 71 / 105 | 34 | 0 |
| indent 0, hash blanked (chosen) | 36 / 51 (gap 1-2 subset; identical to indent 2 on every pair) | 15 | 0 |

- **The hash is the whole story.** Without blanking, line-oriented output barely helps: in the
  common case the only JSON leaf both sides change is some shared view's `hash`
  (`views.containers` is touched by nearly every model edit).
- **Residual conflicts are real.** Every one of the 34 has a leaf both sides set to different
  values: Graphviz coordinates in a shared view both sides relaid out, or one relation's title.
  No text format can merge those correctly, so conflict is the right answer there. These pairs
  are the acceptance test's positive control (their sources merge clean, the artifact must
  still conflict).
- **No source-level conflict** occurred in 105 real pairs, so the source-conflict control has to
  pair a real commit with a crafted edit to the same source line.
- **`views.*.hash`** is an `ohash` SHA-256 of the pre-layout computed view. Nothing in
  `@likec4/diagram`, `@likec4/core` `LikeC4Model`, or this repo reads it. Only the likec4
  CLI's manual-layout drift check does, and that computes from the sources. Measured: the CLI's
  export is byte-identical when a blank-hash artifact sits in its workspace. The key stays
  (value `""`) because the type `ViewWithHash` declares it.
- **Size:** indent 0 with blank hashes is 1,210,507 B, 28.9% of `MAX_C4_BYTES` (4 MiB), leaving
  3.46x room to grow (today 3.70x). Indent 2 would be 1,796,697 B (2.33x).
- **Exposure:** 27 of 121 main commits in the prior 7 days changed the artifact, all alongside a
  `.c4` source.

## Why This Approach

- **A (line-oriented + blank hash): chosen.** Measured win in both directions: 0/105 today,
  71/105 with the change, 0 false-clean merges. CI's byte-exact freshness test
  (`c4-model-freshness.test.sh`, runs on the PR merge ref) still backstops any textual merge
  that isn't a faithful render.
- **B (untrack, generate at build/deploy): rejected.** Premise re-checked: the viewer
  (`app/api/kb/c4/project/route.ts`) lists and fetches the committed blob from GitHub per
  request, and the app commits the file into customer repos. Untracking would need a
  render-on-read path in the product, a much larger change.
- **C (per-view split): rejected.** Measured no gain over A: the per-section merge of the same
  pairs conflicts on the same shared views, again mostly on `hash`.
- **D (auto-resync DIRTY PRs): rejected** as the primary fix (symptom only). The remaining 32%
  still go through the existing local resolver.

## Key Decisions

| Decision | Choice | Why |
|---|---|---|
| Format | `JSON.stringify(o, null, 1)` with leading spaces stripped, `\n` at end | Line per value merges like indent 2 (measured) at +7% bytes instead of +59%. Stripping is safe: a JSON string cannot hold a raw newline |
| Key order | Keep likec4's order (no sort) | Sorting gave no extra merges; likec4 output is already deterministic |
| `views[*].hash` | Set to `""` | Only cross-side overlap in the common case; no runtime reader; key kept for the type |
| Serializer | One Node module at `apps/web-platform/lib/` | The Docker build copies only `apps/web-platform`; the bash writer calls it with `node`. jq never writes the artifact (it reformats numbers) |
| Customer repos | Same format, no migration | Every write already rewrites the whole file; old files convert on their next edit. All readers `JSON.parse` |
| Residual conflicts | Keep `resolve-regenerable-conflicts.sh` | They are real overlaps; regenerating from merged sources is the only correct answer |
| GitHub diff noise | `.gitattributes`: `linguist-generated=true` for the artifact | Collapses a ~54k-line file in PR diffs |
| ADR | Amend ADR-235 (and note on ADR-050) | ADR-235 said these conflicts were "rare"; measured 27/121 commits |
| `rule-metrics.json` | Nothing to build | See below |

## rule-metrics.json (closed out)

- Not tracked on `main`; gitignored (`.gitignore:90`). Last commit touching it is #8384's
  deletion. Its only writer, `scripts/rule-metrics-aggregate.sh`, writes to that ignored path;
  no workflow or hook force-adds it (`git add -f` grep: no hits).
- 37 of 50 open PRs still carry it, all opened before #8384 merged
  (2026-09-21 19:17 UTC). Only **#8329** modifies it relative to its merge base. The other
  36 have it unchanged, so git resolves main's deletion cleanly. #8329 is the one live
  modify/delete conflict, and it already has the `git rm --cached` comment.

## Open Questions

- The 32% residual comes from storing Graphviz coordinates. A layout-free artifact (the browser
  runs the layout) would remove it, but that is a product-rendering change. Deferred as a
  follow-up issue (#8541).
- Customers who also run `likec4 export json` themselves will get the raw one-line format,
  so the file alternates between formats. This is accepted: the app never byte-compares it.

## User-Brand Impact

- **Artifact:** the compiled C4 model `model.likec4.json`, written by the repo's lefthook
  regenerator and by the web app's diagram editor into customer workspace repos.
- **Vector:** a serializer divergence between the two writers, or a reader that rejects the new
  layout, would leave a customer's diagram stale or unrenderable with no error surfaced.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** CTO chose A. Constraints: the module lives in `apps/web-platform/lib/`; only Node
serializes; canonicalize in `c4-render.ts` after the element check and update its "never
re-stringified" comments; add a test that both writers produce identical bytes, plus a
`LikeC4Model.create` blank-hash test; add `linguist-generated`.

### Product

**Summary:** CPO accepts the one-time reformat in customer repos, with a changelog line and no
user notice. The concern about blanking the hash for customers is answered by the CLI
measurement above. Format alternation when a customer runs the CLI themselves is accepted as
a known limit.

### Legal

**Summary:** CLO: no legal surface. The change is formatting only, with no new data, recipient
or write surface. Needs another look only if non-derived content ever enters the file.

## Session Errors

- My first mergeability measurement read an interim results file mid-run (51 of 105 rows).
  The final numbers above come from the finished file.
