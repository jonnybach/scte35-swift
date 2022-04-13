//
//  BitConverter.swift
//  SCTE35Converter
//
//  Created by Joe Lucero on 5/29/19.
//  Copyright © 2019 Real Eyes Media. All rights reserved.
//

import Foundation

class BitConverter {
    /// Will return an array of 8 bits
    /// i.e. input = 15, output = [0, 0, 0, 0, 1, 1, 1, 1]
    static func bits(fromByte byte: UInt8) -> [Bit] {
        var byte = byte
        var bits = [Bit](repeating: .zero, count: 8)
        for i in 0..<8 {
            let currentBit = byte & 0x01
            if currentBit != 0 {
                bits[i] = .one
            }

            byte >>= 1
        }
        return bits.reversed()
    }

    static func bits(fromData data: Data) -> [Bit] {
        var bits: [Bit] = []
        for byte in data {
            let x = BitConverter.bits(fromByte: byte)
            bits.append(contentsOf: x)
        }
        return bits
    }

    static func integer(fromBits bits: [Bit]) -> Int {
        var multiplier = 1
        var total = 0
        var bits = bits

        while !bits.isEmpty {
            guard let bit = bits.popLast() else { continue }
            total += bit.rawValue * multiplier
            multiplier *= 2
        }

        return total
    }

    static func string(fromBits bits: [Bit]) -> String? {
        guard bits.count % 8 == 0 else { return nil }
        let count = bits.count

        let bytes = stride(from: 0, to: count, by: 8).map { (last) -> [Bit] in
            return Array(bits[last..<last+8])
        }

        var string: String = ""
        for byte in bytes {
            let intValueOfChar = integer(fromBits: byte)
            guard let uni = UnicodeScalar(intValueOfChar) else { return nil }
            let char = Character(uni)
            string.append(char)
        }

        return string
    }

    static func smpteString(fromBits bits: [Bit]) -> String? {
        guard bits.count == 256 else { return nil }
        let nibbles = stride(from: 0, to: bits.count, by: 4).map { (last) -> [Bit] in
            return Array(bits[last..<last+4])
        }

        var stringToReturn = ""
        let finalIndex = nibbles.count - 1
        for (index, nibble) in nibbles.enumerated() {
            let intValue = BitConverter.integer(fromBits: nibble)
            let char = String(format: "%01X", intValue)
            stringToReturn.append(char)
            if index != 0 && index != finalIndex && index % 8 == 7 {
                stringToReturn.append(".")
            }
        }

        return stringToReturn
    }

    static func isanString(fromBits bits: [Bit]) -> String? {
        guard bits.count == 96 else { return nil }
        let nibbles = stride(from: 0, to: bits.count, by: 4).map { (last) -> [Bit] in
            return Array(bits[last..<last+4])
        }

        var stringToReturn = ""
        let indicesForDash = [3, 7, 11, 19]
        for (index, nibble) in nibbles.enumerated() {
            let intValue = BitConverter.integer(fromBits: nibble)
            let char = String(format: "%01X", intValue)
            stringToReturn.append(char)
            // TODO: - use page 9 of SCTE Documentation [ISO 15706-2] to find check characters
            if indicesForDash.contains(index) {
                stringToReturn.append("-")
            } else if index == 15 {
                stringToReturn.append("-?-")
            } else if index == 23 {
                stringToReturn.append("-?")
            }
        }
        return stringToReturn
    }

    static func eidrString(fromBits bits: [Bit]) -> String? {
        guard bits.count == 96 else { return nil }
        let firstTwoBytes = Array(bits[0..<16])
        let integerValue = BitConverter.integer(fromBits: firstTwoBytes)
        let nibbles = stride(from: 16, to: bits.count, by: 4).map { (last) -> [Bit] in
            return Array(bits[last..<last+4])
        }

        var stringToReturn = "10.\(integerValue)/"
        let indicesForDash = Set<Int>(arrayLiteral: 3, 7, 11, 15)
        for (index, nibble) in nibbles.enumerated() {
            let intValue = BitConverter.integer(fromBits: nibble)
            let char = String(format: "%01X", intValue)
            stringToReturn.append(char)
            if indicesForDash.contains(index) {
                stringToReturn.append("-")
            }
        }
        // TODO: - use page 9 of SCTE Documentation [EIDR ID FORMAT] to find check character
        return stringToReturn + "-?"
    }

    static func hexString(fromBits bits: [Bit]) -> String {
        let binaryString = bits.reduce("") { return $0 + $1.description }
        guard let binaryAsInt = Int(binaryString, radix: 2) else { return "" }
        return "0x" + String(binaryAsInt, radix: 16).uppercased()
    }

    static func convertToBase64String(hexString: String) -> String? {
        var hexString = hexString
        if let index = hexString.firstIndex(of: "x") {
            hexString.removeSubrange(hexString.startIndex...index)
        }

        let length = hexString.count / 2
        var data = Data(capacity: length)
        for i in 0..<length {
            let j = hexString.index(hexString.startIndex, offsetBy: i*2)
            let k = hexString.index(j, offsetBy: 2)
            let bytes = hexString[j..<k]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
        }
        return data.base64EncodedString()
    }

    // Tribune Media Systems Program ID.  12 characters; 2 alpha characters followed by 10 numbers
    static func tidString(from bits: [Bit]) -> String? {
        let decodedString = BitConverter.string(fromBits: bits)
        guard
            let decodedString = decodedString,
            decodedString.count == 12
        else {
            return nil
        }

        // Check that string follows TID (Tribune Media Systems Program identifier) format rules
        for (index, char) in decodedString.enumerated() {
            switch index {
            case 0..<2:
                if !char.isLetter { return nil }
            case 2..<12:
                if !char.isNumber { return nil }
            default:
                return nil
            }
        }

        return decodedString
    }
}
