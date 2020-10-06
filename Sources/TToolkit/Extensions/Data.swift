import Foundation

//this is an enum for standardized byte order marks that typically reside at the beginning of data blobs stored on disk
fileprivate enum BOM: UInt {
	static let all:Set<Self> = Set([.utf8BOM, .utf16BEBOM, .utf16LEBOM, .utf32BEBOM, .utf32LEBOM, .utf7BOM, .utf1BOM, .utfEBCDICBOM, .scsuBOM, .bocu1BOM, .gb18030BOM])
	
	case utf8BOM		// 239 187 191
	case utf16BEBOM		// 254 255
	case utf16LEBOM		// 255 254
	case utf32BEBOM		// 0 0 254 255
	case utf32LEBOM		// 255 254 0 0
	
	case utf7BOM		// 43 47 118 56
						// 43 47 118 57
						// 43 47 118 43
						// 43 47 118 47
						// 43 47 118 56 45
						
	case utf1BOM		// 247 100 76
	case utfEBCDICBOM	// 211 115 102 115
	case scsuBOM		// 14 254 115
	case bocu1BOM		// 251 238 40
	case gb18030BOM		// 132 49 149 51
	
	static func potentialBOMs(fromStartingByte startingByte:UInt8) -> Set<BOM>? {
		switch startingByte {
			case 239:
				return Set([.utf8BOM])
			case 254:
				return Set([.utf16BEBOM])
			case 255:
				return Set([.utf16LEBOM, .utf32LEBOM])
			case 0:
				return Set([.utf32BEBOM])
			case 43:
				return Set([.utf7BOM])
			case 247:
				return Set([.utf1BOM])
			case 221:
				return Set([.utfEBCDICBOM])
			case 14:
				return Set([.scsuBOM])
			case 251:
				return Set([.bocu1BOM])
			case 132:
				return Set([.gb18030BOM])
			default:
				return nil
		}
	}
	
	func canHandle(byte:UInt8, index:Int) -> Bool? {
		switch self {
			case .utf8BOM:
			switch index {
				case 0:
				if byte == 239 {
					return true
				}
				return false
				
				case 1:
				if byte == 187 {
					return true
				}
				return false
				
				case 2:
				if byte == 191 {
					return true
				}
				return false
				
				default:
				return nil
			}
			
			case .utf16BEBOM:
			switch index {
				case 0:
				if byte == 254 {
					return true
				}
				return false
				
				case 1:
				if byte == 255 {
					return true
				}
				return false
				
				default:
				return nil
			}
			
			case .utf16LEBOM:
			switch index {
				case 0:
				if byte == 255 {
					return true
				}
				return false
				
				case 1:
				if byte == 254 {
					return true
				}
				return false
				
				default:
				return nil
			}
			
			case .utf32BEBOM:
			switch index {
				case 0, 1:
				if byte == 0 {
					return true
				}
				return false
				
				case 2:
				if byte == 254 {
					return true
				}
				return false
				
				case 3:
				if byte == 255 {
					return true
				}
				return false
				
				default:
				return nil
			}
			
			case .utf32LEBOM:
			switch index {
				case 0:
				if byte == 255 {
					return true
				}
				return false
				
				case 1:
				if byte == 254 {
					return true
				}
				return false
				
				case 2, 3:
				if byte == 0 {
					return true
				}
				return false
				
				default:
				return nil
			}
			
			case .utf7BOM:
			switch index {
				case 0:
				if byte == 43 {
					return true
				}
				return false
				
				case 1:
				if byte == 47 {
					return true
				}
				return false
				
				case 2:
				if byte == 118 {
					return true
				}
				return false
				
				case 3:
				switch byte {
					case 56, 57, 43, 47:
					return true
					
					default:
					return false
				}
				
				case 4:
				if byte == 45 {
					return true
				}
				return nil
				
				default:
				return nil
			}
			
			case .utf1BOM:
			switch index {
				case 0:
				if byte == 247 {
					return true
				}
				return false
				
				case 1:
				if byte == 100 {
					return true
				}
				return false
				
				case 2:
				if byte == 76 {
					return true
				}
				return false
				
				default:
				return nil
			}
			
			case .utfEBCDICBOM:
			switch index {
				case 0:
				if byte == 221 {
					return true
				}
				return false
				
				case 1:
				if byte == 115 {
					return true
				}
				return false
				
				case 2:
				if byte == 102 {
					return true
				}
				return false
				
				case 3:
				if byte == 115 {
					return true
				}
				return false
				
				default:
				return nil
			}
			
			case .scsuBOM:
			switch index {
				case 0:
				if byte == 14 {
					return true
				}
				return false
				
				case 1:
				if byte == 254 {
					return true
				}
				return false
				
				case 2:
				if byte == 255 {
					return true
				}
				return false
				
				default:
				return nil
			}
			
			case .bocu1BOM:
			switch index {
				case 0:
				if byte == 251 {
					return true
				}
				return false
				
				case 1:
				if byte == 238 {
					return true
				}
				return false
				
				case 2:
				if byte == 40 {
					return true
				}
				return false
				
				default:
				return nil
			}

			case .gb18030BOM:
			switch index {
				case 0:
				if byte == 132 {
					return true
				}
				return false
				
				case 1:
				if byte == 49 {
					return true
				}
				return false
				
				case 2:
				if byte == 149 {
					return true
				}
				return false
				
				case 3:
				if byte == 51 {
					return true
				}
				return false
				
				default:
				return nil
			}
		}
	}
}

