//
//  SoundManager.swift
//  Whist
//
//  Created by Tony Buffard on 2025-01-15.
//

import AudioToolbox
import AVFoundation

class SoundManager: NSObject, AVAudioPlayerDelegate {
    private var audioPlayers: [String: AVAudioPlayer] = [:]

    struct SoundConfig: Identifiable {
        let id: String          // Stable internal key used by the game and Preferences
        let label: String       // User-facing label shown in Settings
        let fileName: String
        let defaultVolume: Float
    }

    /// Single source of truth for all sound effects.
    /// - `id` is the stable key used by the game code and stored in Preferences.
    /// - `label` is what we display in the Settings UI.
    static let allSoundConfigs: [SoundConfig] = [
        .init(id: "shuffle",  label: "Mélange des cartes",   fileName: "card shuffle.mp3",  defaultVolume: 0.5),
        .init(id: "applaud",  label: "Applaudissements",    fileName: "applaud.wav",       defaultVolume: 0.8),
        .init(id: "fail",     label: "Suspense - raté",      fileName: "fail.wav",          defaultVolume: 1.0),
        .init(id: "impact",   label: "Suspense - réussi",    fileName: "impact.wav",        defaultVolume: 1.0),
        .init(id: "confetti", label: "Confetti",             fileName: "Confetti.wav",      defaultVolume: 1.0),
        .init(id: "pouet",    label: "Klaxon",               fileName: "pouet.wav",         defaultVolume: 1.0),
        .init(id: "click",    label: "Clic",                 fileName: "normal-click.wav",  defaultVolume: 0.2),
        .init(id: "playCard", label: "Mouvement de carte",    fileName: "play card.mp3",     defaultVolume: 0.2)
    ]

    static let soundConfigsById: [String: SoundConfig] = {
        Dictionary(uniqueKeysWithValues: allSoundConfigs.map { ($0.id, $0) })
    }()

    override init() {
        super.init()
        preloadAllSounds()
    }

    /// Preload all sound files listed in `allSoundConfigs`
    private func preloadAllSounds() {
        for config in Self.allSoundConfigs {
            preloadSound(baseName: config.id, fullFileName: config.fileName)
        }
    }

    /// Preload a sound using AVAudioPlayer
    func preloadSound(baseName: String, fullFileName: String) {
        guard audioPlayers[baseName] == nil else {
            return
        }

        let components = fullFileName.split(separator: ".")
        guard components.count == 2 else {
            logger.audio("Invalid full file name format: \(fullFileName)")
            return
        }
        let name = String(components[0])
        let ext = String(components[1])

        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            logger.audio("Sound file \(fullFileName) not found.")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            audioPlayers[baseName] = player
            logger.audio("Preloaded sound: \(fullFileName) as '\(baseName)'")
        } catch {
            logger.audio("Failed to create AVAudioPlayer for \(fullFileName): \(error.localizedDescription)")
        }
    }

    /// Play a preloaded sound. Uses default volume if volume parameter is nil.
    func playSound(named baseName: String, volume: Float? = nil) {
        let defaultVol = Self.soundConfigsById[baseName]?.defaultVolume ?? 1.0
        let chosenVol = volume ?? defaultVol
        guard chosenVol > 0 else { return }

        guard let player = audioPlayers[baseName] else {
            logger.audio("Sound '\(baseName)' was not preloaded. Attempting to load now...")
            if let config = Self.soundConfigsById[baseName] {
                preloadSound(baseName: baseName, fullFileName: config.fileName)
                if let newlyLoadedPlayer = audioPlayers[baseName] {
                    let finalVolume = volume ?? config.defaultVolume
                    playLoadedSound(player: newlyLoadedPlayer, volume: finalVolume, baseName: baseName)
                } else {
                    logger.audio("Failed to load and play sound '\(baseName)' on the fly.")
                }
            } else {
                logger.audio("Could not find config info for '\(baseName)' to load on the fly.")
            }
            return
        }

        let finalVolume = volume ?? Self.soundConfigsById[baseName]?.defaultVolume ?? 1.0
        playLoadedSound(player: player, volume: finalVolume, baseName: baseName)
    }

    private func playLoadedSound(player: AVAudioPlayer, volume: Float, baseName: String) {
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }

        player.volume = max(0.0, min(1.0, volume))
        player.play()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        player.currentTime = 0
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let baseName = audioPlayers.first { $0.value == player }?.key ?? "Unknown"
        logger.audio("Audio decode error for \(baseName): \(error?.localizedDescription ?? "nil")")
    }

    /// Unload a sound to free up memory
    func unloadSound(named baseName: String) {
        if let player = audioPlayers[baseName] {
            player.stop()
            audioPlayers.removeValue(forKey: baseName)
        }
    }

    /// Unload all sounds
    func unloadAllSounds() {
        for player in audioPlayers.values {
            player.stop()
        }
        audioPlayers.removeAll()
        logger.audio("Unloaded all sounds.")
    }
}

extension GameManager {
    func playSound(named filename: String) {
        // Use per-sound volume from Preferences (0 = mute)
        let baseVolume = preferences.soundVolume(for: filename)
        guard baseVolume > 0 else { return }

        if filename != "pouet" {
            soundManager.playSound(named: filename, volume: baseVolume)
        } else {
            // Keep the slow/fast variant while still respecting the user's base volume
            let multiplier: Float = amSlowPoke ? 1.0 : 0.3
            soundManager.playSound(named: "pouet", volume: baseVolume * multiplier)
        }
    }
}
