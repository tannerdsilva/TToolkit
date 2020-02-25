import Foundation

//for URL's where self represents a local file path to a JSON encoded. 
extension URL {
	public func read<T>(_ inputType:T.Type) throws -> T where T:Decodable {
		return try JSONDecoder.decodeBinaryJSON(file:self, type:inputType)
	}
}