# Community Discovery Check (Conditional)

After local research completes, check whether the project uses a stack not covered by built-in agents. If so, offer to install community agents from trusted registries.

**Step 1: Detect project stacks** using file-signature heuristics:

| Files Present | Detected Stack |
|---------------|---------------|
| `pubspec.yaml` + `*.dart` | flutter |
| `Cargo.toml` + `*.rs` | rust |
| `mix.exs` + `*.ex` | elixir |
| `go.mod` + `*.go` | go |
| `Package.swift` + `*.swift` | swift |
| `build.gradle` + `*.kt` | kotlin |
| `composer.json` + `*.php` | php |

Run Glob checks for each stack's signature files. Stacks already covered by built-in agents (Rails, TypeScript, general security/architecture) are excluded.

**Step 2: Check for coverage gaps** by searching agent frontmatter:

```bash
# Replace <detected_stack> with the actual stack name, e.g.:
grep -rl "stack: flutter" plugins/soleur/agents/ 2>/dev/null
```

If any agent file has a matching `stack:` field, that stack is covered -- skip it. Collect uncovered stacks.

**Step 3: Spawn agent-finder** if any gaps exist:

```
Task agent-finder: "Detected stacks: [list]. Uncovered stacks: [list].
Search registries for community agents/skills matching these uncovered stacks
and present suggestions for user approval."
```

**Step 4: Handle results.** After agent-finder returns:
- If artifacts were installed: announce "Installed N community artifacts for [stacks]. They will be available in subsequent commands."
- If all suggestions were skipped: continue silently.
- If agent-finder failed (network errors): continue silently. Discovery must never block planning.

**Skip condition:** If no uncovered stacks are detected, skip this phase entirely with no output.
