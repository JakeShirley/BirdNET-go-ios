# Development Guide

This project should be versioned and released with semantic-release.

## Versioning And Releases

Use semantic-release as the source of truth for release versions, release notes, and Git tags. Do not manually choose release versions or hand-edit generated changelog entries as part of normal feature work.

Expected release model:

- Commits use Conventional Commits.
- semantic-release analyzes commits to decide the next version.
- CI publishes release notes and tags when changes land on the release branch.
- iOS marketing versions should be derived from the semantic-release version during release automation.
- iOS build numbers can remain CI-generated monotonic build identifiers.
- GitHub Actions iOS jobs run on the `macos-26` image and verify the selected iOS SDK is 26.x before building.
- Checked-in Xcode and package versions stay at `0.0.0-development`; release builds pass the semantic-release version to `xcodebuild` without committing that bump back to the repository.

The release workflow intentionally does not use `@semantic-release/git`, `@semantic-release/changelog`, or any other plugin that commits generated version or changelog changes back to the repository.

### TestFlight Uploads

When semantic-release creates a new release on `main`, the GitHub Actions release workflow uses Apple Actions to import the Apple Distribution certificate, download the App Store provisioning profile, and upload the exported IPA to TestFlight. The local release script only archives and exports the signed IPA so the marketing version can come from the semantic-release version. The build number defaults to `<GITHUB_RUN_NUMBER>.<GITHUB_RUN_ATTEMPT>` so reruns produce a distinct App Store Connect build.

Configure these secrets in the GitHub Actions `AppStore` environment before enabling release uploads:

- `APP_STORE_CONNECT_API_KEY_ID`: App Store Connect API key ID.
- `APP_STORE_CONNECT_API_ISSUER_ID`: App Store Connect issuer ID.
- `APP_STORE_CONNECT_API_PRIVATE_KEY`: full `.p8` private key contents. Escaped `\n` line breaks are accepted.
- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`: base64-encoded Apple Distribution `.p12` certificate.
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`: password for the `.p12` certificate.

The App Store Connect app record for `org.odinseye.onpa` must already exist. An active App Store provisioning profile for that bundle ID must also exist in Apple Developer; `apple-actions/download-provisioning-profiles` downloads an existing active profile and does not create one. The profile must include the Apple Distribution certificate imported by the workflow. Set `IOS_BUILD_NUMBER` in the release workflow environment only if a manual build-number override is needed.

To create the signing assets:

1. Generate a certificate signing request on a trusted Mac:

	- Open Keychain Access.
	- Choose Keychain Access > Certificate Assistant > Request a Certificate From a Certificate Authority.
	- Enter an email address and common name, choose Saved to disk, and save the `.certSigningRequest` file.

2. Create the Apple Distribution certificate:

	- Go to Apple Developer > Certificates, Identifiers & Profiles > Certificates.
	- Add a new `Apple Distribution` certificate and upload the `.certSigningRequest` file.
	- Download the generated `.cer` file and open it on the same Mac that created the request.
	- In Keychain Access, find the `Apple Distribution` certificate under My Certificates. It must have a private key nested under it.
	- Export the certificate plus private key as a `.p12` file and set a strong export password.

3. Create the App Store provisioning profile:

	- Go to Apple Developer > Certificates, Identifiers & Profiles > Profiles.
	- Add a new profile using the `App Store` distribution type.
	- Select the app ID for `org.odinseye.onpa`.
	- Select the Apple Distribution certificate from the previous step.
	- Name and generate the profile. It must show as active in Apple Developer.
	- If you rotate or replace the Apple Distribution certificate later, edit or regenerate this profile so it includes the new certificate.
	- The release workflow downloads the active profile automatically with `apple-actions/download-provisioning-profiles`.

