import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct OwnerWorkerLogsView: View {
    let storeId: UUID
    let workerId: UUID
    let workerName: String

    struct LogRow: Decodable, Identifiable {
        let id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
    }

    @State private var logs: [LogRow] = []
    @State private var isLoading = false
    @State private var loadError: String?

    private let calendar = AppTime.calendar
    private let isoFormatter = AppTime.iso

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workerName)
                        .font(.system(size: 26, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundColor(.appTextPrimary)
                    Text("이번 달 근무 \(logs.count)건")
                        .font(.app(.callout, .medium))
                        .foregroundColor(.appTextSecondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)

                if isLoading && logs.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .appCard()
                } else if logs.isEmpty {
                    Text("근무 내역이 없어요.")
                        .font(.app(.callout, .medium))
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(logs.enumerated()), id: \.element.id) { index, log in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color.appLine)
                                    .frame(height: 1)
                            }
                            logRow(log)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 4)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
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
            await loadLogs()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("근무 내역")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadLogs()
        }
    }

    private func logRow(_ log: LogRow) -> some View {
        let (minutes, rangeText) = computeMinutesAndRange(log)
        let color = normalizedStatus(log.status) == "pending" ? Color.appCaution : statusColor(log.status)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rangeText)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.appTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(formatHours(minutes))
                    .font(.app(.caption))
                    .foregroundColor(.appTextSecondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(statusLabel(log.status))
                    .font(.app(.caption, .semibold))
                    .foregroundColor(color)
            }
        }
        .padding(.vertical, 13)
    }

    @MainActor
    private func loadLogs() async {
        #if canImport(Supabase)
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? Date()
            let startISO = isoFormatter.string(from: start)
            let endISO = isoFormatter.string(from: end)

            let rows: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at,check_out_at,status")
                .eq("store_id", value: storeId.uuidString)
                .eq("worker_id", value: workerId.uuidString)
                .gte("check_in_at", value: startISO)
                .lt("check_in_at", value: endISO)
                .order("check_in_at", ascending: false)
                .limit(200)
                .execute()
                .value
            logs = rows
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private func computeMinutesAndRange(_ log: LogRow) -> (Int, String) {
        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso

        let start = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
        let isOpen = log.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let parsedEnd = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
        let minutes = (isOpen || parsedEnd == nil) ? 0 : max(0, Int(floor((parsedEnd?.timeIntervalSince(start) ?? 0) / 60.0)))

        let df = AppTime.displayFormatter("M월 d일 HH:mm")
        let startText = df.string(from: start)
        let endText = (isOpen || parsedEnd == nil) ? "진행 중" : df.string(from: parsedEnd ?? start)
        return (minutes, "\(startText) - \(endText)")
    }




}
