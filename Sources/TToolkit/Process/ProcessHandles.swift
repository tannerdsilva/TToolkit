import Dispatch
import Foundation

#if canImport(Darwin)
	import Darwin
	fileprivate let _read = Darwin.read(_:_:_:)
	fileprivate let _write = Darwin.write(_:_:_:)
	fileprivate let _close = Darwin.close(_:)
	fileprivate let o_cloexec = Darwin.O_CLOEXEC
	fileprivate let _pipe = Darwin.pipe(_:)
#elseif canImport(Glibc)
	import Glibc
	fileprivate let _read = Glibc.read(_:_:_:)
	fileprivate let _write = Glibc.write(_:_:_:)
	fileprivate let _close = Glibc.close(_:)
	fileprivate let o_cloexec = Glibc.O_CLOEXEC
	fileprivate let _pipe = Glibc.pipe(_:)
#endif

internal class ProcessPipes {
	typealias Handler = (ProcessHandle) -> Void

	private let scheduleQueue:DispatchQueue
	
	let reading:ProcessHandle
	let writing:ProcessHandle
	
	//MARK: Handlers
	//these are the timing sources that handle the readability and writability handler 
	private var writeSource:DispatchSourceProtocol? = nil
	private var readSource:DispatchSourceProtocol? = nil

	//readability handler
	private var _readHandler:Handler? = nil
	var readHandler:Handler? {
		get {
			return _readHandler
		}
		set {
			//cancel the old handler source if it exists
			if let hasReadSource = readSource {
				hasReadSource.cancel()
			}
			
			//if there is a new handler to schedule...
			if let hasNewHandler = newValue {
				_readHandler = hasNewHandler
				//schedule the new timer
				let newSource = DispatchSource.makeReadSource(fileDescriptor:reading.fileDescriptor, queue:scheduleQueue)
				newSource.setEventHandler { [weak self] in
					guard let self = self else {
						return
					}
					hasNewHandler(self.reading)
				}
				readSource = newSource
				newSource.activate()
			} else {
				_readHandler = nil
				readSource = nil
			}
		}
	}
	
	//write handler
	private var _writeHandler:Handler? = nil
	var writeHandler:Handler? {
		get {
			return _writeHandler
		}
		set {
			//cancel the existing writing source if it exists
			if let hasWriteSource = writeSource {
				hasWriteSource.cancel()
			}
			//assign the new value and schedule a new writing source if necessary
			if let hasNewHandler = newValue {
				_writeHandler = hasNewHandler
				//schedule the new timer
				let newSource = DispatchSource.makeWriteSource(fileDescriptor:writing.fileDescriptor, queue:scheduleQueue)
				newSource.setEventHandler { [weak self] in
					guard let self = self else {
						return
					}
					hasNewHandler(self.writing)
				}
				writeSource = newSource
				newSource.activate()
			} else {
				_writeHandler = nil
				writeSource = nil
			}
		}
	}
	
	init(queue:DispatchQueue) throws {
		let readWrite = try Self.forReadingAndWriting()
		
		self.reading = readWrite.r
		self.writing = readWrite.w
		
		self.scheduleQueue = DispatchQueue(label:"com.tannersilva.instance.process-pipe.callback", target:queue)
	}
	
	fileprivate static func forReadingAndWriting() throws -> (r:ProcessHandle, w:ProcessHandle) {
		let fds = UnsafeMutablePointer<Int32>.allocate(capacity:2)
		defer {
			fds.deallocate()
		}
		
		let rwfds = _pipe(fds)
		switch rwfds {
			case 0:
				let readFD = fds.pointee
				let writeFD = fds.successor().pointee
				
				return (r:ProcessHandle(fd:readFD), w:ProcessHandle(fd:writeFD))
			default:
			throw ExecutingProcess.ProcessError.unableToCreatePipes
		}
	}
	
	func close() {
		reading.close()
		writing.close()
		readHandler = nil
		writeHandler = nil
	}
	
	deinit {
		if _readHandler != nil {
			readHandler = nil
		}
		
		if _writeHandler != nil {
			writeHandler = nil
		}
	}
}

internal class ProcessHandle {
	private var _fd:Int32
	var fileDescriptor:Int32 {
		get {
			return _fd
		}
	}
	
	init(fd:Int32) {
		self._fd = fd
	}
	
	func write(_ dataObj:Data) throws {
		try dataObj.withUnsafeBytes({
			if let hasBaseAddress = $0.baseAddress {
				try write(buf:hasBaseAddress, length:dataObj.count)
			}
		})
	}
	
	fileprivate func write(buf:UnsafeRawPointer, length:Int) throws {
		var bytesRemaining = length
		while bytesRemaining > 0 {
			var bytesWritten = 0
			repeat {
				bytesWritten = _write(_fd, buf.advanced(by:length - bytesRemaining), bytesRemaining)
			} while (bytesWritten < 0 && errno == EINTR)
			if bytesWritten <= 0 {
				//should throw something here
				return
			}
			bytesRemaining -= bytesWritten
		}
	}
	
	func availableData() -> Data? {
		var statbuf = stat()
		if fstat(_fd, &statbuf) < 0 {
			return nil
		}
		
		let readBlockSize:Int
		if statbuf.st_mode & S_IFMT == S_IFREG && statbuf.st_blksize > 0 {
			readBlockSize = Int(clamping:statbuf.st_blksize)
		} else {
			readBlockSize = 1024 * 8
		}
		
		guard var dynamicBuffer = malloc(readBlockSize + 1) else {
			return nil
		}
		defer {
			free(dynamicBuffer)
		}
		
		let amountRead = read(_fd, dynamicBuffer, readBlockSize)
		guard amountRead > 0 else {
			return nil
		}
		let bytesBound = dynamicBuffer.bindMemory(to:UInt8.self, capacity:amountRead)
		return Data(bytes:bytesBound, count:amountRead)
	}
	
	func close() {
		guard _fd != -1 else {
			return
		}
		
		guard _close(_fd) >= 0 else {
			return
		}
		_fd = -1
	}
	
	deinit {
		if _fd != -1 {
			_ = _close(_fd)
		}
	}

}