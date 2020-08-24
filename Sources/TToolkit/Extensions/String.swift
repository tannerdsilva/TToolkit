import Foundation

fileprivate enum StringError:Error {
    case unableToConvertToData
}

public extension String {
	//static function that creates a string of random length
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
	
	//safely returns a data structure based on this strings contents
	public func safeData(using thisEncoding:String.Encoding) throws -> Data {
		guard let saveVariable = self.data(using:thisEncoding) else {
			throw StringError.unableToConvertToData
		}
		return saveVariable
	}
	
	//encode a string into a URL
	public func urlEncodedString() -> String? {
		var allowedCharacters = CharacterSet.urlQueryAllowed
		allowedCharacters.remove(charactersIn:";/?:@&=+$, ")
		return self.addingPercentEncoding(withAllowedCharacters:allowedCharacters)
	}
}