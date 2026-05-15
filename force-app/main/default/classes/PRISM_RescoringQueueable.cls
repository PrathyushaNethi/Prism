/**
 * PRISM - RescoringQueueable
 * Async re-scores a list of Assets outside the trigger transaction.
 */
public with sharing class PRISM_RescoringQueueable implements Queueable {
    private List<Id> assetIds;

    public PRISM_RescoringQueueable(List<Id> assetIds) {
        this.assetIds = assetIds;
    }

    public void execute(QueueableContext ctx) {
        PRISM_WildfireRiskScoringService.scoreAssets(assetIds);
    }
}
