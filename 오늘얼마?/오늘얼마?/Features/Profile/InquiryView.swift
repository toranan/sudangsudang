import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Supabase)
import Supabase
#endif

// 사장님·알바생 공통 '문의하기'. inquiries 테이블에 바로 넣고, 운영자는 Supabase 대시보드에서 본다.
struct InquiryView: View {
    let role: String

    private struct InquiryInsert: Encodable {
        let user_id: UUID
        let category: String
        let message: String
        let role: String
        let contact: String?
        let app_version: String
        let device: String
    }

    private static let categories: [(value: String, title: String)] = [
        ("오류 신고", "오류 신고"),
        ("기능 제안", "기능 제안"),
        ("기타", "기타")
    ]

    @Environment(\.dismiss) private var dismiss
    @State private var category = "오류 신고"
    @State private var message = ""
    @State private var contact = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var errorMessage: String?
    @FocusState private var isMessageFocused: Bool

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if didSend {
                    sentState
                } else {
                    form
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, appTabBarReservedHeight + 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("문의하기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("불편한 점이나 바라는 기능을 남겨주세요. 바로 확인할게요.")
                .font(.app(.callout))
                .foregroundColor(.appTextSecondary)
                .padding(.horizontal, 4)

            ChoiceChips(options: Self.categories, selected: category) { category = $0 }

            VStack(alignment: .leading, spacing: 6) {
                Text("내용")
                    .font(.app(.caption, .semibold))
                    .foregroundColor(.appTextSecondary)
                    .padding(.horizontal, 4)
                TextEditor(text: $message)
                    .font(.app(.body))
                    .focused($isMessageFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .padding(10)
                    .background(Color.appSurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.field, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("예: 출근 버튼을 눌렀는데 기록이 안 남아요")
                                .font(.app(.body))
                                .foregroundColor(.appTextSecondary.opacity(0.6))
                                .padding(.horizontal, 15)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("답변 받을 연락처 (선택)")
                    .font(.app(.caption, .semibold))
                    .foregroundColor(.appTextSecondary)
                    .padding(.horizontal, 4)
                TextField("이메일 또는 전화번호", text: $contact)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .appInputField()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appWarning)
                    .padding(.horizontal, 4)
            }

            Button {
                Task { await send() }
            } label: {
                Text(isSending ? "보내는 중..." : "보내기")
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(trimmedMessage.isEmpty || isSending)
            .opacity(trimmedMessage.isEmpty ? 0.5 : 1)
        }
    }

    private var sentState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.appAccent)
                .frame(width: 40, height: 40)
                .background(Color.appAccentSoft, in: Circle())
            Text("문의를 보냈어요")
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.4)
                .foregroundColor(.appTextPrimary)
            Text("확인하는 대로 반영하거나 연락드릴게요.")
                .font(.app(.callout))
                .foregroundColor(.appTextSecondary)
            Button("돌아가기") { dismiss() }
                .buttonStyle(SecondaryButtonStyle(foregroundColor: .appTextPrimary))
                .padding(.top, 6)
        }
        .padding(.top, 24)
    }

    @MainActor
    private func send() async {
        guard !trimmedMessage.isEmpty, !isSending else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        #if canImport(Supabase)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let device = "\(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)"
        let trimmedContact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let userId = try await SupabaseManager.shared.currentUserId()
            try await SupabaseManager.shared.client
                .from("inquiries")
                .insert(InquiryInsert(
                    user_id: userId,
                    category: category,
                    message: String(trimmedMessage.prefix(4000)),
                    role: role,
                    contact: trimmedContact.isEmpty ? nil : trimmedContact,
                    app_version: "\(version) (\(build))",
                    device: device
                ))
                .execute()
            Haptics.success()
            isMessageFocused = false
            withAnimation(.easeOut(duration: 0.2)) { didSend = true }
        } catch {
            errorMessage = "보내지 못했어요. 잠시 후 다시 시도해주세요."
        }
        #endif
    }
}
