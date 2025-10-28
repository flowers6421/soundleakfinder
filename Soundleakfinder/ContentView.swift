//
//  ContentView.swift
//  Soundleakfinder
//
//  Created by Umut Tan on 26.10.2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar - Minimal controls
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sound Level Meter")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)

                // Status indicator - minimal
                VStack(alignment: .leading, spacing: 8) {
                    Text("STATUS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.6)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(audioEngine.isRunning ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 8, height: 8)

                        Text(audioEngine.isRunning ? "Recording" : "Stopped")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                Divider()
                    .padding(.horizontal, 24)

                // Input device - clean and simple
                VStack(alignment: .leading, spacing: 8) {
                    Text("INPUT DEVICE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.6)

                    if audioEngine.inputDevices.isEmpty {
                        Text("No devices found")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("", selection: $audioEngine.selectedDeviceID) {
                            ForEach(audioEngine.inputDevices) { device in
                                Text(device.name)
                                    .font(.system(size: 13))
                                    .tag(Optional(device.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                // Sensitivity slider - minimal and elegant
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("SENSITIVITY")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .tracking(0.6)

                        Spacer()

                        Text("\(Int(audioEngine.sensitivity * 100))%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(value: $audioEngine.sensitivity, in: 0.1...2.0)
                        .tint(.blue)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                Spacer()

                // Bottom controls - minimal
                VStack(spacing: 12) {
                    Button(action: {
                        if audioEngine.isRunning {
                            audioEngine.stopAudioEngine()
                        } else {
                            audioEngine.startAudioEngine()
                        }
                    }) {
                        Text(audioEngine.isRunning ? "Stop" : "Start")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(audioEngine.isRunning ? .red : .blue)

                    Button(action: {
                        audioEngine.enumerateInputDevices()
                    }) {
                        Text("Refresh Devices")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(width: 280)
            .background(.ultraThinMaterial)

            Divider()

            // Main content - Sound level visualization
            SoundLevelMeterView(
                soundLevel: audioEngine.levelDetector.soundLevel,
                isDetecting: audioEngine.levelDetector.isDetecting
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(
            colorScheme == .dark ?
                Color(red: 0.11, green: 0.11, blue: 0.12) :
                Color(red: 0.98, green: 0.98, blue: 0.99)
        )
        .onAppear {
            audioEngine.enumerateInputDevices()
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}
