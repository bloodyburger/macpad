//
//  MPEditorView.mm
//  MacPad — Objective-C++ bridge over Scintilla's Cocoa backend.
//
//  Copyright (C) 2026 MacPad contributors.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

#import "MPEditorView.h"

#import "ScintillaView.h"
#import "Scintilla.h"

// ILexer.h must precede Lexilla.h. In C++ Lexilla.h does
// `using Scintilla::ILexer5;` and says outright that ILexer.h has to have been
// included first; only its C path falls back to `typedef void ILexer5`.
// ScintillaView.h pulls in Scintilla.h but not ILexer.h.
#import "ILexer.h"
#import "Lexilla.h"

#include <cmath>     // lround
#include <cstring>   // strlen
#include <string>
#include <vector>

/// Scintilla's lParam carries pointers as integers. Be explicit about it.
static inline NSInteger MPPtr(const void *p) {
	return static_cast<NSInteger>(reinterpret_cast<uintptr_t>(p));
}

// Margin indices, left to right.
static const int kMarginLineNumbers = 0;
static const int kMarginBookmarks   = 1;
static const int kMarginFolding     = 2;

// Marker number used for bookmarks. Scintilla reserves 25-31 for folding.
static const int kMarkerBookmark = 1;

@interface MPEditorView () <ScintillaNotificationProtocol>
@end

@implementation MPEditorView {
	ScintillaView *_sci;
	NSString *_lexerName;
}

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		[self mp_buildScintilla];
	}
	return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if (self) {
		[self mp_buildScintilla];
	}
	return self;
}

- (void)mp_buildScintilla {
	// ScintillaView must be laid out by frame, not by Auto Layout constraints.
	//
	// It does all of its internal layout inside -setFrame:, which is where it
	// calls positionSubViews and mBackend->Resize(). Its scroll view is created
	// at a placeholder 100x10 and its content view at NSZeroRect, and nothing
	// but -setFrame: ever corrects that. Auto Layout assigns frames without
	// reliably routing through -setFrame:, so under constraints Scintilla keeps
	// the placeholder sizes and draws nothing at all — the document fills with
	// text and the view stays blank.
	//
	// So: no constraints, no autoresizing mask either (that path goes through
	// -setFrameSize:), and -layout drives -setFrame: explicitly.
	_sci = [[ScintillaView alloc] initWithFrame:self.bounds];
	_sci.translatesAutoresizingMaskIntoConstraints = YES;
	_sci.autoresizingMask = NSViewNotSizable;
	[self addSubview:_sci];
	_sci.delegate = self;

	// Scintilla must be told the buffer is UTF-8; without this it treats bytes
	// as a legacy code page and multi-byte characters break.
	[self send:SCI_SETCODEPAGE wparam:SC_CP_UTF8];

	// Multiple selections and typing into all of them, on by default.
	[self send:SCI_SETMULTIPLESELECTION wparam:1];
	[self send:SCI_SETADDITIONALSELECTIONTYPING wparam:1];
	[self send:SCI_SETMULTIPASTE wparam:1];

	[self mp_configureMargins];
}

- (void)mp_configureMargins {
	[self send:SCI_SETMARGINS wparam:3];

	[self send:SCI_SETMARGINTYPEN wparam:kMarginLineNumbers lparam:SC_MARGIN_NUMBER];

	[self send:SCI_SETMARGINTYPEN wparam:kMarginBookmarks lparam:SC_MARGIN_SYMBOL];
	[self send:SCI_SETMARGINMASKN wparam:kMarginBookmarks lparam:(1 << kMarkerBookmark)];
	[self send:SCI_SETMARGINSENSITIVEN wparam:kMarginBookmarks lparam:1];
	[self send:SCI_MARKERDEFINE wparam:kMarkerBookmark lparam:SC_MARK_CIRCLE];

	[self send:SCI_SETMARGINTYPEN wparam:kMarginFolding lparam:SC_MARGIN_SYMBOL];
	[self send:SCI_SETMARGINMASKN wparam:kMarginFolding lparam:(NSInteger)SC_MASK_FOLDERS];
	[self send:SCI_SETMARGINSENSITIVEN wparam:kMarginFolding lparam:1];

	// Box-tree fold markers.
	const int folderMarkers[7][2] = {
		{SC_MARKNUM_FOLDEROPEN,    SC_MARK_BOXMINUS},
		{SC_MARKNUM_FOLDER,        SC_MARK_BOXPLUS},
		{SC_MARKNUM_FOLDERSUB,     SC_MARK_VLINE},
		{SC_MARKNUM_FOLDERTAIL,    SC_MARK_LCORNER},
		{SC_MARKNUM_FOLDEREND,     SC_MARK_BOXPLUS},
		{SC_MARKNUM_FOLDEROPENMID, SC_MARK_BOXMINUS},
		{SC_MARKNUM_FOLDERMIDTAIL, SC_MARK_TCORNER},
	};
	for (int i = 0; i < 7; i++) {
		[self send:SCI_MARKERDEFINE wparam:folderMarkers[i][0] lparam:folderMarkers[i][1]];
	}
}

