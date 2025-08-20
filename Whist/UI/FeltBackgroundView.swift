//
//  FeltBackgroundView.swift
//  Whist
//
//  Created by Tony Buffard on 2024-12-04.
//

import SwiftUI
import simd

// MARK: - Advanced Felt View

//struct AdvancedFeltView: View {
struct FeltBackgroundView: View {
    /// The main base color for the felt.
    var baseColorIndex: Int
    
    /// How strong the radial shading is (0 = none, 1 = quite dark edges).
    var radialShadingStrength: Double
    
    /// How heavy the “wear & tear” looks (scratches, spots, etc.).
    var wearIntensity: Double
    
    /// How visible the random motif pattern is (0 = off, 1 = full).
    var motif: String
    var motifVisibility: Double
    var motifScale: CGFloat
    
    /// Whether to show the random scratch overlay.
    var showScratches: Bool
    
    init(
        baseColorIndex: Int = 0,
        radialShadingStrength: Double = 0.5,
        wearIntensity: Double = 0,
        motif: String = [
            "star.fill", "heart.fill", "moon.fill", "leaf.fill", "snowflake",
            "suit.spade.fill", "suit.heart.fill", "suit.diamond.fill", "suit.club.fill",
            "sparkles", "bolt.fill",
            "gearshape.fill", "globe", "camera.metering.spot"
        ].randomElement() ?? "circle.fill",
        motifVisibility: Double = 0.25, //[0.25, 0.5, 0.75, 1].randomElement() ?? 0.25,
        motifScale: CGFloat = 0.5, //CGFloat.random(in: 0...1),
        showScratches: Bool = Bool.random()
    ) {
        // Set all parameters using provided values or defaults
        self.baseColorIndex = baseColorIndex
        self.radialShadingStrength = radialShadingStrength
        self.wearIntensity = wearIntensity
        self.motif = motif
        self.motifVisibility = motifVisibility
        self.motifScale = motifScale
        self.showScratches = showScratches
        logger.log("motifVisibility: \(motifVisibility)")
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 1. Base texture image – color filled then masked by alpha-only noise texture
                GameConstants.feltColors[baseColorIndex]
                    .overlay(
                        Image("noiseTexture-4-alpha")
                            .resizable(resizingMode: .tile)
                            .blendMode(.multiply)
                    )
                
                // 3. Wear & Tear Overlays
                if wearIntensity > 0 {
                    HandWearOverlay(wearIntensity: wearIntensity)
                        .blendMode(.multiply)
                        .allowsHitTesting(false)
                    
                    DynamicWearOverlay(wearIntensity: wearIntensity, timeOffset: 0)
                        .blendMode(.softLight)
                    
                    StainsOverlay(
                        beerStainProbability: wearIntensity,
                        beerStainCount: Int(ceil(5 * wearIntensity)),
                        wearSpotProbability: wearIntensity,
                        wearSpotCount: Int(ceil(10 * wearIntensity)),
                        intensity: wearIntensity
                    )
                    .blendMode(.overlay) // overlay
                    
                    if showScratches {
                        ScratchesOverlay(intensity: wearIntensity)
                            .blendMode(.softLight)
                            .allowsHitTesting(false)
                    }
                }
                
                // 4. Tile-pattern motif overlay: render minimal tile and repeat
                if motifVisibility > 0 {
                    let motifSize = 30 * motifScale
                    let spacing = motifSize * 0.1
                    let tileW = motifSize + spacing
                    let tileH = motifSize + spacing
                    // Generate a two-column offset tile image
                    if let tileCGImage = {
                        let renderer = ImageRenderer(content:
                                                        Canvas { context, _ in
                            let motifImage = Image(systemName: motif)
                            // Draw in first column (no offset)
                            let rect1a = CGRect(
                                x: 0,
                                y: 0,
                                width: motifSize,
                                height: motifSize
                            )
                            context.draw(motifImage, in: rect1a)
                            let rect1b = CGRect(
                                x: 0,
                                y: tileH,
                                width: motifSize,
                                height: motifSize
                            )
                            context.draw(motifImage, in: rect1b)
                            
                            // Draw in second column, offset half motif vertically
                            let rect2a = CGRect(
                                x: tileW,
                                y: -(tileH / 2),
                                width: motifSize,
                                height: motifSize
                            )
                            context.draw(motifImage, in: rect2a)
                            let rect2b = CGRect(
                                x: tileW,
                                y: tileH / 2,
                                width: motifSize,
                                height: motifSize
                            )
                            context.draw(motifImage, in: rect2b)
                            let rect2c = CGRect(
                                x: tileW,
                                y: tileH * 1.5,
                                width: motifSize,
                                height: motifSize
                            )
                            context.draw(motifImage, in: rect2c)
                        }
                            .frame(width: tileW * 2, height: tileH * 2)
                        )
                        return renderer.cgImage
                    }() {
                        Image(decorative: tileCGImage, scale: 1)
                            .resizable(resizingMode: .tile)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .opacity(motifVisibility)
                            .blendMode(.softLight)
                    }
                }
                
                // 5. Radial shading for depth
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.clear,
                        Color.black.opacity(radialShadingStrength * 0.6)
                    ]),
                    center: .center,
                    startRadius: 50,
                    endRadius: min(geometry.size.width, geometry.size.height) / 1.5
                )
                .blendMode(.multiply)
                
                RadialGradient(
                    gradient: Gradient(colors: [
                        .clear,
                        .black.opacity(radialShadingStrength * 0.3)
                    ]),
                    center: .init(x: 0.55, y: 0.5),
                    startRadius: 30,
                    endRadius: min(geometry.size.width, geometry.size.height) / 1.6
                )
                .blendMode(.multiply)
            }
            .edgesIgnoringSafeArea(.all)
        }
    }
}


