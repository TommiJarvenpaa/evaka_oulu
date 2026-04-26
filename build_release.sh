#!/bin/bash
set -e

flutter build apk --release

version=$(git describe --tags --abbrev=0 2>/dev/null)
count=$(git rev-list "${version}..HEAD" --count 2>/dev/null || echo "0")
name="eVaka-Oulu-${version}.${count}.apk"

cp build/app/outputs/flutter-apk/app-release.apk "build/app/outputs/flutter-apk/${name}"
echo "APK: build/app/outputs/flutter-apk/${name}"
