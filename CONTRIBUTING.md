# Contributing

Bug reports and pull requests are welcome. For anything bigger than a fix, open an issue first so we can agree on the approach before you invest time.

## Setup

```sh
brew install xcodegen swiftlint swiftformat
make run
```

`make test` and `make lint` must pass — CI enforces both on every pull request. The Xcode project is generated from `project.yml` by XcodeGen and is not committed; edit `project.yml`, never the `.xcodeproj`.

## Ground rules

The real-time audio callback (`ProcessTap.render`) runs on the HAL IO thread: no allocation, no locks, no Objective-C calls, no logging inside it. Changes there get extra scrutiny.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org) (`feat:`, `fix:`, `docs:`, …), imperative mood, English.

Fader sends nothing over the network and collects nothing — contributions adding telemetry, analytics, or auto-update phoning home will be declined.
