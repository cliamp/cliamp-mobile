# iOS port: parity plan and progress tracker

Port the current Android app to iOS with parity in **features, appearance, and experience**. A working audio player alone is not completion: navigation, queue semantics, feedback, persistence, recovery, and the cliamp visual identity all count.

## Baseline and scope

- Baseline inspected: Android source at `21782fd233b4ab089dc1e6ea56e758a2aa2a8477`, on 2026-09-16.
- Claude's independent review has been incorporated into this single execution plan. Review corrections refine the existing task IDs; they do not imply implementation or device verification.
- Target: the new client in [`ios/`](../ios/). That directory currently holds only the `FND-01` scaffold (project generation, CI, placeholder shell); no product implementation is credited below.
- This inventory comes from source inspection, not a device audit. Phase 0 captures the running Android reference and resolves discrepancies before they become requirements.
- Source order: current implementation and verified behavior, then [queue contract](queue-behavior.md), then [design system](design.md). The [concept](concept.md) and older README screen lists provide history, not the current navigation specification.
- Default planning scope: iPhone, portrait and landscape. Minimum iOS version and iPad support are decisions in `FND-01`; neither is silently assumed complete.
- Native iOS implementation lives independently of Android. Share design tokens, fixtures, vocabulary, and behavior contracts; do not require shared application code.
- Each phase can produce an internal usable build. Finishing a phase is not a claim of full parity. All phases and unresolved differences remain visible through release.

### Baseline discrepancies to resolve

| Topic | What the inspected source says | Planning consequence |
| --- | --- | --- |
| Navigation | `NavRoutes.kt` / `CliampRoot.kt` have Stations, Podcasts, Library, plus detail screens and overlays. | Do not recreate the older PLAY / LIB / QUEUE / :CMD / STATS tab list. |
| Terminal mode | No Terminal mode setting, PTY host, or terminal route found in this Android baseline. | Outside this port's current parity denominator. If introduced later, follow [AGENTS.md](../AGENTS.md): use the real cliamp TUI, never a SwiftUI imitation. Feasibility requires its own decision. |
| Statistics | Directory counts exist in Settings; no standalone historical STATS route found. | Port the counts and local song play statistics. Treat a historical radio statistics screen as new scope. |
| Listener counts | The cliamp section shows its channel count; station rows can show Radio Browser votes. No live-listener fetch/rendering was found. | RAD-01 requires channel counts, not live listeners. Live listener counts would be new scope. |
| Buffer control | The preference is read once at player construction. The maximum buffer is four times the setting, bounded to 60–180 seconds. | Capture the exact thresholds below; DEC-01 must distinguish baseline behavior from any deliberate live-update improvement. |
| Local library | Android queries MediaStore music after permission, without a per-file import step. | Compare iOS media-library access and Files-based options in DEC-02; record any added import steps as an experience difference. |
| Cellular toggle | Settings says “Stream over cellular”; the consumer found is the download manager's unmetered-network check. | `DEC-04` must settle expected streaming enforcement. Do not claim Android already enforces it for all playback. |
| Widget visualization | `WidgetRenderer.kt` pushes FFT bitmap updates; the design document's static-widget description is stale. | Capture actual Android behavior and decide an iOS equivalent in `DEC-03`; do not promise identical update cadence. |
| Copy / color rules | Source includes title-case screen/settings labels, oxide red accents, and error text using `destructiveInk`. | Use captured source screens and semantic roles. Do not mechanically enforce older “all lowercase” or “red only destructive” prose over current UI. |
| Defaults | `Prefs.kt` persists a 30-second default buffer; temporary UI state declares other initial values. | Use persistent defaults, verify first-frame behavior, and avoid copying placeholder state as the product contract. |

Not baseline features: sleep timer, repeat modes, Last.fm, cloud sync, cross-device queue transfer, CarPlay, watchOS, Live Activities, live theme editing, TOML themes, or arbitrary provider downloads. Adding any requires a new scoped row. Full queue restoration after process death is explicitly absent from the current queue contract.

## How to execute and update this file

1. Select the next dependency-ready ID. Set its state to `W` and add an owner and issue/branch link in Evidence. Work on one reviewable slice; split large rows into stable suffixed IDs if needed.
2. Read the source group listed for that phase and reproduce the Android behavior with the same fixture. Resolve uncertainty as a decision, not an undocumented implementation choice.
3. Implement the slice, including empty/loading/error states and persistence where applicable. Record tests and device observations.
4. Sign off three gates independently: **F** = functional behavior, **V** = visuals, **X** = interaction and experience. Store results in `F/V/X` order. `—` means unchecked, `P` passed, `!` failed, `NA` not applicable with a reason in Evidence.
5. Set `D` only when all applicable gates pass and evidence is linked. `R` means implemented but awaiting review; it does not count as done. Update the phase summary and activity log in the same change.

States: `N` not started; `W` working; `B` blocked; `R` ready for verification; `D` verified done; `E` accepted platform exception. A blocked row needs the dependency, owner, and next action. An exception needs a decision record naming the limitation, alternative experience, approver, and date. It remains a difference, never a parity pass.

Progress is **D / all scoped task rows**, with E and B reported separately. Splitting or adding rows changes the denominator explicitly. Phase 0 is engineering preparation, so also report product parity across phases 1–7 separately. Never infer progress from files created, code size, or a passing build.

### Phase summary

| Phase | Deliverable | Depends on | Done / scoped | Exceptions | Blocked | State |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | Reference evidence and feasible foundation | — | 0 / 5 | 0 | 0 | W |
| 1 | Recognizable cliamp shell and design system | 0 | 0 / 8 | 0 | 0 | W |
| 2 | Radio works end to end, including background playback | 1; FND-03 audio spike; DEC-07 transport decision | 0 / 12 | 0 | 0 | W |
| 3 | Queue, local library, playlists, and search | 2 | 0 / 13 | 0 | 0 | N |
| 4 | Podcasts, resume, and offline listening | 3 queue and storage | 0 / 8 | 0 | 0 | N |
| 5 | Every current server provider | 3 queue and storage; provider spike in 0 | 0 / 12 | 0 | 0 | N |
| 6 | Settings, audio character, scrobbling, and system surfaces | 2; FND-01 minimum OS and DEC-03 surface mapping; integrate 4 and 5 | 0 / 9 | 0 | 0 | W |
| 7 | Cross-feature and release acceptance | 1–6 | 0 / 5 | 0 | 0 | N |

Initial total: **0 / 72 tasks verified**, **0 / 67 product tasks verified**, no accepted exceptions. Counts describe task completion, not effort or schedule. Phases 4 and 5 can proceed independently once their prerequisites pass. Resolve the phase 6 audio and widget risks in phase 0, even though their finished UI arrives later.

## Source reference map

All paths below are relative links into the inspected Android implementation. Read its current revision again when executing a row; record any baseline change in the activity log.

