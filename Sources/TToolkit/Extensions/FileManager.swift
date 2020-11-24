import Foundation

extension FileManager {
     public func mktemp() throws -> URL {
    	let temporaryDirectory = try FileManager.default.temporaryDirectory
    	let dirName = String.random(length:Int.random(in:10..<24))
    	let targetURL = temporaryDirectory.appendingPathComponent(dirName, isDirectory:true)
		try FileManager.default.createDirectory(at:targetURL, withIntermediateDirectories:false)
		return targetURL
    }
}