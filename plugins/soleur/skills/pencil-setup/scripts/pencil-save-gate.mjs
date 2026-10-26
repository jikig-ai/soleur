// pencil-save-gate.mjs — pure decision function for auto-save after a
// pencil REPL mutation. Extracted so it can be unit-tested without
// importing the adapter.
//
// Why this exists: the adapter previously called save() unconditionally
// after every mutating op (batch_design, open_document,
// etc.). When a mutation errored (auth failure, invalid property), the
// follow-up save() still ran and wrote a 0-byte or stale .pen file to
// disk. The caller saw a successful save but no real content — the
// "silent drop" that preceded #2630's fabricated "headless stub"
// narrative.

/**
 * Decide whether to SKIP the post-mutation save() call.
 *
 * Returns true only when the last classification explicitly reports
 * isError === truthy. Missing/null/undefined classifications allow
 * the save (preserves existing behavior for first-call and for callers
 * that don't track classifications).
 */
export function shouldSkipSave(lastClassification) {
  if (!lastClassification || typeof lastClassification !== "object") {
    return false;
  }
  return Boolean(lastClassification.isError);
}

// --- Empty-overwrite sentinel (#11143) ---------------------------------
//
// The headless engine writes only on `save()`, and a document opened without
// `--in` is empty, so any save over an existing .pen replaced it with the
// 96-byte empty document. Every save now goes through `runGuardedSave`: an
// empty in-memory document is never written over a file that still holds a
// top-level node, and nothing is written over a file that exists but is not a
// recognizable .pen document. The check compares the live file with the live
// document, so there is no stored value for an edit to weaken.
//
// Known limits: this catches empty-over-non-empty, not partial truncation or a
// lower node count, and it cannot see a second writer between the disk read
// and the engine write.

/** The file exists with content, but it is not a document the engine can load back. */
export const DISK_UNRECOGNIZED = "unrecognized";

/**
 * State of the .pen text on disk:
 *   null               missing or blank: nothing recoverable to protect
 *   a number           a parseable document with that many top-level nodes
 *   DISK_UNRECOGNIZED  non-blank text that is not a .pen document (unparseable
 *                      JSON, a git conflict, a document with no children array).
 *                      The engine loads such a file as an EMPTY document without
 *                      an error, so the next save would destroy hand-recoverable
 *                      content.
 */
export function diskTopLevelCount(text) {
  if (text === null || text === undefined) return null;
  let s = String(text);
  if (s.charCodeAt(0) === 0xfeff) s = s.slice(1);
  if (s.trim() === "") return null;
  let doc;
  try {
    doc = JSON.parse(s);
  } catch {
    return DISK_UNRECOGNIZED;
  }
  if (doc && typeof doc === "object" && Array.isArray(doc.children)) {
    return doc.children.length;
  }
  return DISK_UNRECOGNIZED;
}

/**
 * Top-level node count of the in-memory document from a `batch_get()` result.
 * null when the shape cannot be determined (the caller must treat that as
 * unsafe, not as zero). Pass the UNTRUNCATED text: a capped response is not
 * valid JSON and would read as unreadable.
 */
export function memoryTopLevelCount(batchGetText) {
  if (batchGetText === null || batchGetText === undefined) return null;
  let parsed;
  try {
    parsed = JSON.parse(String(batchGetText));
  } catch {
    return null;
  }
  if (Array.isArray(parsed)) return parsed.length;
  if (parsed && typeof parsed === "object" && Array.isArray(parsed.nodes)) {
    return parsed.nodes.length;
  }
  return null;
}

/**
 * @returns {{ allow: boolean, reason: string }}
 */
export function decideSave({ diskCount, memoryCount }) {
  if (diskCount === null || diskCount === undefined) {
    return { allow: true, reason: "target missing or blank: nothing to protect" };
  }
  if (diskCount === DISK_UNRECOGNIZED) {
    return {
      allow: false,
      reason: "target exists but is not a recognizable .pen document",
    };
  }
  if (diskCount === 0) {
    return { allow: true, reason: "target holds no nodes: nothing to protect" };
  }
  if (memoryCount === null || memoryCount === undefined) {
    return {
      allow: false,
      reason: `target holds ${diskCount} top-level node(s) and the in-memory document could not be read`,
    };
  }
  if (memoryCount === 0) {
    return {
      allow: false,
      reason: `target holds ${diskCount} top-level node(s) but the in-memory document is empty`,
    };
  }
  return { allow: true, reason: `in-memory document has ${memoryCount} top-level node(s)` };
}

export function refusalMessage({ file, source, diskCount, memoryCount, memoryReason, diskReason }) {
  const lines = [`REFUSED save: ${file} was not modified.`];
  if (diskCount === DISK_UNRECOGNIZED) {
    lines.push(
      `It exists but is not a recognizable .pen document${diskReason ? ` (${diskReason})` : ""}: unparseable JSON, git conflict markers, or not a Pencil file. The engine would load it as an empty document and the save would destroy content you may still be able to recover.`,
      "Next step: open_document a new file path and continue the design there. Do not delete or recreate the file to bypass this check."
    );
  } else if (memoryCount === null || memoryCount === undefined) {
    lines.push(
      `It holds ${diskCount} top-level node(s) on disk, but the in-memory document could not be read${memoryReason ? `: ${memoryReason}` : ""}, so the save could not be checked.`,
      "Next step: retry the call; if it keeps failing, open_document a new file path. Do not delete or recreate the file to bypass this check."
    );
  } else {
    lines.push(
      `It holds ${diskCount} top-level node(s) on disk, but the in-memory document has ${memoryCount}; saving would replace the file with an empty document.`,
      "Likely cause: the file was never loaded into this session. Next step: call open_document on this file (it now loads the existing content), then re-apply the edit; to start over instead, open_document a new file path. Do not delete or recreate the file to bypass this check."
    );
  }
  if (source === "auto-save") {
    lines.push(
      "The edit you just made is applied in memory but not persisted, and will be lost on the next open_document."
    );
  }
  return lines.join("\n");
}

/**
 * The only save path. Dependencies are injected so the ordering (check before
 * save, no save sent on refusal) is unit-testable without the MCP SDK.
 * `readDisk` and `probeMemory` may throw: a throw is an UNKNOWN state, never a
 * clean one, and its message is carried into the refusal.
 *
 * @param {{ file: string, source: "save"|"auto-save", readDisk: () => Promise<string|null>,
 *           probeMemory: () => Promise<string|null>, send: () => Promise<string> }} deps
 */
export async function runGuardedSave({ file, source, readDisk, probeMemory, send }) {
  let diskCount;
  let diskReason;
  try {
    diskCount = diskTopLevelCount(await readDisk());
  } catch (err) {
    diskCount = DISK_UNRECOGNIZED;
    diskReason = String(err?.message ?? err);
  }
  let memoryCount = null;
  let memoryReason;
  if (typeof diskCount === "number" && diskCount > 0) {
    try {
      memoryCount = memoryTopLevelCount(await probeMemory());
      if (memoryCount === null) memoryReason = "its batch_get() result was not a node list";
    } catch (err) {
      memoryReason = String(err?.message ?? err);
    }
  }
  const decision = decideSave({ diskCount, memoryCount });
  if (!decision.allow) {
    return {
      saved: false,
      refused: true,
      reason: decision.reason,
      message: refusalMessage({ file, source, diskCount, memoryCount, memoryReason, diskReason }),
    };
  }
  const raw = await send();
  return { saved: true, refused: false, raw };
}
