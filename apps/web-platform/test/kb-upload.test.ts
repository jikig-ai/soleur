import { describe, test, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const {
  mockGetUser,
  mockFrom,
  mockGithubApiGet,
  mockGithubApiPost,
  mockGenerateInstallationToken,
  mockRandomCredentialPath,
  mockIsPathInWorkspace,
  mockExecFile,
  mockWriteFileSync,
  mockUnlinkSync,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockGithubApiGet: vi.fn(),
  mockGithubApiPost: vi.fn(),
  mockGenerateInstallationToken: vi.fn(),
  mockRandomCredentialPath: vi.fn(),
  mockIsPathInWorkspace: vi.fn(),
  mockExecFile: vi.fn(),
  mockWriteFileSync: vi.fn(),
  mockUnlinkSync: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
  })),
  createServiceClient: vi.fn(() => ({
    from: mockFrom,
  })),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.ai" })),
  rejectCsrf: vi.fn(
    (_route: string, _origin: string | null) =>
      new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));

vi.mock("@/server/github-api", () => ({
  githubApiGet: mockGithubApiGet,
  githubApiPost: mockGithubApiPost,
}));

vi.mock("@/server/github-app", () => ({
  generateInstallationToken: mockGenerateInstallationToken,
  randomCredentialPath: mockRandomCredentialPath,
}));

vi.mock("@/server/sandbox", () => ({
  isPathInWorkspace: mockIsPathInWorkspace,
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: vi.fn(),
}));

vi.mock("node:child_process", () => ({
  execFile: mockExecFile,
}));

vi.mock("node:util", () => ({
  promisify: vi.fn((fn: unknown) => fn),
}));

vi.mock("node:fs", () => ({
  writeFileSync: mockWriteFileSync,
  unlinkSync: mockUnlinkSync,
}));

// ---------------------------------------------------------------------------
// Import route handler AFTER mocks
// ---------------------------------------------------------------------------

import { POST } from "@/app/api/kb/upload/route";
import { validateOrigin } from "@/lib/auth/validate-origin";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const TEST_USER_ID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
const TEST_INSTALLATION_ID = 12345;
const TEST_WORKSPACE_PATH = "/workspaces/test-user";
const TEST_REPO_URL = "https://github.com/test-owner/test-repo";

function createFormData(file: File, targetDir: string, sha?: string): FormData {
  const formData = new FormData();
  formData.append("file", file);
  formData.append("targetDir", targetDir);
  if (sha) formData.append("sha", sha);
  return formData;
}

function createRequest(formData: FormData, origin?: string): Request {
  const headers = new Headers();
  if (origin) headers.set("Origin", origin);
  return new Request("http://localhost:3000/api/kb/upload", {
    method: "POST",
    body: formData,
    headers,
  });
}

function setupAuthenticatedUser() {
  mockGetUser.mockResolvedValue({
    data: { user: { id: TEST_USER_ID } },
  });
}

function setupUserData(overrides: Record<string, unknown> = {}) {
  const mockSingle = vi.fn().mockResolvedValue({
    data: {
      workspace_path: TEST_WORKSPACE_PATH,
      workspace_status: "ready",
      repo_url: TEST_REPO_URL,
      github_installation_id: TEST_INSTALLATION_ID,
      ...overrides,
    },
    error: null,
  });
  const mockEq = vi.fn(() => ({ single: mockSingle }));
  const mockSelect = vi.fn(() => ({ eq: mockEq }));

  mockFrom.mockImplementation((table: string) => {
    if (table === "users") {
      return { select: mockSelect };
    }
    return {};
  });
}

function setupFullMocks() {
  setupAuthenticatedUser();
  setupUserData();
  mockIsPathInWorkspace.mockReturnValue(true);
  mockGenerateInstallationToken.mockResolvedValue("test-token");
  mockRandomCredentialPath.mockReturnValue("/tmp/git-cred-test-uuid");
  // File does not exist (404 from GitHub)
  mockGithubApiGet.mockRejectedValue(new Error("GitHub API request failed: 404 /repos/test-owner/test-repo/contents/knowledge-base/uploads/test.png"));
  // Successful PUT
  mockGithubApiPost.mockResolvedValue({
    content: { sha: "newsha123", path: "knowledge-base/uploads/test.png" },
    commit: { sha: "commitsha456" },
  });
  // Successful git pull
  mockExecFile.mockResolvedValue({ stdout: "", stderr: "" });
}

