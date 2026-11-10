//
//  regex_conformance.cxx
//  MacPad — regex dialect conformance harness.
//
//  Drives MacPad's regex engine through a real Scintilla Document, exercising
//  the exact code path the app uses: Document::FindText and
//  Document::SubstituteByPosition, which reach BoostRegexSearch through
//  Scintilla's CreateRegexSearch hook.
//
//  This deliberately links only Scintilla's platform-independent core, so it
//  builds and runs anywhere a C++17 compiler does — no Xcode, no macOS, no
//  AppKit. That makes the search engine testable in CI on Linux.
//
//  Each expectation below is the documented behaviour of Boost.Regex's Perl
//  syntax as MacPad configures it. This file is the definition of MacPad's
//  regex dialect.
//
//  Build and run:  Tests/Integration/run.sh
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

#include <cstddef>
#include <cstdlib>
#include <cstdint>
#include <cassert>
#include <cstring>
#include <cstdarg>
#include <cstdio>
#include <cmath>
#include <climits>

#include <stdexcept>
#include <new>
#include <utility>
#include <string>
#include <string_view>
#include <vector>
#include <array>
#include <map>
#include <forward_list>
#include <optional>
#include <algorithm>
#include <iterator>
#include <memory>
#include <chrono>

// Document.h needs the same include chain Document.cxx assembles before it.
#include "ScintillaTypes.h"
#include "ILoader.h"
#include "ILexer.h"
#include "Debugging.h"
#include "CharacterType.h"
#include "CharacterCategoryMap.h"
#include "Position.h"
#include "SplitVector.h"
#include "Partitioning.h"
#include "RunStyles.h"
#include "CellBuffer.h"
#include "PerLine.h"
#include "CharClassify.h"
#include "Decoration.h"
#include "CaseFolder.h"
#include "Document.h"

using namespace Scintilla;
using namespace Scintilla::Internal;

// ---------------------------------------------------------------- Platform
// The core expects these; the GUI layers normally provide them.
namespace Scintilla::Internal::Platform {
void DebugPrintf(const char *format, ...) noexcept {
	va_list args;
	va_start(args, format);
	vfprintf(stderr, format, args);
	va_end(args);
}
bool ShowAssertionPopUps(bool) noexcept { return false; }
void Assert(const char *c, const char *file, int line) noexcept {
	fprintf(stderr, "Scintilla assertion failed: %s at %s:%d\n", c, file, line);
}
}  // namespace Scintilla::Internal::Platform

// ------------------------------------------------------------------- harness
namespace {

int checks = 0;
int failures = 0;

void report(bool ok, const std::string &label, const std::string &got,
            const std::string &want) {
	++checks;
	if (ok) {
		printf("  pass  %s\n", label.c_str());
		return;
	}
	++failures;
	printf("  FAIL  %s\n          got  [%s]\n          want [%s]\n",
	       label.c_str(), got.c_str(), want.c_str());
}

constexpr FindOption kRegexFlags =
	static_cast<FindOption>(static_cast<int>(FindOption::RegExp) |
	                        static_cast<int>(FindOption::MatchCase));

std::string documentText(Document &doc) {
	std::string out(static_cast<size_t>(doc.Length()), '\0');
	if (!out.empty()) {
		doc.GetCharRange(out.data(), 0, doc.Length());
	}
	return out;
}

/// What does `pattern` match in `subject`? Returns the matched text, or a
/// marker when there is no match.
std::string findMatch(const std::string &subject, const std::string &pattern,
                      bool caseSensitive = true) {
	Document doc(DocumentOption::Default);
	doc.InsertString(0, subject);
	const FindOption flags = caseSensitive
		? kRegexFlags
		: static_cast<FindOption>(static_cast<int>(FindOption::RegExp));

	// *length is in/out: on entry it must be the pattern length.
	Sci::Position length = static_cast<Sci::Position>(pattern.size());
	const Sci::Position at = doc.FindText(0, doc.Length(), pattern.c_str(), flags, &length);
	if (at < 0) {
		return "<no match>";
	}
	return subject.substr(static_cast<size_t>(at), static_cast<size_t>(length));
}

/// Replace every match, the way Replace All does.
std::string replaceAll(const std::string &subject, const std::string &pattern,
                       const std::string &replacement) {
	Document doc(DocumentOption::Default);
	doc.InsertString(0, subject);

	Sci::Position cursor = 0;
	int guard = 0;
	while (cursor <= doc.Length() && ++guard < 1000) {
		Sci::Position length = static_cast<Sci::Position>(pattern.size());
		const Sci::Position at =
			doc.FindText(cursor, doc.Length(), pattern.c_str(), kRegexFlags, &length);
		if (at < 0) {
			break;
		}
		Sci::Position replacementLength = 0;
		const char *expanded =
			doc.SubstituteByPosition(replacement.c_str(), &replacementLength);
		const std::string expandedCopy(expanded ? expanded : "",
		                               static_cast<size_t>(replacementLength));

		const Sci::Position matchedLength = length;
		doc.DeleteChars(at, matchedLength);
		doc.InsertString(at, expandedCopy.data(),
		                 static_cast<Sci::Position>(expandedCopy.size()));

		// Advance past the replacement, and one further for a zero-width
		// match, which consumed no source character.
		cursor = at + static_cast<Sci::Position>(expandedCopy.size())
		       + ((matchedLength == 0) ? 1 : 0);
	}
	return documentText(doc);
}

/// Where does a search starting at `from` land? Used for direction tests.
Sci::Position findFrom(const std::string &subject, const std::string &pattern,
                       Sci::Position from, Sci::Position to) {
	Document doc(DocumentOption::Default);
	doc.InsertString(0, subject);
	Sci::Position length = static_cast<Sci::Position>(pattern.size());
	return doc.FindText(from, to, pattern.c_str(), kRegexFlags, &length);
}

void expectMatch(const std::string &label, const std::string &subject,
                 const std::string &pattern, const std::string &want) {
	const std::string got = findMatch(subject, pattern);
	report(got == want, label, got, want);
}

void expectReplace(const std::string &label, const std::string &subject,
                   const std::string &pattern, const std::string &replacement,
                   const std::string &want) {
	const std::string got = replaceAll(subject, pattern, replacement);
	report(got == want, label, got, want);
}

void expectPosition(const std::string &label, Sci::Position got, Sci::Position want) {
	report(got == want, label, std::to_string(got), std::to_string(want));
}

}  // namespace

