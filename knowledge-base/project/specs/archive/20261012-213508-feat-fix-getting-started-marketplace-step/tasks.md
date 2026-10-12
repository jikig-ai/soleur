# Tasks: fix getting-started marketplace step

## Phase 1: Core Implementation

### 1.1 Update Installation section

- [ ] 1.1.1 Edit `plugins/soleur/docs/pages/getting-started.njk` line 56-58 to show both commands in the quickstart code block
- [ ] 1.1.2 Verify the `<pre><code>` block renders both commands on separate lines

### 1.2 Update FAQ answer

- [ ] 1.2.1 Edit the "What do I need to run Soleur?" FAQ answer (line 168) to include the marketplace add step before the install command
- [ ] 1.2.2 Verify the HTML `<code>` tags wrap each command correctly

### 1.3 Update JSON-LD structured data

- [ ] 1.3.1 Edit the FAQPage JSON-LD schema text (line 204) to match the updated FAQ answer

## Phase 2: Validation

### 2.1 Build check

- [ ] 2.1.1 Run Eleventy build to verify the page compiles without errors
- [ ] 2.1.2 Verify the output HTML contains both commands in the correct locations
