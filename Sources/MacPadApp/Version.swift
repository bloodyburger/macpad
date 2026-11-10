//
//  Version.swift
//  MacPad
//
//  MacPad — a native text and code editor for macOS.
//  Copyright (C) 2026 MacPad contributors.
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation, either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program. If not, see <https://www.gnu.org/licenses/>.
//
//  SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

enum EngineVersions {
    /// Versions of the engines MacPad is built against, shown in About and in
    /// bug reports. Kept in step with Tools/fetch-deps.sh.
    static let scintillaVersion = "5.6.9"
    static let lexillaVersion = "5.5.5"
}
