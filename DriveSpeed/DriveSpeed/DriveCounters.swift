//
//  DriveCounters.swift
//  DriveSpeed
//
//  Reads cumulative per-device byte counters via IOKit (IOBlockStorageDriver).
//  Increment 1.1 — the disk-side replacement for NetSpeed's NetworkCounters.swift,
//  which was deleted in Increment 1.2 when SpeedSampler switched to this source.
//

import Foundation
import IOKit
import IOKit.storage

/// A single physical storage device's cumulative byte counters, as reported by
/// the OS, together with the bus it sits on.
///
/// `interconnect` is the raw `Physical Interconnect` string — "Apple Fabric",
/// "PCI-Express", "USB", and so on. Increment 1.3 turns it into the FR-10
/// internal + USB filter; 1.1 only proves we can read it.
///
/// `bsdName` and `productName` exist for the Increment 1.1 console snapshot and
/// nothing else. Per FR-10d the shipped sampler keeps no per-device identity, so
/// these must not acquire a second caller — they go away with the snapshot.
///
/// `nonisolated` explicitly: the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, so a bare declaration would be implicitly main-actor isolated.
/// Reading IOKit registry properties has nothing to do with the main actor, and
/// leaving the default in place makes `SpeedSampler`'s off-actor sampling helper
/// a concurrency warning.
nonisolated struct DriveCounter {
    let bsdName: String
    let productName: String
    let interconnect: String
    let bytesRead: UInt64
    let bytesWritten: UInt64
}

