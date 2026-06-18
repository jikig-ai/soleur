# Architecture Diagrams — LikeC4 C4 Model

This directory holds **one** consolidated [LikeC4](https://likec4.dev/) C4 model
and the page that renders it. The Mermaid → LikeC4 migration (PR #4883) replaced
three inline-Mermaid `.md` files with the file set below — a model source split
across `.c4` files, a compiled JSON, and a single interactive view page. **Nothing
here is redundant**; each file has a distinct role, described below. The view page
and the compiled JSON are load-bearing — do not delete the JSON or re-split the
page without cause (see Sharp Edges).

The three C4 layers you remember from the Mermaid era did not multiply — they now
live as three **views** over a single model, surfaced through one interactive page
(`c4-model.md`) whose embedded diagram drills down Context → Containers →
Components in place. The extra `.c4` files are the model *source* that Mermaid used
to inline into each `.md`.

## File taxonomy

| File | Kind | Role |
|---|---|---|
| `spec.c4` | LikeC4 DSL (source) | Declares element KINDS once (actor / system / container / database / component) and tags. Authored by the `soleur:architecture diagram` skill. |
| `model.c4` | LikeC4 DSL (source) | The consolidated C4 model — **single source of truth**. Every element declared exactly once (≈40 elements, ≈51 relations as of the 2026-06-03 migration; authoritative counts live in `model.likec4.json`). Migrated 1:1 from the former 3 Mermaid diagrams. Nesting creates C4 boundaries. |
| `views.c4` | LikeC4 DSL (source) | One view per C4 level: `context` (L1), `containers` (L2), `components` (L3). Define-once-render-many — the three C4 layers live here as VIEWS, giving clickable drill-down Context → Containers → Components. The C4 "code" level is intentionally excluded per convention. |
| `model.likec4.json` | Compiled artifact (generated) | COMPILED, pre-layouted model **REQUIRED by the web viewer at runtime**. `apps/web-platform/components/kb/c4-diagram.tsx` renders the `@likec4/diagram`-backed diagram from `data.dump` (the `@likec4/diagram` import lives in the sibling `c4-shared.tsx`; the dump is fetched via the KB C4 API); the client libs are pinned WITHOUT the likec4 compiler, so the DSL is compiled at author-time and the JSON is shipped to the browser. **Do NOT hand-edit or delete — regenerate it from the `.c4` sources.** |
| `c4-model.md` | View page (interactive) | The single human-readable page. Embeds the `context` view via a ` ```likec4-view ` fenced block; the diagram drills down in place L1 → L2 → L3 (Context → Containers → Components). Carries per-level `## Notes` (with ADR cross-references) for all three levels. |

(`README.md` — this file — is the directory index, not a LikeC4 view page: it has
no ` ```likec4-view ` block. `.gitkeep` keeps the directory tracked when empty.)

`c4-model.md` consolidates what the Mermaid era split across three pages
(`system-context.md`, `container.md`, `component-plugin.md`): LikeC4's in-place
drill-down makes a single embedded `context` view sufficient to reach all three
levels, so the per-level pages were merged into one. Only the embedded block
changed from ` ```mermaid ` to ` ```likec4-view `; every per-level Note carried
over.

## Authoring workflow

1. Edit the `.c4` sources (`spec.c4` / `model.c4` / `views.c4`) via the
   `soleur:architecture` skill (`architecture diagram` sub-command). Define each
   element once in `model.c4`; scope it per C4 level in `views.c4`.
2. Regeneration of `model.likec4.json` is **automatic on commit** — the
   `c4-model-regenerate` pre-commit hook (`lefthook.yml`) re-renders and
   re-stages it from the edited `.c4` sources, and a CI freshness test
   (`plugins/soleur/test/c4-model-freshness.test.sh`) is the merge-gating
   backstop if the hook is bypassed (`--no-verify`). You normally do **not**
   regenerate by hand. To regenerate ad-hoc (or when committing outside the
   hook), run the pinned, off-tree-validated, idempotent primitive from the repo
   root:

   ```bash
   bash scripts/regenerate-c4-model.sh
   ```

   To validate the source only (without rewriting the artifact):

   ```bash
   cd knowledge-base/engineering/architecture/diagrams
   npx -y likec4@1.50.0 validate .
   ```

   The pinned `1.50.0` MUST match `apps/web-platform/Dockerfile` +
   `package.json` (`@likec4/core` / `@likec4/diagram`), guarded by
   `c4-likec4-version-pin.test.ts`. The script renders off-tree and refuses to
   publish an empty/invalid model, so a broken `.c4` never clobbers the good
   committed artifact.

3. Commit the `.c4` edits; the hook stages the regenerated `model.likec4.json`
   alongside them.
4. **Never hand-edit `model.likec4.json`** — it is a build output; any manual
   change is lost on the next regeneration and can desync the viewer from the
   `.c4` source.

> Comments in `.c4` files are NOT exported into `model.likec4.json`, so a
> comment-only edit does not require regeneration. Any change to the
> `specification` / `model` / `views` bodies DOES.

## Cross-references

- **DSL syntax:** `plugins/soleur/skills/architecture/references/likec4-reference.md`
- **Authoring / render commands:** the `soleur:architecture` skill (`SKILL.md`).
