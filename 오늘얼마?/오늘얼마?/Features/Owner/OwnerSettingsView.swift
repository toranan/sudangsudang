import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

// 사장님 설정 탭: 항목을 눌러 들어가 바꾸는 목록.
struct OwnerSettingsView: View {
    @State private var isShowingDeleteAccountConfirm = false
    @State private var isShowingDeleteAccountError = false
    @State private var deleteAccountErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("설정")
                    .font(.system(size: 26, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundColor(.appTextPrimary)
                    .padding(.top, 10)

                group("매장") {
                    NavigationLink {
                        PayrollDefaultsView()
                    } label: {
                        row(
                            "급여 기본값",
                            subtitle: "시급 · 휴게 · 주휴 · 야간 · 공제",
                            systemImage: "wonsign",
                            showsChevron: true
                        )
                    }
                    .buttonStyle(PressableRowStyle())
                }

                group("계정") {
                    Button {
                        Task {
                            await SupabaseManager.shared.signOut()
                            NotificationCenter.default.post(name: .didLogout, object: nil)
                        }
                    } label: {
                        row("로그아웃", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(PressableRowStyle())

                    Rectangle().fill(Color.appLine).frame(height: 1)

                    Button {
                        isShowingDeleteAccountConfirm = true
                    } label: {
                        row("계정 삭제", systemImage: "trash", color: .appWarning)
                    }
                    .buttonStyle(PressableRowStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color.appBackground.ignoresSafeArea())
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
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.app(.caption, .semibold))
                .foregroundColor(.appTextSecondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0, content: content)
                .padding(.horizontal, 18)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        }
    }

    private func row(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String,
        color: Color = .appTextPrimary,
        showsChevron: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color == .appTextPrimary ? .appAccent : color)
                .frame(width: 34, height: 34)
                .background(color == .appTextPrimary ? Color.appAccentSoft : color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.callout, .semibold))
                    .foregroundColor(color)
                if let subtitle {
                    Text(subtitle)
                        .font(.app(.caption))
                        .foregroundColor(.appTextSecondary)
                }
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.appTextSecondary)
            }
        }
        .padding(.vertical, 14)
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
}

// 매장 기본 급여 규칙. 직원별로 다르게 할 항목만 알바관리 → 직원 → 설정에서 바꾼다.
struct PayrollDefaultsView: View {
    struct StoreDefaults: Codable, Identifiable, Equatable {
        let id: UUID
        let name: String
        var default_hourly_wage: Double
        var default_apply_weekly_allowance: Bool
        var default_apply_night_allowance: Bool
        var default_deduction_type: String
        var default_break_policy: String
        var default_break_minutes: Int
    }

    private struct DefaultsUpdate: Encodable {
        let default_hourly_wage: Double
        let default_apply_weekly_allowance: Bool
        let default_apply_night_allowance: Bool
        let default_deduction_type: String
        let default_break_policy: String
        let default_break_minutes: Int
    }

    @State private var stores: [StoreDefaults] = []
    @State private var selectedStoreId: UUID?
    @State private var draft: StoreDefaults?
    @State private var wageInput: String = ""
    @State private var breakMinutesInput: String = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var needsDatabaseUpdate = false
    @State private var loadError: String?
    @State private var saveMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                payrollDefaultsSection

                if let loadError {
                    Text(loadError)
                        .font(.app(.caption, .medium))
                        .foregroundColor(.appWarning)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .appRefreshable {
            await load()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .task {
            await load()
        }
        .navigationTitle("급여 기본값")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    // MARK: - Payroll defaults

    @ViewBuilder
    private var payrollDefaultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stores.count > 1 {
                HStack {
                    Spacer()
                    storePicker
                }
            }

            if needsDatabaseUpdate {
                Text("DB 업데이트 후 사용할 수 있어요.")
                    .font(.app(.callout))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard()
            } else if isLoading && draft == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .appCard()
            } else if stores.isEmpty {
                Text("매장을 등록하면 기본값을 정할 수 있어요.")
                    .font(.app(.callout))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard()
            } else if let draft {
                VStack(alignment: .leading, spacing: 0) {
                    settingRow("시급") {
                        HStack(spacing: 6) {
                            TextField("10320", text: $wageInput)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.app(.body, .semibold))
                                .frame(width: 110)
                            Text("원")
                                .font(.app(.body))
                                .foregroundColor(.appTextSecondary)
                        }
                    }
                    MinimumWageHint(input: wageInput)
                        .padding(.bottom, 6)

                    Divider()

                    settingRow("무급 휴게") {
                        choiceChips(
                            PayrollBreakPolicy.allCases.map { ($0.rawValue, $0 == .none ? "없음" : $0 == .statutory ? "법정" : "직접") },
                            selected: draft.default_break_policy
                        ) { self.draft?.default_break_policy = $0 }
                    }
                    if draft.default_break_policy == PayrollBreakPolicy.custom.rawValue {
                        settingRow("근무마다") {
                            HStack(spacing: 6) {
                                TextField("30", text: $breakMinutesInput)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.app(.body, .semibold))
                                    .frame(width: 60)
                                Text("분")
                                    .font(.app(.body))
                                    .foregroundColor(.appTextSecondary)
                            }
                        }
                    }
                    Text(breakHelpText(for: draft.default_break_policy))
                        .font(.app(.caption))
                        .foregroundColor(.appTextSecondary)
                        .padding(.bottom, 12)

                    Divider()

                    settingRow("주휴수당") {
                        choiceChips([("on", "지급"), ("off", "미지급")], selected: draft.default_apply_weekly_allowance ? "on" : "off") {
                            self.draft?.default_apply_weekly_allowance = ($0 == "on")
                        }
                    }

                    Divider()

                    settingRow("야간수당") {
                        choiceChips([("on", "지급"), ("off", "미지급")], selected: draft.default_apply_night_allowance ? "on" : "off") {
                            self.draft?.default_apply_night_allowance = ($0 == "on")
                        }
                    }

                    Divider()

                    settingRow("공제") {
                        choiceChips(
                            PayrollDeductionType.allCases.map { ($0.rawValue, $0 == .withholding ? "3.3%" : "4대보험") },
                            selected: draft.default_deduction_type
                        ) { self.draft?.default_deduction_type = $0 }
                    }
                }
                .appCard()

