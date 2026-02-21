//
//  WhistApp.swift
//  Whist
//
//  Created by Tony Buffard on 2024-11-18.
//  Entry point of the application.

import SwiftUI
import Firebase
import FirebaseAppCheck
import FirebaseAuth
import AppKit

@main
struct WhistApp: App {
    @StateObject var preferences: Preferences
    @StateObject var gameManager: GameManager
    
    // ADD: AppDelegate needed for GameKit listener on macOS
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Configure Firebase
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        FirebaseApp.configure()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            do {
                try Auth.auth().signOut()
                logger.log("✅ Signed out previous anonymous user")
            } catch {
                logger.log("⚠️ Could not sign out anonymous user: \(error.localizedDescription)")
            }
            Auth.auth().signInAnonymously { authResult, error in
                if let error = error {
                    logger.log("❌ Firebase anonymous sign-in failed: \(error.localizedDescription)")
                } else if let uid = authResult?.user.uid {
                    logger.log("✅ Signed in anonymously with UID: \(uid)")
                }
            }
        }
        logger.log("Firebase UID: \(Auth.auth().currentUser?.uid ?? "nil")")
        let settings = FirestoreSettings()
        #if DEBUG
        settings.cacheSettings = MemoryCacheSettings()
        #else
        settings.cacheSettings = PersistentCacheSettings() // Use disk-backed cache
        #endif
        Firestore.firestore().settings = settings
        #if DEBUG // So that I can assign a player for each app
        UserDefaults.standard.removeObject(forKey: "playerId")
        #endif
        
        // Initialize preferences
        let prefs = Preferences()
        
        // Use singleton instances for signaling and P2P
        let signaling = FirebaseSignalingManager.shared
        let connection = P2PConnectionManager.shared
        
        // Initialize the core game manager with our custom matchmaking
        let manager = GameManager(connectionManager: connection,
                                  signalingManager: signaling,
                                  preferences: prefs)
        
        // Wire up state objects
        _preferences = StateObject(wrappedValue: prefs)
        _gameManager = StateObject(wrappedValue: manager)
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if preferences.playerId.isEmpty {
                    IdentityPromptView(playerId: $preferences.playerId)
                        .onAppear {
                            if let window = NSApplication.shared.windows.first {
#if DEBUG
                                let windowPositions: [CGPoint] = [
                                    CGPoint(x: 100, y: 700),
                                    CGPoint(x: 500, y: 700),
                                    CGPoint(x: 900, y: 700),
                                    CGPoint(x: 100, y: 100),
                                    CGPoint(x: 500, y: 100),
                                    CGPoint(x: 900, y: 100)
                                ]
                                let randomPosition = windowPositions.randomElement() ?? CGPoint(x: 100, y: 700)
                                window.setFrame(
                                    NSRect(x: randomPosition.x,
                                           y: randomPosition.y,
                                           width: 800,
                                           height: 600),
                                    display: true
                                )
#endif
                                window.contentAspectRatio = NSSize(width: 4, height: 3)
                                window.minSize = NSSize(width: 800, height: 600)
                            }
                        }
                } else {
                    ContentView()
                        .onAppear {
                            if let window = NSApplication.shared.windows.first {
                                #if DEBUG
                                window.setFrame(
                                            NSRect(x: window.frame.origin.x,
                                                   y: window.frame.origin.y,
                                                   width: 800,
                                                   height: 600),
                                            display: true
                                        )
                                #endif
                                window.contentAspectRatio = NSSize(width: 4, height: 3)
                                window.minSize = NSSize(width: 800, height: 600)
                            }
                            logger.setLocalPlayer(with: preferences.playerId)
                            PresenceManager.shared.configure(with: preferences.playerId)
                        }
                }
            }
            .environmentObject(preferences)
            .environmentObject(gameManager)
        }
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) { }
            Group {
                ScoresMenuCommands()
                if preferences.playerId == "toto" {
                    DatabaseMenuCommands(preferences: preferences, gameManager: gameManager)
                }
                NetworkMenuCommands(gameManager: gameManager)
            }
        }
        
        Settings {
            PreferencesView()
                .environmentObject(preferences)
                .environmentObject(gameManager)
        }
        
        // Secondary window for ScoresView with an identifier.
        Window("Scores", id: "ScoresWindow") {
            ScoresView()
                .environmentObject(gameManager)
                .environmentObject(preferences)
        }
        .commandsRemoved()
    }
}

struct ScoresMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    
    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()
            Button("Voir les scores") {
                openWindow(id: "ScoresWindow")
            }
            .keyboardShortcut("s", modifiers: [.command])
            Divider()
        }
    }
}

struct DatabaseMenuCommands: Commands {
    let preferences: Preferences
    let gameManager: GameManager
    
    init(preferences: Preferences, gameManager: GameManager) {
        self.preferences = preferences
        self.gameManager = gameManager
    }
    
