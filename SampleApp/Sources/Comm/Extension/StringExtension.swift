//
//  StringExtension.swift
//  SampleApp
//
//  Created by childc on 2021/02/26.
//  Copyright © 2021 sktelecom. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

// MARK: - Regular Expression
extension String {
    func matchingStrings(regex: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: regex, options: []) else { return [] }
        let nsString = self as NSString
        let results  = regex.matches(in: self, options: [], range: NSRange(location: 0, length: nsString.length))
        return results.map { result in
            (0..<result.numberOfRanges).map { result.range(at: $0).location != NSNotFound
                ? nsString.substring(with: result.range(at: $0))
                : ""
            }
        }
    }
}

// MARK: - remove emoji
extension String {
    var stringWithoutEmoji: String {
        return String(self.filter { !$0.isEmoji() })
    }
}

extension Character {
    fileprivate func isEmoji() -> Bool {
        switch self {
        case Character(UnicodeScalar(UInt32(0x1F600))!)...Character(UnicodeScalar(UInt32(0x1F64F))!),
             Character(UnicodeScalar(UInt32(0x1F300))!)...Character(UnicodeScalar(UInt32(0x1F5FF))!),
             Character(UnicodeScalar(UInt32(0x1F680))!)...Character(UnicodeScalar(UInt32(0x1F6FF))!),
             Character(UnicodeScalar(UInt32(0x2600))!)...Character(UnicodeScalar(UInt32(0x26FF))!),
             Character(UnicodeScalar(UInt32(0x2700))!)...Character(UnicodeScalar(UInt32(0x27BF))!),
             Character(UnicodeScalar(UInt32(0xFE00))!)...Character(UnicodeScalar(UInt32(0xFE0F))!):
            return true
            
        default:
            return false
        }
    }
}
