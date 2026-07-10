import SwiftUI
import Combine
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(Supabase)
import Supabase
#endif

struct JoinStoreView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var token: String = ""
    @State private var error: String?

    let onSubmit: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("초대코드 입력하기")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.appTextPrimary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("초대코드")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.appTextSecondary)
                    TextField("사장님이 보내준 초대코드를 입력", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(12)
                        .background(Color.appSurface)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appLine, lineWidth: 1)
                        )
                }

                if let error {
                    Text(error)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.appWarning)
                }

                Button("추가하기") {
                    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        error = "초대코드를 입력해주세요."
                        return
                    }
                    onSubmit(trimmed)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("닫기") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())

                Spacer()
            }
            .padding(20)
            .navigationTitle("초대코드 입력하기")
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(Color.appBackground.ignoresSafeArea())
    }
}

