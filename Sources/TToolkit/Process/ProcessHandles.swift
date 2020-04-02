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


fileprivate let ioThreads = DispatchQueue(label:"com.tannersilva.global.process-handle.io", qos:Priority.highest.asDispatchQoS(), attributes:[.concurrent])
fileprivate let ppLocks = DispatchQueue(label:"com.tannersilva.global.process-pipe.sync", attributes:[.concurrent])
fileprivate let ppInit = DispatchQueue(label:"com.tannersilva.global.process-pipe.init-serial")

internal class ProcessPipes {
	typealias ReadHandler = (Data) -> Void
	typealias WriteHandler = (ProcessHandle) -> Void
	
	private let concurrentSchedule:DispatchQueue
	private let internalSync:DispatchQueue
	private let internalCallback:DispatchQueue
	
	let reading:ProcessHandle
	let writing:ProcessHandle
	
	//MARK: Handlers
	//these are the timing sources that handle the readability and writability handler 
	private var writeSource:DispatchSourceProtocol? = nil
	private var readSource:DispatchSourceProtocol? = nil
	
	private var _callbackQueue:DispatchQueue
	var handlerQueue:DispatchQueue {
		get {
			return internalSync.sync {
				return _callbackQueue
			}
		}
		set {
			internalSync.sync {
				_callbackQueue = newValue
				internalCallback.setTarget(queue:_callbackQueue)
			}
		}
	}

	//readability handler
	private var _readHandler:ReadHandler? = nil
	var readHandler:ReadHandler? {
		get {
			return internalSync.sync {
				return _readHandler
			}
		}
		set {
			internalSync.sync {
				//cancel the old handler source if it exists
				if let hasReadSource = readSource {
					hasReadSource.cancel()
				}
				
				//if there is a new handler to schedule...
				if let hasNewHandler = newValue {
					_readHandler = hasNewHandler

					//schedule the new timer
					let newSource = DispatchSource.makeReadSource(fileDescriptor:reading.fileDescriptor, queue:concurrentSchedule)
					let reader = reading
					let intCbQueue = internalCallback
					newSource.setEventHandler { [weak self] in
						guard let self = self else {
							return
						}
						self.internalSync.sync {
							if let newData = reader.availableData() {
								intCbQueue.async {
									hasNewHandler(newData)
								}
							}
						}
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
	
	//write handler
	private var _writeHandler:WriteHandler? = nil
	var writeHandler:WriteHandler? {
		get {
			return internalSync.sync {
				return _writeHandler
			}
		}
		set {
			internalSync.sync {
				//cancel the existing writing source if it exists
				if let hasWriteSource = writeSource {
					hasWriteSource.cancel()
				}
				//assign the new value and schedule a new writing source if necessary
				if let hasNewHandler = newValue {
					_writeHandler = hasNewHandler
					
					//schedule the new timer
					let newSource = DispatchSource.makeWriteSource(fileDescriptor:writing.fileDescriptor, queue:concurrentSchedule)
					let writer = writing
					let intCbQueue = internalCallback
					newSource.setEventHandler { [weak self] in
						intCbQueue.async { [weak self] in
							guard let self = self else {
								return
							}
							hasNewHandler(self.writing)
						}
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
	
	init(priority:Priority = Priority.`default`, callback:DispatchQueue? = nil) throws {
		let readWrite = try Self.forReadingAndWriting(priority:priority)
		
		self.reading = readWrite.r
		self.writing = readWrite.w
		
		self.concurrentSchedule = DispatchQueue(label:"com.tannersilva.instance.process-pipe.schedule", target:ioThreads)
		let ints = DispatchQueue(label:"com.tannersilva.instance.process-pipe.sync", qos:priority.asDispatchQoS(), target:ppLocks)
		self.internalSync = ints
		let icb = DispatchQueue(label:"com.tannersilva.instance.process-pipe.callback", target:callback ?? priority.globalConcurrentQueue)
		self.internalCallback = icb
		self._callbackQueue = callback ?? priority.globalConcurrentQueue
	}
	
	fileprivate static func forReadingAndWriting(priority:Priority = Priority.`default`) throws -> (r:ProcessHandle, w:ProcessHandle) {
		let fds = UnsafeMutablePointer<Int32>.allocate(capacity:2)
		defer {
			fds.deallocate()
		}
		
		return try ppInit.sync {
			let rwfds = _pipe(fds)
			switch rwfds {
				case 0:
					let readFD = fds.pointee
					let writeFD = fds.successor().pointee
				
					return (r:ProcessHandle(fd:readFD, priority:priority), w:ProcessHandle(fd:writeFD, priority:priority))
				default:
				throw ExecutingProcess.ProcessError.unableToCreatePipes
			}
		}
	}
	
	func close() {
			reading.close()
			writing.close()
			readHandler = nil
			writeHandler = nil
	}
	
	deinit {
		readHandler = nil
		writeHandler = nil
	}
}

fileprivate let phLock = DispatchQueue(label:"com.tannersilva.global.process-handle.sync", attributes:[.concurrent])

internal class ProcessHandle {
	fileprivate let internalSync:DispatchQueue
	
	private var _fd:Int32
	var fileDescriptor:Int32 {
		get {
			return _fd
		}
	}
	
	init(fd:Int32, priority:Priority = Priority.`default`) {
		self._fd = fd
		self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process-handle.sync", qos:priority.asDispatchQoS(), target:phLock)
	}
	
	func write(_ dataObj:Data) throws {
		try internalSync.sync {
			try dataObj.withUnsafeBytes({
				if let hasBaseAddress = $0.baseAddress {
					try write(buf:hasBaseAddress, length:dataObj.count)
				}
			})
		}
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
		internalSync.sync {
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
	}
	
	func close() {
		internalSync.sync {
			guard _fd != -1 else {
				return
			}
		
			guard _close(_fd) >= 0 else {
				return
			}
			_fd = -1
		}
	}
	
	deinit {
		if _fd != -1 {
			_ = _close(_fd)
		}
	}

}