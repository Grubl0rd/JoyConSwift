//
//  Controller.swift
//  JoyConSwift
//
//  Created by magicien on 2019/06/16.
//  Copyright © 2019 DarkHorse. All rights reserved.
//

import Foundation
import SceneKit

public class Controller {
    struct StickCalibration {
        var minXDiff: CGFloat
        var midX: CGFloat
        var maxXDiff: CGFloat
        var minYDiff: CGFloat
        var midY: CGFloat
        var maxYDiff: CGFloat
        var deadZone: CGFloat
        var rangeRatio: CGFloat
    }
    
    struct AccSensorCalibration {
        var xOrigin: CGFloat
        var yOrigin: CGFloat
        var zOrigin: CGFloat
        var xSensitivity: CGFloat
        var ySensitivity: CGFloat
        var zSensitivity: CGFloat
        var xCoeff: CGFloat
        var yCoeff: CGFloat
        var zCoeff: CGFloat
        var xOffset: CGFloat
        var yOffset: CGFloat
        var zOffset: CGFloat
    }
    
    struct GyroSensorCalibration {
        var xSensitivity: CGFloat
        var ySensitivity: CGFloat
        var zSensitivity: CGFloat
        var xCoeff: CGFloat
        var yCoeff: CGFloat
        var zCoeff: CGFloat
        var xOffset: CGFloat
        var yOffset: CGFloat
        var zOffset: CGFloat
    }
    
    let device: IOHIDDevice
    public let serialID: String
    var handlers: [UInt8: (IOHIDValue) -> Void]
    var spiReadHandler: [UInt32: ([UInt8]) -> Void]
    private var packetCounter: UInt8
    
    private var subcommandQueue: [Subcommand]
    private var processingSubcommand: Subcommand?
    
    var lStickFactoryCalibration: StickCalibration?
    var lStickUserCalibration: StickCalibration?
    var lStickCalibration: StickCalibration? {
        get {
            return self.lStickUserCalibration ?? self.lStickFactoryCalibration
        }
    }
    
    var rStickFactoryCalibration: StickCalibration?
    var rStickUserCalibration: StickCalibration?
    var rStickCalibration: StickCalibration? {
        get {
            return self.rStickUserCalibration ?? self.rStickFactoryCalibration
        }
    }
    
    var accFactoryCalibration: AccSensorCalibration?
    var accUserCalibration: AccSensorCalibration?
    var accCalibration: AccSensorCalibration? {
        get {
            return self.accUserCalibration ?? self.accFactoryCalibration
        }
    }
    
    var gyroFactoryCalibration: GyroSensorCalibration?
    var gyroUserCalibration: GyroSensorCalibration?
    var gyroCalibration: GyroSensorCalibration? {
        get {
            return self.gyroUserCalibration ?? self.gyroFactoryCalibration
        }
    }

    public var type: JoyCon.ControllerType {
        return .unknown
    }
    
    public internal(set) var isConnected: Bool
    public internal(set) var battery: JoyCon.BatteryStatus
    public internal(set) var isCharging: Bool
    public internal(set) var buttonState: [JoyCon.Button: Bool]
    public internal(set) var leftStickDirection: JoyCon.StickDirection
    public internal(set) var rightStickDirection: JoyCon.StickDirection
    public internal(set) var lStickRawPos: CGPoint
    public internal(set) var lStickPos: CGPoint
    public internal(set) var rStickRawPos: CGPoint
    public internal(set) var rStickPos: CGPoint
    public internal(set) var acceleration: SCNVector3
    public internal(set) var gyro: SCNVector3
    public internal(set) var bodyColor: CGColor
    public internal(set) var buttonColor: CGColor
    public internal(set) var leftGripColor: CGColor?
    public internal(set) var rightGripColor: CGColor?
    
