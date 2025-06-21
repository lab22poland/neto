//
//  netoApp.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//

import SwiftUI

@main
struct netoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
#if os(macOS)
        .windowResizability(.contentSize)
#endif
    }
}
