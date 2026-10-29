import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct ApprovalView: View {
    struct StoreOption: Identifiable, Hashable {
        let id: UUID
        let name: String
    }

    struct WorkerInfo: Decodable {
        let name: String
    }

    struct LogRow: Decodable, Identifiable {
        let id: UUID
        let store_id: UUID
        let worker_id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
        let workers: WorkerInfo?
    }

    @State private var stores: [StoreOption] = []
    @State private var selectedStoreId: UUID?
    @State private var pending: [LogRow] = []
    @State private var recent: [LogRow] = []
    @State private var isLoading = false
    @State private var isUserRefreshing = false
    @State private var loadError: String?
    @State private var lastStoresLoadedAt: Date?
    @State private var lastLogsLoadedAt: Date?
    @State private var lastLogsStoreId: UUID?
    @State private var storesRequest = LatestRequest()
    @State private var logsRequest = LatestRequest()
    private let cacheTTLSeconds: TimeInterval = 120

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("근무 승인")
                        .font(.system(size: 26, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundColor(.appTextPrimary)
                    Text(pending.isEmpty ? "확인할 근무가 없어요" : "승인 기다리는 근무 \(pending.count)건")
                        .font(.app(.callout, .medium))
                        .foregroundColor(.appTextSecondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 8)

                if !stores.isEmpty {
                    storePicker
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("대기 중", count: pending.count)
                    if isLoading && pending.isEmpty && recent.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .appCard()
                    } else if pending.isEmpty {
                        Text("대기 중인 요청이 없어요.")
                            .font(.app(.callout, .medium))
                            .foregroundColor(.appTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appCard()
                    } else {
                        VStack(spacing: 10) {
                            ForEach(pending) { item in
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack(spacing: 12) {
                                        workerAvatar(item)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(workerDisplayName(item))
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.appTextPrimary)
                                            Text(formatRange(item))
                                                .font(.app(.caption))
                                                .foregroundColor(.appTextSecondary)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.85)
                                        }
                                        Spacer(minLength: 8)
                                        statusDot(
                                            hasCheckout(item) ? "승인 대기" : "근무 중",
                                            color: hasCheckout(item) ? .appCaution : .appAccent
                                        )
                                    }

                                    Text(formatDetail(item))
                                        .font(.app(.callout, .semibold))
                                        .foregroundColor(.appTextPrimary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 11)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.appFill)
                                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.field, style: .continuous))

                                    HStack(spacing: 8) {
                                        Button(action: {
                                            Task { await updateStatus(item, status: "rejected") }
                                        }) {
                                            decisionLabel("반려", foreground: .appWarning, background: Color.appWarning.opacity(0.12))
                                        }
                                        .buttonStyle(PressableRowStyle())
                                        Button(action: {
                                            Task { await updateStatus(item, status: "approved") }
                                        }) {
                                            decisionLabel("승인", foreground: .appOnInk, background: .appInk)
                                        }
                                        .buttonStyle(PressableRowStyle())
                                        .disabled(!hasCheckout(item))
                                        .opacity(hasCheckout(item) ? 1.0 : 0.5)
                                    }
                                    if !hasCheckout(item) {
                                        Text("퇴근 처리 후 승인할 수 있어요.")
                                            .font(.app(.caption, .medium))
                                            .foregroundColor(.appTextSecondary)
                                    }
                                }
                                .appCard()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("최근 승인/반려", count: nil)
                    if recent.isEmpty {
                        Text("최근 내역이 없어요.")
                            .font(.app(.callout, .medium))
                            .foregroundColor(.appTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appCard()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(recent.enumerated()), id: \.element.id) { index, item in
                                if index > 0 {
                                    Rectangle()
                                        .fill(Color.appLine)
                                        .frame(height: 1)
                                }
                                HStack(spacing: 12) {
                                    workerAvatar(item)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(workerDisplayName(item))
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(.appTextPrimary)
                                        Text(formatRange(item))
                                            .font(.app(.caption))
                                            .foregroundColor(.appTextSecondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                        Text(formatDetail(item))
                                            .font(.app(.caption))
                                            .foregroundColor(.appTextSecondary)
                                    }
                                    Spacer(minLength: 8)
                                    statusDot(
                                        normalizedStatus(item.status) == "approved" ? "승인" : "반려",
                                        color: normalizedStatus(item.status) == "approved" ? .appAccent : .appWarning
                                    )
                                }
                                .padding(.vertical, 12)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 4)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                    }
                }

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
            Task { await loadLogs(force: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await refresh(force: false) }
        }
    }

    private func sectionTitle(_ title: String, count: Int?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 19, weight: .heavy))
                .tracking(-0.4)
                .foregroundColor(.appTextPrimary)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundColor(.appAccent)
            }
        }
        .padding(.horizontal, 4)
    }

    private func workerAvatar(_ item: LogRow) -> some View {
        Text(String(workerDisplayName(item).prefix(1)))
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.appAccent)
            .frame(width: 34, height: 34)
            .background(Color.appAccentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    // 반려·승인을 반씩 나눠 쓰는 낮은 버튼.
    private func decisionLabel(_ title: String, foreground: Color, background: Color) -> some View {
        Text(title)
            .font(.app(.callout, .semibold))
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.field, style: .continuous))
    }

    private func statusDot(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.app(.caption, .semibold))
                .foregroundColor(color)
        }
    }

    private var storePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(stores) { store in
                    let isSelected = store.id == selectedStoreId
                    Button(action: { selectedStoreId = store.id }) {
                        Text(store.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isSelected ? .appOnInk : .appTextSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(isSelected ? Color.appInk : Color.appSurface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
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
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func loadLogs(force: Bool) async {
        guard let storeId = selectedStoreId else {
            logsRequest.invalidate()
            pending = []
            recent = []
            return
        }
        #if canImport(Supabase)
        let now = Date()
        if !force,
           let lastLogsLoadedAt,
           let lastLogsStoreId,
           lastLogsStoreId == storeId,
           now.timeIntervalSince(lastLogsLoadedAt) < cacheTTLSeconds {
            return
        }
        let requestID = logsRequest.begin()
        isLoading = true
        loadError = nil
        defer {
            if logsRequest.isCurrent(requestID) {
                isLoading = false
            }
        }
        do {
            // 화면에 필요한 것만 받는다: 대기 전체 + 최근 처리 10건 (매장 전체 이력을 받지 않음).
            let columns = "id,store_id,worker_id,check_in_at,check_out_at,status,workers(name)"
            async let pendingRows: [LogRow] = SupabaseManager.shared
                .client
                .from("work_logs")
                .select(columns)
                .eq("store_id", value: storeId.uuidString)
                .or("status.is.null,status.eq.pending")
                .order("check_in_at", ascending: false)
                .execute()
                .value
            async let recentRows: [LogRow] = SupabaseManager.shared
                .client
                .from("work_logs")
                .select(columns)
                .eq("store_id", value: storeId.uuidString)
                .in("status", values: ["approved", "rejected"])
                .order("check_in_at", ascending: false)
                .limit(10)
                .execute()
                .value
            let (pendingResult, recentResult) = try await (pendingRows, recentRows)

            guard logsRequest.isCurrent(requestID), selectedStoreId == storeId else { return }
            pending = pendingResult
            recent = recentResult
            self.lastLogsLoadedAt = now
            self.lastLogsStoreId = storeId
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            guard logsRequest.isCurrent(requestID), selectedStoreId == storeId else { return }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func refresh(force: Bool) async {
        await loadStores(force: force)
        await loadLogs(force: force)
    }

    @MainActor
    private func updateStatus(_ item: LogRow, status: String) async {
        #if canImport(Supabase)
        if status == "approved", !hasCheckout(item) {
            loadError = "퇴근 처리된 기록만 승인할 수 있어요."
            return
        }
        do {
            let ownerId = try await SupabaseManager.shared.currentUserId()
            struct UpdatePayload: Encodable {
                let status: String
                let approved_by: UUID
                let approved_at: String
            }
            let iso = AppTime.iso
            let payload = UpdatePayload(
                status: status,
                approved_by: ownerId,
                approved_at: iso.string(from: Date())
            )
            _ = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .update(payload)
                .eq("id", value: item.id.uuidString)
                .execute()
            Haptics.success()
            applyStatusLocally(item, status: status)
            NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
        } catch {
            Haptics.error()
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    // 승인/반려 직후 전체를 다시 받지 않고 대기 목록에서 최근 처리로 옮긴다.
    @MainActor
    private func applyStatusLocally(_ item: LogRow, status: String) {
        let updated = LogRow(
            id: item.id,
            store_id: item.store_id,
            worker_id: item.worker_id,
            check_in_at: item.check_in_at,
            check_out_at: item.check_out_at,
            status: status,
            workers: item.workers
        )
        withAnimation(.easeOut(duration: 0.2)) {
            pending.removeAll { $0.id == item.id }
            recent = Array(([updated] + recent.filter { $0.id != item.id })
                .sorted { $0.check_in_at > $1.check_in_at }
                .prefix(10))
        }
    }

    private func hasCheckout(_ item: LogRow) -> Bool {
        !(item.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }


    private func workerDisplayName(_ item: LogRow) -> String {
        let trimmed = item.workers?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "알바생" : trimmed
    }

    private func formatRange(_ item: LogRow) -> String {
        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso
        let start = parser.date(from: item.check_in_at) ?? iso.date(from: item.check_in_at) ?? Date()
        let end = item.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
        let formatter = AppTime.displayFormatter("M월 d일 HH:mm")
        let startText = formatter.string(from: start)
        let endText = end.map { formatter.string(from: $0) } ?? "--:--"
        return "\(startText) - \(endText)"
    }

    private func formatDetail(_ item: LogRow) -> String {
        let minutes = calcMinutes(checkIn: item.check_in_at, checkOut: item.check_out_at)
        return "\(formatHours(minutes)) 근무 요청"
    }

    private func calcMinutes(checkIn: String, checkOut: String?) -> Int {
        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso
        let start = parser.date(from: checkIn) ?? iso.date(from: checkIn) ?? Date()
        let end = checkOut.flatMap { parser.date(from: $0) ?? iso.date(from: $0) } ?? Date()
        let minutes = floor(end.timeIntervalSince(start) / 60.0)
        return max(0, Int(minutes))
    }

}
