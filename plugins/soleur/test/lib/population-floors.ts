/**
 * The anti-vacuity floors for the plugin's own component populations, in ONE place.
 *
 * WHY THIS FILE EXISTS. Four suites independently floor "how many skills are there" —
 * `grok-harness-invoke`, `harness-tool-map`, `harness-discovery-smoke` and
 * `harness-parity-tree`. They had drifted to 100 / 99 / 100 / 99 against one measured
 * population of 102, so "the floor" was really four numbers, each raised by whichever
 * review round happened to look at it. A floor's whole job is to be tight; four copies
 * guarantee the loosest one sets the real slack, and slack in a floor is deletion budget
 * (see `work/SKILL.md` §"A GUARD RUN WITHOUT THE ARGUMENT THAT BOUNDS IT").
 *
 * WHAT THESE ARE NOT. They are not expected counts and they are not ratchets — nothing
 * regenerates them. They are hand-set absolute floors whose only question is "did the
 * pathspec stop matching?". A suite that wants to assert an exact number asserts it
 * directly; these say only that the population did not collapse.
 *
 * RAISING THEM. Raise in the same edit that adds the population members, never in a later
 * tidy-up, and re-measure with the command in each constant's comment. Because every
 * consumer reads the same symbol, one edit moves all four suites — which is the point.
 */

/**
 * Tracked `plugins/soleur/skills/*\/SKILL.md`.
 *
 * Measured 2026-09-23: **102** (`git ls-files ':(glob)plugins/soleur/skills/*\/SKILL.md' | wc -l`).
 * 103 directories exist; `skills/flag-bootstrap/` carries no `SKILL.md`, so a directory
 * count and a file count legitimately differ by one here — do not "fix" one to the other.
 */
export const MIN_TRACKED_SKILLS = 99;

/**
 * Tracked `plugins/soleur/commands/*.md`. Measured 2026-09-23: **3** (`go`, `help`, `sync`).
 * Floored at 2 because #8236 may retire one, and this floor is not the place to relitigate that.
 */
export const MIN_TRACKED_COMMANDS = 2;

/**
 * Tracked `plugins/soleur/skills/*\/references/**\/*.md` — the NG-P references half that
 * entered the parity population in ADR-245. Measured 2026-09-23: **115**.
 */
export const MIN_TRACKED_REFERENCES = 110;

/**
 * Registry agents discovered by `discoverAgentPaths()`. Measured 2026-09-23: **67**.
 */
export const MIN_REGISTRY_AGENTS = 65;

/**
 * Names a harness manifest's declared roots are expected to yield.
 *
 * Distinct from `MIN_TRACKED_SKILLS` even though today they sit at the same value: this
 * one is a property of `.codex-plugin/plugin.json` / `.devin-plugin/plugin.json`, and a
 * manifest that drops `./skills` collapses it while the tree stays unchanged. Keeping the
 * two symbols separate is what lets that failure name its own cause (AP-021).
 */
export const MIN_MANIFEST_DECLARED_SKILLS = 99;
