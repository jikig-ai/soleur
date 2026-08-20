// ESLint 9 flat config for apps/web-platform (#1327).
//
// Replaces `next lint`, which Next.js 16 removes and which could not run here
// anyway: there was no config, so it dropped into an interactive
// "configure ESLint?" prompt and exited 1.
//
// ON eslint-config-next. It is still a devDependency and this config imports NOTHING
// from it. An earlier version of this comment claimed it was "the dependency vehicle"
// supplying the parser and every rule source, and that "removing it removes every Next
// and React rule source and the TS parser". That was measured and is FALSE: with
// node_modules/eslint-config-next moved aside entirely, `eslint . -f json` returns a
// byte-identical report — 2020 files, 192 findings, same byRule. The claim was written
// before the six imports below were declared as direct devDependencies and was never
// reconciled with them.
//
// What it uniquely still provides is eslint-plugin-react, eslint-plugin-import,
// eslint-plugin-jsx-a11y and @rushstack/eslint-patch — none of which this config
// registers today. It is therefore a genuine removal candidate, kept for now because it
// is the supported vehicle for turning those rule families on (notably react/no-danger,
// which is off today while five files use dangerouslySetInnerHTML). Removing it is a
// deliberate separate decision, not a tidy-up to fold into this PR.
//
// Provenance of the six imports, since the same false comment credited all six to
// eslint-config-next: @next/eslint-plugin-next, @typescript-eslint/parser and
// @typescript-eslint/eslint-plugin and eslint-plugin-react-hooks are also published
// under it, but `@eslint/js` is a direct dependency of `eslint` itself and `globals`
// arrives through `eslint` -> `@eslint/eslintrc`.
//
// All six are declared in this package's devDependencies. They were not, and resolved
// only by npm hoisting through eslint-config-next's tree — which pins
// @typescript-eslint/* as `^5.4.2 || ^6.0.0 || ^7.0.0 || ^8.0.0`, four majors wide, so a
// transitive bump could have moved the parser with nothing here constraining it.
import js from "@eslint/js";
import next from "@next/eslint-plugin-next";
import tsPlugin from "@typescript-eslint/eslint-plugin";
import tsParser from "@typescript-eslint/parser";
import globals from "globals";
import reactHooks from "eslint-plugin-react-hooks";

export default [
  {
    // 31 of the 192 pinned findings are unused `eslint-disable` directives, which ESLint
    // reports only because its DEFAULT for this is "warn". Pinned explicitly so an ESLint
    // minor cannot move the ratchet's baseline without anyone editing this repo.
    linterOptions: { reportUnusedDisableDirectives: "warn" },
  },
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
