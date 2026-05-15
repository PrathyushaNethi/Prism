/**
 * PRISM - AIPriorityQueueService
 * Generates and refreshes the AI Priority Queue by:
 *   1. Reading all WildfireRiskScore records above threshold
 *   2. Joining with open DefectFindings
 *   3. Computing a composite priority rank
 *   4. Upserting AIPriorityQueue__c records
 *   5. Auto-creating WorkOrders for Tier 1 / Tier 2 items
 */
public with sharing class PRISM_AIPriorityQueueService {

    private static final Decimal SCORE_THRESHOLD = 30.0;

    public static void refreshQueue() {
        List<PRISM_WildfireRiskScore__c> highRisk = [
            SELECT Id, Score__c, Tier__c, Asset__c,
                   Asset__r.ComponentType__c,
                   Asset__r.Circuit__r.ServiceTerritory__r.Name,
                   Asset__r.Circuit__r.ServiceTerritory__r.ActiveFireNearby__c
            FROM PRISM_WildfireRiskScore__c
            WHERE Score__c >= :SCORE_THRESHOLD
            ORDER BY Score__c DESC
            LIMIT 200
        ];

        if (highRisk.isEmpty()) return;

        List<PRISM_AIPriorityQueue__c> queueEntries = new List<PRISM_AIPriorityQueue__c>();
        Integer rank = 1;

        for (PRISM_WildfireRiskScore__c wrs : highRisk) {
            String action    = determineAction(wrs.Score__c, wrs.Tier__c,
                                               wrs.Asset__r.Circuit__r.ServiceTerritory__r.ActiveFireNearby__c);
            String rationale = buildRationale(wrs);

            PRISM_AIPriorityQueue__c entry = new PRISM_AIPriorityQueue__c(
                WildfireRiskScore__c  = wrs.Id,
                Rank__c               = rank,
                CompositeScore__c     = wrs.Score__c,
                RecommendedAction__c  = action,
                ActionRationale__c    = rationale,
                GeneratedDate__c      = System.now(),
                WorkOrderCreated__c   = false
            );
            queueEntries.add(entry);
            rank++;
        }

        insert queueEntries;

        // Auto-create WorkOrders for Tier 1 and Tier 2
        List<PRISM_WorkOrder__c> autoWorkOrders = new List<PRISM_WorkOrder__c>();
        for (Integer i = 0; i < queueEntries.size(); i++) {
            PRISM_WildfireRiskScore__c wrs = highRisk[i];
            if (wrs.Tier__c == 'Tier 1 - Extreme' || wrs.Tier__c == 'Tier 2 - High') {
                autoWorkOrders.add(new PRISM_WorkOrder__c(
                    AIPriorityQueue__c = queueEntries[i].Id,
                    WorkType__c        = wrs.Tier__c == 'Tier 1 - Extreme' ? 'Emergency Repair' : 'Scheduled Repair',
                    Status__c          = 'New',
                    Priority__c        = wrs.Tier__c == 'Tier 1 - Extreme' ? 'Critical' : 'High',
                    ScheduledDate__c   = wrs.Tier__c == 'Tier 1 - Extreme'
                                         ? System.today()
                                         : System.today().addDays(7)
                ));
            }
        }

        if (!autoWorkOrders.isEmpty()) {
            insert autoWorkOrders;

            // Mark queue entries as having work orders
            Set<Id> queueIdsWithWO = new Set<Id>();
            for (PRISM_WorkOrder__c wo : autoWorkOrders) {
                queueIdsWithWO.add(wo.AIPriorityQueue__c);
            }
            List<PRISM_AIPriorityQueue__c> toUpdate = new List<PRISM_AIPriorityQueue__c>();
            for (Id qId : queueIdsWithWO) {
                toUpdate.add(new PRISM_AIPriorityQueue__c(Id = qId, WorkOrderCreated__c = true));
            }
            update toUpdate;
        }
    }

    private static String determineAction(Decimal score, String tier, Boolean activeFire) {
        if (activeFire == true && score >= 70) return 'Immediate De-energize';
        if (tier == 'Tier 1 - Extreme')        return 'Emergency Repair Within 24hrs';
        if (tier == 'Tier 2 - High')           return 'Schedule Repair This Week';
        if (tier == 'Tier 3 - Elevated')       return 'Schedule Repair This Month';
        return 'Monitor and Reassess';
    }

    private static String buildRationale(PRISM_WildfireRiskScore__c wrs) {
        String r = 'Asset risk tier: ' + wrs.Tier__c + '. Composite score: ' + wrs.Score__c + '/100.';
        if (wrs.Asset__r.Circuit__r.ServiceTerritory__r.ActiveFireNearby__c) {
            r += ' Active fire detected in service territory.';
        }
        r += ' Component type: ' + wrs.Asset__r.ComponentType__c + '.';
        return r;
    }
}
