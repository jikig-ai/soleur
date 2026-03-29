---
title: "pip --require-hashes requires ALL transitive dependencies to be pinned"
date: 2026-03-29
category: build-errors
tags: [python, pip, supply-chain, dependencies]
symptoms: "ERROR: In --require-hashes mode, all requirements must have their versions pinned with =="
module: plugins/soleur/skills/gemini-imagegen
---

# Learning: pip --require-hashes requires ALL transitive dependencies

## Problem

When implementing supply chain hardening (#1174), the plan prescribed
`pip install --require-hashes -r requirements.txt` with SHA-256 hashes
for direct dependencies (google-genai, Pillow). Installation failed
because pip's `--require-hashes` mode is all-or-nothing: once ANY
package has a `--hash` line, ALL packages (including transitive
dependencies) must also have pinned versions and hashes.

google-genai has ~20 transitive dependencies (anyio, httpx, pydantic,
cryptography, etc.), none of which were in requirements.txt.

## Solution

Dropped `--require-hashes` and hash lines from requirements.txt. Kept
exact version pins (`==`) as the primary supply chain defense. Exact
version pinning prevents pip from resolving to a malicious newer version,
which was the attack vector in the litellm incident.

Full hash verification for the entire dependency tree requires
`pip-compile` from `pip-tools`, which generates a locked requirements
file with all transitive deps and their hashes. This is a future
enhancement, not a blocker for the initial hardening.

## Key Insight

pip's `--require-hashes` is not a "hash the packages you list" feature --
it is a "verify the integrity of your ENTIRE dependency tree" feature.
Using it requires either (a) listing every transitive dependency with
hashes, or (b) using `pip-compile --generate-hashes` to automate that.
For projects with few Python dependencies, exact version pinning (`==`)
provides most of the supply chain defense without the maintenance burden
of full hash verification.

## Session Errors

1. **pip --require-hashes failed on transitive dependencies** -- The plan
   prescribed `--require-hashes` without accounting for transitive deps.
   Caught during QA when `pip install` failed with "all requirements must
   have their versions pinned with ==". **Recovery:** Dropped hashes, kept
   exact version pins. **Prevention:** When prescribing pip hash
   verification in plans, verify that ALL transitive dependencies are
   accounted for, or use `pip-compile` to generate the full locked file.

2. **Security reminder hook blocked workflow edits (expected)** -- The
   `security_reminder_hook.py` PreToolUse hook blocked the first
   Edit/Write on `.github/workflows/*.yml` files. This was documented in
   the plan as a known edge case. Second attempts succeeded after user
   approval. **Prevention:** Already documented in plan; no additional
   prevention needed.

## Tags

category: build-errors
module: plugins/soleur/skills/gemini-imagegen
