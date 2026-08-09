//
//  NetworkCounters.swift
//  DriveSpeed
//
//  Reads cumulative per-interface byte counters via getifaddrs (AF_LINK).
//  Increment 1.1 (the one-shot console snapshot was removed in the Phase 2 cleanup).
//

import Foundation

/// A single network interface's cumulative byte counters, as reported by the OS.
struct InterfaceCounter {
    let name: String
    let bytesIn: UInt64
    let bytesOut: UInt64
}

enum NetworkCounters {

    /// Reads cumulative in/out byte counters for every hardware-level (AF_LINK)
    /// interface the system currently knows about.
    ///
    /// NOTE: `getifaddrs` exposes the classic `if_data` struct, whose byte
    /// counters are 32-bit and wrap at 4 GiB. That is fine for proving we can
    /// read the counters (Increment 1.1) and for the short-interval deltas we
    /// compute later. If we ever need accurate *cumulative* totals, we will
    /// switch to `sysctl` (NET_RT_IFLIST2 / `if_data64`, which uses 64-bit
    /// counters). This is the counter-source spot the build plan flags to
    /// revisit.
    static func readAll() -> [InterfaceCounter] {
        var results: [InterfaceCounter] = []

        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0 else { return results }
        defer { freeifaddrs(ifaddrPtr) }

        var cursor = ifaddrPtr
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }

            // Only AF_LINK entries carry per-interface traffic statistics.
            guard let addr = current.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let dataPtr = current.pointee.ifa_data else {
                continue
            }

            let name = String(cString: current.pointee.ifa_name)
            let data = dataPtr.assumingMemoryBound(to: if_data.self)
            results.append(
                InterfaceCounter(
                    name: name,
                    bytesIn: UInt64(data.pointee.ifi_ibytes),
                    bytesOut: UInt64(data.pointee.ifi_obytes)
                )
            )
        }

        return results
    }
}
