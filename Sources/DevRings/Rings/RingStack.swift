import AppKit
import DevRingsCore
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    var darkened: Color { Color(nsColor: NSColor(self).blended(withFraction: 0.3, of: .black) ?? NSColor(self)) }
}

enum RingKind {
    case ship, review, ticket

    var color: Color {
        switch self {
        case .ship: Color(hex: 0xFA114F)
        case .review: Color(hex: 0x1EEAEF)
        case .ticket: Color(hex: 0x92E82A)
        }
    }
}

extension RingID {
    var kind: RingKind {
        switch self {
        case .ship: .ship
        case .review: .review
        case .ticket: .ticket
        }
    }

    var color: Color { kind.color }
}

struct RingStack: View {
    var rings: [RingResult]
    var paused: Bool
    var lineWidth: CGFloat
    var gap: CGFloat
    var trackOpacity = 0.2
    /// Overrides each ring's colour, for the menu bar's monochrome and grey styles.
    var tint: ((RingResult) -> Color)?
    var flat = false
    var waitsForLayout = false

    @State private var revealed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(rings: [RingResult], paused: Bool, lineWidth: CGFloat, gap: CGFloat, trackOpacity: Double = 0.2, animated: Bool = true,
         tint: ((RingResult) -> Color)? = nil, flat: Bool = false, waitsForLayout: Bool = false) {
        self.rings = rings
        self.paused = paused
        self.lineWidth = lineWidth
        self.gap = gap
        self.trackOpacity = trackOpacity
        self.tint = tint
        self.flat = flat
        self.waitsForLayout = waitsForLayout
        _revealed = State(initialValue: !animated)
    }

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { i, ring in
                RingView(progress: revealed ? ring.progress : 0,
                         color: tint?(ring) ?? (paused ? .gray : ring.id.color),
                         lineWidth: lineWidth, trackOpacity: trackOpacity, flat: flat)
                    .padding(CGFloat(i) * (lineWidth + gap))
                    .animation(reduceMotion ? nil : .spring(duration: 1.1, bounce: 0.12).delay(Double(i) * 0.08),
                               value: revealed)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            guard !revealed else { return }
            // In a menu, state changed after onAppear isn't drawn until the menu closes, so the fill has to start
            // here. Views that rebuild in place, like the settings previews, wait for layout instead: starting in
            // onAppear there also animated their position, sliding the tracks in from the side.
            if waitsForLayout {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { revealed = true }
            } else {
                revealed = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let parts = rings.map { "\($0.name), \($0.count) of \($0.goal)\($0.isClosed ? ", closed" : "")" }
        return (paused ? ["Paused"] : parts).joined(separator: "; ")
    }
}
