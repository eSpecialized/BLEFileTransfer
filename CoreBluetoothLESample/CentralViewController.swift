/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A class to discover, connect, receive notifications and write data to peripherals by using a transfer service and characteristic.
*/

import UIKit
import CoreBluetooth
import os

class CentralViewController: UIViewController {
    // UIViewController overrides, properties specific to this class, private helper methods, etc.

    //https://www.bluetooth.com/specifications/gatt/characteristics/
    //SPS named device is the INKBird sensor. but making heads or tails of the data there is difficult.
    let temperatureDeviceCharacteristics = [
        CBUUID(string: "0x2A1E"),
        CBUUID(string: "0x2A3C"),
        CBUUID(string: "0x2A6E"),
        CBUUID(string: "0x2A1F"),
        CBUUID(string: "0x2A20"),
        CBUUID(string: "0x2A1C"),
        CBUUID(string: "0x2A1D")
    ]

    @IBOutlet var logView: UITextView!
    @IBOutlet var textView: UITextView!

    var centralManager: CBCentralManager!

    var discoveredOutOfRangePeripherals = [CBPeripheral]()
    var discoveredPeripherals = [CBPeripheral]()
    var transferCharacteristic: CBCharacteristic?
    var writeIterationsComplete = 0
    var connectionIterationsComplete = 0

    var connectedPeripheral: CBPeripheral?
    
    let defaultIterations = 5     // change this value based on test usecase
    
    var data = Data()

