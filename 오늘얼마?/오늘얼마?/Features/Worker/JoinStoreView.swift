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
    @FocusState private var isTokenFocused: Bool

    let onSubmit: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("사장님께 받은 코드로 매장을 연결해요")
                        .font(.app(.callout, .medium))
                        .foregroundColor(.appTextSecondary)
                    Text("초대코드 입력하기")
                        .font(.system(size: 24, weight: .heavy))
                        .tracking(-0.6)
                        .foregroundColor(.appTextPrimary)
                }
                .padding(.horizontal, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("초대코드")
                        .font(.app(.caption, .semibold))
                        .foregroundColor(.appTextSecondary)
                    TextField("사장님이 보내준 매장 코드", text: $token)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled()
                        .focused($isTokenFocused)
                        .appInputField()

                    if let error {
                        Text(error)
                            .font(.app(.caption, .medium))
                            .foregroundColor(.appWarning)
                    }
                }
                .appCard()

                Button("추가하기") {
                    let trimmed = token.filter(\.isNumber)
                    guard !trimmed.isEmpty else {
                        error = "초대코드를 입력해주세요."
                        return
                    }
                    onSubmit(trimmed)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("닫기") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle(foregroundColor: .appTextSecondary))

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { isTokenFocused = false }
            .background(Color.appBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