| Key | Starting points |
| --- | --- |
| NAV | [routes](../android/app/src/main/java/stream/cliamp/mobile/ui/NavRoutes.kt), [root navigation](../android/app/src/main/java/stream/cliamp/mobile/ui/CliampRoot.kt), [external entry points](../android/app/src/main/java/stream/cliamp/mobile/MainActivity.kt) |
| DESIGN | [design system](design.md), [themes and typography](../android/app/src/main/java/stream/cliamp/mobile/ui/theme/), [components](../android/app/src/main/java/stream/cliamp/mobile/ui/components/), [fonts](../android/app/src/main/res/font/), [theme fixture](custom-theme.json) |
| PLAYER | [connection and queue](../android/app/src/main/java/stream/cliamp/mobile/playback/PlayerConnection.kt), [service](../android/app/src/main/java/stream/cliamp/mobile/playback/PlaybackService.kt), [resolver](../android/app/src/main/java/stream/cliamp/mobile/playback/StreamResolver.kt), [reconnect](../android/app/src/main/java/stream/cliamp/mobile/playback/Reconnector.kt), [player screen](../android/app/src/main/java/stream/cliamp/mobile/ui/screens/NowPlayingScreen.kt) |
| RADIO | [stations screen](../android/app/src/main/java/stream/cliamp/mobile/ui/screens/StationsScreen.kt), [repository](../android/app/src/main/java/stream/cliamp/mobile/data/Repository.kt), [directory](../android/app/src/main/java/stream/cliamp/mobile/data/RadioBrowser.kt), [built-ins](../android/app/src/main/java/stream/cliamp/mobile/data/CliampRadio.kt), [artwork](../android/app/src/main/java/stream/cliamp/mobile/data/StationArtSource.kt) |
| QUEUE | [behavior contract](queue-behavior.md), [source identity](../android/app/src/main/java/stream/cliamp/mobile/playback/PlaybackContext.kt), [queue UI](../android/app/src/main/java/stream/cliamp/mobile/ui/screens/QueueScreen.kt), [queue edit tests](../android/app/src/test/java/stream/cliamp/mobile/playback/QueueEditsTest.kt), [queue entry tests](../android/app/src/test/java/stream/cliamp/mobile/ui/screens/QueueEntriesTest.kt), [navigation tests](../android/app/src/androidTest/java/stream/cliamp/mobile/playback/QueueNavigationTest.kt), [playback tests](../android/app/src/androidTest/java/stream/cliamp/mobile/playback/QueuePlaybackTest.kt) |
| LIBRARY | [library and playlist screens](../android/app/src/main/java/stream/cliamp/mobile/ui/screens/LocalScreen.kt), [local indexing](../android/app/src/main/java/stream/cliamp/mobile/data/LocalLibrary.kt), [playlist storage](../android/app/src/main/java/stream/cliamp/mobile/data/PlaylistStore.kt), [global search](../android/app/src/main/java/stream/cliamp/mobile/ui/search/), [search state](../android/app/src/main/java/stream/cliamp/mobile/ui/screens/SearchViewModel.kt) |
| PODCAST | [directory and feed data](../android/app/src/main/java/stream/cliamp/mobile/data/PodcastRepository.kt), [feed parser](../android/app/src/main/java/stream/cliamp/mobile/data/PodcastFeed.kt), [directory screen](../android/app/src/main/java/stream/cliamp/mobile/ui/screens/PodcastsScreen.kt), [episode screen](../android/app/src/main/java/stream/cliamp/mobile/ui/screens/PodcastShowScreen.kt), [downloads](../android/app/src/main/java/stream/cliamp/mobile/data/Downloads.kt) |
| PROVIDER | [catalog and auth fields](../android/app/src/main/java/stream/cliamp/mobile/data/provider/ProviderCatalog.kt), [browse adapters](../android/app/src/main/java/stream/cliamp/mobile/data/provider/ProviderBrowse.kt), [clients and stores](../android/app/src/main/java/stream/cliamp/mobile/data/provider/), [wizard](../android/app/src/main/java/stream/cliamp/mobile/ui/screens/ProviderWizard.kt), [browse UI](../android/app/src/main/java/stream/cliamp/mobile/ui/screens/ProviderBrowseScreen.kt), [SFTP playback](../android/app/src/main/java/stream/cliamp/mobile/playback/SftpDataSource.kt) |
| SETTINGS | [persistent defaults](../android/app/src/main/java/stream/cliamp/mobile/data/Prefs.kt), [settings UI](../android/app/src/main/java/stream/cliamp/mobile/ui/screens/SettingsScreen.kt), [startup behavior](../android/app/src/main/java/stream/cliamp/mobile/CliampApp.kt), [database](../android/app/src/main/java/stream/cliamp/mobile/data/db/) |
| AUDIO | [FFT and EQ presets](../android/app/src/main/java/stream/cliamp/mobile/playback/AudioFx.kt), [spectrum state](../android/app/src/main/java/stream/cliamp/mobile/data/visualizer/Visualizer.kt), [scope UI](../android/app/src/main/java/stream/cliamp/mobile/ui/screens/ScopeScreen.kt), [scrobbler](../android/app/src/main/java/stream/cliamp/mobile/data/Scrobble.kt) |
| SYSTEM | [widgets and tile](../android/app/src/main/java/stream/cliamp/mobile/widget/), [manifest](../android/app/src/main/AndroidManifest.xml), [media service](../android/app/src/main/java/stream/cliamp/mobile/playback/PlaybackService.kt) |

## Phase 0 — establish evidence and remove feasibility risks

References: NAV, DESIGN, PLAYER, PROVIDER, SYSTEM. Exit: a runnable iOS skeleton, a captured Android reference, and recorded platform decisions. Spikes must exercise actual media; a diagram alone is insufficient.

