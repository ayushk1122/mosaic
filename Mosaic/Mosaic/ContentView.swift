//
//  ContentView.swift
//  Mosaic
//
//  Created by Ayush Krishnappa on 9/28/26.
//

import SwiftUI

struct ContentView: View {
    var account: MosaicAccount? = nil
    var linked: Binding<MosaicLink.Target?> = .constant(nil)

    var body: some View {
        MosaicTabShell(account: account, linked: linked)
    }
}

#Preview("Mosaic") {
    MosaicTabShell(persistToDisk: false)
}
