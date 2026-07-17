import SwiftUI
import Combine
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(Supabase)
import Supabase
#endif

struct WorkerCheckInView: View {
    let store: WorkerHomeView.StorePay
    @State private var isCheckedIn: Bool = false
    @State private var currentLogId: UUID?
    @State private var currentCheckInAt: Date?
    @State private var liveMinutes: Int = 0
    @State private var isLoadingAction: Bool = false
    @State private var actionError: String?
    @State private var monthLogsForNet: [WorkLogRow] = []
    @State private var isLoadingMonthLogsForNet = false
    @State private var startHourInput: String = ""
    @State private var startMinuteInput: String = ""
    @State private var endHourInput: String = ""
    @State private var endMinuteInput: String = ""
    @State private var isSavingManual = false
    @State private var manualError: String?
    @State private var applyWeeklyAllowance: Bool = false
    @State private var applyNightAllowance: Bool = false
    @State private var deductionType: PayrollDeductionType = .withholding
    @State private var payday: Int = PayrollLocalSettings.defaultPayday
    @State private var fixedSchedules: [WorkerFixedSchedule] = []
    @State private var fixedWeekday: Int = 1
    @State private var fixedStartHourInput: String = ""
    @State private var fixedStartMinuteInput: String = ""
    @State private var fixedEndHourInput: String = ""
    @State private var fixedEndMinuteInput: String = ""
    @State private var fixedScheduleError: String?
    @State private var isShowingFixedScheduleInput = false
    @State private var isShowingManualAddInput = false
    @State private var isAutoApplyingFixedSchedule = false
    @State private var lastAutoFixedScheduleCheckKey: String?
    @State private var lastAutoFixedScheduleCheckedAt: Date?
    private var allowManualAdd: Bool { store.isPersonal }
    private var shouldAutoApproveLogs: Bool { store.isPersonal }
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let autoFixedScheduleCheckThrottle: TimeInterval = 300

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("오늘 근무")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("근무 시간")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                Text(formatHours(displayMinutes))
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Text("예상 급여")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                Text(formatWon(displayPay))
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                            }
                        }
                        .appCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("이번 달 요약")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("총 근무 시간")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                Text(store.monthWorkedText)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                Text("세전 예상")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                Text(store.monthPayText)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(.appTextPrimary)
                                Text("세후 예상 \(monthNetPayText())")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                            }
                        }
                        .appCard()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "출퇴근")
                        VStack(spacing: 12) {
                            Button(action: {
                                Task { await toggleCheckIn() }
                            }) {
                                HStack {
                                    if isLoadingAction {
                                        ProgressView()
                                            .tint(.white)
                                        Text("처리 중...")
                                    } else {
                                        Image(systemName: isCheckedIn ? "stop.fill" : "play.fill")
                                        Text(isCheckedIn ? "퇴근하기" : "출근하기")
                                    }
                                }
                            }
                            .buttonStyle(PrimaryButtonStyle(backgroundColor: isCheckedIn ? .appWarning : .appAccent))
                            .disabled(isLoadingAction)
                            .opacity(isLoadingAction ? 0.6 : 1.0)

                            HStack {
                                Image(systemName: "mappin.circle.fill")
                                .foregroundColor(.appTextSecondary)
                                Text(isCheckedIn ? "\(store.name)에서 근무 중" : "\(store.name) 출근 대기")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, 4)
                        }
                        if let actionError {
                            Text(actionError)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appWarning)
                        }
                    }

                    if store.isPersonal {
                        fixedScheduleSection
                    }

                    manualAddSection

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "세부 설정")
                        VStack(alignment: .leading, spacing: 10) {
                            if store.isPersonal {
                                Toggle(isOn: $applyWeeklyAllowance) {
                                    Text("주휴수당 적용")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextPrimary)
                                }
                                .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                                .onChange(of: applyWeeklyAllowance) { _ in
                                    persistLocalPayrollSettings()
                                }

                                Toggle(isOn: $applyNightAllowance) {
                                    Text("야간수당 적용 (22:00~06:00 +50%)")
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextPrimary)
                                }
                                .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                                .onChange(of: applyNightAllowance) { _ in
                                    persistLocalPayrollSettings()
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("공제 방식 (택 1)")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    HStack(spacing: 8) {
                                        ForEach(PayrollDeductionType.allCases) { option in
                                            Button(action: {
                                                deductionType = option
                                                persistLocalPayrollSettings()
                                            }) {
                                                Text(option.title)
                                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                                    .foregroundColor(deductionType == option ? .white : .appTextPrimary)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 10)
                                                    .background(deductionType == option ? Color.appAccent : Color.appSurface)
                                                    .cornerRadius(10)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 10)
                                                            .stroke(deductionType == option ? Color.appAccent : Color.appLine, lineWidth: 1)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("월급일")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Picker("월급일", selection: $payday) {
                                        ForEach(1...31, id: \.self) { day in
                                            Text("\(day)일").tag(day)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .onChange(of: payday) { _ in
                                        persistLocalPayrollSettings()
                                    }
                                }

                                HStack {
                                    Text("정산기간")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Spacer()
                                    Text("매월 1일 ~ 말일")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                }

                                Text("다음 월급일 \(nextPaydayDateText())")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)

                                Text("개인 매장의 세부 설정은 이 기기에서만 저장돼요.")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("사장님이 설정한 기준이 적용돼요.")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(.appTextPrimary)
                                    Text("공제 방식: \(store.deductionType.title)")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Text("주휴수당: \(store.applyWeeklyAllowance ? "적용" : "미적용")")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Text("야간수당: \(store.applyNightAllowance ? "적용" : "미적용")")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Text("월급일: 매월 \(store.paydayText)")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Text("정산기간: 매월 1일 ~ 말일")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Text("다음 월급일 \(nextPaydayDateText())")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                }
                            }
                        }
                        .appCard()
                    }

                historyEntryCard

                if store.isPersonal {
                    refundEstimateSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
        .navigationTitle(store.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadCurrentLog()
            await loadMonthLogsForNet()
            NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
        }
        .task {
            if store.isPersonal {
                // Personal store defaults: withholding + no night/weekly allowance.
                applyWeeklyAllowance = false
                applyNightAllowance = false
                deductionType = .withholding
                payday = PayrollLocalSettings.defaultPayday
                if let local = PayrollLocalSettingsStore.load(workerId: store.workerId) {
                    applyWeeklyAllowance = local.applyWeeklyAllowance
                    applyNightAllowance = local.applyNightAllowance
                    deductionType = local.deductionType
                    let localPayday = local.payday == 0 ? PayrollLocalSettings.defaultPayday : local.payday
                    payday = min(max(localPayday, 1), 31)
                }
                loadFixedSchedules()
            } else {
                applyWeeklyAllowance = store.applyWeeklyAllowance
                applyNightAllowance = store.applyNightAllowance
                deductionType = store.deductionType
                payday = store.payday
            }
            await loadCurrentLog()
            await autoAddCompletedFixedSchedulesIfNeeded()
            await loadMonthLogsForNet()
        }
        .onReceive(timer) { _ in
            updateLiveMinutes()
            Task { await autoAddCompletedFixedSchedulesIfNeeded() }
        }
    }

    private var historyEntryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "내역")
            NavigationLink {
                WorkerStoreHistoryView(
                    storeName: store.name,
                    storeId: store.id,
                    workerId: store.workerId,
                    hourlyWage: store.hourlyWage
                )
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("내역 보기")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                        Text("전체 근무 내역을 화면에서 길게 확인할 수 있어요.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
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
            .buttonStyle(.plain)
        }
        .appCard()
    }

    private var manualAddSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "근무 추가")
            if allowManualAdd {
                VStack(alignment: .leading, spacing: 10) {
                    Button(isShowingManualAddInput ? "입력 닫기" : "추가하기") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingManualAddInput.toggle()
                            if !isShowingManualAddInput {
                                manualError = nil
                            }
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .appCard()

                if isShowingManualAddInput {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("출근 시간")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                timeInputRow(hour: $startHourInput, minute: $startMinuteInput)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("퇴근 시간")
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                timeInputRow(hour: $endHourInput, minute: $endMinuteInput)
                            }
                        }

                        Text("종료가 출근보다 빠르면 다음날 퇴근으로 계산돼요.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)

                        if let manualError {
                            Text(manualError)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appWarning)
                        }

                        Button(action: {
                            Task { await addManualWork() }
                        }) {
                            Text(isSavingManual ? "추가 중..." : "근무 추가")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isSavingManual)
                        .opacity(isSavingManual ? 0.6 : 1.0)
                    }
                    .appCard()
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            } else {
                Text("사장님과 연동된 근무는 직접 추가할 수 없어요.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                    .appCard()
            }
        }
    }

    private var fixedScheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "고정 스케줄")

            VStack(alignment: .leading, spacing: 10) {
                if fixedSchedules.isEmpty {
                    Text("아직 등록된 고정 스케줄이 없어요.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(sortedFixedSchedules) { schedule in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(weekdayLabel(schedule.weekday))요일")
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.appTextPrimary)
                                    Text("\(formatHourMinute(schedule.startHour, schedule.startMinute)) - \(formatHourMinute(schedule.endHour, schedule.endMinute))")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                }
                                Spacer()
                                Button("적용") {
                                    applyFixedScheduleToManualInput(schedule)
                                }
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.appAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color.appAccent.opacity(0.1))
                                .cornerRadius(8)

                                Button(role: .destructive) {
                                    removeFixedSchedule(schedule)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.appWarning)
                                        .padding(6)
                                }
                            }
                            .padding(10)
                            .background(Color.appSurface)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                        }
                    }
                }

                Button(isShowingFixedScheduleInput ? "입력 닫기" : "추가하기") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isShowingFixedScheduleInput.toggle()
                        if !isShowingFixedScheduleInput {
                            fixedScheduleError = nil
                        }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .appCard()

            if isShowingFixedScheduleInput {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("요일", selection: $fixedWeekday) {
                        Text("일").tag(0)
                        Text("월").tag(1)
                        Text("화").tag(2)
                        Text("수").tag(3)
                        Text("목").tag(4)
                        Text("금").tag(5)
                        Text("토").tag(6)
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("출근 시간")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                            timeInputRow(hour: $fixedStartHourInput, minute: $fixedStartMinuteInput)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("퇴근 시간")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                            timeInputRow(hour: $fixedEndHourInput, minute: $fixedEndMinuteInput)
                        }
                    }

                    if let fixedScheduleError {
                        Text(fixedScheduleError)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.appWarning)
                    }

                    Button("등록하기") {
                        addFixedSchedule()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .appCard()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var refundEstimateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "환급금 계산")
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("연간 환산 급여")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text(formatWon(refundEstimate.annualGross))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                }
                HStack {
                    Text("원천징수 예상")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text(formatWon(refundEstimate.annualWithholding))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                }
                HStack {
                    Text("연말정산 예상세액")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    Spacer()
                    Text(formatWon(refundEstimate.estimatedSettlementTax))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                }
                HStack {
                    Text("예상 환급금")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                    Spacer()
                    Text(formatWon(refundEstimate.expectedRefund))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.appAccent)
                }
                Text(refundEstimate.note)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
            }
            .appCard()
        }
    }

}

