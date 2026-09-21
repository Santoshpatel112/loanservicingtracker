/**
 * @description       : LWC Controller for Finspectra Prizm Loan Servicing & Repayment Platform.
 *                      Enforces strict role-based authentication and separate portal routing:
 *                      - Administrator (santoshpatelvns5@gmail.com) ➔ Admin CRM Master Center ONLY
 *                      - Regular Borrower ➔ Borrower Self-Service Portal ONLY
 * @author            : Santosh Patel (santoshpatelvns5@gmail.com)
 * @created           : 2026
 * @last modified on  : 2026-09-21
 **/
import { LightningElement, api, wire, track } from 'lwc';
import loginUser                from '@salesforce/apex/LoanController.loginUser';
import registerUser             from '@salesforce/apex/LoanController.registerUser';
import getLoanSchedules         from '@salesforce/apex/LoanController.getLoanSchedules';
import getLoanDetails           from '@salesforce/apex/LoanController.getLoanDetails';
import getLoanSummaryStats       from '@salesforce/apex/LoanController.getLoanSummaryStats';
import getBorrowerLoans         from '@salesforce/apex/LoanController.getBorrowerLoans';
import getAdminPortfolioMetrics from '@salesforce/apex/LoanController.getAdminPortfolioMetrics';
import getAllLoans              from '@salesforce/apex/LoanController.getAllLoans';
import createLoanApplication    from '@salesforce/apex/LoanController.createLoanApplication';
import updateLoanStatus         from '@salesforce/apex/LoanController.updateLoanStatus';
import updateBorrowerProfile    from '@salesforce/apex/LoanController.updateBorrowerProfile';
import markAsPaid               from '@salesforce/apex/LoanController.markAsPaid';
import runReminderBatchNow      from '@salesforce/apex/LoanController.runReminderBatchNow';
import { refreshApex }          from '@salesforce/apex';

const TOAST_DURATION_MS = 4500;
const CURRENCY_LOCALE   = 'en-IN';
const ADMIN_EMAIL       = 'santoshpatelvns5@gmail.com';

export default class LoanServicingDashboard extends LightningElement {

    // ─── Public API ──────────────────────────────────────────────────────────
    @api recordId;

    // ─── Authentication & Session State ──────────────────────────────────────
    @track isAuthenticated   = false;
    @track currentUser       = null; // { email, name, role, isAdmin, title }
    @track authMode          = 'login'; // 'login' | 'register'
    @track loginEmail        = '';
    @track loginPassword     = '';
    @track regName           = '';
    @track regEmail          = '';
    @track regPhone          = '';
    @track regPassword       = '';

    // ─── Common UI State ─────────────────────────────────────────────────────
    @track selectedLoanId    = null;
    @track isLoading         = false;
    @track showToast         = false;
    @track toastTitle        = '';
    @track toastMessage      = '';
    @track toastSuccess      = true;
    @track processingIds     = new Set();

    // ─── Borrower Portal State ───────────────────────────────────────────────
    @track schedules         = [];
    @track filteredSchedules  = [];
    @track loanDetails       = null;
    @track summaryStats      = null;
    @track borrowerLoans     = [];
    @track searchTerm        = '';
    @track activeFilter      = 'All';

    // ─── Admin CRM State ─────────────────────────────────────────────────────
    @track adminMetrics      = null;
    @track allLoans          = [];
    @track adminSearchTerm   = '';
    @track adminFilterStatus = 'All';

    // ─── Modals State ────────────────────────────────────────────────────────
    @track showApplyModal    = false;
    @track applyForm         = {
        borrowerName: '',
        borrowerEmail: '',
        principal: 500000,
        interestRate: 10.5,
        tenure: 12,
        loanType: 'Personal Loan'
    };

    @track showEditModal     = false;
    @track editForm          = {
        loanId: null,
        borrowerName: '',
        borrowerEmail: '',
        principal: 0,
        interestRate: 0,
        tenure: 0,
        loanType: ''
    };

