import SwiftUI

extension Binding where Value == Bool {
    static func isPresenting<Item: Sendable>(_ item: Binding<Item?>) -> Binding<Bool> {
        Binding(
            get: { item.wrappedValue != nil },
            set: { isPresented in
                if !isPresented { item.wrappedValue = nil }
            }
        )
    }
}
