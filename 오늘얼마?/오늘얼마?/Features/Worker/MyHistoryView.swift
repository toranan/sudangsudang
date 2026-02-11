import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct MyHistoryView: View {
    struct WorkerRow: Decodable {
        let id: UUID
        let store_id: UUID
        let hourly_wage: Double?
        let apply_weekly_allowance: Bool?
        let deduction_type: String?
        let stores: StoreName?
    }

    struct StoreName: Decodable {
        let name: String
        let is_personal: Bool?
    }

    struct LogRow: Decodable, Identifiable {
        let id: UUID
        let store_id: UUID
        let worker_id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String
    }

    struct WorkItem: Identifiable {
        let id = UUID()
        let date: String
        let time: String
        let hours: String
        let pay: String
        let status: String
        let statusColor: Color
    }

    @State private var monthWorkedText: String = "0시간"
    @State private var monthPayText: String = "0원"
    @State private var monthNetPayText: String = "0원"
    @State private var items: [WorkItem] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "이번 달 요약")
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("총 근무 시간")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                            Text(monthWorkedText)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.appTextPrimary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text("세전 예상")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                            Text(monthPayText)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.appTextPrimary)
                            Text("세후 예상 \(monthNetPayText)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                        }
                    }
                    .appCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "최근 근무 기록")

                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .appCard()
                    } else if items.isEmpty {
                        Text("근무 기록이 없어요.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                            .appCard()
                    } else {
                        VStack(spacing: 10) {
                            ForEach(items) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    Circle()
                                        .fill(Color.appLine)
                                        .frame(width: 44, height: 44)
                                        .overlay(
                                            Image(systemName: "calendar")
                                                .foregroundColor(.appTextSecondary)
                                        )
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(item.date)
                                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            StatusPill(text: item.status, color: item.statusColor)
                                        }
                                        Text(item.time)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(.appTextSecondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 6) {
                                        Text(item.hours)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundColor(.appTextPrimary)
                                        Text(item.pay)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
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
                        }
                    }

                    if let loadError {
                        Text(loadError)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appWarning)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .task {
            await loadData()
        }
    }

    @MainActor
    private func loadData() async {
        #if canImport(Supabase)
        isLoading = true
        defer { isLoading = false }
        do {
            let userId = try await SupabaseManager.shared.currentUserId()
            let workers: [WorkerRow]
            do {
                workers = try await SupabaseManager.shared
                    .client
                    .from("workers")
                    .select("id,store_id,hourly_wage,apply_weekly_allowance,deduction_type,stores(name,is_personal)")
                    .eq("user_id", value: userId.uuidString)
                    .execute()
                    .value
            } catch {
                let message = error.localizedDescription.lowercased()
                if message.contains("apply_weekly_allowance") || message.contains("deduction_type") {
                    workers = try await SupabaseManager.shared
                        .client
                        .from("workers")
                        .select("id,store_id,hourly_wage,stores(name,is_personal)")
                        .eq("user_id", value: userId.uuidString)
                        .execute()
                        .value
                } else {
                    throw error
                }
            }

            let workerById = Dictionary(uniqueKeysWithValues: workers.map { ($0.id, $0) })
            let workerIds = workers.map { $0.id.uuidString }

            if workerIds.isEmpty {
                items = []
                monthWorkedText = "0시간"
                monthPayText = "0원"
                monthNetPayText = "0원"
                return
            }

            let calendar = Calendar.current
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? Date()
            let iso = ISO8601DateFormatter()

            let logs: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,store_id,worker_id,check_in_at,check_out_at,status")
                .in("worker_id", values: workerIds)
                .gte("check_in_at", value: iso.string(from: monthStart))
                .lt("check_in_at", value: iso.string(from: monthEnd))
                .order("check_in_at", ascending: false)
                .execute()
                .value

            let parser = ISO8601DateFormatter()
            parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M월 d일"

            var totalMinutes = 0
            var totalPay: Double = 0
            var rendered: [WorkItem] = []

            let countedLogs = logs.filter { $0.status != "rejected" }

            // Summary totals should include the entire month (not only the first page).
            for log in countedLogs {
                let checkIn = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
                let checkOut = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
                let minutes = Self.calcMinutes(checkIn: checkIn, checkOut: checkOut)
                totalMinutes += minutes

                let worker = workerById[log.worker_id]
                let wage = worker?.hourly_wage ?? 0
                let pay = Double(minutes) / 60.0 * wage
                totalPay += pay
            }

            // Net pay summary is computed per worker record (store-specific settings).
            var netTotal: Double = 0
            let grouped = Dictionary(grouping: countedLogs, by: { $0.worker_id })
            for (workerId, wLogs) in grouped {
                guard let worker = workerById[workerId] else { continue }
                let wage = worker.hourly_wage ?? 0
                let minutes = wLogs.reduce(0) { partial, log in
                    let checkIn = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
                    let checkOut = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
                    return partial + Self.calcMinutes(checkIn: checkIn, checkOut: checkOut)
                }
                let gross = Double(minutes) / 60.0 * wage
                var applyWeekly = worker.apply_weekly_allowance ?? false
                var deductionType = PayrollDeductionType(rawValue: worker.deduction_type ?? "") ?? .withholding
                if worker.stores?.is_personal == true,
                   let local = PayrollLocalSettingsStore.load(workerId: worker.id) {
                    applyWeekly = local.applyWeeklyAllowance
                    deductionType = local.deductionType
                }
                let weeklyAllowance = applyWeekly
                    ? PayrollCalculator.estimateWeeklyAllowancePay(checkInOut: wLogs.map { ($0.check_in_at, $0.check_out_at) }, wage: wage)
                    : 0
                let breakdown = PayrollCalculator.deductionBreakdown(gross: gross + weeklyAllowance, type: deductionType)
                let net = max(0, gross + weeklyAllowance - breakdown.totalDeduction)
                netTotal += net
            }

            // Render list items (first page only)
            for log in logs.prefix(20) {
                let checkIn = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
                let checkOut = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
                let minutes = Self.calcMinutes(checkIn: checkIn, checkOut: checkOut)

                let worker = workerById[log.worker_id]
                let wage = worker?.hourly_wage ?? 0
                let pay = Double(minutes) / 60.0 * wage

                let start = timeFormatter.string(from: checkIn)
                let end = checkOut.map { timeFormatter.string(from: $0) } ?? "--:--"
                let statusColor: Color = log.status == "approved" ? .appPositive : (log.status == "rejected" ? .appWarning : .appTextSecondary)
                let statusLabel: String = log.status == "approved" ? "승인" : (log.status == "rejected" ? "반려" : "대기")

                rendered.append(
                    WorkItem(
                        date: dateFormatter.string(from: checkIn),
                        time: "\(start) - \(end)",
                        hours: Self.formatHours(minutes),
                        pay: Self.formatWon(pay),
                        status: statusLabel,
                        statusColor: statusColor
                    )
                )
            }

            monthWorkedText = Self.formatHours(totalMinutes)
            monthPayText = Self.formatWon(totalPay)
            monthNetPayText = Self.formatWon(netTotal)
            items = rendered
        } catch {
            loadError = error.localizedDescription
        }
        #endif
    }

    private static func calcMinutes(checkIn: Date, checkOut: Date?) -> Int {
        let end = checkOut ?? Date()
        let minutes = floor(end.timeIntervalSince(checkIn) / 60.0)
        return max(0, Int(minutes))
    }

    private static func formatWon(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let number = formatter.string(from: NSNumber(value: Int(value))) ?? "0"
        return "\(number)원"
    }

    private static func formatHours(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)시간 \(m)분"
    }
}
