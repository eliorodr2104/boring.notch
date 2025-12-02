//
//  BluetoothManager.swift
//  boringNotch
//
//  Created by Eliomar Alejandro Rodriguez Ferrer on 02/12/25.
//

import Foundation
import Combine
import CoreAudio
import IOBluetooth

struct ConnectedHeadphone: Equatable {
    let name        : String
    let batteryLevel: Int?
    let isApple     : Bool
    
    var icon: String {
        let nameLower = name.lowercased()
        
        if nameLower.contains("airpods max") { return "airpodsmax" }
        if nameLower.contains("pro")         { return "airpodspro" }
        if nameLower.contains("airpods")     { return "airpods" }
        
        return "headphones"
    }
    
}

class BluetoothManager: ObservableObject {
    static let shared = BluetoothManager()
    
    @Published var currentHeadphone: ConnectedHeadphone? = nil
    @Published var isHeadphoneConnected: Bool = false
    
    private var lastDeviceID: AudioObjectID = kAudioObjectUnknown
    
    private init() {
        // Avvia il monitoraggio all'avvio
        startMonitoringAudioHardware()
    }
    
    // MARK: - CoreAudio Monitoring
    
    private func startMonitoringAudioHardware() {
        // Ascolta il cambio del dispositivo di output predefinito
        var defaultDevAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDevAddr,
            nil
        ) { [weak self] _, _ in
            self?.checkCurrentOutputDevice()
        }
        
        // Controllo iniziale
        checkCurrentOutputDevice()
    }
    
    private func checkCurrentOutputDevice() {
        
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
                
            let currentDeviceID = self.systemOutputDeviceID()
            self.lastDeviceID = currentDeviceID
                
            // 1. Controllo Transport Type
            guard self.isBluetoothDevice(deviceID: currentDeviceID) else {
                Task { @MainActor in
                    if self.currentHeadphone != nil {
                        self.currentHeadphone = nil
                        self.isHeadphoneConnected = false
                        print("Disconnected")
                    }
                }
                return
            }
                
            // 2. Nome
            let deviceName = self.getAudioDeviceName(deviceID: currentDeviceID) ?? "Bluetooth Audio"
                
            // 3. Batteria (Ora questa chiamata pesante avviene in .utility e non blocca)
            let battery = self.fetchBatteryLevel(deviceName: deviceName)
            
            let newHeadphone = ConnectedHeadphone(
                name: deviceName,
                batteryLevel: battery,
                isApple: deviceName.lowercased().contains("airpods") || deviceName.lowercased().contains("beats")
            )
                
            // 4. Aggiornamento UI
            Task { @MainActor in
                if self.currentHeadphone != newHeadphone {
                    self.currentHeadphone = newHeadphone
                    self.isHeadphoneConnected = true
                        
                    print("Connected Bluetooth device: \(deviceName) - Battery: \(battery ?? -1)%")
                        
                    BoringViewCoordinator.shared.toggleSneakPeek(
                        type: .headphones,
                        show: true
                    )
                }
            }
        }
    }
    
    // MARK: - IOBluetooth Helpers (Battery)
    
    private func fetchBatteryLevel(deviceName: String) -> Int? {
        // Ottieni tutti i dispositivi accoppiati
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return nil }
        
        // Cerchiamo il device che è CONNESSO e ha un nome simile
        if let targetDevice = devices.first(where: { device in
            return device.isConnected() && (device.name == deviceName || deviceName.contains(device.name))
        }) {
            
            if let level = targetDevice.value(forKey: "batteryPercentSingle") as? Int {
                return level
            }
                    
            if let level = targetDevice.value(forKey: "batteryPercentCombined") as? Int {
                return level
            }
                    
            if let level = targetDevice.value(forKey: "batteryLevel") as? Int {
                return level
            }
        }
        
        return nil
    }
    
    // MARK: - CoreAudio Low Level Helpers
    
    private func systemOutputDeviceID() -> AudioObjectID {
        var deviceID = kAudioObjectUnknown
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID)
        return deviceID
    }
    
    private func isBluetoothDevice(deviceID: AudioObjectID) -> Bool {
        var transportType: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<UInt32>.size)
        
        guard AudioObjectHasProperty(deviceID, &addr) else { return false }
        AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &transportType)
        
        return transportType == kAudioDeviceTransportTypeBluetooth ||
               transportType == kAudioDeviceTransportTypeBluetoothLE
    }
    
    private func getAudioDeviceName(deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var nameRef: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        
        let status = withUnsafeMutablePointer(to: &nameRef) { namePtr in
            
            return AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                UnsafeMutableRawPointer(namePtr)
            )
        }
        
        if status == noErr, let result = nameRef {
            return result as String
        }
        
        return nil
    }
}
