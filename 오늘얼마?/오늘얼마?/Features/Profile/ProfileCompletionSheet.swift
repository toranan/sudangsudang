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
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Spacer()
                        if canDismissManually {
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.appTextPrimary)
                                    .frame(width: 40, height: 40)
                                    .background(Color.appFill)
                                    .clipShape(Circle())
                            }
                            .accessibilityLabel("닫기")
                            .disabled(isSaving)
                        }
                    }
                    .frame(minHeight: 40)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.title)
                            .font(.system(size: 24, weight: .heavy))
                            .tracking(-0.5)
                            .foregroundColor(.appTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(context.message)
                            .font(.app(.callout))
                            .foregroundColor(.appTextSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("표시 이름")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.appTextSecondary)
                            TextField("예: 홍길동", text: $name)
                                .textContentType(.name)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .appInputField()
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("전화번호")
                                .font(.system(size: 14, weight: .semibold))
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
                                .appInputField()
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.app(.caption, .medium))
                            .foregroundColor(.appWarning)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 6) {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.appOnInk)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(context.primaryActionTitle)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSaving || (context.requiresName && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))

                if context.showsSkip {
                    Button {
                        Task { await skip() }
                    } label: {
                        Text(context.skipTitle)
                            .font(.app(.callout, .semibold))
                            .foregroundColor(.appTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableRowStyle())
                    .disabled(isSaving)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Color.appSurface.ignoresSafeArea())
        .interactiveDismissDisabled(isSaving || !canDismissManually)
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