// MARK: - Noise Speckles Overlay

/// Adds small elliptical speckles of black/white noise, giving a fuzzy/fibrous impression.
struct NoiseSpecklesOverlay: View {
    var densityFactor: Double = 40 // bigger = fewer speckles
    
    var body: some View {
        Canvas { context, size in
            let particleCount = Int(size.width * size.height / densityFactor)
            for _ in 0..<particleCount {
                // Random positions
                let x = Double.random(in: 0...size.width)
                let y = Double.random(in: 0...size.height)
                
                // Slight variation in speck size
                let w = Double.random(in: 0.5...3.0)
                let h = Double.random(in: 0.5...3.0)
                
                // Subtle speck opacity
                let opacity = Double.random(in: 0.05...0.15)
                
                // Mix of white or black noise
                let isWhiteNoise = Bool.random()
                let color = isWhiteNoise
                ? Color.white.opacity(opacity)
                : Color.black.opacity(opacity)
                
                // Draw a small ellipse
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)),
                    with: .color(color)
                )
            }
        }
    }
}

// MARK: - Wear & Tear Overlays

struct ScratchesOverlay: View {
    var intensity: Double
    
    var body: some View {
        Canvas { context, size in
            // Number of scratch clusters depends on intensity
            //            let scratchCount = Int(size.width * size.height * intensity / 15000)
            let scratchCount = Int(ceil(intensity * 5))
            for _ in 0..<scratchCount {
                let startX = Double.random(in: 0...size.width)
                let startY = Double.random(in: 0...size.height)
                let angle = Double.random(in: 0..<360).degreesToRadians
                let clusterWidth = max(2, min(100, randomGaussian(mean: 20, deviation: 15) * (0.5 + intensity / 2)))
                
                // Generate parallel scratches in a cluster
                for offset in stride(from: -clusterWidth / 2, through: clusterWidth / 2, by: Double.random(in: 1...3)) {
                    let length = max(10, min(1000, randomGaussian(mean: 50, deviation: 50) * (0.5 + intensity / 2)))
                    let thickness = Double.random(in: 0.5...2.0)
                    let lineOpacity = max(0.01, min(0.9, randomGaussian(mean: 0.2, deviation: 0.2) * (0.5 + intensity / 2)))
                    
                    let startOffsetX = startX + CGFloat(cos(angle + .pi / 2)) * offset
                    let startOffsetY = startY + CGFloat(sin(angle + .pi / 2)) * offset
                    let endOffsetX = startOffsetX + CGFloat(cos(angle)) * length
                    let endOffsetY = startOffsetY + CGFloat(sin(angle)) * length
                    
                    var scratchPath = Path()
                    scratchPath.move(to: CGPoint(x: startOffsetX, y: startOffsetY))
                    scratchPath.addLine(to: CGPoint(x: endOffsetX, y: endOffsetY))
                    
                    context.stroke(
                        scratchPath,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: Color.white.opacity(0.5 * lineOpacity), location: 0.0),
                                .init(color: Color.white.opacity(0.8 * lineOpacity), location: 0.5),
                                .init(color: Color.white.opacity(0.5 * lineOpacity), location: 1.0)
                            ]),
                            startPoint: CGPoint(x: startOffsetX, y: startOffsetY),
                            endPoint: CGPoint(x: endOffsetX, y: endOffsetY)
                        ),
                        lineWidth: thickness
                    )
                }
            }
        }
    }
}

struct SpotsOverlay: View {
    var intensity: Double
    var isLight: Bool
    
    var body: some View {
        Canvas { context, size in
            // For “dark” spots, we may want fewer/larger patches, for “light” maybe more/fewer, etc.
            let spotDivider: Double = isLight ? 35000 : 120000
            let spotCount = Int(size.width * size.height * intensity / spotDivider) * 10
            
            for _ in 0..<spotCount {
                let x = Double.random(in: 0...size.width)
                let y = Double.random(in: 0...size.height)
                let maxSize = max(10, min(200, randomGaussian(mean: 30, deviation: 50) * (0.5 + intensity / 2)))
                let opacity = max(0.05, min(0.15, randomGaussian(mean: 0.1, deviation: 0.02) * (0.5 + intensity / 2)))
                drawSpot(context: &context, size: size, centerX: x, centerY: y, maxSize: maxSize, opacity: opacity, depth: 0)
            }
        }
    }
    
    private let maxRecursionDepth = 1
    
