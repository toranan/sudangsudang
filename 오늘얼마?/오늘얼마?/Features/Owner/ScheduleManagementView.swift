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

    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date?

    @State private var isLoading = false
    @State private var isUserRefreshing = false
    @State private var loadError: String?

    @State private var lastStoresLoadedAt: Date?
    @State private var lastStoreScopedKey: String?
    @State private var lastStoreScopedLoadedAt: Date?
    @State private var loadingStoreScopedKey: String?
    @State private var lastMonthScopedKey: String?
    @State private var lastMonthScopedLoadedAt: Date?
    @State private var loadingMonthScopedKey: String?

    @State private var isPresentingTemplateManager = false
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
                if !stores.isEmpty {
                    storePicker
                }

                templateSection

                monthHeader

                calendarGrid

                dayScheduleSection

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
        .task {
            await refresh(force: false)
        }
        .onChange(of: selectedStoreId) { _ in
            Task { await loadStoreScopedData(force: true) }
        }
        .onChange(of: currentMonth) { _ in
            Task { await loadMonthScopedData(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await refresh(force: false) }
        }
        .sheet(isPresented: $isPresentingTemplateManager) {
            TemplateManagementSheet(
                workers: workers,
                templates: templates,
                onSave: { draft, editing in
                    await saveTemplate(draft: draft, editing: editing)
                },
                onDelete: { template in
                    await deactivateTemplate(template)
                },
                workerName: { workerId in
                    workerName(workerId)
                },
                formatTimeRange: { start, end in
                    formatTimeRange(start: start, end: end)
                },
                weekdayLabel: { weekday in
                    weekdayLabel(weekday)
                }
            )
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
            HStack(spacing: 8) {
                ForEach(stores) { store in
                    let isSelected = store.id == selectedStoreId
                    Button(action: { selectedStoreId = store.id }) {
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
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var templateSection: some View {
        HStack(spacing: 12) {
            Text("주간 설정")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.appTextPrimary)

            Spacer()

            Button("설정하기") {
                isPresentingTemplateManager = true
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundColor(.appAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.appSurface)
            .cornerRadius(999)
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    .stroke(Color.appLine, lineWidth: 1)
            )
        }
        .appCard()
    }

    private var monthHeader: some View {
        HStack(spacing: 12) {
            Button(action: {
                currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
            }) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(SecondaryButtonStyle())

            Text(monthTitle)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.appTextPrimary)

            Button(action: {
                currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
            }) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(SecondaryButtonStyle())

            Spacer()

            if isLoading {
                ProgressView()
            }
        }
    }

    private var calendarGrid: some View {
        let days = makeMonthDays()
        let counts = entryCountsByDate

        return VStack(spacing: 8) {
            HStack {
                ForEach(["일", "월", "화", "수", "목", "금", "토"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(days) { day in
                    if let date = day.date {
                        let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                        let count = counts[calendar.startOfDay(for: date)] ?? 0

                        Button(action: {
                            selectedDate = date
                        }) {
                            VStack(spacing: 4) {
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(isSelected ? .white : .appTextPrimary)
                                if count > 0 {
                                    Text("\(count)명")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundColor(isSelected ? .white.opacity(0.9) : .appTextSecondary)
                                } else {
                                    Text(" ")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.appAccent : Color.appSurface)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .appCard()
    }

    private var dayScheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedDate {
                SectionHeader(title: dayTitle(selectedDate), trailing: "근무 추가") {
                    entryEditorContext = .create(date: selectedDate)
                }

                let dayEntries = entriesForDay(selectedDate)
                if dayEntries.isEmpty {
                    Text("등록된 근무가 없어요.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                        .appCard()
                } else {
                    VStack(spacing: 10) {
                        ForEach(dayEntries) { entry in
                            Button(action: {
                                entryEditorContext = .edit(date: selectedDate, row: entry)
                            }) {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.workers?.name ?? workerName(entry.worker_id))
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundColor(.appTextPrimary)
                                        Text(formatTimeRange(start: entry.check_in_time, end: entry.check_out_time))
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(.appTextSecondary)
                                    }

                                    Spacer()

                                    StatusPill(
                                        text: entry.source == "template" ? "자동" : "수동",
                                        color: entry.source == "template" ? .appAccent : .appTextSecondary
                                    )
                                }
                                .padding(12)
                                .background(Color.appSurface)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.appLine, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .appCard()
                }
            } else {
                Text("날짜를 선택하면 해당 일자의 근무자를 볼 수 있어요.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
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
            workers = []
            templates = []
            entries = []
            selectedDate = nil
            return
        }

        let key = storeId.uuidString
        let now = Date()
        if loadingStoreScopedKey == key { return }
        if !force,
           lastStoreScopedKey == key,
           let lastStoreScopedLoadedAt,
           now.timeIntervalSince(lastStoreScopedLoadedAt) < cacheTTLSeconds {
            return
        }

        loadingStoreScopedKey = key
        defer { loadingStoreScopedKey = nil }
        await loadWorkers()
        await loadTemplates()
        await loadMonthScopedData(force: force)
        lastStoreScopedKey = key
        lastStoreScopedLoadedAt = Date()
    }

    @MainActor
    private func loadMonthScopedData(force: Bool) async {
        guard let storeId = selectedStoreId else {
            entries = []
            selectedDate = nil
            return
        }

        let key = "\(storeId.uuidString)|\(monthCacheKey(currentMonth))"
        let now = Date()
        if loadingMonthScopedKey == key { return }
        if !force,
           lastMonthScopedKey == key,
           let lastMonthScopedLoadedAt,
           now.timeIntervalSince(lastMonthScopedLoadedAt) < cacheTTLSeconds {
            return
        }

        loadingMonthScopedKey = key
        defer { loadingMonthScopedKey = nil }
        await ensureTemplateEntriesForCurrentMonth()
        await loadEntries()
        lastMonthScopedKey = key
        lastMonthScopedLoadedAt = Date()
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

            stores = rows
            lastStoresLoadedAt = Date()
            if selectedStoreId == nil || !rows.contains(where: { $0.id == selectedStoreId }) {
                selectedStoreId = rows.first?.id
            }
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func loadWorkers() async {
        guard let storeId = selectedStoreId else {
            workers = []
            return
        }
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

            workers = rows.filter { $0.is_active ?? true }
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func loadTemplates() async {
        guard let storeId = selectedStoreId else {
            templates = []
            return
        }
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

            templates = rows
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func ensureTemplateEntriesForCurrentMonth() async {
        guard let storeId = selectedStoreId else { return }
        let activeTemplates = templates.filter { $0.is_active ?? true }
        guard !activeTemplates.isEmpty else { return }

        #if canImport(Supabase)
        do {
            let monthStart = firstDay(of: currentMonth)
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
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func loadEntries() async {
        guard let storeId = selectedStoreId else {
            entries = []
            selectedDate = nil
            return
        }

        #if canImport(Supabase)
        isLoading = true
        defer { isLoading = false }
        do {
            loadError = nil
            let monthStart = firstDay(of: currentMonth)
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

            entries = rows

            if let selectedDate,
               calendar.isDate(selectedDate, equalTo: currentMonth, toGranularity: .month) {
                // keep current selection
            } else {
                if calendar.isDate(Date(), equalTo: currentMonth, toGranularity: .month) {
                    selectedDate = Date()
                } else {
                    selectedDate = monthStart
                }
            }
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func saveTemplate(
        draft: TemplateEditorSheet.Draft,
        editing: WeeklyTemplateRow?
    ) async {
        guard let storeId = selectedStoreId else { return }

        #if canImport(Supabase)
        do {
            if let editing {
                struct UpdatePayload: Encodable {
                    let worker_id: UUID
                    let weekday: Int
                    let check_in_time: String
                    let check_out_time: String?
                    let updated_at: String
                }
                let payload = UpdatePayload(
                    worker_id: draft.workerId,
                    weekday: draft.weekday,
                    check_in_time: draft.checkInTime,
                    check_out_time: draft.checkOutTime,
                    updated_at: AppTime.isoString(from: Date())
                )
                _ = try await SupabaseManager.shared
                    .client
                    .from("schedule_templates")
                    .update(payload)
                    .eq("id", value: editing.id.uuidString)
                    .execute()
            } else {
                struct InsertPayload: Encodable {
                    let store_id: UUID
                    let worker_id: UUID
                    let weekday: Int
                    let check_in_time: String
                    let check_out_time: String?
                    let is_active: Bool
                    let created_by: UUID
                }
                let ownerId = try await SupabaseManager.shared.currentUserId()
                let payload = InsertPayload(
                    store_id: storeId,
                    worker_id: draft.workerId,
                    weekday: draft.weekday,
                    check_in_time: draft.checkInTime,
                    check_out_time: draft.checkOutTime,
                    is_active: true,
                    created_by: ownerId
                )
                _ = try await SupabaseManager.shared
                    .client
                    .from("schedule_templates")
                    .insert(payload)
                    .execute()
            }

            await loadTemplates()
            await loadMonthScopedData(force: true)
        } catch {
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func deactivateTemplate(_ template: WeeklyTemplateRow) async {
        #if canImport(Supabase)
        do {
            struct UpdatePayload: Encodable {
                let is_active: Bool
                let updated_at: String
            }
            let payload = UpdatePayload(
                is_active: false,
                updated_at: AppTime.isoString(from: Date())
            )

            _ = try await SupabaseManager.shared
                .client
                .from("schedule_templates")
                .update(payload)
                .eq("id", value: template.id.uuidString)
                .execute()

            // Future generated schedules from this template are removed.
            let todayText = dayFormatter.string(from: calendar.startOfDay(for: Date()))
            _ = try await SupabaseManager.shared
                .client
                .from("schedule_entries")
                .delete()
                .eq("template_id", value: template.id.uuidString)
                .gte("work_date", value: todayText)
                .execute()

            await loadTemplates()
            await loadEntries()
            lastMonthScopedKey = nil
            lastMonthScopedLoadedAt = nil
        } catch {
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
            await loadEntries()
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

        while items.count % 7 != 0 {
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

private struct TemplateManagementSheet: View {
    private enum EditorContext: Identifiable {
        case create
        case edit(ScheduleManagementView.WeeklyTemplateRow)

        var id: String {
            switch self {
            case .create:
                return "create"
            case .edit(let template):
                return "edit:\(template.id.uuidString)"
            }
        }

        var template: ScheduleManagementView.WeeklyTemplateRow? {
            switch self {
            case .create:
                return nil
            case .edit(let template):
                return template
            }
        }
    }

    let workers: [ScheduleManagementView.WorkerOption]
    let templates: [ScheduleManagementView.WeeklyTemplateRow]
    let onSave: (TemplateEditorSheet.Draft, ScheduleManagementView.WeeklyTemplateRow?) async -> Void
    let onDelete: (ScheduleManagementView.WeeklyTemplateRow) async -> Void
    let workerName: (UUID) -> String
    let formatTimeRange: (String, String?) -> String
    let weekdayLabel: (Int) -> String

    @Environment(\.dismiss) private var dismiss
    @State private var editorContext: EditorContext?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if templates.isEmpty {
                        Text("주간 설정이 없어요. 추가하면 자동으로 스케줄이 생성돼요.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                            .appCard()
                    } else {
                        VStack(spacing: 10) {
                            ForEach(sortedWeekdays, id: \.self) { weekday in
                                let dayTemplates = templates(for: weekday)

                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 8) {
                                        Text("\(weekdayLabel(weekday))요일")
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundColor(.appTextPrimary)

                                        Text("\(dayTemplates.count)건")
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            .foregroundColor(.appAccent)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.appAccent.opacity(0.12))
                                            .cornerRadius(999)

                                        Spacer()
                                    }

                                    VStack(spacing: 8) {
                                        ForEach(dayTemplates) { template in
                                            templateRow(template)
                                        }
                                    }
                                }
                                .appCard()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("주간 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("추가") {
                        editorContext = .create
                    }
                    .disabled(workers.isEmpty)
                }
            }
        }
        .sheet(item: $editorContext) { context in
            TemplateEditorSheet(
                workers: workers,
                initialTemplate: context.template,
                onSave: { draft in
                    Task {
                        await onSave(draft, context.template)
                    }
                }
            )
        }
    }

    private func templateRow(_ template: ScheduleManagementView.WeeklyTemplateRow) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.workers?.name ?? workerName(template.worker_id))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                Text(formatTimeRange(template.check_in_time, template.check_out_time))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            Menu {
                Button("수정") {
                    editorContext = .edit(template)
                }
                Button("삭제", role: .destructive) {
                    Task { await onDelete(template) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.appTextSecondary)
                    .padding(6)
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

    private var sortedWeekdays: [Int] {
        Array(groupedTemplates.keys).sorted()
    }

    private var groupedTemplates: [Int: [ScheduleManagementView.WeeklyTemplateRow]] {
        Dictionary(grouping: templates, by: \.weekday)
    }

    private func templates(for weekday: Int) -> [ScheduleManagementView.WeeklyTemplateRow] {
        (groupedTemplates[weekday] ?? []).sorted { lhs, rhs in
            if lhs.check_in_time == rhs.check_in_time {
                return workerName(lhs.worker_id) < workerName(rhs.worker_id)
            }
            return lhs.check_in_time < rhs.check_in_time
        }
    }
}

private struct TemplateEditorSheet: View {
    struct Draft {
        let workerId: UUID
        let weekday: Int
        let checkInTime: String
        let checkOutTime: String?
    }

    let workers: [ScheduleManagementView.WorkerOption]
    let initialTemplate: ScheduleManagementView.WeeklyTemplateRow?
    let onSave: (Draft) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var workerId: UUID?
    @State private var weekday: Int = 1
    @State private var startHour: String = ""
    @State private var startMinute: String = ""
    @State private var endHour: String = ""
    @State private var endMinute: String = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("요일")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextPrimary)

                        Picker("요일", selection: $weekday) {
                            Text("일").tag(0)
                            Text("월").tag(1)
                            Text("화").tag(2)
                            Text("수").tag(3)
                            Text("목").tag(4)
                            Text("금").tag(5)
                            Text("토").tag(6)
                        }
                        .pickerStyle(.segmented)
                    }
                    .appCard()

                    timeInputSection

                    if let error {
                        Text(error)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appWarning)
                    }

                    Button(action: save) {
                        Text(initialTemplate == nil ? "템플릿 추가" : "템플릿 저장")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(workers.isEmpty)
                    .opacity(workers.isEmpty ? 0.5 : 1.0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(initialTemplate == nil ? "주간 설정 추가" : "주간 설정 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
            .task {
                applyInitialValue()
            }
        }
    }

    private var timeInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("시간")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.appTextPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("근무자")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)

                if workers.isEmpty {
                    Text("등록된 알바가 없어요. 먼저 알바관리에서 알바를 등록해주세요.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                } else {
                    Picker("근무자", selection: Binding(
                        get: { workerId ?? workers.first?.id },
                        set: { workerId = $0 }
                    )) {
                        ForEach(workers) { worker in
                            Text(worker.name).tag(Optional(worker.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("출근 시간 (필수)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    timeField(hour: $startHour, minute: $startMinute)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("퇴근 시간 (선택)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    timeField(hour: $endHour, minute: $endMinute)
                }
            }

            Text("퇴근 시간은 비워둘 수 있어요.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.appTextSecondary)
        }
        .appCard()
    }

    private func timeField(hour: Binding<String>, minute: Binding<String>) -> some View {
        HStack(spacing: 8) {
            TextField("시", text: hour)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .foregroundColor(.appTextPrimary)
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
            TextField("분", text: minute)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
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

    private func applyInitialValue() {
        workerId = initialTemplate?.worker_id ?? workers.first?.id
        weekday = initialTemplate?.weekday ?? 1

        let start = parseTime(initialTemplate?.check_in_time)
        startHour = start.hour
        startMinute = start.minute

        let end = parseTime(initialTemplate?.check_out_time)
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
                weekday: weekday,
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("근무 일자")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                        Text(dayTitle)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                    }
                    .appCard()

                    timeInputSection

                    if let error {
                        Text(error)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appWarning)
                    }

                    Button(action: save) {
                        Text(initialEntry == nil ? "근무 추가" : "근무 저장")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(workers.isEmpty)
                    .opacity(workers.isEmpty ? 0.5 : 1.0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(initialEntry == nil ? "근무 추가" : "근무 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
            .task {
                applyInitialValue()
            }
        }
    }

    private var dayTitle: String {
        let comps = calendar.dateComponents([.year, .month, .day], from: selectedDate)
        return "\(comps.year ?? 0)년 \(comps.month ?? 0)월 \(comps.day ?? 0)일"
    }

    private var timeInputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("시간")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.appTextPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text("근무자")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)

                if workers.isEmpty {
                    Text("등록된 알바가 없어요. 먼저 알바관리에서 알바를 등록해주세요.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                } else {
                    Picker("근무자", selection: Binding(
                        get: { workerId ?? workers.first?.id },
                        set: { workerId = $0 }
                    )) {
                        ForEach(workers) { worker in
                            Text(worker.name).tag(Optional(worker.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("출근 시간 (필수)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    timeField(hour: $startHour, minute: $startMinute)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("퇴근 시간 (선택)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    timeField(hour: $endHour, minute: $endMinute)
                }
            }

            Text("퇴근 시간은 비워둘 수 있어요.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.appTextSecondary)
        }
        .appCard()
    }

    private func timeField(hour: Binding<String>, minute: Binding<String>) -> some View {
        HStack(spacing: 8) {
            TextField("시", text: hour)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .foregroundColor(.appTextPrimary)
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
            TextField("분", text: minute)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
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
