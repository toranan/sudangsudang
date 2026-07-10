import SwiftUI
import Combine
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(Supabase)
import Supabase
#endif

struct WorkerHomeView: View {
    struct StorePay: Identifiable, Hashable {
        let id: UUID
        let workerId: UUID
        let name: String
        let isPersonal: Bool
        let hourlyWage: Double
        let applyWeeklyAllowance: Bool
        let applyNightAllowance: Bool
        let deductionType: PayrollDeductionType
        let payday: Int
        let todayMinutes: Int
        let todayPay: Double
        let monthMinutes: Int
        let monthPay: Double
        let monthNetPay: Double

        var todayWorkedText: String { formatHours(todayMinutes) }
        var monthWorkedText: String { formatHours(monthMinutes) }
        var todayPayText: String { formatWon(todayPay) }
        var monthPayText: String { formatWon(monthPay) }
        var monthNetPayText: String { formatWon(monthNetPay) }
        var paydayText: String { "\(payday)일" }
        var nextPaydayDateText: String {
            WorkerHomeView.formatDate(PayrollPayday.nextPaydayDate(payday: payday))
        }
    }

    struct WorkerRow: Decodable {
        let id: UUID
        let store_id: UUID
        let hourly_wage: Double?
        let apply_weekly_allowance: Bool?
        let deduction_type: String?
        let apply_night_allowance: Bool?
        let payday: Int?
        let is_active: Bool?
        let stores: StoreName?
    }

    struct StoreName: Decodable {
        let name: String
        let is_personal: Bool?
    }

    struct LogRow: Decodable {
        let store_id: UUID
        let worker_id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
    }

    @State private var storePays: [StorePay] = []
    @State private var selectedStoreId: UUID?
    @State private var isStoreDropdownExpanded = false
    @State private var isLoading = false
    @State private var isUserRefreshing = false
    @State private var loadError: String?
    @State private var lastLoadedAt: Date?
    @State private var lastLoadedMonthKey: String?
    @State private var didBackfillPersonalLinks = false
    @State private var selectedMonth: Date = AppTime.calendar.date(from: AppTime.calendar.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var isPresentingJoinStore = false
    @State private var isPresentingPersonalStore = false
    @State private var isPresentingJoinProfileGate = false
    @State private var joinProfileGateName: String = ""
    @State private var joinProfileGatePhone: String = ""
    @State private var pendingJoinToken: String?
    @State private var profileGateSaveCompleted = false
    @State private var pendingDeleteStore: StorePay?
    @State private var isShowingDeleteConfirm = false
    @State private var deleteError: String?
    @State private var isShowingDeleteAccountConfirm = false
    @State private var isShowingDeleteAccountError = false
    @State private var deleteAccountErrorMessage: String?
    @State private var deepLinkTargetStore: StorePay?
    @State private var pendingDeepLinkStoreId: UUID?

    var body: some View {
        presentedHomeContent
    }

    private var presentedHomeContent: some View {
        baseHomeContent
            .alert("퇴사처리하시겠습니까?", isPresented: $isShowingDeleteConfirm) {
                Button("퇴사하기", role: .destructive) {
                    guard let store = pendingDeleteStore else { return }
                    Task { await processRetirement(store) }
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
            .sheet(isPresented: $isPresentingJoinStore) {
                JoinStoreView { token in
                    Task {
                        await beginJoinStoreFlow(token: token)
                    }
                }
            }
            .sheet(isPresented: $isPresentingPersonalStore) {
                CreatePersonalStoreView { name, address in
                    Task {
                        await createPersonalStore(name: name, address: address)
                    }
                }
            }
            .sheet(isPresented: $isPresentingJoinProfileGate, onDismiss: {
                guard profileGateSaveCompleted, let token = pendingJoinToken else { return }
                profileGateSaveCompleted = false
                let savedName = joinProfileGateName
                let savedPhone = joinProfileGatePhone
                Task {
                    #if DEBUG
                    print("DEBUG: profile gate dismissed. name=\(savedName) phone=\(savedPhone) token=\(token)")
                    #endif
                    // 1) 프로필 저장
                    #if canImport(Supabase)
                    do {
                        let userId = try await SupabaseManager.shared.currentUserId()
                        try await SupabaseManager.shared.patchProfile(
                            id: userId,
                            name: savedName.isEmpty ? nil : savedName,
                            phone: savedPhone.isEmpty ? nil : savedPhone
                        )
                        #if DEBUG
                        print("DEBUG: patchProfile succeeded")
                        #endif
                    } catch {
                        #if DEBUG
                        print("DEBUG: patchProfile failed: \(error.localizedDescription)")
                        #endif
                    }
                    #endif
                    // 2) 매장 추가
                    await joinStore(token: token)
                }
            }) {
                ProfileCompletionSheet(
                    context: .init(
                        title: "프로필을 설정할까요?",
                        message: "사장님과의 연동을 위해 이름 입력이 필요해요. 전화번호도 입력할 수 있어요.",
                        primaryActionTitle: "저장하고 추가",
                        showsSkip: false,
                        requiresName: true
                    ),
                    initialName: joinProfileGateName,
                    initialPhone: joinProfileGatePhone,
                    onSave: { name, phone in
                        // ⚠️ async 작업 금지 — 메모리 충돌 방지
                        // 값만 @State에 저장하고 onDismiss에서 처리
                        joinProfileGateName = name ?? ""
                        joinProfileGatePhone = phone ?? ""
                        profileGateSaveCompleted = true
                    },
                    onSkip: nil
                )
            }
    }

    private var baseHomeContent: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerStrip
                    storePaySection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .refreshable {
                await refreshFromUser()
            }
            .refreshStatusOverlay(isVisible: isUserRefreshing)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $deepLinkTargetStore) { store in
                WorkerCheckInView(store: store)
            }
        }
        .task {
            await loadData(force: false)
            await processPendingDeepLink()
        }
        .onChange(of: selectedMonth) { _ in
            Task { await loadData(force: true) }
        }
        .onChange(of: storePays) { _ in
            resolvePendingDeepLink()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didAcceptInvite)) { _ in
            Task { await loadData(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .payrollSettingsDidChange)) { _ in
            Task { await loadData(force: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .didOpenWorkerCheckIn)) { note in
            guard let storeId = note.object as? UUID else { return }
            Task { await openStoreFromDeepLink(storeId: storeId) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await loadData(force: false) }
        }
    }

    @ViewBuilder
    private var storePaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "내 매장")

