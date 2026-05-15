trigger PRISM_DefectFindingTrigger on PRISM_DefectFinding__c (after insert, after update) {
    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            PRISM_DefectFindingTriggerHandler.afterInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            PRISM_DefectFindingTriggerHandler.afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }
}