| ID | Work and acceptance criterion | State | F/V/X | Owner / evidence |
| --- | --- | --- | --- | --- |
| FND-01 | Choose minimum OS against DEC-03's surface requirements, iPhone sizes, iPad scope, stack, and device matrix. Create a locally runnable project and a macOS CI job with pinned runner/Xcode versions and an explicit signing approach; start with unsigned simulator build/test unless device CI is selected. Document commands in `ios/README.md`; update `AGENTS.md` for Android/iOS ownership and applicable Swift guidance without inventing installed skills. | R | P/NA/NA | 2026-09-16: XcodeGen scaffold at `d894f39`; iOS 18.0, universal iPhone/iPad, SwiftUI + Swift 6, app + local SPM packages; CI `macos-26` + Xcode 26.6 + XcodeGen 2.45.4 unsigned. F: P locally (unsigned build, 4 tests, simulator launch); V/X: NA (placeholder shell only). CI first run pending push. Evidence: [`docs/ios-parity-evidence/FND-01.md`](ios-parity-evidence/FND-01.md). |
| FND-02 | Capture every reachable Android screen, overlay, menu, and major state against this commit; include portrait/landscape videos, navigation, defaults, and discrepancy decisions. Index fixtures/captures by task/scenario ID. Measure launch, tap-to-audio, scrolling, memory and battery under repeatable conditions, then record device-specific budgets and review tolerances for QA-04. | N | —/—/— | — |
| FND-03 | First prove one live ICY MP3 stream with real playback FFT and continuous audio while the physical device is locked; verify metadata and foreground/background transitions. Then extend to seekable HTTP, local files, SFTP, EQ, mono and speed. Resolve public HTTP playlists/redirects/streams via DEC-07 and record the codec/container matrix before choosing the engine. The first spike alone does not complete this row. | W | —/—/— | 2026-09-16: live ICY MP3 plays through AVPlayer with a post-effects `MTAudioProcessingTap` and vDSP FFT driving the meters, proven on the iPhone 17 simulator (`8d6d231`); locked-device/background, metadata, codec matrix and DEC-07 fixtures still pending. |
| FND-04 | Prove secure credential storage, media-library versus Files access/reopen, local-network provider access, and interactive system surfaces on FND-01's minimum OS. Record constraints and experience differences in DEC-01–03, DEC-05 and DEC-07. | N | —/—/— | — |
| FND-05 | Define stable media/account/list/queue-occurrence IDs and persistence boundaries. Add deterministic radio, feed, provider, local-file, 130-item queue, and theme fixtures, including a nonopaque alpha-first color such as `#80445566`. Capture the observable constants table below and port relevant Android queue test scenarios; establish test/screenshot conventions. | N | —/—/— | — |

### Reference constants and boundary fixtures

These values pin observable Android behavior for FND-05 and later gates. They do not require identical iOS internals; document a deliberate behavioral difference in the owning decision. The playback source reference is [PlayerConnection.kt](../android/app/src/main/java/stream/cliamp/mobile/playback/PlayerConnection.kt).

| Behavior | Android reference | Required check / owner |
| --- | --- | --- |
| Loaded playback window | `WINDOW = 60` | Use 130 finite tracks with repeated occurrences; edit after item 60, then advance across both 60 and 120 boundaries without losing order or playback position. QUE-04, J-05. |
| Rapid transport taps | `NAV_DEBOUNCE_MS = 180` | An isolated tap applies immediately; a burst settles on its final target. Test taps both inside and outside the 180 ms interval. RAD-07, QUE-02. |
| Saved progress | `PROGRESS_INTERVAL = 5_000` | Measure progress saved during uninterrupted playback and on pause/item changes; test termination just before/after a save. Do not promise zero loss on abrupt termination. POD-04, LIB-05. |
| Previous history depth | `PAST_CAP = 100` | Exercise more than 100 played items and verify bounded history navigation. QUE-02. |
| Persisted widget source | Eight entries before and after current, wrapping; up-next preview takes four | Capture cold/warm behavior with short and long lists; this snapshot is not full queue restoration. SYS-01, DEC-03. |
| Seek at the end | Requests at or beyond `duration - 250 ms` return without seeking | Verify position stays unchanged for a rejected request; an earlier seek succeeds. Do not implement this as a clamp to the last 250 ms. RAD-08. |
| Buffer setting | [PlaybackService.kt](../android/app/src/main/java/stream/cliamp/mobile/playback/PlaybackService.kt) reads it at construction; minimum 2s, maximum `clamp(setting × 4, 60s, 180s)`, start 0.5s, rebuffer 2s | Test setting 5/30/60s → maximum 60/120/180s. These are configured thresholds, not guaranteed actual buffered duration. A running Android player keeps its original configuration. SET-01, DEC-01. |
| Shuffle-off | Restores saved `_baseSource`, anchored on the audible item | Without intervening edits, restore pre-shuffle order; queue edits and same-list selections can update the base. Test both paths against Android and preserve current playback position. QUE-04. |
| Cold-launch navigation | With more than one fallback item and no explicit list selected, Previous/Next wrap and both are enabled | Capture history-seeded fallback, empty/single-item cases, and the transition to a finite explicit list. Service-only startup initially uses history or favorites; the UI supplies recent history when composed. RAD-12. |

## Phase 1 — design system and navigation

References: DESIGN, NAV. Exit: recognizable cliamp screens with fixture content, correct navigation, and reviewed dark/light rendering.

| ID | Work and acceptance criterion | State | F/V/X | Owner / evidence |
| --- | --- | --- | --- | --- |
| VIS-01 | Implement all 32 palette roles plus `dark`; system selects oxide/oxide-light. Match source color values and safe-area/status-bar treatment without a wrong-theme launch flash. | W | —/—/— | 2026-09-16: all 32 roles plus `dark` ported with the Android values and unit tests (`ee947cb`); system resolves oxide/oxide-light. Paired captures, status-bar treatment and launch-flash review still open. |
| VIS-02 | Bundle Poppins for text and JetBrains Mono for numeric readouts, matching weights, tracking, line height, and title scale. Verify long titles and ticking clocks; include font notices. | W | —/—/— | 2026-09-16: both families bundled and registered, all six faces asserted by test (`3753476`); scale, tracking and line heights ported in `CliampType`. Long-title/clock review pending; OFL texts and notices shipped (`3bfced0`, `0eb4c2e`). |
| VIS-03 | Port rows, hairlines, headers, chips, toggles, square slider handles, icons, and empty states. Start from 22-point logical gutters; compare geometry at matched content widths. Preserve usable touch targets. | W | —/—/— | 2026-09-16: rows, hairlines, headers, chips, toggles, square slider handles and the full hand-drawn icon set live in `CliampDesign` with path-parser tests (`ee947cb`, `3753476`); matched-width geometry review pending. |
| VIS-04 | Match mechanical keys: 64-point face, 11-point radius, 3-point press travel, dark inset bevel/light shelf, pressed and disabled states, and haptic setting. Review press/release video and physical-device feel. | W | —/—/— | 2026-09-16: `MechKey` ported with both builds, 3-point travel, 38% disabled alpha and the haptics environment (`ee947cb`); press/release video and physical-device feel pending. |
| VIS-05 | Deliver Stations / Podcasts / Library tabs, swipe navigation, preserved tab state, mini-player chrome, portrait tab bar, and landscape trailing rail. Scrolling filter chips must not trap page navigation. | W | —/—/— | 2026-09-16: tabs, mini-player chrome, portrait bar and landscape rail live with the placeholders (`3753476`); swipe navigation, tab-state preservation and chip-gesture boundary checks pending. |
| VIS-06 | Deliver detail navigation and Player / Queue / Scope / Provider overlays with correct chrome visibility, no touch-through, sensible iOS back gestures, and source-matched transition character. | W | —/—/— | 2026-09-16: Player and Settings present as covers with working back/down keys (`3753476`); Queue/Scope/Provider overlays, transition character and iOS back-gesture review pending. |
| VIS-07 | Add all 27 concrete palettes plus system mode and immediate persistent switching. Compare representative dark/light/high-contrast palettes across screens; mechanically validate every role for every palette. | N | —/—/— | — |
| VIS-08 | Import custom JSON themes using all 32 roles and `dark`, with `#RRGGBB` or alpha-first `#AARRGGBB` colors. Exercise a nonopaque 8-digit value, not just the 6-digit example theme. Valid import applies immediately; invalid import names the fault without mutation; removal/broken stored data falls back safely. | N | —/—/— | — |

