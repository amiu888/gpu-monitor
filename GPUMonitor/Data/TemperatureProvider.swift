import Foundation
import IOKit

// Reads temperature via IOHIDEventSystemClient (the real path for M4 Apple Silicon).
// SMC key-value interface does not expose temps on M4 Max — PMU sensors are the source.
final class TemperatureProvider {
    private typealias IOHIDEventRef = OpaquePointer

    private let fw = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)

    private typealias CreateFn    = @convention(c) (CFAllocator?, Int32, CFDictionary?) -> AnyObject?
    private typealias SetMatchFn  = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopySvcsFn  = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias SvcPropFn   = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int64, Int32) -> IOHIDEventRef?
    private typealias FloatFn     = @convention(c) (IOHIDEventRef, Int64) -> Double

    private let kTempEvent: Int64 = 15
    private var client: AnyObject?

    private var create:       CreateFn?
    private var setMatch:     SetMatchFn?
    private var copyServices: CopySvcsFn?
    private var svcProp:      SvcPropFn?
    private var copyEvent:    CopyEventFn?
    private var floatVal:     FloatFn?

    init() {
        guard let fw else { return }
        guard let fnCreate = dlsym(fw, "IOHIDEventSystemClientCreateWithType"),
              let fnMatch  = dlsym(fw, "IOHIDEventSystemClientSetMatching"),
              let fnSvcs   = dlsym(fw, "IOHIDEventSystemClientCopyServices"),
              let fnProp   = dlsym(fw, "IOHIDServiceClientCopyProperty"),
              let fnEvent  = dlsym(fw, "IOHIDServiceClientCopyEvent"),
              let fnFloat  = dlsym(fw, "IOHIDEventGetFloatValue") else { return }

        create       = unsafeBitCast(fnCreate, to: CreateFn.self)
        setMatch     = unsafeBitCast(fnMatch,  to: SetMatchFn.self)
        copyServices = unsafeBitCast(fnSvcs,   to: CopySvcsFn.self)
        svcProp      = unsafeBitCast(fnProp,   to: SvcPropFn.self)
        copyEvent    = unsafeBitCast(fnEvent,  to: CopyEventFn.self)
        floatVal     = unsafeBitCast(fnFloat,  to: FloatFn.self)

        // Type 1 = simple client; type 2 (monitor) returns no events without runloop setup
        if let c = create?(kCFAllocatorDefault, 1, nil) {
            let matching: NSDictionary = ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 0x0005]
            setMatch?(c, matching)
            client = c
        }
    }

    struct Temps {
        var cpu: Double?  // °C
        var gpu: Double?  // °C
    }

    func fetch() -> Temps {
        guard let client,
              let svcsRaw = copyServices?(client)?.takeRetainedValue() else { return Temps() }

        var dieTemps: [Double] = []
        var devTemps: [Double] = []

        for i in 0..<CFArrayGetCount(svcsRaw) {
            guard let ptr = CFArrayGetValueAtIndex(svcsRaw, i) else { continue }
            let svc = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
            guard let ev = copyEvent?(svc, kTempEvent, 0, 0) else { continue }
            let t = floatVal?(ev, kTempEvent << 16) ?? 0
            guard t > 1, t < 150 else { continue }
            let name = svcProp?(svc, "Product" as CFString)?.takeRetainedValue() as? String ?? ""
            // PMU tdie* = CPU cluster die temps; PMU tdev* = device (includes GPU)
            if name.hasPrefix("PMU tdie") {
                dieTemps.append(t)
            } else if name.hasPrefix("PMU tdev") {
                devTemps.append(t)
            }
        }

        return Temps(
            cpu: dieTemps.isEmpty ? nil : dieTemps.max(),
            gpu: devTemps.isEmpty ? nil : devTemps.max()
        )
    }
}
