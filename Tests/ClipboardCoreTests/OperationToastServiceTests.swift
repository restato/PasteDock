import ClipboardCore
import Testing

@Test
func operationToastQueueEnqueuesDequeuesInOrder() async {
    let service = OperationToastService()

    await service.enqueue(OperationToast(message: "one", style: .info))
    await service.enqueue(OperationToast(message: "two", style: .success))

    #expect(await service.pendingCount() == 2)

    let first = await service.dequeue()
    let second = await service.dequeue()
    let third = await service.dequeue()

    #expect(first == OperationToast(message: "one", style: .info))
    #expect(second == OperationToast(message: "two", style: .success))
    #expect(third == nil)
    #expect(await service.pendingCount() == 0)
}