## Phase 2 — radio and the complete playback loop

References: RADIO, PLAYER, NAV, SETTINGS. Exit: browse → play → lock phone → control playback → recover a lost network, on a real iPhone.

| ID | Work and acceptance criterion | State | F/V/X | Owner / evidence |
| --- | --- | --- | --- | --- |
| RAD-01 | Load cliamp channels from the playlist endpoint with the 12-channel fallback; show the channel count in the section label and active/favorite state. No network still yields the fallback list. Live listener counts are outside the baseline. | W | —/—/— | 2026-09-16: live `streams.m3u` fetch with the twelve-channel fallback, count in the section label, active rail and in-memory favourites (`3753476`, 15 channels observed live); offline-fallback test and favourite persistence (RAD-12) pending. |
| RAD-02 | Browse Radio Browser with 60-item pages, top-voted (`votes`) and trending (`clicktrend`) ordering, tags/country filters, current query, counts, retry and exhausted state. Match mirror failover, URL deduplication and play reporting. Retain the source HLS filter: accept unflagged entries or entries whose resolved URL ends in `.m3u8`; cover query-string/case boundary examples. DEC-07 covers HTTP results. | R | —/—/— | 2026-09-16: directory client with DNS discovery, pinned mirror, two-pass failover, retry and dead-mirror skipping; 60-item pages, top/trending/tag/country, stats, dedupe, HLS filter and click reporting, all unit-tested (`7afdeb9`, `960d825`). Live directory observed with 51,802 playable; visual/device review pending, HTTP results await DEC-07. |
| RAD-03 | Preserve independent list/grid choices for cliamp, custom stations, and directory sections after relaunch. Loading more must preserve current items and scroll position. | R | —/—/— | 2026-09-16: the three grid/list choices persist in defaults and pages append in place, with a reset keeping the current rows until the new query lands (`960d825`); relaunch/scroll checks on device pending. |
| RAD-04 | Add/remove custom stations with source-equivalent URL/name validation and persistence. Test empty names, malformed URLs, duplicate entries, and playback from the custom section. | R | —/—/— | 2026-09-16: validation ported and unit-tested (blank, missing scheme, non-http, www host fallback), JSON persistence replaces duplicates by URL, and the add form/remove menu render (`7afdeb9`, `960d825`); on-device playback from the section pending. |
| RAD-05 | Resolve supported M3U/PLS URLs and redirects over HTTP and HTTPS under DEC-07, then play FND-03 codec/container fixtures. Verify playlist fetch and media fetch separately. Unsupported or malformed media reports a stable error without endless retries. | N | —/—/— | — |
| RAD-06 | Full player shows source, artwork, title/artist or ICY title, format data, status, favorite/shuffle actions, queue access, and transport. Match portrait and landscape layouts and long-text treatment. | W | —/—/— | 2026-09-16: player with source line, fallback art plate, title, live status, favourite and transport at iPhone portrait width (`3753476`); ICY titles, format data, shuffle/queue access, landscape split and long-text handling pending. |
| RAD-07 | Mini-player and full player observe one playback state. Play/pause, Previous, Next, favorite and queue access stay synchronized through rapid navigation/source changes. Test isolated transport taps and bursts across the 180 ms baseline debounce boundary. | W | —/—/— | 2026-09-16: both surfaces read the one `RadioPlayer` and mirror play/pause (`3753476`); burst/debounce and rapid source-switch tests pending, Previous/Next disabled until the queue lands. |
| RAD-08 | Show streaming rule for live media and seek/elapsed/remaining controls only when actually seekable. Verify near-end seek rejection from the constants table. Match speed cycle (1, 1.25, 1.5, 1.75, 2, 0.5, 0.75), persistence and enabled states by source. | N | —/—/— | — |
| RAD-09 | Artwork loads after playback begins. Match provider/local/radio artwork selection, letterboxing, cliamp channel treatment, and fallback plates; failed or slow art must not delay audio. | N | —/—/— | — |
| RAD-10 | Recover radio errors with 1/2/4/8/15/30-second backoff, a 20-second stall watchdog, and immediate retry on network return. Amber reconnect state/count stays coherent; pausing cancels unwanted recovery. | N | —/—/— | — |
| RAD-11 | Continue background and locked-device playback. System metadata, play/pause/skip, Bluetooth/headset controls, interruptions, and route removal use the same playback owner; never produce two simultaneous players. | N | —/—/— | — |
| RAD-12 | Save last item, favorites and history. Cold launch is silent by default; auto-resume opt-in follows current startup behavior. With multiple fallback items before explicit list playback, Previous/Next wrap as a ring and both are enabled; test empty/single-item fallbacks and the transition to finite list navigation. Browsing or reconnecting UI never accidentally replays audio. | N | —/—/— | — |

## Phase 3 — queue, local library, playlists, search

References: QUEUE, LIBRARY, SETTINGS. Exit: all queue scenarios below pass for local music and radio, with working persistent library and search.