    private func drawSpot(context: inout GraphicsContext,
                          size: CGSize,
                          centerX: Double,
                          centerY: Double,
                          maxSize: Double,
                          opacity: Double,
                          depth: Int)
    {
        // Generate shape
        let path = generateOrganicShape(centerX: centerX, centerY: centerY, maxSize: maxSize)
        let adjustedOpacity = max(0.01, min(1.0, opacity * pow(0.8, Double(depth))))
        
        context.drawLayer { layerContext in
            layerContext.fill(
                path,
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: baseColor(isLight: isLight)
                            .opacity(opacity * 1.0), location: 0.0),
                        .init(color: baseColor(isLight: isLight)
                            .opacity(opacity * 0.4), location: 0.8),
                        .init(color: Color.clear, location: 1.0)
                    ]),
                    center: CGPoint(x: centerX, y: centerY),
                    startRadius: 0,
                    endRadius: maxSize / 2
                )
            )
        }
        
        // Possibly add “child” spots
        if depth < maxRecursionDepth && Bool.random(probability: 0.1) {
            let childX = centerX + Double.random(in: -maxSize / 2...maxSize / 2)
            let childY = centerY + Double.random(in: -maxSize / 2...maxSize / 2)
            let childMaxSize = maxSize * Double.random(in: 0.4...0.8)
            
            drawSpot(
                context: &context,
                size: size,
                centerX: childX,
                centerY: childY,
                maxSize: childMaxSize,
                opacity: adjustedOpacity,
                depth: depth + 1
            )
        }
    }
    
    private func generateOrganicShape(centerX: Double, centerY: Double, maxSize: Double) -> Path {
        var path = Path()
        let points = Int.random(in: 6...10)
        let radius = maxSize / 2
        
        for i in 0..<points {
            let angle = Double(i) * (360.0 / Double(points)).degreesToRadians
            let distanceVariation = radius * Double.random(in: -0.1...0.1)
            let distance = radius + distanceVariation
            
            let x = centerX + Double(cos(angle)) * distance
            let y = centerY + Double(sin(angle)) * distance
            
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        path.closeSubpath()
        return path
    }
    
    private func baseColor(isLight: Bool) -> Color {
        if isLight {
            // Off-white for the highlights
            return Color(white: 0.9)
        } else {
            // Off-black for the darker patches
            return Color(white: 0.1)
        }
    }
}

// MARK: - Motif Pattern

struct MotifPatternOverlay: View {
    var motif: String
    var scale: CGFloat
    
    var body: some View {
        Canvas { context, size in
            let textureSize: CGFloat = 2048
            let motifSize: CGFloat = 30 * scale
            let spacing: CGFloat = motifSize * 0.1
            let xCount = Int(textureSize / (motifSize + spacing)) + 1
            let yCount = Int(textureSize / (motifSize + spacing)) + 1
            let motifImage = Image(systemName: motif)
            
            for xIndex in 0..<xCount {
                for yIndex in 0..<yCount {
                    let x = CGFloat(xIndex) * (motifSize + spacing) + motifSize / 2
                    let y = CGFloat(yIndex) * (motifSize + spacing)
                    + (xIndex % 2 == 0 ? 0 : motifSize / 2)
                    
                    let rect = CGRect(
                        x: x - motifSize / 2,
                        y: y - motifSize / 2,
                        width: motifSize,
                        height: motifSize
                    )
                    context.draw(motifImage, in: rect)
                }
            }
        }
        .frame(width: 2048, height: 2048)
        .drawingGroup()
    }
}

// MARK: - Perlin Noise Implementation

fileprivate func perlinNoise(_ x: Double, _ y: Double) -> Double {
    // A very simple Perlin-like function using "random gradient" approach.
    // For production apps, consider a well-tested Perlin library or more advanced noise.
    // This example is purely for demonstration.
    
    // Floor to get the integer grid corners
    let xi = Int(floor(x)) & 255
    let yi = Int(floor(y)) & 255
    
    // Relative x, y within the cell
    let xf = x - floor(x)
    let yf = y - floor(y)
    
    // Fetch random gradients at the four corners
    let topRight     = grad(hash: perm[xi + 1 + perm[yi + 1]], x: xf - 1, y: yf - 1)
    let topLeft      = grad(hash: perm[xi + 0 + perm[yi + 1]], x: xf - 0, y: yf - 1)
    let bottomRight  = grad(hash: perm[xi + 1 + perm[yi + 0]], x: xf - 1, y: yf - 0)
    let bottomLeft   = grad(hash: perm[xi + 0 + perm[yi + 0]], x: xf - 0, y: yf - 0)
    
    // Smooth interpolation
    let u = fade(xf)
    let v = fade(yf)
    
    // Interpolate along x, then y
    let lerpBottom = lerp(bottomLeft, bottomRight, u)
    let lerpTop    = lerp(topLeft, topRight, u)
    let value      = lerp(lerpBottom, lerpTop, v)
    
    // value in [-1, 1]
    return value
}

// MARK: - Utilities for Perlin

/// A classic Perlin “fade” function that smooths t in [0,1].
fileprivate func fade(_ t: Double) -> Double {
    return t * t * t * (t * (t * 6 - 15) + 10)
}

