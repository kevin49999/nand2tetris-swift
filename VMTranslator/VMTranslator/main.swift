//
//  main.swift
//  VMTranslator
//
//  Created by Kevin Johnson on 4/8/21.
//

import Foundation

var labels = 0

func vmToAsm() {
    let argCount = CommandLine.argc
    guard argCount == 2 else {
        print("Pass in the path to one Hack assembly file")
        return
    }

    let codeWriter = CodeWriter()
    let path = CommandLine.arguments[1]
    let url = URL(fileURLWithPath: path)
    var asmString = ""
    var oneFile = false
    do {
        let fileName = url.deletingPathExtension().pathComponents.last!
        if let inputFile = try stringIfVmFile(url: url) {
            oneFile = true
            addFile(
                inputFile: inputFile,
                asmString: &asmString,
                fileName: fileName,
                codeWriter: codeWriter
            )
        } else {
            // directory tests need bootstrap code
            codeWriter.initStackPointer(result: &asmString)
            codeWriter.call(result: &asmString, arg1: "Sys.init", arg2: "0")
            let items = try FileManager.default.contentsOfDirectory(atPath: path)
            for item in items {
                let url = URL(fileURLWithPath: path.appending(item))
                if let inputFile = try stringIfVmFile(url: url) {
                    // do only really use for static though
                    let fileName = url.deletingPathExtension().pathComponents.last!
                    addFile(
                        inputFile: inputFile,
                        asmString: &asmString,
                        fileName: fileName,
                        codeWriter: codeWriter
                    )
                }
            }
        }
    } catch {
        print(error)
        return
    }

    let asmUrl: URL
    if oneFile {
        asmUrl = url.deletingPathExtension().appendingPathExtension("asm")
    } else {
        let directoryName = url.deletingPathExtension().pathComponents.last!
        asmUrl = url.appendingPathComponent("/\(directoryName)").appendingPathExtension("asm")
    }
    FileManager.default.createFile(
        atPath: asmUrl.path,
        contents: asmString.data(using: .ascii)
    )
}

