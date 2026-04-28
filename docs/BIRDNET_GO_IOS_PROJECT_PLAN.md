# BirdNET-Go iOS Project Plan

Last updated: 2026-04-26
Status: Implementation started. FND-001 has established the native SwiftUI app shell.

## Purpose

Build a native iOS companion app for BirdNET-Go stations. The app should help a user connect to one or more BirdNET-Go instances, monitor live and historical bird detections, play related media, receive useful alerts, and eventually perform safe station administration from an iPhone or iPad.

This document is the long-term planning and progress tracker for Copilot and future contributors. Update it whenever a feature is implemented, deferred, redesigned, or blocked.

## Sources Consulted

- Local BirdNET-Go source: `/Users/jakeshirley/birdnet-go/`
- BirdNET-Go upstream repository: `https://github.com/tphakala/birdnet-go`
- BirdNET-Go API v2 docs: `/Users/jakeshirley/birdnet-go/internal/api/v2/README.md`
- BirdEcho, previously Perch, adjacent mobile app: `https://github.com/arunrajiah/birdecho`
- Apple iOS developer overview for iOS 26-era platform direction: `https://developer.apple.com/ios/`
- Apple Liquid Glass adoption guidance: `https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass`
- Apple Intelligence and WidgetKit developer guidance: `https://developer.apple.com/apple-intelligence/`, `https://developer.apple.com/widgets/`

## Product Direction

The app should be a direct BirdNET-Go companion, not a standalone bird classifier. BirdNET-Go remains the station-side analyzer and source of truth. The iOS app should focus on station connection, realtime monitoring, historical exploration, media playback, notifications, and selected station management.

Recommended initial stack:

- Native iOS app using Swift, SwiftUI, Swift Concurrency, Observation, and the latest stable Xcode/iOS SDK available when implementation begins.
- `URLSession` for REST and SSE networking, using async/await and a single shared realtime connection manager per station.
- `AVPlayer` for audio clips and HLS live audio.
- SwiftData for local cache, station profiles, and preferences unless real captured data shows a need for lower-level SQLite.
- Keychain for credentials and station tokens.
- UserNotifications for local notifications in the first release, with APNs and ActivityKit push notifications considered later if a server-side relay is introduced.
- WidgetKit, App Intents, ActivityKit, and Control Center controls as planned platform extensions, not initial app dependencies.
- Foundation Models and other Apple Intelligence APIs only for optional, privacy-preserving convenience features. BirdNET-Go remains the detection engine and source of truth.

Rationale: the app is iOS-specific, needs Keychain, background behavior, notifications, media playback, local network permissions, and a polished Apple platform experience. SwiftUI keeps the first app small while leaving room for iPad, widgets, controls, Live Activities, App Intents, and watchOS later. Build with the latest SDK to pick up current platform behavior, but gate iOS 26-only APIs with availability checks if the minimum deployment target is older.

## Current iOS Platform Direction

These notes reflect current Apple platform guidance as of April 2026. They should be revisited after WWDC26 and whenever the project chooses a minimum iOS version.

| Area | Planning Impact |
| --- | --- |
| iOS 26 design | Use standard SwiftUI navigation, lists, forms, sheets, toolbars, controls, and system colors so the app adopts Liquid Glass automatically. Avoid hard-coded custom chrome that would fight the system material. |
| Navigation | Keep the tab-based phone app, but structure it so `TabView` can adapt to iPad sidebars with `NavigationSplitView` and sidebar-adaptable tab behavior. Consider a dedicated Search tab role once search becomes a primary workflow. |
| Forms and settings | Prefer SwiftUI `Form` and standard grouped layouts for station setup, settings, and admin screens. Test larger row metrics, sheet corners, reduced transparency, increased contrast, and reduced motion. |
| Icons and visual assets | Plan a layered app icon using Icon Composer, plus SF Symbols for toolbar/menu actions. Avoid custom icon treatments that duplicate system effects. |
| Widgets and Live Activities | Treat WidgetKit as a single strategy for widgets, Live Activities, controls, and watch complications. Start with one glanceable feature, then expand across contexts. |
| App Intents | Model core user actions as App Intents over time: open latest detection, check station status, start live audio, show favorite species, and refresh widgets/controls. |
| Apple Intelligence | Consider Foundation Models for optional local summarization, natural-language filtering, and station diagnostics explanations. Do not use generative features for species identification decisions or anything that changes station state without explicit user action. |
| Passkeys | Passkeys are worth supporting only if BirdNET-Go or an upstream auth provider exposes WebAuthn/OIDC flows that can work cleanly on iOS. Do not invent an app-only auth scheme. |
| Background behavior | iOS still constrains long-running background networking. Plan foreground SSE, cache-aware widgets, APNs-backed updates, and explicit background audio policy instead of assuming continuous background polling. |

