/**
 * #9776 — hosted must-ask lane: the pure destroy-family classifier.
 *
 * Guard 1 of the plan (`## Guard Contract`): no hosted Bash command that force-pushes over, deletes or mirror-pushes
 * a protected branch, runs terraform/tofu destroy, or deletes a ref or repository through `gh`, reaches execution
 * without an Approve. This file drives the classifier over the stored corpus (`fixtures/destroy-ask-corpus.json`)
 * and adds the unit rows the corpus cannot express (laziness of the resolver, thrown errors, size bound, near-miss).
 *
 * Anti-vacuity: the row floor is a literal directly above its `if`, the rule-id set is compared by identity, and the
 * floor is reported by a plain throw, never through the assertions it backstops.
 */
import { describe, test, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  classifyDestroyFamily,
  destroyNearMiss,
  DESTROY_RULE_PREFIX,
  DESTROY_RULE_IDS,
  type ProtectedBranches,
} from "../server/destroy-ask-classifier";
import { isBashCommandSafe } from "../server/safe-bash";

interface Row {
  cmd: string;
  expect: "ask" | "pass";
  rule: string | null;
  protected?: string[];
  authoritative?: boolean;
  hookAsks: boolean;
  note?: string;
  nearMiss?: boolean;
  parityExempt?: string;
}
const corpus = JSON.parse(
  readFileSync(join(__dirname, "fixtures", "destroy-ask-corpus.json"), "utf8"),
) as { rows: Row[] };

function resolverFor(row: Pick<Row, "protected" | "authoritative">) {
  const calls = { n: 0 };
  const resolve = async (): Promise<ProtectedBranches> => {
    calls.n += 1;
    return {
      names: new Set((row.protected ?? ["main", "master"]).map((s) => s.toLowerCase())),
      authoritative: row.authoritative !== false,
    };
  };
  return { resolve, calls };
}

describe("destroy-ask classifier — corpus", () => {
  test("the corpus is not empty and covers every rule id (floor)", () => {
    const MIN_ROWS = 200;
    if (corpus.rows.length < MIN_ROWS) {
      throw new Error(`corpus has ${corpus.rows.length} rows, floor is ${MIN_ROWS}: a truncated corpus is vacuous`);
    }
    const seen = new Set(corpus.rows.filter((r) => r.expect === "ask").map((r) => r.rule));
    expect([...seen].sort()).toEqual(DESTROY_RULE_IDS.map((id) => id.slice(DESTROY_RULE_PREFIX.length)).filter((s) => s !== "classifier-error").sort());
  });

  test.each(corpus.rows.map((r, i) => [i, r] as const))("row %i classifies as declared", async (_i, row) => {
    const { resolve } = resolverFor(row);
    const match = await classifyDestroyFamily(row.cmd, resolve);
    const label = JSON.stringify(row.cmd);
    if (row.expect === "ask") {
      expect(match, `expected an ask for ${label}`).not.toBeNull();
      expect(match!.ruleId, label).toBe(`${DESTROY_RULE_PREFIX}${row.rule}`);
    } else {
      expect(match, `expected NO ask for ${label}, got ${match?.ruleId}`).toBeNull();
    }
  });

  test("every ask row is not safe-bash (CTO invariant: the safe-bash allow cannot pre-empt the lane)", () => {
    const asks = corpus.rows.filter((r) => r.expect === "ask");
    expect(asks.length).toBeGreaterThan(100);
    for (const row of asks) {
      expect(isBashCommandSafe(row.cmd), JSON.stringify(row.cmd)).toBe(false);
    }
  });

  test("every ask row the hook does not ask carries a hostedOnly note; parity exemptions are explicit", () => {
    for (const row of corpus.rows) {
      if (row.expect === "ask" && !row.hookAsks) {
        expect(row.note ?? "", JSON.stringify(row.cmd)).toContain("hostedOnly");
      }
      if (row.expect === "pass" && row.hookAsks) {
        expect(row.parityExempt ?? "", JSON.stringify(row.cmd)).not.toBe("");
      }
    }
  });

  test("every pass row declared nearMiss yields a near-miss event and no ask", () => {
    const declared = corpus.rows.filter((r) => r.expect === "pass" && r.nearMiss === true);
    expect(declared.length).toBeGreaterThanOrEqual(5);
    for (const row of declared) {
      expect(destroyNearMiss(row.cmd), JSON.stringify(row.cmd)).not.toBeNull();
    }
  });
});

