import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// 매장 고유 코드를 보여주고 공유하는 작은 시트.
struct StoreInviteSheet: View {
    let storeId: UUID
    let storeName: String

    @Environment(\.dismiss) private var dismiss
    @State private var code: String?
    @State private var isLoading = false
    @State private var isReissuing = false
    @State private var isShowingReissueConfirm = false
    @State private var didCopy = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("매장 코드")
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundColor(.appTextPrimary)
                Text("알바생이 앱에서 이 코드를 입력하면 \(storeName)에 바로 연결돼요")
                    .font(.app(.caption))
                    .foregroundColor(.appTextSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {

                Group {
                    if let code {
                        Text(spaced(code))
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .tracking(2)
                            .monospacedDigit()
                            .foregroundColor(.appTextPrimary)
                            .textSelection(.enabled)
                    } else if isLoading {
                        ProgressView()
                    } else {
                        Text("---- ----")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .foregroundColor(.appLine)
                    }
                }
                .frame(height: 48)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Color.appFill, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))

            HStack(spacing: 10) {
                Button {
                    guard let code else { return }
                    UIPasteboard.general.string = code
                    Haptics.success()
                    didCopy = true
                } label: {
                    Label(didCopy ? "복사됨" : "복사", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(SecondaryButtonStyle(foregroundColor: .appTextPrimary))

                if let code {
                    ShareLink(item: shareMessage(code: code)) {
                        Label("공유하기", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button {} label: {
                        Label("공유하기", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(true)
                }
            }
            .disabled(code == nil)

            if let errorMessage {
                Text(errorMessage)
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appWarning)
                    .multilineTextAlignment(.center)
            }

            Button {
                isShowingReissueConfirm = true
            } label: {
                Text(isReissuing ? "바꾸는 중…" : "코드 새로 만들기")
                    .font(.app(.caption, .medium))
                    .foregroundColor(.appTextSecondary)
                    .underline()
            }
            .disabled(code == nil || isReissuing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color.appSurface.ignoresSafeArea())
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .alert("코드를 새로 만들까요?", isPresented: $isShowingReissueConfirm) {
            Button("새로 만들기", role: .destructive) {
                Task { await reissue() }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("지금 코드는 더 이상 쓸 수 없어요. 이미 연결된 직원은 그대로예요.")
        }
        .task {
            await load()
        }
    }

    private func spaced(_ code: String) -> String {
        guard code.count == 8 else { return code }
        return "\(code.prefix(4)) \(code.suffix(4))"
    }

    private func shareMessage(code: String) -> String {
        "[수당수당] \(storeName) 매장 코드: \(code)\n앱에서 '초대코드 입력하기'에 넣어주세요.\nhowmuch://invite?token=\(code)"
    }

    @MainActor
    private func load() async {
        #if canImport(Supabase)
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            code = try await SupabaseManager.shared.fetchOrCreateStoreCode(storeId: storeId)
        } catch {
            errorMessage = AppErrorMessage.userMessage(error)
        }
        #endif
    }

    @MainActor
    private func reissue() async {
        #if canImport(Supabase)
        isReissuing = true
        errorMessage = nil
        defer { isReissuing = false }
        do {
            code = try await SupabaseManager.shared.reissueStoreCode(storeId: storeId)
            didCopy = false
            Haptics.success()
        } catch {
            errorMessage = AppErrorMessage.userMessage(error)
        }
        #endif
    }
}