## BirdNET-Go Integration Surface

BirdNET-Go exposes a v2 HTTP API under `/api/v2`. There is no OpenAPI spec in the current local source, so the canonical API reference is the BirdNET-Go API README in `internal/api/v2/README.md`.

Key endpoints for the initial app:

| Area | Endpoint | Notes |
| --- | --- | --- |
| Connectivity | `GET /api/v2/ping` | Lightweight online check. |
| Health | `GET /api/v2/health` | Station health check. |
| App config | `GET /api/v2/app/config` | Public config, security state, version, CSRF token source. |
| Auth | `POST /api/v2/auth/login` | Login with server-side rate limiting. |
| Auth | `POST /api/v2/auth/logout` | Auth required. |
| Auth | `GET /api/v2/auth/status` | Auth required. |
| Detection list | `GET /api/v2/detections` | Public detection list with filtering. |
| Recent detections | `GET /api/v2/detections/recent` | Public recent feed. |
| Detection detail | `GET /api/v2/detections/:id` | Public detection detail. |
| Search | `POST /api/v2/search` | Public advanced search. |
| Live detections | `GET /api/v2/detections/stream` | Public, rate-limited SSE. |
| Sound levels | `GET /api/v2/soundlevels/stream` | Public, rate-limited SSE. |
| Audio levels | `GET /api/v2/streams/audio-level` | Public SSE, connection-limited. |
| Audio clip | `GET /api/v2/audio/:id` | Public playback by detection ID. |
| Spectrogram | `GET /api/v2/spectrogram/:id` | Public spectrogram image by detection ID. |
| Spectrogram status | `GET /api/v2/spectrogram/:id/status` | Public generation status by detection ID. |
| Spectrogram generate | `POST /api/v2/spectrogram/:id/generate` | Public async generation request by detection ID. |
| Species image | `GET /api/v2/media/species-image` | Public thumbnail/metadata flow. |
| Species list | `GET /api/v2/species` | Public species info. |
| Species taxonomy | `GET /api/v2/species/taxonomy` | Public taxonomy hierarchy. |
| Analytics | `GET /api/v2/analytics/species/daily` | Public daily species summary. |
| Analytics | `GET /api/v2/analytics/species/summary` | Public overall species stats. |
| Analytics | `GET /api/v2/analytics/time/hourly` | Public hourly patterns. |
| HLS start | `POST /api/v2/streams/hls/:sourceID/start` | Auth required unless station enables public live audio. |
| HLS playlist | `GET /api/v2/streams/hls/t/:streamToken/playlist.m3u8` | Token-based access, good fit for `AVPlayer`. |
| HLS heartbeat | `POST /api/v2/streams/hls/heartbeat` | Keeps a stream alive. |
| Stream status | `GET /api/v2/streams/status` | Auth required. |
| Stream health SSE | `GET /api/v2/streams/health/stream` | Auth required SSE. |
| Settings dashboard | `GET /api/v2/settings/dashboard` | Public non-sensitive display preferences. |
| Settings full | `GET /api/v2/settings` | Auth required. |
| System info | `GET /api/v2/system/info` | Auth required. |
| System resources | `GET /api/v2/system/resources` | Auth required. |
| Notifications stream | `GET /api/v2/notifications/stream` | Public, rate-limited SSE. |
| Alerts | `/api/v2/alerts/*` | Mixed public/auth endpoints, requires v2 database. |
| Insights | `/api/v2/insights/*` | Public endpoints, requires v2 database. |

Important integration constraints:

