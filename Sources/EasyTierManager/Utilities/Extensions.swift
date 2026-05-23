import AppKit
import SwiftUI

extension NSColor {
    var color: Color {
        Color(self)
    }

    static var background: NSColor {
        NSColor(named: "Background") ?? NSColor.windowBackgroundColor
    }

    static var background1: NSColor {
        NSColor(named: "Background1") ?? NSColor.controlBackgroundColor
    }

    static var background2: NSColor {
        NSColor(named: "Background2") ?? NSColor.underPageBackgroundColor
    }

    static var border: NSColor {
        NSColor(named: "Border") ?? NSColor.separatorColor
    }

    static var border2: NSColor {
        NSColor(named: "Border2") ?? NSColor.gridColor
    }
}
