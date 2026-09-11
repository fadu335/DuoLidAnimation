import Foundation
import IOKit.hid
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, ["VendorID":1452,"DeviceUsagePage":32,"DeviceUsage":138] as CFDictionary)
let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
print("Matching sensors: \(devices.count)")
for device in devices {
 let status = IOHIDDeviceOpen(device, 0)
 print(String(format:"Open: 0x%08x", status))
 guard status == kIOReturnSuccess else { continue }
 for _ in 0..<5 {
  for type in [kIOHIDReportTypeFeature, kIOHIDReportTypeInput] {
   var bytes = [UInt8](repeating:0,count:16)
   var length = bytes.count
   let result = IOHIDDeviceGetReport(device,type,1,&bytes,&length)
   print(String(format:"type=%d status=0x%08x", type.rawValue,result),"length=\(length) bytes=\(bytes.prefix(length))")
   if result == kIOReturnSuccess && length >= 3 { print("Lid angle: \(Double(UInt16(bytes[1]) | UInt16(bytes[2]) << 8))°") }
  }
  Thread.sleep(forTimeInterval:0.1)
 }
 IOHIDDeviceClose(device,0)
}
