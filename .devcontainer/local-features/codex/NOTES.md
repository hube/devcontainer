## Codex Remote Control

Codex remote control requires the container to be reachable via SSH. This local
feature depends on the [sshd feature][1] to launch an ssh server that listens on
port 2222. The consuming devcontainer must then publish that port in order to
reach the container's ssh server, e.g. by adding the following to the
`devcontainer.json` file:

```
{
  ...
  "appPort": ["127.0.0.1:2222:2222"]
}
```

See the [devcontainer documentation][2] for details

[1]: https://github.com/devcontainers/features/tree/main/src/sshd
[2]: https://containers.dev/implementors/json_reference/#image-specific
