# Engine contract probe transcript

engine: @pen.dev/cli@0.3.13 probed 2026-10-27
scope: engine and adapter cases
result: all cases passed (145 passed)

Credential, `$HOME`, absolute paths, UUIDs (including a document `fileToken`) and account lines are scrubbed by `plugins/soleur/test/lib/scrub-transcript.mjs`; `pen status` output is never recorded.

```text
PASS pen status reports Active for the credential (fail-open engine guard)
PASS installed @pen.dev/cli version equals the check_deps.sh pin
RECORD undici version in the engine tree under test: 8.12.2
PASS parsed tool signatures from --help
PASS every REPL_SURFACE tool has exactly the signature the CLI prints
PASS none of the 9 removed tools is listed in --help
PASS --help documents the save() shell command
PASS session starts and reaches the prompt
PASS startup prints [INFO] Ready. before the prompt
PASS prompt is `pen > ` at the end of the buffer
PASS raw prompt bytes equal REPL_PROMPT_RAW
RECORD ANSI escapes on piped stdout: yes (the engine colours even on a pipe)
PASS nonce count on an empty document is 0
PASS a count line for another nonce is not accepted
PASS batch_design reply starts with OK
PASS reply carries a ## Print output section
PASS second consecutive batch_design reply starts with OK
PASS the alias preamble defines I and U inside execute
PASS nonce count after two top-level inserts is 2
PASS a node name that imitates the count line does not change the parse
PASS save() replies exactly `Saved <path>` on stdout
PASS the saved file holds the three top-level nodes
PASS the saved file is larger than the 96-byte empty document
PASS the saved document carries a version
PASS batch_get() answers Unknown tool:
PASS batch_get: the enrichment appends the exact removed-tool hint to the engine's answer
PASS snapshot_layout() answers Unknown tool:
PASS snapshot_layout: the enrichment appends the exact removed-tool hint to the engine's answer
PASS get_guidelines() answers Unknown tool:
PASS get_guidelines: the enrichment appends the exact removed-tool hint to the engine's answer
PASS get_style_guide() answers Unknown tool:
PASS get_style_guide: the enrichment appends the exact removed-tool hint to the engine's answer
PASS get_style_guide_tags() answers Unknown tool:
PASS get_style_guide_tags: the enrichment appends the exact removed-tool hint to the engine's answer
PASS find_empty_space_on_canvas() answers Unknown tool:
PASS find_empty_space_on_canvas: the enrichment appends the exact removed-tool hint to the engine's answer
PASS set_variables() answers Unknown tool:
PASS set_variables: the enrichment appends the exact removed-tool hint to the engine's answer
PASS search_all_unique_properties() answers Unknown tool:
PASS search_all_unique_properties: the enrichment appends the exact removed-tool hint to the engine's answer
PASS replace_all_matching_properties() answers Unknown tool:
PASS replace_all_matching_properties: the enrichment appends the exact removed-tool hint to the engine's answer
PASS batch_design() (the old name) answers Unknown tool:
PASS read_skill() index lists the guide and top-level paths
PASS read_skill index lists pen-schema.md
PASS read_skill index lists execute.md
PASS read_skill index lists at least 9 guide/ paths
PASS every listed path passes the adapter's read_skill validator
PASS read_skill on all 14 paths, each followed by an intact save() reply
PASS guide names in SKILL.md equal the engine's read_skill index
PASS guide names in ux-design-lead.md equal the engine's read_skill index
PASS a failed save prints `Save failed:`
RECORD Save failed: stream: stderr
PASS a failed save is not confirmed with a Saved line
PASS a failed save left no file behind
PASS no engine write appears in the 15 s after a failed save (directory writable again)
RECORD save() after the cause of a failed save is fixed: Saved (the engine kept the edit in memory)
PASS created a frame to export and read its id
PASS export format png writes a png file
PASS export png: the reply names one path inside the requested directory
PASS export format jpeg writes a jpeg file
PASS export jpeg: the reply names one path inside the requested directory
PASS export format webp writes a webp file
PASS export webp: the reply names one path inside the requested directory
PASS export format pdf writes a pdf file
PASS export pdf: the reply names one path inside the requested directory
PASS png scale 3 yields 3x the pixel dimensions of scale 1
PASS jpeg quality 10 yields a smaller file than quality 95
PASS webp quality 10 yields a smaller file than quality 95
PASS Export of a missing node id errors and writes nothing
PASS positive control: the same edit plus save() DOES change the bytes
PASS no engine write to any file during a 15 s idle window after an unsaved edit (mtime polling)
PASS edit then exit(): the engine process is gone
PASS edit then exit(): the file is byte-identical to before the session
PASS edit then SIGTERM: the engine process is gone
PASS edit then SIGTERM: the file is byte-identical to before the session
PASS edit then SIGKILL: the engine process is gone
PASS edit then SIGKILL: the file is byte-identical to before the session
NOTE a timed autosave firing later than 15 s after the edit is outside the observation window (stated limit)
PASS the DSL sandbox defines none of process/require/fetch/XMLHttpRequest/Buffer/module/console/timers/std/os (typeof is undefined)
PASS escape routes (this, Function constructor, eval) reach no process/require/fetch
RECORD DSL host globals (every global that is not an ECMAScript built-in): C,Copy,D,Delete,Export,FindEmptySpace,G,Generate,Get,GetVariables,I,Insert,M,Move,Print,R,Replace,SetVariables,TakeScreenshot,U,Update,__batchDesignC,__batchDesignD,__batchDesignExportGlobals,__batchDesignFindEmptySpace,__batchDesignG,__batchDesignGet,__batchDesignGetVariables,__batchDesignI,__batch
PASS pinned engine behaviour: the DSL host-function set
RECORD dynamic import("node:fs") inside the DSL: never-settled
PASS dynamic import does not hand the DSL a loadable node:fs module
RECORD batch_design Export to an absolute dir outside the document dir: writes there
RECORD batch_design Export over an existing file: yes (replaced the existing file); reply: OK Global variables (e.g. blue) carry over to subsequent calls! ## Print outpu
RECORD batch_design Export of two nodes as pdf: export.pdf
RECORD batch_design Export html-css to a new file path in the document dir: writes the named html file
RECORD batch_design Export html-css to the open document's own path: OVERWRITES the open document file with html (the design is gone from disk); reply: OK Global variables (e.g. blue) carry over to subsequent calls! ## Print outpu
PASS the document was saved before the html Export-over-document test
RECORD image fill url (abs) pointing outside the document dir: loaded (renders the local file's pixels)
RECORD image fill url (fileurl) pointing outside the document dir: loaded (renders the local file's pixels)
RECORD image fill url (traversal) pointing outside the document dir: loaded (renders the local file's pixels)
PASS the image fills above were tried against a real exported png
NOTE batch_design host-function behaviour is RECORDED above and PINNED below; switch to a shadowing prelude only if Export overwrites arbitrary files or image urls read local files (CTO ruling 11.2)
PASS pinned engine behaviour: exportOutside
PASS pinned engine behaviour: exportOverwrite
PASS pinned engine behaviour: exportPdfMulti
PASS pinned engine behaviour: exportHtmlNewFile
PASS pinned engine behaviour: exportHtmlOverDocument
PASS pinned engine behaviour: imageAbs
PASS pinned engine behaviour: imageFileUrl
PASS pinned engine behaviour: imageTraversal
PASS recipes: created the 60-rectangle frame and read its id
PASS recipe: Get(id,(n,c)=>Print(c.bounds.width)) prints the frame's measured width FIRST
PASS pinned engine behaviour: Get(id, visitor) visits the node and all of its descendants (one Print line per node)
PASS recipe: Get(id,(n,c)=>Print(n.id+' '+c.bounds.width)) (the hint's own example) prints the id and the width, frame first
RECORD recipe: c.problems values across the frame and its 60 rectangles: -, string:partially clipped
PASS recipe: the c.problems visitor runs on every node of the frame without an error
PASS pinned engine behaviour: c.problems is a string, `partially clipped` or `fully clipped`, undefined when the node has no problem (the 400x300 frame clips overhanging rectangles)
PASS recipe: Print(FindEmptySpace({width:50,height:50})) prints a position
RECORD recipe: FindEmptySpace reply: {"x":400,"y":0}
RECORD recipe (steering): raw Export with a relative directory lands: next to the document (relative to the .pen's directory)
PASS pinned engine behaviour: a raw Export with a relative directory is resolved against the document's directory, not the engine's working directory
PASS control: an unmodified copy of the seed document loads its 3 top-level nodes
PASS no engine write to the unrecognised-version file in a 15 s idle window after an edit (mtime polling)
RECORD --in with an unrecognised document version: opens EMPTY (0 top-level nodes loaded, no error): the save sentinel is the only guard
PASS pinned engine behaviour: unrecognised document version
PASS opening the unrecognised-version file did not rewrite it
RECORD engine echoes a canary credential in its own output (raw/base64/urlencoded): no
PASS the saved .pen holds no form of the canary credential (bytes scanned)
RECORD files the engine wrote under HOME in a session: none
PASS no file the engine wrote under HOME contains a form of the canary credential
PASS positive control: this probe's own redactor removes the canary in all three forms
RECORD lockfile packages declaring an install script (skipped by --ignore-scripts): @google/genai, protobufjs
RECORD install method: npm 11.20.0 ci --ignore-scripts rc=0 in 25 s; node v26.12.1
PASS npm ci --ignore-scripts from the committed lockfile succeeds
PASS npm ci left the lockfile byte-identical
PASS the --ignore-scripts install holds the pinned engine version
PASS an engine installed with --ignore-scripts starts, applies an edit and saves
PASS pen status reports Active from the --ignore-scripts install
PASS adapter: open_document on a new path
PASS adapter: batch_design with I(...) aliases
PASS adapter: second consecutive batch_design
PASS adapter: explicit save
PASS adapter: saved file is larger than the 96-byte empty document
PASS adapter: reopen in a fresh session loads the saved nodes
PASS adapter: get_screenshot
PASS adapter: export_nodes
PASS adapter: removed tool batch_get answers with its exact hint
PASS adapter: removed tool snapshot_layout answers with its exact hint
PASS adapter: removed tool get_guidelines answers with its exact hint
PASS adapter: removed tool get_style_guide answers with its exact hint
PASS adapter: removed tool get_style_guide_tags answers with its exact hint
PASS adapter: removed tool find_empty_space_on_canvas answers with its exact hint
PASS adapter: removed tool set_variables answers with its exact hint
PASS adapter: removed tool search_all_unique_properties answers with its exact hint
PASS adapter: removed tool replace_all_matching_properties answers with its exact hint
PASS adapter: the default binary resolution (HOME at the real prefix, no override) opens, edits and saves
PASS adapter: the default resolution did not go through the --pencil-binary override
PASS adapter: deleting every node of a saved file is refused, `REFUSED save: [reason=empty]` is line 1 of the tool result
PASS adapter: the `empty` refusal left the saved node on disk
PASS adapter: a save over a file rewritten behind the session is refused, `REFUSED save: [reason=stale]` is line 1 of the tool result
PASS adapter: the stale refusal left the file byte-identical
PASS adapter: no write to the stale file in a 15 s idle window after the refusal (mtime polling)
PASS adapter: an explicit save while the refusal is pending is refused as refusal-pending
PASS adapter: a file removed behind a live session is recreated from the session with the removal NOTE
RECORD adapter: raw DSL Export html-css over the open document: file OVERWRITTEN with html; result: REFUSED save: [reason=unrecognized] <WORK>/adapter-overwrite.pen was not modified.
PASS pinned adapter behaviour: a raw-DSL Export html over the open document destroys it (the accepted-residual boundary, reported)
PASS adapter: the next edit after such an overwrite is refused as `unrecognized` (the overwritten file is never saved over)
RECORD adapter open_document on an unrecognised document version: isError: open failed: <WORK>/adapter-version.pen holds 3 top-level node(s) on disk but loaded empty; it was not modified No other tool runs unt
PASS adapter: open_document refuses a file the engine loads with fewer top-level nodes (load fidelity)
PASS adapter: the refused open did not modify the file
PASS adapter: a canary credential appears nowhere in adapter stderr or any tool result (raw, base64, urlencoded)
PASS adapter: the saved .pen holds no form of the canary credential
PASS acceptance: the committed design .pen set was enumerated
RECORD acceptance agent engine selection workspace default engine.pen: disk=1 loaded=1
RECORD acceptance analytics activation funnel.pen: disk=1 loaded=1
RECORD acceptance app ui concierge activity trail.pen: disk=4 loaded=4
RECORD acceptance app ui inbox bulk archive.pen: disk=2 loaded=2
RECORD acceptance app ui session completion inline.pen: disk=2 loaded=2
RECORD acceptance auth otp code step wireframe.pen: disk=2 loaded=2
RECORD acceptance billing subscription management.pen: disk=4 loaded=4
RECORD acceptance billing upgrade modal at capacity.pen: disk=3 loaded=3
RECORD acceptance brand brand linkedin cover.pen: disk=1 loaded=1
RECORD acceptance brand brand visual identity brainstorm.pen: disk=6 loaded=6
RECORD acceptance brand brand x banner.pen: disk=1 loaded=1
RECORD acceptance brand solar radiance 2026 05 05 solar radiance mockups.pen: disk=1 loaded=1
RECORD acceptance byok cost tracking cost tracking wireframes.pen: disk=5 loaded=5
RECORD acceptance byok cost tracking workflow cost breakdown.pen: disk=7 loaded=7
RECORD acceptance chat new conversation rail affordance.pen: disk=5 loaded=5
RECORD acceptance chat reasoning narration.pen: disk=3 loaded=3
RECORD acceptance chat reconnect resume states.pen: disk=1 loaded=1
RECORD acceptance chat workflow ended copy states.pen: disk=1 loaded=1
RECORD acceptance command center cc embedded skill surfaces.pen: disk=6 loaded=6
RECORD acceptance command center chat ux redesign.pen: disk=5 loaded=5
RECORD acceptance command center concierge streamed commands.pen: disk=1 loaded=1
RECORD acceptance command center team workspace collaboration.pen: disk=3 loaded=3
RECORD acceptance command center workspace invite acceptance.pen: disk=7 loaded=7
RECORD acceptance command palette command shortcuts wireframes.pen: disk=2 loaded=2
RECORD acceptance command palette super key accelerators.pen: disk=10 loaded=10
RECORD acceptance concierge chat composer repo setup states.pen: disk=3 loaded=3
RECORD acceptance concierge concierge confirm scope single card.pen: disk=1 loaded=1
RECORD acceptance crm beta crm pipeline.pen: disk=7 loaded=7
RECORD acceptance crm crm new lead chat.pen: disk=3 loaded=3
RECORD acceptance dashboard nav inbox attention badge.pen: disk=3 loaded=3
RECORD acceptance dashboard nav sidebar float collapse toggle.pen: disk=1 loaded=1
RECORD acceptance dashboard action feedback variant a forge restraint.pen: disk=4 loaded=4
RECORD acceptance dashboard action feedback variant b instrumented spec.pen: disk=4 loaded=4
RECORD acceptance dashboard action feedback variant c ember glow.pen: disk=4 loaded=4
RECORD acceptance dashboard blueprint cards variant a two zones.pen: disk=3 loaded=3
RECORD acceptance dashboard blueprint cards variant b enriched chips.pen: disk=2 loaded=2
RECORD acceptance dashboard dashboard load states.pen: disk=6 loaded=6
RECORD acceptance dashboard releases nav relocation.pen: disk=2 loaded=2
RECORD acceptance dashboard sidebar resizer gold doubleclick.pen: disk=6 loaded=6
RECORD acceptance debug mode debug mode stream.pen: disk=4 loaded=4
RECORD acceptance domain leaders agent identity badges.pen: disk=7 loaded=7
RECORD acceptance domain leaders named domain leaders.pen: disk=7 loaded=7
RECORD acceptance engineering c4 code viewer zoom syntax.pen: disk=1 loaded=1
RECORD acceptance engineering c4 stale banner resurrection.pen: disk=1 loaded=1
RECORD acceptance inbox command center.pen: disk=4 loaded=4
RECORD acceptance inbox conversation state status badge interactions.pen: disk=6 loaded=6
RECORD acceptance inbox dashboard inbox.pen: disk=5 loaded=5
RECORD acceptance inbox operator email triage.pen: disk=4 loaded=4
RECORD acceptance inbox severity ranked inbox.pen: disk=10 loaded=10
RECORD acceptance kb file upload kb file upload flows.pen: disk=14 loaded=14
RECORD acceptance kb mobile chat kb mobile fullscreen chat.pen: disk=11 loaded=11
RECORD acceptance kb viewer c4 concierge header consistency.pen: disk=3 loaded=3
RECORD acceptance kb viewer c4 diagram fullscreen expand.pen: disk=2 loaded=2
RECORD acceptance kb viewer c4 viewer no code panel gated edit.pen: disk=6 loaded=6
RECORD acceptance kb viewer kb doc viewer share chat fixes.pen: disk=3 loaded=3
RECORD acceptance kb viewer kb viewer wireframes.pen: disk=3 loaded=3
RECORD acceptance kb viewer shared document diagram render.pen: disk=5 loaded=5
RECORD acceptance kb kb sidebar resize handle bar.pen: disk=5 loaded=5
RECORD acceptance marketing homepage fanout demo 9577.pen: disk=4 loaded=4
RECORD acceptance marketing homepage hero trust 9579.pen: disk=12 loaded=12
RECORD acceptance marketing learn nav go deeper rail.pen: disk=2 loaded=2
RECORD acceptance mobile chat tour revision mobile chat and tour revision.pen: disk=10 loaded=10
RECORD acceptance mobile kanban mobile kanban board phase 3.pen: disk=17 loaded=17
RECORD acceptance mobile phase 3 mobile phase 3 tables and sheets.pen: disk=7 loaded=7
RECORD acceptance mobile pwa mobile chat surface phase 1.pen: disk=2 loaded=2
RECORD acceptance navigation kb mobile drill in nav.pen: disk=11 loaded=11
RECORD acceptance navigation kb mobile nav redesign wireframes.pen: disk=36 loaded=36
RECORD acceptance navigation kb nav d4 bolder drilled.pen: disk=2 loaded=2
RECORD acceptance navigation kb nav d4 bolder variant.pen: disk=1 loaded=1
RECORD acceptance navigation nav rail position resume.pen: disk=4 loaded=4
RECORD acceptance navigation sidebar band reorder fold.pen: disk=6 loaded=6
RECORD acceptance navigation single nav rail.pen: disk=7 loaded=7
RECORD acceptance navigation workspace logo upload.pen: disk=4 loaded=4
RECORD acceptance notifications notification permission prompt.pen: disk=4 loaded=4
RECORD acceptance onboarding connect repo.pen: disk=2 loaded=2
RECORD acceptance onboarding guided tour.pen: disk=9 loaded=9
RECORD acceptance onboarding onboarding walkthrough.pen: disk=3 loaded=3
RECORD acceptance post connect sync post connect sync wireframes.pen: disk=3 loaded=3
RECORD acceptance pricing pricing page v2 wireframes.pen: disk=0 loaded=0
RECORD acceptance product concierge autonomous toggle.pen: disk=1 loaded=1
RECORD acceptance releases releases page.pen: disk=4 loaded=4
RECORD acceptance routines routines management.pen: disk=13 loaded=13
RECORD acceptance routines run status lifecycle.pen: disk=3 loaded=3
RECORD acceptance runaway guard l5 runaway guard surfaces.pen: disk=5 loaded=5
RECORD acceptance scope grants pr g cohort onboarding.pen: disk=7 loaded=7
RECORD acceptance settings agent web access.pen: disk=3 loaded=3
RECORD acceptance settings concierge command execution.pen: disk=4 loaded=4
RECORD acceptance settings connected services.pen: disk=3 loaded=3
RECORD acceptance settings egress audit log.pen: disk=25 loaded=25
RECORD acceptance settings general workspace identity relocation.pen: disk=1 loaded=1
RECORD acceptance settings kb reconnect affordance.pen: disk=2 loaded=2
RECORD acceptance shared document cta banner visibility states.pen: disk=8 loaded=8
RECORD acceptance shared document cta banner waitlist.pen: disk=5 loaded=5
RECORD acceptance support support chat interface.pen: disk=6 loaded=6
RECORD acceptance support support handoff repo connected prefill.pen: disk=2 loaded=2
RECORD acceptance tab content cache swr loading states.pen: disk=10 loaded=10
RECORD acceptance team workspace team workspace flows.pen: disk=4 loaded=4
RECORD acceptance theme toggle theme toggle iteration.pen: disk=2 loaded=2
RECORD acceptance upgrade modal at capacity.pen: disk=5 loaded=5
RECORD acceptance web platform super key shortcuts help overlay.pen: disk=3 loaded=3
RECORD acceptance website homepage getting started wireframes.pen: disk=2 loaded=2
RECORD acceptance website homepage kiss declutter.pen: disk=2 loaded=2
RECORD acceptance workspace connection member owner repo states.pen: disk=1 loaded=1
RECORD acceptance workspace connection repo connect block states.pen: disk=4 loaded=4
RECORD acceptance workstream creator attribution.pen: disk=2 loaded=2
RECORD acceptance workstream workstream filter bar.pen: disk=3 loaded=3
RECORD acceptance workstream workstream issue crud.pen: disk=29 loaded=29
RECORD acceptance workstream workstream kanban.pen: disk=5 loaded=5
RECORD load-fidelity acceptance summary: 108 committed design .pen files, 108 parse as documents, 108 load faithfully, 0 refused by the engine, 0 load with fewer top-level nodes, 119 s
PASS acceptance: every committed file was evaluated
PASS acceptance (ruling 6): no committed design .pen loads with fewer top-level nodes than on disk
PASS acceptance: the committed files the engine refuses to open are exactly the pinned set
PASS acceptance: opening every file left every copy byte-identical
```
