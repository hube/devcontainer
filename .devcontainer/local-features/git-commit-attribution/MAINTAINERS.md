# Accept attribution-validator changes

The TypeScript validator is bundled into `dist/validate`, which the Feature
installs at image build. Local checks verify the source and committed bundle;
supported-session acceptance separately verifies the affected invocation and its
approved continuation. The timeout bounds trailer parsing, not every git command
used by range validation.

## Check the source and bundle

From an isolated repository worktree with the package's supported Node version:

```sh
npm ci
npm run typecheck
npm run lint
npm test
npm run build
git diff --exit-code -- .devcontainer/local-features/git-commit-attribution/dist/
```

Run the bundle comparison after committing the rebuilt bundle. Before committing,
compare another build byte-for-byte with the candidate bundle. CI also compares
the repository's other committed bundles.

The parser-failure tests substitute an executable on `PATH` for the parser only:
normal parsing uses real git. A controlled hanging parser exercises our deadline,
forced termination, output relay and diagnostics, under an independent outer
watchdog. Run the same assertion with the deadline removed in a disposable source
copy and retain the failing result. These fixtures verify our wiring and establish
no Codex or kernel-policy behavior. Do not run the attribution post-start shell
suite against a live workspace; its setup can damage unrelated repository state.

## Verify supported execution and publication

Use the candidate `dist/validate`, a readable trailer contract and an attributed
message file. Record their paths and hashes. Bound the whole invocation with an
outer watchdog, retain stdout, stderr, status and any execution-tool error, and
run:

```sh
node .devcontainer/local-features/git-commit-attribution/dist/validate \
  commit-msg /absolute/path/to/message --spec /absolute/path/to/trailer-contract
```

Run that exact invocation first under the supported session's default policy,
then through its supported approval path if recovery is required. Preserve the
actual approval decision and result together. A controlled hanging executable
cannot stand in for this runtime acceptance. An outer watchdog firing means the
validator did not establish bounded completion in that run.

In a disposable repository's own linked worktree, install a task-local commit-msg
hook pointing at the candidate bundle and fixture contract. With the hanging
parser selected only for that hook, verify the attempted commit fails and HEAD
is unchanged. Restore real git for the hook and verify a complete attributed
message permits a signed commit. Never change another repository's hooks or
signing configuration for this acceptance.

Publish the signed, attributed delivery commit and its review artifact only to
the authorized destination. Verify the commit signature, remote head and exact
published body through readback; use the maintained control catalogue referenced
by [verification-controls.md](https://github.com/hube/claude-home/blob/main/instructions/verification-controls.md).
Keep fixture evidence, actual sandbox results and publication results separate.
Unavailable acceptance remains outstanding in the delivery record.
