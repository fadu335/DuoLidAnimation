# Development

The project uses Swift 6, AppKit, ScreenCaptureKit, IOKit HID, MetalKit and Metal Performance Shaders. Deployment target: macOS 14.

## Checks

```sh
./Utilities/build.sh
./build/DuoLidAnimation.app/Contents/MacOS/DuoLidAnimation --sensor 100
./build/DuoLidAnimation.app/Contents/MacOS/DuoLidAnimation --self-test
./build/DuoLidAnimation.app/Contents/MacOS/DuoLidAnimation --capture-test --wake-test
```

Run capture tests with no other copy of the app running. They need Screen Recording permission. The tests read a physical lid sensor; they cannot run fully on a generic CI machine.

`--self-test` compiles the Metal library, checks easing and offscreen geometry, and renders a synthetic fixture into `build/ReferenceFrames`. This fixture is never used by desktop capture. `--wake-test` invokes sleep/wake handlers and checks that the window, renderer, stream and animation state survive duplicate notifications. It does not put the machine to sleep.

The initial local environment had only Command Line Tools. Swift builds and GPU/runtime tests passed; the generated Xcode project was syntax-checked, but a successful local `xcodebuild` run was not possible without full Xcode.

## Project files

`Utilities/generate-project.py` regenerates the dependency-free native Xcode project. Add new source files to its source list when they live outside the main source directories. The Metal source is copied as a resource and compiled at runtime in both build paths.

`Utilities/toolchain` contains a workaround for CLT installations with duplicate SwiftBridging module maps. Its generated VFS overlay stays local. A regular Xcode installation uses its selected SDK without this workaround.

## Release checks

Keep application logs, registry dumps, captured content, user settings, module caches and old binaries out of Git. Package the `.app` with `ditto`, verify its signature with `codesign --verify --deep --strict`, then test the ZIP with `unzip -t`.

Distributed builds are arm64 and ad-hoc signed. They are not notarized. A stable Developer ID signature is needed for normal distribution without local-signing friction.
