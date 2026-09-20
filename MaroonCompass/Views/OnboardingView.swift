import SwiftUI

struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.accent, AppTheme.deepBlue, Color.black.opacity(0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "location.north.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(AppTheme.gold)
                        Text("Maroon Compass")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text("Your Fall 2026 schedule and campus, organized around what comes next.")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    HStack(spacing: 12) {
                        StatTile(value: "\(store.engine.courses.count)", label: "courses")
                        StatTile(value: "\(store.totalCredits)", label: "credits")
                        StatTile(value: "\(store.engine.patterns.count)", label: "weekly meetings")
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Schedule loaded", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                        ForEach(store.engine.courses) { course in
                            HStack(spacing: 12) {
                                CourseGlyph(course: course, size: 34)
                                Text(course.displayCode)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(course.credits) cr")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }
                    }
                    .padding(18)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(AppTheme.gold)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Classrooms verified")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Your Howdy registration supplied each CRN, section, instructor, building, room, and meeting time.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.title2)
                            .foregroundStyle(AppTheme.gold)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Build your personal plan")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Add lunch, study sessions, sleep, work, and other routines around protected class meetings.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }

                    VStack(spacing: 10) {
                        Button {
                            store.selectedTab = .schedule
                            store.completeOnboarding()
                            dismiss()
                        } label: {
                            Label("Explore my schedule", systemImage: "calendar.badge.checkmark")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundStyle(AppTheme.accent)

                        Button {
                            store.completeOnboarding()
                            dismiss()
                        } label: {
                            Text("Go to Today")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.78))
                    }

                    Text("Unofficial student companion · Schedule data stays on this device")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                }
                .padding(24)
                .padding(.top, 24)
            }
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold()).foregroundStyle(.white)
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.64))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
