/**
 * @description       : LWC Controller for Loan Servicing Dashboard
 *                      Modern Finspectra-style EMI Tracker with KPIs, filtering,
 *                      search, progress tracking, and amortization breakdown.
 * @author            : Santosh Patel
 * @created           : 2026
 * @last modified on  : 2026-09-21
 **/
import { LightningElement, api, wire, track } from 'lwc';
import getLoanSchedules   from '@salesforce/apex/LoanController.getLoanSchedules';
import getLoanDetails     from '@salesforce/apex/LoanController.getLoanDetails';
import getLoanSummaryStats from '@salesforce/apex/LoanController.getLoanSummaryStats';
import markAsPaid         from '@salesforce/apex/LoanController.markAsPaid';
import { refreshApex }    from '@salesforce/apex';

// ─── Constants ──────────────────────────────────────────────────────────────
const TOAST_DURATION_MS = 4000;
const CURRENCY_LOCALE   = 'en-IN';

export default class LoanServicingDashboard extends LightningElement {

    // ── Public Properties ────────────────────────────────────────────────────
    @api recordId;

    // ── Tracked State ────────────────────────────────────────────────────────
    @track schedules        = [];
    @track filteredSchedules = [];
    @track loanDetails      = null;
    @track summaryStats     = null;
    @track isLoading        = false;
    @track hasError         = false;
    @track errorMessage     = '';
    @track activeFilter     = 'All';
    @track searchTerm       = '';
    @track showToast        = false;
    @track toastTitle       = '';
    @track toastMessage     = '';
    @track toastSuccess     = true;
    @track processingIds    = new Set();

    // Wire result references for refreshApex
    _wiredSchedulesResult;
    _wiredStatsResult;
    _wiredDetailsResult;
    _toastTimer;

    // ─── Wire: Loan Details ─────────────────────────────────────────────────
    @wire(getLoanDetails, { loanId: '$recordId' })
    wiredLoanDetails(result) {
        this._wiredDetailsResult = result;
        if (result.data) {
            this.loanDetails = result.data;
        } else if (result.error) {
            console.error('getLoanDetails error:', result.error);
        }
    }

    // ─── Wire: Repayment Schedules ──────────────────────────────────────────
    @wire(getLoanSchedules, { loanId: '$recordId' })
    wiredSchedules(result) {
        this._wiredSchedulesResult = result;
        this.isLoading = true;

        if (result.data) {
            this.hasError = false;
            this.schedules = this._enrichSchedules(result.data);
            this._applyFilters();
            this.isLoading = false;
        } else if (result.error) {
            this.hasError    = true;
            this.errorMessage = this._extractError(result.error);
            this.schedules   = [];
            this.filteredSchedules = [];
            this.isLoading   = false;
        }
    }

    // ─── Wire: Summary Stats ────────────────────────────────────────────────
    @wire(getLoanSummaryStats, { loanId: '$recordId' })
    wiredStats(result) {
        this._wiredStatsResult = result;
        if (result.data) {
            this.summaryStats = result.data;
        } else if (result.error) {
            this.summaryStats = null;
        }
    }

    // ─── Data Enrichment ────────────────────────────────────────────────────

    /**
     * Enriches raw schedule records with display-ready properties.
     */
    _enrichSchedules(rawSchedules) {
        return rawSchedules.map((item, index) => {
            const dueDate   = item.Due_Date__c ? new Date(item.Due_Date__c + 'T00:00:00') : null;
            const isPaid    = item.Status__c === 'Paid';
            const isOverdue = item.Status__c === 'Overdue';

            return {
                ...item,
                rowIndex          : index + 1,
                isPaid            : isPaid,
                isProcessing      : this.processingIds.has(item.Id),
                formattedEmi      : this._formatCurrency(item.EMI_Amount__c),
                formattedPrincipal: this._formatCurrency(item.Principal_Component__c),
                formattedInterest : this._formatCurrency(item.Interest_Component__c),
                formattedBalance  : this._formatCurrency(item.Outstanding_Balance__c),
                dueDateDay        : dueDate ? dueDate.getDate().toString().padStart(2, '0') : '--',
                dueDateMonthYear  : dueDate ? this._formatMonthYear(dueDate) : '--',
                statusBadgeClass  : this._getStatusBadgeClass(item.Status__c),
                rowClass          : isPaid ? 'ps-row ps-row-paid' : isOverdue ? 'ps-row ps-row-overdue' : 'ps-row',
                actionButtonId    : `pay-btn-${item.Id}`
            };
        });
    }

    // ─── Event Handlers ─────────────────────────────────────────────────────

    handleMarkPaid(event) {
        const scheduleId   = event.currentTarget.dataset.id;
        const scheduleName = event.currentTarget.dataset.name;

        // Optimistic UI: mark as processing
        this.processingIds = new Set([...this.processingIds, scheduleId]);
        this._updateProcessingState(scheduleId, true);

        markAsPaid({ scheduleId })
            .then(() => {
                this._showToast('Payment Recorded', `${scheduleName} marked as Paid successfully!`, true);
                return this._refreshAll();
            })
            .catch(error => {
                this._showToast('Update Failed', this._extractError(error), false);
                this.processingIds.delete(scheduleId);
                this._updateProcessingState(scheduleId, false);
            });
    }

    handleRefresh() {
        this.isLoading = true;
        this._refreshAll().then(() => {
            this.isLoading = false;
        });
    }

