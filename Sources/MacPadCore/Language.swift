//
//  Language.swift
//  MacPad
//
//  Language definitions: which Lexilla lexer to attach, which keyword lists to
//  feed it, how its style numbers map to semantic roles, and how to comment a
//  line in it.
//
//  This is a hand-written starter set covering the languages people reach for
//  daily. Milestone M4 replaces it with a data-driven catalogue of ~90
//  languages loaded from a definitions file. The shape here deliberately
//  mirrors that file so the swap is mechanical.
//
//  Note on the C family: Lexilla has no `java`, `javascript`, `go` or `swift`
//  lexer. All of them run through the `cpp` lexer, varying only the keyword
//  lists and comment markers, which is how Lexilla intends them to be used.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

// Scintilla's predefined style numbers (from Scintilla.h, which is not exposed
// to Swift because it also carries C types we want to keep out of the bridge).
// Int, not Int32: these are passed to MPEditorView's NSInteger parameters, and
// Swift does not implicitly widen Int32. The SCE_* constants imported from
// SciLexer.h are Int32, so style numbers taken from a Language's styleRoles
// need an explicit Int() at the call site.
enum ScintillaStyle {
    static let `default`: Int    = 32
    static let lineNumber: Int   = 33
    static let braceLight: Int   = 34
    static let braceBad: Int     = 35
    static let controlChar: Int  = 36
    static let indentGuide: Int  = 37
    static let callTip: Int      = 38
    static let foldDisplayText: Int = 39
}

/// A semantic styling role. Lexer style numbers are per-lexer and meaningless
/// across languages; roles let one theme colour every language.
enum StyleRole: Hashable {
    case normal
    case comment
    case documentationComment
    case keyword
    case secondaryKeyword
    case type
    case string
    case character
    case escapeSequence
    case number
    case `operator`
    case preprocessor
    case identifier
    case functionName
    case className
    case tag
    case unknownTag
    case attribute
    case unknownAttribute
    case entity
    case propertyName
    case heading
    case link
    case emphasis
    case strong
    case codeSpan
    case variable
    case regex
    case error
    case added
    case deleted
    case changed
}

struct Language {
    /// Our identifier, shown in the Language menu and stored in sessions.
    let id: String
    let displayName: String
    /// The Lexilla lexer name. Must be one of Lexilla's 139 registered names.
    let lexer: String
    let fileExtensions: [String]
    /// Exact filenames that select this language regardless of extension.
    let fileNames: [String]
    /// Scintilla keyword set index (0...8) to a space-separated word list.
    let keywordSets: [Int: String]
    /// Lexer style number to semantic role.
    let styleRoles: [Int32: StyleRole]
    let lineComment: String?
    let blockComment: (open: String, close: String)?
    let defaultUsesTabs: Bool
    let defaultTabWidth: Int

    init(id: String,
         displayName: String,
         lexer: String,
         fileExtensions: [String] = [],
         fileNames: [String] = [],
         keywordSets: [Int: String] = [:],
         styleRoles: [Int32: StyleRole] = [:],
         lineComment: String? = nil,
         blockComment: (open: String, close: String)? = nil,
         defaultUsesTabs: Bool = false,
         defaultTabWidth: Int = 4) {
        self.id = id
        self.displayName = displayName
        self.lexer = lexer
        self.fileExtensions = fileExtensions
        self.fileNames = fileNames
        self.keywordSets = keywordSets
        self.styleRoles = styleRoles
        self.lineComment = lineComment
        self.blockComment = blockComment
        self.defaultUsesTabs = defaultUsesTabs
        self.defaultTabWidth = defaultTabWidth
    }
}

// MARK: - Shared style maps

private enum StyleMap {

    /// The `cpp` lexer, shared by every C-family language.
    static let cFamily: [Int32: StyleRole] = [
        SCE_C_DEFAULT:            .normal,
        SCE_C_COMMENT:            .comment,
        SCE_C_COMMENTLINE:        .comment,
        SCE_C_COMMENTDOC:         .documentationComment,
        SCE_C_COMMENTLINEDOC:     .documentationComment,
        SCE_C_COMMENTDOCKEYWORD:  .documentationComment,
        SCE_C_NUMBER:             .number,
        SCE_C_WORD:               .keyword,
        SCE_C_WORD2:              .secondaryKeyword,
        SCE_C_STRING:             .string,
        SCE_C_STRINGRAW:          .string,
        SCE_C_CHARACTER:          .character,
        SCE_C_ESCAPESEQUENCE:     .escapeSequence,
        SCE_C_PREPROCESSOR:       .preprocessor,
        SCE_C_OPERATOR:           .`operator`,
        SCE_C_IDENTIFIER:         .identifier,
        SCE_C_REGEX:              .regex,
        SCE_C_VERBATIM:           .string,
        SCE_C_HASHQUOTEDSTRING:   .string,
        SCE_C_STRINGEOL:          .error,
    ]

