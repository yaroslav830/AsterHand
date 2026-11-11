# Native Android diagnostics

Build the main APK first, then run `python scripts/build_android_tests.py`. The separate test-only APK uses the target application's existing development signing certificate; target classes are compilation inputs and are not duplicated in the test APK.

Run instrumentation only when there is no active user task. Android instrumentation restarts the target application process. Use an explicitly selected ADB serial:

```text
adb -s SERIAL install -r -t dist/AsterHand-0.10.16-android-tests.apk
adb -s SERIAL shell am instrument -w com.pocketagent.test/.AsterInstrumentation
```

The default test runs in the actual target application's ordinary UID. It checks project isolation, persisted records, protected deletion, symlink handling, independent microphone/read-aloud mute preferences with restoration, and a normal-UID command probe. Original project and credential-store bytes must remain unchanged. No API key, network model request, microphone recording, consent decision, or lock-screen interaction is part of these tests.

Optional `-e ui true` opens only the target's own Activity and reads its local WebView DOM readiness, control counts and horizontal overflow. It never dismisses or changes the keyguard. DOM checks behind a locked screen are **not** proof of visible rendering, touch, keyboard, accessibility consent, continuous voice recognition, or live AI replies.

`CoreSelfTest.startQuestionFixture(context)` is an explicit in-app foreground-service fixture. Its question is labeled as a test and does not authorize anything. A visible option must be selected through the real UI before checking `questionFixtureResult`; the fixture never chooses its own answer. These helpers are not exported Android components.

The optional `-e suite privilege` runner invokes the separate privilege-isolation suite in the same ordinary app UID. Root and ADB availability must already be authorized/configured; it may show the normal Root manager approval prompt. `-e bridge-unavailable true` verifies fail-closed behavior when the ADB bridge is intentionally absent. No general RPC or QA network endpoint is exposed.
