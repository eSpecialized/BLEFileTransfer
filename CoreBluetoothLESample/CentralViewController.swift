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

    @IBOutlet var logView: UITextView!
    @IBOutlet var textView: UITextView!
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var progressView: UIProgressView!

    var expectedBytes = 0
    var fileName = ""

    var centralManager: CBCentralManager!

    var discoveredPeripheral: CBPeripheral?
    var transferCharacteristic: CBCharacteristic?
    var writeIterationsComplete = 0
    var connectionIterationsComplete = 0
    
    let defaultIterations = 5     // change this value based on test usecase

    var imageController: ImageDisplayViewController!
    
    var data = Data()

    // MARK: - view lifecycle
    
    override func viewDidLoad() {
        centralManager = CBCentralManager(delegate: self, queue: .global(qos: .userInitiated), options: [CBCentralManagerOptionShowPowerAlertKey: true])
        super.viewDidLoad()
        logView.text = "starting up\n"
    }
	
    override func viewWillDisappear(_ animated: Bool) {
        // Don't keep it going while we're not showing.
        centralManager.stopScan()
        logit("Scanning stopped")

        data.removeAll(keepingCapacity: false)
        
        super.viewWillDisappear(animated)
    }

    // MARK: - Helper Methods

    private func logit(_ logEntry: String) {
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }

            let oldText = strongSelf.logView.text ?? ""
            strongSelf.logView.text = oldText + logEntry + "\n"

            //scroll to the bottom of the view
            let bottom = NSMakeRange(strongSelf.logView.text.count - 1, 1)
            strongSelf.logView.scrollRangeToVisible(bottom)
        }
    }

    /*
     * We will first check if we are already connected to our counterpart
     * Otherwise, scan for peripherals - specifically for our service's 128bit CBUUID
     */
    private func retrievePeripheral() {
        
        let connectedPeripherals: [CBPeripheral] = (centralManager.retrieveConnectedPeripherals(withServices: [TransferService.serviceUUID]))
        
        logit("Found connected Peripherals with transfer service: \(connectedPeripherals)")
        
        if let connectedPeripheral = connectedPeripherals.last {
            logit("Connecting to peripheral \(connectedPeripheral)")
			self.discoveredPeripheral = connectedPeripheral
            centralManager.connect(connectedPeripheral, options: nil)
        } else {
            // We were not connected to our counterpart, so start scanning
            centralManager.scanForPeripherals(withServices: [TransferService.serviceUUID],
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
        guard let discoveredPeripheral = discoveredPeripheral,
            case .connected = discoveredPeripheral.state else { return }
        
        for service in (discoveredPeripheral.services ?? [] as [CBService]) {
            for characteristic in (service.characteristics ?? [] as [CBCharacteristic]) {
                if characteristic.uuid == TransferService.characteristicUUID && characteristic.isNotifying {
                    // It is notifying, so unsubscribe
                    self.discoveredPeripheral?.setNotifyValue(false, for: characteristic)
                }
            }
        }
        
        // If we've gotten this far, we're connected, but we're not subscribed, so we just disconnect
        centralManager.cancelPeripheralConnection(discoveredPeripheral)
    }
    
    /*
     *  Write some test data to peripheral
     */
    private func writeData() {
    
        guard let discoveredPeripheral = discoveredPeripheral,
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
                logit("Discovered perhiperal not in expected range, at \(RSSI.intValue)")
                return
        }
        
        logit("Discovered \(String(describing: peripheral.name)) at \(RSSI.intValue)")
        
        // Device is in range - have we already seen it?
        if discoveredPeripheral != peripheral {
            
            // Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it.
            discoveredPeripheral = peripheral
            
            // And finally, connect to the peripheral.
            logit("Connecting to perhiperal \(peripheral)")
            centralManager.connect(peripheral, options: nil)
        }
    }

    /*
     *  If the connection fails for whatever reason, we need to deal with it.
     */
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logit("Failed to connect to \(peripheral). String(describing: error)")
        cleanup()
    }
    
    /*
     *  We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
     */
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logit("Peripheral Connected")
        
        // Stop scanning
        centralManager.stopScan()
        logit("Scanning stopped")
        
        // set iteration info
        connectionIterationsComplete += 1
        writeIterationsComplete = 0
        
        // Clear the data that we may already have
        data.removeAll(keepingCapacity: false)
        
        // Make sure we get the discovery callbacks
        peripheral.delegate = self
        
        // Search only for services that match our UUID
        peripheral.discoverServices([TransferService.serviceUUID])
    }
    
    /*
     *  Once the disconnection happens, we need to clean up our local copy of the peripheral
     */
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logit("Perhiperal Disconnected")
        discoveredPeripheral = nil
        
        // We're disconnected, so start scanning again
        if connectionIterationsComplete < defaultIterations {
            retrievePeripheral()
        } else {
            logit("Connection iterations completed")
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let destination = segue.destination as? ImageDisplayViewController {
            destination.image = imageView.image
            imageController = destination
        }
    }
}

