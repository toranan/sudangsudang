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

    private let calendar = Calendar.current
    private let isoFormatter = ISO8601DateFormatter()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: workerName, trailing: "이번 달 근무")

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .appCard()
                } else if logs.isEmpty {
                    Text("근무 내역이 없어요.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                        .appCard()
                } else {
                    VStack(spacing: 10) {
                        ForEach(logs) { log in
                            logRow(log)
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
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("근무 내역")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadLogs()
        }
        .task {
            await loadLogs()
        }
    }

    private func logRow(_ log: LogRow) -> some View {
        let (minutes, rangeText) = computeMinutesAndRange(log)
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rangeText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                Text("\(formatHours(minutes)) · \(statusLabel(log.status))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
            }
            Spacer()
            StatusPill(text: statusLabel(log.status), color: statusColor(log.status))
        }
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appLine, lineWidth: 1)
        )
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
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()

        let start = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
        let isOpen = log.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let parsedEnd = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
        let minutes = (isOpen || parsedEnd == nil) ? 0 : max(0, Int(floor((parsedEnd?.timeIntervalSince(start) ?? 0) / 60.0)))

        let df = DateFormatter()
        df.dateFormat = "M월 d일 HH:mm"
        let startText = df.string(from: start)
        let endText = (isOpen || parsedEnd == nil) ? "진행 중" : df.string(from: parsedEnd ?? start)
        return (minutes, "\(startText) - \(endText)")
    }

    private func normalizedStatus(_ status: String?) -> String {
        let value = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "pending" : value
    }

    private func statusLabel(_ status: String?) -> String {
        let value = normalizedStatus(status)
        return value == "approved" ? "승인" : (value == "rejected" ? "반려" : "대기")
    }

    private func statusColor(_ status: String?) -> Color {
        let value = normalizedStatus(status)
        return value == "approved" ? .appPositive : (value == "rejected" ? .appWarning : .appTextSecondary)
    }

    private func formatHours(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)시간 \(m)분"
    }
}
