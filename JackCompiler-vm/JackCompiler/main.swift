//
//  main.swift
//  JackCompiler
//
//  Created by Kevin Johnson on 5/16/21.
//

import Foundation

func jackToVm() {
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
                        fileName: path.appending("/output/\(fileName)") // ""
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
    let result = engine.vmWriter.string
    print("---\n\(result)")
    // write
    FileManager.default.createFile(
        atPath: "\(fileName).vm",
        contents: result.data(using: .ascii)
    )
}

func stringIfJackFile(url: URL) throws -> String? {
    if url.pathExtension == "jack" {
        return try String(contentsOf: url, encoding: .utf8)
    }
    return nil
}

jackToVm()

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

    // FIXME: currently trimming "," characters from Strings when tokenizing
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

    @discardableResult
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
    let symbolTable: SymbolTable = .init()
    let vmWriter: VMWriter = .init()
    var currentClassName = ""
    var currentSubroutineName = ""

    init(tokenizer: JackTokenizer) {
        self.tokenizer = tokenizer
    }

    /// class: 'class' className '{' classVarDec* subroutineDec* '}'
    func compileClass() {
        let token = tokenizer.advance()!
        guard case .KEYWORD(.CLASS) = token else {
            preconditionFailure()
        }
        compileClassName()
        findRequiredSymbol(.openingBrace)
        while case .KEYWORD(let kw) = tokenizer.peekNext, kw.isClassVarDecOrSubroutine {
            tokenizer.advance()
            switch kw {
            case .STATIC:
                compileClassVarDec(kind: .STATIC)
            case .FIELD:
                compileClassVarDec(kind: .FIELD)
            case .FUNCTION, .CONSTRUCTOR, .METHOD:
                compileSubroutineDec(keyword: kw)
            default:
                preconditionFailure()
            }
        }
        findRequiredSymbol(.closingBrace)
    }

    /// classVarDec: { 'static' | 'field' } type varName (',' varName)*  ';'
    func compileClassVarDec(kind: SymbolTable.Kind) {
        let type = compileType()
        let name = compileVarName()
        self.symbolTable.define(
            name: name,
            type: type,
            kind: kind
        )
        while case .SYMBOL(let sym) = tokenizer.peekNext, case .comma = sym {
            findRequiredSymbol(.comma)
            let name = compileVarName()
            self.symbolTable.define(
                name: name,
                type: type,
                kind: kind
            )
        }
        findRequiredSymbol(.semiColon)
    }

    /// subroutineDec: ('constructor' | 'function '| 'method') ('void' | type) subroutineName '(' parameterList ')' subroutineBody
    func compileSubroutineDec(keyword: Keyword) {
        /// void | type
        _ = compileVoidOrType()
        compileSubroutineName()
        symbolTable.startSubroutine()
        if keyword == .METHOD {
            self.symbolTable.define(
                name: "this",
                type: self.currentClassName,
                kind: .ARG
            )
        }
        findRequiredSymbol(.openParanthesis)
        compileParameterList()
        findRequiredSymbol(.closingParanthesis)
        compileSubroutineBody(keyword: keyword)
    }

    /// void | type
    func compileVoidOrType() -> String {
        if tokenizer.peekNext?.isType == true {
            return compileType()
        } else {
            tokenizer.advance()
            /// assert it's void though, assuming here
            return "void"
        }
    }

    /// parameterList: (parameter (',' parameter)*)?
    func compileParameterList() {
        if tokenizer.peekNext?.isType == true {
            compileParameter()
        }
        while case .SYMBOL(let sym) = tokenizer.peekNext,
              case .comma = sym {
            findRequiredSymbol(.comma)
            compileParameter()
        }
    }

    /// parameter: type varName
    func compileParameter() {
        if tokenizer.peekNext?.isType == true {
            let type = compileType()
            let name = compileVarName()
            symbolTable.define(
                name: name,
                type: type,
                kind: .ARG
            )
        }
    }

    /// subroutineBody: '{' varDec* statements '}'
    func compileSubroutineBody(keyword: Keyword) {
        findRequiredSymbol(.openingBrace)
        while case .KEYWORD(let kw) = tokenizer.peekNext,
              case .VAR = kw  {
            compileVarDec()
        }
        vmWriteFuncDeclaration(keyword: keyword)
        compileStatements()
        findRequiredSymbol(.closingBrace)
    }

    /// varDec: 'var' type varName (',' varName)* ';'
    func compileVarDec() {
        _ = tokenizer.advance()
        /// assert(token == Token.KEYWORD(.VAR))
        let type = compileType()
        let name = compileVarName()
        symbolTable.define(
            name: name,
            type: type,
            kind: .VAR
        )
        while case .SYMBOL(let sym) = tokenizer.peekNext,
              case .comma = sym  {
            tokenizer.advance()
            let n = compileVarName()
            symbolTable.define(
                name: n,
                type: type,
                kind: .VAR
            )
        }
        findRequiredSymbol(.semiColon)
    }

    /// type: 'int' | 'char' | 'boolean' | className
    func compileType() -> String  {
        let token = tokenizer.advance()!
        var str = ""
        switch token {
        case .KEYWORD(let kw):
            switch kw {
            case .INT, .CHAR, .BOOLEAN:
                str = kw.rawValue
            default:
                preconditionFailure()
            }
        case .IDENTIFIER(let name):
            str = name
        default:
            preconditionFailure()
        }
        return str
    }

    /// statement: letStatement | ifStatement | whileStatement | doStatement | returnStatement
    func compileStatements() {
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
    }

    /// letStatement: 'let' varName ('[' expression ']')? '=' expression ';'
    func compileLet(token: Token) {
        /// assert(token == Token.KEYWORD(.LET))
        let name = compileVarName()
        var isSubscript = false
        if case .SYMBOL(let sym) = tokenizer.peekNext,
           case .openingBracket = sym {
            isSubscript = true
            vmPushVariable(name: name)
            findRequiredSymbol(.openingBracket)
            compileExpression()
            findRequiredSymbol(.closingBracket)
            vmWriter.writeRaw(str: "add")
        }
        findRequiredSymbol(.equals)
        compileExpression()
        findRequiredSymbol(.semiColon)
        if isSubscript {
            vmPopArrayElement()
        } else {
            vmPopVariable(name: name)
        }
    }

    /// do_statement: 'do' subroutineCall ';'
    func compileDo(token: Token) {
        /// assert(token == Token.KEYWORD(.DO))
        let name = compileVarName()
        compileSubroutineCall(name: name)
        vmWriter.writePop(segment: "temp", index: 0)
        findRequiredSymbol(.semiColon)
    }

    /// whileStatement: 'while' '(' expression ')' '{' statements '}'
    func compileWhile(token: Token) {
        /// assert(token == Token.KEYWORD(.WHILE))
        let topLabel = newLabel()
        vmWriter.writeLabel(label: topLabel)
        compileConditionalExpressionStatements(label: topLabel)
    }

    /// ifStatement: 'if' '(' expression ')' '{' statements '}'
    /// ('else' '{' statements '}')?
    func compileIf(token: Token) {
        /// assert(token == Token.KEYWORD(.IF))
        let endLabel = newLabel()
        compileConditionalExpressionStatements(label: endLabel)
        if case .KEYWORD(let sym) = tokenizer.peekNext,
           case .ELSE = sym {
            tokenizer.advance()
            findRequiredSymbol(.openingBrace)
            compileStatements()
            findRequiredSymbol(.closingBrace)
        }
        vmWriter.writeLabel(label: endLabel)
    }

    /// shared for `if` and `while`
    func compileConditionalExpressionStatements(label: String) {
        findRequiredSymbol(.openParanthesis)
        compileExpression()
        findRequiredSymbol(.closingParanthesis)
        vmWriter.writeRaw(str: "not")
        let notIfLabel = newLabel()
        vmWriter.writeIf(label: notIfLabel)
        findRequiredSymbol(.openingBrace)
        compileStatements()
        findRequiredSymbol(.closingBrace)
        vmWriter.writeGoto(label: label)
        vmWriter.writeLabel(label: notIfLabel)
    }

    var labels = 0
    func newLabel() -> String {
        labels += 1
        return "label\(labels)"
    }

    /// returnStatement: 'return' expression? ';'
    func compileReturn(token: Token) {
        if tokenizer.peekNext != nil,
           tokenizer.peekTwoAhead != nil,
           tokenizer.peekNext!.isTerm(next: tokenizer.peekTwoAhead!) {
            compileExpression()
        } else {
            vmWriter.writePush(segment: "constant", index: 0)
        }
        findRequiredSymbol(.semiColon)
        vmWriter.writeReturn()
    }

    /// subroutineCall: subroutineName '(' expressionList ')'
    /// | (className | varName) '.' subroutineName '(' expressionList ')'
    func compileSubroutineCall(name: String) {
        var mName = name
        let value = symbolTable[mName]
        var numArgs = 1

        if case .SYMBOL(let sym) = tokenizer.peekNext,
           case .period = sym {
            findRequiredSymbol(.period)
            let (args, n) = compileDottedSubroutineCall(
                name: mName,
                type: value?.type
            )
            numArgs = args
            mName = n
        } else {
            vmWriter.writePush(segment: "pointer", index: 0)
            mName = "\(self.currentClassName).\(mName)"
        }
        findRequiredSymbol(.openParanthesis)
        numArgs += compileExpressionList()
        findRequiredSymbol(.closingParanthesis)
        vmWriter.writeCall(name: mName, nArgs: numArgs)
    }

    /// returns numberOfArgs and name
    func compileDottedSubroutineCall(name: String, type: String?) -> (Int, String) {
        let objName = name
        var numArgs = 0
        var mName = compileVarName()
        switch type {
        case "int", "char", "boolean", "void":
            print("cannot use on built-in type")
        case nil:
            mName = "\(objName).\(mName)"
        default:
            numArgs = 1
            vmPushVariable(name: objName)
            mName = symbolTable.typeOf(name: objName)! + ".\(mName)"
        }
        return (numArgs, mName)
    }

    /// term: integerConstant | stringConstant | keywordConstant | varName
    /// | varName '[' expression ']' | subroutineCall | '(' expression ')'
    /// | unaryOp term
    func compileTerm() {
        switch tokenizer.peekNext {
        case .KEYWORD(let kw):
            tokenizer.advance()
            switch kw {
            case .THIS:
                vmWriter.writePush(segment: "pointer", index: 0)
            case .TRUE:
                vmWriter.writePush(segment: "constant", index: 1)
                vmWriter.writeRaw(str: "neg")
            case .FALSE, .NULL:
                vmWriter.writePush(segment: "constant", index: 0)
            default:
                preconditionFailure()
            }
        case .IDENTIFIER:
            let name = compileVarName()
            if case .SYMBOL(let sym) = tokenizer.peekNext,
               case .openingBracket = sym {
                compileArraySubscript(name: name)
            } else if case .SYMBOL(let sym) = tokenizer.peekNext,
                      case .openParanthesis = sym {
                compileSubroutineCall(name: name)
            } else if case .SYMBOL(let sym) = tokenizer.peekNext,
                      case .period = sym {
                compileSubroutineCall(name: name)
            } else {
                vmPushVariable(name: name)
            }
        case .STRING_CONST(let str):
            tokenizer.advance()
            vmWriter.writePush(segment: "constant", index: str.count)
            vmWriter.writeCall(name: "String.new", nArgs: 1)
            for c in Array(str) {
                vmWriter.writePush(segment: "constant", index: Int(c.asciiValue!))
                vmWriter.writeCall(name: "String.appendChar", nArgs: 2)
            }
        case .INT_CONST(let int):
            tokenizer.advance()
            vmWriter.writePush(segment: "constant", index: int)
        case .SYMBOL(let sym):
            switch sym {
            case .openParanthesis:
                tokenizer.advance()
                compileExpression()
                findRequiredSymbol(.closingParanthesis)
            case .tilde, .minusSign:
                /// unaryOps
                tokenizer.advance()
                compileTerm()
                vmWriter.writeUnaryCommand(symbol: sym.rawValue)
            default:
                break
            }
        default:
            break // also can break when it's just not a term, move on
        }
    }

    /// '[' expression ']'
    func compileArraySubscript(name: String) {
        vmPushVariable(name: name)
        findRequiredSymbol(.openingBracket)
        compileExpression()
        findRequiredSymbol(.closingBracket)
        vmWriter.writeRaw(str: "add")
        vmWriter.writePop(segment: "pointer", index: 1)
        vmWriter.writePush(segment: "that", index: 0)
    }

    /// expressionList: (expression (',' expression)*)?
    func compileExpressionList() -> Int {
        var numArgs = 0
        if tokenizer.peekNext != nil,
           tokenizer.peekTwoAhead != nil,
           tokenizer.peekNext!.isTerm(next: tokenizer.peekTwoAhead!) {
            compileExpression()
            numArgs = 1
            while case .SYMBOL(let sym) = tokenizer.peekNext,
                  case .comma = sym {
                tokenizer.advance()
                compileExpression()
                numArgs += 1
            }
        }
        return numArgs
    }

    /// expression: term (op term)*
    func compileExpression() {
        compileTerm()
        while case .SYMBOL(let sym) = tokenizer.peekNext, sym.isOp {
            tokenizer.advance()
            compileTerm()
            vmWriter.writeCommand(symbol: sym.rawValue)
        }
    }

    /// className: identifier
    func compileClassName() {
        self.currentClassName = compileIdentifier()
    }

    /// subroutineName: identifier
    func compileSubroutineName() {
        self.currentSubroutineName = compileIdentifier()
    }

    /// varName: identifier
    func compileVarName() -> String {
        return compileIdentifier()
    }

    /// identifier
    func compileIdentifier() -> String {
        guard let token = tokenizer.advance(),
           case .IDENTIFIER(let name) = token else {
            preconditionFailure()
        }
        return name
    }

    /// helper
    func findRequiredSymbol(_ symbol: Symbol) {
        guard let token = tokenizer.advance(),
           case .SYMBOL(let s) = token,
           case symbol = s else {
            print("couldn't find", symbol, "token was", tokenizer.current!)
            preconditionFailure()
        }
    }

    // MARK: - VM Helper

    func vmWriteFuncDeclaration(keyword: Keyword) {
        let name = "\(self.currentClassName).\(self.currentSubroutineName)"
        vmWriter.writeFunction(name: name, nLocals: symbolTable.varCount)
        vmLoadThisPointer(keyword: keyword)
    }

    func vmPushVariable(name: String) {
        guard let value = symbolTable[name] else {
            print("coudn't find variable to push with name: \(name)")
            return
        }
        vmWriter.writePush(
            segment: value.kind.segment,
            index: value.index
        )
    }

    func vmPopVariable(name: String) {
        guard let value = symbolTable[name] else {
            print("coudn't find variable to push with name: \(name)")
            return
        }
        vmWriter.writePop(
            segment: value.kind.segment,
            index: value.index
        )
    }

    func vmLoadThisPointer(keyword: Keyword) {
        if keyword == .METHOD {
            vmWriter.writePush(segment: "argument", index: 0)
            vmWriter.writePop(segment: "pointer", index: 0)
        } else if keyword == .CONSTRUCTOR {
            vmWriter.writePush(
                segment: "constant",
                index: symbolTable.varCount(kind: .FIELD)
            )
            vmWriter.writeCall(name: "Memory.alloc", nArgs: 1)
            vmWriter.writePop(segment: "pointer", index: 0)
        }
    }

    func vmPopArrayElement() {
        vmWriter.writePop(segment: "temp", index: 1)
        vmWriter.writePop(segment: "pointer", index: 1)
        vmWriter.writePush(segment: "temp", index: 1)
        vmWriter.writePop(segment: "that", index: 0)
    }
}

