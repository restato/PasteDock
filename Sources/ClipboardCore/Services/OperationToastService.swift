import Foundation

public actor OperationToastService {
    private var queue: [OperationToast] = []

    public init() {}

    public func enqueue(_ toast: OperationToast) {
        queue.append(toast)
    }

    public func dequeue() -> OperationToast? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    public func pendingCount() -> Int {
        queue.count
    }
}
