// RED-first (cq-write-failing-tests-before) unit tests for the C4 producer that
// turns sync's component docs into a LikeC4 model (#7332, plan Phase 1).
//
// The corpus this parses is NOT a specified contract today — it is emergent LLM
// behaviour. Skouer's component docs happen to carry `**Internal**: [x](x.md)`
// markdown links; Soleur's own carry prose ("None (agents are standalone)"), 4
// times out of 4. So the failure this suite exists to catch is not a crash: it is
// a corpus that yields elements, exits 0, validates clean, and renders a diagram
// of DISCONNECTED BOXES reported as success. `assessRender` is the gate, and the
// prose-form fixture is what proves it goes red (plan AC2 — "a gate that has never
// been seen red is not a gate").
//
// All fixtures are synthesized (cq-test-fixtures-synthesized-only) — no captured
// customer content.

import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";

import {
  DIAG_RE,
  GENERATED_HEADER,
  LIKEC4_VERSION,
  C4_MARKER,
  C4_MARKER_FIELDS,
  assessRender,
  buildEdges,
  formatC4Marker,
  canOverwrite,
  countModelJson,
  generateC4,
  generateSpecC4,
  generateViewPage,
  generateViewsC4,
  loadComponentDir,
  parseComponentDoc,
  toId,
} from "../lib/c4-from-components";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const FIXTURES = join(import.meta.dir, "fixtures", "component-docs");
const dir = (name: string) => join(FIXTURES, name);

// ---------------------------------------------------------------------------
// 1.2 — parse both forms
// ---------------------------------------------------------------------------

describe("parseComponentDoc — frontmatter form (the specified contract)", () => {
  it("reads the `dependencies:` list and reports frontmatter as the source", () => {
    const doc = parseComponentDoc(
      readFileSync(join(dir("frontmatter-form"), "api-gateway.md"), "utf8"),
      "api-gateway",
    );
    expect(doc).not.toBeNull();
    expect(doc!.name).toBe("api-gateway");
    expect(doc!.deps).toEqual(["auth-service", "record-store"]);
    expect(doc!.depSource).toBe("frontmatter");
  });

  // `dependencies: []` is a DECLARATION of no dependencies. It must not collapse
  // into the same state as a doc that never declared any — the coverage summary
  // and the degraded verdict both need to distinguish "author said none" from
  // "author said nothing", or a corpus of silent docs reads as a corpus of leaves.
  it("distinguishes an explicit empty list from an absent declaration", () => {
    const declared = parseComponentDoc(
      readFileSync(join(dir("frontmatter-form"), "record-store.md"), "utf8"),
      "record-store",
    );
    expect(declared!.deps).toEqual([]);
    expect(declared!.depSource).toBe("frontmatter");

    const silent = parseComponentDoc(
      readFileSync(join(dir("prose-form"), "agents.md"), "utf8"),
      "agents",
    );
    expect(silent!.deps).toEqual([]);
    expect(silent!.depSource).toBe("none");
  });
});

describe("parseComponentDoc — link fallback (docs written before the contract)", () => {
  it("extracts `**Internal**: [name](name.md)` links when frontmatter is absent", () => {
    const doc = parseComponentDoc(
      readFileSync(join(dir("link-form"), "web-server.md"), "utf8"),
      "web-server",
    );
    expect(doc!.deps).toEqual(["cache-layer", "database"]);
    expect(doc!.depSource).toBe("links");
  });

  it("recovers nothing from Soleur's own prose form", () => {
    // The exact string 4 of Soleur's 4 component docs use. If this ever parses to
    // a non-empty dep set, the parser is inventing edges from prose.
    const doc = parseComponentDoc(
      readFileSync(join(dir("prose-form"), "commands.md"), "utf8"),
      "commands",
    );
    expect(doc!.deps).toEqual([]);
    expect(doc!.depSource).toBe("none");
  });

  it("tolerates a `## Dependencies` section with no `**Internal**` line at all", () => {
    // The real `ci-guards.md` case: 7 docs do not imply 7 connected elements.
    const doc = parseComponentDoc(
      readFileSync(join(dir("prose-form"), "skills.md"), "utf8"),
      "skills",
    );
    expect(doc).not.toBeNull();
    expect(doc!.deps).toEqual([]);
    expect(doc!.depSource).toBe("none");
  });
});

