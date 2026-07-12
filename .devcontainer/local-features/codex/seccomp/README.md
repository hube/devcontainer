# Vendored seccomp profile

`userns.json` is Moby's default seccomp profile with three edits that let
Codex's Bubblewrap-based patch helper create an unprivileged user namespace.
Without them, every Codex edit fails (hube/devcontainer#36).

JSON cannot carry comments, so this file is the record of what was changed and
why.

## Upstream

| | |
|---|---|
| Repository | [`moby/profiles`](https://github.com/moby/profiles) |
| Tag | `seccomp/v0.2.3` |
| File | `seccomp/default.json` |
| SHA-256 (upstream) | `536529b665dd0972c37bfb569f5d4ac8a53592e7b00752bc39ff063ca9864c74` |
| SHA-256 (generated `userns.json`) | `d563d512691ae8f2d437bfa7a9e77ac7d8c8d4a785277f8234bd688f4857ab86` |

The profile used to live in `moby/moby` at `profiles/seccomp/default.json`.
It does not any more — that path is absent from current Moby release tags, and
the profiles are now published from their own independently versioned
repository.

## Edits

The upstream `defaultAction` is `SCMP_ACT_ERRNO`, so a syscall is denied unless
a rule allows it. The three edits start from different upstream states, which is
why they are described separately:

1. **`mount`, `umount2`, `setns`, `unshare` are ungated.** Upstream allows them
   only when the container holds `CAP_SYS_ADMIN`. They are now allowed
   unconditionally. Bubblewrap needs them *inside* the namespace it creates, and
   the `CAP_SYS_ADMIN` it gains there is invisible to seccomp — Docker compiles
   the filter from the container's bounding capabilities at start time — so
   gating on the capability is equivalent to denying them.
2. **`pivot_root` is newly allowed.** It appears nowhere upstream, so it was
   denied by the default action rather than capability-gated. This genuinely
   widens the allowlist beyond what any capability grants today.
3. **The `clone` argument filter is dropped.** Upstream allows `clone` only when
   `(flags & 0x7e020000) == 0`; that mask is exactly the `CLONE_NEW*` namespace
   bits. Removing the filter is what permits `CLONE_NEWUSER`.

`clone3` is deliberately left alone: upstream returns `ENOSYS` for it without
`CAP_SYS_ADMIN`, which makes glibc fall back to `clone`, where the flag filter
above can actually be enforced. Seccomp cannot inspect `clone3`'s flags (they
sit behind a userspace pointer), so ungating it would open a namespace path that
cannot be filtered at all.

Everything else is unchanged. All other syscalls the default profile denies stay
denied — this is a much narrower relaxation than `seccomp=unconfined`.

## Re-vendoring

Do this when upstream publishes a profile release that adds syscalls the
container needs (the symptom is a new syscall returning `EPERM` for no obvious
reason). Never hand-edit `userns.json`; regenerate it so the diff stays
reviewable.

```bash
TAG=seccomp/v0.2.3   # bump to the release you are moving to
curl -fsSL -o /tmp/default.json \
  "https://raw.githubusercontent.com/moby/profiles/${TAG}/seccomp/default.json"
sha256sum /tmp/default.json   # record this in the table above

jq '
  .syscalls |= (
    map(if (.names | index("clone")) and has("args") then del(.args) else . end)
    + [{"names":["mount","umount2","setns","unshare","pivot_root"],"action":"SCMP_ACT_ALLOW"}]
  )
' /tmp/default.json > userns.json
```

Verify the generated SHA-256, record it in the table and test, then review the
diff against the previous `userns.json` and run
`../test/test-seccomp-profile.sh`, which checks both the shape of the file and
that Bubblewrap actually works under it.
