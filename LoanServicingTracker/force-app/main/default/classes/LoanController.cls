/**
 * @description       : Apex Controller for Loan Servicing & EMI Tracker LWC
 * @author            : Santosh Patel
 * @created           : 2026
 * @last modified on  : 2026-09-21
 * @coverage          : Covered by LoanServicingHandlerTest.cls
 **/
public with sharing class LoanController {

    /**
     * @description Fetches all repayment schedules for a given Loan record.
     *              Cacheable for LWC @wire performance.
     * @param loanId The Id of the Loan__c record
     * @return List<Repayment_Schedule__c>
     **/
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
     * @description Fetches the Loan record details for the dashboard header.
     * @param loanId The Id of the Loan__c record
     * @return Loan__c
     **/
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
     * @description Returns summary statistics for the dashboard KPI cards.
     * @param loanId The Id of the Loan__c record
     * @return Map<String, Object> containing stats
     **/
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
                totalPending = amt != null ? amt : 0;
            } else if (status == 'Overdue') {
                overdueCount = cnt;
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
     * @description Marks a single Repayment Schedule as Paid (DML Update).
     * @param scheduleId The Id of the Repayment_Schedule__c record
     **/
    @AuraEnabled
    public static void markAsPaid(Id scheduleId) {
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

            if (schedule.Status__c == 'Paid') {
                throw new AuraHandledException('This EMI is already marked as Paid.');
            }

            schedule.Status__c = 'Paid';
            update schedule;

        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            throw new AuraHandledException('Error updating EMI status: ' + e.getMessage());
        }
    }

    /**
     * @description Marks multiple Repayment Schedules as Paid in bulk.
     * @param scheduleIds List of Repayment_Schedule__c Ids
     **/
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
            throw new AuraHandledException('Bulk update failed: ' + e.getMessage());
        }
    }

    /**
     * @description Marks a schedule as Overdue.
     * @param scheduleId The Id of the Repayment_Schedule__c record
     **/
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
}
