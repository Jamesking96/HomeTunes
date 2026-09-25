#!/usr/bin/env bash
# One-time setup on macOS / Linux. Run from this folder:  ./setup.sh
#
# Same steps as setup.ps1 (the Windows version):
#   1. `flutter create .` generates the missing platform folders (windows/, android/ ...),
#   2. tool/patch_platforms.dart adjusts those generated files for HomeTunes,
#   3. `flutter pub get` downloads the packages listed in pubspec.yaml.
# `set -e` stops the script as soon as any step fails.
set -e
flutter create --org com.hometunes --project-name hometunes --platforms=windows,android,linux,macos,ios .
dart run tool/patch_platforms.dart
flutter pub get
echo
echo "Done. Run the app with:  flutter run -d macos   (or -d linux / -d android)"