#pragma mark - Layout

/// Give ScintillaView its frame through -setFrame:, which is the only path
/// that makes it reposition its scroll view, margin view and content view.
- (void)mp_resizeScintilla {
	const NSRect target = self.bounds;
	if (!NSEqualRects(_sci.frame, target)) {
		[_sci setFrame:target];
	}
}

- (void)layout {
	[super layout];
	[self mp_resizeScintilla];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
	[super resizeSubviewsWithOldSize:oldSize];
	[self mp_resizeScintilla];
}

- (void)setFrameSize:(NSSize)newSize {
	[super setFrameSize:newSize];
	// Auto Layout resizes a constrained view through -setFrameSize:, not
	// -setFrame:, so this is the hook that actually fires for us.
	[self mp_resizeScintilla];
}

- (void)viewDidMoveToWindow {
	[super viewDidMoveToWindow];
	// The first real size usually arrives with the window, and the margin
	// width below could not be measured before there was a drawing surface.
	[self mp_resizeScintilla];
}

#pragma mark - Diagnostics

- (NSString *)layoutDescription {
	NSMutableString *out = [NSMutableString string];
	[out appendFormat:@"  MPEditorView   frame=%@ bounds=%@ hidden=%d window=%@\n",
	 NSStringFromRect(self.frame), NSStringFromRect(self.bounds),
	 (int)self.isHidden, self.window ? @"yes" : @"NO"];

	if (_sci == nil) {
		[out appendString:@"  ScintillaView  *** nil ***\n"];
		return out;
	}
	[out appendFormat:@"  ScintillaView  frame=%@ hidden=%d\n",
	 NSStringFromRect(_sci.frame), (int)_sci.isHidden];

	NSScrollView *sv = _sci.scrollView;
	[out appendFormat:@"  scrollView     frame=%@\n",
	 sv ? NSStringFromRect(sv.frame) : @"(nil)"];
	[out appendFormat:@"  documentView   frame=%@\n",
	 sv.documentView ? NSStringFromRect(sv.documentView.frame) : @"(nil)"];

	NSView *content = (NSView *)[_sci content];
	[out appendFormat:@"  SCIContentView frame=%@\n",
	 content ? NSStringFromRect(content.frame) : @"(nil)"];

	[out appendFormat:@"  margins: n=%ld lineNo=%ld bookmark=%ld fold=%ld\n",
	 (long)[self send:SCI_GETMARGINS],
	 (long)[self send:SCI_GETMARGINWIDTHN wparam:kMarginLineNumbers],
	 (long)[self send:SCI_GETMARGINWIDTHN wparam:kMarginBookmarks],
	 (long)[self send:SCI_GETMARGINWIDTHN wparam:kMarginFolding]];
	[out appendFormat:@"  doc: length=%ld lines=%ld firstResponder=%@\n",
	 (long)self.length, (long)self.lineCount,
	 self.window.firstResponder ?: @"(none)"];
	return out;
}

#pragma mark - Raw message channel

- (NSInteger)send:(NSInteger)message wparam:(NSInteger)wparam lparam:(NSInteger)lparam {
	return (NSInteger)[ScintillaView directCall:_sci
	                                    message:(unsigned int)message
	                                     wParam:(uptr_t)wparam
	                                     lParam:(sptr_t)lparam];
}

