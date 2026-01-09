# SClean Test Implementation Plan

A prioritized list of tests worth implementing, organized by layer and priority.

---

## Implementation Status

| Phase | Status | Tests |
|-------|--------|-------|
| Phase 1 - Core Logic | **COMPLETED** | 44 tests |
| Phase 2 - Data Integrity | Pending | - |
| Phase 3 - Feature Logic | Pending | - |
| Phase 4 - Integration | Pending | - |

---

## Testing Principles Applied

Based on the testing guide and codebase analysis:
- **Behavior over implementation**: Assert outcomes (items moved, restored, deleted), not internal state
- **Testable core via DI**: Services need protocol abstractions for PhotoKit, storage, and clock
- **Deterministic tests**: Use fakes/mocks - no real Photos library in unit tests
- **Edge cases covered**: Empty states, last item, missing metadata, already-trashed
- **Persistence survives restart**: Trash, stats, index cache tested for round-trip
- **Permissions tested**: denied/limited/full access paths

---

## 1. Unit Tests - Services (High Priority)

### TrashService Tests **[IMPLEMENTED]**
**File**: `SCleanTests/Services/TrashServiceTests.swift` (14 tests)

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `trash_addsItemToTrashedItems` | Basic trash operation | Call `trash("asset1")` → `trashedItems` contains item with correct ID and timestamp |
| `trash_setsLastTrashedID` | Undo tracking | Call `trash("asset1")` → `lastTrashedID == "asset1"` |
| `trash_doesNotAddDuplicates` | Duplicate prevention | Trash same ID twice → only 1 item in trash |
| `restore_removesItemFromTrash` | Basic restore | Trash item, call `restore("asset1")` → item removed from `trashedItems` |
| `restoreMultiple_removesAllSpecifiedItems` | Bulk restore | Trash 3 items, restore 2 → only 1 remains |
| `undoLastTrash_restoresLastItem` | Undo feature | Trash "a", trash "b", undo → "b" restored, "a" still trashed |
| `undoLastTrash_clearsLastTrashedID` | Undo state reset | After undo → `lastTrashedID == nil` |
| `isTrashed_returnsTrueForTrashedItems` | Query function | Trash item → `isTrashed` returns true |
| `isTrashed_returnsFalseForNonTrashedItems` | Query function | `isTrashed("unknown")` returns false |
| `filterVisible_excludesTrashedItems` | List filtering | Given 5 assets, 2 trashed → filter returns 3 |
| `clearAll_emptiesTrash` | Clear operation | Trash 3 items, clearAll → `trashedItems.isEmpty` |
| `remove_deletesSpecificIDs` | Post-deletion cleanup | Trash 3, remove 2 → 1 remains |
| `trashedItems_orderedByTrashedAtOldestFirst` | Ordering | Trash a, b, c → order is [a, b, c] |
| `persistence_survivesReload` | Data survives restart | Trash items, create new service instance → items present |
| `migration_convertsLegacySetFormat` | Legacy migration | Seed UserDefaults with old Set<String> format → loads correctly with timestamps |

### DeletionService Tests **[IMPLEMENTED - Models Only]**
**File**: `SCleanTests/Services/DeletionServiceTests.swift` (12 tests)

*Note: Full service testing requires PHPhotoLibrary mocking. Phase 1 covers model tests only.*

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `deletionResult_isFullSuccess_trueWhenAllDeleted` | Computed property | deleted=5, failed=[] → `isFullSuccess == true` |
| `deletionResult_isPartialSuccess_trueWhenSomeFailures` | Computed property | deleted=3, failed=["a","b"] → `isPartialSuccess == true` |
| `deletionResult_isFailure_trueWhenNoneDeleted` | Computed property | deleted=0, failed=["a"] → `isFailure == true` |
| `deletionResult_totalAttempted_sumOfDeletedAndFailed` | Computed property | deleted=3, failed=2 → total=5 |
| `deletionResult_empty_hasZeroCounts` | Static factory | `.empty` → all counts zero |
| `deletionProgress_fractionCompleted_calculatedCorrectly` | Progress calculation | current=3, total=10 → 0.3 |
| `deletionProgress_fractionCompleted_zeroWhenTotalIsZero` | Edge case | total=0 → fraction=0 |
| `deletionProgress_fractionCompleted_oneWhenComplete` | Edge case | current=total → fraction=1.0 |
| `deletionError_hasLocalizedDescriptions` | Error messages | All error cases have non-empty descriptions |
| `deletionError_unknownIncludesMessage` | Custom message | `.unknown("msg")` includes "msg" |
| `deletionError_equatable` | Equality | Same cases are equal, different are not |