                Text("직원마다 다르게 하려면 알바관리 → 직원 → 설정에서 바꿀 수 있어요.")
                    .font(.app(.caption))
                    .foregroundColor(.appTextSecondary)
                    .padding(.horizontal, 4)

                Button(isSaving ? "저장 중..." : "저장") {
                    Task { await save() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving || !hasChanges || AppConfig.isBelowMinimumWage(wageInput))

                if let saveMessage {
                    Text(saveMessage)
                        .font(.app(.caption, .medium))
                        .foregroundColor(.appPositive)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var storePicker: some View {
        Menu {
            ForEach(stores) { store in
                Button(store.name) { select(store.id) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(stores.first(where: { $0.id == selectedStoreId })?.name ?? "매장")
                    .font(.app(.callout, .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundColor(.appTextSecondary)
        }
    }

    private func settingRow<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title)
                .font(.app(.body, .medium))
                .foregroundColor(.appTextPrimary)
            Spacer()
            trailing()
        }
        .padding(.vertical, 12)
    }

    private func choiceChips(
        _ options: [(value: String, title: String)],
        selected: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        ChoiceChips(options: options, selected: selected, onSelect: onSelect)
    }

    private func breakHelpText(for policy: String) -> String {
        switch PayrollBreakPolicy(rawOrNone: policy) {
        case .none:
            return "근무시간 전부를 급여로 계산해요. 4시간 이상 근무에는 휴게 30분을 줘야 해요."
        case .statutory:
            return "4시간 이상 근무 시 30분, 8시간 30분 이상 근무 시 1시간을 무급으로 빼요."
        case .custom:
            return "근무마다 입력한 시간만큼 무급으로 빼요."
        }
    }

    // MARK: - Data

    private var hasChanges: Bool {
        guard let draft, let original = stores.first(where: { $0.id == draft.id }) else { return false }
        return resolvedDraft(draft) != original
    }

    private func resolvedDraft(_ draft: StoreDefaults) -> StoreDefaults {
        var resolved = draft
        resolved.default_hourly_wage = Double(wageInput.filter(\.isNumber)) ?? draft.default_hourly_wage
        resolved.default_break_minutes = draft.default_break_policy == PayrollBreakPolicy.custom.rawValue
            ? min(240, Int(breakMinutesInput.filter(\.isNumber)) ?? 0)
            : 0
        return resolved
    }

    private func select(_ storeId: UUID) {
        selectedStoreId = storeId
        saveMessage = nil
        guard let store = stores.first(where: { $0.id == storeId }) else {
            draft = nil
            return
        }
        draft = store
        wageInput = String(Int(store.default_hourly_wage))
        breakMinutesInput = store.default_break_minutes > 0 ? String(store.default_break_minutes) : ""
    }

    @MainActor
    private func load() async {
        #if canImport(Supabase)
        isLoading = true
        defer { isLoading = false }
        do {
            let ownerId = try await SupabaseManager.shared.currentUserId()
            let rows: [StoreDefaults] = try await SupabaseManager.shared
                .client
                .from("stores")
                .select("id,name,default_hourly_wage,default_apply_weekly_allowance,default_apply_night_allowance,default_deduction_type,default_break_policy,default_break_minutes")
                .eq("owner_id", value: ownerId.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value
            needsDatabaseUpdate = false
            loadError = nil
            stores = rows
            let keep = selectedStoreId.flatMap { id in rows.first(where: { $0.id == id })?.id }
            if let id = keep ?? rows.first?.id {
                select(id)
            } else {
                draft = nil
            }
        } catch {
            if AppErrorMessage.isCancellation(error) { return }
            // 마이그레이션(20261029_store_payroll_defaults) 적용 전이면 컬럼이 없다.
            if error.localizedDescription.lowercased().contains("default_") {
                needsDatabaseUpdate = true
                return
            }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func save() async {
        #if canImport(Supabase)
        guard let draft else { return }
        let resolved = resolvedDraft(draft)
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await SupabaseManager.shared
                .client
                .from("stores")
                .update(DefaultsUpdate(
                    default_hourly_wage: max(0, resolved.default_hourly_wage),
                    default_apply_weekly_allowance: resolved.default_apply_weekly_allowance,
                    default_apply_night_allowance: resolved.default_apply_night_allowance,
                    default_deduction_type: resolved.default_deduction_type,
                    default_break_policy: resolved.default_break_policy,
                    default_break_minutes: resolved.default_break_minutes
                ))
                .eq("id", value: resolved.id.uuidString)
                .execute()
            if let index = stores.firstIndex(where: { $0.id == resolved.id }) {
                stores[index] = resolved
            }
            select(resolved.id)
            Haptics.success()
            saveMessage = "저장했어요. 매장 기본값을 따르는 직원에게 바로 적용돼요."
            NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
        } catch {
            Haptics.error()
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }
}