extension CentralViewController: CBPeripheralDelegate {
    // implementations of the CBPeripheralDelegate methods

    /*
     *  The peripheral letting us know when services have been invalidated.
     */
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        
        for service in invalidatedServices where service.uuid == TransferService.serviceUUID {
            logit("Transfer service is invalidated - rediscover services")
            peripheral.discoverServices([TransferService.serviceUUID])
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
            peripheral.discoverCharacteristics([TransferService.characteristicUUID], for: service)
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
        for characteristic in serviceCharacteristics where characteristic.uuid == TransferService.characteristicUUID {
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
        
        guard let characteristicData = characteristic.value else { return }

        let stringFromData = String(data: characteristicData, encoding: .utf8) ?? ""

        if fileName.isEmpty {
            logit("Received \(characteristicData.count) bytes: \(stringFromData)")
        }

        if stringFromData.hasPrefix("====") {
            print("captureHeader")
            captureHeader(from: characteristicData)
        }
        // Have we received the end-of-message token?
        else if stringFromData == "EOM" {
            print("EOM received")
            // End-of-message case: show the data.
            // Dispatch the text view update to the main queue for updating the UI, because
            // we don't know which thread this method will be called back on.
            DispatchQueue.main.async() {
                self.processData()
            }
            
            // Write test data, only if we were not capturing a file. IE don't send the same info back to the sender.
            if fileName.isEmpty {
                writeData()
            }
        } else {
            print(".")
            // Otherwise, just append the data to what we have previously received.
            data.append(characteristicData)

            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }

                let percentage = Float(strongSelf.data.count) / Float(strongSelf.expectedBytes)
                strongSelf.progressView.progress = percentage
            }
        }
    }

    /*
     *  The peripheral letting us know whether our subscribe/unsubscribe happened or not
     */
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        // Deal with errors (if any)
        if let error = error {
            logit("Error changing notification state: \(error.localizedDescription)")
            return
        }
        
        // Exit if it's not the transfer characteristic
        guard characteristic.uuid == TransferService.characteristicUUID else { return }
        
        if characteristic.isNotifying {
            // Notification has started
            logit("Notification began on \(characteristic)")
        } else {
            // Notification has stopped, so disconnect from the peripheral
            logit("Notification stopped on \(characteristic). Disconnecting")
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

    func processData() {
        if !fileName.isEmpty {
            let image = UIImage(data: data)
            logit("Image info captured \(image.debugDescription)")

            //show the image if able to.
            if imageView != nil {
                imageView.isHidden = false
                imageView.image = image

                if imageController == nil {
                    performSegue(withIdentifier: "showImageView", sender: self)
                } else {
                    imageController.imageView.image = image
                }
            }

            //reset for next set of data etc.
            data = Data()
            fileName = ""
        } else {
            //just display the string
            self.textView.text = String(data: self.data, encoding: .utf8)
        }
    }

    func captureHeader(from receivedData: Data) {
        guard let firstString = String(data: receivedData, encoding: .utf8) else { return }

        guard firstString.hasPrefix("====") else { return }

        if firstString.contains("|") {
            // I realize I could split this on commas. But lets use regex anyway.
            let filteredString = firstString.replacingOccurrences(of: "|", with: ",")

            do {
                let regularExpression = try NSRegularExpression(pattern: ",(.+),(.+),", options: .allowCommentsAndWhitespace)
                if
                    let result = regularExpression.firstMatch(in: filteredString, options: [], range: NSRange(location: 0, length: filteredString.count)),
                    result.numberOfRanges > 1
                {
                    let capture = result.range(at: 1)
                    let startIndex = filteredString.index(filteredString.startIndex, offsetBy: capture.location)
                    let endIndex = filteredString.index(filteredString.startIndex, offsetBy: capture.upperBound)
                    fileName = String(filteredString[startIndex..<endIndex])
                    logit("Captured [\(fileName)]")

                    let capturedSize = result.range(at: 2)
                    let startIndex2 = filteredString.index(filteredString.startIndex, offsetBy: capturedSize.location)
                    let endIndex2 = filteredString.index(filteredString.startIndex, offsetBy: capturedSize.upperBound)
                    let newString2 = String(filteredString[startIndex2..<endIndex2])
                    expectedBytes = Int(newString2) ?? 0
                    logit("[\(expectedBytes) bytes expected]")

                    DispatchQueue.main.async { [weak self] in
                        self?.progressView.isHidden = false
                    }
                }

            } catch {
                print(error)
            }
        }
    }
}