    static let python: [Int32: StyleRole] = [
        SCE_P_DEFAULT:       .normal,
        SCE_P_COMMENTLINE:   .comment,
        SCE_P_COMMENTBLOCK:  .comment,
        SCE_P_NUMBER:        .number,
        SCE_P_STRING:        .string,
        SCE_P_CHARACTER:     .character,
        SCE_P_WORD:          .keyword,
        SCE_P_WORD2:         .secondaryKeyword,
        SCE_P_TRIPLE:        .string,
        SCE_P_TRIPLEDOUBLE:  .string,
        SCE_P_CLASSNAME:     .className,
        SCE_P_DEFNAME:       .functionName,
        SCE_P_OPERATOR:      .`operator`,
        SCE_P_IDENTIFIER:    .identifier,
        SCE_P_DECORATOR:     .preprocessor,
        SCE_P_FSTRING:       .string,
        SCE_P_FCHARACTER:    .string,
        SCE_P_FTRIPLE:       .string,
        SCE_P_FTRIPLEDOUBLE: .string,
    ]

    /// `hypertext` (HTML) and `xml` share the SCE_H_* style space.
    static let markup: [Int32: StyleRole] = [
        SCE_H_DEFAULT:           .normal,
        SCE_H_TAG:               .tag,
        SCE_H_TAGUNKNOWN:        .unknownTag,
        SCE_H_ATTRIBUTE:         .attribute,
        SCE_H_ATTRIBUTEUNKNOWN:  .unknownAttribute,
        SCE_H_NUMBER:            .number,
        SCE_H_DOUBLESTRING:      .string,
        SCE_H_SINGLESTRING:      .string,
        SCE_H_OTHER:             .identifier,
        SCE_H_COMMENT:           .comment,
        SCE_H_ENTITY:            .entity,
        SCE_H_TAGEND:            .tag,
        SCE_H_XMLSTART:          .preprocessor,
        SCE_H_XMLEND:            .preprocessor,
        SCE_H_CDATA:             .string,
        SCE_H_QUESTION:          .preprocessor,
        SCE_H_VALUE:             .string,
    ]

    static let css: [Int32: StyleRole] = [
        SCE_CSS_DEFAULT:              .normal,
        SCE_CSS_TAG:                  .tag,
        SCE_CSS_CLASS:                .className,
        SCE_CSS_PSEUDOCLASS:          .secondaryKeyword,
        SCE_CSS_UNKNOWN_PSEUDOCLASS:  .error,
        SCE_CSS_OPERATOR:             .`operator`,
        SCE_CSS_IDENTIFIER:           .propertyName,
        SCE_CSS_UNKNOWN_IDENTIFIER:   .error,
        SCE_CSS_VALUE:                .string,
        SCE_CSS_COMMENT:              .comment,
        SCE_CSS_ID:                   .identifier,
        SCE_CSS_IMPORTANT:            .keyword,
        SCE_CSS_DIRECTIVE:            .preprocessor,
        SCE_CSS_DOUBLESTRING:         .string,
        SCE_CSS_SINGLESTRING:         .string,
        SCE_CSS_ATTRIBUTE:            .attribute,
        SCE_CSS_VARIABLE:             .variable,
    ]

    static let json: [Int32: StyleRole] = [
        SCE_JSON_DEFAULT:       .normal,
        SCE_JSON_NUMBER:        .number,
        SCE_JSON_STRING:        .string,
        SCE_JSON_STRINGEOL:     .error,
        SCE_JSON_PROPERTYNAME:  .propertyName,
        SCE_JSON_ESCAPESEQUENCE: .escapeSequence,
        SCE_JSON_LINECOMMENT:   .comment,
        SCE_JSON_BLOCKCOMMENT:  .comment,
        SCE_JSON_OPERATOR:      .`operator`,
        SCE_JSON_KEYWORD:       .keyword,
        SCE_JSON_LDKEYWORD:     .secondaryKeyword,
        SCE_JSON_ERROR:         .error,
    ]