describe("destroy-ask classifier — resolver laziness and degradation", () => {
  test("the resolver is awaited only after a force, delete or mirror push with a named destination", async () => {
    const lazy = resolverFor({});
    await classifyDestroyFamily("git status", lazy.resolve);
    await classifyDestroyFamily("git push origin feat-x", lazy.resolve);
    await classifyDestroyFamily("terraform destroy", lazy.resolve);
    await classifyDestroyFamily("git push -f", lazy.resolve);
    await classifyDestroyFamily("git push --mirror", lazy.resolve);
    expect(lazy.calls.n).toBe(0);
    await classifyDestroyFamily("git push -f origin main", lazy.resolve);
    expect(lazy.calls.n).toBe(1);
  });

  test("a resolver that throws degrades to unresolved: every force push asks", async () => {
    const throwing = async (): Promise<ProtectedBranches> => {
      throw new Error("boom");
    };
    const m = await classifyDestroyFamily("git push --force-with-lease origin feat-x", throwing);
    expect(m?.ruleId).toBe(`${DESTROY_RULE_PREFIX}git-push-unknown-default`);
  });

  test("a thrown classifier error is a match, never a pass", async () => {
    const evil = { toString() { throw new Error("hostile"); } } as unknown as string;
    const m = await classifyDestroyFamily(evil, async () => ({ names: new Set(["main"]), authoritative: true }));
    expect(m).not.toBeNull();
    expect(m!.ruleId).toBe(`${DESTROY_RULE_PREFIX}classifier-error`);
    expect(m!.error).toBeDefined();
  });

  test("an input past the size bound is unparseable: asks only when it names push or destroy", async () => {
    const pad = "x ".repeat(40_000);
    const { resolve } = resolverFor({});
    expect((await classifyDestroyFamily(`echo ${pad}`, resolve))).toBeNull();
    const m = await classifyDestroyFamily(`echo ${pad} terraform destroy`, resolve);
    expect(m?.ruleId).toBe(`${DESTROY_RULE_PREFIX}fail-closed-keyword`);
  });

  test("nesting past the depth bound is unparseable and fails toward ask when it names push", async () => {
    let cmd = "git push -f origin main";
    for (let i = 0; i < 7; i++) cmd = `bash -lc '${cmd.replace(/'/g, `'\\''`)}'`;
    const m = await classifyDestroyFamily(cmd, async () => ({ names: new Set(["main"]), authoritative: true }));
    expect(m).not.toBeNull();
  });

  test("a NUL byte is unparseable", async () => {
    const m = await classifyDestroyFamily("git push -f origin main\u0000", async () => ({ names: new Set(["main"]), authoritative: true }));
    expect(m?.ruleId).toBe(`${DESTROY_RULE_PREFIX}fail-closed-keyword`);
  });
});

describe("destroy-ask classifier — match payload", () => {
  test("a match names the family and the matched segment (for the card), and nothing else sensitive", async () => {
    const { resolve } = resolverFor({});
    const m = await classifyDestroyFamily("echo start && cd /w && git push --force origin main && echo done", resolve);
    expect(m).toMatchObject({ family: "git-default-branch", ruleId: `${DESTROY_RULE_PREFIX}git-force-default` });
    expect(m!.segment).toContain("git push --force origin main");
    expect(m!.segment).not.toContain("echo start");
  });

  test("terraform and gh families", async () => {
    const { resolve } = resolverFor({});
    expect((await classifyDestroyFamily("terraform destroy", resolve))?.family).toBe("terraform-destroy");
    expect((await classifyDestroyFamily("gh repo delete o/r --yes", resolve))?.family).toBe("gh-destroy");
    expect((await classifyDestroyFamily("git push -f origin \"x", resolve))?.family).toBe("fail-closed");
  });
});

describe("destroy near-miss", () => {
  test("keyword present but no match is a near-miss; ordinary commands are not", () => {
    expect(destroyNearMiss("echo terraform destroy docs")).not.toBeNull();
    expect(destroyNearMiss("git push --force-with-lease origin feat-x")).not.toBeNull();
    expect(destroyNearMiss("gh issue delete 5")).not.toBeNull();
    expect(destroyNearMiss("gh api graphql -f query='mutation{deleteRef(input:{})}'")).not.toBeNull();
    expect(destroyNearMiss("ls -la")).toBeNull();
    expect(destroyNearMiss("git push origin feat-x")).toBeNull();
  });
});