// MARK: - SymbolTable

class SymbolTable {
    enum Kind: String {
        case STATIC = "static", FIELD = "this"
        case ARG = "argument", VAR = "local"

        var segment: String { rawValue }
    }

    struct HashValue {
        let type: String
        let kind: Kind
        let index: Int
    }

    var classScope: [String: HashValue] = [:]
    var staticCount = 0
    var fieldCount = 0
    var subroutineScope: [String: HashValue] = [:]
    var argumentCount = 0
    var varCount = 0

    func startSubroutine() {
        subroutineScope = [:]
        argumentCount = 0
        varCount = 0
    }

    subscript(name: String) -> HashValue? {
        if subroutineScope[name] != nil {
            return subroutineScope[name]
        } else if classScope[name] != nil {
            return classScope[name]
        }
        return nil
    }

    func define(name: String, type: String, kind: Kind) {
        switch kind {
        case .STATIC:
            guard classScope[name] == nil else {
                return
            }
            classScope[name] = .init(
                type: type,
                kind: kind,
                index: staticCount
            )
            staticCount += 1
        case .FIELD:
            guard classScope[name] == nil else {
                return
            }
            classScope[name] = .init(
                type: type,
                kind: kind,
                index: fieldCount
            )
            fieldCount += 1
        case .ARG:
            guard subroutineScope[name] == nil else {
                return
            }
            subroutineScope[name] = .init(
                type: type,
                kind: kind,
                index: argumentCount
            )
            argumentCount += 1
        case .VAR:
            guard subroutineScope[name] == nil else {
                return
            }
            subroutineScope[name] = .init(
                type: type,
                kind: kind,
                index: varCount
            )
            varCount += 1
        }
    }

