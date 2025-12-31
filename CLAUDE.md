# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SClean is a Swift/SwiftUI iOS app for efficiently browsing and cleaning up photos/videos from the photo library. Users can organize media by year, mark items for trash with undo capability, and permanently delete media while tracking deletion statistics.

- **Bundle ID:** com.seihabits.SClean
- **Platform:** iOS (SwiftUI)
- **Build System:** Xcode (no external dependencies)

## Build Commands

```bash
# Build (command line)
xcodebuild -scheme SClean -configuration Debug build

# Run tests
xcodebuild test -scheme SClean -configuration Debug

# In Xcode: Cmd+B (build), Cmd+U (test), Cmd+R (run)
```

## Architecture

### Service-Oriented + MVVM-Lite Pattern

**Services (Core/):** Business logic with `@MainActor`, `ObservableObject`, singleton pattern
**Views (Features/):** SwiftUI views injecting services via `@StateObject`/`@ObservedObject`

### Key Services

| Service | Purpose |
|---------|---------|
| PhotoLibraryService | Indexes photos, groups by year, handles caching |
| PhotoPermissionService | Manages photo library permissions |
| YearPhotosService | Loads assets for a specific year |
| ThumbnailLoader | Efficient thumbnail loading with PHCachingImageManager |
| FullImageLoader | Full-resolution image loading |
| TrashService | In-app soft delete with undo |
| DeletionService | Permanent deletion via PHPhotoLibrary |
| StatsService | Tracks lifetime deletion counts/bytes |

### State Pattern

Services use explicit state enums for type-safe state management:
```swift
enum LibraryState: Equatable, Sendable {
    case idle, loading, loaded([YearBucket]), empty, error(String)
}
```

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

Use semantic colors (`Color.scBackground`, `Color.scSurface`, `Color.scTextPrimary`, etc.) from Theme.swift - never hardcode colors.

### Surface Styling

- Content cards: `scCardStyle()`
- Controls/buttons: `scControlSurface()`
- iOS 26+ uses liquid glass for controls, solid surfaces for content

## Code Conventions

- Service classes marked `@MainActor` for thread safety
- State enums are `Equatable, Sendable`
- All Views have `#Preview` blocks
- Background thread callbacks use `nonisolated`
- Async/await for all async work in services

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
