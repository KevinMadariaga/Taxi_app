//
//  RideWidgetExtensionBundle.swift
//  RideWidgetExtension
//
//  Created by Kevin Madariaga on 4/09/26.
//

import WidgetKit
import SwiftUI

@main
struct RideWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        RideWidgetExtension()
        RideWidgetExtensionControl()
        RideWidgetExtensionLiveActivity()
    }
}
