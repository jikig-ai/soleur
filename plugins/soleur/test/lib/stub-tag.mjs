// stub-tag.mjs — per-session side channels for fixtures/pencil-stub-repl.mjs. The adapter hands the child a scrubbed environment, so a tag cannot travel as an env var from the test; taggedStub() writes a one-line wrapper that sets STUB_TAG and imports the stub, and sideFile() is the one place the `<out>[.<tag>].<ext>` naming lives (stub and tests both call it).
import { chmodSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

/** `<out>.<ext>` untagged, `<out>.<tag>.<ext>` when the session has a tag (ext: log | pid | flags). */
export const sideFile = (outFile, ext, tag = process.env.STUB_TAG ?? "") => `${outFile}${tag ? `.${tag}` : ""}.${ext}`;

/** Write a mode-0755 wrapper for `stubPath` that runs it as session `tag`; returns the wrapper path (use it as PENCIL_BINARY). */
export function taggedStub(stubPath, tag, dir) {
  const wrapper = join(dir, `stub-${tag}.mjs`);
  writeFileSync(wrapper, `process.env.STUB_TAG = ${JSON.stringify(tag)}; await import(${JSON.stringify(pathToFileURL(stubPath).href)});\n`, { mode: 0o755 });
  chmodSync(wrapper, 0o755);
  return wrapper;
}
