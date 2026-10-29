import SwiftUI

enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(AppError)

    var value: Value? {
        if case .loaded(let value) = self { value } else { nil }
    }

    var isLoading: Bool {
        if case .loading = self { true } else { false }
    }

    func map<Transformed>(_ transform: (Value) -> Transformed) -> LoadState<Transformed> {
        switch self {
        case .idle: .idle
        case .loading: .loading
        case .loaded(let value): .loaded(transform(value))
        case .failed(let error): .failed(error)
        }
    }
}

/// Loads into `state`, keeping already-loaded content on screen during a refresh.
///
/// - Returns: The error when refreshing existing content fails, so the caller can show it
///   without replacing the content with an error screen.
@discardableResult
func refreshContent<Value>(
    _ state: Binding<LoadState<Value>>,
    operation: () async throws -> Value
) async -> AppError? {
    let previous = state.wrappedValue.value
    if previous == nil {
        state.wrappedValue = .loading
    }
    do {
        state.wrappedValue = .loaded(try await operation())
        return nil
    } catch {
        if error.isCancellation {
            if previous == nil { state.wrappedValue = .idle }
            return nil
        }
        let appError = AppError(error)
        guard previous != nil else {
            state.wrappedValue = .failed(appError)
            return nil
        }
        return appError
    }
}
