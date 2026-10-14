---
title: Workspace agent engine settings implementation brief
date: 2026-09-11
status: ready-for-implementation
---

Source: [workspace-default-engine.pen](workspace-default-engine.pen), frame
`rbLVa` (Workspace Default Agent Engine). Review export:
[01-workspace-default-agent-engine.png](screenshots/01-workspace-default-agent-engine.png).

- **Page structure:** Existing workspace settings shell; one vertical content
  column containing the heading, current default card, Codex connection card,
  and dispatch behavior notice. Desktop canvas is 1440 × 900. The 216px navigation
  rail has a collapse affordance. Reuse the application's existing settings
  navigation in implementation; the rail in this wireframe is contextual shell.
- **Heading:** `WORKSPACE / SETTINGS`, then `DEFAULT AGENT ENGINE`.
  Introductory copy: “Choose the engine for new conversations and future routine
  runs. Existing conversations and started runs keep their engine, including
  retries.” The routine definition does not retain yesterday's default: each
  future run selects the current workspace default at dispatch and binds it for
  continuation and retries.
- **Engine Default Card:** Vertical stack with `ACTIVE DEFAULT`, `READY`, a
  full-width bordered selector showing `CLAUDE CODE` and `CHANGE >`, then
  `Claude Code • Verified • Interactive approvals • Live streaming`.
  Gold border emphasizes the selected engine. These are illustrative populated
  states; actual status and capability text must come from qualification results,
  never from a static promise. Changing the selector opens eligible engine
  choices with unavailable choices disabled and their reason visible.
- **Codex Availability:** Heading `CODEX / SET UP CONNECTION`. Body:
  “Choose how Codex is connected. This choice determines the billing source.
  Availability is checked separately for conversations and routines.” Two equal
  columns form one mutually exclusive authentication radio group:
  - Selected `API KEY`: `Billed to your OpenAI API account`; action
    `CONNECT API KEY →`. The selected method has a gold border.
  - Unselected `CHATGPT SUBSCRIPTION`: `Uses your eligible ChatGPT plan limits`;
    action `SIGN IN WITH CHATGPT →`. The alternate method has a neutral border.
  - Below the choices: `Selected method: API key · Not connected` and
    `NOT READY TO SELECT · Connection and workflow checks required`.
  Selecting a method is explicit and must not silently activate a different
  billing method. Starting the alternate connection action selects that method
  visibly; a completed connection does not change the workspace engine default.
  Persist the selected authentication mode separately from connection readiness.
- **Dispatch behavior notice:** “If the selected engine or sign-in method is
  unavailable, work pauses with a clear reason. Soleur never switches engines or
  billing methods automatically.” Render the concrete recovery action with
  failed dispatches: reconnect, request owner access, or choose a qualified engine
  explicitly. Do not imply a failed operation continues running in the background.
- **Connection interactions:** API-key setup reuses encrypted server-managed
  credentials; never display a stored key. ChatGPT sign-in launches the managed
  login/device flow, shows pending/connected/expired/revoked status, and offers
  cancel/reconnect. Do not ask users to paste access or refresh tokens. Show the
  connected account, selected mode, billing source, and applicable data controls
  before saving. An authentication-mode change must be explicit and rechecked
  against workspace policy. Keep the prior committed selection on failed saves.
- **Workflow availability:** Display separate readiness for conversations and
  routine runs. A partial future provider can be offered only for its qualified
  workflow; unsupported operations carry a reason and no fallback. Do not expose
  Grok Build or Devin as supported solely because they exist in the registry.
- **Interaction and responsive implementation:** Use semantic buttons, a labelled
  select/dialog, and native radio inputs with visible focus. Mark pending saves
  and authentication completion in an accessible status region. Stack auth cards
  at narrow widths and retain the application's mobile settings shell. Use
  production contrast-compliant tokens; the desktop wireframe establishes
  structure and emphasis, not a requirement to reproduce muted placeholder
  contrast. Scope default mutations to authorized workspace owners and show a
  read-only value with a clear access explanation for other members.

## Specialist findings and disposition

- **Resolved:** Earlier copy excluded routines. The heading now includes future
  routine runs and explains stable bindings for started runs and retries.
- **Resolved:** Earlier Codex card required an API key and said “available to
  enable” while qualification was incomplete. Both authentication modes now have
  explicit billing descriptions; connection and workflow checks gate readiness.
- **Resolved:** The dispatch notice now prohibits silent engine or billing-method
  changes. The active engine remains separate from a pending Codex connection.
- **Resolved:** The contextual 260px sidebar had no collapse action. It is now
  216px and includes collapse. Implementation should use the existing app shell.
- **Disposition:** Ready as the implementation structure for the agreed scope.
  No remaining product decision or structural conflict with the updated plan.
  Runtime qualification, sign-in security, accessibility, and responsive QA
  remain implementation checks; the mock does not certify runtime capabilities.

## Design verification

- Pencil layout inspection reported no layout problems after changes.
- Source opened from a committed recovery input and saved through Pencil MCP;
  final size 14,534 bytes (initial size 8,947 bytes).
- Export requested at scale 3; the renderer produced a complete 4096 × 2560 PNG,
  visually inspected for copy and clipping. The adapter timed out waiting for its
  prompt after writing the file; file signature, dimensions, and visual rendering
  confirmed the export independently. The old review export was replaced.
- Adapter diagnostic: `open_document.filePath` is the output path. This installed
  adapter requires `inputPath` to load existing content; without it the editor is
  empty despite an unchanged on-disk source. The pre-restart auto-save briefly
  reduced the output to 40 bytes; committed input recovery restored it before
  edits. Future iteration must supply a separate input snapshot and verify both
  loaded nodes and post-save size, not just the initial post-open byte count.
