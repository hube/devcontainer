# Accept attribution-validator changes

The TypeScript validator is bundled into `dist/validate`, which the Feature
installs at image build. Source/bundle checks and actual sandbox continuation
produce separate acceptance evidence. The implementation PR is their delivery
record.

The parser deadline applies to `git interpret-trailers --parse`. The separate
`validate --range BASE..HEAD` command checks existing commits and also runs
other git commands; those commands are outside this parser deadline.

## Check the source and bundle

Run these commands from this repository's root, the directory containing
`package.json`, in your own linked worktree. Node 24 or newer and npm must
already be installed and selected; `node --version` reads the selected version.

```sh
node --version
npm ci
npm run typecheck
npm run lint
npm test
npm run build
```

Before committing, preserve the candidate bundle, rebuild and compare it:

```sh
gca_candidate=$(mktemp)
cp .devcontainer/local-features/git-commit-attribution/dist/validate "$gca_candidate"
npm run build
cmp "$gca_candidate" .devcontainer/local-features/git-commit-attribution/dist/validate
```

After committing the rebuilt bundle, run the committed-bundle gate:

```sh
git diff --exit-code -- .devcontainer/local-features/git-commit-attribution/dist/
```

The focused parser suite substitutes an executable on `PATH` only for parser
failures; normal parsing uses real git. It checks both enforcement modes and
hook/range contexts, including captured output and a separate outer watchdog:

```sh
npm test -- tests-vitest/git-commit-attribution/parser-failure.test.ts
```

For live-workspace verification, use the parser suite above; do not run the
attribution post-start shell suite, whose setup can damage unrelated repository
state.

## Verify Codex continuation

Here, supported-session acceptance means a Codex desktop remote session or its
delegated agent being verified for delivery. Its effective runtime policy must
expose the supported approved execution path. Read the actual policy and use
[canonical recovery](https://github.com/hube/claude-home/blob/main/instructions/setup-recovery.md)
for the execution tool's approval interface.

In the same repository root, create an attributed message file using the block
in [NOTES.md](NOTES.md#recover-from-trailer-parser-failure), replacing its
placeholders with the actual authoring values. Set `gca_message` to that file's
absolute path. The consuming container supplies the mounted contract below.
GNU `timeout` must be available for the independent outer watchdog.

```sh
gca_contract=/etc/devcontainer/feature/git-commit-attribution/trailer-contract
test -r "$gca_message"
test -r "$gca_contract"
sha256sum .devcontainer/local-features/git-commit-attribution/dist/validate \
  "$gca_message" "$gca_contract"
(
gca_status=0
timeout --signal=KILL 8s node \
  .devcontainer/local-features/git-commit-attribution/dist/validate \
  commit-msg "$gca_message" --spec "$gca_contract" || gca_status=$?
printf 'validator command status: %s\n' "$gca_status"
exit "$gca_status"
)
```

Run that exact invocation under default policy, then through supported approval
when recovery is required. Retain the invocation, working directory, input
hashes, stdout/stderr, status, attached execution errors and exposed approval
result together. A validator timeout returns 1 with its own timeout diagnosis.
An outer watchdog termination, including status 124 or 137, does not establish
bounded validator completion. Successful validation returns 0.

## Record delivery acceptance

On the implementation PR, record command results and distinguish controlled
parser fixtures from actual sandbox/approved-continuation results. For signed
attributed delivery publication, use the existing
[signing/publication procedure](https://github.com/hube/claude-home/blob/main/instructions/committing.md)
and maintained publication controls reached through
[verification-controls.md](https://github.com/hube/claude-home/blob/main/instructions/verification-controls.md).
Record an unavailable acceptance member as outstanding on that same PR.
