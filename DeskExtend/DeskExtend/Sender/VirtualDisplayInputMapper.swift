import Foundation
import AppKit

class VirtualDisplayInputMapper {
    private let geometry: VirtualDisplayGeometry
    private var lastMouseLocation: NSPoint = .zero
    
    init(geometry: VirtualDisplayGeometry) {
        self.geometry = geometry
    }
    
    func mapMouseEvent(_ event: NSEvent, window: NSWindow) -> MouseInputEvent? {
        let windowLocation = event.locationInWindow
        let screenLocation = window.convertPoint(toScreen: windowLocation)
        
        let mappedX = screenLocation.x - CGFloat(geometry.virtualX)
        let mappedY = screenLocation.y - CGFloat(geometry.virtualY)
        
        guard mappedX >= 0 && mappedX <= 1920 && mappedY >= 0 && mappedY <= 1080 else {
            return nil
        }
        
        lastMouseLocation = NSPoint(x: mappedX, y: mappedY)
        
        return MouseInputEvent(
            x: Int(mappedX),
            y: Int(mappedY),
            type: mapMouseEventType(event.type),
            button: mapMouseButton(event),
            scrollDelta: mapScrollDelta(event),
            timestamp: Date()
        )
    }
    
    func mapKeyEvent(_ event: NSEvent) -> KeyboardInputEvent? {
        return KeyboardInputEvent(
            keyCode: event.keyCode,
            characters: event.characters ?? "",
            type: event.type == .keyDown ? .down : .up,
            modifiers: mapModifiers(event),
            timestamp: Date()
        )
    }
    
    private func mapMouseEventType(_ type: NSEvent.EventType) -> MouseInputEvent.EventType {
        switch type {
        case .leftMouseDown: return .down
        case .leftMouseUp: return .up
        case .mouseMoved: return .move
        case .leftMouseDragged: return .drag
        case .rightMouseDown: return .down
        case .rightMouseUp: return .up
        case .rightMouseDragged: return .drag
        case .scrollWheel: return .scroll
        default: return .move
        }
    }
    
    private func mapMouseButton(_ event: NSEvent) -> MouseInputEvent.Button {
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            return .left
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            return .right
        case .otherMouseDown, .otherMouseUp:
            return .middle
        default:
            return .left
        }
    }
    
    private func mapScrollDelta(_ event: NSEvent) -> (dx: Double, dy: Double)? {
        guard event.type == .scrollWheel else { return nil }
        return (dx: Double(event.scrollingDeltaX), dy: Double(event.scrollingDeltaY))
    }
    
    private func mapModifiers(_ event: NSEvent) -> Set<KeyboardInputEvent.Modifier> {
        var modifiers: Set<KeyboardInputEvent.Modifier> = []
        let flags = event.modifierFlags
        
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        
        return modifiers
    }
}

struct MouseInputEvent {
    enum EventType {
        case down, up, move, drag, scroll
    }
    
    enum Button {
        case left, right, middle
    }
    
    let x: Int
    let y: Int
    let type: EventType
    let button: Button
    let scrollDelta: (dx: Double, dy: Double)?
    let timestamp: Date
}

struct KeyboardInputEvent {
    enum EventType {
        case down, up
    }
    
    enum Modifier: Hashable {
        case shift, control, option, command
    }
    
    let keyCode: UInt16
    let characters: String
    let type: EventType
    let modifiers: Set<Modifier>
    let timestamp: Date
}