private extension WorkerCheckInView {
    var displayMinutes: Int {
        isCheckedIn ? store.todayMinutes + liveMinutes : store.todayMinutes
    }

    var displayPay: Double {
        store.todayPay
    }

    func updateLiveMinutes() {
        guard isCheckedIn, let checkIn = currentCheckInAt else { return }
        let minutes = floor(Date().timeIntervalSince(checkIn) / 60.0)
        liveMinutes = max(0, Int(minutes))
    }

    func persistLocalPayrollSettings() {
        PayrollLocalSettingsStore.save(
            workerId: store.workerId,
            settings: PayrollLocalSettings(
                applyWeeklyAllowance: applyWeeklyAllowance,
                deductionType: deductionType,
                applyNightAllowance: applyNightAllowance,
                payday: payday
            )
        )
        NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
    }

    func monthNetPayText() -> String {
        formatWon(monthNetPay())
    }

    func nextPaydayDateText() -> String {
        let date = PayrollPayday.nextPaydayDate(payday: payday)
        let formatter = AppTime.displayFormatter("M월 d일")
        return formatter.string(from: date)
    }

    var refundEstimate: PayrollRefundEstimate {
        PayrollCalculator.estimateAnnualRefund(
            monthlyTaxablePay: monthTaxablePayForEstimate(),
            deductionType: deductionType
        )
    }

