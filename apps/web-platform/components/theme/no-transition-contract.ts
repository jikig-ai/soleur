/**
 * Shared contract between the inline boot script (`no-fouc-script.tsx`) and
 * the runtime provider (`theme-provider.tsx`). Both managers inject and
 * remove a transient `<style id="__soleur-no-transition">` to suppress CSS
 * transitions and keyframe animations for one paint frame around a theme
 * change. They MUST agree on the id and the CSS text or one side's bail
 * guard will not match the other side's element.
 *
 * The boot script cannot import at runtime — it is rendered as an inline
 * `<script dangerouslySetInnerHTML>` whose body must be self-contained
 * before the bundle loads. It interpolates these constants at build time
 * via a JS template literal, so any drift between the two files is caught
 * by the build step (TypeScript compile-time identity).
 */

export const NO_TRANSITION_STYLE_ID = "__soleur-no-transition";

export const NO_TRANSITION_CSS_TEXT =
  "* { transition: none !important; animation-duration: 0s !important; }";
