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

// --- Empty-overwrite sentinel (#11143) and stale-file guard (#11168) --------
//
// The headless engine writes only on `save()`, and a document opened without
// `--in` is empty, so any save over an existing .pen replaced it with the
// 96-byte empty document. Every save now goes through `runGuardedSave`:
//   1. an empty in-memory document is never written over a file that still holds
//      a top-level node, and nothing is written over a file that exists but is not
//      a recognizable .pen document (`decideSave`, #11143; compares the live file
//      with the live document, so there is no stored value for an edit to weaken);
//   2. a save never replaces a file whose content differs from what THIS session
//      last loaded or last saved (`decideStale`, #11168; compares a stored
//      baseline with a fresh read taken after the memory probe, immediately
//      before the engine's `save()`).
// Limits: a second writer between the fresh read and the engine's write is not
// caught, and the post-save read adopts whatever is on disk at that instant.

import { createHash } from "node:crypto";
import { parseCountReply } from "./pencil-repl-surface.mjs";

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
  let s = Buffer.isBuffer(text) ? text.toString("utf8") : String(text);
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
 * Top-level node count of the in-memory document from the reply to the adapter's
 * count snippet (`execute` printing `TOPLEVEL_COUNT:<nonce>:<n>`). Exactly one
 * line carrying THIS call's nonce counts; zero lines, two lines, another nonce or
 * an error reply give null (the caller must treat that as unsafe, not as zero).
 * Pass the UNTRUNCATED reply text.
 */
