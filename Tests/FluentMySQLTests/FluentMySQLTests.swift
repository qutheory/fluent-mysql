import Async
import XCTest
import FluentBenchmark
import Dispatch
import FluentMySQL
import COperatingSystem
import Service
import Console

class FluentMySQLTests: XCTestCase {
    var benchmarker: Benchmarker<MySQLDatabase>!
    var database: MySQLDatabase!

    override func setUp() {
        let eventLoop = MultiThreadedEventLoopGroup(numThreads: 1)
        let config = MySQLDatabaseConfig(
            hostname: "localhost",
            port: 3306,
            username: "vapor_username",
            password: "vapor_password",
            database: "vapor_database"
        )
        database = MySQLDatabase(config: config)
        database.logger = DatabaseLogger(database: .mysql, handler: PrintLogHandler())
        benchmarker = try! Benchmarker(database, on: eventLoop, onFail: XCTFail)
    }

    func testSchema() throws {
        try benchmarker.benchmarkSchema()
    }
    
    func testModels() throws {
        try benchmarker.benchmarkModels_withSchema()
    }
    
    func testRelations() throws {
        try benchmarker.benchmarkRelations_withSchema()
    }
    
    func testTimestampable() throws {
        try benchmarker.benchmarkTimestampable_withSchema()
    }
    
    func testTransactions() throws {
        try benchmarker.benchmarkTransactions_withSchema()
    }

    func testChunking() throws {
         try benchmarker.benchmarkChunking_withSchema()
    }

    func testMySQLJoining() throws {
        let conn = try benchmarker.pool.requestConnection().wait()
        _ = try conn.simpleQuery("drop table if exists tablea;").wait()
        _ = try conn.simpleQuery("drop table if exists tableb;").wait()
        _ = try conn.simpleQuery("drop table if exists tablec;").wait()
        _ = try conn.simpleQuery("create table tablea (id INT, cola INT);").wait()
        _ = try conn.simpleQuery("create table tableb (colb INT);").wait()
        _ = try conn.simpleQuery("create table tablec (colc INT);").wait()

        _ = try conn.simpleQuery("insert into tablea values (1, 1);").wait()
        _ = try conn.simpleQuery("insert into tablea values (2, 2);").wait()
        _ = try conn.simpleQuery("insert into tablea values (3, 3);").wait()
        _ = try conn.simpleQuery("insert into tablea values (4, 4);").wait()

        _ = try conn.simpleQuery("insert into tableb values (1);").wait()
        _ = try conn.simpleQuery("insert into tableb values (2);").wait()
        _ = try conn.simpleQuery("insert into tableb values (3);").wait()

        _ = try conn.simpleQuery("insert into tablec values (2);").wait()
        _ = try conn.simpleQuery("insert into tablec values (3);").wait()
        _ = try conn.simpleQuery("insert into tablec values (4);").wait()

        let all = try A.query(on: conn)
            .join(B.self, field: \.colb, to: \.cola)
            .alsoDecode(B.self)
            .join(C.self, field: \.colc, to: \.cola)
            .alsoDecode(C.self)
            .all().wait()

        XCTAssertEqual(all.count, 2)
        for ((a, b), c) in all {
            print(a.cola)
            print(b.colb)
            print(c.colc)
        }
    }

    func testMySQLCustomSQL() throws {
        let conn = try benchmarker.pool.requestConnection().wait()
        _ = try conn.simpleQuery("drop table if exists tablea;").wait()
        _ = try conn.simpleQuery("create table tablea (id INT, cola INT);").wait()
        _ = try conn.simpleQuery("insert into tablea values (1, 1);").wait()
        _ = try conn.simpleQuery("insert into tablea values (2, 2);").wait()
        _ = try conn.simpleQuery("insert into tablea values (3, 3);").wait()
        _ = try conn.simpleQuery("insert into tablea values (4, 4);").wait()

        let all = try A.query(on: conn)
            .customSQL { sql in
                switch sql {
                case .query(var query):
                    let predicate = DataPredicate(column: "cola", comparison: .isNull)
                    query.predicates.append(.predicate(predicate))
                    sql = .query(query)
                default: break
                }
            }
            .all().wait()

        XCTAssertEqual(all.count, 0)
    }