- (NSInteger)send:(NSInteger)message wparam:(NSInteger)wparam {
	return [self send:message wparam:wparam lparam:0];
}

- (NSInteger)send:(NSInteger)message {
	return [self send:message wparam:0 lparam:0];
}

#pragma mark - Content

- (NSString *)text {
	const NSInteger len = [self send:SCI_GETLENGTH];
	if (len <= 0) {
		return @"";
	}
	std::vector<char> buffer(static_cast<size_t>(len) + 1, '\0');
	[self send:SCI_GETTEXT wparam:(len + 1) lparam:MPPtr(buffer.data())];
	NSString *s = [[NSString alloc] initWithBytes:buffer.data()
	                                       length:(NSUInteger)len
	                                     encoding:NSUTF8StringEncoding];
	return s ?: @"";
}

- (void)setText:(NSString *)text {
	const char *utf8 = [text UTF8String] ?: "";
	[self send:SCI_SETTEXT wparam:0 lparam:MPPtr(utf8)];
}

- (NSInteger)length {
	return [self send:SCI_GETLENGTH];
}

- (NSInteger)lineCount {
	return [self send:SCI_GETLINECOUNT];
}

- (NSString *)selectedText {
	const NSInteger len = [self send:SCI_GETSELTEXT wparam:0 lparam:0];
	if (len <= 0) {
		return @"";
	}
	std::vector<char> buffer(static_cast<size_t>(len) + 1, '\0');
	[self send:SCI_GETSELTEXT wparam:0 lparam:MPPtr(buffer.data())];
	NSString *s = [NSString stringWithUTF8String:buffer.data()];
	return s ?: @"";
}

- (void)insertTextAtCaret:(NSString *)string {
	[self replaceSelectionWith:string];
}

- (void)replaceSelectionWith:(NSString *)string {
	const char *utf8 = [string UTF8String] ?: "";
	[self send:SCI_REPLACESEL wparam:0 lparam:MPPtr(utf8)];
}

#pragma mark - Lines and ranges

- (NSString *)textOfLine:(NSInteger)line {
	if (line < 0 || line >= self.lineCount) {
		return @"";
	}
	const NSInteger len = [self send:SCI_LINELENGTH wparam:line];
	if (len <= 0) {
		return @"";
	}
	std::vector<char> buffer(static_cast<size_t>(len) + 1, '\0');
	[self send:SCI_GETLINE wparam:line lparam:MPPtr(buffer.data())];
	NSString *s = [[NSString alloc] initWithBytes:buffer.data()
	                                       length:(NSUInteger)len
	                                     encoding:NSUTF8StringEncoding];
	return s ?: @"";
}

- (NSInteger)lengthOfLine:(NSInteger)line {
	return [self send:SCI_LINELENGTH wparam:line];
}

- (NSInteger)endPositionOfLine:(NSInteger)line {
	return [self send:SCI_GETLINEENDPOSITION wparam:line];
}

- (void)insertText:(NSString *)string atPosition:(NSInteger)position {
	const char *utf8 = [string UTF8String] ?: "";
	[self send:SCI_INSERTTEXT wparam:position lparam:MPPtr(utf8)];
}

- (void)deleteByteRange:(NSRange)range {
	[self send:SCI_DELETERANGE wparam:(NSInteger)range.location lparam:(NSInteger)range.length];
}

- (NSInteger)selectionStart { return [self send:SCI_GETSELECTIONSTART]; }
- (NSInteger)selectionEnd   { return [self send:SCI_GETSELECTIONEND]; }

#pragma mark - Undo grouping

- (void)beginUndoAction { [self send:SCI_BEGINUNDOACTION]; }
- (void)endUndoAction   { [self send:SCI_ENDUNDOACTION]; }

#pragma mark - Documents (tabs)

- (NSInteger)documentPointer {
	return [self send:SCI_GETDOCPOINTER];
}

- (void)setDocumentPointer:(NSInteger)documentPointer {
	[self send:SCI_SETDOCPOINTER wparam:0 lparam:documentPointer];
}

- (NSInteger)createDocument {
	// bytes = 0 (default allocation), documentOptions = SC_DOCUMENTOPTION_DEFAULT
	return [self send:SCI_CREATEDOCUMENT wparam:0 lparam:0];
}