/// `nonisolated` for the same reason as `DriveCounter` above — this is a pure
/// measurement layer with no UI coupling, so it stays actor-agnostic.
nonisolated enum DriveCounters {

    /// Reads cumulative read/write byte counters for every physical storage
    /// device the system currently knows about.
    ///
    /// Matching on `IOBlockStorageDriver` is what pins this to the *physical*
    /// device layer: exactly one instance exists per whole disk, and APFS
    /// synthesized containers have none at all, so there is nothing to
    /// double-count (FR-10b). This is the disk analogue of NetSpeed's exclusion
    /// of VPN and virtual interfaces, except the layer choice does the work and
    /// no exclusion list is needed.
    ///
    /// Two properties of these counters differ from NetSpeed's `getifaddrs`
    /// source and are worth keeping in mind:
    ///
    /// - **They are 64-bit.** `if_data`'s counters are 32-bit and wrap at 4 GiB,
    ///   which NetSpeed had to guard against and was observed doing in practice.
    ///   Wrap is not a practical concern here.
    /// - **They are per-attachment, not lifetime.** The `IOBlockStorageDriver`
    ///   is instantiated when the device attaches, with its statistics starting
    ///   at zero (FR-10c, measured). That is why attaching a drive cannot inject
    ///   a false spike, and why *detaching* one — not attaching — is the case the
    ///   sampler has to handle.
    ///
    /// Returns an empty array rather than throwing if the registry is
    /// unavailable, so callers degrade to a zero reading (NFR-4).
    static func readAll() -> [DriveCounter] {
        var results: [DriveCounter] = []

        guard let matching = IOServiceMatching("IOBlockStorageDriver") else { return results }

        // IOServiceGetMatchingServices consumes a reference to `matching`;
        // we must not release it ourselves.
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return results
        }
        defer { IOObjectRelease(iterator) }

        while case let drive = IOIteratorNext(iterator), drive != IO_OBJECT_NULL {
            defer { IOObjectRelease(drive) }

            // The counters themselves live on the IOBlockStorageDriver.
            guard let statistics = IORegistryEntryCreateCFProperty(
                    drive,
                    kIOBlockStorageDriverStatisticsKey as CFString,
                    kCFAllocatorDefault,
                    0
                  )?.takeRetainedValue() as? [String: Any] else {
                continue
            }

            let bytesRead = (statistics[kIOBlockStorageDriverStatisticsBytesReadKey] as? NSNumber)?.uint64Value ?? 0
            let bytesWritten = (statistics[kIOBlockStorageDriverStatisticsBytesWrittenKey] as? NSNumber)?.uint64Value ?? 0

            results.append(
                DriveCounter(
                    bsdName: searchString(from: drive, key: "BSD Name", inParents: false) ?? "?",
                    productName: searchDictionary(from: drive, key: "Device Characteristics")?["Product Name"] as? String ?? "?",
                    interconnect: searchDictionary(from: drive, key: "Protocol Characteristics")?["Physical Interconnect"] as? String ?? "?",
                    bytesRead: bytesRead,
                    bytesWritten: bytesWritten
                )
            )
        }

        return results
    }

    // MARK: Registry lookup helpers

    /// Searches the registry for a dictionary-valued property, walking *up* the
    /// parent chain. The characteristics dictionaries live on the parent
    /// `IOBlockStorageDevice`, not on the driver we matched.
    ///
    /// NOTE: `IORegistryEntrySearchCFProperty` returns an already-retained
    /// `CFTypeRef?` in Swift and is cast directly — unlike
    /// `IORegistryEntryCreateCFProperty` above, which returns
    /// `Unmanaged<CFTypeRef>!` and needs `takeRetainedValue()`. Mixing the two up
    /// is a compile error, so the asymmetry is deliberate rather than an oversight.
    private static func searchDictionary(from entry: io_registry_entry_t, key: String) -> [String: Any]? {
        IORegistryEntrySearchCFProperty(
            entry,
            kIOServicePlane,
            key as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        ) as? [String: Any]
    }

    /// Searches the registry for a string-valued property. `inParents` is false
    /// for the BSD name, which lives on the *child* `IOMedia` rather than up the
    /// parent chain.
    private static func searchString(from entry: io_registry_entry_t, key: String, inParents: Bool) -> String? {
        var options = IOOptionBits(kIORegistryIterateRecursively)
        if inParents { options |= IOOptionBits(kIORegistryIterateParents) }
        return IORegistryEntrySearchCFProperty(
            entry,
            kIOServicePlane,
            key as CFString,
            kCFAllocatorDefault,
            options
        ) as? String
    }

    // MARK: Increment 1.1 scaffolding

    /// Prints a one-shot snapshot of every physical storage device to the console.
    ///
    /// Temporary: this exists to satisfy Increment 1.1's verification (console
    /// shows plausible counters and a correct bus per device) and is removed in
    /// the Phase 2 cleanup, exactly as NetSpeed's equivalent snapshot was. It is
    /// the only reason `bsdName` and `productName` are read at all.
    static func printSnapshot() {
        let drives = readAll()
        print("DriveSpeed — \(drives.count) physical storage device(s):")
        for drive in drives {
            let read = String(format: "%.2f", Double(drive.bytesRead) / 1_000_000_000)
            let written = String(format: "%.2f", Double(drive.bytesWritten) / 1_000_000_000)
            print("  "
                  + rightPad(drive.bsdName, 8)
                  + rightPad(drive.productName, 20)
                  + rightPad(drive.interconnect, 14)
                  + "read " + leftPad(read, 8) + " GB"
                  + "   written " + leftPad(written, 8) + " GB")
        }
    }

    /// Pads on the right to `width` for column alignment, with at least one
    /// trailing space so over-long values never run into the next column.
    ///
    /// Done by hand because `String(format:)`'s field-width flags are silently
    /// ignored for the `%@` object specifier on Darwin — `"%-22@"` pads nothing,
    /// which is why the first cut of this snapshot printed ragged columns.
    private static func rightPad(_ string: String, _ width: Int) -> String {
        string.count >= width
            ? string + " "
            : string + String(repeating: " ", count: width - string.count)
    }

    /// Pads on the left to `width`, right-aligning the numeric columns.
    private static func leftPad(_ string: String, _ width: Int) -> String {
        string.count >= width
            ? string
            : String(repeating: " ", count: width - string.count) + string
    }
}
