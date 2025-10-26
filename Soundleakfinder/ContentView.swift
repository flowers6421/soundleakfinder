//
//  ContentView.swift
//  Soundleakfinder
//
//  Created by Umut Tan on 26.10.2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()

    var body: some View {
        VStack(spacing: 20) {
            Text("🔊 Sound Leak Finder")
                .font(.title)
                .fontWeight(.bold)

            // Permission Status
            HStack {
                Circle()
                    .fill(audioEngine.permissionGranted ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                Text(audioEngine.permissionGranted ? "Microphone Access: Granted" : "Microphone Access: Denied")
                    .font(.caption)
                Spacer()
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)

            // Status Section
            HStack {
                Circle()
                    .fill(audioEngine.isRunning ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                Text(audioEngine.isRunning ? "Recording" : "Stopped")
                    .font(.subheadline)
                Spacer()
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)

            // Level Meters
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio Levels")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Peak:")
                            .frame(width: 50, alignment: .leading)
                        ProgressView(value: Double(audioEngine.peakLevel), total: 1.0)
                        Text(String(format: "%.2f", audioEngine.peakLevel))
                            .font(.caption)
                            .frame(width: 40, alignment: .trailing)
                    }

                    HStack {
                        Text("RMS:")
                            .frame(width: 50, alignment: .leading)
                        ProgressView(value: Double(audioEngine.rmsLevel), total: 1.0)
                        Text(String(format: "%.2f", audioEngine.rmsLevel))
                            .font(.caption)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)

            // Device Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Input Devices")
                    .font(.headline)

                if audioEngine.inputDevices.isEmpty {
                    Text("No input devices found")
                        .font(.caption)
                        .foregroundColor(.gray)
                } else {
                    Picker("Device", selection: $audioEngine.selectedDeviceID) {
                        ForEach(audioEngine.inputDevices) { device in
                            Text(device.name).tag(Optional(device.id))
                        }
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)

            // Control Buttons
            HStack(spacing: 12) {
                Button(action: {
                    audioEngine.enumerateInputDevices()
                }) {
                    Label("Scan Devices", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button(action: {
                    if audioEngine.isRunning {
                        audioEngine.stopAudioEngine()
                    } else {
                        audioEngine.startAudioEngine()
                    }
                }) {
                    Label(audioEngine.isRunning ? "Stop" : "Start", systemImage: audioEngine.isRunning ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            audioEngine.enumerateInputDevices()
        }
    }
}

#Preview {
    ContentView()
}
