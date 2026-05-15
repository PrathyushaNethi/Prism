/**
 * PRISM - InspectionController
 * Apex controller for the prismInspectionAssignment LWC.
 */
public with sharing class PRISM_InspectionController {

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getInspectionData(Id inspectionId) {
        PRISM_Inspection__c insp = [
            SELECT Id, Name, Status__c, InspectionDate__c, InspectionMethod__c,
                   Inspector__c, Inspector__r.Name,
                   WindSpeedMPH__c, HumidityPercent__c, TemperatureFahrenheit__c,
                   FireDangerLevel__c, RedFlagWarning__c, NearestActiveFireMiles__c,
                   Attachment__c, Attachment__r.Name, Attachment__r.AttachmentType__c,
                   Notes__c
            FROM PRISM_Inspection__c
            WHERE Id = :inspectionId
            LIMIT 1
        ];

        List<PRISM_DefectFinding__c> defects = [
            SELECT Id, Name, DefectType__c, Severity__c, Description__c,
                   PhotoURL__c, WorkOrderCreated__c
            FROM PRISM_DefectFinding__c
            WHERE Inspection__c = :inspectionId
            ORDER BY Severity__c ASC
        ];

        return new Map<String, Object>{
            'inspection' => insp,
            'defects'    => defects
        };
    }

    @AuraEnabled
    public static Id createWorkOrderFromDefect(Id defectId) {
        PRISM_DefectFinding__c defect = [
            SELECT Id, Severity__c, WorkOrderCreated__c
            FROM PRISM_DefectFinding__c
            WHERE Id = :defectId LIMIT 1
        ];

        if (defect.WorkOrderCreated__c) {
            throw new AuraHandledException('Work Order already exists for this defect.');
        }

        PRISM_WorkOrder__c wo = new PRISM_WorkOrder__c(
            DefectFinding__c = defectId,
            WorkType__c      = defect.Severity__c == '1 - Imminent Hazard' ? 'Emergency Repair' : 'Scheduled Repair',
            Status__c        = 'New',
            Priority__c      = defect.Severity__c == '1 - Imminent Hazard' ? 'Critical' : 'High',
            ScheduledDate__c = System.today()
        );
        insert wo;

        defect.WorkOrderCreated__c = true;
        update defect;

        return wo.Id;
    }
}