    public var buttonPressHandler: ((JoyCon.Button) -> Void)?
    public var buttonReleaseHandler: ((JoyCon.Button) -> Void)?
    public var leftStickHandler: ((JoyCon.StickDirection) -> Void)?
    public var rightStickHandler: ((JoyCon.StickDirection) -> Void)?
    public var leftStickPosHandler: ((_ pos: CGPoint) -> Void)?
    public var rightStickPosHandler: ((_ pos: CGPoint) -> Void)?
    public var sensorHandler: (() -> Void)?
    
    public init(device: IOHIDDevice) {
        self.device = device
        self.serialID = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? ""
        self.handlers = [:]
        self.spiReadHandler = [:]
        self.isConnected = false
        self.packetCounter = 0
        self.subcommandQueue = []
        self.battery = .unknown
        self.isCharging = false
        self.buttonState = [:]
        self.leftStickDirection = .Neutral
        self.rightStickDirection = .Neutral
        self.lStickRawPos = CGPoint(x: 0, y: 0)
        self.lStickPos = CGPoint(x: 0, y: 0)
        self.rStickRawPos = CGPoint(x: 0, y: 0)
        self.rStickPos = CGPoint(x: 0, y: 0)
        self.acceleration = SCNVector3(x: 0, y: 0, z: 0)
        self.gyro = SCNVector3(x: 0, y: 0, z: 0)
        self.bodyColor = CGColor(red: 0.333, green: 0.333, blue: 0.333, alpha: 0.333)
        self.buttonColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    }
    
    func readInitializeData() {
        self.readControllerColor()
        self.readCalibration()
    }
    
    func handleError(result: Int32, value: IOHIDValue) {}

    func handleInput(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let reportID = IOHIDElementGetReportID(element)
        
        switch reportID {
        case 0x3F:
            self.handleSimpleInput(value: value)
        case 0x21:
            self.handleFullCommandInput(value: value)
        case 0x30:
            self.handleFullSensorInput(value: value)
        default:
            break
        }
    }
    
    func handleSimpleInput(value: IOHIDValue) {
        self.readSimpleState(value: value)
    }

    func handleFullCommandInput(value: IOHIDValue) {
        let ptr = IOHIDValueGetBytePtr(value)
        let ack = (ptr+12).pointee
        if ack & 0x80 == 0 {
            // NACK
            self.receiveSubcommand(value: value)
            return
        }
        
        self.readStandardState(value: value)

        if ack == 0x80 {
            // Simple ACK
            self.receiveSubcommand(value: value)
            return
        }

        self.receiveSubcommand(value: value)
    }
    
    func handleFullSensorInput(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let reportID = IOHIDElementGetReportID(element)
        let reportCount = IOHIDElementGetReportCount(element)
        
        if reportCount <= 1 {
            // There's no data.
            return
        }

        self.readStandardState(value: value)
        self.readSensorData(value: value)
        
        if reportID == 0x31 {
            self.readNFCData(value: value)
        }
    }

    func readSimpleState(value: IOHIDValue) {}

    func readStandardState(value: IOHIDValue) {
        let ptr = IOHIDValueGetBytePtr(value)
        let data = (ptr+1).pointee
        
        self.isCharging = data & 0x10 == 0x10
        
        switch (data & 0xE0) {
        case 0x80:
            self.battery = .full
        case 0x60:
            self.battery = .medium
        case 0x40:
            self.battery = .low
        case 0x20:
            self.battery = .critical
        case 0x00:
            self.battery = .empty
        default:
            self.battery = .unknown
        }
    }
    
    func readSensorData(value: IOHIDValue) {
        let ptr = IOHIDValueGetBytePtr(value)

        if self.sensorHandler != nil {
            self.readSensorData(at: ptr + 12)
            self.readSensorData(at: ptr + 24)
        }
        self.readSensorData(at: ptr + 36)
    }
    
