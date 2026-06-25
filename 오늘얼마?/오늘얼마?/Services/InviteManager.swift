import Foundation
#if canImport(Supabase)
import Supabase
#endif

extension Notification.Name {
    static let didReceiveInvite = Notification.Name("didReceiveInvite")
    static let didAcceptInvite = Notification.Name("didAcceptInvite")
    static let didOpenWorkerCheckIn = Notification.Name("didOpenWorkerCheckIn")
}

final class InviteManager {
    static let shared = InviteManager()
    private let pendingTokenKey = "pending_invite_token"

    private init() {}

    struct InvitePreview {
        let token: String
        let storeId: UUID
        let storeName: String
    }

    func handleIncomingURL(_ url: URL) {
        guard let token = Self.extractToken(from: url) else { return }
        #if DEBUG
        print("DEBUG: InviteManager.handleIncomingURL token=\(token) url=\(url.absoluteString)")
        #endif
        UserDefaults.standard.set(token, forKey: pendingTokenKey)
        // When app is coming from background, observers can miss the post if it happens
        // during the scene transition. Posting on the main queue makes delivery more reliable.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .didReceiveInvite, object: nil)
        }
    }


    func pendingToken() -> String? {
        UserDefaults.standard.string(forKey: pendingTokenKey)
    }

    func clearPendingToken() {
        UserDefaults.standard.removeObject(forKey: pendingTokenKey)
    }

    #if canImport(Supabase)
    func fetchPendingInvitePreview() async -> InvitePreview? {
        guard let token = pendingToken() else { return nil }

        struct InviteRow: Decodable {
            let store_id: UUID
        }

        do {
            let invite: InviteRow = try await SupabaseManager.shared.client
                .from("invites")
                .select("store_id")
                .eq("token", value: token)
                .single()
                .execute()
                .value

            let store: Store = try await SupabaseManager.shared.client
                .from("stores")
                .select()
                .eq("id", value: invite.store_id.uuidString)
                .single()
                .execute()
                .value

            return InvitePreview(token: token, storeId: invite.store_id, storeName: store.name)
        } catch {
            return nil
        }
    }

    func acceptPendingInvite(token: String) async throws {
        try await SupabaseManager.shared.acceptInvite(token: token)
        clearPendingToken()
    }
    #endif

    private static func extractToken(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = (components.host ?? "").lowercased()
        let path = components.path.lowercased()
        let isInviteRoute = (host == "invite") || path.contains("/invite")
        guard isInviteRoute else { return nil }
        let token = components.queryItems?.first(where: { $0.name == "token" })?.value
        return token?.isEmpty == false ? token : nil
    }
}

final class WorkerDeepLinkManager {
    static let shared = WorkerDeepLinkManager()
    private let pendingStoreIdKey = "pending_worker_checkin_store_id"

    private init() {}

    func handleIncomingURL(_ url: URL) {
        guard let storeId = Self.extractWorkerCheckInStoreId(from: url) else { return }
        UserDefaults.standard.set(storeId.uuidString, forKey: pendingStoreIdKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .didOpenWorkerCheckIn, object: storeId)
        }
    }

    func pendingStoreId() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: pendingStoreIdKey) else { return nil }
        return UUID(uuidString: raw)
    }

    func clearPendingStoreId() {
        UserDefaults.standard.removeObject(forKey: pendingStoreIdKey)
    }

    private static func extractWorkerCheckInStoreId(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "howmuch" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = (components.host ?? "").lowercased()
        let path = components.path.lowercased()
        let isWorkerCheckInRoute = (host == "worker" && path == "/checkin") || path.contains("/worker/checkin")
        guard isWorkerCheckInRoute else { return nil }

        let rawStoreId = components.queryItems?.first(where: {
            let key = $0.name.lowercased()
            return key == "store_id" || key == "storeid"
        })?.value
        guard let rawStoreId else { return nil }
        return UUID(uuidString: rawStoreId)
    }
}
