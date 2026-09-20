import SwiftUI

struct SurfaceCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .stroke(.primary.opacity(0.07), lineWidth: 0.5)
            }
    }
}

struct CourseGlyph: View {
    let course: Course
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: course.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(course.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct PersonalBlockGlyph: View {
    let category: PersonalBlockCategory
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct OccurrenceRow: View {
    let occurrence: ScheduleOccurrence
    let location: CourseLocation?
    let sourceLocationText: String?

    init(occurrence: ScheduleOccurrence, location: CourseLocation?, sourceLocationText: String? = nil) {
        self.occurrence = occurrence
        self.location = location
        self.sourceLocationText = sourceLocationText
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(CampusFormatters.time.string(from: occurrence.start))
                    .font(.subheadline.weight(.semibold))
                Text(CampusFormatters.time.string(from: occurrence.end))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(occurrence.course.tint)
                .frame(width: 4, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(occurrence.isSpecial ? occurrence.title : occurrence.course.code)
                        .font(.headline)
                    if occurrence.isSpecial {
                        Text("SPECIAL")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(occurrence.course.tint.opacity(0.12), in: Capsule())
                    }
                }
                let hasKnownLocation = location != nil || sourceLocationText != nil
                Label(
                    location.map { [$0.feature.abbreviation ?? $0.feature.name, $0.room].compactMap { $0 }.joined(separator: " · ") }
                        ?? sourceLocationText
                        ?? "Location not added",
                    systemImage: hasKnownLocation ? "mappin.and.ellipse" : "mappin.slash"
                )
                .font(.subheadline)
                .foregroundStyle(hasKnownLocation ? .primary : .secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .padding(.top, 5)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(occurrence.course.code), \(CampusFormatters.time.string(from: occurrence.start)) to \(CampusFormatters.time.string(from: occurrence.end)), \(location?.feature.name ?? sourceLocationText ?? "location not added")")
    }
}

struct PersonalBlockRow: View {
    let occurrence: PersonalBlockOccurrence
    var showsDisclosure = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .trailing, spacing: 3) {
                Text(CampusFormatters.time.string(from: occurrence.visibleStart))
                    .font(.subheadline.weight(.semibold))
                Text(CampusFormatters.time.string(from: occurrence.visibleEnd))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 72, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2)
                .fill(occurrence.block.category.tint)
                .frame(width: 4, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: occurrence.block.category.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(occurrence.block.category.tint)
                    Text(occurrence.block.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Text(occurrence.block.category.title)
                    if let location = occurrence.block.location, !location.isEmpty {
                        Text("·")
                        Text(location).lineLimit(1)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if occurrence.continuesFromPreviousDay || occurrence.continuesIntoNextDay {
                    Text(occurrence.continuesFromPreviousDay ? "Continues from yesterday" : "Continues tomorrow")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(occurrence.block.category.tint)
                }
            }
            Spacer(minLength: 0)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 5)
            }
        }
        .contentShape(Rectangle())
        .opacity(occurrence.block.isEnabled ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(occurrence.block.title), \(CampusFormatters.time.string(from: occurrence.visibleStart)) to \(CampusFormatters.time.string(from: occurrence.visibleEnd)), \(occurrence.block.category.title)")
    }
}

struct AcademicBanner: View {
    let item: AcademicException

    private var color: Color {
        switch item.kind {
        case .noClass: .orange
        case .redefinedFriday: .purple
        case .finals: AppTheme.accent
        case .milestone: .blue
        }
    }

    private var icon: String {
        switch item.kind {
        case .noClass: "moon.zzz.fill"
        case .redefinedFriday: "arrow.trianglehead.2.clockwise.rotate.90.calendar"
        case .finals: "pencil.and.list.clipboard"
        case .milestone: "flag.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: AppTheme.compactRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(AppTheme.accent)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct LoadingRow: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
