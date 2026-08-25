import Foundation

enum ScheduleSeed {
    static let term = Term(
        institution: "Texas A&M University",
        campus: "College Station",
        name: "Fall 2026",
        firstClassDate: "2026-08-24",
        lastClassDate: "2026-12-03",
        finalsStartDate: "2026-12-07",
        finalsEndDate: "2026-12-10",
        timeZoneIdentifier: "America/Chicago"
    )

    static let courses: [Course] = [
        Course(
            id: "CHEM-107-504",
            code: "CHEM 107",
            section: "504",
            title: "General Chemistry for Engineering Students",
            credits: 3,
            catalogSummary: "Chemistry concepts and principles with an emphasis on engineering context and practical applications.",
            colorHex: "C46D2E",
            symbol: "atom"
        ),
        Course(
            id: "CHEM-117-541",
            code: "CHEM 117",
            section: "541",
            title: "Engineering Chemistry Laboratory",
            credits: 1,
            catalogSummary: "Laboratory applications of chemistry concepts relevant to engineering and technology.",
            colorHex: "D88B45",
            symbol: "flask.fill"
        ),
        Course(
            id: "ENGR-102-505",
            code: "ENGR 102",
            section: "505",
            title: "Engineering Lab I – Computation",
            credits: 2,
            catalogSummary: "Computer applications for engineers, problem solving, software design, debugging, ethics, and pathways to success.",
            colorHex: "287D8E",
            symbol: "chevron.left.forwardslash.chevron.right"
        ),
        Course(
            id: "FYEX-101-537",
            code: "FYEX 101",
            section: "537",
            title: "First Year Experience",
            credits: 0,
            catalogSummary: "Self-efficacy, engagement in learning, purpose, and integration into the university community.",
            colorHex: "8A63B8",
            symbol: "person.3.fill"
        ),
        Course(
            id: "MATH-151-531",
            code: "MATH 151",
            section: "531",
            title: "Engineering Mathematics I",
            credits: 4,
            catalogSummary: "Coordinates, vectors, analytic geometry, functions, limits, derivatives, integration, and computer algebra.",
            colorHex: "2B67B2",
            symbol: "function"
        ),
        Course(
            id: "POLS-207-502",
            code: "POLS 207",
            section: "502",
            title: "State and Local Government",
            credits: 3,
            catalogSummary: "State and local government and politics, with special reference to the constitution and politics of Texas.",
            colorHex: "57784B",
            symbol: "building.columns.fill"
        )
    ]

    static let patterns: [MeetingPattern] = [
        MeetingPattern(id: "52dfe775-292f-4166-a87f-9fb574d05e0b", courseID: "CHEM-107-504", weekdays: [.tuesday, .thursday], startHour: 8, startMinute: 0, endHour: 9, endMinute: 15, sourceUntilUTC: "2026-12-10T15:15:00Z", sourceLocationText: "ILCB · 113", sourceNotes: "Instructor: Sungyub Han"),
        MeetingPattern(id: "375e47cc-d616-4cdb-99e1-b159b2ceefc7", courseID: "CHEM-117-541", weekdays: [.tuesday], startHour: 11, startMinute: 10, endHour: 14, endMinute: 0, sourceUntilUTC: "2026-12-10T20:00:00Z", sourceLocationText: "ILSQ · E311", sourceNotes: "Instructor: Zachary Martinez"),
        MeetingPattern(id: "021400c7-8ea4-4f5a-a69e-4e7cadec98fa", courseID: "ENGR-102-505", weekdays: [.monday], startHour: 17, startMinute: 10, endHour: 18, endMinute: 0, sourceUntilUTC: "2026-12-11T00:00:00Z", sourceLocationText: "ZACH · 353", sourceNotes: "Instructor: Craig Spears"),
        MeetingPattern(id: "59e3847c-c41f-47cf-b99f-a5529eda24b9", courseID: "ENGR-102-505", weekdays: [.wednesday], startHour: 17, startMinute: 10, endHour: 19, endMinute: 0, sourceUntilUTC: "2026-12-11T01:00:00Z", sourceLocationText: "ZACH · 353", sourceNotes: "Instructor: Craig Spears"),
        MeetingPattern(id: "25571d5d-ab8c-408d-81b3-f2b6553574b3", courseID: "ENGR-102-505", weekdays: [.monday], startHour: 18, startMinute: 1, endHour: 19, endMinute: 0, sourceUntilUTC: "2026-12-11T01:00:00Z", sourceLocationText: "ZACH · 353", sourceNotes: "Instructor: Craig Spears"),
        MeetingPattern(id: "ad304b0d-58d2-44e0-af37-1f3ead149fee", courseID: "FYEX-101-537", weekdays: [.monday], startHour: 15, startMinute: 0, endHour: 15, endMinute: 50, sourceUntilUTC: "2026-12-10T21:50:00Z", sourceLocationText: "BLOC · 105", sourceNotes: "Instructor: Susan Owen"),
        MeetingPattern(id: "117116d5-28bf-4d80-bdda-15d648ae23bc", courseID: "MATH-151-531", weekdays: [.tuesday, .thursday], startHour: 15, startMinute: 55, endHour: 17, endMinute: 10, sourceUntilUTC: "2026-12-10T23:10:00Z", sourceLocationText: "HELD · 100", sourceNotes: "Instructor: Christopher Sze"),
        MeetingPattern(id: "0abe17c7-e4fd-44a2-bf00-5499b655ddcc", courseID: "MATH-151-531", weekdays: [.monday, .wednesday], startHour: 11, startMinute: 30, endHour: 12, endMinute: 20, sourceUntilUTC: "2026-12-10T18:20:00Z", sourceLocationText: "BLOC · 123", sourceNotes: "Instructor: Christopher Sze"),
        MeetingPattern(id: "a132c235-725e-42e2-9df5-d47d3c06680c", courseID: "POLS-207-502", weekdays: [.monday, .wednesday, .friday], startHour: 9, startMinute: 10, endHour: 10, endMinute: 0, sourceUntilUTC: "2026-12-10T16:00:00Z", sourceLocationText: "ILCB · 113", sourceNotes: "Instructor: Dwight Roblyer")
    ]

