import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

// 직원 설정 화면의 '고정 근무' 카드. 스케줄 탭과 같은 schedule_templates를 요일 칩으로 보여주고 여기서 바로 고친다.
struct WorkerFixedScheduleCard: View {
    let workerId: UUID
    let storeId: UUID

    struct TemplateRow: Decodable, Identifiable {
        let id: UUID
        let weekday: Int
        let check_in_time: String
        let check_out_time: String?
    }

    // weekday는 0=일 … 6=토. 화면에는 월요일부터 보여준다.
    static let weekdayOrder = [1, 2, 3, 4, 5, 6, 0]
    static let weekdayTitles = ["일", "월", "화", "수", "목", "금", "토"]

    @State private var templates: [TemplateRow] = []
    @State private var isLoading = true
    @State private var isEditing = false
    @State private var errorMessage: String?

    private var activeDays: Set<Int> {
        Set(templates.map(\.weekday))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("고정 근무")
                    .font(.app(.callout, .semibold))
                    .foregroundColor(.appTextPrimary)
                Spacer()
                Button("편집") { isEditing = true }
                    .font(.app(.callout, .semibold))
                    .foregroundColor(.appAccent)
                    .disabled(isLoading)
            }

            HStack(spacing: 6) {
                ForEach(Self.weekdayOrder, id: \.self) { day in
                    let isOn = activeDays.contains(day)
                    Text(Self.weekdayTitles[day])
                        .font(.app(.caption, .bold))
                        .foregroundColor(isOn ? .white : .appTextSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            isOn ? Color.appAccent : Color.appFill,
                            in: RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                        )
                }
            }

