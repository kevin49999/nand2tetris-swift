//
//  main.swift
//  JackCompiler
//
//  Created by Kevin Johnson on 5/16/21.
//

import Foundation

func jackToXml() {
    let argCount = CommandLine.argc
    guard argCount == 2 else {
        print("Pass in the path to one Jack file or directory")
        return
    }

    let path = CommandLine.arguments[1]
    let url = URL(fileURLWithPath: path)
    do {
        let fileName = url.deletingPathExtension().pathComponents.last!
        if let inputFile = try stringIfJackFile(url: url) {
            // single file
            addFile(
                inputFile: inputFile,
                fileName: fileName // save as fileName.xml in that directory
            )
        } else {
            // directory
            let items = try FileManager.default.contentsOfDirectory(atPath: path)
            for item in items {
                let url = URL(fileURLWithPath: path.appending(item))
                if let inputFile = try stringIfJackFile(url: url) {
                    let fileName = url.deletingPathExtension().pathComponents.last!
                    addFile(
                        inputFile: inputFile,
                        fileName: fileName // ""
                    )
                }
            }
        }
    } catch {
        print(error)
        return
    }
}

func addFile(
    inputFile: String,
    fileName: String
) {
    // lex
    let tokenizer = JackTokenizer(inputFile: inputFile)
    tokenizer.tokenize()
    // parse
    let engine = CompilationEngine(tokenizer: tokenizer)
    engine.compileClass()
    let result = engine.xmlString
    print("---\n\(result)")
    // write
    FileManager.default.createFile(
        atPath: "\(fileName).xml",
        contents: result.data(using: .ascii)
    )
}

func stringIfJackFile(url: URL) throws -> String? {
    if url.pathExtension == "jack" {
        return try String(contentsOf: url, encoding: .utf8)
    }
    return nil
}

jackToXml()

// MARK: - Keyword

enum Keyword: String {
    case CLASS = "class", METHOD = "method", FUNCTION = "function"
    case CONSTRUCTOR = "constructor", INT = "int"
    case BOOLEAN = "boolean", CHAR = "char", VOID = "void"
    case VAR = "var", STATIC = "static", FIELD = "field", LET = "let"
    case DO = "do", IF = "if", ELSE = "else", WHILE = "while"
    case RETURN = "return", TRUE = "true", FALSE = "false"
    case NULL = "null", THIS = "this"

    var isStatement: Bool {
        switch self {
        case .LET, .IF, .WHILE, .DO, .RETURN:
            return true
        default:
            return false
        }
    }

    var isClassVarDecOrSubroutine: Bool {
        switch self {
        case .STATIC, .FIELD:
            /// classVarDec
            return true
            /// subroutine
        case .FUNCTION, .CONSTRUCTOR, .METHOD:
            return true
        default:
            return false
        }
    }
}

// MARK: - Symbol

enum Symbol: Character {
    /// {
    case openingBrace = "{"
    /// }
    case closingBrace = "}"
    /// [
    case openingBracket = "["
    /// ]
    case closingBracket = "]"
    /// (
    case openParanthesis = "("
    /// )
    case closingParanthesis = ")"
    case period = "."
    case comma = ","
    case semiColon = ";"
    case plusSign = "+"
    /// minusSign
    case minusSign = "-"
    case asterisk = "*"
    case slash = "/"
    case ampersand = "&"
    case verticalBar = "|"
    case lessThan = "<", greaterThan = ">"
    case equals = "="
    /// ~
    case tilde = "~"

    var xmlSymbol: String {
        switch self {
        case .lessThan:
            return "&lt;"
        case .greaterThan:
            return "&gt;"
        case .ampersand:
            return "&amp;"
        default:
            return "\(rawValue)"
        }
    }

    var isOp: Bool {
        switch self {
        case .plusSign, .minusSign, .asterisk, .slash, .ampersand, .verticalBar, .lessThan, .greaterThan, .equals:
            return true
        default:
            return false
        }
    }

    var isUnaryOp: Bool {
        switch self {
        case .tilde, .minusSign:
            return true
        default:
            return false
        }
    }
}

// MARK: - Comment

enum Comment: String {
    case restOfLine = "//"
    case multiLineOpen = "/**"
    case multiLineClose = "*/"
}

// MARK: - Token

