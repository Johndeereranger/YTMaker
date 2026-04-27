//
//  StringExtensions.swift
//  NewAgentBuilder
//
//  Created by Byron Smith on 5/10/25.
//

import Foundation
import CryptoKit

extension String {
    func normalized() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func sha256ToUUID() -> String {
        let data = Data(self.utf8)
        let hashBytes = Array(SHA256.hash(data: data)) // ✅ convert to [UInt8]
        let uuid = UUID(uuid: (
            hashBytes[0], hashBytes[1], hashBytes[2], hashBytes[3],
            hashBytes[4], hashBytes[5], hashBytes[6], hashBytes[7],
            hashBytes[8], hashBytes[9], hashBytes[10], hashBytes[11],
            hashBytes[12], hashBytes[13], hashBytes[14], hashBytes[15]
        ))
        return uuid.uuidString
    }
}
