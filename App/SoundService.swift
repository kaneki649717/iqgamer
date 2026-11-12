import SwiftUI
import AVFoundation
import BoardCore
import UIKit

/// 音效 + 触觉反馈服务。
/// 音频由 scripts/make_sounds.py 程序化合成；落子/吃子音效风格可在设置里挑选。
final class SoundService {
    static let shared = SoundService()

    /// 固定音效
    enum SFX: String, CaseIterable {
        case win = "win"
        case lose = "lose"
        case draw = "draw"
        case click = "click"
    }

    enum HapticStyle {
        case place
        case capture
        case win, lose, draw
        case uiTap
    }

    static let placeStyleNames = ["古典木声", "厚实木声", "轻巧木声", "沉稳大木"]
    static let stoneStyleNames = ["清脆石子", "明亮玉子", "柔和石子", "温润瓷石"]
    static let captureStyleNames = ["厚实吃子", "连贯双击", "轻巧吃子", "低频重击"]

    private var players: [String: AVAudioPlayer] = [:]
    private let hapticImpact = UIImpactFeedbackGenerator(style: .light)
    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    private let hapticNotify = UINotificationFeedbackGenerator()

    private init() {
        hapticImpact.prepare()
        hapticMedium.prepare()
        preload(["place_wood_a", "place_wood_b", "place_wood_c", "place_wood_d",
                 "place_stone_a", "place_stone_b", "place_stone_c", "place_stone_d",
                 "capture_a", "capture_b", "capture_c", "capture_d",
                 "win", "lose", "draw", "click"])
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    private func preload(_ names: [String]) {
        for n in names {
            if let url = Bundle.main.url(forResource: n, withExtension: "wav") {
                let p = try? AVAudioPlayer(contentsOf: url)
                p?.prepareToPlay()
                players[n] = p
            }
        }
    }

    // MARK: - 设置读取

    private var soundOn: Bool {
        UserDefaults.standard.object(forKey: "soundOn") == nil
            || UserDefaults.standard.bool(forKey: "soundOn")
    }

    private var hapticsOn: Bool {
        UserDefaults.standard.object(forKey: "hapticsOn") == nil
            || UserDefaults.standard.bool(forKey: "hapticsOn")
    }

    private var volume: Float {
        Float(UserDefaults.standard.object(forKey: "soundVolume") as? Double ?? 0.9)
    }

    private var placeStyle: Int { min(UserDefaults.standard.integer(forKey: "placeStyle"), 3) }
    private var captureStyle: Int { min(UserDefaults.standard.integer(forKey: "captureStyle"), 3) }

    // MARK: - 播放

    private func play(file: String) {
        guard soundOn, let p = players[file] else { return }
        p.volume = volume
        if p.isPlaying { p.currentTime = 0 }
        p.play()
    }

    func play(_ sfx: SFX) {
        play(file: sfx.rawValue)
    }

    func haptic(_ style: HapticStyle) {
        guard hapticsOn else { return }
        switch style {
        case .place: hapticImpact.impactOccurred(intensity: 0.7)
        case .capture: hapticMedium.impactOccurred(intensity: 1.0)
        case .uiTap: hapticImpact.impactOccurred(intensity: 0.4)
        case .win: hapticNotify.notificationOccurred(.success)
        case .lose: hapticNotify.notificationOccurred(.error)
        case .draw: hapticNotify.notificationOccurred(.warning)
        }
    }

    /// 落子反馈（风格按设置），capture 由调用方判定
    func moveFeedback(gameID: GameID, capture: Bool) {
        if capture {
            play(file: "capture" + ["_a", "_b", "_c", "_d"][captureStyle])
            haptic(.capture)
            return
        }
        let family: String
        switch gameID {
        case .go, .gomoku, .reversi: family = "stone"
        default: family = "wood"
        }
        play(file: "place_\(family)_" + ["a", "b", "c", "d"][placeStyle])
        haptic(.place)
    }
}
