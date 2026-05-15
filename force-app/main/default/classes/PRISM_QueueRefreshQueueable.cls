public with sharing class PRISM_QueueRefreshQueueable implements Queueable {
    public void execute(QueueableContext ctx) {
        PRISM_AIPriorityQueueService.refreshQueue();
    }
}