| ID | Work and acceptance criterion | State | F/V/X | Owner / evidence |
| --- | --- | --- | --- | --- |
| QUE-01 | Own one ordered upcoming sequence and explicit source-list identity. Same-list selection preserves pending order; different-list selection replaces it; browsing, sort changes, and refresh never replace it. | N | —/—/— | — |
| QUE-02 | Next and natural completion consume the first pending occurrence; end stops. Queue taps select an occurrence, including duplicate songs. Previous navigates playback history, with the 100-entry cap; test more than 100 plays and rapid transport bursts. | N | —/—/— | — |
| QUE-03 | Support drag reorder, swipe-left removal, Play next, append, and Clear. Clear removes the entire continuation while current playback continues; no confirmation for Clear or source replacement. | N | —/—/— | — |
| QUE-04 | Shuffle explicitly changes order; different-list playback respects enabled shuffle and same-list taps preserve the edited sequence. Shuffle-off restores the saved base order without resetting the audible item; test with and without intervening queue edits. Use 130 tracks to verify edits beyond the 60-item loaded window and continuation across multiple boundaries. | N | —/—/— | — |
| LIB-01 | Index playable local audio using DEC-02. Android automatically queries permitted MediaStore music without individual imports; evaluate iOS media-library and Files options and explicitly record any added import steps or inaccessible content. Read metadata/artwork, group by folder, and handle denied/revoked access, removed files and reindexing without broken identity. | N | —/—/— | — |
| LIB-02 | Port smart lists: local songs, downloads, favorites, recently played; favorites scopes all/local/stations/podcasts. Counts, empty states, folder filters, artwork, and active-item indicators match. | N | —/—/— | — |
| LIB-03 | Create, rename, pin/unpin, delete user playlists and add/remove members. Support the source UI's local/radio/podcast member picker and mixed-source playback; empty/duplicate names behave deliberately. | N | —/—/— | — |
| LIB-04 | Persist playlist identity/membership and per-list title/artist/album/recently-added sort. Renaming, sorting, or reopening the active list leaves its pending queue unchanged. | N | —/—/— | — |
| LIB-05 | Port song-info metadata, favorite action, and play statistics. Local positions start from zero by default and resume only with Resume local songs enabled. | N | —/—/— | — |
| SRC-01 | Fuzzy global search with source labels/highlighting and all/local/radio/podcasts/tags/providers filters. Capture all six chips and verify each filter. Blank-query suggestions, no results, loading and errors match; stale queries cannot replace newer results. | N | —/—/— | — |
| SRC-02 | Search the same available catalogs: local, favorites/history, radio/tags, provider accounts, shows, and cached episodes of subscribed shows. Open tags/accounts/shows appropriately; playable hits use query/filter queue identity. | N | —/—/— | — |
| SRC-03 | Search preserves its query and does not overwrite podcast browse state. External search entry opens directly without a home-screen flash and returns to a valid home destination. | N | —/—/— | — |
| DAT-01 | Relaunch restores favorites, history, custom stations, playlist membership/sorts/pins, and layout settings. Test database upgrades and missing media; never persist signed provider playback URLs. | N | —/—/— | — |

## Phase 4 — podcasts and offline listening

References: PODCAST, QUEUE, LIBRARY. Exit: discover → subscribe → play → download → airplane mode → resume works as one journey.

| ID | Work and acceptance criterion | State | F/V/X | Owner / evidence |
| --- | --- | --- | --- | --- |
| POD-01 | Browse/search the iTunes podcast directory, country/top/category selection, paging/deduplication, and subscribed/directory list-grid preferences. Cached content remains useful during refresh or failure. | N | —/—/— | — |
| POD-02 | Subscribe/unsubscribe and reopen shows with artwork, description, episode metadata, and cached feed content. Persist subscriptions and handle malformed/unavailable feeds without losing saved data. | N | —/—/— | — |
| POD-03 | Play episodes in displayed show order; show switches replace the source queue and same-show selections preserve edits. Episode Play next/add-to-queue actions work in a mixed queue. | N | —/—/— | — |
| POD-04 | Persist progress by canonical media URL using the baseline save cadence and lifecycle checks in the constants table; show progress/completion badges and current episode actions. Completed items or items within 30 seconds of the end restart from zero; verify seek and speed behavior. | N | —/—/— | — |
| POD-05 | Manual download shows progress/bytes, completion/error, cancellation, and removal. Only complete files become playable downloads; relaunch cleans partial/missing files consistently. | N | —/—/— | — |
| POD-06 | Offline playback prefers the local episode without changing its history/favorite/queue/progress identity. Deleting a download leaves a usable remote episode; test deletion around active playback. | N | —/—/— | — |
| POD-07 | Auto-download opt-in fetches the latest three eligible full, unplayed episodes of a subscribed show and applies source retention rules. Manual downloads are retained; honor the agreed cellular policy. | N | —/—/— | — |
| POD-08 | Downloads smart list and subscribed-episode search reflect downloads/progress changes immediately. Test interrupted download, low storage, missing files, offline launch, and later network return. | N | —/—/— | — |

## Phase 5 — server providers

References: PROVIDER, PLAYER, LIBRARY. Exit: each provider has its own passing connect → browse → play → seek → background → relaunch evidence. Passing one adapter does not certify another.

| ID | Work and acceptance criterion | State | F/V/X | Owner / evidence |
| --- | --- | --- | --- | --- |
| PRV-01 | Generic add/edit/remove account wizard supports multiple accounts, provider-specific fields and conditional auth. Test before saving; probe failure or cancellation must not save a broken account. | N | —/—/— | — |
| PRV-02 | Keep passwords/tokens/private keys in secure storage; resolve opaque account/track references at playback time. Inspect storage/logs/history for secrets and replayable URLs; account deletion cleans its secrets. | N | —/—/— | — |
| PRV-03 | Match common browse roots/filtering, artists → albums → tracks, available starred results, all-provider songs, artwork, errors, and empty states. Playing an album track supplies account+album list identity. | N | —/—/— | — |
| PRV-04 | Navidrome: URL/user/password probe, signed Subsonic requests, browse, artwork, playback and seek pass with a real test account and deterministic fixtures. | N | —/—/— | — |
| PRV-05 | Generic Subsonic: separately verify a compatible non-Navidrome server through the same journey; retain its own catalog entry and credential handling. | N | —/—/— | — |
| PRV-06 | Jellyfin: verify both API-token and username/password branches, browsing, playback headers, artwork, seek, and authentication failure. | N | —/—/— | — |
| PRV-07 | Emby: independently verify API-key and username/password branches and the common provider journey; do not assume Jellyfin verification covers it. | N | —/—/— | — |
| PRV-08 | Plex: verify URL + X-Plex-Token, library traversal, stream selection and seek. Preserve current fallback behavior where per-track artwork is unavailable. | N | —/—/— | — |
| PRV-09 | Audiobookshelf: verify API-key and username/password setup, library/book → track playback, multipart identity and seek. Do not invent artist/starred capabilities absent from the source adapter. | N | —/—/— | — |
| PRV-10 | Lyrion: verify optional credentials, browsing, covers, playback and seek; include empty and unavailable server cases. | N | —/—/— | — |
| PRV-11 | SSH/SFTP setup supports password, pasted key/passphrase, and Tailscale auth paths; folders/port and discovery match. Show first-use fingerprint and pin host keys; key mismatch fails clearly. | N | —/—/— | — |
| PRV-12 | SFTP progressively indexes filename-derived metadata, shows scan status and rescan, removes stale entries after a successful scan, and streams/seeks remotely without full-file staging. Playback and concurrent indexing coexist. | N | —/—/— | — |

Provider-specific limitations are part of the reference: not every adapter implements artists/starred or per-track covers. Record supported capability fixtures per provider rather than displaying made-up content or marking genuine missing iOS support as an empty library.

## Phase 6 — settings, audio, and system experiences

References: SETTINGS, AUDIO, SYSTEM, NAV. Exit: preferences affect real behavior and outside-app controls agree with inside-app state.

