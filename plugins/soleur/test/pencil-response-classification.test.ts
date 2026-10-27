import { describe, test, expect } from "bun:test";
import { classifyResponse, stripAnsi } from "../skills/pencil-setup/scripts/pencil-response-classify.mjs";

// The adapter's response classifier marks failure REPL strings as errors. The
// pre-fix classifier only matched /^Error:/, /^\[ERROR\]/ and
// /^Invalid properties:/, so auth-failure strings passed through as "success",
// which is how a failed mutation produced a 0-byte .pen without surfacing to the
// caller. @pen.dev/cli 0.3.13 prints its failures on stderr (red `Error:` /
// `Save failed:`, yellow `Unknown tool:`); the adapter hands the merged text here.

describe("classifyResponse — pre-existing error prefixes (regression guard)", () => {
  test("`Error: foo` is still an error", () => {
    const { isError, text } = classifyResponse("Error: something broke");
    expect(isError).toBe(true);
    expect(text).toBe("Error: something broke");
  });

  test("`[ERROR] foo` is still an error", () => {
    const { isError } = classifyResponse("[ERROR] something broke");
    expect(isError).toBe(true);
  });

  test("`Invalid properties: foo` is still an error", () => {
    const { isError } = classifyResponse("Invalid properties: padding is unexpected");
    expect(isError).toBe(true);
  });

  test("normal output (node id dump) is NOT an error", () => {
    const { isError } = classifyResponse('node0="abc"\nnode1="def"');
    expect(isError).toBe(false);
  });

  test("trims trailing/leading whitespace", () => {
    const { text } = classifyResponse("   hello world   \n");
    expect(text).toBe("hello world");
  });

  test("stripAnsi is the one shared export and also strips private-mode CSI (`ESC[?25l`)", () => {
    expect(stripAnsi("\x1b[?25lhidden cursor\x1b[?25h")).toBe("hidden cursor");
    expect(stripAnsi("\x1b[31mred\x1b[39m \x1b[2K\x1b[1;32mgreen")).toBe("red green");
    expect(classifyResponse("\x1b[?25l\x1b[31mError: red\x1b[39m").isError).toBe(true);
  });

  test("the class covers every CSI parameter byte (`:`, `<`, `=`, `>`, `?`) and every final byte (`@`..`~`)", () => {
    expect(stripAnsi("a\x1b[38:2:1:2:3mb")).toBe("ab"); // colon-separated sub-parameters
    expect(stripAnsi("a\x1b[>4;2mb\x1b[=1cc\x1b[<1ud")).toBe("abcd"); // private parameter prefixes
    expect(stripAnsi("a\x1b[2@b\x1b[3~c\x1b[5`d")).toBe("abcd"); // final bytes outside [a-zA-Z]
    expect(stripAnsi("Act\x1b[0mive")).toBe("Active");
  });

  test("strips ANSI escape sequences", () => {
    const { text } = classifyResponse("\x1b[31mError: red\x1b[0m");
    expect(text).toBe("Error: red");
    expect(classifyResponse("\x1b[31mError: red\x1b[0m").isError).toBe(true);
  });
});

describe("classifyResponse — auth-failure patterns", () => {
  test("the engine's own auth line is an error through the [ERROR] pattern", () => {
    // @pen.dev/cli 0.3.13 with no key and no login (measured)
    expect(
      classifyResponse('[ERROR] Authentication required. Run "pen login" or set PEN_CLI_KEY environment variable.').isError
    ).toBe(true);
  });

  test("`Invalid API key` is an error (case-insensitive)", () => {
    expect(classifyResponse("Invalid API key").isError).toBe(true);
    expect(classifyResponse("invalid api key: expired").isError).toBe(true);
  });

  test("`Unauthorized` is an error (case-insensitive)", () => {
    expect(classifyResponse("Unauthorized").isError).toBe(true);
    expect(classifyResponse("unauthorized: token expired").isError).toBe(true);
  });

  test("HTTP 401 response body is an error", () => {
    expect(classifyResponse("HTTP 401 Unauthorized").isError).toBe(true);
  });

  test("a login word in an innocuous context is NOT misclassified (the backtick `pencil login` pattern is retired)", () => {
    expect(classifyResponse('Created login form node node0="abc"').isError).toBe(false);
    expect(classifyResponse("Please run `pencil login` to authenticate").isError).toBe(false);
  });
});

