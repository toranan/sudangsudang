import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct ScheduleManagementView: View {
    struct StoreOption: Decodable, Identifiable, Hashable {
        let id: UUID
        let name: String
    }

    struct WorkerOption: Decodable, Identifiable, Hashable {
        let id: UUID
        let name: String
        let is_active: Bool?
    }

    struct WorkerName: Decodable {
        let name: String
    }

    struct WeeklyTemplateRow: Decodable, Identifiable {
        let id: UUID
        let store_id: UUID
        let worker_id: UUID
        let weekday: Int
        let check_in_time: String
        let check_out_time: String?
        let is_active: Bool?
        let workers: WorkerName?
    }

    struct ScheduleEntryRow: Decodable, Identifiable {
        let id: UUID
        let store_id: UUID
        let worker_id: UUID
        let work_date: String
        let check_in_time: String
        let check_out_time: String?
        let source: String
        let template_id: UUID?
        let workers: WorkerName?
    }

    private enum EntryEditorContext: Identifiable {
        case create(date: Date)
        case edit(date: Date, row: ScheduleEntryRow)

        var id: String {
            switch self {
            case .create(let date):
                return "create:\(date.timeIntervalSince1970)"
            case .edit(_, let row):
                return "edit:\(row.id.uuidString)"
            }
        }

        var date: Date {
            switch self {
            case .create(let date):
                return date
            case .edit(let date, _):
                return date
            }
        }

        var row: ScheduleEntryRow? {
            switch self {
            case .create:
                return nil
            case .edit(_, let row):
                return row
            }
        }
    }

    private struct MonthDay: Identifiable {
        let id: String
        let date: Date?
    }

    @State private var stores: [StoreOption] = []
    @State private var selectedStoreId: UUID?
    @State private var workers: [WorkerOption] = []
    @State private var templates: [WeeklyTemplateRow] = []
    @State private var entries: [ScheduleEntryRow] = []
    // 매장·월별로 받아 둔 일정. 달을 넘길 때 먼저 보여주고 뒤에서 새로 받는다.
    @State private var monthEntriesCache: [String: [ScheduleEntryRow]] = [:]

    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date?

    @State private var isLoading = false
    @State private var isUserRefreshing = false
    @State private var loadError: String?

    @State private var lastStoresLoadedAt: Date?
    @State private var lastStoreScopedKey: String?
    @State private var lastStoreScopedLoadedAt: Date?
    @State private var lastMonthScopedKey: String?
    @State private var lastMonthScopedLoadedAt: Date?
    @State private var storesRequest = LatestRequest()
    @State private var storeScopedRequest = LatestRequest()
    @State private var monthScopedRequest = LatestRequest()

    @State private var entryEditorContext: EntryEditorContext?

    private let cacheTTLSeconds: TimeInterval = 120
    private let calendar = AppTime.calendar
    private let dayFormatter: DateFormatter = {
        let formatter = AppTime.displayFormatter("yyyy-MM-dd")
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("스케줄")
                        .font(.system(size: 26, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)

                if !stores.isEmpty {
                    storePicker
                }

                calendarGrid

                dayScheduleSection

                if let loadError {
                    Text(loadError)
                        .font(.app(.caption, .medium))
                        .foregroundColor(.appWarning)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .appRefreshable {
            await refreshFromUser()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .task {
            await refresh(force: false)
        }
        .onChange(of: selectedStoreId) { oldValue, _ in
            // 첫 선택(nil → 첫 매장)은 refresh()가 이어서 로드하므로 중복 요청을 건너뛴다.
            guard oldValue != nil else { return }
            Task { await loadStoreScopedData(force: true) }
        }
        .onChange(of: currentMonth) { _ in
            if let storeId = selectedStoreId,
               let cached = monthEntriesCache["\(storeId.uuidString)|\(monthCacheKey(currentMonth))"] {
                entries = cached
            }
            Task { await loadMonthScopedData(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await refresh(force: false) }
        }
        .sheet(item: $entryEditorContext) { context in
            ScheduleEntryEditorSheet(
                selectedDate: context.date,
                workers: workers,
                initialEntry: context.row,
                onSave: { draft in
                    Task {
                        await saveEntry(draft: draft, date: context.date, editing: context.row)
                    }
                }
            )
        }
    }

    private var storePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(stores) { store in
                    ScheduleChip(
                        title: store.name,
                        isSelected: store.id == selectedStoreId,
                        unselectedFill: .appSurface
                    ) {
                        selectedStoreId = store.id
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 8) {
            Text(monthTitle)
                .font(.system(size: 19, weight: .heavy))
                .tracking(-0.4)
                .foregroundColor(.appTextPrimary)

            Spacer()

            monthStepButton(systemImage: "chevron.left", value: -1)
            monthStepButton(systemImage: "chevron.right", value: 1)
        }
    }

    private func monthStepButton(systemImage: String, value: Int) -> some View {
        Button(action: {
            currentMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) ?? currentMonth
        }) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.appTextPrimary)
                .frame(width: 34, height: 34)
                .background(Color.appFill)
                .clipShape(Circle())
        }
        .buttonStyle(PressableRowStyle())
    }

    private var calendarGrid: some View {
        let days = makeMonthDays()
        let counts = entryCountsByDate

        return VStack(spacing: 14) {
            monthHeader

            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(["일", "월", "화", "수", "목", "금", "토"], id: \.self) { day in
                        Text(day)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.appTextSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                    ForEach(days) { day in
                        if let date = day.date {
                            let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                            let isToday = calendar.isDateInToday(date)
                            let count = counts[calendar.startOfDay(for: date)] ?? 0

                            Button(action: {
                                selectedDate = date
                            }) {
                                VStack(spacing: 3) {
                                    Text("\(calendar.component(.day, from: date))")
                                        .font(.system(size: 15, weight: isSelected || isToday ? .bold : .medium))
                                        .foregroundColor(isSelected ? .appOnInk : (isToday ? .appAccent : .appTextPrimary))
                                    Text(count > 0 ? "\(count)명" : " ")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(isSelected ? .appOnInk.opacity(0.75) : .appAccent)
                                }
                                .frame(maxWidth: .infinity, minHeight: 46)
                                .background(isSelected ? Color.appInk : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(height: 46)
                        }
                    }
                }
            }
        }
        .appCard()
    }

    private var dayScheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedDate {
                HStack {
                    Text(dayTitle(selectedDate))
                        .font(.system(size: 19, weight: .heavy))
                        .tracking(-0.4)
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    Button(action: { entryEditorContext = .create(date: selectedDate) }) {
                        Label("근무 추가", systemImage: "plus")
                            .labelStyle(AppButtonLabelStyle())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.appOnInk)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.appInk)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PressableRowStyle())
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)

                let dayEntries = entriesForDay(selectedDate)
                if dayEntries.isEmpty {
                    Text("등록된 근무가 없어요.")
                        .font(.app(.callout, .medium))
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(dayEntries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color.appLine)
                                    .frame(height: 1)
                            }
                            Button(action: {
                                entryEditorContext = .edit(date: selectedDate, row: entry)
                            }) {
                                let name = entry.workers?.name ?? workerName(entry.worker_id)
                                let isTemplate = entry.source == "template"
                                HStack(spacing: 12) {
                                    Text(String(name.prefix(1)))
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(isTemplate ? .appAccent : .appLavender)
                                        .frame(width: 40, height: 40)
                                        .background(isTemplate ? Color.appAccentSoft : Color.appLavenderSoft)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.appTextPrimary)
                                        Text(formatTimeRange(start: entry.check_in_time, end: entry.check_out_time))
                                            .font(.app(.caption))
                                            .foregroundColor(.appTextSecondary)
                                    }

                                    Spacer()

                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(isTemplate ? Color.appAccent : Color.appTextSecondary)
                                            .frame(width: 7, height: 7)
                                        Text(isTemplate ? "자동" : "수동")
                                            .font(.app(.caption, .semibold))
                                            .foregroundColor(isTemplate ? .appAccent : .appTextSecondary)
                                    }
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(PressableRowStyle())
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                }
            } else {
                Text("날짜를 선택하면 해당 일자의 근무자를 볼 수 있어요.")
                    .font(.app(.callout, .medium))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard()
            }
        }
    }

    private var monthTitle: String {
        let comps = calendar.dateComponents([.year, .month], from: currentMonth)
        return "\(comps.year ?? 0)년 \(comps.month ?? 0)월"
    }

    private var entryCountsByDate: [Date: Int] {
        var counts: [Date: Int] = [:]
        for entry in entries {
            guard let date = parseDay(entry.work_date) else { continue }
            let day = calendar.startOfDay(for: date)
            counts[day, default: 0] += 1
        }
        return counts
    }

    @MainActor
    private func refresh(force: Bool) async {
        await loadStores(force: force)
        await loadStoreScopedData(force: force)
    }

    @MainActor
    private func refreshFromUser() async {
        isUserRefreshing = true
        defer { isUserRefreshing = false }
        await refresh(force: true)
    }

    @MainActor
    private func loadStoreScopedData(force: Bool) async {
        guard let storeId = selectedStoreId else {
            storeScopedRequest.invalidate()
            monthScopedRequest.invalidate()
            workers = []
            templates = []
            entries = []
            selectedDate = nil
            return
        }

        let key = storeId.uuidString
        let now = Date()
        if !force,
           lastStoreScopedKey == key,
           let lastStoreScopedLoadedAt,
           now.timeIntervalSince(lastStoreScopedLoadedAt) < cacheTTLSeconds {
            return
        }

        let requestID = storeScopedRequest.begin()
        await loadWorkers(storeId: storeId, requestID: requestID)
        guard isCurrentStoreRequest(requestID, storeId: storeId) else { return }
        await loadTemplates(storeId: storeId, requestID: requestID)
        guard isCurrentStoreRequest(requestID, storeId: storeId) else { return }
        await loadMonthScopedData(force: force)
        guard isCurrentStoreRequest(requestID, storeId: storeId) else { return }
        lastStoreScopedKey = key
        lastStoreScopedLoadedAt = Date()
    }

    @MainActor
    private func loadMonthScopedData(force: Bool) async {
        guard let storeId = selectedStoreId else {
            monthScopedRequest.invalidate()
            entries = []
            selectedDate = nil
            return
        }

        let requestedMonth = currentMonth
        let key = "\(storeId.uuidString)|\(monthCacheKey(requestedMonth))"
        let now = Date()
        if !force,
           lastMonthScopedKey == key,
           let lastMonthScopedLoadedAt,
           now.timeIntervalSince(lastMonthScopedLoadedAt) < cacheTTLSeconds {
            return
        }

        let requestID = monthScopedRequest.begin()
        let requestedTemplates = templates
        await ensureTemplateEntries(
            storeId: storeId,
            month: requestedMonth,
            templates: requestedTemplates,
            requestID: requestID,
            key: key
        )
        guard isCurrentMonthRequest(requestID, key: key) else { return }
        await loadEntries(storeId: storeId, month: requestedMonth, requestID: requestID, key: key)
        guard isCurrentMonthRequest(requestID, key: key) else { return }
        lastMonthScopedKey = key
        lastMonthScopedLoadedAt = Date()
    }

    private func isCurrentStoreRequest(_ requestID: UUID, storeId: UUID) -> Bool {
        storeScopedRequest.isCurrent(requestID) && selectedStoreId == storeId
    }

    private func isCurrentMonthRequest(_ requestID: UUID, key: String) -> Bool {
        guard let storeId = selectedStoreId else { return false }
        let currentKey = "\(storeId.uuidString)|\(monthCacheKey(currentMonth))"
        return monthScopedRequest.isCurrent(requestID) && currentKey == key
    }

    @MainActor
    private func loadStores(force: Bool) async {
        #if canImport(Supabase)
        let now = Date()
        if !force,
           !stores.isEmpty,
           selectedStoreId != nil,
           let lastStoresLoadedAt,
           now.timeIntervalSince(lastStoresLoadedAt) < cacheTTLSeconds {
            return
        }
        let requestID = storesRequest.begin()
        do {
            loadError = nil
            let ownerId = try await SupabaseManager.shared.currentUserId()
            let rows: [StoreOption] = try await SupabaseManager.shared
                .client
                .from("stores")
                .select("id,name")
                .eq("owner_id", value: ownerId.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value

            guard storesRequest.isCurrent(requestID) else { return }
            stores = rows
            lastStoresLoadedAt = Date()
            if selectedStoreId == nil || !rows.contains(where: { $0.id == selectedStoreId }) {
                selectedStoreId = rows.first?.id
            }
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard storesRequest.isCurrent(requestID) else { return }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func loadWorkers(storeId: UUID, requestID: UUID) async {
        #if canImport(Supabase)
        do {
            let rows: [WorkerOption] = try await SupabaseManager.shared
                .client
                .from("workers")
                .select("id,name,is_active")
                .eq("store_id", value: storeId.uuidString)
                .order("name", ascending: true)
                .execute()
                .value

            guard isCurrentStoreRequest(requestID, storeId: storeId) else { return }
            workers = rows.filter { $0.is_active ?? true }
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard isCurrentStoreRequest(requestID, storeId: storeId) else { return }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func loadTemplates(storeId: UUID, requestID: UUID) async {
        #if canImport(Supabase)
        do {
            let rows: [WeeklyTemplateRow] = try await SupabaseManager.shared
                .client
                .from("schedule_templates")
                .select("id,store_id,worker_id,weekday,check_in_time,check_out_time,is_active,workers(name)")
                .eq("store_id", value: storeId.uuidString)
                .eq("is_active", value: true)
                .order("weekday", ascending: true)
                .order("check_in_time", ascending: true)
                .execute()
                .value

            guard isCurrentStoreRequest(requestID, storeId: storeId) else { return }
            templates = rows
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard isCurrentStoreRequest(requestID, storeId: storeId) else { return }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func ensureTemplateEntries(
        storeId: UUID,
        month: Date,
        templates: [WeeklyTemplateRow],
        requestID: UUID,
        key: String
    ) async {
        let activeTemplates = templates.filter { $0.is_active ?? true }
        guard !activeTemplates.isEmpty else { return }

        #if canImport(Supabase)
        do {
            let monthStart = firstDay(of: month)
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            let startText = dayFormatter.string(from: monthStart)
            let endText = dayFormatter.string(from: monthEnd)

            struct ExistingSeed: Decodable {
                let template_id: UUID?
                let work_date: String
            }

            let existingRows: [ExistingSeed] = try await SupabaseManager.shared
                .client
                .from("schedule_entries")
                .select("template_id,work_date")
                .eq("store_id", value: storeId.uuidString)
                .gte("work_date", value: startText)
                .lt("work_date", value: endText)
                .execute()
                .value

            var existingKeys = Set<String>()
            for row in existingRows {
                guard let templateId = row.template_id else { continue }
                existingKeys.insert("\(templateId.uuidString)|\(row.work_date)")
            }

            let ownerId = try await SupabaseManager.shared.currentUserId()

            struct InsertPayload: Encodable {
                let store_id: UUID
                let worker_id: UUID
                let work_date: String
                let check_in_time: String
                let check_out_time: String?
                let source: String
                let template_id: UUID
                let created_by: UUID
            }

            var inserts: [InsertPayload] = []
            var cursor = monthStart
            while cursor < monthEnd {
                let weekday = (calendar.component(.weekday, from: cursor) + 6) % 7
                let workDate = dayFormatter.string(from: cursor)

                for template in activeTemplates where template.weekday == weekday {
                    let key = "\(template.id.uuidString)|\(workDate)"
                    guard !existingKeys.contains(key) else { continue }
                    existingKeys.insert(key)
                    inserts.append(
                        InsertPayload(
                            store_id: storeId,
                            worker_id: template.worker_id,
                            work_date: workDate,
                            check_in_time: template.check_in_time,
                            check_out_time: template.check_out_time,
                            source: "template",
                            template_id: template.id,
                            created_by: ownerId
                        )
                    )
                }

                cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? monthEnd
            }

            if !inserts.isEmpty {
                guard isCurrentMonthRequest(requestID, key: key) else { return }
                _ = try await SupabaseManager.shared
                    .client
                    .from("schedule_entries")
                    .insert(inserts)
                    .execute()
            }
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            let message = error.localizedDescription.lowercased()
            if message.contains("duplicate key") {
                return
            }
            guard isCurrentMonthRequest(requestID, key: key) else { return }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func loadEntries(storeId: UUID, month: Date, requestID: UUID, key: String) async {
        #if canImport(Supabase)
        isLoading = true
        defer {
            if isCurrentMonthRequest(requestID, key: key) {
                isLoading = false
            }
        }
        do {
            loadError = nil
            let monthStart = firstDay(of: month)
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
            let startText = dayFormatter.string(from: monthStart)
            let endText = dayFormatter.string(from: monthEnd)

            let rows: [ScheduleEntryRow] = try await SupabaseManager.shared
                .client
                .from("schedule_entries")
                .select("id,store_id,worker_id,work_date,check_in_time,check_out_time,source,template_id,workers(name)")
                .eq("store_id", value: storeId.uuidString)
                .gte("work_date", value: startText)
                .lt("work_date", value: endText)
                .order("work_date", ascending: true)
                .order("check_in_time", ascending: true)
                .execute()
                .value

            guard isCurrentMonthRequest(requestID, key: key) else { return }
            monthEntriesCache[key] = rows
            withAnimation(.easeOut(duration: 0.2)) {
                entries = rows
            }

            if let selectedDate,
               calendar.isDate(selectedDate, equalTo: month, toGranularity: .month) {
                // keep current selection
            } else {
                if calendar.isDate(Date(), equalTo: month, toGranularity: .month) {
                    selectedDate = Date()
                } else {
                    selectedDate = monthStart
                }
            }
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard isCurrentMonthRequest(requestID, key: key) else { return }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func saveEntry(
        draft: ScheduleEntryEditorSheet.Draft,
        date: Date,
        editing: ScheduleEntryRow?
    ) async {
        guard let storeId = selectedStoreId else { return }

        #if canImport(Supabase)
        do {
            if let editing {
                struct UpdatePayload: Encodable {
                    let worker_id: UUID
                    let check_in_time: String
                    let check_out_time: String?
                    let updated_at: String
                }
                let payload = UpdatePayload(
                    worker_id: draft.workerId,
                    check_in_time: draft.checkInTime,
                    check_out_time: draft.checkOutTime,
                    updated_at: AppTime.isoString(from: Date())
                )
                _ = try await SupabaseManager.shared
                    .client
                    .from("schedule_entries")
                    .update(payload)
                    .eq("id", value: editing.id.uuidString)
                    .execute()
            } else {
                struct InsertPayload: Encodable {
                    let store_id: UUID
                    let worker_id: UUID
                    let work_date: String
                    let check_in_time: String
                    let check_out_time: String?
                    let source: String
                    let created_by: UUID
                }
                let ownerId = try await SupabaseManager.shared.currentUserId()
                let payload = InsertPayload(
                    store_id: storeId,
                    worker_id: draft.workerId,
                    work_date: dayFormatter.string(from: date),
                    check_in_time: draft.checkInTime,
                    check_out_time: draft.checkOutTime,
                    source: "manual",
                    created_by: ownerId
                )
                _ = try await SupabaseManager.shared
                    .client
                    .from("schedule_entries")
                    .insert(payload)
                    .execute()
            }

            entryEditorContext = nil
            await loadMonthScopedData(force: true)
        } catch {
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private func entriesForDay(_ date: Date) -> [ScheduleEntryRow] {
        let day = calendar.startOfDay(for: date)
        return entries
            .filter {
                guard let parsed = parseDay($0.work_date) else { return false }
                return calendar.isDate(parsed, inSameDayAs: day)
            }
            .sorted { lhs, rhs in
                if lhs.check_in_time == rhs.check_in_time {
                    return workerName(lhs.worker_id) < workerName(rhs.worker_id)
                }
                return lhs.check_in_time < rhs.check_in_time
            }
    }

    private func makeMonthDays() -> [MonthDay] {
        var items: [MonthDay] = []
        let start = firstDay(of: currentMonth)
        let range = calendar.range(of: .day, in: .month, for: start) ?? 1..<2
        let firstWeekday = calendar.component(.weekday, from: start)
        let leadingEmpty = (firstWeekday + 6) % 7

        for index in 0..<leadingEmpty {
            items.append(MonthDay(id: "leading-\(index)", date: nil))
        }

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: start) {
                items.append(MonthDay(id: "day-\(day)", date: date))
            }
        }

        // 달마다 4~6주로 줄 수가 달라 높이가 흔들리지 않게 항상 6주(42칸)로 채운다.
        while items.count < 42 {
            items.append(MonthDay(id: "trailing-\(items.count)", date: nil))
        }

        return items
    }

    private func firstDay(of date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func monthCacheKey(_ date: Date) -> String {
        dayFormatter.string(from: firstDay(of: date))
    }

    private func parseDay(_ raw: String) -> Date? {
        dayFormatter.date(from: raw)
    }

    private func workerName(_ workerId: UUID) -> String {
        workers.first(where: { $0.id == workerId })?.name ?? "알바생"
    }

    private func weekdayLabel(_ weekday: Int) -> String {
        switch weekday {
        case 0: return "일"
        case 1: return "월"
        case 2: return "화"
        case 3: return "수"
        case 4: return "목"
        case 5: return "금"
        case 6: return "토"
        default: return "-"
        }
    }

    private func dayTitle(_ date: Date) -> String {
        let comps = calendar.dateComponents([.month, .day], from: date)
        return "\(comps.month ?? 0)월 \(comps.day ?? 0)일 근무"
    }

    private func formatTime(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 5 {
            return String(trimmed.prefix(5))
        }
        return trimmed
    }

    private func formatTimeRange(start: String, end: String?) -> String {
        let startText = formatTime(start)
        let endText: String
        if let end, !end.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            endText = formatTime(end)
        } else {
            endText = "미정"
        }
        return "\(startText) ~ \(endText)"
    }
}

private struct ScheduleEntryEditorSheet: View {
    struct Draft {
        let workerId: UUID
        let checkInTime: String
        let checkOutTime: String?
    }

    let selectedDate: Date
    let workers: [ScheduleManagementView.WorkerOption]
    let initialEntry: ScheduleManagementView.ScheduleEntryRow?
    let onSave: (Draft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var workerId: UUID?
    @State private var startHour: String = ""
    @State private var startMinute: String = ""
    @State private var endHour: String = ""
    @State private var endMinute: String = ""
    @State private var error: String?

    private let calendar = AppTime.calendar

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ScheduleCloseButton { dismiss() }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(initialEntry == nil ? "근무 추가" : "근무 수정")
                            .font(.system(size: 26, weight: .heavy))
                            .tracking(-0.6)
                            .foregroundColor(.appTextPrimary)
                        Text(dayTitle)
                            .font(.app(.callout, .medium))
                            .foregroundColor(.appTextSecondary)
                    }

                    timeInputSection

                    if let error {
                        Text(error)
                            .font(.app(.caption, .medium))
                            .foregroundColor(.appWarning)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            Button(action: save) {
                Text(initialEntry == nil ? "근무 추가" : "근무 저장")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(workers.isEmpty)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color.appSurface)
        }
        .background(Color.appSurface.ignoresSafeArea())
        .task {
            applyInitialValue()
        }
    }

    private var dayTitle: String {
        let comps = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        return "\(comps.year ?? 0)년 \(comps.month ?? 0)월 \(comps.day ?? 0)일"
    }

    private var timeInputSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                ScheduleFieldLabel(text: "근무자")

                if workers.isEmpty {
                    Text("등록된 알바가 없어요. 먼저 알바관리에서 알바를 등록해주세요.")
                        .font(.app(.callout))
                        .foregroundColor(.appTextSecondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appFill)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.field, style: .continuous))
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(workers) { worker in
                                ScheduleChip(
                                    title: worker.name,
                                    isSelected: (workerId ?? workers.first?.id) == worker.id
                                ) {
                                    workerId = worker.id
                                }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        ScheduleFieldLabel(text: "출근")
                        timeField(hour: $startHour, minute: $startMinute)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ScheduleFieldLabel(text: "퇴근 (선택)")
                        timeField(hour: $endHour, minute: $endMinute)
                    }
                }

                Text("퇴근 시간은 비워둘 수 있어요.")
                    .font(.app(.caption))
                    .foregroundColor(.appTextSecondary)
            }
        }
    }

    private func timeField(hour: Binding<String>, minute: Binding<String>) -> some View {
        HStack(spacing: 2) {
            TextField("시", text: hour)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
            Text(":")
                .foregroundColor(.appTextSecondary)
            TextField("분", text: minute)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
        }
        .font(.system(size: 20, weight: .bold))
        .foregroundColor(.appTextPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(Color.appFill)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.field, style: .continuous))
    }

    private func applyInitialValue() {
        workerId = initialEntry?.worker_id ?? workers.first?.id

        let start = parseTime(initialEntry?.check_in_time)
        startHour = start.hour
        startMinute = start.minute

        let end = parseTime(initialEntry?.check_out_time)
        endHour = end.hour
        endMinute = end.minute
    }

    private func parseTime(_ raw: String?) -> (hour: String, minute: String) {
        guard let raw else { return ("", "") }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let comps = trimmed.split(separator: ":")
        guard comps.count >= 2 else { return ("", "") }
        return (String(comps[0]), String(comps[1]))
    }

    private func save() {
        error = nil

        guard let workerId else {
            error = "근무자를 선택해주세요."
            return
        }

        guard let checkInTime = buildRequiredTime(hour: startHour, minute: startMinute) else {
            error = "출근 시간을 올바르게 입력해주세요."
            return
        }

        let checkOut = buildOptionalTime(hour: endHour, minute: endMinute)
        guard checkOut.isValid else {
            error = "퇴근 시간을 올바르게 입력해주세요."
            return
        }

        onSave(
            Draft(
                workerId: workerId,
                checkInTime: checkInTime,
                checkOutTime: checkOut.value
            )
        )
        dismiss()
    }

    private func buildRequiredTime(hour: String, minute: String) -> String? {
        guard let h = Int(hour.filter { $0.isNumber }),
              let m = Int(minute.filter { $0.isNumber }),
              (0...23).contains(h),
              (0...59).contains(m) else {
            return nil
        }
        return String(format: "%02d:%02d:00", h, m)
    }

    private func buildOptionalTime(hour: String, minute: String) -> (isValid: Bool, value: String?) {
        let hText = hour.trimmingCharacters(in: .whitespacesAndNewlines)
        let mText = minute.trimmingCharacters(in: .whitespacesAndNewlines)
        if hText.isEmpty && mText.isEmpty {
            return (true, nil)
        }
        guard let built = buildRequiredTime(hour: hour, minute: minute) else {
            return (false, nil)
        }
        return (true, built)
    }
}

// 매장, 근무자 선택에 쓰는 알약 칩. 선택되면 검정으로 채운다.
private struct ScheduleChip: View {
    let title: String
    let isSelected: Bool
    var unselectedFill: Color = .appFill
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? .appOnInk : .appTextSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSelected ? Color.appInk : unselectedFill)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ScheduleCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.appTextPrimary)
                .frame(width: 40, height: 40)
                .background(Color.appFill)
                .clipShape(Circle())
        }
        .accessibilityLabel("닫기")
    }
}

private struct ScheduleFieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.appTextSecondary)
    }
}