- Mutating endpoints use CSRF protection. The app must fetch `/api/v2/app/config`, retain the CSRF token, and attach it to state-changing requests according to BirdNET-Go expectations.
- Auth may be BasicAuth, OAuth2/OIDC, token, API key, browser session, or local subnet depending on station configuration. The first iOS version should support the common direct login flow and be designed so other auth modes can be added cleanly.
- Some endpoints are intentionally public read-only. The app should still treat the station URL as private user data.
- HLS live audio returns a `stream_token` and playlist URL. This avoids custom-header problems with native media playback.
- Realtime streams are SSE and rate-limited. The app should reconnect with backoff and avoid opening duplicate streams.
- Some newer features, including alerts and insights, can return `409 Conflict` when the enhanced v2 database is unavailable.
- BirdNET-Go can use self-signed or local TLS. The app should plan an explicit trust model for local stations before any broad release.

## Initial App Goal

Ship a useful read-focused iOS app that connects directly to a BirdNET-Go station and gives the user a live pocket view of detections.

Initial app scope:

1. Connect to a BirdNET-Go base URL.
2. Validate station connectivity and fetch app config.
3. Log in when required and store credentials/tokens securely.
4. Show live and recent detections.
5. Show detection detail with species data, confidence, time, audio playback, and spectrogram when available.
6. Support pull-to-refresh, basic filtering, and local cache for graceful offline behavior.
7. Provide a small settings area for station connection, theme, cache reset, diagnostics, and logout.

Explicitly out of scope for the first implementation pass:

- On-device bird identification.
- Station setup wizard or full configuration editing.
- Push notification backend.
- watchOS, widgets, and Live Activities.
- Multi-station synchronization.
- Full admin controls such as restart, model reload, TLS uploads, or support dumps.

## Information Architecture

Initial navigation should be tab-based:

| Tab | Initial Purpose | Long-Term Direction |
| --- | --- | --- |
| Feed | Live and recent detections. | Advanced filters, saved views, realtime events, new species badges. |
| Species | Species detected by the station. | Species profiles, favorite species, seasonal history, taxonomy browsing. |
| Dashboard | Daily activity and simple weekly charts. | Insights, migration patterns, dawn chorus, weather overlays. |
| Station | Connection, status, and account. | Stream health, resource usage, settings, admin controls. |

Detection detail should be reachable from Dashboard, Feed, Species, notifications, and search results.

## Long-Term Feature Backlog

Status values: `not-started`, `in-progress`, `done`, `blocked`, `deferred`.

### Foundation

| ID | Status | Feature | Notes |
| --- | --- | --- | --- |
| FND-001 | done | Native SwiftUI app shell | Xcode project, shared scheme, SwiftUI app entry point, Dashboard/Feed/Species tab shell, and Dashboard station management entry point. |
| FND-002 | done | App architecture | Added App, Domain, Networking, Storage, and Features boundaries with environment-injected API and profile store protocols. |
| FND-003 | done | Environment configuration | Added launch/environment station URL overrides and an opt-in local network test profile. |
| FND-004 | done | Local persistence | Persists active station profile and preferences locally; adds a file-backed cache foundation for future detection/species payloads. |
| FND-005 | done | Error model | Shared `AppError` maps offline, auth, TLS, rate limit, server, URL, and invalid station responses to user-friendly recovery messages. |
| FND-006 | done | Logging and diagnostics | Dashboard station management generates a local diagnostics text bundle with station hosts, usernames, tokens, cookies, and passwords redacted. |
| FND-007 | done | Accessibility baseline | Combined-element VoiceOver labels and values across Stats KPIs/heatmap/hourly bars/hearing rows, Feed detection rows, Species rows and detail metrics, Detection detail weather chips, plus reduced-motion gating on the live-feed insertion animation. AGENTS.md captures the ongoing baseline (Dynamic Type, VoiceOver labels, contrast tokens, reduced motion, 44pt hit targets). |
| FND-008 | not-started | Localization foundation | Prepare app strings for BirdNET-Go's multilingual audience. |
| FND-009 | done | Liquid Glass-ready design system | DesignSystem token namespace (DS.accent, DS.Surface, DS.Shape, DS.Radius, DS.AccentTint, DS.Overlay) centralizes accent color, system surface tones, and standard radii so views adopt platform colors and SF Symbols by default with minimal custom chrome. |
| FND-010 | not-started | Availability-gated platform features | Wrap iOS 26-only APIs so the deployment target can be chosen deliberately. |

### Station Connection and Security

