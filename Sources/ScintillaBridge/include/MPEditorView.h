//
//  MPEditorView.h
//  MacPad — Objective-C++ bridge over Scintilla's Cocoa backend.
//
//  This header is imported into Swift via the bridging header, so it must stay
//  free of any Scintilla or C++ type. ScintillaView, SCNotification and the
//  SCI_* message space are confined to MPEditorView.mm.
//
//  Copyright (C) 2026 MacPad contributors.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MPEditorView;

/// Scintilla notifications, decoded into a form Swift can use. Scintilla's own
/// notification payload is a C struct delivered through an Objective-C
/// protocol; MPEditorView absorbs that and re-emits these instead.
@protocol MPEditorViewDelegate <NSObject>
@optional
/// Text was inserted or deleted.
- (void)editorTextDidChange:(MPEditorView *)editor;
/// Caret moved or the selection changed.
- (void)editorSelectionDidChange:(MPEditorView *)editor;
/// The document became clean (SCN_SAVEPOINTREACHED).
- (void)editorDidReachSavePoint:(MPEditorView *)editor;
/// The document became dirty (SCN_SAVEPOINTLEFT).
- (void)editorDidLeaveSavePoint:(MPEditorView *)editor;
/// A margin was clicked — used for bookmarks and folding.
- (void)editorDidClickMargin:(NSInteger)margin atPosition:(NSInteger)position editor:(MPEditorView *)editor
    NS_SWIFT_NAME(editorDidClickMargin(_:atPosition:editor:));
/// A fold marker was clicked.
- (void)editorDidRequestFoldToggleAtLine:(NSInteger)line editor:(MPEditorView *)editor
    NS_SWIFT_NAME(editorDidRequestFoldToggle(atLine:editor:));
/// A file was dropped on the editor (SCN_URIDROPPED), one call per file.
/// MacPad opens it in a new tab.
- (void)editor:(MPEditorView *)editor didDropFileAtPath:(NSString *)path
    NS_SWIFT_NAME(editor(_:didDropFileAtPath:));
@end


/// A text editing view backed by Scintilla.
///
/// Hosts a ScintillaView as its sole subview. One MPEditorView is one editing
/// pane (a split window will have two); the *documents* it displays are
/// swapped underneath it via `documentPointer`, which is how tabs work — the
/// view is reused, the document changes.
@interface MPEditorView : NSView

@property(nonatomic, weak, nullable) id<MPEditorViewDelegate> delegate;

#pragma mark - Diagnostics

/// Frames of this view and of Scintilla's internal views, for diagnosing
/// layout faults that only show up in a running app.
- (NSString *)layoutDescription;
/// Feed the view the SCN_URIDROPPED notification Scintilla sends for a file
/// dropped on the editor, exactly as the Cocoa layer would. Scintilla's
/// notification struct is not visible to Swift, so tests go through this.
- (void)deliverDroppedFileNotificationForTesting:(NSString *)path;

#pragma mark - Raw message channel

/// Send a raw Scintilla message. Everything else here is sugar over this.
/// Exposed deliberately: parity work will need messages this wrapper has no
/// typed method for, and inventing one per message would be busywork.
- (NSInteger)send:(NSInteger)message wparam:(NSInteger)wparam lparam:(NSInteger)lparam;
- (NSInteger)send:(NSInteger)message wparam:(NSInteger)wparam;
- (NSInteger)send:(NSInteger)message;

#pragma mark - Content

/// Whole-buffer text. Scintilla stores UTF-8 internally; conversion to and
/// from the file's on-disk encoding is the caller's business.
@property(nonatomic, copy) NSString *text;
@property(nonatomic, readonly) NSInteger length;
@property(nonatomic, readonly) NSInteger lineCount;
@property(nonatomic, readonly, copy) NSString *selectedText;

- (void)insertTextAtCaret:(NSString *)string NS_SWIFT_NAME(insertTextAtCaret(_:));
- (void)replaceSelectionWith:(NSString *)string NS_SWIFT_NAME(replaceSelection(with:));

#pragma mark - Lines and ranges

/// Text of one line, including its line ending. Empty for an invalid line.
- (NSString *)textOfLine:(NSInteger)line NS_SWIFT_NAME(text(ofLine:));
/// Byte length of a line, including its line ending.
- (NSInteger)lengthOfLine:(NSInteger)line NS_SWIFT_NAME(length(ofLine:));
/// Byte position just past the last character of a line, before its EOL.
- (NSInteger)endPositionOfLine:(NSInteger)line NS_SWIFT_NAME(endPosition(ofLine:));

- (void)insertText:(NSString *)string atPosition:(NSInteger)position NS_SWIFT_NAME(insertText(_:atPosition:));
- (void)deleteByteRange:(NSRange)range NS_SWIFT_NAME(deleteByteRange(_:));

