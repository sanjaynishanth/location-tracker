# One-time setup: generates the Android project around the app source.
# Requires the Flutter SDK to be installed and on PATH (run `flutter doctor` first).
# Run this from inside the app\ folder:  .\setup.ps1

$ErrorActionPreference = "Stop"

# 1. Protect our source files, then let flutter create generate the platform folders
Copy-Item pubspec.yaml pubspec.yaml.bak -Force
Copy-Item lib lib_bak -Recurse -Force

flutter create --org ai.glimmora --project-name field_tracker --platforms android .

# 2. Restore our source (flutter create may have overwritten it with the demo app)
Copy-Item pubspec.yaml.bak pubspec.yaml -Force
Remove-Item pubspec.yaml.bak -Force
Remove-Item lib -Recurse -Force
Move-Item lib_bak lib
if (Test-Path test) { Remove-Item test -Recurse -Force }

# 3. Apply our AndroidManifest (permissions + location foreground service)
Copy-Item android-overrides\AndroidManifest.xml android\app\src\main\AndroidManifest.xml -Force

# 4. Plugins need minimum Android SDK 23 (Android 6.0)
$gradle = Get-ChildItem android\app -Filter "build.gradle*" | Select-Object -First 1
(Get-Content $gradle.FullName) -replace "flutter\.minSdkVersion", "23" | Set-Content $gradle.FullName

# 5. Fetch packages
flutter pub get

Write-Host ""
Write-Host "Setup complete. Build the APK with:  flutter build apk --release" -ForegroundColor Green
Write-Host "APK will be at: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
