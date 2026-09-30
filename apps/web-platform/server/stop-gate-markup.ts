// Pure helper: removes the plugin Stop hook's `<stop>OPERATOR-GATE|BLOCKED ...</stop>`
// escape-hatch markup from an assistant text block before the cc runner hands it to
// `onText`.
//
// Why this exists: `plugins/soleur/hooks/unkept-promise-hook.sh` is an operator-CLI
// guard whose block reason tells the model to write `<stop>OPERATOR-GATE: ...</stop>`
// (or `<stop>BLOCKED: ...</stop>`). In the web Concierge that tag replaced the model's
// own question list (text is replaced per block, W8). The env opt-out in `agent-env.ts`
// removes the producer; this strip is a second boundary on the cc runner's text path.
// It is NOT a boundary for every surface: tool inputs, the legacy agent-runner, Codex
// frames and the SDK transcript are outside it (see the ADR-093 amendment).
//
// Scope is deliberately the hook's own vocabulary, mirroring the hook's grep
// (`<stop>[[:space:]]*(OPERATOR-GATE|BLOCKED)`): an attribute-less `<stop>` followed by
// one of those two words. Anything wider corrupts legitimate replies — an SVG gradient
// answer carries `<stop offset="0" .../>` elements, and prose can mention the tag.
//
// Linear by construction: every `indexOf` starts where the previous one ended, so
// many openers with no closer cannot make it quadratic (a lazy `[\s\S]*?` regex did).
//
// Harness vocabulary is hard-coded here on purpose and must not grow into a
// permanent tag allowlist. Remove this file once the producer is confirmed gone in
// production (the `stop-gate-markup-stripped` Sentry op staying at zero is that
// evidence); the parity guard classifies Stop hooks but never observes markup.

export interface StopGateStripResult {
  /** The text with every stop-gate span removed and, when any was found, tidied. */
  text: string;
  /** True when at least one sentinel span (terminated or not) was found. */
  hadMarkup: boolean;
  /** True when nothing but markup was present. */
  markupOnly: boolean;
}

const OPEN = "<stop>";
const CLOSE = "</stop>";
// The sentinel word must follow the opener within this many characters (whitespace
// only in between), so the lookahead stays bounded.
const SENTINEL_WINDOW = 48;
const SENTINEL = /^\s*(?:operator-gate|blocked)/;

export function stripStopGateMarkup(input: string): StopGateStripResult {
  if (!input) return { text: input, hadMarkup: false, markupOnly: false };
  const lower = input.toLowerCase();
  let out = "";
  let pos = 0;
  let hadMarkup = false;
  let i = lower.indexOf(OPEN);
  while (i !== -1) {
    const after = i + OPEN.length;
    if (!SENTINEL.test(lower.slice(after, after + SENTINEL_WINDOW))) {
      // A `<stop>` that is not the hook's sentinel: leave it alone.
      i = lower.indexOf(OPEN, after);
      continue;
    }
    hadMarkup = true;
    out += input.slice(pos, i);
    const close = lower.indexOf(CLOSE, after);
    if (close === -1) {
      // Unterminated sentinel: everything from here is the model's gate text.
      pos = input.length;
      break;
    }
    pos = close + CLOSE.length;
    i = lower.indexOf(OPEN, pos);
  }
  if (!hadMarkup) return { text: input, hadMarkup: false, markupOnly: false };
  out += input.slice(pos);
  // A nested sentinel leaves the outer closer behind; drop stray closers, then tidy
  // the blank lines a removed mid-text span leaves.
  const text = out
    .replace(/<\/stop\s*>/gi, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  return { text, hadMarkup: true, markupOnly: text.length === 0 };
}
