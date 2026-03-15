# ContainerUtility

ContainerUtility is a native macOS SwiftUI app for working with the `container` CLI through a focused desktop UI. It is designed as a lightweight utility that can live in the menu bar while giving you a full workspace for containers, images, networks, volumes, registry sessions, runtime health, recent operations, and diagnostics.

## Features

- Native macOS app built with SwiftUI
- Menu bar extra for quick status and fast access back to the main window
- Onboarding flow for first launch and login-item setup
- Runtime health dashboard with compatibility and preflight checks
- Container management with inspect, logs, stats, and exec workflows
- Image workflows for pull, tag, push, import, export, and cleanup
- Network and volume management with relationship-aware usage details
- Registry login and logout workflows
- Activity center for queued, running, failed, and completed operations
- Diagnostics export for redacted troubleshooting bundles and summaries

## Requirements

- macOS with an Xcode toolchain that supports the project deployment target
- Xcode for building and running the app
- The `container` CLI installed and available on `PATH`

The current compatibility policy in code expects a `container` CLI version in the range `>= 0.9.0` and `< 1.0.0`.

## Getting Started

1. Clone the repository.
2. Make sure the `container` CLI is installed and reachable from your shell.
3. Open `ContainerUtility/ContainerUtility.xcodeproj` in Xcode.
4. Select the `ContainerUtility` target and run the app.

The app is configured as a menu bar utility, so it may launch without a normal Dock presence depending on your current settings and onboarding state.

## Project Structure

```text
ContainerUtility/
├── README.md
├── ContainerUtility/
│   ├── ContainerUtility.xcodeproj
│   └── ContainerUtility/
│       ├── App/             # app entrypoint, scenes, settings, onboarding, shared model
│       ├── Domain/          # UI-facing domain and diagnostics models
│       ├── Features/        # containers, images, networks, volumes, activity, diagnostics, home
│       ├── Infrastructure/  # command runner, CLI adapter, refresh controller, diagnostics export
│       └── Shared/          # reusable UI building blocks
```

## License

See [License](./LICENSE.md).
