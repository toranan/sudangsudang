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
        let store_id: UUID
        let name: String
        let phone: String?
        let hourly_wage: Double?
        let is_active: Bool?
        let apply_weekly_allowance: Bool?
        let deduction_type: String?
    }

    struct WorkLogRow: Decodable, Identifiable {
        let id: UUID
        let worker_id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String
    }

    enum DetailTab: String, CaseIterable, Identifiable {
        case logs = "내역"
        case net = "세후금액"
        case wage = "시급"

        var id: String { rawValue }
    }

    @State private var stores: [StoreOption] = []
    @State private var selectedStoreId: UUID?
    @State private var workers: [WorkerRow] = []
    @State private var monthLogsByWorker: [UUID: [WorkLogRow]] = [:]
    @State private var monthPayByWorker: [UUID: Double] = [:]
    @State private var monthMinutesByWorker: [UUID: Int] = [:]
    @State private var isLoadingWorkers = false
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
    @State private var selectedMonth: Date = Date()
    @State private var lastStoresLoadedAt: Date?
    @State private var lastWorkersLoadedAt: Date?
    @State private var lastWorkersKey: String?
    private let cacheTTLSeconds: TimeInterval = 45

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
                    if isLoadingWorkers {
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
            await refresh(force: true)
        }

        .background(Color.appBackground.ignoresSafeArea())
        .sheet(item: $selectedWorker) { worker in
            WorkerDetailSheet(
                worker: worker,
                monthLogs: monthLogsByWorker[worker.id] ?? [],
                monthPay: monthPayByWorker[worker.id] ?? 0,
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
            Task { await loadWorkers(force: false) }
        }
    }

    private var monthSelector: some View {
        HStack(spacing: 12) {
            Button(action: {
                selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
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
                selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
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
    private func loadStores(force: Bool) async {
        #if canImport(Supabase)
        let now = Date()
        if !force,
           let lastStoresLoadedAt,
           now.timeIntervalSince(lastStoresLoadedAt) < cacheTTLSeconds {
            return
        }
        do {
            let result: [Store] = try await SupabaseManager.shared
                .client
                .from("stores")
                .select()
                .execute()
                .value
            stores = result.map { StoreOption(id: $0.id, name: $0.name) }
            if selectedStoreId == nil {
                selectedStoreId = stores.first?.id
            }
            self.lastStoresLoadedAt = now
        } catch {
            inviteError = error.localizedDescription
        }
        #endif
    }

    @MainActor
    private func loadWorkers(force: Bool) async {
        guard let storeId = selectedStoreId else {
            workers = []
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
        isLoadingWorkers = true
        workersError = nil
        defer { isLoadingWorkers = false }
        do {
            do {
                // Newer schema: includes payroll settings columns.
                let rows: [WorkerRow] = try await SupabaseManager.shared
                    .client
                    .from("workers")
                    .select("id,store_id,name,phone,hourly_wage,is_active,apply_weekly_allowance,deduction_type")
                    .eq("store_id", value: storeId.uuidString)
                    .order("joined_at", ascending: false)
                    .execute()
                    .value
                workers = rows
                await loadMonthlyLogs(storeId: storeId, workers: rows)
            } catch {
                // Safety net: if DB migration is not applied yet, re-fetch without the new columns.
                let message = error.localizedDescription.lowercased()
                if message.contains("apply_weekly_allowance") || message.contains("deduction_type") {
                    let rows: [WorkerRow] = try await SupabaseManager.shared
                        .client
                        .from("workers")
                        .select("id,store_id,name,phone,hourly_wage,is_active")
                        .eq("store_id", value: storeId.uuidString)
                        .order("joined_at", ascending: false)
                        .execute()
                        .value
                    workers = rows
                    await loadMonthlyLogs(storeId: storeId, workers: rows)
                } else {
                    throw error
                }
            }
            self.lastWorkersLoadedAt = now
            self.lastWorkersKey = key
        } catch {
            workersError = error.localizedDescription
        }
        #endif
    }

    private func monthKey(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(comps.year ?? 0)-\(comps.month ?? 0)"
    }

    @MainActor
    private func refresh(force: Bool) async {
        await loadStores(force: force)
        await loadWorkers(force: force)
    }
    
    // Formatting helpers utilized by parent view
    private func formatWon(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: Int(value))) ?? "0"
        return "\(number)원"
    }
    
    private func formatWonRaw(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        return formatter.string(from: NSNumber(value: Int(value))) ?? ""
    }

    private func formatHours(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)시간 \(m)분"
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: date)
    }

    @MainActor
    private func loadMonthlyLogs(storeId: UUID, workers: [WorkerRow]) async {
        #if canImport(Supabase)
        do {
            let calendar = Calendar.current
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? Date()
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? Date()
            let iso = ISO8601DateFormatter()

            let rows: [WorkLogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,worker_id,check_in_at,check_out_at,status")
                .eq("store_id", value: storeId.uuidString)
                .gte("check_in_at", value: iso.string(from: monthStart))
                .lt("check_in_at", value: iso.string(from: monthEnd))
                .execute()
                .value

            var byWorker: [UUID: [WorkLogRow]] = [:]
            for row in rows where row.status == "approved" {
                byWorker[row.worker_id, default: []].append(row)
            }

            var payByWorker: [UUID: Double] = [:]
            var minutesByWorker: [UUID: Int] = [:]
            for worker in workers {
                let wage = worker.hourly_wage ?? 0
                let logs = byWorker[worker.id] ?? []
                let minutes = logs.reduce(0) { partial, log in
                    partial + calcMinutes(checkIn: log.check_in_at, checkOut: log.check_out_at)
                }
                payByWorker[worker.id] = calcPay(minutes: minutes, wage: wage)
                minutesByWorker[worker.id] = minutes
            }

            monthLogsByWorker = byWorker
            monthPayByWorker = payByWorker
            monthMinutesByWorker = minutesByWorker
        } catch {
            workersError = error.localizedDescription
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
            workersError = error.localizedDescription
        }
        #endif
    }

    // Helper calculation functions need to be available for parent logic too
    private func calcMinutes(checkIn: String, checkOut: String?) -> Int {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let start = parser.date(from: checkIn) ?? iso.date(from: checkIn) ?? Date()
        let end = checkOut.flatMap { parser.date(from: $0) ?? iso.date(from: $0) } ?? Date()
        let minutes = floor(end.timeIntervalSince(start) / 60.0)
        return max(0, Int(minutes))
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
            let expiresAt = Calendar.current.date(byAdding: .hour, value: 48, to: Date()) ?? Date()
            let invite = try await SupabaseManager.shared.createInvite(storeId: storeId, expiresAt: expiresAt)
            inviteCode = invite.token
            inviteLink = URL(string: "howmuch://invite?token=\(invite.token)")
        } catch {
            inviteError = error.localizedDescription
        }
        #endif
    }
}

