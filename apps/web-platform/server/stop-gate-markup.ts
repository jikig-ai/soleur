// Pure helper: removes the plugin Stop hook's `<stop>...</stop>` escape-hatch
// markup from an assistant text block before it reaches any user-visible surface.
//
// Why this exists: `plugins/soleur/hooks/unkept-promise-hook.sh` is an operator-CLI
// guard whose block reason tells the model to write `<stop>OPERATOR-GATE: ...</stop>`.
// In the web Concierge that tag replaced the model's own question list (text is
// replaced per block, W8). The env opt-out in `agent-env.ts` removes the producer;
// this strip is the boundary that keeps the markup off the screen whichever layer
// produces it.
//
// Harness vocabulary is hard-coded here on purpose. Remove this file once the
// plugin-stop-hooks-web-parity guard has run clean for several releases; it must
// not grow into a permanent tag allowlist. Fenced code samples containing the tag
// are out of scope and are stripped like any other occurrence.

export interface StopGateStripResult {
  /** The text with every stop-gate tag removed and the result trimmed. */
  text: string;
  /** True when at least one tag (terminated or not) was found. */
  hadMarkup: boolean;
  /** True when nothing but markup was present. */
  markupOnly: boolean;
}

// `<stop>` or `<stop attr...>`, case-insensitive. The `[\s>]` guard keeps
// lookalikes such as `<stopwatch>` and `<stops>` out.
const OPEN_TAG = /<stop(?=[\s>])[^>]*>/i;
const TERMINATED = /<stop(?=[\s>])[^>]*>[\s\S]*?<\/stop\s*>/gi;

export function stripStopGateMarkup(input: string): StopGateStripResult {
  if (!input || !OPEN_TAG.test(input)) {
    return { text: input, hadMarkup: false, markupOnly: false };
  }
  // Terminated pairs first (non-greedy, so two tags do not swallow the prose
  // between them), then truncate at any remaining unterminated opening tag.
  let out = input.replace(TERMINATED, "");
  const open = out.search(OPEN_TAG);
  if (open >= 0) out = out.slice(0, open);
  // A removed mid-text tag leaves a run of blank lines; collapse it to one.
  const text = out.replace(/\n{3,}/g, "\n\n").trim();
  return { text, hadMarkup: true, markupOnly: text.length === 0 };
}
