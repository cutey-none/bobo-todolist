import Foundation
import SwiftData

@Model
final class ProgressEntry {
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var text: String
    @Attribute(.externalStorage) var imageData: Data?
    var createdAt: Date

    init(taskID: UUID, text: String, imageData: Data? = nil, createdAt: Date = Date()) {
        self.id = UUID()
        self.taskID = taskID
        self.text = text
        self.imageData = imageData
        self.createdAt = createdAt
    }
}
