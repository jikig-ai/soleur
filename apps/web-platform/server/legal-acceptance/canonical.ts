/**
 * Text registry for founder legal acceptances (#12011, ADR-319).
 *
 * A request to accept a legal text can only be created from a committed file in `texts/<key>.md`. The `text_hash`
 * that the database binds to a decision is the sha256 of that file's RAW BYTES, so what the founder was shown and
 * what is hashed cannot differ: the card renders the same bytes it hashed. The browser never supplies text or a hash.
 *
 * File shape: an optional front-matter block, then the text.
 *
 *     ---
 *     version: 2026-11-01
 *     valid_until: 2026-12-31      (optional; after it the text is expired and no new acceptance is taken)
 *     ---
 *     The text the founder reads.
 *
 * Rules: the file name (minus `.md`) is the key and must match KEY_RE (the database CHECK is the same pattern);
 * line endings are LF only (a CR makes the bytes, and therefore the hash, differ between platforms, so it is
 * refused); `version` is required. `texts/.gitattributes` pins LF in the working tree.
 *
 * `sha256sum <file>` produces the same value, which is how the shell-side gate (PR-D) will compare it.
 *
 * DEPLOYED PATH: the server is bundled with esbuild into dist/server/index.cjs, so `__dirname` there is `dist/server` and has
 * no `texts/`; the route handlers run from the Next build under `.next`. The Dockerfile therefore COPIES the directory
 * to `/app/server/legal-acceptance/texts`, and `resolveTextsDir` falls back to `<cwd>/server/legal-acceptance/texts` when
 * the module-relative directory does not exist (cwd is /app in the image, the same convention as
 * `infra/egress-forwarder.mjs`). Bytes are copied untouched, so `sha256sum <file>` still equals the hash.
 * Proved by test/legal-acceptance/registry-embedding.test.ts (builds the real bundle layout).
 */

import { createHash } from "node:crypto";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";

export const KEY_RE = /^[a-z0-9][a-z0-9-]{0,62}$/;
export const TEXT_HASH_RE = /^[0-9a-f]{64}$/;

/** Where `texts/` lives relative to the working directory in the deployed image (and in the source tree under apps/web-platform). */
export const TEXTS_DIR_FROM_CWD = path.join("server", "legal-acceptance", "texts");

/**
 * The registry directory: next to this module when it exists (source tree, vitest), else under the working directory
 * (the deployed image, where this code runs from `dist/server` or `.next`). When neither exists the module-relative
 * path is returned so a missing directory fails the same way it always did (unknown_key, never a guess).
 */
export function resolveTextsDir(
  opts: { moduleDir?: string; cwd?: string; exists?: (p: string) => boolean } = {},
): string {
  const moduleDir = "moduleDir" in opts ? opts.moduleDir : typeof __dirname === "string" ? __dirname : undefined;
  const cwd = opts.cwd ?? process.cwd();
  const exists = opts.exists ?? existsSync;
  const candidates = [...(moduleDir ? [path.join(moduleDir, "texts")] : []), path.join(cwd, TEXTS_DIR_FROM_CWD)];
  return candidates.find((c) => exists(c)) ?? candidates[0];
}

export const TEXTS_DIR = resolveTextsDir();

export class LegalTextError extends Error {
  constructor(
    public readonly code: "bad_key" | "bad_bytes" | "no_front_matter" | "bad_version" | "bad_valid_until" | "unknown_key",
    message: string,
  ) {
    super(message);
    this.name = "LegalTextError";
  }
}

export interface LegalTextEntry {
  key: string;
  version: string;
  /** ISO date (YYYY-MM-DD) or null. The text is current through the END of that day, UTC. */
  validUntil: string | null;
  textHash: string;
  /** The full raw text exactly as hashed, front matter included. */
  raw: string;
  /** The text below the front matter: what the card shows. */
  body: string;
}

/** sha256 hex of raw bytes. A string is encoded as UTF-8. Refuses CR so the hash is the same on every platform. */
export function textHash(raw: string | Uint8Array): string {
  const bytes = typeof raw === "string" ? Buffer.from(raw, "utf8") : Buffer.from(raw);
  if (bytes.includes(0x0d)) throw new LegalTextError("bad_bytes", "legal text must use LF line endings only");
  return createHash("sha256").update(bytes).digest("hex");
}

/**
 * Parse one registry file. Throws LegalTextError with a static message (the text is never echoed).
 * `raw` may be the file's bytes: the hash is taken over the BYTES and the text is decoded afterwards with invalid UTF-8
 * refused, so `sha256sum <file>` and `textHash` can never disagree (a string read with a lossy decode would).
 */
export function parseLegalText(key: string, source: string | Uint8Array): LegalTextEntry {
  if (!KEY_RE.test(key)) throw new LegalTextError("bad_key", "legal text key is not a valid key");
  const hash = textHash(source);
  let raw: string;
  try {
    raw = typeof source === "string" ? source : new TextDecoder("utf-8", { fatal: true }).decode(source);
  } catch {
    throw new LegalTextError("bad_bytes", "legal text is not valid UTF-8");
  }
  const m = /^---\n([\s\S]*?)\n---\n([\s\S]*)$/.exec(raw);
  if (!m) throw new LegalTextError("no_front_matter", "legal text has no front matter");
  const fields = new Map<string, string>();
  for (const line of m[1].split("\n")) {
    const kv = /^([a-z_]+):\s*(.*?)\s*$/.exec(line);
    if (kv) fields.set(kv[1], kv[2]);
  }
  const version = fields.get("version") ?? "";
  if (version.length < 1 || version.length > 32) throw new LegalTextError("bad_version", "legal text version is missing or too long");
  const validUntil = fields.get("valid_until") ?? null;
  if (validUntil !== null && !/^\d{4}-\d{2}-\d{2}$/.test(validUntil)) throw new LegalTextError("bad_valid_until", "valid_until must be YYYY-MM-DD");
  return { key, version, validUntil, textHash: hash, raw, body: m[2] };
}

/** True when the entry can still take a new acceptance at `now`. */
export function isCurrent(entry: LegalTextEntry, now: Date = new Date()): boolean {
  if (entry.validUntil === null) return true;
  return now.getTime() < Date.parse(`${entry.validUntil}T00:00:00Z`) + 86_400_000;
}

/** Load every `<key>.md` in a directory. Files whose name is not a valid key (README.md) are skipped. */
export function loadLegalTexts(dir: string = TEXTS_DIR): Map<string, LegalTextEntry> {
  const out = new Map<string, LegalTextEntry>();
  for (const f of readdirSync(dir)) {
    if (!f.endsWith(".md")) continue;
    const key = f.slice(0, -3);
    if (!KEY_RE.test(key)) continue;
    out.set(key, parseLegalText(key, readFileSync(path.join(dir, f))));
  }
  return out;
}

/**
 * The entry for a key, or throws `unknown_key`. The only way a request for a text is created. Reads only
 * `<key>.md`, so one malformed sibling file cannot take every key down.
 */
export function getLegalText(key: string, dir: string = TEXTS_DIR): LegalTextEntry {
  if (!KEY_RE.test(key)) throw new LegalTextError("unknown_key", "no such legal text");
  let bytes: Buffer;
  try {
    bytes = readFileSync(path.join(dir, `${key}.md`));
  } catch {
    throw new LegalTextError("unknown_key", "no such legal text");
  }
  return parseLegalText(key, bytes);
}