    static let shell: [Int32: StyleRole] = [
        SCE_SH_DEFAULT:     .normal,
        SCE_SH_ERROR:       .error,
        SCE_SH_COMMENTLINE: .comment,
        SCE_SH_NUMBER:      .number,
        SCE_SH_WORD:        .keyword,
        SCE_SH_STRING:      .string,
        SCE_SH_CHARACTER:   .character,
        SCE_SH_OPERATOR:    .`operator`,
        SCE_SH_IDENTIFIER:  .identifier,
        SCE_SH_SCALAR:      .variable,
        SCE_SH_PARAM:       .variable,
        SCE_SH_BACKTICKS:   .string,
        SCE_SH_HERE_DELIM:  .preprocessor,
        SCE_SH_HERE_Q:      .string,
    ]

    static let yaml: [Int32: StyleRole] = [
        SCE_YAML_DEFAULT:    .normal,
        SCE_YAML_COMMENT:    .comment,
        SCE_YAML_IDENTIFIER: .propertyName,
        SCE_YAML_KEYWORD:    .keyword,
        SCE_YAML_NUMBER:     .number,
        SCE_YAML_REFERENCE:  .variable,
        SCE_YAML_DOCUMENT:   .preprocessor,
        SCE_YAML_TEXT:       .string,
        SCE_YAML_ERROR:      .error,
        SCE_YAML_OPERATOR:   .`operator`,
    ]

    static let markdown: [Int32: StyleRole] = [
        SCE_MARKDOWN_DEFAULT:     .normal,
        SCE_MARKDOWN_LINE_BEGIN:  .normal,
        SCE_MARKDOWN_STRONG1:     .strong,
        SCE_MARKDOWN_STRONG2:     .strong,
        SCE_MARKDOWN_EM1:         .emphasis,
        SCE_MARKDOWN_EM2:         .emphasis,
        SCE_MARKDOWN_HEADER1:     .heading,
        SCE_MARKDOWN_HEADER2:     .heading,
        SCE_MARKDOWN_HEADER3:     .heading,
        SCE_MARKDOWN_HEADER4:     .heading,
        SCE_MARKDOWN_HEADER5:     .heading,
        SCE_MARKDOWN_HEADER6:     .heading,
        SCE_MARKDOWN_PRECHAR:     .normal,
        SCE_MARKDOWN_ULIST_ITEM:  .keyword,
        SCE_MARKDOWN_OLIST_ITEM:  .keyword,
        SCE_MARKDOWN_BLOCKQUOTE:  .comment,
        SCE_MARKDOWN_STRIKEOUT:   .deleted,
        SCE_MARKDOWN_HRULE:       .`operator`,
        SCE_MARKDOWN_LINK:        .link,
        SCE_MARKDOWN_CODE:        .codeSpan,
        SCE_MARKDOWN_CODE2:       .codeSpan,
        SCE_MARKDOWN_CODEBK:      .codeSpan,
    ]

    static let sql: [Int32: StyleRole] = [
        SCE_SQL_DEFAULT:          .normal,
        SCE_SQL_COMMENT:          .comment,
        SCE_SQL_COMMENTLINE:      .comment,
        SCE_SQL_COMMENTDOC:       .documentationComment,
        SCE_SQL_NUMBER:           .number,
        SCE_SQL_WORD:             .keyword,
        SCE_SQL_STRING:           .string,
        SCE_SQL_CHARACTER:        .character,
        SCE_SQL_OPERATOR:         .`operator`,
        SCE_SQL_IDENTIFIER:       .identifier,
        SCE_SQL_WORD2:            .secondaryKeyword,
        SCE_SQL_QUOTEDIDENTIFIER: .identifier,
    ]

    static let rust: [Int32: StyleRole] = [
        SCE_RUST_DEFAULT:         .normal,
        SCE_RUST_COMMENTBLOCK:    .comment,
        SCE_RUST_COMMENTLINE:     .comment,
        SCE_RUST_COMMENTBLOCKDOC: .documentationComment,
        SCE_RUST_COMMENTLINEDOC:  .documentationComment,
        SCE_RUST_NUMBER:          .number,
        SCE_RUST_WORD:            .keyword,
        SCE_RUST_WORD2:           .secondaryKeyword,
        SCE_RUST_WORD3:           .type,
        SCE_RUST_WORD4:           .type,
        SCE_RUST_STRING:          .string,
        SCE_RUST_STRINGR:         .string,
        SCE_RUST_CHARACTER:       .character,
        SCE_RUST_OPERATOR:        .`operator`,
        SCE_RUST_IDENTIFIER:      .identifier,
        SCE_RUST_MACRO:           .preprocessor,
        SCE_RUST_LIFETIME:        .variable,
        SCE_RUST_BYTESTRING:      .string,
        SCE_RUST_BYTECHARACTER:   .character,
    ]

