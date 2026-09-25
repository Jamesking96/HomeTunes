# One-time setup on Windows. Run from this folder:  .\setup.ps1
# Needs Flutter installed and on PATH (https://docs.flutter.dev/get-started/install/windows).
#
# The repo only holds the Dart code (lib/, test/, tool/, packages/). This script:
#   1. lets `flutter create` generate the missing platform folders (windows/, android/ ...),
#   2. runs tool/patch_platforms.dart to tweak those generated files for HomeTunes
#      (app name, Android permissions, icons etc.),
#   3. downloads the Dart/Flutter packages listed in pubspec.yaml.
# Safe to run again: `flutter create .` only adds files that are missing.
$ErrorActionPreference = "Stop"
# Each step checks $LASTEXITCODE because "Stop" only catches PowerShell errors, not a
# failing external program like flutter or dart.
flutter create --org com.hometunes --project-name hometunes --platforms=windows,android,linux,macos,ios .
if ($LASTEXITCODE -ne 0) { throw "flutter create failed" }
dart run tool/patch_platforms.dart
if ($LASTEXITCODE -ne 0) { throw "patching failed" }
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
Write-Host ""
Write-Host "Done. Run the app with:  flutter run -d windows"
Write-Host "Or on a plugged-in Android phone:  flutter run -d android"