enum Token {
    case KEYWORD(Keyword), SYMBOL(Symbol)
    case IDENTIFIER(String)
    case INT_CONST(Int), STRING_CONST(String)
    /// not quite accurate because won't be present in the xml, but for now
    case COMMENT(Comment)

    var isType: Bool {
        switch self {
        case .KEYWORD(let kw):
            switch kw {
            case .INT, .CHAR, .BOOLEAN:
                return true
            default:
                return false
            }
        case .IDENTIFIER:
            // className
            return true
        default:
            return false
        }
    }

    func isTerm(next: Token) -> Bool{
        switch self {
        case .SYMBOL(let sym):
            switch sym {
            case .openParanthesis:
                return true
            case .tilde, .minusSign:
                return true
            default:
                break
            }
        case .STRING_CONST, .INT_CONST, .KEYWORD, .IDENTIFIER:
            return true
        default:
            break
        }
        return false
    }
}

// MARK: - JackTokenizer

class JackTokenizer {
    let inputFile: String
    let fileName: String = ""
    var current: Token?
    var hasMoreTokens: Bool { !tokens.isEmpty }
    var peekNext: Token? { return tokens.first }
    var peekTwoAhead: Token? {
        if tokens.count >= 2 {
            return tokens[1]
        }
        return nil
    }
    private var tokens: [Token] = []

    init(inputFile: String) {
        self.inputFile = inputFile
    }

    /// removes all comments and whitespace from th input stream and b
    /// breaks it into Jack-language tokens
    func tokenize() {
        print(inputFile)
        var result = [Token]()
        let lines = inputFile.components(separatedBy: "\n")
        var openMultiLineComment = false
        for line in lines {
            let chars = Array(line)
            var current = ""
            var line = [Token]()
            var i = 0
            while i < chars.count {
                if let sym = Symbol(rawValue: chars[i]) {
                    /// lookahead
                    switch sym {
                    case .slash:
                        if i + 1 < chars.count, chars[i + 1] == "/" {
                            line.append(.COMMENT(.restOfLine))
                            i += 2
                        } else if i + 2 < chars.count, chars[i + 1] == "*", chars[i + 2] == "*" {
                            line.append(.COMMENT(.multiLineOpen))
                            i += 3
                        } else {
                            fallthrough
                        }
                    case .asterisk:
                        if i + 1 < chars.count, chars[i + 1] == "/" {
                            line.append(.COMMENT(.multiLineClose))
                            i += 2
                        } else {
                            fallthrough
                        }
                    default:
                        if let token = detectToken(from: current) {
                            line.append(token)
                            current = ""
                        }
                        line.append(.SYMBOL(sym))
                        i += 1
                    }
                } else {
                    /// checking for empty space doesn't work for Array.new
                    if chars[i] == " ", let token = detectToken(from: current) {
                        line.append(token)
                        current = ""
                    } else {
                        current.append(chars[i])
                    }
                    i += 1
                }
            }
            // 2nd pass comment checking alright for now
            var final = [Token]()
            outer: for token in line {
                switch token {
                case .COMMENT(let cmt):
                    switch cmt {
                    case .restOfLine:
                        break outer
                    case .multiLineOpen:
                        openMultiLineComment = true
                    case .multiLineClose:
                        openMultiLineComment = false
                    }
                default:
                    if !openMultiLineComment {
                        final.append(token)
                    }
                }
            }
            result.append(contentsOf: final)
        }
        self.tokens = result
    }

    func detectToken(from word: String) -> Token? {
        let trim = word.trimmingCharacters(in: .whitespacesAndNewlines)
        if let int = Int(trim) {
            return .INT_CONST(int)
        } else if !trim.isEmpty {
            if trim.count > 1 {
                if let kw = Keyword(rawValue: trim) {
                    return .KEYWORD(kw)
                } else {
                    if trim.first == "\"" {
                        if trim.last == "\"" {
                            var str = trim
                            str.removeFirst()
                            str.removeLast()
                            return .STRING_CONST(str)
                        }
                        return nil
                    } else {
                        return .IDENTIFIER(trim)
                    }
                }
            } else {
                return .IDENTIFIER(trim)
            }
        }
        return nil
    }

    func advance() -> Token? {
        guard hasMoreTokens else { return nil }
        current = tokens.removeFirst()
        return current
    }

