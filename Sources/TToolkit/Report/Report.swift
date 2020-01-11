import Foundation

fileprivate let encoder = JSONEncoder()
fileprivate let decoder = JSONDecoder()

enum ReportError: Error {
	case journalHeadMissing
}

//MARK: Report
//public typealias Reportable = Codable & Hashable
public class Report<T> where T:Hashable, T:Codable {
    public typealias UnitType = T
    public typealias ReportModifier = (URL, T) throws -> T
    
    public let journal:Journal
    public let name:String
    private let filename:String
    
    public init(journal:Journal, name:String) {
        self.journal = journal
        self.name = name
        self.filename = name + ".json"
    }
    
    public func writeToHead(_ inputObjects:UnitType) throws {
    	guard let writeURL = journal.currentHeadURL else {
    		throw ReportError.journalHeadMissing
    	}
    	try inputObjects.encodeBinaryJSON(file:writeURL.appendingPathComponent(filename, isDirectory:false))
    }
        
    public func loadSnapshot(_ date:Date) throws -> UnitType {
		let readURL = try journal.loadFrame(.dateOnOrBefore(date)).directory.appendingPathComponent(filename, isDirectory:false)
		return try JSONDecoder.decodeBinaryJSON(file:readURL, type:UnitType.self)
    }
    
    public func reverseModify(using enumFunction:ReportModifier) throws {
    	try journal.enumerateBackwards(using: { filePath, time in
    		let readURL = filePath.appendingPathComponent(filename, isDirectory:false)
    		let loadedData:T = try JSONDecoder.decodeBinaryJSON(file:readURL, type:T.self)
    		if let resultToWrite = try? enumFunction(filePath, loadedData) {
    			try resultToWrite.encodeBinaryJSON(file:readURL)
    		}
    		return .proceed
    	})
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