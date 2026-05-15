import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getQueueEntries from '@salesforce/apex/PRISM_AIPriorityQueueController.getQueueEntries';
import createWorkOrderFromQueue from '@salesforce/apex/PRISM_AIPriorityQueueController.createWorkOrderFromQueue';
import triggerQueueRefresh from '@salesforce/apex/PRISM_AIPriorityQueueController.triggerQueueRefresh';

export default class PrismAIPriorityQueue extends LightningElement {
    @track isLoading = true;
    @track queueEntries = [];
    wiredResult;

    @wire(getQueueEntries)
    wiredQueue(result) {
        this.wiredResult = result;
        if (result.data) {
            this.queueEntries = result.data.map(e => ({
                ...e,
                showRationale : false,
                rowClass      : this.getRowClass(e.WildfireRiskScore__r?.Tier__c),
                scoreClass    : this.getScoreClass(e.CompositeScore__c),
                actionClass   : this.getActionClass(e.RecommendedAction__c)
            }));
            this.isLoading = false;
        } else if (result.error) {
            this.isLoading = false;
            this.showToast('Error', 'Could not load queue.', 'error');
        }
    }

    get hasEntries() { return this.queueEntries.length > 0; }

    getRowClass(tier) {
        const base = 'queue-row slds-p-around_small slds-m-bottom_x-small';
        if (tier === 'Tier 1 - Extreme') return base + ' tier-1';
        if (tier === 'Tier 2 - High')    return base + ' tier-2';
        return base;
    }

    getScoreClass(score) {
        if (score >= 80) return 'score-badge score-extreme';
        if (score >= 60) return 'score-badge score-high';
        if (score >= 40) return 'score-badge score-elevated';
        return 'score-badge score-moderate';
    }

    getActionClass(action) {
        if (action === 'Immediate De-energize' || action === 'Emergency Repair Within 24hrs') {
            return 'action-badge action-critical';
        }
        if (action === 'Schedule Repair This Week') return 'action-badge action-high';
        return 'action-badge action-normal';
    }

    toggleRationale(event) {
        const id = event.target.dataset.id;
        this.queueEntries = this.queueEntries.map(e =>
            e.Id === id ? { ...e, showRationale: !e.showRationale } : e
        );
    }

    handleCreateWO(event) {
        const queueId = event.target.dataset.id;
        createWorkOrderFromQueue({ queueEntryId: queueId })
            .then(() => {
                this.showToast('Success', 'Work Order created.', 'success');
                return refreshApex(this.wiredResult);
            })
            .catch(err => this.showToast('Error', err.body.message, 'error'));
    }

    handleRefresh() {
        this.isLoading = true;
        triggerQueueRefresh()
            .then(() => refreshApex(this.wiredResult))
            .then(() => { this.isLoading = false; })
            .catch(err => {
                this.isLoading = false;
                this.showToast('Error', err.body.message, 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
