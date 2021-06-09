import Foundation

extension String {
	//static function that creates a string of random length
	static func random(length:Int = 32) -> String {
		let base = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
		let baseLength = base.count
		var randomString = ""
		for _ in 0..<length {
			let randomIndex = Int.random(in:0..<baseLength)
			randomString.append(base[base.index(base.startIndex, offsetBy:randomIndex)])
		}
		return randomString
	}
}