export function memoryTopLevelCount(replyText, nonce) {
  if (replyText === null || replyText === undefined) return null;
  return parseCountReply(replyText, nonce);
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

const NEVER_BYPASS = "Do not delete or recreate the file to bypass this check.";

/**
 * Refusal text. `stale` selects the #11168 family (a decideStale code; `changed`
 * is an alias of `stale`); without it the #11143 texts apply, unchanged.
 */
export function refusalMessage({ file, source, diskCount, memoryCount, memoryReason, diskReason, stale, cause, detail, restarted }) {
  const lines = [`REFUSED save: ${file} was not modified.`];
  if (stale) {
    const code = stale === "changed" ? "stale" : stale;
    if (code === "stale") {
      lines.push(
        "It changed on disk since this session loaded or last saved it (another session, git, or an editor such as Pencil Desktop). Edits made since are not persisted, and re-opening discards them.",
        `Next step: stop editing, call open_document on ${file}, then replay the refused operations in order. Keep one writer per file (there is no lock). ${NEVER_BYPASS} If open_document itself fails on the changed file, stop: do not retry or recreate it, and tell the user the file was changed by another tool.`
      );
    } else if (code === "missing") {
      lines.push(
        "The file no longer exists on disk: it was removed or renamed since this session loaded or last saved it. Edits made since are not persisted.",
        `Next step: tell the user the file was removed by another tool, then call open_document on ${file} (this starts a new empty document, so replay the refused operations in order) or open_document a different new path. Keep one writer per file. ${NEVER_BYPASS}`
      );
    } else if (code === "refusal-pending") {
      lines.push(
        restarted
          ? "An earlier save was refused because the file changed on disk, and the session restarted since: the earlier edits were discarded when the engine reloaded the file. Edits made since are not persisted."
          : "An earlier save was refused because the file changed on disk, and no open_document has succeeded since. Edits made since are not persisted, and re-opening discards them.",
        `Next step: call open_document on ${file}, then replay the refused operations in order. Keep one writer per file (there is no lock). ${NEVER_BYPASS} If open_document itself fails on the changed file, stop: do not retry or recreate it, and tell the user the file was changed by another tool.`
      );
    } else {
      // unknown-baseline: why the session cannot say what is on disk
      const why =
        cause === "unconfirmed-save"
          ? "The last save was not confirmed by the engine (its reply was not `Saved <file>`), so what is on disk is unknown: the edit may or may not have been written."
          : cause === "post-save-read-failed"
            ? `The last save was confirmed, but the file could not be read back afterwards${detail ? ` (${detail})` : ""}, so the session cannot tell whether what is on disk is what it saved.`
            : cause === "capture-failed"
              ? `The file could not be read to compare it with this session's copy${detail ? ` (${detail})` : ""}: it may have been replaced by a link or a special file.`
              : "This session has no record of what it loaded from the file, so it cannot tell whether the file changed.";
      lines.push(
        why,
        `Next step: call open_document on ${file} (it reloads what is on disk and re-baselines), then replay the refused operations in order. Keep one writer per file. ${NEVER_BYPASS} If open_document itself fails, stop and tell the user.`
      );
    }
  } else if (diskCount === DISK_UNRECOGNIZED) {
    lines.push(
      `It exists but is not a recognizable .pen document${diskReason ? ` (${diskReason})` : ""}: unparseable JSON, git conflict markers, or not a Pencil file. The engine would load it as an empty document and the save would destroy content you may still be able to recover.`,
      `Next step: open_document a new file path and continue the design there. ${NEVER_BYPASS}`
    );
  } else if (memoryCount === null || memoryCount === undefined) {
    lines.push(
      `It holds ${diskCount} top-level node(s) on disk, but the in-memory document could not be read${memoryReason ? `: ${memoryReason}` : ""}, so the save could not be checked.`,
      `Next step: retry the call; if it keeps failing, open_document a new file path. ${NEVER_BYPASS}`
    );
  } else {
    lines.push(
      `It holds ${diskCount} top-level node(s) on disk, but the in-memory document has ${memoryCount}; saving would replace the file with an empty document.`,
      `Likely cause: the file was never loaded into this session. Next step: call open_document on this file (it now loads the existing content), then re-apply the edit; to start over instead, open_document a new file path. ${NEVER_BYPASS}`
    );
  }
  if (source === "auto-save") {
    lines.push(
      "The edit you just made is applied in memory but not persisted, and will be lost on the next open_document."
    );
  }
  return lines.join("\n");
}

// --- The stale-file guard (#11168) -------------------------------------------
//
// The session keeps ONE baseline of the file it is bound to, as a tagged value:
//   { tag: "none" }                          no target bound
//   { tag: "missing" }                       the file was absent when captured
//   { tag: "hash", hash }                    SHA-256 of the canonical document
//   { tag: "unknown", cause, detail? }       a capture, a read-back or a save reply failed
// A present blank file is a `hash` (of the empty bytes), not `missing`.

/**
 * SHA-256 (hex) of the canonical JSON of the document: BOM stripped,
 * JSON.stringify(JSON.parse(text)), so line endings, indentation and a formatter
 * cannot make every save refuse. Text that does not parse is hashed as the raw
 * bytes (any change to it is a change).
 */
export function fingerprintBytes(bytes) {
  const buf = Buffer.isBuffer(bytes) ? bytes : Buffer.from(String(bytes ?? ""), "utf8");
  let text = buf.toString("utf8");
  if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  let material = buf;
  try {
    material = Buffer.from(JSON.stringify(JSON.parse(text)), "utf8");
  } catch {
    // not a JSON document: the raw bytes are the fingerprint
  }
  return createHash("sha256").update(material).digest("hex");
}

/** Bytes (Buffer|string) or null (the file does not exist) -> a baseline state. */
export function fingerprintState(bytes) {
  if (bytes === null || bytes === undefined) return { tag: "missing" };
  return { tag: "hash", hash: fingerprintBytes(bytes) };
}

/** First 8 hex characters of a hash, for log lines (never the full value). */
export function hash8(hash) {
  return typeof hash === "string" && /^[0-9a-f]{8,}$/.test(hash) ? hash.slice(0, 8) : "-";
}

/**
 * The stale check: a pure function of the stored baseline, the file as it is now
 * and the refusalPending flag. Only an exact `missing`/`hash` match allows.
 *
 * @returns {{ allow: true } | { allow: false, code: "stale"|"missing"|"unknown-baseline"|"refusal-pending",
 *            arm: boolean, cause?: string, detail?: string, baselineHash?: string, diskHash?: string, reason: string }}
 */
export function decideStale({ baseline, current, refusalPending }) {
  const baselineHash = baseline?.tag === "hash" ? baseline.hash : undefined;
  const diskHash = current?.tag === "hash" ? current.hash : undefined;
  const refuse = (code, reason, extra = {}) => ({ allow: false, code, reason, arm: false, baselineHash, diskHash, ...extra });
  if (refusalPending) {
    return refuse("refusal-pending", "an earlier save was refused as stale and no open_document has succeeded since");
  }
  if (!baseline || (baseline.tag !== "missing" && baseline.tag !== "hash" && baseline.tag !== "unknown")) {
    return refuse("unknown-baseline", "no baseline: the session has no record of what it loaded", { cause: "no-baseline" });
  }
  if (baseline.tag === "unknown") {
    return refuse("unknown-baseline", "the session cannot tell what is on disk", { cause: baseline.cause ?? "unknown", detail: baseline.detail });
  }
  if (!current || current.tag === "unknown") {
    return refuse("unknown-baseline", "the file could not be read to compare it", {
      cause: current?.cause ?? "capture-failed",
      detail: current?.detail,
    });
  }
  if (baseline.tag === "missing") {
    return current.tag === "missing"
      ? { allow: true }
      : refuse("stale", "the file appeared on disk after this session started on a missing path", { arm: true });
  }
  // baseline.tag === "hash"
  if (current.tag === "missing") return refuse("missing", "the file was removed from disk behind the session", { arm: true });
  if (current.tag === "hash" && current.hash === baseline.hash) return { allow: true };
  return refuse("stale", "the file changed on disk since this session loaded or last saved it", { arm: true });
}

/** The path of exactly one `Saved <path>` line (ANSI stripped, trimmed), else null. */
export function savedReplyPath(raw) {
  if (typeof raw !== "string") return null;
  const text = raw.replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "").trim();
  const m = /^Saved ([^\n]+)$/.exec(text);
  return m ? m[1].trim() : null;
}

