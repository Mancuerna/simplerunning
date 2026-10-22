# SimpleRunning

Offline Android training app for the self-powered Bodytone ZROTH, built with
Flutter. No registration, analytics or automatic uploads. The runner controls belt
speed; the app guides the session and records the treadmill's Bluetooth data.

## Features

- Dark interface with training, plans, history and progress tabs.
- Free sessions with live speed, pace, active time and distance.
- Configurable intervals: 1–30 rounds, running and recovery durations, optional
  warm-up and cool-down. Each round includes its recovery, including the last one.
- Per-block countdown, pause/resume, skip and 30-second extension. Timers use
  monotonic elapsed time rather than counting callbacks. Distance blocks wait for
  actual distance updates. Guided sessions save and stop the console on completion.
- One voice on/off switch. Cues use Android's default TTS engine with the phone's
  current language, unmodified phrases, and no custom voice, pitch or rate settings.
  Disabling voice stops any currently spoken cue and uses beeps instead: short
  countdown ticks and a distinct transition tone, at the phone media volume.
  Vibration remains independent.
- Original 9-week walk/run starter template and 8-week 5-to-10-km template, each
  with three sessions per week. Any session can be previewed or repeated. The
  next unfinished session is offered automatically.
- Saved sessions, speed chart, block summaries, peak speed, weekly totals and
  distance over the last seven calendar days.
- Per-session JSONL/CSV export; complete JSON backup and additive restore.

The starter template builds toward 30 continuous minutes, which does not guarantee
5 km. The 10-km template assumes a comfortable 5-km baseline. Templates are not a
reproduction of a branded C25K programme or an individualized prescription.
The general walk/run progression and recovery-day approach are consistent with the
[NHS introduction to Couch to 5K](https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/couch-to-5k-running-plan/).
Repeat weeks as needed. Progress is derived from fully finished, unskipped sessions;
ending early keeps the recorded workout without completing the plan objective.
Extending a block does not prevent completion.

## Use

1. Close other apps connected to the treadmill. Enable Bluetooth and grant the
   requested permissions. Older Android versions may require location.
2. Choose a free workout, configure intervals or select a plan session.
3. Tap **Buscar cinta**, connect, then **Empezar entrenamiento**.
4. Keep the app visible; the screen stays awake. Pause freezes the active training
   clock and excludes distance while paused; it does not pause the console.
5. Use **Finalizar y guardar**, or let a guided session finish. The console stop
   command does not physically brake the belt.
6. Review the saved session in **Historial** and aggregate totals in **Progreso**.

Background recording and automatic reconnection are not implemented. A dropped
connection saves an interrupted session. Samples flush every second, allowing
history recovery after process termination. Missing speed is null rather than zero.
Average pace includes recovery blocks and excludes manual pauses.

Distance comes from console counter deltas in 10-meter increments. The first
reading after start/resume is a baseline; small distances before it may be omitted.
Console resets never subtract distance. Per-block distances and paces are approximate
because counter updates can straddle a block boundary.

## Data portability

Settings exports all sessions as a versioned JSON file. Restore uses Android's
file chooser and validates the entire file before importing. Existing sessions
are retained, exact duplicate records are skipped, and supplied filenames are
ignored. Restore accepts up to 1,000 sessions and 20 MiB per backup. Local files
remain private until shared. Uninstalling removes them; Android backup is disabled.

Training JSONL includes a `training_start` with recipe metadata, timestamped
`sample` records (active seconds, meters, nullable speed and block), phase/pause/
resume/skip/extend events, and `training_end` with save/goal completion status.
Older free-session files remain readable. A missing end denotes interruption.

## Bluetooth

Checksum-validated FitShow FFF1 status (`0x51`) carries running speed in tenths of
km/h at payload byte 2. Workout (`0x52 0x00`) provides distance. FTMS speed is
unreliable on this machine and is not used for training.

Initialization sends an anonymous session slot with unset profile fields, local
clock/model negotiation and information queries using ATT Write Command. This
sequence and live readings have been checked on the target treadmill. No speed or
incline targets are sent. Queries alternate workout and status; three consecutive
write failures pause polling. A matching unsolicited frame does not prove causality.

