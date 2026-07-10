import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct StoreKnowledgeManagementView: View {
    let storeId: UUID
    let storeName: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPanel: StoreKnowledgePanel = .documents
    @State private var selectedFilter: StoreDocumentFilter = .notice
    @State private var documents: [StoreDocumentRow] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var loadMessage: String?
    @State private var storageMode: StoreKnowledgeStorageMode = .local

    @State private var isPresentingEditor = false
    @State private var viewingDocument: StoreDocumentRow?
    @State private var editingDocument: StoreDocumentRow?
    @State private var draftKind: StoreDocumentKind = .manual
    @State private var draftTitle = ""
    @State private var draftContent = ""
    @State private var draftIsPinned = false

    @State private var chatInput = ""
    @State private var isAsking = false
    @State private var chatMessages: [StoreKnowledgeChatMessage] = []

    var body: some View {
        VStack(spacing: 18) {
            header
            panelPicker

            Group {
                if selectedPanel == .documents {
                    ScrollView {
                        documentsPanel
                            .padding(.bottom, 32)
                    }
                    .refreshable {
                        await loadDocuments()
                    }
                } else {
                    chatPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await loadDocuments()
        }
        .sheet(isPresented: $isPresentingEditor) {
            editorSheet
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
                Text("가게 관리")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextPrimary)
                Text(storeName)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if storageMode == .local {
                StatusPill(text: "기기 저장", color: .appWarning)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var panelPicker: some View {
        Picker("", selection: $selectedPanel) {
            ForEach(StoreKnowledgePanel.allCases) { panel in
                Text(panel.title).tag(panel)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }

    private var documentsPanel: some View {
        VStack(spacing: 14) {
            SectionHeader(title: "등록된 문서")
                .padding(.horizontal, 20)

            HStack(spacing: 10) {
                Button(action: { openEditor(kind: .notice) }) {
                    Label("공지 등록", systemImage: "megaphone.fill")
                }
                .buttonStyle(PrimaryButtonStyle(backgroundColor: .appPositive))

                Button(action: { openEditor(kind: .manual) }) {
                    Label("매뉴얼 추가", systemImage: "book.closed.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 20)

            Picker("", selection: $selectedFilter) {
                ForEach(StoreDocumentFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

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
                Text("등록된 문서가 없어요.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard()
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredDocuments) { document in
                        documentRow(document)
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
                Text("오늘얼마 매뉴얼 챗봇")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextPrimary)

                Text("등록한 공지와 매뉴얼을 기준으로\n직원 질문에 바로 답변해요.")
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

    private var editorSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("", selection: $draftKind) {
                        ForEach(StoreDocumentKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("제목")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        TextField("예: 포스기 마감 방법", text: $draftTitle)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .padding(14)
                            .background(Color.appSurface)
                            .cornerRadius(14)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("내용")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        TextEditor(text: $draftContent)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .frame(minHeight: 260)
                            .padding(10)
                            .scrollContentBackground(.hidden)
                            .background(Color.appSurface)
                            .cornerRadius(14)
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(editingDocument == nil ? "문서 추가" : "문서 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        isPresentingEditor = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "저장 중" : "저장") {
                        Task { await saveDraft() }
                    }
                    .disabled(isSaving || draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var filteredDocuments: [StoreDocumentRow] {
        sortedDocuments.filter { document in
            selectedFilter.includes(document.kind)
        }
    }

    private var sortedDocuments: [StoreDocumentRow] {
        documents.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return (lhs.updatedAt ?? lhs.createdAt ?? .distantPast) > (rhs.updatedAt ?? rhs.createdAt ?? .distantPast)
        }
    }

    private func documentRow(_ document: StoreDocumentRow) -> some View {
        Button(action: { viewingDocument = document }) {
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

                        Spacer()

                        Button {
                            Task { await togglePinned(document) }
                        } label: {
                            Image(systemName: document.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(document.isPinned ? .appAccent : .appTextSecondary)
                                .frame(width: 30, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button {
                                viewingDocument = nil
                                openEditor(document)
                            } label: {
                                Label("수정", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                Task { await deleteDocument(document) }
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.appTextSecondary)
                                .frame(width: 30, height: 26)
                        }
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

                    if let dateText = formattedDate(document.updatedAt ?? document.createdAt) {
                        Text(dateText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                    }
                }
            }
            .padding(16)
            .background(Color.appSurface)
            .cornerRadius(18)
            .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func documentDetailSheet(_ document: StoreDocumentRow) -> some View {
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

                    VStack(alignment: .leading, spacing: 8) {
                        Text(document.title)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.appTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let dateText = formattedDate(document.updatedAt ?? document.createdAt) {
                            Text(dateText)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.appTextSecondary)
                        }
                    }

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

                ToolbarItem(placement: .confirmationAction) {
                    Button("수정") {
                        viewingDocument = nil
                        openEditor(document)
                    }
                }
            }
        }
    }

    private func chatBubble(_ message: StoreKnowledgeChatMessage) -> some View {
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
                .clipShape(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
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

    private func openEditor(_ document: StoreDocumentRow? = nil, kind: StoreDocumentKind = .notice) {
        editingDocument = document
        draftKind = document?.kind ?? kind
        draftTitle = document?.title ?? ""
        draftContent = document?.content ?? ""
        draftIsPinned = document?.isPinned ?? false
        isPresentingEditor = true
    }

    @MainActor
    private func loadDocuments() async {
        isLoading = true
        defer { isLoading = false }

        #if canImport(Supabase)
        do {
            let rows: [StoreDocumentRow] = try await SupabaseManager.shared
                .client
                .from("store_documents")
                .select()
                .eq("store_id", value: storeId.uuidString)
                .execute()
                .value
            documents = rows
            storageMode = .cloud
            loadMessage = nil
            return
        } catch {
            storageMode = .local
            loadMessage = "서버 문서함에 연결되지 않아 이 기기에 저장돼요."
        }
        #endif

        documents = loadLocalDocuments()
    }

    @MainActor
    private func saveDraft() async {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = draftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !content.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        if storageMode == .cloud {
            #if canImport(Supabase)
            do {
                let payload = StoreRagIndexRequest(
                    action: "index",
                    id: editingDocument?.id,
                    storeId: storeId,
                    title: title,
                    content: content,
                    documentType: draftKind.rawValue,
                    isPinned: draftIsPinned
                )
                let response: StoreRagIndexResponse = try await SupabaseManager.shared
                    .client
                    .functions
                    .invoke(
                        "store-rag",
                        options: FunctionInvokeOptions(body: payload)
                    )
                replaceDocument(response.document)
                loadMessage = nil
                isPresentingEditor = false
                return
            } catch {
                loadMessage = AppErrorMessage.userMessage(error)
            }
            #endif
        }

        let now = Date()
        if let editingDocument {
            let updated = StoreDocumentRow(
                id: editingDocument.id,
                storeId: storeId,
                title: title,
                content: content,
                documentType: draftKind.rawValue,
                isPinnedValue: draftIsPinned,
                createdAt: editingDocument.createdAt,
                updatedAt: now
            )
            replaceDocument(updated)
        } else {
            documents.append(
                StoreDocumentRow(
                    id: UUID(),
                    storeId: storeId,
                    title: title,
                    content: content,
                    documentType: draftKind.rawValue,
                    isPinnedValue: draftIsPinned,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
        saveLocalDocuments()
        isPresentingEditor = false
    }

    @MainActor
    private func deleteDocument(_ document: StoreDocumentRow) async {
        if storageMode == .cloud {
            #if canImport(Supabase)
            do {
                _ = try await SupabaseManager.shared
                    .client
                    .from("store_documents")
                    .delete()
                    .eq("id", value: document.id.uuidString)
                    .execute()
                documents.removeAll { $0.id == document.id }
                loadMessage = nil
                return
            } catch {
                loadMessage = AppErrorMessage.userMessage(error)
            }
            #endif
        }

        documents.removeAll { $0.id == document.id }
        saveLocalDocuments()
    }

    @MainActor
    private func togglePinned(_ document: StoreDocumentRow) async {
        let nextValue = !document.isPinned

        if storageMode == .cloud {
            #if canImport(Supabase)
            do {
                let payload = StoreDocumentPinPayload(is_pinned: nextValue)
                let updated: StoreDocumentRow = try await SupabaseManager.shared
                    .client
                    .from("store_documents")
                    .update(payload)
                    .eq("id", value: document.id.uuidString)
                    .select()
                    .single()
                    .execute()
                    .value
                replaceDocument(updated)
                loadMessage = nil
                return
            } catch {
                loadMessage = AppErrorMessage.userMessage(error)
            }
            #endif
        }

        var updated = document
        updated.isPinnedValue = nextValue
        updated.updatedAt = Date()
        replaceDocument(updated)
        saveLocalDocuments()
    }

    @MainActor
    private func askQuestion() async {
        let question = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAsking else { return }

        chatMessages.append(StoreKnowledgeChatMessage(role: .user, content: question))
        chatInput = ""
        isAsking = true
        defer { isAsking = false }

        if storageMode == .cloud {
            #if canImport(Supabase)
            do {
                let payload = StoreRagAskRequest(
                    action: "ask",
                    storeId: storeId,
                    question: question
                )
                let response: StoreRagAskResponse = try await SupabaseManager.shared
                    .client
                    .functions
                    .invoke(
                        "store-rag",
                        options: FunctionInvokeOptions(body: payload)
                    )
                chatMessages.append(StoreKnowledgeChatMessage(role: .assistant, content: response.displayAnswer))
                return
            } catch {
                loadMessage = AppErrorMessage.userMessage(error)
            }
            #endif
        }

        chatMessages.append(StoreKnowledgeChatMessage(role: .assistant, content: answer(for: question)))
    }

    private func answer(for question: String) -> String {
        guard !documents.isEmpty else {
            return "등록된 매뉴얼이나 공지가 아직 없어요."
        }

        let tokens = searchTokens(question)
        let normalizedQuestion = question.lowercased()
        let matches = sortedDocuments.compactMap { document -> StoreKnowledgeMatch? in
            let haystack = "\(document.title) \(document.content)".lowercased()
            var score = haystack.contains(normalizedQuestion) ? 100 : 0
            for token in tokens where token.count >= 2 {
                if haystack.contains(token) {
                    score += max(2, token.count)
                }
            }
            guard score > 0 else { return nil }
            return StoreKnowledgeMatch(document: document, score: score, snippet: snippet(from: document, tokens: tokens, query: normalizedQuestion))
        }
        .sorted { $0.score > $1.score }

        guard !matches.isEmpty else {
            return "등록된 문서에서 관련 내용을 찾지 못했어요."
        }

        let sourceLines = matches.prefix(3).map { match in
            "- \(match.document.title)\n  \(match.snippet)"
        }
        return "문서에서 확인한 내용이에요.\n\n\(sourceLines.joined(separator: "\n\n"))"
    }

    private func searchTokens(_ text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        return text
            .lowercased()
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func snippet(from document: StoreDocumentRow, tokens: [String], query: String) -> String {
        let candidates = document.content
            .components(separatedBy: CharacterSet(charactersIn: "\n.。!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let exact = candidates.first(where: { $0.lowercased().contains(query) }) {
            return exact.normalizedPreview(limit: 120)
        }

        for token in tokens where token.count >= 2 {
            if let hit = candidates.first(where: { $0.lowercased().contains(token) }) {
                return hit.normalizedPreview(limit: 120)
            }
        }

        return document.content.normalizedPreview(limit: 120)
    }

    private func replaceDocument(_ document: StoreDocumentRow) {
        if let index = documents.firstIndex(where: { $0.id == document.id }) {
            documents[index] = document
        } else {
            documents.append(document)
        }
    }

    private func loadLocalDocuments() -> [StoreDocumentRow] {
        guard let data = UserDefaults.standard.data(forKey: localStorageKey),
              let rows = try? JSONDecoder().decode([StoreDocumentRow].self, from: data) else {
            return []
        }
        return rows
    }

    private func saveLocalDocuments() {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        UserDefaults.standard.set(data, forKey: localStorageKey)
    }

    private var localStorageKey: String {
        "store_documents.\(storeId.uuidString)"
    }

    private func formattedDate(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 HH:mm"
        return formatter.string(from: date)
    }
}

private enum StoreKnowledgePanel: String, CaseIterable, Identifiable {
    case documents
    case chat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .documents: return "문서"
        case .chat: return "챗봇"
        }
    }
}

private enum StoreDocumentFilter: String, CaseIterable, Identifiable {
    case notice
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "매뉴얼"
        case .notice: return "공지"
        }
    }

    func includes(_ kind: StoreDocumentKind) -> Bool {
        switch self {
        case .manual: return kind == .manual
        case .notice: return kind == .notice
        }
    }
}

private enum StoreDocumentKind: String, Codable, CaseIterable, Identifiable {
    case manual
    case notice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "매뉴얼"
        case .notice: return "공지"
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

private enum StoreKnowledgeStorageMode {
    case cloud
    case local
}

private struct StoreDocumentRow: Codable, Identifiable, Hashable {
    let id: UUID
    let storeId: UUID
    var title: String
    var content: String
    var documentType: String?
    var isPinnedValue: Bool?
    var createdAt: Date?
    var updatedAt: Date?

    var kind: StoreDocumentKind {
        StoreDocumentKind(rawValue: documentType ?? "") ?? .manual
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

private struct StoreRagIndexRequest: Encodable {
    let action: String
    let id: UUID?
    let storeId: UUID
    let title: String
    let content: String
    let documentType: String
    let isPinned: Bool
}

private struct StoreDocumentPinPayload: Encodable {
    let is_pinned: Bool
}

private struct StoreRagIndexResponse: Decodable {
    let document: StoreDocumentRow
}

private struct StoreRagAskRequest: Encodable {
    let action: String
    let storeId: UUID
    let question: String
}

private struct StoreRagAskResponse: Decodable {
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

private struct StoreKnowledgeChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let content: String
}

private struct StoreKnowledgeMatch {
    let document: StoreDocumentRow
    let score: Int
    let snippet: String
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
