# Functional Overlap Check

After the stack-gap check, search community registries for skills/agents that functionally overlap with the feature being planned. This prevents redundant development when community tools already cover the planned functionality.

**Always runs** -- unlike the Community Discovery Check which is conditional on stack gaps. Any feature could have community overlap regardless of technology stack.

**Step 1:** Extract the feature description from the `<feature_description>` tag.

**Step 2:** Spawn the functional-discovery agent.

If the brainstorm document (loaded in Phase 0.5) contains a `## Capability Gaps` section, include the gap descriptions as additional search context in the Task prompt:

```
Task functional-discovery: "Feature description: [feature_description text].
[If brainstorm contains Capability Gaps: Additional context -- the following
capability gaps were identified during brainstorming: [gap descriptions].]
Search community registries for skills/agents with similar functionality
and present install/skip suggestions."
```

**Step 3: Handle results.**
- If artifacts were installed: announce "Installed N community artifacts with similar functionality. They will be available in subsequent commands."
- If all suggestions were skipped or zero results: continue silently.
- If functional-discovery failed (network errors): continue silently. Discovery must never block planning.