describe("parseComponentDoc — deprecated filter (sync.md never deletes removed components)", () => {
  it("returns null for a `status: deprecated` doc", () => {
    const doc = parseComponentDoc(
      readFileSync(join(dir("mixed-deprecated"), "legacy-worker.md"), "utf8"),
      "legacy-worker",
    );
    expect(doc).toBeNull();
  });

  it("keeps active docs in the same corpus", () => {
    const docs = loadComponentDir(dir("mixed-deprecated"));
    expect(docs.map((d) => d.name).sort()).toEqual(["job-queue", "scheduler"]);
  });
});

// ---------------------------------------------------------------------------
// edges
// ---------------------------------------------------------------------------

describe("buildEdges", () => {
  it("builds an edge per declared dependency", () => {
    const edges = buildEdges(loadComponentDir(dir("frontmatter-form")));
    expect(edges).toEqual([
      { from: "api-gateway", to: "auth-service" },
      { from: "api-gateway", to: "record-store" },
      { from: "auth-service", to: "record-store" },
    ]);
  });

  it("drops edges whose target is not in the corpus", () => {
    // cache-layer declares `ghost-service`, which no doc defines. A dangling edge
    // makes likec4 emit `Could not resolve …` and fail the diagnostic gate, so the
    // producer must not emit it in the first place.
    const edges = buildEdges(loadComponentDir(dir("link-form")));
    expect(edges.some((e) => e.to === "ghost-service")).toBe(false);
    expect(edges).toEqual([
      { from: "cache-layer", to: "database" },
      { from: "web-server", to: "cache-layer" },
      { from: "web-server", to: "database" },
    ]);
  });

  it("drops edges pointing at a deprecated component", () => {
    // scheduler declares `legacy-worker`, filtered out by the deprecated gate.
    const edges = buildEdges(loadComponentDir(dir("mixed-deprecated")));
    expect(edges.some((e) => e.to === "legacy-worker")).toBe(false);
    expect(edges).toEqual([{ from: "scheduler", to: "job-queue" }]);
  });

  it("is deterministic — repeated builds are identical", () => {
    const a = buildEdges(loadComponentDir(dir("frontmatter-form")));
    const b = buildEdges(loadComponentDir(dir("frontmatter-form")));
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
  });
});

// ---------------------------------------------------------------------------
// 1.3 — the three validation gates
// ---------------------------------------------------------------------------

describe("assessRender — three gates", () => {
  const clean = { diagnostics: "workspace: /tmp/x\ndone\n" };
  // Default the gate input to non-zero so each existing case keeps exercising the
  // arm it was written for; the gate itself is pinned by its own cases below.
  const g = (n: number) => ({ generatedRelationships: n });

  it("reports ok when elements and relationships are both non-zero", () => {
    expect(assessRender({ ...clean, ...g(3), elementCount: 3, relationshipCount: 3 }).status).toBe("ok");
  });

  // PLAN AC2 — the gate that catches the real failure. This is the whole reason
  // the relationship count is a gate at all: a link-free corpus produces valid,
  // non-empty, diagnostic-clean output that is nonetheless a diagram of
  // disconnected boxes.
  // THE GATE, and the reason it must read the PRODUCER's edge set rather than the
  // rendered model's. `likec4 export json .` renders the whole diagrams directory, so
  // on any repo with a hand-authored model.c4 the rendered count is dominated by edges
  // this producer did not create — measured on this repo: 4 docs with zero
  // `dependencies:`, producer contributed 0, merged render reported 135. Gating on the
  // rendered count made the module's whole reason for existing unreachable in exactly
  // the two-writer scenario it was designed around.
  it("reports DEGRADED when THIS PRODUCER contributed no relationships", () => {
    const v = assessRender({ ...clean, ...g(0), elementCount: 3, relationshipCount: 0 });
    expect(v.status).toBe("degraded");
    expect(v.reason).toBe("no-generated-relationships");
  });

  it("still reports DEGRADED when the MERGED model has relationships but the producer added none", () => {
    // The previously-unreachable case: a pre-existing hand-authored model.c4 supplies
    // 135 relations, the producer supplies 0. Old behaviour: ok. Correct: degraded.
    const v = assessRender({ ...clean, ...g(0), elementCount: 67, relationshipCount: 135 });
    expect(v.status).toBe("degraded");
    expect(v.reason).toBe("no-generated-relationships");
  });

  it("reports ok when the producer contributed edges even if the merged count is larger", () => {
    const v = assessRender({ ...clean, ...g(3), elementCount: 67, relationshipCount: 135 });
    expect(v.status).toBe("ok");
  });

  it("reports failed on an empty model", () => {
    expect(assessRender({ ...clean, ...g(0), elementCount: 0, relationshipCount: 0 }).status).toBe("failed");
  });

  it("reports failed when the diagnostic stream carries a source fault", () => {
    for (const diagnostics of [
      "Invalid model.c4\n",
      "Could not resolve reference to Element named 'ghost'\n",
      "    Line 274: unexpected token\n",
    ]) {
      expect(assessRender({ diagnostics, ...g(5), elementCount: 5, relationshipCount: 5 }).status).toBe(
        "failed",
      );
    }
  });

  it("does not false-fail on a workspace path containing the ANCHORED marker words", () => {
    // regenerate-c4-model.sh anchors two of its three alternations for exactly
    // this reason: likec4 echoes `workspace: /abs/path`, so `^Invalid ` and the
    // indented `Line N:` form cannot match a repo path mid-line.
    const diagnostics = "workspace: /home/u/Invalid Line 3: dir/repo\n";
    expect(assessRender({ diagnostics, ...g(5), elementCount: 5, relationshipCount: 5 }).status).toBe("ok");
  });

  it("DOES trip on `Could not resolve` anywhere on the line — faithful to the shell", () => {
    // Deliberately unanchored upstream ("`Could not resolve` is a distinctive
    // likec4 phrase", regenerate-c4-model.sh:92). A checkout path containing that
    // exact phrase would false-FAIL. That residual risk is inherited on purpose:
    // AC5 requires mirroring the shell gate, and diverging here would make the
    // producer and the script disagree about what a source fault is.
    const diagnostics = "workspace: /home/u/Could not resolve/repo\n";
    expect(assessRender({ diagnostics, ...g(5), elementCount: 5, relationshipCount: 5 }).status).toBe(
      "failed",
    );
  });
});