4. Add the credentials as GitHub Actions secrets in the `AppStore` environment. This command keeps the `.p12` binary base64-encoded and avoids writing secret values into shell history:

	```sh
	base64 < /path/to/OnpaDistribution.p12 | tr -d '\n' | gh secret set IOS_DISTRIBUTION_CERTIFICATE_BASE64 --env AppStore
	printf '%s' 'your-p12-export-password' | gh secret set IOS_DISTRIBUTION_CERTIFICATE_PASSWORD --env AppStore
	gh secret set APP_STORE_CONNECT_API_PRIVATE_KEY --env AppStore < /path/to/AuthKey_YOUR_KEY_ID.p8
	printf '%s' 'YOUR_KEY_ID' | gh secret set APP_STORE_CONNECT_API_KEY_ID --env AppStore
	printf '%s' 'YOUR_ISSUER_ID' | gh secret set APP_STORE_CONNECT_API_ISSUER_ID --env AppStore
	```

Keep the `.p8`, `.p12`, and any downloaded `.mobileprovision` files outside the repository after creating the secrets. The repository `.gitignore` excludes common local copies, but these files are production credentials and should be treated like passwords.

## Commit Message Format

All feature, bug fix, maintenance, documentation, test, and CI commits should use semantic-release-compatible Conventional Commits:

```text
<type>(optional-scope): [PLAN-ID] <description>

optional body

optional footer
```

Include one or more project plan step IDs from `docs/BIRDNET_GO_IOS_PROJECT_PLAN.md` near the start of the subject. Use the relevant backlog ID for the work being implemented, fixed, or documented. If a commit spans multiple planned steps, include each ID in separate brackets.

Examples:

```text
feat: [FND-004] persist active station profile
feat(feed): [DET-001] add recent detections list
fix(auth): [CON-004] support password-only station login
docs: [FND-002] document app architecture boundaries
refactor(storage): [FND-004] split profile persistence protocol
feat: [CON-001] [CON-002] validate manual station connection
```

For repository-only work that does not map to a planned backlog step, use `[NO-PLAN]` and explain why in the commit body.

Common types:

- `feat`: user-visible feature or capability.
- `fix`: user-visible bug fix.
- `perf`: performance improvement.
- `refactor`: code restructuring with no intended behavior change.
- `test`: test-only change.
- `docs`: documentation-only change.
- `build`: build system or dependency change.
- `ci`: CI workflow change.
- `chore`: repository maintenance that does not affect released behavior.

Breaking changes must use either a `!` after the type or a `BREAKING CHANGE:` footer:

```text
feat(api)!: require authenticated station profiles
```

```text
feat(api): require authenticated station profiles

BREAKING CHANGE: unauthenticated saved station profiles must be migrated before use.
```

Examples:

```text
feat(feed): [DET-002] add live detection stream
fix(auth): [CON-005] refresh csrf token after login
docs(release): [NO-PLAN] document semantic-release workflow
test(api): [CON-002] add station config decoding fixtures
ci(release): [NO-PLAN] add semantic-release workflow
```

## Agent And Contributor Expectations

- Do not make a Git commit unless explicitly asked.
- When asked to commit, use a Conventional Commit message that semantic-release can analyze and include the relevant project plan step tag.
- Prefer small commits with one release meaning each.
- Do not manually edit generated release notes, tags, or version bumps unless the release automation itself is being fixed.
- If a change is user-visible, choose `feat`, `fix`, or `perf` instead of hiding it under `chore`.
- Keep release-impacting changes separate from unrelated documentation or cleanup when practical.

## Debug App Configuration

The app supports debug station configuration through launch arguments and environment variables:

```sh
xcrun simctl launch --terminate-running-process <device-id> org.odinseye.onpa --args -initialTab dashboard -stationURL http://192.168.1.50:8080 -debugShowStationManagement
```

Supported debug inputs:

