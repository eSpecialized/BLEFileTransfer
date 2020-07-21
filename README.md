# About

This Repo was converted from Apples "Transferring Data Between Bluetooth Low Energy Devices" Applet, and extended to work for Apple TV as a Central.


# References and Links

[URL To Original Project](https://developer.apple.com/documentation/corebluetooth/transferring_data_between_bluetooth_low_energy_devices)


# Changes to original code

* Added second textView on each screen allowing logging to show up on the AppleTV or iPhone.
* Peripheral doesn't allow instantiating "init()" called on peripheral methods on tvOS, as such I wrapped them under `#if os(tvOS)`
* Apples Original README.md renamed to APPREADME.md to maintain the files.
* PeripheralViewController heavily modified with #if os(tvOS).

