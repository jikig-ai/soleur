// Shared 8-word-shingle similarity scorer.
//
// Extracted from `plugins/soleur/test/agent-originality.test.ts` (#8289) so a
// second consumer can REUSE the scorer instead of re-implementing it. The three
// functions were module-local in a `.test.ts` with zero `export` statements, so
// "reuse, do not re-implement" was unsatisfiable until they moved here.
//
// Provenance and calibration both stay where they already are, deliberately:
// the methodology-attribution header and the threshold-calibration record live
// in `../agent-originality.test.ts`, which is the artifact that owns the
// decision. Restating either here would create a second copy that drifts from
// the first, and the drifting copy is the one a future reader lands on. Read
// that file's header before changing the neutralization or the window size.
//
// The ONE thing a caller must know: an artifact with zero shingles shares zero
// shingles with everything and therefore passes a "0 shared shingles" bar
// trivially. A file that is mostly headings, field names and answer stubs can
// normalize to fewer words than one window. So every comparison built on this
// module needs a non-vacuity floor on its own inputs — assert the input yields
// at least N distinct shingles BEFORE reading any overlap count. `jaccard`
// returns 0 for an empty set for the same reason, and that 0 means
// "incomparable", never "distinct".

/** Default shingle window, in words. */
export const SHINGLE_N = 8;

/**
 * Minimal neutralization: lowercase, and collapse every run of
 * non-alphanumeric characters to a single space. Deliberately does NOT
 * neutralize proper nouns — see `../agent-originality.test.ts` for why that
 * upstream behaviour was dropped.
 */
export function neutralize(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9\s]+/g, " ");
}

/**
 * The set of distinct n-word shingles in `text`, after neutralization.
 * Returns an empty set when the text normalizes to fewer than `n` words.
 */
export function shingles(text: string, n = SHINGLE_N): Set<string> {
  const words = neutralize(text).split(/\s+/).filter(Boolean);
  const out = new Set<string>();
  for (let i = 0; i + n <= words.length; i++) {
    out.add(words.slice(i, i + n).join(" "));
  }
  return out;
}

/**
 * Jaccard similarity of two shingle sets, in [0,1]. Returns 0 when either set
 * is empty — which means "incomparable", not "distinct". Guard for emptiness at
 * the call site rather than reading a 0 as a pass.
 */
export function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let inter = 0;
  for (const s of a) if (b.has(s)) inter++;
  return inter / (a.size + b.size - inter);
}

/** The shingles `a` and `b` share. Its `.size` is the shared-shingle count. */
export function sharedShingles(a: Set<string>, b: Set<string>): Set<string> {
  const out = new Set<string>();
  for (const s of a) if (b.has(s)) out.add(s);
  return out;
}
