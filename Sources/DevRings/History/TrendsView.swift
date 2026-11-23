import Charts
import DevRingsCore
import SwiftUI

struct Card<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(.headline) }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
    }
}

struct TrendsView: View {
    let history: History

    private struct Total: Identifiable {
        let week: Date
        let ring: String
        let count: Int
        var id: String { "\(week)\(ring)" }
    }

    private struct Rate: Identifiable {
        let week: Date
        let rate: Double
        var id: Date { week }
    }

    var body: some View {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let weeks = (0..<8).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
        let names = ringNames
        var totals: [Total] = []
        var rates: [Rate] = []
        for week in weeks {
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week) }.map { LocalDay.string($0) }
            let records = days.compactMap { history.days[$0] }
            for (kind, name) in names {
                totals.append(Total(week: week, ring: name, count: records.flatMap(\.rings).filter { $0.id.kind == kind }.map(\.count).reduce(0, +)))
            }
            let counted = days.filter(history.counts)
            if !counted.isEmpty {
                rates.append(Rate(week: week, rate: Double(counted.filter { history.days[$0]?.isPerfect == true }.count) / Double(counted.count)))
            }
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
            Card(title: "Weekly totals") {
                Chart(totals) {
                    BarMark(x: .value("Week", $0.week, unit: .weekOfYear), y: .value("Count", $0.count))
                        .foregroundStyle(by: .value("Ring", $0.ring))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale(domain: names.map(\.1), range: names.map(\.0.color))
                .frame(height: 220)
            }
            Card(title: "Days with every ring closed") {
                Chart(rates) {
                    AreaMark(x: .value("Week", $0.week, unit: .weekOfYear), y: .value("Rate", $0.rate))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [Color(hex: 0xFFD60A).opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Week", $0.week, unit: .weekOfYear), y: .value("Rate", $0.rate))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Color(hex: 0xFFD60A))
                    PointMark(x: .value("Week", $0.week, unit: .weekOfYear), y: .value("Rate", $0.rate))
                        .foregroundStyle(Color(hex: 0xFFD60A))
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1]) { value in
                        AxisGridLine()
                        AxisValueLabel { if let rate = value.as(Double.self) { Text(rate, format: .percent) } }
                    }
                }
                .frame(height: 220)
            }
            }
            .padding(20)
        }
    }

    private var ringNames: [(RingKind, String)] {
        [(.ship, "Ship"), (.review, "Review")] + (history.settings.setup.ticket.map { [(.ticket, $0.name)] } ?? [])
    }
}
