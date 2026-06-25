import ActivityKit
import WidgetKit
import SwiftUI

struct WorkerCheckInActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var statusText: String
        var checkInAt: Date
    }

    var storeId: String
    var storeName: String
}

struct WorkerCheckInLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkerCheckInActivityAttributes.self) { context in
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "briefcase.fill")
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.cyan.opacity(0.75))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.storeName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(context.state.statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 8)
                Text(context.state.checkInAt, style: .timer)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .widgetURL(Self.workerCheckInURL(storeId: context.attributes.storeId))
            .activityBackgroundTint(Color(red: 0.08, green: 0.14, blue: 0.24))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("출근 중")
                        .font(.system(size: 13, weight: .semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.checkInAt, style: .timer)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.storeName)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium))
                }
            } compactLeading: {
                Image(systemName: "briefcase.fill")
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(context.state.checkInAt, style: .timer)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "briefcase.fill")
                    .foregroundStyle(.white)
            }
            .widgetURL(Self.workerCheckInURL(storeId: context.attributes.storeId))
            .keylineTint(Color.cyan)
        }
    }

    private static func workerCheckInURL(storeId: String) -> URL? {
        URL(string: "howmuch://worker/checkin?store_id=\(storeId)")
    }
}