func addFile(inputFile: String, asmString: inout String, fileName: String, codeWriter: CodeWriter) {
    let tokens = Lexer().tokenize(inputFile: inputFile)
    let parser = Parser(tokens: tokens)
    let codeWriter = CodeWriter()
    while parser.hasMoreCommands {
        var asmCommand = ""
        parser.advance()
        let c = parser.current!
        let t = parser.commandType(command: c)
        asmCommand.append("// \(c)\n")
        switch t {
        case .C_ARITHMETIC:
            let arg1 = parser.arg1(command: c)!
            switch arg1 {
            case "add":
                codeWriter.decrementStackPointer(result: &asmCommand)
                // store y value in D
                asmCommand.append("A=M\n")
                asmCommand.append("D=M\n")
                codeWriter.decrementStackPointer(result: &asmCommand)
                // x to y and store in D
                asmCommand.append("A=M\n")
                asmCommand.append("D=D+M\n")
                codeWriter.dToTopOfStack(result: &asmCommand)
                codeWriter.incrementStackPointer(result: &asmCommand)
            case "sub":
                codeWriter.decrementStackPointer(result: &asmCommand)
                // store -y value in D
                asmCommand.append("A=M\n")
                asmCommand.append("D=-M\n")
                codeWriter.decrementStackPointer(result: &asmCommand)
                // add x + (-y) and store in d
                asmCommand.append("A=M\n")
                asmCommand.append("D=D+M\n")
                codeWriter.dToTopOfStack(result: &asmCommand)
                codeWriter.incrementStackPointer(result: &asmCommand)
            case "neg":
                codeWriter.decrementStackPointer(result: &asmCommand)
                // store -y value in D
                asmCommand.append("A=M\n")
                asmCommand.append("D=-M\n")
                codeWriter.dToTopOfStack(result: &asmCommand)
                codeWriter.incrementStackPointer(result: &asmCommand)
            case "eq":
                codeWriter.decrementStackPointer(result: &asmCommand)
                // store first value in D
                asmCommand.append("A=M\n")
                asmCommand.append("D=M\n")
                codeWriter.decrementStackPointer(result: &asmCommand)
                // subtract second value from first
                asmCommand.append("A=M\n")
                asmCommand.append("D=D-M\n")
                // create jump label
                labels += 1
                let label = "LABEL\(labels)"
                asmCommand.append("@\(label)\n")
                asmCommand.append("D;JEQ\n")
                // do the non-jump, setting 0 to end of SP
                asmCommand.append("@SP\n")
                asmCommand.append("A=M\n")
                asmCommand.append("M=0\n")
                // don't continue on to -1 set if did the 0 set above
                labels += 1
                let label2 = "LABEL\(labels)"
                asmCommand.append("@\(label2)\n")
                asmCommand.append("0;JMP\n")
                // jeq jump label
                asmCommand.append("(\(label))\n")
                asmCommand.append("@SP\n")
                asmCommand.append("A=M\n")
                asmCommand.append("M=-1\n")
                // label for jumping over 1 set
                asmCommand.append("(\(label2))\n")
                codeWriter.incrementStackPointer(result: &asmCommand)
            case "gt":
                codeWriter.decrementStackPointer(result: &asmCommand)
                asmCommand.append("A=M\n")
                asmCommand.append("D=M\n")
                codeWriter.decrementStackPointer(result: &asmCommand)
                asmCommand.append("A=M\n")
                asmCommand.append("D=D-M\n")
                labels += 1
                let label = "LABEL\(labels)"
                asmCommand.append("@\(label)\n")
                asmCommand.append("D;JLT\n")
                asmCommand.append("@SP\n")
                asmCommand.append("A=M\n")
                asmCommand.append("M=0\n")
                labels += 1
                let label2 = "LABEL\(labels)"
                asmCommand.append("@\(label2)\n")
                asmCommand.append("0;JMP\n")
                asmCommand.append("(\(label))\n")
                asmCommand.append("@SP\n")
                asmCommand.append("A=M\n")
                asmCommand.append("M=-1\n")
                asmCommand.append("(\(label2))\n")
                codeWriter.incrementStackPointer(result: &asmCommand)
            case "lt":
                codeWriter.decrementStackPointer(result: &asmCommand)
                asmCommand.append("A=M\n")
                asmCommand.append("D=M\n")
                codeWriter.decrementStackPointer(result: &asmCommand)
                asmCommand.append("A=M\n")
                asmCommand.append("D=D-M\n")
                labels += 1
                let label = "LABEL\(labels)"
                asmCommand.append("@\(label)\n")
                asmCommand.append("D;JGT\n")
                asmCommand.append("@SP\n")
                asmCommand.append("A=M\n")
                asmCommand.append("M=0\n")
                labels += 1
                let label2 = "LABEL\(labels)"
                asmCommand.append("@\(label2)\n")
                asmCommand.append("0;JMP\n")
                asmCommand.append("(\(label))\n")
                asmCommand.append("@SP\n")
                asmCommand.append("A=M\n")
                asmCommand.append("M=-1\n")
                asmCommand.append("(\(label2))\n")
                codeWriter.incrementStackPointer(result: &asmCommand)
            case "and":
                codeWriter.decrementStackPointer(result: &asmCommand)
                // store y value in D
                asmCommand.append("A=M\n")
                asmCommand.append("D=M\n")
                codeWriter.decrementStackPointer(result: &asmCommand)
                // bitwise AND with x and stored y value
                asmCommand.append("A=M\n")
                asmCommand.append("D=D&M\n")
                codeWriter.dToTopOfStack(result: &asmCommand)
                codeWriter.incrementStackPointer(result: &asmCommand)
            case "or":
                codeWriter.decrementStackPointer(result: &asmCommand)
                // store y value in D
                asmCommand.append("A=M\n")
                asmCommand.append("D=M\n")
                codeWriter.decrementStackPointer(result: &asmCommand)
                // bitwise OR with x and stored y value
                asmCommand.append("A=M\n")
                asmCommand.append("D=D|M\n")
                codeWriter.dToTopOfStack(result: &asmCommand)
                codeWriter.incrementStackPointer(result: &asmCommand)
            case "not":
                codeWriter.decrementStackPointer(result: &asmCommand)
                // store !y value in D
                asmCommand.append("A=M\n")
                asmCommand.append("D=!M\n")
                codeWriter.dToTopOfStack(result: &asmCommand)
                codeWriter.incrementStackPointer(result: &asmCommand)
            default:
                break
            }
        case .C_PUSH:
            let arg1 = parser.arg1(command: c)!
            let arg2 = parser.arg2(command: c)!
            switch arg1 {
            case "constant":
                asmCommand.append("@\(arg2)\n")
                asmCommand.append("D=A\n")
                codeWriter.dToTopOfStack(result: &asmCommand)
                codeWriter.incrementStackPointer(result: &asmCommand)
            case "local":
                codeWriter.push(baseAddress: "LCL", offset: arg2, result: &asmCommand)
            case "argument":
                codeWriter.push(baseAddress: "ARG", offset: arg2, result: &asmCommand)
            case "this":
                codeWriter.push(baseAddress: "THIS", offset: arg2, result: &asmCommand)
            case "that":
                codeWriter.push(baseAddress: "THAT", offset: arg2, result: &asmCommand)
            case "temp":
                codeWriter.push(baseAddress: "5", offset: arg2, result: &asmCommand)
            case "pointer":
                switch arg2 {
                case "0":
                    asmCommand.append("@R3\n")
                    asmCommand.append("D=M\n")
                    asmCommand.append("@SP\n")
                    asmCommand.append("A=M\n")
                    asmCommand.append("M=D\n")
                    codeWriter.incrementStackPointer(result: &asmCommand)
                case "1":
                    asmCommand.append("@R4\n")
                    asmCommand.append("D=M\n")
                    asmCommand.append("@SP\n")
                    asmCommand.append("A=M\n")
                    asmCommand.append("M=D\n")
                    codeWriter.incrementStackPointer(result: &asmCommand)
                default:
                    preconditionFailure()
                }
            case "static":
                asmCommand.append("@\(fileName).\(arg2)\n")
                asmCommand.append("D=M\n")
                codeWriter.dToTopOfStack(result: &asmCommand)
                codeWriter.incrementStackPointer(result: &asmCommand)
            default:
                break
            }
        case .C_POP:
            let arg1 = parser.arg1(command: c)!
            let arg2 = parser.arg2(command: c)!
            switch arg1 {
            case "local":
                codeWriter.decrementStackPointer(result: &asmCommand)
                codeWriter.pop(baseAddress: "LCL", offset: arg2, result: &asmCommand)
            case "argument":
                codeWriter.decrementStackPointer(result: &asmCommand)
                codeWriter.pop(baseAddress: "ARG", offset: arg2, result: &asmCommand)
            case "this":
                codeWriter.decrementStackPointer(result: &asmCommand)
                codeWriter.pop(baseAddress: "THIS", offset: arg2, result: &asmCommand)
            case "that":
                codeWriter.decrementStackPointer(result: &asmCommand)
                codeWriter.pop(baseAddress: "THAT", offset: arg2, result: &asmCommand)
            case "temp":
                codeWriter.decrementStackPointer(result: &asmCommand)
                asmCommand.append("@\(arg2)\n")
                asmCommand.append("D=A\n")
                asmCommand.append("@5\n")
                // base address is 5, not value stored at 5
                asmCommand.append("D=D+A\n")
                asmCommand.append("@R13\n")
                asmCommand.append("M=D\n")
                asmCommand.append("@SP\n")
                asmCommand.append("A=M\n")
                asmCommand.append("D=M\n")
                asmCommand.append("@R13\n")
                asmCommand.append("A=M\n")
                asmCommand.append("M=D\n")
            case "pointer":
                switch arg2 {
                case "0":
                    codeWriter.decrementStackPointer(result: &asmCommand)
                    asmCommand.append("@SP\n")
                    asmCommand.append("A=M\n")
                    asmCommand.append("D=M\n")
                    asmCommand.append("@R3\n")
                    asmCommand.append("M=D\n")
                case "1":
                    codeWriter.decrementStackPointer(result: &asmCommand)
                    asmCommand.append("@SP\n")
                    asmCommand.append("A=M\n")
                    asmCommand.append("D=M\n")
                    asmCommand.append("@R4\n")
                    asmCommand.append("M=D\n")
                default:
                    preconditionFailure()
                }
            case "static":
                codeWriter.decrementStackPointer(result: &asmCommand)
                asmCommand.append("@SP\n")
                asmCommand.append("A=M\n")
                asmCommand.append("D=M\n")
                asmCommand.append("@\(fileName).\(arg2)\n")
                asmCommand.append("M=D\n")
            default:
                break
            }
        case .C_LABEL:
            let arg1 = parser.arg1(command: c)!
            asmCommand.append("(\(arg1))\n")
        case .C_IF_GOTO:
            // popping and storing value at top of stack
            codeWriter.decrementStackPointer(result: &asmCommand)
            asmCommand.append("@SP\n")
            asmCommand.append("A=M\n")
            asmCommand.append("D=M\n")
            let arg1 = parser.arg1(command: c)!
            asmCommand.append("@\(arg1)\n")
            // jump if topmost value not equal to 0
            asmCommand.append("D;JNE\n")
        case .C_GOTO:
            let arg1 = parser.arg1(command: c)!
            codeWriter.goto(address: arg1, result: &asmCommand)
        case .C_FUNCTION:
            let arg1 = parser.arg1(command: c)!
            asmCommand.append("(\(arg1))\n")
            let arg2 = parser.arg2(command: c)!
            let k = Int(arg2)!
            for _ in 0..<k {
                asmCommand.append("D=0\n")
                codeWriter.dToTopOfStack(result: &asmCommand)
                codeWriter.incrementStackPointer(result: &asmCommand)
            }
        case .C_RETURN:
            codeWriter.return(result: &asmCommand)
        case .C_CALL:
            let arg1 = parser.arg1(command: c)! // Main.function
            let arg2 = parser.arg2(command: c)! // 0
            codeWriter.call(result: &asmCommand, arg1: arg1, arg2: arg2)
        }
        asmString.append(asmCommand)
    }
}

