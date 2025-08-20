//
//  Extensions.swift
//  Whist
//
//  Created by Tony Buffard on 2024-11-18.
//  Useful extensions to standard types.

import Foundation
import SwiftUI

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

extension String {
    /// Returns the first character of the string as a String.
    /// If the string is empty, returns an empty string.
    func firstInitial() -> String {
        return self.first.map { String($0) } ?? ""
    }
    
    /// Returns the initials from the string.
    /// For example, "Tony Buffard" returns "TB".
    func initials() -> String {
        let words = self.split(separator: " ")
        let initials = words.compactMap { $0.first }.map { String($0) }
        return initials.joined()
    }
    
    func toPlayerIdEnum() -> PlayerId {
        PlayerId(rawValue: self) ?? .dd
    }
}

extension Bool {
    static func random(probability: Double) -> Bool {
        guard (0...1).contains(probability) else { return false }
        return Double.random(in: 0...1) < probability
    }
}

extension Color {
    /// Multiplies the RGB components of the color by a factor
    func withRGBMultiplication(_ factor: CGFloat) -> Color {
        guard let components = self.cgColor?.components, components.count >= 3 else {
            return self // Fallback to original color if components are unavailable
        }

        let red = min(1.0, components[0] * factor)
        let green = min(1.0, components[1] * factor)
        let blue = min(1.0, components[2] * factor)

        return Color(red: red, green: green, blue: blue)
    }
}

extension View {
    func snapshot() -> NSImage? {
        let controller = NSHostingController(rootView: self)
        let targetSize = controller.view.intrinsicContentSize
        let contentRect = NSRect(origin: .zero, size: targetSize)
        
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = controller.view
        
        guard
            let bitmapRep = controller.view.bitmapImageRepForCachingDisplay(in: contentRect)
        else { return nil }
        
        controller.view.cacheDisplay(in: contentRect, to: bitmapRep)
        let image = NSImage(size: bitmapRep.size)
        image.addRepresentation(bitmapRep)
        return image
    }
}

extension Double {
    var toRadians: Double { self * .pi / 180.0 }
}

extension Path {
    /// Creates a reversed version of the current path.
    func reversedPath() -> Path {
        var reversedPath = Path()
        var elements: [Path.Element] = []

        // Collect all path elements
        self.forEach { element in
            elements.append(element)
        }

        // Iterate through elements in reverse order
        for element in elements.reversed() {
            switch element {
            case .move(to: let point):
                reversedPath.move(to: point)
            case .line(to: let point):
                reversedPath.addLine(to: point)
            case .quadCurve(to: let point, control: let controlPoint):
                reversedPath.addQuadCurve(to: point, control: controlPoint)
            case .curve(to: let point, control1: let control1, control2: let control2):
                reversedPath.addCurve(to: point, control1: control1, control2: control2)
            case .closeSubpath:
                reversedPath.closeSubpath()
            }
        }

        return reversedPath
    }
}
