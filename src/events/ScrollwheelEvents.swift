import Cocoa

class ScrollwheelEvents {
    static var shouldBeEnabled: Bool!
    private static var eventTap: CFMachPort!
    // accumulated precise (trackpad) scroll distance not yet converted into selection steps
    private static var scrollAccumulatorX = CGFloat(0)
    private static var scrollAccumulatorY = CGFloat(0)
    private static let pixelsPerSelectionStep = CGFloat(50)

    static func observe() {
        observe_()
        toggle(false)
    }

    static func toggle(_ enabled: Bool) {
        guard enabled != shouldBeEnabled else { return }
        shouldBeEnabled = enabled
        scrollAccumulatorX = 0
        scrollAccumulatorY = 0
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        }
    }

    static func reEnableTapIfNeeded() {
        guard let eventTap, shouldBeEnabled, !CGEvent.tapIsEnabled(tap: eventTap) else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        Logger.warning { "" }
    }

    private static func observe_() {
        // CGEvent.tapCreate returns null if ensureAccessibilityCheckboxIsChecked() didn't pass
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap, // we need raw data
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: NSEvent.EventTypeMask.scrollWheel.rawValue,
            callback: handleEvent,
            userInfo: nil)
        if let eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
            CFRunLoopAddSource(BackgroundWork.keyboardAndMouseAndTrackpadEventsThread.runLoop, runLoopSource, .commonModes)
        } else {
            App.restart()
        }
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
        if type.rawValue == NSEvent.EventType.scrollWheel.rawValue {
            if Preferences.scrollToSelectEnabled && SwitcherSession.isActive && handleSelectionScroll(cgEvent) {
                return nil // absorb: the scroll drives the switcher selection
            }
            if cgEvent.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
                // block continuous (trackpad) scrolling; let discrete (mouse) scrolling through
                return nil
            }
        } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) && shouldBeEnabled {
            CGEvent.tapEnable(tap: eventTap!, enable: true)
        }
        return Unmanaged.passUnretained(cgEvent) // focused app will receive the event
    }

    /// the selection follows the scroll direction (or the opposite, per the direction setting),
    /// on both axes: vertical scroll moves up/down, horizontal scroll moves left/right.
    /// Trackpads accumulate precise pixel deltas so a continuous swipe steps through the tiles;
    /// mouse wheels step once per notch
    private static func handleSelectionScroll(_ cgEvent: CGEvent) -> Bool {
        guard let nsEvent = cgEvent.toNSEvent() else { return false }
        if nsEvent.hasPreciseScrollingDeltas {
            accumulateThenCycle(&scrollAccumulatorY, nsEvent.scrollingDeltaY, horizontal: false)
            accumulateThenCycle(&scrollAccumulatorX, nsEvent.scrollingDeltaX, horizontal: true)
        } else if nsEvent.scrollingDeltaY != 0 {
            cycleSelection(nsEvent.scrollingDeltaY > 0 ? 1 : -1, horizontal: false)
        } else if nsEvent.scrollingDeltaX != 0 {
            cycleSelection(nsEvent.scrollingDeltaX > 0 ? 1 : -1, horizontal: true)
        }
        return true
    }

    private static func accumulateThenCycle(_ accumulator: inout CGFloat, _ delta: CGFloat, horizontal: Bool) {
        if delta * accumulator < 0 {
            // direction flipped; discard leftover momentum so the selection turns around instantly
            accumulator = 0
        }
        accumulator += delta
        let steps = Int(accumulator / pixelsPerSelectionStep)
        if steps != 0 {
            accumulator -= CGFloat(steps) * pixelsPerSelectionStep
            cycleSelection(steps, horizontal: horizontal)
        }
    }

    private static func cycleSelection(_ steps: Int, horizontal: Bool) {
        // positive steps = positive scrollingDelta = the user scrolled down/right (with natural scrolling)
        var towardsNext = steps > 0
        if Preferences.scrollToSelectDirection == .reversed {
            towardsNext.toggle()
        }
        DispatchQueue.main.async {
            // the titles style is a vertical list: only vertical scroll moves the selection.
            // The other styles lay tiles out in rows: vertical scroll moves between rows,
            // horizontal scroll moves through the tiles, wrapping across rows
            let isVerticalList = Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .titles
            guard !(isVerticalList && horizontal) else { return }
            if Preferences.trackpadHapticFeedbackEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
            }
            let direction: Direction = horizontal ? (towardsNext ? .right : .left) : (towardsNext ? .down : .up)
            for _ in 0..<abs(steps) {
                App.cycleSelection(direction, allowWrap: false)
            }
        }
    }
}
