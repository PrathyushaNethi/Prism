/**
 * PRISM - AIPriorityQueueController
 * Apex controller for the prismAIPriorityQueue LWC.
 */
public with sharing class PRISM_AIPriorityQueueController {

    @AuraEnabled(cacheable=true)
    public static List<PRISM_AIPriorityQueue__c> getQueueEntries() {
        return [
            SELECT Id, Name, Rank__c, CompositeScore__c, RecommendedAction__c,
                   ActionRationale__c, WorkOrderCreated__c, GeneratedDate__c,
                   WildfireRiskScore__r.Score__c, WildfireRiskScore__r.Tier__c,
                   WildfireRiskScore__r.Asset__r.Name,
                   WildfireRiskScore__r.Asset__r.ComponentType__c,
                   WildfireRiskScore__r.Asset__r.Circuit__r.Name,
                   WildfireRiskScore__r.Asset__r.Circuit__r.ServiceTerritory__r.Name
            FROM PRISM_AIPriorityQueue__c
            WHERE WorkOrderCreated__c = false
            ORDER BY Rank__c ASC
            LIMIT 100
        ];
    }

    @AuraEnabled
    public static Id createWorkOrderFromQueue(Id queueEntryId) {
        PRISM_AIPriorityQueue__c entry = [
            SELECT Id, RecommendedAction__c, WorkOrderCreated__c
            FROM PRISM_AIPriorityQueue__c
            WHERE Id = :queueEntryId LIMIT 1
        ];

        if (entry.WorkOrderCreated__c) {
            throw new AuraHandledException('Work Order already exists for this queue entry.');
        }

        String workType = 'Scheduled Repair';
        String priority = 'Medium';
        if (entry.RecommendedAction__c == 'Immediate De-energize' ||
            entry.RecommendedAction__c == 'Emergency Repair Within 24hrs') {
            workType = 'Emergency Repair';
            priority = 'Critical';
        } else if (entry.RecommendedAction__c == 'Schedule Repair This Week') {
            priority = 'High';
        }

        PRISM_WorkOrder__c wo = new PRISM_WorkOrder__c(
            AIPriorityQueue__c = queueEntryId,
            WorkType__c        = workType,
            Status__c          = 'New',
            Priority__c        = priority,
            ScheduledDate__c   = System.today()
        );
        insert wo;

        entry.WorkOrderCreated__c = true;
        update entry;

        return wo.Id;
    }

    @AuraEnabled
    public static void triggerQueueRefresh() {
        System.enqueueJob(new PRISM_QueueRefreshQueueable());
    }
}
