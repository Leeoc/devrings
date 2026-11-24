import AppKit
import DevRingsCore
import SwiftUI

/// The menu bar rings as an image. Monochrome is a template image, so macOS tints it like every other
/// menu bar icon: dark on light bars, light on dark ones, and inverted while the menu is open.
@MainActor
enum MenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func image(for day: DayRecord, style: MenuBarStyle) -> NSImage {
        let image = NSImage(size: size)
        // Rendered at each backing scale so it's crisp on both standard and Retina displays.
        for scale in [1.0, 2.0, 3.0] {
            let renderer = ImageRenderer(content: rings(day, style))
            renderer.scale = scale
            if let cgImage = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cgImage)
                rep.size = size
                image.addRepresentation(rep)
            }
        }
        image.isTemplate = style == .monochrome
        return image
    }

    /// `ink` only matters for monochrome: black for the template image, or the bar's text colour in previews.
    static func rings(_ day: DayRecord, _ style: MenuBarStyle, ink: Color = .black, size: CGFloat = size.width,
                      animated: Bool = false) -> some View {
        RingStack(rings: day.rings, paused: day.pause != nil, lineWidth: size * 0.135, gap: size * 0.03,
                  trackOpacity: style == .monochrome ? 0.28 : 0.22, animated: animated,
                  tint: tint(style, paused: day.pause != nil, ink: ink), flat: true, waitsForLayout: animated)
            .frame(width: size, height: size)
    }

    private static func tint(_ style: MenuBarStyle, paused: Bool, ink: Color) -> ((RingResult) -> Color)? {
        switch style {
        case .colour: nil
        case .monochrome: { _ in ink }
        case .greyUntilClosed: { ring in ring.isClosed && !paused ? ring.id.color : Color(white: 0.56) }
        }
    }

    /// Today's rings at fixed, unlapped progress, so previews fill once and show one ring closed.
    static func example(like day: DayRecord) -> DayRecord {
        var example = day
        example.pause = nil
        let counts = [7, 10, 5]
        let item = RingItem(ref: "", title: "", url: URL(string: "https://example.com")!)
        for i in example.rings.indices {
            example.rings[i].goal = 10
            example.rings[i].items = Array(repeating: item, count: counts[i % counts.count])
        }
        return example
    }

    static func count(_ day: DayRecord) -> String {
        "\(day.rings.filter(\.isClosed).count)/\(day.rings.count)"
    }
}

extension MenuBarStyle {
    var title: String {
        switch self {
        case .colour: "Colour"
        case .monochrome: "Monochrome"
        case .greyUntilClosed: "Grey until closed"
        }
    }

    var detail: String {
        switch self {
        case .colour: "The ring colours, as in Fitness."
        case .monochrome: "Matches your other menu bar icons."
        case .greyUntilClosed: "Rings light up as you close them."
        }
    }
}

/// Three cards, like the Appearance picker in System Settings. Choosing one replays its rings filling up.
struct MenuBarStylePicker: View {
    let day: DayRecord
    @Binding var selection: MenuBarStyle
    let showsCount: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(MenuBarStyle.allCases, id: \.self) { style in
                StyleCard(day: MenuBarIcon.example(like: day), style: style, showsCount: showsCount, selected: style == selection) {
                    selection = style
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

private struct StyleCard: View {
    let day: DayRecord
    let style: MenuBarStyle
    let showsCount: Bool
    let selected: Bool
    let select: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let ink: Color = dark ? .white : .black
        Button(action: select) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    // A new identity when selected, so the rings rebuild and play their opening spring.
                    MenuBarIcon.rings(day, style, ink: ink, size: 52, animated: selected)
                        .id(selected)
                    if showsCount {
                        Text(MenuBarIcon.count(day))
                            .font(.system(size: 22, weight: .medium).monospacedDigit())
                            .foregroundStyle(ink)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 88)
                .background(dark ? Color(white: 0.09) : Color(white: 0.95), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color(nsColor: .separatorColor),
                                      lineWidth: selected ? 3 : 0.5)
                }
                VStack(spacing: 1) {
                    Text(style.title).font(.callout.weight(selected ? .semibold : .regular))
                    Text(style.detail).font(.caption).foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.title). \(style.detail)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
