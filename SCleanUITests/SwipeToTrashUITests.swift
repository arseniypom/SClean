//
//  SwipeToTrashUITests.swift
//  SCleanUITests
//
//  UI tests for swipe-to-trash animation
//  Verifies that photos don't shift unexpectedly after swipe
//

import XCTest

final class SwipeToTrashUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helper to find elements by accessibility identifier

    private func element(withIdentifier identifier: String) -> XCUIElement {
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    // MARK: - Test: Next Photo Position Consistency

    /// Tests that the next photo doesn't shift vertically when swipe-to-trash completes.
    ///
    /// This test detects the visual "shift down" bug by:
    /// 1. Recording the Y position of the photo BEFORE swipe
    /// 2. Performing swipe-to-trash
    /// 3. Capturing Y position multiple times AFTER swipe to detect any movement
    /// 4. Comparing positions to detect drift
    @MainActor
    func testSwipeToTrash_nextPhotoDoesNotShiftVertically() throws {
        print("\n" + String(repeating: "=", count: 60))
        print("TEST: testSwipeToTrash_nextPhotoDoesNotShiftVertically")
        print(String(repeating: "=", count: 60))

        // MARK: 1. Navigate to media viewer
        print("\n--- STEP 1: Navigate to media viewer ---")

        let yearCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'yearCard_'"))
        let firstYearCard = yearCards.firstMatch
        XCTAssertTrue(firstYearCard.waitForExistence(timeout: 10), "Year card should appear on home screen")
        print("Found year card: \(firstYearCard.identifier)")
        firstYearCard.tap()

        let firstPhoto = app.buttons["gridPhoto_0"]
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 10), "Grid photo should appear")
        print("Found grid photo, tapping...")
        firstPhoto.tap()

        let currentPhoto = element(withIdentifier: "currentPhotoView")
        XCTAssertTrue(currentPhoto.waitForExistence(timeout: 5), "Current photo view should appear")
        print("Media viewer opened successfully")

        // Let initial animations settle
        Thread.sleep(forTimeInterval: 0.5)

        // MARK: 2. Capture initial state
        print("\n--- STEP 2: Capture initial state (BEFORE swipe) ---")

        print("Container (currentPhotoView) frame:")
        let containerFrame = currentPhoto.frame
        print("  - Origin: (\(String(format: "%.1f", containerFrame.origin.x)), \(String(format: "%.1f", containerFrame.origin.y)))")
        print("  - Size: \(String(format: "%.1f", containerFrame.width)) x \(String(format: "%.1f", containerFrame.height))")

        // Try to find the ACTUAL IMAGE element (photoImage)
        // This might not exist if: image still loading, it's a video, or error state
        let initialPhotoImage = element(withIdentifier: "photoImage")
        let hasPhotoImage = initialPhotoImage.waitForExistence(timeout: 5)

        // Determine which element to measure
        let measureElement: XCUIElement
        let measureElementName: String

        if hasPhotoImage {
            measureElement = initialPhotoImage
            measureElementName = "photoImage (actual image)"
            print("\n✓ Found photoImage element - will measure actual image position")
        } else {
            measureElement = currentPhoto
            measureElementName = "currentPhotoView (container)"
            print("\n⚠️ photoImage not found (might be video or still loading)")
            print("  Falling back to measuring container position")
        }

        let initialFrame = measureElement.frame
        print("\nMeasuring: \(measureElementName)")
        print("  - Origin: (\(String(format: "%.1f", initialFrame.origin.x)), \(String(format: "%.1f", initialFrame.origin.y)))")
        print("  - Size: \(String(format: "%.1f", initialFrame.width)) x \(String(format: "%.1f", initialFrame.height))")
        print("  - Center Y: \(String(format: "%.2f", initialFrame.midY))")
        print("  - MinY (TOP): \(String(format: "%.2f", initialFrame.minY))")
        print("  - MaxY (BOTTOM): \(String(format: "%.2f", initialFrame.maxY))")

        // MARK: 3. Perform swipe-to-trash gesture
        print("\n--- STEP 3: Perform swipe-to-trash gesture ---")

        let startPoint = currentPhoto.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let endPoint = currentPhoto.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))

        print("Swiping from center (0.5, 0.5) to top (0.5, 0.1)...")
        let swipeStartTime = Date()
        startPoint.press(forDuration: 0.05, thenDragTo: endPoint)
        let swipeEndTime = Date()
        print("Swipe gesture completed in \(String(format: "%.2f", swipeEndTime.timeIntervalSince(swipeStartTime)))s")

        // MARK: 4. Rapid multi-capture to detect shift
        print("\n--- STEP 4: Rapid position capture (detecting shift) ---")

        // Wait minimal time for animation to complete
        // Animation is 0.35s fly + 0.38s delay = 0.73s total
        // But XCUITest's "wait for idle" should have handled most of this
        Thread.sleep(forTimeInterval: 0.2)

        // Find the element to measure (same type as initial)
        let newMeasureElement: XCUIElement
        if hasPhotoImage {
            let newPhotoImage = element(withIdentifier: "photoImage")
            if newPhotoImage.waitForExistence(timeout: 3) {
                newMeasureElement = newPhotoImage
                print("Measuring: photoImage (actual image)")
            } else {
                // Fall back to container
                let newContainer = element(withIdentifier: "currentPhotoView")
                guard newContainer.waitForExistence(timeout: 2) else {
                    XCTFail("Neither photoImage nor currentPhotoView found after swipe")
                    return
                }
                newMeasureElement = newContainer
                print("⚠️ photoImage not found after swipe, using container")
            }
        } else {
            let newContainer = element(withIdentifier: "currentPhotoView")
            guard newContainer.waitForExistence(timeout: 2) else {
                XCTFail("currentPhotoView not found after swipe")
                return
            }
            newMeasureElement = newContainer
            print("Measuring: currentPhotoView (container)")
        }

        print("Capturing positions...")

        // Capture position multiple times to detect any ongoing shift
        var captures: [(time: TimeInterval, y: CGFloat, minY: CGFloat)] = []
        let captureStartTime = Date()

        // Capture 20 times over ~500ms
        for i in 0..<20 {
            let frame = newMeasureElement.frame
            let elapsed = Date().timeIntervalSince(captureStartTime)
            captures.append((elapsed, frame.midY, frame.minY))

            if i < 5 || i >= 15 {
                // Print first 5 and last 5 captures
                print("Capture \(String(format: "%2d", i)): t=\(String(format: "%.3f", elapsed))s, centerY=\(String(format: "%.2f", frame.midY)), topY=\(String(format: "%.2f", frame.minY))")
            } else if i == 5 {
                print("  ... (captures 5-14 omitted) ...")
            }

            Thread.sleep(forTimeInterval: 0.025) // 25ms between captures
        }

        // MARK: 5. Analyze captures for shift
        print("\n--- STEP 5: Analyze for position shift ---")

        let centerYValues = captures.map { $0.y }
        let topYValues = captures.map { $0.minY }

        let minCenterY = centerYValues.min()!
        let maxCenterY = centerYValues.max()!
        let firstCenterY = centerYValues.first!
        let lastCenterY = centerYValues.last!
        let rangeCenterY = maxCenterY - minCenterY
        let driftCenterY = lastCenterY - firstCenterY

        let minTopY = topYValues.min()!
        let maxTopY = topYValues.max()!
        let rangeTopY = maxTopY - minTopY

        print("Center Y analysis over \(String(format: "%.0f", captures.last!.time * 1000))ms:")
        print("  - First capture: \(String(format: "%.2f", firstCenterY))")
        print("  - Last capture: \(String(format: "%.2f", lastCenterY))")
        print("  - Min: \(String(format: "%.2f", minCenterY))")
        print("  - Max: \(String(format: "%.2f", maxCenterY))")
        print("  - Range (max-min): \(String(format: "%.2f", rangeCenterY)) points")
        print("  - Drift (last-first): \(String(format: "%.2f", driftCenterY)) points")

        print("\nTop Y (minY) analysis:")
        print("  - Min: \(String(format: "%.2f", minTopY))")
        print("  - Max: \(String(format: "%.2f", maxTopY))")
        print("  - Range: \(String(format: "%.2f", rangeTopY)) points")

        // MARK: 6. Compare with initial position
        print("\n--- STEP 6: Compare with initial position ---")

        let finalFrame = newMeasureElement.frame
        let positionChange = finalFrame.midY - initialFrame.midY
        let topPositionChange = finalFrame.minY - initialFrame.minY

        print("Position comparison (\(measureElementName)):")
        print("  - Initial center Y (before swipe): \(String(format: "%.2f", initialFrame.midY))")
        print("  - Final center Y (after swipe): \(String(format: "%.2f", finalFrame.midY))")
        print("  - Center Y change: \(String(format: "%.2f", positionChange)) points")
        print("")
        print("  - Initial top Y (before swipe): \(String(format: "%.2f", initialFrame.minY))")
        print("  - Final top Y (after swipe): \(String(format: "%.2f", finalFrame.minY))")
        print("  - Top Y change: \(String(format: "%.2f", topPositionChange)) points")
        print("")
        print("  - Initial size: \(String(format: "%.1f", initialFrame.width)) x \(String(format: "%.1f", initialFrame.height))")
        print("  - Final size: \(String(format: "%.1f", finalFrame.width)) x \(String(format: "%.1f", finalFrame.height))")
        print("  - Size change: \(String(format: "%.1f", finalFrame.width - initialFrame.width)) x \(String(format: "%.1f", finalFrame.height - initialFrame.height))")

        // Use the larger of center or top change for assertion
        let rangeY = rangeCenterY

        // MARK: 7. Assertions
        print("\n--- STEP 7: Assertions ---")

        // Assert 1: No shift during observation (captures should be stable)
        let maxAllowedRange: CGFloat = 2.0
        print("Assert 1: Center Y range (\(String(format: "%.2f", rangeY))) should be < \(maxAllowedRange)")
        XCTAssertLessThan(
            rangeY,
            maxAllowedRange,
            """

            ❌ SHIFT DETECTED during observation!
            The photo's Y position changed while being observed.
            This indicates an ongoing animation or layout instability.

            Range: \(String(format: "%.2f", rangeY)) points (max allowed: \(maxAllowedRange))
            First center Y: \(String(format: "%.2f", firstCenterY))
            Last center Y: \(String(format: "%.2f", lastCenterY))
            """
        )

        // Assert 2: Position should match initial (photos should be at same Y)
        let maxAllowedDrift: CGFloat = 3.0
        print("Assert 2: Position change (\(String(format: "%.2f", abs(positionChange)))) should be < \(maxAllowedDrift)")
        XCTAssertLessThan(
            abs(positionChange),
            maxAllowedDrift,
            """

            ❌ POSITION MISMATCH detected!
            The next photo is at a different Y position than the previous photo.
            This indicates a layout inconsistency between the preview and TabView page.

            Initial center Y: \(String(format: "%.2f", initialFrame.midY))
            Final center Y: \(String(format: "%.2f", finalFrame.midY))
            Difference: \(String(format: "%.2f", positionChange)) points
            """
        )

        // Assert 3: Top position should also match (catches top-anchoring issues)
        print("Assert 3: Top Y change (\(String(format: "%.2f", abs(topPositionChange)))) should be < \(maxAllowedDrift)")
        XCTAssertLessThan(
            abs(topPositionChange),
            maxAllowedDrift,
            """

            ❌ TOP POSITION MISMATCH detected!
            The next photo's top edge is at a different position.

            Initial top Y: \(String(format: "%.2f", initialFrame.minY))
            Final top Y: \(String(format: "%.2f", finalFrame.minY))
            Difference: \(String(format: "%.2f", topPositionChange)) points
            """
        )

        print("\n✅ All assertions passed")
        print(String(repeating: "=", count: 60) + "\n")
    }

    // MARK: - Test: Multiple Consecutive Swipes

    /// Tests that multiple consecutive swipes don't accumulate position errors.
    @MainActor
    func testSwipeToTrash_multipleSwipesNoAccumulatedShift() throws {
        print("\n" + String(repeating: "=", count: 60))
        print("TEST: testSwipeToTrash_multipleSwipesNoAccumulatedShift")
        print(String(repeating: "=", count: 60))

        // Navigate to viewer
        let yearCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'yearCard_'"))
        let firstYearCard = yearCards.firstMatch
        XCTAssertTrue(firstYearCard.waitForExistence(timeout: 10), "Year card should appear")
        firstYearCard.tap()

        let firstPhoto = app.buttons["gridPhoto_0"]
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 10), "Grid photo should appear")
        firstPhoto.tap()

        let currentPhoto = element(withIdentifier: "currentPhotoView")
        XCTAssertTrue(currentPhoto.waitForExistence(timeout: 5), "Current photo view should appear")

        Thread.sleep(forTimeInterval: 0.5)

        // Record initial Y position
        let initialY = currentPhoto.frame.midY
        print("\nInitial Y position: \(String(format: "%.2f", initialY))")
        print("\nPerforming 3 consecutive swipes...\n")

        // Perform 3 consecutive swipes
        for swipeIndex in 0..<3 {
            let photo = element(withIdentifier: "currentPhotoView")
            guard photo.waitForExistence(timeout: 3) else {
                print("Swipe \(swipeIndex + 1): No more photos available")
                break
            }

            let start = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            start.press(forDuration: 0.05, thenDragTo: end)

            Thread.sleep(forTimeInterval: 0.3)

            let newPhoto = element(withIdentifier: "currentPhotoView")
            if newPhoto.exists {
                let newY = newPhoto.frame.midY
                let drift = newY - initialY
                print("Swipe \(swipeIndex + 1): Y=\(String(format: "%.2f", newY)), drift from initial=\(String(format: "%.2f", drift))")

                XCTAssertLessThan(
                    abs(drift),
                    5.0,
                    """

                    ❌ ACCUMULATED DRIFT detected after swipe \(swipeIndex + 1)!
                    Initial Y: \(String(format: "%.2f", initialY))
                    Current Y: \(String(format: "%.2f", newY))
                    Drift: \(String(format: "%.2f", drift)) points
                    """
                )
            }
        }

        print("\n✅ No accumulated drift detected")
        print(String(repeating: "=", count: 60) + "\n")
    }

    // MARK: - Test: Frame-by-Frame Shift Detection

    /// Specifically designed to catch the "appears then shifts down" bug.
    /// Captures position immediately after swipe and checks for any movement.
    @MainActor
    func testSwipeToTrash_detectVisualShiftAfterAppear() throws {
        print("\n" + String(repeating: "=", count: 60))
        print("TEST: testSwipeToTrash_detectVisualShiftAfterAppear")
        print(String(repeating: "=", count: 60))

        // Navigate to viewer
        let yearCards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'yearCard_'"))
        let firstYearCard = yearCards.firstMatch
        XCTAssertTrue(firstYearCard.waitForExistence(timeout: 10), "Year card should appear")
        firstYearCard.tap()

        let firstPhoto = app.buttons["gridPhoto_0"]
        XCTAssertTrue(firstPhoto.waitForExistence(timeout: 10), "Grid photo should appear")
        firstPhoto.tap()

        let currentPhoto = element(withIdentifier: "currentPhotoView")
        XCTAssertTrue(currentPhoto.waitForExistence(timeout: 5), "Current photo view should appear")

        Thread.sleep(forTimeInterval: 0.5)

        print("\n--- Performing swipe and capturing positions rapidly ---")

        // Perform swipe
        let start = currentPhoto.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = currentPhoto.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        start.press(forDuration: 0.05, thenDragTo: end)

        // Immediately start capturing (don't wait for full animation)
        // This should catch the photo appearing and any subsequent shift

        var captures: [CGFloat] = []
        let newPhoto = element(withIdentifier: "currentPhotoView")

        // Capture as fast as possible for 1 second
        let captureStart = Date()
        while Date().timeIntervalSince(captureStart) < 1.0 {
            if newPhoto.exists {
                captures.append(newPhoto.frame.midY)
            }
            // No sleep - capture as fast as XCUITest allows
        }

        print("Captured \(captures.count) frames in 1 second")

        guard captures.count >= 5 else {
            XCTFail("Not enough captures to analyze (got \(captures.count), need >= 5)")
            return
        }

        // Analyze captures
        let minY = captures.min()!
        let maxY = captures.max()!
        let range = maxY - minY

        // Look for pattern: starts at one Y, then shifts to another
        let firstFiveAvg = captures.prefix(5).reduce(0, +) / 5.0
        let lastFiveAvg = captures.suffix(5).reduce(0, +) / 5.0
        let avgShift = lastFiveAvg - firstFiveAvg

        print("\nAnalysis:")
        print("  - Total captures: \(captures.count)")
        print("  - Y range: \(String(format: "%.2f", range)) points")
        print("  - First 5 avg Y: \(String(format: "%.2f", firstFiveAvg))")
        print("  - Last 5 avg Y: \(String(format: "%.2f", lastFiveAvg))")
        print("  - Average shift: \(String(format: "%.2f", avgShift)) points")

        // Print some sample captures
        print("\nSample captures (Y values):")
        let sampleIndices = [0, 1, 2, captures.count/4, captures.count/2, captures.count*3/4, captures.count-3, captures.count-2, captures.count-1]
        for i in sampleIndices where i < captures.count {
            print("  [\(i)]: \(String(format: "%.2f", captures[i]))")
        }

        // Assert: shift should be minimal
        let maxAllowedShift: CGFloat = 2.0
        XCTAssertLessThan(
            abs(avgShift),
            maxAllowedShift,
            """

            ❌ VISUAL SHIFT DETECTED!
            The photo shifted after appearing.

            Average of first 5 captures: \(String(format: "%.2f", firstFiveAvg))
            Average of last 5 captures: \(String(format: "%.2f", lastFiveAvg))
            Shift: \(String(format: "%.2f", avgShift)) points

            This is the "appears then shifts down" bug!
            """
        )

        print("\n✅ No visual shift detected")
        print(String(repeating: "=", count: 60) + "\n")
    }
}
