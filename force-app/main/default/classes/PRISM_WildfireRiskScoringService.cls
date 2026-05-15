public with sharing class PRISM_WildfireRiskScoringService {

    private static final Decimal WEIGHT_DEFECT    = 0.40;
    private static final Decimal WEIGHT_WEATHER   = 0.35;
    private static final Decimal WEIGHT_ASSET_AGE = 0.15;
    private static final Decimal WEIGHT_COMP_TYPE = 0.10;

    public static void scoreAssets(List<Id> assetIds) {
        for (Id aid : assetIds) {
            scoreAsset(aid);
        }
    }

    public static void scoreAsset(Id assetId) {
        List<SObject> assetList = Database.query(
            'SELECT Id, InstallYear__c, ComponentType__c, ' +
            'Circuit__r.ServiceTerritory__r.ActiveFireNearby__c, ' +
            'Circuit__r.ServiceTerritory__r.NearestActiveFireMiles__c ' +
            'FROM PRISM_Asset__c WHERE Id = :assetId LIMIT 1'
        );
        if (assetList.isEmpty()) return;
        SObject asset = assetList[0];

        List<SObject> defectList = Database.query(
            'SELECT Severity__c, DefectType__c FROM PRISM_DefectFinding__c ' +
            'WHERE WorkOrderCreated__c = false ORDER BY CreatedDate DESC LIMIT 50'
        );

        List<SObject> inspList = Database.query(
            'SELECT WindSpeedMPH__c, HumidityPercent__c, TemperatureFahrenheit__c, ' +
            'FireDangerLevel__c, RedFlagWarning__c FROM PRISM_Inspection__c ' +
            'ORDER BY InspectionDate__c DESC LIMIT 5'
        );

        SObject circuit   = asset.getSObject('Circuit__r');
        SObject territory = circuit != null ? circuit.getSObject('ServiceTerritory__r') : null;
        Boolean activeFire  = territory != null ? (Boolean) territory.get('ActiveFireNearby__c') : false;
        Decimal nearestFire = territory != null ? (Decimal) territory.get('NearestActiveFireMiles__c') : null;

        Decimal defectScore  = calcDefectScore(defectList);
        Decimal weatherScore = calcWeatherScore(inspList, activeFire, nearestFire);
        Decimal ageScore     = calcAgeScore((Decimal) asset.get('InstallYear__c'));
        Decimal compScore    = calcComponentScore((String) asset.get('ComponentType__c'));

        Decimal composite = ((defectScore * WEIGHT_DEFECT) + (weatherScore * WEIGHT_WEATHER)
                           + (ageScore * WEIGHT_ASSET_AGE) + (compScore * WEIGHT_COMP_TYPE))
                           .setScale(2, RoundingMode.HALF_UP);

        List<SObject> existing = Database.query(
            'SELECT Id, Score__c FROM PRISM_WildfireRiskScore__c ' +
            'WHERE Asset__c = :assetId ORDER BY CalculatedDate__c DESC LIMIT 1'
        );

        Schema.SObjectType wrsType = Schema.getGlobalDescribe().get('PRISM_WildfireRiskScore__c');
        SObject wrs;
        if (!existing.isEmpty()) {
            wrs = existing[0];
            wrs.put('PreviousScore__c', wrs.get('Score__c'));
        } else {
            wrs = wrsType.newSObject();
            wrs.put('Asset__c', assetId);
        }
        wrs.put('Score__c',          composite);
        wrs.put('Tier__c',           getTier(composite));
        wrs.put('CalculatedDate__c', System.now());
        wrs.put('ScoreFactors__c',   JSON.serialize(new Map<String,Object>{
            'defect' => defectScore, 'weather' => weatherScore,
            'age' => ageScore, 'component' => compScore
        }));
        upsert wrs;
    }

    private static Decimal calcDefectScore(List<SObject> defects) {
        if (defects.isEmpty()) return 0;
        Decimal total = 0;
        for (SObject d : defects) {
            String sev = (String) d.get('Severity__c');
            String typ = (String) d.get('DefectType__c');
            Decimal pts = sev == '1 - Imminent Hazard' ? 100 :
                          sev == '2 - Priority' ? 70 :
                          sev == '3 - Routine'  ? 35 : 15;
            if (typ == 'Vegetation Encroachment') pts = Math.min(pts * 1.25, 100);
            total += pts;
        }
        return Math.min(total / defects.size(), 100);
    }

    private static Decimal calcWeatherScore(List<SObject> insp, Boolean activeFire, Decimal nearestMiles) {
        Decimal score = 0;
        if (activeFire == true) {
            score += 40;
            if (nearestMiles != null && nearestMiles < 5)  score += 40;
            else if (nearestMiles != null && nearestMiles < 15) score += 20;
        }
        if (!insp.isEmpty()) {
            SObject i = insp[0];
            if (i.get('RedFlagWarning__c') == true) score += 20;
            String fd = (String) i.get('FireDangerLevel__c');
            if      (fd == 'Extreme')   score += 15;
            else if (fd == 'Very High') score += 10;
            else if (fd == 'High')      score += 5;
            Decimal w = (Decimal) i.get('WindSpeedMPH__c');
            Decimal h = (Decimal) i.get('HumidityPercent__c');
            Decimal t = (Decimal) i.get('TemperatureFahrenheit__c');
            if (w != null && w > 35) score += 10;
            if (h != null && h < 15) score += 10;
            if (t != null && t > 90) score += 5;
        }
        return Math.min(score, 100);
    }

    private static Decimal calcAgeScore(Decimal yr) {
        if (yr == null) return 50;
        Integer age = System.today().year() - yr.intValue();
        if (age >= 50) return 100; if (age >= 40) return 80;
        if (age >= 30) return 60;  if (age >= 20) return 40;
        if (age >= 10) return 20;  return 5;
    }

    private static Decimal calcComponentScore(String t) {
        if (t == 'Conductor') return 90;         if (t == 'Insulator') return 70;
        if (t == 'Fuse') return 60;              if (t == 'Recloser') return 50;
        if (t == 'Voltage Regulator') return 40; if (t == 'Capacitor Bank') return 30;
        return 20;
    }

    private static String getTier(Decimal s) {
        if (s >= 80) return 'Tier 1 - Extreme'; if (s >= 60) return 'Tier 2 - High';
        if (s >= 40) return 'Tier 3 - Elevated'; if (s >= 20) return 'Tier 4 - Moderate';
        return 'Tier 5 - Low';
    }
}
