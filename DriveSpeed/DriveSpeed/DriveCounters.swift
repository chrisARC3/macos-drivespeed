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
/// "PCI-Express", "USB", and so on — which `isSampled(interconnect:)` turns into
/// the FR-10 filter.
///
/// Three fields is all of it. Earlier increments also carried `bsdName` and
/// `productName` to make the Phase 1 console snapshot legible; both were removed
/// with that scaffolding in Increment 2.3, per FR-10d — DriveSpeed keeps no
/// per-device identity, and dropping them also removes two registry searches per
/// device per tick.
///
/// `nonisolated` explicitly: the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor`, so a bare declaration would be implicitly main-actor isolated.
/// Reading IOKit registry properties has nothing to do with the main actor, and
/// leaving the default in place makes `SpeedSampler`'s off-actor sampling helper
/// a concurrency warning.
nonisolated struct DriveCounter {
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
                    interconnect: searchDictionary(from: drive, key: "Protocol Characteristics")?["Physical Interconnect"] as? String ?? "?",
                    bytesRead: bytesRead,
                    bytesWritten: bytesWritten
                )
            )
        }

        return results
    }

    // MARK: Bus filter (FR-10)

    /// The `Physical Interconnect` values DriveSpeed counts: the Mac's internal
    /// storage plus USB.
    ///
    /// `Apple Fabric` is how Apple Silicon's internal SSD reports — **not**
    /// `NVMe`, which macOS never reports on this hardware (FR-10a). `PCI-Express`
    /// is accepted so the filter stays correct on an Intel Mac or a genuine PCIe
    /// slot, though nothing on the target machine matches it. `USB` covers every
    /// external drive here, including NVMe drives in USB enclosures.
    ///
    /// Everything else is excluded: Thunderbolt and SATA are out of scope for v1
    /// for want of testable hardware (§3), and disk images fall outside these
    /// values too — their backing I/O is already counted once on the real device.
    /// Adding a bus later is a one-line change to this set.
    private static let sampledInterconnects: Set<String> = ["Apple Fabric", "PCI-Express", "USB"]

    /// Whether a device on this bus counts toward the readings (FR-10).
    ///
    /// A plain predicate rather than a bus enum on purpose: FR-10 sums internal
    /// and USB into a single pair of figures, so nothing downstream ever needs to
    /// know *which* of the two a device sits on — only whether it qualifies.
    static func isSampled(interconnect: String) -> Bool {
        sampledInterconnects.contains(interconnect)
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
}
