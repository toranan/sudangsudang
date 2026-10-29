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
        let applied_hourly_wage: Double?
        let applied_night_allowance: Bool?
    }

    @State private var storePays: [StorePay] = []
    @State private var selectedStoreId: UUID?
    @State private var isStoreDropdownExpanded = false
    @State private var chatTarget: StoreChatTarget?
    @State private var isLoading = false
    @State private var isUserRefreshing = false
    @State private var loadError: String?
    @State private var lastLoadedAt: Date?
    @State private var lastLoadedMonthKey: String?
    @State private var latestLoadRequestID: UUID?
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
            .fullScreenCover(item: $chatTarget) { target in
                WorkerStoreChatView(storeId: target.id, storeName: target.name)
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
                VStack(alignment: .leading, spacing: 14) {
                    headerStrip
                    storePaySection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .appRefreshable {
                await refreshFromUser()
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
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
        VStack(alignment: .leading, spacing: 12) {
            if isLoading && storePays.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .appCard()
            } else if storePays.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("아직 등록된 매장이 없어요")
                        .font(.app(.headline, .bold))
                        .foregroundColor(.appTextPrimary)
                    Text("사장님께 받은 매장 코드를 입력하거나, 혼자 쓰는 매장을 직접 추가할 수 있어요.")
                        .font(.app(.callout))
                        .foregroundColor(.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: { isPresentingJoinStore = true }) {
                        Text("매장 코드 입력하기")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button(action: { isPresentingPersonalStore = true }) {
                        Text("매장 추가하기")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .appCard()
            } else {
                if isStoreDropdownExpanded {
                    workerStoreDropdown
                }

                if let selectedStorePay {
                    selectedStoreSummaryCard(selectedStorePay)
                    selectedStorePayCard(selectedStorePay)
                    selectedStoreStatTiles(selectedStorePay)
                    selectedStoreQuickMenu(selectedStorePay)
                }
            }

            if let loadError {
                Text(loadError)
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appWarning)
            }
            if let deleteError {
                Text(deleteError)
                    .font(.app(.caption, .medium))
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

    // 매장 캡슐을 누르면 펼쳐지는 매장 목록.
    private var workerStoreDropdown: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                let rows = [selectedStorePay].compactMap { $0 } + selectableStorePays
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, store in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.appLine)
                            .frame(height: 1)
                    }
                    workerStoreDropdownRow(store, isSelected: store.id == selectedStorePay?.id)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))

            HStack(spacing: 10) {
                ActionTile(
                    title: "매장 코드 입력",
                    subtitle: "사장님 매장 연결",
                    systemImage: "number"
                ) {
                    isPresentingJoinStore = true
                }
                ActionTile(
                    title: "매장 추가",
                    subtitle: "혼자 기록하기",
                    systemImage: "plus",
                    tint: .appLavender,
                    fill: .appLavenderSoft
                ) {
                    isPresentingPersonalStore = true
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func workerStoreDropdownRow(_ store: StorePay, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                selectStore(store)
                withAnimation(.easeInOut(duration: 0.18)) {
                    isStoreDropdownExpanded = false
                }
            } label: {
                HStack(spacing: 12) {
                    storeAvatar(store)
                    workerStoreInfo(store)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.appAccent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableRowStyle())

            workerStoreMenu(store)
        }
        .padding(.vertical, 12)
    }

    private func storeAvatar(_ store: StorePay) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(store.isPersonal ? Color.appLavenderSoft : Color.appAccentSoft)
            .frame(width: 40, height: 40)
            .overlay(
                Text(String(store.name.prefix(1)))
                    .font(.app(.callout, .bold))
                    .foregroundColor(store.isPersonal ? .appLavender : .appAccent)
            )
    }

    private func workerStoreInfo(_ store: StorePay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(store.name)
                    .font(.app(.body, .bold))
                    .foregroundColor(.appTextPrimary)
                    .lineLimit(1)

                if store.isPersonal {
                    Text("개인")
                        .font(.app(.caption, .semibold))
                        .foregroundColor(.appLavender)
                }
            }

            Text("시급 \(formatWon(store.hourlyWage)) · 월급일 \(store.paydayText)")
                .font(.app(.caption))
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.appTextSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
    }

    private func selectStore(_ store: StorePay) {
        selectedStoreId = store.id
    }

    // 오늘 번 돈과 출퇴근 화면으로 가는 검정 버튼.
    private func selectedStoreSummaryCard(_ store: StorePay) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(store.todayMinutes > 0 ? Color.appAccent : Color.appTextSecondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                Text(store.todayMinutes > 0 ? "오늘 \(store.todayWorkedText) 근무" : "오늘 기록된 근무가 없어요")
                    .font(.app(.caption, .bold))
                    .foregroundColor(store.todayMinutes > 0 ? .appAccent : .appTextSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(store.todayMinutes > 0 ? Color.appAccentSoft : Color.appFill, in: Capsule())

            Text(store.todayPayText)
                .font(.system(size: 36, weight: .heavy))
                .tracking(-1.2)
                .monospacedDigit()
                .foregroundColor(.appTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .padding(.top, 8)

            Text("오늘 번 돈")
                .font(.app(.callout))
                .foregroundColor(.appTextSecondary)

            NavigationLink {
                WorkerCheckInView(store: store)
            } label: {
                Text("출근 · 퇴근하기")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func selectedStorePayCard(_ store: StorePay) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(monthTitle(selectedMonth)) 예상 급여")
                    .font(.app(.callout, .medium))
                    .foregroundColor(.white.opacity(0.8))
                Text(store.monthPayText)
                    .font(.system(size: 23, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text("월급날까지")
                    .font(.app(.caption, .medium))
                    .foregroundColor(.white.opacity(0.8))
                Text(paydayDDayText(store))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(Color.appAccent)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func paydayDDayText(_ store: StorePay) -> String {
        let calendar = AppTime.calendar
        let today = calendar.startOfDay(for: Date())
        let payday = calendar.startOfDay(for: PayrollPayday.nextPaydayDate(payday: store.payday))
        let days = calendar.dateComponents([.day], from: today, to: payday).day ?? 0
        return days <= 0 ? "D-Day" : "D-\(days)"
    }

    private func selectedStoreStatTiles(_ store: StorePay) -> some View {
        HStack(spacing: 10) {
            statTile(title: "\(monthTitle(selectedMonth)) 근무", value: store.monthWorkedText)
            statTile(title: "세후 예상", value: store.monthNetPayText, valueColor: .appAccent)
            statTile(title: "시급", value: formatWon(store.hourlyWage))
        }
    }

    private func statTile(title: String, value: String, valueColor: Color = .appTextPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.appTextSecondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func selectedStoreQuickMenu(_ store: StorePay) -> some View {
        HStack(spacing: 10) {
            NavigationLink {
                WorkerStoreKnowledgeView(storeId: store.id, storeName: store.name)
            } label: {
                workerQuickMenuRow(icon: "megaphone.fill", title: "가게 소식", subtitle: "공지 · 매뉴얼")
            }
            .buttonStyle(PressableRowStyle())

            Button {
                chatTarget = StoreChatTarget(id: store.id, name: store.name)
            } label: {
                workerQuickMenuRow(
                    icon: "sparkles",
                    title: "물어보기",
                    subtitle: "매장 챗봇",
                    tint: .appLavender,
                    fill: .appLavenderSoft
                )
            }
            .buttonStyle(PressableRowStyle())
        }
    }

    // ActionTile과 같은 모양이지만 NavigationLink 라벨로 쓴다.
    private func workerQuickMenuRow(
        icon: String,
        title: String,
        subtitle: String,
        tint: Color = .appAccent,
        fill: Color = .appAccentSoft
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.appTextPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.appTextSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                if let selectedStorePay {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isStoreDropdownExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(selectedStorePay.name)
                                .font(.app(.callout, .bold))
                                .foregroundColor(.appTextPrimary)
                                .lineLimit(1)
                            Image(systemName: isStoreDropdownExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.appTextSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.appSurface, in: Capsule())
                    }
                    .buttonStyle(PressableRowStyle())
                }

                Spacer(minLength: 8)

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
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.appTextSecondary)
                        .frame(width: 36, height: 36)
                        .background(Color.appSurface, in: Circle())
                }
            }

            // 좌우로 밀어서 달을 바꾼다.
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(monthTitle(selectedMonth)) 총급여 · 세후 \(totalMonthNetPayText)")
                        .font(.app(.callout, .medium))
                        .foregroundColor(.appTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(totalMonthPayText)
                        .font(.system(size: 23, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundColor(.appTextPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 12)
                HStack(spacing: 2) {
                    Button(action: moveToPreviousMonth) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.appTextSecondary)
                            .frame(width: 30, height: 30)
                    }
                    Text(monthTitle(selectedMonth))
                        .font(.app(.caption, .bold))
                        .foregroundColor(.appTextPrimary)
                    Button(action: moveToNextMonth) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.appTextSecondary)
                            .frame(width: 30, height: 30)
                    }
                }
                .padding(.horizontal, 2)
                .background(Color.appSurface, in: Capsule())
            }
            .padding(.horizontal, 4)
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
        }
    }

    private var totalMonthPayText: String {
        formatWon(storePays.reduce(0) { $0 + $1.monthPay })
    }

    private var totalMonthNetPayText: String {
        formatWon(storePays.reduce(0) { $0 + $1.monthNetPay })
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

        let requestID = UUID()
        latestLoadRequestID = requestID
        isLoading = true
        loadError = nil
        defer {
            if latestLoadRequestID == requestID {
                isLoading = false
            }
        }
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
                guard latestLoadRequestID == requestID else { return }
                storePays = []
                selectedStoreId = nil
                isStoreDropdownExpanded = false
                lastLoadedAt = now
                lastLoadedMonthKey = monthKey
                return
            }

            let workerIds = activeWorkers.map { $0.id.uuidString }
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? Date()
            let allowanceLogRange = PayrollCalculator.weeklyAllowanceLogRange(forMonth: monthStart)
            let iso = AppTime.iso

            let logs: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("store_id,worker_id,check_in_at,check_out_at,status,applied_hourly_wage,applied_night_allowance")
                .in("worker_id", values: workerIds)
                .gte("check_in_at", value: iso.string(from: allowanceLogRange.start))
                .lt("check_in_at", value: iso.string(from: allowanceLogRange.end))
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
                let allowanceLogs = storeLogs.filter { log in
                    let status = log.status ?? "pending"
                    let hasCheckout = !(log.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    return status == "approved" && hasCheckout
                }
                let countedLogs = allowanceLogs.filter { log in
                    guard let checkIn = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) else {
                        return false
                    }
                    return checkIn >= monthStart && checkIn < monthEnd
                }

                var monthMinutes = 0
                var todayMinutes = 0
                var monthGross = 0.0
                var todayGross = 0.0

                for log in countedLogs {
                    let checkIn = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
                    let checkOut = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
                    let minutes = WorkerHomeView.calcMinutes(checkIn: checkIn, checkOut: checkOut)
                    let gross = PayrollCalculator.grossPay(
                        checkIn: checkIn,
                        checkOut: checkOut,
                        appliedHourlyWage: log.applied_hourly_wage,
                        appliedNightAllowance: log.applied_night_allowance,
                        fallbackHourlyWage: wage,
                        fallbackNightAllowance: applyNightAllowance
                    )
                    monthMinutes += minutes
                    monthGross += gross
                    if checkIn >= todayStart && checkIn < tomorrow {
                        todayMinutes += minutes
                        todayGross += gross
                    }
                }

                let weeklyAllowance = applyWeeklyAllowance
                    ? PayrollCalculator.estimateWeeklyAllowancePay(
                        checkInOut: allowanceLogs.map { ($0.check_in_at, $0.check_out_at) },
                        wage: wage,
                        attributedToMonth: monthStart
                    )
                    : 0
                let breakdown = PayrollCalculator.deductionBreakdown(gross: monthGross + weeklyAllowance, type: deductionType)
                let monthNet = max(0, monthGross + weeklyAllowance - breakdown.totalDeduction)

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
                    todayPay: todayGross,
                    monthMinutes: monthMinutes,
                    monthPay: monthGross,
                    monthNetPay: monthNet
                )
                result.append(storePay)
            }

            guard latestLoadRequestID == requestID else { return }
            storePays = result
            reconcileSelectedStore()
            lastLoadedAt = now
            lastLoadedMonthKey = monthKey
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard latestLoadRequestID == requestID else { return }
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
