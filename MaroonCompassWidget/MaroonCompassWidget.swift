import AppIntents
import SwiftUI
import WidgetKit

struct MaroonWidgetConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Next Class"
    static let description = IntentDescription("Shows the next meeting in the embedded Fall 2026 schedule.")
}

struct WidgetShowTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Maroon Compass"
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult { .result() }
}

struct MaroonCompassWidgetEntry: TimelineEntry {
    let date: Date
    let next: WidgetOccurrence?
}

struct MaroonCompassWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MaroonCompassWidgetEntry {
        MaroonCompassWidgetEntry(date: Date(), next: WidgetSchedule.placeholder)
    }

    func snapshot(for configuration: MaroonWidgetConfigurationIntent, in context: Context) async -> MaroonCompassWidgetEntry {
        MaroonCompassWidgetEntry(date: Date(), next: WidgetSchedule.next(after: Date()))
    }

    func timeline(for configuration: MaroonWidgetConfigurationIntent, in context: Context) async -> Timeline<MaroonCompassWidgetEntry> {
        let now = Date()
        let next = WidgetSchedule.next(after: now)
        let refresh = next.map { min($0.end.addingTimeInterval(60), now.addingTimeInterval(30 * 60)) }
            ?? now.addingTimeInterval(6 * 60 * 60)
        return Timeline(entries: [MaroonCompassWidgetEntry(date: now, next: next)], policy: .after(refresh))
    }
}

struct MaroonCompassWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MaroonCompassWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                inlineView
            case .accessoryRectangular:
                rectangularView
            case .systemMedium:
                mediumView
            default:
                smallView
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryInline || family == .accessoryRectangular {
                Color.clear
            } else {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.38, blue: 0.82), Color(red: 0.015, green: 0.11, blue: 0.28)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "location.north.circle.fill")
                Text("NEXT CLASS").font(.caption2.weight(.bold))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.78))

            if let next = entry.next {
                Text(next.code).font(.title2.bold()).foregroundStyle(.white)
                Text(next.title).font(.caption).foregroundStyle(.white.opacity(0.78)).lineLimit(2)
                Spacer(minLength: 0)
                Text(next.start, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text(next.start, style: .relative)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
            } else {
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.white)
                Text("Semester schedule complete").font(.headline).foregroundStyle(.white)
                Spacer()
            }
        }
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Label("Maroon Compass", systemImage: "location.north.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.78))
                if let next = entry.next {
                    Text(next.code).font(.title.bold()).foregroundStyle(.white)
                    Text(next.title).font(.subheadline).foregroundStyle(.white.opacity(0.78)).lineLimit(2)
                    Text(next.start, format: .dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                } else {
                    Text("Fall schedule complete").font(.title2.bold()).foregroundStyle(.white)
                }
            }
            Spacer()
            VStack(spacing: 9) {
                if let next = entry.next {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 35))
                        .foregroundStyle(.white)
                    Text(next.start, style: .relative)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                }
                Button(intent: WidgetShowTodayIntent()) {
                    Label("Open", systemImage: "arrow.up.right")
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
    }

    private var rectangularView: some View {
        HStack {
            Image(systemName: "calendar.badge.clock")
            if let next = entry.next {
                VStack(alignment: .leading) {
                    Text(next.code).font(.headline)
                    Text(next.start, format: .dateTime.weekday(.abbreviated).hour().minute()).font(.caption)
                }
                Spacer()
                Text(next.start, style: .relative).font(.caption.monospacedDigit())
            } else {
                Text("Fall schedule complete").font(.headline)
            }
        }
    }

    private var inlineView: some View {
        Group {
            if let next = entry.next {
                Label("\(next.code) · \(next.start.formatted(date: .omitted, time: .shortened))", systemImage: "calendar")
            } else {
                Label("Schedule complete", systemImage: "checkmark.circle")
            }
        }
    }
}

