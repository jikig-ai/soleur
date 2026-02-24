# Learning: BSL 1.1 License Migration Pattern

## Problem

Switching Soleur from Apache-2.0 to BSL 1.1 required coordinated updates across license files, metadata, documentation, and 14 legal documents in two parallel directory trees. Three distinct issues surfaced during execution.

## Solution

### License Text Sourcing

Never use WebFetch to retrieve content that must be reproduced character-for-character (license templates, legal boilerplate). WebFetch summarizes through a small model -- it cannot transcribe verbatim. Use `curl <raw-url>` via Bash instead. GitHub raw URLs (`raw.githubusercontent.com`) are reliable for license templates.

### Write/Edit After Context Compaction

When a session continues from compacted context, prior Read calls are no longer in the conversation window. The Write/Edit tools correctly reject operations on unread files. At the start of any continued session, Read every file you intend to modify before writing -- even if the content is known from memory.

### Dual-Location Legal Documents

Legal docs exist in two parallel trees: `docs/legal/` (source markdown) and `plugins/soleur/docs/pages/legal/` (Eleventy templates). Any prose change must be applied to both copies in the same pass. Build an explicit (source, mirror) pair list before starting, and verify via grep that both copies have the new text before committing.

### Version Bump Classification

A license change is a legal/policy change, not a functional API change. MINOR bump is correct (new constraint on use, but no change to plugin interface or behavior). MAJOR is reserved for breaking changes to plugin API, agent interface, or command contract. Document the reasoning in the CHANGELOG entry.

### BSL 1.1 Parameters Checklist

When filling in the BSL 1.1 template:
- **Licensor:** Company name
- **Licensed Work:** Product name and minimum version
- **Additional Use Grant:** What production use IS allowed (keep it simple -- avoid HashiCorp's multi-paragraph definitions unless needed)
- **Change Date:** Rolling (per-version) vs fixed date
- **Change License:** The OSS license it converts to
- **SPDX identifier:** `BUSL-1.1` (not `BSL-1.1`)

## Key Insight

A license migration is a cross-cutting scope change that touches license artifacts, SPDX metadata, user-facing READMEs, and legal prose across multiple directory trees. The execution pattern is: (1) source the template text via curl (not WebFetch), (2) write license files, (3) update metadata, (4) update all documentation pairs in lockstep, (5) MINOR version bump with explicit reasoning in CHANGELOG.

## Session Errors

1. Write tool rejected LICENSE file writes -- files read in prior session but context compacted
2. Edit tool rejected 3 legal doc edits -- same cause (files not read in current context)
3. WebFetch returned summarized paraphrase of BSL 1.1 template -- unusable for verbatim license text

## Tags
category: implementation-patterns
module: license-migration
