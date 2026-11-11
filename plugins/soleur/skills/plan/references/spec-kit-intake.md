# Spec Kit intake

Read this only when the branch `spec.md` is absent and the argument is an existing `specs/<prefix>-<short-name>/` directory. Prefix is three digits or `YYYYMMDD-HHMMSS`. The short-name starts with a letter or digit.

Capture `pwd` before any `cd`. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/spec-kit-intake.sh"`. Pass that `pwd` as `--cwd` when `--dir` is relative. An argument that is already absolute is `--dir` as given, including after one-shot has changed directory.

On non-zero, stop. Do not edit the kit directory, do not run the script again, and do not paste the path as prose. A refusal is final.

On zero, show the receipt. Save the projected body, the text after the single `--- projected ---` line, as `knowledge-base/project/specs/<branch>/spec.md` only when that file is absent. Then plan from the saved file. Do not replace an existing file, including a zero-byte file. An empty spec directory is not the stop.

The script writes nothing. `plan.md` and `tasks.md` are side evidence under `--- side-evidence ---`, indented four spaces, and are not requirements. The receipt lists what moved, what was unmapped, and the never-read names `research.md`, `data-model.md`, `contracts`, and `quickstart.md`.
