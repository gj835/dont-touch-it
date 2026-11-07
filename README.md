# Don't Touch It

A macOS menu bar app that stops accidental touches on a touch screen.

When Touch Guard is on, a finger touching the screen shows a full-screen warning (a red "Don't Touch It!" by default, or an image you choose) instead of reaching the app underneath. Mouse and trackpad input keeps working as usual.

## Supported devices

- A MacBook Pro with a touch screen.
- An iPad connected to a Mac with Sidecar.

Requires macOS 27.

## Status: in development

This app is still being developed, and it needs data from real touch-screen hardware to get better.

While Touch Guard runs, the app records a few usage counts in a log file on your own Mac, for example how many touches the hardware reported, how many the app caught, and how soon touches followed mouse or trackpad use. The log does not contain where you touched or clicked, what you typed, or any window, app, or file names. It also records your Mac model and macOS version. The app never uploads anything.

This is on by default. A notice on first launch says so, and **Record Usage Diagnostics** in the menu bar menu turns it off.

**Please share your log on GitHub.** Open an issue in this repository and paste the `usage env:` and `usage summary:` lines, or attach the log file. Read it first if you like; it is plain text.

- Show the log: **Reveal Touch Guard Log…** in the menu bar menu.
- Location: `~/Library/Logs/Don't Touch It/TouchGuard.log`
- Delete it: **Clear Touch Guard Log…** in the menu bar menu.

## Permissions

Touch Guard needs two permissions. macOS asks for them, or you can add the app yourself in System Settings > Privacy & Security.

| Permission | Why |
| --- | --- |
| Input Monitoring | To notice mouse, trackpad, and scroll input so it can pass through to the app underneath, and to count touches reported by the touch hardware. |
| Accessibility | To replay the first mouse or scroll event so the app underneath receives it. |

After allowing them, quit and reopen the app. The app does not need Screen Recording, Camera, Microphone, Full Disk Access, or network access.

## Build

```sh
./Scripts/build-app.sh
open "dist/Don't Touch It.app"
```

Requires the Swift toolchain.

## License

MIT. See [LICENSE](LICENSE).
