import Foundation
import CoreLocation
// Limit use of Contacts framework
import class Contacts.CNPostalAddressFormatter

@objc(Locations)
class Locations: NSObject {
  
  @objc
  static func requiresMainQueueSetup() -> Bool {
    return true
  }

  struct AddressTS {
    let name: String
    let address: String
    /// Expect in milliseconds
    let timestamp: Double
    
    static let invalid = AddressTS(name: "", address: "", timestamp: 0)
  }
  
  struct AddressPeriod {
    let name: String
    let address: String
    let start: Double
    let end: Double
  }
  
  @objc
  func reverseGeoCode(_ geoList: [NSDictionary], callback: @escaping RCTResponseSenderBlock) {
    // Fire an asynchronous callback when all your requests finish in synchronous.
    let asyncGroup = DispatchGroup()
    // List of AddressTS
    var placeList = [AddressTS](repeating: .invalid, count: geoList.count)
    for (index, geo) in geoList.enumerated() {
      let lat = geo.value(forKey: "latitude") as! Double
      let lon = geo.value(forKey: "longitude") as! Double
      let timestamp = geo.value(forKey: "time") as! Double
      
      asyncGroup.enter()
      // Reverse Geocoding With CLGeocoder
      let gecoder = CLGeocoder()
      
      gecoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon)) { (addresses, error) in
        if error == nil, let address = addresses?.first {
          // Async: Here you can get all the info by combining that you can make address!
          var addressString = ""
          if #available(iOS 11.0, *) {
            addressString = CNPostalAddressFormatter
              .string(from: address.postalAddress!, style: .mailingAddress)
              .replacingOccurrences(of: "\n", with: ", ")
          } else {
            if let lines = address.addressDictionary?["FormattedAddressLines"] as? [String] {
              addressString = lines.joined(separator: ", ")
            }
          }
          
          // async - sequential reserved - fixed size
          placeList[index] = AddressTS(
            name: address.name ?? "",
            address: addressString,
            timestamp: timestamp
          )
          asyncGroup.leave()
        }
      }
    }
    
    asyncGroup.notify(queue: .main) {
      print("Finished the loop - find \(geoList.count) addresses")
      let results = self.aggregateAddressList(addressTSList: placeList)
      callback([results])
    }
  }
  
  //---------------------------------------------------------------------------------
  // MARK: - Step2: aggregate address result - from timestamp to period
  //---------------------------------------------------------------------------------
  func aggregateAddressList(addressTSList: [AddressTS]) -> [[String]] {
    guard let first = addressTSList.first else { return [] }
    
    var AddressPeriodList: [AddressPeriod] = []  // List of AddressPeriod
    var start: Double = first.timestamp // UTC start
    var end: Double = first.timestamp // UTC end
    var previous = first // address pointer
    
    let TEN_MINUTES_IN_MS: Double = 10 * 60 * 1000
    
    /// Add an adress and the stay interval to adress list. If end time is same as start time, +10 minutes.
    func appendAddress(_ address: AddressTS) {
      AddressPeriodList.append(AddressPeriod(
        name: address.name, address: address.address, start: start,
        end: start == end ? start + TEN_MINUTES_IN_MS : end
      ))
    }
    
    for address_ts in addressTSList.dropFirst() {
      if address_ts.address != previous.address {
        appendAddress(previous)
        // update to current location
        start = address_ts.timestamp
        end = address_ts.timestamp
        previous = address_ts
      } else { // same location, update end time
        end = address_ts.timestamp
      }
    }
    appendAddress(previous)

    return condensed(AddressPeriodList)
  }
  
  func condensed(_ AddressPeriodList: [AddressPeriod]) -> [[String]] {
    return Dictionary(grouping: AddressPeriodList, by: { $0.address })
      .map { (address, info) -> (end: Double, [String]) in
        // Sort all periods of stay at same location
        let sorted = info.sorted { $0.end < $1.end }
        // Get the latest time stayed
        let end = sorted.last!.end
        // Join all the periods together with format start - end[, start - end]
        let period = sorted
          .map { "\(format($0.start)) - \(format($0.end))" }
          .joined(separator: ", ")
        return (end: end, [info[0].name, address, period])
    } .sorted { $0.end > $1.end } // sort all location by last time present
      .map { $0.1 }
  }
  
  func format(_ double: Double) -> String {
    return NumberFormatter.noDecimal
      .string(from: double as NSNumber) ?? "\(double)"
  }
}

extension NumberFormatter {
  static let noDecimal: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.maximumFractionDigits = 0
    return formatter
  }()
}
