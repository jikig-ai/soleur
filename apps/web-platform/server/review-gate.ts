/**
 * Abort-aware review gate promise with timeout safety net.
 *
 * Extracted from agent-runner.ts for unit testability without SDK/Supabase
 * dependencies. Follows the same extraction pattern as tool-path-checker.ts.
 */

export interface ReviewGateEntry {
  resolve: (selection: string) => void;
  options: string[];
}

export interface AgentSession {
  abort: AbortController;
  reviewGateResolvers: Map<string, ReviewGateEntry>;
  sessionId: string | null;
}

export const REVIEW_GATE_TIMEOUT_MS = 5 * 60 * 1_000; // 5 minutes
export const MAX_SELECTION_LENGTH = 256;

// SDK AskUserQuestion schema types (from @anthropic-ai/claude-agent-sdk)
interface SdkQuestionOption {
  label: string;
  description?: string;
  preview?: string;
}

interface SdkQuestion {
  question: string;
  header: string;
  options: SdkQuestionOption[];
  multiSelect: boolean;
}

export interface ReviewGateInput {
  question: string;
  header: string;
  options: string[];
  descriptions: Record<string, string | undefined>;
  isNewSchema: boolean;
}

/**
 * Extract review gate fields from the SDK's AskUserQuestion tool input.
 * Handles both the new SDK schema (questions[] array) and legacy format
 * (flat question/options fields).
 */
export function extractReviewGateInput(
  toolInput: Record<string, unknown>,
): ReviewGateInput {
  const questions = Array.isArray(toolInput.questions)
    ? (toolInput.questions as SdkQuestion[])
    : undefined;

  const firstQ = questions && questions.length > 0 ? questions[0] : undefined;

  if (firstQ) {
    const options = firstQ.options.map((o) => o.label);
    const descriptions = Object.fromEntries(
      firstQ.options.map((o) => [o.label, o.description]),
    );
    return {
      question: firstQ.question,
      header: firstQ.header || "Input needed",
      options: options.length > 0 ? options : ["Approve", "Reject"],
      descriptions,
      isNewSchema: true,
    };
  }

  // Legacy fallback
  const question =
    (toolInput.question as string) || "Agent needs your input";
  const rawOptions = Array.isArray(toolInput.options)
    ? (toolInput.options as unknown[]).filter(
        (o): o is string => typeof o === "string",
      )
    : [];

  return {
    question,
    header: "Input needed",
    options: rawOptions.length > 0 ? rawOptions : ["Approve", "Reject"],
    descriptions: {},
    isNewSchema: false,
  };
}

/**
 * Build the updatedInput response for the SDK after the user makes a selection.
 * New schema returns { questions, answers: { [question]: selection } }.
 * Legacy schema returns { ...toolInput, answer: selection }.
 */
export function buildReviewGateResponse(
  toolInput: Record<string, unknown>,
  selection: string,
  isNewSchema: boolean,
): Record<string, unknown> {
  if (isNewSchema) {
    const questions = toolInput.questions as SdkQuestion[];
    const questionText = questions[0].question;
    return {
      questions,
      answers: { [questionText]: selection },
    };
  }
  return { ...toolInput, answer: selection };
}

/**
 * Validate that a review gate selection is one of the offered options
 * and within the length limit. Throws on invalid input.
 */
export function validateSelection(
  options: string[],
  selection: string,
): void {
  if (selection.length > MAX_SELECTION_LENGTH) {
    throw new Error("Invalid review gate selection");
  }
  if (!options.includes(selection)) {
    throw new Error("Invalid review gate selection");
  }
}

/**
 * Create a promise that resolves when the user responds to a review gate,
 * or rejects when the session is aborted (disconnect) or the timeout elapses.
 */
export function abortableReviewGate(
  session: AgentSession,
  gateId: string,
  signal: AbortSignal,
  timeoutMs: number = REVIEW_GATE_TIMEOUT_MS,
  options: string[] = ["Approve", "Reject"],
): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    if (signal.aborted) {
      reject(signal.reason || new Error("Session aborted"));
      return;
    }

    const timer = setTimeout(() => {
      signal.removeEventListener("abort", onAbort);
      session.reviewGateResolvers.delete(gateId);
      reject(new Error("Review gate timed out"));
    }, timeoutMs);
    timer.unref();

    const onAbort = () => {
      clearTimeout(timer);
      session.reviewGateResolvers.delete(gateId);
      reject(signal.reason || new Error("Session aborted"));
    };

    signal.addEventListener("abort", onAbort, { once: true });

    session.reviewGateResolvers.set(gateId, {
      resolve: (selection: string) => {
        clearTimeout(timer);
        signal.removeEventListener("abort", onAbort);
        resolve(selection);
      },
      options,
    });
  });
}