- `-stationURL <url>` or `-debugStationURL <url>`: prefill and override the active station URL for the launch.
- `BIRDNET_GO_STATION_URL=<url>`: environment equivalent of `-stationURL`.
- `-useLocalStationProfile`: prefill a local test station profile when no station profile is saved.
- `-localStationURL <url>`: override the local test profile URL. Defaults to `http://localhost:8080`.
- `-debugDetectionID <id>`: open a detection detail screen on launch for visual simulator checks.
- `-debugSpeciesName <name>`: open a species detail screen after the Species or Dashboard tab loads for visual simulator checks.
- `-debugShowStationManagement`: open station management from the Dashboard navigation bar on launch for visual simulator checks.
- `-debugShowSettings`: open settings from the Dashboard station menu on launch for visual simulator checks.
- `-debugShowChangelog`: open the changelog screen (via Settings) on launch for visual simulator checks.
- `-debugShowDeleteStationConfirmation`: open the delete station confirmation after station management loads for visual simulator checks.
- `-initialTab <dashboard|feed|species>`: choose the launch tab. `stats` and `station` remain accepted as legacy aliases for `dashboard`.
- `BIRDNET_GO_USE_LOCAL_STATION_PROFILE=1`: environment equivalent of `-useLocalStationProfile`.
- `BIRDNET_GO_LOCAL_STATION_URL=<url>`: environment equivalent of `-localStationURL`.
- `BIRDNET_GO_DEBUG_DETECTION_ID=<id>`: environment equivalent of `-debugDetectionID`.
- `BIRDNET_GO_DEBUG_SPECIES_NAME=<name>`: environment equivalent of `-debugSpeciesName`.
- `BIRDNET_GO_DEBUG_SHOW_STATION_MANAGEMENT=1`: environment equivalent of `-debugShowStationManagement`.
- `BIRDNET_GO_DEBUG_SHOW_SETTINGS=1`: environment equivalent of `-debugShowSettings`.
- `BIRDNET_GO_DEBUG_SHOW_CHANGELOG=1`: environment equivalent of `-debugShowChangelog`.
- `BIRDNET_GO_DEBUG_SHOW_DELETE_STATION_CONFIRMATION=1`: environment equivalent of `-debugShowDeleteStationConfirmation`.

The active station profile and app preferences are persisted with `UserDefaults`. Station credentials remain Keychain-only, and session cookies remain ephemeral.

User-facing errors should flow through `AppError` so offline, authentication, TLS, rate limit, server, URL, and invalid station responses use consistent language across features. Station management opens from the Dashboard navigation bar and can generate a local diagnostics bundle for troubleshooting; diagnostics redact station hosts, usernames, tokens, cookies, and passwords before writing a shareable text file under the app caches directory.

## Screenshot Tooling

Use the tracked screenshot runner to refresh README images after visible UI changes:

```sh
npm run screenshots
```

The runner builds the Debug simulator app, starts [scripts/mock_birdnet_go_server.js](../scripts/mock_birdnet_go_server.js), installs the app on the simulator, launches the Dashboard, Feed, Species, and Dashboard station management views, and writes PNGs to [docs/screenshots](screenshots). The mock station can also be run on its own for manual checks:

```sh
npm run mock-station
```

Useful overrides:

- `DEVICE_NAME="iPhone 17"` and `IOS_VERSION=26.1` choose the simulator destination.
- `SCREENSHOT_DIR=path/to/output` writes screenshots somewhere else.
- `SKIP_BUILD=1` reuses the existing app in `build/DerivedData`.
- `MOCK_PORT=18082` avoids a port conflict with another local fixture.

## App Structure

The iOS app keeps foundation code in separate source areas so feature work can grow without mixing concerns:

- `src/Onpa/App`: SwiftUI app entry point, tab shell, app configuration, and dependency environment wiring.
- `src/Onpa/Domain`: shared app models, detection DTOs, and domain state.
- `src/Onpa/Networking`: BirdNET-Go API client protocols, URLSession implementations, and SSE stream parsing.
- `src/Onpa/Storage`: storage protocols, UserDefaults-backed profile/preference persistence, local cache storage, and Keychain-backed credential storage.
- `src/Onpa/Features`: user-facing SwiftUI feature modules such as Dashboard, Feed, DetectionDetail, Species, and Station. Feature view models own screen state and call dependencies through `AppEnvironment`.

