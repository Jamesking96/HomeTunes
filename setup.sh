#!/usr/bin/env bash
# One-time setup on macOS / Linux. Run from this folder:  ./setup.sh
set -e
flutter create --org com.hometunes --project-name hometunes --platforms=windows,android,linux,macos,ios .
dart run tool/patch_platforms.dart
flutter pub get
echo
echo "Done. Run the app with:  flutter run -d macos   (or -d linux / -d android)"
