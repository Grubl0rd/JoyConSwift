//
//  JoyCon.swift
//  JoyConSwift
//
//  Created by magicien on 2019/06/16.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import Foundation

public enum JoyCon {
    public enum ControllerType: String {
        case JoyConL = "Joy-Con (L)"
        case JoyConR = "Joy-Con (R)"
        case ProController = "Pro Controller"
        case unknown = "unknown"
    }
    
    public enum OutputType: UInt8 {
        case subcommand = 0x01
        case firmwareUpdate = 0x03
        case rumble = 0x10
        case nfcIR = 0x11
    }
    
    public enum HCIState: UInt8 {
        case disconnect = 0x00
        case rebootAndReconnect = 0x01
        case rebootAndParing = 0x02
        case rebootAndReconnectHome = 0x04
    }
    
    public enum InputMode: UInt8 {
        case pollingNFCIR = 0x00
        case pollingNFCIRConfig = 0x01
        case pollingNFCIRData = 0x02
        case pollingIRCamera = 0x03
        case standardFull = 0x30
        case nfcIR = 0x31
        case simple = 0x3F
    }
    
    public enum PlayerLightPattern {
        case on
        case off
        case flash
    }
    
    public enum BatteryStatus: UInt8 {
        case full
        case medium
        case low
        case critical
        case empty
        case unknown
    }
    
    public enum Button {
        // JoyCon (L)
        case Minus
        case Capture
        case LStick
        case Down
        case Up
        case Right
        case Left
        case LeftSR
        case LeftSL
        case L
        case ZL
        
        // JoyCon (R)
        case Plus
        case Home
        case RStick
        case X
        case Y
        case B
        case A
        case RightSR
        case RightSL
        case R
        case ZR
    }
    
    public enum StickDirection {
        case Up
        case UpRight
        case Right
        case DownRight
        case Down
        case DownLeft
        case Left
        case UpLeft
        case Neutral
    }
}