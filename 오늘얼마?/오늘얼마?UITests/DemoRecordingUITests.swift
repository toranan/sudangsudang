import XCTest

// 공모전 데모 영상 촬영용. 실행할 때 TEST_RUNNER_DEMO_ROLE=owner|worker, TEST_RUNNER_DEMO_EMAIL, TEST_RUNNER_DEMO_PASSWORD를 넘긴다.
// 화면을 천천히 넘기고, 녹화는 바깥에서 simctl recordVideo로 한다.
final class DemoRecordingUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipIf(env["DEMO_EMAIL"] == nil, "데모 계정 환경변수가 없어서 건너뜀")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["DEMO_EMAIL"] = env["DEMO_EMAIL"]
        app.launchEnvironment["DEMO_PASSWORD"] = env["DEMO_PASSWORD"]
        app.launch()
        return app
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor
    func testDumpScreens() throws {
        try XCTSkipIf(env["DEMO_DUMP"] == nil)
        let app = launch()
        pause(8)
        let out = env["DEMO_DUMP"]!
        try app.debugDescription.write(toFile: out, atomically: true, encoding: .utf8)
    }

    // MARK: - 촬영 흐름

    private func dump(_ app: XCUIApplication, _ name: String) {
        guard let dir = env["DEMO_DUMP_DIR"] else { return }
        try? app.debugDescription.write(toFile: "\(dir)/\(name).txt", atomically: true, encoding: .utf8)
    }

    @discardableResult
    private func tap(_ app: XCUIApplication, containing text: String, wait: Double = 8) -> Bool {
        let el = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        guard el.waitForExistence(timeout: wait) else {
            print("DEMO: missing button \(text)")
            return false
        }
        el.tap()
        return true
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists { back.tap() } else {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        }
    }

    private func ask(_ app: XCUIApplication, _ question: String) {
        let field = app.textFields["궁금한 걸 물어보세요"].exists ? app.textFields["궁금한 걸 물어보세요"] : app.textViews.firstMatch
        field.tap()
        pause(0.6)
        field.typeText(question)
        pause(0.8)
        tap(app, containing: "보내기")
        // 답변이 올 때까지 기다린다(입력창이 다시 켜질 때까지).
        pause(12)
    }

    @MainActor
    func testWorkerFlow() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "worker")
        let app = launch()
        pause(5)
        dump(app, "w0_home")
        tap(app, containing: "출근 · 퇴근하기")
        pause(2.5)
        dump(app, "w1_checkin")
        tap(app, containing: "출근하기")
        pause(8)
        dump(app, "w2_checked_in")
        goBack(app)
        pause(2)
        tap(app, containing: "달력")
        pause(4)
        dump(app, "w3_calendar")
        tap(app, containing: "내 기록")
        pause(4)
        dump(app, "w4_history")
        app.swipeUp()
        pause(3)
        tap(app, containing: "출퇴근")
        pause(2)
        tap(app, containing: "물어보기")
        pause(3)
        dump(app, "w5_chat")
        ask(app, "마감할 때 우유는 어떻게 해요?")
        dump(app, "w6_answer1")
        ask(app, "주차 지원 돼요?")
        dump(app, "w7_answer2")
        pause(3)
    }

    // 챗봇 장면만 다시 찍을 때
    @MainActor
    func testWorkerChat() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "worker")
        let app = launch()
        pause(5)
        dump(app, "c0_home")
        tap(app, containing: "물어보기")
        pause(3)
        dump(app, "c1_chat")
        ask(app, "마감할 때 우유는 어떻게 해요?")
        dump(app, "c2_answer1")
        ask(app, "주차 지원 돼요?")
        dump(app, "c3_answer2")
        pause(3)
        // 근거 카드를 눌러 원문을 연다.
        if env["DEMO_OPEN_SOURCE"] != nil {
            app.swipeDown()
            pause(1.5)
            tap(app, containing: "원문 보기")
            pause(4)
            dump(app, "c4_source")
        }
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let dir = env["DEMO_DUMP_DIR"] else { return }
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    }

    // 노션용 직원 급여 설정 화면 캡처
    @MainActor
    func testOwnerShots() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        pause(6)
        shot(app, "shot_owner_home")
        tap(app, containing: "알바관리")
        pause(3)
        tap(app, containing: "민수", wait: 6)
        pause(3)
        // 탭바의 '설정'(톱니바퀴)과 구분해 직원 상세의 '설정' 칩을 누른다.
        let wage = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "설정", "gearshape.fill")).firstMatch
        // 상세가 아래로 스크롤된 채 열리면 칩이 화면 밖이라, 위로 끌어 올린 뒤 누른다.
        var tries = 0
        while wage.waitForExistence(timeout: 5), !wage.isHittable, tries < 4 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
            pause(1)
            tries += 1
        }
        if wage.isHittable { wage.tap() }
        pause(4)
        dump(app, "shot_wage")
        shot(app, "shot_wage")
    }

    // 사장님 AI 비서: 추천 질문 4개를 물어보고, 답과 '상세' 화면 숫자를 비교할 수 있게 저장한다.
    @MainActor
    func testOwnerAgent() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        pause(6)
        tap(app, containing: "AI 비서에게 물어보기")
        pause(2)
        let questions = [
            "이번 달 인건비 얼마야?",
            "이번 주 주휴수당 못 받는 사람 있어?",
            "승인 기다리는 근무 보여줘",
            "내일 누가 출근해?"
        ]
        for (index, question) in questions.enumerated() {
            ask(app, question)
            pause(18)
            dump(app, "agent_\(index + 1)")
            shot(app, "agent_\(index + 1)")
        }
        tap(app, containing: "닫기")
        pause(2)
        tap(app, containing: "예상 인건비")
        pause(5)
        dump(app, "agent_detail")
        shot(app, "agent_detail")
    }

    // AI 비서 근무 추가: 시각이 빠지면 되묻는지, 확인 카드가 뜨는지 본다. 데모 데이터를 바꾸지 않게 취소로 끝낸다.
    @MainActor
    func testOwnerAgentAddWork() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        pause(6)
        tap(app, containing: "AI 비서에게 물어보기")
        pause(2)
        ask(app, "어제 민수 근무 추가해줘")
        pause(10)
        dump(app, "write_1")
        shot(app, "write_1")
        ask(app, "오후 6시부터 10시까지")
        pause(14)
        dump(app, "write_2")
        shot(app, "write_2")
        if tap(app, containing: "취소", wait: 5) {
            pause(2)
        }
        dump(app, "write_3")
        shot(app, "write_3")
    }

    // AI 비서 저장까지: 추가 → 수정은 저장하고, 일괄 승인은 카드만 보고 취소한다.
    @MainActor
    func testOwnerAgentSave() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        pause(6)
        tap(app, containing: "AI 비서에게 물어보기")
        pause(2)
        let steps: [(String, String?)] = [
            ("어제 민수 근무 추가해줘", nil),
            ("오후 6시부터 10시까지", "추가하기"),
            ("방금 넣은 근무 퇴근을 9시로 바꿔줘", "수정하기"),
            ("승인 기다리는 근무 다 승인해줘", "취소")
        ]
        for (index, step) in steps.enumerated() {
            ask(app, step.0)
            pause(14)
            dump(app, "save_\(index + 1)a")
            shot(app, "save_\(index + 1)a")
            if let button = step.1, tap(app, containing: button, wait: 5) {
                pause(16)
                dump(app, "save_\(index + 1)b")
                shot(app, "save_\(index + 1)b")
            }
        }
        tap(app, containing: "닫기")
        pause(3)
        tap(app, containing: "예상 인건비")
        pause(5)
        dump(app, "save_detail")
    }

    // AI 비서 급여 설정: 적용 범위를 되묻는지, 카드 금액이 맞는지 본다. 데모 설정은 바꾸지 않게 취소한다.
    @MainActor
    func testOwnerAgentSettings() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        pause(6)
        tap(app, containing: "AI 비서에게 물어보기")
        pause(2)
        let steps: [(String, String?)] = [
            ("민수 주휴수당 빼줘", nil),
            ("이번 달 근무에도 적용해줘", "취소"),
            ("야간수당 전부 적용하지 마. 이번 달부터", "취소")
        ]
        for (index, step) in steps.enumerated() {
            ask(app, step.0)
            pause(14)
            dump(app, "settings_\(index + 1)")
            shot(app, "settings_\(index + 1)")
            if let button = step.1, tap(app, containing: button, wait: 5) {
                pause(2)
            }
        }
    }

    // AI 비서 결근: 뭉뚱그린 말 → 사람별 체크 카드 → 체크 해제 → 말로 정정 → 취소(데모 데이터 유지)
    @MainActor
    func testOwnerAgentAbsent() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        pause(6)
        tap(app, containing: "AI 비서에게 물어보기")
        pause(2)
        ask(app, "29일에 다 결근했어")
        pause(16)
        dump(app, "absent_1")
        shot(app, "absent_1")
        let firstChecked = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "선택됨")).firstMatch
        if firstChecked.waitForExistence(timeout: 3) {
            firstChecked.tap()
            pause(1)
        }
        dump(app, "absent_2")
        shot(app, "absent_2")
        ask(app, "아 사실은 지수 한 명이었어")
        pause(16)
        dump(app, "absent_3")
        shot(app, "absent_3")
        tap(app, containing: "취소", wait: 5)
        pause(2)
        dump(app, "absent_4")
    }

    // AI 비서 결근 저장까지: 3명 카드 → 말로 한 명으로 정정 → 실제 저장
    @MainActor
    func testOwnerAgentAbsentSave() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        pause(6)
        tap(app, containing: "AI 비서에게 물어보기")
        pause(2)
        ask(app, "28일에 다 결근했어")
        pause(16)
        dump(app, "save_absent_1")
        shot(app, "save_absent_1")
        ask(app, "아 사실은 민수 한 명이었어")
        pause(16)
        dump(app, "save_absent_2")
        shot(app, "save_absent_2")
        tap(app, containing: "결근 처리", wait: 5)
        pause(16)
        dump(app, "save_absent_3")
        shot(app, "save_absent_3")
    }

    // AI 비서 알바 고르기: 누구인지 없으면 이름 버튼이 뜨고, 눌러서 이어 간다. 마지막 카드는 취소.
    @MainActor
    func testOwnerAgentChooseWorker() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        pause(6)
        tap(app, containing: "AI 비서에게 물어보기")
        pause(2)
        ask(app, "3시간 근무 추가해줘")
        pause(12)
        dump(app, "choose_1")
        shot(app, "choose_1")
        let minsu = app.buttons["민수"]
        if minsu.waitForExistence(timeout: 5) { minsu.tap() }
        pause(16)
        dump(app, "choose_2")
        shot(app, "choose_2")
        ask(app, "어제 오후 2시부터")
        pause(16)
        dump(app, "choose_3")
        shot(app, "choose_3")
        tap(app, containing: "취소", wait: 5)
        pause(2)
    }

    // MARK: - 노션용 AI 비서 시연 녹화 (기능별 한 편씩)

    // 보내고 나서 키보드를 내려 카드가 가려지지 않게 한다.
    private func say(_ app: XCUIApplication, _ text: String, wait: Double) {
        let field = app.textFields["궁금한 걸 물어보세요"].exists ? app.textFields["궁금한 걸 물어보세요"] : app.textViews.firstMatch
        field.tap()
        pause(0.6)
        field.typeText(text)
        pause(0.8)
        tap(app, containing: "보내기")
        pause(0.5)
        // 대화 영역을 한 번 눌러 키보드를 내린다(헤더 바로 아래 빈 곳).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.13)).tap()
        pause(wait)
    }

    private func openAgent(_ app: XCUIApplication) {
        pause(4)
        tap(app, containing: "AI 비서에게 물어보기")
        pause(2.5)
    }

    @MainActor
    func testClipRead() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        openAgent(app)
        say(app, "이번 달 인건비 얼마야?", wait: 16)
        shot(app, "clip_read_1")
        say(app, "이번 주 주휴수당 못 받는 사람 있어?", wait: 20)
        shot(app, "clip_read_2")
    }

    @MainActor
    func testClipAdd() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        openAgent(app)
        say(app, "어제 3시간 근무 추가해줘", wait: 12)
        shot(app, "clip_add_1")
        let jisu = app.buttons["지수"]
        if jisu.waitForExistence(timeout: 5) { jisu.tap() }
        pause(14)
        say(app, "오후 2시부터", wait: 16)
        shot(app, "clip_add_2")
        tap(app, containing: "추가하기", wait: 5)
        pause(14)
        shot(app, "clip_add_3")
    }

    @MainActor
    func testClipApprove() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        openAgent(app)
        say(app, "승인 기다리는 근무 다 승인해줘", wait: 16)
        shot(app, "clip_approve_1")
        tap(app, containing: "승인하기", wait: 5)
        pause(14)
        shot(app, "clip_approve_2")
    }

    @MainActor
    func testClipAbsent() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        openAgent(app)
        say(app, "28일에 다 결근했어", wait: 18)
        shot(app, "clip_absent_1")
        let firstChecked = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "선택됨")).firstMatch
        if firstChecked.waitForExistence(timeout: 3) { firstChecked.tap() }
        pause(2.5)
        shot(app, "clip_absent_2")
        tap(app, containing: "결근 처리", wait: 5)
        pause(14)
        shot(app, "clip_absent_3")
    }

    @MainActor
    func testClipSettings() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        openAgent(app)
        say(app, "지수 주휴수당 빼줘", wait: 12)
        shot(app, "clip_settings_1")
        // 언제부터 적용할지 버튼으로 고른다.
        pause(2)
        if !tap(app, containing: "이번 달", wait: 6) {
            say(app, "이번 달 근무에도 적용해줘", wait: 0)
        }
        pause(16)
        shot(app, "clip_settings_2")
        app.swipeUp()
        pause(3)
        shot(app, "clip_settings_3")
        // 데모 설정은 바꾸지 않는다.
        tap(app, containing: "취소", wait: 5)
        pause(1)
    }

    // 사장님 홈·상세 금액 확인용
    @MainActor
    func testOwnerDetail() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        pause(6)
        dump(app, "home")
        shot(app, "home")
        app.swipeUp()
        pause(1)
        shot(app, "home_bottom")
        app.swipeDown()
        pause(1)
        tap(app, containing: "예상 인건비")
        pause(5)
        dump(app, "detail")
    }

    // 앱스토어 스크린샷용 알바생 화면
    @MainActor
    func testWorkerStoreShots() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "worker")
        let app = launch()
        pause(6)
        shot(app, "w_home")
        tap(app, containing: "출근 · 퇴근하기")
        pause(3)
        shot(app, "w_checkin")
        goBack(app)
        pause(2)
        tap(app, containing: "달력")
        pause(4)
        shot(app, "w_calendar")
        tap(app, containing: "내 기록")
        pause(4)
        shot(app, "w_history")
        tap(app, containing: "출퇴근")
        pause(2)
        tap(app, containing: "물어보기")
        pause(3)
        ask(app, "마감할 때 우유는 어떻게 해요?")
        // 키보드를 내린 화면으로 찍는다.
        let title = app.staticTexts["물어보기"].firstMatch
        if title.exists { title.tap() }
        pause(2)
        shot(app, "w_chat")
        tap(app, containing: "원문 보기")
        pause(4)
        shot(app, "w_source")
    }

    // 앱스토어 스크린샷용 사장님 화면
    @MainActor
    func testOwnerStoreShots() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        pause(6)
        shot(app, "o_home")
        tap(app, containing: "확인하기")
        pause(4)
        shot(app, "o_approval")
        app.swipeUp()
        pause(1.5)
        shot(app, "o_approval_scrolled")
        app.swipeUp()
        app.swipeUp()
        pause(1.5)
        shot(app, "o_approval_bottom")
        tap(app, containing: "홈")
        pause(2)
        tap(app, containing: "가게 매뉴얼")
        pause(4)
        shot(app, "o_docs")
        let back = app.buttons.matching(NSPredicate(format: "label == %@", "Back")).firstMatch
        if back.exists { back.tap() }
        pause(2)
        tap(app, containing: "알바관리")
        pause(4)
        shot(app, "o_workers")
        tap(app, containing: "민수", wait: 6)
        pause(4)
        shot(app, "o_worker_detail")
        let wage = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "설정", "gearshape.fill")).firstMatch
        if wage.waitForExistence(timeout: 5), wage.isHittable { wage.tap() }
        pause(4)
        shot(app, "o_wage")
    }

    @MainActor
    func testOwnerFlow() throws {
        try XCTSkipIf(env["DEMO_ROLE"] != "owner")
        let app = launch()
        pause(5)
        dump(app, "o0_home")
        tap(app, containing: "확인하기")
        pause(3)
        dump(app, "o1_approval")
        // 탭바에도 '승인'이 있어서, 카드의 '반려' 버튼 오른쪽을 눌러 승인한다.
        let reject = app.buttons.matching(NSPredicate(format: "label == %@", "반려")).firstMatch
        if reject.waitForExistence(timeout: 10) {
            pause(2)
            let f = reject.frame
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: f.maxX + f.width / 2 + 8, dy: f.midY))
                .tap()
        }
        pause(4)
        dump(app, "o2_approved")
        tap(app, containing: "홈")
        pause(3)
        dump(app, "o3_after_back")
        tap(app, containing: "가게 매뉴얼")
        pause(3)
        dump(app, "o4_docs")
        let manualFilter = app.buttons.matching(NSPredicate(format: "label == %@", "매뉴얼")).firstMatch
        if manualFilter.waitForExistence(timeout: 5) { manualFilter.tap() }
        pause(2.5)
        let closing = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "마감 순서,")).firstMatch
        if closing.waitForExistence(timeout: 5) { closing.tap() }
        pause(5)
        dump(app, "o5_doc")
        // 문서 화면이 시트면 아래로 내려 닫고, 푸시 화면이면 뒤로 간다.
        if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        }
        pause(2)
        dump(app, "o5b_after_doc")
        let back = app.buttons.matching(NSPredicate(format: "label == %@", "Back")).firstMatch
        if back.exists { back.tap() }
        pause(2)
        tap(app, containing: "알바관리")
        pause(3)
        dump(app, "o6_workers")
        tap(app, containing: "민수", wait: 6)
        pause(4)
        dump(app, "o7_worker_detail")
        app.swipeUp()
        pause(3)
    }
}