| ID | Status | Feature | Notes |
| --- | --- | --- | --- |
| CON-001 | done | Manual station connection | Dashboard station management accepts a base URL and validates `/ping` plus `/app/config`. |
| CON-002 | done | Connection validation | Validates URL scheme, host, TLS state, BirdNET-Go app config identity, and version. |
| CON-003 | done | Secure credential storage | Basic-auth credentials are saved only through Keychain; session cookies use an ephemeral URLSession. |
| CON-004 | done | Login/logout | Supports password-only simple auth via BirdNET-Go's compatibility username, direct `/auth/login`, auth-code callback completion, `/auth/status`, and `/auth/logout`. |
| CON-005 | not-started | CSRF handling | Fetch and attach CSRF token for mutations. |
| CON-006 | not-started | Local network discovery | Explore Bonjour/mDNS or subnet scan if BirdNET-Go exposes discoverable metadata. |
| CON-007 | not-started | Self-signed TLS flow | Explicit user approval, certificate fingerprint display, revocation/reset. |
| CON-008 | not-started | Multiple station profiles | Add, switch, rename, and remove stations. |
| CON-009 | not-started | Remote access guidance | Handle Cloudflare tunnel, reverse proxy, VPN, and local-only stations. |
| CON-010 | not-started | Auth mode expansion | Add API key, token, OAuth/OIDC, and local subnet-aware UX as needed. |
| CON-011 | not-started | Passkey/OIDC readiness | Support only if BirdNET-Go or a configured auth provider exposes compatible flows. |

### Detection Feed

| ID | Status | Feature | Notes |
| --- | --- | --- | --- |
| DET-001 | done | Recent detections list | Feed tab loads `/detections/recent?limit=10`, renders recent detections, and falls back to cached results when available. |
| DET-002 | done | Live SSE feed | Feed tab connects to `/detections/stream`, merges live detection events into the recent list, and reconnects with exponential backoff up to 30 seconds. |
| DET-003 | done | Pull-to-refresh | Manual refresh reloads `/detections/recent?limit=10` and preserves the active live stream task. |
| DET-004 | not-started | Infinite history | Paginate older detections. |
| DET-005 | not-started | Detection cards | Species, confidence, time, thumbnail, source, reviewed/locked states if available. |
| DET-006 | not-started | Feed filters | Date, species, confidence, source, reviewed, locked, favorites. |
| DET-007 | not-started | Search | Use `/search` for advanced query support. |
| DET-008 | not-started | Offline feed cache | Last successful data remains viewable offline. |
| DET-009 | not-started | New species highlighting | Use analytics or local history to identify first-seen species. |
| DET-010 | not-started | Feed sharing | Share a detection summary card with image/audio attribution. |

### Detection Detail and Media

| ID | Status | Feature | Notes |
| --- | --- | --- | --- |
| MED-001 | done | Detection detail screen | Feed rows open a detail screen backed by `/detections/:id`, with species, confidence, time, source, clip, and status fields. |
| MED-002 | done | Audio clip playback | Detail screen builds a station-relative `/audio/:id` URL and plays available clips with `AVPlayer`. |
| MED-003 | done | Spectrogram display | Detail screen checks `/spectrogram/:id/status`, auto-generates missing spectrograms when the default-on setting is enabled, and overlays audio playback position on the station-relative `/spectrogram/:id` PNG. |
| MED-004 | done | Species image and attribution | Detection detail loads `/media/species-image` by scientific name and shows `/media/species-image/info` author/license attribution when available. |
| MED-005 | done | Weather context | Detail screen loads `/weather/detection/:id` when available and shows weather, temperature, wind, humidity, pressure, location, and sun times without blocking core detection data. |
| MED-006 | done | Time-of-day context | Detail screen loads `/detections/:id/time-of-day` and falls back to weather or detection payload time-of-day context when needed. |
| MED-007 | not-started | Clip extraction | Auth-only future feature using `/audio/:id/clip`. |
| MED-008 | not-started | Save/share audio | Respect station privacy and media attribution. |
| MED-009 | not-started | Review and lock actions | Auth-only future actions. |
| MED-010 | not-started | Delete detection | Auth-only admin action with confirmation. |

### Species Experience

