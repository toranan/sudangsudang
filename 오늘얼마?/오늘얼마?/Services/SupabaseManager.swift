import Foundation
#if canImport(Supabase)
import Supabase
#endif

final class SupabaseManager {
    static let shared = SupabaseManager()

    let supabaseURL: URL
    let supabaseAnonKey: String

    #if canImport(Supabase)
    private(set) var client: SupabaseClient
    let authClient: SupabaseClient
    #endif

    private let customAccessTokenKey = "supabase.custom.access.token"
    private let customUserIdKey = "supabase.custom.user.id"
    private let lastRoleKey = "supabase.last.role"
    private var customAccessToken: String?
    private var customUserId: UUID?

    private init() {
        let urlString = AppConfig.supabaseUrl
        let anonKey = AppConfig.supabaseAnonKey
        let fallbackURL = URL(string: "https://invalid.local")!
        let fallbackAnonKey = anonKey.isEmpty ? "invalid-anon-key" : anonKey
        let url = URL(string: urlString) ?? fallbackURL
        if URL(string: urlString) == nil || anonKey.isEmpty {
            assertionFailure("Invalid Supabase configuration. Check AppConfig.supabaseUrl / supabaseAnonKey.")
        }

        self.supabaseURL = url
        self.supabaseAnonKey = fallbackAnonKey
        #if canImport(Supabase)
        self.authClient = SupabaseClient(supabaseURL: url, supabaseKey: fallbackAnonKey)
        self.client = self.authClient
        self.customAccessToken = UserDefaults.standard.string(forKey: customAccessTokenKey)
        if let savedUserId = UserDefaults.standard.string(forKey: customUserIdKey) {
            self.customUserId = UUID(uuidString: savedUserId)
        }

        if let token = customAccessToken {
            print("DEBUG: found customAccessToken in UserDefaults")
        } else {
            print("DEBUG: no customAccessToken in UserDefaults")
        }
        
        if let token = customAccessToken, let userId = customUserId {
            if isTokenValid(token) {
                print("DEBUG: Token is valid. Restoring session.")
                setCustomSession(accessToken: token, userId: userId)
            } else {
                print("DEBUG: Token is INVALID. Clearing session.")
                clearCustomSession()
            }
        } else if customAccessToken != nil {
            print("DEBUG: customAccessToken present but userId missing (or logic fallthrough). Clearing.")
            clearCustomSession()
        }
        #endif
    }

    func checkHeader() {
        print("Supabase Manager Initialized")
    }

    #if canImport(Supabase)
    func currentUserId() async throws -> UUID {
        if let customUserId {
            return customUserId
        }
        let session = try await authClient.auth.session
        return session.user.id
    }

    func restoreProfileIfPossible() async throws -> Profile? {
        if let customUserId, let token = customAccessToken, isTokenValid(token) {
            return try await fetchProfile(id: customUserId)
        }
        if let _ = try? await authClient.auth.session {
            let userId = try await currentUserId()
            return try await fetchProfile(id: userId)
        }
        return nil
    }

    func restoreProfileSnapshotIfPossible() async throws -> ProfileSnapshot? {
        if let customUserId, let token = customAccessToken, isTokenValid(token) {
            return try await fetchProfileSnapshot(id: customUserId)
        }
        if let _ = try? await authClient.auth.session {
            let userId = try await currentUserId()
            return try await fetchProfileSnapshot(id: userId)
        }
        return nil
    }

    func saveLastRole(_ role: Profile.Role) {
        UserDefaults.standard.set(role.rawValue, forKey: lastRoleKey)
    }

    func lastSavedRole() -> Profile.Role? {
        guard let raw = UserDefaults.standard.string(forKey: lastRoleKey) else {
            return nil
        }
        return Profile.Role(rawValue: raw)
    }

    func clearLastRole() {
        UserDefaults.standard.removeObject(forKey: lastRoleKey)
    }

    func hasStoredSession() async -> Bool {
        if let token = customAccessToken, customUserId != nil, isTokenValid(token) {
            return true
        }
        return (try? await authClient.auth.session) != nil
    }

    func validateStoredSession() async -> Bool {
        if let token = customAccessToken, customUserId != nil, isTokenValid(token) {
            let accepted = await isAccessTokenAccepted(token)
            if !accepted {
                clearCustomSession()
                return false
            }
            return true
        }

        if let session = try? await authClient.auth.session {
            let accepted = await isAccessTokenAccepted(session.accessToken)
            if !accepted {
                try? await authClient.auth.signOut()
                return false
            }
            return true
        }

        return false
    }

    private func isTokenValid(_ token: String) -> Bool {
        guard let exp = jwtExpiration(token) else {
            print("DEBUG: Could not parse expiration from token.")
            return false
        }
        let now = Date().timeIntervalSince1970
        let isValid = now < exp
        print("DEBUG: Token Exp Check: Now(\(now)) < Exp(\(exp)) = \(isValid)")
        return isValid
    }

