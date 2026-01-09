# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SClean is a Swift/SwiftUI iOS app for efficiently browsing and cleaning up photos/videos from the photo library. Users can organize media by year, mark items for trash with undo capability, and permanently delete media while tracking deletion statistics.

- **Bundle ID:** com.seihabits.SClean
- **Platform:** iOS 18+ (SwiftUI)
- **Build System:** Xcode (no external dependencies)

## Build Commands

```bash
# Build (command line)
xcodebuild -scheme SClean -configuration Debug build

# Run tests
xcodebuild test -scheme SClean -configuration Debug

# Run a single test
xcodebuild test -scheme SClean -only-testing:SCleanTests/TestClassName/testMethodName

# In Xcode: Cmd+B (build), Cmd+U (test), Cmd+R (run)
```

## Architecture

### Service-Oriented + MVVM-Lite Pattern

**Services (Core/Services/):** Business logic with `@MainActor`, `ObservableObject`, singleton pattern via `static let shared`
**Views (Features/):** SwiftUI views injecting services via `@StateObject`/`@ObservedObject`

### Key Services

| Service | Purpose |
|---------|---------|
| PhotoLibraryService | Indexes photos, groups by year, uses LibraryIndexer for background work |
| PhotoPermissionService | Manages photo library permissions |
| YearPhotosService | Loads assets for a specific year |
| ThumbnailLoader | Efficient thumbnail loading with PHCachingImageManager |
| FullImageLoader | Full-resolution image loading |
| TrashService | In-app soft delete with undo (persisted to UserDefaults) |
| DeletionService | Permanent deletion via PHPhotoLibrary |
| StatsService | Tracks lifetime deletion counts/bytes |

### State Pattern

Services use explicit state enums for type-safe state management:
```swift
enum LibraryState: Equatable, Sendable {
    case idle, loading, loaded([YearBucket]), empty, error(String)
}
```

### Concurrency Pattern

- Services are `@MainActor` for UI thread safety
- Data models crossing actor boundaries use `nonisolated` and `Sendable`
- Background work (e.g., `LibraryIndexer`) uses `nonisolated` with async callbacks
- `PHPhotoLibraryChangeObserver` callbacks require `nonisolated` wrapper classes

### Navigation Flow

```
RootView (permission gate)
  └─> HomeView (years list)
      ├─> YearGridView (3-column grid)
      │   └─> MediaViewerView (full-screen paging + swipe-to-trash)
      ├─> TrashView (review/restore/delete)
      └─> SettingsView (appearance, refresh)
```

## Design System

### Color Foundation: "Ink / Paper / Blade"

- **Ink** (#0A0A0C) - Near-black
- **Paper** (#F7F7FA) - Off-white
- **Blade** (#6D7CFF) - Accent for interactive states

Use semantic colors from Theme.swift - never hardcode colors:
- `Color.scBackground`, `Color.scSurface`, `Color.scSurfaceElevated`
- `Color.scTextPrimary`, `Color.scTextSecondary`, `Color.scTextDisabled`
- `Color.scBorder`, `Color.scTint`, `Color.scDestructive`

### Surface Styling (Liquid Glass aware)

Per iOS 26+ Liquid Glass rules: glass is for **controls**, solid surfaces for **content**.

- Content cards: `scCardStyle()` - solid background, no glass
- Control surfaces: `scControlSurface()` - glass on iOS 26+, material on older
- Floating buttons: `scFloatingButtonStyle()` - glass on iOS 26+

### Spacing & Layout

Use `Spacing` enum: `.xxs(4)`, `.xs(8)`, `.sm(12)`, `.md(16)`, `.lg(24)`, `.xl(32)`, `.xxl(40)`
Use `CornerRadius` enum: `.sm(10)`, `.md(14)`, `.lg(16)`
Use `Typography` for fonts: `.largeTitle`, `.title1`, `.headline`, `.body`, etc.

## Code Conventions

- Service classes marked `@MainActor` with `static let shared` singleton
- State enums are `Equatable, Sendable`
- All Views have `#Preview` blocks
- Background thread callbacks use `nonisolated`
- Async/await for all async work in services
- Use `@Published private(set)` for observable state

## Directory Structure

```
SClean/
├── SCleanApp.swift              # App entry point
├── Core/
│   ├── Design/                  # Theme, Components, Appearance
│   ├── Persistence/             # LibraryIndexStore (caching)
│   └── Services/                # 8 core services
└── Features/
    ├── Root/                    # RootView (permission coordinator)
    ├── Permission/              # Permission request UI
    ├── Home/                    # Years list + stats card
    ├── YearGrid/                # Photo grid for year
    ├── Viewer/                  # Full-screen media viewer
    ├── Trash/                   # Trash management UI
    └── Settings/                # Appearance settings
```

## Data Persistence

- **UserDefaults:** Appearance mode, deletion stats, trashed items, UI hints
- **LibraryIndexStore:** Cached photo index (JSON on disk) for fast app launch
- **ThumbnailLoader:** PHCachingImageManager for grid thumbnails (150x150)
