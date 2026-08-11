# SleepSwitch

A tiny macOS menu-bar app that shows whether your Mac is allowed to sleep
(`pmset disablesleep`) and lets you flip it from the tray — no terminal, no
password after one-time setup.

- ☀️ **Sun** — sleep disabled (`disablesleep 1`): the Mac stays awake.
- 🌙 **Moon** — sleep allowed (`disablesleep 0`): normal sleep behavior.

Click the icon and pick **Never sleep** or **Allow sleep**. The state is
re-read every few seconds, so changes made in Terminal show up too.

## Build & run

Requires macOS with the Swift toolchain (Xcode or Command Line Tools).

```bash
./build.sh
open SleepSwitch.app
```

## Passwordless toggling

Changing `disablesleep` requires root. The first time you switch, macOS asks
for your admin password **once** — that same authorization also installs a
tightly-scoped sudoers rule so every switch after that is instant and silent.

The rule (installed at `/etc/sudoers.d/sleepswitch`) permits **only** these
two exact commands for your user, nothing else:

```
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -a disablesleep 1
```

It is validated with `visudo -cf` before install, so it can never corrupt
your sudo configuration.

Prefer the terminal? `sudo ./enable-nopass.sh` installs the same rule;
`sudo ./disable-nopass.sh` removes it and the app goes back to prompting.

## Project layout

| Path | Purpose |
|------|---------|
| `Sources/main.swift` | The entire app — tray icon, menu, pmset read/write. |
| `build.sh` | Compiles and bundles `SleepSwitch.app`. |
| `Info.plist` | Bundle metadata (`LSUIElement` = menu-bar agent). |
| `enable-nopass.sh` / `disable-nopass.sh` | Optional terminal setup/teardown for the passwordless rule. |

## License

MIT