- (void)addRefDocument:(NSInteger)doc {
	[self send:SCI_ADDREFDOCUMENT wparam:0 lparam:doc];
}

- (void)releaseDocument:(NSInteger)doc {
	[self send:SCI_RELEASEDOCUMENT wparam:0 lparam:doc];
}

#pragma mark - Undo / clipboard

- (void)undo       { [self send:SCI_UNDO]; }
- (void)redo       { [self send:SCI_REDO]; }
- (BOOL)canUndo    { return [self send:SCI_CANUNDO] != 0; }
- (BOOL)canRedo    { return [self send:SCI_CANREDO] != 0; }
- (void)cutSelection       { [self send:SCI_CUT]; }
- (void)copySelection      { [self send:SCI_COPY]; }
- (void)pasteFromClipboard { [self send:SCI_PASTE]; }
- (void)selectAllText      { [self send:SCI_SELECTALL]; }
- (void)deleteSelection    { [self send:SCI_CLEAR]; }
- (void)uppercaseSelection { [self send:SCI_UPPERCASE]; }
- (void)lowercaseSelection { [self send:SCI_LOWERCASE]; }
- (BOOL)hasSelection       { return [self send:SCI_GETSELECTIONEMPTY] == 0; }
- (BOOL)canPaste           { return [self send:SCI_CANPASTE] != 0; }

- (NSString *)textInByteRange:(NSRange)range {
	const NSInteger documentLength = self.length;
	const NSInteger start = (NSInteger)range.location;
	const NSInteger end = MIN((NSInteger)NSMaxRange(range), documentLength);
	const NSInteger len = end - start;
	if (start < 0 || len <= 0) {
		return @"";
	}
	[self send:SCI_SETTARGETRANGE wparam:start lparam:end];
	std::vector<char> buffer(static_cast<size_t>(len) + 1, '\0');
	[self send:SCI_GETTARGETTEXT wparam:0 lparam:MPPtr(buffer.data())];
	NSString *s = [[NSString alloc] initWithBytes:buffer.data()
	                                       length:(NSUInteger)len
	                                     encoding:NSUTF8StringEncoding];
	return s ?: @"";
}

// ScintillaView asks its own -menuForEvent: first and falls back to
// Scintilla's built-in menu only when that returns nil, so the view's menu
// property is the hook for a custom right-click menu.
- (NSMenu *)contextMenu { return _sci.menu; }
- (void)setContextMenu:(NSMenu *)contextMenu { _sci.menu = contextMenu; }
- (void)markSavePoint { [self send:SCI_SETSAVEPOINT]; }
- (BOOL)isDirty    { return [self send:SCI_GETMODIFY] != 0; }

#pragma mark - Caret, selection, navigation

- (NSInteger)currentPosition {
	return [self send:SCI_GETCURRENTPOS];
}

- (void)setCurrentPosition:(NSInteger)currentPosition {
	[self send:SCI_SETCURRENTPOS wparam:currentPosition];
}

- (NSInteger)currentLine {
	return [self send:SCI_LINEFROMPOSITION wparam:[self send:SCI_GETCURRENTPOS]];
}

- (NSInteger)currentColumn {
	return [self send:SCI_GETCOLUMN wparam:[self send:SCI_GETCURRENTPOS]];
}

- (void)setSelectionFrom:(NSInteger)anchor to:(NSInteger)caret {
	[self send:SCI_SETSEL wparam:anchor lparam:caret];
}

- (void)gotoLine:(NSInteger)line        { [self send:SCI_GOTOLINE wparam:line]; }
- (void)gotoPosition:(NSInteger)position { [self send:SCI_GOTOPOS wparam:position]; }
- (void)scrollCaretIntoView             { [self send:SCI_SCROLLCARET]; }

- (NSInteger)positionForLine:(NSInteger)line {
	return [self send:SCI_POSITIONFROMLINE wparam:line];
}

- (NSInteger)lineForPosition:(NSInteger)position {
	return [self send:SCI_LINEFROMPOSITION wparam:position];
}

#pragma mark - Syntax highlighting