    static let diff: [Int32: StyleRole] = [
        SCE_DIFF_DEFAULT:  .normal,
        SCE_DIFF_COMMENT:  .comment,
        SCE_DIFF_COMMAND:  .keyword,
        SCE_DIFF_HEADER:   .heading,
        SCE_DIFF_POSITION: .preprocessor,
        SCE_DIFF_DELETED:  .deleted,
        SCE_DIFF_ADDED:    .added,
        SCE_DIFF_CHANGED:  .changed,
    ]

    static let properties: [Int32: StyleRole] = [
        SCE_PROPS_DEFAULT:   .normal,
        SCE_PROPS_COMMENT:   .comment,
        SCE_PROPS_SECTION:   .heading,
        SCE_PROPS_ASSIGNMENT: .`operator`,
        SCE_PROPS_DEFVAL:    .string,
        SCE_PROPS_KEY:       .propertyName,
    ]

    static let makefile: [Int32: StyleRole] = [
        SCE_MAKE_DEFAULT:    .normal,
        SCE_MAKE_COMMENT:    .comment,
        SCE_MAKE_PREPROCESSOR: .preprocessor,
        SCE_MAKE_IDENTIFIER: .variable,
        SCE_MAKE_OPERATOR:   .`operator`,
        SCE_MAKE_TARGET:     .functionName,
        SCE_MAKE_IDEOL:      .error,
    ]
}

// MARK: - Keyword lists

private enum Keywords {
    static let c = """
        auto break case char const continue default do double else enum extern float for goto if \
        inline int long register restrict return short signed sizeof static struct switch typedef \
        union unsigned void volatile while _Bool _Complex _Imaginary
        """

    static let cpp = """
        alignas alignof and and_eq asm auto bitand bitor bool break case catch char char8_t \
        char16_t char32_t class compl concept const consteval constexpr constinit const_cast \
        continue co_await co_return co_yield decltype default delete do double dynamic_cast else \
        enum explicit export extern false float for friend goto if inline int long mutable \
        namespace new noexcept not not_eq nullptr operator or or_eq private protected public \
        register reinterpret_cast requires return short signed sizeof static static_assert \
        static_cast struct switch template this thread_local throw true try typedef typeid \
        typename union unsigned using virtual void volatile wchar_t while xor xor_eq
        """

    static let javascript = """
        abstract arguments async await boolean break byte case catch char class const continue \
        debugger default delete do double else enum eval export extends false final finally float \
        for function goto if implements import in instanceof int interface let long native new \
        null of package private protected public return short static super switch synchronized \
        this throw throws transient true try typeof var void volatile while with yield
        """

    static let typescript = """
        abstract any as asserts async await bigint boolean break case catch class const constructor \
        continue declare default delete do else enum export extends false finally for from function \
        get global if implements import in infer instanceof interface is keyof let module namespace \
        never new null number object of package private protected public readonly require return \
        satisfies set static string super switch symbol this throw true try type typeof undefined \
        unique unknown var void while yield
        """

    static let java = """
        abstract assert boolean break byte case catch char class const continue default do double \
        else enum extends final finally float for goto if implements import instanceof int \
        interface long native new package private protected public return short static strictfp \
        super switch synchronized this throw throws transient try var void volatile while \
        true false null record sealed permits yield
        """

    static let swift = """
        associatedtype class deinit enum extension fileprivate func import init inout internal let \
        open operator private precedencegroup protocol public rethrows static struct subscript \
        typealias var actor async await break case catch continue default defer do else fallthrough \
        for guard if in repeat return throw switch where while as Any catch false is nil super \
        self Self throws true try some
        """

    static let go = """
        break case chan const continue default defer else fallthrough for func go goto if import \
        interface map package range return select struct switch type var true false iota nil \
        append cap close complex copy delete imag len make new panic print println real recover
        """

