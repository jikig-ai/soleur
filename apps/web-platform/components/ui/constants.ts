// Gold-gradient primary CTA fill. Colors are wired to the
// `--soleur-accent-gradient-{start,end}` theme tokens (app/globals.css) so the
// gradient stays in lockstep with the Tailwind `from-soleur-accent-gradient-*`
// utilities used by the dashboard CTAs and kb-chat-trigger — no literal hex.
// Direction is `90deg` (left→right) to match those Tailwind `bg-gradient-to-r`
// CTAs, so every gold-gradient surface shares one horizontal direction (#3334).
export const GOLD_GRADIENT =
  "linear-gradient(90deg, var(--soleur-accent-gradient-start), var(--soleur-accent-gradient-end))";
