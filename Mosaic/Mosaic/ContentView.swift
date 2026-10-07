//
//  ContentView.swift
//  Mosaic
//
//  Created by Ayush Krishnappa on 9/28/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        MosaicTabShell()
    }
}

#Preview("Mosaic") {
    MosaicTabShell(persistToDisk: false)
}
