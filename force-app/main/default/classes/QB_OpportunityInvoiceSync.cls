public with sharing class QB_OpportunityInvoiceSync {

    // Output structure for results
    public class Output {
        public Id opportunityId;
        public String quickBooksInvoiceId;
        public String quickBooksCustomerId;
        public String message;
        public Boolean success;
    }

    /**
     * Syncs Opportunities to QuickBooks Invoices.
     * Accepts a list of Opportunity IDs, ensures the Account exists in QuickBooks,
     * and creates an Invoice for Opportunities in Stage=Paid.
     */
    public static List<Output> syncOpportunities(List<Id> opportunityIds) {
        List<Output> results = new List<Output>();
        if (opportunityIds == null || opportunityIds.isEmpty()) return results;

        // Load Opportunities
        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, Name, Amount, StageName, AccountId, QuickBooks_Invoice_Id__c
            FROM Opportunity
            WHERE Id IN :opportunityIds
            WITH USER_MODE
        ]);

        // Collect Account IDs
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity o : opps.values()) {
            if (o.AccountId != null) accountIds.add(o.AccountId);
        }

        // Load Accounts
        Map<Id, Account> accounts = accountIds.isEmpty() ? new Map<Id, Account>() :
            new Map<Id, Account>([
                SELECT Id, Name, Phone, PersonEmail__c, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                       QuickBooks_Company_Id__c, QuickBooks_Customer_Id__c
                FROM Account
                WHERE Id IN :accountIds
                WITH USER_MODE
            ]);

        // Process each Opportunity
        for (Id oppId : opportunityIds) {
            Output outRec = new Output();
            outRec.opportunityId = oppId;
            outRec.success = false;

            try {
                Opportunity opp = opps.get(oppId);
                if (opp == null) {
                    outRec.message = 'Opportunity not found';
                    results.add(outRec);
                    continue;
                }

                if (opp.StageName != QB_Enums.STAGE_PAID) {
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

                // Ensure Customer in QuickBooks
                String customerId = QB_Service.ensureCustomer(acc);

                // Create Invoice in QuickBooks
                String invoiceId = QB_Service.createInvoiceFromOpportunity(opp, acc, customerId, '1');

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