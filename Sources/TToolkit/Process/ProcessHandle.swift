import Dispatch
import Foundation

#if canImport(Darwin)
	import Darwin
	fileprivate let _read = Darwin.read(_:_:_:)
	fileprivate let _write = Darwin.write(_:_:_:)
	fileprivate let _close = Darwin.close(_:)
#elseif canImport(Glibc)
	import Glibc
	fileprivate let _read = Glibc.read(_:_:_:)
	fileprivate let _write = Glibc.write(_:_:_:)
	fileprivate let _close = Glibc.close(_:)
#endif

internal class ProcessPipes {
	typealias Handler = (ProcessHandle) -> Void

	let queue:DispatchQueue
	let priority:Priority
	
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
			return queue.sync {
				return _readHandler
			}
		}
		set {
			queue.sync {
				//cancel the old handler source if it exists
				if let hasReadSource = readSource {
					hasReadSource.cancel()
				}
				
				//if there is a new handler to schedule...
				if let hasNewHandler = newValue {
					_readHandler = hasNewHandler

					let newFD = dup(reading.fileDescriptor)
										
					//schedule the new timer
					let concQueue = priority.globalConcurrentQueue
					let newSource = DispatchSource.makeWriteSource(fileDescriptor:newFD, queue:queue)
					newSource.setEventHandler { [weak self] in
						print("read handler 1 called")
						concQueue.async { [weak self] in
							guard let self = self else {
								return
							}
							print("read handler 2 called")
							hasNewHandler(self.reading)
						}
					}
					newSource.setCancelHandler {
						_ = _close(newFD)
					}
					readSource = newSource
					newSource.activate()
					print(Colors.magenta("OK read handler scheduled for \(reading.fileDescriptor) when \(writing.fileDescriptor) is written"))
				} else {
					_readHandler = nil
					readSource = nil
				}
			}
		}
	}
	
	//write handler
	private var _writeHandler:Handler? = nil
	var writeHandler:Handler? {
		get {
			return queue.sync {
				return _writeHandler
			}
		}
		set {
			queue.sync {
				//cancel the existing writing source if it exists
				if let hasWriteSource = writeSource {
					hasWriteSource.cancel()
				}
				//assign the new value and schedule a new writing source if necessary
				if let hasNewHandler = newValue {
					_writeHandler = hasNewHandler
					
					let newFD = dup(writing.fileDescriptor)
					
					//schedule the new timer
					let concQueue = priority.globalConcurrentQueue
					let newSource = DispatchSource.makeWriteSource(fileDescriptor:newFD, queue:queue)
					newSource.setEventHandler { [weak self] in
						print("write handler 1 called")
						concQueue.async { [weak self] in
							guard let self = self else {
								return
							}
							print("write handler 2 called")
							hasNewHandler(self.writing)
						}
					}
					newSource.setCancelHandler {
						_ = _close(newFD)
					}
					writeSource = newSource
					newSource.activate()
					print(Colors.magenta("OK write handler scheduled for \(writing.fileDescriptor) when \(reading.fileDescriptor) is available for writing"))
				} else {
					_writeHandler = nil
					writeSource = nil
				}
			}
		}
	}
	
	init(priority:Priority, queue:DispatchQueue) {
		let readWrite = Self.forReadingAndWriting(priority:priority, queue:queue)
		
		self.reading = readWrite.r
		self.writing = readWrite.w
		
		print(Colors.Yellow("===== PROCESS PIPE INITIALIZED ====="))
		print(Colors.Yellow("R:\t\(readWrite.r.fileDescriptor)"))
		print(Colors.Yellow("W:\t\(readWrite.w.fileDescriptor)"))
		print(Colors.Yellow("===================================="))
		
		self.priority = priority
		self.queue = queue
	}
	
	fileprivate static func forReadingAndWriting(priority:Priority, queue:DispatchQueue) -> (r:ProcessHandle, w:ProcessHandle) {
		let fds = UnsafeMutablePointer<Int32>.allocate(capacity:2)
		defer {
			fds.deallocate()
		}
		
		let rwfds = pipe(fds)
		switch rwfds {
			case 0:
				let readFD = fds.pointee
				let writeFD = fds.successor().pointee
								
				return (r:ProcessHandle(fd:readFD, autoClose:true), w:ProcessHandle(fd:writeFD, autoClose:true))
			default:
			fatalError("Error calling pipe(): \(errno)")
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
	
	var autoClose:Bool
	
	init(fd:Int32, autoClose:Bool) {
		self._fd = fd
		self.autoClose = autoClose
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
			print(Colors.Red("statbuf fstat fail"))
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
			print(Colors.Red("ERROR CLOSING FILE DESCRIPTOR \(_fd)"))
			return
		}
		print(Colors.dim("[ \(fileDescriptor) ] - CLOSED"))
		_fd = -1
	}
	
	deinit {
		print(Colors.red("[ \(fileDescriptor) ] - DEINIT"))
		if _fd != -1 && autoClose == true {
			close()
		}
	}

}