@property(nonatomic, readonly) NSInteger selectionStart;
@property(nonatomic, readonly) NSInteger selectionEnd;

#pragma mark - Undo grouping

/// Group several edits into one undo step. Must be balanced.
- (void)beginUndoAction;
- (void)endUndoAction;

#pragma mark - Documents (tabs)

/// Opaque Scintilla document handle. Zero is never valid.
@property(nonatomic) NSInteger documentPointer;

/// Create a new, empty document with a reference count of 1. The caller owns
/// that reference and must pass it to `releaseDocument:` when done.
- (NSInteger)createDocument;
- (void)addRefDocument:(NSInteger)doc NS_SWIFT_NAME(addRefDocument(_:));
- (void)releaseDocument:(NSInteger)doc NS_SWIFT_NAME(releaseDocument(_:));

#pragma mark - Undo / clipboard

- (void)undo;
- (void)redo;
@property(nonatomic, readonly) BOOL canUndo;
@property(nonatomic, readonly) BOOL canRedo;
// Named away from cut/copy/paste: NSObject already declares `- (id)copy`, and
// redeclaring it as `- (void)copy` is a conflicting-return-type error.
- (void)cutSelection;
- (void)copySelection;
- (void)pasteFromClipboard;
- (void)selectAllText;
/// Delete the selected text without touching the clipboard.
- (void)deleteSelection;
/// Change the case of the selected text in place; the selection stays.
- (void)uppercaseSelection;
- (void)lowercaseSelection;
/// Whether any text is selected.
@property(nonatomic, readonly) BOOL hasSelection;
/// Whether the clipboard holds something the editor can paste.
@property(nonatomic, readonly) BOOL canPaste;
/// The text between two byte offsets. Uses Scintilla's target range, so a
/// pending Replace must not rely on the target surviving this call.
- (NSString *)textInByteRange:(NSRange)range NS_SWIFT_NAME(text(inByteRange:));
/// The menu shown on right-click in the text and margins. Nil gives
/// Scintilla's own basic menu.
@property(nonatomic, strong, nullable) NSMenu *contextMenu;
/// Collapse the undo history and mark the current state as the save point.
- (void)markSavePoint;
@property(nonatomic, readonly) BOOL isDirty;

#pragma mark - Caret, selection, navigation

@property(nonatomic) NSInteger currentPosition;
@property(nonatomic, readonly) NSInteger currentLine;
@property(nonatomic, readonly) NSInteger currentColumn;
- (void)setSelectionFrom:(NSInteger)anchor to:(NSInteger)caret NS_SWIFT_NAME(setSelection(from:to:));
- (void)gotoLine:(NSInteger)line NS_SWIFT_NAME(goToLine(_:));
- (void)gotoPosition:(NSInteger)position NS_SWIFT_NAME(goToPosition(_:));
- (void)scrollCaretIntoView;
- (NSInteger)positionForLine:(NSInteger)line NS_SWIFT_NAME(position(forLine:));
- (NSInteger)lineForPosition:(NSInteger)position NS_SWIFT_NAME(line(forPosition:));

#pragma mark - Syntax highlighting

/// Attach a Lexilla lexer by its Lexilla name (e.g. "cpp", "python", "xml").
/// Returns NO if Lexilla has no lexer under that name.
- (BOOL)setLexerNamed:(NSString *)lexerName NS_SWIFT_NAME(setLexerNamed(_:));
/// Lexilla's name for the attached lexer, or nil when none is set.
@property(nonatomic, readonly, copy, nullable) NSString *lexerName;
/// Keyword list `index` for the current lexer, space separated.
- (void)setKeywords:(NSString *)keywords forSet:(NSInteger)index NS_SWIFT_NAME(setKeywords(_:forSet:));
/// Re-lex a byte range. Pass -1 for `end` to mean end of document.
- (void)colouriseFrom:(NSInteger)start to:(NSInteger)end NS_SWIFT_NAME(colourise(from:to:));

/// The names of every lexer Lexilla was built with.
+ (NSArray<NSString *> *)availableLexerNames;

#pragma mark - Styling

- (void)setStyle:(NSInteger)style foreground:(NSColor *)color;
- (void)setStyle:(NSInteger)style background:(NSColor *)color;
- (void)setStyle:(NSInteger)style bold:(BOOL)bold;
- (void)setStyle:(NSInteger)style italic:(BOOL)italic;
- (void)setStyle:(NSInteger)style underline:(BOOL)underline;
- (void)setStyle:(NSInteger)style fontName:(NSString *)fontName size:(CGFloat)size;
/// Copy style 32 (STYLE_DEFAULT) over every other style. Call before applying
/// per-style colours, as Scintilla requires.
- (void)applyDefaultStyleToAll;
- (void)setCaretForeground:(NSColor *)color;
- (void)setCaretLineBackground:(NSColor *)color visible:(BOOL)visible;
/// Selection colour, applied to the inactive selection too, so a match the
/// find bar selected stays visible while the find field has keyboard focus.
- (void)setSelectionBackground:(NSColor *)color;
/// Background of the fold margin (both of its colours), normally the same as
/// the line-number margin.
- (void)setFoldMarginBackground:(NSColor *)color;