    func testMySQLSet() throws {
        let conn = try benchmarker.pool.requestConnection().wait()
        _ = try conn.simpleQuery("drop table if exists tablea;").wait()
        _ = try conn.simpleQuery("create table tablea (id INT, cola INT);").wait()
        _ = try conn.simpleQuery("insert into tablea values (1, 1);").wait()
        _ = try conn.simpleQuery("insert into tablea values (2, 2);").wait()

        _ = try A.query(on: conn).update(["cola": "3", "id": 2]).wait()

        let all = try A.query(on: conn).all().wait()
        print(all)
    }

    func testJSONType() throws {
        let conn = try benchmarker.pool.requestConnection().wait()
        defer { _ = try? User.revert(on: conn).wait() }
        _ = try User.prepare(on: conn).wait()
        let user = User(id: nil, name: "Tanner", pet: Pet(name: "Ziz"))
        _ = try user.save(on: conn).wait()
        try print(User.query(on: conn).filter(\.id == 5).all().wait())
        let users = try User.query(on: conn).all().wait()
        XCTAssertEqual(users[0].id, 1)
        XCTAssertEqual(users[0].name, "Tanner")
        XCTAssertEqual(users[0].pet.name, "Ziz")
    }

    func testContains() throws {
        try benchmarker.benchmarkContains_withSchema()
    }

    func testBugs() throws {
        try benchmarker.benchmarkBugs_withSchema()
    }

    func testGH93() throws {
        let conn = try benchmarker.pool.requestConnection().wait()
        defer { benchmarker.pool.releaseConnection(conn) }

        struct Post: MySQLModel, Migration {
            var id: Int?
            var title: String
            var strap: String
            var content: String
            var category: Int
            var slug: String
            var date: Date

            static func prepare(on connection: MySQLConnection) -> Future<Void> {
                return MySQLDatabase.create(self, on: connection) { builder in
                    try builder.field(type: .int64(), for: \.id, isOptional: false, isIdentifier: true)
                    try builder.field(for: \.title)
                    try builder.field(for: \.strap)
                    try builder.field(type: .text(), for: \.content)
                    try builder.field(for: \.category)
                    try builder.field(for: \.slug)
                    try builder.field(for: \.date)
                }
            }
        }

        defer { try? Post.revert(on: conn).wait() }
        try Post.prepare(on: conn).wait()

        var post = Post(id: nil, title: "a", strap: "b", content: "c", category: 1, slug: "d", date: .init())
        post = try post.save(on: conn).wait()
        try Post.query(on: conn).delete().wait()
    }

    func testIndexes() throws {
        try benchmarker.benchmarkIndexSupporting_withSchema()
    }

    func testGH61() throws {
        let conn = try benchmarker.pool.requestConnection().wait()
        defer { benchmarker.pool.releaseConnection(conn) }

        let res = try conn.query("SELECT ? as emojis", ["👏🐬💧"]).wait()
        try XCTAssertEqual(String.convertFromMySQLData(res[0].firstValue(forColumn: "emojis")!), "👏🐬💧")
    }

    func testGH76() throws {
        let conn = try benchmarker.pool.requestConnection().wait()
        defer { benchmarker.pool.releaseConnection(conn) }

        struct BoolTest: MySQLModel, Migration {
            var id: Int?
            var bool: Bool
        }

        defer { try? BoolTest.revert(on: conn).wait() }
        try BoolTest.prepare(on: conn).wait()

        var test = BoolTest(id: nil, bool: true)
        test = try test.save(on: conn).wait()
    }

