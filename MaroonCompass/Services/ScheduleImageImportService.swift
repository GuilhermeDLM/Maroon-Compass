import Foundation
import UIKit
import Vision

#if canImport(FoundationModels)
import FoundationModels
#endif

struct ScheduleImageImportResult: Sendable {
    let draft: ScheduleDraft
    let recognizedLineCount: Int
    let usedAppleIntelligence: Bool
}

enum ScheduleImageImportError: LocalizedError {
    case invalidImage
    case noText
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImage: "The selected image could not be opened. Try another screenshot or photo."
        case .noText: "I couldn't read text in this image. Try a clearer image or add the classes manually."
        case .imageTooLarge: "This image is too large to analyze. Try a smaller screenshot or photo."
        }
    }
}

struct ScheduleImageImportService: Sendable {
    private struct OCRLine: Sendable {
        let text: String
        let x: Double
        let y: Double
    }

    func analyze(_ imageData: Data, currentTerm: Term, useAppleIntelligence: Bool = true) async throws -> ScheduleImageImportResult {
        try Task.checkCancellation()
        guard imageData.count <= 20_000_000 else { throw ScheduleImageImportError.imageTooLarge }
        guard UIImage(data: imageData) != nil else { throw ScheduleImageImportError.invalidImage }

        let recognition = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try recognizeText(imageData)
        }
        let lines = try await withTaskCancellationHandler {
            try await recognition.value
        } onCancel: {
            recognition.cancel()
        }
        try Task.checkCancellation()
        guard !lines.isEmpty else { throw ScheduleImageImportError.noText }
        let text = lines.map(\.text).joined(separator: "\n")
        let ocrDraft = Self.parseRecognizedText(lines, currentTerm: currentTerm)

