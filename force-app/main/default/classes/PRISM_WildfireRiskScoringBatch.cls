public with sharing class PRISM_WildfireRiskScoringBatch implements Database.Batchable<SObject>, Schedulable {

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new PRISM_WildfireRiskScoringBatch(), 50);
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator(
            'SELECT Id FROM PRISM_Asset__c WHERE OperationalStatus__c = \'Active\''
        );
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Id> ids = new List<Id>();
        for (SObject a : scope) ids.add((Id) a.get('Id'));
        try {
            PRISM_WildfireRiskScoringService.scoreAssets(ids);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'PRISM Batch error: ' + e.getMessage());
        }
    }

    public void finish(Database.BatchableContext bc) {
        PRISM_AIPriorityQueueService.refreshQueue();
    }
}