function makeTestFile(name = "test.png", size?: number): File {
  const content = size
    ? new Uint8Array(size)
    : new Uint8Array([0x89, 0x50, 0x4e, 0x47]); // PNG magic bytes
  return new File([content], name, { type: "image/png" });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("POST /api/kb/upload", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // 1. CSRF validation
  test("returns 403 when CSRF validation fails", async () => {
    vi.mocked(validateOrigin).mockReturnValueOnce({
      valid: false,
      origin: "https://evil.com",
    });

    const formData = createFormData(makeTestFile(), "uploads");
    const res = await POST(createRequest(formData, "https://evil.com"));
    expect(res.status).toBe(403);
  });

  // 2. Auth
  test("returns 401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });

    const formData = createFormData(makeTestFile(), "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(401);

    const body = await res.json();
    expect(body.error).toMatch(/unauthorized/i);
  });

  // 3. Type validation
  test("returns 415 for disallowed file type (.exe)", async () => {
    setupFullMocks();

    const exeFile = new File([new Uint8Array([0x4d, 0x5a])], "virus.exe", {
      type: "application/x-msdownload",
    });
    const formData = createFormData(exeFile, "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(415);
  });

  // 4. Size validation
  test("returns 413 for file exceeding 20MB", async () => {
    setupFullMocks();

    const largeFile = makeTestFile("big.png", 21 * 1024 * 1024);
    const formData = createFormData(largeFile, "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(413);
  });

  // 5. Path traversal
  test("returns 400 for path traversal in targetDir", async () => {
    setupFullMocks();
    mockIsPathInWorkspace.mockReturnValue(false);

    const formData = createFormData(makeTestFile(), "../../etc/passwd");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(400);
  });

  // 6. Null byte
  test("returns 400 for null byte in targetDir", async () => {
    setupFullMocks();

    const formData = createFormData(makeTestFile(), "uploads\0evil");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(400);
  });

  // 7. Filename sanitization — leading dot
  test("returns 400 for filename starting with a dot", async () => {
    setupFullMocks();

    const dotFile = new File([new Uint8Array([0x89, 0x50])], ".hidden.png", {
      type: "image/png",
    });
    const formData = createFormData(dotFile, "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(400);
  });

  // 8. Filename sanitization — control characters
  test("returns 400 for filename with control characters only", async () => {
    setupFullMocks();

    const ctrlFile = new File([new Uint8Array([0x89, 0x50])], "\x01\x02.png", {
      type: "image/png",
    });
    const formData = createFormData(ctrlFile, "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(400);
  });

  // 9. Windows reserved names
  test("returns 400 for Windows reserved filename (CON)", async () => {
    setupFullMocks();

    const conFile = new File([new Uint8Array([0x89, 0x50])], "CON.png", {
      type: "image/png",
    });
    const formData = createFormData(conFile, "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(400);
  });

  // 10. Duplicate detection
  test("returns 409 with sha when file already exists", async () => {
    setupFullMocks();
    // Override: file DOES exist at GitHub
    mockGithubApiGet.mockResolvedValue({
      sha: "existingsha789",
      name: "test.png",
      path: "knowledge-base/uploads/test.png",
    });

    const formData = createFormData(makeTestFile(), "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(409);

    const body = await res.json();
    expect(body.sha).toBe("existingsha789");
  });

  // 11. Successful upload (includes credential helper verification)
  test("returns 201 with path, sha, commitSha on success", async () => {
    setupFullMocks();

    const formData = createFormData(makeTestFile(), "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(201);

    const body = await res.json();
    expect(body.path).toBeDefined();
    expect(body.sha).toBe("newsha123");
    expect(body.commitSha).toBe("commitsha456");

    // Verify git pull used credential helper
    expect(mockExecFile).toHaveBeenCalledWith(
      "git",
      expect.arrayContaining(["-c", expect.stringContaining("credential.helper=!")]),
      expect.objectContaining({ cwd: TEST_WORKSPACE_PATH }),
    );
  });

  // 12. Overwrite with sha
  test("includes sha in GitHub PUT when provided for overwrite", async () => {
    setupFullMocks();

    const formData = createFormData(makeTestFile(), "uploads", "existingsha789");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(201);

    // Verify githubApiPost was called with sha in the body
    expect(mockGithubApiPost).toHaveBeenCalledWith(
      TEST_INSTALLATION_ID,
      expect.stringContaining("/contents/knowledge-base/uploads/test.png"),
      expect.objectContaining({ sha: "existingsha789" }),
      "PUT",
    );
  });

  // 13. Workspace sync failure
  test("returns 500 with SYNC_FAILED when git pull fails", async () => {
    setupFullMocks();
    // Override: git pull fails
    mockExecFile.mockRejectedValue(new Error("git pull failed: merge conflict"));

    const formData = createFormData(makeTestFile(), "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(500);

    const body = await res.json();
    expect(body.code).toBe("SYNC_FAILED");
  });

  // 14. GitHub API error
  test("returns 502 when GitHub API returns an error during upload", async () => {
    setupFullMocks();
    // Override: GitHub PUT fails with a non-404 error
    mockGithubApiGet.mockRejectedValue(new Error("GitHub API request failed: 404 /repos/test-owner/test-repo/contents/knowledge-base/uploads/test.png"));
    mockGithubApiPost.mockRejectedValue(new Error("GitHub API request failed: 500 /repos/test-owner/test-repo/contents/knowledge-base/uploads/test.png"));

    const formData = createFormData(makeTestFile(), "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(502);

    const body = await res.json();
    expect(body.code).toBe("GITHUB_API_ERROR");
  });

  // 15. Credential helper: written with correct content and permissions
  test("credential helper is written with correct content and permissions", async () => {
    setupFullMocks();

    const formData = createFormData(makeTestFile(), "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(201);

    expect(mockWriteFileSync).toHaveBeenCalledWith(
      "/tmp/git-cred-test-uuid",
      expect.stringContaining("x-access-token"),
      expect.objectContaining({ mode: 0o700 }),
    );
  });

  // 16. Credential helper: cleanup after successful pull
  test("credential helper file is cleaned up after successful pull", async () => {
    setupFullMocks();

    const formData = createFormData(makeTestFile(), "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(201);

    expect(mockUnlinkSync).toHaveBeenCalledWith("/tmp/git-cred-test-uuid");
  });

  // 17. Credential helper: cleanup after failed pull
  test("credential helper file is cleaned up after failed pull", async () => {
    setupFullMocks();
    mockExecFile.mockRejectedValue(new Error("git pull failed"));

    const formData = createFormData(makeTestFile(), "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(500);

    // Helper must still be cleaned up even on failure
    expect(mockUnlinkSync).toHaveBeenCalledWith("/tmp/git-cred-test-uuid");
  });

  // 18. Credential helper: SYNC_FAILED when token generation fails
  test("returns SYNC_FAILED when installation token generation fails", async () => {
    setupFullMocks();
    mockGenerateInstallationToken.mockRejectedValue(
      new Error("GitHub installation token request failed: 401"),
    );

    const formData = createFormData(makeTestFile(), "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(500);

    const body = await res.json();
    expect(body.code).toBe("SYNC_FAILED");
    // git pull should NOT have been called
    expect(mockExecFile).not.toHaveBeenCalled();
  });

  // 19. Credential helper: cleanup failure does not break upload
  test("returns 201 when credential helper cleanup fails", async () => {
    setupFullMocks();
    mockUnlinkSync.mockImplementation(() => {
      throw new Error("ENOENT: no such file or directory");
    });

    const formData = createFormData(makeTestFile(), "uploads");
    const res = await POST(createRequest(formData, "https://app.soleur.ai"));
    expect(res.status).toBe(201);

    const body = await res.json();
    expect(body.sha).toBe("newsha123");
  });
});
