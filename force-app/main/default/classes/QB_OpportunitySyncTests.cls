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
        // 1. Accounts
        Account a = new Account(
            Name = 'Acme Corp',
            Phone = '555-111-2222',
            BillingStreet = '1 Main',
            BillingCity = 'San Francisco',
            BillingState = 'CA',
            BillingPostalCode = '94105',
            BillingCountry = 'US'
        );
        insert a;

        // 2. Opportunities
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

    // Helper method to simulate CMDT record in test context
    @TestVisible
public static QB_Config__mdt getTestableConfig;

// ...existing code...

// Ensure loadConfig or equivalent uses the testable config:
private static QB_Config__mdt loadConfig() {
    if (Test.isRunningTest() && getTestableConfig != null) {
        return getTestableConfig;
    }
    return [SELECT Realm_Id__c, Default_Item_Ref__c FROM QB_Config__mdt WHERE MasterLabel = 'Org Defaults' LIMIT 1];
}

// Ensure ensureCustomer accepts an Account parameter (not just an Id):
public static String ensureCustomer(Account acct) {
    // If account already has a QuickBooks Customer Id, return it
    if (String.isNotBlank(acct.QuickBooks_Customer_Id__c)) {
        return acct.QuickBooks_Customer_Id__c;
    }

    QB_Config__mdt cfg = loadConfig();

    // Build the request to create a customer in QuickBooks
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:QuickBooks/v3/company/' + cfg.Realm_Id__c + '/customer');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json');
    req.setHeader('Accept', 'application/json');

    Map<String, Object> body = new Map<String, Object>{
        'DisplayName' => acct.Name
    };
    req.setBody(JSON.serialize(body));

    Http http = new Http();
    HttpResponse res = http.send(req);

    Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
    Map<String, Object> customer = (Map<String, Object>) parsed.get('Customer');
    String custId = (String) customer.get('Id');

    // Write back to Account
    acct.QuickBooks_Customer_Id__c = custId;
    update acct;

    return custId;
}

    @IsTest
    static void testInvocableHappyPath() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());

        // Inject test CMDT record
        QB_Service.getTestableConfig = createTestConfig();

        Opportunity o = [SELECT Id, Name, StageName FROM Opportunity WHERE Name = 'Opp Paid Path' LIMIT 1];
        o.StageName = 'Paid';
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
    static void testTriggerQueuesQueueable() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());
        QB_Service.getTestableConfig = createTestConfig();

        Opportunity o = [SELECT Id, StageName FROM Opportunity WHERE Name = 'Opp Skip Not Paid' LIMIT 1];
        o.StageName = 'Paid';
        update o;

        Test.stopTest();

        Opportunity refreshed = [SELECT QuickBooks_Invoice_Id__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('INV-999', refreshed.QuickBooks_Invoice_Id__c, 'Trigger path should have created invoice and updated field');
    }

    @IsTest
    static void testEnsureCustomerWritesBack() {
        Account a = [SELECT Id, Name, QuickBooks_Customer_Id__c FROM Account WHERE Name = 'Acme Corp' LIMIT 1];
        System.assertEquals(null, a.QuickBooks_Customer_Id__c, 'Precondition: no customer id before test');

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());
        QB_Service.getTestableConfig = createTestConfig();

        String custId = QB_Service.ensureCustomer(a);
        Test.stopTest();

        System.assertEquals('CUST-123', custId, 'Should return created customer id');

        a = [SELECT QuickBooks_Customer_Id__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('CUST-123', a.QuickBooks_Customer_Id__c, 'Account should be updated with customer id');
    }
}