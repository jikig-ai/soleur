# Tasks: Sync landing page .pen file after CaaS badge removal

## Phase 1: Discovery

- [ ] 1.1 Open `brand-visual-identity-brainstorm.pen` via `mcp__pencil__open_document` (absolute path)
- [ ] 1.2 Get editor state with schema (`mcp__pencil__get_editor_state`)
- [ ] 1.3 List top-level document nodes (`mcp__pencil__batch_get`)
- [ ] 1.4 Identify the landing page / homepage hero mockup frame
- [ ] 1.5 Drill into hero frame structure (`mcp__pencil__batch_get` with `readDepth: 3`)

## Phase 2: Identify Target Elements

- [ ] 2.1 Search for text nodes containing "Company-as-a-Service" in the hero section
- [ ] 2.2 Identify the badge container frame (pill wrapper)
- [ ] 2.3 Capture "before" screenshot of the landing page mockup
- [ ] 2.4 Measure current hero padding via `mcp__pencil__snapshot_layout`

## Phase 3: Execute Changes

- [ ] 3.1 Delete the CaaS badge element (`mcp__pencil__batch_design` with `D()`)
- [ ] 3.2 Adjust hero top padding from 128 to 80 (`mcp__pencil__batch_design` with `U()`)

## Phase 4: Verify

- [ ] 4.1 Capture "after" screenshot of the landing page mockup
- [ ] 4.2 Visual comparison: badge gone, tighter spacing, no layout breakage
- [ ] 4.3 Check layout for problems (`mcp__pencil__snapshot_layout` with `problemsOnly: true`)
- [ ] 4.4 Verify other mockup screens in the .pen file are unmodified

## Phase 5: Commit

- [ ] 5.1 Run compound (`soleur:compound`) before committing
- [ ] 5.2 Commit: `refactor(design): sync .pen landing page after CaaS badge removal`
- [ ] 5.3 Push and create PR referencing #323