    static let csharp = """
        abstract as base bool break byte case catch char checked class const continue decimal \
        default delegate do double else enum event explicit extern false finally fixed float for \
        foreach goto if implicit in int interface internal is lock long namespace new null object \
        operator out override params private protected public readonly ref return sbyte sealed \
        short sizeof stackalloc static string struct switch this throw true try typeof uint ulong \
        unchecked unsafe ushort using virtual void volatile while var record init nameof async await
        """

    static let python = """
        and as assert async await break class continue def del elif else except False finally for \
        from global if import in is lambda None nonlocal not or pass raise return True try while \
        with yield match case
        """

    static let pythonBuiltins = """
        abs aiter all anext any ascii bin bool breakpoint bytearray bytes callable chr classmethod \
        compile complex delattr dict dir divmod enumerate eval exec filter float format frozenset \
        getattr globals hasattr hash help hex id input int isinstance issubclass iter len list \
        locals map max memoryview min next object oct open ord pow print property range repr \
        reversed round set setattr slice sorted staticmethod str sum super tuple type vars zip \
        self cls
        """

    static let rust = """
        as async await break const continue crate dyn else enum extern false fn for if impl in let \
        loop match mod move mut pub ref return self Self static struct super trait true type unsafe \
        use where while
        """

    static let rustTypes = """
        bool char f32 f64 i8 i16 i32 i64 i128 isize str u8 u16 u32 u64 u128 usize Box Option \
        Result String Vec HashMap HashSet Rc Arc RefCell Cell Mutex RwLock Some None Ok Err
        """

    static let shell = """
        alias bg bind break builtin caller case cd command compgen complete compopt continue \
        declare dirs disown do done echo elif else enable esac eval exec exit export fc fg fi for \
        function getopts hash help history if in jobs kill let local logout mapfile popd printf \
        pushd pwd read readarray readonly return select set shift shopt source suspend test then \
        time times trap true type typeset ulimit umask unalias unset until wait while
        """

    static let sql = """
        add all alter and any as asc between by case cast check column commit constraint create \
        cross current_date current_time database default delete desc distinct drop else end exists \
        foreign from full group having if in index inner insert intersect into is join key left \
        like limit not null offset on or order outer primary references right rollback select set \
        table then transaction union unique update using values view when where with
        """

    static let css = """
        align-items background background-color border border-radius bottom box-shadow box-sizing \
        color content cursor display flex flex-direction float font font-family font-size \
        font-weight gap grid grid-template-columns height justify-content left letter-spacing \
        line-height margin max-height max-width min-height min-width opacity overflow padding \
        position right text-align text-decoration top transform transition visibility white-space \
        width z-index
        """

    static let htmlTags = """
        a abbr address area article aside audio b base bdi bdo blockquote body br button canvas \
        caption cite code col colgroup data datalist dd del details dfn dialog div dl dt em embed \
        fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 head header hgroup hr html i \
        iframe img input ins kbd label legend li link main map mark menu meta meter nav noscript \
        object ol optgroup option output p picture pre progress q rp rt ruby s samp script search \
        section select slot small source span strong style sub summary sup table tbody td template \
        textarea tfoot th thead time title tr track u ul var video wbr
        """

    static let json = "true false null"

    static let yaml = "true false null yes no on off ~"
}

// MARK: - Catalogue

enum LanguageCatalog {

    /// Plain text: Lexilla's `null` lexer applies no styling at all.
    static let plainText = Language(
        id: "normal",
        displayName: "Normal Text",
        lexer: "null",
        fileExtensions: ["txt", "text", "log", "nfo"],
        styleRoles: [0: .normal]
    )

