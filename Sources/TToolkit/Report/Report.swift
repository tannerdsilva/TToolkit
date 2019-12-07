import Foundation

fileprivate let encoder = JSONEncoder()
fileprivate let decoder = JSONDecoder()

//MARK: Report
public typealias Reportable = Codable & Hashable
struct Report<T:Collection> where T.Element:Reportable {
    typealias UnitType = T.Element
    
    public let journal:Journal
    public let name:String
    private let filename:String
    
    init(journal:Journal, name:String) {
        self.journal = journal
        self.name = name
        self.filename = name + ".json"
    }
    
    func advanceHeadAndWrite(_ inputObjects:UnitType) throws {
        let writeURL = try journal.advanceHead(withDate: Date()).appendingPathComponent(filename, isDirectory:false)
        try inputObjects.encodeJSON(to: writeURL)
    }
    
    func loadSnapshot(_ date:Date) throws -> UnitType {
		let readURL = try journal.directoryOnOrBefore(date:date).appendingPathComponent(filename, isDirectory:false)
		let readData = try Data(contentsOf:readURL)
		return try decoder.decode(UnitType.self, from:readData)
    }
}

//MARK: Snapshot Object (used by Report)
//private enum ReportSnapshotError:Error {
//    case hashingCollision
//}
//private struct ReportSnapshot<T> where T:Reportable {
//    typealias ObjectType = Set<T>
//    
//    let hashes:Set<Int>
//    let hashMap:[Int:T]
//    
//    //for initializing with a any given collection of a matching element type
//    public init<U:Collection>(_ inputObjects:U) throws where U.Element == T {
//        self.hashes = Set(inputObjects.map({ $0.hashValue }))
//        self.hashMap = Dictionary(grouping: inputObjects, by: { return $0.hashValue }).compactMapValues({ $0.first })
//        guard inputObjects.count == self.hashes.count && self.hashes.count == self.hashMap.count else {
//            print(Colors.Red("Error! Hashing collision in the ReportTimePoint object"))
//            throw ReportSnapshotError.hashingCollision
//        }
//    }
//}
//extension ReportSnapshot {
//    fileprivate init(readingFromFile thisFile:URL) throws {
//        let fileData = try Data(contentsOf:thisFile)
//        let decoder = JSONDecoder()
//        let decodedObjects = try decoder.decode([ObjectType.Element].self, from: fileData)
//        try self.init(decodedObjects)
//    }
//    public func write(to file:URL) throws {
//        let allObjects = hashes.compactMap({ return hashMap[$0] })
//        let encoder = JSONEncoder()
//        let encodedData = try encoder.encode(allObjects)
//        try encodedData.write(to:file)
//    }
//}