| ID | Status | Feature | Notes |
| --- | --- | --- | --- |
| SPC-001 | done | Detected species list | Species tab loads `/species`, augments rows with recent detection summaries, and caches per station for offline fallback. |
| SPC-002 | done | Species detail | Species and Dashboard rows open detail pages with station images, recent species detections, and playable clip samples. |
| SPC-003 | not-started | Favorites | Local favorites first, sync or station rules later. |
| SPC-004 | not-started | Taxonomy browsing | Use `/species/taxonomy`. |
| SPC-005 | not-started | Rarity and range indicators | Use BirdNET-Go species and range filter endpoints. |
| SPC-006 | not-started | Ignore species management | Auth-only future feature using `/detections/ignore`. |
| SPC-007 | not-started | Species notes | Local notes first, station-backed if BirdNET-Go adds support. |
| SPC-008 | not-started | Similar species education | Future content layer, avoid copyrighted field guide text. |

### Analytics and Insights

| ID | Status | Feature | Notes |
| --- | --- | --- | --- |
| ANA-001 | done | Daily counts | Dashboard loads `/analytics/species/daily` and caches per station/date. |
| ANA-002 | not-started | Species summary | Use `/analytics/species/summary`. |
| ANA-003 | done | Hourly activity chart | Dashboard renders per-species hourly heatmap from daily analytics `hourly_counts`, with recent-detection fallback. |
| ANA-004 | not-started | Daily trend chart | Use `/analytics/time/daily`. |
| ANA-005 | not-started | New species timeline | Use `/analytics/species/detections/new`. |
| ANA-006 | not-started | Dashboard KPIs | Use `/dashboard/kpis` when v2 database supports it. |
| ANA-007 | not-started | Expected today | Use `/insights/expected-today`. |
| ANA-008 | not-started | Regional expected species | Use `/insights/expected-today/regional`. |
| ANA-009 | not-started | Phantom species | Use `/insights/phantom-species`. |
| ANA-010 | not-started | Dawn chorus and migration insights | Use `/insights/dawn-chorus` and `/insights/migration`. |
| ANA-011 | not-started | Weather overlays | Use weather endpoints for context. |
| ANA-012 | not-started | Export stats | CSV, image, or share sheet later. |
| ANA-013 | not-started | On-device summaries | Optional Foundation Models summaries of station trends, with plain-data fallback. |
| ANA-014 | not-started | Natural-language filters | Optional local query parsing into explicit BirdNET-Go filters; never bypass normal filter review. |

### Live Audio and Source Monitoring

| ID | Status | Feature | Notes |
| --- | --- | --- | --- |
| AUD-001 | not-started | Audio level meter | Use `/streams/audio-level`. |
| AUD-002 | not-started | Sound level stream | Use `/soundlevels/stream`. |
| AUD-003 | not-started | HLS live audio start | Use `/streams/hls/:sourceID/start`. |
| AUD-004 | not-started | HLS playback | Use tokenized playlist URL with `AVPlayer`. |
| AUD-005 | not-started | HLS heartbeat | Keep active streams alive while playing. |
| AUD-006 | not-started | Stream picker | Select available source once station exposes/sanitizes source list. |
| AUD-007 | not-started | Stream health | Use `/streams/status`, `/streams/health`, and health SSE. |
| AUD-008 | not-started | Quiet hours status | Use `/streams/quiet-hours/status`. |
| AUD-009 | not-started | Background audio policy | Decide if live station audio should continue in background. |
| AUD-010 | not-started | Clipping and silence warnings | Surface source health in station management. |

### Notifications and Alerts

| ID | Status | Feature | Notes |
| --- | --- | --- | --- |
| NTF-001 | not-started | Local favorite notifications | Notify once per species per day while app can observe feed. |
| NTF-002 | not-started | Notification preferences | Species, confidence threshold, quiet hours, station selection. |
| NTF-003 | not-started | In-app notification list | Use `/notifications` and unread count. |
| NTF-004 | not-started | Notification SSE | Use `/notifications/stream` while foregrounded. |
| NTF-005 | not-started | Background refresh strategy | Evaluate iOS limits for polling and SSE. |
| NTF-006 | not-started | Push notification relay | Future service if true background alerts are required. |
| NTF-007 | not-started | BirdNET-Go alert rules view | Use `/alerts/rules` when v2 database is available. |
| NTF-008 | not-started | Alert rule editor | Auth-only future feature. |
| NTF-009 | not-started | Alert history | Use `/alerts/history`. |

