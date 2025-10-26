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
        // Run DSP validation on startup
        #if DEBUG
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
