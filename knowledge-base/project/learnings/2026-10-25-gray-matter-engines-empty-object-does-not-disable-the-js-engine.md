# Learning: `matter(raw, { engines: {} })` does not disable gray-matter's js engine

## Problem

`apps/web-platform/server/kb-reader.ts` parsed front matter with `matter(raw, { engines: {} })` under a comment
saying this "disables custom YAML engines, preventing code injection". gray-matter 4.0.3 MERGES `engines` over
its defaults (`Object.assign({}, engines, opts.parsers, opts.engines)` in `lib/defaults.js`), so the `js` /
`javascript` engine stays registered and a `---js` opener evaluates the block as JavaScript. Measured: a page
opening `---js` whose body was `(globalThis.X = 1, { title: 'x' })` set `X` for `---js`, `---javascript`,
`---JS`, `--- js`, `---\tjs` and `---Javascript`. The same pattern was copied into the new pattern-layer parser,
and two cron functions (`cron-content-publisher`, `cron-strategy-review`) called a bare `matter(raw)`.

## Solution

One module, `server/front-matter-guard.ts`, is the only importer of `gray-matter`. It applies two independent
defences, each sufficient alone:

1. refuse any opener line that is not `---` plus optional blanks (a language tag selects an engine);
2. override both engine names to throw (`{ js: throws, javascript: throws }`; gray-matter lowercases and aliases
   the names).

Every caller already catches a throw. `test/front-matter-guard.test.ts` pins each layer ALONE (layer 2 by
calling gray-matter directly with the overrides, with a control showing `engines: {}` does run the payload), and
`test/kb-security.test.ts` walks the whole app and fails if any other file imports `gray-matter` (static,
dynamic, `require`, side-effect forms).

## Key Insight

A security comment on a library option is a claim about the library's merge semantics; run the payload before
trusting it. And a class fixed at one call site is open at its siblings: grep the dependency's import across the
whole app, then make the fix a module that callers cannot bypass plus a source pin that fails on a new importer.

## Session Errors

None specific to this insight (see the companion learning dated 2026-10-25 for the session's process errors).

## Tags

category: security-issues
module: apps/web-platform/server/front-matter-guard