// ---------------------------------------------------------------------------
// countModelJson — the key mapping assessRender depends on
// ---------------------------------------------------------------------------

describe("countModelJson — pinned against a REAL likec4 artifact", () => {
  // This is the one thing no assessRender test can cover. assessRender takes
  // plain numbers, so reading the wrong JSON key is invisible to it: the producer
  // reported `relationships=0` for a corpus whose .c4 carried three edges,
  // because likec4 emits `relations` and the first implementation read
  // `relationships`. Every corpus would have reported degraded — a gate that
  // always fires. Pin the mapping against the repo's own committed model.
  const realModel = readFileSync(
    join(REPO_ROOT, "knowledge-base/engineering/architecture/diagrams/model.likec4.json"),
    "utf8",
  );

  it("reads a non-zero element AND relationship count from Soleur's own model", () => {
    const counts = countModelJson(realModel);
    // Deliberately not literal counts — those drift with every model edit. The
    // claim under test is that BOTH keys resolve, which a wrong key cannot satisfy.
    expect(counts.elements).toBeGreaterThan(0);
    expect(counts.relationships).toBeGreaterThan(0);
  });

  it("agrees with the artifact's own top-level keys", () => {
    const parsed = JSON.parse(realModel) as Record<string, Record<string, unknown>>;
    expect(countModelJson(realModel)).toEqual({
      elements: Object.keys(parsed.elements).length,
      relationships: Object.keys(parsed.relations).length,
    });
  });

  it("returns zeros for malformed or non-object payloads rather than throwing", () => {
    expect(countModelJson("not json")).toEqual({ elements: 0, relationships: 0 });
    expect(countModelJson('{"elements":null,"relations":[]}')).toEqual({
      elements: 0,
      relationships: 0,
    });
  });
});

// ---------------------------------------------------------------------------
// 1.4 — non-destructive write contract
// ---------------------------------------------------------------------------

describe("canOverwrite — never clobber a hand edit", () => {
  it("allows writing when no file exists", () => {
    expect(canOverwrite(null)).toBe(true);
  });

  it("allows overwriting a file this producer wrote", () => {
    expect(canOverwrite(`${GENERATED_HEADER}\n\nmodel {\n}\n`)).toBe(true);
  });

  it("REFUSES to overwrite a file lacking the GENERATED header", () => {
    // /soleur:architecture writes the canonical three filenames cwd-relative and
    // the agent sandbox pins cwd = workspacePath. A tester who hand-corrects a
    // wrong edge must not have it silently reverted by the next sync.
    expect(canOverwrite("model {\n  component api\n}\n")).toBe(false);
  });

  it("refuses a file that only mentions the header inside prose", () => {
    // cq-assert-anchor-not-bare-token: the header must be the leading line, not a
    // substring somewhere in the body.
    expect(canOverwrite(`model {\n  // ${GENERATED_HEADER}\n}\n`)).toBe(false);
  });
});

