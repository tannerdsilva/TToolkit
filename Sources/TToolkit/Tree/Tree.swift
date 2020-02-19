import Foundation

extension Array {
	fileprivate mutating func popMedianValue() -> Element {
		let fi = startIndex
		let length = Double(count)
		let targetOffset = Int(floor((length / 2)))
		let targetIndex = index(fi, offsetBy:targetOffset)
		return remove(at:targetIndex)
	}
	
	fileprivate mutating func splitInHalf() -> (left:ArraySlice<Element>, right:ArraySlice<Element>) {
		let fi = startIndex
		let ei = endIndex
		let length = Double(count)
		let targetOffset = Int(floor((length / 2)))
		let targetIndex = index(fi, offsetBy:targetOffset)
		return (left:self[fi..<targetIndex], right:self[targetIndex..<ei])
	}
}

extension ArraySlice {
	fileprivate mutating func popMedianValue() -> Element {
		let fi = startIndex
		let length = Double(count)
		let targetOffset = Int(floor((length / 2)))
		let targetIndex = index(fi, offsetBy:targetOffset)
		return remove(at:targetIndex)
	}
	
	fileprivate func splitInHalf() -> (left:ArraySlice<Element>, right:ArraySlice<Element>) {
		let fi = startIndex
		let ei = endIndex
		let length = Double(count)
		let targetOffset = Int(floor((length / 2)))
		let targetIndex = index(fi, offsetBy:targetOffset)
		return (left:self[fi..<targetIndex], right:self[targetIndex..<ei])
	}
}

enum Child:UInt8 {
	case left
	case right
}

class Tree<T> where T:Comparable, T:Hashable {
	
	private var val:T?
	
	private var left:Tree<T>? = nil
	private var right:Tree<T>? = nil
	
	init() {
		val = nil
	}
	
	init(_ input:T?) {
		val = input
	}
	
	public func forEveryValue(_ doThisWork:@escaping(T) throws -> Void) rethrows {
		if val != nil {
			try doThisWork(val!)
		}
		
		if left != nil {
			try left!.forEveryValue(doThisWork)
		}
		
		if right != nil {
			try right!.forEveryValue(doThisWork)
		}
	}
	
	//return the side that has a higher number of children
	private var imbalance:Child? {
		get {
			let leftCount = left?.childCount ?? 0
			let rightCount = right?.childCount ?? 0
			
			let absoluteDelta = Int(abs(leftCount - rightCount))
			
			if leftCount == rightCount || absoluteDelta < 2 {
				return nil
			} else if leftCount < rightCount {
				return .right
			} else if rightCount < leftCount {
				return .left
			}
			return nil
		}
	}
	
	public func insert(_ newValue:T) {
		if val == nil { 
			val = newValue
		} else if val!.hashValue > newValue.hashValue {
			if left != nil {
				left!.insert(newValue)
			} else {
				left = Tree<T>(newValue)
			}
		} else {
			if right != nil {
				right!.insert(newValue)
			} else {
				right = Tree<T>(newValue)
			}
		}
	}
	
	private func childValues(_ buildArray:inout Array<T>) {
		if val != nil {
			buildArray.append(val!)
		}

		if left != nil {
			left!.childValues(&buildArray)
		}
		
		if right != nil {
			right!.childValues(&buildArray)
		}
	}
	
	var childValues:[T] {
		get {
			var buildChildValues = [T]()
			
			if let hasRight = right {
				buildChildValues.append(contentsOf:hasRight.childValues)
			}
			
			if let hasLeft = left { 
				buildChildValues.append(contentsOf:hasLeft.childValues)
			}
			
			if val != nil {
				buildChildValues.append(val!)
			}
			return buildChildValues 
		}
	}
	
	var childCount:Int {
		get {
			if left == nil && right == nil {
				if val != nil {
					return 1
				} else {
					return 0
				}
			} else if left != nil && right == nil {
				return left!.childCount + 1
			} else if right != nil && left == nil {
				return right!.childCount + 1
			} else {
				let rightCount = right!.childCount
				let leftCount = left!.childCount
				return rightCount + leftCount + 1
			}
		}
	}
		
	var depth:Int {
		get {
			var leftDepth:Int? = nil
			if left != nil {
				leftDepth = left!.depth
			}

			var rightDepth:Int? = nil
			if right != nil {
				rightDepth = right!.depth
			}

			if leftDepth != nil && rightDepth != nil {
				if leftDepth! > rightDepth! {
					return leftDepth! + 1
				} else {
					return rightDepth! + 1
				}
			} else if leftDepth != nil {
				return leftDepth! + 1
			} else if rightDepth != nil {
				return rightDepth! + 1
			} else {
				return 0
			}
		}
	}
}

//class Tree<T> where T:Hashable, T:Comparable {
//	public var val:T
//	
//	public var left:Tree<T>? = nil
//	public var right:Tree<T>? = nil
//	
//	public var depth:Int {
//		var depthToBuild = 0
//		if left == nil && right == nil {
//			return 0
//		}
//		
//		var leftDepth = 0
//		if let hasLeft = left {
//			leftDepth = hasLeft.depth
//		}
//		
//		var rightDepth = 0
//		if let hasRight = right {
//			rightDepth = hasRight.depth
//		}
//		
//		//return the deeper of the two depths
//		if leftDepth < rightDepth {
//			return rightDepth
//		} else if leftDepth > rightDepth {
//			return leftDepth
//		} else {
//			return leftDepth
//		}
//	}
//	
//	public var children:[T]? {
//		get { 
//			var leftChildren = left?.children
//			var rightChildren = right?.children
//			if leftChildren != nil && rightChildren != nil { 
//				var childrenToBuild = leftChildren!
//				childrenToBuild.append(contentsOf:rightChildren!)
//				return childrenToBuild
//			} else if leftChildren != nil {
//				return leftChildren!
//			} else if rightChildren != nil {
//				return rightChildren!
//			}
//			return nil
//		}
//	}
//	
//	init?<U>(_ input:U) where U:Collection, U.Element == T, U.Element:Hashable, U.Element:Comparable {
//		guard input.count > 0 else {
//			return nil
//		}
//		var inputCopy = input
//		let myElement = inputCopy.dropLast()
//		val = myElement
//		
//		let splitInput = inputCopy.splitInHalf()
//		if let continueSequenceLeft = splitInput.left {
//			left = Tree<T>(continueSequenceLeft)
//		}
//		
//		if let continueSequenceRight = splitInput.right {
//			right = Tree<T>(continueSequenceRight)
//		}
//	}
//	
//	init?<V>(_ input:V) where V:Slice, V.Element == T, V.Element:Hashable, V.Element:Comparable {
//		guard input.count > 0 else {
//			return nil
//		}
//		
//		var inputCopy = input
//		let myElement = inputCopy.dropLast()
//		val = myElement
//		
//		let splitInput = inputCopy.splitInHalf()
//		if let continueSequenceLeft = splitInput.left {
//			left = Tree<T>(continueSequenceLeft)
//		}
//		
//		if let continueSequenceRight = splitInput.right {
//			right = Tree<T>(continueSequenceRight)
//		}
//	}
//	
//class func swap(_ t1:Tree<T>, t2:Tree<T>) {
//	let oneVal = t1.val
//	let oneLeft = t1.left
//	let oneRight = t1.right
//	
//	let twoVal = t2.val
//	let twoLeft = t2.left
//	let twoRight = t2.right
//	
//	t2.val = oneVal
//	t2.left = oneLeft
//	t2.right = oneRight
//	
//	t1.val = twoVal
//	t1.left = twoLeft
//	t1.right = twoRight
//}
//}