    func monthNetPay() -> Double {
        let taxable = monthTaxablePayForEstimate()
        let breakdown = PayrollCalculator.deductionBreakdown(gross: taxable, type: deductionType)
        return max(0, taxable - breakdown.totalDeduction)
    }

    func monthTaxablePayForEstimate() -> Double {
        // If monthly logs are not loaded yet, use the list-computed gross as fallback.
        if isLoadingMonthLogsForNet || monthLogsForNet.isEmpty {
            return max(0, store.monthPay)
        }

        let counted = approvedMonthLogsForNet()
        let wage = store.hourlyWage

        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso

        let gross = counted.reduce(0.0) { partial, log in
            let start = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
            let end = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
            return partial + PayrollCalculator.grossPay(
                checkIn: start,
                checkOut: end,
                appliedHourlyWage: log.applied_hourly_wage,
                appliedNightAllowance: log.applied_night_allowance,
                fallbackHourlyWage: wage,
                fallbackNightAllowance: applyNightAllowance
            )
        }
        let weeklyAllowance = applyWeeklyAllowance
            ? PayrollCalculator.estimateWeeklyAllowancePay(checkInOut: counted.map { ($0.check_in_at, $0.check_out_at) }, wage: wage)
            : 0
        return max(0, gross + weeklyAllowance)
    }

