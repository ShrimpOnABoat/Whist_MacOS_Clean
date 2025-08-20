//
//  ProceduralCracksView.swift
//  Whist
//
//  Created by Tony Buffard on 2025-02-14.
//

import SwiftUI

struct ProceduralCracksView: View {
    let crackCount: Int = 6
    let stepsPerCrack: Int = 10
    let branchProbability: Double = 0.5 // Probability of creating a branch at each step
    let splitChanceDecay: Double = 5
    let killDistance: CGFloat = 80
    let startingWidth: CGFloat = 8
    let widthDecay: Double = 0.55

    var body: some View {
        Canvas { context, size in
            let startPoint: CGPoint = CGPoint(x: size.width / 2, y: size.height / 2)
            for _ in 0..<crackCount {
                createCrackPath(from: startPoint, branchingAt: startPoint, in: size, branchProbability: branchProbability, distance: 0, currentWidth: startingWidth, context: &context)
            }
        }
        .frame(width: 300, height: 300)
    }

    func createCrackPath(from startPoint: CGPoint, branchingAt branchStartPoint: CGPoint, in size: CGSize, branchProbability: Double, distance: CGFloat, currentWidth: CGFloat, context: inout GraphicsContext) {
        var path = Path()
        var totalSegmentLength: CGFloat = 0
        path.move(to: branchStartPoint)
        
        let randomColor: Color = .black
        var currentPoint = branchStartPoint
        var currentAngle = (currentPoint != startPoint) ? atan2(branchStartPoint.y - startPoint.y, branchStartPoint.x - startPoint.x) : Double.random(in: 0...(2 * Double.pi))
        var width = currentWidth

        var previousLeftOffset = CGPoint(
            x: branchStartPoint.x + (width / 2) * cos(currentAngle + .pi / 2),
            y: branchStartPoint.y + (width / 2) * sin(currentAngle + .pi / 2)
        )
        var previousRightOffset = CGPoint(
            x: branchStartPoint.x + (width / 2) * cos(currentAngle - .pi / 2),
            y: branchStartPoint.y + (width / 2) * sin(currentAngle - .pi / 2)
        )

        for _ in 0..<stepsPerCrack {
            let angleDeviation = Double.random(in: -Double.pi/4 ... Double.pi/4)
            currentAngle += angleDeviation
            let segmentLength = CGFloat.random(in: 10...30)
            totalSegmentLength += segmentLength
            
            let nextPoint = CGPoint(x: currentPoint.x + segmentLength * cos(Double(currentAngle)),
                                    y: currentPoint.y + segmentLength * sin(Double(currentAngle)))

            let nextLeftOffset = CGPoint(x: nextPoint.x + (width * widthDecay) * cos(currentAngle + .pi / 2),
                                         y: nextPoint.y + (width * widthDecay) * sin(currentAngle + .pi / 2))
            let nextRightOffset = CGPoint(x: nextPoint.x + (width * widthDecay) * cos(currentAngle - .pi / 2),
                                          y: nextPoint.y + (width * widthDecay) * sin(currentAngle - .pi / 2))
            
            // Create the trapezoid shape for this segment
            var segmentPath = Path()
            segmentPath.move(to: previousLeftOffset)
            segmentPath.addLine(to: nextLeftOffset)
            segmentPath.addLine(to: nextRightOffset)
            segmentPath.addLine(to: previousRightOffset)
            segmentPath.closeSubpath()
            
            context.fill(segmentPath, with: .color(randomColor))
            
            currentPoint = nextPoint
            width = max(width * widthDecay, 1)  // Gradually decrease the width but keep it at least 1
            
            // Update the previous offsets for the next iteration
            previousLeftOffset = nextLeftOffset
            previousRightOffset = nextRightOffset

            if totalSegmentLength > killDistance {
                break
            }

            // Randomly create a branch with the current width
            if Double.random(in: 0...1) < branchProbability {
                createCrackPath(from: startPoint, branchingAt: currentPoint, in: size, branchProbability: branchProbability / splitChanceDecay, distance: distance + totalSegmentLength, currentWidth: width, context: &context)
            }
        }
    }
}

struct ProceduralCracksView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack{
            FeltBackgroundView(
                baseColorIndex: 0,
                radialShadingStrength: 0.4,
                wearIntensity: 1,
                motifVisibility: 0.2,
                motifScale: 1,
                showScratches: true
            )
            ProceduralCracksView()
                .blur(radius: 1)
                .blendMode(.multiply)
        }
        .padding()
        .frame(width: 600, height: 400)
    }
}
