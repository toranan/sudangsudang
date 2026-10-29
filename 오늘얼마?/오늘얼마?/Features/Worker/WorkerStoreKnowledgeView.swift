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

            panelPicker

            ScrollView {
                documentPanel
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
        .sheet(item: $viewingDocument) { document in
            documentDetailSheet(document)
        }
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
                Text("가게 소식")
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
            ForEach(WorkerStoreKnowledgePanel.allCases) { panel in
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
}

enum WorkerStoreKnowledgePanel: String, CaseIterable, Identifiable {
    case notice
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notice: return "공지"
        case .manual: return "매뉴얼"
        }
    }

    var emptyText: String {
        switch self {
        case .notice: return "등록된 공지가 없어요."
        case .manual: return "등록된 매뉴얼이 없어요."
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
