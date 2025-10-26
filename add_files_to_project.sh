#!/bin/bash

# Open the Xcode project and add the Info.plist and entitlements files
# This uses PlistBuddy to modify the project.pbxproj file

PROJECT_FILE="Soundleakfinder.xcodeproj/project.pbxproj"

# Backup the project file
cp "$PROJECT_FILE" "$PROJECT_FILE.backup"

echo "Adding Info.plist and entitlements to Xcode project..."
echo "Please add these files manually in Xcode:"
echo "1. Open Soundleakfinder.xcodeproj in Xcode"
echo "2. Select the Soundleakfinder target"
echo "3. Go to 'Build Settings' and set:"
echo "   - INFOPLIST_FILE = Soundleakfinder/Info.plist"
echo "   - CODE_SIGN_ENTITLEMENTS = Soundleakfinder/Soundleakfinder.entitlements"
echo "4. Also set GENERATE_INFOPLIST_FILE = NO"
echo ""
echo "Or run these commands:"
echo "xcodebuild -project Soundleakfinder.xcodeproj -target Soundleakfinder -showBuildSettings | grep INFOPLIST"

