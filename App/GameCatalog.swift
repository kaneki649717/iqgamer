import SwiftUI
import BoardCore

/// 棋种在 App 里的展示信息
struct GameCatalogItem: Identifiable, Hashable {
    let id: GameID
    let name: String
    let subtitle: String
    let symbol: String          // SF Symbol

    static let all: [GameCatalogItem] = [
        .init(id: .go,       name: "围棋",     subtitle: "9 / 13 / 19 路",      symbol: "circle.circle"),
        .init(id: .shogi,    name: "将棋",     subtitle: "持驹打入",            symbol: "crown.fill"),
        .init(id: .xiangqi,  name: "中国象棋", subtitle: "楚河汉界",            symbol: "rosette"),
        .init(id: .chess,    name: "国际象棋", subtitle: "易位 · 升变",         symbol: "crown"),
        .init(id: .draughts, name: "国际跳棋", subtitle: "10×10 · 飞王",       symbol: "arrow.down.forward.square"),
        .init(id: .gomoku,   name: "五子棋",   subtitle: "先手连五",            symbol: "circle.grid.3x3.fill"),
        .init(id: .reversi,  name: "黑白棋",   subtitle: "翻转对决",            symbol: "circle.lefthalf.filled"),
    ]
}
