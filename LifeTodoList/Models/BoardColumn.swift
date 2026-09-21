import Foundation
import SwiftData

@Model
final class BoardColumn {
    var id: UUID
    var name: String
    var order: Int
    var symbolName: String

    init(id: UUID = UUID(), name: String, order: Int, symbolName: String = "square.grid.2x2") {
        self.id = id
        self.name = name
        self.order = order
        self.symbolName = symbolName
    }
}
