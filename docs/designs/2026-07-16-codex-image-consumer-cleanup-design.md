# Preserve successful Codex consumer cleanup status

**Status:** Approved.

## Problem

The published-image consumer test tracks fixture containers and volumes after
creation, then discovers them again during its exit trap so partial creation
failures can still be cleaned up. When the final discovered resource is already
present in the tracking array, the deduplication comparison returns status 1.
Because each discovery function currently inherits the loop's final status, a
successful rediscovery is reported as a cleanup failure even though every
resource is subsequently removed without a diagnostic.

This caused post-publication acceptance to print that health and sandboxed patch
persistence were verified, then exit 1 during cleanup.

## Decision

**Decided (owner, 2026-07-16, in session):** successful Docker enumeration and
deduplication return zero explicitly, including when every matching resource was
already known.

Add `return 0` after the container and volume discovery loops. Preserve the
existing nonzero return and ordered diagnostic when the underlying Docker
enumeration command fails. Do not change fixture ownership, matching rules,
removal order, or cleanup diagnostics.

## Verification

Add a focused non-Docker cleanup test using the same test-mode pattern as the
runtime cleanup harness. The test seeds known fixture container and volume IDs,
has a Docker stub return those same IDs during exit-trap rediscovery, and
requires cleanup to remove each resource once and exit zero. It also requires a
pre-existing nonzero test status to remain unchanged after successful cleanup.

The regression test must fail against the current implementation because
duplicate rediscovery leaks status 1, then pass after the explicit successful
returns are added. Existing discovery and removal failure behavior remains
covered by the production diagnostics and the full published-image acceptance
test.

## Rejected alternatives

### Rely on an `if` statement's implicit status

Rewriting the deduplication expression as an `if` block would make the common
duplicate path less surprising, but it would continue to couple the function's
contract to whichever command happens to execute last in the loop.

### Replace tracking arrays with associative sets

Associative sets would make deduplication explicit but would expand a
two-function status fix into unrelated data-structure refactoring and require a
new Bash-version compatibility decision.
