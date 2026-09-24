# One-time setup on Windows. Run from this folder:  .\setup.ps1
# Needs Flutter installed and on PATH (https://docs.flutter.dev/get-started/install/windows).
$ErrorActionPreference = "Stop"
flutter create --org com.hometunes --project-name hometunes --platforms=windows,android,linux,macos,ios .
if ($LASTEXITCODE -ne 0) { throw "flutter create failed" }
dart run tool/patch_platforms.dart
if ($LASTEXITCODE -ne 0) { throw "patching failed" }
flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
Write-Host ""
Write-Host "Done. Run the app with:  flutter run -d windows"
Write-Host "Or on a plugged-in Android phone:  flutter run -d android"
