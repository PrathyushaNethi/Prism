/**
 * PRISM - WildfireRiskScoringService
 * Calculates composite wildfire risk score for an Asset based on:
 *   - Defect severity and type
 *   - Inspection hazard conditions (wind, humidity, temperature, fire danger)
 *   - Asset age and component type
 * Score range: 0-100. Higher = greater risk.
 */
public with sharing class PRISM_WildfireRiskScoringService {

    // Weights for composite score
    private static final Decimal WEIGHT_DEFECT      = 0.40;
    private static final Decimal WEIGHT_WEATHER     = 0.35;
    private static final Decimal WEIGHT_ASSET_AGE   = 0.15;
    private static final Decimal WEIGHT_COMP_TYPE   = 0.10;

    /**
     * Score a single Asset and upsert its WildfireRiskScore__c record.
     */
    public static PRISM_WildfireRiskScore__c scoreAsset(Id assetId) {
        List<PRISM_Asset__c> assets = [
            SELECT Id, InstallYear__c, ComponentType__c, OperationalStatus__c,
                   Circuit__r.ServiceTerritory__r.ActiveFireNearby__c,
                   Circuit__r.ServiceTerritory__r.NearestActiveFireMiles__c,
                (SELECT Score__c FROM WildfireRiskScores__r ORDER BY CalculatedDate__c DESC LIMIT 1)
            FROM PRISM_Asset__c
            WHERE Id = :assetId
            LIMIT 1
        ];
        if (assets.isEmpty()) return null;

        List<PRISM_DefectFinding__c> defects = [
            SELECT Severity__c, DefectType__c
            FROM PRISM_DefectFinding__c
            WHERE Inspection__r.Attachment__r.Structure__r.ServiceTerritory__c =
                  :assets[0].Circuit__r.Id
            AND WorkOrderCreated__c = false
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];

        List<PRISM_Inspection__c> recentInspections = [
            SELECT WindSpeedMPH__c, HumidityPercent__c, TemperatureFahrenheit__c,
                   FireDangerLevel__c, RedFlagWarning__c, NearestActiveFireMiles__c
            FROM PRISM_Inspection__c
            WHERE Attachment__r.Structure__r.ServiceTerritory__c =
                  :assets[0].Circuit__r.Id
            ORDER BY InspectionDate__c DESC
            LIMIT 5
        ];

        Decimal defectScore  = calcDefectScore(defects);
        Decimal weatherScore = calcWeatherScore(recentInspections,
                                                assets[0].Circuit__r.ServiceTerritory__r.ActiveFireNearby__c,
                                                assets[0].Circuit__r.ServiceTerritory__r.NearestActiveFireMiles__c);
        Decimal ageScore     = calcAgeScore(assets[0].InstallYear__c);
        Decimal compScore    = calcComponentScore(assets[0].ComponentType__c);

        Decimal composite = (defectScore  * WEIGHT_DEFECT)
                          + (weatherScore * WEIGHT_WEATHER)
                          + (ageScore     * WEIGHT_ASSET_AGE)
                          + (compScore    * WEIGHT_COMP_TYPE);

        composite = composite.setScale(2, RoundingMode.HALF_UP);

        // Find or create the risk score record
        PRISM_WildfireRiskScore__c wrs;
        List<PRISM_WildfireRiskScore__c> existing = assets[0].WildfireRiskScores__r;
        if (!existing.isEmpty()) {
            wrs = existing[0];
            wrs.PreviousScore__c = wrs.Score__c;
        } else {
            wrs = new PRISM_WildfireRiskScore__c(Asset__c = assetId);
        }

        wrs.Score__c          = composite;
        wrs.Tier__c           = getTier(composite);
        wrs.CalculatedDate__c = System.now();
        wrs.ScoreFactors__c   = buildFactorsJSON(defectScore, weatherScore, ageScore, compScore);

        upsert wrs;
        return wrs;
    }

    /**
     * Bulk scoring — called by batch job.
     */
    public static void scoreAssets(List<Id> assetIds) {
        for (Id aid : assetIds) {
            scoreAsset(aid);
        }
    }

    // ── Private helpers ────────────────────────────────────────────────────

    private static Decimal calcDefectScore(List<PRISM_DefectFinding__c> defects) {
        if (defects.isEmpty()) return 0;
        Decimal total = 0;
        for (PRISM_DefectFinding__c d : defects) {
            Decimal sev = 0;
            if (d.Severity__c == '1 - Imminent Hazard') sev = 100;
            else if (d.Severity__c == '2 - Priority')   sev = 70;
            else if (d.Severity__c == '3 - Routine')    sev = 35;
            else if (d.Severity__c == '4 - Monitor')    sev = 15;

            // Vegetation encroachment adds wildfire-specific weight
            if (d.DefectType__c == 'Vegetation Encroachment') sev = Math.min(sev * 1.25, 100);
            total += sev;
        }
        return Math.min(total / defects.size(), 100);
    }

    private static Decimal calcWeatherScore(List<PRISM_Inspection__c> inspections,
                                             Boolean activeFire, Decimal nearestFireMiles) {
        if (inspections.isEmpty() && activeFire == false) return 0;
        Decimal score = 0;

        if (activeFire == true) {
            score += 40;
            if (nearestFireMiles != null && nearestFireMiles < 5)  score += 40;
            else if (nearestFireMiles != null && nearestFireMiles < 15) score += 20;
        }

        if (!inspections.isEmpty()) {
            PRISM_Inspection__c latest = inspections[0];
            if (latest.RedFlagWarning__c) score += 20;
            if (latest.FireDangerLevel__c == 'Extreme')   score += 15;
            else if (latest.FireDangerLevel__c == 'Very High') score += 10;
            else if (latest.FireDangerLevel__c == 'High') score += 5;

            if (latest.WindSpeedMPH__c != null && latest.WindSpeedMPH__c > 35) score += 10;
            if (latest.HumidityPercent__c != null && latest.HumidityPercent__c < 15) score += 10;
            if (latest.TemperatureFahrenheit__c != null && latest.TemperatureFahrenheit__c > 90) score += 5;
        }

        return Math.min(score, 100);
    }

    private static Decimal calcAgeScore(Decimal installYear) {
        if (installYear == null) return 50;
        Integer age = System.today().year() - installYear.intValue();
        if (age >= 50) return 100;
        if (age >= 40) return 80;
        if (age >= 30) return 60;
        if (age >= 20) return 40;
        if (age >= 10) return 20;
        return 5;
    }

    private static Decimal calcComponentScore(String componentType) {
        if (componentType == 'Conductor')        return 90;
        if (componentType == 'Insulator')         return 70;
        if (componentType == 'Fuse')              return 60;
        if (componentType == 'Recloser')          return 50;
        if (componentType == 'Voltage Regulator') return 40;
        if (componentType == 'Capacitor Bank')    return 30;
        return 20;
    }

    private static String getTier(Decimal score) {
        if (score >= 80) return 'Tier 1 - Extreme';
        if (score >= 60) return 'Tier 2 - High';
        if (score >= 40) return 'Tier 3 - Elevated';
        if (score >= 20) return 'Tier 4 - Moderate';
        return 'Tier 5 - Low';
    }

    private static String buildFactorsJSON(Decimal def, Decimal weather, Decimal age, Decimal comp) {
        return JSON.serialize(new Map<String, Object>{
            'defectScore'    => def,
            'weatherScore'   => weather,
            'ageScore'       => age,
            'componentScore' => comp,
            'calculatedAt'   => String.valueOf(System.now())
        });
    }
}