### Station Status and Administration

| ID | Status | Feature | Notes |
| --- | --- | --- | --- |
| ADM-001 | not-started | Station status summary | Health, version, auth state, current source state. |
| ADM-002 | not-started | System info | Use `/system/info`. |
| ADM-003 | not-started | Resource usage | Use `/system/resources` and disks endpoints. |
| ADM-004 | not-started | Audio devices | Use `/system/audio/devices` and active device endpoint. |
| ADM-005 | not-started | Settings read-only viewer | Use `/settings` for authenticated users. |
| ADM-006 | not-started | Dashboard settings | Use `/settings/dashboard` public endpoint. |
| ADM-007 | not-started | Safe settings editing | Limited, high-confidence settings first. |
| ADM-008 | not-started | Restart analysis | Auth-only, guarded action using `/control/restart`. |
| ADM-009 | not-started | Reload model | Auth-only, guarded action using `/control/reload`. |
| ADM-010 | not-started | Rebuild range filter | Auth-only or public endpoint depending on BirdNET-Go behavior. |
| ADM-011 | not-started | Support bundle | Auth-only support generation/download. |
| ADM-012 | not-started | TLS certificate status | View status first, editing much later. |
| ADM-013 | not-started | Integration status | MQTT, BirdWeather, weather, eBird status checks. |

### Platform Extensions

| ID | Status | Feature | Notes |
| --- | --- | --- | --- |
| PLT-001 | not-started | iPad layout | Sidebar and multi-column detection detail. |
| PLT-002 | not-started | Widgets | Recent detection, species of day, station status, favorite species. Start with one size and plan expansion. |
| PLT-003 | not-started | Live Activity | Active station listening status or live species ticker, likely APNs-backed for reliable background updates. |
| PLT-004 | not-started | watchOS companion | Favorite species alerts and quick recent detections. |
| PLT-005 | not-started | Shortcuts integration | App Intents for latest detection, station status, favorite species, and live audio. |
| PLT-006 | not-started | Spotlight indexing | Species and recent detections if privacy setting allows. |
| PLT-007 | not-started | App intents | Reusable app actions for Shortcuts, Siri, widgets, controls, and Apple Intelligence surfaces. |
| PLT-008 | not-started | Control Center controls | App Intent-backed controls for opening station status or starting a supported live audio flow. |
| PLT-009 | not-started | Layered app icon | Create a Liquid Glass-era icon with Icon Composer, light/dark/clear/tinted appearance checks. |
| PLT-010 | not-started | Semantic search tab | Use the platform search tab role if search becomes a top-level destination. |
| PLT-011 | not-started | On-device intelligence features | Optional Foundation Models features for summaries, troubleshooting explanations, and filter suggestions. |

### Privacy, Compliance, and Trust

| ID | Status | Feature | Notes |
| --- | --- | --- | --- |
| PRV-001 | not-started | Privacy policy | Explain station URL, credentials, detection cache, notifications. |
| PRV-002 | not-started | Secret redaction | Never log passwords, tokens, station URLs with credentials, or CSRF tokens. |
| PRV-003 | not-started | Cache controls | Clear all local data per station. |
| PRV-004 | not-started | Per-station privacy mode | Hide exact location/source metadata where possible. |
| PRV-005 | not-started | Attribution handling | Species images, eBird/Clements taxonomy, BirdNET-Go license notes. |
| PRV-006 | not-started | App Store review checklist | Local network permission text, background modes, user data disclosure. |
| PRV-007 | not-started | Apple Intelligence privacy review | Document what data stays on-device, what is sent to BirdNET-Go, and how generative output is labeled. |

## Milestones

### Milestone 0: Planning and Validation

Status: not-started

Deliverables:

- Confirm app name, bundle identifier, minimum iOS version, and target devices.
- Decide whether the first implementation targets iOS 26 directly or supports an older minimum with iOS 26 feature gates.
- Confirm direct BirdNET-Go API as primary integration path.
- Decide first auth modes to support.
- Decide how self-signed TLS should be handled.
- Capture sample API responses from a local BirdNET-Go station.
- Review post-WWDC26 SDK changes before implementation if work begins after the conference.
- Convert this plan into GitHub issues or a project board if desired.

Exit criteria:

