public with sharing class PRISM_InspectionController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getInspectionData(Id inspectionId) {
        List<SObject> inspList = Database.query(
            'SELECT Id, Name, Status__c, InspectionDate__c, InspectionMethod__c, ' +
            'Inspector__c, Inspector__r.Name, WindSpeedMPH__c, HumidityPercent__c, ' +
            'TemperatureFahrenheit__c, FireDangerLevel__c, RedFlagWarning__c, ' +
            'NearestActiveFireMiles__c, Attachment__c, ' +
            'Attachment__r.Name, Attachment__r.AttachmentType__c, Notes__c ' +
            'FROM PRISM_Inspection__c WHERE Id = :inspectionId LIMIT 1'
        );
        if (inspList.isEmpty()) throw new AuraHandledException('Inspection not found.');
        List<SObject> defects = Database.query(
            'SELECT Id, Name, DefectType__c, Severity__c, Description__c, ' +
            'PhotoURL__c, WorkOrderCreated__c ' +
            'FROM PRISM_DefectFinding__c WHERE Inspection__c = :inspectionId ' +
            'ORDER BY Severity__c ASC'
        );
        return new Map<String, Object>{
            'inspection' => inspList[0],
            'defects'    => defects
        };
    }

    @AuraEnabled
    public static Id createWorkOrderFromDefect(Id defectId) {
        List<SObject> defects = Database.query(
            'SELECT Id, Severity__c, WorkOrderCreated__c ' +
            'FROM PRISM_DefectFinding__c WHERE Id = :defectId LIMIT 1'
        );
        if (defects.isEmpty()) throw new AuraHandledException('Defect not found.');
        SObject defect = defects[0];
        if ((Boolean) defect.get('WorkOrderCreated__c')) {
            throw new AuraHandledException('Work Order already exists for this defect.');
        }
        String sev = (String) defect.get('Severity__c');
        Schema.SObjectType woType = Schema.getGlobalDescribe().get('PRISM_WorkOrder__c');
        SObject wo = woType.newSObject();
        wo.put('DefectFinding__c', defectId);
        wo.put('WorkType__c',      sev == '1 - Imminent Hazard' ? 'Emergency Repair' : 'Scheduled Repair');
        wo.put('Status__c',        'New');
        wo.put('Priority__c',      sev == '1 - Imminent Hazard' ? 'Critical' : 'High');
        wo.put('ScheduledDate__c', System.today());
        insert wo;
        defect.put('WorkOrderCreated__c', true);
        update defect;
        return (Id) wo.get('Id');
    }
}
