// Pure functions for the #9543 broker-mechanism spike (ADR-311). No sandbox, no I/O: the real-sandbox
// probes in test/broker-mechanism-spike.test.ts pass what they observed to these, and the Guard
// Contract's RED rows run against synthetic observations here.
//
// A hit carries a surface name and a secret ID, never the secret value, so a failing run cannot
// print the decoy it was looking for.

export interface Observation {
  /** Where the text was read inside the sandbox: "env", "proc-environ", "file", "glob-output", "grep-output". */
  surface: string;
  text: string;
}

export interface DeclaredSecret {
  id: string;
  value: string;
}

export interface Hit {
  surface: string;
  secretId: string;
}

export type OutcomeKind = "works" | "does-not-work" | "leaks" | "unmeasurable";

export interface ProbeOutcome {
  probe: string;
  outcome: OutcomeKind;
  /** Required and non-empty: a conclusion with no observed event behind it cannot be constructed. */
  evidence: string[];
}

export class VacuousProbeError extends Error {
  constructor(probe: string) {
    super(`probe "${probe}" observed nothing (0 observed events): a run that saw nothing is vacuous, not a pass`);
    this.name = "VacuousProbeError";
  }
}

/** Every (surface, secret) pair where a declared secret's value appears. Quantifies over ALL secrets. */
export function scanSandboxSurfaces(observations: readonly Observation[], declared: readonly DeclaredSecret[]): Hit[] {
  const hits: Hit[] = [];
  for (const o of observations) {
    for (const s of declared) {
      if (s.value.length > 0 && o.text.includes(s.value)) {
        hits.push({ surface: o.surface, secretId: s.id });
      }
    }
  }
  return hits;
}

function requireEvidence(probe: string, evidence: readonly string[] | undefined): string[] {
  if (!evidence || evidence.length === 0 || evidence.every((e) => e.trim() === "")) {
    throw new Error(`probe "${probe}": a conclusion requires evidence (observed events), none given`);
  }
  return [...evidence];
}

export function unmeasurable(probe: string, reason: string, evidence: readonly string[]): ProbeOutcome {
  const ev = requireEvidence(probe, evidence);
  return { probe, outcome: "unmeasurable", evidence: [`reason: ${reason}`, ...ev] };
}

export interface ClassifyInput {
  probe: string;
  /** Concrete events the probe saw (a Bash call completed, the echo target logged a request, ...). */
  observedEvents: readonly string[];
  scan: readonly Hit[];
  /** Did the far end receive the substituted real value? */
  substitutionObserved: boolean;
  /** Optional extra evidence lines; when passed, it must be non-empty after merging with the derived lines. */
  evidence?: readonly string[];
}

export function classifyOutcome(input: ClassifyInput): ProbeOutcome {
  const { probe, observedEvents, scan, substitutionObserved } = input;
  if (observedEvents.length === 0) throw new VacuousProbeError(probe);
  if (input.evidence !== undefined && input.evidence.length === 0) requireEvidence(probe, input.evidence);

  const evidence: string[] = [...(input.evidence ?? []), ...observedEvents.map((e) => `observed: ${e}`)];
  if (scan.length > 0) {
    for (const h of scan) evidence.push(`secret ${h.secretId} visible on surface ${h.surface}`);
    return { probe, outcome: "leaks", evidence: requireEvidence(probe, evidence) };
  }
  return {
    probe,
    outcome: substitutionObserved ? "works" : "does-not-work",
    evidence: requireEvidence(probe, evidence),
  };
}
