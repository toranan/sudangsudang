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
    @State private var isConfirmingEarlyCheckOut = false
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
            VStack(alignment: .leading, spacing: 14) {
                header
                checkInCard
                monthPayCard
                statTiles
                workToolsSection
                settingsSection
                historyEntryCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            // 탭바 안쪽으로 밀려 들어온 화면이라 탭바 높이만큼 더 내려가게 둔다.
            .padding(.bottom, appTabBarReservedHeight + 24)
        }
        .appRefreshable {
            await loadCurrentLog()
            await loadMonthLogsForNet()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.isPersonal ? "개인 매장 출퇴근" : "출퇴근")
                    .font(.app(.callout, .medium))
                    .foregroundColor(.appTextSecondary)
                Text(store.name)
                    .font(.system(size: 26, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundColor(.appTextPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 4)
    }

    // 상태, 큰 근무 시간, 오늘 번 돈, 출근/퇴근 버튼.
    private var checkInCard: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isCheckedIn ? Color.appPositive : Color.appCaution)
                    .frame(width: 7, height: 7)
                Text(checkInStatusText)
                    .font(.app(.caption, .bold))
                    .foregroundColor(isCheckedIn ? .appAccent : .appTextSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isCheckedIn ? Color.appAccentSoft : Color.appFill, in: Capsule())

            Text(timerText(displayMinutes))
                .font(.system(size: 44, weight: .heavy))
                .tracking(-1.5)
                .monospacedDigit()
                .foregroundColor(.appTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .padding(.top, 4)

            HStack(spacing: 0) {
                Text("오늘 ")
                Text(formatWon(displayPay))
                    .fontWeight(.bold)
                    .foregroundColor(.appTextPrimary)
                Text(" 벌었어요")
            }
            .font(.app(.callout))
            .foregroundColor(.appTextSecondary)

            Button(action: {
                // 출근하자마자 실수로 퇴근을 누르면 0분 기록이 승인 요청으로 가므로 한 번 더 묻는다.
                if isCheckedIn, let start = currentCheckInAt, Date().timeIntervalSince(start) < 60 {
                    isConfirmingEarlyCheckOut = true
                } else {
                    Task { await toggleCheckIn() }
                }
            }) {
                HStack(spacing: 8) {
                    if isLoadingAction {
                        ProgressView()
                            .tint(.appOnInk)
                        Text("처리 중...")
                    } else {
                        Text(isCheckedIn ? "퇴근하기" : "출근하기")
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isLoadingAction)
            .padding(.top, 14)
            .confirmationDialog("0분 근무예요. 저장할까요?", isPresented: $isConfirmingEarlyCheckOut, titleVisibility: .visible) {
                Button("저장") { Task { await toggleCheckIn() } }
                Button("취소", role: .cancel) {}
            } message: {
                Text("취소하면 출근 상태가 유지돼요.")
            }

            Text(isCheckedIn ? "\(store.name)에서 근무 중" : "\(store.name) 출근 대기")
                .font(.system(size: 12))
                .foregroundColor(.appTextSecondary)
                .padding(.top, 2)

            if let actionError {
                Text(actionError)
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appWarning)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private var checkInStatusText: String {
        guard isCheckedIn else { return "출근 전" }
        guard let currentCheckInAt else { return "근무 중" }
        return "\(AppTime.displayFormatter("HH:mm").string(from: currentCheckInAt))부터 근무 중"
    }

    private var monthPayCard: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("이번 달 예상 급여")
                    .font(.app(.callout, .medium))
                    .foregroundColor(.white.opacity(0.8))
                Text(store.monthPayText)
                    .font(.system(size: 23, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("세후 예상 \(monthNetPayText())")
                    .font(.app(.caption, .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                Text("월급날까지")
                    .font(.app(.caption, .medium))
                    .foregroundColor(.white.opacity(0.8))
                Text(paydayDDayText())
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(.white)
                Text(nextPaydayDateText())
                    .font(.app(.caption, .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(Color.appAccent)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var statTiles: some View {
        HStack(spacing: 10) {
            statTile(title: "이번 달", value: store.monthWorkedText)
            statTile(
                title: "주휴수당",
                value: applyWeeklyAllowance ? "적용" : "미적용",
                valueColor: applyWeeklyAllowance ? .appAccent : .appTextSecondary
            )
            statTile(title: "시급", value: formatWon(store.hourlyWage))
        }
    }

    private func statTile(title: String, value: String, valueColor: Color = .appTextPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.appTextSecondary)
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 19, weight: .heavy))
            .foregroundColor(.appTextPrimary)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(Color.appLine)
            .frame(height: 1)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.app(.callout))
                .foregroundColor(.appTextSecondary)
            Spacer()
            Text(value)
                .font(.app(.callout, .semibold))
                .foregroundColor(.appTextPrimary)
        }
        .padding(.vertical, 13)
    }

    // 캡슐 안에서 하나를 고르는 칩 묶음 (세그먼트 대신).
    private func chipGroup<Value: Hashable>(
        _ options: [(value: Value, title: String)],
        selection: Value,
        onSelect: @escaping (Value) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button(action: { onSelect(option.value) }) {
                    Text(option.title)
                        .font(.app(.caption, .semibold))
                        .foregroundColor(isSelected ? .appOnInk : .appTextSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isSelected ? Color.appInk : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.appFill, in: Capsule())
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("세부 설정")
            if store.isPersonal {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle(isOn: $applyWeeklyAllowance) {
                        Text("주휴수당 적용")
                            .font(.app(.callout, .medium))
                            .foregroundColor(.appTextPrimary)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                    .padding(.vertical, 10)
                    .onChange(of: applyWeeklyAllowance) { _ in
                        persistLocalPayrollSettings()
                    }

                    cardDivider

                    Toggle(isOn: $applyNightAllowance) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("야간수당 적용")
                                .font(.app(.callout, .medium))
                                .foregroundColor(.appTextPrimary)
                            Text("22:00~06:00 +50%")
                                .font(.app(.caption))
                                .foregroundColor(.appTextSecondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .appAccent))
                    .padding(.vertical, 10)
                    .onChange(of: applyNightAllowance) { _ in
                        persistLocalPayrollSettings()
                    }

                    cardDivider

                    VStack(alignment: .leading, spacing: 8) {
                        Text("공제 방식")
                            .font(.app(.callout, .medium))
                            .foregroundColor(.appTextPrimary)
                        chipGroup(
                            PayrollDeductionType.allCases.map { (value: $0, title: $0.title) },
                            selection: deductionType
                        ) { option in
                            deductionType = option
                            persistLocalPayrollSettings()
                        }
                    }
                    .padding(.vertical, 13)

                    cardDivider

                    HStack {
                        Text("월급일")
                            .font(.app(.callout, .medium))
                            .foregroundColor(.appTextPrimary)
                        Spacer()
                        Picker("월급일", selection: $payday) {
                            ForEach(1...31, id: \.self) { day in
                                Text("매월 \(day)일").tag(day)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.appTextPrimary)
                        .onChange(of: payday) { _ in
                            persistLocalPayrollSettings()
                        }
                    }
                    .padding(.vertical, 6)

                    cardDivider
                    infoRow("정산기간", "매월 1일 ~ 말일")
                    cardDivider
                    infoRow("다음 월급일", nextPaydayDateText())
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))

                Text("개인 매장의 세부 설정은 이 기기에서만 저장돼요.")
                    .font(.app(.caption))
                    .foregroundColor(.appTextSecondary)
                    .padding(.horizontal, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    infoRow("공제 방식", store.deductionType.title)
                    cardDivider
                    infoRow("주휴수당", store.applyWeeklyAllowance ? "적용" : "미적용")
                    cardDivider
                    infoRow("야간수당", store.applyNightAllowance ? "적용" : "미적용")
                    cardDivider
                    infoRow("월급일", "매월 \(store.paydayText)")
                    cardDivider
                    infoRow("정산기간", "매월 1일 ~ 말일")
                    cardDivider
                    infoRow("다음 월급일", nextPaydayDateText())
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))

                Text("사장님이 설정한 기준이 적용돼요.")
                    .font(.app(.caption))
                    .foregroundColor(.appTextSecondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var historyEntryCard: some View {
        NavigationLink {
            WorkerStoreHistoryView(
                storeName: store.name,
                storeId: store.id,
                workerId: store.workerId,
                hourlyWage: store.hourlyWage
            )
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.appLavenderSoft)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "list.bullet")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.appLavender)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("근무 내역 보기")
                        .font(.app(.body, .bold))
                        .foregroundColor(.appTextPrimary)
                    Text("이 매장의 전체 근무 기록")
                        .font(.app(.caption))
                        .foregroundColor(.appTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.appTextSecondary)
            }
            .padding(16)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        }
        .buttonStyle(PressableRowStyle())
        .padding(.top, 8)
    }

    // 근무 직접 추가와 고정 스케줄 (개인 매장만).
    @ViewBuilder
    private var workToolsSection: some View {
        if allowManualAdd {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("근무 기록")
                HStack(spacing: 10) {
                    ActionTile(
                        title: isShowingManualAddInput ? "입력 닫기" : "근무 추가",
                        subtitle: "오늘 근무 직접 입력",
                        systemImage: isShowingManualAddInput ? "xmark" : "plus"
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingManualAddInput.toggle()
                            if !isShowingManualAddInput {
                                manualError = nil
                            }
                        }
                    }
                    if store.isPersonal {
                        ActionTile(
                            title: isShowingFixedScheduleInput ? "입력 닫기" : "고정 스케줄",
                            subtitle: fixedSchedules.isEmpty ? "요일별 반복 등록" : "\(fixedSchedules.count)개 등록됨",
                            systemImage: isShowingFixedScheduleInput ? "xmark" : "repeat",
                            tint: .appLavender,
                            fill: .appLavenderSoft
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isShowingFixedScheduleInput.toggle()
                                if !isShowingFixedScheduleInput {
                                    fixedScheduleError = nil
                                }
                            }
                        }
                    }
                }

                if isShowingManualAddInput {
                    manualAddInputCard
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if store.isPersonal {
                    if isShowingFixedScheduleInput {
                        fixedScheduleInputCard
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if !fixedSchedules.isEmpty {
                        fixedScheduleListCard
                    }
                }
            }
        } else {
            Text("사장님과 연동된 근무는 직접 추가할 수 없어요.")
                .font(.app(.caption))
                .foregroundColor(.appTextSecondary)
                .padding(.horizontal, 4)
        }
    }

    private var manualAddInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("오늘 근무 추가")
                .font(.app(.body, .bold))
                .foregroundColor(.appTextPrimary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("출근 시간")
                        .font(.app(.caption, .semibold))
                        .foregroundColor(.appTextSecondary)
                    timeInputRow(hour: $startHourInput, minute: $startMinuteInput)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("퇴근 시간")
                        .font(.app(.caption, .semibold))
                        .foregroundColor(.appTextSecondary)
                    timeInputRow(hour: $endHourInput, minute: $endMinuteInput)
                }
            }

            Text("종료가 출근보다 빠르면 다음날 퇴근으로 계산돼요.")
                .font(.app(.caption))
                .foregroundColor(.appTextSecondary)

            if let manualError {
                Text(manualError)
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appWarning)
            }

            Button(action: {
                Task { await addManualWork() }
            }) {
                Text(isSavingManual ? "추가 중..." : "근무 추가")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isSavingManual)
        }
        .appCard()
    }

    private var fixedScheduleInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("고정 스케줄 등록")
                .font(.app(.body, .bold))
                .foregroundColor(.appTextPrimary)

            chipGroup(
                (0...6).map { (value: $0, title: weekdayLabel($0)) },
                selection: fixedWeekday
            ) { day in
                fixedWeekday = day
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("출근 시간")
                        .font(.app(.caption, .semibold))
                        .foregroundColor(.appTextSecondary)
                    timeInputRow(hour: $fixedStartHourInput, minute: $fixedStartMinuteInput)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("퇴근 시간")
                        .font(.app(.caption, .semibold))
                        .foregroundColor(.appTextSecondary)
                    timeInputRow(hour: $fixedEndHourInput, minute: $fixedEndMinuteInput)
                }
            }

            if let fixedScheduleError {
                Text(fixedScheduleError)
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appWarning)
            }

            Button("등록하기") {
                addFixedSchedule()
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .appCard()
    }

    private var fixedScheduleListCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(sortedFixedSchedules.enumerated()), id: \.element.id) { index, schedule in
                if index > 0 {
                    cardDivider
                }
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.appLavenderSoft)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(weekdayLabel(schedule.weekday))
                                .font(.app(.callout, .bold))
                                .foregroundColor(.appLavender)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("매주 \(weekdayLabel(schedule.weekday))요일")
                            .font(.app(.callout, .bold))
                            .foregroundColor(.appTextPrimary)
                        Text("\(formatHourMinute(schedule.startHour, schedule.startMinute)) - \(formatHourMinute(schedule.endHour, schedule.endMinute))")
                            .font(.app(.caption))
                            .foregroundColor(.appTextSecondary)
                    }
                    Spacer()
                    Button("적용") {
                        applyFixedScheduleToManualInput(schedule)
                    }
                    .font(.app(.caption, .bold))
                    .foregroundColor(.appAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.appAccentSoft, in: Capsule())
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        removeFixedSchedule(schedule)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.appTextSecondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
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
        let settings = PayrollLocalSettings(
            applyWeeklyAllowance: applyWeeklyAllowance,
            deductionType: deductionType,
            applyNightAllowance: applyNightAllowance,
            payday: payday
        )
        // .task에서 저장값을 불러올 때도 onChange가 불리므로, 실제로 바뀐 경우에만 다른 화면을 갱신한다.
        guard PayrollLocalSettingsStore.load(workerId: store.workerId) != settings else { return }
        PayrollLocalSettingsStore.save(workerId: store.workerId, settings: settings)
        NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)
    }

    func monthNetPayText() -> String {
        formatWon(monthNetPay())
    }

    // 분 → "3:24" 형태의 큰 근무 시간 표기.
    func timerText(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    func paydayDDayText() -> String {
        let calendar = AppTime.calendar
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: PayrollPayday.nextPaydayDate(payday: payday))
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        return days <= 0 ? "D-Day" : "D-\(days)"
    }

    func nextPaydayDateText() -> String {
        let date = PayrollPayday.nextPaydayDate(payday: payday)
        let formatter = AppTime.displayFormatter("M월 d일")
        return formatter.string(from: date)
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
        let allowanceLogs = approvedAllowanceLogsForNet()
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
                fallbackNightAllowance: applyNightAllowance,
                appliedBreakPolicy: log.applied_break_policy,
                appliedBreakMinutes: log.applied_break_minutes
            )
        }
        // 개인 매장은 기기에 저장된 설정을 쓰므로 근무 기록의 주휴 설정은 보지 않는다.
        let weeklyAllowance = PayrollCalculator.estimateWeeklyAllowancePay(
            logs: allowanceLogs,
            fallbackWage: wage,
            fallbackApply: applyWeeklyAllowance,
            useSnapshot: !store.isPersonal,
            attributedToMonth: Date()
        )
        return max(0, gross + weeklyAllowance)
    }

    func approvedMonthLogsForNet() -> [WorkLogRow] {
        let calendar = AppTime.calendar
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? Date()
        return approvedAllowanceLogsForNet().filter { log in
            guard let checkIn = AppTime.parseISO(log.check_in_at) else { return false }
            return checkIn >= monthStart && checkIn < monthEnd
        }
    }

    func approvedAllowanceLogsForNet() -> [WorkLogRow] {
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
        HStack(spacing: 6) {
            TextField("시", text: hour)
                .keyboardType(.numberPad)
                .font(.app(.body, .semibold))
                .foregroundColor(.appTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .background(Color.appFill)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(":")
                .font(.app(.callout, .bold))
                .foregroundColor(.appTextSecondary)
            TextField("분", text: minute)
                .keyboardType(.numberPad)
                .font(.app(.body, .semibold))
                .foregroundColor(.appTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
                .background(Color.appFill)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    struct WorkLogRow: Decodable, Identifiable, WeeklyAllowanceLogFields {
        let id: UUID
        let check_in_at: String
        let check_out_at: String?
        let status: String?
        let applied_hourly_wage: Double?
        let applied_break_policy: String?
        let applied_break_minutes: Int?
        let applied_weekly_allowance: Bool?
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
            let allowanceLogRange = PayrollCalculator.weeklyAllowanceLogRange(forMonth: monthStart)
            let iso = AppTime.iso
            let rows: [WorkLogRow] = try await SupabaseManager.shared
                .client
                .from("work_logs")
                .select("id,check_in_at,check_out_at,status,applied_hourly_wage,applied_night_allowance,applied_break_policy,applied_break_minutes,applied_weekly_allowance")
                .eq("store_id", value: store.id.uuidString)
                .eq("worker_id", value: store.workerId.uuidString)
                .gte("check_in_at", value: iso.string(from: allowanceLogRange.start))
                .lt("check_in_at", value: iso.string(from: allowanceLogRange.end))
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
        let applied_break_policy: String?
        let applied_break_minutes: Int?
        let applied_weekly_allowance: Bool?
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
                if isLoading && logs.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .appCard()
                } else if logs.isEmpty {
                    Text("근무 내역이 없어요.")
                        .font(.app(.callout))
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
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(formatDate(log.check_in_at))
                                            .font(.app(.callout, .bold))
                                            .foregroundColor(.appTextPrimary)
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(statusColor(log.status))
                                                .frame(width: 6, height: 6)
                                            Text(statusLabel(log.status))
                                                .font(.app(.caption, .semibold))
                                                .foregroundColor(statusColor(log.status))
                                        }
                                    }
                                    Text(formatTimeRange(log))
                                        .font(.app(.caption))
                                        .foregroundColor(.appTextSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(formatWon(totalPay(log)))
                                        .font(.app(.callout, .bold))
                                        .foregroundColor(.appTextPrimary)
                                    Text(formatHours(totalMinutes(log)))
                                        .font(.app(.caption))
                                        .foregroundColor(.appTextSecondary)
                                }
                            }
                            .padding(.vertical, 13)
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
            .padding(.top, 8)
            .padding(.bottom, appTabBarReservedHeight + 24)
        }
        .appRefreshable {
            await refreshFromUser()
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("\(storeName) 내역")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadLocalSettings()
            await loadLogs()
        }
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
                .select("id,check_in_at,check_out_at,status,applied_hourly_wage,applied_night_allowance,applied_break_policy,applied_break_minutes,applied_weekly_allowance")
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
        return PayrollCalculator.calcPaidMinutes(
            checkIn: start,
            checkOut: end,
            appliedBreakPolicy: log.applied_break_policy,
            appliedBreakMinutes: log.applied_break_minutes
        )
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
            fallbackNightAllowance: applyNightAllowance,
            appliedBreakPolicy: log.applied_break_policy,
            appliedBreakMinutes: log.applied_break_minutes
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
