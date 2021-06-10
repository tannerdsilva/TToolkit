import Foundation
import Glibc

extension Int32 {	
	public func readFileHandle(size:Int) throws -> Data {
		guard let readAllocation = malloc(size + 1) else {
			throw POSIXError.error_unknown
		}
		defer {
			free(readAllocation)
		}
		let amountRead = read(self, readAllocation, size)
		guard amountRead > -1 else {
			switch errno {
				case EAGAIN:
					throw POSIXError.error_again;
				case EWOULDBLOCK:
					throw POSIXError.error_wouldBlock;
				case EBADF:
					throw POSIXError.error_bad_fh;
				case EINTR:
					throw POSIXError.error_interrupted;
				case EINVAL:
					throw POSIXError.error_invalid;
				case EIO:
					throw POSIXError.error_io;
				default:
					throw POSIXError.error_unknown;
			}
		}
		guard amountRead != 0 else {
			throw POSIXError.error_pipe
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
						throw POSIXError.error_again;
					case EWOULDBLOCK:
						throw POSIXError.error_wouldBlock;
					case EBADF:
						throw POSIXError.error_bad_fh;
					case EINTR:
						throw POSIXError.error_interrupted;
					case EINVAL:
						throw POSIXError.error_invalid;
					case EIO:
						throw POSIXError.error_io;
					case ENOSPC:
						throw POSIXError.error_noSpace;
					case EPIPE:
						throw POSIXError.error_pipe;
					default:
						throw POSIXError.error_unknown;
				}
			}
			writtenBytes += amountWritten
		}
	}
	
	public func closeFileHandle() {
		close(self);
	}
}
