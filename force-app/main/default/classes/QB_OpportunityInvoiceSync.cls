public with sharing class QB_OpportunityInvoiceSync {

    public class Input {
        public Id opportunityId;
        public String defaultItemRef;
    }

    public class Output {
        public Id opportunityId;
        public String quickBooksInvoiceId;
        public String quickBooksCustomerId;
        public String message;
        public Boolean success;
    }

    public static List<Output> sync(List<Input> inputs) {
        List<Output> results = new List<Output>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }

        // Collect Opportunity Ids
        Set<Id> oppIds = new Set<Id>();
        Map<Id, String> itemOverride = new Map<Id, String>();
        for (Input inRec : inputs) {
            if (inRec == null || inRec.opportunityId == null) continue;
            oppIds.add(inRec.opportunityId);
            if (!String.isBlank(inRec.defaultItemRef)) {
                itemOverride.put(inRec.opportunityId, inRec.defaultItemRef);
            }
        }
        if (oppIds.isEmpty()) return results;

        // Load Opportunities
        Map<Id, Opportunity> opps = new Map<Id, Opportunity>(
            [SELECT Id, Name, Amount, StageName, AccountId, QuickBooks_Invoice_Id__c
             FROM Opportunity
             WHERE Id IN :oppIds
             WITH USER_MODE]
        );

        // Load Accounts
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity o : opps.values()) {
            if (o.AccountId != null) accountIds.add(o.AccountId);
        }

        Map<Id, Account> accounts = accountIds.isEmpty() ? new Map<Id, Account>() :
            new Map<Id, Account>(
                [SELECT Id, Name, QuickBooks_Company_Id__c, QuickBooks_Customer_Id__c
                 FROM Account
                 WHERE Id IN :accountIds
                 WITH USER_MODE]
            );

        // Process each input
        for (Input inRec : inputs) {
            Output outRec = new Output();
            outRec.opportunityId = (inRec != null) ? inRec.opportunityId : null;
            outRec.success = false;
            String defaultItem = itemOverride.containsKey(outRec.opportunityId) ? itemOverride.get(outRec.opportunityId) : '1';

            try {
                Opportunity opp = opps.get(outRec.opportunityId);
                if (opp == null) {
                    outRec.message = 'Opportunity not found';
                    results.add(outRec);
                    continue;
                }
                if (opp.StageName != 'Paid') {
                    outRec.message = 'Opportunity Stage is not Paid; skipping';
                    results.add(outRec);
                    continue;
                }
                if (opp.AccountId == null) {
                    outRec.message = 'Opportunity has no Account';
                    results.add(outRec);
                    continue;
                }

                Account acc = accounts.get(opp.AccountId);
                if (acc == null) {
                    outRec.message = 'Account not found';
                    results.add(outRec);
                    continue;
                }

                if (String.isBlank(acc.QuickBooks_Company_Id__c)) {
                    outRec.message = 'Missing QuickBooks Company Id (realmId) on Account';
                    results.add(outRec);
                    continue;
                }

                // **Here we will call your QB_Service methods**
                String customerId = QB_Service.ensureCustomer(acc);
                String invoiceId = QB_Service.createInvoiceFromOpportunity(opp, acc, customerId, defaultItem);

                outRec.quickBooksCustomerId = customerId;
                outRec.quickBooksInvoiceId = invoiceId;
                outRec.success = true;
                outRec.message = 'Invoice created';
            } catch (Exception ex) {
                outRec.message = 'Error: ' + ex.getMessage();
            }
            results.add(outRec);
        }

        return results;
    }
}