// The engine answers a tool it does not have with `Unknown tool: <name>` (yellow,
// on stderr). It classified as success once and the auto-save ran after it (#11143).
describe("classifyResponse — Unknown tool (#11143)", () => {
  test("`Unknown tool: x` is an error", () => {
    expect(classifyResponse("Unknown tool: find_empty_space_on_canvas").isError).toBe(true);
  });
  test("the engine's yellow-wrapped line is an error (ANSI is stripped first)", () => {
    expect(classifyResponse("\x1b[33mUnknown tool: batch_design\x1b[39m\n").isError).toBe(true);
  });
  test("a node name containing the phrase mid-line is not an error", () => {
    expect(classifyResponse('{"name":"Unknown tool: label"}').isError).toBe(false);
  });
});

// 0.3.13 prints `Save failed: <reason>` (red, on stderr) and nothing else marks the failure.
describe("classifyResponse — Save failed (#11156)", () => {
  test("`Save failed: EACCES...` is an error", () => {
    expect(classifyResponse("Save failed: EACCES: permission denied, open '/x/y.pen'").isError).toBe(true);
  });
  test("the red-wrapped line is an error", () => {
    expect(classifyResponse("\x1b[31mSave failed: disk full\x1b[39m").isError).toBe(true);
  });
  test("a warning block followed by the Save failed line is an error", () => {
    expect(classifyResponse("[WARN] [IPC] request 'save-resource' failed\nSave failed: EACCES").isError).toBe(true);
  });
  test("mid-line mention is not an error", () => {
    expect(classifyResponse('Top-level nodes: `abc` (frame): Save failed: label [user visible]').isError).toBe(false);
  });
  test("`Saved <path>` is not an error", () => {
    expect(classifyResponse("\x1b[32mSaved /tmp/a/doc.pen\x1b[39m").isError).toBe(false);
  });
});

describe("classifyResponse — node names cannot trip the patterns", () => {
  test("created-node lines start with a quote, so a node named like an error is a success", () => {
    for (const name of ["Error: x", "[ERROR] x", "Unknown tool: x", "Save failed: x", "Unauthorized", "HTTP 401", "Invalid API key"]) {
      const reply = `OK\n\nGlobal variables (e.g. frame) carry over to subsequent calls!\n\n## Created nodes by name\n\`\`\`\n"${name}": "abc12" (= frame)\n\`\`\``;
      expect(classifyResponse(reply).isError).toBe(false);
    }
  });

  test("a node name on its own line of a successful execute reply cannot make it an error", () => {
    // a name containing a newline puts `Error:` at a line start inside the success reply
    const reply = 'OK\n\nGlobal variables (e.g. frame) carry over to subsequent calls!\n\n## Created nodes by name\n```\n"Hero\nError: boom": "abc12" (= frame)\n```';
    expect(classifyResponse(reply).isError).toBe(false);
  });

  test("the get_app_state listing with such a name is not an error either", () => {
    const reply = "# Current App State\n\n## Canvas Editor\n\n- Top-level nodes: `abc12` (frame): Hero\nSave failed: boom [user visible]\n";
    expect(classifyResponse(reply).isError).toBe(false);
  });

  test("a genuine error reply (no OK header) is still an error", () => {
    expect(classifyResponse("Error: ### Failure during operation execution\n\n- All operations in this block have been rolled back.").isError).toBe(true);
  });

  test("an `## issues detected:` block on an OK reply is not an error", () => {
    expect(classifyResponse("OK\n\n## Created nodes by name\n\n## issues detected:\n- node abc overflows its parent").isError).toBe(false);
  });
});
