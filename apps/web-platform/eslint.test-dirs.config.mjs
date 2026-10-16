// ESLint 9 flat config for the shrink-only unused-binding ratchet over the test and fixture
// directories that apps/web-platform's own run never reaches (#10331, PR3a).
//
// Run from the REPO ROOT by `python3 scripts/lint-ratchet.py eslint-test-dirs`, which owns the
// scope globs (test/**, plugins/soleur/test/**, plugins/soleur/skills/*/test/**,
// scripts/*.test.mjs) and the baseline. This file is deliberately separate from
// eslint.config.mjs: folding these directories into that run would re-pin the 192-count ratchet
// and the file-count floors of test/eslint-config.test.ts, a required-context test.
//
// Exactly one rule per language family, nothing else. Inline `eslint-disable` waivers are not
// honoured by the ratchet (it runs with --no-inline-config), and reporting unused directives is
// off so that mode cannot add findings of its own.
import tsPlugin from "@typescript-eslint/eslint-plugin";
import tsParser from "@typescript-eslint/parser";

const unusedOptions = { argsIgnorePattern: "^_", varsIgnorePattern: "^_" };

export default [
  { linterOptions: { reportUnusedDisableDirectives: "off" } },
  {
    files: ["**/*.js", "**/*.mjs", "**/*.cjs"],
    languageOptions: { ecmaVersion: "latest", sourceType: "module" },
    rules: { "no-unused-vars": ["warn", unusedOptions] },
  },
  {
    files: ["**/*.ts", "**/*.tsx", "**/*.mts"],
    languageOptions: {
      parser: tsParser,
      ecmaVersion: "latest",
      sourceType: "module",
      parserOptions: { ecmaFeatures: { jsx: true } },
    },
    plugins: { "@typescript-eslint": tsPlugin },
    rules: { "@typescript-eslint/no-unused-vars": ["warn", unusedOptions] },
  },
];
