// pencil-save-gate.mjs — pure decision function for auto-save after a
// pencil REPL mutation. Extracted so it can be unit-tested without
// importing the adapter.
//
// Why this exists: the adapter previously called save() unconditionally
// after every mutating op (batch_design, open_document, set_variables,
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
// top-level node. The check compares the live file with the live document, so
// there is no stored value for an edit to weaken.
//
// Known limit: this catches empty-over-non-empty, not partial truncation or a
// lower node count.

/**
 * Top-level node count of the .pen text on disk. null when there is nothing
 * recoverable to protect: missing, empty or unparseable text.
 */
export function diskTopLevelCount(text) {
  if (text === null || text === undefined) return null;
  const s = String(text);
  if (s.trim() === "") return null;
  let doc;
  try {
    doc = JSON.parse(s);
  } catch {
    return null;
  }
  if (doc && typeof doc === "object" && Array.isArray(doc.children)) {
    return doc.children.length;
  }
  return 0;
}

/**
 * Top-level node count of the in-memory document from a `batch_get()` result.
 * null when the shape cannot be determined (the caller must treat that as
 * unsafe, not as zero).
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
    return { allow: true, reason: "target missing, empty or unparseable: nothing to protect" };
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

export function refusalMessage({ file, source, diskCount, memoryCount }) {
  const mem = memoryCount === null || memoryCount === undefined ? "unreadable" : String(memoryCount);
  const lines = [
    `REFUSED save: ${file} was not modified.`,
    `It holds ${diskCount} top-level node(s) on disk, but the in-memory document has ${mem}; saving would replace the file with an empty document.`,
    "Likely cause: the file was never loaded into this session (call open_document on it, which now loads the existing content).",
    "To start a design from scratch, open_document a new file path instead.",
    "Do not delete or recreate the file to bypass this check.",
  ];
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
 *
 * @param {{ file: string, source: "save"|"auto-save", readDisk: () => Promise<string|null>,
 *           probeMemory: () => Promise<string|null>, send: () => Promise<string> }} deps
 */
export async function runGuardedSave({ file, source, readDisk, probeMemory, send }) {
  const diskCount = diskTopLevelCount(await readDisk());
  let memoryCount = null;
  if (diskCount !== null && diskCount > 0) {
    memoryCount = memoryTopLevelCount(await probeMemory());
  }
  const decision = decideSave({ diskCount, memoryCount });
  if (!decision.allow) {
    return {
      saved: false,
      refused: true,
      reason: decision.reason,
      message: refusalMessage({ file, source, diskCount, memoryCount }),
    };
  }
  const raw = await send();
  return { saved: true, refused: false, raw };
}
