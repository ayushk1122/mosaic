//
//  ContentView.swift
//  Mosaic
//
//  Created by Ayush Krishnappa on 9/28/26.
//

import SwiftUI

struct ContentView: View {
    var account: MosaicAccount? = nil
    var linkedUsername: Binding<String?> = .constant(nil)

    var body: some View {
        MosaicTabShell(account: account, linkedUsername: linkedUsername)
    }
}

#Preview("Mosaic") {
    MosaicTabShell(persistToDisk: false)
}
