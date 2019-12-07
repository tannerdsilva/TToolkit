import Foundation

fileprivate enum StringError:Error {
    case unableToConvertToData
}

public extension String {
	public static func random(length:Int = 32) -> String {
		let base = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
		let baseLength = base.count
		var randomString = ""
		for _ in 0..<length {
			let randomIndex = Int.random(in:0..<baseLength)
			randomString.append(base[base.index(base.startIndex, offsetBy:randomIndex)])
		}
		return randomString
	}
	//safely returns a data structure
	public func safeData(using thisEncoding:String.Encoding) throws -> Data {
		guard let saveVariable = self.data(using:thisEncoding) else {
			throw StringError.unableToConvertToData
		}
		return saveVariable
	}
}