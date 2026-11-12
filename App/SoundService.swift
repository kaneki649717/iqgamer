import SwiftUI
import AVFoundation
import BoardCore
import UIKit

/// 音效 + 触觉反馈服务。
/// 音频文件由 scripts/make_sounds.py 程序化合成（无外部素材/授权问题）。
final class SoundService {
    static let shared = SoundService()

    enum SFX: String, CaseIterable {
        case placeWood = "place_wood"
        case placeStone = "place_stone"
        case capture = "capture"
        case click = "click"
        case win = "win"
        case lose = "lose"
        case draw = "draw"
    }

    enum HapticStyle {
        case place          // 落子：轻
        case capture        // 吃子：中 + 刚性
        case win, lose, draw
        case uiTap
    }

    private var players: [SFX: AVAudioPlayer] = [:]
    private let hapticImpact = UIImpactFeedbackGenerator(style: .light)
    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    private let hapticNotify = UINotificationFeedbackGenerator()

    private init() {
        // 预热触觉引擎，首次触发零延迟
        hapticImpact.prepare()
        hapticMedium.prepare()
        for sfx in SFX.allCases {
            if let url = Bundle.main.url(forResource: sfx.rawValue, withExtension: "wav") {
                let p = try? AVAudioPlayer(contentsOf: url)
                p?.prepareToPlay()
                p?.volume = 0.9
                players[sfx] = p
            }
        }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    func play(_ sfx: SFX) {
        guard UserDefaults.standard.object(forKey: "soundOn") == nil
                || UserDefaults.standard.bool(forKey: "soundOn") else { return }
        let p = players[sfx]
        if p?.isPlaying == true { p?.currentTime = 0 }
        p?.play()
    }

    func haptic(_ style: HapticStyle) {
        guard UserDefaults.standard.object(forKey: "hapticsOn") == nil
                || UserDefaults.standard.bool(forKey: "hapticsOn") else { return }
        switch style {
        case .place: hapticImpact.impactOccurred(intensity: 0.7)
        case .capture: hapticMedium.impactOccurred(intensity: 1.0)
        case .uiTap: hapticImpact.impactOccurred(intensity: 0.4)
        case .win: hapticNotify.notificationOccurred(.success)
        case .lose: hapticNotify.notificationOccurred(.error)
        case .draw: hapticNotify.notificationOccurred(.warning)
        }
    }

    /// 落子反馈（音 + 触觉），capture 判定由调用方给出
    func moveFeedback(gameID: GameID, capture: Bool) {
        let sfx: SFX
        switch gameID {
        case .go, .gomoku, .reversi: sfx = .placeStone
        default: sfx = .placeWood
        }
        if capture {
            play(.capture)
            haptic(.capture)
        } else {
            play(sfx)
            haptic(.place)
        }
    }
}
