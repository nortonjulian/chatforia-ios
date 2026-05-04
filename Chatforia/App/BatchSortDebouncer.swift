import Foundation

final class BatchSortDebouncer {
    private var workItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.chatforia.batchSort", qos: .userInitiated)
    private let debounceInterval: TimeInterval

    init(debounceInterval: TimeInterval = 0.03) { // 30ms default
        self.debounceInterval = debounceInterval
    }

    func scheduleSort(_ sortBlock: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard self != nil else { return }
            sortBlock()
        }
        workItem = item
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }

    func flush() {
        workItem?.perform()
        workItem?.cancel()
        workItem = nil
    }
}