/// Linear interpolation
fileprivate func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    return a + t * (b - a)
}

/// Dot product with a pseudo-random gradient
fileprivate func grad(hash: Int, x: Double, y: Double) -> Double {
    // 8 possible gradient directions in 2D
    switch hash & 7 {
    case 0: return  x + y
    case 1: return  x - y
    case 2: return -x + y
    case 3: return -x - y
    case 4: return  x
    case 5: return -x
    case 6: return  y
    default: return -y
    }
}

/// Precomputed permutation array for pseudo-random gradients
fileprivate let perm: [Int] = {
    let p: [Int] = Array(0...255)
    // For demonstration, a fixed shuffle. Could randomize for seeds.
    return (p + p)
}()

// MARK: - Extensions & Helpers

extension Double {
    var degreesToRadians: CGFloat { CGFloat(self * .pi / 180) }
}

/// A naive Gaussian random generator using the Box-Muller transform
func randomGaussian(mean: Double, deviation: Double) -> Double {
    let u1 = Double.random(in: 0...1)
    let u2 = Double.random(in: 0...1)
    let z = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
    return mean + z * deviation
}

/// Probability-based Bool.random
//extension Bool {
//    /// e.g. `Bool.random(probability: 0.3)` => ~30% chance of `true`.
//    static func random(probability: Double) -> Bool {
//        return Double.random(in: 0...1) < probability
//    }
//}

// MARK: - Color Tweaks

extension Color {
    /// Shift the hue by a certain fraction (e.g., 0.1 => shift hue by ~36 degrees)
    func shiftHue(by fraction: Double) -> Color {
        var (h, s, b, a) = hsba
        h += fraction
        // wrap around
        if h < 0 { h += 1 }
        if h > 1 { h -= 1 }
        return Color(hue: h, saturation: s, brightness: b, opacity: a)
    }
    
    /// Adjust brightness by adding a fraction in [-1, +1].
    func brightness(_ delta: Double) -> Color {
        var (h, s, b, a) = hsba
        b += delta
        b = b.clamped(to: 0...1)
        return Color(hue: h, saturation: s, brightness: b, opacity: a)
    }
    
    /// Decompose Color into (hue, saturation, brightness, alpha).
    private var hsba: (Double, Double, Double, Double) {
        // SwiftUI doesn’t give a direct HSBA accessor, so let’s do a small workaround:
#if canImport(UIKit)
        // On iOS, we can use UIColor
        let uiColor = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s), Double(b), Double(a))
#elseif canImport(AppKit)
        // On macOS, we can do something similar with NSColor
        let nsColor = NSColor(self)
        let converted = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        converted.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return (Double(h), Double(s), Double(b), Double(a))
#else
        // Fallback
        return (0, 0, 0, 1)
#endif
    }
}

// MARK: StainsOverlay

struct StainsOverlay: View {
    /// Probability (0–1) of a beer stain appearing at all
    var beerStainProbability: Double = 0.4
    
    /// Max number of beer stains. Set to 0 if you don’t want them.
    var beerStainCount: Int = 2
    
    /// Probability (0–1) of a repeated-use wear spot (light or dark patch)
    var wearSpotProbability: Double = 0.6
    
    /// Max number of wear spots
    var wearSpotCount: Int = 3
    
    /// Strength of the effect (0 => almost invisible, 1 => normal)
    var intensity: Double = 1.0
    
    var body: some View {
        Canvas { context, size in
            // 1) Draw beer / liquid stains
            if Double.random(in: 0...1) < beerStainProbability {
                let count = Int.random(in: 1...beerStainCount)
                for _ in 0..<count {
                    drawBeerStain(context: &context, size: size)
                }
            }
            
            // 2) Draw repeated-wear spots
            //            if Double.random(in: 0...1) < wearSpotProbability {
            //                let count = Int.random(in: 1...wearSpotCount)
            //                for _ in 0..<count {
            //                    drawWearSpot(context: &context, size: size)
            //                }
            //            }
        }
        .drawingGroup()
    }
    
    // MARK: - 1) Beer / Liquid Stains
    
