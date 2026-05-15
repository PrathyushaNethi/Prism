import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';

import getInspectionData from '@salesforce/apex/PRISM_InspectionController.getInspectionData';
import createWorkOrderFromDefect from '@salesforce/apex/PRISM_InspectionController.createWorkOrderFromDefect';

const FIELDS = [
    'PRISM_Inspection__c.Name',
    'PRISM_Inspection__c.Status__c',
    'PRISM_Inspection__c.WindSpeedMPH__c',
    'PRISM_Inspection__c.HumidityPercent__c',
    'PRISM_Inspection__c.TemperatureFahrenheit__c',
    'PRISM_Inspection__c.FireDangerLevel__c',
    'PRISM_Inspection__c.RedFlagWarning__c',
    'PRISM_Inspection__c.NearestActiveFireMiles__c',
    'PRISM_Inspection__c.Attachment__c'
];

export default class PrismInspectionAssignment extends NavigationMixin(LightningElement) {
    @api recordId;
    @track inspection;
    @track defects = [];
    @track isLoading = true;

    wiredInspectionResult;

    @wire(getInspectionData, { inspectionId: '$recordId' })
    wiredInspection(result) {
        this.wiredInspectionResult = result;
        if (result.data) {
            this.inspection = result.data.inspection;
            this.defects    = result.data.defects.map(d => ({
                ...d,
                severityClass: this.getSeverityClass(d.Severity__c)
            }));
            this.isLoading = false;
        } else if (result.error) {
            this.isLoading = false;
            this.showToast('Error', 'Failed to load inspection data.', 'error');
        }
    }

    get windSpeed()    { return this.inspection?.WindSpeedMPH__c        ?? '--'; }
    get humidity()     { return this.inspection?.HumidityPercent__c     ?? '--'; }
    get temperature()  { return this.inspection?.TemperatureFahrenheit__c ?? '--'; }
    get fireDanger()   { return this.inspection?.FireDangerLevel__c     ?? '--'; }
    get nearestFire()  { return this.inspection?.NearestActiveFireMiles__c ?? '--'; }
    get fireDirection(){ return 'NE'; }  // Would come from external weather API
    get isRedFlag()    { return this.inspection?.RedFlagWarning__c === true; }
    get hasDefects()   { return this.defects && this.defects.length > 0; }

    get statusBadgeClass() {
        const s = this.inspection?.Status__c;
        if (s === 'In Progress') return 'slds-badge slds-theme_warning';
        if (s === 'Completed')   return 'slds-badge slds-theme_success';
        return 'slds-badge';
    }

    getSeverityClass(severity) {
        if (severity === '1 - Imminent Hazard') return 'slds-badge slds-theme_error';
        if (severity === '2 - Priority')         return 'slds-badge slds-theme_warning';
        return 'slds-badge';
    }

    handleCreateWorkOrder(event) {
        const defectId = event.target.dataset.id;
        createWorkOrderFromDefect({ defectId })
            .then(() => {
                this.showToast('Success', 'Work Order created.', 'success');
                return refreshApex(this.wiredInspectionResult);
            })
            .catch(err => {
                this.showToast('Error', err.body.message, 'error');
            });
    }

    handleAddDefect() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'PRISM_DefectFinding__c',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: `Inspection__c=${this.recordId}`
            }
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