- (BOOL)setLexerNamed:(NSString *)lexerName {
	void *lexer = CreateLexer([lexerName UTF8String]);
	if (lexer == nullptr) {
		return NO;
	}
	[self send:SCI_SETILEXER wparam:0 lparam:MPPtr(lexer)];
	_lexerName = [lexerName copy];

	// Lexers only emit fold levels when asked to.
	[self send:SCI_SETPROPERTY wparam:MPPtr("fold") lparam:MPPtr("1")];
	[self send:SCI_SETPROPERTY wparam:MPPtr("fold.compact") lparam:MPPtr("0")];
	return YES;
}

- (NSString *)lexerName {
	return _lexerName;
}

- (void)setKeywords:(NSString *)keywords forSet:(NSInteger)index {
	const char *utf8 = [keywords UTF8String] ?: "";
	[self send:SCI_SETKEYWORDS wparam:index lparam:MPPtr(utf8)];
}

- (void)colouriseFrom:(NSInteger)start to:(NSInteger)end {
	[self send:SCI_COLOURISE wparam:start lparam:end];
}

+ (NSArray<NSString *> *)availableLexerNames {
	NSMutableArray<NSString *> *names = [NSMutableArray array];
	const int count = GetLexerCount();
	for (int i = 0; i < count; i++) {
		char buffer[128] = {0};
		GetLexerName((unsigned int)i, buffer, (int)sizeof(buffer));
		NSString *name = [NSString stringWithUTF8String:buffer];
		if (name.length > 0) {
			[names addObject:name];
		}
	}
	return [names sortedArrayUsingSelector:@selector(compare:)];
}

#pragma mark - Styling

/// Scintilla takes colours as 0x00BBGGRR integers.
static NSInteger MPColourToScintilla(NSColor *color) {
	NSColor *rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
	if (rgb == nil) {
		return 0;
	}
	const NSInteger r = (NSInteger)lround(rgb.redComponent   * 255.0);
	const NSInteger g = (NSInteger)lround(rgb.greenComponent * 255.0);
	const NSInteger b = (NSInteger)lround(rgb.blueComponent  * 255.0);
	return (b << 16) | (g << 8) | r;
}

- (void)setStyle:(NSInteger)style foreground:(NSColor *)color {
	[self send:SCI_STYLESETFORE wparam:style lparam:MPColourToScintilla(color)];
}

- (void)setStyle:(NSInteger)style background:(NSColor *)color {
	[self send:SCI_STYLESETBACK wparam:style lparam:MPColourToScintilla(color)];
}

- (void)setStyle:(NSInteger)style bold:(BOOL)bold {
	[self send:SCI_STYLESETBOLD wparam:style lparam:(bold ? 1 : 0)];
}

- (void)setStyle:(NSInteger)style italic:(BOOL)italic {
	[self send:SCI_STYLESETITALIC wparam:style lparam:(italic ? 1 : 0)];
}

- (void)setStyle:(NSInteger)style underline:(BOOL)underline {
	[self send:SCI_STYLESETUNDERLINE wparam:style lparam:(underline ? 1 : 0)];
}

- (void)setStyle:(NSInteger)style fontName:(NSString *)fontName size:(CGFloat)size {
	const char *utf8 = [fontName UTF8String] ?: "Menlo";
	[self send:SCI_STYLESETFONT wparam:style lparam:MPPtr(utf8)];
	[self send:SCI_STYLESETSIZE wparam:style lparam:(NSInteger)lround(size)];
}

- (void)applyDefaultStyleToAll {
	[self send:SCI_STYLECLEARALL];
}

- (void)setCaretForeground:(NSColor *)color {
	[self send:SCI_SETCARETFORE wparam:MPColourToScintilla(color)];
}

- (void)setCaretLineBackground:(NSColor *)color visible:(BOOL)visible {
	[self send:SCI_SETCARETLINEBACK wparam:MPColourToScintilla(color)];
	[self send:SCI_SETCARETLINEVISIBLE wparam:(visible ? 1 : 0)];
}

