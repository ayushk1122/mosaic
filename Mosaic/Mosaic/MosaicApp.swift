//
//  MosaicApp.swift
//  Mosaic
//
//  Created by Ayush Krishnappa on 9/28/26.
//

import SwiftUI

@main
struct MosaicApp: App {
    var body: some Scene {
        WindowGroup {
            MosaicRootView()
        }
    }
}

private struct MosaicRootView: View {
    private enum LaunchPhase {
        case animating
        case finished
    }

    @State private var launchPhase: LaunchPhase = ProcessInfo.processInfo.arguments.contains("UITestSkipLaunchAnimation")
        ? .finished
        : .animating

    var body: some View {
        Group {
            switch launchPhase {
            case .animating:
                MosaicLaunchAnimationView {
                    withAnimation(.easeOut(duration: 0.35)) {
                        launchPhase = .finished
                    }
                }
            case .finished:
                ContentView()
            }
        }
    }
}
