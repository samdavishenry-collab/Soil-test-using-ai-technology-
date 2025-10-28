AI Soil Tester - Release Build Package
--------------------------------------

This package includes:
- Localized Flutter project (English, Hindi, Tamil) in 'lib/main.dart'
- GitHub Actions workflow at .github/workflows/build.yml which:
  - Sets up Java & Flutter on runner
  - Generates a temporary keystore with password 'changeit' (for demo)
  - Creates key.properties and moves the keystore to android/
  - Builds a signed release APK and uploads it as workflow artifact

How to use (quick):
1. Push this project to a GitHub repository (main or master branch).
2. Go to Actions tab and run the 'Build Release APK' workflow manually (workflow_dispatch) or push to branch.
3. After workflow completes, download the APK artifact from the workflow run's Artifacts section.

Security note:
- The workflow uses a temporary keystore with password 'changeit' for convenience. For production/Play Store, replace with your own secure keystore and store passwords as GitHub Secrets.

If you want, I can also:
- Customize app name, icon, and package id (bundle id) before you push.
- Provide detailed steps to upload to Play Store.
