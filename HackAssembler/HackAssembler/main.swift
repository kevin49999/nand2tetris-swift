//
//  main.swift
//  HackAssembler
//
//  Created by Kevin Johnson on 3/27/21.
//

import Foundation

func assemble() {
    let argCount = CommandLine.argc

    guard argCount == 2 else {
        print("Pass in the path to one Hack assembly file")
        return
    }

    let asmPath = CommandLine.arguments[1] // should be "Name.asm"
    let asmUrl = URL(fileURLWithPath: asmPath)
    guard asmUrl.pathExtension == "asm" else {
        print("File does not contain the asm extension")
        return
    }

    var binString = ""
    do {
        let inputFile = try String(contentsOf: asmUrl, encoding: .utf8)
        let symbolTable = SymbolTable()
        let first = Parser(inputFile: inputFile)
        var romAddress: UInt16 = 0x0000
        while first.hasMoreCommands {
            first.advance()
            let current = first.current!
            print(current)
            switch first.commandType(for: current) {
            case .A_COMMAND, .C_COMMAND:
                romAddress += 1
            case .L_COMMAND:
                switch first.symbol(for: current) {
                case .decimal:
                    preconditionFailure()
                case .string(let sym):
                    symbolTable.addEntry(symbol: sym, address: romAddress)
                }
            }
        }

        let second = Parser(inputFile: inputFile)
        var ramAddress: UInt16 = 0x0010
        while second.hasMoreCommands {
            second.advance()
            let current = second.current!
            var instruction: UInt16 = 0b0000000000000000
            switch second.commandType(for: current) {
            case .A_COMMAND:
                let symbol = second.symbol(for: current)
                switch symbol {
                case .decimal(let decimal):
                    instruction = instruction | decimal
                case .string(let sym):
                    if !symbolTable.contains(symbol: sym) {
                        symbolTable.addEntry(symbol: sym, address: ramAddress)
                        ramAddress += 1
                    }
                    let address = symbolTable.getAddress(symbol: sym)!
                    instruction = instruction | address
                }
                if !binString.isEmpty { binString.append("\n") }
                binString.append(instruction.binaryString())
            case .C_COMMAND:
                instruction = instruction | 0b1110000000000000
                instruction = instruction | Code.comp(mnemonic: second.comp(for: current))
                instruction = instruction | Code.dest(mnemonic: second.dest(for: current))
                instruction = instruction | Code.jump(mnemonic: second.jump(for: current))
                if !binString.isEmpty { binString.append("\n") }
                binString.append(instruction.binaryString())
            case .L_COMMAND:
                break
            }
        }

        print("---")
        print(binString)
        let hackUrl = asmUrl.deletingPathExtension().appendingPathExtension("hack")
        FileManager.default.createFile(
            atPath: hackUrl.path,
            contents: binString.data(using: .ascii)
        )
    } catch {
        print("Couldn't read: \(error)")
    }
}

assemble() // 🚀

// MARK: - Parser

class Parser {
    enum CommandType {
        case A_COMMAND, C_COMMAND, L_COMMAND
    }

    var hasMoreCommands: Bool { return !commands.isEmpty }
    private(set) var current: String?
    private var commands: [String]

