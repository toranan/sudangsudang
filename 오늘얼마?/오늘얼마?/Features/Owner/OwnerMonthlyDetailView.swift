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
        let apply_night_allowance: Bool?
        let apply_weekly_allowance: Bool?
        let is_active: Bool?
    }

    struct LogRow: Decodable, Identifiable, WeeklyAllowanceLogFields {
        let id: UUID
        let worker_id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
        let applied_hourly_wage: Double?
        let applied_break_policy: String?
        let applied_break_minutes: Int?
        let applied_weekly_allowance: Bool?
        let applied_night_allowance: Bool?
    }

    struct Totals {
        let minutes: Int
        let pay: Double
    }

    @State private var workers: [WorkerRow] = []
    @State private var totalsByWorker: [UUID: Totals] = [:]
    @State private var isLoading = false
    @State private var loadError: String?

    private let calendar = AppTime.calendar

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                summaryCard

                Text("알바별")
                    .font(.system(size: 19, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundColor(.appTextPrimary)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)

                if isLoading && workers.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .appCard()
                } else if workers.isEmpty {
                    Text("등록된 알바가 없어요.")
                        .font(.app(.callout, .medium))
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(workers.enumerated()), id: \.element.id) { index, worker in
                            if index > 0 {
                                Rectangle()
                                    .fill(Color.appLine)
                                    .frame(height: 1)
                            }
                            NavigationLink {
                                OwnerWorkerLogsView(storeId: storeId, workerId: worker.id, workerName: worker.name)
                            } label: {
                                workerRow(worker)
                            }
                            .buttonStyle(PressableRowStyle())
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
            .padding(.top, 12)
            .padding(.bottom, appTabBarReservedHeight + 24)
        }
        .appRefreshable {
            await loadAll()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("상세")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAll()
        }
    }

    // 승인된 근무만 합산한 이번 달 합계.
    private var summaryCard: some View {
        let totalPay = totalsByWorker.values.reduce(0) { $0 + $1.pay }
        let totalMinutes = totalsByWorker.values.reduce(0) { $0 + $1.minutes }
        return VStack(alignment: .leading, spacing: 6) {
            Text("이번 달 승인된 인건비")
                .font(.app(.callout, .medium))
                .foregroundColor(.appTextSecondary)
            Text(formatWon(totalPay))
                .font(.system(size: 34, weight: .heavy))
                .tracking(-1)
                .foregroundColor(.appTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("총 \(formatHours(totalMinutes)) · 알바 \(workers.count)명 · 주휴수당 포함")
                .font(.app(.caption, .medium))
                .foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private func workerRow(_ worker: WorkerRow) -> some View {
        let totals = totalsByWorker[worker.id] ?? Totals(minutes: 0, pay: 0)
        return HStack(alignment: .center, spacing: 12) {
            Text(String(worker.name.prefix(1)))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.appAccent)
                .frame(width: 40, height: 40)
                .background(Color.appAccentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(worker.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.appTextPrimary)
                Text("총 \(formatHours(totals.minutes))")
                    .font(.app(.caption))
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()

            Text(formatWon(totals.pay))
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.appTextPrimary)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.appTextSecondary.opacity(0.6))
        }
        .padding(.vertical, 12)
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
                .select("id,name,phone,hourly_wage,apply_night_allowance,apply_weekly_allowance,is_active")
                .eq("store_id", value: storeId.uuidString)
                .order("joined_at", ascending: true)
                .execute()
                .value
            workers = rows

            // 달을 걸친 주의 주휴수당을 계산하려고 앞뒤 주까지 받는다.
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
            let allowanceRange = PayrollCalculator.weeklyAllowanceLogRange(forMonth: monthStart)
            let startISO = AppTime.iso.string(from: allowanceRange.start)
            let endISO = AppTime.iso.string(from: allowanceRange.end)
            let logs: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,worker_id,check_in_at,check_out_at,status,applied_hourly_wage,applied_night_allowance,applied_break_policy,applied_break_minutes,applied_weekly_allowance")
                .eq("store_id", value: storeId.uuidString)
                .gte("check_in_at", value: startISO)
                .lt("check_in_at", value: endISO)
                .execute()
                .value

            totalsByWorker = buildTotals(workers: rows, logs: logs, monthStart: monthStart)
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private func buildTotals(workers: [WorkerRow], logs: [LogRow], monthStart: Date) -> [UUID: Totals] {
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso

        let wageByWorker = Dictionary(uniqueKeysWithValues: workers.map { ($0.id, $0.hourly_wage ?? 0) })
        let nightAllowanceByWorker = Dictionary(uniqueKeysWithValues: workers.map { ($0.id, $0.apply_night_allowance ?? false) })

        var minutesByWorker: [UUID: Int] = [:]
        var payByWorker: [UUID: Double] = [:]
        var allowanceLogsByWorker: [UUID: [LogRow]] = [:]
        for log in logs {
            guard normalizedStatus(log.status) == "approved" else { continue }
            let hasCheckout = !(log.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            guard hasCheckout else { continue }
            allowanceLogsByWorker[log.worker_id, default: []].append(log)

            guard let start = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at),
                  start >= monthStart, start < monthEnd else { continue }
            guard let end = log.check_out_at.flatMap({ parser.date(from: $0) ?? iso.date(from: $0) }) else { continue }
            let minutes = PayrollCalculator.calcPaidMinutes(checkIn: start, checkOut: end, appliedBreakPolicy: log.applied_break_policy, appliedBreakMinutes: log.applied_break_minutes)
            minutesByWorker[log.worker_id, default: 0] += minutes
            payByWorker[log.worker_id, default: 0] += PayrollCalculator.grossPay(
                checkIn: start,
                checkOut: end,
                appliedHourlyWage: log.applied_hourly_wage,
                appliedNightAllowance: log.applied_night_allowance,
                fallbackHourlyWage: wageByWorker[log.worker_id] ?? 0,
                fallbackNightAllowance: nightAllowanceByWorker[log.worker_id] ?? false,
                appliedBreakPolicy: log.applied_break_policy,
                appliedBreakMinutes: log.applied_break_minutes
            )
        }

        // 알바 목록·직원 상세와 같게 주휴수당을 더한다.
        for worker in workers {
            payByWorker[worker.id, default: 0] += PayrollCalculator.estimateWeeklyAllowancePay(
                logs: allowanceLogsByWorker[worker.id] ?? [],
                fallbackWage: worker.hourly_wage ?? 0,
                fallbackApply: worker.apply_weekly_allowance ?? false,
                attributedToMonth: monthStart
            )
        }

        var result: [UUID: Totals] = [:]
        for (workerId, pay) in payByWorker {
            result[workerId] = Totals(minutes: minutesByWorker[workerId] ?? 0, pay: pay)
        }
        return result
    }

    private func calcMinutes(checkIn: Date, checkOut: Date) -> Int {
        let minutes = floor(checkOut.timeIntervalSince(checkIn) / 60.0)
        return max(0, Int(minutes))
    }



}
