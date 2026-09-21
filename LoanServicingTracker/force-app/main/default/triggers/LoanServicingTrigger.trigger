trigger LoanServicingTrigger on Loan__c (after insert, after update) {
    List<Repayment_Schedule__c> schedulesToInsert = new List<Repayment_Schedule__c>();
    
    for (Loan__c loan : Trigger.new) {
        // Check if loan status is updated to Approved
        if (loan.Status__c == 'Approved' && 
            (Trigger.isInsert || Trigger.oldMap.get(loan.Id).Status__c != 'Approved')) {
            
            Decimal principal = loan.Principal_Amount__c;
            Integer tenure = (Integer) loan.Tenure_Months__c;
            Decimal annualRate = loan.Interest_Rate__c;
            
            // Handle Zero Interest Edge Case
            Decimal emi;
            if (annualRate == 0) {
                emi = principal / tenure;
            } else {
                Decimal monthlyRate = (annualRate / 12) / 100;
                emi = (principal * monthlyRate * Math.pow(1 + monthlyRate.doubleValue(), tenure)) / 
                              (Math.pow(1 + monthlyRate.doubleValue(), tenure) - 1);
            }
            
            Date baseDate = System.today();
            
            // Loop to generate monthly repayment schedules
            for (Integer i = 1; i <= tenure; i++) {
                Repayment_Schedule__c schedule = new Repayment_Schedule__c();
                schedule.Loan__c = loan.Id;
                schedule.EMI_Amount__c = emi.setScale(2);
                schedule.Due_Date__c = baseDate.addMonths(i);
                schedule.Status__c = 'Pending';
                schedulesToInsert.add(schedule);
            }
        }
    }
    
    // Bulkified DML Insert
    if (!schedulesToInsert.isEmpty()) {
        insert schedulesToInsert;
    }
}