    var body: some Commands {
        CommandMenu("Database") {
            Button("Restore Database from Backup") {
                // Show a warning alert before restoring
                let alert = NSAlert()
                alert.messageText = "Are you sure you want to restore the database from backup? This will overwrite existing data."
                alert.informativeText = "This action cannot be undone."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Restore")
                alert.addButton(withTitle: "Cancel")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // User confirmed: perform restore
                    let backupDirectory = URL(fileURLWithPath: "/Users/tonybuffard/Library/Containers/com.Tony.Whist/Data/Documents/scores/")
                    Task {
                        let scoresManager = ScoresManager.shared
                        do {
                            try await scoresManager.restoreBackup(from: backupDirectory)
                            await MainActor.run {
                                logger.log("✅ Database restored successfully.")
                            }
                        } catch {
                            await MainActor.run {
                                logger.log("🚨 Error restoring backup: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
            
            Button("Export scores") {
                let exportDirectory = URL(fileURLWithPath: "/Users/tonybuffard/Library/Containers/com.Tony.Whist/Data/Documents/scores/Export")

                Task {
                     let scoresManager = ScoresManager.shared // Use shared instance
                    do {
                         try await scoresManager.exportScoresToLocalDirectory(exportDirectory)
                        // Log success on the main actor
                        await MainActor.run {
                            logger.log("✅ All scores were exported successfully to \(exportDirectory.path).")
                        }
                    } catch {
                         // Log error on the main actor
                         await MainActor.run {
                            logger.log("🚨 Error exporting scores: \(error.localizedDescription)")
                         }
                    }
                }
            }
            
            Button("Clear Saved Game") {
                let alert = NSAlert()
                alert.messageText = "Are you sure you want to clear the saved game?"
                alert.informativeText = "This action cannot be undone."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Clear")
                alert.addButton(withTitle: "Cancel")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    gameManager.clearSavedGameActions()
                }
            }
            
            Button("Export Game Actions") {
                gameManager.exportGameActionsForAnalysis()
            }
            .help("Export all saved game actions to a JSON file. Only available to toto.")
            Divider()
        }
    }
}

class Preferences: ObservableObject {
    @AppStorage("selectedFeltIndex") var selectedFeltIndex: Int = 0
    // Utiliser un toggle pour l'intensité de l'usure, activé par défaut
    @AppStorage("wearIntensity") var wearIntensity: Bool = true
    @AppStorage("motif") var motif: Bool = true
    @AppStorage("motifVisibility") var motifVisibility: Double = 0.5
    @AppStorage("patternOpacity") var patternOpacity: Double = 0.5
    @AppStorage("patternScale") private var patternScaleStorage: Double = 0.5
    @AppStorage("enabledRandomColors") private var enabledRandomColorsData: Data?
    // Per-sound volumes (0 = mute). Stored as JSON in UserDefaults.
    @AppStorage("soundVolumes") private var soundVolumesData: Data?
    #if DEBUG
    @Published var playerId: String = ""
    #else
    @AppStorage("playerId") var playerId: String = ""
    #endif
    
    var patternScale: CGFloat {
        get { CGFloat(patternScaleStorage) }
        set { patternScaleStorage = Double(newValue) }
    }
    
    var currentFelt: Color {
        GameConstants.feltColors[selectedFeltIndex]
    }
    
    // Sauvegarde des couleurs activables pour le tirage aléatoire
    var enabledRandomColors: [Bool] {
        get {
            if let data = enabledRandomColorsData,
               let decoded = try? JSONDecoder().decode([Bool].self, from: data),
               decoded.count == GameConstants.feltColors.count {
                return decoded
            } else {
                // Initialiser avec toutes les couleurs sélectionnées par défaut
                return Array(repeating: true, count: GameConstants.feltColors.count)
            }
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                enabledRandomColorsData = data
            }
        }
    }

    // Default volumes come from SoundManager (stored by sound id)
    var soundVolumes: [String: Float] {
        get {
            if let data = soundVolumesData,
               let decoded = try? JSONDecoder().decode([String: Float].self, from: data) {
                return decoded
            }
            // Initialize with defaults from SoundManager (stored by sound id)
            var defaults: [String: Float] = [:]
            for config in SoundManager.allSoundConfigs {
                defaults[config.id] = config.defaultVolume
            }
            return defaults
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                soundVolumesData = data
            }
        }
    }

    func soundVolume(for name: String) -> Float {
        soundVolumes[name] ?? SoundManager.soundConfigsById[name]?.defaultVolume ?? 1.0
    }

    func setSoundVolume(_ volume: Float, for name: String) {
        var current = soundVolumes
        current[name] = max(0.0, min(1.0, volume))
        soundVolumes = current
    }
}

struct PreferencesView: View {
    @EnvironmentObject var preferences: Preferences
    
    var body: some View {
        TabView {
            // MARK: - Tapis
            VStack {
                Form {
                    // Section pour les couleurs du tapis
                    Section(header: Text("Couleurs du tapis")
                        .font(.headline)
                        .padding(.vertical, 4)) {
                            ForEach(0..<GameConstants.feltColors.count, id: \.self) { idx in
                                Toggle(isOn: Binding<Bool>(
                                    get: { preferences.enabledRandomColors.indices.contains(idx) ? preferences.enabledRandomColors[idx] : false },
                                    set: { newValue in
                                        var current = preferences.enabledRandomColors
                                        if current.indices.contains(idx) {
                                            current[idx] = newValue
                                        } else {
                                            current = Array(repeating: false, count: GameConstants.feltColors.count)
                                            current[idx] = newValue
                                        }
                                        preferences.enabledRandomColors = current
                                    }
                                )) {
                                    HStack {
                                        Circle()
                                            .fill(GameConstants.feltColors[idx])
                                            .frame(width: 20, height: 20)
                                        Text(feltName(for: idx))
                                    }
                                }
                            }
                        }

                    // Section pour le toggle de l'usure du tapis
                    Section(header: Text("Détails")
                        .font(.headline)
                        .padding(.vertical, 4)) {
                            Toggle("Usure du tapis", isOn: $preferences.wearIntensity)
                            Toggle("Motifs", isOn: $preferences.motif)
                        }
                }

                // Bouton pour rafraîchir le background
                Button("Rafraîchir le tapis") {
                    // Récupérer les indices des couleurs activées
                    let enabledIndices = preferences.enabledRandomColors.enumerated().compactMap { (index, isEnabled) in
                        isEnabled ? index : nil
                    }
                    // Si au moins une couleur est sélectionnée, on choisit aléatoirement l'une d'entre elles
                    if let newIndex = enabledIndices.randomElement() {
                        preferences.selectedFeltIndex = newIndex
                    }
                }
                .padding(.top)
            }
            .padding()
            .tabItem {
                Label("Tapis", systemImage: "squareshape.split.2x2")
            }

            // MARK: - Sons
            VStack {
                Form {
                    Section(header: Text("Effets sonores")
                        .font(.headline)
                        .padding(.vertical, 4)) {
                            let configs = SoundManager.allSoundConfigs.sorted { $0.label < $1.label }
                            ForEach(configs) { config in
                                HStack(spacing: 12) {
                                    Text(config.label)
                                        .frame(width: 140, alignment: .leading)

                                    Slider(
                                        value: Binding<Double>(
                                            get: { Double(preferences.soundVolume(for: config.id)) },
                                            set: { preferences.setSoundVolume(Float($0), for: config.id) }
                                        ),
                                        in: 0...1
                                    )

                                    Text("\(Int(preferences.soundVolume(for: config.id) * 100))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 44, alignment: .trailing)
                                }
                            }
                        }
                }
            }
            .padding()
            .tabItem {
                Label("Sons", systemImage: "speaker.wave.2")
            }

            // MARK: - Identité
            VStack {
                Form {
                    Section(header: Text("Identité du joueur")
                        .font(.headline)
                        .padding(.vertical, 4)) {
                            if preferences.playerId.isEmpty {
                                Text("Veuillez choisir votre identité")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                            Picker("", selection: $preferences.playerId) {
                                ForEach(["dd", "gg", "toto"], id: \.self) { id in
                                    Text(id).tag(id)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                }
            }
            .padding()
            .tabItem {
                Label("Identité", systemImage: "person.crop.circle")
            }
        }
        .frame(width: 400)
    }
    
    func feltName(for index: Int) -> String {
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
        return names.indices.contains(index) ? names[index] : "Couleur Inconnue"
    }
}

struct IdentityPromptView: View {
    @Binding var playerId: String
    let identities = ["dd", "gg", "toto"]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Choisissez votre identité")
                .font(.headline)
            Picker("Identité", selection: $playerId) {
                ForEach(identities, id: \.self) { id in
                    Text(id).tag(id)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
        }
        .frame(width: 300, height: 150)
        .padding()
    }
}

struct NetworkMenuCommands: Commands {
    let gameManager: GameManager

    var body: some Commands {
        CommandMenu("Network") {
            Button("Rattraper les actions manquées") {
                gameManager.resetStateAndRestoreGame()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help("Relit les gameActions pour resynchroniser la partie en cours.")

            Divider()

            Button("Admin: Retour à Nouvelle partie") {
                gameManager.adminRefreshToNewGameLobby()
            }
            .disabled(gameManager.gameState.localPlayer?.id != .toto)
            .help("Toto seulement: efface les anciennes gameActions et force un retour synchronisé à Nouvelle partie.")
        }
    }
}
    