**Future (requires PHPhotoLibrary protocol):**
| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `deleteAssets_returnsFullSuccessWhenAllDeleted` | Happy path | Mock successful deletion → `result.isFullSuccess == true` |
| `deleteAssets_mapsUserCancelledError` | Error mapping | Mock PHPhotosError code 3300 → `error == .userCancelled` |
| `deleteAssets_mapsPermissionDeniedError` | Error mapping | Mock PHPhotosError code 3301 → `error == .permissionDenied` |
| `deleteAssets_setsIsDeleting` | Progress state | During deletion → `isDeleting == true`, after → false |

### StatsService Tests **[IMPLEMENTED]**
**File**: `SCleanTests/Services/StatsServiceTests.swift` (9 tests)

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `recordDeletion_incrementsCount` | Basic recording | Record deletion of 5 → `stats.totalMediaDeleted == 5` |
| `recordDeletion_accumulatesBytes` | Byte tracking | Record 1GB, then 500MB → `totalBytesSaved == 1.5GB` |
| `recordDeletion_accumulatesCounts` | Count accumulation | Record 5, then 3 → total = 8 |
| `formattedBytesSaved_showsGBWhenOverThreshold` | Formatting | 2GB saved → `formattedBytesSaved == "2.0"`, `bytesSavedUnit == "GB"` |
| `formattedBytesSaved_showsMBWhenUnderThreshold` | Formatting | 500MB saved → shows MB format |
| `formattedMediaCount_usesDecimalFormat` | Formatting | 1234 items → formatted with locale separator |
| `hasStats_returnsFalseWhenZero` | Empty state | Fresh service → `hasStats == false` |
| `hasStats_returnsTrueAfterRecording` | Non-empty state | After recording → `hasStats == true` |
| `persistence_survivesReload` | Data survives restart | Record stats, new instance → stats preserved |

### YearPhotosService Tests
**File**: `SCleanTests/Services/YearPhotosServiceTests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_fetchPhotos_loadsAssetsForYear` | Basic fetch | Fetch 2024 → returns assets from 2024 only |
| `test_fetchPhotos_excludesAssetsFromOtherYears` | Boundary filtering | 2023 asset excluded from 2024 fetch |
| `test_fetchPhotos_handlesYearBoundary` | Edge: Jan 1 | Asset from Jan 1 00:00:00 included in correct year |
| `test_fetchPhotos_handlesLeapYear` | Edge: Feb 29 | Leap year date handled correctly |
| `test_sortOrder_newestFirst_sortsDescending` | Sort behavior | Assets sorted newest to oldest |
| `test_sortOrder_oldestFirst_sortsAscending` | Sort behavior | Assets sorted oldest to newest |
| `test_fetchPhotos_detectsMediaTypes` | Type detection | Photo, video, livePhoto detected correctly |
| `test_fetchPhotos_handlesNilCreationDate` | Edge: missing date | Asset with nil date → uses distantPast |
| `test_state_transitionsToLoadedOnSuccess` | State machine | Fetch → state becomes `.loaded([...])` |
| `test_state_transitionsToEmptyWhenNoAssets` | State machine | Empty year → state becomes `.empty` |

### LibraryIndexer Tests
**File**: `SCleanTests/Services/LibraryIndexerTests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_buildIndex_createsSnapshotWithAllAssets` | Basic indexing | 100 assets → snapshot has 100 indexed assets |
| `test_buildIndex_groupsByYear` | Year bucketing | Mixed years → `yearBuckets` correctly aggregated |
| `test_buildIndex_reusesMetadataWhenUnchanged` | Cache optimization | Asset unchanged → reuses cached byteSize |
| `test_buildIndex_updatesMetadataWhenAssetModified` | Cache invalidation | Asset modificationDate newer → re-indexes |
| `test_buildIndex_handlesYearChange` | Edge: year changed | Asset year differs from cache → updates year, keeps bytes |
| `test_buildIndex_reportsProgressCorrectly` | Progress callback | Progress handler receives incremental updates |
| `test_buildIndex_respectsCancellation` | Task cancellation | Cancelled task → returns partial or empty result |
| `test_buildIndex_excludesHiddenAssets` | Filter behavior | Hidden asset excluded from index |
| `test_buildIndex_excludesBurstAssets` | Filter behavior | Burst photo excluded |
| `test_estimatedByteSize_sumsAllResources` | Size calculation | Multi-resource asset → total size correct |