- Product scope for the first usable app is agreed.
- API response shapes needed for the initial app are captured in fixtures.
- No station secrets are committed.

### Milestone 1: Initial Usable App

Status: not-started

Deliverables:

- SwiftUI app shell with Dashboard, Feed, and Species tabs plus station management in the Dashboard navigation bar.
- Standard SwiftUI navigation, forms, lists, sheets, and toolbars that adopt current iOS design automatically.
- Manual station connection flow.
- Connectivity check using `/ping`, `/health`, and `/app/config`.
- Login/logout for protected stations.
- Secure credential storage in Keychain.
- Recent detections feed.
- Detection detail with audio clip playback.
- Basic species list.
- Basic daily/hourly stats.
- Offline cache for last viewed data.
- Settings screen for station profile, theme, cache reset, diagnostics, and logout.

Exit criteria:

- A user with a running BirdNET-Go station can connect and browse recent detections.
- Detection audio playback works for available clips.
- The app handles offline, invalid URL, auth failure, and station unavailable states gracefully.
- The app passes a basic visual review with standard and accessibility display settings.

### Milestone 2: Realtime Companion

Status: not-started

Deliverables:

- Live detection SSE integration.
- Audio level and sound level streams.
- Reconnect/backoff logic.
- Favorite species.
- Foreground/local notifications for favorites.
- New species indicators.
- Improved feed filtering and search.

Exit criteria:

- Foreground app updates without manual refresh.
- Realtime networking does not leak duplicate connections.
- Notification preferences are understandable and reversible.

### Milestone 3: Media and Live Audio

Status: not-started

Deliverables:

- Spectrogram status and display.
- Species images with attribution.
- HLS live audio playback.
- HLS heartbeat management.
- Stream status and quiet hours display.
- Detection share card.

Exit criteria:

- The user can listen to live station audio when supported and authorized.
- Media loading is resilient to missing clips, missing images, and station permission differences.

### Milestone 4: Station Insight

Status: not-started

Deliverables:

- Analytics dashboards.
- Expected-today, regional, phantom species, dawn chorus, and migration insights when available.
- Weather overlays.
- Station health, resource usage, disks, and source health.
- In-app notifications list.

Exit criteria:

- The app explains station activity over time, not just individual detections.
- v2-database-only features degrade gracefully when unavailable.

### Milestone 5: Safe Administration

Status: not-started

Deliverables:

- Read-only settings viewer.
- Selected settings editing with validation.
- Review, lock, ignore, and delete detection actions.
- Alert rule viewing and editing.
- Restart/reload controls with clear confirmation.
- Support bundle generation/download.

Exit criteria:

- Any destructive or station-affecting action requires auth, confirmation, and clear feedback.
- CSRF and auth behavior are fully covered by tests.

### Milestone 6: Platform Polish

Status: not-started

Deliverables:

- iPad layout.
- Widgets.
- Live Activities.
- Shortcuts/App Intents.
- Control Center controls.
- Layered app icon and current iOS appearance variants.
- Optional Foundation Models-powered summaries and query assistance.
- watchOS companion investigation or prototype.
- Localization pass.
- Accessibility audit.

Exit criteria:

- The app feels at home across Apple devices and remains useful with accessibility features enabled.

## Initial Technical Work Items

Use these when implementation begins. Do not treat them as started yet.

| ID | Status | Work Item | Acceptance Criteria |
| --- | --- | --- | --- |
| TECH-001 | not-started | Create iOS project | Project builds in Xcode without app logic beyond template shell. |
| TECH-002 | not-started | Define API client protocol | Supports base URL, request building, decoding, auth, CSRF, and errors. |
| TECH-003 | not-started | Define station profile model | Stores name, base URL, auth mode, trust metadata, and last connection state. |
| TECH-004 | not-started | Add Keychain service | Credentials are stored, read, updated, and deleted securely. |
| TECH-005 | not-started | Add fixture-based tests | API models decode captured BirdNET-Go responses. |
| TECH-006 | not-started | Add SSE client | Handles events, cancellation, reconnect, and backoff. |
| TECH-007 | not-started | Add media service | Builds safe station-relative media URLs and supports `AVPlayer`. |
| TECH-008 | not-started | Add local cache | Stores recent detections and species per station. |
| TECH-009 | not-started | Add UI state model | Loading, empty, error, offline, and stale-cache states are explicit. |
| TECH-010 | not-started | Add diagnostics screen | Shows app version, station URL host, API version, auth state, and redacted logs. |
| TECH-011 | not-started | Add platform availability layer | Centralizes iOS 26 feature checks and fallbacks. |
| TECH-012 | not-started | Add App Intents foundation | Defines stable intents for station status, latest detection, favorite species, and live audio. |
| TECH-013 | not-started | Add WidgetKit data provider | Shares sanitized, cache-backed data with widgets, controls, and Live Activities. |
| TECH-014 | not-started | Add optional intelligence service | Wraps Foundation Models features behind capability checks and clear user consent. |

