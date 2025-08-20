//
//  SubtleFailureView.swift
//  Whist
//
//  Created by Tony Buffard on 2025-03-02.
//


//
//  SubtleFailureView.swift
//  Whist
//
//  Created on 2025-03-02.
//

import SwiftUI

struct SubtleFailureView: View {
    // Animation started time
    @State private var animationStartTime: Date = Date()
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                // Calculate progress (0-1 over 0.8 second - shorter duration)
                let elapsed = timeline.date.timeIntervalSince(animationStartTime)
                let progress = min(1.0, elapsed / 0.8)
                
                // Center point
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                
                // Draw soft glow effect
                drawSoftGlow(in: &context, center: center, size: size, progress: progress)
                
                // Draw subtle shimmer particles
                drawShimmerParticles(in: &context, center: center, size: size, progress: progress)
                
                // Draw fading ripple
                drawRipple(in: &context, center: center, size: size, progress: progress)
            }
        }
    }
    
    // Soft glow that appears briefly then fades
    func drawSoftGlow(in context: inout GraphicsContext, center: CGPoint, size: CGSize, progress: Double) {
        // Quick fade in, longer fade out
        let glowOpacity = progress < 0.3 ? 
            progress / 0.3 * 0.3 : // Fade in
            max(0, 0.3 - (progress - 0.3) / 0.7 * 0.3) // Fade out
        
        let glowPath = Path(ellipseIn: CGRect(
            x: center.x - 60,
            y: center.y - 60,
            width: 120,
            height: 120
        ))
        
        // Use a muted color - amber/orange instead of bright red
        let glowColor = Color(hue: 0.08, saturation: 0.6, brightness: 0.9).opacity(glowOpacity)
        
        context.fill(
            glowPath,
            with: .color(glowColor)
        )
    }
    
    // Subtle particles that move outward
    func drawShimmerParticles(in context: inout GraphicsContext, center: CGPoint, size: CGSize, progress: Double) {
        // Only active during middle part of animation
        let particleProgress = max(0, min((progress - 0.1) / 0.6, 1.0))
        
        guard particleProgress > 0 && particleProgress < 1 else { return }
        
        // Use fewer particles for subtlety
        let particleCount = 15
        
        for i in 0..<particleCount {
            // Evenly distribute particles in a circle
            let angle = Double(i) / Double(particleCount) * 2 * .pi
            
            // Add slight randomness to angles
            let finalAngle = angle + Double.random(in: -0.2...0.2)
            
            // Particles move outward
            let distance = 20 + particleProgress * 60
            
            // Small particles
            let particleSize = 2.0 + Double.random(in: 0...1.5)
            
            // Position
            let position = CGPoint(
                x: center.x + cos(finalAngle) * distance,
                y: center.y + sin(finalAngle) * distance
            )
            
            // Create particle
            let particlePath = Path(ellipseIn: CGRect(
                x: position.x - particleSize/2,
                y: position.y - particleSize/2,
                width: particleSize,
                height: particleSize
            ))
            
            // Fade out as they travel
            let opacity = 0.4 * (1 - particleProgress)
            
            // Use muted gold/amber colors
            let hue = 0.08 + Double.random(in: -0.03...0.03)
            let saturation = 0.3 + Double.random(in: 0...0.3)
            let brightness = 0.7 + Double.random(in: 0...0.3)
            
            let particleColor = Color(hue: hue, saturation: saturation, brightness: brightness)
                .opacity(opacity)
            
            context.fill(
                particlePath,
                with: .color(particleColor)
            )
        }
    }
    
    // Expanding ripple effect
    func drawRipple(in context: inout GraphicsContext, center: CGPoint, size: CGSize, progress: Double) {
        // Three subtle ripple waves
        for i in 0...2 {
            // Stagger the start of each ripple
            let delay = Double(i) * 0.15
            let rippleProgress = max(0, min((progress - delay) / (1.0 - delay), 1.0))
            
            guard rippleProgress > 0 else { continue }
            
            // Expand from center
            let radius = rippleProgress * 80
            
            // Fade out as they expand
            let opacity = 0.3 * (1 - rippleProgress)
            
            let ripplePath = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            
            // Use very thin strokes for subtlety
            let strokeWidth = 1.5 - rippleProgress
            
            // Amber color but more muted than the glow
            let rippleColor = Color(hue: 0.09, saturation: 0.4, brightness: 0.9).opacity(opacity)
            
            context.stroke(
                ripplePath,
                with: .color(rippleColor),
                lineWidth: strokeWidth
            )
        }
    }
}

struct SubtleFailureView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color(white: 0.2) // Dark gray background for visibility
            SubtleFailureView()
                .frame(width: 200, height: 200)
        }
    }
}