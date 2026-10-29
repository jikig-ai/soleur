import { afterEach, describe, expect, it, vi } from "vitest";
import {
  ApprovalCanonicalError,
  CANONICAL_VERSION,
  canonicalJson,
  canonicalizeAction,
  computeActionHash,
  deriveApprovalHashKey,
  handlerArgsKey,
  hmacActionText,
} from "@/server/approval/canonical";
import {
  CONVERSATION_ID,
  FIELD_LISTS,
  OTHER_CONVERSATION_ID,
  OTHER_WORKSPACE_ID,
  SAMPLES,
  TOOLS,
  WORKSPACE_ID,
  mutateField,
} from "./fixtures";

const hashOf = (tool: string, s: { input: unknown; server: unknown }, ws = WORKSPACE_ID, conv = CONVERSATION_ID) =>
  computeActionHash({
    toolName: tool,
    workspaceId: ws,
    conversationId: conv,
    action: canonicalizeAction(tool, s.input, s.server),
  });

const ALL_TOOLS = Object.keys(FIELD_LISTS);

describe("canonicalJson", () => {
  it("sorts keys recursively and is stable across key order", () => {
    expect(canonicalJson({ b: 1, a: { d: [3, { y: 1, x: 2 }], c: "z" } })).toBe(
      '{"a":{"c":"z","d":[3,{"x":2,"y":1}]},"b":1}',
    );
    expect(canonicalJson({ a: 1, b: 2 })).toBe(canonicalJson({ b: 2, a: 1 }));
  });

  it("rejects values that have no canonical form instead of coercing them", () => {
    expect(() => canonicalJson({ a: undefined })).toThrow(ApprovalCanonicalError);
    expect(() => canonicalJson({ a: Number.NaN })).toThrow(ApprovalCanonicalError);
    expect(() => canonicalJson({ a: () => 1 })).toThrow(ApprovalCanonicalError);
  });
});

describe("canonicalizeAction: one test row per slice-1 tool (Phase 0.3 field lists)", () => {
  it("covers exactly the eight slice-1 tools", () => {
    expect(ALL_TOOLS.sort()).toEqual(Object.values(TOOLS).sort());
    expect(ALL_TOOLS).toHaveLength(8);
  });

  for (const tool of ALL_TOOLS) {
    describe(tool, () => {
      const list = FIELD_LISTS[tool];
      const sample = SAMPLES[tool];

      it("is versioned and carries every input and server-derived field", () => {
        const a = canonicalizeAction(tool, sample.input, sample.server);
        expect(a.v).toBe(CANONICAL_VERSION);
        expect(a.tool).toBe(tool);
        expect(Object.keys(a.fields).sort()).toEqual([...list.input, ...list.server].sort());
      });

      it("flips the hash when ANY single field changes", () => {
        const base = hashOf(tool, sample);
        for (const field of [...list.input, ...list.server]) {
          expect(hashOf(tool, mutateField(tool, field)), `field ${field}`).not.toBe(base);
        }
      });

      it("hashes the same action to the same value regardless of input key order", () => {
        const reversed = {
          input: Object.fromEntries(Object.entries(sample.input).reverse()),
          server: Object.fromEntries(Object.entries(sample.server).reverse()),
        };
        expect(hashOf(tool, reversed)).toBe(hashOf(tool, sample));
      });

      it("treats a zod default and its omission as the same action", () => {
        for (const [field, dflt] of Object.entries(list.defaults)) {
          const omitted = structuredClone(sample);
          delete omitted.input[field];
          const explicit = structuredClone(sample);
          explicit.input[field] = dflt;
          expect(hashOf(tool, omitted), `default ${field}`).toBe(hashOf(tool, explicit));
        }
      });

      it("binds the tool name, the workspace and the conversation into the hash", () => {
        const base = hashOf(tool, sample);
        expect(hashOf(tool, sample, OTHER_WORKSPACE_ID)).not.toBe(base);
        expect(hashOf(tool, sample, WORKSPACE_ID, OTHER_CONVERSATION_ID)).not.toBe(base);
        const a = canonicalizeAction(tool, sample.input, sample.server);
        expect(() =>
          computeActionHash({ toolName: `${tool}_other`, workspaceId: WORKSPACE_ID, conversationId: CONVERSATION_ID, action: a }),
        ).toThrow(ApprovalCanonicalError);
      });

      it("ignores keys the handler's zod object strips (they cannot change what runs)", () => {
        const extra = { input: { ...sample.input, __injected: "x" }, server: sample.server };
        expect(hashOf(tool, extra)).toBe(hashOf(tool, sample));
      });

      it("fails closed on a wrongly typed or missing required field", () => {
        const req = Object.keys(sample.input).find((k) => !["replyTo", "postalAddress", "optOut", "ftcDisclosure", "art14", "body", "inputs", "force", "base", "jurisdiction"].includes(k));
        if (req) {
          const bad = structuredClone(sample.input);
          bad[req] = { not: "the right type" };
          expect(() => canonicalizeAction(tool, bad, sample.server)).toThrow(ApprovalCanonicalError);
          const missing = structuredClone(sample.input);
          delete missing[req];
          expect(() => canonicalizeAction(tool, missing, sample.server)).toThrow(ApprovalCanonicalError);
        }
        expect(() => canonicalizeAction(tool, null, sample.server)).toThrow(ApprovalCanonicalError);
        expect(() => canonicalizeAction(tool, "string", sample.server)).toThrow(ApprovalCanonicalError);
      });

      if (list.server.length > 0) {
        it("refuses to canonicalize without every server-derived field", () => {
          for (const f of list.server) {
            const s = structuredClone(sample.server);
            delete s[f];
            expect(() => canonicalizeAction(tool, sample.input, s), `missing ${f}`).toThrow(ApprovalCanonicalError);
          }
          expect(() => canonicalizeAction(tool, sample.input, undefined)).toThrow(ApprovalCanonicalError);
        });
      }
    });
  }

  it("rejects a tool outside slice 1", () => {
    expect(() => canonicalizeAction("mcp__soleur_platform__create_issue", {}, {})).toThrow(ApprovalCanonicalError);
    expect(() => canonicalizeAction("Bash", { command: "ls" }, {})).toThrow(ApprovalCanonicalError);
  });

  it("errors carry a static message and never echo the input", () => {
    try {
      canonicalizeAction(TOOLS.emailSend, { to: "secret-recipient@example.test", subject: 5 }, {});
      throw new Error("expected throw");
    } catch (e) {
      expect(e).toBeInstanceOf(ApprovalCanonicalError);
      expect(String((e as Error).message)).not.toContain("secret-recipient");
    }
  });
});

describe("full-input fidelity (the preview was lossy; the canonical object is not)", () => {
  it("github_push_branch binds force, which buildGateMessage omits", () => {
    const base = SAMPLES[TOOLS.pushBranch];
    const forced = { ...base, input: { ...base.input, force: true } };
    expect(hashOf(TOOLS.pushBranch, forced)).not.toBe(hashOf(TOOLS.pushBranch, base));
  });

  it("create_pull_request binds the full body, workflow binds inputs, autonomous binds the value", () => {
    const pr = SAMPLES[TOOLS.createPr];
    expect(hashOf(TOOLS.createPr, { ...pr, input: { ...pr.input, body: "other" } })).not.toBe(hashOf(TOOLS.createPr, pr));
    const wf = SAMPLES[TOOLS.triggerWorkflow];
    expect(hashOf(TOOLS.triggerWorkflow, { ...wf, input: { ...wf.input, inputs: { environment: "prod" } } })).not.toBe(
      hashOf(TOOLS.triggerWorkflow, wf),
    );
    const au = SAMPLES[TOOLS.setAutonomous];
    expect(hashOf(TOOLS.setAutonomous, { ...au, input: { value: false } })).not.toBe(hashOf(TOOLS.setAutonomous, au));
  });

  it("email_reply binds the server-derived recipient that is absent from the model input", () => {
    const r = SAMPLES[TOOLS.emailReply];
    expect(hashOf(TOOLS.emailReply, { ...r, server: { recipient: "someone-else@example.test" } })).not.toBe(
      hashOf(TOOLS.emailReply, r),
    );
  });

  it("does not truncate: a 100 KB body and its 99,999-char prefix hash differently", () => {
    const base = SAMPLES[TOOLS.emailSend];
    const big = "a".repeat(100_000);
    const a = canonicalizeAction(TOOLS.emailSend, { ...base.input, body: big }, {});
    expect(a.fields.body).toBe(big);
    expect(hashOf(TOOLS.emailSend, { input: { ...base.input, body: big }, server: {} })).not.toBe(
      hashOf(TOOLS.emailSend, { input: { ...base.input, body: big.slice(0, 99_999) }, server: {} }),
    );
  });

  it("does not normalise Unicode: NFC and NFD spellings of the same text hash differently", () => {
    const base = SAMPLES[TOOLS.emailSend];
    const nfc = "café";
    const nfd = "café";
    expect(nfc.normalize("NFD")).toBe(nfd);
    expect(hashOf(TOOLS.emailSend, { input: { ...base.input, body: nfc }, server: {} })).not.toBe(
      hashOf(TOOLS.emailSend, { input: { ...base.input, body: nfd }, server: {} }),
    );
  });

  it("does not trim: surrounding whitespace is part of the action and of the hash", () => {
    const base = SAMPLES[TOOLS.emailSend];
    const padded = canonicalizeAction(TOOLS.emailSend, { ...base.input, body: "  hello\n" }, {});
    expect(padded.fields.body).toBe("  hello\n");
    expect(hashOf(TOOLS.emailSend, { input: { ...base.input, body: "hello" }, server: {} })).not.toBe(
      hashOf(TOOLS.emailSend, { input: { ...base.input, body: "hello " }, server: {} }),
    );
  });

  it("workflow inputs hash independent of key order", () => {
    const wf = SAMPLES[TOOLS.triggerWorkflow];
    const a = hashOf(TOOLS.triggerWorkflow, { ...wf, input: { ...wf.input, inputs: { a: "1", b: "2" } } });
    const b = hashOf(TOOLS.triggerWorkflow, { ...wf, input: { ...wf.input, inputs: { b: "2", a: "1" } } });
    expect(a).toBe(b);
  });
});

