import Foundation

fileprivate let encoder = JSONEncoder()
fileprivate let decoder = JSONDecoder()

extension Encodable { 
	public func encodeBinaryJSON(file:URL) throws {
		let binaryData = try encoder.encode(self)
		try binaryData.write(to:file)
	}
}

extension JSONDecoder {
	public static func decodeBinaryJSON<T>(file:URL, type:T.Type) throws -> T where T:Decodable {
		let binaryData = try Data(contentsOf:file)
		return try decoder.decode(T.self, from:binaryData)
	}
}

//also see URL extension files for `read` convenience function