- (void)setSelectionBackground:(NSColor *)color {
	// Element colours, not the deprecated SCI_SETSELBACK: that one leaves the
	// *inactive* selection on Scintilla's default, a faint grey, and the find
	// bar keeps keyboard focus after Find Next, so the match it had just
	// selected was all but invisible. Opaque, same colour, focused or not.
	const NSInteger rgba = MPColourToScintilla(color) | ((NSInteger)0xFF << 24);
	const int elements[] = {
		SC_ELEMENT_SELECTION_BACK,
		SC_ELEMENT_SELECTION_ADDITIONAL_BACK,
		SC_ELEMENT_SELECTION_INACTIVE_BACK,
		SC_ELEMENT_SELECTION_INACTIVE_ADDITIONAL_BACK,
	};
	for (int element : elements) {
		[self send:SCI_SETELEMENTCOLOUR wparam:element lparam:rgba];
	}
}

- (void)setFoldMarginBackground:(NSColor *)color {
	[self send:SCI_SETFOLDMARGINCOLOUR wparam:1 lparam:MPColourToScintilla(color)];
	[self send:SCI_SETFOLDMARGINHICOLOUR wparam:1 lparam:MPColourToScintilla(color)];
}

#pragma mark - Margins and display

- (void)showLineNumbers:(BOOL)visible {
	if (!visible) {
		[self send:SCI_SETMARGINWIDTHN wparam:kMarginLineNumbers lparam:0];
		return;
	}
	// Width sized to the current line count.
	NSInteger digits = 1;
	for (NSInteger n = MAX((NSInteger)1, self.lineCount); n >= 10; n /= 10) {
		digits++;
	}
	NSMutableString *sample = [NSMutableString stringWithString:@"_"];
	for (NSInteger i = 0; i < digits; i++) {
		[sample appendString:@"9"];
	}
	NSInteger width = [self send:SCI_TEXTWIDTH
	                      wparam:STYLE_LINENUMBER
	                      lparam:MPPtr([sample UTF8String])];
	if (width <= 0) {
		// Scintilla cannot measure text until it has a drawing surface, and a
		// zero here would hide the margin for good. Approximate, and let a
		// later call refine it.
		width = 9 * (NSInteger)sample.length;
	}
	[self send:SCI_SETMARGINWIDTHN wparam:kMarginLineNumbers lparam:width];
}

- (void)showFoldMargin:(BOOL)visible {
	[self send:SCI_SETMARGINWIDTHN wparam:kMarginFolding lparam:(visible ? 14 : 0)];
}

- (void)showBookmarkMargin:(BOOL)visible {
	[self send:SCI_SETMARGINWIDTHN wparam:kMarginBookmarks lparam:(visible ? 16 : 0)];
}

- (BOOL)wordWrap { return [self send:SCI_GETWRAPMODE] != 0; }
- (void)setWordWrap:(BOOL)wordWrap {
	[self send:SCI_SETWRAPMODE wparam:(wordWrap ? SC_WRAP_WORD : SC_WRAP_NONE)];
}

- (BOOL)showWhitespace { return [self send:SCI_GETVIEWWS] != SCWS_INVISIBLE; }
- (void)setShowWhitespace:(BOOL)showWhitespace {
	[self send:SCI_SETVIEWWS wparam:(showWhitespace ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE)];
}

- (BOOL)showEndOfLine { return [self send:SCI_GETVIEWEOL] != 0; }
- (void)setShowEndOfLine:(BOOL)showEndOfLine {
	[self send:SCI_SETVIEWEOL wparam:(showEndOfLine ? 1 : 0)];
}

- (BOOL)showIndentGuides { return [self send:SCI_GETINDENTATIONGUIDES] != SC_IV_NONE; }
- (void)setShowIndentGuides:(BOOL)showIndentGuides {
	[self send:SCI_SETINDENTATIONGUIDES wparam:(showIndentGuides ? SC_IV_LOOKBOTH : SC_IV_NONE)];
}

- (NSInteger)tabWidth { return [self send:SCI_GETTABWIDTH]; }
- (void)setTabWidth:(NSInteger)tabWidth { [self send:SCI_SETTABWIDTH wparam:tabWidth]; }

- (BOOL)useTabs { return [self send:SCI_GETUSETABS] != 0; }
- (void)setUseTabs:(BOOL)useTabs { [self send:SCI_SETUSETABS wparam:(useTabs ? 1 : 0)]; }

- (NSInteger)zoomLevel { return [self send:SCI_GETZOOM]; }
- (void)setZoomLevel:(NSInteger)zoomLevel { [self send:SCI_SETZOOM wparam:zoomLevel]; }