    // MARK: - view lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        logView.text = "starting up\n"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Stop Scan", style: .plain, target: self, action: #selector(stopScanning))
    }

    override func viewWillDisappear(_ animated: Bool) {
        // Don't keep it going while we're not showing.
        centralManager.stopScan()
        logit("Scanning stopped")

        data.removeAll(keepingCapacity: false)
        
        super.viewWillDisappear(animated)
    }

    // MARK: - Helper Methods

    @objc
    func stopScanning() {
        centralManager.stopScan()
    }

    private func logit(_ logEntry: String) {
        let oldText = logView.text ?? ""
        logView.text = oldText + logEntry + "\n"

        //scroll to the bottom of the view
        let bottom = NSMakeRange(logView.text.count - 1, 1)
        logView.scrollRangeToVisible(bottom)

        os_log("%s", logEntry)
    }

    /*
     * We will first check if we are already connected to our counterpart
     * Otherwise, scan for peripherals - specifically for our service's 128bit CBUUID
     */
    private func retrievePeripheral() {
        
        let connectedPeripherals: [CBPeripheral] = (centralManager.retrieveConnectedPeripherals(withServices: [])) //TransferService.serviceUUID
        
        logit("Found connected Peripherals with service: \(connectedPeripherals)")
        
        if let peripheral = connectedPeripherals.last {
            logit("Connecting to peripheral \(peripheral)")
            self.discoveredPeripherals.append(peripheral)
            centralManager.connect(peripheral, options: nil)
        } else {
            // We were not connected to our counterpart, so start scanning
            centralManager.scanForPeripherals(withServices: [], //TransferService.serviceUUID
                                               options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }
    
    /*
     *  Call this when things either go wrong, or you're done with the connection.
     *  This cancels any subscriptions if there are any, or straight disconnects if not.
     *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
     */
    private func cleanup() {
        // Don't do anything if we're not connected
        guard !discoveredPeripherals.isEmpty else { return }

        for peripheral in discoveredPeripherals {
            for service in (peripheral.services ?? [] as [CBService]) {
                for characteristic in (service.characteristics ?? [] as [CBCharacteristic]) {

                    if temperatureDeviceCharacteristics.contains(characteristic.uuid) {
                        os_log("Found temperature charactistic on %@", peripheral)
                    }

                    //if characteristic.uuid == TransferService.characteristicUUID && characteristic.isNotifying {
                        // It is notifying, so unsubscribe
                        peripheral.setNotifyValue(false, for: characteristic)
                    //}
                }
            }

            // If we've gotten this far, we're connected, but we're not subscribed, so we just disconnect
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    /*
     *  Write some test data to peripheral
     */
    private func writeData() {
    
        guard let discoveredPeripheral = connectedPeripheral,
                let transferCharacteristic = transferCharacteristic
            else { return }
        
        // check to see if number of iterations completed and peripheral can accept more data
        while writeIterationsComplete < defaultIterations && discoveredPeripheral.canSendWriteWithoutResponse {
                    
            let mtu = discoveredPeripheral.maximumWriteValueLength (for: .withoutResponse)
            var rawPacket = [UInt8]()
            
            let bytesToCopy: size_t = min(mtu, data.count)
			data.copyBytes(to: &rawPacket, count: bytesToCopy)
            let packetData = Data(bytes: &rawPacket, count: bytesToCopy)
			
			let stringFromData = String(data: packetData, encoding: .utf8)
			logit("Writing \(bytesToCopy) bytes: \(String(describing: stringFromData))")
			
            discoveredPeripheral.writeValue(packetData, for: transferCharacteristic, type: .withoutResponse)
            
            writeIterationsComplete += 1
            
        }
        
        if writeIterationsComplete == defaultIterations {
            // Cancel our subscription to the characteristic
            discoveredPeripheral.setNotifyValue(false, for: transferCharacteristic)
        }
    }
    
}

extension CentralViewController: CBCentralManagerDelegate {
    // implementations of the CBCentralManagerDelegate methods

    /*
     *  centralManagerDidUpdateState is a required protocol method.
     *  Usually, you'd check for other states to make sure the current device supports LE, is powered on, etc.
     *  In this instance, we're just using it to wait for CBCentralManagerStatePoweredOn, which indicates
     *  the Central is ready to be used.
     */
    internal func centralManagerDidUpdateState(_ central: CBCentralManager) {

        switch central.state {
        case .poweredOn:
            // ... so start working with the peripheral
            logit("CBManager is powered on")
            retrievePeripheral()
        case .poweredOff:
            logit("CBManager is not powered on")
            // In a real app, you'd deal with all the states accordingly
            return
        case .resetting:
            logit("CBManager is resetting")
            // In a real app, you'd deal with all the states accordingly
            return
        case .unauthorized:
            // In a real app, you'd deal with all the states accordingly
            if #available(iOS 13.0, *) {
                switch central.authorization {
                case .denied:
                    logit("You are not authorized to use Bluetooth")
                case .restricted:
                    logit("Bluetooth is restricted")
                default:
                    logit("Unexpected authorization")
                }
            } else {
                // Fallback on earlier versions
            }
            return
        case .unknown:
            logit("CBManager state is unknown")
            // In a real app, you'd deal with all the states accordingly
            return
        case .unsupported:
            logit("Bluetooth is not supported on this device")
            // In a real app, you'd deal with all the states accordingly
            return
        @unknown default:
            logit("A previously unknown central manager state occurred")
            // In a real app, you'd deal with yet unknown cases that might occur in the future
            return
        }
    }

    /*
     *  This callback comes whenever a peripheral that is advertising the transfer serviceUUID is discovered.
     *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
     *  we start the connection process
     */
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        
        // Reject if the signal strength is too low to attempt data transfer.
        // Change the minimum RSSI value depending on your app’s use case.
        guard RSSI.intValue >= -50
            else {
                if !discoveredOutOfRangePeripherals.contains(peripheral) {
                    discoveredOutOfRangePeripherals.append(peripheral)
                    logit("Discovered \(peripheral.name ?? peripheral.identifier.uuidString)) not in expected range, at \(RSSI.intValue)")
                }

                return
        }

        discoveredOutOfRangePeripherals.removeAll(where: { $0 == peripheral })

        // Device is in range - have we already seen it?
        if !discoveredPeripherals.contains(peripheral) {
            logit("Discovered \(String(describing: peripheral.name ?? peripheral.identifier.uuidString)) at \(RSSI.intValue)")
            
            // Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it.
            discoveredPeripherals.append(peripheral)
            
            // And finally, connect to the peripheral.
            logit(" + Connecting to perhiperal \(peripheral.name ?? peripheral.identifier.uuidString)")
            centralManager.connect(peripheral, options: nil)
        }
    }

    /*
     *  If the connection fails for whatever reason, we need to deal with it.
     */
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logit("Failed to connect to \(peripheral.name ?? peripheral.identifier.uuidString). \(String(describing: error))")
        cleanup()
    }
    
    /*
     *  We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
     */
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logit("\(peripheral.name ?? peripheral.identifier.uuidString) Peripheral Connected")
        
        // Stop scanning
        //centralManager.stopScan()
        //logit("Scanning stopped")
        
        // set iteration info
        connectionIterationsComplete += 1
        writeIterationsComplete = 0
        
        // Clear the data that we may already have
        data.removeAll(keepingCapacity: false)
        
        // Make sure we get the discovery callbacks
        peripheral.delegate = self
        
        // Search only for services that match our UUID
        peripheral.discoverServices([]) //TransferService.serviceUUID
    }
    
    /*
     *  Once the disconnection happens, we need to clean up our local copy of the peripheral
     */
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logit("\(peripheral.name ?? peripheral.identifier.uuidString) Perhiperal Disconnected")
        connectedPeripheral = nil
        
        // We're disconnected, so start scanning again
        if connectionIterationsComplete < defaultIterations {
            retrievePeripheral()
        } else {
            logit("Connection iterations completed")
        }
    }

}

