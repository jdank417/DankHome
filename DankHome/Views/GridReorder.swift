//
//  GridReorder.swift
//  DankHome
//

import Foundation

enum GridReorder {
    /// Sorts items by a saved order; anything not in it keeps its original place at the end.
    static func sorted<T>(_ items: [T], by order: [String], key: (T) -> String) -> [T] {
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return items.enumerated()
            .sorted { (rank[key($0.element)] ?? .max, $0.offset) < (rank[key($1.element)] ?? .max, $1.offset) }
            .map(\.element)
    }
}