    func varCount(kind: Kind) -> Int {
        switch kind {
        case .STATIC:
            return staticCount
        case .FIELD:
            return fieldCount
        case .ARG:
            return argumentCount
        case .VAR:
            return varCount
        }
    }

    func kindOf(name: String) -> Kind? {
        return self[name]?.kind
    }

    func typeOf(name: String) -> String? {
        return self[name]?.type
    }

    func indexOf(name: String) -> Int? {
        return self[name]?.index

    }
}

// MARK: - VMWriter

class VMWriter {
    private(set) var string = ""
    let commands: [Character: String] = [
        "+" : "add",
        "-" : "sub",
        "*" : "call Math.multiply 2",
        "/" : "call Math.divide 2",
        "<" : "lt",
        ">" : "gt",
        "=" : "eq",
        "&" : "and",
        "|" : "or"
    ]
    let unaryCommands: [Character: String] = [
        "-" : "neg",
        "~" : "not"
    ]

    func writePush(segment: String, index: Int) {
        string.append("push \(segment) \(index)\n")
    }

    func writePop(segment: String, index: Int) {
        string.append("pop \(segment) \(index)\n")
    }

    // func writeArithmetic()

    func writeLabel(label: String) {
        string.append("label \(label)\n")
    }

    func writeGoto(label: String) {
        string.append("goto \(label)\n")
    }

    func writeIf(label: String) {
        string.append("if-goto \(label)\n")
    }

    func writeCall(name: String, nArgs: Int) {
        string.append("call \(name) \(nArgs)\n")
    }

    func writeFunction(name: String, nLocals: Int) {
        string.append("function \(name) \(nLocals)\n")
    }

    func writeReturn() {
        string.append("return\n")
    }

    func writeCommand(symbol: Character) {
        string.append("\(commands[symbol]!)\n")
    }

    func writeRaw(str: String) {
        string.append("\(str)\n")
    }

    func writeUnaryCommand(symbol: Character) {
        string.append("\(unaryCommands[symbol]!)\n")
    }
}
