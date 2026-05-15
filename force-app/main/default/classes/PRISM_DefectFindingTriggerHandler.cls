public with sharing class PRISM_DefectFindingTriggerHandler {

    public static void afterInsert(List<SObject> newRecords) {
        handleSeverityOne(newRecords);
    }

    public static void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        List<SObject> changed = new List<SObject>();
        for (SObject d : newRecords) {
            if (d.get('Severity__c') != oldMap.get((Id) d.get('Id')).get('Severity__c')) {
                changed.add(d);
            }
        }
        if (!changed.isEmpty()) handleSeverityOne(changed);
    }

    private static void handleSeverityOne(List<SObject> defects) {
        Schema.SObjectType woType  = Schema.getGlobalDescribe().get('PRISM_WorkOrder__c');
        Schema.SObjectType defType = Schema.getGlobalDescribe().get('PRISM_DefectFinding__c');
        List<SObject> toCreate = new List<SObject>();
        List<SObject> toFlag   = new List<SObject>();
        for (SObject d : defects) {
            if (d.get('Severity__c') == '1 - Imminent Hazard' && d.get('WorkOrderCreated__c') != true) {
                SObject wo = woType.newSObject();
                wo.put('DefectFinding__c', d.get('Id'));
                wo.put('WorkType__c',      'Emergency Repair');
                wo.put('Status__c',        'New');
                wo.put('Priority__c',      'Critical');
                wo.put('ScheduledDate__c', System.today());
                toCreate.add(wo);
                SObject flag = defType.newSObject();
                flag.put('Id',                d.get('Id'));
                flag.put('WorkOrderCreated__c', true);
                toFlag.add(flag);
            }
        }
        if (!toCreate.isEmpty()) {
            insert toCreate;
            update toFlag;
        }
    }
}