int main() {
	printf("MacPad regex conformance — Perl dialect via Boost.Regex\n\n");

	printf("Patterns\n");
	expectMatch("literal", "hello world", "world", "world");
	expectMatch("character class", "abc123", "[0-9]+", "123");
	expectMatch("group and quantifier", "aaab", "a+b", "aaab");
	expectMatch("alternation", "cat dog", "dog|bird", "dog");
	expectMatch("word boundary", "the theme", "\\bthe\\b", "the");
	expectMatch("lazy quantifier", "<a><b>", "<.+?>", "<a>");
	expectMatch("fixed lookbehind", "abc", "(?<=ab)c", "c");
	expectMatch("lookahead", "foobar", "foo(?=bar)", "foo");
	expectMatch("named group", "x=1", "(?<key>\\w+)=", "x=");

	printf("\n\\K match reset (ICU has no equivalent)\n");
	expectMatch("foo\\Kbar reports only bar", "foobar", "foo\\Kbar", "bar");

	printf("\nAlways multi-line (Scintilla's built-in engine cannot do this at all)\n");
	expectMatch("pattern spans a line end", "a\nb", "a\\nb", "a\nb");
	expectMatch("\\R matches CRLF", "a\r\nb", "a\\Rb", "a\r\nb");
	expectMatch("\\R matches LF", "a\nb", "a\\Rb", "a\nb");
	expectMatch("negated class crosses lines", "a\nb", "a[^x]b", "a\nb");

	printf("\n\". matches newline\" — off by default, (?s) opts in\n");
	expectMatch("dot stops at a line end by default", "a\nb", "a.b", "<no match>");
	expectMatch("(?s) lets dot cross", "a\nb", "(?s)a.b", "a\nb");
	expectMatch("(?-s) is explicit off", "a\nb", "(?-s)a.b", "<no match>");

	printf("\nAnchors against the real buffer, not a truncated range\n");
	expectMatch("^ anchors to a line start", "one\ntwo", "^two", "two");
	expectMatch("$ anchors to a line end", "one\ntwo", "one$", "one");

	printf("\nReplacement syntax\n");
	expectReplace("$1 backreference", "ab", "(a)(b)", "$2$1", "ba");
	expectReplace("\\1 backreference", "ab", "(a)(b)", "\\2\\1", "ba");
	expectReplace("${1} braced", "ab", "(a)(b)", "${2}${1}", "ba");
	expectReplace("$& whole match", "abc", "b", "[$&]", "a[b]c");
	expectReplace("\\U...\\E uppercases", "hello there", "(\\w+)", "\\U$1\\E",
	              "HELLO THERE");
	expectReplace("\\L...\\E lowercases", "HELLO", "(\\w+)", "\\L$1\\E", "hello");
	expectReplace("\\u uppercases one char", "hello world", "\\b(\\w)", "\\u$1",
	              "Hello World");
	expectReplace("insert a newline", "a b", " ", "\\n", "a\nb");
	expectReplace("delete matches", "a1b2c3", "[0-9]", "", "abc");

	printf("\nCase sensitivity\n");
	report(findMatch("HELLO", "hello", false) == "HELLO",
	       "case-insensitive search matches", findMatch("HELLO", "hello", false), "HELLO");
	report(findMatch("HELLO", "hello", true) == "<no match>",
	       "case-sensitive search does not", findMatch("HELLO", "hello", true),
	       "<no match>");

	printf("\nDirection and ranges\n");
	// Scintilla signals a backwards search by passing minPos > maxPos.
	expectPosition("forwards finds the first match",
	               findFrom("x-x-x", "x", 0, 5), 0);
	expectPosition("forwards from mid-buffer",
	               findFrom("x-x-x", "x", 1, 5), 2);
	expectPosition("backwards finds the last match",
	               findFrom("x-x-x", "x", 5, 0), 4);
	expectPosition("backwards is bounded by maxPos",
	               findFrom("x-x-x", "x", 3, 0), 2);
	expectPosition("a match crossing the range end is rejected",
	               findFrom("abcdef", "cde", 0, 4), -1);

	printf("\nRobustness\n");
	expectMatch("an invalid pattern reports no match", "abc", "(unclosed", "<no match>");
	expectMatch("an empty-capable pattern terminates", "abc", "x*", "");
	expectReplace("a zero-width match does not loop", "abc", "x*", "-",
	              "-a-b-c-");

	printf("\n%d checks, %d failure%s\n", checks, failures,
	       failures == 1 ? "" : "s");
	return failures == 0 ? 0 : 1;
}