Protocol reference:
[QDomyos-Zwift FitShow implementation](https://github.com/cagnulein/qdomyos-zwift/tree/master/src/devices/fitshowtreadmill).
The installed app subscribes only to the training channel and does not record raw
Bluetooth packets. Historical diagnostic files from earlier versions are left
untouched but are no longer exposed in Settings. Optional diagnostic instrumentation
remains available to development tests. Training history and exports are unchanged.

## Development

Requires Flutter with Dart 3.13.4 or newer and a configured Android SDK/JDK.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`.
Android is the only configured platform. Tests cover framing, polling, connection
loss, timed and distance blocks, completion, pause accounting, persistence,
backup validation, statistics and navigation on narrow/large-text screens.

## CI and automatic releases

The workflows follow the [NDPI Viewer release setup](https://github.com/Mancuerna/ndpiviewer-rs/blob/main/.github/workflows/release.yml), adapted for Flutter/Android:

- **Android CI** runs on pushes to `main`, pull requests and manual dispatch. It
  resolves the lockfile, runs analysis and tests, builds a debug APK, and uploads
  the APK and SHA-256 checksum as an Actions artifact. PR builds need no secrets.
- **Release** runs Release Please on pushes to `main`. Conventional commits such
  as `fix: unblock treadmill startup` and `feat: add a training plan` update a
  release PR with `CHANGELOG.md`, the version in `pubspec.yaml`, and the manifest.
  The Dart strategy also increments the numeric Android build number (`+N`).
- Merging the release PR creates a `vX.Y.Z` tag and a **draft** GitHub Release.
  The workflow checks out that exact tag, validates the version and manifest,
  runs analysis/tests, builds and verifies a signed universal APK, then attaches
  `SimpleRunning-X.Y.Z.apk` and its `.sha256` file. Only then is the release
  published and marked latest. A failed build leaves the release as a draft.
- Release Please uses `GITHUB_TOKEN`; no personal token is required. Because
  bot-created PRs do not trigger normal PR workflows, **Release** explicitly
  dispatches **Android CI** on the release PR branch. Build and publication run
  in the same release workflow instead of relying on tag/release event triggers.

Versions are now managed through release PRs; do not manually bump `pubspec.yaml`
for each fix. The initial manifest baseline is `1.3.3`, and `bootstrap-sha` excludes
history through `87725ae` from the first generated changelog. Subsequent releases
use the previous release automatically.

### One-time repository setup

1. In **Settings → Actions → General → Workflow permissions**, enable
   **Allow GitHub Actions to create and approve pull requests**. Workflows declare
   their required permissions explicitly; the repository default can stay read-only.
2. Keep the existing Android signing key. Add these repository Actions secrets if
   they are not already configured:

   | Secret | Value |
   | --- | --- |
   | `ANDROID_KEYSTORE_BASE64` | Base64-encoded contents of the existing keystore |
   | `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
   | `ANDROID_KEY_ALIAS` | Key alias |
   | `ANDROID_KEY_PASSWORD` | Key password |

   CI fails early when signing secrets are missing; it never generates a replacement
   signing key. Keep a private backup and never commit it. For a new app without an
   existing release key, create one outside the repository:

   ```sh
   keytool -genkeypair -v -keystore /safe/location/simplerunning-release.jks \
     -alias simplerunning -keyalg RSA -keysize 2048 -validity 10000
   ```

3. Once these workflows are on `main`, use Conventional Commit messages (including
   squash-merge titles). Merge the generated release PR when ready to distribute.
   Download the signed APK directly from the repository's **Releases** page.
4. If branch protection is enabled, require the **Required Android CI / build**
   check after its first run. Release PRs receive that same check via dispatch.

### Retry and manual builds

If signing, uploading or publication fails, fix the configuration and run
**Actions → Release → Run workflow** from `main`, supplying the existing tag
(for example `v1.3.4`). This rebuilds that tag and replaces its APK/checksum assets;
it does not create a new version or increment the Android build number. The tag
and Release Please draft must already exist. Retry the newest release only, since
successful publication marks it as latest.

For a standalone build without publishing, run **Actions → Build APK → Run
workflow**. Signed release mode is selected by default; disable it for a debug
APK without signing secrets. Download the artifact named
`SimpleRunning-<version>-<run ID>-<attempt>`; artifacts expire after 30 days.

Local builds without `ANDROID_KEYSTORE_PATH` use the development key. For local
release signing, provide that path and `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD` (no Base64 variable is needed).
Updates signed with the existing release key install in place; a development-key
APK cannot update an installation signed with a different release key.

To validate the release metadata helper locally:

```sh
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 scripts/release_version.py
```

## Repository privacy

Do not commit real captures, device screenshots, user sessions or local credentials.
`btinfo/`, `captures/`, JSONL/log files and local tooling directories are ignored.
Raw BLE data may contain identifiers even when addresses are omitted explicitly.