    private func drawBeerStain(context: inout GraphicsContext, size: CGSize) {
        // Randomly choose one of the regions for the stain center
        let region = Int.random(in: 0...2) // 0 = left, 1 = right, 2 = bottom
        let centerX: Double
        let centerY: Double
        
        switch region {
        case 0: // 30% on the left
            centerX = Double.random(in: 0...(size.width * 0.3))
            centerY = Double.random(in: 0...size.height)
        case 1: // 30% on the right
            centerX = Double.random(in: size.width * 0.7...size.width)
            centerY = Double.random(in: 0...size.height)
        case 2: // 30% on the bottom
            centerX = Double.random(in: 0...size.width)
            centerY = Double.random(in: size.height * 0.7...size.height)
        default:
            logger.fatalErrorAndLog("Unexpected region value")
        }
        
        let ringRadius = Double.random(in: 10...25)
        let ringThickness = ringRadius * Double.random(in: 0.05...0.10) // 5–15% of radius
        let ringOpacity = 0.3 * intensity
        let drinkColors = [
            Color(red: 54 / 255, green: 39 / 255, blue: 24 / 255), // Espresso Brown
            Color(red: 101 / 255, green: 67 / 255, blue: 33 / 255), // Mocha Brown
            Color(red: 78 / 255, green: 52 / 255, blue: 46 / 255), // Dark Roast
            Color(red: 191 / 255, green: 128 / 255, blue: 64 / 255), // Cola Caramel
            Color(red: 220 / 255, green: 170 / 255, blue: 85 / 255), // Honey Amber
            Color(red: 128 / 255, green: 0 / 255, blue: 64 / 255), // Merlot
            Color(red: 94 / 255, green: 38 / 255, blue: 51 / 255), // Bordeaux
            Color(red: 139 / 255, green: 0 / 255, blue: 38 / 255), // Classic Burgundy
            Color(red: 210 / 255, green: 150 / 255, blue: 75 / 255) , // Amber Lager
            Color(red: 140 / 255, green: 105 / 255, blue: 60 / 255) , // Dark Malt
            Color(red: 0.5, green: 0.35, blue: 0.0), // Brownish beer color
            Color(red: 205 / 255, green: 133 / 255, blue: 63 / 255), // Chai Brown
            Color(red: 168 / 255, green: 114 / 255, blue: 45 / 255), // Spiced Amber
            Color(red: 255 / 255, green: 102 / 255, blue: 0 / 255) , // Orange Juice
            Color(red: 255 / 255, green: 182 / 255, blue: 193 / 255), // Pink Grapefruit
            Color(red: 255 / 255, green: 69 / 255, blue: 0 / 255)  , // Blood Orange
            Color(red: 160 / 255, green: 82 / 255, blue: 45 / 255), // Aged Oak
            Color(red: 205 / 255, green: 127 / 255, blue: 50 / 255), // Honey Whiskey
            Color(red: 184 / 255, green: 115 / 255, blue: 51 / 255) // Golden Bourbon
        ]
        
        let ringColor = drinkColors.randomElement() ?? Color.black
        
        // Some random lumps / irregularities
        let lumpsCount = Int.random(in: 3...6)
        
        context.drawLayer { layerContext in
            // Draw the ring
            var ringPath = Path()
            ringPath.addArc(
                center: CGPoint(x: centerX, y: centerY),
                radius: ringRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(360),
                clockwise: false
            )
            
            // stroke the ring with a thick line
            layerContext.stroke(
                ringPath,
                with: .color(ringColor.opacity(ringOpacity)),
                style: StrokeStyle(lineWidth: ringThickness, lineCap: .round, lineJoin: .round)
            )
            
            // Optionally add lumps or small arcs around the ring
            for _ in 0..<lumpsCount {
                let lumpAngle = Double.random(in: 0..<360).degreesToRadians
                let lumpArcAngle = Double.random(in: 10..<40) // degrees
                var lumpPath = Path()
                
                lumpPath.addArc(
                    center: CGPoint(x: centerX, y: centerY),
                    radius: ringRadius + Double.random(in: -5...5),
                    startAngle: .radians(lumpAngle),
                    endAngle: .radians(lumpAngle + lumpArcAngle.toRadians),
                    clockwise: Bool.random()
                )
                
                // stroke lumps with a slightly darker or lighter color
                let lumpOpacity = Double.random(in: 0.1...0.2) * intensity
                layerContext.stroke(
                    lumpPath,
                    with: .color(ringColor.opacity(lumpOpacity)),
                    style: StrokeStyle(lineWidth: Double.random(in: 3...8), lineCap: .round)
                )
            }
            
            // Fill the center with a subtle radial gradient to simulate a faint puddle
            let fillOpacity = 0.05 * intensity
            let fillColor = ringColor.opacity(fillOpacity)
            let fillGradient = Gradient(stops: [
                .init(color: fillColor, location: 0.0),
                .init(color: Color.clear, location: 1.0)
            ])
            layerContext.fill(
                Path(ellipseIn: CGRect(
                    x: centerX - ringRadius,
                    y: centerY - ringRadius,
                    width: ringRadius * 2,
                    height: ringRadius * 2
                )),
                with: .radialGradient(
                    fillGradient,
                    center: CGPoint(x: centerX, y: centerY),
                    startRadius: 0,
                    endRadius: ringRadius
                )
            )
        }
    }
    
    // MARK: - 2) Repeated-Use Wear Spots
    
