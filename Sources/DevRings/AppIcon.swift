import AppKit
import DevRingsCore
import SwiftUI

/// Renders the app icon from the same ring views, so scripts/bundle.sh can build an .icns without Xcode.
enum AppIcon {
    @MainActor static func render(into directory: URL) -> Bool {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let renderer = ImageRenderer(content: IconArt())
                renderer.scale = CGFloat(size * scale) / 1024
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
                let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
                guard (try? png.write(to: directory.appending(path: name))) != nil else { return false }
            }
        }
        return true
    }
}

private struct IconArt: View {
    var body: some View {
        ZStack {
            // macOS icon grid: an 824pt rounded square centred on a 1024pt canvas.
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.03)], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 10)
            RingStack(rings: [ring(.ship, 78), ring(.review, 62), ring(.ticket(UUID()), 88)],
                      paused: false, lineWidth: 80, gap: 12, animated: false)
                .frame(width: 600, height: 600)
        }
        .frame(width: 1024, height: 1024)
    }

    private func ring(_ id: RingID, _ percent: Int) -> RingResult {
        RingResult(id: id, name: "", goal: 100, items: Array(repeating: RingItem(ref: "", title: "", url: URL(string: "https://x")!), count: percent))
    }
}
