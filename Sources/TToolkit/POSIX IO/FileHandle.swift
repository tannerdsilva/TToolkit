import Foundation
import Glibc

public func openFileHandle(path:String, flags:FileHandleOpenFlags, permissions:PosixPermissions = []) throws -> Int32 {
	let newFileHandle = open(path, flags.rawValue, permissions.rawValue)
	guard newFileHandle > -1 else {
		switch errno {
			case EACCES:
				throw FileHandleError.error_access
			case EBUSY:
				throw FileHandleError.error_busy
			case EDQUOT:
				throw FileHandleError.error_quota
			case EEXIST:
				throw FileHandleError.error_exists
			case EFAULT:
				throw FileHandleError.error_fault
			case EFBIG:
				throw FileHandleError.error_fileTooBig
			case EINTR:
				throw FileHandleError.error_interrupted
			case EINVAL:
				throw FileHandleError.error_invalid
			case EISDIR:
				throw FileHandleError.error_isDirectory
			case ELOOP:
				throw FileHandleError.error_linkLoop
			case EMFILE:
				throw FileHandleError.error_fileLimit
			case ENAMETOOLONG:
				throw FileHandleError.error_nameTooLong
			case ENFILE:
				throw FileHandleError.error_fileLimit
			case ENODEV:
				throw FileHandleError.error_noDevice
			case ENOENT:
				throw FileHandleError.error_doesntExist
			case ENOMEM:
				throw FileHandleError.error_noMemory
			case ENOSPC:
				throw FileHandleError.error_noSpace
			case ENOTDIR:
				throw FileHandleError.error_notDirectory
			case ENXIO:
				throw FileHandleError.error_noReader
			case EOPNOTSUPP:
				throw FileHandleError.error_notSupported
			case EOVERFLOW:
				throw FileHandleError.error_overflow
			case EPERM:
				throw FileHandleError.error_permission
			case EROFS:
				throw FileHandleError.error_readOnly
			case ETXTBSY:
				throw FileHandleError.error_busy
			case EWOULDBLOCK:
				throw FileHandleError.error_wouldBlock
			case EBADF:
				throw FileHandleError.error_bad_fh
			case ENOTDIR:
				throw FileHandleError.error_notDirectory
			default:
				throw FileHandleError.error_unknown
		}
	}
	return newFileHandle
}

extension Int32 {	
	public func readFileHandle(size:Int) throws -> Data {
		guard let readAllocation = malloc(size + 1) else {
			throw FileHandleError.error_unknown
		}
		defer {
			free(readAllocation)
		}
		let amountRead = read(self, readAllocation, size)
		guard amountRead > -1 else {
			switch errno {
				case EAGAIN:
					throw FileHandleError.error_again;
				case EWOULDBLOCK:
					throw FileHandleError.error_wouldBlock;
				case EBADF:
					throw FileHandleError.error_bad_fh;
				case EINTR:
					throw FileHandleError.error_interrupted;
				case EINVAL:
					throw FileHandleError.error_invalid;
				case EIO:
					throw FileHandleError.error_io;
				default:
					throw FileHandleError.error_unknown;
			}
		}
		guard amountRead != 0 else {
			throw FileHandleError.error_pipe
		}
		let boundBytes = readAllocation.bindMemory(to:UInt8.self, capacity:amountRead)
		return Data(bytes:boundBytes, count:amountRead)
	}
	
	public func writeFileHandle(_ inputString:String) throws {
		let utf8Data = inputString.data(using:.utf8)!
		try self.writeFileHandle(utf8Data)
	}
	
	public func writeFileHandle(_ inputData:Data) throws {
		var writtenBytes = 0
		while writtenBytes < inputData.count {
			let writeData = inputData.suffix(from:writtenBytes)
			let amountWritten = writeData.withUnsafeBytes { (startBuff) -> Int in
				return write(self, startBuff.baseAddress, writeData.count)
			}
			guard amountWritten > -1 else {
				switch errno {
					case EAGAIN:
						throw FileHandleError.error_again;
					case EWOULDBLOCK:
						throw FileHandleError.error_wouldBlock;
					case EBADF:
						throw FileHandleError.error_bad_fh;
					case EINTR:
						throw FileHandleError.error_interrupted;
					case EINVAL:
						throw FileHandleError.error_invalid;
					case EIO:
						throw FileHandleError.error_io;
					case ENOSPC:
						throw FileHandleError.error_noSpace;
					case EPIPE:
						throw FileHandleError.error_pipe;
					default:
						throw FileHandleError.error_unknown;
				}
			}
			writtenBytes += amountWritten
		}
	}
	
	public func closeFileHandle() {
		close(self);
	}
}
