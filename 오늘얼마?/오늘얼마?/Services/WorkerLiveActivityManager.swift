import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

final class WorkerLiveActivityManager {
    static let shared = WorkerLiveActivityManager()

    private init() {}

    func startOrUpdate(storeId: UUID, storeName: String, checkInAt: Date) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let storeIdString = storeId.uuidString
        let attributes = WorkerCheckInActivityAttributes(
            storeId: storeIdString,
            storeName: storeName
        )
        let state = WorkerCheckInActivityAttributes.ContentState(
            statusText: "출근 중",
            checkInAt: checkInAt
        )
        let content = ActivityContent(state: state, staleDate: nil)

        if let activity = Activity<WorkerCheckInActivityAttributes>.activities.first(where: { $0.attributes.storeId == storeIdString }) {
            await activity.update(content)
            return
        }

        do {
            _ = try Activity<WorkerCheckInActivityAttributes>.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            #if DEBUG
            print("DEBUG: failed to start live activity: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    func end(storeId: UUID) async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }

        let storeIdString = storeId.uuidString
        let activities = Activity<WorkerCheckInActivityAttributes>.activities.filter {
            $0.attributes.storeId == storeIdString
        }
        guard !activities.isEmpty else { return }

        let content = ActivityContent(
            state: WorkerCheckInActivityAttributes.ContentState(
                statusText: "퇴근 완료",
                checkInAt: Date()
            ),
            staleDate: nil
        )

        for activity in activities {
            await activity.end(content, dismissalPolicy: .immediate)
        }
        #endif
    }
}
