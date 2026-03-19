# Tasks: Sync landing page .pen file after CaaS badge removal

## Phase 1: Discovery

- [x] 1.1 Open `brand-visual-identity-brainstorm.pen` via `mcp__pencil__open_document` (absolute path)
- [x] 1.2 Get editor state with schema (`mcp__pencil__get_editor_state`)
- [x] 1.3 List top-level document nodes (`mcp__pencil__batch_get`)
- [x] 1.4 Identify the landing page / homepage hero mockup frame — `0Ja8a` "Solar Forge", hero `VMiJW`
- [x] 1.5 Drill into hero frame structure — badge `tLo8Q` with dot `pTmTl` and text `6lv62`

## Phase 2: Identify Target Elements

- [x] 2.1 Badge text: "The Company-as-a-Service Platform" in node `6lv62`, container `tLo8Q`
- [x] 2.2 Badge container frame: `tLo8Q` (pill with stroke, padding [8,20], gap 8)
- [x] 2.3 Captured "before" screenshot — badge visible above headline
- [x] 2.4 Hero padding was `[100, 80, 80, 80]` (top: 100, not 128 as assumed)

## Phase 3: Execute Changes

- [x] 3.1 Deleted badge container `tLo8Q` via `D("tLo8Q")` — cascaded to children
- [x] 3.2 Adjusted hero padding from `[100, 80, 80, 80]` to `[80, 80, 80, 80]`

## Phase 4: Verify

- [x] 4.1 Captured "after" screenshot — badge gone, tighter spacing
- [x] 4.2 Visual comparison: badge removed, headline is first hero element, layout intact
- [x] 4.3 Layout check: "No layout problems" confirmed
- [x] 4.4 Other frames (First Light, Stellar, Solar Radiance) badges untouched

## Phase 5: Commit

- [ ] 5.1 Run compound (`soleur:compound`) before committing
- [ ] 5.2 Commit: `refactor(design): sync .pen landing page after CaaS badge removal`
- [ ] 5.3 Push and create PR referencing #323