        var draft: ScheduleDraft?
        var usedIntelligence = false
        #if canImport(FoundationModels)
        if useAppleIntelligence, #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            do {
                let suggestion = try await interpretWithAppleIntelligence(
                    imageData: imageData,
                    recognizedText: text,
                    currentTerm: currentTerm
                )
                if let suggestion {
                    draft = Self.reconcile(suggestion, with: ocrDraft)
                    usedIntelligence = true
                }
            } catch {
                // OCR and manual review remain available when model generation fails.
            }
        }
        #endif

        if draft == nil {
            draft = ocrDraft
            draft?.notes.append("Apple Intelligence was unavailable or could not interpret this image. Review the OCR-based draft carefully.")
        }
        try Task.checkCancellation()
        return ScheduleImageImportResult(
            draft: draft!,
            recognizedLineCount: lines.count,
            usedAppleIntelligence: usedIntelligence
        )
    }

    private func recognizeText(_ data: Data) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(data: data).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return OCRLine(text: text, x: observation.boundingBox.minX, y: observation.boundingBox.midY)
        }.sorted { left, right in
            if abs(left.y - right.y) > 0.025 { return left.y > right.y }
            return left.x < right.x
        }
    }

    static func draftFromRecognizedLines(_ textLines: [String], currentTerm: Term) -> ScheduleDraft {
        let lines = textLines.enumerated().map { index, text in
            OCRLine(text: text, x: 0, y: Double(textLines.count - index))
        }
        return parseRecognizedText(lines, currentTerm: currentTerm)
    }

    /// OCR anchors course identity. A model can suggest missing fields, but it cannot add a
    /// duplicate or a course that was not supported by a readable course code in the image.
    static func reconcile(_ suggestion: ScheduleDraft, with ocr: ScheduleDraft) -> ScheduleDraft {
        guard !ocr.courses.isEmpty else { return suggestion }
        var result = ocr
        var matchedSuggestions: Set<Int> = []
        var omittedSuggestions = false
        let ocrIdentities = ocr.courses.compactMap { courseIdentity($0.code)?.code }

        for courseIndex in result.courses.indices {
            guard let identity = courseIdentity(result.courses[courseIndex].code) else { continue }
            let section = result.courses[courseIndex].section.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let repeatedCode = ocrIdentities.filter { $0 == identity.code }.count > 1
            guard let suggestionIndex = suggestion.courses.indices.first(where: { index in
                guard !matchedSuggestions.contains(index),
                      let candidate = courseIdentity(suggestion.courses[index].code),
                      candidate.code == identity.code else { return false }
                let suggestedSection = suggestion.courses[index].section.isEmpty
                    ? candidate.section
                    : suggestion.courses[index].section.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if repeatedCode && suggestedSection.isEmpty { return false }
                return section.isEmpty || suggestedSection.isEmpty || section == suggestedSection
            }) else { continue }

            matchedSuggestions.insert(suggestionIndex)
            let candidate = suggestion.courses[suggestionIndex]
            if result.courses[courseIndex].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.courses[courseIndex].title = candidate.title
            }
            if result.courses[courseIndex].section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.courses[courseIndex].section = candidate.section.isEmpty
                    ? courseIdentity(candidate.code)?.section ?? ""
                    : candidate.section
            }
            if result.courses[courseIndex].meetings.count == candidate.meetings.count {
                for meetingIndex in result.courses[courseIndex].meetings.indices {
                    let suggested = candidate.meetings[meetingIndex]
                    var meeting = result.courses[courseIndex].meetings[meetingIndex]
                    if meeting.weekdays.isEmpty { meeting.weekdays = suggested.weekdays }
                    if meeting.startTime.isEmpty { meeting.startTime = suggested.startTime }
                    if meeting.endTime.isEmpty { meeting.endTime = suggested.endTime }
                    if meeting.buildingCode.isEmpty { meeting.buildingCode = suggested.buildingCode }
                    if meeting.room.isEmpty { meeting.room = suggested.room }
                    result.courses[courseIndex].meetings[meetingIndex] = meeting
                }
            }
        }

        omittedSuggestions = matchedSuggestions.count < suggestion.courses.count
        result.notes.append("Apple Intelligence suggested missing details. Check every class before confirming.")
        if omittedSuggestions {
            result.notes.append("Some AI suggestions did not match readable course codes and were left out. Check the image for missing classes.")
        }
        return result
    }

    private static func courseIdentity(_ raw: String) -> (code: String, section: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pattern = #"^([A-Z]{2,5})\s*[- ]?\s*(\d{3,4})(?:\s*[- ]\s*(\d{3}))?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)),
              let subjectRange = Range(match.range(at: 1), in: trimmed),
              let numberRange = Range(match.range(at: 2), in: trimmed) else { return nil }
        let section = Range(match.range(at: 3), in: trimmed).map { String(trimmed[$0]) } ?? ""
        return (String(trimmed[subjectRange]) + String(trimmed[numberRange]), section)
    }

    private static func parseRecognizedText(_ lines: [OCRLine], currentTerm: Term) -> ScheduleDraft {
        var draft = ScheduleDraft(
            termName: currentTerm.name,
            firstClassDate: currentTerm.firstClassDate,
            lastClassDate: currentTerm.lastClassDate
        )
        let courseExpression = try! NSRegularExpression(pattern: #"^\s*([A-Z]{2,5})\s*[- ]?\s*(\d{3,4})(?:\s*[- ]\s*(\d{3}))?\b"#)
        let timeExpression = try! NSRegularExpression(pattern: #"(?i)(\d{1,2}:\d{2}\s*(?:AM|PM)?)[\s\-–]+(\d{1,2}:\d{2}\s*(?:AM|PM)?)"#)
        let locationExpression = try! NSRegularExpression(pattern: #"\b([A-Z]{2,6})\s+([A-Z0-9]*\d[A-Z0-9-]{0,5})\b"#)
        var currentCourseIndex: Int?
        var foundLocation = false

        for line in lines {
            let upper = line.text.uppercased()
            let range = NSRange(upper.startIndex..<upper.endIndex, in: upper)
            let timeMatch = timeExpression.firstMatch(in: line.text, range: NSRange(line.text.startIndex..<line.text.endIndex, in: line.text))
            if let match = courseExpression.firstMatch(in: upper, range: range),
               let subjectRange = Range(match.range(at: 1), in: upper),
               let numberRange = Range(match.range(at: 2), in: upper) {
                let code = "\(upper[subjectRange]) \(upper[numberRange])"
                let section = Range(match.range(at: 3), in: upper).map { String(upper[$0]) } ?? ""
                if let existing = draft.courses.firstIndex(where: { $0.code == code && $0.section == section }) {
                    currentCourseIndex = existing
                } else {
                    var course = ScheduleDraftCourse()
                    course.code = code
                    course.section = section
                    if let end = Range(match.range, in: line.text)?.upperBound {
                        let titleEnd = timeMatch.flatMap { Range($0.range, in: line.text)?.lowerBound } ?? line.text.endIndex
                        let candidate = String(line.text[end..<titleEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                        course.title = candidate.replacingOccurrences(
                            of: #"(?i)(?:\s+(?:MON|MONDAY|TUE|TUESDAY|WED|WEDNESDAY|THU|THURSDAY|FRI|FRIDAY|MWF|TR|TTH|LAB|LECTURE|RECITATION))+$"#,
                            with: "", options: .regularExpression
                        ).trimmingCharacters(in: .whitespacesAndNewlines)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "-–· "))
                    }
                    course.meetings = []
                    draft.courses.append(course)
                    currentCourseIndex = draft.courses.count - 1
                }
            }

            let days = Self.weekdays(in: upper)
            guard let currentCourseIndex,
                  !days.isEmpty,
                  let timeMatch,
                  let startRange = Range(timeMatch.range(at: 1), in: line.text),
                  let endRange = Range(timeMatch.range(at: 2), in: line.text) else { continue }
            var meeting = ScheduleDraftMeeting()
            meeting.startTime = String(line.text[startRange]).trimmingCharacters(in: .whitespaces)
            meeting.endTime = String(line.text[endRange]).trimmingCharacters(in: .whitespaces)
            meeting.weekdays = days
            if upper.contains("LAB") { meeting.kind = .lab }
            else if upper.contains("RECITATION") { meeting.kind = .recitation }
            if let end = Range(timeMatch.range, in: line.text)?.upperBound {
                let tail = String(line.text[end...]).uppercased()
                let tailRange = NSRange(tail.startIndex..<tail.endIndex, in: tail)
                if let location = locationExpression.firstMatch(in: tail, range: tailRange),
                   let buildingRange = Range(location.range(at: 1), in: tail),
                   let roomRange = Range(location.range(at: 2), in: tail) {
                    let building = String(tail[buildingRange])
                    if !["ROOM", "BLDG", "BUILDING", "CLASS", "CRN", "SECTION", "CREDITS", "UNITS"].contains(building) {
                        meeting.buildingCode = building
                        meeting.room = String(tail[roomRange])
                        foundLocation = true
                    }
                }
            }
            if !draft.courses[currentCourseIndex].meetings.contains(where: {
                $0.weekdays == meeting.weekdays && $0.startTime == meeting.startTime &&
                $0.endTime == meeting.endTime && $0.kind == meeting.kind &&
                $0.buildingCode == meeting.buildingCode && $0.room == meeting.room
            }) {
                draft.courses[currentCourseIndex].meetings.append(meeting)
            }
        }
        if draft.courses.isEmpty {
            draft.courses = [ScheduleDraftCourse()]
            draft.notes.append("No course code was recognized. Add the course details manually.")
        }
        for index in draft.courses.indices where draft.courses[index].meetings.isEmpty {
            draft.courses[index].meetings = [ScheduleDraftMeeting()]
        }
        if foundLocation {
            draft.notes.append("Building and room text came from OCR. Compare similar-looking letters and numbers with the image.")
        }
        return draft
    }

    private static func weekdays(in text: String) -> Set<Weekday> {
        let words = text.uppercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        var result: Set<Weekday> = []
        for word in words {
            switch word {
            case "MWF": result.formUnion([.monday, .wednesday, .friday])
            case "TR", "TTH": result.formUnion([.tuesday, .thursday])
            case "M", "MO", "MON", "MONDAY": result.insert(.monday)
            case "T", "TU", "TUE", "TUESDAY": result.insert(.tuesday)
            case "W", "WE", "WED", "WEDNESDAY": result.insert(.wednesday)
            case "R", "TH", "THU", "THURSDAY": result.insert(.thursday)
            case "F", "FR", "FRI", "FRIDAY": result.insert(.friday)
            case "SA", "SAT", "SATURDAY": result.insert(.saturday)
            case "SU", "SUN", "SUNDAY": result.insert(.sunday)
            default: break
            }
        }
        return result
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct GeneratedSchedule {
    @Guide(description: "Only courses visibly present in the image; never invent missing information")
    var courses: [GeneratedCourse]
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedCourse {
    var courseCode: String
    var courseName: String
    var section: String
    var meetings: [GeneratedMeeting]
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedMeeting {
    @Guide(description: "Comma-separated two-letter weekdays, for example MO,WE,FR; empty if unknown")
    var days: String
    @Guide(description: "Start time with AM or PM, or two-digit 24-hour time; empty if unknown")
    var startTime: String
    @Guide(description: "End time with AM or PM, or two-digit 24-hour time; empty if unknown")
    var endTime: String
    var buildingCode: String
    var room: String
    var meetingType: String
}

@available(iOS 26.0, *)
private func interpretWithAppleIntelligence(
    imageData: Data,
    recognizedText: String,
    currentTerm: Term
) async throws -> ScheduleDraft? {
    let instructions = """
        Extract a student's class schedule for review. Use only information visible in the image or OCR text.
        Never guess a course, weekday, time, section, building, or room. Use an empty string for unknown fields.
        Preserve multiple meetings for one course. Ignore unrelated screen text. Do not infer semester dates.
        """
    let session = LanguageModelSession(instructions: instructions)
    let response: LanguageModelSession.Response<GeneratedSchedule>
    if #available(iOS 27.0, *), let image = UIImage(data: imageData)?.cgImage {
        response = try await session.respond(generating: GeneratedSchedule.self) {
            "Extract the schedule using this image and the OCR text below."
            Attachment(image)
            recognizedText
        }
    } else {
        response = try await session.respond(to: "Extract the schedule from this OCR text:\n\(recognizedText)", generating: GeneratedSchedule.self)
    }
    guard !response.content.courses.isEmpty else { return nil }

    var draft = ScheduleDraft(
        termName: currentTerm.name,
        firstClassDate: currentTerm.firstClassDate,
        lastClassDate: currentTerm.lastClassDate
    )
    for generated in response.content.courses {
        var course = ScheduleDraftCourse()
        course.code = generated.courseCode
        course.title = generated.courseName
        course.section = generated.section
        course.meetings = generated.meetings.map { item in
            var meeting = ScheduleDraftMeeting()
            meeting.weekdays = Set(item.days.uppercased().split(separator: ",").compactMap { Weekday(rawValue: String($0).trimmingCharacters(in: .whitespaces)) })
            meeting.startTime = item.startTime
            meeting.endTime = item.endTime
            meeting.buildingCode = item.buildingCode
            meeting.room = item.room
            meeting.kind = MeetingKind(rawValue: item.meetingType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .other
            return meeting
        }
        if course.meetings.isEmpty { course.meetings = [ScheduleDraftMeeting()] }
        draft.courses.append(course)
    }
    draft.notes.append("Apple Intelligence suggested these fields. Check every class before confirming.")
    return draft
}
#endif
