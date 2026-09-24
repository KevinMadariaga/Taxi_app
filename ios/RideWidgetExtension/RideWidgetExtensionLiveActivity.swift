//
//  RideWidgetExtensionLiveActivity.swift
//  RideWidgetExtension
//
//  Created by Kevin Madariaga on 4/09/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RideWidgetExtensionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct RideWidgetExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideWidgetExtensionAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension RideWidgetExtensionAttributes {
    fileprivate static var preview: RideWidgetExtensionAttributes {
        RideWidgetExtensionAttributes(name: "World")
    }
}

extension RideWidgetExtensionAttributes.ContentState {
    fileprivate static var smiley: RideWidgetExtensionAttributes.ContentState {
        RideWidgetExtensionAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: RideWidgetExtensionAttributes.ContentState {
         RideWidgetExtensionAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: RideWidgetExtensionAttributes.preview) {
   RideWidgetExtensionLiveActivity()
} contentStates: {
    RideWidgetExtensionAttributes.ContentState.smiley
    RideWidgetExtensionAttributes.ContentState.starEyes
}