### FullImageLoader Tests
**File**: `SCleanTests/Services/FullImageLoaderTests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_loadFullImage_cachesResult` | Cache population | Load image → `getCachedImage` returns it |
| `test_getCachedImage_returnsNilWhenNotCached` | Cache miss | Unknown ID → returns nil |
| `test_cache_evictsOldestWhenFull` | LRU eviction | Load 10 images (max 9) → first evicted |
| `test_cache_updatesOrderOnAccess` | LRU ordering | Access cached image → moves to end of eviction queue |
| `test_clearCache_removesAllImages` | Cache clear | Clear → all `getCachedImage` return nil |
| `test_loadFullImage_returnsNilForMissingAsset` | Error handling | Non-existent asset ID → returns nil |

### PhotoPermissionService Tests
**File**: `SCleanTests/Services/PhotoPermissionServiceTests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_status_mapsAuthorizedCorrectly` | Status mapping | PHAuthorizationStatus.authorized → `.authorized` |
| `test_status_mapsLimitedCorrectly` | Status mapping | .limited → `.limited` |
| `test_status_mapsDeniedCorrectly` | Status mapping | .denied → `.denied` |
| `test_canAccessPhotos_trueWhenAuthorized` | Computed property | authorized/limited → true |
| `test_canAccessPhotos_falseWhenDenied` | Computed property | denied/restricted → false |
| `test_isLimited_trueOnlyForLimited` | Computed property | .limited → true, others → false |
| `test_refreshStatus_updatesPublishedStatus` | Refresh behavior | Status change → `status` property updated |

---

## 2. Unit Tests - Data Models (Medium Priority)

### DeletionResult Tests
**File**: `SCleanTests/Models/DeletionResultTests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_isFullSuccess_trueWhenNoFailures` | Computed property | deleted=5, failed=[] → `isFullSuccess == true` |
| `test_isPartialSuccess_trueWhenSomeFailures` | Computed property | deleted=3, failed=["a","b"] → `isPartialSuccess == true` |
| `test_isFailure_trueWhenAllFailed` | Computed property | deleted=0, failed=["a"] → `isFailure == true` |
| `test_totalAttempted_sumOfDeletedAndFailed` | Computed property | deleted=3, failed=2 → total=5 |

### DeletionStats Tests
**File**: `SCleanTests/Models/DeletionStatsTests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_add_incrementsCountAndBytes` | Mutation | add(count:5, bytes:1000) → updated totals |
| `test_zero_startsWithZeroValues` | Factory | `.zero` → both fields are 0 |
| `test_codable_roundTrips` | Serialization | Encode → decode → equal to original |

### LibraryIndexSnapshot Tests
**File**: `SCleanTests/Models/LibraryIndexSnapshotTests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_yearBuckets_aggregatesCorrectly` | Aggregation | 3 assets in 2024, 2 in 2023 → correct bucket counts |
| `test_yearBuckets_sumsBytesByYear` | Aggregation | Bytes summed per year correctly |
| `test_codable_roundTrips` | Serialization | Encode → decode → equal |
| `test_version_matchesCurrentVersion` | Versioning | Snapshot uses current version constant |

### TrashedItem Tests
**File**: `SCleanTests/Models/TrashedItemTests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_codable_roundTrips` | Serialization | Encode → decode → equal |
| `test_id_matchesAssetID` | Identifiable | `id == assetID` |

---

## 3. Unit Tests - Persistence (High Priority)

