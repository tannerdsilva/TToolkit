import Foundation
import Glibc

public class POSIX {
	public static func openFileHandle(path:String, flags:FileHandleOpenFlags, permissions:POSIXPermissions = []) throws -> Int32 {
		let newFileHandle = open(path, flags.rawValue, permissions.rawValue)
		guard newFileHandle > -1 else {
			switch errno {
				case EACCES:
					throw POSIXError.error_access
				case EBUSY:
					throw POSIXError.error_busy
				case EDQUOT:
					throw POSIXError.error_quota
				case EEXIST:
					throw POSIXError.error_exists
				case EFAULT:
					throw POSIXError.error_fault
				case EFBIG:
					throw POSIXError.error_fileTooBig
				case EINTR:
					throw POSIXError.error_interrupted
				case EINVAL:
					throw POSIXError.error_invalid
				case EISDIR:
					throw POSIXError.error_isDirectory
				case ELOOP:
					throw POSIXError.error_linkLoop
				case EMFILE:
					throw POSIXError.error_fileLimit
				case ENAMETOOLONG:
					throw POSIXError.error_nameTooLong
				case ENFILE:
					throw POSIXError.error_fileLimit
				case ENODEV:
					throw POSIXError.error_noDevice
				case ENOENT:
					throw POSIXError.error_doesntExist
				case ENOMEM:
					throw POSIXError.error_noMemory
				case ENOSPC:
					throw POSIXError.error_noSpace
				case ENOTDIR:
					throw POSIXError.error_notDirectory
				case ENXIO:
					throw POSIXError.error_noReader
				case EOPNOTSUPP:
					throw POSIXError.error_notSupported
				case EOVERFLOW:
					throw POSIXError.error_overflow
				case EPERM:
					throw POSIXError.error_permission
				case EROFS:
					throw POSIXError.error_readOnly
				case ETXTBSY:
					throw POSIXError.error_busy
				case EWOULDBLOCK:
					throw POSIXError.error_wouldBlock
				case EBADF:
					throw POSIXError.error_bad_fh
				case ENOTDIR:
					throw POSIXError.error_notDirectory
				default:
					throw POSIXError.error_unknown
			}
		}
		return newFileHandle
	}
	
	public static func createDirectory(at thisPath:String, permissions:POSIXPermissions = [.userAll, .groupAll, .otherRead, .otherExecute]) throws {
		let makeDirResult = mkdir(thisPath, permissions.rawValue)
		guard makeDirResult > -1 else {
			switch errno {
				case EACCES:
					throw POSIXError.error_access
				case EEXIST:
					throw POSIXError.error_exists
				case ELOOP:
					throw POSIXError.error_linkLoop
				case EMLINK:
					throw POSIXError.error_linkMax
				case ENAMETOOLONG:
					throw POSIXError.error_nameTooLong
				case ENOENT:
					throw POSIXError.error_doesntExist
				case ENOSPC:
					throw POSIXError.error_noSpace
				case ENOTDIR:
					throw POSIXError.error_notDirectory
				case EROFS:
					throw POSIXError.error_readOnly
				default:
					throw POSIXError.error_unknown

			}
		}
	}
}