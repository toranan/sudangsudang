import Foundation
#if canImport(Supabase)
import Supabase
#endif

struct AppConfig {
    // 2026년 최저시급 기준. 신규 알바 등록 시 기본값으로 사용.
    static let defaultHourlyWage: Double = 10_320

    static let supabaseUrl = "https://epfcaibrywkberynrvbk.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwZmNhaWJyeXdrYmVyeW5ydmJrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAwNDg4MTMsImV4cCI6MjA4NTYyNDgxM30.E5YhJNMLsggJJ3CuH2Es0V2QfOoUPVFm7J3H2GB9FuQ"
    static let kakaoRestApiKey = "a47c4fab1f9fef87621626c133e93422"
    static var kakaoNativeAppKey: String {
        Bundle.main.object(forInfoDictionaryKey: "KAKAO_NATIVE_APP_KEY") as? String ?? ""
    }
}

enum AppErrorMessage {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isCancellation(underlying)
        }
        return false
    }

    static func userMessage(
        _ error: Error,
        fallback: String = "문제가 발생했어요. 잠시 후 다시 시도해주세요.",
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> String {
        #if DEBUG
        let nsError = error as NSError
        print(
            "[AppError] \(file):\(line) " +
            "domain=\(nsError.domain) code=\(nsError.code) " +
            "description=\(nsError.localizedDescription)"
        )
        #endif

        if isCancellation(error) {
            return fallback
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "인터넷 연결을 확인해주세요."
            case .timedOut:
                return "요청 시간이 초과됐어요. 다시 시도해주세요."
            default:
                break
            }
        }

        let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return fallback
        }
        if containsKorean(raw) {
            return raw
        }

        let lower = raw.lowercased()
        if lower.contains("401") ||
            lower.contains("unauthorized") ||
            lower.contains("jwt") ||
            lower.contains("token") ||
            lower.contains("session") {
            return "로그인 정보가 만료됐어요. 다시 로그인해주세요."
        }
        if lower.contains("403") ||
            lower.contains("forbidden") ||
            lower.contains("permission") ||
            lower.contains("denied") ||
            lower.contains("42501") {
            return "권한이 없어서 요청을 처리할 수 없어요."
        }
        if lower.contains("404") {
            return "요청한 정보를 찾을 수 없어요."
        }
        if lower.contains("409") ||
            lower.contains("duplicate key") ||
            lower.contains("already exists") {
            return "이미 처리된 요청이거나 중복된 데이터예요."
        }
        if lower.contains("400") ||
            lower.contains("bad request") ||
            lower.contains("invalid input") {
            return "입력값을 다시 확인해주세요."
        }
        if lower.contains("500") ||
            lower.contains("502") ||
            lower.contains("503") ||
            lower.contains("504") ||
            lower.contains("internal server") {
            return "서버가 일시적으로 불안정해요. 잠시 후 다시 시도해주세요."
        }

        return fallback
    }

    private static func containsKorean(_ value: String) -> Bool {
        let pattern = "[가-힣]"
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}

enum WorkerAutoRetirement {
    #if canImport(Supabase)
    private struct StoreInfoRow: Decodable {
        let is_personal: Bool?
    }

    private struct ActiveWorkerRow: Decodable {
        let id: UUID
        let joined_at: String?
        let stores: StoreInfoRow?
    }

    private struct RecentCheckInRow: Decodable {
        let worker_id: UUID
    }

    private static let throttleSeconds: TimeInterval = 300

    @MainActor
    static func processForUser(userId: UUID) async throws {
        guard shouldRun(scopeKey: "user_\(userId.uuidString)") else { return }

        let activeWorkers: [ActiveWorkerRow] = try await SupabaseManager.shared
            .client
            .from("workers")
            .select("id,joined_at,stores(is_personal)")
            .eq("user_id", value: userId.uuidString)
            .eq("is_active", value: true)
            .execute()
            .value

        let personalStoreWorkers = activeWorkers.filter { $0.stores?.is_personal == true }
        try await deactivateIfNeeded(activeWorkers: personalStoreWorkers)
    }

    @MainActor
    static func processForStore(storeId: UUID) async throws {
        guard shouldRun(scopeKey: "store_\(storeId.uuidString)") else { return }

        let activeWorkers: [ActiveWorkerRow] = try await SupabaseManager.shared
            .client
            .from("workers")
            .select("id,joined_at,stores(is_personal)")
            .eq("store_id", value: storeId.uuidString)
            .eq("is_active", value: true)
            .execute()
            .value

        let personalStoreWorkers = activeWorkers.filter { $0.stores?.is_personal == true }
        try await deactivateIfNeeded(activeWorkers: personalStoreWorkers)
    }

    @MainActor
    private static func deactivateIfNeeded(activeWorkers: [ActiveWorkerRow]) async throws {
        guard !activeWorkers.isEmpty else { return }

        let now = Date()
        let calendar = AppTime.calendar
        let cutoff = calendar.date(byAdding: .day, value: -14, to: now) ?? now
        let cutoffISO = AppTime.iso.string(from: cutoff)
        let workerIdStrings = activeWorkers.map { $0.id.uuidString }

        let recentRows: [RecentCheckInRow] = try await SupabaseManager.shared
            .client
            .from("work_logs")
            .select("worker_id")
            .in("worker_id", values: workerIdStrings)
            .gte("check_in_at", value: cutoffISO)
            .execute()
            .value

        let recentWorkerIds = Set(recentRows.map(\.worker_id))
        let retireWorkerIds: [String] = activeWorkers.compactMap { worker in
            if recentWorkerIds.contains(worker.id) {
                return nil
            }
            if let joinedAt = parseISODate(worker.joined_at), joinedAt > cutoff {
                return nil
            }
            return worker.id.uuidString
        }

        guard !retireWorkerIds.isEmpty else { return }

        struct UpdatePayload: Encodable {
            let is_active: Bool
        }

        _ = try await SupabaseManager.shared
            .client
            .from("workers")
            .update(UpdatePayload(is_active: false))
            .in("id", values: retireWorkerIds)
            .execute()
    }

    private static func parseISODate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let parserWithFractional = AppTime.isoWithFractionalSeconds
        let parser = AppTime.iso
        return parserWithFractional.date(from: raw) ?? parser.date(from: raw)
    }

    private static func shouldRun(scopeKey: String) -> Bool {
        let key = "worker_auto_retirement_last_run_\(scopeKey)"
        let now = Date().timeIntervalSince1970
        let last = UserDefaults.standard.double(forKey: key)
        if last > 0, (now - last) < throttleSeconds {
            return false
        }
        UserDefaults.standard.set(now, forKey: key)
        return true
    }
    #else
    @MainActor
    static func processForUser(userId: UUID) async throws {
        _ = userId
    }

    @MainActor
    static func processForStore(storeId: UUID) async throws {
        _ = storeId
    }
    #endif
}
