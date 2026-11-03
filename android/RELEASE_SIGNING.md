# Android release signing

Android only installs an APK as an **update** when it is signed with the same
key as the installed one and has a higher `versionCode`. Until November 2026
the APK was signed with the build machine's debug key, so a copy built on
another machine (or after the debug key changed) had to be uninstalled first.

## One-time: create the release key (keep it forever)

Run this on the machine that builds the APKs. It asks for a password, and for
your name and organisation. Pick a strong password and **store it in the
company password manager**.

```
keytool -genkeypair -v -keystore C:\keys\vistar-lr-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias vistar-lr
```

Then create `android/key.properties` (git-ignored, never commit it):

```
storeFile=C:/keys/vistar-lr-release.jks
storePassword=<the password>
keyAlias=vistar-lr
keyPassword=<the password>
```

**Back up `vistar-lr-release.jks` and the password** somewhere safe, outside
this PC. If the key is lost, no future APK can update the installed app, and
every user has to uninstall and reinstall.

## Every APK you hand out

1. Raise `version:` in `pubspec.yaml`. Raise the number after `+` by one each
   time, e.g. `1.0.1+2` → `1.0.2+3`.
2. Build: `flutter build apk --release`.
3. The APK is at `build/app/outputs/flutter-apk/app-release.apk`.

The build prints which key it used. Without `key.properties` it falls back to
the debug key, which is fine for a test build only.

## The first release-signed APK

Phones that have a **debug-signed** copy (every APK handed out before this)
must uninstall it **once** before installing the first release-signed APK.
After that, every new APK installs over the old one.
