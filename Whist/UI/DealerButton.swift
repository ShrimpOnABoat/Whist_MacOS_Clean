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
            // Outer shadow
            Circle()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.2), radius: size * 0.12, x: size * 0.06, y: size * 0.06)
                .frame(width: size, height: size)
            
            // Inner gradient for the 3D effect
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.white, Color.gray.opacity(1)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)
            
            // "D" letter
            Text("DEALER")
                .font(.system(size: size * 0.2, weight: .bold))
                .foregroundColor(.black)
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