## Data Model Notes

Initial domain models likely needed:

- `StationProfile`: local station metadata and connection settings.
- `StationConfig`: response from `/app/config`, including version/security/CSRF-related fields.
- `AuthSession`: authenticated state without exposing raw secrets to UI.
- `Detection`: station detection item from list/detail endpoints.
- `Species`: common name, scientific name, code, rarity, thumbnail metadata.
- `DetectionMedia`: audio URL, spectrogram URL/status, image attribution.
- `AnalyticsSummary`: daily species counts, hourly patterns, totals.
- `StreamState`: HLS token, playlist URL, source ID, heartbeat state.
- `StationHealth`: ping, health, resources, stream status, auth state.

Before coding against these models, capture real JSON samples from BirdNET-Go and make model definitions match actual response shapes.

## Testing Strategy

Planned test coverage:

- Unit tests for URL building, query encoding, and endpoint path handling.
- Unit tests for JSON decoding using captured BirdNET-Go fixtures.
- Unit tests for auth, CSRF, Keychain wrapper behavior, and redaction.
- Unit tests for SSE parsing and reconnect policy.
- UI tests for connection flow, empty states, offline states, feed, and detail playback affordances.
- Visual checks for Liquid Glass-era navigation, forms, tab bars, sheets, widgets, reduced transparency, reduced motion, and increased contrast.
- Availability tests or compile checks for iOS 26-only features and fallbacks on the chosen minimum deployment target.
- Manual integration checklist against a local BirdNET-Go station with auth disabled, auth enabled, self-signed TLS, and unavailable server states.

No tests have been written yet because implementation has not started.

## Open Questions

- What should the app be called?
- What minimum iOS version should be supported?
- Should the app require iOS 26 for the first release, or support an older minimum while using iOS 26 APIs opportunistically?
- Should the first release support only direct BirdNET-Go HTTP API, or also BirdWeather as an optional fallback?
- Which BirdNET-Go auth modes are required for the first release?
- Should self-signed certificates be supported in the first release or deferred?
- Should live audio continue while the app is backgrounded?
- Should favorite species notifications work only while the app is foreground/background-refresh capable, or should a push relay be planned early?
- Should multi-station support be part of v1 or a later release?
- Are Apple Intelligence/Foundation Models features desirable for this app, or should the product remain entirely deterministic?
- Which widgets, controls, or Live Activities are genuinely useful enough to justify APNs/backend work?
- Is this app intended for personal sideload/TestFlight use first, or public App Store distribution?

## Copilot Progress Tracking Rules

When Copilot or a contributor implements work:

1. Update the relevant status in this document.
2. Add new rows instead of overloading broad rows when work becomes concrete.
3. Keep statuses honest. Use `blocked` with a short reason when a dependency is missing.
4. Add implementation notes only when they help future work.
5. Record new API discoveries in the integration table or a short note near it.
6. Add or update acceptance criteria before marking a feature `done`.
7. Do not store credentials, station URLs with embedded secrets, API tokens, CSRF tokens, or private local network details in this file.
8. If the BirdNET-Go API changes, update the endpoint inventory before coding against the new behavior.

## Current Progress Summary

| Date | Change | Notes |
| --- | --- | --- |
| 2026-04-26 | Created initial project plan | Planning artifact only. No implementation started. |
| 2026-04-26 | Refreshed iOS technology plan | Added iOS 26-era guidance for Liquid Glass, App Intents, WidgetKit, ActivityKit, controls, and optional Foundation Models features. |
| 2026-04-26 | Added semantic-release guidance | Added developer documentation and local Copilot instructions for semantic-release-compatible commits. |