struct MaroonCompassNextClassWidget: Widget {
    let kind = "MaroonCompassNextClassWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: MaroonWidgetConfigurationIntent.self,
            provider: MaroonCompassWidgetProvider()
        ) { entry in
            MaroonCompassWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Class")
        .description("Your next Fall 2026 class and countdown.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct MaroonCompassWidgetBundle: WidgetBundle {
    var body: some Widget {
        MaroonCompassNextClassWidget()
    }
}

struct WidgetOccurrence: Hashable {
    let code: String
    let title: String
    let start: Date
    let end: Date
}

private enum WidgetSchedule {
    private struct Pattern {
        let code: String
        let title: String
        let weekdays: Set<Int>
        let startHour: Int
        let startMinute: Int
        let endHour: Int
        let endMinute: Int
    }

    private struct Special {
        let code: String
        let title: String
        let date: String
        let startHour: Int
        let startMinute: Int
        let endHour: Int
        let endMinute: Int
    }

    private static let patterns: [Pattern] = [
        Pattern(code: "CHEM 107", title: "General Chemistry for Engineering Students", weekdays: [3, 5], startHour: 8, startMinute: 0, endHour: 9, endMinute: 15),
        Pattern(code: "CHEM 117", title: "Engineering Chemistry Laboratory", weekdays: [3], startHour: 11, startMinute: 10, endHour: 14, endMinute: 0),
        Pattern(code: "ENGR 102", title: "Engineering Lab I – Computation", weekdays: [2], startHour: 17, startMinute: 10, endHour: 18, endMinute: 0),
        Pattern(code: "ENGR 102", title: "Engineering Lab I – Computation", weekdays: [4], startHour: 17, startMinute: 10, endHour: 19, endMinute: 0),
        Pattern(code: "ENGR 102", title: "Engineering Lab I – Computation", weekdays: [2], startHour: 18, startMinute: 1, endHour: 19, endMinute: 0),
        Pattern(code: "FYEX 101", title: "First Year Experience", weekdays: [2], startHour: 15, startMinute: 0, endHour: 15, endMinute: 50),
        Pattern(code: "MATH 151", title: "Engineering Mathematics I", weekdays: [3, 5], startHour: 15, startMinute: 55, endHour: 17, endMinute: 10),
        Pattern(code: "MATH 151", title: "Engineering Mathematics I", weekdays: [2, 4], startHour: 11, startMinute: 30, endHour: 12, endMinute: 20),
        Pattern(code: "POLS 207", title: "State and Local Government", weekdays: [2, 4, 6], startHour: 9, startMinute: 10, endHour: 10, endMinute: 0)
    ]

    private static let specials: [Special] = [
        Special(code: "MATH 151", title: "Special MATH 151 meeting", date: "2026-09-17", startHour: 17, startMinute: 30, endHour: 18, endMinute: 45),
        Special(code: "MATH 151", title: "Special MATH 151 meeting", date: "2026-10-22", startHour: 17, startMinute: 30, endHour: 18, endMinute: 45),
        Special(code: "MATH 151", title: "Special MATH 151 meeting", date: "2026-11-19", startHour: 17, startMinute: 30, endHour: 18, endMinute: 45)
    ]

    private static let noClassDates: Set<String> = [
        "2026-09-07", "2026-11-25", "2026-11-26", "2026-11-27", "2026-12-04"
    ]

    static var placeholder: WidgetOccurrence {
        let start = date("2026-08-24", hour: 9, minute: 10) ?? Date()
        return WidgetOccurrence(code: "POLS 207", title: "State and Local Government", start: start, end: start.addingTimeInterval(50 * 60))
    }

    static func next(after now: Date) -> WidgetOccurrence? {
        for offset in 0...150 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            if let meeting = occurrences(on: day).first(where: { $0.end > now }) { return meeting }
        }
        return nil
    }

    private static func occurrences(on day: Date) -> [WidgetOccurrence] {
        guard
            let first = date("2026-08-24"),
            let last = date("2026-12-03"),
            calendar.startOfDay(for: day) >= calendar.startOfDay(for: first),
            calendar.startOfDay(for: day) <= calendar.startOfDay(for: last)
        else { return [] }
        let key = dateString(day)
        guard !noClassDates.contains(key) else { return [] }

        let weekday = key == "2026-12-01" ? 6 : calendar.component(.weekday, from: day)
        var result = patterns.filter { $0.weekdays.contains(weekday) }.compactMap { pattern -> WidgetOccurrence? in
            guard
                let start = calendar.date(bySettingHour: pattern.startHour, minute: pattern.startMinute, second: 0, of: day),
                let end = calendar.date(bySettingHour: pattern.endHour, minute: pattern.endMinute, second: 0, of: day)
            else { return nil }
            return WidgetOccurrence(code: pattern.code, title: pattern.title, start: start, end: end)
        }
        result += specials.filter { $0.date == key }.compactMap { item -> WidgetOccurrence? in
            guard
                let start = calendar.date(bySettingHour: item.startHour, minute: item.startMinute, second: 0, of: day),
                let end = calendar.date(bySettingHour: item.endHour, minute: item.endMinute, second: 0, of: day)
            else { return nil }
            return WidgetOccurrence(code: item.code, title: item.title, start: start, end: end)
        }
        return result.sorted { $0.start < $1.start }
    }

    private static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        return value
    }

    private static func date(_ value: String, hour: Int = 12, minute: Int = 0) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute
        ))
    }

    private static func dateString(_ value: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: value)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
