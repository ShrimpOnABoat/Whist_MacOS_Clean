//
//  DealerButton.swift
//  Whist
//
//  Created by Tony Buffard on 2024-12-14.
//

import SwiftUI

struct DealerButton: View {
    // Add a size variable to control the button's overall size
    var size: CGFloat = 50
    
    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.74),
                                    Color.white.opacity(0.34),
                                    Color.black.opacity(0.12)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.62), lineWidth: 1.2)
                )
                .shadow(color: Color.black.opacity(0.24), radius: size * 0.18, x: 0, y: size * 0.08)

            Text("DEALER")
                .font(.system(size: size * 0.18, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.78))
        }
        .background(Color.clear)
    }
}

struct DealerButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            DealerButton(size: 40) // Small size
            DealerButton(size: 50) // Default size
            DealerButton(size: 80) // Large size
        }
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