    private func drawWearSpot(context: inout GraphicsContext, size: CGSize) {
        let centerX = Double.random(in: 0...size.width)
        let centerY = Double.random(in: 0...size.height)
        
        // radius for the entire worn area
        let maxRadius = Double.random(in: 40...150)
        let rotationAngle = Double.random(in: 0..<360).degreesToRadians
        
        // A shape that’s possibly elliptical
        // We'll treat an ellipse or a random polygon, then fill with a gradient that lightens/darkens
        context.drawLayer { layerContext in
            // Step 1. Make the path
            let path = generateEllipticalOrBlobbyPath(
                centerX: centerX,
                centerY: centerY,
                radius: maxRadius,
                angle: rotationAngle
            )
            
            // Step 2. The color shift
            //    Some wear is lighter, some is darker, so pick one randomly
            let lighten = Bool.random()
            // Worn color offset
            let colorStrength = Double.random(in: 0.1...0.4) * intensity
            // For a "beer ring," I'd have gone with browns. But for wear, we can do
            // a subtle black or white overlay. Let's do gray overlay to lighten/darken
            let overlayColor = lighten ? Color.white : Color.black
            
            // Step 3. Fill with radial gradient
            let wornGradient = Gradient(stops: [
                .init(color: overlayColor.opacity(colorStrength * 0.7), location: 0.0),
                .init(color: overlayColor.opacity(colorStrength * 0.2), location: 0.5),
                .init(color: Color.clear, location: 1.0),
            ])
            
            layerContext.fill(
                path,
                with: .radialGradient(
                    wornGradient,
                    center: CGPoint(x: centerX, y: centerY),
                    startRadius: 0,
                    endRadius: maxRadius
                )
            )
        }
    }
    
    /// Generate a slightly elliptical or “blobby” shape
    private func generateEllipticalOrBlobbyPath(centerX: Double, centerY: Double, radius: Double, angle: Double) -> Path {
        var path = Path()
        
        // random # of lumps for a more organic shape
        let lumps = Int.random(in: 3...6)
        
        for i in 0..<lumps {
            let fraction = Double(i) / Double(lumps)
            let theta = fraction * 2 * Double.pi
            
            // vary the radius a bit
            let localRadius = radius + Double.random(in: -0.2...0.2) * radius
            
            // rotate shape by angle
            let rotated = theta + angle
            
            let x = centerX + cos(rotated) * localRadius
            let y = centerY + sin(rotated) * (localRadius * Double.random(in: 0.7...1.0)) // elliptical
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        
        path.closeSubpath()
        return path
    }
}

// MARK: TilingPerlinView

struct TilingPerlinView: View {
    var colorIndex: Int
    var noiseWidth: Int
    var noiseHeight: Int
    var period: Int
    var randSeed: Int
    var tileSize: Int
    var method: Int
    var level: CGFloat
    var scale: CGFloat
    
    @State private var renderedImage: Image? // Holds the rendered image
    
    var body: some View {
        guard let nsImage = NSImage(named: NSImage.Name("feltBackground_\(colorIndex)_\(feltBackgroundName(for: colorIndex))")) else {
            fatalError("Couldn’t load NSImage from assets")
        }
        
        // Ask the NSImage to give you a CGImage backing it:
        var imgRect = CGRect(origin: .zero, size: nsImage.size)
        guard let cgImage = nsImage.cgImage(
            forProposedRect: &imgRect,
            context: .current,
            hints: nil
        ) else {
            fatalError("Couldn’t convert NSImage to CGImage")
        }
        
        return AnyView(
            Image(decorative: cgImage, scale: scale, orientation: .up)
                .resizable(resizingMode: .tile)
        )
    }
}

// MARK: - PerlinNoiseOverlay
struct PerlinNoiseOverlay: View {
    /// Width and height used for sampling. You can tweak these
    /// or match them to the displayed size for 1:1 pixel coverage.
    var noiseWidth: Int = 256
    var noiseHeight: Int = 256
    
    /// “Period” controls the frequency of the noise (bigger => smaller features).
    var period: Int = 64
    
    /// The random seed for reproducible noise.
    var randSeed: Int = 1
    
    /// Whether to draw each noise pixel at 1×1 point, or use a bigger tile.
    /// For large screens, using tileSize > 1 is faster (fewer fills).
    var tileSize: Int = 1
    
    /// Base color for the felt fabric
    var baseColor: Color = Color(red: 34/255, green: 139/255, blue: 34/255)
    
    var method: Int
    var level: CGFloat
    
