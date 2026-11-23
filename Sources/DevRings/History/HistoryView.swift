import Charts
import DevRingsCore
import SwiftUI

struct HistoryView: View {
    let model: AppModel
    @State private var selected = LocalDay.string(.now)
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @FocusState private var calendarFocused: Bool

    var body: some View {
        let history = model.history
        VStack(spacing: 0) {
            SummaryLine(history: history, catchingUp: model.backfillRemaining > 0)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            Divider()
            HStack(spacing: 0) {
                MonthGrid(history: history, month: $month, selected: $selected)
                    .padding(20)
                    .frame(width: 360)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .focusable()
                    .focused($calendarFocused)
                    .focusEffectDisabled()
                    .onKeyPress(.leftArrow) { move(-1) }
                    .onKeyPress(.rightArrow) { move(1) }
                    .onKeyPress(.upArrow) { move(-7) }
                    .onKeyPress(.downArrow) { move(7) }
                Divider()
                ScrollView {
                    DayPanel(model: model, day: selected)
                        .padding(24)
                        .frame(maxWidth: 720, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { calendarFocused = true }
        .onChange(of: selected) { _, day in
            if let date = LocalDay.start(day), let start = Calendar.current.dateInterval(of: .month, for: date)?.start {
                month = start
            }
        }
    }

    private func move(_ days: Int) -> KeyPress.Result {
        guard let day = LocalDay.adding(days, to: selected), day <= model.todayKey else { return .handled }
        selected = day
        return .handled
    }
}

private struct SummaryLine: View {
    let history: History
    let catchingUp: Bool

    var body: some View {
        let recent = (0..<30).compactMap { LocalDay.adding(-$0, to: history.today) }
        let counted = recent.filter(history.counts)
        let perfect = counted.filter { history.days[$0]?.isPerfect == true }.count
        let rings = recent.compactMap { history.days[$0] }.flatMap(\.rings)
        HStack(spacing: 20) {
            stat("flame.fill", .orange, history.streak == 0 ? "No streak yet" : "\(history.streak)-day streak")
            stat("checkmark.seal.fill", Color(hex: 0xFFC400), perfect == 1 ? "1 perfect day" : "\(perfect) perfect days")
            stat("arrow.triangle.merge", RingKind.ship.color, "\(total(rings, .ship)) shipped")
            stat("text.bubble.fill", RingKind.review.color, "\(total(rings, .review)) reviewed")
            Spacer()
            Text(catchingUp ? "Catching up on the last \(AppModel.backfillDays) days…" : "Last 30 days")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private func stat(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        Label {
            Text(text).monospacedDigit()
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }

    private func total(_ rings: [RingResult], _ kind: RingKind) -> Int {
        rings.filter { $0.id.kind == kind }.map(\.count).reduce(0, +)
    }
}

private func date(_ day: String) -> Date { LocalDay.start(day) ?? .now }

/// Mini rings for one day: a grey dot when paused, empty tracks when nothing was recorded.
struct DayCell: View {
    let history: History
    let day: String
    let size: CGFloat

    var body: some View {
        Group {
            if history.isWorkingDay(day), history.pause(on: day) != nil {
                Circle().fill(.secondary.opacity(0.6)).frame(width: size * 0.22, height: size * 0.22)
            } else if let record = history.days[day] {
                rings(record.rings)
            } else if day <= history.today, history.isWorkingDay(day) {
                rings(history.settings.setup.emptyRecord(for: day).rings)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
    }

    private func rings(_ rings: [RingResult]) -> some View {
        RingStack(rings: rings, paused: false, lineWidth: size * 0.12, gap: size * 0.03, trackOpacity: 0.25, animated: false)
    }
}

private struct DayNumber: View {
    let day: String
    let selected: Bool
    let isToday: Bool

    var body: some View {
        Text(date(day), format: .dateTime.day())
            .font(.caption.monospacedDigit().weight(selected || isToday ? .semibold : .regular))
            .foregroundStyle(selected ? Color.white : isToday ? Color.accentColor : Color.primary)
            .frame(width: 22, height: 22)
            .background { if selected { Circle().fill(Color.accentColor) } }
    }
}

private struct MonthGrid: View {
    let history: History
    @Binding var month: Date
    @Binding var selected: String

    var body: some View {
        let calendar = Calendar.current
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let days: [String?] = Array(repeating: nil, count: leading)
            + (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: month) }.map { LocalDay.string($0) }
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let weekdays = (0..<7).map { symbols[($0 + calendar.firstWeekday - 1) % 7] }
        let isCurrentMonth = calendar.isDate(month, equalTo: .now, toGranularity: .month)

        VStack(spacing: 16) {
            HStack {
                Text(month, format: .dateTime.month(.wide).year()).font(.title3.weight(.semibold))
                Spacer()
                Button("Today") { selected = history.today }
                    .disabled(selected == history.today)
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous Month")
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next Month")
                    .disabled(isCurrentMonth)
            }
            .buttonStyle(.borderless)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 12) {
                ForEach(weekdays.indices, id: \.self) { Text(weekdays[$0]).font(.caption2).foregroundStyle(.secondary) }
                ForEach(days.indices, id: \.self) { i in
                    if let day = days[i] {
                        Button { selected = day } label: {
                            VStack(spacing: 3) {
                                DayCell(history: history, day: day, size: 34)
                                DayNumber(day: day, selected: day == selected, isToday: day == history.today)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(day > history.today)
                        .opacity(day > history.today ? 0.35 : 1)
                        .accessibilityLabel(date(day).formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    } else {
                        Color.clear
                    }
                }
            }
        }
    }

    private func shift(_ months: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: months, to: month) { month = next }
    }
}

// MARK: The selected day

private struct DayPanel: View {
    let model: AppModel
    let day: String

    var body: some View {
        let history = model.history
        let record = history.days[day]
        let pause = history.isWorkingDay(day) ? history.pause(on: day) : nil
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(date(day), format: .dateTime.weekday(.wide).day().month(.wide)).font(.title3.weight(.semibold))
                    Text(status(record: record, pause: pause, history: history)).foregroundStyle(.secondary)
                }
                Spacer()
                if day == history.today {
                    Button(pause == nil ? "Pause Today" : "Resume Today") { model.togglePauseToday() }
                }
            }
            if let record {
                HStack(spacing: 28) {
                    RingStack(rings: record.rings, paused: pause != nil, lineWidth: 12, gap: 2.5)
                        .frame(width: 104, height: 104)
                        .id(day)
                    ForEach(record.rings) { ring in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ring.name.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(ring.id.color)
                            Text("\(ring.count)/\(ring.goal)").font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                ForEach(record.rings) { ring in
                    ItemSection(model: model, ring: ring)
                }
            }
        }
    }

    private func status(record: DayRecord?, pause: PauseReason?, history: History) -> String {
        if let pause { return pause.label }
        if !history.isWorkingDay(day) { return "Not a working day" }
        guard let record else { return "Nothing was recorded for this day." }
        if record.isPerfect { return "You closed all your rings" }
        let closed = record.rings.filter(\.isClosed).count
        return day == history.today ? "\(closed) of \(record.rings.count) rings closed so far" : "\(closed) of \(record.rings.count) rings closed"
    }
}

private struct ItemSection: View {
    let model: AppModel
    let ring: RingResult

    var body: some View {
        let kind = ring.id.kind
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(kind.sectionTitle(ring.name)).font(.subheadline.weight(.semibold))
                Text("\(ring.count)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.bottom, 4)
            if ring.items.isEmpty {
                Text(kind.emptyText).font(.callout).foregroundStyle(.tertiary).padding(.vertical, 4)
            }
            ForEach(ring.items.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }, id: \.self) { item in
                ItemRow(item: item, kind: kind, links: model.links(for: item, kind: kind))
            }
        }
    }
}

private struct ItemRow: View {
    let item: RingItem
    let kind: RingKind
    let links: [ItemLink]
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: kind.itemSymbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(kind.color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayTitle(hiding: links.map(\.label))).lineLimit(1)
                Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            ForEach(links) { LinkChip(link: $0) }
            Image(systemName: "arrow.up.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(hovering ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { NSWorkspace.shared.open(item.url) }
        .help("Open \(item.shortRef) in your browser")
        .contextMenu {
            Button("Open in Browser") { NSWorkspace.shared.open(item.url) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isLink)
        .accessibilityLabel(item.title)
        .accessibilityAction { NSWorkspace.shared.open(item.url) }
    }

    private var details: String {
        var parts = [item.shortRef]
        if let project = item.project { parts.append(project) }
        if let status = item.status { parts.append(status) }
        if let date = item.date { parts.append(date.formatted(date: .omitted, time: .shortened)) }
        return parts.joined(separator: " · ")
    }
}

private struct LinkChip: View {
    let link: ItemLink

    var body: some View {
        Button { NSWorkspace.shared.open(link.url) } label: {
            Label(link.label, systemImage: link.symbol)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.fill.tertiary, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Open \(link.label)")
    }
}

private extension RingKind {
    var itemSymbol: String {
        switch self {
        case .ship: "arrow.triangle.merge"
        case .review: "text.bubble.fill"
        case .ticket: "ticket.fill"
        }
    }

    func sectionTitle(_ ringName: String) -> String {
        switch self {
        case .ship: "Shipped"
        case .review: "Reviewed"
        case .ticket: ringName
        }
    }

    var emptyText: String {
        switch self {
        case .ship: "Nothing merged."
        case .review: "No reviews."
        case .ticket: "No tickets moved."
        }
    }
}

extension PauseReason {
    var label: String {
        switch self {
        case .manual: "Paused"
        case .range: "Time off"
        case .calendar: "Out of office"
        case .noActivity: "No activity, so counted as time off"
        }
    }
}
