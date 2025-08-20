//
//  RoundHistoryView.swift
//  Whist
//
//  Created by Tony Buffard on 2025-02-07.
//

import SwiftUI

struct RoundHistoryView: View {
    @EnvironmentObject var gameManager: GameManager
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                VStack(spacing: 5) {
                    headerRow()
                    
                    ForEach(1...min(gameManager.gameState.round - 1, 12), id: \.self) { round in
                        roundRow(round: round)
                    }
                }
                .padding()
            }
            
            Button("Fermer") {
                isPresented = false
            }
            .hidden()
            .keyboardShortcut("s", modifiers: [])
        }
        .frame(width: 450, height: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
    
    // MARK: - Header Row
    func headerRow() -> some View {
        HStack {
            Text("Tour").frame(width: 50).bold().foregroundColor(.primary)
 
            ForEach(["GG", "DD", "Toto"], id: \.self) { name in
                Text(name).frame(width: 100).bold().foregroundColor(.primary)
            }
        }
        .padding(.vertical, 5)
        .background(Color(NSColor.secondaryLabelColor).opacity(0.2))
        .cornerRadius(5)
    }
    
    // MARK: - Round Row
    func roundRow(round: Int) -> some View {
        let players = gameManager.gameState.players.sorted { player1, player2 in
            let order: [PlayerId] = [.gg, .dd, .toto]
            return order.firstIndex(of: player1.id) ?? Int.max < order.firstIndex(of: player2.id) ?? Int.max
        }
        let announcedTotal = players.reduce(0) { $0 + ($1.announcedTricks[safe: round - 1] ?? 0) }
        
        let backgroundColor: Color? = {
            if round > 3 {
                if announcedTotal < round - 2 {
                    let opacity = CGFloat(round - 2 - announcedTotal) * 0.2
                    return Color.blue.opacity(opacity)
                }
                if announcedTotal > round - 2 {
                    let opacity = CGFloat(announcedTotal - (round - 2)) * 0.2
                    return Color.red.opacity(opacity)
                }
            }
            return nil
        }()
        
        return HStack {
            Text(round <= 3 ? "1" : "\(round - 2)")
                .frame(width: 50)
                .bold()
                .padding(.vertical, 5)
            
            ForEach(players) { player in
                VStack {
                    HStack {
                        Text("\(player.madeTricks[safe: round - 1] ?? 0)")
                        Text("/")
                        Text("\(player.announcedTricks[safe: round - 1] ?? 0)")
                        Text("\(player.scores[safe: round - 1] ?? 0)").bold()
                    }
                }
                .frame(width: 100)
            }
        }
        .frame(maxWidth: .infinity)
        .background(backgroundColor)
        .cornerRadius(5)
    }
}