    @track showDrilldownModal    = false;
    @track drilldownLoanId       = null;
    @track drilldownLoanName     = '';
    @track drilldownBorrower     = '';
    @track drilldownSchedules    = [];

    // Wire references
    _wiredSchedulesResult;
    _wiredDetailsResult;
    _wiredStatsResult;
    _wiredBorrowerLoansResult;
    _wiredAdminMetricsResult;
    _wiredAllLoansResult;
    _toastTimer;

    // ─── Lifecycle ───────────────────────────────────────────────────────────
    connectedCallback() {
        if (this.recordId) {
            this.selectedLoanId = this.recordId;
        }
    }

    get adminEmail() {
        return ADMIN_EMAIL;
    }

    get currentLoanId() {
        return this.selectedLoanId || this.recordId;
    }

    get currentUserEmail() {
        return (this.currentUser && this.currentUser.email) || '';
    }

    get currentUserName() {
        return (this.currentUser && this.currentUser.name) || 'User';
    }

    get isAdminSession() {
        return this.currentUser && this.currentUser.isAdmin === true;
    }

    get isLoginMode() {
        return this.authMode === 'login';
    }

    get loginTabClass() {
        return this.isLoginMode ? 'ps-auth-tab ps-auth-tab-active' : 'ps-auth-tab';
    }

    get registerTabClass() {
        return !this.isLoginMode ? 'ps-auth-tab ps-auth-tab-active' : 'ps-auth-tab';
    }

    get userInitials() {
        const name = this.currentUserName;
        return name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase();
    }

    // ─── Authentication Handlers ─────────────────────────────────────────────

    handleSwitchToLogin() {
        this.authMode = 'login';
    }

    handleSwitchToRegister() {
        this.authMode = 'register';
    }

    handleLoginEmailChange(e)    { this.loginEmail = e.target.value; }
    handleLoginPasswordChange(e) { this.loginPassword = e.target.value; }
    handleLoginKeyDown(e) {
        if (e.key === 'Enter') {
            this.handleLoginSubmit();
        }
    }

    handleRegNameChange(e)     { this.regName = e.target.value; }
    handleRegEmailChange(e)    { this.regEmail = e.target.value; }
    handleRegPhoneChange(e)    { this.regPhone = e.target.value; }
    handleRegPasswordChange(e) { this.regPassword = e.target.value; }

    handleQuickLoginAdmin() {
        this.loginEmail    = ADMIN_EMAIL;
        this.loginPassword = 'AdminPassword123!';
        this.handleLoginSubmit();
    }

    handleQuickLoginBorrower() {
        this.loginEmail    = 'priya.sharma@example.com';
        this.loginPassword = 'BorrowerPassword123!';
        this.handleLoginSubmit();
    }

