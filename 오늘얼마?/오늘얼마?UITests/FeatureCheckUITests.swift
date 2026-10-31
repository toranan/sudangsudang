import XCTest

// 기능별 나노 테스트(QA용). TEST_RUNNER_DEMO_ROLE=owner|worker, TEST_RUNNER_DEMO_EMAIL/PASSWORD,
// TEST_RUNNER_QA_DIR(덤프·스크린샷 저장 폴더)을 넘겨 실행한다. 환경변수가 없으면 건너뛴다.
final class FeatureCheckUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var app: XCUIApplication!
    private var testName: String { String(name.split(separator: " ").last?.dropLast() ?? "t") }

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(env["DEMO_EMAIL"] == nil, "데모 계정 환경변수가 없어서 건너뜀")
    }

    private func requireRole(_ role: String) throws {
        try XCTSkipIf(env["DEMO_ROLE"] != role, "역할이 달라 건너뜀")
    }

    @discardableResult
    private func launch() -> XCUIApplication {
        let a = XCUIApplication()
        a.launchEnvironment["DEMO_EMAIL"] = env["DEMO_EMAIL"]
        a.launchEnvironment["DEMO_PASSWORD"] = env["DEMO_PASSWORD"]
        a.launch()
        app = a
        // 홈의 탭바가 뜰 때까지 기다린다.
        _ = a.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "홈", "출퇴근")).firstMatch.waitForExistence(timeout: 20)
        pause(3)
        return a
    }

    private func pause(_ s: Double) { Thread.sleep(forTimeInterval: s) }

    private func snap(_ step: String) {
        guard let dir = env["QA_DIR"] else { return }
        let base = "\(dir)/\(testName)_\(step)"
        try? app.debugDescription.write(toFile: base + ".txt", atomically: true, encoding: .utf8)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: base + ".png"))
    }

    private func button(_ text: String, exact: Bool = false) -> XCUIElement {
        let p = exact ? NSPredicate(format: "label == %@", text) : NSPredicate(format: "label CONTAINS %@", text)
        return app.buttons.matching(p).firstMatch
    }

    @discardableResult
    private func tap(_ text: String, exact: Bool = false, wait: Double = 8) -> Bool {
        let el = button(text, exact: exact)
        guard el.waitForExistence(timeout: wait) else {
            print("QA: missing button \(text)")
            return false
        }
        if !el.isHittable {
            // 화면 밖이면 몇 번 스크롤해 본다.
            for _ in 0..<4 where !el.isHittable { app.swipeUp(); pause(0.6) }
        }
        guard el.isHittable else { print("QA: not hittable \(text)"); return false }
        el.tap()
        return true
    }

    private func tab(_ title: String) {
        // 탭바 버튼(마지막 일치 요소)을 누른다.
        let all = app.buttons.matching(NSPredicate(format: "label == %@", title))
        let n = all.count
        if n > 0 { all.element(boundBy: n - 1).tap() } else { print("QA: missing tab \(title)") }
        pause(3)
    }

    private func text(_ t: String) -> Bool {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", t)).firstMatch.exists
    }

    private func dismissSheet() {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        pause(1.5)
    }

    private func goBack() {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        }
        pause(1.5)
    }

    private func scrollThrough(_ prefix: String, times: Int = 4) {
        for i in 0..<times {
            app.swipeUp()
            pause(1)
            snap("\(prefix)_scroll\(i)")
        }
    }

    // MARK: - 사장님

    @MainActor func testO01_Home() throws {
        try requireRole("owner"); launch()
        snap("home")
        scrollThrough("home", times: 3)
    }

    @MainActor func testO02_WorkerList() throws {
        try requireRole("owner"); launch()
        tab("알바관리")
        snap("list")
        scrollThrough("list", times: 2)
    }

    @MainActor func testO03_WorkerDetailSheet() throws {
        try requireRole("owner"); launch()
        tab("알바관리")
        tap("민수", wait: 8)
        pause(4)
        snap("detail_top")
        for i in 0..<4 { app.swipeUp(); pause(1); snap("detail_scroll\(i)") }
    }

    @MainActor func testO04_Schedule() throws {
        try requireRole("owner"); launch()
        tab("스케줄")
        snap("schedule")
        scrollThrough("schedule", times: 2)
    }

    @MainActor func testO05_Approval() throws {
        try requireRole("owner"); launch()
        tab("승인")
        snap("approval")
        scrollThrough("approval", times: 2)
    }

    @MainActor func testO06_Settings() throws {
        try requireRole("owner"); launch()
        tab("설정")
        snap("settings")
        scrollThrough("settings", times: 2)
    }

    @MainActor func testO07_Manual() throws {
        try requireRole("owner"); launch()
        tap("가게 매뉴얼")
        pause(3)
        snap("docs")
        scrollThrough("docs", times: 2)
    }

    // MARK: - 알바생

    @MainActor func testW01_Home() throws {
        try requireRole("worker"); launch()
        snap("home")
        scrollThrough("home", times: 3)
    }

    @MainActor func testW02_CheckInScreen() throws {
        try requireRole("worker"); launch()
        tap("출근 · 퇴근하기")
        pause(3)
        snap("checkin")
        scrollThrough("checkin", times: 2)
    }

    @MainActor func testW03_Calendar() throws {
        try requireRole("worker"); launch()
        tab("달력")
        snap("calendar")
        scrollThrough("calendar", times: 2)
    }

    @MainActor func testW04_History() throws {
        try requireRole("worker"); launch()
        tab("내 기록")
        snap("history")
        scrollThrough("history", times: 2)
    }

    @MainActor func testW05_Profile() throws {
        try requireRole("worker"); launch()
        tab("내 프로필")
        snap("profile")
        scrollThrough("profile", times: 2)
    }
    // MARK: - 2차: 동작 확인

    private func waitText(_ t: String, _ timeout: Double) -> Bool {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", t)).firstMatch.waitForExistence(timeout: timeout)
    }

    private func openWorkerDetail(_ name: String = "민수") {
        tab("알바관리")
        tap(name, wait: 8)
        pause(3)
    }

    private func detailChip(_ title: String) {
        let chip = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", title, "gearshape.fill")).firstMatch
        var tries = 0
        while chip.waitForExistence(timeout: 5), !chip.isHittable, tries < 4 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
            pause(1); tries += 1
        }
        if chip.isHittable { chip.tap() } else { print("QA: chip not hittable \(title)") }
        pause(3)
    }

    private func wageField() -> XCUIElement {
        app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "10320")).firstMatch
    }

    private func setField(_ f: XCUIElement, _ value: String) {
        f.tap(); pause(0.5)
        let cur = (f.value as? String) ?? ""
        f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: max(cur.count, 8)))
        f.typeText(value)
        pause(0.5)
    }

    @MainActor func testO08_InviteSheet() throws {
        try requireRole("owner"); launch()
        tap("초대 코드 보내기")
        pause(4)
        snap("invite")
        print("QA: invite 6digit=\(app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9 ]{6,7}$")).count)")
        dismissSheet()
        snap("after_close")
    }

    @MainActor func testO09_DirectRegisterSheet() throws {
        try requireRole("owner"); launch()
        tap("직접 직원 등록")
        pause(3)
        snap("register")
        // 전화번호 자동 하이픈 확인(저장은 하지 않는다)
        let phone = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS %@", "010")).firstMatch
        if phone.waitForExistence(timeout: 3) { phone.tap(); phone.typeText("01099998888"); pause(1); print("QA: phone value=\(phone.value ?? "")") }
        snap("register_typed")
        dismissSheet()
        if app.buttons["취소"].exists { app.buttons["취소"].tap() }
        snap("after_close")
    }

    @MainActor func testO10_MonthlyDetail() throws {
        try requireRole("owner"); launch()
        tap("예상 인건비")
        pause(4)
        snap("monthly")
        tap("민수", wait: 6)
        pause(4)
        snap("worker_logs")
        app.swipeUp(); pause(1); snap("worker_logs_scroll")
    }

    @MainActor func testO11_WageSettingsSaveAndRevert() throws {
        try requireRole("owner"); launch()
        openWorkerDetail()
        detailChip("설정")
        snap("wage_open")
        let f = wageField()
        guard f.waitForExistence(timeout: 6) else { print("QA: wage field missing (store default?)"); snap("no_field"); return }
        let original = (f.value as? String) ?? ""
        print("QA: wage original=\(original)")
        // 1) 최저시급 미만은 막혀야 한다(서버로 안 감).
        setField(f, "5000")
        tap("저장", exact: true)
        pause(2)
        snap("below_min")
        print("QA: below-min error shown=\(waitText("최저시급", 2))")
        // 2) 값 바꿔 저장 → 다시 열어 확인 → 원래 값으로 되돌림
        let changed = String((Int(original) ?? 10320) + 10)
        setField(f, changed)
        tap("저장", exact: true)
        pause(3)
        snap("saved")
        print("QA: saved msg=\(button("저장했어요").exists)")
        dismissSheet()
        tap("민수", wait: 8); pause(3)
        detailChip("설정")
        let f2 = wageField()
        _ = f2.waitForExistence(timeout: 6)
        print("QA: wage reopened=\(f2.value ?? "nil") expected=\(changed)")
        snap("reopened")
        setField(f2, original.isEmpty ? "10320" : original)
        tap("저장", exact: true)
        pause(3)
        print("QA: reverted saved=\(button("저장했어요").exists)")
        snap("reverted")
    }

    @MainActor func testO12_ManualOpen() throws {
        try requireRole("owner"); launch()
        tap("가게 매뉴얼")
        pause(3)
        tap("매뉴얼", exact: true)
        pause(2)
        snap("manual_list")
        let closing = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "마감")).firstMatch
        if closing.waitForExistence(timeout: 5) { closing.tap() } else { print("QA: no 마감 doc") }
        pause(4)
        snap("doc_open")
        app.swipeUp(); pause(1); snap("doc_scroll")
    }

    @MainActor func testO13_ScheduleAdd() throws {
        try requireRole("owner"); launch()
        tab("스케줄")
        tap("근무 추가")
        pause(3)
        snap("add_sheet")
        app.swipeUp(); pause(1); snap("add_sheet_scroll")
        dismissSheet()
        if app.buttons["취소"].exists { app.buttons["취소"].tap(); pause(1) }
        snap("after_close")
        // 이전 달로 이동
        let prev = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR identifier == %@", "이전", "chevron.left")).firstMatch
        if prev.exists { prev.tap(); pause(3) }
        snap("prev_month")
    }

    @MainActor func testO14_RejectTodayTestLog() throws {
        try requireRole("owner"); launch()
        tab("승인")
        snap("before")
        // 오늘(QA 출퇴근으로 생긴) 근무가 맨 위에 있을 때만 반려한다.
        let today = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "10월 31일")).firstMatch
        guard today.waitForExistence(timeout: 6) else { print("QA: no today pending log"); return }
        let reject = app.buttons.matching(NSPredicate(format: "label == %@", "반려")).firstMatch
        guard reject.exists, abs(reject.frame.minY - today.frame.minY) < 220 else { print("QA: reject not near today card"); return }
        reject.tap()
        pause(2)
        snap("after_reject_tap")
        // 확인창이 있으면 확정
        let confirm = app.alerts.buttons.matching(NSPredicate(format: "label CONTAINS %@", "반려")).firstMatch
        if confirm.exists { confirm.tap() }
        pause(4)
        snap("after_reject")
    }

    @MainActor func testO15_SettingsSubpages() throws {
        try requireRole("owner"); launch()
        tab("설정")
        tap("급여 기본값")
        pause(3)
        snap("pay_defaults")
        app.swipeUp(); pause(1); snap("pay_defaults_scroll")
        goBack()
        tap("문의하기")
        pause(3)
        snap("inquiry")
    }

    @MainActor func testO16_StoreSwitcherAndNetTab() throws {
        try requireRole("owner"); launch()
        tap("수당카페")
        pause(2)
        snap("store_menu")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        pause(1)
        openWorkerDetail()
        detailChip("세후금액")
        snap("net")
        app.swipeUp(); pause(1); snap("net_scroll")
    }

    @MainActor func testW06_MoreMenu() throws {
        try requireRole("worker"); launch()
        let more = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@ OR identifier == %@", "더보기", "More", "ellipsis")).firstMatch
        if more.waitForExistence(timeout: 5) { more.tap() } else { print("QA: no more button") }
        pause(2)
        snap("menu")
    }

    @MainActor func testW07_StoreNews() throws {
        try requireRole("worker"); launch()
        tap("가게 소식")
        pause(4)
        snap("news")
        let first = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "마감")).firstMatch
        if first.waitForExistence(timeout: 4) { first.tap(); pause(3) }
        snap("doc")
        app.swipeUp(); pause(1); snap("doc_scroll")
    }

    @MainActor func testW08_CheckInOut() throws {
        try requireRole("worker"); launch()
        tap("출근 · 퇴근하기")
        pause(3)
        tap("출근하기", exact: true)
        pause(6)
        snap("checked_in")
        print("QA: after checkin has 퇴근하기=\(button("퇴근하기", exact: true).exists)")
        tap("퇴근하기", exact: true)
        pause(3)
        snap("checkout_tap")
        // 확인창이 뜨면 퇴근 확정
        let alertBtn = app.alerts.buttons.matching(NSPredicate(format: "label CONTAINS %@", "퇴근")).firstMatch
        if alertBtn.exists { alertBtn.tap(); pause(4) }
        let sheetBtn = app.sheets.buttons.matching(NSPredicate(format: "label CONTAINS %@", "퇴근")).firstMatch
        if sheetBtn.exists { sheetBtn.tap(); pause(4) }
        snap("checked_out")
        goBack()
        snap("home_after")
    }

    @MainActor func testW09_Chat() throws {
        try requireRole("worker"); launch()
        tap("물어보기")
        pause(3)
        snap("open")
        func ask(_ q: String) {
            let field = app.textFields["궁금한 걸 물어보세요"].exists ? app.textFields["궁금한 걸 물어보세요"] : app.textViews.firstMatch
            field.tap(); pause(0.5)
            field.typeText(q); pause(0.5)
            tap("보내기")
            let start = Date()
            // 답이 올 때까지(사용자 메시지 이후 새 텍스트) 최대 40초
            while Date().timeIntervalSince(start) < 40 {
                pause(2)
                if app.images.matching(NSPredicate(format: "identifier == %@", "ellipsis")).count == 0 && Date().timeIntervalSince(start) > 6 { break }
            }
            print("QA: answer wait \(Int(Date().timeIntervalSince(start)))s")
        }
        ask("마감할 때 우유는 어떻게 해요?")
        snap("q1")
        print("QA: q1 source cards=\(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "원문 보기")).count)")
        ask("주차 지원 돼요?")
        snap("q2")
        print("QA: total source cards after q2=\(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "원문 보기")).count)")
        let src = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "원문 보기")).firstMatch
        if src.exists {
            if !src.isHittable { app.swipeDown(); pause(1) }
            src.tap(); pause(4)
            snap("source")
            print("QA: source sheet title=\(waitText("답변 근거", 3))")
        }
    }

    @MainActor func testW10_ProfileEditAndInquiry() throws {
        try requireRole("worker"); launch()
        tab("내 프로필")
        tap("수정", exact: true)
        pause(3)
        snap("edit")
        dismissSheet()
        if app.buttons["취소"].exists { app.buttons["취소"].tap(); pause(1) }
        tap("문의하기")
        pause(3)
        snap("inquiry")
    }

    @MainActor func testW11_CalendarDayAndMonth() throws {
        try requireRole("worker"); launch()
        tab("달력")
        let d29 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "29")).firstMatch
        if d29.waitForExistence(timeout: 5) { d29.tap(); pause(2) }
        snap("day29")
        let d31 = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "31")).firstMatch
        if d31.exists { d31.tap(); pause(2) }
        snap("day31")
        let next = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label CONTAINS %@", "chevron.right", "다음")).firstMatch
        if next.exists { next.tap(); pause(3) }
        snap("next_month")
    }

    @MainActor func testW12_WorkHistoryFromCheckIn() throws {
        try requireRole("worker"); launch()
        tap("출근 · 퇴근하기")
        pause(3)
        tap("근무 내역 보기")
        pause(4)
        snap("logs")
        app.swipeUp(); pause(1); snap("logs_scroll")
    }
    // MARK: - 3차

    @MainActor func testO17_JisuNetAndSettings() throws {
        try requireRole("owner"); launch()
        openWorkerDetail("지수")
        detailChip("세후금액")
        snap("net")
        detailChip("설정")
        snap("settings")
    }

    @MainActor func testO18_WageSaveRevert() throws {
        try requireRole("owner"); launch()
        openWorkerDetail()
        detailChip("설정")
        // '시급 매장 기본' 줄을 누르면 직접 입력으로 바뀐다.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "시급", "매장 기본")).firstMatch
        if row.waitForExistence(timeout: 5) { row.tap(); pause(1) } else { print("QA: wage row missing") }
        let f = wageField()
        guard f.waitForExistence(timeout: 5) else { print("QA: wage field still missing"); snap("nofield"); return }
        snap("custom")
        setField(f, "5000")
        app.swipeUp(); pause(1)
        let save = button("저장", exact: true)
        print("QA: save exists=\(save.exists) hittable=\(save.isHittable)")
        snap("before_save_low")
        if save.isHittable { save.tap(); pause(2) }
        snap("below_min")
        print("QA: below-min error=\(waitText("최저시급", 2))")
        app.swipeDown(); pause(1)
        setField(wageField(), "10330")
        app.swipeUp(); pause(1)
        if button("저장", exact: true).isHittable { button("저장", exact: true).tap(); pause(3) }
        snap("saved")
        print("QA: saved msg=\(button("저장했어요").exists)")
        dismissSheet()
        snap("list_after_save")
        tap("민수", wait: 8); pause(3)
        detailChip("설정")
        print("QA: reopened field=\(wageField().exists ? (wageField().value as? String ?? "?") : "none(store default)")")
        snap("reopened")
        // 되돌리기: '매장 기본' 칩
        let storeChip = app.buttons.matching(NSPredicate(format: "label == %@", "매장 기본")).firstMatch
        if storeChip.exists { storeChip.tap(); pause(1) }
        app.swipeUp(); pause(1)
        if button("저장", exact: true).isHittable { button("저장", exact: true).tap(); pause(3) }
        print("QA: revert saved=\(button("저장했어요").exists)")
        snap("reverted")
        dismissSheet()
        tap("민수", wait: 8); pause(3)
        detailChip("설정")
        print("QA: final wage field=\(wageField().exists ? (wageField().value as? String ?? "?") : "none(store default)")")
        snap("final")
    }

    @MainActor func testO19_ScheduleDays() throws {
        try requireRole("owner"); launch()
        tab("스케줄")
        for d in ["2", "5", "24"] {
            let b = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", d + ",")).firstMatch
            let b2 = b.exists ? b : app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", d)).firstMatch
            if b2.exists { b2.tap(); pause(2) } else { print("QA: day \(d) missing") }
            snap("day\(d)")
        }
    }

    @MainActor func testO20_ApprovalBottom() throws {
        try requireRole("owner"); launch()
        tab("승인")
        for _ in 0..<8 { app.swipeUp(); pause(0.4) }
        pause(1)
        snap("bottom")
    }

    @MainActor func testW13_NewsManualTab() throws {
        try requireRole("worker"); launch()
        tap("가게 소식")
        pause(3)
        tap("매뉴얼", exact: true)
        pause(2)
        snap("manual_tab")
        let doc = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "마감")).firstMatch
        if doc.waitForExistence(timeout: 4) { doc.tap(); pause(3) } else { print("QA: no 마감 doc in worker news") }
        snap("doc")
    }
    private func typeWage(_ value: String) {
        let f = wageField()
        guard f.waitForExistence(timeout: 5) else { print("QA: no wage field"); return }
        // 커서를 맨 끝에 두고 지운 뒤 입력
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap(); pause(0.5)
        f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        f.typeText(value); pause(0.5)
        print("QA: typed field=\(f.value ?? "nil")")
        // 키보드 닫기: 이름 영역을 누른다
        app.staticTexts["민수"].firstMatch.tap(); pause(1)
    }

    private func tapSave() -> Bool {
        let save = button("저장", exact: true)
        for _ in 0..<3 where !(save.exists && save.isHittable) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
            pause(1)
        }
        guard save.exists, save.isHittable else { print("QA: save not hittable"); return false }
        save.tap(); pause(3); return true
    }

    @MainActor func testO21_WageSaveRevert2() throws {
        try requireRole("owner"); launch()
        openWorkerDetail()
        detailChip("설정")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "시급", "매장 기본")).firstMatch
        if row.waitForExistence(timeout: 5) { row.tap(); pause(1) }
        typeWage("5000")
        snap("low_typed")
        _ = tapSave()
        print("QA: below-min error=\(waitText("최저시급", 2))")
        snap("low_result")
        app.swipeDown(); pause(1)
        typeWage("10330")
        _ = tapSave()
        print("QA: saved msg=\(button("저장했어요").exists)")
        snap("saved")
        dismissSheet()
        tap("민수", wait: 8); pause(3)
        detailChip("설정")
        print("QA: reopened field=\(wageField().exists ? (wageField().value as? String ?? "?") : "none(store default)")")
        snap("reopened")
        let storeChip = app.buttons.matching(NSPredicate(format: "label == %@", "매장 기본")).firstMatch
        if storeChip.exists { storeChip.tap(); pause(1) }
        _ = tapSave()
        print("QA: revert saved=\(button("저장했어요").exists)")
        dismissSheet()
        tap("민수", wait: 8); pause(3)
        detailChip("설정")
        print("QA: final=\(wageField().exists ? (wageField().value as? String ?? "?") : "none(store default)")")
        snap("final")
    }
}