| ID | Work and acceptance criterion | State | F/V/X | Owner / evidence |
| --- | --- | --- | --- | --- |
| SET-01 | Settings exposes/persists auto-resume, resume local songs, auto-download, cellular policy, mono, 5–60-second buffer, haptics and spectrum/off. Confirm defaults and actual behavior. Buffer follows the threshold/construction-time contract above unless DEC-01 explicitly records a different application policy; changing the slider alone is not proof it affected running playback. | W | —/—/— | 2026-09-16: the page exposes every listed default with the source geometry, and the six built-in themes switch live; values are in-memory only and none of the audio effects are wired yet (`3753476`). Persistence is DAT-01's, behavior is AUD/SET verification. |
| SET-02 | Port favorite/history counts, purge history, directory statistics, app version and attribution link. Purging history does not delete favorites, files, playlists, or interrupt the current item. | N | —/—/— | — |
| AUD-01 | Real playback-driven spectrum supplies 64 bands to player, mini-player and Scope brick meters. Match grid/peak decay and idle behavior; spectrum/off removes rendering work. No synthetic animation accepted as real FFT. | W | —/—/— | 2026-09-16: real 64-band FFT from the playback tap feeds the ported MeterCore; player and mini player meters verified moving on the simulator, spectrum/off removes both (`c3c668b`, `8d6d231`). Scope screen, EQ coupling and grid/peak review pending. |
| AUD-02 | Seven EQ controls at 60/150/400/1k/3k/8k/16k, all 17 presets listed below, and custom band state persist and affect audible output. Android maps nominal frequencies to device-reported EQ bands; record that mapping and the iOS response rather than assuming identical DSP. Verify source types, routes and enabled/disabled transitions. | N | —/—/— | — |
| AUD-03 | Mono downmix and speed apply live without unexpectedly restarting or duplicating audio. Verify channels/speed with known audio fixtures. Validate buffer thresholds and reconnect behavior under SET-01 and DEC-01 separately; Android buffer changes apply on the next player construction. | N | —/—/— | — |
| SCB-01 | ListenBrainz token wizard validates before saving and supports disconnect. Count local/provider listens once after half duration or four minutes, whichever is earlier; unknown duration uses four minutes. Radio/podcasts do not scrobble; offline failure preserves local counts. | N | —/—/— | — |
| SYS-01 | Adapt compact/expanded playback widgets to iOS sizes with current title/artwork, transport and available quick actions. Verify FND-01/DEC-03 OS availability and cold/warm persisted source/up-next behavior from the constants table. Theme/state stay coherent; record unavailable controls or FFT-refresh differences. | N | —/—/— | — |
| SYS-02 | Provide fast entry equivalent to the search widget and quick-settings tile via DEC-03 surfaces. Interactive widgets require iOS 17 and Control Center controls iOS 18; if the minimum OS is lower, specify availability checks and review the alternative experience as a difference. Verify cold/warm launch, silent idle state and transport consistency. | N | —/—/— | — |
| SYS-03 | Port share-text/URL intake: extract a supported URL, save a custom station, and tune it as the Android entry point does, using the approved iOS handoff. Test malformed input, cancellation, and cold/warm app state. | N | —/—/— | — |

Persistent defaults from `Prefs.kt`: system palette; haptics on; spectrum on; cellular allowed; mono off; buffer 30s; EQ off/flat/zero bands; auto-resume off; auto-download off; resume local songs off; speed 1×; internal volume 1 (no in-app volume control in the baseline). Radio sections default to lists, podcast sections to grids, and playlist sort to title. The buffer value is a configuration input, not literal buffered duration; use the constants table. Verify observable behavior during FND-02 before sign-off.

EQ preset inventory: **flat, rock, pop, jazz, classical, bass, treble, vocal, electronic, acoustic, hip-hop, r&b, loudness, late night, podcast, speakers, headphone**. AUD-02 verifies all 17 names and their band vectors against `AudioFx.kt`.

## Phase 7 — complete parity acceptance

References: all groups. Exit: every in-scope row verified or an explicitly accepted, separately reported platform exception.

| ID | Work and acceptance criterion | State | F/V/X | Owner / evidence |
| --- | --- | --- | --- | --- |
| QA-01 | Run every journey in the scenario matrix on the declared minimum and current supported iOS versions, including a physical iPhone. Link failures to task IDs and rerun after fixes. | N | —/—/— | — |
| QA-02 | Complete paired screenshot/video review for every screen/state in FND-02. Fix unexplained typography, color, spacing, artwork, transition, haptic, or interaction differences; document system-owned variations. | N | —/—/— | — |
| QA-03 | Verify VoiceOver order/labels/actions, large text, contrast, Reduce Motion, keyboard dismissal, safe areas and reachable targets. Recheck playback/queue operations with accessibility enabled. | N | —/—/— | — |
| QA-04 | Measure launch, tap-to-audio, large-list scrolling, queue edits, memory, and foreground/background battery cost against the captured baseline and budgets set in phase 0. A long playback/network-change session has no crashes, runaway retries or duplicate audio. | N | —/—/— | — |
| QA-05 | Verify clean install and upgrade preservation, signed release build/device provisioning, bundled assets/notices and reproducible commands. Choose and verify the intended distribution route (for example ad-hoc or TestFlight), including certificates/profiles and CI secret ownership. Review every open decision/task count and remaining differences before calling the port complete. | N | —/—/— | — |

## Visual and experience acceptance contract

Use the same data, artwork, theme, playback state, and approximately equal content width in paired captures. Compare app content separately from OS status bars, keyboards, file pickers, lock-screen controls, and permission dialogs. Native iOS system surfaces can differ while preserving the same task and state.

Capture at least:

- All three tabs in list/grid, with loaded, empty, loading, error and offline states where applicable.
- Full player and mini-player: idle, playing, paused, buffering, reconnecting, failed, live and seekable; short/long titles and missing/real artwork.
- Queue: empty, one item, duplicates, long list, drag, swipe, shuffle and Clear.
- Library smart lists, playlist editor/member picker, song info, provider list/wizard/browse, podcast show/episode menu, search (all six category chips) and settings.
- Scope/EQ and theme import success/error; default oxide dark/light, phosphor dark/light, an Omarchy palette and a custom palette.
- Portrait, landscape, keyboard visible, large text, reduced motion, and system theme changes while the app is open.

Use source geometry as the starting logical-point values, not a promise that Android device pixels equal iPhone pixels. Review control travel, easing, touch response, navigation continuity and haptics with video and real devices; screenshots cannot certify feel. For brick meters, match the 24-column player, 32-column Scope and 14-column mini presets and their grid/peak behavior. Use deterministic spectrum frames for screenshots and actual audio for FFT verification.

Accessibility and iOS gesture adjustments are explicit port acceptance requirements, not claims that Android already passes them. Preserve the design while making those interactions usable.

