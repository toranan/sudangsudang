import SwiftUI

struct ProfileCompletionSheet: View {
    struct Context {
        let title: String
        let message: String
        let primaryActionTitle: String
        let showsSkip: Bool
        let skipTitle: String
        let requiresName: Bool

        init(
            title: String,
            message: String,
            primaryActionTitle: String = "저장",
            showsSkip: Bool = true,
            skipTitle: String = "건너뛰기",
            requiresName: Bool = false
        ) {
            self.title = title
            self.message = message
            self.primaryActionTitle = primaryActionTitle
            self.showsSkip = showsSkip
            self.skipTitle = skipTitle
            self.requiresName = requiresName
        }
    }

    @Environment(\.dismiss) private var dismiss

    let context: Context
    let initialName: String
    let initialPhone: String
    let onSave: (String?, String?) -> Void
    let onSkip: (() -> Void)?

    @State private var name: String
    @State private var phone: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        context: Context,
        initialName: String = "",
        initialPhone: String = "",
        onSave: @escaping (String?, String?) -> Void,
        onSkip: (() -> Void)? = nil
    ) {
        self.context = context
        self.initialName = initialName
        self.initialPhone = initialPhone
        self.onSave = onSave
        self.onSkip = onSkip
        _name = State(initialValue: initialName)
        _phone = State(initialValue: initialPhone)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(context.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextPrimary)

                Text(context.message)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.appTextSecondary)

                VStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("표시 이름")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        TextField("예: 홍길동", text: $name)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(12)
                            .background(Color.appSurface)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("전화번호")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.appTextSecondary)
                        TextField("010-1234-5678", text: $phone)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .onChange(of: phone) { newValue in
                                let formatted = formatPhone(newValue)
                                if formatted != newValue {
                                    phone = formatted
                                }
                            }
                            .padding(12)
                            .background(Color.appSurface)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.appLine, lineWidth: 1)
                            )
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appWarning)
                }

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(context.primaryActionTitle)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving || (context.requiresName && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                .opacity((isSaving || (context.requiresName && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)) ? 0.7 : 1.0)

                if context.showsSkip {
                    Button {
                        Task { await skip() }
                    } label: {
                        Text(context.skipTitle)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(isSaving)
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canDismissManually {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { dismiss() }
                            .disabled(isSaving)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving || !canDismissManually)
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var canDismissManually: Bool {
        !(context.requiresName && !context.showsSkip)
    }

    @MainActor
    private func save() async {
        if context.requiresName && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "표시 이름을 입력해주세요."
            return
        }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveName = trimmedName.isEmpty ? nil : trimmedName
        let effectivePhone = trimmedPhone.isEmpty ? nil : trimmedPhone
        #if DEBUG
        print("DEBUG: ProfileCompletionSheet save tapped. name=\(effectiveName ?? "nil") phone=\(effectivePhone ?? "nil")")
        #endif
        onSave(effectiveName, effectivePhone)
        #if DEBUG
        print("DEBUG: ProfileCompletionSheet save finished.")
        #endif
        dismiss()
    }

    @MainActor
    private func skip() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        if let onSkip {
            onSkip()
        }
        dismiss()
    }

    private func formatPhone(_ value: String) -> String {
        let digits = value.filter { $0.isNumber }
        let prefix = digits.prefix(11)
        let count = prefix.count

        if count <= 3 {
            return String(prefix)
        } else if count <= 7 {
            let a = prefix.prefix(3)
            let b = prefix.dropFirst(3)
            return "\(a)-\(b)"
        } else {
            let a = prefix.prefix(3)
            let b = prefix.dropFirst(3).prefix(4)
            let c = prefix.dropFirst(7)
            return "\(a)-\(b)-\(c)"
        }
    }
}
