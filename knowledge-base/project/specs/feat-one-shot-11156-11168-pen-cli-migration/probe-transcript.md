# Engine contract probe transcript

engine: @pen.dev/cli@0.3.13 probed 2026-10-26
scope: engine and adapter cases
result: all cases passed (93 passed)

Credential, `$HOME`, absolute paths, UUIDs (including a document `fileToken`) and account lines are scrubbed by `plugins/soleur/test/lib/scrub-transcript.mjs`; `pen status` output is never recorded.

```text
PASS pen status reports Active for the credential (fail-open engine guard)
PASS installed @pen.dev/cli version equals the check_deps.sh pin
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
PASS snapshot_layout() answers Unknown tool:
PASS get_guidelines() answers Unknown tool:
PASS get_style_guide() answers Unknown tool:
PASS get_style_guide_tags() answers Unknown tool:
PASS find_empty_space_on_canvas() answers Unknown tool:
PASS search_all_unique_properties() answers Unknown tool:
PASS replace_all_matching_properties() answers Unknown tool:
PASS set_variables() answers Unknown tool:
PASS batch_design() (the old name) answers Unknown tool:
PASS read_skill() index lists the guide and top-level paths
PASS read_skill index lists pen-schema.md
PASS read_skill index lists execute.md
PASS read_skill index lists at least 9 guide/ paths
PASS every listed path passes the adapter's read_skill validator
PASS read_skill on all 14 paths, each followed by an intact save() reply
PASS a failed save prints `Save failed:`
RECORD Save failed: stream: stderr
PASS a failed save is not confirmed with a Saved line
PASS a failed save left no file behind
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
PASS edit then exit(): the engine process is gone
PASS edit then exit(): the file is byte-identical to before the session
PASS edit then SIGTERM: the engine process is gone
PASS edit then SIGTERM: the file is byte-identical to before the session
PASS edit then SIGKILL: the engine process is gone
PASS edit then SIGKILL: the file is byte-identical to before the session
NOTE a timed autosave firing later than 2 s after the edit is outside the observation window (stated limit)
RECORD batch_design Export to an absolute dir outside the document dir: writes there
RECORD batch_design Export over an existing file: yes (replaced the existing file); reply: OK Global variables (e.g. red) carry over to subsequent calls! ## Print output
RECORD image fill url (abs) pointing outside the document dir: loaded (renders the local file's pixels)
RECORD image fill url (fileurl) pointing outside the document dir: loaded (renders the local file's pixels)
RECORD image fill url (traversal) pointing outside the document dir: loaded (renders the local file's pixels)
PASS the image fills above were tried against a real exported png
NOTE batch_design host-function behaviour is RECORDED above and PINNED below; switch to a shadowing prelude only if Export overwrites arbitrary files or image urls read local files (CTO ruling 11.2)
PASS pinned engine behaviour: exportOutside
PASS pinned engine behaviour: exportOverwrite
PASS pinned engine behaviour: imageAbs
PASS pinned engine behaviour: imageFileUrl
PASS pinned engine behaviour: imageTraversal
PASS control: an unmodified copy of the seed document loads its 3 top-level nodes
RECORD --in with an unrecognised document version: opens EMPTY (0 top-level nodes loaded, no error): the save sentinel is the only guard
PASS pinned engine behaviour: unrecognised document version
PASS opening the unrecognised-version file did not rewrite it
RECORD engine echoes a canary credential in its own output (raw/base64/urlencoded): no
NOTE the adapter side of the canary case (stderr and every tool result) is a TODO(adapter) case below
PASS positive control: this probe's own redactor removes the canary in all three forms
PASS adapter: open_document on a new path
PASS adapter: batch_design with I(...) aliases
PASS adapter: second consecutive batch_design
PASS adapter: explicit save
PASS adapter: saved file is larger than the 96-byte empty document
PASS adapter: reopen in a fresh session loads the saved nodes
PASS adapter: get_screenshot
PASS adapter: export_nodes
PASS adapter: removed tool batch_get answers with a hint
PASS adapter: removed tool snapshot_layout answers with a hint
PASS adapter: removed tool get_guidelines answers with a hint
PASS adapter: removed tool get_style_guide answers with a hint
PASS adapter: removed tool get_style_guide_tags answers with a hint
PASS adapter: removed tool find_empty_space_on_canvas answers with a hint
PASS adapter: removed tool search_all_unique_properties answers with a hint
PASS adapter: removed tool replace_all_matching_properties answers with a hint
PASS adapter: removed tool set_variables answers with a hint
PASS adapter: an empty document is refused over a non-empty file
PASS adapter: the refused save left the file byte-identical
PASS adapter: a save over a file rewritten behind the session is refused as stale
PASS adapter: the stale refusal left the file byte-identical
RECORD adapter open_document on an unrecognised document version: isError: open failed: <WORK>/adapter-version.pen holds 3 top-level node(s) on disk but loaded empty; it was not modified No other tool runs unt
PASS adapter: a canary credential appears nowhere in adapter stderr or any tool result (raw, base64, urlencoded)
```