public enum LinebreakType:UInt8 {
	case cr
	case lf
	case crlf
}

extension Data {
	public func lineParse() -> [Data]? {
		return self.lineSlice(removeBOM:true)
	}
    public func lineSlice(removeBOM:Bool) -> [Data] {
        return self.lineSlice(removeBOM: removeBOM) ?? [Data]()
    }
    public func lineSlice(removeBOM:Bool) -> [Data]? {
        return self.lineSlice(removeBOM: removeBOM, completeLinesOnly:false).lines
    }
    public func lineSlice(removeBOM:Bool, completeLinesOnly:Bool) -> (lines:[Data]?, remain:Data?) {
		let bytesCount = self.count
		if (bytesCount > 0) {
            
			var bomTail:Int? = nil
			if removeBOM == true {
                
                //this portion of the parser tries to identify the leading byte order mark if the user has specified that they want this stripped
				if var potentialBOMS = BOM.potentialBOMs(fromStartingByte:self[0]) {
					var i = 1
					while i < bytesCount && i < 5 && bomTail == nil && potentialBOMS.count > 0 {
						for (_, curPotentialBOM) in potentialBOMS.enumerated() {
							let canHandle = curPotentialBOM.canHandle(byte:self[i], index:i)
							if canHandle == false {
								potentialBOMS.remove(curPotentialBOM)
							}
							
							if potentialBOMS.count == 1 && canHandle == nil {
								bomTail = i
							}
						}
						i += 1
					}
					if (bomTail == nil && potentialBOMS.count == 1) {
						bomTail = 5
					}
				}
			}

			//itterate to find the line breaks
			var lf = Set<Range<Self.Index>>()
			var lfLast:Self.Index? = nil
			var crLast:Self.Index? = nil
			var cr = Set<Range<Self.Index>>()
			var crlf = Set<Range<Self.Index>>()
			var suspectedLineCount:UInt64 = 0
            
            //this enum and function are needed for later
            enum int_line_mode:Int8 {
                case cr
                case lf
                case crlf
            }
            func isLastLineComplete(_ mode:int_line_mode) -> Bool {
                switch mode {
                    case .cr:
                        guard bytesCount > 0 else {
                            return false
                        }
                        let lastIndex = endIndex.advanced(by: -1)
                        if self[lastIndex] == 13 {
                            return true
                        }
                        return false
                    case .lf:
                        guard bytesCount > 0 else {
                            return false
                        }
                        let lastIndex = endIndex.advanced(by: -1)
                        if self[lastIndex] == 10 {
                            return true
                        }
                        return false
                    case .crlf:
                        guard bytesCount > 1 else {
                            return false
                        }
                        let lastIndex = endIndex.advanced(by: -1)
                        let secondLast = endIndex.advanced(by: -2)
                        if self[lastIndex] == 10 && self[secondLast] == 13 {
                            return true
                        }
                        return false
                }
                return false
            }
			
			//main parsing loop
			for (n, curByte) in enumerated() {
                switch curByte {
                    case 10: //lf
                        let lb:Data.Index
                        if let hasLb = lfLast {
                            lb = hasLb.advanced(by: 1)
                        } else {
                            lb = bomTail ?? startIndex
                        }
                        
                        //was last character cr?
                        if (crLast != nil && crLast! == n-1) {
                            crlf.update(with:lb..<crLast!)
                        } else {
                            suspectedLineCount += 1
                        }

                        lf.update(with:lb..<n)
                        lfLast = n
                    case 13: //cr
                        let lb:Data.Index
                        if let hasLb = crLast {
                            lb = hasLb.advanced(by: 1)
                        } else {
                            lb = bomTail ?? startIndex
                        }

                        cr.update(with:lb..<n)
                        crLast = n
                        suspectedLineCount += 1
                    default:
                    break;
                }
            }
			
			if suspectedLineCount == 0 { 
				let lb = bomTail ?? startIndex
                
                if completeLinesOnly == true {
                    return (lines:nil, remain:self)
                } else {
                    return (lines:[self[lb..<bytesCount]], remain:nil)
                }
			}
			
			let crlfTotal = crlf.count
			let suspectedLineCountAsDouble = Double(suspectedLineCount)
			var lfTotal = lf.count - crlfTotal
			if (lfTotal < 0) {
				lfTotal = 0
			}
			var crTotal = cr.count - crlfTotal
			if (crTotal < 0) {
				crTotal = 0
			}
			
			let lfPercent:Double = Double(lfTotal)/suspectedLineCountAsDouble
			let crPercent:Double = Double(crTotal)/suspectedLineCountAsDouble
			let crlfPercent:Double = Double(crlfTotal)/suspectedLineCountAsDouble

			if (crlfPercent > crPercent && crlfPercent > lfPercent) {
				var lb:Self.Index
                if let hasLb = lfLast {
                    lb = hasLb.advanced(by: 1)
                } else {
                    lb = bomTail ?? startIndex
                }

				if lb < endIndex {
					crlf.update(with:lb..<endIndex)
				}
                
                var linesToReturn = crlf.sorted(by: { $0.lowerBound < $1.lowerBound }).map {
                    self[$0]
                }
                
                //remove last line if not complete
                if completeLinesOnly == true {
                    if isLastLineComplete(.crlf) == true {
                        if linesToReturn.count == 1 {
                            return (lines:[self], remain:nil)
                        } else {
                            return (lines:linesToReturn, remain:nil)
                        }
                    } else {
                        if linesToReturn.count == 1 {
                            return (lines:nil, remain:self)
                        } else {
                            let lastLine = linesToReturn.removeLast()
                            return (lines:linesToReturn, remain:lastLine)
                        }
                    }
                } else {
                    return (lines:linesToReturn, remain:nil)
                }
				
			} else if (lfPercent > crlfPercent && lfPercent > crPercent) {
				var lb:Self.Index
                if let hasLb = lfLast {
                    lb = hasLb.advanced(by: 1)
                } else {
                    lb = bomTail ?? startIndex
                }

                if lb < endIndex {
                    lf.update(with:lb..<endIndex)
                }
				
                var linesToReturn = lf.sorted(by: { $0.lowerBound < $1.lowerBound }).map {
                    self[$0]
                }
				
                //remove last line if not complete
                if completeLinesOnly == true {
                    if isLastLineComplete(.crlf) == true {
                        if linesToReturn.count == 1 {
                            return (lines:[self], remain:nil)
                        } else {
                            return (lines:linesToReturn, remain:nil)
                        }
                    } else {
                        if linesToReturn.count == 1 {
                            return (lines:nil, remain:self)
                        } else {
                            let lastLine = linesToReturn.removeLast()
                            return (lines:linesToReturn, remain:lastLine)
                        }
                    }
                } else {
                    return (lines:linesToReturn, remain:nil)
                }
                
			} else {
				var lb:Self.Index
                if let hasLb = crLast {
                    lb = hasLb.advanced(by: 1)
                } else {
                    lb = bomTail ?? startIndex
                }
                
				if lb < endIndex {
					cr.update(with:lb..<endIndex)
				}
			
                var linesToReturn = cr.sorted(by: { $0.lowerBound < $1.lowerBound }).map {
                    self[$0]
                }
                
                //remove last line if not complete
                if completeLinesOnly == true {
                    if isLastLineComplete(.crlf) == true {
                        if linesToReturn.count == 1 {
                            return (lines:[self], remain:nil)
                        } else {
                            return (lines:linesToReturn, remain:nil)
                        }
                    } else {
                        if linesToReturn.count == 1 {
                            return (lines:nil, remain:self)
                        } else {
                            let lastLine = linesToReturn.removeLast()
                            return (lines:linesToReturn, remain:lastLine)
                        }
                    }
                } else {
                    return (lines:linesToReturn, remain:nil)
                }
			}
		} else {
            return (lines:nil, remain:nil)
		}
	}
	