    static let all: [Language] = [
        plainText,

        Language(id: "c", displayName: "C", lexer: "cpp",
                 fileExtensions: ["c", "h"],
                 keywordSets: [0: Keywords.c],
                 styleRoles: StyleMap.cFamily,
                 lineComment: "//", blockComment: ("/*", "*/")),

        Language(id: "cpp", displayName: "C++", lexer: "cpp",
                 fileExtensions: ["cpp", "cxx", "cc", "c++", "hpp", "hxx", "hh", "h++", "ipp", "inl"],
                 keywordSets: [0: Keywords.cpp],
                 styleRoles: StyleMap.cFamily,
                 lineComment: "//", blockComment: ("/*", "*/")),

        Language(id: "objc", displayName: "Objective-C", lexer: "cpp",
                 fileExtensions: ["m", "mm"],
                 keywordSets: [0: Keywords.c + " " + Keywords.cpp],
                 styleRoles: StyleMap.cFamily,
                 lineComment: "//", blockComment: ("/*", "*/")),

        Language(id: "csharp", displayName: "C#", lexer: "cpp",
                 fileExtensions: ["cs"],
                 keywordSets: [0: Keywords.csharp],
                 styleRoles: StyleMap.cFamily,
                 lineComment: "//", blockComment: ("/*", "*/")),

        Language(id: "java", displayName: "Java", lexer: "cpp",
                 fileExtensions: ["java"],
                 keywordSets: [0: Keywords.java],
                 styleRoles: StyleMap.cFamily,
                 lineComment: "//", blockComment: ("/*", "*/")),

        Language(id: "javascript", displayName: "JavaScript", lexer: "cpp",
                 fileExtensions: ["js", "mjs", "cjs", "jsx"],
                 keywordSets: [0: Keywords.javascript],
                 styleRoles: StyleMap.cFamily,
                 lineComment: "//", blockComment: ("/*", "*/"), defaultTabWidth: 2),

        Language(id: "typescript", displayName: "TypeScript", lexer: "cpp",
                 fileExtensions: ["ts", "tsx", "mts", "cts"],
                 keywordSets: [0: Keywords.typescript],
                 styleRoles: StyleMap.cFamily,
                 lineComment: "//", blockComment: ("/*", "*/"), defaultTabWidth: 2),

        Language(id: "swift", displayName: "Swift", lexer: "cpp",
                 fileExtensions: ["swift"],
                 keywordSets: [0: Keywords.swift],
                 styleRoles: StyleMap.cFamily,
                 lineComment: "//", blockComment: ("/*", "*/")),

        Language(id: "go", displayName: "Go", lexer: "cpp",
                 fileExtensions: ["go"],
                 keywordSets: [0: Keywords.go],
                 styleRoles: StyleMap.cFamily,
                 lineComment: "//", blockComment: ("/*", "*/"),
                 defaultUsesTabs: true, defaultTabWidth: 4),

        Language(id: "rust", displayName: "Rust", lexer: "rust",
                 fileExtensions: ["rs"],
                 keywordSets: [0: Keywords.rust, 2: Keywords.rustTypes],
                 styleRoles: StyleMap.rust,
                 lineComment: "//", blockComment: ("/*", "*/")),

        Language(id: "python", displayName: "Python", lexer: "python",
                 fileExtensions: ["py", "pyw", "pyi"],
                 keywordSets: [0: Keywords.python, 1: Keywords.pythonBuiltins],
                 styleRoles: StyleMap.python,
                 lineComment: "#"),

        Language(id: "ruby", displayName: "Ruby", lexer: "ruby",
                 fileExtensions: ["rb", "rbw", "gemspec"],
                 fileNames: ["Gemfile", "Rakefile"],
                 styleRoles: [:],
                 lineComment: "#", defaultTabWidth: 2),

        Language(id: "php", displayName: "PHP", lexer: "phpscript",
                 fileExtensions: ["php", "php3", "php4", "php5", "phtml"],
                 styleRoles: [:],
                 lineComment: "//", blockComment: ("/*", "*/")),

        Language(id: "html", displayName: "HTML", lexer: "hypertext",
                 fileExtensions: ["html", "htm", "xhtml", "shtml"],
                 keywordSets: [0: Keywords.htmlTags],
                 styleRoles: StyleMap.markup,
                 blockComment: ("<!--", "-->"), defaultTabWidth: 2),

        Language(id: "xml", displayName: "XML", lexer: "xml",
                 fileExtensions: ["xml", "xsd", "xsl", "xslt", "svg", "plist", "storyboard", "xib",
                                  "rss", "atom", "pom"],
                 styleRoles: StyleMap.markup,
                 blockComment: ("<!--", "-->"), defaultTabWidth: 2),

        Language(id: "css", displayName: "CSS", lexer: "css",
                 fileExtensions: ["css", "scss", "less"],
                 keywordSets: [0: Keywords.css],
                 styleRoles: StyleMap.css,
                 blockComment: ("/*", "*/"), defaultTabWidth: 2),

        Language(id: "json", displayName: "JSON", lexer: "json",
                 fileExtensions: ["json", "jsonc", "json5", "ipynb"],
                 keywordSets: [0: Keywords.json],
                 styleRoles: StyleMap.json,
                 lineComment: "//", defaultTabWidth: 2),

        Language(id: "yaml", displayName: "YAML", lexer: "yaml",
                 fileExtensions: ["yml", "yaml"],
                 keywordSets: [0: Keywords.yaml],
                 styleRoles: StyleMap.yaml,
                 lineComment: "#", defaultTabWidth: 2),

        Language(id: "toml", displayName: "TOML", lexer: "toml",
                 fileExtensions: ["toml"],
                 fileNames: ["Cargo.lock"],
                 styleRoles: [:],
                 lineComment: "#"),

        Language(id: "markdown", displayName: "Markdown", lexer: "markdown",
                 fileExtensions: ["md", "markdown", "mdown", "mkd"],
                 styleRoles: StyleMap.markdown),

        Language(id: "shell", displayName: "Shell", lexer: "bash",
                 fileExtensions: ["sh", "bash", "zsh", "ksh", "command"],
                 fileNames: [".bashrc", ".bash_profile", ".zshrc", ".profile", ".zprofile"],
                 keywordSets: [0: Keywords.shell],
                 styleRoles: StyleMap.shell,
                 lineComment: "#"),

        Language(id: "powershell", displayName: "PowerShell", lexer: "powershell",
                 fileExtensions: ["ps1", "psm1", "psd1"],
                 styleRoles: [:],
                 lineComment: "#", blockComment: ("<#", "#>")),

        Language(id: "batch", displayName: "Batch", lexer: "batch",
                 fileExtensions: ["bat", "cmd"],
                 styleRoles: [:],
                 lineComment: "REM "),

        Language(id: "sql", displayName: "SQL", lexer: "sql",
                 fileExtensions: ["sql", "ddl"],
                 keywordSets: [0: Keywords.sql],
                 styleRoles: StyleMap.sql,
                 lineComment: "--", blockComment: ("/*", "*/")),

        Language(id: "lua", displayName: "Lua", lexer: "lua",
                 fileExtensions: ["lua"],
                 styleRoles: [:],
                 lineComment: "--", blockComment: ("--[[", "]]")),

        Language(id: "perl", displayName: "Perl", lexer: "perl",
                 fileExtensions: ["pl", "pm", "pod"],
                 styleRoles: [:],
                 lineComment: "#"),

        Language(id: "makefile", displayName: "Makefile", lexer: "makefile",
                 fileExtensions: ["mk", "mak"],
                 fileNames: ["Makefile", "makefile", "GNUmakefile"],
                 styleRoles: StyleMap.makefile,
                 lineComment: "#", defaultUsesTabs: true, defaultTabWidth: 8),

        Language(id: "cmake", displayName: "CMake", lexer: "cmake",
                 fileExtensions: ["cmake"],
                 fileNames: ["CMakeLists.txt"],
                 styleRoles: [:],
                 lineComment: "#"),

        Language(id: "diff", displayName: "Diff", lexer: "diff",
                 fileExtensions: ["diff", "patch"],
                 styleRoles: StyleMap.diff),

        Language(id: "properties", displayName: "Properties", lexer: "props",
                 fileExtensions: ["properties", "ini", "cfg", "conf", "editorconfig"],
                 fileNames: [".gitconfig", ".editorconfig"],
                 styleRoles: StyleMap.properties,
                 lineComment: "#"),
    ]

    private static let byExtension: [String: Language] = {
        var map: [String: Language] = [:]
        for language in all {
            for ext in language.fileExtensions {
                map[ext.lowercased()] = language
            }
        }
        return map
    }()

    private static let byFileName: [String: Language] = {
        var map: [String: Language] = [:]
        for language in all {
            for name in language.fileNames {
                map[name] = language
            }
        }
        return map
    }()

    static func language(withID id: String) -> Language? {
        all.first { $0.id == id }
    }

    /// Pick a language for a file. Exact filename wins over extension, which
    /// is what files like `Makefile` with no extension need.
    static func language(forFileNamed fileName: String) -> Language {
        if let byName = byFileName[fileName] {
            return byName
        }
        let ext = (fileName as NSString).pathExtension.lowercased()
        if !ext.isEmpty, let byExt = byExtension[ext] {
            return byExt
        }
        return plainText
    }

    static func language(for url: URL?) -> Language {
        guard let url else { return plainText }
        return language(forFileNamed: url.lastPathComponent)
    }
}