#pragma mark - Margins and display

- (void)showLineNumbers:(BOOL)visible NS_SWIFT_NAME(showLineNumbers(_:));
- (void)showFoldMargin:(BOOL)visible NS_SWIFT_NAME(showFoldMargin(_:));
- (void)showBookmarkMargin:(BOOL)visible NS_SWIFT_NAME(showBookmarkMargin(_:));
@property(nonatomic) BOOL wordWrap;
@property(nonatomic) BOOL showWhitespace;
@property(nonatomic) BOOL showEndOfLine;
@property(nonatomic) BOOL showIndentGuides;
@property(nonatomic) NSInteger tabWidth;
@property(nonatomic) BOOL useTabs;
@property(nonatomic) NSInteger zoomLevel;
@property(nonatomic) BOOL readOnly;
/// End-of-line mode: 0 = CRLF, 1 = CR, 2 = LF (Scintilla's SC_EOL_* order).
@property(nonatomic) NSInteger eolMode;
- (void)convertAllLineEndsTo:(NSInteger)eolMode NS_SWIFT_NAME(convertAllLineEnds(to:));

#pragma mark - Folding

- (void)toggleFoldAtLine:(NSInteger)line NS_SWIFT_NAME(toggleFold(atLine:));
- (void)foldAll;
- (void)unfoldAll;

#pragma mark - Bookmarks

- (void)toggleBookmarkAtLine:(NSInteger)line NS_SWIFT_NAME(toggleBookmark(atLine:));
- (NSInteger)nextBookmarkAfterLine:(NSInteger)line NS_SWIFT_NAME(nextBookmark(afterLine:));
- (NSInteger)previousBookmarkBeforeLine:(NSInteger)line NS_SWIFT_NAME(previousBookmark(beforeLine:));
- (void)clearAllBookmarks;

#pragma mark - Search

/// Search the buffer. `flags` is a Scintilla search-flag bitmask; use
/// MPSearchFlags below rather than literals.
/// Returns the match start, or -1 when there is no match. On a match the
/// target range is left set to it, so `replaceTargetWith:` can follow.
- (NSInteger)findText:(NSString *)needle
                 from:(NSInteger)start
                   to:(NSInteger)end
                flags:(NSInteger)flags NS_SWIFT_NAME(findText(_:from:to:flags:));
/// Replace the current target range. Returns the replacement's byte length.
- (NSInteger)replaceTargetWith:(NSString *)replacement NS_SWIFT_NAME(replaceTarget(with:));
/// As above but with `\1`-style group references expanded; regex searches only.
- (NSInteger)replaceTargetWithExpanded:(NSString *)replacement NS_SWIFT_NAME(replaceTarget(withExpanded:));
@property(nonatomic, readonly) NSInteger targetStart;
@property(nonatomic, readonly) NSInteger targetEnd;

/// Highlight every occurrence of `needle` using indicator `indicator`.
/// Returns the number of occurrences marked.
- (NSInteger)markAllOccurrencesOf:(NSString *)needle
                            flags:(NSInteger)flags
                        indicator:(NSInteger)indicator
                            color:(NSColor *)color
    NS_SWIFT_NAME(markAllOccurrences(of:flags:indicator:color:));
- (void)clearIndicator:(NSInteger)indicator NS_SWIFT_NAME(clearIndicator(_:));

@end


/// Scintilla search flags, re-exported so Swift need not know SCFIND_*.
///
/// The values are Scintilla's own (SCFIND_* in Scintilla.h) and are passed
/// straight through to SCI_SETSEARCHFLAGS, so they must match exactly. They
/// once were 1, 2, 4, 8...: whole word happened to coincide with SCFIND_WHOLEWORD
/// and worked, while Match Case and regular expressions were silently ignored.
/// ScintillaConstantsTests checks these against the vendored header.
typedef NS_OPTIONS(NSInteger, MPSearchFlags) {
	MPSearchFlagNone          = 0,
	MPSearchFlagWholeWord     = 0x2,          // SCFIND_WHOLEWORD
	MPSearchFlagMatchCase     = 0x4,          // SCFIND_MATCHCASE
	MPSearchFlagWordStart     = 0x00100000,   // SCFIND_WORDSTART
	MPSearchFlagRegExp        = 0x00200000,   // SCFIND_REGEXP
	MPSearchFlagPosix         = 0x00400000,   // SCFIND_POSIX
	MPSearchFlagCxx11RegEx    = 0x00800000,   // SCFIND_CXX11REGEX
};

NS_ASSUME_NONNULL_END