    func cutLines(flush:Bool) -> (lines:[Data]?, cut:Data.Index) {
    	if (flush) {
			print("CL CALLED \(self.count)")
		}
		//itterate to find the line breaks
		var lf = Set<Range<Self.Index>>()
		var lfLast:Self.Index? = nil
		var crLast:Self.Index? = nil
		var cr = Set<Range<Self.Index>>()
		var crlf = Set<Range<Self.Index>>()
		var suspectedLineCount:UInt64 = 0
		
		//main parsing loop
		for (n, curByte) in enumerated() {
			switch curByte {
				case 10: //lf
					let lb:Data.Index
					if let hasLb = lfLast {
						lb = hasLb.advanced(by: 1)
					} else {
						lb = startIndex
					}
					
					//was last character cr?
					if (crLast != nil && crLast! == n-1) {
						crlf.update(with:lb..<crLast!)
					} else {
						suspectedLineCount += 1
					}

					lf.update(with:lb..<n)
					lfLast = n
				case 13: //cr
					let lb:Data.Index
					if let hasLb = crLast {
						lb = hasLb.advanced(by: 1)
					} else {
						lb = startIndex
					}

					cr.update(with:lb..<n)
					crLast = n
					suspectedLineCount += 1
				default:
				break;
			}
		}
		
		if (flush) {
			print("OK COOL WE FUCKING PARSED THINGS")
		}
		//if there were no lines, return early
		if suspectedLineCount == 0 { 
			return (lines:nil, cut:self.startIndex)
		}
		
		let crlfTotal = crlf.count
		let suspectedLineCountAsDouble = Double(suspectedLineCount)
		var lfTotal = lf.count - crlfTotal
		if (lfTotal < 0) {
			lfTotal = 0
		}
		var crTotal = cr.count - crlfTotal
		if (crTotal < 0) {
			crTotal = 0
		}
	
		func returnValueForLines(_ linesIn:[Range<Self.Index>]) -> (lines:[Data]?, cut:Self.Index) {
			print("OK FUCKING COOL THE THING IS BEING CALLED")
			if linesIn.count <= 1 && flush == false {
				return (lines:nil, cut:startIndex)
			} else if flush == false {
				var pickLines = linesIn
				let lastLine = pickLines.removeLast()
                return (lines:pickLines.map { self[$0] }, cut:lastLine.lowerBound)
            } else {
                return (lines:linesIn.map { self[$0] }, cut:endIndex)
            }
		}
		
		let lfPercent:Double = Double(lfTotal)/suspectedLineCountAsDouble
		let crPercent:Double = Double(crTotal)/suspectedLineCountAsDouble
		let crlfPercent:Double = Double(crlfTotal)/suspectedLineCountAsDouble

		if (crlfPercent > crPercent && crlfPercent > lfPercent) {
			//CR-LF MODE
			
			//add the final line
			var lb:Self.Index
			if let hasLb = lfLast {
				lb = hasLb.advanced(by:1)
			} else {
				lb = startIndex
			}
			if lb < endIndex {
				crlf.update(with:lb..<endIndex)
			}
			
			return returnValueForLines(crlf.sorted(by: { $0.lowerBound < $1.lowerBound }))
			
			//parse the line indexes and return
		} else if (lfPercent > crlfPercent && lfPercent > crPercent) {
			//LF MODE
			
			//add the final line
			var lb:Self.Index
			if let hasLb = lfLast {
				lb = hasLb.advanced(by:1)
			} else {
				lb = startIndex
			}
			if lb < endIndex {
				lf.update(with:lb..<endIndex)
			}
			
			return returnValueForLines(lf.sorted(by: { $0.lowerBound < $1.lowerBound }))
		} else {
			//CR MODE
			
			//add the final line
			var lb:Self.Index
			if let hasLb = crLast {
				lb = hasLb.advanced(by: 1)
			} else {
				lb = startIndex
			}
			if lb < endIndex {
				cr.update(with:lb..<endIndex)
			}
			
			return returnValueForLines(cr.sorted(by: { $0.lowerBound < $1.lowerBound }))
		}
	}
}