            if isLoading && storePays.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .appCard()
            } else if storePays.isEmpty {
                Text("등록된 매장이 없어요.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                    .appCard()
                Button(action: { isPresentingJoinStore = true }) {
                    Text("초대코드 입력하기")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(action: { isPresentingPersonalStore = true }) {
                    Text("매장 추가하기")
                }
                .buttonStyle(SecondaryButtonStyle())
            } else {
                VStack(spacing: 14) {
                    workerStoreDropdown

                    if let selectedStorePay {
                        selectedStoreSummaryCard(selectedStorePay)
                        selectedStoreQuickMenu(selectedStorePay)
                    }
                }
            }

            if let loadError {
                Text(loadError)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appWarning)
            }
            if let deleteError {
                Text(deleteError)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appWarning)
            }
        }
    }

    private var selectedStorePay: StorePay? {
        storePays.first(where: { $0.id == selectedStoreId }) ?? storePays.first
    }

    private var selectableStorePays: [StorePay] {
        guard let selectedStorePay else { return storePays }
        return storePays.filter { $0.id != selectedStorePay.id }
    }

    @MainActor
    private func refreshFromUser() async {
        isUserRefreshing = true
        defer { isUserRefreshing = false }
        await loadData(force: true)
    }

    private var workerStoreDropdown: some View {
        VStack(spacing: 10) {
            if let selectedStorePay {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isStoreDropdownExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            workerStoreInfo(selectedStorePay)
                            Spacer()
                            Image(systemName: isStoreDropdownExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.appTextSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    workerStoreMenu(selectedStorePay)
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
                    ForEach(selectableStorePays) { store in
                        workerStoreDropdownRow(store)
                    }

                    Button(action: { isPresentingJoinStore = true }) {
                        Label("초대코드 입력하기", systemImage: "number")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button(action: { isPresentingPersonalStore = true }) {
                        Label("매장 추가하기", systemImage: "plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func workerStoreDropdownRow(_ store: StorePay) -> some View {
        HStack(spacing: 10) {
            Button {
                selectStore(store)
                withAnimation(.easeInOut(duration: 0.18)) {
                    isStoreDropdownExpanded = false
                }
            } label: {
                HStack(spacing: 10) {
                    workerStoreInfo(store)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            workerStoreMenu(store)
        }
        .padding(12)
        .background(Color.appSurface)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.appLine, lineWidth: 1)
        )
    }

    private func workerStoreInfo(_ store: StorePay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(store.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                    .lineLimit(1)

                if store.isPersonal {
                    Text("개인")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.appAccent.opacity(0.1))
                        .cornerRadius(7)
                }
            }

            Text("시급 \(formatWon(store.hourlyWage)) · 월급일 \(store.paydayText)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.appTextSecondary)
                .lineLimit(1)
        }
    }

    private func workerStoreMenu(_ store: StorePay) -> some View {
        Menu {
            Button(role: .destructive) {
                pendingDeleteStore = store
                isShowingDeleteConfirm = true
            } label: {
                Label(store.isPersonal ? "매장 삭제" : "퇴사하기", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.appTextSecondary)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
    }

    private func selectStore(_ store: StorePay) {
        selectedStoreId = store.id
    }

    private func selectedStoreSummaryCard(_ store: StorePay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(monthTitle(selectedMonth)) 예상 급여")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                Spacer()
                Text(store.monthWorkedText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
            }

            Text(store.monthPayText)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.appTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Divider()
                .background(Color.appLine)

            HStack {
                summaryPair(title: "오늘 급여", value: store.todayPayText)
                Spacer()
                summaryPair(title: "세후 예상", value: store.monthNetPayText, alignment: .trailing)
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.appLine, lineWidth: 1)
        )
    }

    private func summaryPair(title: String, value: String, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.appTextSecondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.appTextPrimary)
        }
    }

    private func selectedStoreQuickMenu(_ store: StorePay) -> some View {
        VStack(spacing: 0) {
            NavigationLink {
                WorkerCheckInView(store: store)
            } label: {
                workerQuickMenuRow(icon: "timer", title: "출근/퇴근하기")
            }
            .buttonStyle(.plain)

            Divider()
                .padding(.leading, 56)

            NavigationLink {
                WorkerStoreKnowledgeView(storeId: store.id, storeName: store.name)
            } label: {
                workerQuickMenuRow(icon: "megaphone.fill", title: "공지 · 매뉴얼 · 챗봇")
            }
            .buttonStyle(.plain)
        }
        .background(Color.appSurface)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.appLine, lineWidth: 1)
        )
    }

    private func workerQuickMenuRow(icon: String, title: String) -> some View {
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

    private func storePayCard(_ store: StorePay) -> some View {
        NavigationLink {
            WorkerCheckInView(store: store)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(store.name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Menu {
                        Button(role: .destructive) {
                            pendingDeleteStore = store
                            isShowingDeleteConfirm = true
                        } label: {
                            Text("퇴사하기")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.appTextSecondary)
                            .padding(.horizontal, 4)
                    }
                }
                HStack(alignment: .bottom) {
                    Text(store.monthPayText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    Text("\(monthTitle(selectedMonth)) \(store.monthWorkedText)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                }
                HStack {
                    Text("오늘 급여")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text(store.todayPayText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                }
                HStack {
                    Text("세후 예상")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text(store.monthNetPayText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                }
            }
            .padding(14)
            .background(Color.appSurface)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.appLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func processPendingDeepLink() async {
        guard let pendingStoreId = WorkerDeepLinkManager.shared.pendingStoreId() else { return }
        await openStoreFromDeepLink(storeId: pendingStoreId)
    }

    @MainActor
    private func openStoreFromDeepLink(storeId: UUID) async {
        if let store = storePays.first(where: { $0.id == storeId }) {
            deepLinkTargetStore = nil
            await Task.yield()
            deepLinkTargetStore = store
            WorkerDeepLinkManager.shared.clearPendingStoreId()
            pendingDeepLinkStoreId = nil
            return
        }

        pendingDeepLinkStoreId = storeId
        await loadData(force: true)
        resolvePendingDeepLink()
    }

    @MainActor
    private func resolvePendingDeepLink() {
        guard let storeId = pendingDeepLinkStoreId else { return }
        guard let store = storePays.first(where: { $0.id == storeId }) else { return }
        deepLinkTargetStore = nil
        Task { @MainActor in
            await Task.yield()
            deepLinkTargetStore = store
            WorkerDeepLinkManager.shared.clearPendingStoreId()
            pendingDeepLinkStoreId = nil
        }
    }

    private var headerStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button(action: moveToPreviousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appTextSecondary)
                }
                Spacer()
                Text(monthTitle(selectedMonth))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                Spacer()
                Button(action: moveToNextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.appTextSecondary)
                }
            }
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onEnded { value in
                        if value.translation.width <= -30 {
                            moveToNextMonth()
                        } else if value.translation.width >= 30 {
                            moveToPreviousMonth()
                        }
                    }
            )

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("총급여")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    Text(totalMonthPayText)
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
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
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.appTextSecondary)
                }
            }

            HStack {
                Text("\(monthTitle(selectedMonth)) 총급여")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                Spacer()
                Text("세후 예상 \(totalMonthNetPayText)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
            }
            HStack {
                Text("예상 환급금")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                Spacer()
                Text(totalRefundEstimateText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextSecondary)
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.appLine, lineWidth: 1)
        )
    }

    private var totalMonthPayText: String {
        formatWon(storePays.reduce(0) { $0 + $1.monthPay })
    }

    private var totalMonthNetPayText: String {
        formatWon(storePays.reduce(0) { $0 + $1.monthNetPay })
    }

    private var totalRefundEstimateText: String {
        let total = storePays.reduce(0.0) { partial, store in
            let estimate = PayrollCalculator.estimateAnnualRefund(
                monthlyTaxablePay: store.monthPay,
                deductionType: store.deductionType
            )
            return partial + estimate.expectedRefund
        }
        return formatWon(total)
    }
    @MainActor
    private func loadData(force: Bool) async {
        #if canImport(Supabase)
        let now = Date()
        let calendar = AppTime.calendar
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
        let monthKey = Self.monthKey(monthStart)
        // Cache: avoid re-fetching on every view transition.
        // Pull-to-refresh or explicit events should pass force=true.
        if !force,
           lastLoadedMonthKey == monthKey,
           let lastLoadedAt,
           now.timeIntervalSince(lastLoadedAt) < 120 {
            return
        }

        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let userId = try await SupabaseManager.shared.currentUserId()
            if !didBackfillPersonalLinks {
                didBackfillPersonalLinks = true
                await backfillPersonalStoreWorkerLinksIfNeeded(userId: userId)
            }
            do {
                try await WorkerAutoRetirement.processForUser(userId: userId)
            } catch {
                if AppErrorMessage.isCancellation(error) {
                    return
                }
                #if DEBUG
                print("DEBUG: auto retirement (worker home) failed: \(error.localizedDescription)")
                #endif
            }
            let workers: [WorkerRow]
            do {
                workers = try await SupabaseManager.shared
                    .client
                    .from("workers")
                    .select("id,store_id,hourly_wage,apply_weekly_allowance,deduction_type,apply_night_allowance,payday,is_active,stores(name,is_personal)")
                    .eq("user_id", value: userId.uuidString)
                    .execute()
                    .value
            } catch {
                // Backward-compatible fetch if DB migration isn't applied yet.
                let message = error.localizedDescription.lowercased()
                if message.contains("apply_night_allowance") || message.contains("payday") {
                    workers = try await SupabaseManager.shared
                        .client
                        .from("workers")
                        .select("id,store_id,hourly_wage,apply_weekly_allowance,deduction_type,is_active,stores(name,is_personal)")
                        .eq("user_id", value: userId.uuidString)
                        .execute()
                        .value
                } else if message.contains("apply_weekly_allowance") || message.contains("deduction_type") {
                    workers = try await SupabaseManager.shared
                        .client
                        .from("workers")
                        .select("id,store_id,hourly_wage,is_active,stores(name,is_personal)")
                        .eq("user_id", value: userId.uuidString)
                        .execute()
                        .value
                } else {
                    throw error
                }
            }

            let activeWorkers = workers.filter { $0.is_active ?? true }

            if activeWorkers.isEmpty {
                storePays = []
                selectedStoreId = nil
                isStoreDropdownExpanded = false
                lastLoadedAt = now
                lastLoadedMonthKey = monthKey
                return
            }

            let workerIds = activeWorkers.map { $0.id.uuidString }
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? Date()
            let iso = AppTime.iso

            let logs: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("store_id,worker_id,check_in_at,check_out_at,status")
                .in("worker_id", values: workerIds)
                .gte("check_in_at", value: iso.string(from: monthStart))
                .lt("check_in_at", value: iso.string(from: monthEnd))
                .execute()
                .value

            let todayStart = calendar.startOfDay(for: Date())
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? Date()

            let parser = AppTime.isoWithFractionalSeconds

            let logsByWorkerId = Dictionary(grouping: logs, by: \.worker_id)
            var result: [StorePay] = []
            for worker in activeWorkers {
                let storeId = worker.store_id
                let wage = worker.hourly_wage ?? 0
                let storeName = worker.stores?.name ?? "매장"
                let isPersonal = worker.stores?.is_personal ?? false
                var applyWeeklyAllowance = worker.apply_weekly_allowance ?? false
                var deductionType = PayrollDeductionType(rawValue: worker.deduction_type ?? "") ?? .withholding
                var applyNightAllowance = worker.apply_night_allowance ?? false
                var payday = min(max(worker.payday ?? PayrollLocalSettings.defaultPayday, 1), 31)

                if isPersonal, let local = PayrollLocalSettingsStore.load(workerId: worker.id) {
                    applyNightAllowance = local.applyNightAllowance
                    payday = local.payday == 0 ? 31 : min(max(local.payday, 1), 31)
                    applyWeeklyAllowance = local.applyWeeklyAllowance
                    deductionType = local.deductionType
                }

                let storeLogs = logsByWorkerId[worker.id, default: []].filter { $0.store_id == storeId }
                let countedLogs = storeLogs.filter { log in
                    let status = log.status ?? "pending"
                    let hasCheckout = !(log.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    return status == "approved" && hasCheckout
                }

                var monthMinutes = 0
                var todayMinutes = 0
                var monthNightMinutes = 0
                var todayNightMinutes = 0

                for log in countedLogs {
                    let checkIn = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
                    let checkOut = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
                    let minutes = WorkerHomeView.calcMinutes(checkIn: checkIn, checkOut: checkOut)
                    let nightMinutes = PayrollCalculator.calcNightMinutes(checkIn: checkIn, checkOut: checkOut)
                    monthMinutes += minutes
                    monthNightMinutes += nightMinutes
                    if checkIn >= todayStart && checkIn < tomorrow {
                        todayMinutes += minutes
                        todayNightMinutes += nightMinutes
                    }
                }

                let monthBasePay = Double(monthMinutes) / 60.0 * wage
                let monthNightPremium = applyNightAllowance ? Double(monthNightMinutes) / 60.0 * wage * PayrollCalculator.nightPremiumRate : 0
                let monthGross = monthBasePay + monthNightPremium
                let weeklyAllowance = applyWeeklyAllowance
                    ? PayrollCalculator.estimateWeeklyAllowancePay(checkInOut: countedLogs.map { ($0.check_in_at, $0.check_out_at) }, wage: wage)
                    : 0
                let breakdown = PayrollCalculator.deductionBreakdown(gross: monthGross + weeklyAllowance, type: deductionType)
                let monthNet = max(0, monthGross + weeklyAllowance - breakdown.totalDeduction)
                let todayBasePay = Double(todayMinutes) / 60.0 * wage
                let todayNightPremium = applyNightAllowance ? Double(todayNightMinutes) / 60.0 * wage * PayrollCalculator.nightPremiumRate : 0

                let storePay = StorePay(
                    id: storeId,
                    workerId: worker.id,
                    name: storeName,
                    isPersonal: isPersonal,
                    hourlyWage: wage,
                    applyWeeklyAllowance: applyWeeklyAllowance,
                    applyNightAllowance: applyNightAllowance,
                    deductionType: deductionType,
                    payday: payday,
                    todayMinutes: todayMinutes,
                    todayPay: todayBasePay + todayNightPremium,
                    monthMinutes: monthMinutes,
                    monthPay: monthGross,
                    monthNetPay: monthNet
                )
                result.append(storePay)
            }

            storePays = result
            reconcileSelectedStore()
            lastLoadedAt = now
            lastLoadedMonthKey = monthKey
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private func reconcileSelectedStore() {
        guard !storePays.isEmpty else {
            selectedStoreId = nil
            isStoreDropdownExpanded = false
            return
        }

        if let selectedStoreId,
           storePays.contains(where: { $0.id == selectedStoreId }) {
            return
        }

        selectedStoreId = storePays.first?.id
        isStoreDropdownExpanded = false
    }

    @MainActor
    private func backfillPersonalStoreWorkerLinksIfNeeded(userId: UUID) async {
        #if canImport(Supabase)
        struct PersonalStoreRow: Decodable {
            let id: UUID
        }
        struct LinkedWorkerRow: Decodable {
            let store_id: UUID
        }
        struct WorkerInsert: Encodable {
            let user_id: UUID
            let store_id: UUID
            let name: String
            let phone: String?
            let hourly_wage: Double
            let is_active: Bool
        }

        do {
            let personalStores: [PersonalStoreRow] = try await SupabaseManager.shared
                .client
                .from("stores")
                .select("id")
                .eq("owner_id", value: userId.uuidString)
                .eq("is_personal", value: true)
                .execute()
                .value

            if personalStores.isEmpty { return }

            let storeIds = personalStores.map { $0.id.uuidString }
            let linkedWorkers: [LinkedWorkerRow] = try await SupabaseManager.shared
                .client
                .from("workers")
                .select("store_id")
                .eq("user_id", value: userId.uuidString)
                .in("store_id", values: storeIds)
                .execute()
                .value

            let linkedStoreIds = Set(linkedWorkers.map { $0.store_id })
            let missingStoreIds = personalStores
                .map { $0.id }
                .filter { !linkedStoreIds.contains($0) }

            if missingStoreIds.isEmpty { return }

            let snapshot = try? await SupabaseManager.shared.fetchProfileSnapshot(id: userId)
            let trimmedProfileName = snapshot?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let workerName = trimmedProfileName.isEmpty ? "나" : trimmedProfileName
            let trimmedPhone = snapshot?.phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let workerPhone = trimmedPhone.isEmpty ? nil : trimmedPhone

            let inserts = missingStoreIds.map { storeId in
                WorkerInsert(
                    user_id: userId,
                    store_id: storeId,
                    name: workerName,
                    phone: workerPhone,
                    hourly_wage: AppConfig.defaultHourlyWage,
                    is_active: true
                )
            }

            _ = try await SupabaseManager.shared
                .client
                .from("workers")
                .insert(inserts)
                .execute()
        } catch {
            #if DEBUG
            print("DEBUG: backfillPersonalStoreWorkerLinksIfNeeded failed: \(error.localizedDescription)")
            #endif
        }
        #endif
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
    private func processRetirement(_ store: StorePay) async {
        #if canImport(Supabase)
        do {
            if store.isPersonal == true {
                _ = try await SupabaseManager.shared
                    .client
                    .from("stores")
                    .delete()
                    .eq("id", value: store.id.uuidString)
                    .execute()
            } else {
                try await SupabaseManager.shared.retireWorkerLink(workerId: store.workerId)
            }
            pendingDeleteStore = nil
            await loadData(force: true)
        } catch {
            deleteError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func beginJoinStoreFlow(token: String) async {
        #if canImport(Supabase)
        do {
            let userId = try await SupabaseManager.shared.currentUserId()
            pendingJoinToken = token
            #if DEBUG
            print("DEBUG: beginJoinStoreFlow start. userId=\(userId) token=\(token)")
            #endif

            let snapshot: SupabaseManager.ProfileSnapshot
            do {
                snapshot = try await SupabaseManager.shared.fetchProfileSnapshot(id: userId)
            } catch {
                // If the profile row doesn't exist yet, create a minimal one and continue with the name gate.
                if SupabaseManager.isPostgrestSingleObjectCoerceError(error) {
                    #if DEBUG
                    print("DEBUG: profile snapshot missing. creating minimal profile row. userId=\(userId)")
                    #endif
                    try await SupabaseManager.shared.ensureMinimalProfileRow(
                        id: userId,
                        email: nil,
                        role: .worker
                    )
                    joinProfileGateName = ""
                    joinProfileGatePhone = ""
                    isPresentingJoinProfileGate = true
                    #if DEBUG
                    print("DEBUG: showing profile gate sheet (name required). userId=\(userId)")
                    #endif
                    return
                }
                throw error
            }

            joinProfileGateName = snapshot.name ?? ""
            joinProfileGatePhone = snapshot.phone ?? ""

            let nameMissing = (snapshot.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            #if DEBUG
            print("DEBUG: profile snapshot loaded. nameMissing=\(nameMissing) name='\(snapshot.name ?? "nil")' phone='\(snapshot.phone ?? "nil")'")
            #endif

            // Hard gate for name only. Phone remains optional for App Review compliance.
            if nameMissing {
                isPresentingJoinProfileGate = true
                #if DEBUG
                print("DEBUG: showing profile gate sheet (name missing). userId=\(userId)")
                #endif
                return
            }

            await joinStore(token: token)
        } catch {
            if SupabaseManager.isProfilesAuthUserForeignKeyError(error) {
                // Local custom session can become inconsistent with Supabase Auth (auth.users).
                // Force a clean logout so the user can log in again.
                await SupabaseManager.shared.signOut()
                NotificationCenter.default.post(name: .didLogout, object: nil)
                loadError = "로그인이 꼬였어요. 다시 로그인해주세요."
            } else {
                loadError = AppErrorMessage.userMessage(error)
            }
            #if DEBUG
            print("DEBUG: beginJoinStoreFlow failed. error=\(error)")
            #endif
        }
        #else
        await joinStore(token: token)
        #endif
    }

    @MainActor
    private func joinStore(token: String) async {
        #if canImport(Supabase)
        do {
            #if DEBUG
            print("DEBUG: joinStore start. token=\(token)")
            #endif
            try await SupabaseManager.shared.acceptInvite(token: token)
            pendingJoinToken = nil
            isPresentingJoinProfileGate = false
            #if DEBUG
            print("DEBUG: joinStore success. token=\(token). reloading data.")
            #endif
            NotificationCenter.default.post(name: .didAcceptInvite, object: nil)
            await loadData(force: true)
        } catch {
            loadError = "초대코드 추가 실패: \(AppErrorMessage.userMessage(error))"
            #if DEBUG
            print("DEBUG: joinStore failed. token=\(token) error=\(error)")
            #endif
        }
        #endif
    }

    @MainActor
    private func createPersonalStore(name: String, address: String) async {
        #if canImport(Supabase)
        do {
            let userId = try await SupabaseManager.shared.currentUserId()
            struct StoreInsert: Encodable {
                let name: String
                let address: String?
                let owner_id: UUID
                let is_personal: Bool
            }
            struct CreatedStoreRow: Decodable {
                let id: UUID
            }
            struct WorkerInsert: Encodable {
                let user_id: UUID
                let store_id: UUID
                let name: String
                let phone: String?
                let hourly_wage: Double
                let is_active: Bool
            }
            let payload = StoreInsert(
                name: name,
                address: address.isEmpty ? nil : address,
                owner_id: userId,
                is_personal: true
            )

            let createdStore: CreatedStoreRow = try await SupabaseManager.shared
                .client
                .from("stores")
                .insert(payload)
                .select("id")
                .single()
                .execute()
                .value

            let snapshot = try? await SupabaseManager.shared.fetchProfileSnapshot(id: userId)
            let trimmedProfileName = snapshot?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let workerName = trimmedProfileName.isEmpty ? "나" : trimmedProfileName
            let trimmedPhone = snapshot?.phone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let workerPayload = WorkerInsert(
                user_id: userId,
                store_id: createdStore.id,
                name: workerName,
                phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                hourly_wage: AppConfig.defaultHourlyWage,
                is_active: true
            )

            do {
                _ = try await SupabaseManager.shared
                    .client
                    .from("workers")
                    .insert(workerPayload)
                    .execute()
            } catch {
                // Keep data consistent: if worker link fails, remove the just-created personal store.
                _ = try? await SupabaseManager.shared
                    .client
                    .from("stores")
                    .delete()
                    .eq("id", value: createdStore.id.uuidString)
                    .execute()
                throw error
            }

            await loadData(force: true)
        } catch {
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private static func calcMinutes(checkIn: Date, checkOut: Date?) -> Int {
        guard let end = checkOut else { return 0 }
        let minutes = floor(end.timeIntervalSince(checkIn) / 60.0)
        return max(0, Int(minutes))
    }

    private func moveToPreviousMonth() {
        let calendar = AppTime.calendar
        selectedMonth = calendar.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
    }

    private func moveToNextMonth() {
        let calendar = AppTime.calendar
        selectedMonth = calendar.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = AppTime.displayFormatter("M월")
        return formatter.string(from: date)
    }

    private static func monthKey(_ date: Date) -> String {
        let formatter = AppTime.displayFormatter("yyyy-MM")
        return formatter.string(from: date)
    }


    private static func formatDate(_ date: Date) -> String {
        let formatter = AppTime.displayFormatter("M/d")
        return formatter.string(from: date)
    }

}

