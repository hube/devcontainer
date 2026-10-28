# Accept skills startup changes

The Feature owns clone/ref-refresh and the independent installer calls. The
agent-skills repository owns installation. Verify these boundaries separately:
caller tests with a named subprocess stub establish argument and failure wiring;
real installation in disposable consumers establishes installed state. Neither
proves that a running harness session has reloaded its skills.

## Check the caller

Run the repository checks from `package.json` and `.github/workflows/tests.yml`.
The focused caller suite is:

```bash
npx vitest run tests-vitest/agent-skills.test.ts
```

It stubs `spawnSync`, not the maintained installer or harness runtime, and checks
explicit targets, each target's failure, both failing, captured output and
non-blocking completion. Build the committed helper with `npm run build` and
compare the generated agent-skills bundle as well as the existing bundles.

## Verify installation in disposable consumers

Use a disposable container user home and a writable copy of the maintained
agent-skills repository. Record its full commit SHA, Node and both harness
versions. Keep real configuration, authentication and history outside the
consumer. Verify scratch-directory creation succeeded before deriving child
paths; retain evidence rather than recursively cleaning paths derived from
unchecked variables.

Use the normal installed hook and its options file, with the disposable clone
as `cloneDir`. Establish working SSH prerequisites for a fresh clone; an existing
clone must refresh its refs without moving HEAD. Run a fresh startup, then repeat
startup against that installed state. Also seed a consumer with the maintained
installer's existing installations before invoking the hook, and repeat it.

For each path, read the Claude link, Codex marketplace root and plugin installed
state using the [operator readbacks](NOTES.md#activate-and-check-skills). Compare
unrelated synthetic Claude settings and Codex configuration, authentication and
history bytes before/after. Prove the comparator rejects an altered baseline.
Keep CLI stubs out of this installed-state acceptance; name missing CLI/runtime
support as an acceptance gap rather than substituting caller test success.

In a separate disposable consumer, place a user-owned file at
`~/.claude/skills/hube-agent` before startup. Confirm the hook relays the installer
conflict, the file bytes stay unchanged, and Codex is still attempted. Exercise
a Codex marketplace conflict in another consumer and confirm Claude still
installs while the conflicting registration is preserved. Capture each failing
command's output and exit status alongside installed-state readback.

Reconcile NOTES.md with the behavior exercised. Obtain the required reader-proxy
review through the designated reviewer. Report unrun members explicitly; a
successful hook status alone establishes only non-blocking startup.