const sleepMs = (ms) => new Promise((r) => setTimeout(r, ms));

function requireDeps(deps, names) {
  for (const name of names) {
    if (typeof deps[name] !== "function") {
      throw new TypeError(`runGuardedSave: dependency '${name}' is required (an unguarded save path is not allowed)`);
    }
  }
}

/**
 * The only save path. Dependencies are injected so the ordering (checks before
 * save, no save sent on refusal) is unit-testable without the MCP SDK.
 *
 *   readDisk()        bytes (Buffer|string) or null when the file does not exist; may throw
 *   probeMemory()     { text, nonce }: the count-snippet reply and the nonce it carried; may throw
 *   readFresh()       like readDisk, called AFTER the probe, immediately before the save
 *   getBaseline()     the stored baseline state
 *   isRefusalPending() the refusalPending flag
 *   send()            emits the engine's save and returns its reply (the adapter's one emission site)
 *   isConfirmed(raw)  true only for `Saved <this file>`
 *   readAfterSave()   bytes after a confirmed save; retried 3 times
 *   adoptBaseline(s)  stores a new baseline state (called once per save, after `send`)
 *   wasRestarted()    optional: true when the engine was respawned while a refusal was pending (wording only)
 *
 * Order: readDisk, probeMemory (only when the file holds nodes), decideSave
 * (empty / unrecognized), readFresh, decideStale, send, readAfterSave, adoptBaseline.
 */