// Separate Struct for Sheet to fix state persistence issues
struct WorkerDetailSheet: View {
    let worker: WorkerManagementView.WorkerRow
    let monthLogs: [WorkerManagementView.WorkLogRow]
    let monthPay: Double
    let onUpdate: () async -> Void

    @State private var detailTab: WorkerManagementView.DetailTab = .logs
    @State private var wageInput: String = ""
    @State private var isSavingWage = false
    @State private var wageError: String?
    @State private var applyWeeklyAllowance: Bool = false
    @State private var deductionType: PayrollDeductionType = .withholding
    @State private var isSavingPayroll = false
    @State private var payrollError: String?
    @State private var manualHours: String = ""
    @State private var manualMinutes: String = ""
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

            if detailTab == .wage {
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
            if let wage = worker.hourly_wage {
                let formatter = NumberFormatter()
                formatter.numberStyle = .none
                wageInput = formatter.string(from: NSNumber(value: Int(wage))) ?? ""
            }
            if !didLoadPayrollState {
                applyWeeklyAllowance = worker.apply_weekly_allowance ?? false
                if let raw = worker.deduction_type,
                   let parsed = PayrollDeductionType(rawValue: raw) {
                    deductionType = parsed
                } else {
                    deductionType = .withholding
                }
                didLoadPayrollState = true
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
    }

    private var wageView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("시급 (원)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                TextField("예: 10000", text: $wageInput)
                    .keyboardType(.numberPad)
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("공제 방식 (택 1)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    Picker("", selection: $deductionType) {
                        ForEach(PayrollDeductionType.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: deductionType) { _ in
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
        let gross = monthPay
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
                    Text(formatWon(monthPay))
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
                                Text(formatWon(calcPay(minutes: calcMinutes(checkIn: log.check_in_at, checkOut: log.check_out_at), wage: worker.hourly_wage ?? 0)))
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
                    Text("시간")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    TextField("예: 3", text: $manualHours)
                        .keyboardType(.numberPad)
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
                    TextField("예: 30", text: $manualMinutes)
                        .keyboardType(.numberPad)
                        .padding(10)
                        .background(Color.appSurface)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.appLine, lineWidth: 1)
                        )
                }
            }

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
            wageError = error.localizedDescription
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
            }
            let payload = UpdatePayload(
                apply_weekly_allowance: applyWeeklyAllowance,
                deduction_type: deductionType.rawValue
            )
            _ = try await SupabaseManager.shared
                .client
                .from("workers")
                .update(payload)
                .eq("id", value: worker.id.uuidString)
                .execute()
            await onUpdate()
        } catch {
            payrollError = error.localizedDescription
        }
        #endif
    }

    @MainActor
    private func addManualWork() async {
        #if canImport(Supabase)
        isSavingManual = true
        manualError = nil
        defer { isSavingManual = false }

        let h = Int(manualHours.filter { $0.isNumber }) ?? 0
        let m = Int(manualMinutes.filter { $0.isNumber }) ?? 0
        let totalMinutes = h * 60 + m
        guard totalMinutes > 0 else {
            manualError = "근무 시간을 입력해주세요."
            return
        }

        let calendar = Calendar.current
        let today = Date()
        let dayStart = calendar.startOfDay(for: today)
        let endDate = Date()
        var checkIn = endDate.addingTimeInterval(TimeInterval(-totalMinutes * 60))
        if checkIn < dayStart {
            checkIn = dayStart
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
            let iso = ISO8601DateFormatter()
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
            manualHours = ""
            manualMinutes = ""
            await onUpdate()
        } catch {
            manualError = error.localizedDescription
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

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let end = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) } ?? Date()
        var checkIn = end.addingTimeInterval(TimeInterval(-totalMinutes * 60))

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
            editError = error.localizedDescription
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
            editError = error.localizedDescription
        }
        #endif
    }

    // Duplicate helpers for self-contained View
    private func formatWon(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: Int(value))) ?? "0"
        return "\(number)원"
    }

    private func formatDate(_ isoString: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let date = parser.date(from: isoString) ?? iso.date(from: isoString) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: date)
    }

    private func formatTimeRange(_ log: WorkerManagementView.WorkLogRow) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let start = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
        let end = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let startText = formatter.string(from: start)
        let endText = end.map { formatter.string(from: $0) } ?? "--:--"
        return "\(startText) - \(endText)"
    }

    private func formatHours(_ val: Int) -> String {
        let h = val / 60
        let m = val % 60
        return "\(h)시간 \(m)분"
    }

    private func totalMinutes() -> Int {
        monthLogs.reduce(0) { partial, log in
            partial + calcMinutes(checkIn: log.check_in_at, checkOut: log.check_out_at)
        }
    }
    
    private func calcMinutes(checkIn: String, checkOut: String?) -> Int {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let start = parser.date(from: checkIn) ?? iso.date(from: checkIn) ?? Date()
        let end = checkOut.flatMap { parser.date(from: $0) ?? iso.date(from: $0) } ?? Date()
        // Floor to minute to avoid inflating time (e.g., 30 seconds shouldn't become +1 minute).
        let minutes = floor(end.timeIntervalSince(start) / 60.0)
        return max(0, Int(minutes))
    }

    private func calcPay(minutes: Int, wage: Double) -> Double {
        Double(minutes) / 60.0 * wage
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
    
    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}