    handleSearch(event) {
        this.searchTerm = event.target.value;
        this._applyFilters();
    }

    handleFilterAll()     { this._setFilter('All'); }
    handleFilterPending() { this._setFilter('Pending'); }
    handleFilterPaid()    { this._setFilter('Paid'); }
    handleFilterOverdue() { this._setFilter('Overdue'); }

    handleCloseToast() {
        this.showToast = false;
        clearTimeout(this._toastTimer);
    }

    // ─── Private Helpers ─────────────────────────────────────────────────────

    _setFilter(filter) {
        this.activeFilter = filter;
        this._applyFilters();
    }

    _applyFilters() {
        let result = this.schedules;

        // Status filter
        if (this.activeFilter !== 'All') {
            result = result.filter(s => s.Status__c === this.activeFilter);
        }

        // Search filter
        const term = (this.searchTerm || '').toLowerCase().trim();
        if (term) {
            result = result.filter(s =>
                (s.Name || '').toLowerCase().includes(term) ||
                (s.Status__c || '').toLowerCase().includes(term)
            );
        }

        this.filteredSchedules = result;
    }

    _updateProcessingState(scheduleId, isProcessing) {
        this.filteredSchedules = this.filteredSchedules.map(s => ({
            ...s,
            isProcessing: s.Id === scheduleId ? isProcessing : s.isProcessing
        }));
    }

    async _refreshAll() {
        await Promise.all([
            refreshApex(this._wiredSchedulesResult),
            refreshApex(this._wiredStatsResult),
            refreshApex(this._wiredDetailsResult)
        ]);
    }

    _showToast(title, message, isSuccess) {
        clearTimeout(this._toastTimer);
        this.toastTitle   = title;
        this.toastMessage = message;
        this.toastSuccess = isSuccess;
        this.showToast    = true;

        this._toastTimer = setTimeout(() => {
            this.showToast = false;
        }, TOAST_DURATION_MS);
    }

    _formatCurrency(value) {
        if (value == null) return '—';
        return new Intl.NumberFormat(CURRENCY_LOCALE, {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(value);
    }

    _formatMonthYear(date) {
        return date.toLocaleDateString('en-IN', { month: 'short', year: 'numeric' });
    }

    _getStatusBadgeClass(status) {
        const base = 'ps-badge ';
        switch (status) {
            case 'Paid':    return base + 'ps-badge-paid';
            case 'Overdue': return base + 'ps-badge-overdue';
            default:        return base + 'ps-badge-pending';
        }
    }

    _extractError(error) {
        if (error && error.body && error.body.message) return error.body.message;
        if (error && error.message) return error.message;
        return 'An unexpected error occurred.';
    }

    // ─── Computed Properties ─────────────────────────────────────────────────

    get dashboardClass() {
        return 'ps-dashboard';
    }

    get hasSchedules() {
        return this.filteredSchedules && this.filteredSchedules.length > 0;
    }

    get scheduleCount() {
        return this.schedules ? this.schedules.length : 0;
    }

    get filteredCount() {
        return this.filteredSchedules ? this.filteredSchedules.length : 0;
    }

    get progressBarStyle() {
        const pct = (this.summaryStats && this.summaryStats.progressPct) || 0;
        return `width: ${pct}%`;
    }

    get loanStatusLabel() {
        return this.loanDetails ? (this.loanDetails.Status__c || 'Unknown') : 'Loading...';
    }

    get statusBadgeClass() {
        const status = this.loanDetails ? this.loanDetails.Status__c : '';
        if (status === 'Approved') return 'ps-loan-status ps-status-approved';
        if (status === 'Closed')   return 'ps-loan-status ps-status-closed';
        return 'ps-loan-status ps-status-pending';
    }

    get formattedPrincipal() {
        return this.loanDetails ? this._formatCurrency(this.loanDetails.Principal_Amount__c) : '—';
    }

    get formattedEMI() {
        if (!this.schedules || this.schedules.length === 0) return '—';
        return this._formatCurrency(this.schedules[0].EMI_Amount__c);
    }

    get formattedTotalPaid() {
        return this.summaryStats ? this._formatCurrency(this.summaryStats.totalPaid) : '0.00';
    }

    get formattedTotalPending() {
        return this.summaryStats ? this._formatCurrency(this.summaryStats.totalPending) : '0.00';
    }

    get formattedTotalPayable() {
        if (!this.schedules || this.schedules.length === 0) return '—';
        const total = this.schedules.reduce((sum, s) => sum + (s.EMI_Amount__c || 0), 0);
        return this._formatCurrency(total);
    }

    get toastClass() {
        return this.toastSuccess ? 'ps-toast ps-toast-success ps-toast-enter' : 'ps-toast ps-toast-error ps-toast-enter';
    }

    get filterAllClass()     { return this._filterTabClass('All'); }
    get filterPendingClass() { return this._filterTabClass('Pending'); }
    get filterPaidClass()    { return this._filterTabClass('Paid'); }
    get filterOverdueClass() { return this._filterTabClass('Overdue'); }

    _filterTabClass(filter) {
        return this.activeFilter === filter ? 'ps-filter-tab ps-filter-tab-active' : 'ps-filter-tab';
    }

    // ─── Disconnected Callback ───────────────────────────────────────────────
    disconnectedCallback() {
        clearTimeout(this._toastTimer);
    }
}
