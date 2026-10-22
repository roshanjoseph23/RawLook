# RawLook

RawLook is an offline, non-destructive SwiftUI photo editor for iPhone, iPad and Mac. It develops supported camera RAW (including Fujifilm RAF), JPEG, HEIC, PNG and TIFF, applies JSON reference looks, and exports new JPEG, HEIC or 16-bit TIFF files. The supplied look is an **estimate**, not recovered original photographer settings.

Requires Xcode 16+ and an Apple SDK to build; deployment targets are iOS 17.0 and macOS 14.0. One multiplatform app target shares all source files. Swift language mode is 5 with complete strict concurrency checking. There are no third-party dependencies or network calls.

## Build

On a Mac, install Xcode and XcodeGen 2.42+:

```sh
brew install xcodegen
xcodegen generate
open RawLook.xcodeproj
```

The generated `RawLook.xcodeproj` is committed. Regenerate with `xcodegen generate` after adding presets or source files, or changing `project.yml`, and keep the generated project. Select the RawLook scheme and a Mac or iOS destination, set your signing team, then build. Run RawLookTests using Product → Test. The empty AppIcon set is a placeholder; supply artwork before distribution. macOS uses only sandbox and user-selected read/write entitlements.

The app and Metal shader cannot be compiled on Linux. Linux verification covers the Foundation-only executable model, color mathematics and geometry, not Apple framework integration. XcodeGen is available in this Linux workspace at `/workspace/XcodeGen/.build/release/xcodegen`; project generation is verified here.

## Linux core verification

```sh
export PATH=/workspace/swift-6.1.2-RELEASE-debian12/usr/bin:$PATH
cd LinuxCheck
swift build
swift test
```

LinuxCheck is an independent, dependency-free verification package, excluded from the Xcode project. Its source and test symlinks share the actual app core and XCTest files. No Package.resolved is needed. Linux tests find the original preset relative to the resolved test source path; app-hosted tests read it from the app bundle.

## Add a preset

Drop a schema-v1 JSON into `Presets/`, regenerate the project, then build. No code changes are needed. The folder reference bundles the complete directory recursively, including `Presets/source/warm-garden-portraits.json`, which is unchanged. The loader enumerates top-level JSON URLs and recursively enumerates bundle resources, so flattened resources and nested folder references work. Duplicate profile IDs and invalid presets appear as warnings in the inspector. Unsupported enabled extra effects are reported and skipped. GPU capacity is 16 anchors and 16 knots per curve; larger definitions are rejected with a visible error.

## Pipeline

1. Apple's CIRAWFilter provides camera-specific demosaicing, default baseline rendering, file as-shot white balance and per-photo exposure. RAW imports create one owned data-backed `CIRAWFilter`, retained on the renderer actor so security-scoped access can end safely. Each render restores the saved as-shot temperature/tint before applying the edit snapshot. RAW neutral picking sets the decoder’s neutral location once at full scale, reads back temperature/tint and saves manual white balance for subsequent previews, exports and undo; non-RAW imports never attempt RAW decoding. Photos imports use transferable data with original encoding preferred. Unsupported camera RAW produces an actionable error. Non-RAW exposure uses CIExposureAdjust in extended linear sRGB. Non-RAW temperature/tint uses CITemperatureAndTint; neutral picking averages a 5×5 linear patch and applies channel gains.
2. The creative handoff explicitly encodes linear sRGB using its exact transfer function, then clamps. The Metal CIKernel mirrors the Float CPU reference: standard HSL, original-HSL circular sector interpolation and smooth neutral protection, piecewise-linear master and channel curves, global HSL saturation, then linear-light strength mixing. All knots and anchors are packed into a nearest-sampled 16×5 RGBAf data image with nil color space, with no LUT approximation. Only counts, flags and options are float uniforms; the ROI callback supplies the full table extent. The kernel is loaded from default.metallib; project-wide Core Image Metal compile/link flags apply on both platforms. Fast math is disabled. Small CPU/GPU floating-point rounding differences remain possible.
3. User adjustments follow the look. Curves in the curve editor **replace** preset curve data inside steps 2–3 of the look, so they participate in strength blending; there is no second application of the preset curves. Disabled or omitted JSON stages stay skipped. Reset restores the selected preset's original knots.
4. Brilliance combines a shadow lift (0.25×), highlight recovery (0.2×) and large-radius local contrast (0.1×). Clarity uses CIUnsharpMask with radius 1.5% of the long edge and intensity 0.35×. Other controls use Core Image built-ins; neutral settings skip their filters exactly.
5. Straightening keeps the largest centered **original-aspect** rectangle inside the rotated source, then applies quarter turns/flips and normalized crop geometry. Aspect options fit inside that safe image, and constrained crop resizing preserves the selected ratio. This deliberately preserves the image aspect during straightening rather than finding a differently proportioned maximum-area rectangle.
6. Previews use 1800-pixel proxies (800 while dragging). The renderer actor owns its CIContext, decoder and kernel. Canceled preview tasks and generation checks suppress stale images. Full-resolution export runs in the actor, with an indeterminate progress indicator. JPEG is 8-bit, TIFF RGBA16, and HEIC tries 10-bit on iOS 18/macOS 15+, falling back to 8-bit on older OS versions or unsupported devices. CIContext embeds the selected sRGB or Display P3 profile. Export uses a new file document or add-only Photos request and never mutates an imported source.

