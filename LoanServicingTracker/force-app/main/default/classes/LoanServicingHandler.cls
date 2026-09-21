/**
 * @description       : Trigger Handler for Loan Servicing — Trigger→Handler Pattern
 *                      Generates amortized EMI repayment schedules on Loan approval.
 *                      Handles: bulkification, zero-interest, duplicate prevention.
 * @author            : Santosh Patel
 * @created           : 2026
 * @last modified on  : 2026-09-21
 **/
public with sharing class LoanServicingHandler {

    /**
     * @description Entry point called from LoanServicingTrigger.
     *              Processes after insert and after update events.
     * @param newLoans    Trigger.new list
     * @param oldLoanMap  Trigger.oldMap (null for inserts)
     * @param isInsert    True if trigger fires on insert
     **/
    public static void handleAfterInsertUpdate(
        List<Loan__c> newLoans,
        Map<Id, Loan__c> oldLoanMap,
        Boolean isInsert
    ) {
        // Filter loans that just became 'Approved' for the first time
        List<Loan__c> loansToProcess = new List<Loan__c>();

        for (Loan__c loan : newLoans) {
            if (loan.Status__c == 'Approved') {
                Boolean isNewApproval = isInsert ||
                    (oldLoanMap != null && oldLoanMap.get(loan.Id).Status__c != 'Approved');

                if (isNewApproval) {
                    loansToProcess.add(loan);
                }
            }
        }

        if (loansToProcess.isEmpty()) {
            return;
        }

        // Duplicate Prevention: Check if schedules already exist
        Set<Id> loanIds = new Map<Id, Loan__c>(loansToProcess).keySet();
        Set<Id> alreadyProcessedLoanIds = new Set<Id>();

        for (AggregateResult ar : [
            SELECT Loan__c
            FROM Repayment_Schedule__c
            WHERE Loan__c IN :loanIds
            GROUP BY Loan__c
        ]) {
            alreadyProcessedLoanIds.add((Id) ar.get('Loan__c'));
        }

        // Generate schedules only for loans without existing schedules
        List<Repayment_Schedule__c> schedulesToInsert = new List<Repayment_Schedule__c>();

        for (Loan__c loan : loansToProcess) {
            if (!alreadyProcessedLoanIds.contains(loan.Id)) {
                schedulesToInsert.addAll(generateSchedules(loan));
            }
        }

        // Bulkified DML Insert
        if (!schedulesToInsert.isEmpty()) {
            insert schedulesToInsert;
        }
    }

    /**
     * @description Generates monthly amortized repayment schedule records for a loan.
     *              Uses reducing-balance EMI formula with zero-interest edge case handling.
     * @param loan  The approved Loan__c record
     * @return List<Repayment_Schedule__c>
     **/
    private static List<Repayment_Schedule__c> generateSchedules(Loan__c loan) {
        List<Repayment_Schedule__c> schedules = new List<Repayment_Schedule__c>();

        // Guard: validate required fields
        if (loan.Principal_Amount__c == null || loan.Tenure_Months__c == null
            || loan.Interest_Rate__c == null) {
            return schedules;
        }

        Decimal principal  = loan.Principal_Amount__c;
        Integer tenure     = (Integer) loan.Tenure_Months__c;
        Decimal annualRate = loan.Interest_Rate__c;
        Date baseDate      = loan.Disbursement_Date__c != null
                                ? loan.Disbursement_Date__c
                                : System.today();

        // EMI Formula: Reducing-balance amortization
        Decimal monthlyEmi;
        Decimal monthlyRate = 0;

        if (annualRate == 0) {
            // Zero-interest: simple division
            monthlyEmi = (principal / tenure).setScale(2);
        } else {
            monthlyRate = ((annualRate / 12) / 100);
            Double r    = monthlyRate.doubleValue();
            Double p    = principal.doubleValue();
            Double n    = tenure;
            Double pow  = Math.pow(1 + r, n);
            monthlyEmi  = Decimal.valueOf((p * r * pow) / (pow - 1)).setScale(2);
        }

        // Generate amortization schedule with principal/interest breakdown
        Decimal outstandingBalance = principal;

        for (Integer i = 1; i <= tenure; i++) {
            Decimal interestComponent  = (annualRate == 0) ? 0
                : (outstandingBalance * monthlyRate).setScale(2);
            Decimal principalComponent = (monthlyEmi - interestComponent).setScale(2);

            // Adjust last installment for rounding differences
            if (i == tenure) {
                principalComponent = outstandingBalance;
                monthlyEmi = (principalComponent + interestComponent).setScale(2);
            }

            outstandingBalance = (outstandingBalance - principalComponent).setScale(2);

            Repayment_Schedule__c schedule = new Repayment_Schedule__c(
                Loan__c                  = loan.Id,
                EMI_Amount__c            = monthlyEmi,
                Due_Date__c              = baseDate.addMonths(i),
                Status__c                = 'Pending',
                Principal_Component__c   = principalComponent,
                Interest_Component__c    = interestComponent,
                Outstanding_Balance__c   = outstandingBalance < 0 ? 0 : outstandingBalance
            );
            schedules.add(schedule);
        }

        return schedules;
    }
}