- (BOOL)readOnly { return [self send:SCI_GETREADONLY] != 0; }
- (void)setReadOnly:(BOOL)readOnly { [self send:SCI_SETREADONLY wparam:(readOnly ? 1 : 0)]; }

- (NSInteger)eolMode { return [self send:SCI_GETEOLMODE]; }
- (void)setEolMode:(NSInteger)eolMode { [self send:SCI_SETEOLMODE wparam:eolMode]; }

- (void)convertAllLineEndsTo:(NSInteger)eolMode {
	[self send:SCI_CONVERTEOLS wparam:eolMode];
	[self send:SCI_SETEOLMODE wparam:eolMode];
}

#pragma mark - Folding

- (void)toggleFoldAtLine:(NSInteger)line {
	[self send:SCI_TOGGLEFOLD wparam:line];
}

- (void)foldAll {
	[self send:SCI_FOLDALL wparam:SC_FOLDACTION_CONTRACT];
}

- (void)unfoldAll {
	[self send:SCI_FOLDALL wparam:SC_FOLDACTION_EXPAND];
}

#pragma mark - Bookmarks

- (void)toggleBookmarkAtLine:(NSInteger)line {
	const NSInteger markers = [self send:SCI_MARKERGET wparam:line];
	if (markers & (1 << kMarkerBookmark)) {
		[self send:SCI_MARKERDELETE wparam:line lparam:kMarkerBookmark];
	} else {
		[self send:SCI_MARKERADD wparam:line lparam:kMarkerBookmark];
	}
}

- (NSInteger)nextBookmarkAfterLine:(NSInteger)line {
	return [self send:SCI_MARKERNEXT wparam:(line + 1) lparam:(1 << kMarkerBookmark)];
}

- (NSInteger)previousBookmarkBeforeLine:(NSInteger)line {
	return [self send:SCI_MARKERPREVIOUS wparam:(line - 1) lparam:(1 << kMarkerBookmark)];
}

- (void)clearAllBookmarks {
	[self send:SCI_MARKERDELETEALL wparam:kMarkerBookmark];
}

#pragma mark - Search

- (NSInteger)findText:(NSString *)needle
                 from:(NSInteger)start
                   to:(NSInteger)end
                flags:(NSInteger)flags {
	const char *utf8 = [needle UTF8String];
	if (utf8 == nullptr || *utf8 == '\0') {
		return -1;
	}
	[self send:SCI_SETSEARCHFLAGS wparam:flags];
	[self send:SCI_SETTARGETRANGE wparam:start lparam:(end < 0 ? self.length : end)];
	return [self send:SCI_SEARCHINTARGET
	           wparam:(NSInteger)strlen(utf8)
	           lparam:MPPtr(utf8)];
}

- (NSInteger)replaceTargetWith:(NSString *)replacement {
	const char *utf8 = [replacement UTF8String] ?: "";
	return [self send:SCI_REPLACETARGET
	           wparam:(NSInteger)strlen(utf8)
	           lparam:MPPtr(utf8)];
}

- (NSInteger)replaceTargetWithExpanded:(NSString *)replacement {
	const char *utf8 = [replacement UTF8String] ?: "";
	return [self send:SCI_REPLACETARGETRE
	           wparam:(NSInteger)strlen(utf8)
	           lparam:MPPtr(utf8)];
}

- (NSInteger)targetStart { return [self send:SCI_GETTARGETSTART]; }
- (NSInteger)targetEnd   { return [self send:SCI_GETTARGETEND]; }

- (NSInteger)markAllOccurrencesOf:(NSString *)needle
                            flags:(NSInteger)flags
                        indicator:(NSInteger)indicator
                            color:(NSColor *)color {
	[self send:SCI_INDICSETSTYLE wparam:indicator lparam:INDIC_ROUNDBOX];
	[self send:SCI_INDICSETFORE wparam:indicator lparam:MPColourToScintilla(color)];
	// Drawn under the text at a strength that reads as a highlight. The
	// default alpha of 30 is a tint that disappears on a dark theme.
	[self send:SCI_INDICSETUNDER wparam:indicator lparam:1];
	[self send:SCI_INDICSETALPHA wparam:indicator lparam:110];
	[self send:SCI_INDICSETOUTLINEALPHA wparam:indicator lparam:200];
	[self send:SCI_SETINDICATORCURRENT wparam:indicator];
	[self send:SCI_INDICATORCLEARRANGE wparam:0 lparam:self.length];

	const char *utf8 = [needle UTF8String];
	if (utf8 == nullptr || *utf8 == '\0') {
		return 0;
	}
	const NSInteger needleLength = (NSInteger)strlen(utf8);
	const NSInteger documentLength = self.length;

	NSInteger count = 0;
	NSInteger searchFrom = 0;
	[self send:SCI_SETSEARCHFLAGS wparam:flags];

	while (searchFrom < documentLength) {
		[self send:SCI_SETTARGETRANGE wparam:searchFrom lparam:documentLength];
		const NSInteger found = [self send:SCI_SEARCHINTARGET
		                            wparam:needleLength
		                            lparam:MPPtr(utf8)];
		if (found < 0) {
			break;
		}
		const NSInteger matchStart = self.targetStart;
		const NSInteger matchEnd = self.targetEnd;
		[self send:SCI_INDICATORFILLRANGE wparam:matchStart lparam:(matchEnd - matchStart)];
		count++;

		// A zero-length match (possible with regex) would loop forever.
		searchFrom = (matchEnd > matchStart) ? matchEnd : matchStart + 1;
	}
	return count;
}

- (void)clearIndicator:(NSInteger)indicator {
	[self send:SCI_SETINDICATORCURRENT wparam:indicator];
	[self send:SCI_INDICATORCLEARRANGE wparam:0 lparam:self.length];
}

#pragma mark - Testing support

- (void)deliverDroppedFileNotificationForTesting:(NSString *)path {
	SCNotification scn = {};
	scn.nmhdr.code = SCN_URIDROPPED;
	scn.text = path.UTF8String;
	[self notification:&scn];
}

#pragma mark - ScintillaNotificationProtocol

- (void)notification:(SCNotification *)notification {
	if (notification == nullptr) {
		return;
	}
	id<MPEditorViewDelegate> target = self.delegate;
	if (target == nil) {
		return;
	}

	switch (notification->nmhdr.code) {
		case SCN_MODIFIED: {
			const int kTextChange = SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT;
			if (notification->modificationType & kTextChange) {
				if ([target respondsToSelector:@selector(editorTextDidChange:)]) {
					[target editorTextDidChange:self];
				}
			}
			break;
		}
		case SCN_UPDATEUI: {
			if (notification->updated & SC_UPDATE_SELECTION) {
				if ([target respondsToSelector:@selector(editorSelectionDidChange:)]) {
					[target editorSelectionDidChange:self];
				}
			}
			break;
		}
		case SCN_SAVEPOINTREACHED:
			if ([target respondsToSelector:@selector(editorDidReachSavePoint:)]) {
				[target editorDidReachSavePoint:self];
			}
			break;
		case SCN_SAVEPOINTLEFT:
			if ([target respondsToSelector:@selector(editorDidLeaveSavePoint:)]) {
				[target editorDidLeaveSavePoint:self];
			}
			break;
		case SCN_MARGINCLICK: {
			const NSInteger line = [self send:SCI_LINEFROMPOSITION
			                          wparam:(NSInteger)notification->position];
			if (notification->margin == kMarginFolding) {
				[self toggleFoldAtLine:line];
				if ([target respondsToSelector:@selector(editorDidRequestFoldToggleAtLine:editor:)]) {
					[target editorDidRequestFoldToggleAtLine:line editor:self];
				}
			} else if ([target respondsToSelector:@selector(editorDidClickMargin:atPosition:editor:)]) {
				[target editorDidClickMargin:notification->margin
				                  atPosition:(NSInteger)notification->position
				                      editor:self];
			}
			break;
		}
		case SCN_URIDROPPED:
			// Scintilla's Cocoa layer accepts file drags itself and reports
			// each dropped file here as a path.
			if (notification->text != nullptr
			    && [target respondsToSelector:@selector(editor:didDropFileAtPath:)]) {
				NSString *path = [NSString stringWithUTF8String:notification->text];
				if (path.length > 0) {
					[target editor:self didDropFileAtPath:path];
				}
			}
			break;
		default:
			break;
	}
}

@end
