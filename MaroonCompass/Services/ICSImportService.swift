import Foundation

struct ICSImportService: Sendable {
    private let campusTimeZone = TimeZone(identifier: "America/Chicago") ?? .gmt

    func parse(data: Data, sourceName: String) throws -> (ImportedScheduleBundle, CalendarImportReport) {
        guard data.count <= 2_000_000 else { throw ICSImportError.fileTooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw ICSImportError.invalidEncoding }

        let eventBlocks = splitEvents(unfold(text))
        guard !eventBlocks.isEmpty else { throw ICSImportError.noEvents }

        var courseByID: [String: Course] = [:]
        var patterns: [MeetingPattern] = []
        var oneTimeEvents: [OneTimeEvent] = []
        var diagnostics: [String: [String: String]] = [:]
        var normalizedAnchors = 0
        var skipped = 0
        var adjustmentCount = 0

        for (index, block) in eventBlocks.enumerated() {
            let grouped = Dictionary(grouping: block.compactMap(parseProperty), by: \.name)
            guard
                let summaryProperty = grouped["SUMMARY"]?.first,
                let startProperty = grouped["DTSTART"]?.first,
                let endProperty = grouped["DTEND"]?.first,
                let start = parseDateTime(startProperty),
                let end = parseDateTime(endProperty)
            else {
                skipped += 1
                continue
            }

            let summary = unescapeText(summaryProperty.value).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else {
                skipped += 1
                continue
            }
            let course = course(from: summary)
            courseByID[course.id] = course

            let uid = grouped["UID"]?.first?.value.trimmingCharacters(in: .whitespacesAndNewlines)
                .nonempty ?? "imported-\(index)-\(course.id)"
            let location = grouped["LOCATION"]?.first.map { unescapeText($0.value) }.flatMap(\.nonempty)
            let notes = grouped["DESCRIPTION"]?.first.map { unescapeText($0.value) }.flatMap(\.nonempty)
            let rule = grouped["RRULE"]?.first.map { parseRule($0.value) }
            let ruleDays = rule?["BYDAY"]?
                .split(separator: ",")
                .compactMap { token in Weekday(rawValue: String(token.suffix(2)).uppercased()) } ?? []
            let untilDate = rule?["UNTIL"].flatMap { parseDateTime(ICSProperty(name: "UNTIL", parameters: [:], value: $0))?.date }
            let actsAsOneTime = rule == nil || rule?["COUNT"] == "1" || (untilDate == start.date && ruleDays.count <= 1)

            let excludedDates = parseDateList(grouped["EXDATE"] ?? [])
            let additionalDates = parseDateList(grouped["RDATE"] ?? [])
            adjustmentCount += excludedDates.count + additionalDates.count

            if actsAsOneTime {
                oneTimeEvents.append(OneTimeEvent(
                    id: uid,
                    courseID: course.id,
                    date: start.date,
                    startHour: start.hour,
                    startMinute: start.minute,
                    endHour: end.hour,
                    endMinute: end.minute,
                    title: summary == course.id ? "Special \(course.code) meeting" : summary.replacingOccurrences(of: "-", with: " "),
                    sourceLocationText: location,
                    sourceNotes: notes
                ))
            } else {
                let days = ruleDays.isEmpty ? [weekday(for: start.date)].compactMap { $0 } : ruleDays
                guard !days.isEmpty else {
                    skipped += 1
                    continue
                }
                if let anchorWeekday = weekday(for: start.date), !days.contains(anchorWeekday) {
                    normalizedAnchors += 1
                }
                patterns.append(MeetingPattern(
                    id: uid,
                    courseID: course.id,
                    weekdays: days,
                    startHour: start.hour,
                    startMinute: start.minute,
                    endHour: end.hour,
                    endMinute: end.minute,
                    sourceUntilUTC: rule?["UNTIL"] ?? "",
                    excludedDates: excludedDates,
                    additionalDates: additionalDates,
                    sourceLocationText: location,
                    sourceNotes: notes
                ))
            }

            let unknown = diagnosticValues(from: grouped)
            if !unknown.isEmpty { diagnostics[uid] = unknown }
        }

        guard !patterns.isEmpty || !oneTimeEvents.isEmpty else { throw ICSImportError.noUsableEvents }
        let courses = courseByID.values.sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }
        let bundle = ImportedScheduleBundle(
            sourceName: sourceName,
            importedAt: Date(),
            courses: courses,
            patterns: patterns,
            oneTimeEvents: oneTimeEvents,
            diagnosticProperties: diagnostics.isEmpty ? nil : diagnostics
        )

