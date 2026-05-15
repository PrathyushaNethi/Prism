/**
 * PRISM - DefectFindingTriggerHandler
 * On insert/update of DefectFinding:
 *   - Severity 1 (Imminent Hazard) → immediately create Work Order
 *   - Trigger re-scoring of the related Asset's WildfireRiskScore
 */
public with sharing class PRISM_DefectFindingTriggerHandler {

    public static void afterInsert(List<PRISM_DefectFinding__c> newRecords) {
        handleSeverityOneAutoWorkOrder(newRecords);
        triggerRescoring(newRecords);
    }

    public static void afterUpdate(List<PRISM_DefectFinding__c> newRecords,
                                   Map<Id, PRISM_DefectFinding__c> oldMap) {
        List<PRISM_DefectFinding__c> changed = new List<PRISM_DefectFinding__c>();
        for (PRISM_DefectFinding__c d : newRecords) {
            if (d.Severity__c != oldMap.get(d.Id).Severity__c) changed.add(d);
        }
        if (!changed.isEmpty()) {
            handleSeverityOneAutoWorkOrder(changed);
            triggerRescoring(changed);
        }
    }

    private static void handleSeverityOneAutoWorkOrder(List<PRISM_DefectFinding__c> defects) {
        List<PRISM_WorkOrder__c> toCreate = new List<PRISM_WorkOrder__c>();
        List<PRISM_DefectFinding__c> toFlag = new List<PRISM_DefectFinding__c>();

        for (PRISM_DefectFinding__c d : defects) {
            if (d.Severity__c == '1 - Imminent Hazard' && !d.WorkOrderCreated__c) {
                toCreate.add(new PRISM_WorkOrder__c(
                    DefectFinding__c = d.Id,
                    WorkType__c      = 'Emergency Repair',
                    Status__c        = 'New',
                    Priority__c      = 'Critical',
                    ScheduledDate__c = System.today()
                ));
                toFlag.add(new PRISM_DefectFinding__c(Id = d.Id, WorkOrderCreated__c = true));
            }
        }

        if (!toCreate.isEmpty()) {
            insert toCreate;
            update toFlag;
        }
    }

    private static void triggerRescoring(List<PRISM_DefectFinding__c> defects) {
        // Collect Asset IDs via the Inspection → Attachment → Structure chain
        Set<Id> inspIds = new Set<Id>();
        for (PRISM_DefectFinding__c d : defects) {
            if (d.Inspection__c != null) inspIds.add(d.Inspection__c);
        }
        if (inspIds.isEmpty()) return;

        // Find Assets in the same territory as the inspections
        List<PRISM_Asset__c> assets = [
            SELECT Id FROM PRISM_Asset__c
            WHERE Circuit__r.ServiceTerritory__c IN (
                SELECT Attachment__r.Structure__r.ServiceTerritory__c
                FROM PRISM_Inspection__c
                WHERE Id IN :inspIds
            )
            LIMIT 50
        ];

        List<Id> assetIds = new List<Id>();
        for (PRISM_Asset__c a : assets) assetIds.add(a.Id);
        if (!assetIds.isEmpty()) {
            System.enqueueJob(new PRISM_RescoringQueueable(assetIds));
        }
    }
}
