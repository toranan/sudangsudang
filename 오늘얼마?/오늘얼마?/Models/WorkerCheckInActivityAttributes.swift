import Foundation

#if canImport(ActivityKit)
import ActivityKit

struct WorkerCheckInActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var statusText: String
        var checkInAt: Date
    }

    var storeId: String
    var storeName: String
}
#endif