describe("generateC4", () => {
  const docs = loadComponentDir(dir("frontmatter-form"));

  it("stamps the GENERATED header as the first line", () => {
    expect(generateC4(docs, buildEdges(docs)).split("\n")[0]).toBe(GENERATED_HEADER);
  });

  it("round-trips through canOverwrite (its own output is overwritable)", () => {
    expect(canOverwrite(generateC4(docs, buildEdges(docs)))).toBe(true);
  });

  it("is deterministic — no timestamp, stable ordering", () => {
    expect(generateC4(docs, buildEdges(docs))).toBe(generateC4(docs, buildEdges(docs)));
  });
});

// ---------------------------------------------------------------------------
// AC4 / AC5 — drift guards against the two in-repo precedents
// ---------------------------------------------------------------------------

describe("drift guards", () => {
  const regenScript = readFileSync(join(REPO_ROOT, "scripts/regenerate-c4-model.sh"), "utf8");

  // AC4. Both-gates validation (diagnostic stream AND element count) is only safe
  // while the pin holds — likec4's diagnostic WORDING is version-specific, which is
  // exactly why c4-render.ts refuses to gate on it.
  it("pins likec4 to the same version as regenerate-c4-model.sh", () => {
    const m = regenScript.match(/^LIKEC4_VERSION="([^"]+)"/m);
    expect(m).not.toBeNull();
    expect(LIKEC4_VERSION).toBe(m![1]);
  });

  it("pins likec4 to the same version as the server-side renderer", () => {
    const render = readFileSync(
      join(REPO_ROOT, "apps/web-platform/server/c4-render.ts"),
      "utf8",
    );
    expect(render).toContain(`likec4@${LIKEC4_VERSION}`);
  });

  // AC5. Mirror the SHELL gate, not c4-render.ts's. Assert behavioural equivalence
  // across a probe corpus rather than string equality — the shell uses POSIX
  // `[[:space:]]` and JS uses `\s`, so a literal comparison would be a false
  // signal in both directions.
  it("matches regenerate-c4-model.sh's DIAG_RE on an identical probe corpus", () => {
    const m = regenScript.match(/^DIAG_RE='([^']+)'/m);
    expect(m).not.toBeNull();
    const shellEquivalent = new RegExp(m![1].replace(/\[\[:space:\]\]/g, "\\s"), "m");

    const probes = [
      "Invalid model.c4",
      "Could not resolve reference",
      "    Line 274: unexpected token",
      "\tLine 9: bad",
      "workspace: /tmp/repo",
      "done in 1.2s",
      "invalid lowercase should not match",
      "some Invalid mid-line text should not match",
    ];
    for (const p of probes) {
      expect([p, DIAG_RE.test(p)]).toEqual([p, shellEquivalent.test(p)]);
    }
  });

  // AC5 negative half. The producer must not carry an instruction to mirror
  // c4-render.ts's stderr handling — c4-render.ts:193-195 explicitly REJECTS
  // stderr gating ("wording can drift across likec4 patch versions"), and it is
  // right to for a runtime save path that cannot pin the CLI. The producer can,
  // so it gates on both. Presence of good phrasing is not absence of bad.
  it("contains no instruction to mirror c4-render.ts's stderr handling", () => {
    const src = readFileSync(join(REPO_ROOT, "plugins/soleur/lib/c4-from-components.ts"), "utf8");
    expect(src).not.toMatch(/mirror\s+c4-render/i);
    expect(src).toMatch(/regenerate-c4-model\.sh/);
  });
});

// ---------------------------------------------------------------------------
// The four exports that had ZERO test callers
// ---------------------------------------------------------------------------
//
// Review found `toId`, `generateSpecC4`, `generateViewsC4` and `generateViewPage`
// absent from the import list entirely — four pure string generators, trivially
// testable, written without a test because they looked obvious. Two of the
// surviving mutations were live defects rather than gaps:
//
//   * `toId` dropping camelCase left the suite green AND disarmed a second test —
//     the e2e deprecated check greps for `legacyWorker`, an id `toId` produces, so
//     changing the casing makes that guard structurally unable to fail.
//   * `generateViewPage`'s fence naming a view `generateViewsC4` never declares
//     renders nothing in the KB viewer — precisely what the e2e's "carries a
//     likec4-view fence" assertion claims to prevent, while only checking that a
//     fence exists.

