/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A class to advertise, send notifications and receive data from central looking for transfer service and characteristic.
*/

import UIKit
import CoreBluetooth
import os

class PeripheralViewController: UIViewController {

    let advertisingOnString = "advertising: ON"
    let advertisingOffString = "advertising: OFF"

    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet var logView: UITextView!
    @IBOutlet var textView: UITextView!

    @IBOutlet weak var imageView: UIImageView!

    #if os(tvOS)
    @IBOutlet var advertisingButton: UIButton!
    #else
    @IBOutlet var advertisingSwitch: UISwitch!
    #endif
    @IBOutlet weak var uploadButton: UIButton!

    var peripheralManager: CBPeripheralManager!

    var transferCharacteristic: CBMutableCharacteristic?
    var connectedCentral: CBCentral?
    var dataToSend = Data()
    var sendDataIndex: Int = 0
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        #if os(tvOS)
        peripheralManager = CBPeripheralManager()
        peripheralManager.delegate = self
        #else
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
        peripheralManager.delegate = self
        #endif

        super.viewDidLoad()

        #if os(tvOS)
        logView.text = "Not Supported on tvOS Yet\n"
        #else
        logView.text = "Starting up\n"
        progressView.isHidden = true
        #endif
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        // Don't keep advertising going while we're not showing.
        peripheralManager.stopAdvertising()

        super.viewWillDisappear(animated)
    }
    
    // MARK: - Switch Methods

    @IBAction func switchChanged(_ sender: Any) {
        // All we advertise is our service's UUID.
        #if !os(tvOS)
        if advertisingSwitch.isOn {
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [TransferService.serviceUUID]])
        } else {
            peripheralManager.stopAdvertising()
        }
        #endif
    }

    @IBAction func buttonTapped(_ sender: Any) {
        #if os(tvOS)
        if advertisingButton.titleLabel?.text == advertisingOffString {
            advertisingButton.titleLabel?.text = advertisingOnString
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [TransferService.serviceUUID]])
        } else {
            advertisingButton.titleLabel?.text = advertisingOffString
            peripheralManager.stopAdvertising()
        }
        #endif
    }


    @IBAction func showImagePicker(_ sender: Any) {
        #if !os(tvOS)
        if UIImagePickerController.isSourceTypeAvailable(UIImagePickerController.SourceType.photoLibrary) {
            let imagePickerController = UIImagePickerController()
            imagePickerController.delegate = self
            imagePickerController.mediaTypes = ["public.image"]
            imagePickerController.allowsEditing = true
            imagePickerController.sourceType = .photoLibrary

            navigationController?.present(imagePickerController, animated: true, completion: {
                self.logit("Showing Image Picker.")
            })
        }
        #endif
    }

    // MARK: - Helper Methods

    private func logit(_ logEntry: String) {
        let oldText = logView.text ?? ""
        logView.text = oldText + logEntry + "\n"
        
        //scroll to the bottom of the view
        let bottom = NSMakeRange(logView.text.count - 1, 1)
        logView.scrollRangeToVisible(bottom)

        print(logit)
    }

    /*
     *  Sends the next amount of data to the connected central
     */
    static var sendingEOM = false
    
    private func sendData() {
		
		guard let transferCharacteristic = transferCharacteristic else {
			return
		}
		
        // First up, check if we're meant to be sending an EOM
        if PeripheralViewController.sendingEOM {
            // send it
            let didSend = peripheralManager.updateValue("EOM".data(using: .utf8)!, for: transferCharacteristic, onSubscribedCentrals: nil)
            // Did it send?
            if didSend {
                // It did, so mark it as sent
                PeripheralViewController.sendingEOM = false
                logit("Sent: EOM")
            }
            // It didn't send, so we'll exit and wait for peripheralManagerIsReadyToUpdateSubscribers to call sendData again
            return
        }
        
        // We're not sending an EOM, so we're sending data
        // Is there any left to send?
        if sendDataIndex >= dataToSend.count {
            // No data left.  Do nothing
            return
        }
        
        // There's data left, so send until the callback fails, or we're done.
        var didSend = true

        while didSend {
            
            // Work out how big it should be
            var amountToSend = dataToSend.count - sendDataIndex
            if let mtu = connectedCentral?.maximumUpdateValueLength {
                amountToSend = min(amountToSend, mtu)
            }
            
            // Copy out the data we want
            let chunk = dataToSend.subdata(in: sendDataIndex..<(sendDataIndex + amountToSend))
            
            // Send it
            didSend = peripheralManager.updateValue(chunk, for: transferCharacteristic, onSubscribedCentrals: nil)
            
            // If it didn't work, drop out and wait for the callback
            if !didSend {
                return
            }
            
            //let stringFromData = String(data: chunk, encoding: .utf8)
            //logit("Sent \(chunk.count)")// bytes: \(String(describing: stringFromData))")
            //print("Sent \(chunk.count)")// bytes: \(String(describing: stringFromData))")
            let totalPercent = Float(sendDataIndex) / Float(dataToSend.count)
            progressView.progress = totalPercent

            // It did send, so update our index
            sendDataIndex += amountToSend
            // Was it the last one?
            if sendDataIndex >= dataToSend.count {
                // It was - send an EOM
                
                // Set this so if the send fails, we'll send it next time
                PeripheralViewController.sendingEOM = true
                
                //Send it
                let eomSent = peripheralManager.updateValue("EOM".data(using: .utf8)!,
                                                             for: transferCharacteristic, onSubscribedCentrals: nil)
                
                if eomSent {
                    // It sent; we're all done
                    PeripheralViewController.sendingEOM = false
                    logit("Sent: EOM")
                }

                logit("Sent \(dataToSend.count) bytes Completed")
                return
            }
        }
    }

    private func setupPeripheral() {
        // Build our service.
        // Start with the CBMutableCharacteristic.
        #if os(tvOS)
        //FIXME: Cannot call init on these two items.
        //let transferCharacteristic = CBMutableCharacteristic()

        // Create a service from the characteristic.
        //let transferService = CBMutableService()

        #else
        let transferCharacteristic = CBMutableCharacteristic(type: TransferService.characteristicUUID,
                                                         properties: [.notify, .writeWithoutResponse],
                                                         value: nil,
                                                         permissions: [.readable, .writeable])
        
        // Create a service from the characteristic.
        let transferService = CBMutableService(type: TransferService.serviceUUID, primary: true)

        // Add the characteristic to the service.
        transferService.characteristics = [transferCharacteristic]
        
        // And add it to the peripheral manager.
        peripheralManager.add(transferService)
        
        // Save the characteristic for later.
        self.transferCharacteristic = transferCharacteristic
        #endif

    }

    private func pickerDidSelect(image: UIImage?, fileName: String?) {
        textView.resignFirstResponder()
        logView.resignFirstResponder()

        guard
            let fileHandle = fileName,
            let imageHandle = image,
            let endData = "\n=============== END ============\n".data(using: .utf8),
            let imageData = imageHandle.jpegData(compressionQuality: 0.85),
            let fileData = "===============|\(fileHandle)|\(imageData.count)|============\n".data(using: .utf8)
        else {
            logit("User cancelled Image Picking")
            return
        }

        var mutableData = Data()

        mutableData.append(fileData)
        mutableData.append(imageData.base64EncodedData(options: [.endLineWithLineFeed, .lineLength76Characters]))
        mutableData.append(endData)

        dataToSend = mutableData
        logit("Send \(dataToSend.count) bytes, watch the progress bar for completion percentage")

        progressView.isHidden = false
        progressView.progress = 0
    }
}