### LibraryIndexStore Tests **[IMPLEMENTED]**
**File**: `SCleanTests/Persistence/LibraryIndexStoreTests.swift` (8 tests)

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `saveAndLoad_roundTrips` | Basic persistence | Save snapshot → load → equal |
| `load_returnsNilWhenNoFile` | Empty state | Fresh store → `loadSnapshot()` returns nil |
| `load_returnsNilForVersionMismatch` | Version guard | Old version file → returns nil (cache invalidated) |
| `clearSnapshot_deletesFile` | Clear operation | Save, clear, load → nil |
| `save_createsDirectoryIfNeeded` | Directory handling | Nested directory created if missing |
| `snapshot_yearBuckets_aggregatesCorrectly` | Aggregation | 3 assets in 2024, 2 in 2023 → correct bucket counts and bytes |
| `snapshot_yearBuckets_sortedNewestFirst` | Ordering | Years sorted descending |
| `snapshot_codable_roundTrips` | Serialization | Encode → decode → equal |

---

## 4. Unit Tests - View Logic (Medium Priority)

These tests require extracting pure functions from views.

### MediaViewerView Logic Tests
**File**: `SCleanTests/ViewLogic/MediaViewerLogicTests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_visibleAssets_filtersTrashedItems` | Filter logic | 5 assets, 2 trashed → 3 visible |
| `test_currentVisibleIndex_mapsToFilteredList` | Index mapping | Absolute index 3 → visible index accounting for trashed |
| `test_nextVisibleIndex_findsNextNonTrashed` | Navigation | Current at index 2, next trashed → skips to 4 |
| `test_nextVisibleIndex_returnsNilAtEnd` | Edge: end of list | At last visible item → returns nil |
| `test_advanceToNextVisible_wrapsCorrectly` | Wrap behavior | After last visible → stays (or wraps based on impl) |

### SwipeToTrashModifier Logic Tests
**File**: `SCleanTests/ViewLogic/SwipeToTrashLogicTests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_trashProgress_normalizedCorrectly` | Progress calculation | 45pt drag / 90pt threshold → 0.5 |
| `test_trashProgress_clampedToOne` | Clamping | 180pt drag → 1.0 (not 2.0) |
| `test_shouldTrash_trueAboveThreshold` | Threshold check | ≥90pt upward → true |
| `test_shouldTrash_falseForDownwardDrag` | Direction check | Downward drag → false regardless of magnitude |

### EmptyTrashConfirmation Logic Tests
**File**: `SCleanTests/ViewLogic/EmptyTrashConfirmationLogicTests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_requiresHoldToConfirm_trueOver200Items` | Threshold | 201 items → requires hold |
| `test_requiresHoldToConfirm_falseUnder200Items` | Threshold | 199 items → simple tap OK |
| `test_holdComplete_triggersAfterDuration` | Hold timing | Hold 1+ second → triggers confirm |

---

## 5. UI Tests - Smoke Tests (Low Priority, High Value)

### Permission Flow
**File**: `SCleanUITests/PermissionFlowUITests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_deniedState_showsBlockedScreen` | Permission blocked | App with denied permission → shows "Open Settings" button |
| `test_grantPermission_showsHomeView` | Permission granted | Grant access → HomeView with years visible |

### Browse & Trash Flow
**File**: `SCleanUITests/BrowseAndTrashUITests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_browseYear_opensGridView` | Navigation | Tap year card → YearGridView appears |
| `test_tapPhoto_opensViewer` | Navigation | Tap grid cell → MediaViewerView appears |
| `test_swipeUp_trashesPhoto` | Core interaction | Swipe up in viewer → toast appears, photo advances |
| `test_undoToast_restoresPhoto` | Undo flow | Tap undo on toast → photo restored |

### Trash Management Flow
**File**: `SCleanUITests/TrashManagementUITests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_openTrash_showsTrashedItems` | Navigation | Tap trash button → TrashView with items |
| `test_restoreFromTrash_removesFromList` | Restore | Select item, tap restore → item removed from trash |
| `test_emptyTrash_showsConfirmation` | Delete flow | Tap "Empty Trash" → confirmation sheet appears |
| `test_confirmDelete_removesAllItems` | Delete flow | Confirm deletion → trash empty, stats updated |

### Settings Flow
**File**: `SCleanUITests/SettingsUITests.swift`

| Test | Purpose | Flow/Outcome |
|------|---------|--------------|
| `test_changeAppearance_updatesTheme` | Theme switching | Select "Dark" → app switches to dark mode |

---

## 6. Regression Tests (Add Per Bug)

Create `SCleanTests/Regressions/` directory. Add one test per fixed bug with naming:

