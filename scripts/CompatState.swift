import SwiftUI

// A stand-in for SwiftUI's `@State`, injected by build_app.sh only when the
// toolchain can't expand the real one.
//
// In current macOS SDKs `State` is an attached macro as well as a property
// wrapper, and the macro is what `@State` resolves to. Expanding it needs the
// SwiftUIMacros compiler plugin, which ships inside Xcode and has never been
// part of the Command Line Tools — so a CLT-only build of any SwiftUI view
// that uses `@State` fails before it starts.
//
// The property wrapper the macro stands in front of is still there, and is
// still public. This holds one of those and forwards to it, which is the same
// shape SwiftUI's own `GestureState` uses internally: SwiftUI walks nested
// `DynamicProperty` members, so the storage and invalidation behaviour is the
// real thing rather than an imitation of it.
@propertyWrapper
struct CompatState<Value>: DynamicProperty {
    private var storage: State<Value>

    init(wrappedValue: Value) {
        storage = State(wrappedValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> {
        storage.projectedValue
    }
}