func stringIfVmFile(url: URL) throws -> String? {
    if url.pathExtension == "vm" {
        return try String(contentsOf: url, encoding: .utf8)
    }
    return nil
}

vmToAsm()

// MARK: - Parser

class Parser {
    enum CommandType {
        case C_ARITHMETIC
        case C_PUSH, C_POP
        case C_LABEL
        case C_GOTO, C_IF_GOTO
        case C_FUNCTION
        case C_RETURN
        case C_CALL
    }

    var hasMoreCommands: Bool { !tokens.isEmpty }
    private(set) var current: [Token]?
    private var tokens: [[Token]]

    init(tokens: [[Token]]) {
        self.tokens = tokens
    }

    func advance() {
        self.current = tokens.removeFirst()
    }

    func commandType(command: [Token]) -> CommandType {
        let first = command.first!
        switch first {
        case .word(let str):
            switch str {
            case "push":
                return .C_PUSH
            case "pop":
                return .C_POP
            case "label":
                return .C_LABEL
            case "add", "sub", "neg", "eq", "gt", "lt", "and", "or", "not":
                return .C_ARITHMETIC
            case "if-goto":
                return .C_IF_GOTO
            case "goto":
                return .C_GOTO
            case "function":
                return .C_FUNCTION
            case "return":
                return .C_RETURN
            case "call":
                return .C_CALL
            default:
                preconditionFailure()
            }
        case .number:
            preconditionFailure("Invalid message")
        case .comment:
            break
        }
        return .C_ARITHMETIC
    }

