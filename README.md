# PRISM — Utility Infrastructure Inspection & Wildfire Risk Management

## Overview
PRISM is a Salesforce Lightning application for utility companies to manage field
inspections, track defects, and proactively prioritize maintenance using AI-driven
wildfire risk scoring.

## Data Model
| Object | Description |
|--------|-------------|
| PRISM_ServiceTerritory__c | Top-level geographic territory |
| PRISM_Structure__c | Poles, transformers, switches |
| PRISM_Circuit__c | Feeders, distribution lines |
| PRISM_Attachment__c | Telecom/power/street light attachments on structures |
| PRISM_Inspection__c | Field inspection with live hazard conditions |
| PRISM_Asset__c | Equipment components on circuits |
| PRISM_DefectFinding__c | Defects logged during inspections |
| PRISM_WildfireRiskScore__c | AI-calculated risk score per asset |
| PRISM_WorkOrder__c | Repair/maintenance work orders |
| PRISM_AIPriorityQueue__c | Ranked AI priority queue |

## Key Features
- **Red Flag Warning Banner** — Live hazard conditions displayed on every inspection record
- **Auto Work Order Creation** — Severity-1 defects instantly create Critical work orders
- **Wildfire Risk Scoring Engine** — Composite score based on defect severity, weather, asset age, and component type
- **AI Priority Queue** — Ranked list of assets needing action with recommended actions
- **Nightly Batch Scoring** — Scheduled Apex batch re-scores all active assets at 2am

## Deployment

### Prerequisites
- Salesforce CLI (`sf`) installed
- Authenticated to your org: `sf org login web -a myorg`

### Deploy
```bash
cd prism
sf project deploy start -d force-app -o myorg
```

### Assign Permission Set
```bash
sf org assign permset -n PRISM_Full_Access -o myorg
```

### Schedule Nightly Batch
Run in Developer Console (Execute Anonymous):
```apex
System.schedule('PRISM Nightly Risk Score',
                '0 0 2 * * ?',
                new PRISM_WildfireRiskScoringBatch());
```

## Architecture
```
Trigger: PRISM_DefectFindingTrigger
  └── PRISM_DefectFindingTriggerHandler
       ├── Auto-creates WorkOrders for Severity-1 defects
       └── PRISM_RescoringQueueable (async)
            └── PRISM_WildfireRiskScoringService.scoreAssets()

Scheduled: PRISM_WildfireRiskScoringBatch (nightly 2am)
  └── PRISM_WildfireRiskScoringService.scoreAssets() (all active assets)
  └── PRISM_AIPriorityQueueService.refreshQueue()

LWC: prismInspectionAssignment
  └── Shows Red Flag Warning banner, weather conditions, defect list

LWC: prismAIPriorityQueue
  └── Ranked queue with recommended actions and one-click WO creation
```