    var body: some View {
        Canvas { context, size in
            // 1) Create sampler sized to "ceil(width/period), ceil(height/period)"
            
            let samplerWidth = Int(noiseWidth / period)
            let samplerHeight = Int(noiseHeight / period)
            
            let sampler = PerlinSampler2D(
                width: max(1, samplerWidth),
                height: max(1, samplerHeight),
                period: period,
                randSeed: randSeed
            )
            
            // 2) Draw the noise
            //    We’ll iterate over the target `noiseWidth` × `noiseHeight`,
            //    sample the Perlin value, convert to grayscale, and fill a rect.
            for y in stride(from: 0, to: noiseHeight, by: tileSize) {
                for x in stride(from: 0, to: noiseWidth, by: tileSize) {
                    // scaled sample coordinates
                    var val = sampler.getValue(
                        CGFloat(x) / CGFloat(period),
                        CGFloat(y) / CGFloat(period)
                    )
                    
                    //                    let normalized = max(0, min(1, (val + 1) / 2))
                    if method == 1 { val = compressValueExp(val, exponent: level) }
                    if method == 2 { val = compressValueLinear(val, factor: level) }
                    if method == 3 { val = compressValueTanh(val, factor: level) }
                    let normalized = val / 2 + 1
                    
                    
                    // Multiply each channel by the normalized factor
                    let color = baseColor
                        .opacity(1.0)
                        .withRGBMultiplication(normalized)
                    
                    // Fill tileSize × tileSize rectangle at (x, y)
                    let rect = CGRect(
                        x: CGFloat(x),
                        y: CGFloat(y),
                        width: CGFloat(tileSize),
                        height: CGFloat(tileSize)
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(noiseWidth), height: CGFloat(noiseHeight))
        // You can remove the .frame(...) if you want the view to dynamically resize.
    }
    
    func compressValueExp(_ value: CGFloat, exponent: CGFloat) -> CGFloat {
        let sign: CGFloat = value < 0 ? -1 : 1
        return sign * pow(abs(value), exponent)
    }
    func compressValueLinear(_ value: CGFloat, factor: CGFloat) -> CGFloat {
        return value * factor
    }
    func compressValueTanh(_ value: CGFloat, factor: CGFloat) -> CGFloat {
        return tanh(value * factor)
    }
}

// MARK: PerlinSampler2D
struct PerlinSampler2D {
    let width: Int
    let height: Int
    let period: Int // Period for tiling
    
    // Each cell has (gx, gy) gradient => 2 floats
    var gradients: [CGFloat]
    
    init(width: Int, height: Int, period: Int, randSeed: Int) {
        self.width = width
        self.height = height
        self.period = period
        self.gradients = .init(repeating: 0, count: width * height * 2)
        
        // Initialize gradients with random directions
        var rand = RandomLCG(seed: randSeed)
        for i in stride(from: 0, to: gradients.count, by: 2) {
            let angle = rand.next() * (.pi * 2)
            let x = sin(angle)
            let y = cos(angle)
            gradients[i] = CGFloat(x)
            gradients[i + 1] = CGFloat(y)
        }
    }
    
    /// Dot-product with the gradient at (cellX, cellY), accounting for tiling
    func dot(cellX: Int, cellY: Int, vx: CGFloat, vy: CGFloat) -> CGFloat {
        // Wrap around using modulo with period
        let wrappedX = (cellX % period + period) % period
        let wrappedY = (cellY % period + period) % period
        let idx = (wrappedX + wrappedY * width) * 2 % gradients.count
        
        // Ensure idx is within bounds of the gradients array
        guard idx >= 0 && idx + 1 < gradients.count else {
            return 0 // Return a safe default value
        }
        
        let gx = gradients[idx]
        let gy = gradients[idx + 1]
        return gx * vx + gy * vy
    }
    
    /// Smoothstep (s-curve)
    func sCurve(_ t: CGFloat) -> CGFloat {
        // Equivalent to 6t^5 - 15t^4 + 10t^3
        return t * t * t * (t * (t * 6 - 15) + 10)
    }
    
    /// Linear interpolation
    func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + t * (b - a)
    }
    
    /// Sample Perlin value in [-1, 1] at coordinate (x, y), with tiling
    func getValue(_ x: CGFloat, _ y: CGFloat) -> CGFloat {
        // Integer cells
        let xCell = Int(floor(x)) % period
        let yCell = Int(floor(y)) % period
        
        // Fractional part
        let xFrac = x - floor(x)
        let yFrac = y - floor(y)
        
        // Dot products at the 4 corners
        let v00 = dot(cellX: xCell, cellY: yCell, vx: xFrac, vy: yFrac)
        let v10 = dot(cellX: xCell + 1, cellY: yCell, vx: xFrac - 1, vy: yFrac)
        let v01 = dot(cellX: xCell, cellY: yCell + 1, vx: xFrac, vy: yFrac - 1)
        let v11 = dot(cellX: xCell + 1, cellY: yCell + 1, vx: xFrac - 1, vy: yFrac - 1)
        
        // Interpolate horizontally
        let tx = sCurve(xFrac)
        let vx0 = lerp(v00, v10, tx)
        let vx1 = lerp(v01, v11, tx)
        
        // Interpolate vertically
        let ty = sCurve(yFrac)
        let val = lerp(vx0, vx1, ty)
        
        return val
    }
}

//MARK: Linear Congruential Generator
struct RandomLCG {
    let m = 2147483647   // 2^31 - 1
    let a = 16807        // 7^5
    let q = 127773       // m / a
    let r = 2836         // m % a
    
    // Current seed
    var seed: Int = 1
    
    mutating func setSeed(_ newSeed: Int) {
        var s = newSeed
        if s <= 0 {
            s = -(s % (m - 1)) + 1
        }
        if s > m - 1 {
            s = m - 1
        }
        seed = s
    }
    
    /// Returns a random Double in [0,1).
    mutating func next() -> Double {
        let res = a * (seed % q) - r * (seed / q)
        seed = (res > 0) ? res : res + m
        return Double(seed) / Double(m)
    }
}

/// Helper: rotate a point by `angle` around `origin`
fileprivate func rotatePoint(_ point: CGPoint, by angle: CGFloat, around origin: CGPoint) -> CGPoint {
    let dx = point.x - origin.x
    let dy = point.y - origin.y
    let cosA = cos(angle)
    let sinA = sin(angle)
    let rx = dx * cosA - dy * sinA
    let ry = dx * sinA + dy * cosA
    return CGPoint(x: rx + origin.x, y: ry + origin.y)
}

/// Helper: offset a point by a given center
fileprivate extension CGPoint {
    func offset(by center: CGPoint) -> CGPoint {
        CGPoint(x: self.x + center.x, y: self.y + center.y)
    }
}

extension Comparable {
    /// Utility to clamp a value within a range
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

// MARK: HandWearOverlay
/// An overlay that simulates generic wear from repeated hand contact.
struct HandWearOverlay: View {
    /// Controls the overall intensity of the hand wear.
    var wearIntensity: Double
    
    var body: some View {
        Canvas { context, size in
            // Determine how many wear marks to draw.
            let markCount = Int(ceil(wearIntensity * 3))
            
            for _ in 0..<markCount {
                // Choose a random width (20-40% of the total width) and a fixed-ish height.
                let markWidth = Double.random(in: Double(size.width) * 0.2 ... Double(size.width) * 0.4)
                let markHeight = Double.random(in: 20...50)
                
                // Position the mark near the lower part of the felt.
                let x = Double.random(in: 0...(Double(size.width) - markWidth))
                let y = Double.random(in: Double(size.height) * 0.75 ... Double(size.height) * 0.95)
                let rect = CGRect(x: x, y: y, width: markWidth, height: markHeight)
                
                // Create a soft radial gradient to simulate the worn, smudged area.
                let gradient = Gradient(stops: [
                    .init(color: Color.black.opacity(0.15 * wearIntensity), location: 0.0),
                    .init(color: Color.black.opacity(0.05 * wearIntensity), location: 0.7),
                    .init(color: Color.clear, location: 1.0)
                ])
                
                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        gradient,
                        center: CGPoint(x: rect.midX, y: rect.midY),
                        startRadius: 0,
                        endRadius: min(rect.width, rect.height) / 2
                    )
                )
            }
        }
        .drawingGroup()
    }
}

// MARK: DynamicWearOverlay
struct DynamicWearOverlay: View {
    var wearIntensity: Double
    // An offset to animate the noise—could be tied to a timer.
    var timeOffset: Double = 0
    