    /// in case of `C_ARITHMETIC` the command itself is returned
    func arg1(command: [Token]) -> String? {
        let c = commandType(command: command)
        switch c {
        case .C_ARITHMETIC:
            switch command.first! {
            case .word(let str):
                return str
            case .number, .comment:
                print("arithmetic command should return word for arg1", command)
            }
        case .C_PUSH, .C_POP, .C_LABEL, .C_GOTO, .C_IF_GOTO, .C_FUNCTION, .C_CALL:
            switch command[1] {
            case .word(let str):
                return str
            case .number, .comment:
                print("push, pop, etc. command should return word for arg1", command)
            }
        case .C_RETURN:
            print("arg1 should not be called if the current command is C_RETURN")
        }
        return nil
    }

    /// should only return if the  command is
    /// `C_PUSH`, `C_POP`, `C_FUNCTION`, `C_CALL` (call ex: call Class1.get 0)
    func arg2(command: [Token]) -> String? {
        let c = commandType(command: command)
        switch c {
        case .C_PUSH, .C_POP, .C_FUNCTION, .C_CALL:
            switch command[2] {
            case .number(let num):
                return num
            case .word, .comment:
                print("arg2 should be a number for command: \(command)")
                return nil
            }
        case .C_RETURN, .C_ARITHMETIC, .C_LABEL, .C_GOTO, .C_IF_GOTO:
            print("arg2 should not be called for commandType: \(c)")
            return nil
        }
    }
}

