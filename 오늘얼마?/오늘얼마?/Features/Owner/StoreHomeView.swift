import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct StoreHomeView: View {
    let onNavigateToApproval: () -> Void

    @State private var stores: [Store] = []
    @State private var selectedStoreId: UUID?
    @State private var isPresentingCreateStore = false
    @State private var isPresentingCreateWorker = false
    @State private var isPresentingInviteSheet = false
    @State private var isStoreDropdownExpanded = false
    @State private var isLoadingStores = false
    @State private var isLoadingSummary = false
    @State private var isUserRefreshing = false
    @State private var didLoadSummary = false
    @State private var storeError: String?
    @State private var pendingDeleteStore: Store?
    @State private var isShowingDeleteConfirm = false
    @State private var isShowingDeleteAccountConfirm = false
    @State private var isShowingDeleteAccountError = false
    @State private var deleteAccountErrorMessage: String?

    @State private var workingNow: [String] = []
    @State private var todayMinutes: Int = 0
    @State private var todayPay: Double = 0

    @State private var lastStoresLoadedAt: Date?
    @State private var lastSummaryLoadedAt: Date?
    @State private var lastSummaryStoreId: UUID?
    @State private var latestStoresRequestID: UUID?
    @State private var latestSummaryRequestID: UUID?
    private let cacheTTLSeconds: TimeInterval = 120
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Top Custom Navigation Bar
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedStoreName)
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                    }
                    Spacer()
                    Menu {
                        Button("로그아웃", role: .destructive) {
                            Task {
                                await SupabaseManager.shared.signOut()
                                NotificationCenter.default.post(name: .didLogout, object: nil)
                            }
                        }
                        Button("계정 삭제", role: .destructive) {
                            isShowingDeleteAccountConfirm = true
                        }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                            .foregroundColor(.appTextSecondary)
                            .padding(10)
                            .background(Color.appSurface)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // Main Dashboard Content
                VStack(spacing: 20) {

                    // Store Section
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "내 매장")
                            .padding(.horizontal, 20)

                        if isLoadingStores && stores.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .appCard()
                                .padding(.horizontal, 20)
                        } else if stores.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("아직 등록된 매장이 없어요.")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                Button(action: { isPresentingCreateStore = true }) {
                                    Text("내 매장 등록하기")
                                }
                                .buttonStyle(PrimaryButtonStyle())
                            }
                            .appCard()
                            .padding(.horizontal, 20)
                        } else {
                            storeDropdown
                        }

                        if let storeError {
                            Text(storeError)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appWarning)
                                .padding(.horizontal, 20)
                        }
                    }
                    
                    // 1. Estimated Pay Card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("이번 달 예상 급여")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                            Spacer()
                        }
                        
                        if isLoadingSummary && !didLoadSummary {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            HStack(alignment: .bottom) {
                                Text(formatWon(todayPay))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                                Spacer()
                                Text("총 \(formatHours(todayMinutes))")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                    .padding(.bottom, 6)
                            }
                        }
                        
                        Divider()
                            .background(Color.appLine)
                        
                        NavigationLink {
                            if let storeId = selectedStoreId {
                                OwnerMonthlyDetailView(storeId: storeId)
                            } else {
                                Text("매장을 선택해주세요.")
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color.appBackground.ignoresSafeArea())
                            }
                        } label: {
                            HStack {
                                Text("자세히 보기")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 10, height: 10)
                            }
                            .foregroundColor(.appTextSecondary)
                        }
                    }
                    .appCard()
                    .padding(.horizontal, 20)

                    // 2. Working Now Section
                    VStack(spacing: 12) {
                        SectionHeader(title: "현재 근무 중", trailing: "\(workingNow.count)명")
                            .padding(.horizontal, 20)
                        
                        if workingNow.isEmpty {
                            Text("현재 근무 중인 알바가 없어요.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                                .padding(.horizontal, 20)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(workingNow, id: \.self) { name in
                                        VStack(spacing: 12) {
                                            Circle()
                                                .fill(Color.appAccent.opacity(0.1))
                                                .frame(width: 50, height: 50)
                                                .overlay(
                                                    Text(String(name.prefix(1)))
                                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                                        .foregroundColor(.appAccent)
                                                )
                                            Text(name)
                                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                                .foregroundColor(.appTextPrimary)
                                        }
                                        .padding(16)
                                        .frame(width: 100)
                                        .background(Color.appSurface)
                                        .cornerRadius(20)
                                        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 10)
                            }
                        }
                    }

                    // 3. Quick Actions Grid
                    VStack(spacing: 12) {
                        SectionHeader(title: "빠른 메뉴")
                            .padding(.horizontal, 20)
                        
                        HStack(spacing: 12) {
                            Button(action: { isPresentingInviteSheet = true }) {
                                Label("초대하기", systemImage: "number")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            
                            Button(action: {
                                onNavigateToApproval()
                            }) {
                                Label("근무 승인", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                        .padding(.horizontal, 20)
                        
                        // Additional List Actions
                        VStack(spacing: 0) {
                            quickMenuRow(icon: "person.crop.circle.badge.plus", title: "알바생 등록하기")
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard selectedStoreId != nil else { return }
                                    isPresentingCreateWorker = true
                                }

                            Divider()
                                .padding(.leading, 56)

                            if let selectedStore {
                                NavigationLink {
                                    StoreKnowledgeManagementView(
                                        storeId: selectedStore.id,
                                        storeName: selectedStore.name
                                    )
                                } label: {
                                    quickMenuRow(icon: "book.closed.fill", title: "가게 관리")
                                }
                                .buttonStyle(.plain)
                            } else {
                                quickMenuRow(icon: "book.closed.fill", title: "가게 관리")
                                    .opacity(0.45)
                            }
                        }
                        .background(Color.appSurface)
                        .cornerRadius(20)
                        .padding(.horizontal, 20)
                        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .refreshable {
            await refreshFromUser()
        }
        .refreshStatusOverlay(isVisible: isUserRefreshing)
        .background(Color.appBackground.ignoresSafeArea())
        .sheet(isPresented: $isPresentingCreateStore) {
            CreateStoreView { name, address in
                Task {
                    await createStore(name: name, address: address)
                }
            }
        }
        .sheet(isPresented: $isPresentingCreateWorker) {
            if let storeId = selectedStoreId {
                CreateWorkerView(storeId: storeId) { name, phone, wage in
                    Task {
                        await createWorker(storeId: storeId, name: name, phone: phone, hourlyWage: wage)
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingInviteSheet) {
            WorkerManagementView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("매장을 삭제하시겠습니까?", isPresented: $isShowingDeleteConfirm) {
            Button("삭제", role: .destructive) {
                guard let store = pendingDeleteStore else { return }
                Task { await deleteStore(store) }
            }
            Button("취소", role: .cancel) {
                pendingDeleteStore = nil
            }
        }
        .alert("계정을 삭제하시겠습니까?", isPresented: $isShowingDeleteAccountConfirm) {
            Button("삭제", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("모든 데이터가 삭제되며 복구할 수 없습니다.")
        }
        .alert("계정 삭제 실패", isPresented: $isShowingDeleteAccountError) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(deleteAccountErrorMessage ?? "잠시 후 다시 시도해주세요.")
        }
        .task {
            await refresh(force: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await refresh(force: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .payrollSettingsDidChange)) { _ in
            Task { await refresh(force: true) }
        }
    }

    private var selectedStoreName: String {
        stores.first(where: { $0.id == selectedStoreId })?.name ?? "내 매장"
    }

    private var selectedStore: Store? {
        stores.first(where: { $0.id == selectedStoreId }) ?? stores.first
    }

    private var selectableStores: [Store] {
        guard let selectedStore else { return stores }
        return stores.filter { $0.id != selectedStore.id }
    }

    private var storeDropdown: some View {
        VStack(spacing: 10) {
            if let selectedStore {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isStoreDropdownExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            storeInfo(selectedStore)
                            Spacer()
                            Image(systemName: isStoreDropdownExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.appTextSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    storeDeleteMenu(selectedStore)
                }
                .padding(14)
                .background(Color.appSurface)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.appAccent.opacity(0.35), lineWidth: 1)
                )
            }

            if isStoreDropdownExpanded {
                VStack(spacing: 8) {
                    ForEach(selectableStores) { store in
                        storeDropdownRow(store)
                    }

                    Button(action: { isPresentingCreateStore = true }) {
                        Label("매장 추가하기", systemImage: "plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 20)
    }

    private func storeDropdownRow(_ store: Store) -> some View {
        HStack(spacing: 10) {
            Button {
                selectStore(store)
                withAnimation(.easeInOut(duration: 0.18)) {
                    isStoreDropdownExpanded = false
                }
            } label: {
                HStack(spacing: 10) {
                    storeInfo(store)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            storeDeleteMenu(store)
        }
        .padding(12)
        .background(Color.appSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.appLine, lineWidth: 1)
        )
    }

    private func storeDeleteMenu(_ store: Store) -> some View {
        Menu {
            Button(role: .destructive) {
                pendingDeleteStore = store
                isShowingDeleteConfirm = true
            } label: {
                Label("삭제", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.appTextSecondary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
    }

    private func storeInfo(_ store: Store) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.name)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.appTextPrimary)
                .lineLimit(1)

            if let address = store.address, !address.isEmpty {
                Text(address)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(1)
            }
        }
    }

    private func quickMenuRow(icon: String, title: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.appTextSecondary)
                .frame(width: 24)
            Text(title)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(.appTextPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 12, height: 12)
                .foregroundColor(.appLine)
        }
        .padding(16)
    }

    private func selectStore(_ store: Store) {
        if selectedStoreId != store.id {
            todayMinutes = 0
            todayPay = 0
            workingNow = []
            didLoadSummary = false
        }
        selectedStoreId = store.id
        Task { await loadSummary(force: true) }
    }

    @MainActor
    private func deleteAccount() async {
        do {
            try await SupabaseManager.shared.deleteAccount()
            await SupabaseManager.shared.signOut()
            NotificationCenter.default.post(name: .didLogout, object: nil)
        } catch {
            deleteAccountErrorMessage = AppErrorMessage.userMessage(error)
            isShowingDeleteAccountError = true
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
        let requestID = UUID()
        latestStoresRequestID = requestID
        isLoadingStores = true
        defer {
            if latestStoresRequestID == requestID {
                isLoadingStores = false
            }
        }
        do {
            let ownerId = try await SupabaseManager.shared.currentUserId()
            let result: [Store] = try await SupabaseManager.shared
                .client
                .from("stores")
                .select()
                .eq("owner_id", value: ownerId.uuidString)
                .execute()
                .value
            guard latestStoresRequestID == requestID else { return }
            stores = result
            if selectedStoreId == nil || !stores.contains(where: { $0.id == selectedStoreId }) {
                selectedStoreId = stores.first?.id
            }
            self.lastStoresLoadedAt = now
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard latestStoresRequestID == requestID else { return }
            storeError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    struct LogRow: Decodable {
        let worker_id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
        let workers: WorkerInfo?
        let applied_hourly_wage: Double?
        let applied_night_allowance: Bool?
    }

    struct WorkerInfo: Decodable {
        let name: String
        let hourly_wage: Double?
        let apply_night_allowance: Bool?
    }

    @MainActor
    private func loadSummary(force: Bool) async {
        guard let storeId = selectedStoreId else { return }
        #if canImport(Supabase)
        let now = Date()
        if !force,
           let lastSummaryLoadedAt,
           let lastSummaryStoreId,
           lastSummaryStoreId == storeId,
           now.timeIntervalSince(lastSummaryLoadedAt) < cacheTTLSeconds {
            return
        }
        let requestID = UUID()
        latestSummaryRequestID = requestID
        isLoadingSummary = true
        defer {
            if latestSummaryRequestID == requestID {
                isLoadingSummary = false
            }
        }
        do {
            let calendar = AppTime.calendar
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? Date()
            let iso = AppTime.iso
            let rows: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("worker_id,check_in_at,check_out_at,status,applied_hourly_wage,applied_night_allowance,workers(name,hourly_wage,apply_night_allowance)")
                .eq("store_id", value: storeId.uuidString)
                .gte("check_in_at", value: iso.string(from: start))
                .lt("check_in_at", value: iso.string(from: end))
                .execute()
                .value
            guard latestSummaryRequestID == requestID, selectedStoreId == storeId else { return }

            var minutes = 0
            var pay: Double = 0
            var latestRowByWorker: [UUID: (checkIn: Date, isOpen: Bool, name: String)] = [:]
            let dateParser = AppTime.isoWithFractionalSeconds

            for row in rows {
                let status = row.status ?? "pending"
                if status == "rejected" { continue }

                let checkIn = dateParser.date(from: row.check_in_at) ?? iso.date(from: row.check_in_at) ?? Date()
                let hasCheckoutValue = !(row.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                let parsedCheckout = row.check_out_at.flatMap { dateParser.date(from: $0) ?? iso.date(from: $0) }

                if let name = row.workers?.name {
                    if let prev = latestRowByWorker[row.worker_id] {
                        if checkIn > prev.checkIn {
                            latestRowByWorker[row.worker_id] = (checkIn: checkIn, isOpen: !hasCheckoutValue, name: name)
                        }
                    } else {
                        latestRowByWorker[row.worker_id] = (checkIn: checkIn, isOpen: !hasCheckoutValue, name: name)
                    }
                }

                guard status == "approved", hasCheckoutValue else { continue }
                // If checkout exists but parser fails, keep totals stable with zero-length fallback.
                let effectiveCheckOut: Date? = parsedCheckout ?? checkIn
                let durationMinutes = calcMinutes(checkIn: checkIn, checkOut: effectiveCheckOut)
                minutes += durationMinutes
                let wage = row.workers?.hourly_wage ?? 0
                pay += PayrollCalculator.grossPay(
                    checkIn: checkIn,
                    checkOut: effectiveCheckOut,
                    appliedHourlyWage: row.applied_hourly_wage,
                    appliedNightAllowance: row.applied_night_allowance,
                    fallbackHourlyWage: wage,
                    fallbackNightAllowance: row.workers?.apply_night_allowance ?? false
                )
            }
            let workingNames = latestRowByWorker.values
                .filter { $0.isOpen }
                .map { $0.name }
                .sorted()

            todayMinutes = minutes
            todayPay = pay
            workingNow = workingNames
            didLoadSummary = true
            self.lastSummaryLoadedAt = now
            self.lastSummaryStoreId = storeId
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard latestSummaryRequestID == requestID, selectedStoreId == storeId else { return }
            storeError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private func calcMinutes(checkIn: Date, checkOut: Date?) -> Int {
        guard let end = checkOut else { return 0 }
        let minutes = floor(end.timeIntervalSince(checkIn) / 60.0)
        return max(0, Int(minutes))
    }



    @MainActor
    private func refresh(force: Bool) async {
        await loadStores(force: force)
        await loadSummary(force: force)
    }

    @MainActor
    private func createStore(name: String, address: String) async {
        #if canImport(Supabase)
        do {
            let ownerId = try await SupabaseManager.shared.currentUserId()
            struct StoreInsert: Encodable {
                let name: String
                let address: String?
                let owner_id: UUID
                let is_personal: Bool
            }
            let payload = StoreInsert(
                name: name,
                address: address.isEmpty ? nil : address,
                owner_id: ownerId,
                is_personal: false
            )
            let created: Store = try await SupabaseManager.shared
                .client
                .from("stores")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            stores.insert(created, at: 0)
            selectedStoreId = created.id
            lastStoresLoadedAt = Date()
            await loadSummary(force: true)
        } catch {
            storeError = AppErrorMessage.userMessage(error)
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
            storeError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func deleteStore(_ store: Store) async {
        #if canImport(Supabase)
        do {
            _ = try await SupabaseManager.shared
                .client
                .from("stores")
                .delete()
                .eq("id", value: store.id.uuidString)
                .execute()
            stores.removeAll { $0.id == store.id }
            if selectedStoreId == store.id {
                selectedStoreId = stores.first?.id
            }
            lastStoresLoadedAt = Date()
            await loadSummary(force: true)
        } catch {
            storeError = AppErrorMessage.userMessage(error)
        }
        #endif
        pendingDeleteStore = nil
    }
}

struct CreateStoreView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var address: String = ""
    @State private var searchResults: [KakaoPlace] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var isSearchExpanded = true

    let onSubmit: (String, String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isSearching {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .appCard()
                    } else if !searchResults.isEmpty {
                        if isSearchExpanded {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(searchResults) { place in
                                Button(action: {
                                    hideKeyboard()
                                    applyPlace(place)
                                    isSearchExpanded = false
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(place.placeName)
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundColor(.appTextPrimary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(place.displayAddress)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(.appTextSecondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        }
                    }

                    if let searchError {
                        Text(searchError)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appWarning)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("매장 이름")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        HStack(spacing: 8) {
                            TextField("강남 1호점", text: $name)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit { Task { await searchPlaces() } }
                                .foregroundColor(.appTextPrimary)
                                .padding(12)
                                .background(Color.appSurface)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.appLine, lineWidth: 1)
                                )
                            Button("검색") {
                                Task { await searchPlaces() }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .frame(width: 80)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("주소 (선택)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        TextField("서울 강남구 ...", text: $address)
                            .foregroundColor(.appTextPrimary)
                            .padding(12)
                            .background(Color.appSurface)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                    }

                    Button(action: {
                        onSubmit(name, address)
                        dismiss()
                    }) {
                        Text("등록하기")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
                }
                .padding(20)
            }
            .navigationTitle("매장 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var kakaoRestApiKey: String? {
        return AppConfig.kakaoRestApiKey
    }

    @MainActor
    private func searchPlaces() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchError = "검색어를 입력해주세요."
            return
        }
        guard let apiKey = kakaoRestApiKey else {
            searchError = "KAKAO_REST_API_KEY가 설정되어 있지 않습니다."
            return
        }

        isSearching = true
        searchError = nil
        defer { isSearching = false }

        do {
            let results = try await KakaoLocalSearch.search(query: trimmed, apiKey: apiKey)
            searchResults = results
            isSearchExpanded = true
        } catch {
            searchError = AppErrorMessage.userMessage(error)
        }
    }

    private func applyPlace(_ place: KakaoPlace) {
        name = place.placeName
        address = place.displayAddress
    }

    private struct KakaoSearchResponse: Decodable {
        let documents: [KakaoPlace]
    }

    private struct KakaoPlace: Decodable, Identifiable {
        let id: String
        let placeName: String
        let addressName: String?
        let roadAddressName: String?
        let phone: String
        let categoryName: String
        let x: String
        let y: String

        enum CodingKeys: String, CodingKey {
            case id
            case placeName = "place_name"
            case addressName = "address_name"
            case roadAddressName = "road_address_name"
            case phone
            case categoryName = "category_name"
            case x
            case y
        }

        var displayAddress: String {
            if let roadAddressName, !roadAddressName.isEmpty {
                return roadAddressName
            }
            return addressName ?? "-"
        }
    }

    private enum KakaoLocalSearch {
        static func search(query: String, apiKey: String) async throws -> [KakaoPlace] {
            var components = URLComponents(string: "https://dapi.kakao.com/v2/local/search/keyword.json")
            components?.queryItems = [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "size", value: "10")
            ]
            guard let url = components?.url else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(domain: "KakaoSearch", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "검색 요청에 실패했습니다. (HTTP \(http.statusCode))"
                ])
            }

            let decoded = try JSONDecoder().decode(KakaoSearchResponse.self, from: data)
            return decoded.documents
        }
    }
}

struct CreateWorkerView: View {
    @Environment(\.dismiss) private var dismiss
    let storeId: UUID
    let onSubmit: (String, String, Double) -> Void

    @State private var name: String = ""
    @State private var phone: String = ""
    @State private var wage: String = String(Int(AppConfig.defaultHourlyWage))

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("이름")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    TextField("홍길동", text: $name)
                        .padding(12)
                        .background(Color.appSurface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appLine, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("전화번호 (선택)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    TextField("010-1234-5678", text: $phone)
                        .keyboardType(.phonePad)
                        .padding(12)
                        .background(Color.appSurface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appLine, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("시급 (원)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    TextField("예: 10320", text: $wage)
                        .keyboardType(.numberPad)
                        .padding(12)
                        .background(Color.appSurface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appLine, lineWidth: 1)
                        )
                }

                Button(action: {
                    let digits = wage.filter { $0.isNumber }
                    let amount = Double(digits) ?? AppConfig.defaultHourlyWage
                    onSubmit(name, phone, amount)
                    dismiss()
                }) {
                    Text("등록하기")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)

                Spacer()
            }
            .padding(20)
            .navigationTitle("알바생 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
    }
}

private func hideKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #endif
}
