---
name: architecture
description: "This skill should be used when managing Architecture Decision Records or C4 diagrams."
---

# Architecture as Code

Create, manage, and query Architecture Decision Records (ADRs) and maintain an interactive [LikeC4](https://likec4.dev/) architecture model. ADRs are version-controlled markdown; the C4 model is version-controlled LikeC4 DSL (`.c4`). All artifacts live in `knowledge-base/engineering/architecture/`.

## Sub-commands

| Command | Description |
|---------|-------------|
| `architecture create [title]` | Create a new ADR with the next sequential number |
| `architecture list` | Display all ADRs with status, title, and date |
| `architecture supersede <N> [title]` | Mark ADR-N as superseded and create its replacement |
| `architecture diagram [type]` | Create or update the LikeC4 model and its views (context, container, component) |
| `architecture add-container <id>` | Add a container/database element to the model |
| `architecture add-component <id>` | Add a component element to the model |
| `architecture add-relationship <from> <to>` | Add a relationship between two model elements |
| `architecture render` | Validate the LikeC4 project (`likec4 validate`) and report element/view counts |
| `architecture assess [feature]` | Assess a feature against the NFR register and principles register |
| `architecture principle list` | Display the architecture principles register |

If no sub-command is provided, display the table above and ask which sub-command to run.

## Arguments

`$ARGUMENTS` is parsed for a sub-command and optional parameters:

```text
architecture [sub-command] [arguments...]
```

---

## Phase 0: Prerequisites

Verify the knowledge-base directory exists:

```bash
if [[ ! -d "knowledge-base" ]]; then
  echo "No knowledge-base/ directory found. Create one first or run /soleur:sync."
  # Stop execution
fi
```

Create the architecture directories if they do not exist:

```bash
mkdir -p knowledge-base/engineering/architecture/decisions
mkdir -p knowledge-base/engineering/architecture/diagrams
```

**Branch safety check (defense-in-depth):** Run `git branch --show-current`. If the result is `main` or `master`, abort with: "Error: architecture skill cannot run on main/master. Checkout a feature branch first."

---

## Sub-command: create

Create a new ADR with the next sequential number.

### Steps

1. **Determine next ADR number.** List existing ADRs in `knowledge-base/engineering/architecture/decisions/`:

   ```bash
   ls knowledge-base/engineering/architecture/decisions/ADR-*.md 2>/dev/null | sort -V | tail -1
   ```

   Extract the highest number and increment by 1. If no ADRs exist, start at 001.

2. **Get the title.** If a title was provided in `$ARGUMENTS`, use it. Otherwise, use AskUserQuestion: "What architectural decision are you recording?"

3. **Generate the filename.** Convert the title to kebab-case: `ADR-<NNN>-<kebab-title>.md`

4. **Read the ADR template** from [adr-template.md](./references/adr-template.md). The template now documents two labeled body shapes (terse / rich) under the `## Choosing the shape` section. Read that section before proceeding.

5. **Ask the shape rubric.** Present the 5 triggers from the template's `## Choosing the shape` section and pick between the terse and rich shapes. Use AskUserQuestion with options:

   - "No — terse (3 sections)"
   - "Yes — rich (8 sections)"
   - "Unsure — walk me through each trigger"

   If the contributor picks "Unsure," ask each of the 5 triggers as its own yes/no AskUserQuestion. Compute: any yes → rich, all no → terse.

   **Pipeline mode default.** If running inside `/soleur:one-shot` or any other non-interactive caller (no AskUserQuestion available, only `$ARGUMENTS` context), default to **terse**. Rich-shape ADRs in pipeline mode require the caller to pass `shape: rich` explicitly in `$ARGUMENTS`, or the rubric falls through to terse.

6. **Write the ADR file.** Create `knowledge-base/engineering/architecture/decisions/ADR-<NNN>-<kebab-title>.md` using the chosen shape's body block from the template. Fill in frontmatter:
   - `adr: ADR-<NNN>`
   - `title: <title>`
   - `status: active`
   - `date: <today YYYY-MM-DD>`

7. **Gather context.** Ask the user (or use `$ARGUMENTS` context if running in pipeline). The prompt list branches on the shape chosen in step 5:

   **Terse branch (3 prompts):**

   - **Context:** What motivates this decision?
   - **Decision:** What is the change being made?
   - **Consequences:** What becomes easier or harder?

   **Rich branch (8 prompts):**

   - **Context:** What motivates this decision?
   - **Considered Options:** What alternatives were evaluated? (list with pros/cons and links to tentative C4 model changes)
   - **Decision:** Which option was chosen and why?
   - **Consequences:** What becomes easier or harder?
   - **Cost Impacts:** How much does this change increase or reduce costs? (reference `knowledge-base/operations/expenses.md` for baseline; use "None" if no impact)
   - **NFR Impacts:** Which non-functional requirements are affected? Read [nfr-reference.md](./references/nfr-reference.md) for the assessment checklist and common patterns by decision type. Reference NFR IDs from `knowledge-base/engineering/architecture/nfr-register.md`. Use "None" if no impact.
   - **Principle Alignment:** Which architectural principles does this decision align with or deviate from? Read `knowledge-base/engineering/architecture/principles-register.md` for the register. Reference AP-NNN IDs. Use "None" if no impact.
   - **Diagram:** (optional) Should a LikeC4 diagram be included or updated?

8. **Write the ADR body** with the gathered context. If a diagram was requested (rich branch only), update the consolidated LikeC4 model using [likec4-reference.md](./references/likec4-reference.md) (see the `diagram` sub-command) and embed the relevant view with a ` ```likec4-view ` block.

9. **Announce:** "Created ADR-<NNN>: <title> at `knowledge-base/engineering/architecture/decisions/ADR-<NNN>-<kebab-title>.md`"

---

## Sub-command: list

Display all ADRs with their status, number, title, and date.

### Steps

1. **Scan the decisions directory:**

   ```bash
   ls knowledge-base/engineering/architecture/decisions/ADR-*.md 2>/dev/null
   ```

2. **If no ADRs exist:** Display "No ADRs found. Run `/soleur:architecture create` to create one."

3. **For each ADR file:** Read the YAML frontmatter and extract `adr`, `title`, `status`, `date`.

4. **Display as a table:**

   ```text
   | # | Title | Status | Date |
   |---|-------|--------|------|
   | ADR-001 | Use LikeC4 for diagrams | active | 2026-03-27 |
   | ADR-002 | PWA-first architecture | superseded | 2026-03-20 |
   ```

---

## Sub-command: supersede

Mark an existing ADR as superseded and create its replacement.

### Steps

1. **Parse the ADR number** from `$ARGUMENTS`. If not provided, use AskUserQuestion: "Which ADR number to supersede?"

2. **Find the existing ADR** by matching `ADR-<NNN>-*.md` in `knowledge-base/engineering/architecture/decisions/`.

3. **If not found:** Display "ADR-<NNN> not found." and stop.

4. **If already superseded:** Display "ADR-<NNN> is already superseded by ADR-<M>." and stop.

5. **Get the replacement title.** If provided in `$ARGUMENTS`, use it. Otherwise, use AskUserQuestion: "What is the title of the replacement decision?"

6. **Create the replacement ADR** using the `create` sub-command flow (next sequential number). Add `supersedes: ADR-<NNN>` to the YAML frontmatter.

7. **Update the original ADR.** Read the file and update:
   - `status: superseded`
   - Add `superseded-by: ADR-<NEW>`

8. **Announce:** "ADR-<NNN> superseded by ADR-<NEW>: <title>"

---

## Sub-command: diagram

Create or update the canonical **LikeC4** model. Soleur uses ONE consolidated
model — every element is declared once and the views scope it to each C4 level
with clickable drill-down (Context → Container → Component). The model is
rendered interactively in the web Knowledge Base viewer; static Mermaid C4 is no
longer emitted.

**Read [likec4-reference.md](./references/likec4-reference.md) now** for the
complete LikeC4 DSL syntax before editing any model.

### Project layout

> **`.c4` edits are not gated for this workflow.** The `c4-edit` runtime flag
> (commit `3c8849655`) gates ONLY direct end-user edits in the in-browser webapp
> editor (`PUT /api/kb/c4`, default OFF). It does **not** gate a workflow: Concierge
> and the Claude Code plugin terminal are equally-trusted agent contexts that edit
> the `.c4` files on the filesystem (Edit/Write) and commit them via this skill —
> they never route through the webapp endpoint. Edit `.c4` directly; do not defer a
> model change to "ask the Concierge."

The model lives as a LikeC4 project under
`knowledge-base/engineering/architecture/diagrams/`:

- `spec.c4` — `specification` block: element kinds (actor, system, container, database, component) and tags.
- `model.c4` — `model` block: every element (nested systems → containers → components) and every relationship, declared once.
- `views.c4` — `views` block: one `view <id> [of <element>]` per C4 level. `view <id> of <element>` gives the parent element an automatic drill-down button.
- `<view>.md` — thin pages embedding a view for the KB viewer via a fenced ` ```likec4-view ` block whose body is the view id, plus a `## Notes` section.

### Steps

1. **Gather context.** Read to understand the system:
   - `knowledge-base/project/README.md` and `knowledge-base/project/components/`
   - Existing ADRs in `knowledge-base/engineering/architecture/decisions/`
   - The current `.c4` project in the diagrams dir — **READ all three files in full** (`model.c4`, `views.c4`, `spec.c4`), never a single keyword grep (do not duplicate elements that already exist).

   **External-actor / external-system completeness sweep (do this before concluding "nothing to add").** For the change at hand, enumerate every (a) external human actor (who sends/receives the data — correspondents, reviewers, recipients), (b) external system/vendor (inbound webhook, outbound API, third-party store), (c) container/data-store touched, and (d) actor↔surface access relationship that changes. For each, confirm it is already modeled; if not, add it (element + `#external` tag if outside the platform boundary + the relationship edges + the `views.c4` `include` line so it RENDERS). A `grep` for the feature's own noun returning zero is NOT evidence of absence — the gap is usually an external actor/vendor named by role/vendor, not the feature (e.g. an inbound-email "Correspondent" actor + a "Resend" system for an email feature). Also fix any element **description** the change falsifies (e.g. a "Solo founder" actor when the change adds multi-Owner sharing). See `knowledge-base/project/learnings/2026-06-18-c4-impact-requires-reading-all-diagrams-and-enumerating-external-actors.md`.

2. **Edit the consolidated model** (`spec.c4` / `model.c4`), following
   [likec4-reference.md](./references/likec4-reference.md). Key rules:
   - Declare each element exactly once; nest children inside their parent (`system { container { component } }`). Nesting creates the C4 boundary automatically — there is no separate boundary keyword.
   - Relationships: `from -> to "label" { technology "HTTPS" }`. Reference nested elements by qualified path in views (`platform.webapp.dashboard`).
   - Tag third-party systems `#external`.

3. **Edit the views** (`views.c4`): ensure a view exists per level you want to
   show. Wire drill-down with `view <id> of <parent>` so the parent element in
   the higher-level view links into it.

4. **Write/refresh the view page(s).** For each view that needs a KB page, write
   `knowledge-base/engineering/architecture/diagrams/<view>.md`:

   ````markdown
   # <Title> (C4 Level N)

   Generated: YYYY-MM-DD

   ```likec4-view
   <view-id>
   ```

   ## Notes

   [Context about the diagram, references to relevant ADRs]
   ````

5. **Validate** (see `render` below) and **announce**:
   "LikeC4 model updated — N elements, M relationships, K views."

---

## Sub-commands: add-container, add-component, add-relationship

Incremental edits to the consolidated model. Each is a focused patch to the
`.c4` files (no Mermaid). After any patch, run `render` (see below) to
**validate** the source. You do NOT need to hand-regenerate `model.likec4.json`:
the `c4-model-regenerate` pre-commit hook re-renders and re-stages it from the
edited `.c4` sources on commit (run the repo-root `regenerate-c4-model.sh` —
see `render` below — only when committing outside that hook).

- **add-container `<id>`** / **add-component `<id>`** — add an element inside the
  correct parent in `model.c4` (`container` / `database` / `component` kind),
  with `technology` and `description`. Add it to the relevant `view`'s `include`
  list in `views.c4` if it should appear.
- **add-relationship `<from> <to>`** — append `from -> to "label" { technology "…" }`
  to `model.c4`, using existing element ids (qualified if nested).

Gather the label/technology/description from `$ARGUMENTS` or via AskUserQuestion.

---

## Sub-command: render

Validate the LikeC4 project and rebuild the precomputed model the web viewer
renders. The Knowledge Base viewer does NOT run the `likec4` toolchain at
runtime (it would pull vite/esbuild into production deps); it reads the
committed, layouted `model.likec4.json`.

**You normally do not run this by hand.** Regeneration of `model.likec4.json`
is **automatic on commit** via the `c4-model-regenerate` pre-commit hook
(`lefthook.yml`): any staged `.c4` change re-renders and re-stages the artifact,
and a CI freshness test (`plugins/soleur/test/c4-model-freshness.test.sh`) is the
merge-gating backstop if the hook is bypassed. Use `render` only to **validate**
or for an **ad-hoc/out-of-hook** regen:

```bash
# Canonical regen (pinned, off-tree-validated, idempotent) — same primitive the
# pre-commit hook runs:
bash scripts/regenerate-c4-model.sh

# Or validate only (line-numbered diagnostics) without rewriting the artifact:
cd knowledge-base/engineering/architecture/diagrams
npx -y likec4@1.50.0 validate .
```

The pinned `1.50.0` is load-bearing: it MUST match `apps/web-platform/Dockerfile`
+ `package.json` (`@likec4/core` / `@likec4/diagram`), guarded by
`c4-likec4-version-pin.test.ts`. Never pin to a floating tag (the unpinned
`likec4` / a moving release) — a CLI/client schema skew silently corrupts the
rendered diagram. `regenerate-c4-model.sh` renders
off-tree and refuses to publish an empty/invalid model, so a broken `.c4` can
never clobber the good committed artifact.

On success, report element / relationship / view counts (read the
`elements` / `relations` / `views` key counts from `model.likec4.json`). On
failure, surface the line-numbered diagnostics and fix the `.c4` source before
continuing.

---

## Sub-command: assess

Assess a feature or plan against the NFR register to identify which non-functional requirements are relevant and what their current status is.

**Read [nfr-reference.md](./references/nfr-reference.md) now** for the assessment checklist and common NFR patterns by decision type.

### Steps

1. **Get the feature description.** If provided in `$ARGUMENTS`, use it. Otherwise, check for a plan file on the current branch:

   - If on a `feat-*` branch, look for `knowledge-base/project/plans/*<feature-slug>*-plan.md`
   - If a plan exists, read it and extract the feature description from the Overview section
   - Otherwise, use AskUserQuestion: "What feature or change are you assessing?"

2. **Read the NFR register** at `knowledge-base/engineering/architecture/nfr-register.md`.

3. **Read the principles register** at `knowledge-base/engineering/architecture/principles-register.md`. If it does not exist, skip principle alignment in step 5b.

4. **Identify affected containers and links.** Read the Container & Link Inventory in the NFR register. Map the feature to specific C4 containers and links it touches (e.g., a new external service adds a network link; a new UI feature affects Dashboard and API Routes).

5. **Classify the feature** against the decision type patterns from [nfr-reference.md](./references/nfr-reference.md):

   - New external service integration
   - Infrastructure change
   - New user-facing feature
   - Data model change
   - Security change
   - Deployment change

6. **Assess each NFR category.** For each of the 7 categories (Observability, Resilience, Testing, Configuration & Delivery, Scaling & Recovery, Security, Data Quality), determine:

   - Which specific NFRs are relevant to the affected containers/links
   - Current per-container/link status from the NFR register tables
   - Whether this feature improves, degrades, or has no effect on each NFR for the affected containers/links
   - Any evidence gaps (rows with "Applicable: Yes" but no evidence documented)
   - Any new NFRs that should be added to the register

7. **Assess principle alignment.** For each principle in the register (AP-001 through AP-NNN), determine: relevant to this feature (yes/no), alignment status (Aligned/Deviation/N/A), and brief rationale. Skip if the principles register was not found in step 3.

8. **Output the assessment** as a per-container table:

   ```text
   ## NFR Assessment: [Feature Name]

   ### Affected Containers/Links

   - Dashboard, API Routes, Agent Runtime -> New External Service (new link)

   ### Assessment

   | NFR | Requirement | Container/Link | Status | Impact | Evidence Gap |
   |-----|-------------|----------------|--------|--------|-------------|
   | NFR-001 | Logging | New Service | — | Needs attention | No logging configured |
   | NFR-026 | Encryption In-Transit | Agent Runtime -> New Service | — | Needs attention | HTTPS required |
   | NFR-007 | Circuit Breaker | Agent Runtime -> New Service | — | Risk introduced | No fallback for new dependency |
   | NFR-026 | Encryption In-Transit | Founder -> Dashboard | Implemented | No change | Cloudflare |
   ```

   If the principles register was loaded, add a Principle Alignment section:

   ```text
   ### Principle Alignment

   | Principle | Title | Status | Note |
   |-----------|-------|--------|------|
   | AP-001 | Terraform-only provisioning | Aligned | New infra uses Terraform |
   | AP-008 | Doppler secrets | N/A | No new secrets |
   ```

9. **Recommend actions.** For each NFR with "Needs attention" or "Risk introduced" impact, propose a specific action referencing the affected container/link (e.g., "Add circuit breaker on Agent Runtime -> Stripe link", "Configure structured logging for New Service container"). For each principle with "Deviation" status, explain the deviation and whether an exception is justified.

10. **Offer to create an ADR.** If the assessment reveals architectural decisions (e.g., choosing to accept a risk, implementing a new NFR, deviating from a principle), ask: "Create an ADR to document these decisions?" Principle alignment will be pre-filled from the assessment.

---

## ADR vs Learning

ADRs and learnings serve different purposes:

| | ADR | Learning |
|---|-----|---------|
| **When** | At decision time | After implementation |
| **What** | "Why we chose X over Y" | "What went wrong and how we fixed it" |
| **Format** | Context / Decision / Consequences | Problem / Solution / Key Insight |
| **Location** | `knowledge-base/engineering/architecture/decisions/` | `knowledge-base/project/learnings/` |
| **Lifecycle** | Active → Superseded | Evergreen (archived when stale) |

---

## Sub-command: principle list

Display the architecture principles register.

### Steps

1. **Read the principles register** at `knowledge-base/engineering/architecture/principles-register.md`.

2. **If the file does not exist:** Display "No principles register found. Create one at `knowledge-base/engineering/architecture/principles-register.md`."

3. **Display the principles table** from the register, preserving the markdown table format.

4. **Display the enforcement tiers table** below the principles table.