    handleLoginSubmit() {
        if (!this.loginEmail || !this.loginPassword) {
            this._showToast('Missing Credentials', 'Please enter both Email and Password.', false);
            return;
        }

        this.isLoading = true;
        loginUser({ email: this.loginEmail, password: this.loginPassword })
            .then(profile => {
                this.currentUser     = profile;
                this.isAuthenticated = true;
                
                if (profile.isAdmin) {
                    this._showToast(
                        'Welcome Administrator',
                        `Logged in as Master Administrator (${profile.email}). Admin CRM activated.`,
                        true
                    );
                } else {
                    this._showToast(
                        'Welcome Back',
                        `Logged in as ${profile.name}. Borrower Portal activated.`,
                        true
                    );
                }
                return this._refreshAll();
            })
            .catch(error => {
                this._showToast('Authentication Error', this._extractError(error), false);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleRegisterSubmit() {
        if (!this.regName || !this.regEmail || !this.regPassword) {
            this._showToast('Missing Info', 'Full Name, Email, and Password are required.', false);
            return;
        }

        this.isLoading = true;
        registerUser({
            fullName: this.regName,
            email: this.regEmail,
            password: this.regPassword,
            phone: this.regPhone
        })
            .then(profile => {
                this.currentUser     = profile;
                this.isAuthenticated = true;
                this._showToast(
                    'Account Created',
                    `Welcome ${profile.name}! Your account has been registered successfully.`,
                    true
                );
                return this._refreshAll();
            })
            .catch(error => {
                this._showToast('Registration Error', this._extractError(error), false);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleLogout() {
        this.isAuthenticated = false;
        this.currentUser     = null;
        this.loginEmail      = '';
        this.loginPassword   = '';
        this._showToast('Logged Out', 'You have been signed out securely.', true);
    }

    // ─── Wire Adapters ───────────────────────────────────────────────────────

    @wire(getLoanDetails, { loanId: '$currentLoanId' })
    wiredLoanDetails(result) {
        this._wiredDetailsResult = result;
        if (result.data) {
            this.loanDetails = result.data;
            if (!this.selectedLoanId) {
                this.selectedLoanId = result.data.Id;
            }
        }
    }

    @wire(getLoanSchedules, { loanId: '$currentLoanId' })
    wiredSchedules(result) {
        this._wiredSchedulesResult = result;
        if (result.data) {
            this.schedules = this._enrichSchedules(result.data);
            this._applyFilters();
        } else if (result.error) {
            this.schedules = [];
            this.filteredSchedules = [];
        }
    }

    @wire(getLoanSummaryStats, { loanId: '$currentLoanId' })
    wiredStats(result) {
        this._wiredStatsResult = result;
        if (result.data) {
            this.summaryStats = result.data;
        }
    }

    @wire(getBorrowerLoans, { borrowerEmail: '$currentUserEmail' })
    wiredBorrowerLoans(result) {
        this._wiredBorrowerLoansResult = result;
        if (result.data && result.data.length > 0) {
            this.borrowerLoans = result.data;
            if (!this.selectedLoanId || !result.data.find(l => l.Id === this.selectedLoanId)) {
                this.selectedLoanId = result.data[0].Id;
            }
        }
    }

    @wire(getAdminPortfolioMetrics)
    wiredAdminMetrics(result) {
        this._wiredAdminMetricsResult = result;
        if (result.data) {
            this.adminMetrics = result.data;
        }
    }

    @wire(getAllLoans, { filterStatus: '$adminFilterStatus', searchTerm: '$adminSearchTerm' })
    wiredAllLoans(result) {
        this._wiredAllLoansResult = result;
        if (result.data) {
            this.allLoans = result.data;
        }
    }

    // ─── Data Enrichment ────────────────────────────────────────────────────

    _enrichSchedules(rawSchedules) {
        return rawSchedules.map((item, index) => {
            const isPaid    = item.Status__c === 'Paid';
            const isOverdue = item.Status__c === 'Overdue';
            const dueDate   = item.Due_Date__c ? new Date(item.Due_Date__c + 'T00:00:00') : null;

            return {
                ...item,
                rowIndex          : index + 1,
                isPaid            : isPaid,
                isProcessing      : this.processingIds.has(item.Id),
                formattedEmi      : this._formatCurrency(item.EMI_Amount__c),
                formattedPrincipal: this._formatCurrency(item.Principal_Component__c),
                formattedInterest : this._formatCurrency(item.Interest_Component__c),
                formattedBalance  : this._formatCurrency(item.Outstanding_Balance__c),
                dueDateFormatted  : dueDate ? dueDate.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' }) : '—',
                statusBadgeClass  : this._getStatusBadgeClass(item.Status__c),
                rowClass          : isPaid ? 'ps-row ps-row-paid' : (isOverdue ? 'ps-row ps-row-overdue' : 'ps-row')
            };
        });
    }

    // ─── Real-Time Live EMI Calculator Preview ───────────────────────────────

    get previewEMI() {
        const p = parseFloat(this.applyForm.principal) || 0;
        const r = (parseFloat(this.applyForm.interestRate) || 0) / 12 / 100;
        const n = parseInt(this.applyForm.tenure, 10) || 1;

        if (p <= 0 || n <= 0) return '0.00';
        if (r === 0) return this._formatCurrency(p / n);

        const pow = Math.pow(1 + r, n);
        const emi = (p * r * pow) / (pow - 1);
        return this._formatCurrency(emi);
    }

    get previewInterest() {
        const p = parseFloat(this.applyForm.principal) || 0;
        const r = (parseFloat(this.applyForm.interestRate) || 0) / 12 / 100;
        const n = parseInt(this.applyForm.tenure, 10) || 1;

        if (p <= 0 || n <= 0) return '0.00';
        if (r === 0) return '0.00';

        const pow = Math.pow(1 + r, n);
        const emi = (p * r * pow) / (pow - 1);
        const totalPayable = emi * n;
        return this._formatCurrency(totalPayable - p);
    }

    get previewTotalPayable() {
        const p = parseFloat(this.applyForm.principal) || 0;
        const r = (parseFloat(this.applyForm.interestRate) || 0) / 12 / 100;
        const n = parseInt(this.applyForm.tenure, 10) || 1;

        if (p <= 0 || n <= 0) return '0.00';
        if (r === 0) return this._formatCurrency(p);

        const pow = Math.pow(1 + r, n);
        const emi = (p * r * pow) / (pow - 1);
        return this._formatCurrency(emi * n);
    }

    // ─── Borrower Actions ────────────────────────────────────────────────────

    handleLoanSelect(event) {
        this.selectedLoanId = event.target.value;
    }

    handleMarkPaid(event) {
        const scheduleId   = event.currentTarget.dataset.id;
        const scheduleName = event.currentTarget.dataset.name;

        this.processingIds = new Set([...this.processingIds, scheduleId]);
        this.schedules = this._enrichSchedules(this.schedules);
        this._applyFilters();

        markAsPaid({ scheduleId })
            .then(() => {
                this._showToast(
                    'Payment Successful',
                    `${scheduleName} marked as Paid. Instant confirmation receipt email dispatched to borrower!`,
                    true
                );
                return this._refreshAll();
            })
            .catch(error => {
                this._showToast('Payment Failed', this._extractError(error), false);
            })
            .finally(() => {
                this.processingIds.delete(scheduleId);
                this.schedules = this._enrichSchedules(this.schedules);
                this._applyFilters();
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

    _setFilter(filter) {
        this.activeFilter = filter;
        this._applyFilters();
    }

    _applyFilters() {
        let result = this.schedules;
        if (this.activeFilter !== 'All') {
            result = result.filter(s => s.Status__c === this.activeFilter);
        }
        const term = (this.searchTerm || '').toLowerCase().trim();
        if (term) {
            result = result.filter(s =>
                (s.Name || '').toLowerCase().includes(term) ||
                (s.Status__c || '').toLowerCase().includes(term)
            );
        }
        this.filteredSchedules = result;
    }

    // ─── Admin CRM Actions ───────────────────────────────────────────────────

    handleAdminSearch(event) {
        this.adminSearchTerm = event.target.value;
    }

    handleAdminFilterAll()      { this.adminFilterStatus = 'All'; }
    handleAdminFilterPending()  { this.adminFilterStatus = 'Pending'; }
    handleAdminFilterApproved() { this.adminFilterStatus = 'Approved'; }
    handleAdminFilterClosed()   { this.adminFilterStatus = 'Closed'; }

    handleQuickApprove(event) {
        const loanId = event.currentTarget.dataset.id;
        this.isLoading = true;

        updateLoanStatus({ loanId, newStatus: 'Approved', adminComments: `Approved by Administrator (${ADMIN_EMAIL})` })
            .then(() => {
                this._showToast('Loan Approved', 'Repayment schedule generated & approval notification dispatched!', true);
                return this._refreshAll();
            })
            .catch(error => {
                this._showToast('Approval Error', this._extractError(error), false);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleQuickReject(event) {
        const loanId = event.currentTarget.dataset.id;
        this.isLoading = true;

        updateLoanStatus({ loanId, newStatus: 'Rejected', adminComments: 'Application did not meet underwriting criteria.' })
            .then(() => {
                this._showToast('Loan Rejected', 'Application rejected & status notification email sent.', false);
                return this._refreshAll();
            })
            .catch(error => {
                this._showToast('Rejection Error', this._extractError(error), false);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleRunBatchReminders() {
        this.isLoading = true;
        runReminderBatchNow({ daysAhead: 3 })
            .then(message => {
                this._showToast('Batch Service Initiated', message, true);
            })
            .catch(error => {
                this._showToast('Batch Error', this._extractError(error), false);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleViewScheduleDrilldown(event) {
        const loanId = event.currentTarget.dataset.id;
        this.drilldownLoanId = loanId;
        const targetLoan = this.allLoans.find(l => l.Id === loanId);
        if (targetLoan) {
            this.drilldownLoanName = targetLoan.Name;
            this.drilldownBorrower = targetLoan.Borrower_Name__c;
        }

        this.isLoading = true;
        getLoanSchedules({ loanId })
            .then(data => {
                this.drilldownSchedules = this._enrichSchedules(data);
                this.showDrilldownModal = true;
            })
            .catch(error => {
                this._showToast('Ledger Error', this._extractError(error), false);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleCloseDrilldownModal() {
        this.showDrilldownModal = false;
        this.drilldownSchedules = [];
    }

    handleDrilldownMarkPaid(event) {
        const scheduleId = event.currentTarget.dataset.id;
        this.isLoading = true;

        markAsPaid({ scheduleId })
            .then(() => {
                this._showToast('Payment Recorded', 'Installment updated to Paid & confirmation receipt sent.', true);
                return getLoanSchedules({ loanId: this.drilldownLoanId });
            })
            .then(data => {
                this.drilldownSchedules = this._enrichSchedules(data);
                return this._refreshAll();
            })
            .catch(error => {
                this._showToast('Error', this._extractError(error), false);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ─── Modal 1: Loan Application ───────────────────────────────────────────

    handleOpenApplyModal() {
        // Pre-fill borrower name and email from current session
        this.applyForm.borrowerName  = this.currentUserName;
        this.applyForm.borrowerEmail = this.currentUserEmail;
        this.showApplyModal = true;
    }

    handleCloseApplyModal() {
        this.showApplyModal = false;
    }

    handleApplyInput(event) {
        const field = event.target.dataset.field;
        this.applyForm = { ...this.applyForm, [field]: event.target.value };
    }

    handleSubmitApplication() {
        const { borrowerName, borrowerEmail, principal, interestRate, tenure, loanType } = this.applyForm;

        if (!borrowerName || !borrowerEmail) {
            this._showToast('Missing Info', 'Please enter Borrower Name and Email.', false);
            return;
        }

        this.isLoading = true;
        createLoanApplication({
            name: '',
            borrowerName,
            borrowerEmail,
            principal: parseFloat(principal),
            interestRate: parseFloat(interestRate),
            tenure: parseInt(tenure, 10),
            loanType
        })
            .then(newLoan => {
                this._showToast('Application Submitted', `Loan ${newLoan.Name} created in Pending status.`, true);
                this.showApplyModal = false;
                this.selectedLoanId = newLoan.Id;
                return this._refreshAll();
            })
            .catch(error => {
                this._showToast('Submission Failed', this._extractError(error), false);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ─── Modal 2: Edit Profile & Terms ───────────────────────────────────────

    handleOpenEditModal() {
        if (!this.loanDetails) return;
        this.editForm = {
            loanId: this.loanDetails.Id,
            borrowerName: this.loanDetails.Borrower_Name__c || '',
            borrowerEmail: this.loanDetails.Borrower_Email__c || '',
            principal: this.loanDetails.Principal_Amount__c || 0,
            interestRate: this.loanDetails.Interest_Rate__c || 0,
            tenure: this.loanDetails.Tenure_Months__c || 0,
            loanType: this.loanDetails.Loan_Type__c || ''
        };
        this.showEditModal = true;
    }

    handleAdminOpenEdit(event) {
        const loanId = event.currentTarget.dataset.id;
        const targetLoan = this.allLoans.find(l => l.Id === loanId);
        if (!targetLoan) return;

        this.editForm = {
            loanId: targetLoan.Id,
            borrowerName: targetLoan.Borrower_Name__c || '',
            borrowerEmail: targetLoan.Borrower_Email__c || '',
            principal: targetLoan.Principal_Amount__c || 0,
            interestRate: targetLoan.Interest_Rate__c || 0,
            tenure: targetLoan.Tenure_Months__c || 0,
            loanType: targetLoan.Loan_Type__c || ''
        };
        this.showEditModal = true;
    }

    handleCloseEditModal() {
        this.showEditModal = false;
    }

    handleEditInput(event) {
        const field = event.target.dataset.field;
        this.editForm = { ...this.editForm, [field]: event.target.value };
    }

    handleSaveProfileChanges() {
        const { loanId, borrowerName, borrowerEmail, principal, interestRate, tenure, loanType } = this.editForm;

        this.isLoading = true;
        updateBorrowerProfile({
            loanId,
            borrowerName,
            borrowerEmail,
            principal: parseFloat(principal),
            interestRate: parseFloat(interestRate),
            tenure: parseInt(tenure, 10),
            loanType
        })
            .then(() => {
                this._showToast('Profile Updated', 'Details saved & transactional alert email sent to borrower.', true);
                this.showEditModal = false;
                return this._refreshAll();
            })
            .catch(error => {
                this._showToast('Update Failed', this._extractError(error), false);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // ─── Refresh Helpers ─────────────────────────────────────────────────────

    async _refreshAll() {
        await Promise.all([
            refreshApex(this._wiredSchedulesResult),
            refreshApex(this._wiredDetailsResult),
            refreshApex(this._wiredStatsResult),
            refreshApex(this._wiredBorrowerLoansResult),
            refreshApex(this._wiredAdminMetricsResult),
            refreshApex(this._wiredAllLoansResult)
        ]);
    }

    // ─── Toast Handling ──────────────────────────────────────────────────────

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

    handleCloseToast() {
        this.showToast = false;
        clearTimeout(this._toastTimer);
    }

    // ─── Formatting & Computed Properties ────────────────────────────────────

    _formatCurrency(val) {
        if (val == null) return '0.00';
        return new Intl.NumberFormat(CURRENCY_LOCALE, {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(val);
    }

    _getStatusBadgeClass(status) {
        const base = 'ps-status-pill ';
        switch (status) {
            case 'Paid':
            case 'Approved': return base + 'ps-status-approved';
            case 'Overdue':
            case 'Rejected': return base + 'ps-status-rejected';
            case 'Closed':   return base + 'ps-status-closed';
            default:         return base + 'ps-status-pending';
        }
    }

    _extractError(err) {
        if (err && err.body && err.body.message) return err.body.message;
        if (err && err.message) return err.message;
        return 'An unexpected system error occurred.';
    }

    get currentBorrowerName() {
        return (this.loanDetails && this.loanDetails.Borrower_Name__c) || this.currentUserName;
    }

    get currentLoanType() {
        return (this.loanDetails && this.loanDetails.Loan_Type__c) || 'Personal Loan';
    }

    get borrowerInitials() {
        const name = this.currentBorrowerName;
        return name.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase();
    }

    get hasMultipleLoans() {
        return this.borrowerLoans && this.borrowerLoans.length > 1;
    }

    get hasSchedules() {
        return this.filteredSchedules && this.filteredSchedules.length > 0;
    }

    get scheduleCount() {
        return this.schedules ? this.schedules.length : 0;
    }

    get progressBarStyle() {
        const pct = (this.summaryStats && this.summaryStats.progressPct) || 0;
        return `width: ${pct}%`;
    }

    get loanStatusLabel() {
        return (this.loanDetails && this.loanDetails.Status__c) || 'Pending';
    }

    get statusBadgeClass() {
        return this._getStatusBadgeClass(this.loanStatusLabel);
    }

    get formattedPrincipal() {
        return this.loanDetails ? this._formatCurrency(this.loanDetails.Principal_Amount__c) : '0.00';
    }

    get formattedEMI() {
        if (!this.schedules || this.schedules.length === 0) return '0.00';
        return this.schedules[0].formattedEmi;
    }

    get formattedTotalPaid() {
        return this.summaryStats ? this._formatCurrency(this.summaryStats.totalPaid) : '0.00';
    }

    get formattedTotalPending() {
        return this.summaryStats ? this._formatCurrency(this.summaryStats.totalPending) : '0.00';
    }

    get formattedTotalPayable() {
        if (!this.schedules || this.schedules.length === 0) return '0.00';
        const total = this.schedules.reduce((sum, s) => sum + (s.EMI_Amount__c || 0), 0);
        return this._formatCurrency(total);
    }

    get formattedAdminDisbursed() {
        return this.adminMetrics ? this._formatCurrency(this.adminMetrics.totalDisbursed) : '0.00';
    }

    get formattedAdminCollected() {
        return this.adminMetrics ? this._formatCurrency(this.adminMetrics.totalCollected) : '0.00';
    }

    get formattedAdminReceivable() {
        return this.adminMetrics ? this._formatCurrency(this.adminMetrics.totalReceivable) : '0.00';
    }

    get allLoansCount() {
        return this.allLoans ? this.allLoans.length : 0;
    }

    get hasAdminLoans() {
        return this.allLoans && this.allLoans.length > 0;
    }

    get enrichedAdminLoans() {
        return (this.allLoans || []).map(l => ({
            ...l,
            formattedPrincipal: this._formatCurrency(l.Principal_Amount__c),
            statusBadgeClass  : this._getStatusBadgeClass(l.Status__c),
            isPending         : l.Status__c === 'Pending'
        }));
    }

    get toastClass() {
        return this.toastSuccess ? 'ps-toast ps-toast-success' : 'ps-toast ps-toast-error';
    }

    get filterAllClass()     { return this.activeFilter === 'All' ? 'ps-filter-pill ps-filter-pill-active' : 'ps-filter-pill'; }
    get filterPendingClass() { return this.activeFilter === 'Pending' ? 'ps-filter-pill ps-filter-pill-active' : 'ps-filter-pill'; }
    get filterPaidClass()    { return this.activeFilter === 'Paid' ? 'ps-filter-pill ps-filter-pill-active' : 'ps-filter-pill'; }
    get filterOverdueClass() { return this.activeFilter === 'Overdue' ? 'ps-filter-pill ps-filter-pill-active' : 'ps-filter-pill'; }

    get adminFilterAllClass()      { return this.adminFilterStatus === 'All' ? 'ps-filter-pill ps-filter-pill-active' : 'ps-filter-pill'; }
    get adminFilterPendingClass()  { return this.adminFilterStatus === 'Pending' ? 'ps-filter-pill ps-filter-pill-active' : 'ps-filter-pill'; }
    get adminFilterApprovedClass() { return this.adminFilterStatus === 'Approved' ? 'ps-filter-pill ps-filter-pill-active' : 'ps-filter-pill'; }
    get adminFilterClosedClass()   { return this.adminFilterStatus === 'Closed' ? 'ps-filter-pill ps-filter-pill-active' : 'ps-filter-pill'; }

    disconnectedCallback() {
        clearTimeout(this._toastTimer);
    }
}
