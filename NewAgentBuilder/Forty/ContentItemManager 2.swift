//
//  ContentItemManager 2.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 6/1/25.
//

import Foundation
import FirebaseFirestore


enum ContentType: String, CaseIterable, Codable, Equatable {
    case quote = "Quote"
    case note = "Note"
    case study = "Study"
    case bookNote = "Book Note"
    case bibleVerse = "Bible Verse"
    case bibleStory = "Bible Story"
}

struct ContentItem: Identifiable, Equatable, Hashable {
    var id: String { docID }
    var docID: String
    var contentType: ContentType
    var text: String
    var author: String?
    var source: String?
    var summary: String?
    var tags: [String]?

    // Standard initializer
    init(docID: String = UUID().uuidString,
            contentType: ContentType,
            text: String,
            author: String? = nil,
            source: String? = nil,
            summary: String? = nil,
           
            tags: [String]? = nil) {
           self.docID = docID
           self.contentType = contentType
           self.text = text
           self.author = author
           self.source = source
           self.summary = summary
           
           self.tags = tags
       }

    // Initializer from Firestore DocumentSnapshot
    init?(document: DocumentSnapshot) {
        guard let data = document.data() else { return nil }
        
        self.docID = document.documentID
        self.contentType = ContentType(rawValue: data["contentType"] as? String ?? "") ?? .note
        self.text = data["text"] as? String ?? ""
        self.author = data["author"] as? String
        self.source = data["source"] as? String
        self.summary = data["summary"] as? String
        self.tags = data["tags"] as? [String]
    }

    // Convert to Firestore data format
    func toDictionary() -> [String: Any] {
        return [
            "contentType": contentType.rawValue,
            "text": text,
            "author": author ?? "",
            "source": source ?? "",
            "summary": summary ?? "",
            "tags": tags ?? []
        ]
    }
    
    static func == (lhs: ContentItem, rhs: ContentItem) -> Bool {
         lhs.docID == rhs.docID
     }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(docID)
    }
}

class ContentItemManager {
    static let shared = ContentItemManager()
    private let db = Firestore.firestore()
    private let collection = "contentItems" // Firestore Collection Name
    
    // 🔹 Create a Content Item (CREATE)
    func createContentItem(contentType: ContentType, text: String, author: String? = nil, source: String? = nil, summary: String? = nil, completion: @escaping (Bool) -> Void) {
        let contentItem = ContentItem(contentType: contentType, text: text, author: author, source: source, summary: summary)
        
        db.collection(collection).document(contentItem.docID).setData(contentItem.toDictionary()) { error in
            if let error = error {
                print("❌ Error creating Content Item: \(error.localizedDescription)")
                completion(false)
            } else {
                print("✅ Content Item Created Successfully")
                completion(true)
            }
        }
    }
}
