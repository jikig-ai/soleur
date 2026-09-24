// #8495 — the watchdog workflows must tolerate a repeat run in one slot.
//
// The web-server dispatch clock (ADR-248) fires scheduled-inngest-health every
// 15 min and scheduled-zot-restart-loop hourly, and a slot can hold a second,
// queued run (a host collision or a late fallback `schedule:` tick). Two things
// in those workflows were not idempotent against that and are pinned here by
// EXECUTING the workflow's own bytes against a stubbed `gh`:
//   1. Tracker create-or-comment lookups used GitHub issue SEARCH, which lags a
//      just-created issue — the repeat run would file a duplicate tracker. They
//      now LIST by the tracker's label and match the title.
//   2. The auto-restart step would stack a second restart on one still running.

import { execFileSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { parse as parseYaml } from "yaml";

const REPO_ROOT = resolve(__dirname, "../../../..");
const WORKFLOWS = [
  ".github/workflows/scheduled-inngest-health.yml",
  ".github/workflows/scheduled-zot-restart-loop.yml",
];

type Step = { name?: string; run?: string };
function steps(file: string): Step[] {
  const doc = parseYaml(readFileSync(join(REPO_ROOT, file), "utf-8")) as {
    jobs: Record<string, { steps?: Step[] }>;
  };
  return Object.values(doc.jobs).flatMap((j) => j.steps ?? []);
}

const scratch = mkdtempSync(join(tmpdir(), "wd-idem-"));
afterAll(() => rmSync(scratch, { recursive: true, force: true }));

// A PATH-shimmed `gh` that logs its argv and answers from env. It REFUSES an
// issue search (exit 64), so a lookup that regresses to `--search` fails loudly.
const BIN = join(scratch, "bin");
execFileSync("mkdir", ["-p", BIN]);
writeFileSync(
  join(BIN, "gh"),
  `#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$GH_LOG"
case "$1 $2" in
  "issue list")
    # Emulates the real endpoint: --label filters (a tracker's label is its title's
    # bracket prefix), --jq is applied; --search is refused.
    label=""; jqexpr=""; prev=""
    for a in "$@"; do
      [[ "$a" == "--search" ]] && { echo "stub: --search refused" >&2; exit 64; }
      [[ "$prev" == "--label" ]] && label="$a"
      [[ "$prev" == "--jq" ]] && jqexpr="$a"
      prev="$a"
    done
    filtered=$(jq -c --arg l "$label" '[.[] | select($l == "" or (.title | startswith("[" + $l + "]")))]' <<<"$STUB_ISSUES")
    if [[ -n "$jqexpr" ]]; then jq -r "$jqexpr" <<<"$filtered"; else printf '%s' "$filtered"; fi ;;
  "run list")
    [[ "\${STUB_RUNS_FAIL:-0}" == "1" ]] && exit 1
    printf '%s' "$STUB_RUNS" ;;
  "workflow run") : ;;
  *) echo "stub: unexpected gh $*" >&2; exit 64 ;;
esac
`,
);
chmodSync(join(BIN, "gh"), 0o755);

function runBash(script: string, env: Record<string, string>): { out: string; log: string } {
  const log = join(scratch, `gh-${Math.random().toString(36).slice(2)}.log`);
  writeFileSync(log, "");
  const out = execFileSync("bash", ["--noprofile", "--norc", "-eo", "pipefail", "-c", script], {
    env: {
      PATH: `${BIN}:${process.env.PATH}`,
      GH_LOG: log,
      GH_REPO: "o/r",
      ...env,
    } as unknown as NodeJS.ProcessEnv,
    encoding: "utf-8",
  });
  return { out, log: readFileSync(log, "utf-8") };
}

// Every tracker lookup line (create-or-comment dedup) with the title it serves.
function trackerLookups(): Array<{ file: string; line: string; title: string }> {
  const out: Array<{ file: string; line: string; title: string }> = [];
  for (const file of WORKFLOWS) {
    for (const st of steps(file)) {
      // Dedup lookups live in steps that CREATE trackers; recovery (close) steps
      // may keep searching — a lagged close only delays by one run.
      if (!st.run || !st.run.includes("gh issue create")) continue;
      const lines = st.run.split("\n");
      lines.forEach((line, i) => {
        if (!/^\s*EXISTING="?\$\(gh issue list /.test(line)) return;
        const before = lines.slice(0, i).reverse();
        const assign = before
          .map((l) => l.match(/^\s*(?:ISSUE_TITLE|TITLE)="([^"$]*)"\s*$/))
          .find(Boolean);
        out.push({ file, line: line.trim(), title: assign ? assign[1] : "" });
      });
    }
  }
  return out;
}

describe("tracker lookups list by label, never search (#8495)", () => {
  const lookups = trackerLookups();

  it("finds every lookup site in both workflows (anti-vacuity)", () => {
    expect(lookups.length).toBeGreaterThanOrEqual(17);
    // The title-filtered set is exactly the #8495 rewrite: 15 converted sites.
    expect(lookups.filter((l) => l.line.includes("select(.title")).length).toBe(15);
    expect(new Set(lookups.map((l) => l.file)).size).toBe(2);
    for (const l of lookups) expect(l.title, l.line).toMatch(/^\[ci\/[a-z0-9-]+\] /);
  });

  it.each(trackerLookups().map((l) => [l.title, l]))(
    "%s: returns the open tracker whose title contains the class title, via its label",
    (_title, l) => {
      const label = l.title.match(/^\[([^\]]+)\]/)![1];
      // Newest first, as gh lists: another class (other label), a sibling title
      // under the SAME label, then this class's tracker (annotated), then an older one.
      const issues = JSON.stringify([
        { number: 5, title: "[ci/something-else] unrelated" },
        { number: 11, title: `[${label}] a sibling class sharing this label` },
        { number: 22, title: `${l.title} — annotated` },
        { number: 33, title: l.title },
      ]);
      // Title-filtered lookups must pick 22; the two pre-existing label-only
      // lookups (dedicated-host / no-live-scheduler) take the newest same-label
      // issue by design.
      const expected = l.line.includes("select(.title") ? 22 : 11;
      const { out, log } = runBash(
        `search_rc=0\nISSUE_TITLE='${l.title}'\nTITLE='${l.title}'\n${l.line}\necho "RESULT=$EXISTING"`,
        { STUB_ISSUES: issues },
      );
      expect(out).toContain(`RESULT=${expected}`);
      expect(log).toContain(`--label ${label}`);
      expect(log).not.toContain("--search");
    },
  );

  it("each tracker is CREATED with the label its lookup lists by (else the lookup could never find it)", () => {
    for (const file of WORKFLOWS) {
      for (const st of steps(file)) {
        if (!st.run || !st.run.includes("gh issue create")) continue;
        const lines = st.run.split("\n");
        lines.forEach((line, i) => {
          const m = line.match(/^\s*(?:ISSUE_TITLE|TITLE)="(\[([^\]]+)\][^"$]*)"\s*$/);
          if (!m) return;
          const label = m[2];
          // The first `gh issue create` after this assignment must carry the label.
          const rest = lines.slice(i + 1);
          const createAt = rest.findIndex((l) => /gh issue create /.test(l));
          expect(createAt, `${file}: no create after ${m[1]}`).toBeGreaterThanOrEqual(0);
          const createCmd = rest.slice(createAt, createAt + 4).join(" ");
          expect(createCmd, `${file}: ${m[1]}`).toMatch(
            new RegExp(`--label "?${label.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&")}"?(\\s|$)`),
          );
        });
      }
    }
  });

  it("an empty list yields no tracker (so the run files one)", () => {
    const l = lookups[0];
    const { out } = runBash(
      `search_rc=0\nISSUE_TITLE='${l.title}'\nTITLE='${l.title}'\n${l.line}\necho "RESULT=[$EXISTING]"`,
      { STUB_ISSUES: "[]" },
    );
    expect(out).toContain("RESULT=[]");
  });
});

