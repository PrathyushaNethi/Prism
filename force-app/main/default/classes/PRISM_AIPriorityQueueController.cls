public with sharing class PRISM_AIPriorityQueueController {

    @AuraEnabled(cacheable=true)
    public static List<SObject> getQueueEntries() {
        return Database.query(
            'SELECT Id, Name, Rank__c, CompositeScore__c, RecommendedAction__c, ' +
            'ActionRationale__c, WorkOrderCreated__c, GeneratedDate__c, ' +
            'WildfireRiskScore__r.Score__c, WildfireRiskScore__r.Tier__c, ' +
            'WildfireRiskScore__r.Asset__r.Name, ' +
            'WildfireRiskScore__r.Asset__r.ComponentType__c ' +
            'FROM PRISM_AIPriorityQueue__c ' +
            'WHERE WorkOrderCreated__c = false ' +
            'ORDER BY Rank__c ASC LIMIT 100'
        );
    }

    @AuraEnabled
    public static Id createWorkOrderFromQueue(Id queueEntryId) {
        List<SObject> entries = Database.query(
            'SELECT Id, RecommendedAction__c, WorkOrderCreated__c ' +
            'FROM PRISM_AIPriorityQueue__c WHERE Id = :queueEntryId LIMIT 1'
        );
        if (entries.isEmpty()) throw new AuraHandledException('Queue entry not found.');
        SObject entry = entries[0];
        if ((Boolean) entry.get('WorkOrderCreated__c')) {
            throw new AuraHandledException('Work Order already exists.');
        }
        String action   = (String) entry.get('RecommendedAction__c');
        String workType = (action == 'Immediate De-energize' || action == 'Emergency Repair Within 24hrs')
                          ? 'Emergency Repair' : 'Scheduled Repair';
        String priority = (action == 'Immediate De-energize' || action == 'Emergency Repair Within 24hrs')
                          ? 'Critical' : action == 'Schedule Repair This Week' ? 'High' : 'Medium';
        Schema.SObjectType woType = Schema.getGlobalDescribe().get('PRISM_WorkOrder__c');
        SObject wo = woType.newSObject();
        wo.put('AIPriorityQueue__c', queueEntryId);
        wo.put('WorkType__c',        workType);
        wo.put('Status__c',          'New');
        wo.put('Priority__c',        priority);
        wo.put('ScheduledDate__c',   System.today());
        insert wo;
        entry.put('WorkOrderCreated__c', true);
        update entry;
        return (Id) wo.get('Id');
    }

    @AuraEnabled
    public static void triggerQueueRefresh() {
        System.enqueueJob(new PRISM_QueueRefreshQueueable());
    }
}
