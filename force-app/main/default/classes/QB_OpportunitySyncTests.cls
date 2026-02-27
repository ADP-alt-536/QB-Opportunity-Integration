@IsTest
private class QB_OpportunitySyncTests {

    // Simple HTTP mock returning minimal JSON for QuickBooks create Customer/Invoice
    private class QbCreateMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setStatus('200 OK');
            String endpoint = req.getEndpoint();
            if (endpoint != null && endpoint.toLowerCase().contains('/customer')) {
                res.setBody('{"Customer":{"Id":"CUST-123","DisplayName":"Acme"}}');
            } else if (endpoint != null && endpoint.toLowerCase().contains('/invoice')) {
                res.setBody('{"Invoice":{"Id":"INV-999","DocNumber":"1001","TotalAmt":123.45}}');
            } else {
                res.setBody('{"ok":true}');
            }
            return res;
        }
    }

    // Create test data for Opportunities and Accounts
    @TestSetup
    static void setupData() {
        // Get RecordTypes - use try/catch to handle missing record types gracefully
        RecordType renewalRT;
        RecordType newMemberRT;
        try {
            renewalRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Opportunity' AND Name = 'Membership Recurring/Renewal Opportunities' LIMIT 1];
        } catch (QueryException e) {
            // Record type not found, will use null or default
        }
        try {
            newMemberRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Opportunity' AND Name = 'New Membership Opportunities' LIMIT 1];
        } catch (QueryException e) {
            // Record type not found, will use null or default
        }

        // 1. Accounts
        Account a = new Account(
            Name = 'Acme Corp',
            Phone = '555-111-2222',
            BillingStreet = '1 Main',
            BillingCity = 'San Francisco',
            BillingState = 'California',
            BillingPostalCode = '94105',
            BillingCountry = 'United States',
            QuickBooks_Company_Id__c = '123456789'
        );
        insert a;
        // 1a) Contact with Email
        Contact primaryC = new Contact(
            FirstName = 'Alex',
            LastName  = 'Primary',
            AccountId = a.Id,
            Email     = 'primary@example.com'
        );  

insert primaryC;

    // 1b) Set the lookup field that corresponds to Primary_Contact__r
    // This is almost certainly Primary_Contact__c (relationship name Primary_Contact__r).
    a.Primary_Contact__c = primaryC.Id;
    update a;

    // 1c) If you need to assert/use the formula, re-query it
    a = [
    SELECT Id, Primary_Contact__r.Email
    FROM Account
    WHERE Id = :a.Id
];
System.assertEquals('primary@example.com', a.Primary_Contact__r.Email);


        // 2. Opportunities with RecordTypes
        Opportunity o1 = new Opportunity(
            Name = 'Opp Renewal',
            RecordTypeId = renewalRT.Id,
            StageName = 'Prospecting',
            CloseDate = System.today(),
            Amount = 123.45,
            Custom_Membership_Dues__c = 50.00,
            Calculated_Dues_Amount__c = '123.45',
            AccountId = a.Id
        );
        Opportunity o2 = new Opportunity(
            Name = 'Opp New Member',
            RecordTypeId = newMemberRT.Id,
            StageName = 'Prospecting',
            CloseDate = System.today(),
            Amount = 250.00,
            AccountId = a.Id
        );
        insert new List<Opportunity>{o1, o2};
    }

    // Helper method to create test config
    private static QB_Config__mdt createTestConfig() {
        QB_Config__mdt cfg = new QB_Config__mdt(
            MasterLabel = 'Org Defaults',
            Realm_Id__c = '123456789',
            Default_Item_Ref__c = '1'
        );
        return cfg;
    }

    @IsTest
    static void testInvocableWithTwoLineItems() {
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());

        Test.startTest();

        Opportunity o = [SELECT Id, Name, StageName, Effective_Date__c, Paid_Date__c, Amount_Paid__c, AccountId FROM Opportunity WHERE Name = 'Opp Renewal' LIMIT 1];
        o.StageName = 'Paid';
        o.Effective_Date__c = System.today();
        o.Paid_Date__c = System.today();
        o.Amount_Paid__c = 123.45;
        update o;

        // Call invocable directly
        QB_OpportunityInvoiceSync.Input inRec = new QB_OpportunityInvoiceSync.Input();
        inRec.opportunityId = o.Id;
        inRec.defaultItemRef = '1';
        List<QB_OpportunityInvoiceSync.Output> outs = QB_OpportunityInvoiceSync.sync(new List<QB_OpportunityInvoiceSync.Input>{inRec});

        Test.stopTest();

        System.assertEquals(1, outs.size(), 'Should return one result');
        System.assertEquals(true, outs[0].success, 'Expect success');
        System.assertEquals('Invoice created', outs[0].message, 'Should report invoice created');

        Opportunity o2 = [SELECT QuickBooks_Invoice_Id__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('INV-999', o2.QuickBooks_Invoice_Id__c, 'Invoice Id should be written back');
    }

    @IsTest
    static void testInvocableWithSingleLineItem() {
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());

        Test.startTest();

        Opportunity o = [SELECT Id, StageName, Effective_Date__c,
        Paid_Date__c, Amount_Paid__c, AccountId FROM Opportunity WHERE Name = 'Opp New Member' LIMIT 1];
        o.StageName = 'Paid';
        o.Effective_Date__c = System.today();
        o.Paid_Date__c = System.today();
        o.Amount_Paid__c = 250.00;
        update o;

        // Call invocable directly
        QB_OpportunityInvoiceSync.Input inRec = new QB_OpportunityInvoiceSync.Input();
        inRec.opportunityId = o.Id;
        inRec.defaultItemRef = '1';
        List<QB_OpportunityInvoiceSync.Output> outs = QB_OpportunityInvoiceSync.sync(new List<QB_OpportunityInvoiceSync.Input>{inRec});

        Test.stopTest();

        System.assertEquals(1, outs.size(), 'Should return one result');
        System.assertEquals(true, outs[0].success, 'Expect success');
        System.assertEquals('Invoice created', outs[0].message, 'Should report invoice created with single line item');

        Opportunity o2 = [SELECT QuickBooks_Invoice_Id__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('INV-999', o2.QuickBooks_Invoice_Id__c, 'Invoice Id should be written back');
    }

    @IsTest
    static void testTriggerQueuesQueueable() {
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());

        Test.startTest();

        Opportunity o = [SELECT Id, StageName, Effective_Date__c,
        Paid_Date__c, Amount_Paid__c, AccountId
        FROM Opportunity WHERE Name = 'Opp New Member' LIMIT 1];
        o.StageName = 'Paid';
        o.Effective_Date__c = System.today();
        o.Paid_Date__c = System.today();    
        o.Amount_Paid__c = 250.00;
         update o;

        Test.stopTest();

        Opportunity refreshed = [SELECT QuickBooks_Invoice_Id__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('INV-999', refreshed.QuickBooks_Invoice_Id__c, 'Trigger path should have created invoice and updated field');
    }

    @IsTest
    static void testEnsureCustomerWritesBack() {
        Account a = [SELECT Id, Name, QuickBooks_Customer_Id__c, Primary_Contact__r.Email,
           BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry FROM Account WHERE Name = 'Acme Corp' LIMIT 1];
        System.assertEquals(null, a.QuickBooks_Customer_Id__c, 'Precondition: no customer id before test');

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());

        String custId = QB_Service.ensureCustomer(a);
        Test.stopTest();

        System.assertEquals('CUST-123', custId, 'Should return created customer id');

        a = [SELECT QuickBooks_Customer_Id__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('CUST-123', a.QuickBooks_Customer_Id__c, 'Account should be updated with customer id');
    }
}
