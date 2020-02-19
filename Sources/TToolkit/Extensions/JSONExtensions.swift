import Foundation

public enum JSONSerializationError:Error {
	case invalidObjectType
}

public func serializeJSON<T>(_:T.Type, file:URL) throws -> T {
	let fileData = try Data(contentsOf:file)
	guard let fileObject = try JSONSerialization.jsonObject(with:fileData) as? T else {
		throw JSONSerializationError.invalidObjectType
	}
	return fileObject
}

