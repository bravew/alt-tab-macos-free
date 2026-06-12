import Cocoa

/// Off-main-thread screenshot capture for window thumbnails, plus the
/// "preview the selected window" overlay shown next to the switcher panel.
enum WindowThumbnails {
    static func previewSelectedIfNeeded() {
        if let session = SwitcherSession.current, ScreenRecordingPermission.status == .granted
               && TilesPanel.shared.isKeyWindow,
           let window = Windows.selectedWindow(),
           let id = window.cgWindowId,
           let thumbnail = window.thumbnail,
           let frame = previewFrame(window, session.shortcutIndex) {
            PreviewPanel.show(id, thumbnail, frame)
        } else {
            PreviewPanel.shared.orderOut(nil)
        }
    }

    /// Called when a fresh screenshot lands for `window`: refresh the preview contents if it's
    /// showing that window, or show the preview late if the screenshot is the one it was missing
    static func refreshPreviewAfterScreenshot(_ window: Window) {
        guard let session = SwitcherSession.current else { return }
        if !PreviewPanel.shared.isVisible {
            if Windows.selectedWindow()?.cgWindowId == window.cgWindowId {
                previewSelectedIfNeeded()
            }
            return
        }
        if let id = window.cgWindowId,
           let thumbnail = window.thumbnail,
           let frame = previewFrame(window, session.shortcutIndex) {
            PreviewPanel.updateIfShowing(id, thumbnail, frame)
        }
    }

    /// Cocoa-coordinates frame the selected-window preview should occupy,
    /// or nil if no preview feature is enabled for this shortcut
    private static func previewFrame(_ window: Window, _ shortcutIndex: Int) -> NSRect? {
        if Preferences.effectivePreviewBesideList(shortcutIndex) {
            return besideListFrame(window)
        }
        guard Preferences.effectivePreviewSelectedWindow(shortcutIndex),
              let position = window.position, let size = window.size else { return nil }
        // Flip Y coordinate from Quartz (0,0 at top-left) to Cocoa coordinates (0,0 at bottom-left)
        // Always use the primary screen as reference since all coordinates are relative to it
        let y = NSScreen.screens.first!.frame.maxY - (position.y + size.height)
        return NSRect(x: position.x, y: y, width: size.width, height: size.height)
    }

    /// DockDoor-style docked preview: aspect-fit the window into a box beside the switcher panel,
    /// on whichever side has more room, vertically centered on the panel and clamped to the screen
    private static func besideListFrame(_ window: Window) -> NSRect? {
        guard let size = window.size, size.width > 0, size.height > 0 else { return nil }
        let panel = TilesPanel.shared.frame
        let screen = NSScreen.preferred.visibleFrame
        let gap = Appearance.windowPadding
        let roomRight = screen.maxX - panel.maxX - gap * 2
        let roomLeft = panel.minX - screen.minX - gap * 2
        let maxWidth = min(max(roomRight, roomLeft), screen.width * 0.45)
        let maxHeight = screen.height * 0.6
        guard maxWidth >= 100 else { return nil }
        let scale = min(maxWidth / size.width, maxHeight / size.height)
        let fitted = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let x = roomRight >= roomLeft ? panel.maxX + gap : panel.minX - gap - fitted.width
        let y = min(max(panel.midY - fitted.height / 2, screen.minY), screen.maxY - fitted.height)
        return NSRect(x: x.rounded(), y: y.rounded(), width: fitted.width, height: fitted.height)
    }

    // dispatch screenshot requests off the main-thread, then wait for completion
    static func refreshAsync(_ windows: [Window], _ source: RefreshCausedBy, windowRemoved: Bool = false, prioritizedIds: Set<CGWindowID>? = nil) {
        let shortcutIndex = SwitcherSession.activeShortcutIndex
        guard (!windows.isEmpty || windowRemoved) && ScreenRecordingPermission.status == .granted
               && (!Appearance.hideThumbnails || Preferences.effectivePreviewSelectedWindow(shortcutIndex) || Preferences.effectivePreviewBesideList(shortcutIndex))
               && (Preferences.captureWindowsInBackground || SwitcherSession.isActive) else { return }
        var eligibleWindows = [Window]()
        for window in windows {
            if !window.isWindowlessApp, let cgWindowId = window.cgWindowId, cgWindowId != CGWindowID(bitPattern: -1) {
                eligibleWindows.append(window)
            }
        }
        guard (!eligibleWindows.isEmpty || windowRemoved) else { return }
        if #available(macOS 14.0, *),
           // mitigate macOS 15 bugs with ScreenCapture Kit (see https://github.com/lwouis/alt-tab-macos/issues/5190)
           ProcessInfo.processInfo.operatingSystemVersion.majorVersion != 15 {
            WindowCaptureScreenshots.oneTimeScreenshots(eligibleWindows, source, prioritizedIds: prioritizedIds)
        } else {
            WindowCaptureScreenshotsPrivateApi.oneTimeScreenshots(eligibleWindows, source, prioritizedIds: prioritizedIds)
        }
    }
}
