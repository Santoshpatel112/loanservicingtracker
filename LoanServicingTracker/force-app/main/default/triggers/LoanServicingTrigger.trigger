/**
 * @description LoanServicingTrigger — Thin trigger following Handler Pattern.
 *              All business logic is in LoanServicingHandler.cls.
 * @author      Santosh Patel
 * @created     2026
 **/
trigger LoanServicingTrigger on Loan__c (after insert, after update) {
    LoanServicingHandler.handleAfterInsertUpdate(
        Trigger.new,
        Trigger.oldMap,
        Trigger.isInsert
    );
}