## Cross-feature regression scenarios

Record `not run`, `pass`, or `fail`, the build/device, and evidence when executing. These supplement row gates; they do not add another task denominator.

| Scenario | Steps and expected result | Task IDs | Result / evidence |
| --- | --- | --- | --- |
| J-01 First launch | Fresh install → browse → tune radio → navigate tabs → lock phone → pause from system control. Verify default theme, channel count and silent startup. Relaunch with multiple history items: Previous/Next wrap before explicit list playback; then select a finite list and verify end behavior. Also cover empty/single-item fallback. One player owns the session. | VIS-01, RAD-01, RAD-07, RAD-11–12 | not run |
| J-02 Train tunnel | Play live radio → cut network long enough for a stall → restore → pause during another retry. Backoff/status recover correctly, pause stays paused, no duplicate stream. | RAD-10–11 | not run |
| J-03 Same-list queue | A plays from a playlist; edit pending to D/B/C/E → tap C in that original playlist → Next. Pending remains D/B/C/E after the tap; Next plays D. | QUE-01–04 | not run |
| J-04 New source / duplicates | Browse another list without playing → queue unchanged; play there → replacement. Add duplicate URLs → tap/remove one occurrence → correct surviving order. Toggle shuffle on/off with and without intervening edits: restore the saved base for that case and keep the audible item/position. | QUE-01–04 | not run |
| J-05 Long queue / Clear | Use 130 finite tracks with duplicate occurrences. Edit after item 60 → advance across 60 and 120 boundaries → exercise history after more than 100 plays → Clear. No lost tail edits or position reset; Clear removes every pending item while current audio continues. | QUE-02–04 | not run |
| J-06 Mixed sources | Music → queued episode → live station. Finite items advance; live radio waits for Next. Switch to another show then back to a playlist; each new source starts its own continuation. | QUE-01–04, POD-03, PRV-03 | not run |
| J-07 Offline podcast | Subscribe → download → partial listen → relaunch in airplane mode → resume → complete → replay. Identity/progress persist; replay starts at zero. Manual download survives auto retention. | POD-02, POD-04–08 | not run |
| J-08 Provider lifecycle | For each provider: invalid auth → fix → save → browse/play/seek → background → relaunch → edit/remove account. No failed probe saved; secrets never appear in plain history or logs. | PRV-01–12 | not run |
| J-09 SFTP trust / rescan | Connect first host → verify fingerprint → rescan during playback → change remote files → rescan → simulate changed host key. Valid streaming continues; successful scan reconciles deletions; key mismatch fails safely. | PRV-11–12 | not run |
| J-10 Search isolation | Set podcast country/category → search a show and cached episode → exercise all/local/radio/podcasts/tags/providers chips → clear search → return. Browse selection survives; tags/accounts open correctly; query-defined queue follows the contract. | SRC-01–03, POD-01 | not run |
| J-11 Theme and feel | Change palette families → import valid/bad themes, including alpha-first `#80445566` → relaunch → disable haptics/visualizer → rotate. Theme persists everywhere, alpha is interpreted correctly, bad import is atomic, disabled effects stay off, content remains reachable. | VIS-01–08, AUD-01, SYS-01 | not run |
| J-12 External entry | Invoke widget/search/quick control/share while closed and while playing. Correct destination or playback action, no duplicate navigation/player, invalid share has no side effects. | SRC-03, SYS-01–03 | not run |
| J-13 Interruption and files | Play imported local file → interrupt audio/change route → resume → revoke/remove file access → reopen library. State remains coherent and missing media is recoverable. | RAD-11, LIB-01, DAT-01 | not run |
| J-14 Audio and scrobble | Play known stereo fixture → change mono/EQ/speed → test seek requests just before and within the final 250 ms → pause near scrobble threshold → interrupt network. Verify all 17 EQ presets and 5/30/60s buffer settings before/after player reconstruction. Audible effects/FFT agree; qualifying listens use heard time; buffer follows DEC-01. | RAD-08, SET-01, AUD-01–03, SCB-01 | not run |

## Platform decisions and unresolved differences

These are early engineering decisions, not permission gates for writing the port. An approved exception changes the delivered experience and must be visible in the affected task row.

| ID | Decision to make | Evidence / outcome required | State |
| --- | --- | --- | --- |
| DEC-01 | Audio architecture, supported formats and buffer policy | Start with locked-device ICY MP3 playback plus real FFT, then prove every FND-03 source/effect before selecting the engine. Treat PCM access for live streams as a feasibility question. Match construction-time buffering and its thresholds or document the intentional iOS difference; record EQ band mapping and unsupported formats/fallbacks. | open; evidence: AVPlayer + `MTAudioProcessingTap` + vDSP gives real PCM-derived FFT for a live ICY MP3 (simulator, `8d6d231`); locked-device proof and the codec matrix still pending. FND-03, SET-01, AUD-02–03 |
| DEC-02 | Local library and file ownership | Compare `MPMediaLibrary` access, managed Files imports, retained external access, or a combination. For each candidate prove authorization, playable asset access, protected/cloud-only item handling, real FFT/EQ compatibility, reopen, moved/deleted files and folder identity. Android indexes permitted MediaStore music automatically; any added selection/import step or excluded content needs an explicit experience decision. | open; FND-04, LIB-01, AUD-01–02 |
| DEC-03 | Widgets, quick controls, share handoff, and OS-owned playback UI | Map every Android action to FND-01's minimum OS. Interactive widget buttons/toggles start at iOS 17; WidgetKit controls in Control Center start at iOS 18 (references below). Choose the OS floor or record per-version availability and alternative experiences. Prove cold/warm behavior and refresh budget; lost actions or continuous spectrum updates remain explicit differences. | open; FND-01, FND-04, SYS-01–03 |
| DEC-04 | Cellular policy | Confirm Android behavior on-device. Decide whether iOS matches observed download-only enforcement or intentionally enforces the label for all remote playback; record the difference and transition behavior. | open; FND-02, SET-01 |
| DEC-05 | Provider access and background work | Verify LAN permission, authentication, SFTP library suitability and download/scan behavior when suspended or terminated. Apply DEC-07's HTTP/TLS decision to provider and episode requests; do not assume Android process lifetime rules transfer. | open; FND-04, POD-05, PRV-01–12 |
| DEC-06 | Reference drift | At each phase start, compare new Android commits against this baseline. Add/change task IDs and fixtures deliberately; retain completed evidence and rerun affected scenarios. | ongoing |
| DEC-07 | HTTP/TLS transport and ATS configuration | Resolve in phase 0, before radio sign-off. Test public HTTP/HTTPS streams, M3U/PLS fetches, redirects, directory requests and LAN providers using the selected networking/media APIs. Select and document applicable ATS exceptions and their key interactions; a local-network or media-only exception does not establish all public playlist/API paths. Record any required distribution justification and certificate-failure behavior. | decided 2026-09-16: blanket `NSAllowsArbitraryLoads` because `NSAllowsArbitraryLoadsForMedia` did not cover `AVPlayerItem` loads on iOS 26 (verified ATS -1022 with the media key set; a live HTTP directory station then played). App Review justification note is QA-05's; M3U/PLS over HTTP can now be fetched, LAN providers still need DEC-05 verification. FND-03–04, RAD-02, RAD-05, DEC-05 |

