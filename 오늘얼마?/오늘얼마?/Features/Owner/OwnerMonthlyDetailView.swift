import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct OwnerMonthlyDetailView: View {
    let storeId: UUID

    struct WorkerRow: Decodable, Identifiable {
        let id: UUID
        let name: String
        let phone: String?
        let hourly_wage: Double?
        let is_active: Bool?
    }

    struct LogRow: Decodable, Identifiable {
        let id: UUID
        let worker_id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String
    }

    struct Totals {
        let minutes: Int
        let pay: Double
    }

    @State private var workers: [WorkerRow] = []
    @State private var totalsByWorker: [UUID: Totals] = [:]
    @State private var isLoading = false
    @State private var loadError: String?

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "이번 달 알바별")

                if isLoading {
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
                            NavigationLink {
                                OwnerWorkerLogsView(storeId: storeId, workerId: worker.id, workerName: worker.name)
                            } label: {
                                workerRow(worker)
                            }
                            .buttonStyle(.plain)
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
        .navigationTitle("상세")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAll()
        }
    }

    private func workerRow(_ worker: WorkerRow) -> some View {
        let totals = totalsByWorker[worker.id] ?? Totals(minutes: 0, pay: 0)
        return HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(Color.appAccent.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(worker.name.prefix(1)))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.appAccent)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(worker.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                Text("총 \(formatHours(totals.minutes)) · \(formatWon(totals.pay))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.appLine)
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
    private func loadAll() async {
        #if canImport(Supabase)
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let rows: [WorkerRow] = try await SupabaseManager.shared
                .client
                .from("workers")
                .select("id,name,phone,hourly_wage,is_active")
                .eq("store_id", value: storeId.uuidString)
                .order("joined_at", ascending: true)
                .execute()
                .value
            workers = rows

            let (startISO, endISO) = monthRangeISO(for: Date())
            let logs: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,worker_id,check_in_at,check_out_at,status")
                .eq("store_id", value: storeId.uuidString)
                .gte("check_in_at", value: startISO)
                .lt("check_in_at", value: endISO)
                .execute()
                .value

            totalsByWorker = buildTotals(workers: rows, logs: logs)
        } catch {
            loadError = error.localizedDescription
        }
        #endif
    }

    private func buildTotals(workers: [WorkerRow], logs: [LogRow]) -> [UUID: Totals] {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()

        let wageByWorker = Dictionary(uniqueKeysWithValues: workers.map { ($0.id, $0.hourly_wage ?? 0) })

        var minutesByWorker: [UUID: Int] = [:]
        for log in logs {
            let start = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
            let end = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) } ?? Date()
            let minutes = calcMinutes(checkIn: start, checkOut: end)
            minutesByWorker[log.worker_id, default: 0] += minutes
        }

        var result: [UUID: Totals] = [:]
        for (workerId, minutes) in minutesByWorker {
            let wage = wageByWorker[workerId] ?? 0
            let pay = Double(minutes) / 60.0 * wage
            result[workerId] = Totals(minutes: minutes, pay: pay)
        }
        return result
    }

    private func monthRangeISO(for date: Date) -> (String, String) {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? date
        let iso = ISO8601DateFormatter()
        return (iso.string(from: start), iso.string(from: end))
    }

    private func calcMinutes(checkIn: Date, checkOut: Date) -> Int {
        let minutes = floor(checkOut.timeIntervalSince(checkIn) / 60.0)
        return max(0, Int(minutes))
    }

    private func formatWon(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: Int(value))) ?? "0"
        return "\(number)원"
    }

    private func formatHours(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)시간 \(m)분"
    }
}
