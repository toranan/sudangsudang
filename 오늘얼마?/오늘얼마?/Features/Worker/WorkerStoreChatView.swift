import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct StoreChatTarget: Identifiable, Hashable {
    let id: UUID
    let name: String
}

// 알바생용 매장 챗봇. 사장님이 올린 공지·매뉴얼을 근거로 답한다.
// 탭바에 가리지 않도록 전체 화면으로 띄우고, 입력칸은 아래에 고정한다.
struct WorkerStoreChatView: View {
    let storeId: UUID
    let storeName: String

    private struct Message: Identifiable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        let content: String
        var sources: [String] = []
    }

    private struct AskRequest: Encodable {
        let action: String
        let storeId: UUID
        let question: String
    }

    private struct AskResponse: Decodable {
        struct Source: Decodable {
            let title: String
        }
        let answer: String
        let sources: [Source]
    }

    private struct DocumentRow: Decodable {
        let title: String
        let content: String
    }

    private static let suggestions = [
        "마감은 어떻게 해요?",
        "이번 주 공지 있어요?",
        "포스 정산 방법 알려줘"
    ]

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [Message] = []
    @State private var input = ""
    @State private var isAsking = false
    @State private var documents: [DocumentRow] = []
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
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _ in scrollToBottom(proxy) }
                .onChange(of: isAsking) { _ in scrollToBottom(proxy) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            inputBar
        }
        .background(Color.appSurface.ignoresSafeArea())
        .task {
            await loadDocuments()
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        ZStack {
            VStack(spacing: 1) {
                Text("물어보기")
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
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            assistantMark(size: 40)
            VStack(alignment: .leading, spacing: 6) {
                Text("무엇이든 물어보세요")
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundColor(.appTextPrimary)
                Text("사장님이 올린 공지와 매뉴얼을 보고 답해요.")
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
                VStack(alignment: .leading, spacing: 10) {
                    Text(message.content)
                        .font(.app(.callout))
                        .foregroundColor(.appTextPrimary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if !message.sources.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(message.sources, id: \.self) { title in
                                Label(title, systemImage: "doc.text")
                                    .labelStyle(AppButtonLabelStyle())
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.appTextSecondary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.appFill, in: Capsule())
                            }
                        }
                    }
                }
                Spacer(minLength: 24)
            }
        }
    }

    private var typingRow: some View {
        HStack(spacing: 10) {
            assistantMark(size: 28)
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.appTextSecondary)
                .symbolEffect(.variableColor.iterative, options: .repeating)
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

    // MARK: - Data

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

    @MainActor
    private func loadDocuments() async {
        #if canImport(Supabase)
        documents = (try? await SupabaseManager.shared.client
            .from("store_documents")
            .select("title,content")
            .eq("store_id", value: storeId.uuidString)
            .execute()
            .value) ?? []
        #endif
    }

    @MainActor
    private func ask(_ question: String) async {
        guard !question.isEmpty, !isAsking else { return }
        messages.append(Message(role: .user, content: question))
        input = ""
        isAsking = true
        defer { isAsking = false }

        #if canImport(Supabase)
        do {
            let response: AskResponse = try await SupabaseManager.shared.client.functions.invoke(
                "store-rag",
                options: FunctionInvokeOptions(body: AskRequest(action: "ask", storeId: storeId, question: question))
            )
            var titles: [String] = []
            for source in response.sources where !titles.contains(source.title) {
                titles.append(source.title)
            }
            messages.append(Message(role: .assistant, content: response.answer, sources: Array(titles.prefix(3))))
            return
        } catch {
            // 서버 답변이 안 되면 불러온 문서에서 직접 찾아본다.
        }
        #endif

        messages.append(localAnswer(for: question))
    }

    private func localAnswer(for question: String) -> Message {
        guard !documents.isEmpty else {
            return Message(role: .assistant, content: "아직 등록된 공지나 매뉴얼이 없어요. 사장님께 직접 물어봐 주세요.")
        }
        let normalized = question.lowercased()
        let tokens = normalized
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
            .filter { $0.count >= 2 }
        let matches = documents.filter { document in
            let haystack = "\(document.title) \(document.content)".lowercased()
            return haystack.contains(normalized) || tokens.contains(where: haystack.contains)
        }
        guard let first = matches.first else {
            return Message(role: .assistant, content: "등록된 문서에서 관련 내용을 찾지 못했어요.")
        }
        let preview = first.content.count > 160 ? String(first.content.prefix(160)) + "…" : first.content
        return Message(role: .assistant, content: preview, sources: matches.prefix(3).map(\.title))
    }
}
