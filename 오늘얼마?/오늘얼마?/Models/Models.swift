import Foundation

struct Profile: Codable, Identifiable {
    let id: UUID
    let email: String?
    let name: String?
    let phone: String?
    let role: Role
    let createdAt: Date
    let updatedAt: Date?
    
    enum Role: String, Codable {
        case owner
        case worker
    }
}

struct ResumeProfile: Identifiable {
    let id: UUID
    let email: String?
    let name: String?
    let phone: String?
    let role: Profile.Role?
}

enum Onboarding {
    static func needsOnboarding(role: Profile.Role?, name: String?, phone: String?) -> Bool {
        // App Store Review: do not require name/email/phone after Sign in with Apple.
        // We only need the role to route the user into the correct app experience.
        return role == nil
    }
}

struct Store: Codable, Identifiable, Hashable {
    let id: UUID
    let ownerId: UUID
    var name: String
    var address: String?
    var isPersonal: Bool?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case address
        case isPersonal = "is_personal"
        case createdAt = "created_at"
    }
}

struct Worker: Codable, Identifiable {
    let id: UUID
    let userId: UUID?
    let storeId: UUID
    var name: String
    var phone: String?
    var hourlyWage: Double
    var isActive: Bool
    let joinedAt: Date
}

struct WorkLog: Codable, Identifiable {
    let id: UUID
    let storeId: UUID
    let workerId: UUID
    let checkInAt: Date
    var checkOutAt: Date?
    var status: Status
    var approvedBy: UUID?
    var approvedAt: Date?
    
    enum Status: String, Codable {
        case pending
        case approved
        case rejected
    }
    
    var duration: TimeInterval? {
        guard let end = checkOutAt else { return nil }
        return end.timeIntervalSince(checkInAt)
    }
}

struct Invite: Codable, Identifiable {
    let id: UUID
    let storeId: UUID
    let token: String
    let qrUrl: String?
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case storeId = "store_id"
        case token
        case qrUrl = "qr_url"
        case expiresAt = "expires_at"
    }
}
