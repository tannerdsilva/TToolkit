import Foundation

fileprivate let encoder = JSONEncoder()
fileprivate let decoder = JSONDecoder()

//MARK: Report
//public typealias Reportable = Codable & Hashable
public struct Report<T> where T:Hashable, T:Codable {
    public typealias UnitType = T
    
    public let journal:Journal
    public let name:String
    private let filename:String
    
    public init(journal:Journal, name:String) {
        self.journal = journal
        self.name = name
        self.filename = name + ".json"
    }
    
    public func advanceHeadAndWrite(_ inputObjects:UnitType) throws {
        let writeURL = try journal.headDirectory(moveToDate: Date()).appendingPathComponent(filename, isDirectory:false)
        try inputObjects.encodeBinaryJSON(file: writeURL)
    }
    
    public func loadSnapshot(_ date:Date) throws -> UnitType {
		let readURL = try journal.directoryOnOrBefore(date:date).appendingPathComponent(filename, isDirectory:false)
		let readData = try Data(contentsOf:readURL)
		return try decoder.decode(UnitType.self, from:readData)
    }
}

extension Report where UnitType:Sequence, UnitType.Element:Hashable, UnitType.Element:Codable {
	public func compareDates(_ d1:Date, _ d2:Date) throws -> ReportComparison<UnitType.Element> {
		let data1 = Dictionary(grouping:try loadSnapshot(d1), by: { $0.hashValue }).compactMapValues({ $0.first })
		let data2 = Dictionary(grouping:try loadSnapshot(d2), by: { $0.hashValue }).compactMapValues({ $0.first })
		
		let hashes1 = Set(data1.keys)
		let hashes2 = Set(data2.keys)
		
		let common = hashes1.intersection(hashes2)
		
		let _exclusive = hashes1.symmetricDifference(hashes2)
		
		let exclusive1 = _exclusive.subtracting(hashes2)
		let exclusive2 = _exclusive.subtracting(hashes1)
		
		return ReportComparison<UnitType.Element>(data1:data1, data2:data2, hashes1:hashes1, hashes2:hashes2, common:common, exclusive1:exclusive1, exclusive2:exclusive2)
	}
}

public struct ReportComparison<T> where T:Hashable, T:Codable {
	public let data1:[Int:T]
	public let data2:[Int:T]
	
	public let hashes1:Set<Int>
	public let hashes2:Set<Int>
	
	public let common:Set<Int>
	
	public let exclusive1:Set<Int>
	public let exclusive2:Set<Int>
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
