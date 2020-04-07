//
//  ExplodeExtensions.swift
//  Cryptor
//
//  Created by Tanner Silva on 10/17/19.
//

import Foundation

//explosions allow for multi-threaded collection mapping

		let globemerge = DispatchQueue(label:"com.tannersilva.global.function.explode.merge")

extension Collection {
	//explode a collection - no return values	
	public func explode(lanes:Int = ProcessInfo.processInfo.activeProcessorCount, qos:Priority = .`default`, using thisFunction:@escaping (Int, Element) throws -> Void) {
		let concurrent = DispatchQueue(label:"com.tannersilva.function.explode.async", qos:qos.asDispatchQoS(), attributes:[.concurrent])
		let internalSync = DispatchQueue(label:"com.tannersilva.function.explode.sync")
		var iterator = makeIterator()
		
		func popItem() -> Element? {
			return internalSync.sync {
				iterator.next()
			}
		}
		
		concurrent.sync {
			DispatchQueue.concurrentPerform(iterations:lanes) { n in
				globemerge.sync { print("\(n)") }
				while let curItem = popItem() {
					try? thisFunction(n, curItem)
				}
			}
		}
	}

	//explode a collection - allows the user to handle the merging of data themselves.
	//return values of the primary `explode` block are passed to a serial thread where the user can handle the data as necessary	
	public func explode<T>(lanes:Int = ProcessInfo.processInfo.activeProcessorCount, qos:Priority = .`default`, using thisFunction:@escaping (Int, Element) throws -> T?, merge mergeFunction:@escaping (Int, T) throws -> Void) {
		let concurrent = DispatchQueue(label:"com.tannersilva.function.explode.async", qos:qos.asDispatchQoS(), attributes:[.concurrent])
		let internalSync = DispatchQueue(label:"com.tannersilva.function.explode.sync")
		let mergeSync = DispatchQueue(label:"com.tannersilva.function.explode.merge")
		var iterator = makeIterator()
		
		func popItem() -> Element? {
			return internalSync.sync {
				iterator.next()
			}
		}
		
		concurrent.sync {
			DispatchQueue.concurrentPerform(iterations:lanes) { n in
				globemerge.sync { print("\(n)") }
				while let curItem = popItem() {
					if let returnedValue = try? thisFunction(n, curItem) {
						mergeSync.sync {
							try? mergeFunction(n, returnedValue)
						}
					}
				}
			}
		}
	}

	//explode a collection - returns a set of hashable objects
	public func explode<T>(lanes:Int = ProcessInfo.processInfo.activeProcessorCount, qos:Priority = .`default`, using thisFunction:@escaping (Int, Element) throws -> T?) -> Set<T> where T:Hashable {	
		let concurrent = DispatchQueue(label:"com.tannersilva.function.explode.async", qos:qos.asDispatchQoS(), attributes:[.concurrent])
		let internalSync = DispatchQueue(label:"com.tannersilva.function.explode.sync")
		let mergeSync = DispatchQueue(label:"com.tannersilva.function.explode.merge")
		var iterator = makeIterator()
		var buildData = Set<T>()
		
		func popItem() -> Element? {
			return internalSync.sync {
				iterator.next()
			}
		}
		
		concurrent.sync {
			DispatchQueue.concurrentPerform(iterations:lanes) { n in
				globemerge.sync { print("\(n)") }
				while let curItem = popItem() {
					if let returnedValue = try? thisFunction(n, curItem) {
						mergeSync.sync {
							_ = buildData.update(with:returnedValue)
						}
					}
				}
			}
		}
		return buildData
	}


	//explode a collection - returns a dictionary
	public func explode<T, U>(lanes:Int = ProcessInfo.processInfo.activeProcessorCount, qos:Priority = .`default`, using thisFunction:@escaping (Int, Element) throws -> (key:T, value:U)) -> [T:U] where T:Hashable {
		let concurrent = DispatchQueue(label:"com.tannersilva.function.explode.async", qos:qos.asDispatchQoS(), attributes:[.concurrent])
		let internalSync = DispatchQueue(label:"com.tannersilva.function.explode.sync")
		let mergeSync = DispatchQueue(label:"com.tannersilva.function.explode.merge")
		var iterator = makeIterator()
		var buildData = [T:U]()
		
		func popItem() -> Element? {
			return internalSync.sync {
				iterator.next()
			}
		}
		
		concurrent.sync {
			DispatchQueue.concurrentPerform(iterations:lanes) { n in
				globemerge.sync { print("\(n)") }
				while let curItem = popItem() {
					if let returnedValue = try? thisFunction(n, curItem) {
						if returnedValue.value != nil {
							mergeSync.sync {
								buildData[returnedValue.key] = returnedValue.value
							}
						}
					}
				}
			}
		}
		return buildData
	}
}