describe("toId — the identifier the generated .c4 depends on", () => {
  it("camelCases across every separator kebab/snake/space", () => {
    expect(toId("api-gateway")).toBe("apiGateway");
    expect(toId("web_server")).toBe("webServer");
    expect(toId("legacy worker")).toBe("legacyWorker");
  });

  it("produces a LikeC4-safe identifier from awkward input", () => {
    // Emitted UNQUOTED as an identifier, so it must never start with a digit and
    // must contain no separator characters.
    expect(toId("2fa-service")).toMatch(/^[A-Za-z][A-Za-z0-9]*$/);
    expect(toId("a.b/c:d")).toMatch(/^[A-Za-z][A-Za-z0-9]*$/);
  });

  it("never returns an empty identifier", () => {
    expect(toId("---").length).toBeGreaterThan(0);
    expect(toId("")).toMatch(/^[A-Za-z][A-Za-z0-9]*$/);
  });
});

describe("the seeded artifacts", () => {
  it("generateSpecC4 declares the `component` kind the generated model uses", () => {
    const spec = generateSpecC4();
    expect(spec.split("\n")[0]).toBe(GENERATED_HEADER);
    // generateC4 emits `<id> = component "..."`; without this declaration every
    // element is an unresolved reference and the whole render fails.
    expect(spec).toMatch(/element\s+component\s*\{/);
  });

  it("generateViewsC4 declares the view generateViewPage's fence names", () => {
    // THE pairing. Two independently-editable spellings of one identifier: if they
    // desync the page renders nothing, and every existing assertion still passes
    // because a fence is still present.
    const views = generateViewsC4();
    const declared = views.match(/view\s+([A-Za-z][A-Za-z0-9]*)\s*\{/);
    expect(declared).not.toBeNull();

    const page = generateViewPage();
    const fence = page.match(/```likec4-view\n([A-Za-z][A-Za-z0-9]*)\n```/);
    expect(fence).not.toBeNull();

    expect(fence![1]).toBe(declared![1]);
  });

  it("generateViewsC4 carries the GENERATED header; the markdown page does not", () => {
    expect(generateViewsC4().split("\n")[0]).toBe(GENERATED_HEADER);
    // `//` is not a markdown comment — c4-model.md is protected by O_EXCL seeding
    // instead, which is why the uniform "every file carries the header" claim was
    // corrected at review.
    expect(generateViewPage().split("\n")[0]).not.toBe(GENERATED_HEADER);
  });
});

describe("the C4 marker's field set is stable across every branch", () => {
  // The first version emitted a different field set per branch: `generated_*` and
  // `published` only on the render path, `detail` only on the unavailable path,
  // `docs` sometimes. An agent parsing a fixed key set got missing keys with no way
  // to tell absent-because-zero from absent-because-branch. kb-coverage's
  // MARKER_FIELDS already did this correctly; this is the sibling pinned the same way.
  const zero = Object.fromEntries(C4_MARKER_FIELDS.map((f) => [f, 0])) as Record<
    (typeof C4_MARKER_FIELDS)[number],
    number
  >;

  it("emits every field on a bare status with no reason", () => {
    const m = formatC4Marker("ok", zero);
    for (const f of C4_MARKER_FIELDS) expect(m).toContain(`${f}=`);
    expect(m.startsWith(C4_MARKER)).toBe(true);
  });

  it("emits every field when a reason and detail are present", () => {
    const m = formatC4Marker("degraded", zero, "render-timeout", "spawnSync ETIMEDOUT");
    for (const f of C4_MARKER_FIELDS) expect(m).toContain(`${f}=`);
    expect(m).toContain("reason=render-timeout");
  });

  it("keeps reason a bare token so a consumer can classify without parsing prose", () => {
    const m = formatC4Marker("degraded", zero, "no-generated-relationships", "a b c");
    expect(m).toMatch(/reason=[a-z0-9-]+ /);
    // The old form emitted a quoted sentence, so `reason=(\S+)` yielded `"0`.
    expect(m).not.toMatch(/reason="/);
  });

  it("is a single greppable line even when detail carries newlines and quotes", () => {
    const m = formatC4Marker("failed", zero, "source-fault", 'Invalid x\nLine 3: "bad"');
    expect(m).not.toContain("\n");
    // An unescaped quote in detail would terminate the field early.
    expect((m.match(/"/g) ?? []).length % 2).toBe(0);
  });
});