// MARK: - Token

enum Token {
    case word(String)
    case number(String)
    case comment
}

// MARK: - Lexer

// TODO: Do with regular expresions for matching
class Lexer {
    /// returns an array of tokens for each line
    func tokenize(inputFile: String) -> [[Token]] {
        var result = [[Token]]()
        let lines = inputFile.components(separatedBy: "\n")
        for line in lines {
            let chars = Array(line)
            var tokens = [Token]()
            var current = ""
            for i in 0..<chars.count {
                if chars[i] == " " {
                    if let token = detectToken(from: current) {
                        tokens.append(token)
                    }
                    current = ""
                } else {
                    current.append(chars[i])
                }
            }
            if let token = detectToken(from: current) { tokens.append(token) }
            /// cleanup comments pass (not best place but w/e)
            var new = [Token]()
            outer: for t in tokens {
                switch t {
                case .word, .number:
                    new.append(t)
                case .comment:
                    break outer
                }
            }
            /// no empty lines
            if !new.isEmpty { result.append(new) }
        }
        return result
    }

    func detectToken(from word: String) -> Token? {
        if Int(word) != nil {
            return .number(word)
        } else if word == "//" {
            return .comment
        } else if !word.isEmpty {
            return .word(word)
        }
        return nil
    }
}

// MARK: CodeWriter

class CodeWriter {
    func initStackPointer(result: inout String) {
        result.append("@256\n")
        result.append("D=A\n")
        result.append("@SP\n")
        result.append("M=D\n")
    }

    /// pop local x: pop off the stack and set the value of local x equal to it
    func pop(baseAddress: String, offset: String, result: inout String) {
        if offset != "0" {
            result.append("@\(offset)\n")
            result.append("D=A\n")
            result.append("@\(baseAddress)\n")
            result.append("A=M\n")
            result.append("D=D+A\n")
        } else {
            result.append("@\(baseAddress)\n")
            result.append("D=M\n")
        }
        // now storing the location of base + offset in R13
        result.append("@R13\n")
        result.append("M=D\n")
        // storing value at top of stack in D
        result.append("@SP\n")
        result.append("A=M\n")
        result.append("D=M\n")
        // now set location of base + offset = to top of stack value
        result.append("@R13\n")
        result.append("A=M\n")
        result.append("M=D\n")
    }

    /// push local x: push the value at local x to the top of the stack
    func push(baseAddress: String, offset: String,  result: inout String) {
        if offset != "0" {
            result.append("@\(offset)\n")
            result.append("D=A\n")
            result.append("@\(baseAddress)\n")
            result.append("A=M+D\n")
            result.append("D=M\n")
        } else {
            result.append("@\(baseAddress)\n")
            result.append("A=M\n")
            result.append("D=M\n")
        }
        // push value of base + offset
        result.append("@SP\n")
        result.append("A=M\n")
        result.append("M=D\n")
        incrementStackPointer(result: &result)
    }

    func incrementStackPointer(result: inout String) {
        result.append("@SP\n")
        result.append("M=M+1\n")
    }

