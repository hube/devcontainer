import { runCommitMsg, runRange } from './validate';

/**
 * Compiled into the bundle so the `commit-msg` hook (install.sh writes no
 * config of its own) always has a spec to read; install.sh guarantees the
 * interpreter symlink, and the consumer's devcontainer.json declares the
 * spec mount. CI overrides it with `--spec`.
 */
export const DEFAULT_SPEC_PATH = '/etc/devcontainer/feature/git-commit-attribution/trailer-contract';

const USAGE = [
  'Usage:',
  '  validate commit-msg <msgfile> [--spec <path>]',
  '  validate --range <BASE..HEAD> [--spec <path>]',
].join('\n');

function fail(problems: string[]): number {
  for (const problem of problems) {
    process.stderr.write(`git-commit-attribution: ${problem}.\n`);
  }
  process.stderr.write(`${USAGE}\n`);
  return 1;
}

/**
 * Parses `--spec <path>` out of the remaining args, leaving whatever
 * positional argument the caller's mode expects (a msgfile or a range).
 * Collects problems rather than throwing so argv validation reports every
 * defect together, per the validating-input convention.
 */
function extractSpec(rest: string[], problems: string[]): { specPath: string | undefined; positional: string[] } {
  let specPath: string | undefined;
  const positional: string[] = [];

  for (let i = 0; i < rest.length; i++) {
    if (rest[i] === '--spec') {
      if (i + 1 >= rest.length) {
        problems.push("'--spec' requires a value");
        break;
      }
      specPath = rest[i + 1];
      i++;
    } else {
      positional.push(rest[i]);
    }
  }

  return { specPath, positional };
}

export function main(argv: string[]): number {
  if (argv.length === 0) {
    return fail(['no command given; expected commit-msg <msgfile> or --range <BASE..HEAD>']);
  }

  const [command, ...rest] = argv;

  if (command !== 'commit-msg' && command !== '--range') {
    return fail([`unrecognized argument '${command}'`]);
  }

  const problems: string[] = [];
  const { specPath, positional } = extractSpec(rest, problems);

  const positionalName = command === 'commit-msg' ? '<msgfile>' : '<BASE..HEAD>';
  if (positional.length === 0) {
    problems.push(`${command} requires ${positionalName}`);
  } else if (positional.length > 1) {
    problems.push(`unexpected extra argument(s): ${positional.slice(1).join(' ')}`);
  }

  if (problems.length > 0) {
    return fail(problems);
  }

  const resolvedSpec = specPath ?? DEFAULT_SPEC_PATH;
  const outcome = command === 'commit-msg' ? runCommitMsg(positional[0], resolvedSpec) : runRange(positional[0], resolvedSpec);

  for (const line of outcome.stderr) {
    process.stderr.write(`${line}\n`);
  }
  return outcome.exitCode;
}

if (require.main === module) {
  process.exitCode = main(process.argv.slice(2));
}