    static let oneTimeEvents: [OneTimeEvent] = [
        OneTimeEvent(id: "64574d25-5887-4949-9843-fe709564f0ce", courseID: "MATH-151-531", date: "2026-09-17", startHour: 17, startMinute: 30, endHour: 18, endMinute: 45, title: "MATH 151 exam", sourceLocationText: "HECC · 203", sourceNotes: "Instructor: Christopher Sze"),
        OneTimeEvent(id: "e1211fb3-71cd-4244-9f33-db890053614d", courseID: "MATH-151-531", date: "2026-10-22", startHour: 17, startMinute: 30, endHour: 18, endMinute: 45, title: "MATH 151 exam", sourceLocationText: "HECC · 203", sourceNotes: "Instructor: Christopher Sze"),
        OneTimeEvent(id: "e862bc29-8d2e-4822-b590-c7e4ffd3b25f", courseID: "MATH-151-531", date: "2026-11-19", startHour: 17, startMinute: 30, endHour: 18, endMinute: 45, title: "MATH 151 exam", sourceLocationText: "HECC · 203", sourceNotes: "Instructor: Christopher Sze")
    ]

    static let exceptions: [AcademicException] = [
        AcademicException(date: "2026-08-28", kind: .milestone, title: "Add/drop deadline", detail: "Last day to add or drop fall courses."),
        AcademicException(date: "2026-09-07", kind: .noClass, title: "Labor Day", detail: "No classes."),
        AcademicException(date: "2026-09-09", kind: .milestone, title: "Official census date", detail: "Fall semester census date."),
        AcademicException(date: "2026-09-21", kind: .milestone, title: "Curriculum deadline", detail: "Undergraduate change-of-curriculum request deadline."),
        AcademicException(date: "2026-09-25", kind: .milestone, title: "Graduation application deadline", detail: "Apply for December graduation without a late fee."),
        AcademicException(date: "2026-10-12", kind: .milestone, title: "Mid-semester grades", detail: "Mid-semester grades are due at noon."),
        AcademicException(date: "2026-11-04", kind: .milestone, title: "Graduation application closes", detail: "Last day to apply online for December 2026 graduation."),
        AcademicException(date: "2026-11-05", kind: .milestone, title: "Spring preregistration begins", detail: "Spring 2027 preregistration runs through November 20."),
        AcademicException(date: "2026-11-16", kind: .milestone, title: "Q-drop deadline", detail: "Q-drop and withdrawal deadline at 5:00 PM."),
        AcademicException(date: "2026-11-18", kind: .milestone, title: "Bonfire Remembrance Day", detail: "Campus observance; regular classes continue."),
        AcademicException(date: "2026-11-25", kind: .noClass, title: "Reading day", detail: "No classes."),
        AcademicException(date: "2026-11-26", kind: .noClass, title: "Thanksgiving holiday", detail: "No classes."),
        AcademicException(date: "2026-11-27", kind: .noClass, title: "Thanksgiving holiday", detail: "No classes."),
        AcademicException(date: "2026-12-01", kind: .redefinedFriday, title: "Friday classes meet", detail: "The Friday schedule replaces the normal Tuesday schedule."),
        AcademicException(date: "2026-12-02", kind: .milestone, title: "No regular exams", detail: "The university's no-regular-exams period begins; classes continue."),
        AcademicException(date: "2026-12-03", kind: .milestone, title: "Last class day", detail: "Last day of fall semester classes."),
        AcademicException(date: "2026-12-04", kind: .noClass, title: "Reading day", detail: "No classes."),
        AcademicException(date: "2026-12-07", kind: .finals, title: "Final exams begin", detail: "Final exam times and locations have not been added."),
        AcademicException(date: "2026-12-08", kind: .finals, title: "Final examinations", detail: "Final exam times and locations have not been added."),
        AcademicException(date: "2026-12-09", kind: .finals, title: "Final examinations", detail: "Final exam times and locations have not been added."),
        AcademicException(date: "2026-12-10", kind: .finals, title: "Final examinations", detail: "Final exam times and locations have not been added.")
    ]