export async function runGuardedSave(deps) {
  requireDeps(deps, [
    "readDisk",
    "probeMemory",
    "readFresh",
    "getBaseline",
    "isRefusalPending",
    "send",
    "isConfirmed",
    "readAfterSave",
    "adoptBaseline",
  ]);
  const { file, source, readDisk, probeMemory, readFresh, getBaseline, isRefusalPending, send, isConfirmed, readAfterSave, adoptBaseline } = deps;
  const retryDelayMs = deps.retryDelayMs ?? 100;

  let diskCount;
  let diskReason;
  let diskErrCode;
  let diskBytes;
  try {
    diskBytes = await readDisk();
    diskCount = diskTopLevelCount(diskBytes);
  } catch (err) {
    diskReason = String(err?.message ?? err);
    diskErrCode = err?.code;
    return {
      saved: false,
      refused: true,
      code: "unknown-baseline",
      cause: "capture-failed",
      detail: diskErrCode,
      reason: `the file could not be read: ${diskReason}`,
      message: refusalMessage({ file, source, stale: "unknown-baseline", cause: "capture-failed", detail: diskReason }),
    };
  }

  let memoryCount = null;
  let memoryReason;
  if (typeof diskCount === "number" && diskCount > 0) {
    try {
      const { text, nonce } = await probeMemory();
      memoryCount = memoryTopLevelCount(text, nonce);
      if (memoryCount === null) memoryReason = "the count probe reply carried no single count line with this call's nonce";
    } catch (err) {
      memoryReason = String(err?.message ?? err);
    }
  }
  const decision = decideSave({ diskCount, memoryCount });
  if (!decision.allow) {
    return {
      saved: false,
      refused: true,
      code: diskCount === DISK_UNRECOGNIZED ? "unrecognized" : "empty",
      reason: decision.reason,
      message: refusalMessage({ file, source, diskCount, memoryCount, memoryReason, diskReason }),
    };
  }

  // The stale decision uses a read taken NOW (after the probe), not the first one.
  let current;
  try {
    current = fingerprintState(await readFresh());
  } catch (err) {
    current = { tag: "unknown", cause: "capture-failed", detail: String(err?.code ?? err?.message ?? err) };
  }
  const stale = decideStale({ baseline: getBaseline(), current, refusalPending: isRefusalPending() });
  if (!stale.allow) {
    return {
      saved: false,
      refused: true,
      code: stale.code,
      reason: stale.reason,
      arm: stale.arm,
      cause: stale.cause,
      detail: stale.detail,
      baselineHash: stale.baselineHash,
      diskHash: stale.diskHash,
      message: refusalMessage({
        file,
        source,
        stale: stale.code,
        cause: stale.cause,
        detail: stale.detail,
        restarted: typeof deps.wasRestarted === "function" ? Boolean(deps.wasRestarted()) : false,
      }),
    };
  }

  const raw = await send();
  if (!isConfirmed(raw)) {
    adoptBaseline({ tag: "unknown", cause: "unconfirmed-save" });
    return { saved: false, refused: false, unconfirmed: true, raw };
  }
  let after = null;
  let lastErr = null;
  for (let attempt = 0; attempt < 3 && after === null; attempt++) {
    if (attempt > 0) await sleepMs(retryDelayMs);
    try {
      after = fingerprintState(await readAfterSave());
      if (after.tag === "missing") {
        lastErr = new Error("the file is missing right after a confirmed save");
        lastErr.code = "ENOENT";
        after = null;
      }
    } catch (err) {
      lastErr = err;
      after = null;
    }
  }
  if (after === null) {
    adoptBaseline({ tag: "unknown", cause: "post-save-read-failed" });
    return {
      saved: true,
      refused: false,
      confirmed: true,
      raw,
      detail: String(lastErr?.code ?? lastErr?.message ?? lastErr),
      warning: `The save was confirmed, but the file could not be read back (${String(lastErr?.code ?? lastErr?.message ?? lastErr)}); the next save is refused until open_document is called on it.`,
    };
  }
  adoptBaseline(after);
  return { saved: true, refused: false, confirmed: true, raw };
}