    private func jwtExpiration(_ token: String) -> TimeInterval? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else {
            print("DEBUG: Token has insufficient segments: \(segments.count)")
            return nil
        }
        let payload = String(segments[1])
        guard let data = base64URLDecode(payload) else {
            print("DEBUG: base64URLDecode failed for payload")
            return nil
        }
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("DEBUG: JSON parsing failed (not a dictionary)")
                return nil
            }
            if let exp = json["exp"] as? TimeInterval {
                return exp
            }
            if let expInt = json["exp"] as? Int {
                return TimeInterval(expInt)
            }
            print("DEBUG: 'exp' field missing from payload: \(json.keys)")
            return nil
        } catch {
            print("DEBUG: JSON parsing threw error: \(error)")
            return nil
        }
    }

    private func base64URLDecode(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = 4 - (base64.count % 4)
        if padding < 4 {
            base64.append(String(repeating: "=", count: padding))
        }
        return Data(base64Encoded: base64)
    }

    struct KakaoAuthResponse: Decodable {
        let accessToken: String
        let userId: UUID
        let email: String?
        let expiresIn: Int?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case userId = "user_id"
            case email
            case expiresIn = "expires_in"
        }
    }

    func signInWithKakao(accessToken: String) async throws -> KakaoAuthResponse {
        let functionURL = supabaseURL.appendingPathComponent("/functions/v1/kakao-login")
        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        let body = ["access_token": accessToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, urlResponse) = try await URLSession.shared.data(for: request)
        if let http = urlResponse as? HTTPURLResponse, http.statusCode >= 400 {
            let message = String(data: data, encoding: .utf8) ?? "Edge function error"
            throw NSError(domain: "SupabaseFunction", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
        }

        let responsePayload = try JSONDecoder().decode(KakaoAuthResponse.self, from: data)
        let response = responsePayload
        setCustomSession(accessToken: response.accessToken, userId: response.userId)
        return response
    }

    func setCustomSession(accessToken: String, userId: UUID) {
        customAccessToken = accessToken
        customUserId = userId
        UserDefaults.standard.set(accessToken, forKey: customAccessTokenKey)
        UserDefaults.standard.set(userId.uuidString, forKey: customUserIdKey)

        let options = SupabaseClientOptions(
            auth: .init(accessToken: { [weak self] in
                self?.customAccessToken
            })
        )
        client = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: supabaseAnonKey, options: options)
    }

    func clearCustomSession() {
        customAccessToken = nil
        customUserId = nil
        UserDefaults.standard.removeObject(forKey: customAccessTokenKey)
        UserDefaults.standard.removeObject(forKey: customUserIdKey)
        client = authClient
    }

    func signOut() async {
        clearCustomSession()
        clearLastRole()
        try? await authClient.auth.signOut()
    }

    func deleteAccount() async throws {
        #if canImport(Supabase)
        // Use Supabase Functions SDK to ensure the correct access token is attached.
        do {
            _ = try await client.functions.invoke("delete-account")
        } catch {
            // Fallback to manual call with a verified access token for better error detail.
            let accessToken = try await resolveAccessTokenForSecureCall()
            let functionURL = supabaseURL.appendingPathComponent("/functions/v1/delete-account")
            var request = URLRequest(url: functionURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            if let http = urlResponse as? HTTPURLResponse, http.statusCode >= 400 {
                let message = String(data: data, encoding: .utf8) ?? "Delete account error"
                throw NSError(domain: "SupabaseFunction", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            } else {
                throw error
            }
        }
        #endif
    }

    #if canImport(Supabase)
    private func resolveAccessTokenForSecureCall() async throws -> String {
        if let token = customAccessToken, isTokenValid(token) {
            if await isAccessTokenAccepted(token) {
                return token
            }
            // Token is expired or no longer valid on server; clear cached session.
            clearCustomSession()
        }

        let session = try await authClient.auth.session
        return session.accessToken
    }

    private func isAccessTokenAccepted(_ token: String) async -> Bool {
        let url = supabaseURL.appendingPathComponent("/auth/v1/user")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }
    #endif

    struct ProfilePayload: Encodable {
        let id: UUID
        let email: String?
        let name: String?
        let phone: String?
        let role: String
    }

    struct ProfileSnapshot: Decodable {
        let id: UUID
        let email: String?
        let name: String?
        let phone: String?
        let role: String?
    }

    func upsertProfile(_ payload: ProfilePayload) async throws {
        _ = try await client
            .from("profiles")
            .upsert(payload)
            .execute()
    }

    func fetchProfile(id: UUID) async throws -> Profile {
        try await client
            .from("profiles")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    func fetchProfileSnapshot(id: UUID) async throws -> ProfileSnapshot {
        try await client
            .from("profiles")
            .select("id,email,name,phone,role")
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    struct ProfilePatch: Encodable {
        let name: String?
        let phone: String?

        enum CodingKeys: String, CodingKey {
            case name
            case phone
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let name { try container.encode(name, forKey: .name) }
            if let phone { try container.encode(phone, forKey: .phone) }
        }
    }

    func patchProfile(id: UUID, name: String?, phone: String?) async throws {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveName = (trimmedName?.isEmpty == false) ? trimmedName : nil
        let effectivePhone = (trimmedPhone?.isEmpty == false) ? trimmedPhone : nil

        // Nothing to patch.
        if effectiveName == nil && effectivePhone == nil { return }

        #if DEBUG
        print("DEBUG: patchProfile start. id=\(id) name=\(effectiveName ?? "nil") phone=\(effectivePhone ?? "nil")")
        #endif

        _ = try await client
            .from("profiles")
            .update(ProfilePatch(name: effectiveName, phone: effectivePhone))
            .eq("id", value: id.uuidString)
            .execute()

        #if DEBUG
        print("DEBUG: patchProfile success. id=\(id)")
        #endif
    }

    struct MinimalProfileInsert: Encodable {
        let id: UUID
        let email: String?
        let role: String
    }

    func ensureMinimalProfileRow(id: UUID, email: String?, role: Profile.Role) async throws {
        do {
            #if DEBUG
            print("DEBUG: ensureMinimalProfileRow insert start. id=\(id) role=\(role.rawValue)")
            #endif
            _ = try await client
                .from("profiles")
                .insert(MinimalProfileInsert(id: id, email: email, role: role.rawValue))
                .execute()
            #if DEBUG
            print("DEBUG: ensureMinimalProfileRow insert success. id=\(id)")
            #endif
        } catch {
            // If profile already exists, ignore. Otherwise bubble up.
            let message = error.localizedDescription.lowercased()
            #if DEBUG
            print("DEBUG: ensureMinimalProfileRow insert failed. id=\(id) error=\(error)")
            #endif
            if message.contains("duplicate key") || message.contains("already exists") {
                return
            }
            throw error
        }
    }

    static func isPostgrestSingleObjectCoerceError(_ error: Error) -> Bool {
        let msg = error.localizedDescription
        return msg.contains("Cannot coerce the result to a single JSON object") ||
        msg.contains("JSON object requested")
    }

    static func isProfilesAuthUserForeignKeyError(_ error: Error) -> Bool {
        let msg = error.localizedDescription
        return msg.contains("profiles_id_fkey") ||
        msg.contains("violates foreign key constraint") && msg.contains("profiles")
    }

    struct InviteInsert: Encodable {
        let store_id: UUID
        let token: String
        let expires_at: String
    }

    struct InviteRow: Decodable {
        let id: UUID
        let store_id: UUID
        let token: String
        let expires_at: String
    }

    func createInvite(storeId: UUID, expiresAt: Date) async throws -> Invite {
        let formatter = ISO8601DateFormatter()
        let expiresAtISO = formatter.string(from: expiresAt)

        // 6자리 코드는 충돌 가능성이 있으므로, 유니크 충돌 시 몇 번 재시도한다.
        for _ in 0..<5 {
            let payload = InviteInsert(
                store_id: storeId,
                token: generateInviteCode(),
                expires_at: expiresAtISO
            )

            do {
                let row: InviteRow = try await client
                    .from("invites")
                    .insert(payload)
                    .select("id,store_id,token,expires_at")
                    .single()
                    .execute()
                    .value

                let parsedDate = formatter.date(from: row.expires_at) ?? expiresAt
                return Invite(id: row.id, storeId: row.store_id, token: row.token, qrUrl: nil, expiresAt: parsedDate)
            } catch {
                if isInviteTokenConflict(error) {
                    continue
                }
                throw error
            }
        }

        throw NSError(
            domain: "Invite",
            code: 409,
            userInfo: [NSLocalizedDescriptionKey: "초대코드 생성이 일시적으로 실패했어요. 다시 시도해주세요."]
        )
    }

    private func generateInviteCode() -> String {
        let digits = Array("0123456789")
        return String((0..<6).compactMap { _ in digits.randomElement() })
    }

    private func isInviteTokenConflict(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("duplicate key") ||
            message.contains("already exists") ||
            message.contains("23505") ||
            message.contains("invites_token_key")
    }

    func acceptInvite(token: String) async throws {
        #if DEBUG
        print("DEBUG: acceptInvite rpc start. token=\(token)")
        #endif
        _ = try await client
            .rpc("accept_invite", params: ["p_token": token])
            .execute()
        #if DEBUG
        print("DEBUG: acceptInvite rpc success. token=\(token)")
        #endif
    }

    func retireWorkerLink(workerId: UUID) async throws {
        _ = try await client
            .rpc("retire_worker_link", params: ["p_worker_id": workerId.uuidString])
            .execute()
    }
    #endif
}
