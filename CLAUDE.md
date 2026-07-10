# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SClean is a Swift/SwiftUI iOS app for efficiently browsing and cleaning up photos/videos from the photo library. Users browse media grouped by **year, month, type, or actionable cleanup insights**, mark items for trash with undo capability, and permanently delete media while tracking lifetime deletion statistics.

- **Bundle ID:** com.seihabits.SClean
- **Platform:** iOS 17.0 deployment target (SwiftUI). Uses newer APIs behind `#available` checks — e.g. Vision aesthetics scoring (`VNCalculateImageAestheticsScoresRequest`, iOS 18+) and iOS 26+ Liquid Glass — with graceful fallbacks.
- **Build System:** Xcode, no external dependencies (only Apple frameworks: Photos, Vision, CryptoKit)

## Build Commands

```bash
# Build (command line)
xcodebuild -scheme SClean -configuration Debug build

# Run all tests
xcodebuild test -scheme SClean -configuration Debug

# Run a single test (Swift Testing uses struct/function names, not XCTest method names)
xcodebuild test -scheme SClean -only-testing:SCleanTests/StatsServiceTests/recordDeletion_incrementsCount

# In Xcode: Cmd+B (build), Cmd+U (test), Cmd+R (run)
```

Tests use the **Swift Testing** framework (`import Testing`, `@Test`, `struct …Tests`), not XCTest — except UI tests in `SCleanUITests/`, which still use XCTest.

## Architecture

### Service-Oriented + MVVM-Lite Pattern

**Services (`Core/Services/`):** `@MainActor`, `ObservableObject`, singleton via `static let shared`. Expose state through `@Published private(set)`.
**Views (`Features/`):** SwiftUI views injecting services via `@StateObject`/`@ObservedObject`.

### The Snapshot/Indexing Core (most important to understand)

The whole app is driven by one immutable value type: **`LibraryIndexSnapshot`** (in `Core/Persistence/LibraryIndexStore.swift`). It holds a flat `[IndexedAsset]` array. All UI groupings (`yearBuckets`, `monthBuckets`, `typeBuckets`, `insightBuckets`) are **computed properties derived from that one array** — there is no separate per-grouping fetch from Photos.

Flow:
1. `LibraryIndexer` (`nonisolated`, runs off the main actor) enumerates `PHAsset`s and builds the snapshot, emitting progress via an `AsyncStream`.
2. `LibraryIndexStore` persists the snapshot as JSON on disk (`currentVersion` field gates schema migrations — bump it when `IndexedAsset` fields change).
3. `PhotoLibraryService.fetchYears()` loads the cached snapshot first (instant UI), then rebuilds in the background and saves.
4. `PHPhotoLibraryChangeObserver` (via the `nonisolated` `ChangeObserverWrapper`) triggers `refresh()` when the system library changes.

When adding a new grouping or insight, prefer deriving it as a computed property on `LibraryIndexSnapshot` rather than fetching assets separately.

### Insights (on-device content analysis)

The Insights tab surfaces actionable cleanup categories (`InsightCategory` enum: large videos/photos, exact duplicates, heavy old videos, similar shots, receipts, chat/meme dump, short videos). Two kinds:

- **Cheap, metadata-only** insights (size/age/duration) are computed synchronously inside the snapshot's `insightBuckets`.
- **Expensive, content-based** insights run in dedicated services off the main actor and merge their result back asynchronously:
  - `ExactDuplicateInsightService` — CryptoKit hashing of image data
  - `ReceiptInsightService` — Vision OCR text detection
  - `ChatMemeInsightService` — Vision-based screenshot/meme heuristics

These are kicked off as cancellable `Task`s in `PhotoLibraryService` (`startExactDuplicateInsightRefresh`, etc.), each bounded by an **`analysisBudget`** (max assets to analyze, to cap CPU). Results merge in via `mergeAsyncInsightBucket(_:category:)`, which keeps `insightBuckets` sorted by size. Note the `exactDuplicates` bucket is deliberately filtered out of the synchronous load and only appears once its async analysis completes.

### State Pattern

Services use explicit `Equatable, Sendable` state enums, e.g.:
```swift
enum LibraryState: Equatable, Sendable {
    case idle, loading, loaded([YearBucket]), empty, error(String)
}
```

### Concurrency Pattern

