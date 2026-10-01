import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Drift guard (#4964): the `likec4` CLI preinstalled in the Dockerfile MUST be
// pinned to the SAME version as the client renderer `@likec4/core` /
// `@likec4/diagram`. The CLI's `export json` schema must match what
// `LikeC4Model.create` consumes — a mismatched CLI silently emits a drifted
// schema and the rendered diagram breaks. The CLI is a Dockerfile global (not a
// package.json dep, to preserve lockfile parity), so tsc/lockfile checks cannot
// catch this coupling — only this source-read parity test can.
const ROOT = path.resolve(__dirname, "..");
// Repo root — the regen script + CI workflow that ALSO pin likec4 live here,
// outside apps/web-platform.
const REPO_ROOT = path.resolve(ROOT, "..", "..");

function read(rel: string): string {
  return readFileSync(path.join(ROOT, rel), "utf8");
}

function readRepo(rel: string): string {
  return readFileSync(path.join(REPO_ROOT, rel), "utf8");
}

// ---------------------------------------------------------------------------
// Dependency-tree pin (#9300). Pinning `likec4@<version>` pins ONE package; its
// ~190-node transitive tree resolves to the newest releases at run time, and
// npm's CDN can 404 a tarball published minutes earlier. Every place CI resolves
// that tree therefore carries `--before=<D>` too, and (version, D) is a pair.
// `checkLikec4Pins` is the single scanner: the real-file test asserts it returns
// [], and the string-fed self-test below asserts mutated input does not.
// ---------------------------------------------------------------------------
interface Likec4PinFiles {
  ci: string;
  monitor: string;
  renderSh: string;
  genTs: string;
  lib: string;
}

const MIN_DATE_AGE_DAYS = 3;
const DAY_MS = 86_400_000;
const BUMP_HINT =
  "Bump procedure: see BUMPING LIKEC4 in plugins/soleur/scripts/render-c4-model.sh " +
  "(date >= the version's publish time and >= 3 days old: `npm view likec4@<version> time --json`).";

/**
 * Drop whole-line `#`, `//` and block-comment lines, then trailing ` # …` / ` // …` comments,
 * so prose quoting a command (or a decoy flag after it) is not a site. A line starting `*)`
 * (a shell case arm) is code, not a block-comment continuation.
 */
function stripComments(src: string): string {
  return src
    .split("\n")
    .filter((l) => !/^\s*(#|\/\/|\/\*|\*(\s|$|\/))/.test(l))
    .map((l) => l.replace(/\s+(#|\/\/)\s.*$/, "").replace(/\s+#$/, ""))
    .join("\n");
}

/** Every non-comment `npm install -g likec4@<digit…>` command line, derived — never a fixed count. */
function extractInstallLines(src: string): string[] {
  return stripComments(src)
    .split("\n")
    .filter((l) => /npm install -g likec4@[0-9]/.test(l));
}

function exportJsonLines(src: string, needle: RegExp): string[] {
  return stripComments(src)
    .split("\n")
    .filter((l) => needle.test(l));
}

function checkLikec4Pins(files: Likec4PinFiles, now: Date): string[] {
  if (Number.isNaN(now.getTime())) throw new Error("checkLikec4Pins: invalid `now`");
  const violations: string[] = [];
  const dates = new Set<string>();

  // Workflows: EVERY install line must carry the flag (a first-match read misses the 2nd).
  let sites = 0;
  for (const [name, src] of [
    [".github/workflows/ci.yml", files.ci],
    [".github/workflows/main-health-monitor.yml", files.monitor],
  ] as const) {
    const lines = extractInstallLines(src);
    sites += lines.length;
    // Census: a resolution spelled any other way (`npm i -g`, `--global`, `npx`) is not
    // discovered by extractInstallLines, so it must not exist undetected.
    const census = stripComments(src)
      .split("\n")
      .filter((l) => /likec4@[0-9]/.test(l) && /\b(npm|npx|pnpm|bunx|yarn)\b/.test(l));
    for (const l of census) {
      if (!lines.includes(l)) violations.push(`${name}: unrecognised likec4 resolution (use the pinned \`npm install -g likec4@<v> --before=<date>\` form): ${l.trim()}`);
    }
    if (lines.length === 0) violations.push(`${name}: no non-comment \`npm install -g likec4@\` line found`);
    lines.forEach((l, i) => {
      const m = l.match(/--before=(\S+)/);
      if (!m) violations.push(`${name}: install line #${i + 1} has no --before=<date>: ${l.trim()}`);
      else dates.add(m[1]);
    });
  }

  // render-c4-model.sh: the single `export json` line must use the declared date.
  // `--ignore-scripts` distinguishes the real invocation from the human copy-paste hint echoes.
  const renderExport = exportJsonLines(files.renderSh, /--ignore-scripts.*export json/);
  sites += renderExport.length;
  if (renderExport.length !== 1) {
    violations.push(`render-c4-model.sh: expected exactly one non-comment \`export json\` line, found ${renderExport.length}`);
  } else if (!/--before="\$\{LIKEC4_BEFORE\}"(\s|$)/.test(renderExport[0])) {
    violations.push(`render-c4-model.sh: the \`export json\` line does not pass --before=LIKEC4_BEFORE: ${renderExport[0].trim()}`);
  }
  const shDecl = stripComments(files.renderSh).match(/^LIKEC4_BEFORE="([^"]*)"/m);
  if (!shDecl) violations.push('render-c4-model.sh: no LIKEC4_BEFORE="<date>" declaration');
  else dates.add(shDecl[1]);

  // generate-c4-from-components.ts: the `export json` argv line must pass the constant.
  const tsExport = exportJsonLines(files.genTs, /"export",\s*"json"/);
  sites += tsExport.length;
  if (tsExport.length !== 1) {
    violations.push(`generate-c4-from-components.ts: expected exactly one non-comment "export","json" argv line, found ${tsExport.length}`);
  } else if (!/--before=\$\{LIKEC4_BEFORE\}[`\s,\]]/.test(tsExport[0])) {
    violations.push(`generate-c4-from-components.ts: the export json argv line does not pass --before=\${LIKEC4_BEFORE}: ${tsExport[0].trim()}`);
  }
  const libDecl = stripComments(files.lib).match(/export const LIKEC4_BEFORE = "([^"]*)"/);
  if (!libDecl) violations.push('c4-from-components.ts: no `export const LIKEC4_BEFORE = "<date>"`');
  else dates.add(libDecl[1]);

  if (sites === 0) violations.push("examined 0 likec4 resolution sites — the guard is not looking at anything");

  if (dates.size > 1) {
    violations.push(`--before dates differ across sites: ${[...dates].sort().join(", ")}. ${BUMP_HINT}`);
  }
  for (const d of dates) {
    const parsed = /^\d{4}-\d{2}-\d{2}$/.test(d) ? Date.parse(`${d}T00:00:00Z`) : NaN;
    // Round-trip: Date.parse rolls 2026-02-31 over to 03-03.
    const t = !Number.isNaN(parsed) && new Date(parsed).toISOString().slice(0, 10) === d ? parsed : NaN;
    if (Number.isNaN(t)) violations.push(`--before date "${d}" is not a valid YYYY-MM-DD date`);
    else if (now.getTime() - t < MIN_DATE_AGE_DAYS * DAY_MS) {
      violations.push(`--before date ${d} is younger than ${MIN_DATE_AGE_DAYS} days (UTC); a fresh cutoff re-admits CDN-lag tarballs. ${BUMP_HINT}`);
    }
  }
  return violations;
}

function readPinFiles(): Likec4PinFiles {
  return {
    ci: readRepo(".github/workflows/ci.yml"),
    monitor: readRepo(".github/workflows/main-health-monitor.yml"),
    renderSh: readRepo("plugins/soleur/scripts/render-c4-model.sh"),
    genTs: readRepo("plugins/soleur/scripts/generate-c4-from-components.ts"),
    lib: readRepo("plugins/soleur/lib/c4-from-components.ts"),
  };
}

describe("likec4 CLI / client-renderer version parity", () => {
  it("Dockerfile `npm install -g likec4@X` matches @likec4/core and @likec4/diagram in package.json", () => {
    const dockerfile = read("Dockerfile");
    const pkg = JSON.parse(read("package.json")) as {
      dependencies: Record<string, string>;
    };

    const cliMatch = dockerfile.match(/npm install -g likec4@([0-9][^\s"'`]*)/);
    expect(cliMatch, "Dockerfile must pin `npm install -g likec4@<version>`").toBeTruthy();
    const cliVersion = cliMatch![1];

    const core = pkg.dependencies["@likec4/core"];
    const diagram = pkg.dependencies["@likec4/diagram"];
    expect(core, "@likec4/core must be an exact pin").toMatch(/^[0-9]/);
    expect(diagram, "@likec4/diagram must be an exact pin").toMatch(/^[0-9]/);

    expect(cliVersion).toBe(core);
    expect(cliVersion).toBe(diagram);
  });

  // The C4 auto-regen tooling adds two EXECUTABLE surfaces that render the model
  // with the pinned CLI: plugins/soleur/scripts/render-c4-model.sh (pre-commit hook via the
  // scripts/regenerate-c4-model.sh wrapper, the merge resolver, ad-hoc)
  // and the .github/workflows/ci.yml freshness-test install. If either drifts from
  // the Dockerfile/package.json pin, the committed model.likec4.json is rendered by
  // a skewed CLI and the runtime client renderer mismatches. tsc can't catch a bash
  // literal or a YAML step — only this source-read parity assertion can.
  it("render-c4-model.sh and ci.yml pin the same likec4 version as the Dockerfile", () => {
    const dockerfile = read("Dockerfile");
    const cliVersion = dockerfile.match(
      /npm install -g likec4@([0-9][^\s"'`]*)/,
    )![1];

    const script = readRepo("plugins/soleur/scripts/render-c4-model.sh");
    const scriptMatch = script.match(/LIKEC4_VERSION="([0-9][^\s"'`]*)"/);
    expect(
      scriptMatch,
      "render-c4-model.sh must pin LIKEC4_VERSION=\"<version>\"",
    ).toBeTruthy();
    expect(scriptMatch![1]).toBe(cliVersion);

    const ci = readRepo(".github/workflows/ci.yml");
    // matchAll, not match: ci.yml carries several `npm install -g likec4@` lines
    // (test-webplat, test-scripts, test-scripts-heavy) — a first-match read would
    // never see the second copy drift.
    const ciMatches = [
      ...ci.matchAll(/npm install -g likec4@([0-9][^\s"'`]*)/g),
    ];
    expect(
      ciMatches.length,
      "ci.yml must install a pinned `likec4@<version>` for the freshness test",
    ).toBeGreaterThan(0);
    for (const m of ciMatches) {
      expect(m[1]).toBe(cliVersion);
    }

    // 5th surface (#7307): main-health-monitor.yml installs likec4 so that
    // c4-model-freshness.test.sh actually RUNS there — without the CLI that suite
    // self-skips, and a self-skip prints as PASS. Unregistered, a bump to the four
    // sites above would regenerate model.likec4.json under a new schema while the
    // monitor still rendered with the old one, and the monitor would then file a
    // priority/p1-high issue every 6 hours against a perfectly healthy main.
    // NB it must write the LITERAL: this regex requires a digit after `likec4@`,
    // so a `"likec4@${LIKEC4_VERSION}"` form would be silently invisible here.
    const monitor = readRepo(".github/workflows/main-health-monitor.yml");
    const monitorMatch = monitor.match(/npm install -g likec4@([0-9][^\s"'`]*)/);
    expect(
      monitorMatch,
      "main-health-monitor.yml must install a pinned `likec4@<version>`",
    ).toBeTruthy();
    expect(monitorMatch![1]).toBe(cliVersion);

    // No surface may regress to a floating tag.
    expect(script).not.toMatch(/likec4@latest/);
    expect(ci).not.toMatch(/likec4@latest/);
    expect(monitor).not.toMatch(/likec4@latest/);
  });

  // #8861 doc surfaces: the recipes agents copy VERBATIM pin literal
  // `likec4@<version>` — without a census they drift on the next bump and an
  // agent in a customer repo renders with a stale CLI (the same skew class
  // the executable surfaces above are pinned against).
  it("agent-facing likec4 recipes pin the same version and never float @latest", () => {
    const dockerfile = read("Dockerfile");
    const cliVersion = dockerfile.match(
      /npm install -g likec4@([0-9][^\s"'`]*)/,
    )![1];

    const DOC_SURFACES = [
      "plugins/soleur/skills/architecture/references/likec4-reference.md",
      "plugins/soleur/skills/architecture/SKILL.md",
    ];
    for (const path of DOC_SURFACES) {
      const doc = readRepo(path);
      const pins = [...doc.matchAll(/likec4@([0-9][^\s"'`]*)/g)];
      expect(
        pins.length,
        `${path} must pin a literal likec4@<version>`,
      ).toBeGreaterThan(0);
      for (const m of pins) {
        expect(m[1], `${path} pins a stale likec4 version`).toBe(cliVersion);
      }
      expect(doc, `${path} must not float @latest`).not.toMatch(/likec4@latest/);
    }
  });
});

describe("likec4 dependency-tree pin (--before) parity (#9300)", () => {
  it("every likec4 resolution site carries the same, old-enough --before date", () => {
    expect(checkLikec4Pins(readPinFiles(), new Date())).toEqual([]);
  });

  // Cardinality: the scanner derives sites, so deleting a step leaves it green. One install
  // step per job that runs likec4 tests (test-webplat, test-scripts, test-scripts-heavy);
  // bump this with a job, deliberately.
  it("ci.yml carries exactly one pinned install step per likec4-testing job", () => {
    expect(extractInstallLines(readPinFiles().ci)).toHaveLength(3);
  });
});

describe("checkLikec4Pins self-test (string-fed mutations)", () => {
  const NOW = new Date("2026-10-05T00:00:00Z");
  const D = "2026-09-28";
  const installBlock = (flags: string[]) =>
    flags.map((f, i) => `  - name: step ${i}\n    run: |\n      npm install -g likec4@1.50.0${f}\n      likec4 --version`).join("\n");
  const good = (): Likec4PinFiles => ({
    ci:
      "# prose quoting npm install -g likec4@1.50.0 is a comment, not a site\n" +
      installBlock([` --before=${D}`, ` --before=${D}`, ` --before=${D}`]),
    monitor: `      npm install -g likec4@1.50.0 --before=${D}   # literal`,
    renderSh:
      `# header quotes: npx -y --ignore-scripts likec4@\${LIKEC4_VERSION} --before="\${LIKEC4_BEFORE}" export json\n` +
      `LIKEC4_VERSION="1.50.0"\nLIKEC4_BEFORE="${D}"\n` +
      `npx -y --ignore-scripts --before="\${LIKEC4_BEFORE}" "likec4@\${LIKEC4_VERSION}" export json --no-use-dot -o "$T" .\n` +
      `echo "hint: npx -y likec4@\${LIKEC4_VERSION} validate ."`,
    genTs:
      `    // ["-y", "--before=\${LIKEC4_BEFORE}", "export", "json"] in a comment\n` +
      `    ["-y", "--ignore-scripts", \`--before=\${LIKEC4_BEFORE}\`, \`likec4@\${LIKEC4_VERSION}\`, "export", "json", "--no-use-dot", "-o", out, "."],`,
    lib: `export const LIKEC4_VERSION = "1.50.0";\nexport const LIKEC4_BEFORE = "${D}";`,
  });

  it("control: the canonical fixture is clean", () => {
    expect(checkLikec4Pins(good(), NOW)).toEqual([]);
  });

  it("row 1: flag missing from the SECOND of three install lines is caught; a first-match read would not catch it", () => {
    const f = good();
    f.ci = installBlock([` --before=${D}`, "", ` --before=${D}`]);
    expect(checkLikec4Pins(f, NOW).join("\n")).toMatch(/install line #2 has no --before/);
    // Harness row (a): the scanner must read ALL lines — the first line alone is clean.
    const lines = extractInstallLines(f.ci);
    expect(lines).toHaveLength(3);
    expect(lines[0]).toContain("--before=");
    expect(lines[1]).not.toContain("--before=");
  });

  it("row 2: a monitor date that differs by one day trips the single-date check", () => {
    const f = good();
    f.monitor = f.monitor.replace(D, "2026-09-27");
    expect(checkLikec4Pins(f, NOW).join("\n")).toMatch(/dates differ across sites/);
  });

  it("row 3: flag removed from the renderer's export json line while a comment still quotes it", () => {
    const f = good();
    f.renderSh = f.renderSh.replace(` --before="\${LIKEC4_BEFORE}" "likec4@`, ` "likec4@`);
    expect(checkLikec4Pins(f, NOW).join("\n")).toMatch(/render-c4-model\.sh: the `export json` line does not pass/);
  });

  it("row 4: flag removed from the TS export json argv line", () => {
    const f = good();
    f.genTs = f.genTs.replace(` \`--before=\${LIKEC4_BEFORE}\`,`, "");
    expect(checkLikec4Pins(f, NOW).join("\n")).toMatch(/generate-c4-from-components\.ts: the export json argv line does not pass/);
  });

  it("row 5: zero likec4 sites fails instead of passing vacuously", () => {
    const empty: Likec4PinFiles = { ci: "", monitor: "", renderSh: "", genTs: "", lib: "" };
    expect(checkLikec4Pins(empty, NOW).join("\n")).toMatch(/examined 0 likec4 resolution sites/);
  });

  it("row 6: a date younger than 3 days, and a non-date, are both caught", () => {
    const young = good();
    for (const k of ["ci", "monitor", "renderSh", "lib"] as const) young[k] = young[k].replaceAll(D, "2026-10-04");
    expect(checkLikec4Pins(young, NOW).join("\n")).toMatch(/younger than 3 days/);
    const junk = good();
    for (const k of ["ci", "monitor", "renderSh", "lib"] as const) junk[k] = junk[k].replaceAll(D, "yesterday");
    expect(checkLikec4Pins(junk, NOW).join("\n")).toMatch(/not a valid YYYY-MM-DD/);
  });

  // Escape rows: the guard is pristine and fed input it must refuse (review of #9338).
  it("a flag that only appears in a TRAILING comment does not satisfy a site", () => {
    const ci = good();
    ci.ci = installBlock([` --before=${D}`, `   # --before=${D}`, ` --before=${D}`]);
    expect(checkLikec4Pins(ci, NOW).join("\n")).toMatch(/install line #2 has no --before/);
    const sh = good();
    sh.renderSh = sh.renderSh.replace(` --before="\${LIKEC4_BEFORE}" "likec4@`, ` "likec4@`) + "";
    sh.renderSh = sh.renderSh.replace(`export json --no-use-dot -o "$T" .`, `export json --no-use-dot -o "$T" .  # --before="\${LIKEC4_BEFORE}"`);
    expect(checkLikec4Pins(sh, NOW).join("\n")).toMatch(/render-c4-model\.sh: the `export json` line does not pass/);
    const ts = good();
    ts.genTs = ts.genTs.replace(` \`--before=\${LIKEC4_BEFORE}\`,`, "").replace(`"."],`, `"."], // "--before=\${LIKEC4_BEFORE}"`);
    expect(checkLikec4Pins(ts, NOW).join("\n")).toMatch(/generate-c4-from-components\.ts: the export json argv line does not pass/);
  });

  it("an install spelled another way (npm i -g / --global) is flagged, not silently undiscovered", () => {
    for (const spelled of ["npm i -g likec4@1.50.0", "npm install --global likec4@1.50.0", "npx -y likec4@1.50.0 export json"]) {
      const f = good();
      f.ci += `\n      ${spelled}\n`;
      expect(checkLikec4Pins(f, NOW).join("\n")).toMatch(/unrecognised likec4 resolution/);
    }
  });

  it("a mangled variable name or suffix on the flag is not accepted", () => {
    const sh = good();
    // The header comment quotes the flag first, so anchor on the real line's `--ignore-scripts`.
    sh.renderSh = sh.renderSh.replace(`--ignore-scripts --before="\${LIKEC4_BEFORE}"`, `--ignore-scripts --before="\${NOT_LIKEC4_BEFORE}"`);
    expect(checkLikec4Pins(sh, NOW).join("\n")).toMatch(/does not pass/);
    const ts = good();
    ts.genTs = ts.genTs.replace("`--before=${LIKEC4_BEFORE}`", "`--before=${LIKEC4_BEFORE}x`");
    expect(checkLikec4Pins(ts, NOW).join("\n")).toMatch(/does not pass/);
  });

  it("a missing LIKEC4_BEFORE declaration, or a second export line, is caught", () => {
    const sh = good();
    sh.renderSh = sh.renderSh.replace(`LIKEC4_BEFORE="${D}"\n`, "");
    expect(checkLikec4Pins(sh, NOW).join("\n")).toMatch(/no LIKEC4_BEFORE="<date>" declaration/);
    const lib = good();
    lib.lib = lib.lib.replace(/export const LIKEC4_BEFORE.*\n?/, "");
    expect(checkLikec4Pins(lib, NOW).join("\n")).toMatch(/no `export const LIKEC4_BEFORE/);
    const two = good();
    two.renderSh += `npx -y --ignore-scripts "likec4@\${LIKEC4_VERSION}" export json .\n`;
    expect(checkLikec4Pins(two, NOW).join("\n")).toMatch(/exactly one non-comment `export json` line, found 2/);
  });

  it("the 3-day age floor is exact, an impossible date is refused, and an invalid `now` throws", () => {
    const at = (d: string, now: string) => {
      const f = good();
      for (const k of ["ci", "monitor", "renderSh", "lib"] as const) f[k] = f[k].replaceAll(D, d);
      return checkLikec4Pins(f, new Date(now));
    };
    expect(at("2026-10-02", "2026-10-05T00:00:00Z")).toEqual([]); // exactly 3 days: allowed
    expect(at("2026-10-03", "2026-10-05T00:00:00Z").join("\n")).toMatch(/younger than 3 days/); // 2 days
    expect(at("2026-02-31", "2026-10-05T00:00:00Z").join("\n")).toMatch(/not a valid YYYY-MM-DD/);
    expect(() => checkLikec4Pins(good(), new Date("nope"))).toThrow(/invalid `now`/);
  });

  it("a shell case arm starting with `*)` is code, not a block comment", () => {
    const f = good();
    f.ci += "\n      *) npm install -g likec4@1.50.0 ;;\n";
    expect(checkLikec4Pins(f, NOW).join("\n")).toMatch(/has no --before/);
  });

  it("must-PASS: every site moved together to another valid old date is clean (guard is not pinned to one literal)", () => {
    const f = good();
    for (const k of ["ci", "monitor", "renderSh", "lib"] as const) f[k] = f[k].replaceAll(D, "2026-09-29");
    expect(checkLikec4Pins(f, NOW)).toEqual([]);
  });
});
