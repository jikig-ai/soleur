---
name: architecture
description: "This skill should be used when managing Architecture Decision Records or C4 diagrams."
---

# Architecture as Code

Create, manage, and query Architecture Decision Records (ADRs) and generate Mermaid C4 architecture diagrams. All artifacts are stored as version-controlled markdown in `knowledge-base/engineering/architecture/`.

## Sub-commands

| Command | Description |
|---------|-------------|
| `architecture create [title]` | Create a new ADR with the next sequential number |
| `architecture list` | Display all ADRs with status, title, and date |
| `architecture supersede <N> [title]` | Mark ADR-N as superseded and create its replacement |
| `architecture diagram [type]` | Generate a Mermaid C4 diagram (context, container, or component) |
| `architecture assess [feature]` | Assess a feature against the NFR register and recommend relevant requirements |

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

4. **Read the ADR template** from [adr-template.md](./references/adr-template.md).

5. **Write the ADR file.** Create `knowledge-base/engineering/architecture/decisions/ADR-<NNN>-<kebab-title>.md` using the template. Fill in:
   - `adr: ADR-<NNN>`
   - `title: <title>`
   - `status: active`
   - `date: <today YYYY-MM-DD>`

6. **Gather context.** Ask the user (or use `$ARGUMENTS` context if running in pipeline):
   - **Context:** What motivates this decision?
   - **Considered Options:** What alternatives were evaluated? (list with pros/cons and links to tentative C4 model changes)
   - **Decision:** Which option was chosen and why?
   - **Consequences:** What becomes easier or harder?
   - **Cost Impacts:** How much does this change increase or reduce costs? (reference `knowledge-base/operations/expenses.md` for baseline; use "None" if no impact)
   - **NFR Impacts:** Which non-functional requirements are affected? Read [nfr-reference.md](./references/nfr-reference.md) for the assessment checklist and common patterns by decision type. Reference NFR IDs from `knowledge-base/engineering/architecture/nfr-register.md`. Use "None" if no impact.
   - **Diagram:** (optional) Should a Mermaid C4 diagram be included?

7. **Write the ADR body** with the gathered context. If a diagram was requested, generate using proper C4 syntax from [c4-reference.md](./references/c4-reference.md).

8. **Announce:** "Created ADR-<NNN>: <title> at `knowledge-base/engineering/architecture/decisions/ADR-<NNN>-<kebab-title>.md`"

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
   | ADR-001 | Use Mermaid for diagrams | active | 2026-03-27 |
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

Generate a Mermaid C4 model architecture diagram using the proper C4 diagram syntax.

**Read [c4-reference.md](./references/c4-reference.md) now** for the complete C4 Mermaid syntax reference before generating any diagram.

### Steps

1. **Determine diagram type.** If provided in `$ARGUMENTS`, use it. Otherwise, use AskUserQuestion:

   | Type | C4 Level | Mermaid Keyword | Description |
   |------|----------|-----------------|-------------|
   | `context` | Level 1 | `C4Context` | System boundaries, external actors, and system-to-system relationships |
   | `container` | Level 2 | `C4Container` | Applications, databases, and services within the system boundary |
   | `component` | Level 3 | `C4Component` | Internal components of a single container |

2. **Gather context.** Read relevant project files to understand the system:

   - `knowledge-base/project/README.md` for system overview
   - `knowledge-base/project/components/` for component documentation
   - Existing ADRs in `knowledge-base/engineering/architecture/decisions/` for architectural decisions
   - Existing diagrams in `knowledge-base/engineering/architecture/diagrams/` for consistency

3. **Generate the Mermaid diagram** using proper C4 syntax from [c4-reference.md](./references/c4-reference.md). Key rules:

   - Use the correct diagram keyword (`C4Context`, `C4Container`, or `C4Component`)
   - Use C4 shapes: `Person`, `System`, `System_Ext`, `Container`, `ContainerDb`, `Component`, etc.
   - Use `Rel(from, to, label, ?protocol)` for relationships — NOT `-->`
   - Use `Enterprise_Boundary`, `System_Boundary`, or `Container_Boundary` for grouping
   - Use `_Ext` suffix for external systems/actors

4. **Write the diagram file.** Save to `knowledge-base/engineering/architecture/diagrams/<type>.md`:

   ````markdown
   # <Title> (C4 Level N)

   Generated: YYYY-MM-DD

   ```mermaid
   C4Context
   title System Context diagram for [System Name]

   Person(user, "User Role", "Description")
   System(sys, "System Name", "Description")
   System_Ext(ext, "External System", "Description")

   Rel(user, sys, "Uses", "HTTPS")
   Rel(sys, ext, "Sends data to", "API")
   ```

   ## Notes

   [Context about the diagram, references to relevant ADRs]
   ````

5. **Announce:** "Diagram saved to `knowledge-base/engineering/architecture/diagrams/<type>.md`"

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

3. **Classify the feature** against the decision type patterns from [nfr-reference.md](./references/nfr-reference.md):

   - New external service integration
   - Infrastructure change
   - New user-facing feature
   - Data model change
   - Security change
   - Deployment change

4. **Assess each NFR category.** For each of the 7 categories (Observability, Resilience, Testing, Config & Delivery, Scaling & Recovery, Security, Data Quality), determine:

   - Which specific NFRs are relevant to this feature
   - Current status of each relevant NFR
   - Whether this feature improves, degrades, or has no effect on each NFR
   - Any new NFRs that should be added to the register

5. **Output the assessment** as a table:

   ```text
   ## NFR Assessment: [Feature Name]

   | NFR | Requirement | Current Status | Impact | Notes |
   |-----|-------------|---------------|--------|-------|
   | NFR-001 | Logging | Partial | Needs attention | New service requires structured logging |
   | NFR-026 | Encryption In-Transit | Implemented | No change | Already covered by Cloudflare |
   | NFR-007 | Circuit Breaker | Not Implemented | Risk introduced | New API dependency has no fallback |
   ```

6. **Recommend actions.** For each NFR with "Needs attention" or "Risk introduced" impact, propose a specific action (e.g., "Add circuit breaker for Stripe API calls", "Configure structured logging for new service").

7. **Offer to create an ADR.** If the assessment reveals architectural decisions (e.g., choosing to accept a risk, implementing a new NFR), ask: "Create an ADR to document these decisions?"

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