```
test_regression_<issue_number>_<brief_description>
```

Example:
```swift
func test_regression_42_trashingLastItemDoesNotCrash() {
    // Trash the only remaining visible item
    // Assert: no crash, shows "Done" view
}
```

---

## Implementation Order (Recommended)

1. **Phase 1 - Core Logic** **[COMPLETED]**
   - TrashService tests (14 tests)
   - DeletionService tests (12 model tests)
   - StatsService tests (9 tests)
   - LibraryIndexStore tests (8 tests)
   - Test infrastructure (protocols + mocks)

2. **Phase 2 - Data Integrity** (Pending)
   - Model tests (DeletionStats, TrashedItem codable)
   - Additional persistence round-trip tests
   - Migration edge cases

3. **Phase 3 - Feature Logic** (Pending)
   - YearPhotosService tests
   - LibraryIndexer tests
   - FullImageLoader cache tests
   - View logic tests (extracted pure functions)

4. **Phase 4 - Integration** (Pending)
   - Permission service tests
   - UI smoke tests (2-5 critical flows)
   - Full DeletionService tests (requires PhotoLibraryProviding protocol)

---

## Test Infrastructure **[IMPLEMENTED]**

### Protocol Abstractions for DI

**Created in `SClean/Core/Services/Protocols/`:**

```swift
// KeyValueStoring.swift - For storage isolation
protocol KeyValueStoring {
    func data(forKey: String) -> Data?
    func set(_ data: Data?, forKey: String)
    func removeObject(forKey: String)
}
extension UserDefaults: KeyValueStoring {}

// DateProviding.swift - For time isolation
protocol DateProviding {
    var now: Date { get }
}
struct SystemDateProvider: DateProviding {
    var now: Date { Date() }
}
```

**Future (not yet needed):**
```swift
// For PhotoKit isolation (needed for full DeletionService testing)
protocol PhotoLibraryProviding {
    func fetchAssets(with options: PHFetchOptions) -> PHFetchResult<PHAsset>
    func performChanges(_ changeBlock: @escaping () -> Void) async throws
}
```

### Test Helpers **[IMPLEMENTED]**

**Created in `SCleanTests/Helpers/`:**

```swift
// MockKeyValueStore.swift - In-memory storage mock
final class MockKeyValueStore: KeyValueStoring {
    func data(forKey: String) -> Data?
    func set(_ data: Data?, forKey: String)
    func removeObject(forKey: String)
    func reset()  // Clear all data
    func hasKey(_ key: String) -> Bool
}

// MockDateProvider.swift - Controllable date provider
final class MockDateProvider: DateProviding {
    var now: Date
    func advance(by interval: TimeInterval)
    func set(_ date: Date)
}

// TestHelpers.swift - Factory functions
enum TestFactory {
    static func yearAsset(id:, creationDate:, mediaType:, duration:) -> YearAsset
    static func yearAssets(count:, year:) -> [YearAsset]
    static func trashedItem(assetID:, trashedAt:) -> TrashedItem
    static func indexedAsset(id:, year:, byteSize:, lastKnownChangeDate:) -> IndexedAsset
    static func librarySnapshot(version:, lastIndexedAt:, assets:) -> LibraryIndexSnapshot
}

enum TestBytes {
    static let oneMB: Int64, oneGB: Int64, halfGB: Int64, twoGB: Int64
}
```

---

## Running Tests

**In Xcode:**
- `Cmd + U` - Run all tests
- Click diamond icon next to test function/class

**Command Line:**
```bash
cd /Users/arseniypomazkov/MyLibrary/Projects/sclean/SClean

# Run all unit tests
xcodebuild test -scheme SClean -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:SCleanTests

# Run specific test file
xcodebuild test -scheme SClean -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:SCleanTests/TrashServiceTests

# Run specific test method
xcodebuild test -scheme SClean -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -only-testing:SCleanTests/TrashServiceTests/trash_addsItemToTrashedItems
```

---

## Notes

- **Swift Testing framework** used for unit tests (`import Testing`, `@Test` attribute)
- **XCTest** for UI tests (standard for XCUITest)
- Tests run in isolation - mocks reset between tests automatically
- Use `@MainActor` for service tests to match production actor isolation
- Test files auto-discovered via Xcode file system synchronization
