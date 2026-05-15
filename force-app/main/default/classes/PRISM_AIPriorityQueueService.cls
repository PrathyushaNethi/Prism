public with sharing class PRISM_AIPriorityQueueService {

    private static final Decimal SCORE_THRESHOLD = 30.0;

    public static void refreshQueue() {
        List<SObject> highRisk = Database.query(
            'SELECT Id, Score__c, Tier__c, Asset__c, ' +
            'Asset__r.ComponentType__c, ' +
            'Asset__r.Circuit__r.ServiceTerritory__r.ActiveFireNearby__c ' +
            'FROM PRISM_WildfireRiskScore__c ' +
            'WHERE Score__c >= :SCORE_THRESHOLD ORDER BY Score__c DESC LIMIT 200'
        );
        if (highRisk.isEmpty()) return;

        Schema.SObjectType queueType = Schema.getGlobalDescribe().get('PRISM_AIPriorityQueue__c');
        Schema.SObjectType woType    = Schema.getGlobalDescribe().get('PRISM_WorkOrder__c');

        List<SObject> queueEntries = new List<SObject>();
        Integer rank = 1;
        for (SObject wrs : highRisk) {
            String tier   = (String) wrs.get('Tier__c');
            Decimal score = (Decimal) wrs.get('Score__c');
            SObject asset     = wrs.getSObject('Asset__r');
            SObject circuit   = asset != null ? asset.getSObject('Circuit__r') : null;
            SObject territory = circuit != null ? circuit.getSObject('ServiceTerritory__r') : null;
            Boolean activeFire = territory != null ? (Boolean) territory.get('ActiveFireNearby__c') : false;

            String action    = determineAction(score, tier, activeFire);
            String rationale = 'Asset risk tier: ' + tier + '. Score: ' + score + '/100.';
            if (activeFire == true) rationale += ' Active fire in territory.';

            SObject entry = queueType.newSObject();
            entry.put('WildfireRiskScore__c', wrs.get('Id'));
            entry.put('Rank__c',              rank);
            entry.put('CompositeScore__c',    score);
            entry.put('RecommendedAction__c', action);
            entry.put('ActionRationale__c',   rationale);
            entry.put('GeneratedDate__c',     System.now());
            entry.put('WorkOrderCreated__c',  false);
            queueEntries.add(entry);
            rank++;
        }
        insert queueEntries;

        List<SObject> autoWOs = new List<SObject>();
        List<SObject> toFlag  = new List<SObject>();
        for (Integer i = 0; i < queueEntries.size(); i++) {
            String tier = (String) highRisk[i].get('Tier__c');
            if (tier == 'Tier 1 - Extreme' || tier == 'Tier 2 - High') {
                SObject wo = woType.newSObject();
                wo.put('AIPriorityQueue__c', queueEntries[i].get('Id'));
                wo.put('WorkType__c',        tier == 'Tier 1 - Extreme' ? 'Emergency Repair' : 'Scheduled Repair');
                wo.put('Status__c',          'New');
                wo.put('Priority__c',        tier == 'Tier 1 - Extreme' ? 'Critical' : 'High');
                wo.put('ScheduledDate__c',   tier == 'Tier 1 - Extreme' ? System.today() : System.today().addDays(7));
                autoWOs.add(wo);
                SObject flag = queueType.newSObject();
                flag.put('Id',                queueEntries[i].get('Id'));
                flag.put('WorkOrderCreated__c', true);
                toFlag.add(flag);
            }
        }
        if (!autoWOs.isEmpty()) {
            insert autoWOs;
            update toFlag;
        }
    }

    private static String determineAction(Decimal score, String tier, Boolean activeFire) {
        if (activeFire == true && score >= 70) return 'Immediate De-energize';
        if (tier == 'Tier 1 - Extreme')        return 'Emergency Repair Within 24hrs';
        if (tier == 'Tier 2 - High')           return 'Schedule Repair This Week';
        if (tier == 'Tier 3 - Elevated')       return 'Schedule Repair This Month';
        return 'Monitor and Reassess';
    }
}
