import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct WorkerStoreKnowledgeView: View {
    let storeId: UUID
    let storeName: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPanel: WorkerStoreKnowledgePanel = .notice
    @State private var documents: [WorkerStoreDocumentRow] = []
    @State private var viewingDocument: WorkerStoreDocumentRow?
    @State private var isLoading = false
    @State private var loadMessage: String?
    @State private var chatInput = ""
    @State private var isAsking = false
    @State private var chatMessages: [WorkerStoreChatMessage] = []

    var body: some View {
        VStack(spacing: 18) {
            header
            panelPicker

            Group {
                if selectedPanel == .chat {
                    chatPanel
                } else {
                    ScrollView {
                        documentPanel
                            .padding(.bottom, 32)
                    }
                    .refreshable {
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

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.appTextPrimary)
                    .frame(width: 38, height: 38)
                    .background(Color.appSurface)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("가게 소식")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                Text(storeName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var panelPicker: some View {
        Picker("", selection: $selectedPanel) {
            ForEach(WorkerStoreKnowledgePanel.allCases) { panel in
                Text(panel.title).tag(panel)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }

    private var documentPanel: some View {
        VStack(spacing: 12) {
            if let loadMessage {
                Text(loadMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
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
                    .font(.system(size: 14, weight: .medium, design: .rounded))
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
                        .buttonStyle(.plain)
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
                .onChange(of: chatMessages.count) { _ in
                    scrollToLatestMessage(proxy)
                }
                .onChange(of: isAsking) { _ in
                    scrollToLatestMessage(proxy)
                }
            }

            Divider()
                .background(Color.appLine)

            HStack(spacing: 10) {
                TextField("메시지 입력", text: $chatInput, axis: .vertical)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.appSurface)
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.appLine, lineWidth: 1)
                    )
                    .onSubmit { Task { await askQuestion() } }

                Button(action: { Task { await askQuestion() } }) {
                    ZStack {
                        if isAsking {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 42, height: 42)
                    .background(chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.appLine : Color.appAccent)
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
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: Color.appAccent.opacity(0.14), radius: 16, x: 0, y: 8)

            VStack(spacing: 7) {
                Text("가게 매뉴얼 챗봇")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextPrimary)

                Text("공지와 매뉴얼에서 확인한 내용으로\n궁금한 점에 답변해요.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
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
            Image(systemName: document.kind.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(document.kind.color)
                .frame(width: 34, height: 34)
                .background(document.kind.color.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(document.kind.title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(document.kind.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(document.kind.color.opacity(0.1))
                        .cornerRadius(7)

                    if document.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.appAccent)
                    }

                    Spacer()
                }

                Text(document.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                Text(document.content.normalizedPreview(limit: 86))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(Color.appSurface)
        .cornerRadius(18)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
    }

    private func documentDetailSheet(_ document: WorkerStoreDocumentRow) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        Label(document.kind.title, systemImage: document.kind.icon)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(document.kind.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(document.kind.color.opacity(0.1))
                            .cornerRadius(9)

                        if document.isPinned {
                            Label("상단 고정", systemImage: "pin.fill")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.appAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.appAccent.opacity(0.1))
                                .cornerRadius(9)
                        }
                    }

                    Text(document.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.appTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(document.content)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
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
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(message.role == .user ? .white : .appTextPrimary)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(message.role == .user ? Color.appAccent : Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(message.role == .user ? Color.clear : Color.appLine, lineWidth: 1)
                )
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
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.appLine, lineWidth: 1)
            )

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

private enum WorkerStoreKnowledgePanel: String, CaseIterable, Identifiable {
    case notice
    case manual
    case chat

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
        case .manual: return .appAccent
        case .notice: return .appPositive
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
