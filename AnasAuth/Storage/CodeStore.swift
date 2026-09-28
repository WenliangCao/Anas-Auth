import Foundation
import SwiftData

/// ModelContainer 工厂。线上容器自动挂 iCloud 私有 CloudKit 数据库：
/// 用户登录了 iCloud 就多端同步，没登录就退化为纯本地，无需我们维护任何服务器。
enum CodeStore {
    static func makeContainer(inMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema([CodeEntry.self])
        let configuration: ModelConfiguration
        if inMemoryOnly {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
