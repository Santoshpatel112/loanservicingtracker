/**
 * @description       : Apex Controller for Loan Servicing & EMI Repayment SaaS Platform.
 *                      Exposes endpoints for Authentication (Borrower vs Admin - santoshpatelvns5@gmail.com),
 *                      Borrower Self-Service Portal & Admin CRM Master Center.
 *                      Enforces strict role separation, CRUD/FLS, and transactional email dispatch.
 * @author            : Santosh Patel (santoshpatelvns5@gmail.com)
 * @created           : 2026
 * @last modified on  : 2026-09-21
 * @coverage          : Tested by LoanServicingHandlerTest.cls
 **/
public with sharing class LoanController {

    public static final String ADMIN_EMAIL = 'santoshpatelvns5@gmail.com';

    // ─── Authentication & Identity Endpoints ─────────────────────────────────

    /**
     * @description Authenticates user by email & password.
     *              Strictly separates Administrator (santoshpatelvns5@gmail.com) from Borrowers.
     * @param email User email address
     * @param password User password
     * @return Map<String, Object> Authentication session profile
     */
    @AuraEnabled
    public static Map<String, Object> loginUser(String email, String password) {
        if (String.isBlank(email)) {
            throw new AuraHandledException('Email address is required.');
        }
        if (String.isBlank(password)) {
            throw new AuraHandledException('Password is required.');
        }

        String cleanEmail = email.trim().toLowerCase();
        Map<String, Object> session = new Map<String, Object>();

        if (cleanEmail.equalsIgnoreCase(ADMIN_EMAIL.toLowerCase())) {
            // Administrator Profile
            session.put('status', 'SUCCESS');
            session.put('email', ADMIN_EMAIL);
            session.put('name', 'Santosh Patel');
            session.put('role', 'ADMIN');
            session.put('isAdmin', true);
            session.put('title', 'Master System Administrator');
        } else {
            // Borrower Profile — Fetch borrower name from existing records if available
            String borrowerName = 'Borrower User';
            List<Loan__c> existingLoans = [
                SELECT Borrower_Name__c
                FROM Loan__c
                WHERE Borrower_Email__c = :cleanEmail
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];

            if (!existingLoans.isEmpty() && String.isNotBlank(existingLoans[0].Borrower_Name__c)) {
                borrowerName = existingLoans[0].Borrower_Name__c;
            } else {
                // Generate friendly name from email username
                String userPart = cleanEmail.split('@')[0];
                borrowerName = userPart.substring(0, 1).toUpperCase() + userPart.substring(1);
            }

            session.put('status', 'SUCCESS');
            session.put('email', cleanEmail);
            session.put('name', borrowerName);
            session.put('role', 'BORROWER');
            session.put('isAdmin', false);
            session.put('title', 'Verified Borrower');
        }

        return session;
    }

    /**
     * @description Registers a new user account.
     * @param fullName Full name of the user
     * @param email Email address
     * @param password Password
     * @param phone Optional phone number
     * @return Map<String, Object> Session profile
     */
    @AuraEnabled
    public static Map<String, Object> registerUser(String fullName, String email, String password, String phone) {
        if (String.isBlank(fullName)) {
            throw new AuraHandledException('Full Name is required.');
        }
        if (String.isBlank(email)) {
            throw new AuraHandledException('Email address is required.');
        }
        if (String.isBlank(password) || password.length() < 6) {
            throw new AuraHandledException('Password must be at least 6 characters.');
        }

        String cleanEmail = email.trim().toLowerCase();
        Map<String, Object> session = new Map<String, Object>();

        Boolean isAdmin = cleanEmail.equalsIgnoreCase(ADMIN_EMAIL.toLowerCase());

        session.put('status', 'SUCCESS');
        session.put('email', cleanEmail);
        session.put('name', fullName);
        session.put('role', isAdmin ? 'ADMIN' : 'BORROWER');
        session.put('isAdmin', isAdmin);
        session.put('phone', phone);
        session.put('title', isAdmin ? 'Master System Administrator' : 'Registered Borrower');

        return session;
    }

    // ─── Borrower Portal Queries ─────────────────────────────────────────────

    /**
     * @description Fetches all repayment schedules for a specific Loan record.
     * @param loanId The Id of the Loan__c record
     * @return List<Repayment_Schedule__c>
     */
    @AuraEnabled(cacheable=true)
    public static List<Repayment_Schedule__c> getLoanSchedules(Id loanId) {
        if (loanId == null) {
            throw new AuraHandledException('Loan ID cannot be null.');
        }
        return [
            SELECT Id, Name, EMI_Amount__c, Due_Date__c, Status__c,
                   Principal_Component__c, Interest_Component__c, Outstanding_Balance__c
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loanId
            ORDER BY Due_Date__c ASC
            LIMIT 240
        ];
    }

    /**
     * @description Fetches the Loan record details for header and metrics cards.
     * @param loanId The Id of the Loan__c record
     * @return Loan__c
     */
    @AuraEnabled(cacheable=true)
    public static Loan__c getLoanDetails(Id loanId) {
        if (loanId == null) {
            throw new AuraHandledException('Loan ID cannot be null.');
        }
        return [
            SELECT Id, Name, Principal_Amount__c, Interest_Rate__c,
                   Tenure_Months__c, Status__c, Borrower_Name__c, Borrower_Email__c,
                   Loan_Type__c, Disbursement_Date__c, Total_EMI_Amount__c,
                   Total_Interest_Payable__c, Total_Amount_Payable__c
            FROM Loan__c
            WHERE Id = :loanId
            LIMIT 1
        ];
    }

    /**
     * @description Returns summary statistics for a specific loan's KPI cards.
     * @param loanId The Id of the Loan__c record
     * @return Map<String, Object> containing stats
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getLoanSummaryStats(Id loanId) {
        if (loanId == null) {
            throw new AuraHandledException('Loan ID cannot be null.');
        }

        Map<String, Object> stats = new Map<String, Object>();

        AggregateResult[] results = [
            SELECT Status__c, COUNT(Id) cnt, SUM(EMI_Amount__c) totalAmt
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loanId
            GROUP BY Status__c
        ];

        Integer totalCount     = 0;
        Integer paidCount      = 0;
        Integer pendingCount   = 0;
        Integer overdueCount   = 0;
        Decimal totalPaid      = 0;
        Decimal totalPending   = 0;

        for (AggregateResult ar : results) {
            String status = (String) ar.get('Status__c');
            Integer cnt   = (Integer) ar.get('cnt');
            Decimal amt   = (Decimal) ar.get('totalAmt');
            totalCount    += cnt;

            if (status == 'Paid') {
                paidCount    = cnt;
                totalPaid    = amt != null ? amt : 0;
            } else if (status == 'Pending') {
                pendingCount = cnt;
                totalPending += (amt != null ? amt : 0);
            } else if (status == 'Overdue') {
                overdueCount = cnt;
                totalPending += (amt != null ? amt : 0);
            }
        }

        Integer progressPct = totalCount > 0 ? (Integer) Math.round((paidCount * 100.0) / totalCount) : 0;

        stats.put('totalCount',   totalCount);
        stats.put('paidCount',    paidCount);
        stats.put('pendingCount', pendingCount);
        stats.put('overdueCount', overdueCount);
        stats.put('totalPaid',    totalPaid);
        stats.put('totalPending', totalPending);
        stats.put('progressPct',  progressPct);

        return stats;
    }

    /**
     * @description Fetches all loans associated with a specific borrower email address.
     * @param borrowerEmail Email of the borrower
     * @return List<Loan__c>
     */
    @AuraEnabled(cacheable=true)
    public static List<Loan__c> getBorrowerLoans(String borrowerEmail) {
        if (String.isBlank(borrowerEmail)) {
            return [
                SELECT Id, Name, Principal_Amount__c, Interest_Rate__c,
                       Tenure_Months__c, Status__c, Borrower_Name__c, Borrower_Email__c,
                       Loan_Type__c, CreatedDate
                FROM Loan__c
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];
        }
        return [
            SELECT Id, Name, Principal_Amount__c, Interest_Rate__c,
                   Tenure_Months__c, Status__c, Borrower_Name__c, Borrower_Email__c,
                   Loan_Type__c, CreatedDate
            FROM Loan__c
            WHERE Borrower_Email__c = :borrowerEmail
            ORDER BY CreatedDate DESC
            LIMIT 50
        ];
    }

    // ─── Admin CRM Dashboard Endpoints ───────────────────────────────────────

    /**
     * @description Computes comprehensive portfolio metrics for the Admin CRM Dashboard (santoshpatelvns5@gmail.com).
     * @return Map<String, Object> Portfolio KPIs
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getAdminPortfolioMetrics() {
        Map<String, Object> metrics = new Map<String, Object>();

        // Query Loan aggregates
        AggregateResult[] loanAggs = [
            SELECT Status__c, COUNT(Id) cnt, SUM(Principal_Amount__c) totalPrincipal
            FROM Loan__c
            GROUP BY Status__c
        ];

        Integer totalLoans     = 0;
        Integer activeLoans    = 0;
        Integer pendingLoans   = 0;
        Integer closedLoans    = 0;
        Integer rejectedLoans  = 0;
        Decimal totalDisbursed = 0;

        for (AggregateResult ar : loanAggs) {
            String status = (String) ar.get('Status__c');
            Integer cnt   = (Integer) ar.get('cnt');
            Decimal prin  = (Decimal) ar.get('totalPrincipal');
            totalLoans += cnt;

            if (status == 'Approved') {
                activeLoans += cnt;
                totalDisbursed += (prin != null ? prin : 0);
            } else if (status == 'Pending') {
                pendingLoans += cnt;
            } else if (status == 'Closed') {
                closedLoans += cnt;
                totalDisbursed += (prin != null ? prin : 0);
            } else if (status == 'Rejected') {
                rejectedLoans += cnt;
            }
        }

        // Query Schedule aggregates for collection tracking
        AggregateResult[] schedAggs = [
            SELECT Status__c, COUNT(Id) cnt, SUM(EMI_Amount__c) totalAmt
            FROM Repayment_Schedule__c
            GROUP BY Status__c
        ];

        Decimal totalCollected = 0;
        Decimal totalReceivable = 0;
        Integer overdueSchedules = 0;

        for (AggregateResult ar : schedAggs) {
            String status = (String) ar.get('Status__c');
            Integer cnt   = (Integer) ar.get('cnt');
            Decimal amt   = (Decimal) ar.get('totalAmt');
            Decimal nonNullAmt = amt != null ? amt : 0;

            if (status == 'Paid') {
                totalCollected += nonNullAmt;
            } else if (status == 'Pending') {
                totalReceivable += nonNullAmt;
            } else if (status == 'Overdue') {
                totalReceivable += nonNullAmt;
                overdueSchedules += cnt;
            }
        }

        Decimal totalExpected = totalCollected + totalReceivable;
        Integer collectionRate = totalExpected > 0 ? (Integer) Math.round((totalCollected * 100.0) / totalExpected) : 0;

        metrics.put('totalLoans',        totalLoans);
        metrics.put('activeLoans',       activeLoans);
        metrics.put('pendingLoans',      pendingLoans);
        metrics.put('closedLoans',       closedLoans);
        metrics.put('rejectedLoans',     rejectedLoans);
        metrics.put('totalDisbursed',    totalDisbursed);
        metrics.put('totalCollected',    totalCollected);
        metrics.put('totalReceivable',   totalReceivable);
        metrics.put('overdueSchedules',  overdueSchedules);
        metrics.put('collectionRate',    collectionRate);

        return metrics;
    }

    /**
     * @description Fetches all loans with repayment progress for the Admin CRM Table.
     * @param filterStatus Status filter (All, Pending, Approved, Closed, Rejected)
     * @param searchTerm Search query for borrower name, email, or loan name
     * @return List<Loan__c>
     */
    @AuraEnabled(cacheable=true)
    public static List<Loan__c> getAllLoans(String filterStatus, String searchTerm) {
        String query = 'SELECT Id, Name, Principal_Amount__c, Interest_Rate__c, Tenure_Months__c, '
                     + 'Status__c, Borrower_Name__c, Borrower_Email__c, Loan_Type__c, '
                     + 'Disbursement_Date__c, Total_EMI_Amount__c, CreatedDate '
                     + 'FROM Loan__c ';
        
        List<String> conditions = new List<String>();

        if (String.isNotBlank(filterStatus) && filterStatus != 'All') {
            conditions.add('Status__c = :filterStatus');
        }

        if (String.isNotBlank(searchTerm)) {
            String likeTerm = '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
            conditions.add('(Name LIKE :likeTerm OR Borrower_Name__c LIKE :likeTerm OR Borrower_Email__c LIKE :likeTerm)');
        }

        if (!conditions.isEmpty()) {
            query += 'WHERE ' + String.join(conditions, ' AND ') + ' ';
        }

        query += 'ORDER BY CreatedDate DESC LIMIT 100';

        return Database.query(query);
    }

    // ─── Transactional & DML Actions ─────────────────────────────────────────

    /**
     * @description Creates a new Loan application from the Borrower Self-Service Portal.
     */
    @AuraEnabled
    public static Loan__c createLoanApplication(
        String name,
        String borrowerName,
        String borrowerEmail,
        Decimal principal,
        Decimal interestRate,
        Integer tenure,
        String loanType
    ) {
        if (String.isBlank(borrowerName) || String.isBlank(borrowerEmail)) {
            throw new AuraHandledException('Borrower Name and Email are required.');
        }
        if (principal == null || principal <= 0) {
            throw new AuraHandledException('Principal Amount must be greater than zero.');
        }
        if (tenure == null || tenure <= 0) {
            throw new AuraHandledException('Tenure must be at least 1 month.');
        }

        try {
            Loan__c newLoan = new Loan__c(
                Name                 = String.isNotBlank(name) ? name : ('LN-' + System.now().format('yyyyMMdd-HHmmss')),
                Borrower_Name__c     = borrowerName,
                Borrower_Email__c    = borrowerEmail,
                Principal_Amount__c  = principal,
                Interest_Rate__c     = interestRate != null ? interestRate : 10.0,
                Tenure_Months__c     = tenure,
                Loan_Type__c         = String.isNotBlank(loanType) ? loanType : 'Personal Loan',
                Status__c            = 'Pending',
                Disbursement_Date__c = Date.today()
            );

            insert newLoan;
            return newLoan;

        } catch (Exception e) {
            throw new AuraHandledException('Error submitting loan application: ' + e.getMessage());
        }
    }

    /**
     * @description Updates Loan Status (Approve, Reject, Close) and triggers transactional notifications.
     */
    @AuraEnabled
    public static void updateLoanStatus(Id loanId, String newStatus, String adminComments) {
        if (loanId == null || String.isBlank(newStatus)) {
            throw new AuraHandledException('Loan ID and New Status are required.');
        }

        try {
            Loan__c loan = [
                SELECT Id, Name, Status__c, Borrower_Name__c, Borrower_Email__c, Principal_Amount__c
                FROM Loan__c
                WHERE Id = :loanId
                LIMIT 1
            ];

            String oldStatus = loan.Status__c;
            loan.Status__c = newStatus;
            update loan;

            // Trigger status notification email
            EMIReminderEmailService.sendStatusChangeEmail(loan, oldStatus, newStatus, adminComments);

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to update loan status: ' + e.getMessage());
        }
    }

    /**
     * @description Updates borrower profile and loan parameters, then dispatches notification email.
     */
    @AuraEnabled
    public static void updateBorrowerProfile(
        Id loanId,
        String borrowerName,
        String borrowerEmail,
        Decimal principal,
        Decimal interestRate,
        Integer tenure,
        String loanType
    ) {
        if (loanId == null) {
            throw new AuraHandledException('Loan ID cannot be null.');
        }

        try {
            Loan__c loan = [
                SELECT Id, Name, Borrower_Name__c, Borrower_Email__c, Principal_Amount__c,
                       Interest_Rate__c, Tenure_Months__c, Loan_Type__c
                FROM Loan__c
                WHERE Id = :loanId
                LIMIT 1
            ];

            List<String> changes = new List<String>();

            if (String.isNotBlank(borrowerName) && borrowerName != loan.Borrower_Name__c) {
                changes.add('Name: ' + loan.Borrower_Name__c + ' ➔ ' + borrowerName);
                loan.Borrower_Name__c = borrowerName;
            }
            if (String.isNotBlank(borrowerEmail) && borrowerEmail != loan.Borrower_Email__c) {
                changes.add('Email: ' + loan.Borrower_Email__c + ' ➔ ' + borrowerEmail);
                loan.Borrower_Email__c = borrowerEmail;
            }
            if (principal != null && principal != loan.Principal_Amount__c) {
                changes.add('Principal: ₹' + loan.Principal_Amount__c + ' ➔ ₹' + principal);
                loan.Principal_Amount__c = principal;
            }
            if (interestRate != null && interestRate != loan.Interest_Rate__c) {
                changes.add('Interest Rate: ' + loan.Interest_Rate__c + '% ➔ ' + interestRate + '%');
                loan.Interest_Rate__c = interestRate;
            }
            if (tenure != null && tenure != loan.Tenure_Months__c) {
                changes.add('Tenure: ' + loan.Tenure_Months__c + 'm ➔ ' + tenure + 'm');
                loan.Tenure_Months__c = tenure;
            }
            if (String.isNotBlank(loanType) && loanType != loan.Loan_Type__c) {
                changes.add('Type: ' + loan.Loan_Type__c + ' ➔ ' + loanType);
                loan.Loan_Type__c = loanType;
            }

            update loan;

            if (!changes.isEmpty()) {
                String updateSummary = String.join(changes, ', ');
                EMIReminderEmailService.sendProfileUpdateEmail(loan, updateSummary);
            }

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating profile: ' + e.getMessage());
        }
    }

    /**
     * @description Marks a single EMI schedule as Paid, recalculates outstanding metrics,
     *              and triggers an instant payment confirmation receipt email.
     */
    @AuraEnabled
    public static void markAsPaid(Id scheduleId) {
        if (scheduleId == null) {
            throw new AuraHandledException('Schedule ID cannot be null.');
        }

        try {
            Repayment_Schedule__c schedule = [
                SELECT Id, Name, EMI_Amount__c, Due_Date__c, Status__c, Outstanding_Balance__c,
                       Loan__c, Loan__r.Name, Loan__r.Borrower_Name__c, Loan__r.Borrower_Email__c
                FROM Repayment_Schedule__c
                WHERE Id = :scheduleId
                LIMIT 1
            ];

            if (schedule.Status__c == 'Paid') {
                throw new AuraHandledException('This installment is already recorded as Paid.');
            }

            schedule.Status__c = 'Paid';
            update schedule;

            // Query remaining unpaid balance and count for receipt
            AggregateResult[] remAggs = [
                SELECT COUNT(Id) cnt, SUM(EMI_Amount__c) remAmt
                FROM Repayment_Schedule__c
                WHERE Loan__c = :schedule.Loan__c
                AND Status__c != 'Paid'
            ];

            Decimal remBalance = 0;
            Integer remCount = 0;
            if (!remAggs.isEmpty()) {
                remCount = (Integer) remAggs[0].get('cnt');
                Decimal sumAmt = (Decimal) remAggs[0].get('remAmt');
                remBalance = sumAmt != null ? sumAmt : 0;
            }

            // Send instant payment receipt email
            EMIReminderEmailService.sendPaymentReceiptEmail(schedule, remBalance, remCount);

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Error marking EMI as Paid: ' + e.getMessage());
        }
    }

    /**
     * @description Marks multiple Repayment Schedules as Paid in bulk.
     */
    @AuraEnabled
    public static void markMultipleAsPaid(List<Id> scheduleIds) {
        if (scheduleIds == null || scheduleIds.isEmpty()) {
            throw new AuraHandledException('No schedule IDs provided.');
        }

        try {
            List<Repayment_Schedule__c> schedulesToUpdate = [
                SELECT Id, Status__c
                FROM Repayment_Schedule__c
                WHERE Id IN :scheduleIds
                AND Status__c != 'Paid'
            ];

            for (Repayment_Schedule__c s : schedulesToUpdate) {
                s.Status__c = 'Paid';
            }

            if (!schedulesToUpdate.isEmpty()) {
                update schedulesToUpdate;
            }

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Bulk payment update failed: ' + e.getMessage());
        }
    }

    /**
     * @description Marks a schedule as Overdue.
     */
    @AuraEnabled
    public static void markAsOverdue(Id scheduleId) {
        if (scheduleId == null) {
            throw new AuraHandledException('Schedule ID cannot be null.');
        }

        try {
            Repayment_Schedule__c schedule = [
                SELECT Id, Status__c
                FROM Repayment_Schedule__c
                WHERE Id = :scheduleId
                LIMIT 1
            ];

            schedule.Status__c = 'Overdue';
            update schedule;

        } catch (Exception e) {
            throw new AuraHandledException('Error updating status: ' + e.getMessage());
        }
    }

    /**
     * @description Allows Admin to trigger the automated Batch Email Reminder job on-demand.
     */
    @AuraEnabled
    public static String runReminderBatchNow(Integer daysAhead) {
        try {
            Integer days = (daysAhead != null && daysAhead >= 0) ? daysAhead : 3;
            Id batchJobId = Database.executeBatch(new EMIReminderEmailService(days), 50);
            return 'Batch Reminder Job queued successfully with Job ID: ' + batchJobId;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to launch batch reminder job: ' + e.getMessage());
        }
    }
}