            Text(summaryText)
                .font(.app(.caption))
                .foregroundColor(.appTextSecondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appWarning)
            }
        }
        .padding(18)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        .task { await load() }
        .sheet(isPresented: $isEditing) {
            WorkerFixedScheduleEditor(
                initialDays: activeDays,
                initialStart: templates.first.map { Self.clock($0.check_in_time) } ?? "18:00",
                initialEnd: templates.first?.check_out_time.map(Self.clock) ?? "22:00"
            ) { days, start, end in
                await save(days: days, start: start, end: end)
            }
        }
    }

    private var summaryText: String {
        guard !templates.isEmpty else { return "정해진 근무 요일이 없어요" }
        let hours = Self.weeklyHoursText(templates)
        let ranges = Set(templates.map { "\(Self.clock($0.check_in_time)) – \($0.check_out_time.map(Self.clock) ?? "미정")" })
        if ranges.count == 1, let range = ranges.first {
            return "\(range) · 주 \(hours)시간"
        }
        return "요일마다 시간이 달라요 · 주 \(hours)시간"
    }

    // "18:00:00" → "18:00"
    static func clock(_ time: String) -> String {
        String(time.prefix(5))
    }

    private static func minutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    // 퇴근이 출근보다 이르면 자정을 넘긴 근무로 본다.
    static func weeklyHoursText(_ templates: [TemplateRow]) -> String {
        let total = templates.reduce(0) { sum, row in
            guard let start = minutes(row.check_in_time),
                  let end = row.check_out_time.flatMap(minutes) else { return sum }
            return sum + (end > start ? end - start : end + 24 * 60 - start)
        }
        let hours = Double(total) / 60
        return hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
    }

    // MARK: - Data

    @MainActor
    private func load() async {
        #if canImport(Supabase)
        defer { isLoading = false }
        do {
            templates = try await SupabaseManager.shared.client
                .from("schedule_templates")
                .select("id,weekday,check_in_time,check_out_time")
                .eq("worker_id", value: workerId.uuidString)
                .eq("store_id", value: storeId.uuidString)
                .eq("is_active", value: true)
                .order("weekday")
                .execute()
                .value
            errorMessage = nil
        } catch {
            guard !AppErrorMessage.isCancellation(error) else { return }
            errorMessage = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    // 빠진 요일은 끄고(앞으로 생길 일정도 지움), 남은 요일은 시간을 바꾸고, 새 요일은 추가한다.
    @MainActor
    private func save(days: Set<Int>, start: String, end: String) async {
        #if canImport(Supabase)
        let client = SupabaseManager.shared.client
        let now = AppTime.isoString(from: Date())
        let startTime = start + ":00"
        let endTime = end + ":00"
        do {
            struct Deactivate: Encodable { let is_active: Bool; let updated_at: String }
            struct UpdateTimes: Encodable { let check_in_time: String; let check_out_time: String; let updated_at: String }
            struct Insert: Encodable {
                let store_id: UUID
                let worker_id: UUID
                let weekday: Int
                let check_in_time: String
                let check_out_time: String
                let is_active: Bool
                let created_by: UUID
            }

            let removed = templates.filter { !days.contains($0.weekday) }
            if !removed.isEmpty {
                let ids = removed.map(\.id.uuidString)
                try await client.from("schedule_templates")
                    .update(Deactivate(is_active: false, updated_at: now))
                    .in("id", values: ids)
                    .execute()
                let today = AppTime.displayFormatter("yyyy-MM-dd").string(from: Date())
                try await client.from("schedule_entries")
                    .delete()
                    .in("template_id", values: ids)
                    .gte("work_date", value: today)
                    .execute()
            }

            let kept = templates.filter { days.contains($0.weekday) }
            if !kept.isEmpty {
                try await client.from("schedule_templates")
                    .update(UpdateTimes(check_in_time: startTime, check_out_time: endTime, updated_at: now))
                    .in("id", values: kept.map(\.id.uuidString))
                    .execute()
            }

            let added = days.subtracting(activeDays)
            if !added.isEmpty {
                let ownerId = try await SupabaseManager.shared.currentUserId()
                try await client.from("schedule_templates")
                    .insert(added.sorted().map {
                        Insert(
                            store_id: storeId,
                            worker_id: workerId,
                            weekday: $0,
                            check_in_time: startTime,
                            check_out_time: endTime,
                            is_active: true,
                            created_by: ownerId
                        )
                    })
                    .execute()
            }
            Haptics.success()
            await load()
        } catch {
            errorMessage = AppErrorMessage.userMessage(error)
        }
        #endif
    }
}

// 요일을 고르고 출퇴근 시간을 한 번에 정하는 작은 시트.
private struct WorkerFixedScheduleEditor: View {
    let initialDays: Set<Int>
    let initialStart: String
    let initialEnd: String
    let onSave: (Set<Int>, String, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var days: Set<Int> = []
    @State private var start = Date()
    @State private var end = Date()
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("고정 근무")
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.4)
                .foregroundColor(.appTextPrimary)

            HStack(spacing: 6) {
                ForEach(WorkerFixedScheduleCard.weekdayOrder, id: \.self) { day in
                    let isOn = days.contains(day)
                    Button {
                        Haptics.tap()
                        if isOn { days.remove(day) } else { days.insert(day) }
                    } label: {
                        Text(WorkerFixedScheduleCard.weekdayTitles[day])
                            .font(.app(.caption, .bold))
                            .foregroundColor(isOn ? .white : .appTextSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                isOn ? Color.appAccent : Color.appFill,
                                in: RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(spacing: 0) {
                timeRow("출근", selection: $start)
                Rectangle().fill(Color.appLine).frame(height: 1)
                timeRow("퇴근", selection: $end)
            }
            .padding(.horizontal, 16)
            .background(Color.appFill)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.field, style: .continuous))

            Button(isSaving ? "저장 중..." : "저장") {
                Task {
                    isSaving = true
                    await onSave(days, Self.text(start), Self.text(end))
                    isSaving = false
                    dismiss()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .background(Color.appSurface.ignoresSafeArea())
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .onAppear {
            days = initialDays
            start = Self.date(initialStart)
            end = Self.date(initialEnd)
        }
    }

    private func timeRow(_ title: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(title)
                .font(.app(.callout, .semibold))
                .foregroundColor(.appTextPrimary)
            Spacer()
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .padding(.vertical, 8)
    }

    private static func date(_ clock: String) -> Date {
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        return AppTime.calendar.date(
            bySettingHour: parts.first ?? 9,
            minute: parts.count > 1 ? parts[1] : 0,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private static func text(_ date: Date) -> String {
        AppTime.displayFormatter("HH:mm").string(from: date)
    }
}
