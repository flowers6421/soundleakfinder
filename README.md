# 🎯 Soundleakfinder

A professional macOS acoustic source localization app for detecting and locating sound leaks.

![macOS](https://img.shields.io/badge/macOS-26.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## ✨ Features

- 📍 **Real-time Sound Source Localization**: Pinpoint the exact location of sound sources using advanced DSP algorithms
- 📊 **Live Visualization**: Real-time display of sound source direction and intensity
- ⚡ **High-Performance DSP**: GCC-PHAT and TDOA algorithms using Apple's Accelerate framework

## 🚀 Quick Start

### Installation

1. Download `Soundleakfinder-1.0.dmg`
2. Open the DMG file
3. Drag **Soundleakfinder.app** to your **Applications** folder
4. Launch the app from Applications or Spotlight


## 📋 Requirements

- macOS 26.0 or later
- Microphone access permission
- (Optional) Network access for remote microphones

## 🔧 Building from Source

```bash
# Clone the repository
git clone https://github.com/yourusername/soundleakfinder.git
cd soundleakfinder

# Open in Xcode
open Soundleakfinder.xcodeproj

# Build and run (⌘R)
```

### Build DMG

```bash
./build_dmg.sh
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.
