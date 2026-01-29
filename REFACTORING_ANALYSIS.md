# Refactoring Analysis: Safety x Impact

## Executive Summary

This document analyzes potential refactoring opportunities in the SClean codebase, ranked by **Safety x Impact** score.

---

## TOP 5 REFACTORING OPPORTUNITIES (Ranked)

### #1: Remove ObservableObject from ThumbnailLoader
**Safety: 10/10 | Impact: 8/10 | Effort: 5 min**

```swift
// BEFORE - ThumbnailLoader.swift:22
@MainActor
final class ThumbnailLoader: ObservableObject { ... }

// AFTER
@MainActor
final class ThumbnailLoader { ... }
```

**Why safest:** Zero `@Published` properties. Nothing observes it. Views call methods directly via `.shared`. This is dead protocol conformance.

**Why impactful:** Removes false architectural signal, eliminates observation overhead, cleaner code.

---

### #2: Fix TrashService Over-Observation in Grids
**Safety: 9/10 | Impact: 9/10 | Effort: 30 min**

**Problem:** YearGridView, MonthGridView, TypeGridView all do this:
```swift
@ObservedObject private var trashService = TrashService.shared
// But only use: trashService.isTrashed(asset.id) in gridCell
```

**Impact:** Every trash change -> full grid redraw (100s of cells!)

**Fix Option A (simplest):** Pass trashed IDs set to grid cells
```swift
// In grid view
let trashedIDs = Set(trashService.trashedItems.map(\.assetID))

// In ForEach
gridCell(for: asset, isTrashed: trashedIDs.contains(asset.id))
```

**Fix Option B (best):** Extract grid cell into separate view that checks trash status internally - only affected cells redraw.

**Why safe:** Logic unchanged, just moved where check happens.

---

### #3: Fix HomeView Stats Observation
**Safety: 9/10 | Impact: 7/10 | Effort: 10 min**

**Problem:**
```swift
// HomeView.swift
@StateObject private var statsService = StatsService.shared  // HomeView observes
// ...
StatsCardView(statsService: statsService)  // But only StatsCardView uses it
```

**Impact:** Any stat change redraws entire HomeView.

**Fix:**
```swift
// StatsCardView owns its own observation
struct StatsCardView: View {
    @State private var statsService = StatsService.shared  // After @Observable migration
    // OR currently:
    @StateObject private var statsService = StatsService.shared
}
```

**Why safe:** Moving observation ownership, not changing behavior.

---

### #4: Cache visibleAssets in MediaViewerView
**Safety: 9/10 | Impact: 6/10 | Effort: 15 min**

**Problem:**
```swift
// MediaViewerView.swift:47-48 - Called 5 times per render
private var visibleAssets: [YearAsset] {
    assets.filter { !trashService.isTrashed($0.id) }  // O(n) every time
}
```

**Fix:**
```swift
@State private var visibleAssets: [YearAsset] = []

.onChange(of: trashService.trashedItems) { _, _ in
    visibleAssets = assets.filter { !trashService.isTrashed($0.id) }
}
.onAppear {
    visibleAssets = assets.filter { !trashService.isTrashed($0.id) }
}
```

**Why safe:** Same filtering logic, just cached.

---

### #5: @Observable Migration (StatsService first)
**Safety: 8/10 | Impact: 8/10 | Effort: 20 min**

StatsService is the **ideal first candidate**:
- Single `@Published` property
- Simple singleton pattern
- Already `@MainActor`
- No complex initialization

```swift
// BEFORE
@MainActor
final class StatsService: ObservableObject {
    @Published private(set) var stats: DeletionStats = .zero
}

// AFTER
@MainActor
@Observable
final class StatsService {
    private(set) var stats: DeletionStats = .zero
}
```

Then update views:
```swift
// BEFORE
@StateObject private var statsService = StatsService.shared

// AFTER
@State private var statsService = StatsService.shared
```

---

## SAFETY x IMPACT MATRIX

| Refactoring | Safety | Impact | Effort | Priority |
|-------------|--------|--------|--------|----------|
| Remove ThumbnailLoader ObservableObject | 10 | 8 | 5min | **#1** |
| Fix grid TrashService observation | 9 | 9 | 30min | **#2** |
| Fix HomeView stats observation | 9 | 7 | 10min | **#3** |
| Cache visibleAssets | 9 | 6 | 15min | **#4** |
| @Observable: StatsService | 8 | 8 | 20min | **#5** |
| @Observable: PhotoPermissionService | 8 | 7 | 20min | #6 |
| @Observable: TrashService | 8 | 8 | 25min | #7 |
| @Observable: All remaining services | 7 | 9 | 2hr | #8 |
| Extract HomeView tab content | 9 | 5 | 45min | #9 |
| foregroundColor -> foregroundStyle | 10 | 1 | 1min | #10 |

---

## ObservableObject -> @Observable Migration Analysis

### Services Using ObservableObject (10 total)

| Service | @Published | Singleton | Risk |
|---------|------------|-----------|------|
| PhotoLibraryService | 2 | No | Low |
| TrashService | 2 | Yes | Low |
| StatsService | 1 | Yes | Low |
| DeletionService | 2 | Yes | Low |
| PhotoPermissionService | 1 | No | Low |
| YearPhotosService | 2 | No | Low |
| MonthPhotosService | 2 | No | Low |
| TypePhotosService | 1 | No | Low |
| ThumbnailLoader | 0 | Yes | **Remove** |
| FullImageLoader | 0 | Yes | N/A |
| SwipeToTrashAnimationState | 3 | No | Low |

### Migration Changes Required

**Service Classes:**
```swift
// BEFORE
@MainActor
final class SomeService: ObservableObject {
    @Published private(set) var state: SomeState = .idle
}

// AFTER
@MainActor
@Observable
final class SomeService {
    private(set) var state: SomeState = .idle
}
```

**View Property Wrappers:**

| Before | After | Notes |
|--------|-------|-------|
| `@StateObject private var service = Service()` | `@State private var service = Service()` | Owned instances |
| `@StateObject private var service = Service.shared` | `@State private var service = Service.shared` | Singletons |
| `@ObservedObject var service: Service` | `var service: Service` | Injected, read-only |
| `@ObservedObject var service: Service` + binding | `@Bindable var service: Service` | If bindings needed |

### Risk Analysis

**LOW RISK (Safe to migrate):**
1. @Published -> regular property: Direct replacement
2. @MainActor preservation: Already in place
3. Singleton pattern: Works identically
4. Async/await patterns: No changes needed

**MEDIUM RISK (Requires attention):**
1. @StateObject -> @State timing difference (creates on view init vs first body access)
2. Observation granularity change (should improve performance)

---

## What NOT to Refactor (Hidden Risks)

| Tempting Change | Why Avoid |
|-----------------|-----------|
| Remove FullImageLoader class | Used for caching, not observation |
| Change PHPhotoLibraryChangeObserver pattern | Nonisolated wrapper is correct |
| Refactor LibraryIndexer to actor | Already Sendable struct, works well |
| Add @EnvironmentObject for services | Current DI pattern is cleaner |

---

## Codebase Strengths (Already Modern)

- Using `NavigationStack` (not deprecated NavigationView)
- Using modern `onChange(of:) { _, new in }` syntax
- Using `clipShape` (not deprecated cornerRadius)
- All services properly `@MainActor` isolated
- Clean Sendable conformances for actor boundaries
- Proper nonisolated patterns for PHPhotoLibrary callbacks
