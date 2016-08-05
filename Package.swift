import PackageDescription

let package = Package(
    name: "FluentMySQL",
    dependencies: [
   		.Package(url: "https://github.com/vapor/mysql.git", majorVersion: 0, minor: 4),
   		.Package(url: "https://github.com/vapor/fluent.git", majorVersion: 0, minor: 9),
    ]
)
