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
internal typealias WriteHandler = () -> Void

fileprivate let ioThreads = DispatchQueue(label:"com.tannersilva.global.process-handle.io", attributes:[.concurrent])
fileprivate let ppLocks = DispatchQueue(label:"com.tannersilva.global.process-pipe.sync", attributes:[.concurrent])
fileprivate let ppInit = DispatchQueue(label:"com.tannersilva.global.process-pipe.init-serial")

/*
	When external processes are launched, there is no way of influencing the rate of which that processess will output data.
	The PipeReader class is used to immediately read data from available file descriptors. after a Data object is captured, Pipereader will call the completion handler at a specified dispatch queue while respecting that queues QoS
	This internal class allows data to be captured from the pipe handles immediately while potentially diverting the actual handling of that data for a later time based on the destination queue's QoS
*/
internal class PipeReader {
	let internalSync:DispatchQueue
	
	var handleQueue:[ProcessHandle:DispatchSourceProtocol]
	
	init() {
		self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process-pipe.reader.sync")
		self.handleQueue = [ProcessHandle:DispatchSourceProtocol]()
	}
	
	func scheduleForReading(_ handle:ProcessHandle, work:@escaping(ReadHandler)) {
			internalSync.sync {
				let newSource = DispatchSource.makeReadSource(fileDescriptor:handle.fileDescriptor, queue:Priority.highest.globalConcurrentQueue)
				newSource.setEventHandler {
					if let newData = handle.availableData() {
						work(newData)
					}
				}
				if let hasExisting = handleQueue[handle] {
					hasExisting.cancel()
				}
				handleQueue[handle] = newSource
				newSource.activate()
			}
	}
	
	func unschedule(_ handle:ProcessHandle) {
			internalSync.sync {
				if let hasExisting = handleQueue[handle] {
					hasExisting.cancel()
					handleQueue[handle] = nil
				}
			}
	}
}
internal let globalPR = PipeReader()

internal class WriteWatcher {
	fileprivate static let whThreads = DispatchQueue(label:"com.tannerdsilva.global.process.pipe.write-handler", qos:maximumPriority, attributes:[.concurrent])
	let internalSync = DispatchQueue(label:"com.tannersilva.instance.process.pipe.write-handler.sync", target:whThreads)
	
	var handleQueue:[ProcessHandle:DispatchSourceProtocol]
	
	init() {
		self.handleQueue = [ProcessHandle:DispatchSourceProtocol]()
	}
	
	func scheduleWriteAvailability(_ handle:ProcessHandle, queue:DispatchQueue, group:DispatchGroup, work:@escaping(WriteHandler)) {
		let newSource = DispatchSource.makeReadSource(fileDescriptor:handle.fileDescriptor, queue:queue)
		group.enter()
		newSource.setEventHandler {
			group.enter()
			work()
			group.leave()
		}
		newSource.setCancelHandler {
			group.leave()
		}
		internalSync.sync {
			if let hasExisting = handleQueue[handle] {
				hasExisting.cancel()
			}
			handleQueue[handle] = newSource
			newSource.activate()
		}
		print(Colors.magenta("[\(handle.fileDescriptor)] scheduled for writing."))
	}
	
	func unschedule(_ handle:ProcessHandle) {
		internalSync.sync {
			if let hasExisting = handleQueue[handle] {
				hasExisting.cancel()
				handleQueue[handle] = nil
			}
		}
		print(Colors.magenta("[\(handle.fileDescriptor)] unscheduled from writing"))
	}
}
internal let globalWH = WriteWatcher()

internal class ProcessPipes {
	private let internalSync:DispatchQueue

	let reading:ProcessHandle
	let writing:ProcessHandle

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
					globalPR.scheduleForReading(reading, work:hasNewHandler)
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
//				if let hasNewHandler = newValue {
//					_writeHandler = hasNewHandler
//					globalWH.scheduleWriteAvailability(writing, queue:internalCallback, group:_callbackGroup, work:hasNewHandler)
//				} else {
//					if _writeHandler != nil {
//						globalWH.unschedule(writing)
//					}
//				}
//			}
//		}
//	}
	
	init() throws {
		let readWrite = try Self.forReadingAndWriting()
		
		self.reading = readWrite.r
		self.writing = readWrite.w

		let ints = DispatchQueue(label:"com.tannersilva.instance.process-pipe.sync", target:ppLocks)
		self.internalSync = ints
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
				throw ExecutingProcess.ExecutingProcessError.unableToCreatePipes
			}
		}
	}
	
	func close() {
		readHandler = nil
//		reading.close()
//		writing.close()
//		writeHandler = nil
	}
	
	deinit {
		readHandler = nil
//		writeHandler = nil
	}
}

internal class ProcessHandle:Hashable {
	fileprivate static let globalQueue = DispatchQueue(label:"com.tannersilva.global.process.handle.sync", attributes:[.concurrent])

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
		self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process-handle.sync", target:Self.globalQueue)
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