    init(inputFile: String) {
        self.commands = []
        let lines = inputFile.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("//") {
                continue
            }
            if line.isEmpty {
                continue
            }
            commands.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func advance() {
        guard hasMoreCommands else { return }
        current = commands.removeFirst()
    }

    func commandType(for command: String) -> CommandType {
        if command.hasPrefix("@") {
            return .A_COMMAND
        } else if command.hasPrefix("(") {
            return .L_COMMAND
        }
        return .C_COMMAND
    }

    enum Symbol {
        case decimal(UInt16)
        case string(String)
    }

    /// Returns  symbol or decimal for command (only for A_COMMAND and L_COMMAND)
    func symbol(for command: String) -> Symbol {
        switch commandType(for: command) {
        case .A_COMMAND:
            let comp = command.components(separatedBy: "@")
            let val = comp[1]
            if let dec = UInt16(val) {
                return .decimal(dec)
            } else {
                return .string(val)
            }
        case .C_COMMAND:
            preconditionFailure("No symbol for c-commands")
        case .L_COMMAND:
            let chars = Array(command)
            var result = ""
            for i in 1..<command.count {
                if chars[i] == ")" { break }
                result.append(chars[i])
            }
            return .string(result)
        }
    }

    /// Returns the comp mnemonic for a c-command
    func comp(for command: String) -> String {
        guard case .C_COMMAND = commandType(for: command) else {
            preconditionFailure("comp only used for c-commands")
        }
        let chars = Array(command)
        var result = ""
        for c in chars {
            if c == " " {
                break
            }
            if c == ";" {
                return result
            }
            if c == "=" {
                result = ""
                continue // moving onto dest=comp style
            }
            result.append(c)
        }
        return result
    }

    /// Returns the dest mnemonic in the for a  c-command (no dest when jumping)
    func dest(for command: String) -> String? {
        guard case .C_COMMAND = commandType(for: command) else {
            preconditionFailure("dest only used for c-commands")
        }
        let chars = Array(command)
        var result = ""
        for c in chars {
            if c == "=" {
                return result
            }
            if c == ";" {
                break
            }
            result.append(c)
        }
        return nil
    }

    /// Returns the jump mnemonic in the current c-command
    func jump(for command: String) -> String? {
        guard case .C_COMMAND = commandType(for: command) else {
            preconditionFailure("jump only used for c-commands")
        }
        let chars = Array(command)
        var result = ""
        var appendToJump = false
        for c in chars {
            if c == "=" {
                break
            }
            if appendToJump {
                if c == " " {
                    return result
                } else {
                    result.append(c)
                }
            }
            if c == ";" {
                appendToJump = true
            }
        }
        return (result.isEmpty) ? nil : result
    }
}

// MARK: - Code

struct Code {
    /// returns 16 bits with the a bit and 6 c bits flipped with the others set to 0
    static func comp(mnemonic: String) -> UInt16 {
        switch mnemonic {
        case "0":
            return 0b0000101010000000
        case "1":
            return 0b0000111111000000
        case "-1":
            return 0b0000111010000000
        case "D":
            return 0b0000001100000000
        case "A":
            return 0b0000110000000000
        case "M":
            return 0b0001110000000000
        case "!D":
            return 0b0000001101000000
        case "!A":
            return 0b0000110001000000
        case "!M":
            return 0b0001110001000000
        case "D+1":
            return 0b0000011111000000
        case "A+1":
            return 0b0000110111000000
        case "M+1":
            return 0b0001110111000000
        case "D-1":
            return 0b0000001110000000
        case "A-1":
            return 0b0000110010000000
        case "M-1":
            return 0b0001110010000000
        case "D+A":
            return 0b0000000010000000
        case "D+M":
            return 0b0001000010000000
        case "D-A":
            return 0b0000010011000000
        case "D-M":
            return 0b0001010011000000
        case "A-D":
            return 0b0000000111000000
        case "M-D":
            return 0b0001000111000000
        case "D&A":
            return 0b0000000000000000
        case "D&M":
            return 0b0001000000000000
        case "D|A":
            return 0b0000010101000000
        case "D|M":
            return 0b0001010101000000
        default:
            preconditionFailure()
        }
    }

    /// returns 16 bits with the 3 d bits flipped with the others set to 0
    static func dest(mnemonic: String?) -> UInt16 {
        if let mnemonic = mnemonic {
            switch mnemonic {
            case "M":
                return 0b0000000000001000
            case "D":
                return 0b0000000000010000
            case "MD":
                return 0b0000000000011000
            case "A":
                return 0b0000000000100000
            case "AM":
                return 0b0000000000101000
            case "AD":
                return 0b0000000000110000
            case "AMD":
                return 0b0000000000111000
            default:
                preconditionFailure()
            }
        } else {
            return 0b0000000000000000
        }
    }

    /// returns 16 bits, with the 3 j bits flipped with the others set to 0
    static func jump(mnemonic: String?) -> UInt16 {
        if let mnemonic = mnemonic {
            switch mnemonic {
            case "JGT":
                return 0b0000000000000001
            case "JEQ":
                return 0b0000000000000010
            case "JGE":
                return 0b0000000000000011
            case "JLT":
                return 0b0000000000000100
            case "JNE":
                return 0b0000000000000101
            case "JLE":
                return 0b0000000000000110
            case "JMP":
                return 0b0000000000000111
            default:
                preconditionFailure()
            }
        } else {
            return 0b0000000000000000
        }
    }
}

// MARK: - SymbolTable

class SymbolTable {
    private var hash: [String: UInt16]

    init(hash: [String: UInt16] = SymbolTable.predifinedSymbols) {
        self.hash = hash
    }

    func addEntry(symbol: String, address: UInt16) {
        hash[symbol] = address
    }

    func contains(symbol: String) -> Bool {
        return hash[symbol] != nil
    }

    func getAddress(symbol: String) -> UInt16? {
        return hash[symbol]
    }
}

extension SymbolTable {
    static let predifinedSymbols: [String: UInt16] = [
        "SP": 0x0000,
        "LCL": 0x0001,
        "ARG": 0x0002,
        "THIS": 0x0003,
        "THAT": 0x0004,
        "R0": 0x0000,
        "R1": 0x0001,
        "R2": 0x0002,
        "R3": 0x0003,
        "R4": 0x0004,
        "R5": 0x0005,
        "R6": 0x0006,
        "R7": 0x0007,
        "R8": 0x0008,
        "R9": 0x0009,
        "R10": 0x000a,
        "R11": 0x000b,
        "R12": 0x000c,
        "R13": 0x000d,
        "R14": 0x000e,
        "R15": 0x000f,
        "SCREEN": 0x4000,
        "KBD": 0x6000,
    ]
}

/// modified https://stackoverflow.com/questions/26181221/how-to-convert-a-decimal-number-to-binary-in-swift
extension UInt16 {
    func binaryString() -> String {
        let binaryString = String(self, radix: 2)
        if leadingZeroBitCount > 0 {
            let result = String(repeating: "0", count: leadingZeroBitCount)
            if result.count == 16 {
                /// maybe more elegant solution, but would return 17 bits for 0 otherwise
                return result
            }
            return "\(result)\(binaryString)"
        }
        return binaryString
    }
}
