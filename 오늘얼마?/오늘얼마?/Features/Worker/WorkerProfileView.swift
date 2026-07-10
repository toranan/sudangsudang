import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct WorkerProfileView: View {
    struct WorkerRow: Decodable {
        let id: UUID
        let store_id: UUID
        let is_active: Bool?
        let joined_at: String?
        let stores: StoreName?
    }

    struct StoreName: Decodable {
        let name: String
    }

    struct CareerEntry: Identifiable {
        let id: UUID
        let storeName: String
        let periodText: String
    }

    @State private var profileName: String = "알바생"
    @State private var profilePhone: String = ""
    @State private var profileEmail: String = ""

    @State private var linkedStores: [String] = []
    @State private var careerEntries: [CareerEntry] = []
    @State private var growthLevel: WorkerGrowthLevel = .seedling
    @State private var hasSincerityMark = false
    @State private var ownerRatingText: String = "사장평가 미입력"
    @State private var careerDurationText: String = "0일"

    @State private var loadError: String?
    @State private var isLoading = false
    @State private var isUserRefreshing = false
    @State private var isPresentingProfileEdit = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    characterHeaderCard

                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Text(profileName)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                                if hasSincerityMark {
                                    Image("sincerity_mark")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 24, height: 24)
                                }
                                Spacer(minLength: 0)
                            }

                            if !profilePhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(profilePhone)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                            }
                            if !profileEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(profileEmail)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                            }

                            Button("프로필 수정") {
                                isPresentingProfileEdit = true
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        .appCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "내 경력")

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("성장 단계")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                Spacer()
                                Text(growthLevel.rawValue)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                            }

                            HStack {
                                Text("성실마크")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                Spacer()
                                if hasSincerityMark {
                                    StatusPill(text: "부여됨", color: .appPositive)
                                } else {
                                    Text("미부여")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                }
                            }

                            HStack {
                                Text("사장평가 평균")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                Spacer()
                                Text(ownerRatingText)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                            }

                            HStack {
                                Text("연결 매장")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                Spacer()
                                Text("\(linkedStores.count)개")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                            }

                            HStack {
                                Text("총 근속")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                Spacer()
                                Text(careerDurationText)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                            }
                        }
                        .appCard()

                        if careerEntries.isEmpty {
                            Text("연결된 매장이 없어요.")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                                .appCard()
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(careerEntries) { entry in
                                    HStack {
                                        Text(entry.storeName)
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(.appTextPrimary)
                                        Spacer()
                                        Text(entry.periodText)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(.appTextSecondary)
                                    }
                                }
                            }
                            .appCard()
                        }

                        ShareLink(item: careerSubmissionText) {
                            Label("경력 제출하기", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "계정")
                        Button("로그아웃") {
                            Task {
                                await SupabaseManager.shared.signOut()
                                NotificationCenter.default.post(name: .didLogout, object: nil)
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    if let loadError {
                        Text(loadError)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appWarning)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .refreshable {
                await refreshFromUser()
            }
            .refreshStatusOverlay(isVisible: isUserRefreshing)
        }
        .sheet(isPresented: $isPresentingProfileEdit) {
            ProfileCompletionSheet(
                context: .init(
                    title: "프로필 수정",
                    message: "이름/전화번호를 수정할 수 있어요.",
                    primaryActionTitle: "저장",
                    showsSkip: false
                ),
                initialName: profileName,
                initialPhone: profilePhone,
                onSave: { name, phone in
                    Task {
                        #if canImport(Supabase)
                        do {
                            let userId = try await SupabaseManager.shared.currentUserId()
                            try await SupabaseManager.shared.patchProfile(id: userId, name: name, phone: phone)
                        } catch {
                            // ignore
                        }
                        #endif
                        await loadData()
                    }
                },
                onSkip: nil
            )
        }
        .task {
            await loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didAcceptInvite)) { _ in
            Task { await loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await loadData() }
        }
    }

    @MainActor
    private func refreshFromUser() async {
        isUserRefreshing = true
        defer { isUserRefreshing = false }
        await loadData()
    }

    @MainActor
    private func loadData() async {
        #if canImport(Supabase)
        isLoading = true
        defer { isLoading = false }
        do {
            let userId = try await SupabaseManager.shared.currentUserId()
            do {
                try await WorkerAutoRetirement.processForUser(userId: userId)
            } catch {
                if AppErrorMessage.isCancellation(error) {
                    return
                }
                #if DEBUG
                print("DEBUG: auto retirement (worker profile) failed: \(error.localizedDescription)")
                #endif
            }
            let snapshot = try await SupabaseManager.shared.fetchProfileSnapshot(id: userId)
            let trimmedName = (snapshot.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            profileName = trimmedName.isEmpty ? "알바생" : trimmedName
            profilePhone = snapshot.phone ?? ""
            profileEmail = snapshot.email ?? ""

            let workers: [WorkerRow] = try await SupabaseManager.shared
                .client
                .from("workers")
                .select("id,store_id,is_active,joined_at,stores(name)")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            struct LatestLogRow: Decodable {
                let worker_id: UUID
                let check_in_at: String
                let status: String?
            }
            let inactiveWorkerIds = workers
                .filter { !($0.is_active ?? true) }
                .map(\.id)
            var latestCheckInByWorker: [UUID: Date] = [:]
            if !inactiveWorkerIds.isEmpty {
                let logRows: [LatestLogRow] = try await SupabaseManager.shared
                    .client
                    .from("work_logs")
                    .select("worker_id,check_in_at,status")
                    .in("worker_id", values: inactiveWorkerIds.map(\.uuidString))
                    .order("check_in_at", ascending: false)
                    .execute()
                    .value
                for row in logRows {
                    if row.status == "rejected" { continue }
                    if latestCheckInByWorker[row.worker_id] != nil { continue }
                    if let checkIn = parseISODate(row.check_in_at) {
                        latestCheckInByWorker[row.worker_id] = checkIn
                    }
                }
            }

            let builtEntries = workers.map { worker in
                let startDate = parseJoinedAt(worker.joined_at)
                let isActive = worker.is_active ?? true
                let endDate = isActive ? nil : latestCheckInByWorker[worker.id]
                return CareerEntry(
                    id: worker.id,
                    storeName: worker.stores?.name ?? "매장",
                    periodText: formatWorkPeriod(startDate: startDate, endDate: endDate, isActive: isActive)
                )
            }
            .sorted { lhs, rhs in
                let lhsStart = workers.first(where: { $0.id == lhs.id }).flatMap { parseJoinedAt($0.joined_at) } ?? .distantPast
                let rhsStart = workers.first(where: { $0.id == rhs.id }).flatMap { parseJoinedAt($0.joined_at) } ?? .distantPast
                return lhsStart > rhsStart
            }

            careerEntries = builtEntries
            linkedStores = Array(Set(builtEntries.map(\.storeName))).sorted()
            let earliestJoinedAt = workers.compactMap { parseJoinedAt($0.joined_at) }.min()
            careerDurationText = formatCareerDuration(from: earliestJoinedAt)
            let summary = try await buildOverallSummary(workers: workers)
            growthLevel = summary.level
            hasSincerityMark = summary.hasSincerityMark
            ownerRatingText = summary.ownerRating.map { String(format: "%.1f점", $0) } ?? "사장평가 미입력"
            loadError = nil
        } catch {
            if AppErrorMessage.isCancellation(error) { return }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private var growthCharacterImageName: String {
        switch growthLevel {
        case .seedling:
            return "howmuch1"
        case .junior:
            return "howmuch2"
        case .pro:
            return "howmuch3"
        case .ace:
            return "howmuch4"
        case .veteran:
            return "howmuch5"
        }
    }

    private var careerSubmissionText: String {
        let careerLines = careerEntries.isEmpty
            ? "- 등록된 근무 이력이 없습니다."
            : careerEntries.map { "- \($0.storeName): \($0.periodText)" }.joined(separator: "\n")

        return [
            "수당수당 경력 요약",
            "",
            "이름: \(profileName)",
            "경력일: \(careerDurationText)",
            "",
            "매장별 근무기간",
            careerLines
        ].joined(separator: "\n")
    }

    private func formatCareerDuration(from startDate: Date?) -> String {
        guard let startDate else { return "0일" }
        let calendar = AppTime.calendar
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: Date())
        let totalDays = max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)

        if totalDays >= 365 {
            let years = totalDays / 365
            let months = (totalDays % 365) / 30
            return months > 0 ? "\(years)년 \(months)개월" : "\(years)년"
        }
        if totalDays >= 30 {
            let months = totalDays / 30
            let days = totalDays % 30
            return days > 0 ? "\(months)개월 \(days)일" : "\(months)개월"
        }
        return "\(totalDays)일"
    }

    private func formatWorkPeriod(startDate: Date?, endDate: Date?, isActive: Bool) -> String {
        let startText = formatDate(startDate) ?? "-"
        if isActive {
            return "\(startText) ~ 근무중"
        }
        let endText = formatDate(endDate) ?? startText
        return "\(startText) ~ \(endText)"
    }

    private func formatDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = AppTime.displayFormatter("yyyy.MM.dd")
        return formatter.string(from: date)
    }

    private var characterHeaderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "내 프로필")
            VStack(alignment: .center, spacing: 8) {
                Image(growthCharacterImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
            }
            .appCard()
        }
    }

    @MainActor
    private func buildOverallSummary(workers: [WorkerRow]) async throws -> WorkerEvaluationSummary {
        #if canImport(Supabase)
        guard !workers.isEmpty else {
            return WorkerEvaluationSummary(
                level: .seedling,
                hasSincerityMark: false,
                scheduledCount: 0,
                absentRate: 0,
                lateRate: 0,
                ownerRating: nil
            )
        }

        struct ScheduleEvalRow: Decodable {
            let worker_id: UUID
            let work_date: String
            let check_in_time: String
        }
        struct WorkLogEvalRow: Decodable {
            let worker_id: UUID
            let check_in_at: String
            let status: String?
        }
        struct RatingEvalRow: Decodable {
            let worker_id: UUID
            let rating: Double
        }

        let workerIds = workers.map(\.id)
        let workerIdStrings = workerIds.map(\.uuidString)

        let schedules: [ScheduleEvalRow]
        do {
            schedules = try await SupabaseManager.shared
                .client
                .from("schedule_entries")
                .select("worker_id,work_date,check_in_time")
                .in("worker_id", values: workerIdStrings)
                .execute()
                .value
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("schedule_entries") {
                let joinedAt = workers.compactMap { parseJoinedAt($0.joined_at) }.min() ?? Date()
                return WorkerEvaluationSummary(
                    level: WorkerGrowthLevel.from(joinedAt: joinedAt),
                    hasSincerityMark: false,
                    scheduledCount: 0,
                    absentRate: 0,
                    lateRate: 0,
                    ownerRating: nil
                )
            }
            throw error
        }

        let ratings: [RatingEvalRow]
        do {
            ratings = try await SupabaseManager.shared
                .client
                .from("worker_owner_ratings")
                .select("worker_id,rating")
                .in("worker_id", values: workerIdStrings)
                .execute()
                .value
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("worker_owner_ratings") {
                let joinedAt = workers.compactMap { parseJoinedAt($0.joined_at) }.min() ?? Date()
                return WorkerEvaluationSummary(
                    level: WorkerGrowthLevel.from(joinedAt: joinedAt),
                    hasSincerityMark: false,
                    scheduledCount: 0,
                    absentRate: 0,
                    lateRate: 0,
                    ownerRating: nil
                )
            }
            throw error
        }

        let ownerRating: Double? = ratings.isEmpty
            ? nil
            : ratings.map(\.rating).reduce(0, +) / Double(ratings.count)

        let dateOnlyFormatter = AppTime.displayFormatter("yyyy-MM-dd")
        let todayKey = dateOnlyFormatter.string(from: Date())
        let schedulesToEvaluate = schedules.filter { $0.work_date <= todayKey }
        if schedulesToEvaluate.isEmpty {
            let joinedAt = workers.compactMap { parseJoinedAt($0.joined_at) }.min() ?? Date()
            let active = workers.contains { $0.is_active ?? true }
            return buildSummary(
                joinedAt: joinedAt,
                isActive: active,
                scheduledCount: 0,
                absentCount: 0,
                lateCount: 0,
                ownerRating: ownerRating
            )
        }

        let earliestDate = schedulesToEvaluate
            .compactMap { dateOnlyFormatter.date(from: $0.work_date) }
            .min() ?? AppTime.calendar.startOfDay(for: Date())
        let iso = AppTime.iso
        let parserWithFractional = AppTime.isoWithFractionalSeconds

        let logs: [WorkLogEvalRow] = try await SupabaseManager.shared
            .client
            .from("work_logs")
            .select("worker_id,check_in_at,status")
            .in("worker_id", values: workerIdStrings)
            .gte("check_in_at", value: iso.string(from: earliestDate))
            .execute()
            .value

        var earliestLogByWorkerDay: [UUID: [String: Date]] = [:]
        for log in logs {
            if log.status == "rejected" { continue }
            let checkIn = parserWithFractional.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at)
            guard let checkIn else { continue }
            let dayKey = dateOnlyFormatter.string(from: checkIn)
            if let existing = earliestLogByWorkerDay[log.worker_id]?[dayKey] {
                if checkIn < existing {
                    earliestLogByWorkerDay[log.worker_id]?[dayKey] = checkIn
                }
            } else {
                earliestLogByWorkerDay[log.worker_id, default: [:]][dayKey] = checkIn
            }
        }

        let schedulesByWorker = Dictionary(grouping: schedulesToEvaluate, by: \.worker_id)
        var scheduledCount = 0
        var absentCount = 0
        var lateCount = 0
        for workerId in workerIds {
            let workerSchedules = schedulesByWorker[workerId] ?? []
            scheduledCount += workerSchedules.count
            for schedule in workerSchedules {
                guard let scheduledAt = scheduledDateTime(workDate: schedule.work_date, checkInTime: schedule.check_in_time) else {
                    continue
                }
                guard let actualCheckIn = earliestLogByWorkerDay[workerId]?[schedule.work_date] else {
                    absentCount += 1
                    continue
                }
                if actualCheckIn.timeIntervalSince(scheduledAt) > 600 {
                    lateCount += 1
                }
            }
        }

        let joinedAt = workers.compactMap { parseJoinedAt($0.joined_at) }.min() ?? Date()
        let active = workers.contains { $0.is_active ?? true }
        return buildSummary(
            joinedAt: joinedAt,
            isActive: active,
            scheduledCount: scheduledCount,
            absentCount: absentCount,
            lateCount: lateCount,
            ownerRating: ownerRating
        )
        #else
        return WorkerEvaluationSummary(
            level: .seedling,
            hasSincerityMark: false,
            scheduledCount: 0,
            absentRate: 0,
            lateRate: 0,
            ownerRating: nil
        )
        #endif
    }

    private func buildSummary(
        joinedAt: Date,
        isActive: Bool,
        scheduledCount: Int,
        absentCount: Int,
        lateCount: Int,
        ownerRating: Double?
    ) -> WorkerEvaluationSummary {
        let safeScheduledCount = max(0, scheduledCount)
        let absentRate = safeScheduledCount > 0
            ? (Double(absentCount) / Double(safeScheduledCount)) * 100.0
            : 0
        let lateRate = safeScheduledCount > 0
            ? (Double(lateCount) / Double(safeScheduledCount)) * 100.0
            : 0
        let level = WorkerGrowthLevel.from(joinedAt: joinedAt)
        let hasMark = WorkerEvaluationPolicy.shouldGrantSincerityMark(
            isActive: isActive,
            scheduledCount: safeScheduledCount,
            absentRate: absentRate,
            lateRate: lateRate,
            ownerRating: ownerRating
        )
        return WorkerEvaluationSummary(
            level: level,
            hasSincerityMark: hasMark,
            scheduledCount: safeScheduledCount,
            absentRate: absentRate,
            lateRate: lateRate,
            ownerRating: ownerRating
        )
    }

    private func parseJoinedAt(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return parseISODate(raw)
    }

    private func parseISODate(_ raw: String) -> Date? {
        let parserWithFractional = AppTime.isoWithFractionalSeconds
        let parser = AppTime.iso
        return parserWithFractional.date(from: raw) ?? parser.date(from: raw)
    }

    private func scheduledDateTime(workDate: String, checkInTime: String) -> Date? {
        let dayParts = workDate.split(separator: "-")
        let timeParts = checkInTime.split(separator: ":")
        guard dayParts.count == 3, timeParts.count >= 2,
              let year = Int(dayParts[0]),
              let month = Int(dayParts[1]),
              let day = Int(dayParts[2]),
              let hour = Int(timeParts[0]),
              let minute = Int(timeParts[1]) else {
            return nil
        }
        let second = timeParts.count >= 3 ? (Int(timeParts[2]) ?? 0) : 0
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return AppTime.calendar.date(from: components)
    }
}
