import Foundation
import Glibc

public struct FileHandleOpenFlags:OptionSet {
	public let rawValue:Int32
	
	public init(rawValue:Int32) {
		self.rawValue = rawValue
	}
	
	public static let readOnly = FileHandleOpenFlags(rawValue:O_RDONLY)
	public static let writeOnly = FileHandleOpenFlags(rawValue:O_WRONLY)
	public static let readWrite = FileHandleOpenFlags(rawValue:O_RDWR)
	
	public static let append = FileHandleOpenFlags(rawValue:O_APPEND)
	public static let async = FileHandleOpenFlags(rawValue:O_ASYNC)
	public static let create = FileHandleOpenFlags(rawValue:O_CREAT)
	public static let directory = FileHandleOpenFlags(rawValue:O_DIRECTORY)
	public static let dsync = FileHandleOpenFlags(rawValue:O_DSYNC)
	public static let ensureCreate = FileHandleOpenFlags(rawValue:O_EXCL)
	public static let noTTY = FileHandleOpenFlags(rawValue:O_NOCTTY)
	public static let noFollow = FileHandleOpenFlags(rawValue:O_NOFOLLOW)
	public static let noBlock = FileHandleOpenFlags(rawValue:O_NONBLOCK)
}
