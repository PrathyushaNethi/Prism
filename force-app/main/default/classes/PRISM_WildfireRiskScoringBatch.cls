/**
 * PRISM - WildfireRiskScoringBatch
 * Nightly batch job that re-scores all active Assets
 * and refreshes the AI Priority Queue.
 *
 * Schedule via: System.schedule('PRISM Nightly Risk Score',
 *                               '0 0 2 * * ?',
 *                               new PRISM_WildfireRiskScoringBatch());
 */
public with sharing class PRISM_WildfireRiskScoringBatch
        implements Database.Batchable<SObject>, Database.Stateful, Schedulable {

    private Integer processed = 0;
    private Integer errors    = 0;

    // ── Schedulable ────────────────────────────────────────────────────────
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new PRISM_WildfireRiskScoringBatch(), 50);
    }

    // ── Batchable ──────────────────────────────────────────────────────────
    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id
            FROM PRISM_Asset__c
            WHERE OperationalStatus__c = 'Active'
        ]);
    }

    public void execute(Database.BatchableContext bc, List<PRISM_Asset__c> scope) {
        List<Id> ids = new List<Id>();
        for (PRISM_Asset__c a : scope) ids.add(a.Id);
        try {
            PRISM_WildfireRiskScoringService.scoreAssets(ids);
            processed += ids.size();
        } catch (Exception e) {
            errors += ids.size();
            System.debug(LoggingLevel.ERROR, 'PRISM Batch scoring error: ' + e.getMessage());
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug('PRISM Nightly Scoring complete. Processed: ' + processed + ' Errors: ' + errors);
        // Refresh AI queue after scoring
        PRISM_AIPriorityQueueService.refreshQueue();
    }
}
