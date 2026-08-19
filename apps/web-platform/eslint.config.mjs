// ESLint 9 flat config for apps/web-platform (#1327).
//
// Replaces `next lint`, which Next.js 16 removes and which could not run here
// anyway: there was no config, so it dropped into an interactive
// "configure ESLint?" prompt and exited 1.
//
// WHY eslint-config-next STAYS A DEPENDENCY: this file consumes
// @next/eslint-plugin-next's native `flatConfig` export rather than
// eslint-config-next's legacy eslintrc content, so the package looks unused. It
// is not. It is the dependency vehicle that supplies @typescript-eslint/parser,
// @typescript-eslint/eslint-plugin, eslint-plugin-react, -react-hooks, -import,
// -jsx-a11y and @next/eslint-plugin-next. Removing it removes every rule source
// and the parser. See the plan's Decision 2.
import js from "@eslint/js";
import next from "@next/eslint-plugin-next";
import tsPlugin from "@typescript-eslint/eslint-plugin";
import tsParser from "@typescript-eslint/parser";
import globals from "globals";
import reactHooks from "eslint-plugin-react-hooks";

export default [
  {
    ignores: [
      "**/node_modules/**",
      ".next/**",
      "dist/**",
      "coverage/**",
      "public/**",
      "supabase/**",
      "playwright-report/**",
      "test-results/**",
      "**/__goldens__/**",
      "**/*.min.js",
    ],
  },

  js.configs.recommended,

  // Node-side JavaScript: scripts, config files, mjs/cjs tooling.
  {
    files: ["**/*.js", "**/*.mjs", "**/*.cjs"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: { ...globals.node },
    },
  },

  // TypeScript. `no-undef` is off here because the compiler already resolves
  // identifiers and the ESLint rule cannot see TS type-only declarations —
  // leaving it on produces a large false-positive class, not real defects.
  {
    files: ["**/*.ts", "**/*.tsx", "**/*.mts"],
    languageOptions: {
      parser: tsParser,
      ecmaVersion: "latest",
      sourceType: "module",
      parserOptions: { ecmaFeatures: { jsx: true } },
      globals: { ...globals.node, ...globals.browser },
    },
    plugins: { "@typescript-eslint": tsPlugin },
    rules: {
      "no-undef": "off",
      // The TS-aware version understands type-only usage and `_`-prefixed
      // intentional discards; the core rule does not.
      "no-unused-vars": "off",
      "@typescript-eslint/no-unused-vars": [
        "warn",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_" },
      ],
    },
  },

  // react-hooks must be registered even though its rules ship as warnings here:
  // the codebase already carries `eslint-disable` comments naming
  // react-hooks/exhaustive-deps, and an unregistered rule makes ESLint ERROR
  // with "Definition for rule ... was not found" — 5 of them before this block
  // existed. Those were config gaps, not findings.
  {
    files: ["**/*.jsx", "**/*.tsx"],
    plugins: { "react-hooks": reactHooks },
    rules: {
      "react-hooks/rules-of-hooks": "error",
      "react-hooks/exhaustive-deps": "warn",
    },
  },

  // Next.js core-web-vitals rules, via the plugin's own flat-config export.
  {
    files: ["**/*.js", "**/*.jsx", "**/*.mjs", "**/*.ts", "**/*.tsx"],
    plugins: next.flatConfig.coreWebVitals.plugins,
    rules: next.flatConfig.coreWebVitals.rules,
  },
  // Test files: `rules-of-hooks` matches on the `use*` NAMING convention, so a
  // vi.mock factory variable called `useSWRMock` reads as a hook called outside
  // a component. All 4 occurrences are that false positive, not real violations
  // — so this is scoped to test/** rather than disabled globally.
  {
    files: ["test/**/*.ts", "test/**/*.tsx"],
    rules: { "react-hooks/rules-of-hooks": "off" },
  },

  // ── First-run disposition ratchet ────────────────────────────────────────
  // This codebase has never been linted, so every rule below fires on
  // pre-existing code. They are demoted to `warn` DELIBERATELY and
  // individually — never a blanket disable to reach zero:
  //
  //   * the findings are real code smells worth fixing, so the rules stay ON;
  //   * but making them errors on day one would mean a permanently red lint
  //     run, and a gate that is always red trains its readers to ignore it —
  //     the exact failure mode that let a Sentry gate rot for three months.
  //
  // The pinned count in test/eslint-config.test.ts is the ratchet: this set
  // cannot grow silently, and it can be driven down file by file. A NEW
  // violation of any rule left at `error` still fails the run.
  {
    files: ["**/*.js", "**/*.jsx", "**/*.mjs", "**/*.cjs", "**/*.ts", "**/*.tsx", "**/*.mts"],
    // Flat config scopes plugins per config object, so the @next/next severity
    // overrides below need the plugin declared HERE too — inheriting it from
    // the block above is not how flat config resolves rule namespaces.
    plugins: next.flatConfig.coreWebVitals.plugins,
    rules: {
      "no-empty": "warn",
      "no-control-regex": "warn",
      "no-useless-escape": "warn",
      "no-fallthrough": "warn",
      "no-redeclare": "warn",
      "no-regex-spaces": "warn",
      "require-yield": "warn",
      "@next/next/no-img-element": "warn",
      "@next/next/no-assign-module-variable": "warn",
    },
  },
];
