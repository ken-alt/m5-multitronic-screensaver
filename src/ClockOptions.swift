//
//  ClockOptions.swift
//  M-5 Panel with Clock screensaver
//
//  The configure sheet. `ScreenSaverView` still exposes `hasConfigureSheet`
//  and `configureSheet` — both are present and undeprecated in the macOS 26
//  SDK — and the redesigned System Settings pane still calls them, so a saver
//  can carry preferences without reaching for anything private.
//
//  Built in code rather than a nib: the whole sheet is two controls, and a nib
//  would have to be copied into all five bundles by the build script.
//

import ScreenSaver
import Cocoa

/// What a saver has to provide to carry this sheet. The savers that use it do
/// not share a base class — one is the M-5 panel with the clock module sunk
/// into it, another is that module standing alone — and what 24-hour does to
/// the panel differs between them, so the sheet asks rather than assumes.
protocol ClockOptionsHost: AnyObject {
    func optionsChanged()

    /// One line under the control saying what the choice does to *this* panel.
    var optionsNote: String { get }
}

final class ClockOptions: NSObject {

    static let shared = ClockOptions()

    private var window: NSWindow?
    private var format: NSSegmentedControl?
    private var note: NSTextField?
    private weak var view: ClockOptionsHost?

    /// The sheet, reused across openings. System Settings runs this modally
    /// and expects the sheet to end itself, so both buttons do.
    func sheet(for view: ClockOptionsHost) -> NSWindow {
        self.view = view
        if let w = window {
            format?.selectedSegment = ShipboardClock.use24Hour ? 1 : 0
            note?.stringValue = view.optionsNote
            return w
        }

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 164),
                         styleMask: [.titled], backing: .buffered, defer: false)
        // Sized to the content rect, not contentLayoutRect - the latter
        // excludes the title bar, which pushed the buttons off the bottom.
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 164))

        let title = NSTextField(labelWithString: "Shipboard Clock")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.frame = NSRect(x: 24, y: 122, width: 332, height: 22)

        let caption = NSTextField(labelWithString: "Time format")
        caption.font = .systemFont(ofSize: 12)
        caption.textColor = .secondaryLabelColor
        caption.frame = NSRect(x: 24, y: 98, width: 120, height: 18)

        let seg = NSSegmentedControl(labels: ["12-hour", "24-hour"],
                                     trackingMode: .selectOne,
                                     target: nil, action: nil)
        seg.frame = NSRect(x: 22, y: 66, width: 200, height: 24)
        seg.selectedSegment = ShipboardClock.use24Hour ? 1 : 0
        format = seg

        // A 24-hour reading has no AM/PM, and what each panel does about that
        // window is its own business — worth saying, since it changes the
        // shape of the panel rather than just its text.
        let note = NSTextField(labelWithString: view.optionsNote)
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor
        note.frame = NSRect(x: 24, y: 46, width: 332, height: 16)
        self.note = note

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: 186, y: 12, width: 84, height: 32)
        cancel.keyEquivalent = "\u{1b}"

        let ok = NSButton(title: "OK", target: self, action: #selector(accept(_:)))
        ok.bezelStyle = .rounded
        ok.frame = NSRect(x: 274, y: 12, width: 84, height: 32)
        ok.keyEquivalent = "\r"

        for v in [title, caption, seg, note, cancel, ok] as [NSView] { content.addSubview(v) }
        w.contentView = content
        window = w
        return w
    }

    private func close(_ w: NSWindow) {
        if let parent = w.sheetParent {
            parent.endSheet(w)
        } else {
            w.orderOut(nil)
        }
    }

    @objc private func accept(_ sender: Any) {
        ShipboardClock.use24Hour = (format?.selectedSegment == 1)
        view?.optionsChanged()
        if let w = window { close(w) }
    }

    @objc private func cancel(_ sender: Any) {
        if let w = window { close(w) }
    }
}