    static let resources: [ResourceContact] = [
        ResourceContact(id: "911", name: "Emergency", subtitle: "Police, fire, or medical emergency", phone: "911", url: nil, symbol: "sos.circle.fill", isEmergency: true),
        ResourceContact(id: "upd", name: "University Police", subtitle: "Non-emergency", phone: "979-845-2345", url: URL(string: "https://upd.tamu.edu/"), symbol: "shield.fill", isEmergency: false),
        ResourceContact(id: "uems", name: "University Emergency Medical Services", subtitle: "Non-emergency campus EMS", phone: "979-845-1525", url: URL(string: "https://ems.tamu.edu/"), symbol: "staroflife.fill", isEmergency: false),
        ResourceContact(id: "escort", name: "Corps Safety Escort", subtitle: "Verify current service hours", phone: "979-845-6789", url: URL(string: "https://www.tamu.edu/campus-community/campus-safety.html"), symbol: "figure.walk", isEmergency: false),
        ResourceContact(id: "dialanurse", name: "Dial-A-Nurse", subtitle: "After-hours non-emergency nurse advice", phone: "979-458-8379", url: URL(string: "https://uhs.tamu.edu/medical/index.html"), symbol: "phone.badge.waveform.fill", isEmergency: false),
        ResourceContact(id: "counseling", name: "Counseling after-hours support", subtitle: "Mental health support outside business hours", phone: "979-845-2700", url: URL(string: "https://uhs.tamu.edu/mental-health/"), symbol: "heart.text.square.fill", isEmergency: false),
        ResourceContact(id: "uhs", name: "University Health Services", subtitle: "Medical and mental health resources", phone: "979-458-4584", url: URL(string: "https://uhs.tamu.edu/"), symbol: "cross.case.fill", isEmergency: false),
        ResourceContact(id: "transport", name: "Transportation Help", subtitle: "Bus and transportation information", phone: "979-847-7433", url: URL(string: "https://transport.tamu.edu/"), symbol: "bus.fill", isEmergency: false),
        ResourceContact(id: "parking", name: "Parking Customer Assistance", subtitle: "Permits, lots, garages, and parking help", phone: "979-862-7275", url: URL(string: "https://transport.tamu.edu/about/contact.aspx"), symbol: "parkingsign.circle.fill", isEmergency: false),
        ResourceContact(id: "motorist", name: "Motorist Assistance", subtitle: "On-campus jump starts, air, or emergency fuel", phone: "979-845-0057", url: URL(string: "https://transport.tamu.edu/parking/motoristassist.aspx"), symbol: "car.badge.gearshape.fill", isEmergency: false),
        ResourceContact(id: "facilities", name: "AggieWorks", subtitle: "Facilities help and urgent issues", phone: "979-845-4311", url: URL(string: "https://facilities.tamu.edu/"), symbol: "wrench.and.screwdriver.fill", isEmergency: false),
        ResourceContact(id: "operator", name: "University Operator", subtitle: "Texas A&M directory assistance", phone: "979-845-3211", url: URL(string: "https://www.tamu.edu/contact.html"), symbol: "phone.connection.fill", isEmergency: false),
        ResourceContact(id: "food", name: "Food Resources", subtitle: "The 12th Can, Pocket Pantries, and meal support", phone: nil, url: URL(string: "https://studentlife.tamu.edu/support/food-resources/"), symbol: "basket.fill", isEmergency: false),
        ResourceContact(id: "libraries", name: "University Libraries", subtitle: "Study spaces, research help, and services", phone: nil, url: URL(string: "https://library.tamu.edu/"), symbol: "books.vertical.fill", isEmergency: false),
        ResourceContact(id: "academicsuccess", name: "StudyHub & Academic Support", subtitle: "Tutoring, supplemental instruction, and coaching", phone: nil, url: URL(string: "https://studyhub.tamu.edu/"), symbol: "graduationcap.fill", isEmergency: false),
        ResourceContact(id: "disability", name: "Disability Resources", subtitle: "Access coordination and accommodations", phone: nil, url: URL(string: "https://disability.tamu.edu/"), symbol: "accessibility.fill", isEmergency: false),
        ResourceContact(id: "studentassistance", name: "Student Assistance Services", subtitle: "Practical support for personal and academic concerns", phone: nil, url: URL(string: "https://studentlife.tamu.edu/support/studentcare/"), symbol: "person.crop.circle.badge.questionmark.fill", isEmergency: false),
        ResourceContact(id: "dining", name: "Aggie Dining", subtitle: "Official dining locations, plans, and information", phone: nil, url: URL(string: "https://www.tamu.edu/campus-community/dining.html"), symbol: "fork.knife", isEmergency: false),
        ResourceContact(id: "currentstudents", name: "Current Student Resources", subtitle: "Official university services and links", phone: nil, url: URL(string: "https://www.tamu.edu/current-students/"), symbol: "person.text.rectangle.fill", isEmergency: false)
    ]
}