    func testReferences() throws {
        let conn = try benchmarker.pool.requestConnection().wait()
        defer { benchmarker.pool.releaseConnection(conn) }

        // Prep tables
        defer {
        	try? Child.revert(on: conn).wait()
			try? Parent.revert(on: conn).wait()
		}
        try Parent.prepare(on: conn).wait()
        try Child.prepare(on: conn).wait()
        MySQLDatabase.enableLogging(conn.logger!, on: conn)
        // Save Parent
        var parent = Parent(id: 64, name: "Jerry")
        parent = try parent.create(on: conn).wait()
        // Save Child with a ref to previously saved Parent
        let savedParent = try Parent.query(on: conn).first().wait()
        XCTAssertEqual(savedParent!.id!, parent.id!, "Fetched ID \(savedParent!.id!) != saved ID \(parent.id!)")
        print("Parent saved with ID", savedParent?.id ?? "NOT SAVED")
        var child = Child(id: nil, name: "Morty", parentId: savedParent!.id!)
        child = try child.save(on: conn).wait()

        if let fetched = try Child.query(on: conn).first().wait() {
            XCTAssertEqual(child.id, fetched.id)
            XCTAssertEqual(child.name, fetched.name)
            XCTAssertEqual(child.parentId, fetched.parentId)
        } else {
            XCTFail()
        }
    }

    func testForeignKeyIndexCount() throws {
        let conn = try benchmarker.pool.requestConnection().wait()
        defer { benchmarker.pool.releaseConnection(conn) }

        // Prep tables
        defer {
        	try? Child.revert(on: conn).wait()
			try? Parent.revert(on: conn).wait()
		}
        try Parent.prepare(on: conn).wait()
        try Child.prepare(on: conn).wait()

        let testDatabase = database.config.database
        // Fetch how many contraints were created in Child, ignoring primary keys
        // Should be 1 (Parent-Child foreign key)
        let query = "select COUNT(1) as resultCount from information_schema.KEY_COLUMN_USAGE where table_schema = '\(testDatabase)' and table_name = '\(Child.entity)' and constraint_name != 'PRIMARY'"

        // conn.all(CountResult.self, in: query).wait() has been removed
        let fetched = try conn.simpleQuery(query).wait()
        if let fetchedFirst = fetched.first,
            let resultData = fetchedFirst.firstValue(forColumn: "resultCount"),
            let resultCount = try? Int.convertFromMySQLData(resultData) {
            XCTAssertEqual(1, resultCount)
        } else {
            XCTFail()
        }
    }
    
    func testLifecycle() throws {
        try benchmarker.benchmarkLifecycleHooks_withSchema()
    }

    static let allTests = [
        ("testSchema", testSchema),
        ("testModels", testModels),
        ("testRelations", testRelations),
        ("testTimestampable", testTimestampable),
        ("testTransactions", testTransactions),
        ("testChunking", testChunking),
        ("testMySQLJoining",testMySQLJoining),
        ("testMySQLCustomSQL", testMySQLCustomSQL),
        ("testMySQLSet", testMySQLSet),
        ("testJSONType", testJSONType),
        ("testContains", testContains),
        ("testBugs", testBugs),
        ("testGH93", testGH93),
        ("testIndexes", testIndexes),
        ("testGH61", testGH61),
        ("testGH76", testGH76),
        ("testReferences", testReferences),
        ("testForeignKeyIndexCount", testForeignKeyIndexCount),
        ("testLifecycle", testLifecycle)
    ]
}

struct A: MySQLModel {
    static let entity = "tablea"
    var id: Int?
    var cola: Int
}
struct B: MySQLModel {
    static let entity = "tableb"
    var id: Int?
    var colb: Int
}
struct C: MySQLModel {
    static let entity = "tablec"
    var id: Int?
    var colc: Int
}

struct User: MySQLModel, Migration {
    var id: Int?
    var name: String
    var pet: Pet
}

struct Pet: MySQLJSONType {
    var name: String
}

final class Parent: MySQLModel, Migration {
    var id: Int?
    var name: String
    
    init(id: Int?, name: String) {
        self.id = id
        self.name = name
    }
}

final class Child: MySQLModel, Migration {
    var id: Int?
    var name: String
    var parentId: Int

    init(id: Int?, name: String, parentId: Int) {
        self.id = id
        self.name = name
        self.parentId = parentId
    }
    
    static func prepare(on connection: MySQLDatabase.Connection) -> Future<Void> {
        return Database.create(self, on: connection, closure: { builder in
            try addProperties(to: builder)
            try builder.addReference(from: \.parentId, to: \Parent.id, actions: .update)
        })
    }
}