    func outputToXml(path: String) {
        var xmlString = "<tokens>\n"
        while let t = advance() {
            switch t {
            case .KEYWORD(let kw):
                xmlString.append("<keyword> \(kw.rawValue) </keyword>\n")
            case .SYMBOL(let sym):
                xmlString.append("<symbol> \(sym.xmlSymbol) </symbol>\n")
            case .IDENTIFIER(let identifier):
                xmlString.append("<identifier> \(identifier) </identifier>\n")
            case .INT_CONST(let int):
                xmlString.append("<integerConstant> \(int) </integerConstant>\n")
            case .STRING_CONST(let str):
                xmlString.append("<stringConstant> \(str) </stringConstant>\n")
            case .COMMENT:
                print("comments shouldn't enter xml output, or be present at this point")
                break
            }
        }
        xmlString.append("</tokens>")
        print(xmlString)
        FileManager.default.createFile(
            atPath: "\(path).xml",
            contents: xmlString.data(using: .ascii)
        )
    }
}

// MARK: - CompilationEngine

class CompilationEngine {
    let tokenizer: JackTokenizer
    var depth = 0
    var xmlString = ""

    init(tokenizer: JackTokenizer) {
        self.tokenizer = tokenizer
    }

    func compileClass() {
        let token = tokenizer.advance()!
        guard case .KEYWORD(.CLASS) = token else {
            preconditionFailure()
        }
        writeNonTerminal("class")
        writeToken(token)
        // class name
        compileIdentifier()
        findAndWriteRequiredSymbol(.openingBrace)
        // static dec or subroutines
        while case .KEYWORD(let kw) = tokenizer.peekNext, kw.isClassVarDecOrSubroutine {
            let token = tokenizer.advance()!
            switch kw {
            case .STATIC, .FIELD:
                compileClassVarDec(token: token)
            case .FUNCTION, .CONSTRUCTOR, .METHOD:
                compileSubroutineDec(token)
            default:
                preconditionFailure()
            }
        }
        findAndWriteRequiredSymbol(.closingBrace)
        writeTerminal("class")
    }

    /// compiles a static declaration or a field declaration
    func compileClassVarDec(token: Token) {
        writeNonTerminal("classVarDec")
        writeToken(token)
        compileType()
        compileIdentifier()
        // (, varName)*
        while case .SYMBOL(let sym) = tokenizer.peekNext, case .comma = sym {
            findAndWriteRequiredSymbol(.comma)
            compileIdentifier()
        }
        findAndWriteRequiredSymbol(.semiColon)
        writeTerminal("classVarDec")
    }

    /// compiles a complete method, function or constructor
    func compileSubroutineDec(_ keyword: Token) {
        writeNonTerminal("subroutineDec")
        writeToken(keyword)
        // void or type
        let tok = tokenizer.advance()!
        switch tok {
        case .IDENTIFIER, .KEYWORD(.VOID):
            writeToken(tok)
        default:
            preconditionFailure()
        }
        // subroutineName
        compileIdentifier()
        findAndWriteRequiredSymbol(.openParanthesis)
        compileParameterList()
        findAndWriteRequiredSymbol(.closingParanthesis)
        compileSubroutineBody()
        writeTerminal("subroutineDec")
    }

    func compileParameterList() {
        writeNonTerminal("parameterList")
        // ((type VarName) (, type varName)*)?
        if tokenizer.peekNext?.isType == true {
            let token = tokenizer.advance()!
            writeToken(token)
            compileIdentifier()
        }
        // (, varName)*
        while case .SYMBOL(let sym) = tokenizer.peekNext,
              case .comma = sym {
            findAndWriteRequiredSymbol(.comma)
            compileType()
            compileIdentifier()
        }
        writeTerminal("parameterList")
    }

    func compileSubroutineBody() {
        writeNonTerminal("subroutineBody")
        findAndWriteRequiredSymbol(.openingBrace)
        while case .KEYWORD(let kw) = tokenizer.peekNext,
              case .VAR = kw  {
            compileVarDec(token: tokenizer.advance()!)
        }
        compileStatements()
        findAndWriteRequiredSymbol(.closingBrace)
        writeTerminal("subroutineBody")
    }

    func compileVarDec(token: Token) {
        writeNonTerminal("varDec")
        // var
        writeToken(token)
        compileType()
        // varName
        compileIdentifier()
        while case .SYMBOL(let sym) = tokenizer.peekNext,
              case .comma = sym  {
            findAndWriteRequiredSymbol(.comma)
            compileIdentifier()
        }
        findAndWriteRequiredSymbol(.semiColon)
        writeTerminal("varDec")
    }

