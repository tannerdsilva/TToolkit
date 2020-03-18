/*
WORK IN PROGRESS

import Foundation

// limbs are single digits in base 2^64
// each index of a limbs array storess one digit of the number.
// the least significant digit is stored at index 0. The most significant digit is stored at the last index
public typealias Limbs = [UInt64]
public typealias Limb = UInt64


// a digit is a number in base 10^18
// digits are used for printing numbers. digits are created from limbs
public typealias Digits = [UInt64]
public typealias Digit = UInt64

precedencegroup ExponentiationPrecedence
{
	associativity: left
	higherThan: MultiplicationPrecedence
	lowerThan: BitwiseShiftPrecedence
}

// Exponentiation operator
infix operator ** : ExponentiationPrecedence

*/