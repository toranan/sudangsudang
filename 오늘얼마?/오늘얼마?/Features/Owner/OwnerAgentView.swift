import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

// 사장님 AI 비서. owner-agent 함수가 Claude를 부르고, Claude가 고른 조회 도구는 앱이 실행해 결과를 돌려준다.
// 근무를 바꾸는 도구는 확인 카드만 띄우고, 사장님이 확인을 눌러야 저장한 뒤 대화를 이어 간다.
// 대화 기록(history)은 Claude API 형식 그대로 들고 있다가 매 요청마다 보낸다.
struct OwnerAgentView: View {
    let storeId: UUID
    let storeName: String

    private struct Message: Identifiable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        let content: String
        var proposal: OwnerAgentProposal?
        var proposalState: ProposalState = .pending
        // 체크된 항목. 처음엔 모두 체크.
        var selected: Set<UUID> = []
        // 고르는 버튼(알바 이름이나 정해진 답)과 고른 것
        var choices: [String] = []
        var chosen: String?
    }

    // 사장님이 버튼으로 고르길 기다리는 도구 호출
    private struct PendingChoice {
        let messageId: UUID
        let toolUseId: String
        // 고른 버튼 앞에 붙여 도구 결과로 보낼 말. 예: "사장님이 고른 알바"
        let resultLabel: String
        let otherResults: [AnyJSON]
    }

    private enum ProposalState: Equatable {
        case pending, saving, saved, cancelled, superseded
        case failed(String)
    }

    // 사장님 확인을 기다리는 쓰기 도구 호출
    private struct PendingAction {
        let messageId: UUID
        let toolUseId: String
        let proposal: OwnerAgentProposal
        // 같은 응답에서 함께 부른 다른 도구의 결과. 확인 결과와 같이 보낸다.
        let otherResults: [AnyJSON]
    }

    private struct AgentRequest: Encodable {
        let storeId: UUID
        let messages: [AnyJSON]
    }

    private struct IncompleteAnswer: Error {}

    private struct AgentResponse: Decodable {
        let content: [AnyJSON]
        let stop_reason: String?
    }

    private static let suggestions = [
        "이번 달 인건비 얼마야?",
        "이번 주 주휴수당 못 받는 사람 있어?",
        "승인 기다리는 근무 보여줘",
        "내일 누가 출근해?"
    ]

    // 질문 하나에 도구를 부르는 최대 횟수
    private static let maxToolRounds = 8
    // 서버가 받는 메시지 수 제한(60)보다 작게 유지한다.
    private static let maxHistoryCount = 40

    private static let toolStatusText: [String: String] = [
        "list_workers": "알바 목록 보는 중",
        "get_month_payroll": "인건비 계산하는 중",
        "get_weekly_allowance_status": "주휴수당 확인하는 중",
        "list_pending_approvals": "승인 대기 근무 보는 중",
        "get_work_logs": "근무 기록 보는 중",
        "get_schedule": "스케줄 보는 중",
        "add_work_log": "근무 추가 준비하는 중",
        "update_work_log": "근무 수정 준비하는 중",
        "set_work_log_status": "승인·반려 준비하는 중",
        "update_payroll_settings": "급여 설정 변경 준비하는 중",
        "mark_absent": "결근 처리 준비하는 중",
        "choose_worker": "알바 목록 보는 중",
        "ask_choice": "물어볼 것 정리하는 중"
    ]

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [Message] = []
    @State private var history: [AnyJSON] = []
    @State private var input = ""
    @State private var isAsking = false
    @State private var statusText: String?
    @State private var pendingAction: PendingAction?
    @State private var pendingChoice: PendingChoice?
    @FocusState private var isInputFocused: Bool

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if messages.isEmpty && !isAsking {
                            emptyState
                        }
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                        if isAsking {
                            typingRow
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(TapGesture().onEnded { dismissKeyboard() })
                .onChange(of: messages.count) { _ in scrollToBottom(proxy) }
                .onChange(of: isAsking) { _ in scrollToBottom(proxy) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputBar
        }
        .background(Color.appSurface.ignoresSafeArea())
    }

    // MARK: - Pieces

    private var topBar: some View {
        ZStack {
            VStack(spacing: 1) {
                Text("AI 비서")
                    .font(.app(.callout, .bold))
                    .foregroundColor(.appTextPrimary)
                Text(storeName)
                    .font(.system(size: 12))
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(1)
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.appTextPrimary)
                        .frame(width: 34, height: 34)
                        .background(Color.appFill, in: Circle())
                }
                .buttonStyle(PressableRowStyle())
                .accessibilityLabel("닫기")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { dismissKeyboard() }
    }

    private func dismissKeyboard() {
        if isInputFocused { isInputFocused = false }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            assistantMark(size: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text("매장 일을 물어보세요")
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundColor(.appTextPrimary)
                Text("근무 기록과 급여를 앱 화면과 같은 기준으로 계산해 답해요. 근무와 급여 설정을 바꿀 때는 확인을 받고 저장해요.")
                    .font(.app(.callout))
                    .foregroundColor(.appTextSecondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button {
                        Task { await ask(suggestion) }
                    } label: {
                        HStack(spacing: 8) {
                            Text(suggestion)
                                .font(.app(.callout, .medium))
                                .foregroundColor(.appTextPrimary)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.appTextSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.appFill, in: Capsule())
                    }
                    .buttonStyle(PressableRowStyle())
                }
            }
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private func messageRow(_ message: Message) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 56)
                Text(message.content)
                    .font(.app(.callout, .medium))
                    .foregroundColor(.appOnInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.appInk)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 10) {
                assistantMark(size: 28)
                if let proposal = message.proposal {
                    proposalCard(message, proposal: proposal)
                } else if !message.choices.isEmpty {
                    choiceRow(message)
                } else {
                    Text(message.content)
                        .font(.app(.callout))
                        .foregroundColor(.appTextPrimary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 24)
                }
            }
        }
    }

    // 저장 전 확인 카드. 무엇이 바뀌는지와 그 주 주휴수당 영향을 한 번에 보여 준다.
    private func proposalCard(_ message: Message, proposal: OwnerAgentProposal) -> some View {
        let state = message.proposalState
        let isEditable = state == .pending
        let effects = proposal.effects(selected: message.selected)
        return VStack(alignment: .leading, spacing: 12) {
            Text(proposal.title)
                .font(.app(.body, .bold))
                .foregroundColor(.appTextPrimary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(proposal.rows, id: \.self) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.label)
                            .font(.app(.caption, .medium))
                            .foregroundColor(.appTextSecondary)
                            .frame(minWidth: 52, alignment: .leading)
                        Text(row.value)
                            .font(.app(.callout, .semibold))
                            .foregroundColor(.appTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            if !proposal.items.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(proposal.items) { item in
                        itemRow(item, isOn: message.selected.contains(item.id), isEditable: isEditable) {
                            toggle(item.id, in: message.id)
                        }
                    }
                }
            }

            if !effects.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("승인된 근무 기준 변화")
                        .font(.app(.caption, .semibold))
                        .foregroundColor(.appTextSecondary)
                    ForEach(effects, id: \.self) { line in
                        Text(line)
                            .font(.app(.caption))
                            .foregroundColor(.appTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            switch state {
            case .pending, .saving:
                HStack(spacing: 8) {
                    Button("취소") {
                        Task { await cancelPending() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(state == .saving)

                    Button {
                        Task { await confirmPending() }
                    } label: {
                        if state == .saving {
                            ProgressView().tint(.white)
                        } else {
                            Text(proposal.confirmTitle(selectedCount: message.selected.count))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(state == .saving || (!proposal.items.isEmpty && message.selected.isEmpty))
                }
            case .saved:
                stateLabel("저장했어요", systemImage: "checkmark.circle.fill", color: .appAccent)
            case .cancelled:
                stateLabel("취소했어요. 저장하지 않았어요.", systemImage: "xmark.circle", color: .appTextSecondary)
            case .superseded:
                stateLabel("다른 요청을 해서 저장하지 않았어요.", systemImage: "arrow.uturn.down.circle", color: .appTextSecondary)
            case .failed(let message):
                stateLabel(message, systemImage: "exclamationmark.triangle.fill", color: .appWarning)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // 고르는 버튼(알바 이름이나 정해진 답). 고르면 그 버튼으로 대화를 이어 간다.
    private func choiceRow(_ message: Message) -> some View {
        let isOpen = pendingChoice?.messageId == message.id && message.chosen == nil
        return VStack(alignment: .leading, spacing: 10) {
            Text(message.content)
                .font(.app(.callout))
                .foregroundColor(.appTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 8) {
                ForEach(message.choices, id: \.self) { name in
                    let isChosen = message.chosen == name
                    Button {
                        Task { await choose(name) }
                    } label: {
                        Text(name)
                            .font(.app(.callout, .semibold))
                            .foregroundColor(isChosen ? .appOnInk : .appTextPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(isChosen ? Color.appInk : Color.appFill, in: Capsule())
                    }
                    .buttonStyle(PressableRowStyle())
                    .disabled(!isOpen || isAsking)
                    .opacity(isOpen || isChosen ? 1 : 0.5)
                }
            }
        }
    }

    private func itemRow(_ item: OwnerAgentProposal.Item, isOn: Bool, isEditable: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isOn ? .appAccent : .appTextSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.app(.callout, .semibold))
                        .foregroundColor(isOn ? .appTextPrimary : .appTextSecondary)
                    Text(item.detail)
                        .font(.app(.caption))
                        .foregroundColor(.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .accessibilityLabel("\(item.title) \(isOn ? "선택됨" : "선택 안 됨")")
    }

    private func toggle(_ itemId: UUID, in messageId: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        if messages[index].selected.contains(itemId) {
            messages[index].selected.remove(itemId)
        } else {
            messages[index].selected.insert(itemId)
        }
    }

    private func stateLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.app(.caption, .semibold))
            .foregroundColor(color)
    }

    private var typingRow: some View {
        HStack(spacing: 10) {
            assistantMark(size: 28)
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.appTextSecondary)
                .symbolEffect(.variableColor.iterative, options: .repeating)
            if let statusText {
                Text(statusText)
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appTextSecondary)
            }
        }
    }

    private func assistantMark(size: CGFloat) -> some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundColor(.appAccent)
            .frame(width: size, height: size)
            .background(Color.appAccentSoft, in: Circle())
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("궁금한 걸 물어보세요", text: $input, axis: .vertical)
                .font(.app(.callout))
                .focused($isInputFocused)
                .lineLimit(1...4)
                .padding(.vertical, 8)
                .submitLabel(.send)
                .onSubmit { Task { await ask(trimmedInput) } }

            Button {
                Task { await ask(trimmedInput) }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(trimmedInput.isEmpty ? .appTextSecondary : .appOnInk)
                    .frame(width: 34, height: 34)
                    .background(trimmedInput.isEmpty ? Color.appLine : Color.appInk, in: Circle())
            }
            .disabled(trimmedInput.isEmpty || isAsking)
            .accessibilityLabel("보내기")
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(Color.appFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.appSurface)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                if isAsking {
                    proxy.scrollTo("typing", anchor: .bottom)
                } else if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Agent loop

    private enum AgentOutcome {
        case answer(String)
        case awaitingConfirmation
    }

    @MainActor
    private func ask(_ question: String) async {
        guard !question.isEmpty, !isAsking else { return }
        // 카드를 확인하지 않고 다른 질문을 하면 그 작업은 취소로 본다.
        if let action = pendingAction {
            closePending(action, state: .superseded, result: "사장님이 확인하지 않고 다른 말을 했어요. 저장하지 않았어요. 정정한 내용이면 새로 제안하세요.", isError: false, reply: "저장하지 않았어요.")
        }
        messages.append(Message(role: .user, content: question))
        input = ""

        // 버튼 대신 직접 입력했으면, 기다리던 도구 결과와 입력을 한 메시지로 보낸다.
        if let pending = pendingChoice {
            pendingChoice = nil
            history.append(["role": "user", "content": .array(pending.otherResults + [
                Self.toolResult(pending.toolUseId, "사장님이 버튼을 고르지 않고 직접 입력했어요. 아래 말을 보세요.", isError: false),
                ["type": "text", "text": .string(question)]
            ])])
            await continueAgent(rollbackTo: history, fallback: "답을 받지 못했어요. 다시 말해 주세요.")
            return
        }

        // 실패하면 이번 질문의 기록을 되돌려서, 다음 질문이 깨진 대화로 가지 않게 한다.
        let savedHistory = history
        trimHistory()
        history.append(["role": "user", "content": .string(question)])
        await continueAgent(rollbackTo: savedHistory, fallback: nil)
    }

    @MainActor
    private func choose(_ name: String) async {
        guard let pending = pendingChoice, !isAsking else { return }
        pendingChoice = nil
        if let index = messages.firstIndex(where: { $0.id == pending.messageId }) {
            messages[index].chosen = name
        }
        history.append(["role": "user", "content": .array(pending.otherResults + [
            Self.toolResult(pending.toolUseId, "\(pending.resultLabel): \(name)", isError: false)
        ])])
        await continueAgent(rollbackTo: history, fallback: "답을 받지 못했어요. 다시 말해 주세요.")
    }

    @MainActor
    private func continueAgent(rollbackTo savedHistory: [AnyJSON], fallback: String?) async {
        isAsking = true
        statusText = nil
        defer {
            isAsking = false
            statusText = nil
        }
        do {
            if case let .answer(text) = try await runAgent() {
                messages.append(Message(role: .assistant, content: text))
            }
        } catch {
            history = savedHistory
            if let fallback {
                // 저장은 끝났으니 대화가 이어지도록 짧은 답을 대신 남긴다.
                history.append(["role": "assistant", "content": .string(fallback)])
                messages.append(Message(role: .assistant, content: fallback))
            } else if error is IncompleteAnswer {
                messages.append(Message(role: .assistant, content: "확인할 게 많아서 답을 다 만들지 못했어요. 질문을 나눠서 물어봐 주세요."))
            } else if !AppErrorMessage.isCancellation(error) {
                messages.append(Message(role: .assistant, content: "답을 받지 못했어요. 잠시 후 다시 물어봐 주세요."))
            }
        }
    }

    @MainActor
    private func runAgent() async throws -> AgentOutcome {
        #if canImport(Supabase)
        let tools = OwnerAgentTools(storeId: storeId)
        for _ in 0..<Self.maxToolRounds {
            let response: AgentResponse = try await SupabaseManager.shared.client.functions.invoke(
                "owner-agent",
                options: FunctionInvokeOptions(body: AgentRequest(storeId: storeId, messages: history))
            )
            history.append(["role": "assistant", "content": .array(response.content)])

            let toolUses = response.content.compactMap { $0.objectValue }.filter { $0["type"]?.stringValue == "tool_use" }
            guard response.stop_reason == "tool_use", !toolUses.isEmpty else {
                if response.stop_reason == "refusal" {
                    return .answer("이 질문에는 답할 수 없어요.")
                }
                let text = Self.text(of: response.content)
                return .answer(text.isEmpty ? "답을 만들지 못했어요. 다시 물어봐 주세요." : text)
            }

            var results: [AnyJSON] = []
            var card: (message: Message, toolUseId: String, proposal: OwnerAgentProposal)?
            var choice: (message: Message, toolUseId: String, resultLabel: String)?
            for block in toolUses {
                guard let id = block["id"]?.stringValue, let name = block["name"]?.stringValue else { continue }
                statusText = Self.toolStatusText[name] ?? "확인하는 중"
                let input = block["input"]?.objectValue ?? [:]
                if name == "choose_worker" {
                    // 사장님 답을 기다리는 건 한 번에 하나만.
                    guard card == nil, choice == nil else {
                        results.append(Self.toolResult(id, "한 번에 하나씩만 물어볼 수 있어요.", isError: true))
                        continue
                    }
                    let names = (try? await tools.activeWorkerNames()) ?? []
                    guard !names.isEmpty else {
                        results.append(Self.toolResult(id, "등록된 알바가 없어요.", isError: true))
                        continue
                    }
                    let question = input["question"]?.stringValue ?? "누구인가요?"
                    choice = (Message(role: .assistant, content: question, choices: names), id, "사장님이 고른 알바")
                    continue
                }
                if name == "ask_choice" {
                    guard card == nil, choice == nil else {
                        results.append(Self.toolResult(id, "한 번에 하나씩만 물어볼 수 있어요.", isError: true))
                        continue
                    }
                    let options = (input["options"]?.arrayValue ?? [])
                        .compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    guard (2...4).contains(options.count), Set(options).count == options.count else {
                        results.append(Self.toolResult(id, "버튼은 서로 다른 2~4개로 주세요.", isError: true))
                        continue
                    }
                    let question = input["question"]?.stringValue ?? "어떻게 할까요?"
                    choice = (Message(role: .assistant, content: question, choices: options), id, "사장님이 고른 답")
                    continue
                }
                guard OwnerAgentTools.writeToolNames.contains(name) else {
                    let result = await tools.run(name: name, input: input)
                    results.append(Self.toolResult(id, result.text, isError: result.isError))
                    continue
                }
                // 확인은 한 번에 하나씩 받는다.
                guard card == nil, choice == nil else {
                    results.append(Self.toolResult(id, "확인은 한 번에 하나씩 받아요. 앞의 확인이 끝난 뒤 다시 제안하세요.", isError: true))
                    continue
                }
                do {
                    let proposal = try await tools.propose(name: name, input: input)
                    card = (Message(role: .assistant, content: proposal.title, proposal: proposal, selected: proposal.allItemIds), id, proposal)
                } catch let error as OwnerAgentTools.ToolError {
                    results.append(Self.toolResult(id, error.message, isError: true))
                } catch {
                    results.append(Self.toolResult(id, "확인 카드를 만들지 못했어요.", isError: true))
                }
            }

            if let choice {
                messages.append(choice.message)
                pendingChoice = PendingChoice(messageId: choice.message.id, toolUseId: choice.toolUseId, resultLabel: choice.resultLabel, otherResults: results)
                return .awaitingConfirmation
            }
            if let card {
                messages.append(card.message)
                pendingAction = PendingAction(messageId: card.message.id, toolUseId: card.toolUseId, proposal: card.proposal, otherResults: results)
                return .awaitingConfirmation
            }
            history.append(["role": "user", "content": .array(results)])
        }
        throw IncompleteAnswer()
        #else
        return .answer("")
        #endif
    }

    @MainActor
    private func confirmPending() async {
        guard let action = pendingAction, !isAsking else { return }
        let selected = messages.first(where: { $0.id == action.messageId })?.selected ?? []
        setProposalState(action.messageId, .saving)
        do {
            try await OwnerAgentTools(storeId: storeId).execute(action.proposal, selected: selected)
        } catch {
            closePending(action, state: .failed("저장하지 못했어요. 다시 요청해 주세요."), result: "저장에 실패했어요: \(AppErrorMessage.userMessage(error))", isError: true, reply: "저장하지 못했어요.")
            return
        }
        setProposalState(action.messageId, .saved)
        pendingAction = nil
        NotificationCenter.default.post(name: .payrollSettingsDidChange, object: nil)

        history.append(["role": "user", "content": .array(action.otherResults + [
            Self.toolResult(action.toolUseId, "사장님이 확인해서 저장했어요: \(action.proposal.summary(selected: selected))", isError: false)
        ])])
        await continueAgent(rollbackTo: history, fallback: "저장했어요.")
    }

    @MainActor
    private func cancelPending() async {
        guard let action = pendingAction, !isAsking else { return }
        closePending(action, state: .cancelled, result: "사장님이 취소했어요. 저장하지 않았어요.", isError: false, reply: "취소했어요.")
    }

    // 확인을 기다리던 도구 호출에 결과를 붙이고, 짧은 답으로 대화를 닫는다(모델은 다시 부르지 않는다).
    @MainActor
    private func closePending(_ action: PendingAction, state: ProposalState, result: String, isError: Bool, reply: String) {
        setProposalState(action.messageId, state)
        history.append(["role": "user", "content": .array(action.otherResults + [
            Self.toolResult(action.toolUseId, result, isError: isError)
        ])])
        history.append(["role": "assistant", "content": .string(reply)])
        pendingAction = nil
    }

    private func setProposalState(_ messageId: UUID, _ state: ProposalState) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        messages[index].proposalState = state
    }

    private static func toolResult(_ id: String, _ text: String, isError: Bool) -> AnyJSON {
        [
            "type": "tool_result",
            "tool_use_id": .string(id),
            "content": .string(text),
            "is_error": .bool(isError)
        ]
    }

    private static func text(of content: [AnyJSON]) -> String {
        content
            .compactMap { $0.objectValue }
            .filter { $0["type"]?.stringValue == "text" }
            .compactMap { $0["text"]?.stringValue }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // 오래된 대화를 앞에서부터 버린다. 도구 결과만 남지 않게 사장님 질문에서 끊는다.
    private func trimHistory() {
        while history.count > Self.maxHistoryCount {
            guard let next = history.indices.dropFirst().first(where: { index in
                let message = history[index].objectValue
                return message?["role"]?.stringValue == "user" && message?["content"]?.stringValue != nil
            }) else {
                history = []
                return
            }
            history.removeFirst(next)
        }
    }
}

// 버튼을 한 줄에 넣을 수 있는 만큼 넣고, 넘치면 다음 줄로 내린다.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
