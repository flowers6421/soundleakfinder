#!/bin/bash

# Build and create DMG for Soundleakfinder
# This script builds the app with the correct settings and packages it into a DMG

set -e  # Exit on error

# Configuration
APP_NAME="Soundleakfinder"
PROJECT_FILE="Soundleakfinder.xcodeproj"
TARGET="Soundleakfinder"
CONFIGURATION="Release"
BUILD_DIR="build/Release"
DMG_DIR="dmg_build"
DMG_NAME="Soundleakfinder-1.0.dmg"

echo "🔨 Building ${APP_NAME}..."

# Clean previous builds
rm -rf build
rm -rf "${DMG_DIR}"
rm -f "${DMG_NAME}"

# Build the app with the correct settings
xcrun xcodebuild \
    -project "${PROJECT_FILE}" \
    -target "${TARGET}" \
    -configuration "${CONFIGURATION}" \
    clean build

echo "✅ Build completed successfully!"

# Find the built app
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"

if [ ! -d "${APP_PATH}" ]; then
    echo "❌ Error: App not found at ${APP_PATH}"
    exit 1
fi

echo "📦 Creating DMG..."

# Create temporary directory for DMG contents
mkdir -p "${DMG_DIR}"

# Copy the app to the DMG directory
cp -R "${APP_PATH}" "${DMG_DIR}/"

# Create a symbolic link to Applications folder
ln -s /Applications "${DMG_DIR}/Applications"

# Create the DMG
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_NAME}"

# Clean up temporary directory
rm -rf "${DMG_DIR}"

echo "✅ DMG created successfully: ${DMG_NAME}"
echo ""
echo "📍 Location: $(pwd)/${DMG_NAME}"
echo ""
echo "You can now distribute this DMG file!"
echo "Users can drag ${APP_NAME}.app to their Applications folder."

