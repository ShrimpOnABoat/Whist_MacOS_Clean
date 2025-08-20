//
//  CameraShakeModifier.swift
//  Whist
//
//  Created by Tony Buffard on 2025-03-02.
//

import SwiftUI

// A modifier that applies random shake to any view
struct CameraShakeModifier: ViewModifier {
    // Current shake offset
    @Binding var currentOffset: CGSize
    
    func body(content: Content) -> some View {
        content
            .offset(x: currentOffset.width, y: currentOffset.height)
    }
}

// Extend View to make it easier to apply the modifier
extension View {
    func cameraShake(offset: Binding<CGSize>) -> some View {
        self.modifier(CameraShakeModifier(currentOffset: offset))
    }
}

// Add these properties to your GameManager class:


// Add this method to your GameManager class:

// Update the Effects layer in GameView.swift to include our new impact effect:

// Apply camera shake to the game content in GameView.swift:
// Wrap the main content ZStack with this modifier:
