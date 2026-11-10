//
//  MacPad-Bridging-Header.h
//  Objective-C surface visible to Swift.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

#import "MPEditorView.h"

// Lexilla's SciLexer.h is 2200-odd `#define SCE_<LEXER>_<STYLE> n` constants
// and nothing else — no includes, no types. Exposing it here hands Swift every
// lexer's style numbers (SCE_C_COMMENT, SCE_PY_STRING, …) as Int32 constants,
// so the theme and language models can name styles instead of hard-coding
// numbers transcribed by hand.
#import "SciLexer.h"