## Changelog Pipeline

Settings > Changelog displays the contents of `CHANGELOG.md` bundled with the app build.

- **Local development builds** ship `src/Onpa/Resources/CHANGELOG.md` as a hard-coded placeholder so the screen always renders something. Edit that file freely while iterating; do not delete it.
- **GitHub release builds** generate a fresh root-level `CHANGELOG.md` via `@semantic-release/changelog`. `scripts/build_testflight_ipa.sh` then copies the generated file over `src/Onpa/Resources/CHANGELOG.md` immediately before `xcodebuild archive`, so the bundled changelog matches the release notes for that version. The file is also attached to the GitHub Release and committed back to `main` by `@semantic-release/git`, so future releases append to a growing history rather than overwriting it.
- The build script restores the dev placeholder on exit (success or failure) so local working copies aren't dirtied after a release run.

To preview the production changelog locally, run `npx semantic-release --dry-run --no-ci` from the repo root, then copy the generated `CHANGELOG.md` into `src/Onpa/Resources/` before rebuilding.

The Feed feature keeps recent-list refresh and live streaming separate: pull-to-refresh fetches `/api/v2/detections/recent?limit=10`, while the view model's live task listens to `/api/v2/detections/stream`, deduplicates incoming detections by ID, updates the same local cache, and reconnects with capped exponential backoff.

The Species feature loads `/api/v2/species` for station catalog enrichment and augments the list with recent detection summaries from `/api/v2/detections/recent`. Because BirdNET-Go stations may reject the catalog endpoint depending on configuration or version, catalog failures are quiet when recent detections can still populate the detected-species list. The species response decoder accepts both bare arrays and common response envelopes so it can tolerate BirdNET-Go API shape changes, and the merged list is cached per station for stale offline fallback. Species rows open detail pages that request `/api/v2/detections?queryType=species&species=<name>&numResults=<n>` for recent species-specific detections, use `/api/v2/media/species-image?name=<scientific-name>` for the hero image, and expose playable audio samples through `/api/v2/audio/:id`.

The Dashboard tab loads `/api/v2/analytics/species/daily?date=<yyyy-mm-dd>&limit=<n>` for the selected day and renders the returned `hourly_counts` as a per-species heatmap. Heatmap species rows link to the Species detail screen. It also fetches `/api/v2/detections/recent` for the Currently Hearing strip. If daily analytics are unavailable but recent detections load, the view builds a same-day summary from recent detections; successful dashboard payloads are cached per station and date for stale offline fallback.

Detection detail uses `/api/v2/detections/:id` for the canonical detail payload. Audio playback uses a station-relative `/api/v2/audio/:id` URL with `AVPlayer`; the auth-only clip extraction endpoint is intentionally left for later media editing work.

Species images on detection detail use `/api/v2/media/species-image?name=<scientific-name>` and attribution metadata from `/api/v2/media/species-image/info?name=<scientific-name>`. Attribution is treated as non-critical: missing or unavailable metadata does not block the detail screen, while available author and license values are shown on the image.

Weather and time-of-day context are loaded as non-critical detail supplements. The app requests `/api/v2/weather/detection/:id` for weather near the detection time and `/api/v2/detections/:id/time-of-day` for the explicit sun-position bucket, falling back to weather or detection payload values if the dedicated time-of-day endpoint is unavailable.

Spectrogram display uses the ID-based media endpoints with `size=lg&raw=true`, matching BirdNET-Go's compact web players by requesting an image without generated axes or legends. The app checks `/api/v2/spectrogram/:id/status` first, displays `/api/v2/spectrogram/:id` when the status is `exists` or `generated`, and fetches `/api/v2/app/config` so it can attach the current CSRF token before posting to `/api/v2/spectrogram/:id/generate`. Missing spectrograms are generated automatically by default; users can turn off Auto Fetch Spectrograms in Station > Media and generate them manually from the detail player. The detail media surface combines audio playback and spectrogram display so `AVPlayer` progress is overlaid as a vertical playhead on the image.
