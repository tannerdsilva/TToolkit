import Foundation

extension FileManager {
     public func mktemp(clashVerify:Bool = false) throws -> URL {
    	let temporaryDirectory = try FileManager.default.temporaryDirectory
    	let dirName = String.random(length:Int.random(in:10..<24))
    	let targetURL = temporaryDirectory.appendingPathComponent(dirName, isDirectory:true)
    	if clashVerify {
    		if try FileManager.default.fileExists(atPath:targetURL.path) == true {
    			throw CommandError.temporaryDirectoryNameConflict
    		}
    	}
		try FileManager.default.createDirectory(at:targetURL, withIntermediateDirectories:false)
		return targetURL
    }
}