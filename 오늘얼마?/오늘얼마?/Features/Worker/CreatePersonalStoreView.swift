import SwiftUI
import Combine
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(Supabase)
import Supabase
#endif

struct CreatePersonalStoreView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var address: String = ""
    @State private var searchResults: [KakaoPlace] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var isSearchExpanded = true

    let onSubmit: (String, String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("혼자 근무를 기록할 매장을 만들어요")
                            .font(.app(.callout, .medium))
                            .foregroundColor(.appTextSecondary)
                        Text("매장 추가하기")
                            .font(.system(size: 24, weight: .heavy))
                            .tracking(-0.6)
                            .foregroundColor(.appTextPrimary)
                    }
                    .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("매장명")
                            .font(.app(.caption, .semibold))
                            .foregroundColor(.appTextSecondary)
                        HStack(spacing: 8) {
                            TextField("매장명", text: $name)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                                .onSubmit { Task { await searchPlaces(manualTrigger: true) } }
                                .foregroundColor(.appTextPrimary)
                                .appInputField()
                            Button {
                                Task { await searchPlaces(manualTrigger: true) }
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.appOnInk)
                                    .frame(width: 48, height: 48)
                                    .background(Color.appInk)
                                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.field, style: .continuous))
                            }
                            .buttonStyle(PressableRowStyle())
                            .accessibilityLabel("검색")
                        }

                        if !address.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "mappin")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(address)
                                    .font(.app(.caption, .medium))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.appTextSecondary)
                            .padding(.top, 2)
                        }

                        if let searchError {
                            Text(searchError)
                                .font(.app(.caption, .medium))
                                .foregroundColor(.appWarning)
                        }
                    }
                    .appCard()

                    if isSearching {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .appCard()
                    } else if !searchResults.isEmpty && isSearchExpanded {
                        VStack(spacing: 0) {
                            ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, place in
                                if index > 0 {
                                    Rectangle()
                                        .fill(Color.appLine)
                                        .frame(height: 1)
                                }
                                Button(action: {
                                    name = place.placeName
                                    address = place.displayAddress
                                    isSearchExpanded = false
                                    hideKeyboard()
                                }) {
                                    HStack(spacing: 12) {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color.appAccentSoft)
                                            .frame(width: 36, height: 36)
                                            .overlay(
                                                Image(systemName: "mappin")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(.appAccent)
                                            )
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(place.placeName)
                                                .font(.app(.callout, .bold))
                                                .foregroundColor(.appTextPrimary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Text(place.displayAddress)
                                                .font(.app(.caption))
                                                .foregroundColor(.appTextSecondary)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(PressableRowStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
                    }

                    Button(action: {
                        onSubmit(name, address)
                        dismiss()
                    }) {
                        Text("등록하기")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                        .foregroundColor(.appTextPrimary)
                }
            }
        }
        .task(id: name) {
            await debouncedAutoSearch()
        }
    }

    private var kakaoRestApiKey: String? {
        let key = AppConfig.kakaoRestApiKey
        return key.isEmpty ? nil : key
    }

    @MainActor
    private func debouncedAutoSearch() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchError = nil
            return
        }
        isSearchExpanded = true
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        await searchPlaces(query: trimmed, manualTrigger: false)
    }

    @MainActor
    private func searchPlaces(manualTrigger: Bool) async {
        await searchPlaces(query: name, manualTrigger: manualTrigger)
    }

    @MainActor
    private func searchPlaces(query: String, manualTrigger: Bool) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchError = manualTrigger ? "검색어를 입력해주세요." : nil
            return
        }
        guard let apiKey = kakaoRestApiKey else {
            searchError = "KAKAO_REST_API_KEY가 설정되어 있지 않습니다."
            return
        }
        isSearching = true
        searchError = nil
        defer { isSearching = false }
        do {
            let results = try await KakaoLocalSearch.search(query: trimmed, apiKey: apiKey)
            if Task.isCancelled { return }
            searchResults = results
            isSearchExpanded = true
        } catch {
            if Task.isCancelled { return }
            searchError = AppErrorMessage.userMessage(error)
        }
    }

    private struct KakaoSearchResponse: Decodable {
        let documents: [KakaoPlace]
    }

    private struct KakaoPlace: Decodable, Identifiable {
        let id: String
        let placeName: String
        let addressName: String?
        let roadAddressName: String?

        enum CodingKeys: String, CodingKey {
            case id
            case placeName = "place_name"
            case addressName = "address_name"
            case roadAddressName = "road_address_name"
        }

        var displayAddress: String {
            if let roadAddressName, !roadAddressName.isEmpty {
                return roadAddressName
            }
            return addressName ?? "-"
        }
    }

    private enum KakaoLocalSearch {
        static func search(query: String, apiKey: String) async throws -> [KakaoPlace] {
            var components = URLComponents(string: "https://dapi.kakao.com/v2/local/search/keyword.json")
            components?.queryItems = [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "size", value: "10")
            ]
            guard let url = components?.url else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw NSError(domain: "KakaoSearch", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "검색 요청에 실패했습니다. (HTTP \(http.statusCode))"
                ])
            }

            let decoded = try JSONDecoder().decode(KakaoSearchResponse.self, from: data)
            return decoded.documents
        }
    }

    private func hideKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}

