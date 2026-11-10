//
//  MPRegexSearch.cxx
//  MacPad — Perl-syntax regular expression search for Scintilla.
//
//  Scintilla lets a host replace its regex engine wholesale: define
//  SCI_OWNREGEX and supply Scintilla::Internal::CreateRegexSearch returning a
//  RegexSearchBase. MacPad uses that hook to install Boost.Regex, which gives
//  Find/Replace a full Perl dialect with case-converting replacements.
//
//  Why not the macOS-native options:
//
//    NSRegularExpression is ICU. It lacks things a code editor's search
//    needs: no \K in patterns, and in replacements no \U \L \u \l \E case
//    conversion, no $& / $` / $' / $+ / $^N, and no ?N:yes:no conditionals.
//    Its template syntax is $0..$n and nothing else. \U$1\E is an everyday
//    idiom, so ICU would be a visible downgrade, not a shortcut.
//
//    NSTextFinder, the native find bar, has no regular expression support at
//    all — literal, case-insensitive, whole-word and diacritic-insensitive
//    only. For an editor whose headline search feature is regex it is a
//    non-starter, however nice the stock UI is.
//
//  Boost.Regex costs almost nothing here: since 1.75 it compiles header-only
//  in BOOST_REGEX_STANDALONE mode, which turns itself on when
//  <boost/version.hpp> is absent. No library to build, no other Boost
//  libraries to vendor.
//
//  The dialect's behaviours, each established by experiment rather than
//  assumption (see Tests/Integration/regex_conformance.cxx):
//
//    * Perl syntax, and searches are ALWAYS multi-line — a pattern may match
//      across line ends, and \R matches any line-ending sequence. Scintilla's
//      own built-in engine is line-oriented and cannot do this at all, which
//      is the single largest behavioural gap this file closes.
//    * `.` does NOT cross a line end by default. Boost's plain perl mode is
//      the opposite, so the base flags include no_mod_s. The find bar's
//      ". matches newline" option is then an inline (?s) on the pattern,
//      verified to still opt in even under no_mod_s.
//    * Replacements use format_all, which is what enables \U \L \E, $& and
//      the conditional forms.
//
//  Copyright (C) 2026 MacPad contributors.
//  SPDX-License-Identifier: GPL-3.0-or-later
//

#include <cstddef>
#include <cstdlib>
#include <cstdint>
#include <cassert>
#include <cstring>
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
#include <regex>

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

#include <boost/regex.hpp>

using namespace Scintilla;
using namespace Scintilla::Internal;

namespace {

/// Base syntax flags. `no_mod_s` is what makes `.` stop at a line end, which
/// is the default; a pattern may still opt in with (?s).
constexpr boost::regex::flag_type kBaseFlags =
	boost::regex::perl | boost::regex::no_mod_s;

/// Replacement flags. `format_all` is what enables \U \L \E, $& and the
/// conditional ?N:yes:no forms.
// Not constexpr: Boost's operator| for match_flags is a plain inline function.
const boost::match_flag_type kFormatFlags =
	boost::match_default | boost::format_all;

class BoostRegexSearch : public RegexSearchBase {
public:
	explicit BoostRegexSearch(CharClassify *) noexcept {}

	BoostRegexSearch(const BoostRegexSearch &) = delete;
	BoostRegexSearch(BoostRegexSearch &&) = delete;
	BoostRegexSearch &operator=(const BoostRegexSearch &) = delete;
	BoostRegexSearch &operator=(BoostRegexSearch &&) = delete;
	~BoostRegexSearch() override = default;

	Sci::Position FindText(Document *doc,
	                       Sci::Position minPos,
	                       Sci::Position maxPos,
	                       const char *pattern,
	                       bool caseSensitive,
	                       bool word,
	                       bool wordStart,
	                       FindOption flags,
	                       Sci::Position *length) override;

	const char *SubstituteByPosition(Document *doc,
	                                 const char *replacement,
	                                 Sci::Position *length) override;

private:
	/// Compile `pattern`, reusing the last compiled expression when possible.
	/// Returns false on an invalid pattern.
	bool Compile(const char *pattern, bool caseSensitive);

	/// The searched text. `match` holds iterators into this, so it must stay
	/// alive and unchanged between FindText and SubstituteByPosition.
	std::string buffer;
	/// Document position that buffer[0] corresponds to.
	Sci::Position bufferDocumentOffset = 0;

	boost::regex expression;
	std::string compiledPattern;
	boost::regex::flag_type compiledFlags = 0;
	bool hasExpression = false;

	boost::cmatch match;
	bool hasMatch = false;

