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

extension ModelContext {
    /// 与库中已有条目去重后插入并立即保存，返回新增与跳过的数量。
    /// 不依赖自动保存：保存失败时撤销插入并抛出，界面不会显示成功而重启后数据消失
    func addCodes(_ codes: [OTPCode]) throws -> (added: Int, skipped: Int) {
        let existing = try fetch(FetchDescriptor<CodeEntry>())
        let (unique, skipped) = ImportService.filteringExisting(codes, in: existing)
        for code in unique {
            insert(CodeEntry(code: code))
        }
        try saveOrRollback()
        return (unique.count, skipped)
    }

    /// 立即保存；失败时撤销未保存的改动再抛出，让界面与磁盘保持一致
    func saveOrRollback() throws {
        do {
            try save()
        } catch {
            rollback()
            throw error
        }
    }
}

extension CodeStore {
    /// 保存失败时展示给用户的文案
    static func saveFailureMessage(_ error: Error) -> String {
        String(localized: "Your changes couldn’t be saved: \(error.localizedDescription)")
    }
}
