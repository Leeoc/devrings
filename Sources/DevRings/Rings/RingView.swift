import SwiftUI

/// Angles are in turns, 0 at 3 o'clock, increasing clockwise. Callers rotate by -90° to start at 12.
struct RingArc: Shape {
    var from: Double
    var to: Double

    func path(in rect: CGRect) -> Path {
        Path { p in
            p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
                     startAngle: .degrees(from * 360), endAngle: .degrees(to * 360), clockwise: false)
        }
    }
}

struct RingCap: Shape {
    var turn: Double
    var diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let a = turn * 2 * .pi
        let c = CGPoint(x: rect.midX + r * cos(a), y: rect.midY + r * sin(a))
        return Path(ellipseIn: CGRect(x: c.x - diameter / 2, y: c.y - diameter / 2, width: diameter, height: diameter))
    }
}

struct RingView: View, @MainActor Animatable {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat
    var trackOpacity = 0.2
    /// Draws the ring in its pure colour. The darker start that gives large rings depth just reads as dull at icon size.
    var flat = false

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(trackOpacity), lineWidth: lineWidth)
            Group {
                if progress >= 1 { lapped } else if progress > 0 { partial }
            }
            .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }

    private var start: Color { flat ? color : color.darkened }

    // The stroke uses butt caps and separate cap discs, because an AngularGradient
    // is undefined outside its angle range and would tint the round caps wrongly.
    private var partial: some View {
        ZStack {
            RingArc(from: 0, to: progress)
                .stroke(AngularGradient(colors: [start, color], center: .center,
                                        startAngle: .zero, endAngle: .degrees(360 * progress)),
                        lineWidth: lineWidth)
            RingCap(turn: 0, diameter: lineWidth).fill(start)
            RingCap(turn: progress, diameter: lineWidth).fill(color)
        }
    }

    // Past 100% the whole ring is filled with the gradient ending at the head, and the head
    // casts a shadow forward onto the start of the ring. The trailing arc is redrawn over the
    // cap's back half so the shadow only shows ahead of it.
    private var lapped: some View {
        let full = AngularGradient(colors: [start, color], center: .center, startAngle: .zero, endAngle: .degrees(360))
        return ZStack {
            Circle().stroke(full, lineWidth: lineWidth)
            RingCap(turn: 0, diameter: lineWidth)
                .fill(color)
                .shadow(color: .black.opacity(0.45), radius: lineWidth * 0.15, y: lineWidth * 0.12)
                .mask(Circle().stroke(lineWidth: lineWidth))
            RingArc(from: -0.25, to: 0).stroke(full, lineWidth: lineWidth)
        }
        .rotationEffect(.degrees(progress.truncatingRemainder(dividingBy: 1) * 360))
    }
}
