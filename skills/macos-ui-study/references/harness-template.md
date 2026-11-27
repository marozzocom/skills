# SwiftPM Dual-Mode Study Harness

A zero-dependency SwiftPM template that runs both as:
1. **Headless `@2x` Retina snapshotter:** `.build/debug/StudyApp --render <dir>` (uses `.prohibited` activation policy — never steals focus or opens a window; resolves semantic `NSColor`s accurately per `NSAppearance`).
2. **Live interactive macOS app:** `.build/debug/StudyApp` (activates with a real window, Dock icon, toolbar variant/appearance toggles, and terminates cleanly when the last window closes).

## `Package.swift`

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StudyApp",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "StudyApp", targets: ["StudyApp"])
    ],
    targets: [
        .executableTarget(
            name: "StudyApp",
            path: "Sources/StudyApp"
        )
    ]
)
```

## `Sources/StudyApp/main.swift`

```swift
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct StudyShowcaseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("UI Study — Native macOS") {
            ShowcaseWindowView()
                .frame(minWidth: 640, minHeight: 340)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
private func renderSnapshots(to outputDir: String) throws {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)

    try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

    let configs: [(name: String, scheme: ColorScheme, width: CGFloat)] = [
        ("study-dark.png", .dark, 680),
        ("study-light.png", .light, 680)
    ]

    for config in configs {
        let appearance = NSAppearance(named: config.scheme == .dark ? .darkAqua : .aqua)
        let canvasBg = config.scheme == .dark
            ? Color(red: 0.118, green: 0.118, blue: 0.125)
            : Color(red: 0.945, green: 0.949, blue: 0.957)

        let view = ZStack {
            canvasBg
            StudySubjectView()
                .frame(width: config.width)
                .padding(32)
        }
        .environment(\.colorScheme, config.scheme)
        .fixedSize()

        let hostingView = NSHostingView(rootView: view)
        hostingView.appearance = appearance
        let fittingSize = hostingView.fittingSize
        hostingView.frame = CGRect(origin: .zero, size: fittingSize)
        hostingView.layoutSubtreeIfNeeded()

        guard hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) != nil else {
            fputs("Failed to create bitmap rep for \(config.name)\n", stderr)
            continue
        }

        let pixelWidth = Int(fittingSize.width * 2)
        let pixelHeight = Int(fittingSize.height * 2)
        guard let retinaRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            continue
        }
        retinaRep.size = fittingSize

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: retinaRep) {
            NSGraphicsContext.current = ctx
            ctx.cgContext.interpolationQuality = .high
            appearance?.performAsCurrentDrawingAppearance {
                hostingView.displayIgnoringOpacity(hostingView.bounds, in: ctx)
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        if let pngData = retinaRep.representation(using: .png, properties: [:]) {
            let outPath = (outputDir as NSString).appendingPathComponent(config.name)
            try pngData.write(to: URL(fileURLWithPath: outPath))
            print("Rendered: \(outPath) (\(pixelWidth)x\(pixelHeight))")
        }
    }
}

if let renderIndex = CommandLine.arguments.firstIndex(of: "--render") {
    let outDir = renderIndex + 1 < CommandLine.arguments.count
        ? CommandLine.arguments[renderIndex + 1]
        : "/tmp/ui-study-renders"
    do {
        try MainActor.assumeIsolated {
            try renderSnapshots(to: outDir)
        }
    } catch {
        fputs("Render failed: \(error)\n", stderr)
        exit(1)
    }
} else {
    StudyShowcaseApp.main()
}
```
