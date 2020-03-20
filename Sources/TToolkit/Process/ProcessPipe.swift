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

public class ProcessPipe {
	private var queue:DispatchQueue
	private var concurrentGlobal:DispatchQueue
	
	private var _fd:Int32
	
	public typealias OutputHandler = (ProcessPipe) -> Void
	
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
	
	public init(priority:Priority, queue:DispatchQueue, fileDescriptor:Int32) {
		self.queue = queue
		self.concurrentGlobal = DispatchQueue.global(qos:priority.asDispatchQoS())
		self._fd = fileDescriptor
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
}