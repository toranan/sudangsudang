import Foundation

/// Tracks which asynchronous load is allowed to update view state.
struct LatestRequest {
    private var id: UUID?

    mutating func begin() -> UUID {
        let requestID = UUID()
        id = requestID
        return requestID
    }

    mutating func invalidate() {
        id = nil
    }

    func isCurrent(_ requestID: UUID) -> Bool {
        id == requestID
    }
}