- Services are `@MainActor`.
- Data models crossing actor boundaries are declared `nonisolated struct`/`nonisolated enum` and are `Sendable` (e.g. `IndexedAsset`, `YearBucket`, `LibraryIndexSnapshot`).
- Background work (`LibraryIndexer`, insight services) uses `nonisolated` static/async methods.
- `PHPhotoLibraryChangeObserver` requires a `nonisolated final class` NSObject wrapper.

### Testability via Protocol Injection

To keep tests deterministic with no real Photos library / clock / `UserDefaults`, side effects are abstracted behind protocols in `Core/Services/Protocols/`:
- `DateProviding` (real: `SystemDateProvider`, test: `MockDateProvider`)
- `KeyValueStoring` (real: `UserDefaults` conformance, test: `MockKeyValueStore`)

Services take these as init parameters with production defaults. When writing a testable service, inject the dependency rather than calling `Date()` / `UserDefaults.standard` directly. See `docs/testing-guide.md` for the testing philosophy (test behavior not implementation; cover persistence-survives-restart, limited/denied permissions, and add a regression test per fixed bug).

### Key Services

| Service | Purpose |
|---------|---------|
| PhotoLibraryService | Orchestrates indexing, exposes year/month/type/insight buckets, manages change observer + async insight tasks |
| LibraryIndexer | `nonisolated` background PHAsset enumeration → snapshot |
| PhotoPermissionService | Photo library permission state (full / limited / denied) |
| YearPhotosService / MonthPhotosService / TypePhotosService / InsightPhotosService | Load the asset list for a specific bucket on demand |
| ThumbnailLoader | Grid thumbnails via `PHCachingImageManager` (150×150) |
| FullImageLoader | Full-resolution image loading for the viewer |
| TrashService | In-app soft delete with undo, persisted to UserDefaults |
| DeletionService | Permanent deletion via `PHPhotoLibrary` |
| StatsService | Lifetime deletion counts/bytes |
| ExactDuplicate/Receipt/ChatMeme InsightService | Async content analysis (see Insights above) |

### Navigation Flow

```
RootView (permission gate)
  └─> HomeView (segmented tabs: Years / Months / Types / Insights; floating trash button)
      ├─> YearGridView / MonthGridView / TypeGridView / InsightGridView (grids)
      │   └─> MediaViewerView (full-screen paging + swipe-to-trash)
      ├─> TrashView (review/restore → DeletionProgressView → DeletionResultView)
      └─> SettingsView (appearance, refresh index)
```

## Design System

### Color Foundation: "Ink / Paper / Blade"

- **Ink** (#0A0A0C) near-black · **Paper** (#F7F7FA) off-white · **Blade** (#6D7CFF) accent

Use semantic colors from `Theme.swift` — **never hardcode colors**:
`Color.scBackground`, `.scSurface`, `.scSurfaceElevated`, `.scTextPrimary`, `.scTextSecondary`, `.scTextDisabled`, `.scBorder`, `.scTint`, `.scDestructive`.

### Surface Styling (Liquid Glass aware)

Per iOS 26+ Liquid Glass rules: glass is for **controls**, solid surfaces for **content**.
- Content cards: `scCardStyle()` — solid background, no glass
- Control surfaces: `scControlSurface()` — glass on iOS 26+, material on older
- Floating buttons: `scFloatingButtonStyle()` — glass on iOS 26+

### Spacing & Layout

`Spacing` enum: `.xxs(4)`, `.xs(8)`, `.sm(12)`, `.md(16)`, `.lg(24)`, `.xl(32)`, `.xxl(40)`
`CornerRadius` enum: `.sm(10)`, `.md(14)`, `.lg(16)`
`Typography` for fonts: `.largeTitle`, `.title1`, `.headline`, `.body`, etc.

## Code Conventions

- Service classes `@MainActor` with `static let shared`.
- Observable state via `@Published private(set)`.
- State enums and cross-actor models are `Equatable, Sendable`; cross-actor types declared `nonisolated`.
- Background callbacks use `nonisolated`; async/await for all async work.
- All Views have `#Preview` blocks.

## Data Persistence

- **UserDefaults:** appearance mode, deletion stats, trashed items, UI hints (abstracted via `KeyValueStoring`).
- **LibraryIndexStore:** cached `LibraryIndexSnapshot` as JSON on disk for fast launch; versioned schema.
- **ThumbnailLoader:** `PHCachingImageManager` for grid thumbnails.
