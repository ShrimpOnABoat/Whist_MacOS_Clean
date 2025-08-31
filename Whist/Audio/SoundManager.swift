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
    private let soundConfigs: [String: (fileName: String, defaultVolume: Float)] = [
        "card shuffle": ("card shuffle.mp3", 0.5),
        "applaud": ("applaud.wav", 0.8),
        "fail": ("fail.wav", 1.0),
        "impact": ("impact.wav", 1.0),
        "Confetti": ("Confetti.wav", 1.0),
        "pouet": ("pouet.wav", 1.0),
        "normal-click": ("normal-click.wav", 0.0), // Volume 0 to effectively disable
        "play card": ("play card.mp3", 0.2)
    ]

    override init() {
        super.init()
        preloadAllSounds()
    }

    /// Preload all sound files listed in `soundConfigs`
    private func preloadAllSounds() {
        for (baseName, config) in soundConfigs {
            preloadSound(baseName: baseName, fullFileName: config.fileName)
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
        guard soundConfigs[baseName]?.defaultVolume ?? 1.0 > 0 else {
            return
        }

        guard let player = audioPlayers[baseName] else {
            logger.audio("Sound '\(baseName)' was not preloaded. Attempting to load now...")
            if let config = soundConfigs[baseName] {
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

        let finalVolume = volume ?? soundConfigs[baseName]?.defaultVolume ?? 1.0
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
        #if DEBUG
        guard gameState.localPlayer?.id == .toto else { return }
        #endif
        if filename != "pouet" {
            soundManager.playSound(named: filename)
        } else {
            soundManager.playSound(named: "pouet", volume: amSlowPoke ? 1.0 : 0.3)
        }
    }
}
