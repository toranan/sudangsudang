import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct WorkerManagementView: View {
    struct StoreOption: Identifiable, Hashable {
        let id: UUID
        let name: String
    }

    struct WorkerRow: Decodable, Identifiable {
        let id: UUID
        let user_id: UUID?
        let store_id: UUID
        let name: String
        let phone: String?
        let hourly_wage: Double?
        let is_active: Bool?
        let apply_weekly_allowance: Bool?
        let deduction_type: String?
        let apply_night_allowance: Bool?
        let payday: Int?
        let joined_at: String?
    }

    struct EvaluationSummary {
        let value: WorkerEvaluationSummary

        var levelTitle: String { value.level.rawValue }
        var hasSincerityMark: Bool { value.hasSincerityMark }
        var ownerRatingText: String {
            guard let ownerRating = value.ownerRating else { return "미입력" }
            return String(format: "%.1f점", ownerRating)
        }
    }

    struct WorkLogRow: Decodable, Identifiable {
        let id: UUID
        let worker_id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
        let applied_hourly_wage: Double?
        let applied_night_allowance: Bool?
    }

    enum DetailTab: String, CaseIterable, Identifiable {
        case logs = "내역"
        case net = "세후금액"
        case wage = "시급"
        case evaluation = "평가"

        var id: String { rawValue }
    }

    @State private var stores: [StoreOption] = []
    @State private var selectedStoreId: UUID?
    @State private var workers: [WorkerRow] = []
    @State private var monthLogsByWorker: [UUID: [WorkLogRow]] = [:]
    @State private var monthPayByWorker: [UUID: Double] = [:]
    @State private var monthMinutesByWorker: [UUID: Int] = [:]
    @State private var evaluationByWorker: [UUID: EvaluationSummary] = [:]
    @State private var isLoadingWorkers = false
    @State private var isUserRefreshing = false
    @State private var workersError: String?
    @State private var selectedWorker: WorkerRow?
    @State private var wageInput: String = ""
    @State private var isSavingWage = false
    @State private var wageError: String?
    @State private var detailTab: DetailTab = .wage
    @State private var manualHours: String = ""
    @State private var manualMinutes: String = ""
    @State private var isSavingManual = false
    @State private var manualError: String?
    @State private var inviteCode: String?
    @State private var inviteLink: URL?
    @State private var isCreatingInvite = false
    @State private var inviteError: String?
    @State private var isPresentingCreateWorker = false
    @State private var selectedMonth: Date = AppTime.calendar.date(from: AppTime.calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var lastStoresLoadedAt: Date?
    @State private var lastWorkersLoadedAt: Date?
    @State private var lastWorkersKey: String?
    @State private var storesRequest = LatestRequest()
    @State private var workersRequest = LatestRequest()
    private let cacheTTLSeconds: TimeInterval = 120

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "초대 관리")
                    if !stores.isEmpty {
                        storePicker
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("알바 초대를 빠르게")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text("초대코드를 공유해 연결할 수 있어요")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        Button(action: {
                            Task { await createInvite() }
                        }) {
                            Label("알바 초대하기", systemImage: "number")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(selectedStoreId == nil || isCreatingInvite)
                        .opacity(selectedStoreId == nil || isCreatingInvite ? 0.5 : 1.0)

                        Button(action: {
                            isPresentingCreateWorker = true
                        }) {
                            Label("알바 직접 등록", systemImage: "person.badge.plus")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(selectedStoreId == nil)
                        .opacity(selectedStoreId == nil ? 0.5 : 1.0)

                        if let inviteCode {
                            HStack(spacing: 8) {
                                Text("초대코드: \(inviteCode)")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                                Spacer()
                                Button(action: {
                                    self.inviteCode = nil
                                    inviteLink = nil
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.appLine)
                                }
                            }
                            .padding(.top, 6)

                            ShareLink(item: inviteCode) {
                                Label("초대코드 공유", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }

                        if let inviteLink {
                            ShareLink(item: inviteLink) {
                                Label("초대 링크 공유", systemImage: "link")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }

                        if let inviteError {
                            Text(inviteError)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appWarning)
                        }
                    }
                    .appCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "알바 목록", trailing: "\(workers.count)명")
                    monthSelector
                    if isLoadingWorkers && workers.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .appCard()
                    } else if workers.isEmpty {
                        Text("등록된 알바가 없어요.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                            .appCard()
                    } else {
                        VStack(spacing: 10) {
                            ForEach(workers) { worker in
                                Button(action: {
                                    selectedWorker = worker
                                    wageInput = worker.hourly_wage.map { formatWonRaw($0) } ?? ""
                                    wageError = nil
                                    manualError = nil
                                    manualHours = ""
                                    manualMinutes = ""
                                    detailTab = .logs
                                }) {
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(Color.appLine)
                                            .frame(width: 44, height: 44)
                                            .overlay(
                                                Text(String(worker.name.prefix(1)))
                                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                                    .foregroundColor(.appTextSecondary)
                                            )
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(worker.name)
                                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                            if let phone = worker.phone, !phone.isEmpty {
                                                Text(phone)
                                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                                    .foregroundColor(.appTextSecondary)
                                            }
                                            if let summary = evaluationByWorker[worker.id] {
                                                HStack(spacing: 6) {
                                                    Text(summary.levelTitle)
                                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                                        .foregroundColor(.appTextSecondary)
                                                    if summary.hasSincerityMark {
                                                        StatusPill(text: "성실마크", color: .appPositive)
                                                    }
                                                }
                                            }
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 4) {
                                            Text(formatWon(monthPayByWorker[worker.id] ?? 0))
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundColor(.appTextPrimary)
                                            Text(formatHours(monthMinutesByWorker[worker.id] ?? 0))
                                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                                .foregroundColor(.appTextSecondary)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.appSurface)
                                    .cornerRadius(14)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.appLine, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let workersError {
                        Text(workersError)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appWarning)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable {
            await refreshFromUser()
        }
        .refreshStatusOverlay(isVisible: isUserRefreshing)

        .background(Color.appBackground.ignoresSafeArea())
        .sheet(item: $selectedWorker) { worker in
            WorkerDetailSheet(
                worker: worker,
                monthLogs: monthLogsByWorker[worker.id] ?? [],
                monthPay: monthPayByWorker[worker.id] ?? 0,
                initialEvaluation: evaluationByWorker[worker.id]?.value,
                onUpdate: { await loadWorkers(force: true) }
            )
            .id(worker.id)
        }
        .sheet(isPresented: $isPresentingCreateWorker) {
            if let storeId = selectedStoreId {
                CreateWorkerView(storeId: storeId) { name, phone, wage in
                    Task {
                        await createWorker(storeId: storeId, name: name, phone: phone, hourlyWage: wage)
                        await loadWorkers(force: true)
                    }
                }
            }
        }
        .task {
            await refresh(force: false)
        }
        .onChange(of: selectedMonth) { _ in
            Task { await loadWorkers(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await refresh(force: false) }
        }
    }

    private var monthSelector: some View {
        HStack(spacing: 12) {
            Button(action: {
                selectedMonth = AppTime.calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appTextSecondary)
            }
            Spacer()
            Text(monthTitle(selectedMonth))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.appTextPrimary)
            Spacer()
            Button(action: {
                selectedMonth = AppTime.calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
            }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.appTextSecondary)
            }
        }
        .padding(12)
        .background(Color.appSurface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appLine, lineWidth: 1)
        )
    }

    private var storePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(stores) { store in
                    let isSelected = store.id == selectedStoreId
                    Button(action: {
                        selectedStoreId = store.id
                        inviteCode = nil
                        inviteLink = nil
                        Task { await loadWorkers(force: false) }
                    }) {
                        Text(store.name)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(isSelected ? .white : .appTextPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color.appAccent : Color.appSurface)
                            .cornerRadius(999)
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @MainActor
    private func refreshFromUser() async {
        isUserRefreshing = true
        defer { isUserRefreshing = false }
        await refresh(force: true)
    }

    @MainActor
    private func loadStores(force: Bool) async {
        #if canImport(Supabase)
        let now = Date()
        if !force,
           let lastStoresLoadedAt,
           now.timeIntervalSince(lastStoresLoadedAt) < cacheTTLSeconds {
            return
        }
        let requestID = storesRequest.begin()
        do {
            let ownerId = try await SupabaseManager.shared.currentUserId()
            let result: [Store] = try await SupabaseManager.shared
                .client
                .from("stores")
                .select()
                .eq("owner_id", value: ownerId.uuidString)
                .execute()
                .value
            guard storesRequest.isCurrent(requestID) else { return }
            stores = result.map { StoreOption(id: $0.id, name: $0.name) }
            if selectedStoreId == nil || !stores.contains(where: { $0.id == selectedStoreId }) {
                selectedStoreId = stores.first?.id
            }
            self.lastStoresLoadedAt = now
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard storesRequest.isCurrent(requestID) else { return }
            inviteError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func loadWorkers(force: Bool) async {
        guard let storeId = selectedStoreId else {
            workersRequest.invalidate()
            workers = []
            evaluationByWorker = [:]
            return
        }
        #if canImport(Supabase)
        let now = Date()
        let key = "\(storeId.uuidString)|\(monthKey(selectedMonth))"
        if !force,
           lastWorkersKey == key,
           let lastWorkersLoadedAt,
           now.timeIntervalSince(lastWorkersLoadedAt) < cacheTTLSeconds {
            return
        }
        let requestID = workersRequest.begin()
        let requestedMonth = selectedMonth
        isLoadingWorkers = true
        workersError = nil
        defer {
            if workersRequest.isCurrent(requestID) {
                isLoadingWorkers = false
            }
        }
        do {
            do {
                try await WorkerAutoRetirement.processForStore(storeId: storeId)
            } catch {
                if AppErrorMessage.isCancellation(error) {
                    return
                }
                #if DEBUG
                print("DEBUG: auto retirement (owner workers) failed: \(error.localizedDescription)")
                #endif
            }
            do {
                // Newer schema: includes payroll settings columns.
                let rows: [WorkerRow] = try await SupabaseManager.shared
                    .client
                    .from("workers")
                    .select("id,user_id,store_id,name,phone,hourly_wage,is_active,apply_weekly_allowance,deduction_type,apply_night_allowance,payday,joined_at")
                    .eq("store_id", value: storeId.uuidString)
                    .order("joined_at", ascending: false)
                    .execute()
                    .value
                let activeRows = rows.filter { $0.is_active ?? true }
                guard isCurrentWorkersRequest(requestID, key: key) else { return }
                workers = activeRows
                await loadMonthlyLogs(storeId: storeId, workers: activeRows, month: requestedMonth, requestID: requestID, key: key)
                await loadWorkerEvaluations(storeId: storeId, workers: activeRows, requestID: requestID, key: key)
            } catch {
                // Safety net: if DB migration is not applied yet, re-fetch without the new columns.
                let message = error.localizedDescription.lowercased()
                if message.contains("apply_night_allowance") || message.contains("payday") {
                    let rows: [WorkerRow] = try await SupabaseManager.shared
                        .client
                        .from("workers")
                        .select("id,user_id,store_id,name,phone,hourly_wage,is_active,apply_weekly_allowance,deduction_type,joined_at")
                        .eq("store_id", value: storeId.uuidString)
                        .order("joined_at", ascending: false)
                        .execute()
                        .value
                    let activeRows = rows.filter { $0.is_active ?? true }
                    guard isCurrentWorkersRequest(requestID, key: key) else { return }
                    workers = activeRows
                    await loadMonthlyLogs(storeId: storeId, workers: activeRows, month: requestedMonth, requestID: requestID, key: key)
                    await loadWorkerEvaluations(storeId: storeId, workers: activeRows, requestID: requestID, key: key)
                } else if message.contains("apply_weekly_allowance") || message.contains("deduction_type") {
                    let rows: [WorkerRow] = try await SupabaseManager.shared
                        .client
                        .from("workers")
                        .select("id,user_id,store_id,name,phone,hourly_wage,is_active,joined_at")
                        .eq("store_id", value: storeId.uuidString)
                        .order("joined_at", ascending: false)
                        .execute()
                        .value
                    let activeRows = rows.filter { $0.is_active ?? true }
                    guard isCurrentWorkersRequest(requestID, key: key) else { return }
                    workers = activeRows
                    await loadMonthlyLogs(storeId: storeId, workers: activeRows, month: requestedMonth, requestID: requestID, key: key)
                    await loadWorkerEvaluations(storeId: storeId, workers: activeRows, requestID: requestID, key: key)
                } else {
                    throw error
                }
            }
            guard isCurrentWorkersRequest(requestID, key: key) else { return }
            self.lastWorkersLoadedAt = now
            self.lastWorkersKey = key
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard isCurrentWorkersRequest(requestID, key: key) else { return }
            workersError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private func monthKey(_ date: Date) -> String {
        let comps = AppTime.calendar.dateComponents([.year, .month], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)"
    }

    private func isCurrentWorkersRequest(_ requestID: UUID, key: String) -> Bool {
        guard let storeId = selectedStoreId else { return false }
        let currentKey = "\(storeId.uuidString)|\(monthKey(selectedMonth))"
        return workersRequest.isCurrent(requestID) && currentKey == key
    }

    @MainActor
    private func refresh(force: Bool) async {
        await loadStores(force: force)
        await loadWorkers(force: force)
    }
    
    // Formatting helpers utilized by parent view
    
    private func formatWonRaw(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        return formatter.string(from: NSNumber(value: Int(value))) ?? ""
    }


    private func monthTitle(_ date: Date) -> String {
        let formatter = AppTime.displayFormatter("yyyy년 M월")
        return formatter.string(from: date)
    }

    @MainActor
    private func loadMonthlyLogs(
        storeId: UUID,
        workers: [WorkerRow],
        month: Date,
        requestID: UUID,
        key: String
    ) async {
        #if canImport(Supabase)
        do {
            let calendar = AppTime.calendar
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? Date()
            let iso = AppTime.iso

            let rows: [WorkLogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,worker_id,check_in_at,check_out_at,status,applied_hourly_wage,applied_night_allowance")
                .eq("store_id", value: storeId.uuidString)
                .gte("check_in_at", value: iso.string(from: monthStart))
                .lt("check_in_at", value: iso.string(from: monthEnd))
                .execute()
                .value

            var byWorker: [UUID: [WorkLogRow]] = [:]
            for row in rows where normalizedStatus(row.status) == "approved" && !(row.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                byWorker[row.worker_id, default: []].append(row)
            }

            var payByWorker: [UUID: Double] = [:]
            var minutesByWorker: [UUID: Int] = [:]
            for worker in workers {
                let wage = worker.hourly_wage ?? 0
                let applyNightAllowance = worker.apply_night_allowance ?? false
                let logs = byWorker[worker.id] ?? []
                var minutes = 0
                var pay: Double = 0
                for log in logs {
                    let dates = parseWorkLogDates(checkIn: log.check_in_at, checkOut: log.check_out_at)
                    minutes += PayrollCalculator.calcMinutes(checkIn: dates.start, checkOut: dates.end)
                    pay += PayrollCalculator.grossPay(
                        checkIn: dates.start,
                        checkOut: dates.end,
                        appliedHourlyWage: log.applied_hourly_wage,
                        appliedNightAllowance: log.applied_night_allowance,
                        fallbackHourlyWage: wage,
                        fallbackNightAllowance: applyNightAllowance
                    )
                }
                payByWorker[worker.id] = pay
                minutesByWorker[worker.id] = minutes
            }

            guard isCurrentWorkersRequest(requestID, key: key) else { return }
            monthLogsByWorker = byWorker
            monthPayByWorker = payByWorker
            monthMinutesByWorker = minutesByWorker
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard isCurrentWorkersRequest(requestID, key: key) else { return }
            workersError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func loadWorkerEvaluations(
        storeId: UUID,
        workers: [WorkerRow],
        requestID: UUID,
        key: String
    ) async {
        #if canImport(Supabase)
        guard !workers.isEmpty else {
            guard isCurrentWorkersRequest(requestID, key: key) else { return }
            evaluationByWorker = [:]
            return
        }

        do {
            let ownerId = try await SupabaseManager.shared.currentUserId()
            let selectedPersonByWorker = Dictionary(uniqueKeysWithValues: workers.map { ($0.id, personKey(for: $0)) })
            let selectedPersonKeys = Set(selectedPersonByWorker.values)

            struct WorkerIdentityRow: Decodable {
                let id: UUID
                let user_id: UUID?
                let joined_at: String?
                let is_active: Bool?
            }

            var identityRows = workers.map {
                WorkerIdentityRow(
                    id: $0.id,
                    user_id: $0.user_id,
                    joined_at: $0.joined_at,
                    is_active: $0.is_active
                )
            }
            let userIds = Array(Set(workers.compactMap { $0.user_id?.uuidString }))
            if !userIds.isEmpty {
                let extraRows: [WorkerIdentityRow] = try await SupabaseManager.shared
                    .client
                    .from("workers")
                    .select("id,user_id,joined_at,is_active")
                    .in("user_id", values: userIds)
                    .execute()
                    .value
                let existingIds = Set(identityRows.map(\.id))
                identityRows.append(contentsOf: extraRows.filter { !existingIds.contains($0.id) })
            }

            var workerIdsByPerson: [String: [UUID]] = [:]
            var earliestJoinedByPerson: [String: Date] = [:]
            var isActiveByPerson: [String: Bool] = [:]
            for row in identityRows {
                let key = row.user_id?.uuidString ?? row.id.uuidString
                guard selectedPersonKeys.contains(key) else { continue }
                workerIdsByPerson[key, default: []].append(row.id)
                if let joined = parseJoinedAt(row.joined_at) {
                    if let existing = earliestJoinedByPerson[key] {
                        earliestJoinedByPerson[key] = min(existing, joined)
                    } else {
                        earliestJoinedByPerson[key] = joined
                    }
                }
                isActiveByPerson[key] = (isActiveByPerson[key] ?? false) || (row.is_active ?? true)
            }

            let allWorkerIds = Array(Set(workerIdsByPerson.values.flatMap { $0 }))
            if allWorkerIds.isEmpty {
                guard isCurrentWorkersRequest(requestID, key: key) else { return }
                evaluationByWorker = Dictionary(uniqueKeysWithValues: workers.map { worker in
                    let key = selectedPersonByWorker[worker.id] ?? worker.id.uuidString
                    let joinedAt = earliestJoinedByPerson[key] ?? parseJoinedAt(worker.joined_at) ?? Date()
                    let summary = buildSummary(
                        joinedAt: joinedAt,
                        isActive: isActiveByPerson[key] ?? (worker.is_active ?? true),
                        scheduledCount: 0,
                        absentCount: 0,
                        lateCount: 0,
                        ownerRating: nil
                    )
                    return (worker.id, EvaluationSummary(value: summary))
                })
                return
            }
            let workerIdStrings = allWorkerIds.map(\.uuidString)

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
                    guard isCurrentWorkersRequest(requestID, key: key) else { return }
                    evaluationByWorker = Dictionary(uniqueKeysWithValues: workers.map { worker in
                        let key = selectedPersonByWorker[worker.id] ?? worker.id.uuidString
                        let joinedAt = earliestJoinedByPerson[key] ?? parseJoinedAt(worker.joined_at) ?? Date()
                        let summary = buildSummary(
                            joinedAt: joinedAt,
                            isActive: isActiveByPerson[key] ?? (worker.is_active ?? true),
                            scheduledCount: 0,
                            absentCount: 0,
                            lateCount: 0,
                            ownerRating: nil
                        )
                        return (worker.id, EvaluationSummary(value: summary))
                    })
                    return
                }
                throw error
            }

            let ratings: [RatingEvalRow]
            do {
                ratings = try await SupabaseManager.shared
                    .client
                    .from("worker_owner_ratings")
                    .select("worker_id,rating")
                    .eq("owner_id", value: ownerId.uuidString)
                    .in("worker_id", values: workerIdStrings)
                    .execute()
                    .value
            } catch {
                let message = error.localizedDescription.lowercased()
                if message.contains("worker_owner_ratings") {
                    guard isCurrentWorkersRequest(requestID, key: key) else { return }
                    evaluationByWorker = Dictionary(uniqueKeysWithValues: workers.map { worker in
                        let key = selectedPersonByWorker[worker.id] ?? worker.id.uuidString
                        let joinedAt = earliestJoinedByPerson[key] ?? parseJoinedAt(worker.joined_at) ?? Date()
                        let summary = buildSummary(
                            joinedAt: joinedAt,
                            isActive: isActiveByPerson[key] ?? (worker.is_active ?? true),
                            scheduledCount: 0,
                            absentCount: 0,
                            lateCount: 0,
                            ownerRating: nil
                        )
                        return (worker.id, EvaluationSummary(value: summary))
                    })
                    return
                }
                throw error
            }
            let workerToPerson = Dictionary(uniqueKeysWithValues: workerIdsByPerson.flatMap { entry in
                entry.value.map { ($0, entry.key) }
            })
            var ownerRatingsByPerson: [String: [Double]] = [:]
            for row in ratings {
                guard let key = workerToPerson[row.worker_id] else { continue }
                ownerRatingsByPerson[key, default: []].append(row.rating)
            }
            let ownerRatingByPerson = ownerRatingsByPerson.mapValues { values in
                values.reduce(0, +) / Double(max(values.count, 1))
            }

            let dateOnlyFormatter = AppTime.displayFormatter("yyyy-MM-dd")
            let todayKey = dateOnlyFormatter.string(from: Date())
            let schedulesToEvaluate = schedules.filter { $0.work_date <= todayKey }

            if schedulesToEvaluate.isEmpty {
                var onlyRatings: [UUID: WorkerEvaluationSummary] = [:]
                for worker in workers {
                    let key = selectedPersonByWorker[worker.id] ?? worker.id.uuidString
                    let joinedAt = earliestJoinedByPerson[key] ?? parseJoinedAt(worker.joined_at) ?? Date()
                    let summary = buildSummary(
                        joinedAt: joinedAt,
                        isActive: isActiveByPerson[key] ?? (worker.is_active ?? true),
                        scheduledCount: 0,
                        absentCount: 0,
                        lateCount: 0,
                        ownerRating: ownerRatingByPerson[key]
                    )
                    onlyRatings[worker.id] = summary
                }
                guard isCurrentWorkersRequest(requestID, key: key) else { return }
                evaluationByWorker = onlyRatings.mapValues { EvaluationSummary(value: $0) }
                return
            }

            let earliestDate = schedulesToEvaluate
                .compactMap { dateOnlyFormatter.date(from: $0.work_date) }
                .min() ?? AppTime.calendar.startOfDay(for: Date())
            let iso = AppTime.iso

            let logs: [WorkLogEvalRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("worker_id,check_in_at,status")
                .in("worker_id", values: workerIdStrings)
                .gte("check_in_at", value: iso.string(from: earliestDate))
                .execute()
                .value

            let parserWithFractional = AppTime.isoWithFractionalSeconds

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

            var schedulesByWorker: [UUID: [ScheduleEvalRow]] = [:]
            for row in schedulesToEvaluate {
                schedulesByWorker[row.worker_id, default: []].append(row)
            }

            var metricsByPerson: [String: (scheduled: Int, absent: Int, late: Int)] = [:]
            for (person, personWorkerIds) in workerIdsByPerson {
                var scheduledCount = 0
                var absentCount = 0
                var lateCount = 0

                for workerId in personWorkerIds {
                    let workerSchedules = schedulesByWorker[workerId] ?? []
                    scheduledCount += workerSchedules.count
                    for schedule in workerSchedules {
                        guard let scheduledDateTime = scheduledDateTime(workDate: schedule.work_date, checkInTime: schedule.check_in_time) else {
                            continue
                        }
                        guard let actualCheckIn = earliestLogByWorkerDay[workerId]?[schedule.work_date] else {
                            absentCount += 1
                            continue
                        }
                        if actualCheckIn.timeIntervalSince(scheduledDateTime) > 600 {
                            lateCount += 1
                        }
                    }
                }
                metricsByPerson[person] = (scheduledCount, absentCount, lateCount)
            }

            var summaries: [UUID: WorkerEvaluationSummary] = [:]
            for worker in workers {
                let key = selectedPersonByWorker[worker.id] ?? worker.id.uuidString
                let metrics = metricsByPerson[key] ?? (0, 0, 0)
                let joinedAt = earliestJoinedByPerson[key] ?? parseJoinedAt(worker.joined_at) ?? Date()
                summaries[worker.id] = buildSummary(
                    joinedAt: joinedAt,
                    isActive: isActiveByPerson[key] ?? (worker.is_active ?? true),
                    scheduledCount: metrics.scheduled,
                    absentCount: metrics.absent,
                    lateCount: metrics.late,
                    ownerRating: ownerRatingByPerson[key]
                )
            }

            guard isCurrentWorkersRequest(requestID, key: key) else { return }
            evaluationByWorker = summaries.mapValues { EvaluationSummary(value: $0) }
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard isCurrentWorkersRequest(requestID, key: key) else { return }
            evaluationByWorker = Dictionary(uniqueKeysWithValues: workers.map { worker in
                let summary = buildSummary(
                    joinedAt: parseJoinedAt(worker.joined_at) ?? Date(),
                    isActive: worker.is_active ?? true,
                    scheduledCount: 0,
                    absentCount: 0,
                    lateCount: 0,
                    ownerRating: nil
                )
                return (worker.id, EvaluationSummary(value: summary))
            })
        }
        #endif
    }

    @MainActor
    private func createWorker(storeId: UUID, name: String, phone: String, hourlyWage: Double) async {
        #if canImport(Supabase)
        do {
            struct WorkerInsert: Encodable {
                let store_id: UUID
                let name: String
                let phone: String?
                let hourly_wage: Double
                let is_active: Bool
            }
            let payload = WorkerInsert(
                store_id: storeId,
                name: name,
                phone: phone.isEmpty ? nil : phone,
                hourly_wage: hourlyWage,
                is_active: true
            )
            _ = try await SupabaseManager.shared
                .client
                .from("workers")
                .insert(payload)
                .execute()
        } catch {
            workersError = AppErrorMessage.userMessage(error)
        }
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

    private func parseJoinedAt(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let parserWithFractional = AppTime.isoWithFractionalSeconds
        let parser = AppTime.iso
        return parserWithFractional.date(from: raw) ?? parser.date(from: raw)
    }

    private func personKey(for worker: WorkerRow) -> String {
        worker.user_id?.uuidString ?? worker.id.uuidString
    }

    // Helper calculation functions need to be available for parent logic too
    private func parseWorkLogDates(checkIn: String, checkOut: String?) -> (start: Date, end: Date?) {
        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso
        let start = parser.date(from: checkIn) ?? iso.date(from: checkIn) ?? Date()
        let end = checkOut.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
        return (start, end)
    }

    private func calcMinutes(checkIn: String, checkOut: String?) -> Int {
        let dates = parseWorkLogDates(checkIn: checkIn, checkOut: checkOut)
        return PayrollCalculator.calcMinutes(checkIn: dates.start, checkOut: dates.end ?? Date())
    }

    private func calcPay(minutes: Int, wage: Double) -> Double {
        Double(minutes) / 60.0 * wage
    }


    @MainActor
    private func createInvite() async {
        guard let storeId = selectedStoreId else { return }
        #if canImport(Supabase)
        isCreatingInvite = true
        inviteError = nil
        defer { isCreatingInvite = false }
        do {
            let expiresAt = AppTime.calendar.date(byAdding: .hour, value: 48, to: Date()) ?? Date()
            let invite = try await SupabaseManager.shared.createInvite(storeId: storeId, expiresAt: expiresAt)
            inviteCode = invite.token
            inviteLink = URL(string: "howmuch://invite?token=\(invite.token)")
        } catch {
            inviteError = AppErrorMessage.userMessage(error)
        }
        #endif
    }
}

// Separate Struct for Sheet to fix state persistence issues
struct WorkerDetailSheet: View {
    let worker: WorkerManagementView.WorkerRow
    let monthLogs: [WorkerManagementView.WorkLogRow]
    let monthPay: Double
    let initialEvaluation: WorkerEvaluationSummary?
    let onUpdate: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var detailTab: WorkerManagementView.DetailTab = .logs
    @State private var wageInput: String = ""
    @State private var isSavingWage = false
    @State private var wageError: String?
    @State private var applyWeeklyAllowance: Bool = false
    @State private var applyNightAllowance: Bool = false
    @State private var deductionType: PayrollDeductionType = .withholding
    @State private var payday: Int = PayrollLocalSettings.defaultPayday
    @State private var isSavingPayroll = false
    @State private var payrollError: String?
    @State private var startHourInput: String = ""
    @State private var startMinuteInput: String = ""
    @State private var endHourInput: String = ""
    @State private var endMinuteInput: String = ""
    @State private var isSavingManual = false
    @State private var manualError: String?
    @State private var editingLog: WorkerManagementView.WorkLogRow?
    @State private var editHours: String = ""
    @State private var editMinutes: String = ""
    @State private var isSavingEdit = false
    @State private var editError: String?
    @State private var pendingDeleteLog: WorkerManagementView.WorkLogRow?
    @State private var isShowingDeleteConfirm = false
    @State private var didLoadPayrollState = false
    @State private var ownerRatingInput: Double = 3.0
    @State private var isSavingRating = false
    @State private var ratingError: String?
    @State private var didLoadRating = false
    @State private var evaluationSummary: WorkerEvaluationSummary?
    @State private var isProcessingRetirement = false
    @State private var retirementError: String?
    @State private var isShowingRetirementConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(worker.name)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.appTextPrimary)

            Picker("", selection: $detailTab) {
                ForEach(WorkerManagementView.DetailTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if detailTab == .evaluation {
                evaluationView
            } else if detailTab == .wage {
                wageView
            } else if detailTab == .net {
                netView
            } else {
                logsView
            }

            Spacer()
        }
        .padding(20)
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
        .onAppear {
            let formatter = NumberFormatter()
            formatter.numberStyle = .none
            if let wage = worker.hourly_wage, wage > 0 {
                wageInput = formatter.string(from: NSNumber(value: Int(wage))) ?? ""
            } else {
                wageInput = formatter.string(from: NSNumber(value: Int(AppConfig.defaultHourlyWage))) ?? ""
            }
            if !didLoadPayrollState {
                applyWeeklyAllowance = worker.apply_weekly_allowance ?? false
                if let raw = worker.deduction_type,
                   let parsed = PayrollDeductionType(rawValue: raw) {
                    deductionType = parsed
                } else {
                    deductionType = .withholding
                }
                applyNightAllowance = worker.apply_night_allowance ?? false
                payday = min(max(worker.payday ?? PayrollLocalSettings.defaultPayday, 1), 31)
                didLoadPayrollState = true
            }
            evaluationSummary = initialEvaluation ?? buildFallbackEvaluation(ownerRating: nil)
        }
        .task {
            if !didLoadRating {
                await loadOwnerRating()
                didLoadRating = true
            }
        }
        .sheet(item: $editingLog) { log in
            VStack(alignment: .leading, spacing: 16) {
                Text("근무 수정")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextPrimary)

                Text(formatDate(log.check_in_at))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("시간")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        TextField("예: 3", text: $editHours)
                            .keyboardType(.numberPad)
                            .foregroundColor(.appTextPrimary)
                            .padding(10)
                            .background(Color.appSurface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("분")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        TextField("예: 30", text: $editMinutes)
                            .keyboardType(.numberPad)
                            .foregroundColor(.appTextPrimary)
                            .padding(10)
                            .background(Color.appSurface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                    }
                }

                if let editError {
                    Text(editError)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appWarning)
                }

                Button(action: {
                    Task { await updateLogDuration(log) }
                }) {
                    Text(isSavingEdit ? "저장 중..." : "저장")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSavingEdit)
                .opacity(isSavingEdit ? 0.6 : 1.0)

                Button("닫기") {
                    editingLog = nil
                }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
            }
            .padding(20)
            .contentShape(Rectangle())
            .onTapGesture { hideKeyboard() }
        }
        .alert("이 근무 내역을 삭제할까요?", isPresented: $isShowingDeleteConfirm) {
            Button("삭제", role: .destructive) {
                guard let log = pendingDeleteLog else { return }
                Task { await deleteLog(log) }
            }
            Button("취소", role: .cancel) { pendingDeleteLog = nil }
        }
        .alert("퇴사처리하시겠습니까?", isPresented: $isShowingRetirementConfirm) {
            Button("퇴사처리", role: .destructive) {
                Task { await processRetirement() }
            }
            Button("취소", role: .cancel) {}
        }
    }

    private var evaluationView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("성장 단계")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                Spacer()
                Text(evaluationSummary?.level.rawValue ?? WorkerGrowthLevel.seedling.rawValue)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
            }

            HStack {
                Text("성실마크")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                Spacer()
                if evaluationSummary?.hasSincerityMark == true {
                    StatusPill(text: "부여됨", color: .appPositive)
                } else {
                    Text("미부여")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("사장 성실도 평가")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { index in
                        Image(systemName: starSymbol(for: index))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.appAccent)
                    }
                    Spacer()
                    Text("\(ownerRatingInput, specifier: "%.1f")점")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                }
                Slider(value: $ownerRatingInput, in: 1...5, step: 0.5)
                    .tint(.appAccent)
                    .onChange(of: ownerRatingInput) { value in
                        ownerRatingInput = clampedHalfStep(value)
                    }
                Text("4.0점 이상 + 결근/지각 기준 충족 시 성실마크가 부여돼요.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
            }

            if let ratingError {
                Text(ratingError)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appWarning)
            }

            Button(action: {
                Task { await saveOwnerRating() }
            }) {
                Text(isSavingRating ? "저장 중..." : "평가 저장")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(isSavingRating)
            .opacity(isSavingRating ? 0.6 : 1.0)

            if let retirementError {
                Text(retirementError)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appWarning)
            }

            Button(action: {
                isShowingRetirementConfirm = true
            }) {
                Text(isProcessingRetirement ? "처리 중..." : "퇴사처리")
            }
            .buttonStyle(PrimaryButtonStyle(backgroundColor: .appWarning))
            .disabled(isProcessingRetirement || isSavingRating)
            .opacity((isProcessingRetirement || isSavingRating) ? 0.6 : 1.0)
        }
        .appCard()
    }

    private var wageView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("시급 (원)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                TextField("예: 10320", text: $wageInput)
                    .keyboardType(.numberPad)
                    .foregroundColor(.appTextPrimary)
                    .padding(12)
                    .background(Color.appSurface)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.appLine, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("세후 설정")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextPrimary)

                Toggle(isOn: $applyWeeklyAllowance) {
                    Text("주휴수당 적용")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                }
                .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                .onChange(of: applyWeeklyAllowance) { _ in
                    Task { await savePayrollSettings() }
                }

                Toggle(isOn: $applyNightAllowance) {
                    Text("야간수당 적용 (22:00~06:00 +50%)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                }
                .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                .onChange(of: applyNightAllowance) { _ in
                    Task { await savePayrollSettings() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("공제 방식 (택 1)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    HStack(spacing: 8) {
                        ForEach(PayrollDeductionType.allCases) { option in
                            Button(action: {
                                deductionType = option
                                Task { await savePayrollSettings() }
                            }) {
                                Text(option.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(deductionType == option ? .white : .appTextPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(deductionType == option ? Color.appAccent : Color.appSurface)
                                    .cornerRadius(10)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(deductionType == option ? Color.appAccent : Color.appLine, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("월급일")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    Picker("월급일", selection: $payday) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)일").tag(day)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: payday) { _ in
                        Task { await savePayrollSettings() }
                    }
                }

                if let payrollError {
                    Text(payrollError)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appWarning)
                }
                if isSavingPayroll {
                    Text("저장 중...")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                } else {
                    Text("세후금액 탭에서 예상 세후 금액을 확인할 수 있어요.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                }
            }
            .appCard()

            if let wageError {
                Text(wageError)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appWarning)
            }

            Button(action: {
                Task { await saveWage() }
            }) {
                Text(isSavingWage ? "저장 중..." : "저장")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSavingWage)
            .opacity(isSavingWage ? 0.6 : 1.0)
        }
    }

    private var netView: some View {
        let wage = effectiveHourlyWage()
        let gross = monthGrossPay(wage: wage)
        let weeklyAllowance = applyWeeklyAllowance ? estimateWeeklyAllowancePay(wage: wage) : 0
        let grossWithAllowance = gross + weeklyAllowance
        let breakdown = PayrollCalculator.deductionBreakdown(gross: grossWithAllowance, type: deductionType)
        let deduction = breakdown.totalDeduction
        let net = max(0, grossWithAllowance - deduction)

        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("이번 달 세후 예상")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                Text(formatWon(net))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                Text("공제/주휴는 설정에 따라 달라지는 예상치예요.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
            }
            .appCard()

            VStack(alignment: .leading, spacing: 10) {
                row(title: "세전(승인된 근무)", value: formatWon(gross))
                row(title: "주휴수당", value: formatWon(weeklyAllowance))
                row(title: "세전 합계", value: formatWon(grossWithAllowance))
                row(title: "공제 방식", value: deductionType.title)
                row(title: "공제율(합)", value: percentText(breakdown.totalRate))
                if breakdown.items.count > 1 {
                    Divider().background(Color.appLine)
                    ForEach(breakdown.items) { item in
                        row(title: item.title, value: "\(percentText(item.rate))  \(formatWon(item.amount))")
                    }
                }
                row(title: "공제액", value: formatWon(deduction))
                Divider().background(Color.appLine)
                row(title: "세후 합계", value: formatWon(net), emphasized: true)
            }
            .appCard()
        }
    }

    private func row(title: String, value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.appTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: emphasized ? .semibold : .medium, design: .rounded))
                .foregroundColor(.appTextPrimary)
        }
    }

    private var logsView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("이번 달 지급액")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                HStack(alignment: .bottom) {
                    Text(formatWon(monthGrossPay(wage: effectiveHourlyWage())))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    Text(formatHours(totalMinutes()))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                }
            }
            .appCard()

            if monthLogs.isEmpty {
                Text("이번 달 근무 내역이 없어요.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                    .appCard()
            } else {
                VStack(spacing: 10) {
                    ForEach(monthLogs) { log in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(formatDate(log.check_in_at))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Spacer()
                                Menu {
                                    Button("수정") {
                                        editingLog = log
                                        let minutes = calcMinutes(checkIn: log.check_in_at, checkOut: log.check_out_at)
                                        editHours = String(minutes / 60)
                                        editMinutes = String(minutes % 60)
                                        editError = nil
                                    }
                                    Button(role: .destructive) {
                                        pendingDeleteLog = log
                                        isShowingDeleteConfirm = true
                                    } label: {
                                        Text("삭제")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .foregroundColor(.appTextSecondary)
                                        .padding(6)
                                }
                            }
                            Text(formatTimeRange(log))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                            HStack {
                                Text(formatHours(calcMinutes(checkIn: log.check_in_at, checkOut: log.check_out_at)))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                Spacer()
                                Text(formatWon(logGrossPay(log, wage: effectiveHourlyWage())))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                            }
                        }
                        .padding(12)
                        .background(Color.appSurface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appLine, lineWidth: 1)
                        )
                    }
                }
            }

            // Manual Add
            manualAddView
        }
    }

    private var manualAddView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("근무 추가")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.appTextPrimary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("출근 시간")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    HStack(spacing: 8) {
                        TextField("시", text: $startHourInput)
                            .keyboardType(.numberPad)
                            .foregroundColor(.appTextPrimary)
                            .multilineTextAlignment(.center)
                            .padding(10)
                            .background(Color.appSurface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                        Text(":")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        TextField("분", text: $startMinuteInput)
                            .keyboardType(.numberPad)
                            .foregroundColor(.appTextPrimary)
                            .multilineTextAlignment(.center)
                            .padding(10)
                            .background(Color.appSurface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("퇴근 시간")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    HStack(spacing: 8) {
                        TextField("시", text: $endHourInput)
                            .keyboardType(.numberPad)
                            .foregroundColor(.appTextPrimary)
                            .multilineTextAlignment(.center)
                            .padding(10)
                            .background(Color.appSurface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                        Text(":")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        TextField("분", text: $endMinuteInput)
                            .keyboardType(.numberPad)
                            .foregroundColor(.appTextPrimary)
                            .multilineTextAlignment(.center)
                            .padding(10)
                            .background(Color.appSurface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                    }
                }
            }

            Text("퇴근이 출근보다 빠르면 다음날 퇴근으로 계산돼요.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.appTextSecondary)

            if let manualError {
                Text(manualError)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appWarning)
            }

            Button(action: {
                Task { await addManualWork() }
            }) {
                Text(isSavingManual ? "추가 중..." : "근무 추가")
            }
            .buttonStyle(PrimaryButtonStyle(backgroundColor: .appAccent))
            .disabled(isSavingManual)
            .opacity(isSavingManual ? 0.6 : 1.0)
        }
        .appCard()
    }

    @MainActor
    private func saveWage() async {
        #if canImport(Supabase)
        isSavingWage = true
        wageError = nil
        defer { isSavingWage = false }
        let digits = wageInput.filter { $0.isNumber }
        guard let wage = Double(digits), wage >= 0 else {
            wageError = "시급을 올바르게 입력해주세요."
            return
        }
        do {
            struct UpdatePayload: Encodable { let hourly_wage: Double }
            let payload = UpdatePayload(hourly_wage: wage)
            _ = try await SupabaseManager.shared
                .client
                .from("workers")
                .update(payload)
                .eq("id", value: worker.id.uuidString)
                .execute()
            await onUpdate()
        } catch {
            wageError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func savePayrollSettings() async {
        #if canImport(Supabase)
        isSavingPayroll = true
        payrollError = nil
        defer { isSavingPayroll = false }
        do {
            struct UpdatePayload: Encodable {
                let apply_weekly_allowance: Bool
                let deduction_type: String
                let apply_night_allowance: Bool
                let payday: Int
            }
            let payload = UpdatePayload(
                apply_weekly_allowance: applyWeeklyAllowance,
                deduction_type: deductionType.rawValue,
                apply_night_allowance: applyNightAllowance,
                payday: payday
            )
            _ = try await SupabaseManager.shared
                .client
                .from("workers")
                .update(payload)
                .eq("id", value: worker.id.uuidString)
                .execute()
            await onUpdate()
        } catch {
            let message = error.localizedDescription.lowercased()
            if message.contains("apply_night_allowance") || message.contains("payday") {
                do {
                    struct LegacyPayload: Encodable {
                        let apply_weekly_allowance: Bool
                        let deduction_type: String
                    }
                    let legacy = LegacyPayload(
                        apply_weekly_allowance: applyWeeklyAllowance,
                        deduction_type: deductionType.rawValue
                    )
                    _ = try await SupabaseManager.shared
                        .client
                        .from("workers")
                        .update(legacy)
                        .eq("id", value: worker.id.uuidString)
                        .execute()
                    payrollError = "야간수당/월급일 설정은 DB 마이그레이션 적용 후 저장돼요."
                    await onUpdate()
                } catch {
                    payrollError = AppErrorMessage.userMessage(error)
                }
            } else {
                payrollError = AppErrorMessage.userMessage(error)
            }
        }
        #endif
    }

    @MainActor
    private func loadOwnerRating() async {
        #if canImport(Supabase)
        ratingError = nil
        do {
            let ownerId = try await SupabaseManager.shared.currentUserId()
            let relatedWorkers = try await loadRelatedWorkersForPerson()
            let workerIdStrings = relatedWorkers.map { $0.id.uuidString }
            guard !workerIdStrings.isEmpty else { return }
            struct RatingRow: Decodable {
                let rating: Double
            }
            let rows: [RatingRow] = try await SupabaseManager.shared
                .client
                .from("worker_owner_ratings")
                .select("rating")
                .eq("owner_id", value: ownerId.uuidString)
                .in("worker_id", values: workerIdStrings)
                .execute()
                .value

            if !rows.isEmpty {
                let average = rows.map(\.rating).reduce(0, +) / Double(rows.count)
                ownerRatingInput = clampedHalfStep(average)
                evaluationSummary = applyOwnerRating(average, to: evaluationSummary)
            }
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            let message = error.localizedDescription.lowercased()
            if message.contains("worker_owner_ratings") {
                return
            }
            ratingError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func saveOwnerRating() async {
        #if canImport(Supabase)
        isSavingRating = true
        ratingError = nil
        defer { isSavingRating = false }

        do {
            let ownerId = try await SupabaseManager.shared.currentUserId()
            let relatedWorkers = try await loadRelatedWorkersForPerson()
            let workerIdStrings = relatedWorkers.map { $0.id.uuidString }
            guard !workerIdStrings.isEmpty else { return }

            struct ExistingRow: Decodable {
                let id: UUID
                let worker_id: UUID
            }
            struct UpdatePayload: Encodable { let rating: Double; let updated_at: String }
            struct InsertPayload: Encodable {
                let store_id: UUID
                let worker_id: UUID
                let owner_id: UUID
                let rating: Double
            }
            let iso = AppTime.iso
            let existing: [ExistingRow] = try await SupabaseManager.shared
                .client
                .from("worker_owner_ratings")
                .select("id,worker_id")
                .eq("owner_id", value: ownerId.uuidString)
                .in("worker_id", values: workerIdStrings)
                .execute()
                .value
            let existingByWorkerId = Dictionary(uniqueKeysWithValues: existing.map { ($0.worker_id, $0.id) })

            for relatedWorker in relatedWorkers {
                if let existingId = existingByWorkerId[relatedWorker.id] {
                    _ = try await SupabaseManager.shared
                        .client
                        .from("worker_owner_ratings")
                        .update(UpdatePayload(rating: clampedHalfStep(ownerRatingInput), updated_at: iso.string(from: Date())))
                        .eq("id", value: existingId.uuidString)
                        .execute()
                } else {
                    let payload = InsertPayload(
                        store_id: relatedWorker.store_id,
                        worker_id: relatedWorker.id,
                        owner_id: ownerId,
                        rating: clampedHalfStep(ownerRatingInput)
                    )
                    _ = try await SupabaseManager.shared
                        .client
                        .from("worker_owner_ratings")
                        .insert(payload)
                        .execute()
                }
            }
            evaluationSummary = applyOwnerRating(clampedHalfStep(ownerRatingInput), to: evaluationSummary)
            await onUpdate()
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            ratingError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private func applyOwnerRating(_ ownerRating: Double, to summary: WorkerEvaluationSummary?) -> WorkerEvaluationSummary {
        let base = summary ?? buildFallbackEvaluation(ownerRating: ownerRating)
        let hasMark = WorkerEvaluationPolicy.shouldGrantSincerityMark(
            isActive: worker.is_active ?? true,
            scheduledCount: base.scheduledCount,
            absentRate: base.absentRate,
            lateRate: base.lateRate,
            ownerRating: ownerRating
        )
        return WorkerEvaluationSummary(
            level: base.level,
            hasSincerityMark: hasMark,
            scheduledCount: base.scheduledCount,
            absentRate: base.absentRate,
            lateRate: base.lateRate,
            ownerRating: ownerRating
        )
    }

    private func buildFallbackEvaluation(ownerRating: Double?) -> WorkerEvaluationSummary {
        let joinedAt = parseJoinedAt(worker.joined_at) ?? Date()
        let level = WorkerGrowthLevel.from(joinedAt: joinedAt)
        let hasMark = WorkerEvaluationPolicy.shouldGrantSincerityMark(
            isActive: worker.is_active ?? true,
            scheduledCount: 0,
            absentRate: 0,
            lateRate: 0,
            ownerRating: ownerRating
        )
        return WorkerEvaluationSummary(
            level: level,
            hasSincerityMark: hasMark,
            scheduledCount: 0,
            absentRate: 0,
            lateRate: 0,
            ownerRating: ownerRating
        )
    }

    private struct RelatedWorkerIdentity: Decodable {
        let id: UUID
        let store_id: UUID
    }

    private func clampedHalfStep(_ value: Double) -> Double {
        let clamped = min(5.0, max(1.0, value))
        return (clamped * 2).rounded() / 2
    }

    private func starSymbol(for index: Int) -> String {
        let full = Double(index)
        let half = Double(index) - 0.5
        if ownerRatingInput >= full {
            return "star.fill"
        }
        if ownerRatingInput >= half {
            return "star.leadinghalf.filled"
        }
        return "star"
    }

    @MainActor
    private func processRetirement() async {
        #if canImport(Supabase)
        isProcessingRetirement = true
        retirementError = nil
        defer { isProcessingRetirement = false }
        do {
            struct UpdatePayload: Encodable {
                let is_active: Bool
            }
            _ = try await SupabaseManager.shared
                .client
                .from("workers")
                .update(UpdatePayload(is_active: false))
                .eq("id", value: worker.id.uuidString)
                .execute()
            await onUpdate()
            dismiss()
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            retirementError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func loadRelatedWorkersForPerson() async throws -> [RelatedWorkerIdentity] {
        #if canImport(Supabase)
        if let userId = worker.user_id {
            let rows: [RelatedWorkerIdentity] = try await SupabaseManager.shared
                .client
                .from("workers")
                .select("id,store_id")
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            if !rows.isEmpty {
                return rows
            }
        }
        #endif
        return [RelatedWorkerIdentity(id: worker.id, store_id: worker.store_id)]
    }

    @MainActor
    private func addManualWork() async {
        #if canImport(Supabase)
        isSavingManual = true
        manualError = nil
        defer { isSavingManual = false }

        let startHour = Int(startHourInput.filter { $0.isNumber }) ?? -1
        let startMinute = Int(startMinuteInput.filter { $0.isNumber }) ?? -1
        let endHour = Int(endHourInput.filter { $0.isNumber }) ?? -1
        let endMinute = Int(endMinuteInput.filter { $0.isNumber }) ?? -1

        guard (0...23).contains(startHour),
              (0...59).contains(startMinute),
              (0...23).contains(endHour),
              (0...59).contains(endMinute) else {
            manualError = "출근/퇴근 시간을 올바르게 입력해주세요. (예: 09시 30분)"
            return
        }

        let calendar = AppTime.calendar
        let dayStart = calendar.startOfDay(for: Date())
        guard let checkIn = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: dayStart),
              let sameDayEnd = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: dayStart) else {
            manualError = "시간 계산에 실패했어요. 다시 입력해주세요."
            return
        }

        guard checkIn != sameDayEnd else {
            manualError = "출근/퇴근 시간이 같아요. 시간을 다시 확인해주세요."
            return
        }

        let endDate: Date
        if sameDayEnd < checkIn {
            endDate = calendar.date(byAdding: .day, value: 1, to: sameDayEnd) ?? sameDayEnd
        } else {
            endDate = sameDayEnd
        }

        do {
            let ownerId = try await SupabaseManager.shared.currentUserId()
            struct InsertPayload: Encodable {
                let store_id: UUID
                let worker_id: UUID
                let check_in_at: String
                let check_out_at: String
                let status: String
                let approved_by: UUID
                let approved_at: String
            }
            let iso = AppTime.iso
            let payload = InsertPayload(
                store_id: worker.store_id,
                worker_id: worker.id,
                check_in_at: iso.string(from: checkIn),
                check_out_at: iso.string(from: endDate),
                status: "approved",
                approved_by: ownerId,
                approved_at: iso.string(from: endDate)
            )
            _ = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .insert(payload)
                .execute()
            startHourInput = ""
            startMinuteInput = ""
            endHourInput = ""
            endMinuteInput = ""
            await onUpdate()
        } catch {
            manualError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func updateLogDuration(_ log: WorkerManagementView.WorkLogRow) async {
        #if canImport(Supabase)
        isSavingEdit = true
        editError = nil
        defer { isSavingEdit = false }

        let h = Int(editHours.filter { $0.isNumber }) ?? 0
        let m = Int(editMinutes.filter { $0.isNumber }) ?? 0
        let totalMinutes = h * 60 + m
        guard totalMinutes > 0 else {
            editError = "근무 시간을 입력해주세요."
            return
        }

        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso
        let end = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) } ?? Date()
        let checkIn = end.addingTimeInterval(TimeInterval(-totalMinutes * 60))

        do {
            struct UpdatePayload: Encodable {
                let check_in_at: String
                let check_out_at: String
                let status: String
            }
            let payload = UpdatePayload(
                check_in_at: iso.string(from: checkIn),
                check_out_at: iso.string(from: end),
                status: "approved"
            )
            _ = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .update(payload)
                .eq("id", value: log.id.uuidString)
                .execute()
            editingLog = nil
            await onUpdate()
        } catch {
            editError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func deleteLog(_ log: WorkerManagementView.WorkLogRow) async {
        #if canImport(Supabase)
        do {
            _ = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .delete()
                .eq("id", value: log.id.uuidString)
                .execute()
            pendingDeleteLog = nil
            await onUpdate()
        } catch {
            editError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    // Duplicate helpers for self-contained View

    private func formatDate(_ isoString: String) -> String {
        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso
        let date = parser.date(from: isoString) ?? iso.date(from: isoString) ?? Date()
        let formatter = AppTime.displayFormatter("M월 d일")
        return formatter.string(from: date)
    }

    private func formatTimeRange(_ log: WorkerManagementView.WorkLogRow) -> String {
        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso
        let start = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
        let end = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
        let formatter = AppTime.displayFormatter("HH:mm")
        let startText = formatter.string(from: start)
        let endText = end.map { formatter.string(from: $0) } ?? "--:--"
        return "\(startText) - \(endText)"
    }


    private func totalMinutes() -> Int {
        monthLogs.reduce(0) { partial, log in
            partial + calcMinutes(checkIn: log.check_in_at, checkOut: log.check_out_at)
        }
    }
    
    private func calcMinutes(checkIn: String, checkOut: String?) -> Int {
        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso
        let start = parser.date(from: checkIn) ?? iso.date(from: checkIn) ?? Date()
        let end = checkOut.flatMap { parser.date(from: $0) ?? iso.date(from: $0) } ?? Date()
        // Floor to minute to avoid inflating time (e.g., 30 seconds shouldn't become +1 minute).
        let minutes = floor(end.timeIntervalSince(start) / 60.0)
        return max(0, Int(minutes))
    }

    private func calcPay(minutes: Int, wage: Double) -> Double {
        Double(minutes) / 60.0 * wage
    }

    private func monthGrossPay(wage: Double) -> Double {
        monthLogs.reduce(0) { partial, log in
            partial + logGrossPay(log, wage: wage)
        }
    }

    private func logGrossPay(_ log: WorkerManagementView.WorkLogRow, wage: Double) -> Double {
        let dates = parseWorkLogDates(checkIn: log.check_in_at, checkOut: log.check_out_at)
        return PayrollCalculator.grossPay(
            checkIn: dates.start,
            checkOut: dates.end,
            appliedHourlyWage: log.applied_hourly_wage,
            appliedNightAllowance: log.applied_night_allowance,
            fallbackHourlyWage: wage,
            fallbackNightAllowance: applyNightAllowance
        )
    }

    private func parseWorkLogDates(checkIn: String, checkOut: String?) -> (start: Date, end: Date?) {
        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso
        let start = parser.date(from: checkIn) ?? iso.date(from: checkIn) ?? Date()
        let end = checkOut.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
        return (start, end)
    }

    private func effectiveHourlyWage() -> Double {
        let digits = wageInput.filter { $0.isNumber }
        if let wage = Double(digits), wage >= 0 {
            return wage
        }
        return worker.hourly_wage ?? 0
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100.0)
    }

    private func estimateWeeklyAllowancePay(wage: Double) -> Double {
        PayrollCalculator.estimateWeeklyAllowancePay(
            checkInOut: monthLogs.map { ($0.check_in_at, $0.check_out_at) },
            wage: wage
        )
    }

    private func parseJoinedAt(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let parserWithFractional = AppTime.isoWithFractionalSeconds
        let parser = AppTime.iso
        return parserWithFractional.date(from: raw) ?? parser.date(from: raw)
    }
    
    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}
