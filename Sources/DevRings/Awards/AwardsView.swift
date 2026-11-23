import DevRingsCore
import SwiftUI

struct AwardsView: View {
    let history: History
    @State private var selected: AwardKind?

    private let sections: [(String, [AwardKind])] = [
        ("Daily", [.firstRing, .perfectDay, .doubleShip, .tripleShip, .newBest]),
        ("Weekly", [.perfectWeek, .reviewerOfTheWeek]),
        ("Streaks", [.streak5, .streak10, .streak25, .streak50, .streak100]),
    ]

    var body: some View {
        let earned = history.awards()
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("You've earned \(earned.count) of \(AwardKind.allCases.count) awards.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                ForEach(sections, id: \.0) { title, kinds in
                    VStack(alignment: .leading, spacing: 16) {
                        Text(title).font(.title2.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)], spacing: 24) {
                            ForEach(kinds) { kind in
                                AwardCell(kind: kind, award: earned[kind]) { selected = kind }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            // Dev flag alongside --fixture/--open-window, for looking at the detail sheet without clicking.
            if let i = CommandLine.arguments.firstIndex(of: "--open-award"), i + 1 < CommandLine.arguments.count {
                let kind = AwardKind(rawValue: CommandLine.arguments[i + 1])
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    selected = kind
                }
            }
        }
        .sheet(item: $selected) { kind in
            AwardDetail(kind: kind, award: earned[kind])
        }
    }
}

extension AwardKind: Identifiable {
    public var id: String { rawValue }
}

private struct AwardCell: View {
    let kind: AwardKind
    let award: EarnedAward?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(spacing: 10) {
                TiltingMedal(kind: kind, earned: award != nil).frame(width: 112, height: 112)
                VStack(spacing: 3) {
                    Text(kind.title).font(.headline)
                    Text(award.map(kind.earnedCaption) ?? kind.howToEarn)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 170)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.title), \(award.map(kind.earnedCaption) ?? "not earned yet")")
    }
}

/// Leans toward the pointer, the way Fitness awards respond to your finger.
private struct TiltingMedal: View {
    let kind: AwardKind
    let earned: Bool
    @State private var tilt = CGSize.zero
    @State private var settling = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            MedalView(kind: kind, earned: earned, tilt: tilt, animated: settling)
                .allowsHitTesting(false)
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            guard !reduceMotion else { return }
                            switch phase {
                            case .active(let point):
                                settling = false
                                tilt = CGSize(width: point.x / geo.size.width * 2 - 1, height: point.y / geo.size.height * 2 - 1)
                            case .ended:
                                settling = true
                                tilt = .zero
                            }
                        }
                }
        }
    }
}

struct AwardDetail: View {
    let kind: AwardKind
    let award: EarnedAward?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = 0.0
    @State private var dragStart: Double?
    @State private var settling = false

    var body: some View {
        VStack(spacing: 20) {
            MedalView(kind: kind, earned: award != nil, back: backText, spin: spin, animated: settling, spinIn: !reduceMotion)
                .frame(width: 260, height: 260)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            settling = false
                            let start = dragStart ?? spin
                            dragStart = start
                            spin = start + value.translation.width / 60
                        }
                        .onEnded { value in
                            settling = true
                            dragStart = nil
                            let flung = spin + value.predictedEndTranslation.width / 120
                            spin = (flung / .pi).rounded() * .pi
                        }
                )
                .help("Drag to turn it over")
            VStack(spacing: 6) {
                Text(kind.title).font(.title2.weight(.bold))
                if let award {
                    Text(kind.earnedCaption(award)).font(.headline).foregroundStyle(.secondary)
                }
                Text(kind.howToEarn).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(32)
        .frame(width: 400)
    }

    private var backText: String {
        guard let award else { return "\(kind.title)\nNot yet earned" }
        return "\(kind.title)\n" + (LocalDay.start(award.lastEarned) ?? .now).formatted(.dateTime.day().month(.wide).year())
    }
}

extension AwardKind {
    var title: String {
        switch self {
        case .firstRing: "First Ring"
        case .perfectDay: "Perfect Day"
        case .perfectWeek: "Perfect Week"
        case .doubleShip: "Double Ship"
        case .tripleShip: "Triple Ship"
        case .reviewerOfTheWeek: "Reviewer of the Week"
        case .newBest: "New Best"
        default: "\(streakLength ?? 0)-Day Streak"
        }
    }

    var howToEarn: String {
        switch self {
        case .firstRing: "Close a ring for the first time."
        case .perfectDay: "Close every ring in a day."
        case .perfectWeek: "Close every ring on every working day of a week."
        case .doubleShip: "Ship twice your goal in a day."
        case .tripleShip: "Ship three times your goal in a day."
        case .reviewerOfTheWeek: "Close Review on every working day of a week."
        case .newBest: "Beat your record for any ring."
        default: "Close every ring \(streakLength ?? 0) working days in a row."
        }
    }

    func earnedCaption(_ award: EarnedAward) -> String {
        let date = (LocalDay.start(award.lastEarned) ?? .now).formatted(.dateTime.day().month(.abbreviated))
        return award.count > 1 ? "Earned \(award.count) times, last on \(date)" : "Earned \(date)"
    }

    var streakLength: Int? {
        switch self {
        case .streak5: 5
        case .streak10: 10
        case .streak25: 25
        case .streak50: 50
        case .streak100: 100
        default: nil
        }
    }

}