describe("computeActionHash (HMAC-SHA256, keyed from SENTRY_USERID_PEPPER)", () => {
  // Known-answer vectors computed OUTSIDE this codebase (python hmac/hashlib over hand-written literals), so a
  // change to canonicalJson, the key derivation or the digest cannot move the expected value with it.
  //   key  = HMAC-SHA256(pepper, "soleur:approval-request:action-sha256:v1")
  //   hash = HMAC-SHA256(key, text)
  const KAT_PEPPER = "kat-pepper-0123456789abcdef";
  const KAT_KEY = "e0b7ffa054210ee9f4d17543d0a24981456a5c637c92134fedec60c9d59fe560";
  const KAT_TEXT_HASH = "f30c86e4e7f037722726c0981bc86496c43605f7bd8983cd0d41ed32eeadeabe"; // over '{"a":1}'
  const KAT_ACTION_TEXT =
    '{"action":{"fields":{"documentPath":"knowledge-base/pricing/q4.md"},"tool":"mcp__soleur_platform__kb_share_create","v":1},' +
    '"conversation_id":"00000000-0000-4000-8000-000000000003","tool_name":"mcp__soleur_platform__kb_share_create",' +
    '"workspace_id":"00000000-0000-4000-8000-000000000001"}';
  const KAT_ACTION_HASH = "974b85df97f307b40371a1b15cc439ea37368753fd3fc12360d25d714faacc1a";
  const KAT_UNKEYED_SHA256 = "7d9d2ef31a3d1d1a678a991c9e112fddcf04a15c29596b9259297c96274e7579";

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("derives the key by domain separation from the pepper (known answer)", () => {
    expect(deriveApprovalHashKey(KAT_PEPPER).toString("hex")).toBe(KAT_KEY);
    expect(hmacActionText('{"a":1}', KAT_PEPPER)).toBe(KAT_TEXT_HASH);
  });

  it("hashes a real canonicalised action to the externally computed HMAC, and NOT to the unkeyed sha256", () => {
    vi.stubEnv("SENTRY_USERID_PEPPER", KAT_PEPPER);
    const s = SAMPLES[TOOLS.kbShareCreate];
    const action = canonicalizeAction(TOOLS.kbShareCreate, s.input, s.server);
    // The text the SUT hashes is the hand-written literal (so canonicalJson cannot drift unnoticed).
    expect(canonicalJson({ tool_name: TOOLS.kbShareCreate, workspace_id: WORKSPACE_ID, conversation_id: CONVERSATION_ID, action })).toBe(KAT_ACTION_TEXT);
    const h = computeActionHash({ toolName: TOOLS.kbShareCreate, workspaceId: WORKSPACE_ID, conversationId: CONVERSATION_ID, action });
    expect(h).toMatch(/^[0-9a-f]{64}$/);
    expect(h).toBe(KAT_ACTION_HASH);
    expect(h).not.toBe(KAT_UNKEYED_SHA256);
  });

  it("a different pepper yields a different hash (the secret is part of the fingerprint)", () => {
    const s = SAMPLES[TOOLS.kbShareCreate];
    const action = canonicalizeAction(TOOLS.kbShareCreate, s.input, s.server);
    const args = { toolName: TOOLS.kbShareCreate, workspaceId: WORKSPACE_ID, conversationId: CONVERSATION_ID, action };
    vi.stubEnv("SENTRY_USERID_PEPPER", KAT_PEPPER);
    const a = computeActionHash(args);
    vi.stubEnv("SENTRY_USERID_PEPPER", `${KAT_PEPPER}-rotated`);
    expect(computeActionHash(args)).not.toBe(a);
  });

  it("FAILS CLOSED when the pepper is unset or empty: key_unavailable, never an unkeyed hash", () => {
    const s = SAMPLES[TOOLS.kbShareCreate];
    const action = canonicalizeAction(TOOLS.kbShareCreate, s.input, s.server);
    const args = { toolName: TOOLS.kbShareCreate, workspaceId: WORKSPACE_ID, conversationId: CONVERSATION_ID, action };
    for (const v of [undefined, ""]) {
      if (v === undefined) vi.stubEnv("SENTRY_USERID_PEPPER", undefined as unknown as string);
      else vi.stubEnv("SENTRY_USERID_PEPPER", v);
      if (v === undefined) delete process.env.SENTRY_USERID_PEPPER;
      let err: unknown;
      try {
        computeActionHash(args);
      } catch (e) {
        err = e;
      }
      expect(err).toBeInstanceOf(ApprovalCanonicalError);
      expect((err as ApprovalCanonicalError).code).toBe("key_unavailable");
      expect((err as Error).message).not.toContain(KAT_UNKEYED_SHA256);
    }
    expect(() => deriveApprovalHashKey("")).toThrow(ApprovalCanonicalError);
    expect(() => hmacActionText("x", "")).toThrow(ApprovalCanonicalError);
  });

  it("rejects a tool name that is not the action's tool", () => {
    const s = SAMPLES[TOOLS.kbShareCreate];
    const action = canonicalizeAction(TOOLS.kbShareCreate, s.input, s.server);
    expect(() =>
      computeActionHash({ toolName: TOOLS.emailSend, workspaceId: WORKSPACE_ID, conversationId: CONVERSATION_ID, action }),
    ).toThrow(ApprovalCanonicalError);
  });

  it("rejects ids that are not UUID-shaped", () => {
    const s = SAMPLES[TOOLS.kbShareCreate];
    const action = canonicalizeAction(TOOLS.kbShareCreate, s.input, s.server);
    expect(() => computeActionHash({ toolName: TOOLS.kbShareCreate, workspaceId: "ws-1", conversationId: CONVERSATION_ID, action })).toThrow(
      ApprovalCanonicalError,
    );
  });
});

describe("handlerArgsKey (execution-grant key a tool handler can recompute)", () => {
  it("applies the same zod defaults as the gate and carries no server-derived field", () => {
    const s = SAMPLES[TOOLS.pushBranch];
    const withDefault = handlerArgsKey(TOOLS.pushBranch, { branch: "feat/x" });
    expect(withDefault).toBe('{"branch":"feat/x","force":false}');
    expect(handlerArgsKey(TOOLS.pushBranch, { branch: "feat/x", force: false })).toBe(withDefault);
    expect(handlerArgsKey(TOOLS.pushBranch, s.input)).not.toContain("headSha");
  });

  it("does not throw on optional keys that are undefined, and rejects invalid input / unsupported tools", () => {
    expect(handlerArgsKey(TOOLS.createPr, { head: "h", title: "t", body: undefined })).toBe('{"base":"main","head":"h","title":"t"}');
    expect(() => handlerArgsKey(TOOLS.pushBranch, { branch: "" })).toThrow(ApprovalCanonicalError);
    expect(() => handlerArgsKey("mcp__soleur_platform__create_issue", {})).toThrow(ApprovalCanonicalError);
  });
});
