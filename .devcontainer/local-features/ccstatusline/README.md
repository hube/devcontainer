# About

Installs [ccstatusline][1] for a highly-customizable Claude Code status line

# Limitations

The ccstatusline `~/.config/ccstatusline/settings.json` file doesn't seem to
work well with the Docker bind mount, possibly due to how ccstatusline writes to
the settings file

- The devcontainer may be unable to write to the ccstatusline `settings.json`
  file
  - You may see an error like `Error: EACCES: permission denied`
  - Make changes to the ccstatusline settings from the host machine instead
- Changes to the `settings.json` file may require restarting the container to
  take effect
  - When editing the settings using `ccstatusline`, the changes show up
    immediately on a running instance of Claude Code on the host. However, a
    devcontainer instance of Claude Code never sees the change (the
    `settings.json` on the container filesystem remains unchanged)

[1]: https://github.com/sirmalloc/ccstatusline
