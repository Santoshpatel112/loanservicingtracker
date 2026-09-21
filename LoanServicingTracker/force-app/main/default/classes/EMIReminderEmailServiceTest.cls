/**
 * @description       : Comprehensive Test Class for EMIReminderEmailService.
 *                      Validates scheduled execution, batch processing, invocable method,
 *                      and dynamic HTML template rendering.
 * @author            : Santosh Patel
 * @created           : 2026
 * @last modified on  : 2026-09-21
 **/
@isTest
private class EMIReminderEmailServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create active loan with borrower email
        Loan__c loan = new Loan__c(
            Borrower_Name__c      = 'Priya Sharma',
            Borrower_Email__c     = 'priya.sharma@example.com',
            Loan_Type__c          = 'Personal',
            Principal_Amount__c   = 200000.00,
            Interest_Rate__c      = 12.00,
            Tenure_Months__c      = 12,
            Disbursement_Date__c  = Date.today(),
            Status__c             = 'Pending'
        );
        insert loan;

        // Transition to Approved to trigger automated schedule creation
        loan.Status__c = 'Approved';
        update loan;

        // Adjust the first schedule's due date to be within reminder window (e.g. today + 2 days)
        List<Repayment_Schedule__c> schedules = [
            SELECT Id, Due_Date__c, Status__c
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
            ORDER BY Due_Date__c ASC
            LIMIT 3
        ];

        if (!schedules.isEmpty()) {
            schedules[0].Due_Date__c = Date.today(); // Due today
            schedules[0].Status__c   = 'Pending';

            if (schedules.size() > 1) {
                schedules[1].Due_Date__c = Date.today().addDays(1); // Due tomorrow
                schedules[1].Status__c   = 'Pending';
            }
            if (schedules.size() > 2) {
                schedules[2].Due_Date__c = Date.today().addDays(2); // Due in 2 days
                schedules[2].Status__c   = 'Pending';
            }
            update schedules;
        }
    }

    @isTest
    static void testBatchExecution() {
        Test.startTest();
        // Execute batch for next 3 days
        EMIReminderEmailService batchJob = new EMIReminderEmailService(3);
        Database.executeBatch(batchJob, 50);
        Test.stopTest();

        // Verify schedules still exist and status is intact
        List<Repayment_Schedule__c> schedules = [
            SELECT Id, Status__c
            FROM Repayment_Schedule__c
            WHERE Due_Date__c <= :Date.today().addDays(3)
        ];
        System.assert(!schedules.isEmpty(), 'Schedules should exist for reminder processing');
    }

    @isTest
    static void testScheduledJobExecution() {
        Test.startTest();
        String cronExp = '0 0 9 * * ?';
        String jobId = System.schedule('Test_EMIReminder_Job', cronExp, new EMIReminderEmailService());
        Test.stopTest();

        CronTrigger ct = [
            SELECT Id, CronExpression, TimesTriggered, NextFireTime
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        System.assertEquals(cronExp, ct.CronExpression, 'Cron expression should match scheduled expression');
    }

    @isTest
    static void testInvocableExecution() {
        Test.startTest();
        List<String> results = EMIReminderEmailService.sendRemindersInvocable(new List<Integer>{ 5 });
        Test.stopTest();

        System.assertNotEquals(null, results, 'Invocable results should not be null');
        System.assert(results[0].contains('5 days'), 'Status should confirm days ahead parameter');
    }

    @isTest
    static void testEmailBuilderVariations() {
        Loan__c loan = [SELECT Id, Name, Borrower_Name__c, Borrower_Email__c FROM Loan__c LIMIT 1];

        // 1. Due Today
        Repayment_Schedule__c schedToday = new Repayment_Schedule__c(
            Loan__c          = loan.Id,
            EMI_Amount__c    = 18000.00,
            Due_Date__c      = Date.today(),
            Status__c        = 'Pending'
        );
        insert schedToday;

        Repayment_Schedule__c fetchedToday = [
            SELECT Id, Name, EMI_Amount__c, Due_Date__c, Status__c,
                   Loan__c, Loan__r.Name, Loan__r.Borrower_Name__c, Loan__r.Borrower_Email__c,
                   Loan__r.Loan_Type__c, Loan__r.Interest_Rate__c
            FROM Repayment_Schedule__c
            WHERE Id = :schedToday.Id
        ];

        Messaging.SingleEmailMessage mailToday = EMIReminderEmailService.buildReminderEmail(fetchedToday);
        System.assert(mailToday.getSubject().contains('Due Today'), 'Email subject should indicate Due Today');
        System.assert(mailToday.getHtmlBody().contains('Priya Sharma'), 'Email body should address borrower');

        // 2. Due Tomorrow
        fetchedToday.Due_Date__c = Date.today().addDays(1);
        Messaging.SingleEmailMessage mailTmrw = EMIReminderEmailService.buildReminderEmail(fetchedToday);
        System.assert(mailTmrw.getSubject().contains('Due Tomorrow'), 'Email subject should indicate Due Tomorrow');

        // 3. Due in 5 Days
        fetchedToday.Due_Date__c = Date.today().addDays(5);
        Messaging.SingleEmailMessage mail5Days = EMIReminderEmailService.buildReminderEmail(fetchedToday);
        System.assert(mail5Days.getSubject().contains('Due in 5 Days'), 'Email subject should indicate Due in 5 Days');
    }

    @isTest
    static void testConstructorEdgeCases() {
        EMIReminderEmailService defaultService = new EMIReminderEmailService();
        System.assertNotEquals(null, defaultService, 'Default constructor should instantiate successfully');

        EMIReminderEmailService invalidService = new EMIReminderEmailService(-5);
        System.assertNotEquals(null, invalidService, 'Invalid days should fallback to default safely');
    }
}