    func compileType() {
        guard tokenizer.peekNext?.isType == true else {
            preconditionFailure()
        }
        writeToken(tokenizer.advance()!)
    }

    func compileStatements() {
        writeNonTerminal("statements")
        outer: while case .KEYWORD(let sym) = tokenizer.peekNext, sym.isStatement {
            let token = tokenizer.advance()!
            switch sym {
            case .LET:
                compileLet(token: token)
            case .IF:
                compileIf(token: token)
            case .WHILE:
                compileWhile(token: token)
            case .DO:
                compileDo(token: token)
            case .RETURN:
                compileReturn(token: token)
            default:
                break outer
            }
        }
        writeTerminal("statements")
    }

    func compileLet(token: Token) {
        writeNonTerminal("letStatement")
        // let
        writeToken(token)
        // varName
        compileIdentifier()
        // ('[' + expression ']')?
        if case .SYMBOL(let sym) = tokenizer.peekNext,
           case .openingBracket = sym {
            findAndWriteRequiredSymbol(.openingBracket)
            compileExpression()
            findAndWriteRequiredSymbol(.closingBracket)
        }
        findAndWriteRequiredSymbol(.equals)
        compileExpression()
        findAndWriteRequiredSymbol(.semiColon)
        writeTerminal("letStatement")
    }

    func compileDo(token: Token) {
        writeNonTerminal("doStatement")
        writeToken(token)
        compileSubroutineCall()
        findAndWriteRequiredSymbol(.semiColon)
        writeTerminal("doStatement")
    }

    func compileWhile(token: Token) {
        writeNonTerminal("whileStatement")
        writeToken(token)
        findAndWriteRequiredSymbol(.openParanthesis)
        compileExpression()
        findAndWriteRequiredSymbol(.closingParanthesis)
        findAndWriteRequiredSymbol(.openingBrace)
        compileStatements()
        findAndWriteRequiredSymbol(.closingBrace)
        writeTerminal("whileStatement")
    }

    func compileReturn(token: Token) {
        writeNonTerminal("returnStatement")
        // return
        writeToken(token)
        if tokenizer.peekNext != nil,
           tokenizer.peekTwoAhead != nil,
           tokenizer.peekNext!.isTerm(next: tokenizer.peekTwoAhead!) {
            compileExpression()
        }
        findAndWriteRequiredSymbol(.semiColon)
        writeTerminal("returnStatement")
    }

    func compileIf(token: Token) {
        writeNonTerminal("ifStatement")
        // if
        writeToken(token)
        findAndWriteRequiredSymbol(.openParanthesis)
        compileExpression()
        findAndWriteRequiredSymbol(.closingParanthesis)
        findAndWriteRequiredSymbol(.openingBrace)
        compileStatements()
        findAndWriteRequiredSymbol(.closingBrace)
        // (else { statements } )?
        if case .KEYWORD(let sym) = tokenizer.peekNext, case .ELSE = sym {
            let token = tokenizer.advance()!
            writeToken(token)
            findAndWriteRequiredSymbol(.openingBrace)
            compileStatements()
            findAndWriteRequiredSymbol(.closingBrace)
        }
        writeTerminal("ifStatement")
    }

    func compileSubroutineCall() {
        // subroutineName || className || className
        compileIdentifier()
        if case .SYMBOL(let sym) = tokenizer.peekNext, case .openParanthesis = sym {
            findAndWriteRequiredSymbol(.openParanthesis)
        } else {
            findAndWriteRequiredSymbol(.period)
            // subroutineName
            compileIdentifier()
            findAndWriteRequiredSymbol(.openParanthesis)
        }
        compileExpressionList()
        findAndWriteRequiredSymbol(.closingParanthesis)
    }

