//
//  SoundleakfinderApp.swift
//  Soundleakfinder
//
//  Created by Umut Tan on 26.10.2025.
//

import SwiftUI

@main
struct SoundleakfinderApp: App {
    init() {
        // Run DSP validation on startup (DISABLED - causes crashes with assertions)
        // Re-enable only for testing, and remove assertions in production code
        #if DEBUG && false
        DispatchQueue.global(qos: .background).async {
            GCCPHATValidation.validateTDOA()
            GCCPHATValidation.validateTDOAManager()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
