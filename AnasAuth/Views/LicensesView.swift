import SwiftUI

/// 开源许可页：AGPL-3.0 要求的版权、无担保与许可声明（第 5 条 d 款），
/// 以及第三方组件的许可。ISC 许可要求随软件附带其版权与许可原文。
struct LicensesView: View {
    private static let repositoryURL = URL(string: "https://github.com/WenliangCao/Anas-Auth")!
    private static let licenseURL = URL(string: "https://github.com/WenliangCao/Anas-Auth/blob/main/LICENSE")!
    private static let noticesURL = URL(string: "https://github.com/WenliangCao/Anas-Auth/blob/main/THIRD_PARTY_NOTICES.md")!

    var body: some View {
        Form {
            Section {
                Text(verbatim: "Copyright © 2026 WenliangCao")
                Link("Source Code", destination: Self.repositoryURL)
                Link("Full Text of the GNU AGPL-3.0", destination: Self.licenseURL)
            } header: {
                Text(verbatim: "Anas Auth")
            } footer: {
                Text("Anas Auth is free software: you can use, modify and redistribute it under the terms of the GNU Affero General Public License version 3 (AGPL-3.0). It comes with no warranty; see the license for details. This project is not affiliated with ente.")
            }

            Section {
                component("ente Community Brand Icons", license: "AGPL-3.0")
                component("Import Formats (Ported from ente)", license: "AGPL-3.0")
                component("simple-icons Brand Icons", license: "CC0-1.0")
                component("swift-sodium / libsodium", license: "ISC")
                Link("Full Third-Party Notices", destination: Self.noticesURL)
            } header: {
                Text("Third-Party Components")
            } footer: {
                Text("Trademarks shown in icons belong to their respective owners and are used only to identify the corresponding services.")
            }

            Section {
                Text(Self.iscNotice)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } header: {
                Text(verbatim: "swift-sodium / libsodium (ISC)")
            }
        }
        .navigationTitle("Open Source Licenses")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.primary)
    }

    private func component(_ name: LocalizedStringKey, license: String) -> some View {
        LabeledContent(name) { Text(verbatim: license) }
    }

    /// swift-sodium 0.11.0 LICENSE 原文（内含的 libsodium 同为 Frank Denis 的 ISC 许可）
    private static let iscNotice = """
        ISC License

        Copyright (c) 2014-2026, Frank Denis <j at pureftpd dot org>

        Permission to use, copy, modify, and/or distribute this software for any \
        purpose with or without fee is hereby granted, provided that the above \
        copyright notice and this permission notice appear in all copies.

        THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES \
        WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF \
        MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR \
        ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES \
        WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN \
        ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF \
        OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
        """
}
