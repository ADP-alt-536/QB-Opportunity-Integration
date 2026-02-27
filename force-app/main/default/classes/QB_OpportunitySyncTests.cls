@IsTest
private class QB_OpportunitySyncTests {

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
        RecordType renewalRT;
        RecordType newMemberRT;

        try {
            renewalRT = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Opportunity'
                  AND Name = 'Membership Recurring/Renewal Opportunities'
                LIMIT 1
            ];
        } catch (QueryException e) {}

        try {
            newMemberRT = [
                SELECT Id
                FROM RecordType
                WHERE SObjectType = 'Opportunity'
                  AND Name = 'New Membership Opportunities'
                LIMIT 1
            ];
        } catch (QueryException e) {}

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

        Contact primaryC = new Contact(
            FirstName = 'Alex',
            LastName  = 'Primary',
            AccountId = a.Id,
            Email     = 'primary@example.com'
        );
        insert primaryC;

        a.Primary_Contact__c = primaryC.Id;
        update a;

        Opportunity o1 = new Opportunity(
            Name = 'Opp Renewal',
            RecordTypeId = (renewalRT != null ? renewalRT.Id : null),
            StageName = 'Prospecting',
            CloseDate = System.today(),
            Amount = 123.45,
            Custom_Membership_Dues__c = 50.00,
            Calculated_Dues_Amount__c = '123.45',
            AccountId = a.Id
        );
        Opportunity o2 = new Opportunity(
            Name = 'Opp New Member',
            RecordTypeId = (newMemberRT != null ? newMemberRT.Id : null),
            StageName = 'Prospecting',
            CloseDate = System.today(),
            Amount = 250.00,
            AccountId = a.Id
        );
        insert new List<Opportunity>{ o1, o2 };
    }

    private static QB_Config__mdt createTestConfig() {
        return new QB_Config__mdt(
            MasterLabel = 'Org Defaults',
            Realm_Id__c = '123456789',
            Default_Item_Ref__c = '1'
        );
    }

    @IsTest
    static void testQueueableSyncWithTwoLineItems() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());
        QB_Service.getTestableConfig = createTestConfig();

        Account a = [SELECT Id FROM Account WHERE Name = 'Acme Corp' LIMIT 1];
        RecordType renewalRT = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Opportunity'
              AND Name = 'Membership Recurring/Renewal Opportunities'
            LIMIT 1
        ];

        Opportunity o = new Opportunity(
            Name = 'Opp Renewal Queueable',
            RecordTypeId = renewalRT.Id,
            StageName = QB_Enums.STAGE_PAID,
            CloseDate = System.today(),
            AccountId = a.Id,
            Amount = 123.45,
            Effective_Date__c = System.today(),
            Paid_Date__c = System.today(),
            Amount_Paid__c = 123.45,
            Custom_Membership_Dues__c = 50.00,
            Calculated_Dues_Amount__c = '123.45'
        );
        insert o;

        // Match the trigger’s constructor signature
        System.enqueueJob(new QB_SyncQueueable(new List<Id>{ o.Id }));

        Test.stopTest();

        Opportunity o2 = [SELECT QuickBooks_Invoice_Id__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('INV-999', o2.QuickBooks_Invoice_Id__c);

        Account a2 = [SELECT QuickBooks_Customer_Id__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('CUST-123', a2.QuickBooks_Customer_Id__c);
    }

    @IsTest
    static void testQueueableSyncWithSingleLineItem() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());
        QB_Service.getTestableConfig = createTestConfig();

        Account a = [SELECT Id FROM Account WHERE Name = 'Acme Corp' LIMIT 1];
        RecordType newMemberRT = [
            SELECT Id
            FROM RecordType
            WHERE SObjectType = 'Opportunity'
              AND Name = 'New Membership Opportunities'
            LIMIT 1
        ];

        Opportunity o = new Opportunity(
            Name = 'Opp New Member Queueable',
            RecordTypeId = newMemberRT.Id,
            StageName = QB_Enums.STAGE_PAID,
            CloseDate = System.today(),
            AccountId = a.Id,
            Amount = 250.00,
            Effective_Date__c = System.today(),
            Paid_Date__c = System.today(),
            Amount_Paid__c = 250.00
        );
        insert o;

        // Match the trigger’s constructor signature
        System.enqueueJob(new QB_SyncQueueable(new List<Id>{ o.Id }));

        Test.stopTest();

        Opportunity o2 = [SELECT QuickBooks_Invoice_Id__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('INV-999', o2.QuickBooks_Invoice_Id__c);

        Account a2 = [SELECT QuickBooks_Customer_Id__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('CUST-123', a2.QuickBooks_Customer_Id__c);
    }

    @IsTest
    static void testTriggerQueuesQueueable() {
        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());
        QB_Service.getTestableConfig = createTestConfig();

        Opportunity o = [
            SELECT Id, StageName, Effective_Date__c, Paid_Date__c, Amount_Paid__c, AccountId
            FROM Opportunity
            WHERE Name = 'Opp New Member'
            LIMIT 1
        ];

        // Prove we are actually transitioning into Paid
        System.assertNotEquals(QB_Enums.STAGE_PAID, o.StageName, 'Precondition: Opp should not already be Paid in @TestSetup');

        o.StageName = QB_Enums.STAGE_PAID;
        o.Amount = 250.00; // important if invoice creation uses Opportunity.Amount
        o.Effective_Date__c = System.today();
        o.Paid_Date__c = System.today();
        o.Amount_Paid__c = 250.00;
        update o;

        // Verify stage update actually stuck before we stopTest/flush async
        Opportunity afterUpdate = [SELECT StageName FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals(QB_Enums.STAGE_PAID, afterUpdate.StageName, 'StageName should be Paid after update');

        Test.stopTest();

        Opportunity refreshed = [SELECT QuickBooks_Invoice_Id__c FROM Opportunity WHERE Id = :o.Id];
        System.assertEquals('INV-999', refreshed.QuickBooks_Invoice_Id__c, 'Trigger path should write back invoice id');

        Account acc = [SELECT QuickBooks_Customer_Id__c FROM Account WHERE Id = :o.AccountId];
        System.assertEquals('CUST-123', acc.QuickBooks_Customer_Id__c, 'Trigger path should write back customer id');
    }

    @IsTest
    static void testEnsureCustomerWritesBack() {
        Account a = [SELECT Id, QuickBooks_Customer_Id__c FROM Account WHERE Name = 'Acme Corp' LIMIT 1];
        System.assertEquals(null, a.QuickBooks_Customer_Id__c);

        Test.startTest();
        Test.setMock(HttpCalloutMock.class, new QbCreateMock());
        QB_Service.getTestableConfig = createTestConfig();

        a = [
            SELECT Id, Name, QuickBooks_Customer_Id__c, Primary_Contact__r.Email,
                   BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
            FROM Account
            WHERE Id = :a.Id
        ];
        String custId = QB_Service.ensureCustomer(a);

        Test.stopTest();

        System.assertEquals('CUST-123', custId);
        a = [SELECT QuickBooks_Customer_Id__c FROM Account WHERE Id = :a.Id];
        System.assertEquals('CUST-123', a.QuickBooks_Customer_Id__c);
    }
}