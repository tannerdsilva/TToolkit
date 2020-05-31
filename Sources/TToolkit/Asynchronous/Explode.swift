//
//  ExplodeExtensions.swift
//  Cryptor
//
//  Created by Tanner Silva on 10/17/19.
//

import Foundation

//explosions allow for multi-threaded collection mapping
fileprivate let _explodeGlobal = DispatchQueue(label:"com.tannerdsilva.global.function.explode", attributes:[.concurrent])

extension Collection {
	//explode a collection - no return values
    public func explode(using thisFunction:@escaping (Int, Element) throws -> Void) {
        guard count > 0 else {
        	return
        }
        
        let enumerateQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:_explodeGlobal)
        var iterator = self.makeIterator()
        func getNext() -> Self.Element? {
        	return enumerateQueue.sync {
        		return iterator.next()
        	}
        }
        
        DispatchQueue.concurrentPerform(iterations:count) { n in
        	guard let thisItem = getNext() else {
        		return
        	}
        	try? thisFunction(n, thisItem)
        }
    }
    
    //explode a collection - allows the user to handle the merging of data themselves
    public func explode<T>(using thisFunction:@escaping (Int, Element) throws -> T?, merge mergeFunction:@escaping (Int, T) throws -> Void) {
        guard count > 0 else {
        	return
        }
        
        //pre-processing access
        let enumerateQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:_explodeGlobal)
        var iterator = self.makeIterator()
        func getNext() -> Self.Element? {
        	return enumerateQueue.sync {
        		return iterator.next()
        	}
        }
        
        //post-process merging
        let returnQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:_explodeGlobal)
        
        //process
        DispatchQueue.concurrentPerform(iterations:count) { n in
        	guard let thisItem = getNext() else {
        		return
        	}
        	if let returnedValue = try? thisFunction(n, thisItem) {
        		returnQueue.sync {
        			try? mergeFunction(n, returnedValue)
        		}
        	}
        }
    }
    
    //explode a collection - returns a set of hashable objects
    public func explode<T>(using thisFunction:@escaping (Int, Element) throws -> T?) -> Set<T> where T:Hashable {
        guard count > 0 else {
        	return Set<T>()
        }
        
        //pre-processing access
        let enumerateQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:_explodeGlobal)
        var iterator = self.makeIterator()
        func getNext() -> Self.Element? {
        	return enumerateQueue.sync {
        		return iterator.next()
        	}
        }
        
        //post-process merging
        let buildQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:_explodeGlobal)
        var buildData = Set<T>()
        
        //process
        DispatchQueue.concurrentPerform(iterations:count) { n in
        	if let thisItem = getNext(), let returnedValue = try? thisFunction(n, thisItem) {
        		buildQueue.sync {
        			buildData.update(with:returnedValue)
        		}
        	}
        }
        
        return buildData
    }
    
    //explode a collection - returns a dictionary
    public func explode<T, U>(using thisFunction:@escaping (Int, Element) throws -> (key:T, value:U)) -> [T:U] where T:Hashable {
        guard count > 0 else {
        	return [T:U]()
        }
        
        //pre-processing access
        let enumerateQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:_explodeGlobal)
        var iterator = self.makeIterator()
        func getNext() -> Self.Element? {
        	return enumerateQueue.sync {
        		return iterator.next()
        	}
        }
        
        //post-process merging
        let buildQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:_explodeGlobal)
        var buildData = [T:U]()
        
        //process
        DispatchQueue.concurrentPerform(iterations:count) { n in
        	if let thisItem = getNext(), let returnedValue = try? thisFunction(n, thisItem), returnedValue.value != nil {
        		buildQueue.sync {
        			buildData[returnedValue.key] = returnedValue.value
        		}
        	}
        }
        
        return buildData
    }
}