    func compileTerm() {
        writeNonTerminal("term")
        switch tokenizer.peekNext {
        case .KEYWORD:
            let token = tokenizer.advance()!
            writeToken(token)
        case .IDENTIFIER:
            // could just be varName, varName [ expression ], could be subroutineCall
            // which starts either subroutineName || className which are identifiers
            compileIdentifier()
            if case .SYMBOL(let sym) = tokenizer.peekNext, case .openingBracket = sym {
                // [ expression ]
                findAndWriteRequiredSymbol(.openingBracket)
                compileExpression()
                findAndWriteRequiredSymbol(.closingBracket)
            } else if case .SYMBOL(let sym) = tokenizer.peekNext,
                      case .openParanthesis = sym {
                // subroutine 1, repeating that method slightly
                findAndWriteRequiredSymbol(.openParanthesis)
                compileExpressionList()
                findAndWriteRequiredSymbol(.closingParanthesis)
            } else if case .SYMBOL(let sym) = tokenizer.peekNext,
                      case .period = sym {
                // subroutine 2, ""
                findAndWriteRequiredSymbol(.period)
                compileIdentifier()
                findAndWriteRequiredSymbol(.openParanthesis)
                compileExpressionList()
                findAndWriteRequiredSymbol(.closingParanthesis)
            }
        case .STRING_CONST:
            let token = tokenizer.advance()!
            writeToken(token)
        case .INT_CONST:
            let token = tokenizer.advance()!
            writeToken(token)
        case .SYMBOL(let sym):
            switch sym {
            case .openParanthesis:
                findAndWriteRequiredSymbol(.openParanthesis)
                compileExpression()
                findAndWriteRequiredSymbol(.closingParanthesis)
            case .tilde, .minusSign:
                let token = tokenizer.advance()!
                writeToken(token)
                compileTerm()
            default:
                break
            }
        default:
            break // also can break when it's just not a term, move on!
        }
        writeTerminal("term")
    }

    func compileExpressionList() {
        writeNonTerminal("expressionList")
        // (expression (, expression)* )?
        if tokenizer.peekNext != nil,
           tokenizer.peekTwoAhead != nil,
           tokenizer.peekNext!.isTerm(next: tokenizer.peekTwoAhead!) {
            compileExpression()
            while case .SYMBOL(let sym) = tokenizer.peekNext, case .comma = sym {
                findAndWriteRequiredSymbol(.comma)
                compileExpression()
            }
        }
        writeTerminal("expressionList")
    }

    func compileExpression() {
        writeNonTerminal("expression")
        // term
        compileTerm()
        // (op term)*
        while case .SYMBOL(let sym) = tokenizer.peekNext, sym.isOp {
            let token = tokenizer.advance()!
            writeToken(token)
            compileTerm()
        }
        writeTerminal("expression")
    }

    func compileIdentifier() {
        guard let token = tokenizer.advance(),
           case .IDENTIFIER = token else {
            preconditionFailure()
        }
        writeToken(token)
    }

    // MARK: - Helper

    private func writeNonTerminal(_ name: String) {
        if depth > 0 {
            let spaces = String(repeating: " ", count: depth * 2)
            print(name, spaces.count, "!!!")
            xmlString.append("\(spaces)<\(name)>\n")
        } else {
            xmlString.append("<\(name)>\n")
        }
        depth += 1
    }

    private func writeTerminal(_ name: String) {
        depth -= 1
        if depth > 0 {
            let spaces = String(repeating: " ", count: depth * 2)
            xmlString.append("\(spaces)</\(name)>\n")
        } else {
            xmlString.append("</\(name)>\n")
        }
    }

    private func writeToken(_ token: Token) {
        switch token {
        case .KEYWORD(let kw):
            writeLine(key: "keyword", value: kw.rawValue)
        case .SYMBOL(let symbol):
            writeLine(key: "symbol", value: symbol.xmlSymbol)
        case .IDENTIFIER(let i):
            writeLine(key: "identifier", value: i)
        case .INT_CONST(let int):
            writeLine(key: "integerConstant", value: "\(int)")
        case .STRING_CONST(let str):
            writeLine(key: "stringConstant", value: str)
        case .COMMENT:
            preconditionFailure()
        }
    }

    private func writeLine(key: String, value: String) {
        if depth > 0 {
            let spaces = String(repeating: " ", count: depth * 2)
            xmlString.append("\(spaces)<\(key)> \(value) </\(key)>\n")
        } else {
            xmlString.append("<\(key)> \(value) </\(key)>\n")
        }
    }

    private func findAndWriteRequiredSymbol(_ symbol: Symbol) {
        guard let token = tokenizer.advance(),
           case .SYMBOL(let s) = token,
           case symbol = s else {
            print("couldn't find", symbol, "token was", tokenizer.current!)
            // preconditionFailure()
            return
        }
        writeToken(token)
    }
}
