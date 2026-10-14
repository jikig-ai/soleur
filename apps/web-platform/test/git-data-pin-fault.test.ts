import { describe, expect, it } from "vitest";
import {
  classifyGitDataPinFault,
  GIT_DATA_PIN_FAULT_REASONS,
  GitDataHostKeyPinError,
} from "../server/git-data-pin-fault";

// #8572: the pin-fault classifier and the resolver's error class. Unit, no module mocks.

/** A transport rejection shaped the way execFileAsync builds one: a real Error with fields. */
function rejection(fields: { code?: unknown; stderr?: unknown; syscall?: unknown }): Error {
  return Object.assign(new Error("Command failed: ssh …"), fields);
}

const HOST_KEY_STDERR = "Host key verification failed.";

describe("classifyGitDataPinFault", () => {
  const cases: Array<[string, unknown, "ssh" | "git", string | null]> = [
    ["resolver: absent pin", new GitDataHostKeyPinError("pin_absent", { storeEnabled: true }), "ssh", "pin_absent"],
    ["resolver: invalid pin", new GitDataHostKeyPinError("pin_invalid", { storeEnabled: false }), "ssh", "pin_invalid"],
    ["resolver error, via git", new GitDataHostKeyPinError("pin_absent", { storeEnabled: true }), "git", "pin_absent"],
    ["spawn ssh ENOENT", rejection({ code: "ENOENT", syscall: "spawn ssh" }), "ssh", "ssh_client_absent"],
    ["spawn ssh ENOENT under git", rejection({ code: "ENOENT", syscall: "spawn ssh" }), "git", "ssh_client_absent"],
    ["spawn git ENOENT is not a pin fault", rejection({ code: "ENOENT", syscall: "spawn git" }), "git", null],
    ["ssh 255 + host-key text", rejection({ code: 255, stderr: HOST_KEY_STDERR }), "ssh", "host_key_mismatch"],
    ["ssh 128 + host-key text is the remote's status", rejection({ code: 128, stderr: HOST_KEY_STDERR }), "ssh", null],
    // The push is never read for host identity: git's 128 is every fatal error, and some
    // echo the tenant's own bytes (security review F1, #8572).
    [
      "git 128 + host-key text is not read on the push",
      rejection({ code: 128, stderr: `${HOST_KEY_STDERR}\nfatal: Could not read from remote repository.` }),
      "git",
      null,
    ],
    [
      "tenant-forged host-key text in a packed-refs fatal",
      rejection({ code: 128, stderr: "fatal: unexpected line in .git/packed-refs: Host key verification failed" }),
      "git",
      null,
    ],
    ["git 255 + host-key text is not git's status", rejection({ code: 255, stderr: HOST_KEY_STDERR }), "git", null],
    ["ssh 255 + auth text", rejection({ code: 255, stderr: "Permission denied (publickey)." }), "ssh", null],
    [
      "changed key text",
      rejection({ code: 255, stderr: "@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @" }),
      "ssh",
      "host_key_mismatch",
    ],
    ["no key known under the alias", rejection({ code: 255, stderr: "No ED25519 host key is known for git-data and you have requested strict checking." }), "ssh", "host_key_mismatch"],
    ["no common algorithm", rejection({ code: 255, stderr: "Unable to negotiate: no matching host key type found." }), "ssh", "host_key_mismatch"],
    ["host-key text in message only, not stderr", Object.assign(new Error(HOST_KEY_STDERR), { code: 255 }), "ssh", null],
    ["fence reject", rejection({ code: 1, stderr: "remote: fence: stale lease-gen" }), "git", null],
  ];

  it.each(cases)("%s", (_label, err, via, expected) => {
    expect(classifyGitDataPinFault(err, via)).toBe(expected);
  });

  it("accepts the error by name when instanceof fails (a module loaded twice)", () => {
    const twin = Object.assign(new Error("x"), { name: "GitDataHostKeyPinError", reason: "pin_invalid" });
    expect(twin instanceof GitDataHostKeyPinError).toBe(false);
    expect(classifyGitDataPinFault(twin, "ssh")).toBe("pin_invalid");
  });

  it("drops a forged reason outside the resolver's vocabulary", () => {
    for (const reason of ["host_key_mismatch", "ssh_client_absent", "unreachable", "", 1, undefined]) {
      const forged = Object.assign(new Error("x"), { name: "GitDataHostKeyPinError", reason });
      expect(classifyGitDataPinFault(forged, "ssh")).toBeNull();
    }
  });

  it("returns null for hostile or empty inputs and never throws", () => {
    const throwingGetter = Object.defineProperty(new Error("x"), "stderr", {
      get() {
        throw new Error("boom");
      },
    });
    Object.assign(throwingGetter, { code: 255 });
    for (const input of [null, undefined, "Host key verification failed.", 255, {}, [], throwingGetter]) {
      expect(() => classifyGitDataPinFault(input, "ssh")).not.toThrow();
      expect(classifyGitDataPinFault(input, "ssh")).toBeNull();
    }
  });

  it("only ever returns a member of the vocabulary", () => {
    for (const [, err, via] of cases) {
      const r = classifyGitDataPinFault(err, via);
      if (r !== null) expect(GIT_DATA_PIN_FAULT_REASONS).toContain(r);
    }
  });
});

describe("GitDataHostKeyPinError", () => {
  it("keeps the resolver's messages byte-identical", () => {
    expect(new GitDataHostKeyPinError("pin_invalid", { storeEnabled: true }).message).toBe(
      "git-data: GIT_DATA_SSH_HOST_KEY is malformed — expected exactly one `ssh-ed25519 <base64>` key with no host pattern, marker, comment or newline. Refusing to dial the git-data host.",
    );
    expect(new GitDataHostKeyPinError("pin_absent", { storeEnabled: true }).message).toBe(
      "git-data: GIT_DATA_SSH_HOST_KEY is unset (GIT_DATA_STORE_ENABLED=true) — refusing unpinned SSH to the git-data host. The replace job publishes it to Doppler prd; if the secret is already there, the container has not loaded it (dispatch git-data-cutover.yml mode=redeploy to re-load it).",
    );
    expect(new GitDataHostKeyPinError("pin_absent", { storeEnabled: false }).message).toBe(
      "git-data: GIT_DATA_SSH_HOST_KEY is unset (GIT_DATA_STORE_ENABLED is not true) — refusing unpinned SSH to the git-data host. The replace job publishes it to Doppler prd; if the secret is already there, the container has not loaded it (dispatch git-data-cutover.yml mode=redeploy to re-load it).",
    );
  });

  it("is an Error with a fixed name and reason", () => {
    const e = new GitDataHostKeyPinError("pin_absent", { storeEnabled: true });
    expect(e).toBeInstanceOf(Error);
    expect(e.name).toBe("GitDataHostKeyPinError");
    expect(e.reason).toBe("pin_absent");
  });
});
