# cliamp ios

The iOS client is not implemented yet. The [iOS parity plan and progress
tracker](../docs/ios-parity.md) defines the Android baseline, phased work,
acceptance criteria, and remaining platform decisions. Start there when
implementing or reviewing the port, and update its task IDs as work lands.

Two things worth reading before anything lands here:
[`../docs/design.md`](../docs/design.md), which is the design system the Android
client already implements and the thing that keeps the clients recognisably one
app, and [`../android/README.md`](../android/README.md) for the decisions that
turned out to matter — the declarative provider spec, resolving stream URLs at
play time rather than storing them, and keeping credentials out of plain files.

## Foundation decisions (FND-01)

| Topic | Decision |
| --- | --- |
| Minimum OS | iOS 18.0 |
| Devices | Universal iPhone + iPad, portrait and landscape |
| Stack | SwiftUI, Swift 6 language mode, Swift Testing |
| Project | XcodeGen; `project.yml` is the source of truth and `Cliamp.xcodeproj` is generated and ignored |
| Architecture | App target plus local Swift packages under `ios/`; `CliampCore` first |
| Signing | CI builds and tests unsigned for the simulator; device builds use automatic signing with the owner's team and no certificate material in the repo |

The OS floor is set by `DEC-03`'s system surfaces: interactive widgets need iOS
17 and Control Center controls need iOS 18, so an iOS 18 floor avoids fallback
branches for the whole port. A physical iPhone is required from phase 2; its
model is named by the owner before `RAD-11` sign-off.

## Device matrix

| Role | Device |
| --- | --- |
| CI build + hosted unit tests | iPhone 17 simulator, latest iOS runtime |
| Visual review, phone | iPhone 17e (small) and iPhone 17 Pro Max (large) |
| Visual review, tablet | iPad mini (A17 Pro) and iPad Pro 11-inch (M5) |
| Physical device | Required from phase 2; model named by the owner before `RAD-11` |

Reference captures are `FND-02`; the visual review runs in `QA-02`. Portrait and
landscape are both in scope for every role.

## Requirements

- macOS 26.x with Xcode 26.6 (the pinned toolchain; CI uses the same)
- XcodeGen 2.45.4 (`brew install xcodegen`)

## Commands

```sh
brew install xcodegen
xcodegen generate
open Cliamp.xcodeproj

# Package logic (no simulator needed)
swift test --package-path CliampCore

# App build and hosted unit tests, unsigned
xcodebuild build -project Cliamp.xcodeproj -scheme Cliamp \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
xcodebuild test -project Cliamp.xcodeproj -scheme Cliamp \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

The app icon is generated, not hand-drawn: `swift tools/make_appicon.swift
Cliamp/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` rebuilds it
from the same geometry as Android's adaptive icon (oxide bevel ground, the
six-bar mark in cream). The launch screen uses the flat `LaunchBackground`
colour from the same catalog.

`project.yml` is the only project source; regenerate after changing targets,
settings, or `Info.plist` keys instead of editing the generated project.

## Layout

| Path | Role |
| --- | --- |
| `project.yml` | XcodeGen manifest: targets, settings, package wiring |
| `Cliamp/` | App target: `Sources/`, `Tests/`, generated `Info.plist` |
| `CliampCore/` | Local Swift package for shared product logic |
