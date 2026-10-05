//
//  ContentView.swift
//  Mosaic
//
//  Created by Ayush Krishnappa on 9/28/26.
//

import SwiftUI

struct ContentView: View {
    private enum ShellRoute: Hashable {
        case golf
    }

    @State private var path: [ShellRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            PursuitsHomeView(
                fixture: MosaicHomeFixtures.iteration0A,
                openGolf: { path.append(.golf) }
            )
            .navigationDestination(for: ShellRoute.self) { route in
                switch route {
                case .golf:
                    GolfDestinationView()
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