describe("the auto-restart step never stacks a second restart (#8495)", () => {
  const step = steps(WORKFLOWS[0]).find((s) => s.name === "Auto-dispatch inngest restart (failure)");
  const now = Date.now();
  const iso = (minAgo: number) => new Date(now - minAgo * 60_000).toISOString().replace(/\.\d{3}Z$/, "Z");

  it("the step exists and consults the dedup helper before dispatching", () => {
    expect(step?.run).toBeDefined();
    const run = step!.run!;
    expect(run.indexOf("restart_recently_dispatched")).toBeGreaterThan(-1);
    expect(run.indexOf("restart_recently_dispatched")).toBeLessThan(run.indexOf("gh workflow run"));
  });

  it.each([
    ["a restart is queued", JSON.stringify([{ event: "workflow_dispatch", status: "queued", createdAt: iso(2) }]), "0", false],
    ["a restart finished 5 min ago", JSON.stringify([{ event: "workflow_dispatch", status: "completed", createdAt: iso(5) }]), "0", false],
    ["the last restart was 30 min ago", JSON.stringify([{ event: "workflow_dispatch", status: "completed", createdAt: iso(30) }]), "0", true],
    ["no restart ever ran", "[]", "0", true],
    ["the run list read failed (fail-open)", "", "1", true],
  ])("%s → dispatch=%s", (_label, runs, fail, dispatch) => {
    const { out, log } = runBash(step!.run!, {
      STUB_RUNS: runs as string,
      STUB_RUNS_FAIL: fail as string,
      GITHUB_WORKSPACE: REPO_ROOT,
    });
    const dispatched = log.split("\n").some((l) => l.startsWith("workflow run restart-inngest-server.yml"));
    expect(dispatched).toBe(dispatch);
    if (!dispatch) expect(out).toContain("not dispatching a second restart");
  });
});
