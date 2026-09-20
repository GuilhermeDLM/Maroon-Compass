import Foundation

struct PersonalPlanEngine: Sendable {
    let calendar: Calendar

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    func occurrences(on date: Date, blocks: [PersonalBlock]) -> [PersonalBlockOccurrence] {
        let dayStart = calendar.startOfDay(for: date)
        guard
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart),
            let previousDay = calendar.date(byAdding: .day, value: -1, to: dayStart)
        else { return [] }

        return blocks
            .filter(\.isEnabled)
            .flatMap { block in
                [previousDay, dayStart].compactMap { candidateDay in
                    occurrence(for: block, startingOn: candidateDay, visibleFrom: dayStart, until: dayEnd)
                }
            }
            .sorted {
                if $0.visibleStart == $1.visibleStart { return $0.visibleEnd < $1.visibleEnd }
                return $0.visibleStart < $1.visibleStart
            }
    }

    func agenda(
        on date: Date,
        classOccurrences: [ScheduleOccurrence],
        blocks: [PersonalBlock]
    ) -> [DailyAgendaItem] {
        let classItems = classOccurrences.map(DailyAgendaItem.classMeeting)
        let personalItems = occurrences(on: date, blocks: blocks).map(DailyAgendaItem.personal)
        return (classItems + personalItems).sorted {
            if $0.start == $1.start { return $0.end < $1.end }
            return $0.start < $1.start
        }
    }

    func conflicts(
        on date: Date,
        classOccurrences: [ScheduleOccurrence],
        blocks: [PersonalBlock]
    ) -> [PersonalPlanConflict] {
        let items = agenda(on: date, classOccurrences: classOccurrences, blocks: blocks)
        var result: [PersonalPlanConflict] = []

        for firstIndex in items.indices {
            for secondIndex in items.index(after: firstIndex)..<items.endIndex {
                let first = items[firstIndex]
                let second = items[secondIndex]
                guard first.personalBlockID != nil || second.personalBlockID != nil else { continue }
                guard first.start < second.end, second.start < first.end else { continue }
                let overlapStart = max(first.start, second.start)
                let overlapEnd = min(first.end, second.end)
                let personalIDs = Set([first.personalBlockID, second.personalBlockID].compactMap { $0 })
                result.append(PersonalPlanConflict(
                    id: "\(dateString(for: date))-\(first.id)-\(second.id)",
                    firstTitle: first.title,
                    secondTitle: second.title,
                    start: overlapStart,
                    end: overlapEnd,
                    personalBlockIDs: personalIDs
                ))
            }
        }
        return result
    }

    func openWindows(
        on date: Date,
        classOccurrences: [ScheduleOccurrence],
        blocks: [PersonalBlock],
        dayStartsAt startHour: Int = 7,
        dayEndsAt endHour: Int = 23,
        minimumMinutes: Int = 30
    ) -> [PlanTimeWindow] {
        let dayStart = calendar.startOfDay(for: date)
        guard
            let windowStart = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: dayStart),
            let windowEnd = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: dayStart)
        else { return [] }

        var busy = classOccurrences.map { (max($0.start, windowStart), min($0.end, windowEnd)) }
        busy += occurrences(on: date, blocks: blocks).map { (max($0.visibleStart, windowStart), min($0.visibleEnd, windowEnd)) }
        busy = busy.filter { $0.0 < $0.1 }.sorted { $0.0 < $1.0 }

        var merged: [(Date, Date)] = []
        for interval in busy {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }
            if interval.0 <= last.1 {
                merged[merged.count - 1].1 = max(last.1, interval.1)
            } else {
                merged.append(interval)
            }
        }

        var cursor = windowStart
        var windows: [PlanTimeWindow] = []
        let minimumDuration = TimeInterval(minimumMinutes * 60)
        for interval in merged {
            if interval.0.timeIntervalSince(cursor) >= minimumDuration {
                windows.append(PlanTimeWindow(start: cursor, end: interval.0))
            }
            cursor = max(cursor, interval.1)
        }
        if windowEnd.timeIntervalSince(cursor) >= minimumDuration {
            windows.append(PlanTimeWindow(start: cursor, end: windowEnd))
        }
        return windows
    }

    func date(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    func dateString(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func occurrence(
        for block: PersonalBlock,
        startingOn candidateDay: Date,
        visibleFrom dayStart: Date,
        until dayEnd: Date
    ) -> PersonalBlockOccurrence? {
        guard blockOccurs(block, on: candidateDay) else { return nil }
        guard
            let start = calendar.date(bySettingHour: block.startHour, minute: block.startMinute, second: 0, of: candidateDay),
            var end = calendar.date(bySettingHour: block.endHour, minute: block.endMinute, second: 0, of: candidateDay)
        else { return nil }
        if end <= start {
            guard let nextDayEnd = calendar.date(byAdding: .day, value: 1, to: end) else { return nil }
            end = nextDayEnd
        }
        guard start < dayEnd, end > dayStart else { return nil }

        return PersonalBlockOccurrence(
            id: "\(block.id.uuidString)-\(dateString(for: candidateDay))",
            block: block,
            start: start,
            end: end,
            visibleStart: max(start, dayStart),
            visibleEnd: min(end, dayEnd),
            continuesFromPreviousDay: start < dayStart,
            continuesIntoNextDay: end > dayEnd
        )
    }

    private func blockOccurs(_ block: PersonalBlock, on date: Date) -> Bool {
        guard let rangeStart = self.date(block.startDate) else { return false }
        let candidate = calendar.startOfDay(for: date)
        guard candidate >= calendar.startOfDay(for: rangeStart) else { return false }

        switch block.recurrence {
        case .once:
            return calendar.isDate(candidate, inSameDayAs: rangeStart)
        case .weekly:
            if let endDate = block.endDate.flatMap(self.date), candidate > calendar.startOfDay(for: endDate) {
                return false
            }
            guard let weekday = Weekday(calendarWeekday: calendar.component(.weekday, from: candidate)) else { return false }
            return block.weekdays.contains(weekday)
        }
    }
}
