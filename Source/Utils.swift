//
//  Utils.swift
//  JoyConSwift
//
//  Created by magicien on 2019/06/16.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import Foundation

func ReadInt16(from ptr: UnsafePointer<UInt8>) -> Int16 {
    return UnsafeRawPointer(ptr).loadUnaligned(as: Int16.self)
}

func ReadUInt16(from ptr: UnsafePointer<UInt8>) -> UInt16 {
    return UnsafeRawPointer(ptr).loadUnaligned(as: UInt16.self)
}

func ReadInt32(from ptr: UnsafePointer<UInt8>) -> Int32 {
    return UnsafeRawPointer(ptr).loadUnaligned(as: Int32.self)
}

func ReadUInt32(from ptr: UnsafePointer<UInt8>) -> UInt32 {
    return UnsafeRawPointer(ptr).loadUnaligned(as: UInt32.self)
}
