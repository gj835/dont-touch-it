import CoreGraphics

/// Counts where input events were routed while Touch Guard was running, so the
/// diagnostic log can show whether hover, cursor, scroll and gesture input still
/// reached the windows underneath the overlay.
///
/// Only counts are kept. No coordinates, window numbers, application names or
/// event contents are stored or logged.
struct InputRoutingStats {
    private struct Counter {
        var total = 0
        /// Events for which the system reported a window that can handle them.
        var withWindowInfo = 0
        /// Events that the system routed to one of the overlay windows.
        var toOverlay = 0
        /// Events that arrived while the overlay was accepting mouse events.
        var whileOpaque = 0
    }

    private static let categoryOrder = [
        "mouse_moved", "button", "drag", "scroll",
        "gesture_generic", "pinch", "rotate", "swipe", "smart_zoom", "pressure"
    ]
    private var counters: [String: Counter] = [:]

    mutating func reset() {
        counters.removeAll()
    }

    mutating func record(
        _ type: CGEventType,
        event: CGEvent,
        overlayWindowNumbers: Set<Int64>,
        overlayIsOpaque: Bool
    ) {
        guard let category = Self.category(of: type) else { return }
        var counter = counters[category, default: Counter()]
        counter.total += 1
        if overlayIsOpaque {
            counter.whileOpaque += 1
        }
        let handlingWindow = event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
        if handlingWindow != 0 {
            counter.withWindowInfo += 1
            if overlayWindowNumbers.contains(handlingWindow) {
                counter.toOverlay += 1
            }
        }
        counters[category] = counter
    }

    /// One line, for example:
    /// `mouse_moved total=1200 window_info=1200 to_overlay=0 | scroll total=300 ...`
    var summary: String {
        let parts = Self.categoryOrder.compactMap { category -> String? in
            guard let counter = counters[category] else { return nil }
            return "\(category) total=\(counter.total) window_info=\(counter.withWindowInfo) to_overlay=\(counter.toOverlay) while_opaque=\(counter.whileOpaque)"
        }
        return parts.isEmpty ? "no pointer events" : parts.joined(separator: " | ")
    }

    private static func category(of type: CGEventType) -> String? {
        switch type.rawValue {
        case 29: return "gesture_generic"
        case 30: return "pinch"
        case 18: return "rotate"
        case 31: return "swipe"
        case 32: return "smart_zoom"
        case 34: return "pressure"
        default: break
        }
        switch type {
        case .mouseMoved:
            return "mouse_moved"
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            return "button"
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return "drag"
        case .scrollWheel:
            return "scroll"
        default:
            return nil
        }
    }
}
