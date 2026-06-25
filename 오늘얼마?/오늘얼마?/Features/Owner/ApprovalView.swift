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
    private let cacheTTLSeconds: TimeInterval = 120

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !stores.isEmpty {
                    storePicker
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "대기 중")
                    if isLoading && pending.isEmpty && recent.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .appCard()
                    } else if pending.isEmpty {
                        Text("대기 중인 요청이 없어요.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                            .appCard()
                    } else {
                        VStack(spacing: 12) {
                            ForEach(pending) { item in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(workerDisplayName(item))
                                            .font(.system(size: 17, weight: .bold, design: .rounded))
                                            .foregroundColor(.appTextPrimary)
                                        Spacer()
                                        Text(formatRange(item))
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(.appTextSecondary)
                                    }
                                    Text(formatDetail(item))
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextPrimary)

                                    HStack(spacing: 10) {
                                        Button(action: {
                                            Task { await updateStatus(item, status: "rejected") }
                                        }) { Text("반려") }
                                        .buttonStyle(SecondaryButtonStyle(foregroundColor: .appWarning))
                                        Button(action: {
                                            Task { await updateStatus(item, status: "approved") }
                                        }) { Text("승인") }
                                        .buttonStyle(PrimaryButtonStyle())
                                        .disabled(!hasCheckout(item))
                                        .opacity(hasCheckout(item) ? 1.0 : 0.5)
                                    }
                                    if !hasCheckout(item) {
                                        Text("퇴근 처리 후 승인할 수 있어요.")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(.appWarning)
                                    }
                                }
                                .appCard()
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "최근 승인/반려")
                    if recent.isEmpty {
                        Text("최근 내역이 없어요.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                            .appCard()
                    } else {
                        VStack(spacing: 10) {
                            ForEach(recent) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(workerDisplayName(item))
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundColor(.appTextPrimary)
                                        Spacer()
                                        StatusPill(
                                            text: normalizedStatus(item.status) == "approved" ? "승인" : "반려",
                                            color: normalizedStatus(item.status) == "approved" ? .appPositive : .appWarning
                                        )
                                    }
                                    Text(formatRange(item))
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Text(formatDetail(item))
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
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
        .refreshable {
            await refreshFromUser()
        }
        .refreshStatusOverlay(isVisible: isUserRefreshing)
        .background(Color.appBackground.ignoresSafeArea())
        .task {
            await refresh(force: false)
        }
        .onChange(of: selectedStoreId) { _ in
            Task { await loadLogs(force: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await refresh(force: false) }
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
        do {
            let ownerId = try await SupabaseManager.shared.currentUserId()
            let result: [Store] = try await SupabaseManager.shared
                .client
                .from("stores")
                .select()
                .eq("owner_id", value: ownerId.uuidString)
                .execute()
                .value
            stores = result.map { StoreOption(id: $0.id, name: $0.name) }
            if selectedStoreId == nil {
                selectedStoreId = stores.first?.id
            }
            self.lastStoresLoadedAt = now
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func loadLogs(force: Bool) async {
        guard let storeId = selectedStoreId else {
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
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let rows: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,store_id,worker_id,check_in_at,check_out_at,status,workers(name)")
                .eq("store_id", value: storeId.uuidString)
                .order("check_in_at", ascending: false)
                .execute()
                .value

            pending = rows.filter { normalizedStatus($0.status) == "pending" }
            recent = rows.filter {
                let status = normalizedStatus($0.status)
                return status == "approved" || status == "rejected"
            }.prefix(10).map { $0 }
            self.lastLogsLoadedAt = now
            self.lastLogsStoreId = storeId
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
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
            let iso = ISO8601DateFormatter()
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
            await loadLogs(force: true)
        } catch {
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private func hasCheckout(_ item: LogRow) -> Bool {
        !(item.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private func normalizedStatus(_ status: String?) -> String {
        let value = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "pending" : value
    }

    private func workerDisplayName(_ item: LogRow) -> String {
        let trimmed = item.workers?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "알바생" : trimmed
    }

    private func formatRange(_ item: LogRow) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let start = parser.date(from: item.check_in_at) ?? iso.date(from: item.check_in_at) ?? Date()
        let end = item.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
        let formatter = DateFormatter()
        formatter.dateFormat = "M월 d일 HH:mm"
        let startText = formatter.string(from: start)
        let endText = end.map { formatter.string(from: $0) } ?? "--:--"
        return "\(startText) - \(endText)"
    }

    private func formatDetail(_ item: LogRow) -> String {
        let minutes = calcMinutes(checkIn: item.check_in_at, checkOut: item.check_out_at)
        return "\(formatHours(minutes)) 근무 요청"
    }

    private func calcMinutes(checkIn: String, checkOut: String?) -> Int {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let start = parser.date(from: checkIn) ?? iso.date(from: checkIn) ?? Date()
        let end = checkOut.flatMap { parser.date(from: $0) ?? iso.date(from: $0) } ?? Date()
        let minutes = floor(end.timeIntervalSince(start) / 60.0)
        return max(0, Int(minutes))
    }

    private func formatHours(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)시간 \(m)분"
    }
}