    func approvedMonthLogsForNet() -> [WorkLogRow] {
        monthLogsForNet.filter { log in
            let hasCheckout = !(log.check_out_at?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            return normalizedStatus(log.status) == "approved" && hasCheckout
        }
    }



    var sortedFixedSchedules: [WorkerFixedSchedule] {
        fixedSchedules.sorted { lhs, rhs in
            if lhs.weekday == rhs.weekday {
                if lhs.startHour == rhs.startHour {
                    return lhs.startMinute < rhs.startMinute
                }
                return lhs.startHour < rhs.startHour
            }
            return lhs.weekday < rhs.weekday
        }
    }

    func weekdayLabel(_ weekday: Int) -> String {
        switch weekday {
        case 0: return "일"
        case 1: return "월"
        case 2: return "화"
        case 3: return "수"
        case 4: return "목"
        case 5: return "금"
        case 6: return "토"
        default: return "-"
        }
    }

    func formatHourMinute(_ hour: Int, _ minute: Int) -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    func timeInputRow(hour: Binding<String>, minute: Binding<String>) -> some View {
        HStack(spacing: 8) {
            TextField("시", text: hour)
                .keyboardType(.numberPad)
                .foregroundColor(.appTextPrimary)
                .multilineTextAlignment(.center)
                .padding(10)
                .background(Color.appSurface)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.appLine, lineWidth: 1)
                )
            Text(":")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.appTextSecondary)
            TextField("분", text: minute)
                .keyboardType(.numberPad)
                .foregroundColor(.appTextPrimary)
                .multilineTextAlignment(.center)
                .padding(10)
                .background(Color.appSurface)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.appLine, lineWidth: 1)
                )
        }
    }

    func parseHourMinute(hour: String, minute: String) -> (hour: Int, minute: Int)? {
        guard let h = Int(hour.filter { $0.isNumber }),
              let m = Int(minute.filter { $0.isNumber }),
              (0...23).contains(h),
              (0...59).contains(m) else {
            return nil
        }
        return (h, m)
    }

    func loadFixedSchedules() {
        fixedSchedules = WorkerFixedScheduleStore.load(workerId: store.workerId)
    }

    func persistFixedSchedules() {
        WorkerFixedScheduleStore.save(workerId: store.workerId, schedules: fixedSchedules)
    }

    func addFixedSchedule() {
        fixedScheduleError = nil

        guard let start = parseHourMinute(hour: fixedStartHourInput, minute: fixedStartMinuteInput),
              let end = parseHourMinute(hour: fixedEndHourInput, minute: fixedEndMinuteInput) else {
            fixedScheduleError = "고정 스케줄 시간을 올바르게 입력해주세요."
            return
        }

        guard start.hour != end.hour || start.minute != end.minute else {
            fixedScheduleError = "출근/퇴근 시간이 같아요."
            return
        }

        let candidate = WorkerFixedSchedule(
            id: UUID(),
            weekday: fixedWeekday,
            startHour: start.hour,
            startMinute: start.minute,
            endHour: end.hour,
            endMinute: end.minute
        )

        let duplicated = fixedSchedules.contains {
            $0.weekday == candidate.weekday &&
            $0.startHour == candidate.startHour &&
            $0.startMinute == candidate.startMinute &&
            $0.endHour == candidate.endHour &&
            $0.endMinute == candidate.endMinute
        }
        if duplicated {
            fixedScheduleError = "같은 고정 스케줄이 이미 있어요."
            return
        }

        fixedSchedules.append(candidate)
        persistFixedSchedules()
        fixedStartHourInput = ""
        fixedStartMinuteInput = ""
        fixedEndHourInput = ""
        fixedEndMinuteInput = ""
        fixedScheduleError = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowingFixedScheduleInput = false
        }
    }

    func removeFixedSchedule(_ schedule: WorkerFixedSchedule) {
        fixedSchedules.removeAll { $0.id == schedule.id }
        persistFixedSchedules()
    }

    func applyFixedScheduleToManualInput(_ schedule: WorkerFixedSchedule) {
        startHourInput = "\(schedule.startHour)"
        startMinuteInput = "\(schedule.startMinute)"
        endHourInput = "\(schedule.endHour)"
        endMinuteInput = "\(schedule.endMinute)"
        withAnimation(.easeInOut(duration: 0.2)) {
            isShowingManualAddInput = true
        }
    }

    func isOvernightSchedule(_ schedule: WorkerFixedSchedule) -> Bool {
        if schedule.endHour < schedule.startHour {
            return true
        }
        if schedule.endHour == schedule.startHour && schedule.endMinute < schedule.startMinute {
            return true
        }
        return false
    }

    func fixedScheduleDateRange(_ schedule: WorkerFixedSchedule, dayStart: Date) -> (start: Date, end: Date)? {
        let calendar = AppTime.calendar
        guard let start = calendar.date(bySettingHour: schedule.startHour, minute: schedule.startMinute, second: 0, of: dayStart),
              let sameDayEnd = calendar.date(bySettingHour: schedule.endHour, minute: schedule.endMinute, second: 0, of: dayStart) else {
            return nil
        }
        let end: Date
        if sameDayEnd < start {
            end = calendar.date(byAdding: .day, value: 1, to: sameDayEnd) ?? sameDayEnd
        } else {
            end = sameDayEnd
        }
        return (start, end)
    }

    @MainActor
    func autoAddCompletedFixedSchedulesIfNeeded() async {
        #if canImport(Supabase)
        guard store.isPersonal else { return }
        guard !isCheckedIn else { return }
        guard !isAutoApplyingFixedSchedule else { return }
        guard !fixedSchedules.isEmpty else { return }

        let calendar = AppTime.calendar
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let todayWeekday = (calendar.component(.weekday, from: now) + 6) % 7
        let yesterdayWeekday = (todayWeekday + 6) % 7
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

        var dueRanges: [(start: Date, end: Date)] = []

        for schedule in fixedSchedules {
            if schedule.weekday == todayWeekday,
               let range = fixedScheduleDateRange(schedule, dayStart: todayStart),
               range.end <= now {
                dueRanges.append(range)
            }
            if schedule.weekday == yesterdayWeekday,
               isOvernightSchedule(schedule),
               let range = fixedScheduleDateRange(schedule, dayStart: yesterdayStart),
               range.end <= now {
                dueRanges.append(range)
            }
        }

        guard !dueRanges.isEmpty else { return }
        let dueKey = dueRanges
            .sorted(by: { $0.start < $1.start })
            .map { "\($0.start.timeIntervalSince1970)-\($0.end.timeIntervalSince1970)" }
            .joined(separator: "|")
        if lastAutoFixedScheduleCheckKey == dueKey,
           let lastAutoFixedScheduleCheckedAt,
           now.timeIntervalSince(lastAutoFixedScheduleCheckedAt) < autoFixedScheduleCheckThrottle {
            return
        }

        isAutoApplyingFixedSchedule = true
        defer { isAutoApplyingFixedSchedule = false }

        do {
            let iso = AppTime.iso
            let existing: [WorkLogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at,check_out_at,status")
                .eq("store_id", value: store.id.uuidString)
                .eq("worker_id", value: store.workerId.uuidString)
                .gte("check_in_at", value: iso.string(from: yesterdayStart))
                .lt("check_in_at", value: iso.string(from: tomorrowStart))
                .execute()
                .value

            let parser = AppTime.isoWithFractionalSeconds
            let fallback = AppTime.iso

            func hasMatchingLog(for range: (start: Date, end: Date)) -> Bool {
                existing.contains { log in
                    let start = parser.date(from: log.check_in_at) ?? fallback.date(from: log.check_in_at)
                    let end = log.check_out_at.flatMap { parser.date(from: $0) ?? fallback.date(from: $0) }
                    guard let start, let end else { return false }
                    let startDiff = abs(start.timeIntervalSince(range.start))
                    let endDiff = abs(end.timeIntervalSince(range.end))
                    return startDiff < 60 && endDiff < 60
                }
            }

            struct InsertPayload: Encodable {
                let store_id: UUID
                let worker_id: UUID
                let check_in_at: String
                let check_out_at: String
                let status: String
                let approved_by: UUID?
                let approved_at: String?
            }

            let approverId = try await SupabaseManager.shared.currentUserId()
            var insertedCount = 0

            for range in dueRanges.sorted(by: { $0.start < $1.start }) {
                if hasMatchingLog(for: range) {
                    continue
                }
                let payload = InsertPayload(
                    store_id: store.id,
                    worker_id: store.workerId,
                    check_in_at: iso.string(from: range.start),
                    check_out_at: iso.string(from: range.end),
                    status: "approved",
                    approved_by: approverId,
                    approved_at: iso.string(from: range.end)
                )
                _ = try await SupabaseManager.shared
                    .client
                    .from("work_logs")
                    .insert(payload)
                    .execute()
                insertedCount += 1
            }

            if insertedCount > 0 {
                await loadMonthLogsForNet()
                NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
            }
            lastAutoFixedScheduleCheckKey = dueKey
            lastAutoFixedScheduleCheckedAt = now
        } catch {
            if AppErrorMessage.isCancellation(error) {
                return
            }
            #if DEBUG
            print("DEBUG: auto fixed schedule apply failed: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    @MainActor
    func loadCurrentLog() async {
        #if canImport(Supabase)
        do {
            actionError = nil
            struct LogRow: Decodable { let id: UUID; let check_in_at: String }
            let rows: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at")
                .eq("store_id", value: store.id.uuidString)
                .eq("worker_id", value: store.workerId.uuidString)
                .is("check_out_at", value: nil)
                .order("check_in_at", ascending: false)
                .limit(5)
                .execute()
                .value
            if rows.count > 1 {
                actionError = "열린 근무 기록이 여러 개 감지됐어요. 최신 기록 기준으로 표시합니다."
            }
            currentLogId = rows.first?.id
            isCheckedIn = currentLogId != nil
            if let row = rows.first {
                let parser = AppTime.isoWithFractionalSeconds
                let checkInDate = parser.date(from: row.check_in_at) ?? AppTime.iso.date(from: row.check_in_at) ?? Date()
                currentCheckInAt = checkInDate
                updateLiveMinutes()
                await WorkerLiveActivityManager.shared.startOrUpdate(
                    storeId: store.id,
                    storeName: store.name,
                    checkInAt: checkInDate
                )
            } else {
                currentCheckInAt = nil
                liveMinutes = 0
                await WorkerLiveActivityManager.shared.end(storeId: store.id)
            }
        } catch {
            actionError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    func toggleCheckIn() async {
        #if canImport(Supabase)
        isLoadingAction = true
        actionError = nil
        defer { isLoadingAction = false }
        do {
            if let logId = currentLogId {
                let iso = AppTime.iso
                let now = Date()
                if shouldAutoApproveLogs {
                    struct UpdatePayload: Encodable {
                        let check_out_at: String
                        let status: String
                        let approved_by: UUID
                        let approved_at: String
                    }
                    let approverId = try await SupabaseManager.shared.currentUserId()
                    let payload = UpdatePayload(
                        check_out_at: iso.string(from: now),
                        status: "approved",
                        approved_by: approverId,
                        approved_at: iso.string(from: now)
                    )
                    _ = try await SupabaseManager.shared
                        .client
                        .from("work_logs")
                        .update(payload)
                        .eq("id", value: logId.uuidString)
                        .execute()
                } else {
                    struct UpdatePayload: Encodable { let check_out_at: String }
                    let payload = UpdatePayload(check_out_at: iso.string(from: now))
                    _ = try await SupabaseManager.shared
                        .client
                        .from("work_logs")
                        .update(payload)
                        .eq("id", value: logId.uuidString)
                        .execute()
                }
                currentLogId = nil
                isCheckedIn = false
                currentCheckInAt = nil
                Haptics.success()
                NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
                await WorkerLiveActivityManager.shared.end(storeId: store.id)
            } else {
                // Guard against duplicate "open" logs from stale UI state or multi-device retries.
                struct OpenLogRow: Decodable { let id: UUID; let check_in_at: String }
                let openRows: [OpenLogRow] = try await SupabaseManager.shared
                    .client
                    .from("work_logs")
                    .select("id,check_in_at")
                    .eq("store_id", value: store.id.uuidString)
                    .eq("worker_id", value: store.workerId.uuidString)
                    .is("check_out_at", value: nil)
                    .order("check_in_at", ascending: false)
                    .limit(1)
                    .execute()
                    .value
                if let existing = openRows.first {
                    let parser = AppTime.isoWithFractionalSeconds
                    currentLogId = existing.id
                    isCheckedIn = true
                    let checkInDate = parser.date(from: existing.check_in_at) ?? AppTime.iso.date(from: existing.check_in_at) ?? Date()
                    currentCheckInAt = checkInDate
                    updateLiveMinutes()
                    await WorkerLiveActivityManager.shared.startOrUpdate(
                        storeId: store.id,
                        storeName: store.name,
                        checkInAt: checkInDate
                    )
                    Haptics.warning()
                    actionError = "이미 출근 상태예요. 현재 근무 기록으로 동기화했습니다."
                    return
                }

                let iso = AppTime.iso
                let now = Date()
                struct InsertedRow: Decodable { let id: UUID }
                let row: InsertedRow
                if shouldAutoApproveLogs {
                    struct InsertPayload: Encodable {
                        let store_id: UUID
                        let worker_id: UUID
                        let check_in_at: String
                        let status: String
                        let approved_by: UUID
                        let approved_at: String
                    }
                    let approverId = try await SupabaseManager.shared.currentUserId()
                    let payload = InsertPayload(
                        store_id: store.id,
                        worker_id: store.workerId,
                        check_in_at: iso.string(from: now),
                        status: "approved",
                        approved_by: approverId,
                        approved_at: iso.string(from: now)
                    )
                    row = try await SupabaseManager.shared
                        .client
                        .from("work_logs")
                        .insert(payload)
                        .select("id")
                        .single()
                        .execute()
                        .value
                } else {
                    struct InsertPayload: Encodable {
                        let store_id: UUID
                        let worker_id: UUID
                        let check_in_at: String
                    }
                    let payload = InsertPayload(
                        store_id: store.id,
                        worker_id: store.workerId,
                        check_in_at: iso.string(from: now)
                    )
                    row = try await SupabaseManager.shared
                        .client
                        .from("work_logs")
                        .insert(payload)
                        .select("id")
                        .single()
                        .execute()
                        .value
                }
                currentLogId = row.id
                isCheckedIn = true
                currentCheckInAt = now
                updateLiveMinutes()
                Haptics.success()
                NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
                await WorkerLiveActivityManager.shared.startOrUpdate(
                    storeId: store.id,
                    storeName: store.name,
                    checkInAt: now
                )
            }
        } catch {
            Haptics.error()
            actionError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    struct WorkLogRow: Decodable, Identifiable {
        let id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
        let applied_hourly_wage: Double?
        let applied_night_allowance: Bool?
    }

    @MainActor
    func loadMonthLogsForNet() async {
        #if canImport(Supabase)
        isLoadingMonthLogsForNet = true
        defer { isLoadingMonthLogsForNet = false }
        do {
            let calendar = AppTime.calendar
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
            let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? Date()
            let iso = AppTime.iso
            let rows: [WorkLogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at,check_out_at,status,applied_hourly_wage,applied_night_allowance")
                .eq("store_id", value: store.id.uuidString)
                .eq("worker_id", value: store.workerId.uuidString)
                .gte("check_in_at", value: iso.string(from: monthStart))
                .lt("check_in_at", value: iso.string(from: monthEnd))
                .limit(500)
                .execute()
                .value
            monthLogsForNet = rows
        } catch {
            // Ignore: we'll keep showing list-computed net.
        }
        #endif
    }

    @MainActor
    func addManualWork() async {
        #if canImport(Supabase)
        isSavingManual = true
        manualError = nil
        defer { isSavingManual = false }

        let calendar = AppTime.calendar
        let today = Date()
        let dayStart = calendar.startOfDay(for: today)
        let startHour = Int(startHourInput.filter { $0.isNumber }) ?? -1
        let startMinute = Int(startMinuteInput.filter { $0.isNumber }) ?? -1
        let endHour = Int(endHourInput.filter { $0.isNumber }) ?? -1
        let endMinute = Int(endMinuteInput.filter { $0.isNumber }) ?? -1

        guard (0...23).contains(startHour), (0...59).contains(startMinute),
              (0...23).contains(endHour), (0...59).contains(endMinute) else {
            manualError = "출근/퇴근 시간을 올바르게 입력해주세요. (예: 09시 30분)"
            return
        }

        guard let checkIn = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: dayStart),
              let sameDayEnd = calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: dayStart) else {
            manualError = "시간 계산에 실패했어요. 다시 입력해주세요."
            return
        }

        guard checkIn != sameDayEnd else {
            manualError = "출근/퇴근 시간이 같아요. 시간을 다시 확인해주세요."
            return
        }

        let endDate: Date
        if sameDayEnd < checkIn {
            endDate = calendar.date(byAdding: .day, value: 1, to: sameDayEnd) ?? sameDayEnd
        } else {
            endDate = sameDayEnd
        }

        struct InsertPayload: Encodable {
            let store_id: UUID
            let worker_id: UUID
            let check_in_at: String
            let check_out_at: String
            let status: String
            let approved_by: UUID?
            let approved_at: String?
        }
        let iso = AppTime.iso
        do {
            let approverId = try await SupabaseManager.shared.currentUserId()
            let payload = InsertPayload(
                store_id: store.id,
                worker_id: store.workerId,
                check_in_at: iso.string(from: checkIn),
                check_out_at: iso.string(from: endDate),
                status: "approved",
                approved_by: approverId,
                approved_at: iso.string(from: endDate)
            )
            _ = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .insert(payload)
                .execute()
            startHourInput = ""
            startMinuteInput = ""
            endHourInput = ""
            endMinuteInput = ""
            manualError = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowingManualAddInput = false
            }
            await loadMonthLogsForNet()
            NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
        } catch {
            manualError = AppErrorMessage.userMessage(error)
        }
        #endif
    }




    func formatDate(_ isoString: String) -> String {
        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso
        let date = parser.date(from: isoString) ?? iso.date(from: isoString) ?? Date()
        let formatter = AppTime.displayFormatter("M월 d일")
        return formatter.string(from: date)
    }

    func formatTimeRange(_ log: WorkLogRow) -> String {
        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso
        let start = parser.date(from: log.check_in_at) ?? iso.date(from: log.check_in_at) ?? Date()
        let end = log.check_out_at.flatMap { parser.date(from: $0) ?? iso.date(from: $0) }
        let formatter = AppTime.displayFormatter("HH:mm")
        let startText = formatter.string(from: start)
        let endText = end.map { formatter.string(from: $0) } ?? "--:--"
        return "\(startText) - \(endText)"
    }

    func calcMinutes(checkIn: String, checkOut: String?) -> Int {
        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso
        let start = parser.date(from: checkIn) ?? iso.date(from: checkIn) ?? Date()
        let end = checkOut.flatMap { parser.date(from: $0) ?? iso.date(from: $0) } ?? Date()
        let minutes = floor(end.timeIntervalSince(start) / 60.0)
        return max(0, Int(minutes))
    }

    func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

private struct WorkerStoreHistoryView: View {
    struct LogRow: Decodable, Identifiable {
        let id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
        let applied_hourly_wage: Double?
        let applied_night_allowance: Bool?
    }

    let storeName: String
    let storeId: UUID
    let workerId: UUID
    let hourlyWage: Double

    @State private var logs: [LogRow] = []
    @State private var isLoading = false
    @State private var isUserRefreshing = false
    @State private var loadError: String?
    @State private var applyNightAllowance = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .appCard()
                } else if logs.isEmpty {
                    Text("근무 내역이 없어요.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                        .appCard()
                } else {
                    VStack(spacing: 10) {
                        ForEach(logs) { log in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(formatDate(log.check_in_at))
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundColor(.appTextPrimary)
                                    Spacer()
                                    StatusPill(text: statusLabel(log.status), color: statusColor(log.status))
                                }
                                Text(formatTimeRange(log))
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundColor(.appTextSecondary)
                                HStack {
                                    Text(formatHours(totalMinutes(log)))
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.appTextSecondary)
                                    Spacer()
                                    Text(formatWon(totalPay(log)))
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundColor(.appTextPrimary)
                                }
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
        .navigationTitle("\(storeName) 내역")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadLocalSettings()
            await loadLogs()
        }
        .refreshable {
            await refreshFromUser()
        }
        .refreshStatusOverlay(isVisible: isUserRefreshing)
    }

    private func loadLocalSettings() {
        if let local = PayrollLocalSettingsStore.load(workerId: workerId) {
            applyNightAllowance = local.applyNightAllowance
        } else {
            applyNightAllowance = false
        }
    }

    @MainActor
    private func refreshFromUser() async {
        isUserRefreshing = true
        defer { isUserRefreshing = false }
        await loadLogs()
    }

    @MainActor
    private func loadLogs() async {
        #if canImport(Supabase)
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [LogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at,check_out_at,status,applied_hourly_wage,applied_night_allowance")
                .eq("store_id", value: storeId.uuidString)
                .eq("worker_id", value: workerId.uuidString)
                .order("check_in_at", ascending: false)
                .limit(500)
                .execute()
                .value
            logs = rows
            loadError = nil
        } catch {
            loadError = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    private func parseDate(_ isoString: String) -> Date {
        let parser = AppTime.isoWithFractionalSeconds
        let iso = AppTime.iso
        return parser.date(from: isoString) ?? iso.date(from: isoString) ?? Date()
    }

    private func totalMinutes(_ log: LogRow) -> Int {
        let start = parseDate(log.check_in_at)
        let end = log.check_out_at.map(parseDate(_:))
        return PayrollCalculator.calcMinutes(checkIn: start, checkOut: end)
    }

    private func totalPay(_ log: LogRow) -> Double {
        let start = parseDate(log.check_in_at)
        let end = log.check_out_at.map(parseDate(_:))
        return PayrollCalculator.grossPay(
            checkIn: start,
            checkOut: end,
            appliedHourlyWage: log.applied_hourly_wage,
            appliedNightAllowance: log.applied_night_allowance,
            fallbackHourlyWage: hourlyWage,
            fallbackNightAllowance: applyNightAllowance
        )
    }




    private func formatDate(_ isoString: String) -> String {
        let date = parseDate(isoString)
        let formatter = AppTime.displayFormatter("M월 d일")
        return formatter.string(from: date)
    }

    private func formatTimeRange(_ log: LogRow) -> String {
        let start = parseDate(log.check_in_at)
        let end = log.check_out_at.map(parseDate(_:))
        let formatter = AppTime.displayFormatter("HH:mm")
        let startText = formatter.string(from: start)
        let endText = end.map { formatter.string(from: $0) } ?? "--:--"
        return "\(startText) - \(endText)"
    }


}

private struct WorkerFixedSchedule: Identifiable, Codable {
    let id: UUID
    let weekday: Int
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
}

private enum WorkerFixedScheduleStore {
    private static func key(workerId: UUID) -> String {
        "worker_fixed_schedule_v1_\(workerId.uuidString)"
    }

    static func load(workerId: UUID) -> [WorkerFixedSchedule] {
        guard let data = UserDefaults.standard.data(forKey: key(workerId: workerId)) else { return [] }
        return (try? JSONDecoder().decode([WorkerFixedSchedule].self, from: data)) ?? []
    }

    static func save(workerId: UUID, schedules: [WorkerFixedSchedule]) {
        guard let data = try? JSONEncoder().encode(schedules) else { return }
        UserDefaults.standard.set(data, forKey: key(workerId: workerId))
    }
}