    func decrementStackPointer(result: inout String) {
        result.append("@SP\n")
        result.append("M=M-1\n")
    }

    func dToTopOfStack(result: inout String) {
        result.append("@SP\n")
        result.append("A=M\n")
        result.append("M=D\n")
    }

    func goto(address: String, result: inout String) {
        result.append("@\(address)\n")
        result.append("0;JMP\n") // jump
    }

    func call(result: inout String, arg1: String, arg2: String) {
        // push return address (using label below)
        labels += 1
        let label = "LABEL\(labels)"
        result.append("@\(label)\n")
        result.append("D=A\n")
        dToTopOfStack(result: &result)
        incrementStackPointer(result: &result)
        // save LCL of the calling function
        result.append("@R1\n")
        result.append("D=M\n")
        dToTopOfStack(result: &result)
        incrementStackPointer(result: &result)
        // save ARG of the calling function
        result.append("@R2\n")
        result.append("D=M\n")
        dToTopOfStack(result: &result)
        incrementStackPointer(result: &result)
        // save THIS of the calling function
        result.append("@R3\n")
        result.append("D=M\n")
        dToTopOfStack(result: &result)
        incrementStackPointer(result: &result)
        // save THAT of the calling function
        result.append("@R4\n")
        result.append("D=M\n")
        dToTopOfStack(result: &result)
        incrementStackPointer(result: &result)
        // ARG = SP - n - 5
        let int = Int(arg2)! + 5
        result.append("@\(int)\n")
        result.append("D=A\n")
        result.append("@R0\n")
        result.append("A=M\n")
        result.append("AD=A-D\n")
        result.append("@R2\n")
        result.append("M=D\n")
        // LCL = SP
        result.append("@SP\n")
        result.append("D=M\n")
        result.append("@R1\n")
        result.append("M=D\n")
        // goto f
        goto(address: arg1, result: &result)
        // declare a label for the return address
        result.append("(\(label))\n")
    }

    func `return`(result: inout String) {
        // FRAME = LCL (frame is temporary var)
        result.append("@LCL\n")
        result.append("D=M\n")
        result.append("@R13\n")
        result.append("M=D\n")
        // put the return-address in a temp var
        // RET = *(FRAME - 5)
        result.append("@5\n")
        result.append("A=D-A\n")
        result.append("D=M\n")
        result.append("@R14\n")
        result.append("M=D\n")
        // reposition the return value for the caller (pop argument 0)
        decrementStackPointer(result: &result)
        result.append("@ARG\n")
        result.append("D=M\n")
        result.append("@R15\n")
        result.append("M=D\n")
        result.append("@SP\n")
        result.append("A=M\n")
        result.append("D=M\n")
        result.append("@R15\n")
        result.append("A=M\n")
        result.append("M=D\n")
        // restore sp of the caller
        result.append("@ARG\n")
        result.append("D=M\n")
        result.append("@SP\n")
        result.append("M=D+1\n")
        // restore THAT of the caller (THAT = *(FRAME - 1))
        result.append("@R13\n")
        result.append("D=M\n")
        result.append("@1\n")
        result.append("A=D-A\n")
        result.append("D=M\n")
        result.append("@THAT\n")
        result.append("M=D\n")
        // restore THIS of the caller
        result.append("@R13\n")
        result.append("D=M\n")
        result.append("@2\n")
        result.append("A=D-A\n")
        result.append("D=M\n")
        result.append("@THIS\n")
        result.append("M=D\n")
        // restore ARG of the caller
        result.append("@R13\n")
        result.append("D=M\n")
        result.append("@3\n")
        result.append("A=D-A\n")
        result.append("D=M\n")
        result.append("@ARG\n")
        result.append("M=D\n")
        // restore LCL of the caller
        result.append("@R13\n")
        result.append("D=M\n")
        result.append("@4\n")
        result.append("A=D-A\n")
        result.append("D=M\n")
        result.append("@LCL\n")
        result.append("M=D\n")
        // goto ret
        result.append("@R14\n")
        result.append("A=M\n")
        result.append("0;JMP\n")
    }
}