        var reportNotes: [String] = []
        if normalizedAnchors > 0 {
            reportNotes.append("Normalized \(normalizedAnchors) semester-anchor event\(normalizedAnchors == 1 ? "" : "s") using RRULE weekdays, preventing incorrect Monday meetings.")
        }
        if adjustmentCount > 0 {
            reportNotes.append("Preserved \(adjustmentCount) recurrence exclusion or addition\(adjustmentCount == 1 ? "" : "s") from EXDATE/RDATE fields.")
        }
        if skipped > 0 {
            reportNotes.append("Skipped \(skipped) event\(skipped == 1 ? "" : "s") that lacked usable date or summary fields.")
        }
        if !diagnostics.isEmpty {
            reportNotes.append("Retained unknown calendar properties privately for diagnostics without showing raw data in the main schedule.")
        }
        reportNotes.append("Academic-calendar exceptions remain the verified Fall 2026 Texas A&M rules bundled with the app.")

        return (bundle, CalendarImportReport(
            sourceName: sourceName,
            courseCount: courses.count,
            recurringMeetingCount: patterns.count,
            oneTimeEventCount: oneTimeEvents.count,
            normalizedAnchorCount: normalizedAnchors,
            notes: reportNotes
        ))
    }

    private func unfold(_ text: String) -> [String] {
        var result: [String] = []
        for rawLine in text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !result.isEmpty {
                result[result.count - 1] += String(line.dropFirst())
            } else {
                result.append(line)
            }
        }
        return result
    }

    private func splitEvents(_ lines: [String]) -> [[String]] {
        var blocks: [[String]] = []
        var current: [String]?
        for line in lines {
            if line.uppercased() == "BEGIN:VEVENT" {
                current = []
            } else if line.uppercased() == "END:VEVENT" {
                if let current { blocks.append(current) }
                current = nil
            } else if current != nil {
                current?.append(line)
            }
        }
        return blocks
    }

    private func parseProperty(_ line: String) -> ICSProperty? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let left = String(line[..<colon])
        let pieces = left.split(separator: ";", omittingEmptySubsequences: false)
        guard let rawName = pieces.first else { return nil }
        var parameters: [String: String] = [:]
        for piece in pieces.dropFirst() {
            let pair = piece.split(separator: "=", maxSplits: 1)
            if pair.count == 2 {
                parameters[String(pair[0]).uppercased()] = String(pair[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        return ICSProperty(
            name: String(rawName).uppercased(),
            parameters: parameters,
            value: String(line[line.index(after: colon)...])
        )
    }

    private func parseRule(_ value: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: value.split(separator: ";").compactMap { pair in
            let pieces = pair.split(separator: "=", maxSplits: 1)
            guard pieces.count == 2 else { return nil }
            return (String(pieces[0]).uppercased(), String(pieces[1]))
        })
    }

    private func parseDateList(_ properties: [ICSProperty]) -> [String] {
        Array(Set(properties.flatMap { property in
            property.value.split(separator: ",").compactMap { raw -> String? in
                let dateValue = raw.split(separator: "/", maxSplits: 1).first.map(String.init) ?? String(raw)
                return parseDateTime(ICSProperty(name: property.name, parameters: property.parameters, value: dateValue))?.date
            }
        })).sorted()
    }

    private func parseDateTime(_ property: ICSProperty) -> (date: String, hour: Int, minute: Int)? {
        let digits = property.value.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }
        let values = Array(digits)
        guard
            let year = Int(String(values[0..<4])),
            let month = Int(String(values[4..<6])),
            let day = Int(String(values[6..<8]))
        else { return nil }

        guard digits.count >= 12 else {
            return (String(format: "%04d-%02d-%02d", year, month, day), 0, 0)
        }
        guard
            let hour = Int(String(values[8..<10])),
            let minute = Int(String(values[10..<12]))
        else { return nil }

        let sourceTimeZone: TimeZone
        if property.value.uppercased().hasSuffix("Z") {
            sourceTimeZone = .gmt
        } else if let identifier = property.parameters["TZID"], let zone = TimeZone(identifier: identifier) {
            sourceTimeZone = zone
        } else {
            sourceTimeZone = campusTimeZone
        }

        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceTimeZone
        guard let absoluteDate = sourceCalendar.date(from: DateComponents(
            timeZone: sourceTimeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )) else { return nil }

        var campusCalendar = Calendar(identifier: .gregorian)
        campusCalendar.timeZone = campusTimeZone
        let components = campusCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: absoluteDate)
        guard
            let campusYear = components.year,
            let campusMonth = components.month,
            let campusDay = components.day,
            let campusHour = components.hour,
            let campusMinute = components.minute
        else { return nil }
        return (
            String(format: "%04d-%02d-%02d", campusYear, campusMonth, campusDay),
            campusHour,
            campusMinute
        )
    }

    private func weekday(for date: String) -> Weekday? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = campusTimeZone
        guard let value = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        return Weekday(calendarWeekday: calendar.component(.weekday, from: value))
    }

    private func diagnosticValues(from values: [String: [ICSProperty]]) -> [String: String] {
        let handled: Set<String> = [
            "UID", "SUMMARY", "DTSTART", "DTEND", "RRULE", "EXDATE", "RDATE", "LOCATION", "DESCRIPTION",
            "DTSTAMP", "CREATED", "LAST-MODIFIED", "SEQUENCE", "STATUS", "TRANSP"
        ]
        return values.reduce(into: [String: String]()) { result, entry in
            guard !handled.contains(entry.key) else { return }
            let combined = entry.value.prefix(3).map(\.value).joined(separator: " | ")
            if let safeValue = combined.prefix(500).nonempty { result[entry.key] = String(safeValue) }
        }
    }

    private func unescapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private func course(from summary: String) -> Course {
        let canonical = summary.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let known = ScheduleSeed.courses.first(where: { $0.id == canonical }) { return known }

        let parts = canonical.split(separator: "-")
        let code = parts.count >= 2 ? "\(parts[0]) \(parts[1])" : canonical.replacingOccurrences(of: "-", with: " ")
        let section = parts.count >= 3 ? String(parts[2]) : ""
        return Course(
            id: canonical,
            code: code,
            section: section,
            title: "Course title not included",
            credits: 0,
            catalogSummary: "This imported calendar event did not include catalog metadata.",
            colorHex: fallbackColor(for: canonical),
            symbol: "book.closed.fill"
        )
    }

    private func fallbackColor(for value: String) -> String {
        let palette = ["2B67B2", "287D8E", "57784B", "8A63B8", "C46D2E", "A14B68"]
        let index = value.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % palette.count }
        return palette[index]
    }
}

private struct ICSProperty: Sendable {
    let name: String
    let parameters: [String: String]
    let value: String
}

enum ICSImportError: LocalizedError {
    case fileTooLarge
    case invalidEncoding
    case noEvents
    case noUsableEvents

    var errorDescription: String? {
        switch self {
        case .fileTooLarge: "The calendar is larger than the 2 MB safety limit."
        case .invalidEncoding: "The calendar is not valid UTF-8 text."
        case .noEvents: "No calendar events were found."
        case .noUsableEvents: "The calendar did not contain usable class meetings."
        }
    }
}

private extension String {
    var nonempty: String? { isEmpty ? nil : self }
}

private extension Substring {
    var nonempty: Substring? { isEmpty ? nil : self }
}
