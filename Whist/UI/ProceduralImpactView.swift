//
//  ProceduralImpactView.swift
//  Whist
//
//  Created by Tony Buffard on 2025-03-02.
//

import SwiftUI

struct ProceduralImpactView: View {
    // Animation parameters
    @State private var animationStartTime: Date = Date()
    
    // Shockwave parameters
    let shockwaveCount = 3
    let rayCount = 24
    let sparkCount = 60
    let debrisCount = 18
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                // Calculate progress (0-1 over 1 second)
                let elapsed = timeline.date.timeIntervalSince(animationStartTime)
                let progress = min(1.0, elapsed / 1.0)
                
                // Center point
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                
                // Draw flash/flare
                drawFlash(in: &context, center: center, size: size, progress: progress)
                
                // Draw shockwaves
                drawShockwaves(in: &context, center: center, size: size, progress: progress)
                
                // Draw radial rays
                drawRays(in: &context, center: center, size: size, progress: progress)
                
                // Draw sparks
                drawSparks(in: &context, center: center, size: size, progress: progress)
                
                // Draw debris
                drawDebris(in: &context, center: center, size: size, progress: progress)
            }
        }
    }
    
    // Initial flash of impact
    func drawFlash(in context: inout GraphicsContext, center: CGPoint, size: CGSize, progress: Double) {
        // Flash appears instantly and fades quickly
        let flashProgress = max(0, 1 - progress * 3)
        
        guard flashProgress > 0 else { return }
        
        // Outer glow
        let outerGlowPath = Path(ellipseIn: CGRect(
            x: center.x - 100,
            y: center.y - 100,
            width: 200,
            height: 200
        ))
        
        context.fill(
            outerGlowPath,
            with: .color(Color.white.opacity(flashProgress * 0.8))
        )
        
        // Inner bright flash
        let innerFlashPath = Path(ellipseIn: CGRect(
            x: center.x - 50,
            y: center.y - 50,
            width: 100,
            height: 100
        ))
        
        // Use a gradient for the inner flash for added depth - applying opacity directly to colors
        
        // Apply the gradient with proper opacity
        let resolvedInnerShading = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [
                Color.white.opacity(flashProgress),
                Color.yellow.opacity(flashProgress * 0.9),
                Color.orange.opacity(flashProgress * 0.7)
            ]),
            center: center,
            startRadius: 0,
            endRadius: 50
        )
        
        context.fill(
            innerFlashPath,
            with: resolvedInnerShading
        )
    }
    
    // Expanding shockwaves
    func drawShockwaves(in context: inout GraphicsContext, center: CGPoint, size: CGSize, progress: Double) {
        for i in 0..<shockwaveCount {
            // Stagger the start of each shockwave
            let delay = Double(i) * 0.1
            let waveProgress = max(0, min(1, (progress - delay) / 0.9))
            
            guard waveProgress > 0 else { continue }
            
            // Wave grows from center
            let radius = waveProgress * 150
            
            // Fade out as it expands
            let opacity = 0.7 * (1 - waveProgress)
            
            let wavePath = Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            
            // Vary the colors slightly between waves
            let waveColor = i % 2 == 0 ?
                Color.white.opacity(opacity) :
                Color(hue: 0.1, saturation: 0.5, brightness: 1).opacity(opacity)
            
            // Use thinner strokes as they expand
            let strokeWidth = (1 - waveProgress) * 4 + 1
            
            context.stroke(
                wavePath,
                with: .color(waveColor),
                lineWidth: strokeWidth
            )
        }
    }
    
    // Radial rays extending outward
    func drawRays(in context: inout GraphicsContext, center: CGPoint, size: CGSize, progress: Double) {
        // Rays start slightly after initial flash
        let rayProgress = max(0, min(1, (progress - 0.05) / 0.6))
        
        guard rayProgress > 0 else { return }
        
        for i in 0..<rayCount {
            let angle = (Double(i) / Double(rayCount)) * 2 * .pi
            
            // Randomize ray length and thickness
            let rayLength = 50 + Double.random(in: 0...100) * rayProgress
            let rayWidth = 1 + Double.random(in: 1...4)
            
            // Start point is slightly away from center
            let startDistance = 20.0
            let startPoint = CGPoint(
                x: center.x + cos(angle) * startDistance,
                y: center.y + sin(angle) * startDistance
            )
            
            // End point extends outward
            let endPoint = CGPoint(
                x: center.x + cos(angle) * (startDistance + rayLength),
                y: center.y + sin(angle) * (startDistance + rayLength)
            )
            
            var rayPath = Path()
            rayPath.move(to: startPoint)
            rayPath.addLine(to: endPoint)
            
            // Fade out as animation progresses
            let opacity = 0.8 * (1 - rayProgress)
            
            // Vary colors for visual interest
            let hue = Double(i) / Double(rayCount) * 0.1 + 0.05 // Yellow-orange range
            let rayColor = Color(hue: hue, saturation: 0.8, brightness: 1).opacity(opacity)
            
            context.stroke(
                rayPath,
                with: .color(rayColor),
                lineWidth: rayWidth
            )
        }
    }
    
    // Small bright sparks flying outward
    func drawSparks(in context: inout GraphicsContext, center: CGPoint, size: CGSize, progress: Double) {
        // Sparks appear with the initial impact
        let sparkProgress = max(0, min(1, progress / 0.8))
        
        guard sparkProgress > 0 else { return }
        
        for _ in 0..<sparkCount {
            // Random angle and speed
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = 1.0 + Double.random(in: 0...2.0)
            
            // Distance increases with time
            let distance = sparkProgress * 180 * speed
            
            // Sparks get smaller as they travel
            let sparkSize = 3.0 * (1 - sparkProgress * 0.7)
            
            // Position based on angle and distance
            let position = CGPoint(
                x: center.x + cos(angle) * distance,
                y: center.y + sin(angle) * distance
            )
            
            // Only show sparks that haven't traveled too far
            if distance < 200 {
                let sparkPath = Path(ellipseIn: CGRect(
                    x: position.x - sparkSize/2,
                    y: position.y - sparkSize/2,
                    width: sparkSize,
                    height: sparkSize
                ))
                
                // Fade out as they travel
                let opacity = 0.9 * (1 - sparkProgress * speed * 0.5)
                
                // Color based on spark "temperature"
                let temperature = Double.random(in: 0...1)
                let sparkColor = temperature < 0.3 ?
                    Color.white.opacity(opacity) :
                    Color(hue: 0.05 + temperature * 0.05, saturation: 0.9, brightness: 1).opacity(opacity)
                
                context.fill(
                    sparkPath,
                    with: .color(sparkColor)
                )
                
                // Add trails to faster sparks
                if speed > 1.5 && sparkProgress < 0.6 {
                    let trailStart = CGPoint(
                        x: center.x + cos(angle) * (distance * 0.8),
                        y: center.y + sin(angle) * (distance * 0.8)
                    )
                    
                    var trailPath = Path()
                    trailPath.move(to: trailStart)
                    trailPath.addLine(to: position)
                    
                    context.stroke(
                        trailPath,
                        with: .color(sparkColor.opacity(opacity * 0.6)),
                        lineWidth: sparkSize * 0.6
                    )
                }
            }
        }
    }
    
    // Larger debris pieces
    func drawDebris(in context: inout GraphicsContext, center: CGPoint, size: CGSize, progress: Double) {
        // Debris starts flying outward slightly after initial impact
        let debrisProgress = max(0, min(1, (progress - 0.1) / 0.7))
        
        guard debrisProgress > 0 else { return }
        
        for i in 0..<debrisCount {
            // Random angle with some clustering
            let baseAngle = Double(i) / Double(debrisCount) * 2 * .pi
            let angle = baseAngle + Double.random(in: -0.3...0.3)
            
            // Each piece has different speed
            let speed = 0.7 + Double.random(in: 0...1.0)
            
            // Distance increases with time
            let distance = debrisProgress * 140 * speed
            
            // Debris pieces are larger than sparks
            let debrisSize = 5.0 + Double.random(in: 0...8.0)
            
            // Position based on angle and distance
            let position = CGPoint(
                x: center.x + cos(angle) * distance,
                y: center.y + sin(angle) * distance
            )
            
            // Rotation increases with distance
            let rotation = debrisProgress * 2 * .pi * Double.random(in: 1...3)
            
            // Create irregular shapes for debris
            let debrisPath = createDebrisShape(at: position, size: debrisSize, rotation: rotation)
            
            // Fade out gradually
            let opacity = 0.9 * (1 - debrisProgress * 0.8)
            
            // Darker colors for debris
            let debrisColor = Color(
                hue: 0.1,
                saturation: Double.random(in: 0.1...0.3),
                brightness: Double.random(in: 0.6...0.9)
            ).opacity(opacity)
            
            context.fill(
                debrisPath,
                with: .color(debrisColor)
            )
            
            // Add outline to debris
            context.stroke(
                debrisPath,
                with: .color(Color.white.opacity(opacity * 0.5)),
                lineWidth: 1
            )
        }
    }
    
    // Create random debris shapes
    func createDebrisShape(at position: CGPoint, size: Double, rotation: Double) -> Path {
        let points = 5 + Int.random(in: 0...3)
        let innerRadius = size * 0.5
        let outerRadius = size
        
        var path = Path()
        
        for i in 0..<points {
            let angle = (Double(i) / Double(points)) * 2 * .pi + rotation
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            
            let point = CGPoint(
                x: position.x + cos(angle) * radius,
                y: position.y + sin(angle) * radius
            )
            
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        
        path.closeSubpath()
        return path
    }
}

struct ProceduralImpactView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black
            ProceduralImpactView()
                .frame(width: 300, height: 300)
        }
        .previewLayout(.fixed(width: 400, height: 400))
    }
}
