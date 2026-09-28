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
                Text("Copyright © 2026 WenliangCao")
                Link("源代码", destination: Self.repositoryURL)
                Link("GNU AGPL-3.0 许可证全文", destination: Self.licenseURL)
            } header: {
                Text("Anas Auth")
            } footer: {
                Text("Anas Auth 是自由软件：你可以依据 GNU Affero 通用公共许可证第 3 版（AGPL-3.0）的条款使用、修改和再分发它。本程序不提供任何担保，详见许可证全文。本项目与 ente 无隶属关系。")
            }

            Section {
                component("ente 社区品牌图标", license: "AGPL-3.0")
                component("导入格式解析（参照 ente 实现）", license: "AGPL-3.0")
                component("simple-icons 品牌图标", license: "CC0-1.0")
                component("swift-sodium / libsodium", license: "ISC")
                Link("完整第三方声明", destination: Self.noticesURL)
            } header: {
                Text("第三方组件")
            } footer: {
                Text("图标中的商标归各自所有者，仅用于标识对应服务。")
            }

            Section("swift-sodium / libsodium（ISC）") {
                Text(Self.iscNotice)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("开源许可")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.primary)
    }

    private func component(_ name: String, license: String) -> some View {
        LabeledContent(name, value: license)
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