    func readSensorData(at ptr: UnsafePointer<UInt8>) {
        let axInt = ReadInt16(from: ptr)
        let ayInt = ReadInt16(from: ptr + 2)
        let azInt = ReadInt16(from: ptr + 4)
        
        if let cal = self.accCalibration {
            self.acceleration.x = (CGFloat(axInt) - cal.xOffset) * cal.xCoeff
            self.acceleration.y = (CGFloat(ayInt) - cal.yOffset) * cal.yCoeff
            self.acceleration.z = (CGFloat(azInt) - cal.zOffset) * cal.zCoeff + 1.0
        } else {
            self.acceleration.x = CGFloat(axInt) * 0.000244
            self.acceleration.y = CGFloat(ayInt) * 0.000244
            self.acceleration.z = CGFloat(azInt) * 0.000244
        }
        
        let rxInt = ReadInt16(from: ptr + 6)
        let ryInt = ReadInt16(from: ptr + 8)
        let rzInt = ReadInt16(from: ptr + 10)
        
        if let cal = self.gyroCalibration {
            self.gyro.x = (CGFloat(rxInt) - cal.xOffset) * cal.xCoeff
            self.gyro.y = (CGFloat(ryInt) - cal.yOffset) * cal.yCoeff
            self.gyro.z = (CGFloat(rzInt) - cal.zOffset) * cal.zCoeff
        } else {
            self.gyro.x = CGFloat(rxInt) * 0.06103
            self.gyro.y = CGFloat(ryInt) * 0.06103
            self.gyro.z = CGFloat(rzInt) * 0.06103
        }

        self.sensorHandler?()
    }
    
    func readNFCData(value: IOHIDValue) {
        
    }
    
    func reportOutput(type: JoyCon.OutputType, data: [UInt8]) {
        self.packetCounter = (self.packetCounter + 1) & 0x0f;
        
        let report: [UInt8] = [type.rawValue, self.packetCounter] + data
        let result = IOHIDDeviceSetReport(self.device, kIOHIDReportTypeOutput, CFIndex(type.rawValue), report, report.count);
        if (result != kIOReturnSuccess) {
            print(String(format: "IOHIDDeviceSetReport error: %d", result))
            return
        }
    }
    
    func setButtonState(state: [JoyCon.Button: Bool]) {
        state.forEach { [weak self] (button, isPushed) in
            guard let _self = self else { return }
            let wasPushed = _self.buttonState[button] ?? false
            if !wasPushed && isPushed {
                _self.buttonPressHandler?(button)
            } else if wasPushed && !isPushed {
                _self.buttonReleaseHandler?(button)
            }
            _self.buttonState[button] = isPushed
        }
    }
    
    func setLeftStickDirection(direction: JoyCon.StickDirection) {
        if self.leftStickDirection != direction {
            self.leftStickDirection = direction
            self.leftStickHandler?(direction)
        }
    }

    func setRightStickDirection(direction: JoyCon.StickDirection) {
        if self.rightStickDirection != direction {
            self.rightStickDirection = direction
            self.rightStickHandler?(direction)
        }
    }

    func createRumbleData() -> [UInt8] {
        // TODO: Set given frequency
        
        // 00 01 40 40 => 320Hz - 160Hz
        // 4bytes for Left Joy-Con, 4bytes for Right Joy-Con
        return [0x00, 0x01, 0x40, 0x40, 0x00, 0x01, 0x40, 0x40]
    }
    
    func sendSubcommand(type: Subcommand.CommandType, data: [UInt8], responseHandler: @escaping (_ value: IOHIDValue?) -> Void) {
        guard self.isConnected else { return }

        let rumbleData = self.createRumbleData()
        let sendData = rumbleData + [type.rawValue] + data
        let command = Subcommand(type: type, data: sendData, responseHandler: responseHandler)
        
        self.subcommandQueue.append(command)
        self.processSubcommand()
    }
    
    func sendSubcommand(type: Subcommand.CommandType, data: [UInt8]) {
        self.sendSubcommand(type: type, data: data) { _ in }
    }
    
    func receiveSubcommand(value: IOHIDValue) {
        guard let cmd = self.processingSubcommand else { return }

        let ptr = IOHIDValueGetBytePtr(value)
        let ack = (ptr+12).pointee
        let subcommand = (ptr+13).pointee
        
        if cmd.type.rawValue == subcommand {
            if ack & 0x80 == 0 {
                // NACK
                cmd.responseHandler?(nil)
            } else {
                cmd.responseHandler?(value)
            }
            self.processingSubcommand = nil
            self.processSubcommand()
        }
    }
        