extension CentralViewController: CBPeripheralDelegate {
    // implementations of the CBPeripheralDelegate methods

    /*
     *  The peripheral letting us know when services have been invalidated.
     */
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        
        for service in invalidatedServices { // where service.uuid == TransferService.serviceUUID
            logit("\(service.debugDescription) service is invalidated - rediscover services")
            peripheral.discoverServices([]) //TransferService.serviceUUID
        }
    }

    /*
     *  The Transfer Service was discovered
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            logit("Error discovering services:  \(error.localizedDescription)")
            cleanup()
            return
        }
        
        // Discover the characteristic we want...
        
        // Loop through the newly filled peripheral.services array, just in case there's more than one.
        guard let peripheralServices = peripheral.services else { return }
        for service in peripheralServices {
            peripheral.discoverCharacteristics([], for: service) //TransferService.characteristicUUID
        }
    }
    
    /*
     *  The Transfer characteristic was discovered.
     *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
     */
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        // Deal with errors (if any).
        if let error = error {
            logit("Error discovering characteristics: \(error.localizedDescription)")
            cleanup()
            return
        }
        
        // Again, we loop through the array, just in case and check if it's the right one
        guard let serviceCharacteristics = service.characteristics else { return }
        for characteristic in serviceCharacteristics { // where characteristic.uuid == TransferService.characteristicUUID
            // If it is, subscribe to it
            transferCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
        
        // Once this is complete, we just need to wait for the data to come in.
    }
    
    /*
     *   This callback lets us know more data has arrived via notification on the characteristic
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Deal with errors (if any)
        if let error = error {
            logit("Error discovering characteristics: \(error.localizedDescription)")
            cleanup()
            return
        }
        
        guard let characteristicData = characteristic.value,
            let stringFromData = String(data: characteristicData, encoding: .utf8) else { return }
        
        logit("Received \(characteristicData.count) bytes: \(stringFromData)")
        
        // Have we received the end-of-message token?
        if stringFromData == "EOM" {
            // End-of-message case: show the data.
            // Dispatch the text view update to the main queue for updating the UI, because
            // we don't know which thread this method will be called back on.
            DispatchQueue.main.async() {
                self.textView.text = String(data: self.data, encoding: .utf8)
            }
            
            // Write test data
            writeData()
        } else {
            // Otherwise, just append the data to what we have previously received.
            data.append(characteristicData)
        }
    }

    /*
     *  The peripheral letting us know whether our subscribe/unsubscribe happened or not
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        // Deal with errors (if any)
        if let error = error {
            logit("\(peripheral.name ?? peripheral.identifier.uuidString) Error changing notification state: \(error.localizedDescription)")
            return
        }
        
        // Exit if it's not the transfer characteristic
        //guard characteristic.uuid == TransferService.characteristicUUID else { return }
        
        if characteristic.isNotifying {
            // Notification has started
            logit("\(peripheral.name ?? peripheral.identifier.uuidString) Notification began on \(characteristic.uuid.uuidString)")
        } else {
            // Notification has stopped, so disconnect from the peripheral
            logit("\(peripheral.name ?? peripheral.identifier.uuidString) Notification stopped on \(characteristic.uuid.uuidString). Disconnecting")
            cleanup()
        }
        
    }
    
    /*
     *  This is called when peripheral is ready to accept more data when using write without response
     */
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        logit("Peripheral is ready, send data")
        writeData()
    }
    
}
