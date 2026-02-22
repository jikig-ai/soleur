# Learning: Three-way agent disambiguation when adding a third domain agent

## Problem

When adding a third agent (`ops-provisioner`) to an existing two-agent domain (`ops-research` + `ops-advisor`), the plan initially only included disambiguation in the new agent's description. The Kieran reviewer caught that both existing sibling descriptions needed updating too -- they only referenced each other, not the new agent.

## Solution

When adding agent N to a domain with N-1 existing agents, update ALL N agent descriptions to cross-reference each other. For ops-provisioner:

- `ops-provisioner` disambiguates against `ops-research` and `ops-advisor`
- `ops-research` disambiguates against `ops-advisor` and `ops-provisioner` (updated)
- `ops-advisor` disambiguates against `ops-research` and `ops-provisioner` (updated)

## Key Insight

Disambiguation is a graph property, not a node property. Adding one node requires updating all edges. The constitution rule ("agents with overlapping scope must include disambiguation") applies to siblings, not just the new agent. Plan reviewers (especially convention-focused ones like Kieran) reliably catch this.

## Tags

category: integration-issues
module: agents/operations
symptoms: routing accuracy degrades, tasks sent to wrong agent
