import SwiftUI
#if canImport(Supabase)
import Supabase
#endif

struct StoreKnowledgeManagementView: View {
    let storeId: UUID
    let storeName: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: StoreDocumentFilter = .notice
    @State private var documents: [StoreDocumentRow] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var loadMessage: String?
    @State private var saveError: String?
    @State private var storageMode: StoreKnowledgeStorageMode = .local

    @State private var isPresentingEditor = false
    @State private var viewingDocument: StoreDocumentRow?
    @State private var editingDocument: StoreDocumentRow?
    @State private var draftKind: StoreDocumentKind = .manual
    @State private var draftTitle = ""
    @State private var draftContent = ""
    @State private var draftIsPinned = false


    var body: some View {
        VStack(spacing: 18) {
            header

            ScrollView {
                documentsPanel
                    .padding(.bottom, appTabBarReservedHeight + 24)
            }
            .appRefreshable {
                await loadDocuments()
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.appTextPrimary)
                    .frame(width: 40, height: 40)
                    .background(Color.appSurface)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("가게 관리")
                    .font(.system(size: 24, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundColor(.appTextPrimary)
                Text(storeName)
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if storageMode == .local {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.appCaution)
                        .frame(width: 7, height: 7)
                    Text("기기 저장")
                        .font(.app(.caption, .semibold))
                        .foregroundColor(.appCaution)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var documentsPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ActionTile(
                    title: "공지 등록",
                    subtitle: "이번 주 변경 사항",
                    systemImage: StoreDocumentKind.notice.icon,
                    tint: StoreDocumentKind.notice.color,
                    fill: StoreDocumentKind.notice.softColor
                ) {
                    openEditor(kind: .notice)
                }

                ActionTile(
                    title: "매뉴얼 추가",
                    subtitle: "오픈·마감 순서",
                    systemImage: StoreDocumentKind.manual.icon,
                    tint: StoreDocumentKind.manual.color,
                    fill: StoreDocumentKind.manual.softColor
                ) {
                    openEditor(kind: .manual)
                }
            }
            .padding(.horizontal, 20)

            HStack(alignment: .center) {
                Text("등록된 문서")
                    .font(.system(size: 19, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundColor(.appTextPrimary)
                Spacer()
                KnowledgeChipGroup(
                    options: StoreDocumentFilter.allCases,
                    selection: $selectedFilter,
                    title: \.title,
                    compact: true
                )
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)

            if let loadMessage {
                Text(loadMessage)
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
            }

            if isLoading && documents.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .appCard()
                    .padding(.horizontal, 20)
            } else if filteredDocuments.isEmpty {
                Text("등록된 문서가 없어요.")
                    .font(.app(.callout, .medium))
                    .foregroundColor(.appTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard()
                    .padding(.horizontal, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredDocuments.enumerated()), id: \.element.id) { index, document in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.appLine)
                                .frame(height: 1)
                        }
                        documentRow(document)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 4)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                .padding(.horizontal, 20)
            }
        }
    }