	std::string substituted;
};

bool BoostRegexSearch::Compile(const char *pattern, bool caseSensitive) {
	boost::regex::flag_type wanted = kBaseFlags;
	if (!caseSensitive) {
		wanted |= boost::regex::icase;
	}

	if (hasExpression && compiledFlags == wanted && compiledPattern == pattern) {
		return true;
	}

	try {
		expression.assign(pattern, wanted);
	} catch (const boost::regex_error &) {
		// An incomplete pattern is normal while the user is still typing it.
		// Report "no match" rather than letting an exception reach Scintilla.
		hasExpression = false;
		return false;
	} catch (const std::runtime_error &) {
		// Boost raises this when a match exceeds its complexity or stack
		// limits — a catastrophically backtracking pattern, for instance.
		hasExpression = false;
		return false;
	}

	compiledPattern = pattern;
	compiledFlags = wanted;
	hasExpression = true;
	return true;
}

Sci::Position BoostRegexSearch::FindText(Document *doc,
                                         Sci::Position minPos,
                                         Sci::Position maxPos,
                                         const char *pattern,
                                         bool caseSensitive,
                                         bool word,
                                         bool wordStart,
                                         FindOption flags,
                                         Sci::Position *length) {
	// "Match whole word only" and "word start" are not combined with regex,
	// where \b does the job.
	(void)word;
	(void)wordStart;
	(void)flags;

	hasMatch = false;
	if (length != nullptr) {
		*length = 0;
	}
	if (pattern == nullptr || *pattern == '\0' || doc == nullptr) {
		return -1;
	}
	if (!Compile(pattern, caseSensitive)) {
		return -1;
	}

	// Scintilla signals a backwards search by passing minPos > maxPos.
	const bool backwards = minPos > maxPos;
	const Sci::Position documentLength = doc->Length();
	Sci::Position rangeStart = std::clamp(backwards ? maxPos : minPos,
	                                      static_cast<Sci::Position>(0), documentLength);
	const Sci::Position rangeEnd = std::clamp(backwards ? minPos : maxPos,
	                                          static_cast<Sci::Position>(0), documentLength);
	if (rangeStart > rangeEnd) {
		return -1;
	}

	// Extract from the range start to the end of the document, not to the end
	// of the range. Matches are still restricted to the range below, but
	// reading on means `$`, lookahead and \b behave as they would in the whole
	// buffer rather than against an artificial cut. One byte before the range
	// is included where available so that `^` and \b can see what precedes it,
	// which is what match_prev_avail tells Boost to do.
	const bool havePreviousByte = rangeStart > 0;
	const Sci::Position extractFrom = havePreviousByte ? rangeStart - 1 : rangeStart;
	const Sci::Position extractLength = documentLength - extractFrom;
	if (extractLength <= 0) {
		return -1;
	}

	try {
		buffer.resize(static_cast<size_t>(extractLength));
	} catch (const std::bad_alloc &) {
		return -1;
	}
	doc->GetCharRange(buffer.data(), extractFrom, extractLength);
	bufferDocumentOffset = extractFrom;

	const char *const bufferBegin = buffer.data();
	const char *const bufferEnd = bufferBegin + buffer.size();
	const char *searchFrom = bufferBegin + (havePreviousByte ? 1 : 0);

	boost::match_flag_type matchFlags = boost::match_default;
	if (havePreviousByte) {
		matchFlags |= boost::match_prev_avail;
	}

	// Accept only matches that lie wholly inside [rangeStart, rangeEnd].
	const auto positionOf = [&](const char *p) -> Sci::Position {
		return bufferDocumentOffset + static_cast<Sci::Position>(p - bufferBegin);
	};

	boost::cmatch candidate;
	bool found = false;

	const char *cursor = searchFrom;
	while (cursor <= bufferEnd) {
		boost::cmatch attempt;
		bool searched = false;
		try {
			searched = boost::regex_search(cursor, bufferEnd, attempt,
			                               expression, matchFlags);
		} catch (const std::runtime_error &) {
			// Complexity or stack limit hit mid-search.
			break;
		}
		if (!searched) {
			break;
		}

		const Sci::Position matchStart = positionOf(attempt[0].first);
		const Sci::Position matchEnd = positionOf(attempt[0].second);

		if (matchStart > rangeEnd) {
			break;
		}
		if (matchEnd <= rangeEnd) {
			candidate = attempt;
			found = true;
			if (!backwards) {
				break;      // forwards wants the first acceptable match
			}
		}

		// Step past this match and keep looking. A zero-length match would
		// otherwise spin here forever.
		const char *next = attempt[0].second;
		if (next == attempt[0].first) {
			next += 1;
		}
		if (next >= bufferEnd) {
			break;
		}
		cursor = next;
		matchFlags |= boost::match_prev_avail;
	}

	if (!found) {
		return -1;
	}

	match = candidate;
	hasMatch = true;

	const Sci::Position matchStart = positionOf(match[0].first);
	const Sci::Position matchEnd = positionOf(match[0].second);
	if (length != nullptr) {
		*length = matchEnd - matchStart;
	}
	return matchStart;
}

const char *BoostRegexSearch::SubstituteByPosition(Document *doc,
                                                   const char *replacement,
                                                   Sci::Position *length) {
	(void)doc;
	if (!hasMatch || replacement == nullptr) {
		substituted.clear();
		if (length != nullptr) {
			*length = 0;
		}
		return substituted.c_str();
	}

	try {
		substituted = match.format(replacement, kFormatFlags);
	} catch (const boost::regex_error &) {
		// A malformed replacement template, e.g. a reference to a group that
		// does not exist. Substitute nothing rather than corrupting the text.
		substituted.clear();
	} catch (const std::runtime_error &) {
		substituted.clear();
	}

	if (length != nullptr) {
		*length = static_cast<Sci::Position>(substituted.length());
	}
	return substituted.c_str();
}

}  // namespace

// Replaces Scintilla's built-in engine. Reached because the Scintilla target
// is compiled with SCI_OWNREGEX defined, which suppresses the default factory
// at the foot of Document.cxx.
RegexSearchBase *Scintilla::Internal::CreateRegexSearch(CharClassify *charClassTable) {
	return new BoostRegexSearch(charClassTable);
}
