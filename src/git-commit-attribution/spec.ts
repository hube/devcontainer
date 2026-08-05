export const SUPPORTED_SPEC_VERSION = 1;

export type SpecMode = 'warn' | 'enforce';

export interface TrailerRule {
  key: string;
  last: boolean;
}

export interface Spec {
  version: number;
  mode: SpecMode;
  trailers: TrailerRule[]; // in spec order; exactly one rule has last=true
  agentAuthors: string[]; // lowercased addresses
}

export type SpecParseResult =
  | { ok: true; spec: Spec }
  | { ok: false; problem: string }; // names the offending line and its text

function reject(problem: string): { ok: false; problem: string } {
  return { ok: false, problem };
}

/**
 * Parses the v1 trailer-contract spec grammar: one record per non-blank
 * line, whitespace-separated fields. There is no comment syntax — a typo'd
 * record (including a `#` line) must not silently weaken the control, so any
 * unrecognized record type rejects rather than being skipped.
 */
export function parseSpec(text: string): SpecParseResult {
  let version: number | undefined;
  let mode: SpecMode | undefined;
  const trailers: TrailerRule[] = [];
  const seenTrailerKeys = new Set<string>();
  const agentAuthors: string[] = [];

  for (const rawLine of text.split('\n')) {
    const line = rawLine.trim();
    if (line === '') continue;

    const fields = line.split(/\s+/);
    const recordType = fields[0];

    switch (recordType) {
      case 'version': {
        if (version !== undefined) {
          return reject(`duplicate version record: "${line}"`);
        }
        if (fields.length !== 2 || !/^\d+$/.test(fields[1])) {
          return reject(`malformed version line: "${line}"`);
        }
        version = Number(fields[1]);
        if (version !== SUPPORTED_SPEC_VERSION) {
          return reject(
            `spec declares version ${version}, but this validator supports ` +
              `version ${SUPPORTED_SPEC_VERSION} — rebuild the container to ` +
              `update the validator, or pin the spec to the older grammar`,
          );
        }
        break;
      }

      case 'mode': {
        if (mode !== undefined) {
          return reject(`duplicate mode record: "${line}"`);
        }
        if (fields.length !== 2 || (fields[1] !== 'warn' && fields[1] !== 'enforce')) {
          return reject(`malformed mode line: "${line}"`);
        }
        mode = fields[1];
        break;
      }

      case 'trailer': {
        if (fields.length < 3 || fields.length > 4) {
          return reject(`malformed trailer line: "${line}"`);
        }
        const key = fields[1];
        if (fields[2] !== 'required') {
          return reject(`trailer record must specify "required": "${line}"`);
        }
        let last = false;
        if (fields.length === 4) {
          if (fields[3] !== 'last') {
            return reject(`unknown trailer modifier: "${line}"`);
          }
          last = true;
        }
        if (seenTrailerKeys.has(key)) {
          return reject(`duplicate trailer key "${key}": "${line}"`);
        }
        seenTrailerKeys.add(key);
        trailers.push({ key, last });
        break;
      }

      case 'agent-author': {
        if (fields.length !== 2) {
          return reject(`malformed agent-author line: "${line}"`);
        }
        agentAuthors.push(fields[1].toLowerCase());
        break;
      }

      default:
        return reject(`unknown spec record type: "${line}"`);
    }
  }

  if (version === undefined) {
    return reject('spec is missing a version record');
  }
  if (mode === undefined) {
    return reject('spec is missing a mode record');
  }
  if (trailers.length === 0) {
    return reject('spec must declare at least one trailer record');
  }

  const lastFlags = trailers.map((t) => t.last);
  const lastCount = lastFlags.filter(Boolean).length;
  if (lastCount !== 1 || !lastFlags[lastFlags.length - 1]) {
    return reject(
      'exactly one trailer record must be marked "last", and it must be the final trailer record in the spec',
    );
  }

  if (agentAuthors.length === 0) {
    return reject('spec must declare at least one agent-author record');
  }

  return { ok: true, spec: { version, mode, trailers, agentAuthors } };
}