    private var canSaveDraft: Bool {
        !isSaving
            && !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // 문서 추가/수정: 흰 전체 화면, 종류 타일, 밑줄 제목, 회색 본문, 하단 고정 버튼.
    private var editorSheet: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Button(action: { isPresentingEditor = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.appTextPrimary)
                                .frame(width: 40, height: 40)
                                .background(Color.appFill)
                                .clipShape(Circle())
                        }
                        .accessibilityLabel("닫기")

                        Spacer()

                        if storageMode == .local {
                            Text("이 기기에 저장돼요")
                                .font(.app(.callout, .semibold))
                                .foregroundColor(.appTextSecondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(editingDocument == nil ? "어떤 문서를 올릴까요?" : "문서를 수정할게요")
                            .font(.system(size: 26, weight: .heavy))
                            .tracking(-0.6)
                            .foregroundColor(.appTextPrimary)
                        Text("올려두면 직원이 물어볼 때 챗봇이 이 문서를 보고 답해요.")
                            .font(.app(.callout))
                            .foregroundColor(.appTextSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        ForEach(StoreDocumentKind.allCases) { kind in
                            kindTile(kind)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("제목")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.appTextSecondary)
                        TextField("예: 마감 순서", text: $draftTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.appTextPrimary)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(Color.appLine)
                                    .frame(height: 1.5)
                            }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("내용")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.appTextSecondary)
                        TextEditor(text: $draftContent)
                            .font(.system(size: 16))
                            .lineSpacing(5)
                            .foregroundColor(.appTextPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 220)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .overlay(alignment: .topLeading) {
                                if draftContent.isEmpty {
                                    Text("예: 1. 22시에 주문 마감\n2. 커피머신 세척 후 전원 끄기")
                                        .font(.system(size: 16))
                                        .lineSpacing(5)
                                        .foregroundColor(.appTextSecondary.opacity(0.6))
                                        .padding(.horizontal, 17)
                                        .padding(.vertical, 18)
                                        .allowsHitTesting(false)
                                }
                            }
                            .background(Color.appFill)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        Button(action: { draftIsPinned.toggle() }) {
                            HStack(spacing: 6) {
                                Image(systemName: draftIsPinned ? "pin.fill" : "pin")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("상단 고정")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(draftIsPinned ? .appOnInk : .appTextPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(draftIsPinned ? Color.appInk : Color.appFill)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(PressableRowStyle())
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.appAccent)
                            .padding(.top, 1)
                        Text("직원이 \"마감은 몇 시에 해요?\"라고 물으면 **이 문서를 근거로** 답해요.")
                            .font(.system(size: 13))
                            .foregroundColor(.appTextSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            if let saveError {
                Text(saveError)
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appWarning)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            Button(action: { Task { await saveDraft() } }) {
                Text(isSaving ? "저장 중" : (editingDocument == nil ? "등록하기" : "저장하기"))
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSaveDraft)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color.appSurface)
        }
        .background(Color.appSurface.ignoresSafeArea())
    }

    private func kindTile(_ kind: StoreDocumentKind) -> some View {
        let isSelected = draftKind == kind
        return Button(action: { draftKind = kind }) {
            HStack(spacing: 10) {
                Image(systemName: kind.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isSelected ? .appAccent : .appTextSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.appTextPrimary)
                    Text(kind.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.appTextSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.appAccentSoft : Color.appFill)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? Color.appAccent : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableRowStyle())
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(document.kind.color)
                    .frame(width: 40, height: 40)
                    .background(document.kind.softColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(document.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.appTextPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)

                        Button {
                            Task { await togglePinned(document) }
                        } label: {
                            Image(systemName: document.isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(document.isPinned ? .appAccent : .appTextSecondary.opacity(0.7))
                                .frame(width: 28, height: 24)
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
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.appTextSecondary)
                                .frame(width: 28, height: 24)
                        }
                    }

                    Text(document.content.normalizedPreview(limit: 86))
                        .font(.app(.caption))
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)

                    if let dateText = formattedDate(document.updatedAt ?? document.createdAt) {
                        Text(dateText)
                            .font(.system(size: 12))
                            .foregroundColor(.appTextSecondary.opacity(0.8))
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(PressableRowStyle())
    }

    private func documentDetailSheet(_ document: StoreDocumentRow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button(action: { viewingDocument = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.appTextPrimary)
                            .frame(width: 40, height: 40)
                            .background(Color.appFill)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("닫기")

                    Spacer()

                    Button(action: {
                        viewingDocument = nil
                        openEditor(document)
                    }) {
                        Label("수정", systemImage: "pencil")
                            .labelStyle(AppButtonLabelStyle())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.appTextPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.appFill)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PressableRowStyle())
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(document.kind.color)
                                .frame(width: 7, height: 7)
                            Text(document.kind.title)
                                .font(.app(.caption, .semibold))
                                .foregroundColor(document.kind.color)
                        }

                        if document.isPinned {
                            HStack(spacing: 4) {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("상단 고정")
                                    .font(.app(.caption, .semibold))
                            }
                            .foregroundColor(.appTextSecondary)
                        }
                    }

                    Text(document.title)
                        .font(.system(size: 26, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundColor(.appTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let dateText = formattedDate(document.updatedAt ?? document.createdAt) {
                        Text(dateText)
                            .font(.app(.caption, .medium))
                            .foregroundColor(.appTextSecondary)
                    }
                }

                Text(document.content)
                    .font(.system(size: 16))
                    .foregroundColor(.appTextPrimary)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color.appFill)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .background(Color.appSurface.ignoresSafeArea())
    }

    private func openEditor(_ document: StoreDocumentRow? = nil, kind: StoreDocumentKind = .notice) {
        editingDocument = document
        draftKind = document?.kind ?? kind
        draftTitle = document?.title ?? ""
        draftContent = document?.content ?? ""
        draftIsPinned = document?.isPinned ?? false
        saveError = nil
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
                saveError = nil
                isPresentingEditor = false
                return
            } catch {
                // 서버 저장이 실패했는데 이 기기에만 남기면 알바생은 못 보니, 편집 화면을 그대로 두고 알린다.
                saveError = "저장하지 못했어요. 잠시 후 다시 시도해주세요."
                return
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
                return
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
                return
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
        let formatter = AppTime.displayFormatter("M월 d일 HH:mm")
        return formatter.string(from: date)
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

    var subtitle: String {
        switch self {
        case .manual: return "오픈·마감 순서, 레시피"
        case .notice: return "이번 주 변경 사항"
        }
    }

    var color: Color {
        switch self {
        case .manual: return .appAccent
        case .notice: return .appLavender
        }
    }

    var softColor: Color {
        switch self {
        case .manual: return .appAccentSoft
        case .notice: return .appLavenderSoft
        }
    }
}

// 세그먼트 대신 쓰는 알약 칩 묶음. 선택된 칩만 검정으로 채운다.
private struct KnowledgeChipGroup<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var compact = false

    init(options: [Option], selection: Binding<Option>, title: KeyPath<Option, String>, compact: Bool = false) {
        self.options = options
        self._selection = selection
        self.title = { $0[keyPath: title] }
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button(action: {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option }
                }) {
                    Text(title(option))
                        .font(.system(size: compact ? 13 : 14, weight: .semibold))
                        .foregroundColor(isSelected ? .appOnInk : .appTextSecondary)
                        .padding(.horizontal, compact ? 12 : 0)
                        .frame(maxWidth: compact ? nil : .infinity)
                        .padding(.vertical, compact ? 7 : 9)
                        .background(isSelected ? Color.appInk : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(compact ? Color.appFill : Color.appSurface)
        .clipShape(Capsule())
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
