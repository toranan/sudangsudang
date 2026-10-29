import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct WorkerStoreKnowledgeView: View {
    let storeId: UUID
    let storeName: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPanel: WorkerStoreKnowledgePanel
    @State private var documents: [WorkerStoreDocumentRow] = []
    @State private var viewingDocument: WorkerStoreDocumentRow?
    @State private var isLoading = false
    @State private var loadMessage: String?
    @State private var chatInput = ""
    @State private var isAsking = false
    @State private var chatMessages: [WorkerStoreChatMessage] = []
    @FocusState private var isChatInputFocused: Bool

    init(
        storeId: UUID,
        storeName: String,
        initialPanel: WorkerStoreKnowledgePanel = .notice
    ) {
        self.storeId = storeId
        self.storeName = storeName
        _selectedPanel = State(initialValue: initialPanel)
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            if !isChatOnly {
                panelPicker
            }

            Group {
                if isChatOnly {
                    chatPanel
                } else {
                    ScrollView {
                        documentPanel
                            .padding(.bottom, 32)
                    }
                    .appRefreshable {
                        await loadDocuments()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadDocuments()
        }
        .sheet(item: $viewingDocument) { document in
            documentDetailSheet(document)
        }
    }

    private var isChatOnly: Bool {
        selectedPanel == .chat
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.appTextPrimary)
                    .frame(width: 36, height: 36)
                    .background(Color.appSurface, in: Circle())
            }
            .buttonStyle(PressableRowStyle())

            VStack(alignment: .leading, spacing: 4) {
                Text(storeName)
                    .font(.app(.callout, .medium))
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(1)
                Text(isChatOnly ? "물어보기" : "가게 소식")
                    .font(.system(size: 26, weight: .heavy))
                    .tracking(-0.6)
                    .foregroundColor(.appTextPrimary)
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var panelPicker: some View {
        HStack(spacing: 2) {
            ForEach(WorkerStoreKnowledgePanel.documentCases) { panel in
                let isSelected = panel == selectedPanel
                Button(action: { selectedPanel = panel }) {
                    Text(panel.title)
                        .font(.app(.caption, .semibold))
                        .foregroundColor(isSelected ? .appOnInk : .appTextSecondary)
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
        .padding(.horizontal, 20)
    }

    private var documentPanel: some View {
        VStack(spacing: 12) {
            if let loadMessage {
                Text(loadMessage)
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }

            if isLoading && documents.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .appCard()
                    .padding(.horizontal, 20)
            } else if filteredDocuments.isEmpty {
                Text(selectedPanel.emptyText)
                    .font(.app(.callout, .medium))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard()
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredDocuments) { document in
                        Button(action: { viewingDocument = document }) {
                            documentRow(document)
                        }
                        .buttonStyle(PressableRowStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var chatPanel: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if chatMessages.isEmpty && !isAsking {
                            chatIntroView
                                .padding(.top, 38)
                                .padding(.bottom, 16)
                        }

                        ForEach(chatMessages) { message in
                            chatBubble(message)
                                .id(message.id)
                        }

                        if isAsking {
                            typingBubble
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture {
                    isChatInputFocused = false
                }
                .onChange(of: chatMessages.count) { _ in
                    scrollToLatestMessage(proxy)
                }
                .onChange(of: isAsking) { _ in
                    scrollToLatestMessage(proxy)
                }
            }

            HStack(spacing: 10) {
                TextField("메시지 입력", text: $chatInput, axis: .vertical)
                    .font(.app(.callout, .medium))
                    .focused($isChatInputFocused)
                    .lineLimit(1...4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .onSubmit { Task { await askQuestion() } }

                Button(action: { Task { await askQuestion() } }) {
                    ZStack {
                        if isAsking {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.appOnInk)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .appTextSecondary : .appOnInk)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .background(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAsking ? Color.appFill : Color.appInk)
                    .clipShape(Circle())
                }
                .disabled(isAsking || chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(Color.appBackground)
        }
        .frame(maxHeight: .infinity)
    }

    private var chatIntroView: some View {
        VStack(spacing: 14) {
            Image("wallet_mascot")
                .resizable()
                .scaledToFit()
                .frame(width: 108, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(spacing: 7) {
                Text("가게 매뉴얼 챗봇")
                    .font(.app(.headline, .bold))
                    .foregroundColor(.appTextPrimary)

                Text("공지와 매뉴얼에서 확인한 내용으로\n궁금한 점에 답변해요.")
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private func documentRow(_ document: WorkerStoreDocumentRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(document.kind.softColor)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: document.kind.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(document.kind.color)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(document.kind.title)
                        .font(.app(.caption, .bold))
                        .foregroundColor(document.kind.color)

                    if document.isPinned {
                        Text("· 상단 고정")
                            .font(.app(.caption, .semibold))
                            .foregroundColor(.appTextSecondary)
                    }

                    Spacer()
                }

                Text(document.title)
                    .font(.app(.body, .bold))
                    .foregroundColor(.appTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                Text(document.content.normalizedPreview(limit: 86))
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
        }
        .padding(18)
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }

    private func documentDetailSheet(_ document: WorkerStoreDocumentRow) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(document.kind.color)
                            .frame(width: 7, height: 7)
                        Text(document.kind.title)
                            .font(.app(.caption, .bold))
                            .foregroundColor(document.kind.color)

                        if document.isPinned {
                            Text("· 상단 고정")
                                .font(.app(.caption, .semibold))
                                .foregroundColor(.appTextSecondary)
                        }
                    }

                    Text(document.title)
                        .font(.system(size: 24, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundColor(.appTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(document.content)
                        .font(.app(.callout, .medium))
                        .foregroundColor(.appTextPrimary)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("문서 보기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        viewingDocument = nil
                    }
                }
            }
        }
    }

    private func chatBubble(_ message: WorkerStoreChatMessage) -> some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 54)
            }

            Text(message.content)
                .font(.app(.callout, .medium))
                .foregroundColor(message.role == .user ? .appOnInk : .appTextPrimary)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(message.role == .user ? Color.appInk : Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: 54)
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var typingBubble: some View {
        HStack {
            HStack(spacing: 5) {
                Circle()
                    .fill(Color.appTextSecondary.opacity(0.55))
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(Color.appTextSecondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(Color.appTextSecondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Spacer(minLength: 54)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filteredDocuments: [WorkerStoreDocumentRow] {
        sortedDocuments.filter { $0.kind.panel == selectedPanel }
    }

    private var sortedDocuments: [WorkerStoreDocumentRow] {
        documents.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return (lhs.updatedAt ?? lhs.createdAt ?? .distantPast) > (rhs.updatedAt ?? rhs.createdAt ?? .distantPast)
        }
    }

    private func scrollToLatestMessage(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                if isAsking {
                    proxy.scrollTo("typing", anchor: .bottom)
                } else if let lastMessage = chatMessages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }

    @MainActor
    private func loadDocuments() async {
        isLoading = true
        defer { isLoading = false }

        #if canImport(Supabase)
        do {
            let rows: [WorkerStoreDocumentRow] = try await SupabaseManager.shared
                .client
                .from("store_documents")
                .select()
                .eq("store_id", value: storeId.uuidString)
                .execute()
                .value
            documents = rows
            loadMessage = nil
        } catch {
            loadMessage = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func askQuestion() async {
        let question = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAsking else { return }

        chatMessages.append(WorkerStoreChatMessage(role: .user, content: question))
        chatInput = ""
        isAsking = true
        defer { isAsking = false }

        #if canImport(Supabase)
        do {
            let payload = WorkerStoreRagAskRequest(
                action: "ask",
                storeId: storeId,
                question: question
            )
            let response: WorkerStoreRagAskResponse = try await SupabaseManager.shared
                .client
                .functions
                .invoke(
                    "store-rag",
                    options: FunctionInvokeOptions(body: payload)
                )
            chatMessages.append(WorkerStoreChatMessage(role: .assistant, content: response.displayAnswer))
            return
        } catch {
            loadMessage = AppErrorMessage.userMessage(error)
        }
        #endif

        chatMessages.append(WorkerStoreChatMessage(role: .assistant, content: answerFromLoadedDocuments(for: question)))
    }

    private func answerFromLoadedDocuments(for question: String) -> String {
        guard !documents.isEmpty else {
            return "아직 확인할 수 있는 공지나 매뉴얼이 없어요."
        }

        let normalizedQuestion = question.lowercased()
        let tokens = normalizedQuestion
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
            .filter { !$0.isEmpty }
        let matches = sortedDocuments.compactMap { document -> WorkerStoreDocumentRow? in
            let haystack = "\(document.title) \(document.content)".lowercased()
            if haystack.contains(normalizedQuestion) {
                return document
            }
            return tokens.contains(where: { $0.count >= 2 && haystack.contains($0) }) ? document : nil
        }

        guard !matches.isEmpty else {
            return "등록된 문서에서 관련 내용을 찾지 못했어요."
        }

        return matches.prefix(3)
            .map { "- \($0.title)\n  \($0.content.normalizedPreview(limit: 120))" }
            .joined(separator: "\n\n")
    }
}

enum WorkerStoreKnowledgePanel: String, CaseIterable, Identifiable {
    case notice
    case manual
    case chat

    static let documentCases: [WorkerStoreKnowledgePanel] = [.notice, .manual]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notice: return "공지"
        case .manual: return "매뉴얼"
        case .chat: return "챗봇"
        }
    }

    var emptyText: String {
        switch self {
        case .notice: return "등록된 공지가 없어요."
        case .manual: return "등록된 매뉴얼이 없어요."
        case .chat: return ""
        }
    }
}

private enum WorkerStoreDocumentKind: String, Codable {
    case manual
    case notice

    var title: String {
        switch self {
        case .manual: return "매뉴얼"
        case .notice: return "공지"
        }
    }

    var panel: WorkerStoreKnowledgePanel {
        switch self {
        case .manual: return .manual
        case .notice: return .notice
        }
    }

    var icon: String {
        switch self {
        case .manual: return "book.closed.fill"
        case .notice: return "megaphone.fill"
        }
    }

    var color: Color {
        switch self {
        case .manual: return .appLavender
        case .notice: return .appAccent
        }
    }

    var softColor: Color {
        switch self {
        case .manual: return .appLavenderSoft
        case .notice: return .appAccentSoft
        }
    }
}

private struct WorkerStoreDocumentRow: Codable, Identifiable, Hashable {
    let id: UUID
    let storeId: UUID
    var title: String
    var content: String
    var documentType: String?
    var isPinnedValue: Bool?
    var createdAt: Date?
    var updatedAt: Date?

    var kind: WorkerStoreDocumentKind {
        WorkerStoreDocumentKind(rawValue: documentType ?? "") ?? .manual
    }

    var isPinned: Bool {
        isPinnedValue ?? false
    }

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case title
        case content
        case documentType = "document_type"
        case isPinnedValue = "is_pinned"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct WorkerStoreRagAskRequest: Encodable {
    let action: String
    let storeId: UUID
    let question: String
}

private struct WorkerStoreRagAskResponse: Decodable {
    struct Source: Decodable {
        let id: UUID
        let title: String
        let documentType: String?
        let similarity: Double?
    }

    let answer: String
    let sources: [Source]

    var displayAnswer: String {
        guard !sources.isEmpty else { return answer }
        let sourceTitles = sources
            .map(\.title)
            .reduce(into: [String]()) { result, title in
                if !result.contains(title) {
                    result.append(title)
                }
            }
        guard !sourceTitles.isEmpty else { return answer }
        return "\(answer)\n\n참고: \(sourceTitles.joined(separator: ", "))"
    }
}

private struct WorkerStoreChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let content: String
}

private extension String {
    func normalizedPreview(limit: Int) -> String {
        let collapsed = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count <= limit {
            return collapsed
        }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<endIndex]) + "..."
    }
}