## Editing

Open from Files on every platform or Photos on iOS. Large windows have a persistent inspector; narrow windows expose the same tools in a bottom sheet. Before toggles the RAW-stage-only image using the same geometry; press and hold the preview to compare temporarily. Undo/Redo use EditState snapshots; slider and point drags form a single transaction. Command-Z and Shift-Command-Z use the focused editor on Mac. Curve points can be added by tapping, dragged, removed by dragging outside or with labeled remove buttons; VoiceOver can adjust point outputs. Crop exposes corner/edge handles and an aspect picker. Aspect and portrait selections are part of the undo snapshot and survive sheet dismissal. The curve canvas includes a faint 256-bin luminance histogram of the current preview proxy. For neutral picking, the preview temporarily shows the uncropped, unrotated RAW-stage image so locations map directly to decoder coordinates.

## Limits and verification

RAW support depends on Apple's camera support for the OS, including the camera's Bayer or X-Trans sensor. RAW appearance follows Apple's baseline and can vary by OS/camera. The preset has not been fitted to paired neutral RAW and target images. No subject masks, split comparison, HDR output or edit sidecar persistence are included. Large files are held as owned data; full-resolution rendering can use substantial memory. A running Core Image render cannot be interrupted mid-GPU command; cancellation prevents obsolete results from reaching the UI. Export preserves pixels/profile, not source EXIF/GPS metadata.

Linux build and core tests pass. Apple SDK compilation, Metal compilation, GPU-to-CPU parity, Photos permission flows, RAW neutral-location orientation, export bit depth/ICC inspection, crop gestures and accessibility need validation on actual Apple devices. Test source includes deterministic random color checks, transfer values, hue wrap/anchors, curve knots/clamping, invalid schemas/curves and rotated crop containment.

The **swiftui-pro** skill (MIT, Paul Hudson) was used as guidance only. No skill code is vendored. Platform availability and Swift toolchain choices follow this project's deployment requirements.

The final swiftui-pro pass covered api, views, data, accessibility, swift and hygiene references, retaining iOS 17/macOS 14 compatible APIs. API declarations were checked against Apple documentation for CIRAWFilter, CIKernel, CIContext image representations, PhotosPicker, file import/export, focus keys and Photos async requests. JPEG/TIFF/8-bit HEIF representation methods return optional Data without throwing; 10-bit HEIF throws and remains availability-gated with an 8-bit fallback. The Linux environment has no Apple SDK, so Xcode compilation and device validation remain required, especially Metal sampler compilation, RAW neutral-location orientation/readback behavior and codec support.
