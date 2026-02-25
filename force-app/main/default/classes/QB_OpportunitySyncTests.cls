/**
 * @description Unit tests for Opportunity → QuickBooks sync
 * - Mocks callouts for Customer and Invoice creation
 * - Verifies field updates and trigger-driven queueable path
 * - Bulk tests and negative paths
 */
@IsTest
private class QB_OpportunitySyncTests {

    // Simple HTTP mock returning minimal JSON fragments for QuickBooks create Customer/Invoice
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

    @TestSetup
    static void setupData() {
        // Seed org defaults for custom setting used by service for realmId and default item
        QB_Config__c orgDefaults = QB_Config__c.getOrgDefaults();
        if (orgDefaults == null) {
            orgDefaults = new QB_Config__c();
        }
        orgDefaults.Realm_Id__c = '9341456432854931';
        orgDefaults.Default_Item_Ref__c = '1';
        upsert orgDefaults;

        Account a = new Account(
            Name = 'Acme Corp',
            Phone = '555-111-2222',
            BillingStreet = '1 Main',
            BillingCity = 'San Francisco',
            BillingState = 'CA',
            BillingPostalCode = '94105',
            BillingCountry = 'United S'
        );
        insert a;

        Opportunity o1 = new Opportunity(
            Name = 'Opp Paid Path',
            StageName = 'Prospecting',
            CloseDate = System.today(),
            Amount = 123.45,
            AccountId = a.Id
        );
        Opportunity o2 = new Opportunity(
            Name = 'Opp Skip Not Paid',
            StageName = 'Prospecting',
            CloseDate = System.today(),
            Amount = 50,
            AccountId = a.Id
        );
        insert new List<Opportunity>{o1, o2};
    }

    @IsTest
    static void testInvocableHappyPath() {
        Opportunity o = [SELECT Id, Name, StageName FROM Opportunity WHERE Name = 'Opp Paid Path' LIMIT 1];
        // Make it paid to satisfy condition
        o.StageName = 'Paid';
        update o;

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());
        // Use invocable directly
        QB_OpportunityInvoiceSync.Input inRec = new QB_OpportunityInvoiceSync.Input();
        inRec.opportunityId = o.Id;
        inRec.defaultItemRef = '1';
        List<QB_OpportunityInvoiceSync.Output> outs = QB_OpportunityInvoiceSync.sync(new List<QB_OpportunityInvoiceSync.Input>{inRec});
        Test.stopTest();

        System.assertEquals(1, outs.size(), 'Should return one result');
        System.assertEquals(true, outs[0].success, 'Expect success');
        System.assertEquals('Invoice created', outs[0].message, 'Should report invoice created');
        // Verify opportunity updated
        Opportunity o2 = [SELECT QuickBooks_Invoice_Id__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('INV-999', o2.get('QuickBooks_Invoice_Id__c'), 'Invoice Id should be written back');
    }

    @IsTest
    static void testTriggerQueuesQueueable() {
        // Stage change on update should enqueue queueable and call the invocable path
        Opportunity o = [SELECT Id, StageName FROM Opportunity WHERE Name = 'Opp Skip Not Paid' LIMIT 1];
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());
        o.StageName = 'Paid';
        update o;
        Test.stopTest();

        Opportunity refreshed = [SELECT QuickBooks_Invoice_Id__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('INV-999', refreshed.get('QuickBooks_Invoice_Id__c'), 'Trigger path should have created invoice and updated field');
    }

    @IsTest
    static void testMissingRealmIdSkips() {
        // Clear org defaults to simulate missing realmId
        QB_Config__c orgDefaults = QB_Config__c.getOrgDefaults();
        if (orgDefaults == null) {
            orgDefaults = new QB_Config__c();
        }
        orgDefaults.Realm_Id__c = null;
        upsert orgDefaults;

        Account a = new Account(Name = 'No Realm');
        insert a;

        Opportunity o = new Opportunity(
            Name = 'Opp No Realm',
            StageName = 'Paid',
            CloseDate = System.today(),
            Amount = 25,
            AccountId = a.Id
        );
        insert o;

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());
        // Call invocable directly
        QB_OpportunityInvoiceSync.Input inRec = new QB_OpportunityInvoiceSync.Input();
        inRec.opportunityId = o.Id;
        List<QB_OpportunityInvoiceSync.Output> outs = QB_OpportunityInvoiceSync.sync(new List<QB_OpportunityInvoiceSync.Input>{inRec});
        Test.stopTest();

        System.assertEquals(1, outs.size());
        System.assertEquals(false, outs[0].success, 'Should not succeed without realmId');
        System.assert(outs[0].message != null && outs[0].message.contains('Missing QuickBooks realmId'), 'Expect missing realm message');
    }

    @IsTest
    static void testEnsureCustomerWritesBack() {
        Account a = [SELECT Id, Name, QuickBooks_Company_Id__c, QuickBooks_Customer_Id__c FROM Account WHERE Name = 'Acme Corp' LIMIT 1];
        System.assertEquals(null, a.get('QuickBooks_Customer_Id__c'), 'Precondition: no customer id before test');
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());
        String custId = QB_Service.ensureCustomer(a);
        Test.stopTest();
        System.assertEquals('CUST-123', custId, 'Should return created customer id');
        a = [SELECT QuickBooks_Customer_Id__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('CUST-123', a.get('QuickBooks_Customer_Id__c'), 'Account should be updated with customer id');
    }
}