Starting points for iOS feasibility: Apple documents the playback audio session and background configuration in [Configuring your app for media playback](https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback). Its [directory access documentation](https://developer.apple.com/documentation/uikit/providing-access-to-directories) describes document-picker access and security-scoped URLs. [Interactive widgets](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) use supported buttons/toggles and intents. These establish candidate mechanisms, not a guarantee that every cliamp behavior is already feasible; the spikes above must prove the full journeys.

Platform constraints checked for this plan:

- **System-surface OS floors:** Apple's interactive-widget example guards button support with iOS 17 availability; its controls session introduces Control Center controls in iOS 18. FND-01 and DEC-03 must agree on fallbacks before these tasks can pass. See [widget interactivity](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities?changes=_9) and [system controls](https://developer.apple.com/videos/play/wwdc2024/10157/).
- **Transport:** ATS applies by default to covered connections. Verify the chosen API's behavior and the interaction between exception keys rather than selecting one blanket setting by assumption. Media-only exceptions cover AVFoundation loads, not URLSession playlist/API requests; Apple also restricts the intended use of that media exception and requires justification for several exception types. See [ATS configuration](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSAppTransportSecurity), [media exception scope](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSAppTransportSecurity/NSAllowsArbitraryLoadsForMedia?language=objc) and [exception justification](https://developer.apple.com/documentation/Security/preventing-insecure-network-connections?changes=_3). DEC-07 records the tested choice; this plan does not prescribe a global bypass.

The media-library option remains a spike, not a promise of support for all Apple Music/cloud/protected content. Likewise, one successful live-radio FFT test reduces the largest audio risk but does not certify the complete codec/source matrix or system widget refresh behavior.

## Evidence record template

Keep a short record per completed or blocked task in the linked issue/PR or a file under `docs/ios-parity-evidence/` when evidence exists. Do not check in credentials, signed stream URLs, or private server data.

```text
Task ID / owner:
Android baseline commit / build:
iOS commit / build / device / OS:
Fixture and reproduction steps:
Functional result and test link:
Visual result and paired capture link:
Experience result and video/device notes:
Persistence / offline / error checks:
Known difference or blocker / decision ID / next action:
Reviewer / date:
```

## Activity log

| Date | IDs | Change | Evidence |
| --- | --- | --- | --- |
| 2026-09-16 | DEC-07 | Directory playback failed with ATS -1022 on plain-HTTP stations. The media-only exception was proven ineffective for `AVPlayerItem` on iOS 26; a blanket `NSAllowsArbitraryLoads` was adopted and verified with a live HTTP stream (ON AIR, meter live). App Review justification deferred to QA-05. | `project.yml`; player error log -11800/-1022; simulator capture of the HTTP station playing |
| 2026-09-16 | AUD-01, FND-03, DEC-01 | Ported the brick meter and drove it from a real playback FFT: post-effects `MTAudioProcessingTap` → vDSP → shared MeterCore at display rate, player and mini presets, idle/settle behavior. ICY MP3 verified moving on the simulator. | `c3c668b`, `8d6d231`; simulator captures of the player meter in motion |
| 2026-09-16 | RAD-02–04 | Ported the radio-browser directory (mirrors, paging, filters, stats, HLS filter, dedupe, click reporting) and custom stations (validation, JSON store, add form, remove menu); grid choices persist. Directory observed live at 51,802 playable. Rows R/W; gates untouched. | `7afdeb9`, `960d825`; simulator capture of the directory section |
| 2026-09-16 | VIS-01–06, RAD-01, RAD-06–07, SET-01 | Owner-directed reorder: first visible screen before phase 0 finishes. Ported the design contract (`ee947cb`), station/radio models (`4c88b38`), font licences (`3bfced0`, `0eb4c2e`) and the tab shell, Stations on the live cliamp playlist, Now Playing over a real AVPlayer radio transport, and Settings over the six built-in palettes (`3753476`). All rows W; none verified, F/V/X untouched. | [`docs/ios-parity-evidence/first-view-slice.md`](ios-parity-evidence/first-view-slice.md); simulator captures of Stations (light/dark), Player and Settings reviewed during development |
| 2026-09-16 | FND-01 | Addressed codex review findings: `GCC_TREAT_WARNINGS_AS_ERRORS` key, package `-warnings-as-errors`, device matrix moved into `ios/README.md`, stale baseline/next-slice prose refreshed. | [`docs/ios-parity-evidence/FND-01.md`](ios-parity-evidence/FND-01.md) |
| 2026-09-16 | FND-01 | Scaffolded iOS app (XcodeGen, iOS 18, universal, SwiftUI + CliampCore package), pinned unsigned simulator CI, and updated `ios/README.md` / `AGENTS.md` with the recorded decisions. State R; CI first run pending push. | [`docs/ios-parity-evidence/FND-01.md`](ios-parity-evidence/FND-01.md); scaffold at `d894f39` |
| 2026-09-16 | all | Created source-audited baseline and phased execution tracker. No iOS implementation or device verification claimed. | Android `21782fd233b4ab089dc1e6ea56e758a2aa2a8477`; source map above |
| 2026-09-16 | FND, RAD, QUE, LIB, SRC, VIS-08, SET, AUD, SYS, QA, DEC-07 | Incorporated all 15 Claude review findings into existing rows: corrected channel/search/buffer claims, added boundary fixtures and shuffle/cold-start coverage, clarified local-library differences, CI/signing/routing work, OS floors and early transport decisions. Added precise queue-test references, alpha-first theme coverage and all 17 EQ presets. Refined review wording: near-end seeks are rejected; shuffle restores the saved base, which edits can update; fallback ring requires multiple items. Removed the separate review document. | Rechecked Android source and linked Apple documentation; total remains 72 tasks / 67 product tasks, all unverified. Listener counts removed as an erroneous requirement; no task IDs added or removed. |

**Next executable slice:** Remaining radio: RAD-05 playlist URLs/redirects, RAD-09 artwork, RAD-10 reconnect backoff, RAD-11 locked-device background playback (needs the physical iPhone) and RAD-12 favourites/history persistence, plus the Scope screen for AUD-01. Queue and local library start phase 3 after that. FND-01 stays `R` until the pinned CI workflow runs green on GitHub; FND-02 captures remain the outstanding phase 0 evidence.