extension PeripheralViewController: CBPeripheralManagerDelegate {
    // implementations of the CBPeripheralManagerDelegate methods

    /*
     *  Required protocol method.  A full app should take care of all the possible states,
     *  but we're just waiting for to know when the CBPeripheralManager is ready
     *
     *  Starting from iOS 13.0, if the state is CBManagerStateUnauthorized, you
     *  are also required to check for the authorization state of the peripheral to ensure that
     *  your app is allowed to use bluetooth
     */
    internal func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        #if os(tvOS)

        #else
        advertisingSwitch.isEnabled = peripheral.state == .poweredOn
        #endif

        switch peripheral.state {
        case .poweredOn:
            // ... so start working with the peripheral
            logit("CBManager is powered on")
            setupPeripheral()
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
                switch peripheral.authorization {
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
            logit("A previously unknown peripheral manager state occurred")
            // In a real app, you'd deal with yet unknown cases that might occur in the future
            return
        }
    }

    /*
     *  Catch when someone subscribes to our characteristic, then start sending them data
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        logit("Central subscribed to characteristic")
        
        // Get the data, only if an image hasn't been encoded to send.
        if dataToSend.isEmpty {
            dataToSend = textView.text.data(using: .utf8)!
        }
        
        // Reset the index
        sendDataIndex = 0
        
        // save central
        connectedCentral = central
        
        // Start sending
        sendData()
    }
    
    /*
     *  Recognize when the central unsubscribes
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        logit("Central unsubscribed from characteristic")
        connectedCentral = nil
    }
    
    /*
     *  This callback comes in when the PeripheralManager is ready to send the next chunk of data.
     *  This is to ensure that packets will arrive in the order they are sent
     */
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        // Start sending again
        sendData()
    }
    
    /*
     * This callback comes in when the PeripheralManager received write to characteristics
     */
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for aRequest in requests {
            guard let requestValue = aRequest.value,
                let stringFromData = String(data: requestValue, encoding: .utf8) else {
                    continue
            }
            
            logit("Received write request of \(requestValue.count) bytes: \(stringFromData)")
        }
    }
}

extension PeripheralViewController: UITextViewDelegate {
    // implementations of the UITextViewDelegate methods

    /*
     *  This is called when a change happens, so we know to stop advertising
     */
    func textViewDidChange(_ textView: UITextView) {
        // If we're already advertising, stop
        #if os(tvOS)
        if advertisingButton.titleLabel?.text == advertisingOnString {
            advertisingButton.titleLabel?.text = advertisingOffString
            peripheralManager.stopAdvertising()
        }
        #else
        if advertisingSwitch.isOn {
            advertisingSwitch.isOn = false
            peripheralManager.stopAdvertising()
        }
        #endif
    }
    
    /*
     *  Adds the 'Done' button to the title bar
     */
    func textViewDidBeginEditing(_ textView: UITextView) {
        // We need to add this manually so we have a way to dismiss the keyboard
        let rightButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(dismissKeyboard))
        navigationItem.rightBarButtonItem = rightButton
    }
    
    /*
     * Finishes the editing
     */
    @objc
    func dismissKeyboard() {
        textView.resignFirstResponder()
        navigationItem.rightBarButtonItem = nil
    }
}

#if !os(tvOS)
extension PeripheralViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        navigationController?.dismiss(animated: true, completion: nil)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        navigationController?.dismiss(animated: true, completion: nil)
        print(info)
        guard let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage, let fileURL = info[.imageURL] as? URL else {
            logit("Failed to retrieve an image")
            return
        }

        if imageView != nil {
            imageView.isHidden = false
            imageView.image = image
        }

        let fileName = fileURL.lastPathComponent
        pickerDidSelect(image: image, fileName: fileName)
    }
}
#endif