    var body: some View {
        Canvas { context, size in
            // Determine how many wear marks to draw.
            let markCount = Int(ceil(wearIntensity * 10))
            
            for _ in 0..<markCount {
                // Random size and position for each mark.
                let markWidth = Double.random(in: Double(size.width) * 0.2 ... Double(size.width) * 0.4)
                let markHeight = Double.random(in: 20...50)
                let region = Int.random(in: 0...2) // 0 = left, 1 = right, 2 = bottom
                let x: Double
                let y: Double
                
                switch region {
                case 0: // Left side (5-25%)
                    x = Double.random(in: size.width * -0.1...size.width * 0.10)
                    y = Double.random(in: 0...size.height)
                case 1: // Right side (75-95%)
                    x = Double.random(in: size.width * 0.65...size.width * 0.85)
                    y = Double.random(in: 0...size.height)
                case 2: // Bottom (75-95%)
                    x = Double.random(in: size.width * -0.1...size.width * 0.9)
                    y = Double.random(in: size.height * 0.75...size.height * 0.95)
                default:
                    logger.fatalErrorAndLog("Unexpected region value")
                }
                let rect = CGRect(x: x, y: y, width: markWidth, height: markHeight)
                
                // Sample Perlin noise (with time offset) to decide on lightening or darkening.
                let noiseVal = perlinNoise(x + timeOffset, y + timeOffset)
                let lighten = noiseVal > 0
                let overlayColor: Color = lighten ? .white : .black
                let baseOpacity = 0.2 * wearIntensity
                let adjustedOpacity = baseOpacity + (abs(noiseVal) * 0.1)
                
                let gradient = Gradient(stops: [
                    .init(color: overlayColor.opacity(adjustedOpacity), location: 0.0),
                    .init(color: overlayColor.opacity(adjustedOpacity * 0.5), location: 0.7),
                    .init(color: Color.clear, location: 1.0)
                ])
                
                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        gradient,
                        center: CGPoint(x: rect.midX, y: rect.midY),
                        startRadius: 0,
                        endRadius: min(rect.width, rect.height) / 2
                    )
                )
            }
        }
        .drawingGroup()
    }
}

// MARK: - Preview

struct AdvancedFeltView_Previews: PreviewProvider {
    static var previews: some View {
        FeltBackgroundView(
            baseColorIndex: 0,
            radialShadingStrength: 0.4,
            wearIntensity: 1,
            motifVisibility: 0.2,
            motifScale: 1,
            showScratches: true
        )
        .previewLayout(.sizeThatFits)
        .padding()
        .frame(width: 600, height: 400)
        .previewDisplayName("Advanced Felt Surface")
    }
}


private func feltBackgroundName(for index: Int) -> String {
    let names = [
        "Vert Classique",
        "Bleu Profond",
        "Rouge Vin",
        "Violet Royal",
        "Sarcelle",
        "Gris Charbon",
        "Orange Brûlé",
        "Vert Forêt",
        "Marron Chocolat",
        "Rouge Écarlate"
    ]
    return index < names.count ? names[index] : "Vert Classique"
}
