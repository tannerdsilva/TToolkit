import Dispatch
import Foundation

import Glibc
fileprivate let _read = Glibc.read(_:_:_:)
fileprivate let _write = Glibc.write(_:_:_:)
fileprivate let _close = Glibc.close(_:)
fileprivate let _kill = Glibc.kill(_:_:)


/*
	ProcessPipe is a special type of FileHandle object designed specifically for reading streams from external processes.
	Much like the traditional FileHandle class found in the Swift Standard Library, ProcessPipe is able to achieve the same functionality with less complexity.
	
	The underlying posix functions create these types of filehandles in pairs...one for reading and one for writing. As such, there are class functions for initializing a pipe for reading, writing, or both
*/
internal class ProcessHandle {
	var queue:DispatchQueue
	var concurrentGlobal:DispatchQueue
	
	private var _fd:Int32
	public var fileDescriptor:Int32 {
		get {
			return _fd
		}
	}	
	
	private var shouldClose:Bool
	
	public typealias OutputHandler = (ProcessHandle) -> Void
	
	private var _readHandler:OutputHandler? = nil
	private var readHandler:OutputHandler? {
		get {
			return queue.sync {
				return _readHandler
			}
		}
		set {
			queue.sync {
				if let hasReadSource = readSource {
					hasReadSource.cancel()
				}

				if let hasNewHandler = newValue {
					_readHandler = hasNewHandler

					let newFD = dup(_fd)
					_rh_watch_fd = newFD
					
					//schedule the new timer
					let newSource = DispatchSource.makeWriteSource(fileDescriptor:newFD, queue:concurrentGlobal)
					newSource.setEventHandler { [weak self] in
						guard let self = self, let eventHandler = self.readHandler else {
							return
						}
						eventHandler(self)
					}
					newSource.setCancelHandler { [weak self] in
						guard let self = self else {
							return
						}
						_ = _close(newFD)
					}
					readSource = newSource
					newSource.activate()
				} else {
					_readHandler = nil
					readSource = nil
				}
			}
		}
	}
	
	private var _writeHandler:OutputHandler? = nil
	private var writeHandler:OutputHandler? {
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
					
					let newFD = dup(_fd)
					
					//schedule the new timer
					let newSource = DispatchSource.makeWriteSource(fileDescriptor:newFD, queue:concurrentGlobal)
					newSource.setEventHandler { [weak self] in
						guard let self = self, let eventHandler = self.writeHandler else {
							return
						}
						eventHandler(self)
					}
					newSource.setCancelHandler { [weak self] in
						guard let self = self else {
							return
						}
						_ = _close(newFD)
					}
					writeSource = newSource
					newSource.activate()
				} else {
					_writeHandler = nil
					writeSource = nil
				}
			}
		}
	}

	private var writeSource:DispatchSourceProtocol? = nil
	private var readSource:DispatchSourceProtocol? = nil
	
	//MARK: Public Initializers
	public class func forReading(priority:Priority, queue:DispatchQueue) -> ProcessHandle {
		let readWrite = Self.forReadingAndWriting(priority:priority, queue:queue)
		return readWrite.reading
	}
	
	public class func forWriting(priority:Priority, queue:DispatchQueue) -> ProcessHandle {
		let readWrite = Self.forReadingAndWriting(priority:priority, queue:queue)
		return readWrite.writing
	}
	
	fileprivate class func forReadingAndWriting(priority:Priority, queue:DispatchQueue) -> (reading:ProcessHandle, writing:ProcessHandle) {
		let fds = UnsafeMutablePointer<Int32>.allocate(capacity:2)
		defer {
			fds.deallocate()
		}
		
		let rwfds = pipe(fds)
		switch (rwfds, errno) {
			case (0, _):
				let readFD = fds.pointee
				let writeFD = fds.successor().pointee
				
				return (reading:ProcessHandle(priority:priority, queue:queue, fileDescriptor:readFD, autoClose:true), writing:ProcessHandle(priority:priority, queue:queue, fileDescriptor:writeFD, autoClose:true))
			default:
			fatalError("Error calling pipe(): \(errno)")
		}
	}
	
	internal init(priority:Priority, queue:DispatchQueue, fileDescriptor:Int32, autoClose:Bool = true) {
		self.queue = queue
		self.concurrentGlobal = DispatchQueue.global(qos:priority.asDispatchQoS())
		self._fd = fileDescriptor
		self.shouldClose = autoClose
	}
		
	public func write(_ dataObj:Data) throws {
		try dataObj.withUnsafeBytes({ 
			if let hasBaseAddress = $0.baseAddress {
				try write(buf:hasBaseAddress, length:dataObj.count)
			}
		})
	}
	
	fileprivate func write(buf: UnsafeRawPointer, length:Int) throws {
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
	
	public func read() -> Data? {
		let readBlockSize = 1024 * 8
		guard var dynamicBuffer = malloc(readBlockSize) else {
			return nil
		}
		defer {
			free(dynamicBuffer)
		}
		
		let amountRead = _read(_fd, dynamicBuffer, readBlockSize)
		guard amountRead > 0 else {
			return nil
		}
		let bytesBound = dynamicBuffer.bindMemory(to:UInt8.self, capacity:amountRead)
		return Data(bytes:bytesBound, count:amountRead)
	}
	
	public func close() {
		guard _fd != -1 else {
			return
		}
		
		writeHandler = nil
		readHandler = nil
		guard _close(_fd) >= 0 else {
			print(Colors.Red("ERROR CLOSING FILE DESCRIPTOR \(_fd)"))
			return
		}
		_fd = -1
	}
	
	deinit {
		if _fd != -1 && shouldClose == true {
			close()
		}
	}
}