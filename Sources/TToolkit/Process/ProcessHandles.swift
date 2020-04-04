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

internal typealias ReadHandler = (Data) -> Void
internal typealias WriteHandler = (ProcessHandle) -> Void

fileprivate let ioThreads = DispatchQueue(label:"com.tannersilva.global.process-handle.io", attributes:[.concurrent])
fileprivate let ppLocks = DispatchQueue(label:"com.tannersilva.global.process-pipe.sync", attributes:[.concurrent])
fileprivate let ppInit = DispatchQueue(label:"com.tannersilva.global.process-pipe.init-serial")

fileprivate let prThreads = DispatchQueue(label:"com.tannersilva.global.process-pipe.reader", qos:Priority.highest.asDispatchQoS(), attributes:[.concurrent])
internal class PipeReader {
	
	let internalSync:DispatchQueue
	let scheduleQueue:DispatchQueue
	
	var handleQueue:[ProcessHandle:DispatchSourceProtocol]
	
	init() {
		self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process-pipe.reader.sync", target:prThreads)
		self.scheduleQueue = DispatchQueue(label:"com.tannersilva.instance.process-pipe.reader.concurrent", qos:Priority.high.asDispatchQoS(), attributes:[.concurrent], target:prThreads)
		self.handleQueue = [ProcessHandle:DispatchSourceProtocol]()
	}
	
	func scheduleForReading(_ handle:ProcessHandle, queue:DispatchQueue, work:@escaping(ReadHandler)) {
		let newSource = DispatchSource.makeReadSource(fileDescriptor:handle.fileDescriptor, queue:scheduleQueue)
		newSource.setEventHandler {
			if let newData = handle.availableData() {
				print(Colors.Green("read \(newData.count) bytes"))
				let workItem = DispatchWorkItem(flags:[.inheritQoS]) {
					work(newData)
				}
				queue.async(execute:workItem)
			}
		}
		internalSync.sync {
			if let hasExisting = handleQueue[handle] {
				hasExisting.cancel()
			}
			handleQueue[handle] = newSource
			newSource.activate()
		}
		print(Colors.cyan("[\(handle.fileDescriptor)] scheduled for reading."))
	}
	
	func unschedule(_ handle:ProcessHandle) {
		internalSync.sync {
			if let hasExisting = handleQueue[handle] {
				hasExisting.cancel()
				handleQueue[handle] = nil
			}
		}
		print(Colors.magenta("[\(handle.fileDescriptor)] unscheduled"))
	}
}
internal let globalPR = PipeReader()


internal class ProcessPipes {
	private let internalSync:DispatchQueue
	private let internalCallback:DispatchQueue
	
	let reading:ProcessHandle
	let writing:ProcessHandle

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
				if let hasNewHandler = newValue {
					_readHandler = hasNewHandler
					globalPR.scheduleForReading(reading, queue:internalCallback, work:hasNewHandler)
				} else {
					if _readHandler != nil {
						globalPR.unschedule(reading)
					}
					_readHandler = nil
				}
			}
		}
	}
	
//	write handler
//	private var _writeHandler:WriteHandler? = nil
//	var writeHandler:WriteHandler? {
//		get {
//			return internalSync.sync {
//				return _writeHandler
//			}
//		}
//		set {
//			internalSync.sync {
//				cancel the existing writing source if it exists
//				if let hasWriteSource = writeSource {
//					hasWriteSource.cancel()
//				}
//				assign the new value and schedule a new writing source if necessary
//				if let hasNewHandler = newValue {
//					_writeHandler = hasNewHandler
//					
//					schedule the new timer
//					let newSource = DispatchSource.makeWriteSource(fileDescriptor:writing.fileDescriptor, queue:concurrentSchedule)
//					let writer = writing
//					let intCbQueue = internalCallback
//					newSource.setEventHandler { [weak self] in
//						intCbQueue.async { [weak self] in
//							guard let self = self else {
//								return
//							}
//							hasNewHandler(self.writing)
//						}
//					}
//					writeSource = newSource
//					newSource.activate()
//				} else {
//					_writeHandler = nil
//					writeSource = nil
//				}
//			}
//		}
//	}
	
	init(callback:DispatchQueue) throws {
		let readWrite = try Self.forReadingAndWriting()
		
		self.reading = readWrite.r
		self.writing = readWrite.w
		
		let ints = DispatchQueue(label:"com.tannersilva.instance.process-pipe.sync", target:ppLocks)
		self.internalSync = ints
		let icb = DispatchQueue(label:"com.tannersilva.instance.process-pipe.callback", target:callback)
		self.internalCallback = icb
		self._callbackQueue = callback
	}
	
	fileprivate static func forReadingAndWriting() throws -> (r:ProcessHandle, w:ProcessHandle) {
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
				
					return (r:ProcessHandle(fd:readFD), w:ProcessHandle(fd:writeFD))
				default:
				throw ExecutingProcess.ProcessError.unableToCreatePipes
			}
		}
	}
	
	func close() {
		reading.close()
		writing.close()
	}
	
	deinit {
		readHandler = nil
	}
}

fileprivate let sq = DispatchQueue(label:"com.tannersilva.global.process-handle.sync", attributes:[.concurrent])
internal class ProcessHandle:Hashable {
	fileprivate let internalSync:DispatchQueue
	
	private var _isClosed:Bool
	var isClosed:Bool {
		get {
			return internalSync.sync {
				return _isClosed
			}
		}
	}
	
	private let _fd:Int32
	var fileDescriptor:Int32 {
		get {
			internalSync.sync {
				return _fd
			}
		}
	}
	
	init(fd:Int32) {
		self._fd = fd
		self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process-handle.sync", target:sq)
		self._isClosed = false
	}
	
	func write(_ dataObj:Data) throws {
		try internalSync.sync {
			guard _isClosed != true else {
				//should throw
				return
			}
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
		return internalSync.sync {
			guard _isClosed != true else {
				return nil
			}
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
			guard _isClosed != true, _close(_fd) >= 0 else {
				return
			}
		
			_isClosed = true
		}
	}
	
	func hash(into hasher:inout Hasher) {
		hasher.combine(_fd)
	}
	
	static func == (lhs:ProcessHandle, rhs:ProcessHandle) -> Bool {
		return lhs._fd == rhs._fd
	}
	
	deinit {
		if isClosed == false {
			_ = _close(_fd)
		}
	}

}