    func processSubcommand() {
        guard self.processingSubcommand == nil else { return }
        guard self.subcommandQueue.count > 0 else { return }
        
        let cmd = self.subcommandQueue.removeFirst()
        self.processingSubcommand = cmd

        cmd.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] timer in
            timer.invalidate()
            guard let processingSubcommand = self?.processingSubcommand else { return }
            guard timer == processingSubcommand.timer else { return }
            
            cmd.responseHandler?(nil)
            self?.processingSubcommand = nil
            self?.processSubcommand()
        }
        
        self.reportOutput(type: .subcommand, data: cmd.data)
    }
    
    public func setHCIState(state: JoyCon.HCIState) {
        guard self.isConnected else { return }
        
        let data: UInt8 = state.rawValue
        self.sendSubcommand(type: .setHCIState, data: [data])
    }
        
    public func enableIMU(enable: Bool) {
        guard self.isConnected else { return }

        let data: UInt8 = enable ? 1 : 0
        self.sendSubcommand(type: .enableIMU, data: [data])
    }
    
    public func setInputMode(mode: JoyCon.InputMode) {
        guard self.isConnected else { return }
        
        let data: UInt8 = mode.rawValue
        self.sendSubcommand(type: .setInputMode, data: [data])
    }
    
    public func setPlayerLights(
        l1: JoyCon.PlayerLightPattern,
        l2: JoyCon.PlayerLightPattern,
        l3: JoyCon.PlayerLightPattern,
        l4: JoyCon.PlayerLightPattern) {
        guard self.isConnected else { return }
        
        let bit0: UInt8 = l1 == .on ? 0x01 : 0
        let bit1: UInt8 = l2 == .on ? 0x02 : 0
        let bit2: UInt8 = l3 == .on ? 0x04 : 0
        let bit3: UInt8 = l4 == .on ? 0x08 : 0
        let bit4: UInt8 = l1 == .flash ? 0x10 : 0
        let bit5: UInt8 = l2 == .flash ? 0x20 : 0
        let bit6: UInt8 = l3 == .flash ? 0x40 : 0
        let bit7: UInt8 = l4 == .flash ? 0x80 : 0
        
        let data: UInt8 = bit0 | bit1 | bit2 | bit3 | bit4 | bit5 | bit6 | bit7
        
        self.sendSubcommand(type: .setPlayerLights, data: [data])
    }
    
    public func readSPIFlash(address: UInt32, length: UInt8, handler: @escaping ([UInt8]) -> Void) {
        let data: [UInt8] = [
            UInt8(address & 0xFF),
            UInt8((address >> 8) & 0xFF),
            UInt8((address >> 16) & 0xFF),
            UInt8(address >> 24),
            length
        ]
        self.spiReadHandler[address] = handler
        self.sendSubcommand(type: .getSPIFlash, data: data) { [weak self] response in
            guard let data = response else {
                // NACK or Timeout
                return
            }
            self?.handleReadSPIFlash(value: data)
        }
    }
    
    func handleReadSPIFlash(value: IOHIDValue) {
        let ptr = IOHIDValueGetBytePtr(value)
        let address = ReadUInt32(from: ptr+14)
        guard let handler = self.spiReadHandler[address] else { return }
        
        let length = Int((ptr+18).pointee)
        let buffer = UnsafeBufferPointer(start: ptr+19, count: length)
        let data = Array(buffer)
        handler(data)
        
        self.spiReadHandler.removeValue(forKey: address)
    }
    
    func readCalibration() {}
    
    func readLStickCalibration() {
        self.readSPIFlash(address: 0x603d, length: 0x09) { [weak self] data in
            let data0: UInt16 = (UInt16(data[1]) << 8) & 0xF00 | UInt16(data[0])
            let data1: UInt16 = (UInt16(data[2]) << 4) | (UInt16(data[1]) >> 4)
            let data2: UInt16 = (UInt16(data[4]) << 8) & 0xF00 | UInt16(data[3])
            let data3: UInt16 = (UInt16(data[5]) << 4) | (UInt16(data[4]) >> 4)
            let data4: UInt16 = (UInt16(data[7]) << 8) & 0xF00 | UInt16(data[6])
            let data5: UInt16 = (UInt16(data[8]) << 4) | (UInt16(data[7]) >> 4)
            
            self?.lStickFactoryCalibration = StickCalibration(
                minXDiff: CGFloat(data4),
                midX: CGFloat(data2),
                maxXDiff: CGFloat(data0),
                minYDiff: CGFloat(data5),
                midY: CGFloat(data3),
                maxYDiff: CGFloat(data1),
                deadZone: 0,
                rangeRatio: 0
            )
        }
        self.readSPIFlash(address: 0x6086, length: 18) { [weak self] data in
            // TODO: Check if the calculaition is correct.
            let deadzone = data[3]
            let range = UInt16(data[4]) + ((UInt16(data[5]) & 0xF0) << 4)
            
            self?.lStickFactoryCalibration?.deadZone = CGFloat(deadzone)
            self?.lStickFactoryCalibration?.rangeRatio = CGFloat(range)
        }
        
        self.readSPIFlash(address: 0x8010, length: 0x0B) { [weak self] data in
            if (data[0] != 0xB2 || data[1] != 0xA1) {
                // No user calibration data
                return;
            }
            
            let data0: UInt16 = (UInt16(data[3]) << 8) & 0xF00 | UInt16(data[2])
            let data1: UInt16 = (UInt16(data[4]) << 4) | (UInt16(data[3]) >> 4)
            let data2: UInt16 = (UInt16(data[6]) << 8) & 0xF00 | UInt16(data[5])
            let data3: UInt16 = (UInt16(data[7]) << 4) | (UInt16(data[6]) >> 4)
            let data4: UInt16 = (UInt16(data[9]) << 8) & 0xF00 | UInt16(data[8])
            let data5: UInt16 = (UInt16(data[10]) << 4) | (UInt16(data[9]) >> 4)
            
            self?.lStickUserCalibration = StickCalibration(
                minXDiff: CGFloat(data4),
                midX: CGFloat(data2),
                maxXDiff: CGFloat(data0),
                minYDiff: CGFloat(data5),
                midY: CGFloat(data3),
                maxYDiff: CGFloat(data1),
                deadZone: self?.lStickFactoryCalibration?.deadZone ?? 0,
                rangeRatio: self?.lStickFactoryCalibration?.rangeRatio ?? 0
            )
        }
    }
    
    func readRStickCalibration() {
        self.readSPIFlash(address: 0x6046, length: 0x09) { [weak self] data in
            let data0: UInt16 = (UInt16(data[1]) << 8) & 0xF00 | UInt16(data[0])
            let data1: UInt16 = (UInt16(data[2]) << 4) | (UInt16(data[1]) >> 4)
            let data2: UInt16 = (UInt16(data[4]) << 8) & 0xF00 | UInt16(data[3])
            let data3: UInt16 = (UInt16(data[5]) << 4) | (UInt16(data[4]) >> 4)
            let data4: UInt16 = (UInt16(data[7]) << 8) & 0xF00 | UInt16(data[6])
            let data5: UInt16 = (UInt16(data[8]) << 4) | (UInt16(data[7]) >> 4)
            
            self?.rStickFactoryCalibration = StickCalibration(
                minXDiff: CGFloat(data2),
                midX: CGFloat(data0),
                maxXDiff: CGFloat(data4),
                minYDiff: CGFloat(data3),
                midY: CGFloat(data1),
                maxYDiff: CGFloat(data5),
                deadZone: 0,
                rangeRatio: 0
            )
        }
        self.readSPIFlash(address: 0x6098, length: 18) { [weak self] data in
            // TODO: Check if the calculaition is correct.
            let deadzone = data[3]
            let range = UInt16(data[4]) + ((UInt16(data[5]) & 0xF0) << 4)
            
            self?.rStickFactoryCalibration?.deadZone = CGFloat(deadzone)
            self?.rStickFactoryCalibration?.rangeRatio = CGFloat(range)
        }
        
        self.readSPIFlash(address: 0x801B, length: 0x0B) { [weak self] data in
            if (data[0] != 0xB2 || data[1] != 0xA1) {
                // No user calibration data
                return;
            }

            let data0: UInt16 = (UInt16(data[3]) << 8) & 0xF00 | UInt16(data[2])
            let data1: UInt16 = (UInt16(data[4]) << 4) | (UInt16(data[3]) >> 4)
            let data2: UInt16 = (UInt16(data[6]) << 8) & 0xF00 | UInt16(data[5])
            let data3: UInt16 = (UInt16(data[7]) << 4) | (UInt16(data[6]) >> 4)
            let data4: UInt16 = (UInt16(data[9]) << 8) & 0xF00 | UInt16(data[8])
            let data5: UInt16 = (UInt16(data[10]) << 4) | (UInt16(data[9]) >> 4)
            
            self?.rStickUserCalibration = StickCalibration(
                minXDiff: CGFloat(data2),
                midX: CGFloat(data0),
                maxXDiff: CGFloat(data4),
                minYDiff: CGFloat(data3),
                midY: CGFloat(data1),
                maxYDiff: CGFloat(data5),
                deadZone: self?.rStickUserCalibration?.deadZone ?? 0,
                rangeRatio: self?.rStickUserCalibration?.rangeRatio ?? 0
            )
        }
    }
    
    func readSensorCalibration() {
        // Factory calibration
        self.readSPIFlash(address: 0x6020, length: 0x18) { [weak self] data in
            let ptr = UnsafePointer<UInt8>(data)
            
            let accXOrigin = CGFloat(ReadInt16(from: ptr))
            let accYOrigin = CGFloat(ReadInt16(from: ptr+2))
            let accZOrigin = CGFloat(ReadInt16(from: ptr+4))
            let accXSensitivity = CGFloat(ReadInt16(from: ptr+6))
            let accYSensitivity = CGFloat(ReadInt16(from: ptr+8))
            let accZSensitivity = CGFloat(ReadInt16(from: ptr+10))
            
            let gyroXOffset = CGFloat(ReadInt16(from: ptr+12))
            let gyroYOffset = CGFloat(ReadInt16(from: ptr+14))
            let gyroZOffset = CGFloat(ReadInt16(from: ptr+16))
            let gyroXSensitivity = CGFloat(ReadInt16(from: ptr+18))
            let gyroYSensitivity = CGFloat(ReadInt16(from: ptr+20))
            let gyroZSensitivity = CGFloat(ReadInt16(from: ptr+22))

            self?.accFactoryCalibration = AccSensorCalibration(
                xOrigin: accXOrigin,
                yOrigin: accYOrigin,
                zOrigin: accZOrigin,
                xSensitivity: accXSensitivity,
                ySensitivity: accYSensitivity,
                zSensitivity: accZSensitivity,
                xCoeff: 4.0 / (accXSensitivity - accXOrigin),
                yCoeff: 4.0 / (accYSensitivity - accYOrigin),
                zCoeff: 4.0 / (accZSensitivity - accZOrigin),
                xOffset: 0,
                yOffset: 0,
                zOffset: 0
            )
            self?.gyroFactoryCalibration = GyroSensorCalibration(
                xSensitivity: gyroXSensitivity,
                ySensitivity: gyroYSensitivity,
                zSensitivity: gyroZSensitivity,
                xCoeff: 936.0 / (gyroXSensitivity - gyroXOffset),
                yCoeff: 936.0 / (gyroYSensitivity - gyroYOffset),
                zCoeff: 936.0 / (gyroZSensitivity - gyroZOffset),
                xOffset: gyroXOffset,
                yOffset: gyroYOffset,
                zOffset: gyroZOffset
            )
        }
        self.readSPIFlash(address: 0x6080, length: 0x06) { [weak self] data in
            let ptr = UnsafePointer<UInt8>(data)
            
            self?.accFactoryCalibration?.xOffset = CGFloat(ReadInt16(from: ptr))
            self?.accFactoryCalibration?.yOffset = CGFloat(ReadInt16(from: ptr+2))
            self?.accFactoryCalibration?.zOffset = CGFloat(ReadInt16(from: ptr+4))
        }
        
        // User calibration
        self.readSPIFlash(address: 0x8026, length: 0x1A) { [weak self] data in
            let ptr = UnsafePointer<UInt8>(data)
            let magic = ReadUInt16(from: ptr)

            if (magic != 0xA1B2) {
                // No user calibration data
                return
            }
            
            let accXOrigin = CGFloat(ReadInt16(from: ptr+2))
            let accYOrigin = CGFloat(ReadInt16(from: ptr+4))
            let accZOrigin = CGFloat(ReadInt16(from: ptr+6))
            let accXSensitivity = CGFloat(ReadInt16(from: ptr+8))
            let accYSensitivity = CGFloat(ReadInt16(from: ptr+10))
            let accZSensitivity = CGFloat(ReadInt16(from: ptr+12))
            
            let gyroXOffset = CGFloat(ReadInt16(from: ptr+14))
            let gyroYOffset = CGFloat(ReadInt16(from: ptr+16))
            let gyroZOffset = CGFloat(ReadInt16(from: ptr+18))
            let gyroXSensitivity = CGFloat(ReadInt16(from: ptr+20))
            let gyroYSensitivity = CGFloat(ReadInt16(from: ptr+22))
            let gyroZSensitivity = CGFloat(ReadInt16(from: ptr+24))
            
            self?.accUserCalibration = AccSensorCalibration(
                xOrigin: accXOrigin,
                yOrigin: accYOrigin,
                zOrigin: accZOrigin,
                xSensitivity: accXSensitivity,
                ySensitivity: accYSensitivity,
                zSensitivity: accZSensitivity,
                xCoeff: 4.0 / (accXSensitivity - accXOrigin),
                yCoeff: 4.0 / (accYSensitivity - accYOrigin),
                zCoeff: 4.0 / (accZSensitivity - accZOrigin),
                xOffset: self?.accFactoryCalibration?.xOffset ?? 0,
                yOffset: self?.accFactoryCalibration?.yOffset ?? 0,
                zOffset: self?.accFactoryCalibration?.zOffset ?? 0
            )
            self?.gyroUserCalibration = GyroSensorCalibration(
                xSensitivity: gyroXSensitivity,
                ySensitivity: gyroYSensitivity,
                zSensitivity: gyroZSensitivity,
                xCoeff: 936.0 / (gyroXSensitivity - gyroXOffset),
                yCoeff: 936.0 / (gyroYSensitivity - gyroYOffset),
                zCoeff: 936.0 / (gyroZSensitivity - gyroZOffset),
                xOffset: gyroXOffset,
                yOffset: gyroYOffset,
                zOffset: gyroZOffset
            )
        }
    }
    
    func readLStickData(value: IOHIDValue) {
        guard let calib = self.lStickCalibration else { return }

        let ptr = IOHIDValueGetBytePtr(value)
        let stick1 = (ptr+5).pointee
        let stick2 = (ptr+6).pointee
        let stick3 = (ptr+7).pointee
        
        let stickX = CGFloat(UInt16(stick1) | ((UInt16(stick2) & 0x0F) << 8))
        let stickY = CGFloat((UInt16(stick2) >> 4) | (UInt16(stick3) << 4))
        let sx = stickX - calib.midX
        let sy = stickY - calib.midY
        
        if sx < 0 {
            self.lStickRawPos.x = sx / calib.minXDiff
        } else {
            self.lStickRawPos.x = sx / calib.maxXDiff
        }
        
        if sy < 0 {
            self.lStickRawPos.y = sy / calib.minYDiff
        } else {
            self.lStickRawPos.y = sy / calib.maxYDiff
        }
        
        // TODO: Calibration
        let length = self.lStickRawPos.x * self.lStickRawPos.x + self.lStickRawPos.y * self.lStickRawPos.y
        let r = calib.deadZone / calib.maxXDiff
        let dLength = r * r
        
        if length < dLength {
            self.lStickPos.x = 0
            self.lStickPos.y = 0
        } else {
            // TODO: Use rangeRatio
            self.lStickPos.x = self.lStickRawPos.x
            self.lStickPos.y = self.lStickRawPos.y
        }
        
        self.leftStickPosHandler?(self.lStickPos)
    }
    
    func readRStickData(value: IOHIDValue) {
        guard let calib = self.rStickCalibration else { return }
        
        let ptr = IOHIDValueGetBytePtr(value)
        let stick1 = (ptr+8).pointee
        let stick2 = (ptr+9).pointee
        let stick3 = (ptr+10).pointee
        
        let stickX = CGFloat(UInt16(stick1) | ((UInt16(stick2) & 0x0F) << 8))
        let stickY = CGFloat((UInt16(stick2) >> 4) | (UInt16(stick3) << 4))
        let sx = stickX - calib.midX
        let sy = stickY - calib.midY
        
        if sx < 0 {
            self.rStickRawPos.x = sx / calib.minXDiff
        } else {
            self.rStickRawPos.x = sx / calib.maxXDiff
        }
        
        if sy < 0 {
            self.rStickRawPos.y = sy / calib.minYDiff
        } else {
            self.rStickRawPos.y = sy / calib.maxYDiff
        }
        
        // TODO: Calibration
        let length = self.rStickRawPos.x * self.rStickRawPos.x + self.rStickRawPos.y * self.rStickRawPos.y
        let r = calib.deadZone / calib.maxXDiff
        let dLength = r * r
        
        if length < dLength {
            self.rStickPos.x = 0
            self.rStickPos.y = 0
        } else {
            // TODO: Use rangeRatio
            self.rStickPos.x = self.rStickRawPos.x
            self.rStickPos.y = self.rStickRawPos.y
        }
        
        self.rightStickPosHandler?(self.rStickPos)
    }
    
    public func readControllerColor() {
        self.readSPIFlash(address: 0x601B, length: 0x01) { [weak self] data in
            if data[0] == 1 {
                self?.readControllerColorData()
            } else {
                // Default color
                self?.bodyColor = CGColor(red: 0.333, green: 0.333, blue: 0.333, alpha: 0.333)
                self?.buttonColor = CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            }
        }
    }
    
    func readControllerColorData() {
        self.readSPIFlash(address: 0x6050, length: 12) { [weak self] data in
            self?.setControllerColorData(data)
        }
    }
    
    func setControllerColorData(_ data: [UInt8]) {
        guard data.count >= 6 else { return }
        self.bodyColor = CGColor(red: CGFloat(data[0]) / 255.0, green: CGFloat(data[1]) / 255.0, blue: CGFloat(data[2]) / 255.0, alpha: 1.0)
        self.buttonColor = CGColor(red: CGFloat(data[3]) / 255.0, green: CGFloat(data[4]) / 255.0, blue: CGFloat(data[5]) / 255.0, alpha: 1.0)
        
        if self.type == .ProController {
            guard data.count >= 12 else { return }
            self.leftGripColor = CGColor(red: CGFloat(data[6]) / 255.0, green: CGFloat(data[7]) / 255.0, blue: CGFloat(data[8]) / 255.0, alpha: 1.0)
            self.rightGripColor = CGColor(red: CGFloat(data[9]) / 255.0, green: CGFloat(data[10]) / 255.0, blue: CGFloat(data[11]) / 255.0, alpha: 1.0)
        }
    }
    
    func cleanUp() {}
}
