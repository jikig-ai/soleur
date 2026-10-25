// The ONE place server code may call gray-matter (a source test pins that no bare `matter(` or
// `gray-matter` import survives elsewhere under server/). gray-matter MERGES the `engines` option over
// its built-in engines, so `engines: {}` does NOT remove the `js` engine: a `---js` / `---javascript`
// opener evaluates the block as JavaScript inside the web process. Two independent defences, either
// of which is sufficient on its own:
//   1. only a plain `---` opener is parsed (a language tag on the opener line selects an engine);
//   2. both JS engine names are overridden to throw.
// Both failure modes THROW; every caller already treats a throw as "no usable front matter".
import matter from "gray-matter";

const disabled = (): never => {
  throw new Error("js front matter is disabled");
};

/** Engine overrides that make the `js` / `javascript` engines (and their case aliases) throw. */
export const SAFE_MATTER_OPTIONS = { engines: { js: disabled, javascript: disabled } } as const;

/** True when the first line is `---` plus optional trailing blanks (optional BOM, LF or CRLF). */
export function hasPlainFrontMatterOpener(raw: string): boolean {
  return /^﻿?---[ \t]*\r?\n/.test(raw);
}

/** True when the text opens a front-matter block that carries a language tag (or any other junk). */
export function hasTaggedFrontMatterOpener(raw: string): boolean {
  return /^﻿?---[^\r\n]*[\r\n]/.test(raw) && !hasPlainFrontMatterOpener(raw);
}

/** Parse front matter without ever evaluating it. Throws on a tagged opener or a js engine request. */
export function parseFrontMatterSafe(raw: string): matter.GrayMatterFile<string> {
  if (hasTaggedFrontMatterOpener(raw)) throw new Error("tagged front matter opener is refused");
  return matter(raw, SAFE_MATTER_OPTIONS);
}
