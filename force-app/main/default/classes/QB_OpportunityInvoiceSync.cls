public with sharing class QB_OpportunityInvoiceSync {

    public class Input {
        public Id opportunityId;
        public String defaultItemRef; // Optional, default '1'
    }

    public class Output {
        public Id opportunityId;
        public String quickBooksInvoiceId;
        public String quickBooksCustomerId;
        public String message;
        public Boolean success;
    }

    /**
     * Plan object that carries:
     * - what happened during callouts (Outputs)
     * - what should be written back (staged sObjects)
     *
     * IMPORTANT: performCallouts() must not do DML.
     * applyWritebacks() must not do callouts.
     */
    public class SyncPlan {
        public List<Output> results = new List<Output>();

        // staged writebacks
        public List<Account> accountsToUpdate = new List<Account>();
        public List<Opportunity> oppsToUpdate = new List<Opportunity>();

        // convenience maps to avoid duplicates
        public Map<Id, String> customerIdByAccountId = new Map<Id, String>();
        public Map<Id, String> invoiceIdByOppId = new Map<Id, String>();
    }

    /**
     * Convenience entry point (OK to use from Queueable).
     * Runs Phase 1 then Phase 2 in the same transaction, but in a safe order:
     * callouts first, then DML.
     */
    public static List<Output> sync(List<Input> inputs) {
        SyncPlan plan = performCallouts(inputs);
        applyWritebacks(plan);
        return plan.results;
    }

    /**
     * PHASE 1: callouts only.
     * - queries Opportunities/Accounts
     * - validates eligibility
     * - creates/ensures Customer in QBO (callout)
     * - creates Invoice in QBO (callout)
     * - stages SF writebacks in plan (NO DML)
     */
    public static SyncPlan performCallouts(List<Input> inputs) {
        SyncPlan plan = new SyncPlan();
        if (inputs == null || inputs.isEmpty()) return plan;

        // Collect Opportunity Ids and defaultItem overrides
        Set<Id> oppIds = new Set<Id>();
        Map<Id, String> itemOverride = new Map<Id, String>();
        for (Input inRec : inputs) {
            if (inRec == null || inRec.opportunityId == null) continue;
            oppIds.add(inRec.opportunityId);
            if (!String.isBlank(inRec.defaultItemRef)) {
                itemOverride.put(inRec.opportunityId, inRec.defaultItemRef);
            }
        }
        if (oppIds.isEmpty()) return plan;

        // Load Opportunities
        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, Name, Amount, StageName, AccountId, QuickBooks_Invoice_Id__c, RecordType.Name,
                   Custom_Membership_Dues__c, Calculated_Dues_Amount__c
            FROM Opportunity
            WHERE Id IN :oppIds
            WITH USER_MODE
        ]);

        // Gather Accounts
        Set<Id> accountIds = new Set<Id>();
        for (Opportunity o : opps.values()) {
            if (o.AccountId != null) accountIds.add(o.AccountId);
        }

        Map<Id, Account> accounts = accountIds.isEmpty()
            ? new Map<Id, Account>()
            : new Map<Id, Account>([
                SELECT Id, Name, Phone, Primary_Contact__r.Email,
                       BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                       QuickBooks_Company_Id__c, QuickBooks_Customer_Id__c
                FROM Account
                WHERE Id IN :accountIds
                WITH USER_MODE
            ]);

        // Process each input (callouts only; stage DML)
        for (Input inRec : inputs) {
            Output outRec = new Output();
            outRec.opportunityId = (inRec != null) ? inRec.opportunityId : null;
            outRec.success = false;

            String defaultItem = (outRec.opportunityId != null && itemOverride.containsKey(outRec.opportunityId))
                ? itemOverride.get(outRec.opportunityId)
                : '1';

            try {
                Opportunity opp = opps.get(outRec.opportunityId);
                if (opp == null) {
                    outRec.message = 'Opportunity not found';
                    plan.results.add(outRec);
                    continue;
                }
                if (opp.StageName != QB_Enums.STAGE_PAID) {
                    outRec.message = 'Opportunity Stage is not Paid; skipping';
                    plan.results.add(outRec);
                    continue;
                }
                if (opp.AccountId == null) {
                    outRec.message = 'Opportunity has no Account';
                    plan.results.add(outRec);
                    continue;
                }

                Account acc = accounts.get(opp.AccountId);
                if (acc == null) {
                    outRec.message = 'Account not found';
                    plan.results.add(outRec);
                    continue;
                }
                if (String.isBlank(acc.QuickBooks_Company_Id__c)) {
                    outRec.message = 'Missing QuickBooks Company Id (realmId) on Account';
                    plan.results.add(outRec);
                    continue;
                }

                // CALL OUT 1: Ensure/create Customer in QBO, but DO NOT write back here
                String customerId = QB_Service.ensureCustomer(acc, false);
                outRec.quickBooksCustomerId = customerId;

                // stage Account writeback (dedup by Account Id)
                if (!String.isBlank(customerId) && !plan.customerIdByAccountId.containsKey(acc.Id)) {
                    plan.customerIdByAccountId.put(acc.Id, customerId);
                }

                // CALL OUT 2: Create Invoice in QBO, but DO NOT write back here
                String invoiceId = QB_Service.createInvoiceFromOpportunity(opp, acc, customerId, defaultItem, false);
                outRec.quickBooksInvoiceId = invoiceId;

                // stage Opportunity writeback (dedup by Opp Id)
                if (!String.isBlank(invoiceId)) {
                    plan.invoiceIdByOppId.put(opp.Id, invoiceId);
                }

                outRec.message = 'Invoice created';
                outRec.success = true;

            } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, e);
            if (Test.isRunningTest()) {
            throw e;
    }
    outRec.message = 'Error: ' + e.getMessage();
    outRec.success = false;
}

            plan.results.add(outRec);
        }

        // Convert staged maps into sObjects for DML phase
        for (Id accId : plan.customerIdByAccountId.keySet()) {
            plan.accountsToUpdate.add(new Account(
                Id = accId,
                QuickBooks_Customer_Id__c = plan.customerIdByAccountId.get(accId)
            ));
        }
        for (Id oppId : plan.invoiceIdByOppId.keySet()) {
            plan.oppsToUpdate.add(new Opportunity(
                Id = oppId,
                QuickBooks_Invoice_Id__c = plan.invoiceIdByOppId.get(oppId)
            ));
        }

        return plan;
    }

    /**
     * PHASE 2: DML only.
     * Apply the staged writebacks.
     */
    public static void applyWritebacks(SyncPlan plan) {
        if (plan == null) return;

        // DML ONLY (no callouts in this method)
        if (plan.accountsToUpdate != null && !plan.accountsToUpdate.isEmpty()) {
            Database.update(plan.accountsToUpdate, AccessLevel.USER_MODE);
        }
        if (plan.oppsToUpdate != null && !plan.oppsToUpdate.isEmpty()) {
            Database.update(plan.oppsToUpdate, AccessLevel.USER_MODE);
        }
    }
}